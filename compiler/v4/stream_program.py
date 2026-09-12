"""Encode, validate and export the bounded revision-one stream package.

This compiler emits CALL/HALT words and per-PE templates. It makes no runtime
kernel decisions and does not compile the eleven complete recovery algorithms.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ABI_PATH = ROOT / 'config/v4_stream_interface.json'
ABI = json.loads(ABI_PATH.read_text())


def layout(group):
    position = 0
    result = {}
    for name, width in ABI[group + '_fields'].items():
        result[name] = (position, width)
        position += width
    return result


def _pack(group, fields):
    positions = layout(group)
    if fields.keys() - positions.keys():
        raise ValueError('unknown fields: ' + repr(fields.keys() - positions.keys()))
    word = 0
    for name, (position, width) in positions.items():
        value = fields.get(name, 0)
        if not isinstance(value, int) or not 0 <= value < 1 << width:
            raise ValueError(f'{group}.{name} does not fit unsigned{width}')
        word |= value << position
    return word


def _unpack(group, word):
    positions = layout(group)
    width = sum(ABI[group + '_fields'].values())
    if not isinstance(word, int) or not 0 <= word < 1 << width:
        raise ValueError(f'{group} word does not fit {width} bits')
    return {name: (word >> position) & ((1 << size)-1)
            for name, (position, size) in positions.items()}


def _enum(table, value):
    if isinstance(value, str):
        try:
            return ABI[table][value]
        except KeyError as error:
            raise ValueError(f'unknown {table}: {value}') from error
    return value


def decode_program(word):
    return _unpack('program', word)


def encode_program(**fields):
    fields = dict(fields)
    fields['kind'] = _enum('kinds', fields.get('kind', 0))
    word = _pack('program', fields)
    validate_program(word)
    return word


def validate_program(word, template_count=None):
    fields = decode_program(word)
    if fields['kind'] == ABI['kinds']['HALT']:
        if any(value for name, value in fields.items() if name != 'kind'):
            raise ValueError('HALT has nonzero payload')
    elif fields['kind'] == ABI['kinds']['CALL']:
        if fields['reserved'] or not 1 <= fields['frame_count'] <= ABI['limits']['frame_count_max'] or not fields['tail_mask']:
            raise ValueError('invalid CALL fields')
        if template_count is not None and fields['template'] >= template_count:
            raise ValueError('CALL references unloaded template')
    else:
        raise ValueError('unsupported stream instruction')
    return fields


def decode_descriptor(word):
    return _unpack('descriptor', word)


def encode_descriptor(**fields):
    fields = dict(fields)
    fields['output_kind'] = _enum('outputs', fields.get('output_kind', 0))
    word = _pack('descriptor', fields)
    validate_descriptor(word)
    return word


def validate_descriptor(word):
    fields = decode_descriptor(word)
    if fields['reserved'] or fields['output_kind'] not in ABI['outputs'].values():
        raise ValueError('invalid descriptor')
    if fields['output_kind'] != ABI['outputs']['LAST_ACC'] and fields['shift']:
        raise ValueError('EACH/SUM_ACC requires shift zero')
    return fields


def decode_context(word):
    fields = _unpack('context', word)
    width = ABI['context_fields']['immediate']
    if fields['immediate'] & (1 << (width-1)):
        fields['immediate'] -= 1 << width
    return fields


def encode_context(**fields):
    fields = dict(fields)
    fields['op'] = _enum('context_ops', fields.get('op', 0))
    for source in ('src_a', 'src_b'):
        fields[source] = _enum('sources', fields.get(source, 0))
    width = ABI['context_fields']['immediate']
    value = fields.get('immediate', 0)
    if not -(1 << (width-1)) <= value < 1 << (width-1):
        raise ValueError('immediate does not fit signed state format')
    fields['immediate'] = value & ((1 << width)-1)
    word = _pack('context', fields)
    validate_context(word)
    return word


def validate_context(word, descriptor=None):
    fields = decode_context(word)
    if fields['reserved'] or fields['op'] not in ABI['context_ops'].values():
        raise ValueError('invalid stream context')
    if descriptor is not None:
        output = validate_descriptor(descriptor)['output_kind']
        mac = fields['op'] == ABI['context_ops']['MAC']
        if mac == (output == ABI['outputs']['EACH']):
            raise ValueError('context operation incompatible with template output')
    return fields


def validate_package(package):
    if package.get('revision') != ABI['revision']:
        raise ValueError('unsupported stream package revision')
    programs, templates = package['program'], package['templates']
    if not 1 <= len(programs) <= ABI['limits']['program_words'] or not 1 <= len(templates) <= ABI['limits']['templates']:
        raise ValueError('invalid package counts')
    for template in templates:
        validate_descriptor(template['descriptor'])
        if len(template['contexts']) != ABI['limits']['pe_count']:
            raise ValueError('each template must contain exactly32 PE contexts')
        for context in template['contexts']:
            validate_context(context, template['descriptor'])
    for word in programs:
        fields = validate_program(word, len(templates))
        if fields['kind'] == ABI['kinds']['CALL']:
            desc = decode_descriptor(templates[fields['template']]['descriptor'])
            for base, increment in [('src_a', 'inc_a'), ('src_b', 'inc_b'), ('dst', 'inc_dst')]:
                last = fields[base] + (fields['frame_count']-1 if desc[increment] else 0)
                if last >= ABI['limits']['public_blocks']:
                    raise ValueError('CALL address enters private scratch or exceeds RAM')
    return package


def build_package(program, templates):
    package = {'revision': ABI['revision'],
               'program': [encode_program(**word) if isinstance(word, dict) else word for word in program],
               'templates': [{'descriptor': encode_descriptor(**t['descriptor']) if isinstance(t['descriptor'], dict) else t['descriptor'],
                              'contexts': [encode_context(**c) if isinstance(c, dict) else c for c in t['contexts']]}
                             for t in templates]}
    return validate_package(package)


def disassemble(package):
    validate_package(package)
    inverse = {v: k for k, v in ABI['kinds'].items()}
    lines = ['stream revision1: CALL/HALT; compact stream contexts, not legacy tile64']
    for pc, word in enumerate(package['program']):
        f = decode_program(word)
        fields = ' '.join(f'{key}={value}' for key, value in f.items() if key not in ('kind', 'reserved'))
        lines.append(f'{pc:03d}: {word:032x} {inverse[f["kind"]]} {fields}')
    for tid, template in enumerate(package['templates']):
        lines.append(f'template {tid}: {decode_descriptor(template["descriptor"])}')
        for lane, context in enumerate(template['contexts']):
            lines.append(f'  PE{lane:02d}: {context:016x} {decode_context(context)}')
    return '\n'.join(lines) + '\n'


def export_package(package, output):
    validate_package(package)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    program_text = ''.join(f'{word:032x}\n' for word in package['program'])
    template_words = [word for template in package['templates']
                      for word in [template['descriptor'], *template['contexts']]]
    template_text = ''.join(f'{word:016x}\n' for word in template_words)
    image = b''.join(word.to_bytes(16, 'little') for word in package['program'])
    image += b''.join(word.to_bytes(8, 'little') for word in template_words)
    sources = [ABI_PATH, ROOT/'config/v4_pe_interface.json', Path(__file__).resolve()]
    metadata = dict(package, abi='config/v4_stream_interface.json',
                    program_count=len(package['program']), template_count=len(package['templates']),
                    decoded_program=[decode_program(w) for w in package['program']],
                    decoded_templates=[{'descriptor': decode_descriptor(t['descriptor']),
                                        'contexts': [decode_context(w) for w in t['contexts']]} for t in package['templates']],
                    image_sha256=hashlib.sha256(image).hexdigest(),
                    image_hash_encoding='program words128 little-endian then template descriptor64 and32 contexts64 little-endian',
                    source_hashes={str(p.relative_to(ROOT)).replace('\\','/'): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                    host_verification='SHA256 is host evidence; RTL consumes trusted verified flag, not SHA256')
    (output/'program.hex').write_text(program_text)
    (output/'templates.hex').write_text(template_text)
    (output/'package.json').write_text(json.dumps(metadata, indent=2)+'\n')
    (output/'program.txt').write_text(disassemble(package))
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='JSON with revision, program and templates')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    source = json.loads(args.input.read_text())
    if source.get('revision') != ABI['revision']:
        raise SystemExit('unsupported input package revision')
    export_package(build_package(source['program'], source['templates']), args.output)


if __name__ == '__main__':
    main()
