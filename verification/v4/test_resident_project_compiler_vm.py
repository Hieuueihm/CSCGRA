"""Feature5 FACTOR_PROJECT_UPDATE compiler and independent-VM checks."""
import copy
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode, encode, unpack
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute


def fixture(rows=64, columns=256):
    matrix = lfsr32_matrix(0x12345678, rows, columns, scale=8192) / 65536.0
    measurement = np.random.default_rng(77).integers(-4096, 4097, rows) / 16384.0
    return matrix, measurement


def operation_pcs(package, operation):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == operation]


class ResidentProjectCompilerVmTests(unittest.TestCase):
    def pair(self, algorithm, matrix, measurement, policy):
        panel = compile_greedy_qr(algorithm, matrix, policy, qr_profile='panel')
        resident = compile_greedy_qr(algorithm, matrix, policy, qr_profile='resident')
        before = execute(panel, matrix, measurement, limit=3_000_000)
        after = execute(resident, matrix, measurement, limit=3_000_000)
        reference = reference_execute(resident, matrix, measurement, limit=3_000_000)
        for result in (after, reference):
            self.assertEqual(list(result['x']), list(before['x']))
            self.assertEqual(list(result['residual']), list(before['residual']))
            self.assertEqual((result['support'], result['status'], result['outer'], result['inner']),
                             (before['support'], before['status'], before['outer'], before['inner']))
        self.assertEqual(list(after['x']), list(reference['x']))
        self.assertEqual(list(after['residual']), list(reference['residual']))
        return panel, resident, after

    def test_m64_panel_and_resident_match_with_private_project_update(self):
        matrix, measurement = fixture()
        panel, resident, result = self.pair('CoSaMP', matrix, measurement,
                                            Policy(8, max_iterations=3, residual_atol=0))
        self.assertTrue(resident['qr_resident_project_enabled'])
        self.assertEqual((resident['revision'], resident['required_kernel_revision']), (2, 5))
        self.assertGreater(len(operation_pcs(resident, 20)), 0)
        self.assertEqual(operation_pcs(resident, 17), [])
        self.assertEqual(operation_pcs(resident, 18), [])
        self.assertGreaterEqual(result['inner'], 1)
        template_index = unpack(ABI['service_immediate_fields'],
                                decode(resident['program'][operation_pcs(resident, 20)[0]])['immediate'])['template']
        template = resident['templates'][template_index]
        self.assertEqual((template['descriptor'], template['bind_a'], template['bind_b']), (31, 0, 0))
        self.assertEqual(template['contexts'], [297, 296, 291] + [0] * 29)

    def test_gomp_reuse_and_resident_project_compose(self):
        matrix, measurement = fixture(32, 64)
        policy = Policy(4, max_iterations=3, group_size=4, residual_atol=0)
        panel, resident, result = self.pair('GOMP', matrix, measurement, policy)
        self.assertTrue(resident['qr_reuse_enabled'])
        self.assertTrue(resident['qr_resident_project_enabled'])
        self.assertGreater(len(operation_pcs(resident, 19)), 0)
        self.assertGreater(len(operation_pcs(resident, 20)), 0)
        self.assertEqual(operation_pcs(resident, 17), [])
        self.assertEqual(operation_pcs(resident, 18), [])
        self.assertGreaterEqual(result['outer'], 1)

    def test_compact_template_and_canonical_operands_reject_mutation(self):
        matrix, measurement = fixture(32, 64)
        package = compile_greedy_qr('CoSaMP', matrix, Policy(8, max_iterations=2, residual_atol=0),
                                    qr_profile='resident')
        pc = operation_pcs(package, 20)[0]
        template_index = unpack(ABI['service_immediate_fields'], decode(package['program'][pc])['immediate'])['template']
        for name, mutate in (
            ('context', lambda p: p['templates'][template_index]['contexts'].__setitem__(2, 292)),
            ('descriptor', lambda p: p['templates'][template_index].update(descriptor=30)),
            ('unused_dst', lambda p: self._set_field(p, pc, 'dst_v', 1)),
            ('unused_scalar_b', lambda p: self._set_field(p, pc, 'b_s', 1)),
        ):
            with self.subTest(name=name):
                bad = copy.deepcopy(package)
                mutate(bad)
                for runner in (execute, reference_execute):
                    with self.subTest(runner=runner.__module__):
                        with self.assertRaisesRegex(AssertionError, 'FACTOR_PROJECT_UPDATE|factor panel'):
                            runner(bad, matrix, measurement, limit=1_000_000)

    @staticmethod
    def _set_field(package, pc, field, value):
        decoded = decode(package['program'][pc])
        decoded[field] = value
        package['program'][pc] = encode('KERNEL', **{name: decoded[name] for name in ABI['allowed_fields']['KERNEL']})

    def test_maximum_support96_resident_compiles_and_nonproject_profiles_stay_exact(self):
        matrix, _ = fixture(128, 1024)
        policy = Policy(48, max_iterations=2, group_size=48, residual_atol=0)
        resident = compile_greedy_qr('GOMP', matrix, policy, qr_profile='resident')
        self.assertEqual(resident['restricted_support_bound'], 96)
        self.assertTrue(resident['qr_resident_project_enabled'])
        self.assertGreater(len(operation_pcs(resident, 20)), 0)
        # Existing named profiles retain their distinct feature contracts.
        for profile, revision in (('reference', 1), ('balanced', 2), ('panel', 3), ('reuse', 3)):
            package = compile_greedy_qr('CoSaMP', matrix, Policy(8, max_iterations=2, residual_atol=0),
                                        qr_profile=profile)
            self.assertEqual(package['required_kernel_revision'], revision)
            self.assertNotIn(20, [decode(word)['kernel'] for word in package['program']
                                  if decode(word)['kind'] == ABI['kinds']['KERNEL']])


if __name__ == '__main__':
    unittest.main()
