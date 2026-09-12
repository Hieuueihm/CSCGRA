"""Feature10 FACTOR_ENERGY_TAP compiler and VM checks; no RTL evidence.

The paired VMs share Arithmetic and therefore prove command control/publication,
not an independent arithmetic implementation. Each microprogram computes the
raw factor-square sum and tail predicate directly in Python integers.
"""
from __future__ import annotations

import unittest
import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE, Program
from compiler.v4.recovery_program import ABI, decode, encode, unpack
from models.v4.fixed import Arithmetic
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from scripts.v4.export_recovery import compile_spec
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute


def fixture(rows, columns, seed=731):
    matrix = lfsr32_matrix(0x12345678, rows, columns, scale=8192) / 65536.0
    measurement = np.random.default_rng(seed).integers(-4096, 4097, rows) / 16384.0
    return matrix, measurement


def kernel_pcs(package, opcode):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == opcode]


def image_fields(package):
    return {key: package[key] for key in ('program', 'templates', 'vectors', 'constants')}


def energy_micro(*, row, index, offset, length, rows=128, columns=128,
                 scalar_source=0, flag=10, energy=11):
    """Build BUILD_B/INIT/op25 and return its independent integer oracle."""
    matrix, measurement = fixture(rows, columns, 947)
    # A row tap may span the entire factor width.  Build enough legal B
    # columns for the selected factor range instead of accidentally testing
    # an eight-column fixture when L reaches 96.
    support = tuple(range(max(8, index + 1, offset + length if row else 0)))
    p = Program('OMP', matrix, Policy(2, max_iterations=1), None)
    p.vec('A', 128); p.vec('D', 128)
    p.t['scalar_insert'] = len(p.a.templates)
    p.a.templates.append(dict(name='scalar_insert', descriptor=0, bind_a=0, bind_b=0,
                              contexts=[0] * 32))
    p.t['factor_energy_tap'] = p.a.template(
        'factor_energy_tap', 'MAC', 'SUM_ACC', src_a='A', src_b='B', mode=1)
    p.op('zero', 'S', length=96)
    for slot, column in enumerate(support):
        p.set(1, column); p.set(2, slot)
        p.call('SCALAR_INSERT', 'S', 'S', length=96, template='scalar_insert', sa=1, index_s=2)
    p.set(28, len(support)); p.a.emit('BUILD_B', a_v=p.v['S'], a_s=28)
    p.call('FACTOR_INIT', 'A', 'X', length=p.m, template='dot', dense=1,
           support_length_s=28, index_s=0, aux_length_s=0)
    p.set(3, index); p.set(4, offset)
    if scalar_source:
        p.set(scalar_source, 1)
    p.call('FACTOR_ENERGY_TAP', 'D', 'X', 'X', length=length,
           template='factor_energy_tap', out=energy, flag=flag, count=True,
           sa=scalar_source, dense=1, support_length_s=28,
           index_s=3, aux_length_s=4, flags=1 if row else 0)
    p.op('zero', 'X', length=p.n); p.set(6, length)
    p.call('REPLACE_RANGE', 'X', 'X', length=p.n, aux_v=p.v['D'], index_s=0, aux_length_s=6)
    p.a.emit('HALT_STATUS', dst_v=p.v['X'], a_v=p.v['R'], b_v=p.v['S'],
             immediate=ABI['statuses']['MAX_ITERATIONS'])
    package = p.finish(); package['measurement_vector'] = p.v['Y']

    ar = Arithmetic(PROFILE)
    raw_phi = ar.quantize(matrix, PROFILE.coefficient)
    factors = np.asarray(raw_phi[:, support], dtype=object) << 6
    values = [int(factors[index, offset + lane] if row else factors[offset + lane, index])
              for lane in range(length)]
    return package, matrix, measurement, values, sum(value * value for value in values), int(any(values[1:]))


class FactorEnergyTapSoftwareTests(unittest.TestCase):
    def test_full_tap_raw_energy_and_tail_flag_are_generic(self):
        cases = (
            # L1 exercises the legacy tail-zero QR outcome: no tail lane can
            # set the response flag, while the full candidate remains valid.
            dict(row=False, index=2, offset=0, length=1, rows=32, columns=64),
            dict(row=True, index=7, offset=3, length=5, rows=32, columns=64),
            # Crosses frames and includes sparse factor signs; one raw Python
            # sum catches a per-frame round or prefix-only reduction.
            dict(row=False, index=4, offset=17, length=33, rows=64, columns=64),
            dict(row=True, index=31, offset=0, length=96, rows=128, columns=128),
        )
        for shape in cases:
            with self.subTest(**shape):
                package, matrix, measurement, values, expected_energy, expected_tail = energy_micro(**shape)
                pcs = kernel_pcs(package, 25); self.assertEqual(len(pcs), 1)
                fields = decode(package['program'][pcs[0]])
                self.assertEqual((fields['a_v'], fields['b_v'], fields['dst_s'], fields['flag_s'], fields['target']),
                                 (0, 0, 11, 10, 1))
                immediate = unpack(ABI['service_immediate_fields'], fields['immediate'])
                self.assertEqual((immediate['flags'], immediate['support_v'], immediate['aux_v'],
                                  immediate['k_s'], immediate['template']),
                                 (int(shape['row']), 0, 0, 0, package['templates'].index(
                                     next(item for item in package['templates']
                                          if item['name'] == 'factor_energy_tap'))))
                for runner in (execute, reference_execute):
                    result = runner(package, matrix, measurement, limit=20_000)
                    self.assertEqual(list(result['x'])[:len(values)], values)
                    self.assertEqual(result['scalar_registers'][11], expected_energy)
                    self.assertEqual(result['scalar_registers'][10], expected_tail)
                    self.assertEqual(result['status'], 'max_iterations')

    def test_rejects_bad_canonical_fields_and_scalar_alias(self):
        package, matrix, measurement, _, _, _ = energy_micro(
            row=False, index=1, offset=0, length=4, rows=16, columns=32)
        pc = kernel_pcs(package, 25)[0]
        fields = decode(package['program'][pc])
        for name, value in (('a_s', 1), ('flag_s', 11), ('b_v', 1), ('target', 0), ('target', 2), ('target', 3)):
            with self.subTest(name=name):
                bad = dict(package)
                bad['program'] = list(package['program'])
                altered = dict(fields); altered[name] = value
                allowed = set(ABI['allowed_fields']['KERNEL'])
                bad['program'][pc] = encode('KERNEL', **{key: item for key, item in altered.items()
                                                          if key in allowed})
                for runner in (execute, reference_execute):
                    with self.assertRaises(AssertionError):
                        runner(bad, matrix, measurement, limit=20_000)

    def test_false_image_identity_and_export_gating(self):
        matrix, _ = fixture(32, 64)
        policy = Policy(8, max_iterations=2, residual_atol=0)
        baseline = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='view')
        explicit_false = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='view',
                                           factor_energy_tap=False)
        self.assertEqual(image_fields(baseline), image_fields(explicit_false))
        self.assertFalse(baseline['qr_factor_energy_tap_enabled'])
        self.assertNotIn(25, [decode(word)['kernel'] for word in baseline['program']
                              if decode(word)['kind'] == ABI['kinds']['KERNEL']])
        with self.assertRaisesRegex(ValueError, 'requires qr_profile=view'):
            compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='compact', factor_energy_tap=True)
        spec = dict(algorithm='MP', policy=dict(sparsity=8, max_iterations=8),
                    operator=dict(kind='lfsr32', seed=0x12345678, rows=32, columns=64, scale_raw=8192))
        self.assertEqual(image_fields(compile_spec(spec, target_kernel_revision=2)),
                         image_fields(compile_spec(spec, target_kernel_revision=2, factor_energy_tap=True)))
        after = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='view', factor_energy_tap=True)
        self.assertEqual(after['required_kernel_revision'], 10)
        self.assertTrue(after['qr_factor_energy_tap_enabled'])
        self.assertGreater(len(kernel_pcs(after, 25)), 0)

    def _compare_qr(self, algorithm, rows, columns, seed, policy):
        matrix, measurement = fixture(rows, columns, seed)
        before = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view')
        after = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view', factor_energy_tap=True)
        debug = {'qr_T': 'support', 'qr_Y': rows}
        if 'RU_QTY' in {entry['name'] for entry in before['vectors']}:
            debug['RU_QTY'] = rows
        baseline = execute(before, matrix, measurement, limit=7_000_000, debug_vectors=debug)
        observed = []
        for runner in (execute, reference_execute):
            result = runner(after, matrix, measurement, limit=7_000_000, debug_vectors=debug)
            observed.append(result)
            self.assertEqual(
                (list(result['x']), list(result['residual']), result['support'], result['status'],
                 result['outer'], result['inner'], result['debug_factors'], result['debug_vectors']),
                (list(baseline['x']), list(baseline['residual']), baseline['support'], baseline['status'],
                 baseline['outer'], baseline['inner'], baseline['debug_factors'], baseline['debug_vectors']))
        # INIT/EXTEND are physical factor transports and remain exact.
        for opcode in (13, 19):
            before_count = sum(decode(before['program'][pc])['kind'] == ABI['kinds']['KERNEL'] and
                               decode(before['program'][pc])['kernel'] == opcode for pc in baseline['trace'])
            after_count = sum(decode(after['program'][pc])['kind'] == ABI['kinds']['KERNEL'] and
                              decode(after['program'][pc])['kernel'] == opcode for pc in observed[0]['trace'])
            self.assertEqual(before_count, after_count)
        return after, observed[0]

    def test_qr_m32_m64_correction_and_support96(self):
        self._compare_qr('CoSaMP', 32, 64, 171, Policy(8, max_iterations=2, residual_atol=0))
        self._compare_qr('CoSaMP', 64, 256, 311, Policy(8, max_iterations=2, residual_atol=0))
        omp, result = self._compare_qr('OMP', 16, 32, 1,
                                       Policy(4, max_iterations=3, residual_atol=0, ls_normal_rtol=1e-6))
        self.assertGreater(sum(decode(omp['program'][pc])['kernel'] == 19
                               for pc in result['trace'] if decode(omp['program'][pc])['kind'] == 1), 0)
        gomp, result = self._compare_qr('GOMP', 128, 128, 911,
                                        Policy(2, max_iterations=2, group_size=48, residual_atol=0))
        self.assertEqual(len(result['support']), 96)
        self.assertGreater(len(kernel_pcs(gomp, 25)), 0)


if __name__ == '__main__':
    unittest.main()
