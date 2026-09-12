"""Pure compiler/VM guards for the optional generic factor-panel schedule."""
import copy
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE
from compiler.v4.recovery_program import ABI, decode, unpack
from models.v4.fixed import Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy, run
from verification.v4.recovery_program_vm import execute


def fixture(rows=32, columns=64):
    raw_phi = lfsr32_matrix(0x12345678, rows, columns, scale=8192).astype(int)
    matrix = raw_phi / 65536.0
    planted = np.zeros(columns)
    planted[[2, 5, 11, 19, 23, 37, 44, 51]] = [.5, -.7, .6, .8, -.9, .5, .6, -.7]
    return matrix, matrix @ planted


class FactorPanelCompilerVmTests(unittest.TestCase):
    def test_cosamp_panel_vm_matches_serial_and_fixed_qr(self):
        matrix, measurement = fixture()
        policy = Policy(8, max_iterations=3, residual_atol=0)
        serial = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='balanced')
        panel = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='panel', qr_panel_min_columns=8)
        operations = [decode(word)['kernel'] for word in panel['program'] if decode(word)['kind'] == 1]
        self.assertEqual(panel['required_kernel_revision'], 3)
        self.assertEqual(panel['qr_panel_min_columns'], 8)
        self.assertIn(17, operations)
        self.assertIn(18, operations)
        before, after = execute(serial, matrix, measurement), execute(panel, matrix, measurement)
        self.assertEqual(list(after['x']), list(before['x']))
        self.assertEqual(list(after['residual']), list(before['residual']))
        self.assertEqual((after['support'], after['status'], after['outer']),
                         (before['support'], before['status'], before['outer']))
        expected = run('CoSaMP', matrix, measurement, policy, PROFILE,
                       ls_solver='qr', solution_format=Format(24, 20))
        self.assertEqual(list(after['x']), [round(float(value) * 2**22) for value in expected.x])
        self.assertEqual(list(after['residual']), [round(float(value) * 2**22) for value in expected.residual])
        self.assertEqual(after['support'], expected.support)

    def test_statically_narrow_htp_has_balanced_byte_identical_code(self):
        matrix, measurement = fixture()
        del measurement
        policy = Policy(8, max_iterations=8, residual_atol=0)
        balanced = compile_greedy_qr('HTP', matrix, policy, qr_profile='balanced')
        panel = compile_greedy_qr('HTP', matrix, policy, qr_profile='panel', qr_panel_min_columns=8)
        for field in ('program', 'templates', 'vectors', 'constants'):
            self.assertEqual(panel[field], balanced[field], field)
        self.assertEqual(panel['required_kernel_revision'], 2)
        self.assertEqual(panel['qr_panel_disabled_reason'], 'maximum_support_not_wider_than_threshold')
        operations = [decode(word)['kernel'] for word in panel['program'] if decode(word)['kind'] == 1]
        self.assertNotIn(17, operations)
        self.assertNotIn(18, operations)

    def test_panel_vm_rejects_mutated_loaded_context_images(self):
        matrix, measurement = fixture()
        policy = Policy(8, max_iterations=3, residual_atol=0)
        package = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='panel', qr_panel_min_columns=8)
        index = next(unpack(ABI['service_immediate_fields'], decode(word)['immediate'])['template']
                     for word in package['program']
                     if decode(word)['kind'] == 1 and decode(word)['kernel'] == 18)
        bad = copy.deepcopy(package)
        bad['templates'][index]['contexts'][16] ^= 1
        with self.assertRaisesRegex(AssertionError, 'FACTOR_RANK1'):
            execute(bad, matrix, measurement)


if __name__ == '__main__':
    unittest.main()
