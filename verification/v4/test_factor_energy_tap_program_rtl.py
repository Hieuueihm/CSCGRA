"""Controller-only XSim mock checks for feature10 FACTOR_ENERGY_TAP.

This leaf verifies sequencer canonicalization and scalar/count routing. Factor
slot arithmetic, masks and cancellation are owned by the factor-panel gate.
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
SOURCES = ['rtl/v4/control/program_sequencer.sv',
           'verification/v4/program/tb_factor_energy_tap_program.sv']
EXTRAS = ['verification/v4/test_factor_energy_tap_program_rtl.py',
          'compiler/v4/recovery_program.py', 'config/v4_program_interface.json',
          'config/v4_kernel_interface.json', 'rtl/v4/include/program_interface.vh',
          'rtl/v4/include/kernel_interface.vh', 'scripts/v4/xsim.py',
          'docs/v4/architecture/FACTOR_ENERGY_TAP.md']
FIELDS = asm.KERNEL['request_ports']
MAC297, DESCRIPTOR = 297, 23


def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def packed(fields, values):
    value = bit = 0
    for name, width in fields.items():
        value |= (int(values.get(name, 0)) & ((1 << width) - 1)) << bit
        bit += width
    return value


def loader_records(package):
    rows = [(0, index, word) for index, word in enumerate(package['program'])]
    for template_index, template in enumerate(package['templates']):
        rows.append((1, template_index * 33, template['descriptor'] | (template['bind_a'] << 32) |
                     (template['bind_b'] << 64)))
        rows.extend((1, template_index * 33 + lane + 1, context)
                    for lane, context in enumerate(template['contexts']))
    rows.extend((2, index, vector['base'] | (vector['capacity'] << 9))
                for index, vector in enumerate(package['vectors']))
    return [(kind, index, value, int(position + 1 == len(rows)))
            for position, (kind, index, value) in enumerate(rows)]


def immediate(*, length, support_s=2, offset_s=3, index_s=4, flags=0, **extra):
    values = dict(length=length, support_length_s=support_s, aux_length_s=offset_s,
                  index_s=index_s, flags=flags, dense=1, template=0)
    values.update(extra)
    return asm.service_immediate(**values)


def package(*, length=33, support=64, offset=3, index=7, row=False,
            descriptor=DESCRIPTOR, contexts=None, bind_a=0, bind_b=0, rows=128,
            dst_scalar=11, flag_scalar=10, target=1, extra=None):
    if contexts is None: contexts = [MAC297] * 32
    fields = dict(kernel=25, dst_v=1, a_v=0, b_v=0, dst_s=dst_scalar,
                  flag_s=flag_scalar, target=target, length_mode=2,
                  immediate=immediate(length=length, flags=int(row)))
    if extra: fields.update(extra)
    words = [asm.encode('SET', dst_s=2, immediate=support),
             asm.encode('SET', dst_s=3, immediate=offset),
             asm.encode('SET', dst_s=4, immediate=index),
             asm.encode('KERNEL', **fields),
             asm.encode('HALT_STATUS', dst_v=1, a_v=0, b_v=0, immediate=1)]
    return dict(revision=2, program=words,
                templates=[dict(descriptor=descriptor, bind_a=bind_a, bind_b=bind_b,
                                contexts=contexts)],
                # V0 intentionally has a nonzero base. Op25's unused raw A/B
                # request buses must nevertheless be literal zero.
                vectors=[dict(base=61, capacity=128), dict(base=173, capacity=max(1, length))],
                constants=[], _shape=dict(length=length, support=support, offset=offset,
                                           index=index, row=int(row), rows=rows))


def payload(package):
    fields = asm.decode(package['program'][-2]); shape = package['_shape']
    contexts = packed({str(index): 64 for index in range(32)},
                      {str(index): MAC297 for index in range(32)})
    return packed(FIELDS, dict(op=25, contexts=contexts, descriptor=DESCRIPTOR,
        src_a=0, src_b=0, dst=package['vectors'][1]['base'], length=shape['length'],
        rows=shape['rows'], cols=shape['support'], matrix_dense=1, trans=0, r4=0,
        scalar_a=0, scalar_b=0, scalar_bind_a=0, scalar_bind_b=0, shift=0, k=0,
        scale=4096, key=0x1234, generation=3, job=7, tag=100, fmt=1,
        frame_count=0, tail_mask=0, store_mode=0, support_base=0, aux_base=0,
        support_length=shape['support'], aux_length=shape['offset'],
        index=shape['index'], flags=shape['row']))


def vector_case(package, *, services, expected_fault=0, expected_load_fault=0,
                response_data=0, response_count=0):
    loaded = loader_records(package); shape = package['_shape']
    header = [2, len(package['program']), len(package['templates']), len(package['vectors']), 0,
              len(loaded), services, 1000, expected_load_fault, expected_fault, 0,
              8 if expected_fault else 1, 0, shape['rows'], 1024]
    lines = [' '.join(map(str, header))]
    lines.extend(f'{kind} {index} {word:x} {last}' for kind, index, word, last in loaded)
    if services:
        lines.append(f'1 {payload(package):x} {response_data & ((1 << 64) - 1):x} 0 0 '
                     f'{response_count} 1 0')
    return '\n'.join(lines)


class FactorEnergyTapProgramRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_energy_program_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_energy_program.xsim.json'
        cls.before = {name: digest(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_factor_energy_tap_program', SOURCES, root=ROOT)
        if compiled.returncode: raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def replay(self, cases):
        path = self.folder / f'{self._testMethodName}.txt'
        path.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n', encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={path.as_posix()}'], root=ROOT, timeout=300)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        match = re.search(r'PASS program_sequencer cycles=(\d+) checks=(\d+) cases=(\d+)', result.stdout)
        self.assertIsNotNone(match, result.stdout)
        self.assertEqual(int(match.group(3)), len(cases))
        self.assertEqual(self.before, {name: digest(ROOT / name) for name in SOURCES + EXTRAS})
        (self.folder / f'{self._testMethodName}.json').write_text(json.dumps(dict(
            test=self.id(), status='PASS', cases=len(cases), commands=self.commands + result.commands,
            source_sha256=self.before, vectors_sha256=digest(path), stdout=result.stdout,
            scope='controller_only_op25_factor_energy_tap_request_validation_mock_kernel'), indent=2) + '\n')
        return result.stdout

    def test_canonical_axes_tails_raw_scalar_and_count_flag(self):
        cases = []
        for ordinal, shape in enumerate((
            dict(length=1, support=16, offset=0, index=3, row=False),
            dict(length=31, support=64, offset=1, index=7, row=True),
            dict(length=32, support=64, offset=0, index=11, row=False),
            dict(length=33, support=96, offset=2, index=17, row=True),
            dict(length=128, support=24, offset=0, index=23, row=False),
        )):
            item = package(**shape)
            cases.append(vector_case(item, services=1, response_data=-(ordinal + 31),
                                     response_count=ordinal & 1))
        stdout = self.replay(cases)
        self.assertRegex(stdout, r'RF case=4 index=11 data=ffffffffffffffdd')
        self.assertRegex(stdout, r'RF case=4 index=10 data=0000000000000000')

    def test_rejects_before_dispatch_on_canonical_alias_and_bounds_errors(self):
        bad = [
            (package(descriptor=7), 1), (package(contexts=[MAC297] * 31 + [296]), 1),
            (package(bind_a=1), 0), (package(extra={'a_v': 1}), 0), (package(extra={'b_v': 1}), 0),
            (package(extra={'a_s': 1}), 0), (package(extra={'b_s': 1}), 0),
            (package(flag_scalar=11), 0), (package(target=0), 0), (package(target=2), 0), (package(target=3), 0),
            (package(extra={'shift_s': 6}), 0), (package(extra={'immediate': immediate(length=33, flags=2)}), 0),
            (package(extra={'immediate': immediate(length=33, dense=0)}), 0),
            (package(length=0), 0), (package(length=129), 0), (package(support=97), 0),
            (package(offset=127, length=2), 0), (package(index=64), 0), (package(row=True, index=128), 0),
        ]
        stdout = self.replay([vector_case(item, services=0, expected_fault=3,
                                           expected_load_fault=load_fault)
                              for item, load_fault in bad])
        self.assertNotIn('service payload', stdout)


if __name__ == '__main__':
    unittest.main()
