"""Source-bound controller-only XSim checks for feature-8 ROUNDED_AFFINE.

The mocked kernel service verifies the exact sequencer request.  Arithmetic and
scratch publication belong to the stream-kernel integration gate; this leaf
does not claim an end-to-end affine result.
"""
import hashlib
import json
import re
import tempfile
import unittest
from pathlib import Path

from compiler.v4 import recovery_program as asm
from compiler.v4.stream_program import encode_context
from scripts.v4.xsim import compile_rtl, run_rtl


ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    'rtl/v4/control/program_sequencer.sv',
    'verification/v4/program/tb_rounded_affine_program.sv',
]
EXTRAS = [
    'verification/v4/test_rounded_affine_program_rtl.py',
    'compiler/v4/recovery_program.py',
    'compiler/v4/stream_program.py',
    'config/v4_program_interface.json',
    'config/v4_kernel_interface.json',
    'config/v4_stream_interface.json',
    'rtl/v4/include/program_interface.vh',
    'rtl/v4/include/kernel_interface.vh',
    'rtl/v4/include/stream_interface.vh',
    'scripts/v4/xsim.py',
    'docs/v4/architecture/OPERAND_FLOW_ROUND.md',
]
FIELDS = asm.KERNEL['request_ports']
MASK32 = (1 << 32) - 1


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pack(fields, values):
    value = 0
    bit = 0
    for name, width in fields.items():
        value |= (int(values.get(name, 0)) & ((1 << width) - 1)) << bit
        bit += width
    return value


def records(package):
    rows = [(0, index, word) for index, word in enumerate(package['program'])]
    for template_index, template in enumerate(package['templates']):
        rows.append((1, template_index * 33,
                     template['descriptor'] | (template['bind_a'] << 32) |
                     (template['bind_b'] << 64)))
        rows.extend((1, template_index * 33 + lane + 1, context)
                    for lane, context in enumerate(template['contexts']))
    rows.extend((2, index, vector['base'] | (vector['capacity'] << 9))
                for index, vector in enumerate(package['vectors']))
    return [(kind, index, word, int(position + 1 == len(rows)))
            for position, (kind, index, word) in enumerate(rows)]


def affine_package(*, length=33, scalar=-3_145_728, upper='SUB', bind_b=0xffff,
                   descriptor=7, contexts=None, a_capacity=None, c_capacity=None,
                   dst_capacity=None, b_vector=0, extra=None):
    """Create a scalar-B op23 image with V0 deliberately based away from zero."""
    if a_capacity is None:
        a_capacity = length
    if c_capacity is None:
        c_capacity = length
    if dst_capacity is None:
        dst_capacity = length
    lower = encode_context(op='MUL', mode=1, src_a='A', src_b='B')
    upper_context = encode_context(op=upper, mode=1, src_a='A', src_b='B')
    if contexts is None:
        contexts = [lower] * 16 + [upper_context] * 16
    immediate = dict(template=1, length=length, aux_v=1)
    fields = dict(kernel=23, dst_v=2, a_v=0, b_v=b_vector,
                  b_s=1 if bind_b == 0xffff else 0,
                  length_mode=2, immediate=asm.service_immediate(**immediate))
    if extra:
        fields.update(extra)
    words = [
        asm.encode('SET', dst_s=1, immediate=scalar),
        asm.encode('KERNEL', **fields),
        asm.encode('HALT_STATUS', dst_v=2, a_v=0, b_v=1, immediate=1),
    ]
    return {
        'revision': 2,
        'program': words,
        # The first template is valid but unused.  The affine image is held
        # separately so a corrupted op23 image need not alter unrelated load
        # semantics.
        'templates': [
            dict(descriptor=7, bind_a=0, bind_b=0, contexts=[lower] * 32),
            dict(descriptor=descriptor, bind_a=0, bind_b=bind_b, contexts=contexts),
        ],
        # V0's public base is intentionally nonzero: scalar-B form must drive
        # raw kernel_src_b=0 rather than leaking this descriptor base.
        'vectors': [
            dict(base=61, capacity=a_capacity),
            dict(base=173, capacity=c_capacity),
            dict(base=285, capacity=dst_capacity),
            dict(base=397, capacity=length),
        ],
        'constants': [],
    }


def affine_payload(package, *, length, scalar, upper):
    lower = encode_context(op='MUL', mode=1, src_a='A', src_b='B')
    upper_context = encode_context(op=upper, mode=1, src_a='A', src_b='B')
    contexts = pack({str(index): 64 for index in range(32)}, {
        str(index): lower if index < 16 else upper_context for index in range(32)})
    tail = MASK32 if length % 32 == 0 else (1 << (length % 32)) - 1
    fields = asm.decode(package['program'][1])
    scalar_y = package['templates'][1]['bind_b'] == 0xffff
    return pack(FIELDS, dict(
        op=23, contexts=contexts, descriptor=7,
        src_a=package['vectors'][0]['base'],
        src_b=0 if scalar_y else package['vectors'][fields['b_v']]['base'],
        dst=package['vectors'][2]['base'], length=length,
        rows=33, cols=1024, matrix_dense=0, trans=0, r4=0,
        scalar_a=0, scalar_b=scalar if scalar_y else 0,
        scalar_bind_a=0, scalar_bind_b=0xffff if scalar_y else 0,
        shift=0, k=0, scale=4096, key=0x1234, generation=3,
        job=7, tag=100, fmt=1, frame_count=(length + 31) // 32,
        tail_mask=tail, store_mode=0, support_base=0,
        aux_base=package['vectors'][1]['base'], support_length=0,
        aux_length=0, index=0, flags=0))


def vector_case(package, *, services, expected_fault=0, expected_load_fault=0,
                cancel_mode=0, payload=None, length=33):
    loaded = records(package)
    header = [2, len(package['program']), len(package['templates']),
              len(package['vectors']), 0, len(loaded), services, 1000,
              expected_load_fault, expected_fault, 0,
              8 if expected_fault else 1, cancel_mode]
    lines = [' '.join(map(str, header))]
    lines.extend(f'{kind} {index} {word:x} {last}'
                 for kind, index, word, last in loaded)
    if services:
        if payload is None:
            raise AssertionError('a service case needs an exact payload')
        lines.append(f'1 {payload:x} 0 0 0 {length} 1 0')
    return '\n'.join(lines)


class RoundedAffineProgramRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='rounded_affine_program_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'rounded_affine_program.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_rounded_affine_program', SOURCES, root=ROOT)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def replay(self, cases):
        path = self.folder / f'{self._testMethodName}.txt'
        path.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n', encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={path.as_posix()}'], root=ROOT, timeout=300)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        match = re.search(r'PASS program_sequencer cycles=(\d+) checks=(\d+) cases=(\d+)', result.stdout)
        self.assertIsNotNone(match, result.stdout)
        cycles, checks, count = map(int, match.groups())
        self.assertEqual(count, len(cases))
        self.assertEqual(self.before, {name: sha(ROOT / name) for name in SOURCES + EXTRAS})
        record = dict(test=self.id(), status='PASS', cycles=cycles, comparisons=checks,
                      cases=count, commands=self.commands + result.commands,
                      stdout=result.stdout, source_sha256=self.before,
                      vectors_sha256=sha(path),
                      scope='controller_only_op23_request_validation_mock_kernel')
        (self.folder / f'{self._testMethodName}.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')
        return result.stdout

    def test_scalar_and_vector_request_shape_with_nonzero_v0_base(self):
        cases = []
        for length, scalar, upper in ((1, -3_145_728, 'SUB'), (33, 1_048_576, 'ADD'), (64, -1, 'SUB')):
            package = affine_package(length=length, scalar=scalar, upper=upper)
            cases.append(vector_case(package, services=1,
                                     payload=affine_payload(package, length=length,
                                                          scalar=scalar, upper=upper), length=length))
        vector_y = affine_package(length=33, scalar=0, upper='ADD', bind_b=0, b_vector=3)
        cases.append(vector_case(vector_y, services=1,
                                 payload=affine_payload(vector_y, length=33, scalar=0, upper='ADD'),
                                 length=33))
        stdout = self.replay(cases)
        # The testbench compares complete scalar and vector-Y requests.  The
        # scalar form has raw src_b=0 even though V0 itself has a nonzero base;
        # ordinary architectural RF0 remains zero throughout this legal image.
        self.assertEqual(len(re.findall(r'DONE case=\d+', stdout)), len(cases))

    def test_rejects_before_kernel_request_on_canonical_and_capacity_errors(self):
        bad = [
            (affine_package(b_vector=1), 0),
            (affine_package(bind_b=0xfffe), 0),
            # Descriptor15 plus ordinary affine contexts is rejected during
            # image loading.  That is an earlier no-KREQ rejection, not a
            # runtime command-validation result.
            (affine_package(descriptor=15), 1),
            (affine_package(contexts=[encode_context(op='MUL', mode=1, src_a='A', src_b='B')] * 16 +
                            [encode_context(op='ADD', mode=1, src_a='A', src_b='B')] * 15 +
                            [encode_context(op='SUB', mode=1, src_a='A', src_b='B')]), 0),
            (affine_package(a_capacity=32), 0),
            (affine_package(c_capacity=32), 0),
            (affine_package(dst_capacity=32), 0),
            (affine_package(scalar=1 << 26), 0),
            (affine_package(extra={'dst_s': 2}), 0),
            (affine_package(extra={'flag_s': 2}), 0),
            (affine_package(extra={'target': 1}), 0),
            (affine_package(extra={'immediate': asm.service_immediate(template=1, length=33, aux_v=1, flags=1)}), 0),
            (affine_package(extra={'immediate': asm.service_immediate(template=1, length=33, aux_v=1, reserved=1)}), 0),
        ]
        stdout = self.replay([
            vector_case(package, services=0, expected_fault=3,
                        expected_load_fault=load_fault)
            for package, load_fault in bad])
        self.assertNotIn('service payload', stdout)

    def test_delayed_kernel_response_cancel_reset_and_recovery(self):
        package = affine_package(length=33, scalar=-3_145_728, upper='SUB')
        payload = affine_payload(package, length=33, scalar=-3_145_728, upper='SUB')
        # The middle case cancels while the delayed mock response is pending.
        # The third reload must execute normally after reset/recovery.
        stdout = self.replay([
            vector_case(package, services=1, payload=payload, length=33),
            vector_case(package, services=1, payload=payload, length=33, cancel_mode=2),
            vector_case(package, services=1, payload=payload, length=33),
        ])
        self.assertEqual(len(re.findall(r'CASE \d+ complete', stdout)), 3)


if __name__ == '__main__':
    unittest.main()
