"""Generate the revision-one stream interface from its canonical JSON authority."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def render():
    abi = json.loads((ROOT / 'config/v4_stream_interface.json').read_text())
    pe = json.loads((ROOT / 'config/v4_pe_interface.json').read_text())
    if abi['revision'] != 1:
        raise ValueError('stream implementation supports revision one only')
    for name, value in abi['context_ops'].items():
        if pe['ops'][name] != value:
            raise ValueError('stream context opcode differs from PE authority')
    limits = abi['limits']
    required = dict(program_words=256, templates=16, pe_count=32, context_bits=64,
                    descriptor_bits=32, word_bits=128, frame_count_min=1, frame_count_max=32,
                    vector_bits=27, coefficient_bits=18, accumulator_bits=64,
                    memory_blocks=512, public_blocks=480, scratch_base=480, block_address_bits=9)
    if any(limits[key] != value for key, value in required.items()):
        raise ValueError('stream revision-one geometry requires explicit implementation review')
    values = {'REVISION': abi['revision'], 'FORMAT': abi['numeric']['format'],
              'PROGRAM_DEPTH': limits['program_words'], 'TEMPLATE_DEPTH': limits['templates'],
              'FRAME_LIMIT': limits['frame_count_max'], 'PUBLIC_BLOCKS': limits['public_blocks'],
              'SCRATCH_BASE': limits['scratch_base']}
    values.update({name.upper(): value for name, value in limits.items()})
    for prefix, key, total in [('PROGRAM', 'program_fields', limits['word_bits']),
                               ('DESC', 'descriptor_fields', limits['descriptor_bits']),
                               ('CONTEXT', 'context_fields', limits['context_bits'])]:
        position = 0
        for name, width in abi[key].items():
            if not isinstance(width, int) or width <= 0:
                raise ValueError('invalid stream field width')
            values[f'{prefix}_{name.upper()}_LSB'] = position
            values[f'{prefix}_{name.upper()}_W'] = width
            position += width
        if position != total:
            raise ValueError(f'{key} does not fill word')
    for prefix, key in [('KIND', 'kinds'), ('OUTPUT', 'outputs'), ('SRC', 'sources'),
                        ('OP', 'context_ops'), ('CTL_FAULT', 'control_faults'),
                        ('PE_FAULT', 'pe_faults'), ('EXEC_FAULT', 'execution_faults')]:
        values.update({f'{prefix}_{name}': value for name, value in abi[key].items()})
    return '\n'.join(['`ifndef CSR_STREAM_INTERFACE_VH', '`define CSR_STREAM_INTERFACE_VH',
                      '`include "pe_interface.vh"',
                      *[f'`define CSR_STREAM_{key} {value}' for key, value in values.items()],
                      '`endif', ''])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    abi = json.loads((ROOT / 'config/v4_stream_interface.json').read_text())
    path = ROOT / abi['header']
    expected = render()
    if args.check:
        if not path.is_file() or path.read_text() != expected:
            raise SystemExit('stream_interface.vh stale or missing')
    else:
        path.write_text(expected)


if __name__ == '__main__':
    main()
