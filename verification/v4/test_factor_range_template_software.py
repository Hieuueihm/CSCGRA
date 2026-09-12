"""Feature9 FACTOR_RANGE_TEMPLATE compiler and VM checks; no RTL evidence.

The primary and reference VMs share ``Arithmetic``. Their paired execution
checks package control and publication semantics; microprogram assertions form
each raw ACC64 sum independently in Python integers.
"""
from __future__ import annotations

import unittest
import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE, Program
from compiler.v4.recovery_program import ABI, decode
from models.v4.fixed import Arithmetic
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from scripts.v4.export_recovery import compile_spec
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute


def fixture(rows: int, columns: int, seed: int = 177):
    matrix = lfsr32_matrix(0x12345678, rows, columns, scale=8192) / 65536.0
    measurement = np.random.default_rng(seed).integers(-4096, 4097, rows) / 16384.0
    return matrix, measurement


def kernel_pcs(package, opcode):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == opcode]


def identity_fields(package):
    return {key: package[key] for key in ('program', 'templates', 'vectors', 'constants', 'load_records')
            if key in package}


def kernel_trace(package, result, opcode):
    return sum(decode(package['program'][pc])['kind'] == ABI['kinds']['KERNEL'] and
               decode(package['program'][pc])['kernel'] == opcode for pc in result['trace'])


def range_micro(*, row: bool, head: bool, patch: int | None, index: int, offset: int, length: int, rows: int = 12, columns: int = 16):
    """Build a minimal normal BUILD_B/INIT/op24 program with public R input."""
    matrix, measurement = fixture(rows, columns, 313)
    support = (1, 4, 7, 10, 13)
    p = Program('OMP', matrix, Policy(2, max_iterations=1), None)
    p.vec('A', 128); p.vec('D', 128)
    p.t['scalar_insert'] = len(p.a.templates)
    p.a.templates.append(dict(name='scalar_insert', descriptor=0, bind_a=0, bind_b=0,
                              contexts=[0] * 32))
    p.t['factor_range_template'] = p.a.template(
        'factor_range_template', 'MAC', 'SUM_ACC', src_a='A', src_b='B', mode=1)
    p.op('zero', 'S', length=96)
    for slot, column in enumerate(support):
        p.set(1, column); p.set(2, slot)
        p.call('SCALAR_INSERT', 'S', 'S', length=96, template='scalar_insert', sa=1, index_s=2)
    p.set(28, len(support)); p.a.emit('BUILD_B', a_v=p.v['S'], a_s=28)
    p.call('FACTOR_INIT', 'A', 'X', length=p.m, template='dot', dense=1,
           support_length_s=28, index_s=0, aux_length_s=0)
    p.set(3, index); p.set(4, offset)
    flags = (1 if row else 0) | (2 if head else 0) | (4 if patch is not None else 0)
    if patch is not None: p.set(5, patch)
    p.call('FACTOR_RANGE_TEMPLATE', 'D', 'R', length=length, template='factor_range_template',
           out=11, sa=5 if patch is not None else 0, dense=1, support_length_s=28,
           index_s=3, aux_length_s=4, flags=flags)
    # The VM result interface reads full X. Copy only the actual op24 tap into
    # an otherwise valid vector, retaining the op24 publication extent.
    p.op('zero', 'X', length=p.n); p.set(6, 1 if head else length)
    p.call('REPLACE_RANGE', 'X', 'X', length=p.n, aux_v=p.v['D'], index_s=0, aux_length_s=6)
    p.a.emit('HALT_STATUS', dst_v=p.v['X'], a_v=p.v['R'], b_v=p.v['S'],
             immediate=ABI['statuses']['MAX_ITERATIONS'])
    package = p.finish(); package['measurement_vector'] = p.v['Y']

    # Independent raw oracle: FACTOR_INIT imports C18 B widened by <<6;
    # public R is the data-format measurement rescaled into S27.
    ar = Arithmetic(PROFILE)
    raw_phi = ar.quantize(matrix, PROFILE.coefficient)
    raw_measurement = ar.rescale(ar.quantize(measurement, PROFILE.data),
                                 PROFILE.data.frac, PROFILE.state)
    factors = np.asarray(raw_phi[:, support], dtype=object) << 6
    factor_values = [int(factors[index, offset + lane] if row else factors[offset + lane, index])
                     for lane in range(length)]
    if patch is not None: factor_values[0] = patch
    source = [int(raw_measurement[offset + lane]) for lane in range(length)]
    raw_sum = sum(left * right for left, right in zip(factor_values, source))
    return package, matrix, measurement, raw_sum, factor_values[:1] if head else factor_values


class FactorRangeTemplateSoftwareTests(unittest.TestCase):
    def test_generic_signed_row_column_offset_patch_full_and_head(self):
        cases = (
            dict(row=False, head=False, patch=-(1 << 20) + 17, index=2, offset=3, length=5),
            dict(row=True, head=False, patch=None, index=4, offset=1, length=4),
            dict(row=False, head=True, patch=None, index=1, offset=2, length=4),
            dict(row=True, head=True, patch=(1 << 20) - 9, index=7, offset=0, length=5),
            # Crosses a 32-lane frame boundary. The raw expected value is one
            # Python ACC64 sum, so a per-frame/lane round would be visible.
            dict(row=False, head=False, patch=-(1 << 21) + 3, index=2, offset=17, length=33, rows=64, columns=64),
        )
        for shape in cases:
            with self.subTest(**shape):
                package, matrix, measurement, expected_sum, expected_tap = range_micro(**shape)
                pc = kernel_pcs(package, 24); self.assertEqual(len(pc), 1)
                fields = decode(package['program'][pc[0]])
                self.assertEqual((fields['b_v'], fields['dst_s'], fields['flag_s'], fields['target']),
                                 (0, 11, 0, 0))
                for runner in (execute, reference_execute):
                    result = runner(package, matrix, measurement, limit=10000)
                    self.assertEqual(result['scalar_registers'][11], expected_sum)
                    self.assertEqual(list(result['x'])[:len(expected_tap)], expected_tap)
                    self.assertEqual(result['status'], 'max_iterations')

    def test_false_default_image_identity_and_feature_gating(self):
        matrix, _ = fixture(32, 64); policy = Policy(8, max_iterations=2, residual_atol=0)
        default = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='view')
        explicit_false = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='view',
                                           factor_range_template=False)
        self.assertEqual(identity_fields(default), identity_fields(explicit_false))
        self.assertFalse(default['qr_factor_range_template_enabled'])
        self.assertNotIn(24, [decode(word)['kernel'] for word in default['program']
                              if decode(word)['kind'] == ABI['kinds']['KERNEL']])
        with self.assertRaisesRegex(ValueError, 'requires qr_profile=view'):
            compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='compact', factor_range_template=True)
        # The suite flag reaches the exporter but must be inert for a non-QR
        # program; QR-only feature9 never leaks into MP's load image.
        spec = dict(algorithm='MP', policy=dict(sparsity=8, max_iterations=8),
                    operator=dict(kind='lfsr32', seed=0x12345678, rows=32, columns=64, scale_raw=8192))
        self.assertEqual(identity_fields(compile_spec(spec, target_kernel_revision=2)),
                         identity_fields(compile_spec(spec, target_kernel_revision=2, factor_range_template=True)))

    def _compare(self, algorithm, matrix, measurement, policy):
        before = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view')
        after = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view', factor_range_template=True)
        debug_vectors = {'qr_T': 'support', 'qr_Y': matrix.shape[0]}
        if 'RU_QTY' in {entry['name'] for entry in before['vectors']}:
            debug_vectors['RU_QTY'] = matrix.shape[0]
        baseline = execute(before, matrix, measurement, limit=6_000_000, debug_vectors=debug_vectors)
        self.assertEqual(after['required_kernel_revision'], 9)
        self.assertTrue(after['qr_factor_range_template_enabled'])
        self.assertGreater(len(kernel_pcs(after, 24)), 0)
        observed = []
        for runner in (execute, reference_execute):
            result = runner(after, matrix, measurement, limit=6_000_000, debug_vectors=debug_vectors); observed.append(result)
            self.assertEqual((list(result['x']), list(result['residual']), result['support'], result['status'], result['outer'], result['inner']),
                             (list(baseline['x']), list(baseline['residual']), baseline['support'], baseline['status'], baseline['outer'], baseline['inner']))
            self.assertEqual((result['debug_factors'], result['debug_vectors']),
                             (baseline['debug_factors'], baseline['debug_vectors']))
        self.assertEqual((list(observed[0]['x']), list(observed[0]['residual']), observed[0]['support'], observed[0]['status'], observed[0]['outer'], observed[0]['inner'], observed[0]['debug_factors'], observed[0]['debug_vectors']),
                         (list(observed[1]['x']), list(observed[1]['residual']), observed[1]['support'], observed[1]['status'], observed[1]['outer'], observed[1]['inner'], observed[1]['debug_factors'], observed[1]['debug_vectors']))
        # Op24 changes only the factor-read/tap transport. INIT and reuse
        # EXTEND physical operations remain observable and must not drift.
        self.assertEqual(kernel_trace(before, baseline, 13), kernel_trace(after, observed[0], 13))
        self.assertEqual(kernel_trace(before, baseline, 19), kernel_trace(after, observed[0], 19))
        return before, after, observed[0]

    def test_qr_outputs_m32_m64_and_omp_correction_trace(self):
        for rows, columns, seed in ((32, 64, 177), (64, 256, 311)):
            with self.subTest(rows=rows, columns=columns):
                matrix, measurement = fixture(rows, columns, seed)
                self._compare('CoSaMP', matrix, measurement, Policy(8, max_iterations=2, residual_atol=0))
        matrix = lfsr32_matrix(0x12345678, 16, 32, scale=8192) / 65536.0
        measurement = np.random.default_rng(1).integers(-4096, 4097, 16) / 16384.0
        _, package, result = self._compare('OMP', matrix, measurement,
                                            Policy(4, max_iterations=3, residual_atol=0, ls_normal_rtol=1e-6))
        extension = [i for i, pc in enumerate(result['trace']) if decode(package['program'][pc])['kind'] == 1 and decode(package['program'][pc])['kernel'] == 19]
        corrections = [i for i, pc in enumerate(result['trace']) if pc == package['labels']['qr_solve']]
        op24 = [i for i, pc in enumerate(result['trace']) if decode(package['program'][pc])['kind'] == 1 and decode(package['program'][pc])['kernel'] == 24]
        self.assertGreaterEqual(len(extension), 2)
        self.assertTrue(any(point > extension[0] for point in corrections))
        self.assertTrue(any(point > corrections[-1] for point in op24))

    def test_gomp_support96_matches_view(self):
        matrix = lfsr32_matrix(0x12345678, 128, 128, scale=4096) / 65536.0
        measurement = np.random.default_rng(911).integers(-8192, 8193, 128) / 16384.0
        _, package, result = self._compare('GOMP', matrix, measurement,
                                            Policy(2, max_iterations=2, group_size=48, residual_atol=0))
        self.assertEqual(len(result['support']), 96)
        self.assertGreater(len(kernel_pcs(package, 24)), 0)


if __name__ == '__main__':
    unittest.main()
