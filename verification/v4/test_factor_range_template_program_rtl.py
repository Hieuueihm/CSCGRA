"""Source-bound controller-only XSim checks for feature-9 FACTOR_RANGE_TEMPLATE.

The mock service verifies the sequencer request and response ownership.  Factor
reads, MAC arithmetic, candidate publication, and factor invalidation belong to
the panel/kernel integration gate and are intentionally outside this leaf.
"""
import hashlib
import json
import re
import tempfile
import unittest
from pathlib import Path

from compiler.v4 import recovery_program as asm

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    'rtl/v4/control/program_sequencer.sv',
    'verification/v4/program/tb_factor_range_template_program.sv',
]
EXTRAS = [
    'verification/v4/test_factor_range_template_program_rtl.py',
    'compiler/v4/recovery_program.py',
    'config/v4_program_interface.json',
    'config/v4_kernel_interface.json',
    'rtl/v4/include/program_interface.vh',
    'rtl/v4/include/kernel_interface.vh',
    'scripts/v4/xsim.py',
]
FIELDS = asm.KERNEL['request_ports']
MASK32 = (1 << 32) - 1
MAC297 = 297
DESCRIPTOR_SUM_ACC = 23


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


def imm(*, length, support_s=2, offset_s=3, index_s=4, flags=0, dense=1,
        template=0, **extra):
    values = dict(length=length, support_length_s=support_s,
                  aux_length_s=offset_s, index_s=index_s, flags=flags,
                  dense=dense, template=template)
    values.update(extra)
    return asm.service_immediate(**values)


def factor_range_package(*, length, support=24, offset=3, index=7, row=False,
                         head=False, patch=None, source_capacity=None,
                         destination_capacity=None, descriptor=DESCRIPTOR_SUM_ACC,
                         contexts=None, bind_a=0, bind_b=0, rows=128,
                         patch_register=1, extra=None):
    flags = (1 if row else 0) | (2 if head else 0) | (4 if patch is not None else 0)
    tap = 1 if head else length
    if source_capacity is None:
        source_capacity = offset + length
    if destination_capacity is None:
        destination_capacity = tap
    if contexts is None:
        contexts = [MAC297] * 32
    # V0 has a nonzero base.  Canonical op24 raw src_b/support/aux controls
    # must remain literal zero despite this legal descriptor mapping.
    fields = dict(kernel=24, dst_v=1, a_v=0, b_v=0, dst_s=5,
                  a_s=patch_register if patch is not None else 0,
                  length_mode=2,
                  immediate=imm(length=length, flags=flags))
    if extra:
        fields.update(extra)
    words = [
        asm.encode('SET', dst_s=2, immediate=support),
        asm.encode('SET', dst_s=3, immediate=offset),
        asm.encode('SET', dst_s=4, immediate=index),
    ]
    if patch is not None and patch_register:
        words.append(asm.encode('SET', dst_s=1, immediate=patch))
    words.extend([
        asm.encode('KERNEL', **fields),
        asm.encode('HALT_STATUS', dst_v=1, a_v=0, b_v=0, immediate=1),
    ])
    return {
        'revision': 2,
        'program': words,
        'templates': [dict(descriptor=descriptor, bind_a=bind_a, bind_b=bind_b,
                           contexts=contexts)],
        'vectors': [
            dict(base=61, capacity=source_capacity),
            dict(base=173, capacity=destination_capacity),
        ],
        'constants': [],
        '_shape': dict(length=length, support=support, offset=offset, rows=rows,
                       index=index, flags=flags, tap=tap, patch=patch),
    }


def factor_payload(package):
    fields = asm.decode(package['program'][-2])
    shape = package['_shape']
    contexts = pack({str(index): 64 for index in range(32)},
                    {str(index): MAC297 for index in range(32)})
    length = shape['length']
    tail = MASK32 if length % 32 == 0 else (1 << (length % 32)) - 1
    patch = 0 if shape['patch'] is None else shape['patch']
    return pack(FIELDS, dict(
        op=24, contexts=contexts, descriptor=DESCRIPTOR_SUM_ACC,
        src_a=package['vectors'][0]['base'], src_b=0,
        dst=package['vectors'][1]['base'], length=length,
        rows=shape['rows'], cols=shape['support'], matrix_dense=1, trans=0, r4=0,
        scalar_a=patch, scalar_b=0, scalar_bind_a=0, scalar_bind_b=0,
        shift=0, k=0, scale=4096, key=0x1234, generation=3,
        job=7, tag=100, fmt=1, frame_count=0,
        tail_mask=0, store_mode=0, support_base=0, aux_base=0,
        support_length=shape['support'], aux_length=shape['offset'],
        index=shape['index'], flags=shape['flags']))


def vector_case(package, *, services, expected_fault=0, expected_load_fault=0,
                cancel_mode=0, payload=None, response_data=0):
    loaded = records(package)
    header = [2, len(package['program']), len(package['templates']),
              len(package['vectors']), 0, len(loaded), services, 1000,
              expected_load_fault, expected_fault, 0,
              8 if expected_fault else 1, cancel_mode,
              package['_shape']['rows'], 1024]
    lines = [' '.join(map(str, header))]
    lines.extend(f'{kind} {index} {word:x} {last}'
                 for kind, index, word, last in loaded)
    if services:
        if payload is None:
            raise AssertionError('service case needs an exact payload')
        # response count is the requested tap extent; nonzero describes the
        # candidate transport rather than the raw scalar response.
        lines.append(f'1 {payload:x} {response_data & ((1 << 64) - 1):x} 0 0 '
                     f'{package["_shape"]["tap"]} 1 0')
    return '\n'.join(lines)


class FactorRangeTemplateProgramRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_range_program_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_range_program.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_factor_range_template_program', SOURCES, root=ROOT)
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
                      scope='controller_only_op24_factor_range_template_request_validation_mock_kernel')
        (self.folder / f'{self._testMethodName}.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')
        return result.stdout

    def test_row_column_taps_patch_signs_unaligned_and_tails(self):
        cases = []
        # Column/full and row/head cover independent axis/index/offset fields,
        # signed patch transport, and every requested command-size boundary.
        shapes = [
            dict(length=1, support=16, offset=0, index=3, row=False, head=False, patch=1 << 22),
            dict(length=2, support=16, offset=0, index=3, row=False, head=True, patch=0, patch_register=0),
            dict(length=2, support=24, offset=3, index=7, row=False, head=True, patch=-((1 << 22) - 3)),
            dict(length=31, support=32, offset=1, index=5, row=True, head=False, patch=None),
            dict(length=32, support=40, offset=0, index=9, row=True, head=True, patch=-(1 << 20)),
            dict(length=33, support=64, offset=2, index=11, row=False, head=False, patch=(1 << 22) - 1),
            dict(length=96, support=96, offset=0, index=17, row=True, head=False, patch=-(1 << 22)),
            dict(length=128, support=24, offset=0, index=23, row=False, head=True, patch=None),
        ]
        for ordinal, shape in enumerate(shapes):
            package = factor_range_package(**shape)
            cases.append(vector_case(package, services=1,
                                     payload=factor_payload(package),
                                     response_data=-(ordinal + 17)))
        stdout = self.replay(cases)
        # f_dst_s=R5 receives raw ACC64 and is reset for each case.  The final
        # mock response is -23, proving normal scalar response routing remains
        # available independently from candidate tap metadata.
        self.assertRegex(stdout, r'RF case=6 index=5 data=ffffffffffffffe9')

    def test_rejects_before_dispatch_on_canonical_context_bounds_and_capacity(self):
        bad = [
            (factor_range_package(length=33, source_capacity=35), 0),
            (factor_range_package(length=33, destination_capacity=32), 0),
            (factor_range_package(length=33, head=True, source_capacity=35), 0),
            # Descriptor 7 contradicts the all-MAC297 context image, so the
            # loader rejects it before runtime KREQ.  The remaining forms
            # reach EXEC and are rejected before dispatch.
            (factor_range_package(length=33, descriptor=7), 1),
            # The configured descriptor rejects a non-MAC lane during image
            # load; this remains a no-KREQ negative, like descriptor 7.
            (factor_range_package(length=33, contexts=[MAC297] * 31 + [296]), 1),
            (factor_range_package(length=33, bind_a=1), 0),
            (factor_range_package(length=33, extra={'b_v': 1}), 0),
            (factor_range_package(length=33, extra={'flag_s': 6}), 0),
            (factor_range_package(length=33, extra={'target': 1}), 0),
            (factor_range_package(length=33, extra={'shift_s': 6}), 0),
            (factor_range_package(length=33, extra={'immediate': imm(length=33, k_s=6)}), 0),
            (factor_range_package(length=33, extra={'immediate': imm(length=33, flags=8)}), 0),
            (factor_range_package(length=33, extra={'immediate': imm(length=33, dense=0)}), 0),
            (factor_range_package(length=33, extra={'immediate': imm(length=33, support_s=2, offset_s=3, index_s=4, flags=1)}), 0),
            (factor_range_package(length=33, support=97), 0),
            (factor_range_package(length=33, offset=96, index=7), 0),
            (factor_range_package(length=33, offset=1 << 32, index=7, source_capacity=128), 0),
            (factor_range_package(length=33, offset=-1, index=7, source_capacity=128), 0),
            (factor_range_package(length=33, index=1 << 32, source_capacity=128), 0),
            (factor_range_package(length=33, index=-1, source_capacity=128), 0),
            (factor_range_package(length=33, row=True, support=24, index=128), 0),
            (factor_range_package(length=33, patch=1 << 26), 0),
            (factor_range_package(length=33, patch=None, extra={'a_s': 1}), 0),
        ]
        stdout = self.replay([vector_case(package, services=0, expected_fault=3,
                                           expected_load_fault=load_fault)
                              for package, load_fault in bad])
        self.assertNotIn('service payload', stdout)

    def test_delayed_response_cancel_reset_and_recovery(self):
        package = factor_range_package(length=33, support=64, offset=2, index=11,
                                       row=False, head=False, patch=-(1 << 22))
        payload = factor_payload(package)
        stdout = self.replay([
            vector_case(package, services=1, payload=payload, response_data=0x1234),
            vector_case(package, services=1, payload=payload, cancel_mode=2),
            vector_case(package, services=1, payload=payload, response_data=-0x4567),
        ])
        self.assertEqual(len(re.findall(r'CASE \d+ complete', stdout)), 3)


if __name__ == '__main__':
    unittest.main()
