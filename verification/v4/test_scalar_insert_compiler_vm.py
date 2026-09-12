"""Feature6 compact QR emission and integer VM equivalence.

These are compiler/VM gates only. RTL ownership and Vivado gates remain with
the Phase-C kernel owner.
"""
import copy
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode, encode, unpack
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute


def fixture(rows=32, columns=64):
    matrix = lfsr32_matrix(0x12345678, rows, columns, scale=8192) / 65536.0
    measurement = np.random.default_rng(177).integers(-4096, 4097, rows) / 16384.0
    return matrix, measurement


def kernel_pcs(package, op):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == op]


class ScalarInsertCompilerVmTests(unittest.TestCase):
    def test_compact_is_a_suite_profile_for_all_qr_algorithms(self):
        matrix, measurement = fixture()
        for algorithm, policy in (
            ('OMP', Policy(4, max_iterations=3, residual_atol=0)),
            ('GOMP', Policy(4, max_iterations=3, group_size=4, residual_atol=0)),
            ('CoSaMP', Policy(4, max_iterations=2, residual_atol=0)),
            ('SP', Policy(4, max_iterations=2, residual_atol=0)),
            ('HTP', Policy(4, max_iterations=2, residual_atol=0)),
        ):
            with self.subTest(algorithm=algorithm):
                resident = compile_greedy_qr(algorithm, matrix, policy, qr_profile='resident')
                compact = compile_greedy_qr(algorithm, matrix, policy, qr_profile='compact')
                before = execute(resident, matrix, measurement, limit=2_000_000)
                after = execute(compact, matrix, measurement, limit=2_000_000)
                self.assertEqual(list(after['x']), list(before['x']))
                self.assertEqual(list(after['residual']), list(before['residual']))
                self.assertEqual((after['support'], after['status'], after['outer'], after['inner']),
                                 (before['support'], before['status'], before['outer'], before['inner']))
                self.assertEqual(compact['required_kernel_revision'], 6)

    def test_m64_compact_matches_resident_coarse_program(self):
        matrix, measurement = fixture(64, 256)
        policy = Policy(8, max_iterations=3, residual_atol=0)
        resident = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='resident')
        compact = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='compact')
        before = execute(resident, matrix, measurement, limit=3_000_000)
        after = execute(compact, matrix, measurement, limit=3_000_000)
        reference = reference_execute(compact, matrix, measurement, limit=3_000_000)
        self.assertGreater(len(kernel_pcs(compact, 21)), 0)
        for observed in (after, reference):
            self.assertEqual(list(observed['x']), list(before['x']))
            self.assertEqual(list(observed['residual']), list(before['residual']))
            self.assertEqual((observed['support'], observed['status'], observed['outer'], observed['inner']),
                             (before['support'], before['status'], before['outer'], before['inner']))

    def test_compact_replaces_backsolve_scalar_vector_transport(self):
        matrix, measurement = fixture()
        policy = Policy(8, max_iterations=2, residual_atol=0)
        resident = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='resident')
        compact = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='compact')
        pcs = kernel_pcs(compact, 21)
        self.assertTrue(pcs)
        self.assertEqual(compact['required_kernel_revision'], 6)
        self.assertTrue(compact['qr_scalar_insert_enabled'])
        self.assertLess(len(kernel_pcs(compact, 12)), len(kernel_pcs(resident, 12)))
        for pc in pcs:
            fields = decode(compact['program'][pc])
            immediate = unpack(ABI['service_immediate_fields'], fields['immediate'])
            template = compact['templates'][immediate['template']]
            self.assertEqual((template['descriptor'], template['bind_a'], template['bind_b'], template['contexts']),
                             (0, 0, 0, [0] * 32))
            self.assertEqual((fields['a_v'], fields['b_v'], fields['dst_s'], fields['flag_s'], fields['target']),
                             (fields['dst_v'], 0, 0, 0, 0))
            self.assertEqual((immediate['dense'], immediate['transpose'], immediate['r4'], immediate['store_mode'],
                              immediate['flags'], immediate['k_s'], immediate['support_v'], immediate['aux_v'],
                              immediate['support_length_s'], immediate['aux_length_s']), (0,) * 10)
        before = execute(resident, matrix, measurement, limit=2_000_000)
        compact_result = execute(compact, matrix, measurement, limit=2_000_000)
        reference_result = reference_execute(compact, matrix, measurement, limit=2_000_000)
        for observed in (compact_result, reference_result):
            self.assertEqual(list(observed['x']), list(before['x']))
            self.assertEqual(list(observed['residual']), list(before['residual']))
            self.assertEqual((observed['support'], observed['status'], observed['outer'], observed['inner']),
                             (before['support'], before['status'], before['outer'], before['inner']))

    def test_compact_composes_reuse_and_preserves_old_profiles(self):
        matrix, measurement = fixture()
        policy = Policy(4, max_iterations=3, group_size=4, residual_atol=0)
        reuse = compile_greedy_qr('GOMP', matrix, policy, qr_profile='reuse')
        compact = compile_greedy_qr('GOMP', matrix, policy, qr_profile='compact')
        self.assertTrue(compact['qr_reuse_enabled'])
        self.assertGreater(len(kernel_pcs(compact, 19)), 0)
        self.assertGreater(len(kernel_pcs(compact, 21)), 0)
        before = execute(reuse, matrix, measurement, limit=2_000_000)
        after = execute(compact, matrix, measurement, limit=2_000_000)
        self.assertEqual((list(after['x']), list(after['residual']), after['support'], after['status'], after['outer'], after['inner']),
                         (list(before['x']), list(before['residual']), before['support'], before['status'], before['outer'], before['inner']))
        for profile in ('reference', 'balanced', 'panel', 'reuse', 'resident'):
            old = compile_greedy_qr('CoSaMP', matrix, Policy(8, max_iterations=2, residual_atol=0), qr_profile=profile)
            self.assertNotIn(21, [decode(word)['kernel'] for word in old['program']
                                  if decode(word)['kind'] == ABI['kinds']['KERNEL']])

    def test_scalar_insert_vm_rejects_noncanonical_loaded_record(self):
        matrix, measurement = fixture()
        package = compile_greedy_qr('CoSaMP', matrix, Policy(8, max_iterations=2, residual_atol=0),
                                    qr_profile='compact')
        pc = kernel_pcs(package, 21)[0]
        index = unpack(ABI['service_immediate_fields'], decode(package['program'][pc])['immediate'])['template']
        for name, mutate in (
            ('template_context', lambda p: p['templates'][index]['contexts'].__setitem__(0, 1)),
            ('template_bind', lambda p: p['templates'][index].update(bind_a=1)),
            ('source_b', lambda p: self._set_field(p, pc, 'b_v', 1)),
            ('range_scalar', lambda p: self._set_preceding_scalar(p, pc, 1 << 26)),
        ):
            with self.subTest(name=name):
                bad = copy.deepcopy(package)
                mutate(bad)
                for runner in (execute, reference_execute):
                    with self.subTest(runner=runner.__module__):
                        with self.assertRaises((AssertionError, ArithmeticError)):
                            runner(bad, matrix, measurement, limit=2_000_000)

    @staticmethod
    def _set_field(package, pc, field, value):
        fields = decode(package['program'][pc]); fields[field] = value
        package['program'][pc] = encode('KERNEL', **{key: fields[key] for key in ABI['allowed_fields']['KERNEL']})

    @staticmethod
    def _set_preceding_scalar(package, pc, value):
        # The backsolve scalar is computed by DIV directly before the insert.
        fields = decode(package['program'][pc - 1])
        if fields['kind'] != ABI['kinds']['DIV']:
            raise AssertionError('compact insert must directly follow backsolve DIV')
        package['program'][pc - 1] = encode('SET', dst_s=fields['dst_s'], immediate=value)


if __name__ == '__main__':
    unittest.main()
