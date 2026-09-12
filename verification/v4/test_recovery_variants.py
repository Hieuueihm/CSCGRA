"""Integer-model comparisons for QR outers and opt-in sparse forwards."""
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import ALGORITHMS, compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE, compile_recovery
from models.v4.fixed import Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy, run
from verification.v4.recovery_program_vm import execute


class RecoveryVariantTests(unittest.TestCase):
    def test_five_qr_outers_match_fixed_model(self):
        matrix = lfsr32_matrix(0x12345678, 16, 32, scale=16384)/65536.0
        policy = Policy(2, max_iterations=3)
        for refinements in (0, 2):
            for algorithm in ALGORITHMS:
                for zero in (False, True):
                    with self.subTest(algorithm=algorithm, refinements=refinements, zero=zero):
                        y = np.zeros(16) if zero else matrix[:, 3]*1.25+matrix[:, 7]*0.75
                        package = compile_greedy_qr(algorithm, matrix, policy, max_refinements=refinements)
                        actual = execute(package, matrix, y)
                        expected = run(algorithm, matrix, y, policy, PROFILE,
                                       ls_solver='qr', solution_format=Format(24, 20),
                                       qr_max_refinements=refinements)
                        np.testing.assert_array_equal(actual['x'], np.asarray(expected.raw_x)*4)
                        np.testing.assert_array_equal(actual['residual'], np.rint(expected.residual*2**22))
                        self.assertEqual(actual['support'], expected.support)
                        self.assertEqual(actual['status'], expected.status)
                        self.assertEqual(package['qr_max_refinements'], refinements)
                        self.assertFalse(any(expected.events.values()))

    def test_sparse_forward_matches_full_phi_and_fixed_model(self):
        for rows, columns, scale in ((7, 35, 16384), (16, 32, 16384), (128, 1024, 4096)):
            matrix = lfsr32_matrix(0x12345678, rows, columns, scale=scale)/65536.0
            policy = Policy(2, max_iterations=2)
            for algorithm in ('MP', 'GP', 'IHT'):
                for zero in (False, True):
                    with self.subTest(algorithm=algorithm, rows=rows, zero=zero):
                        y = np.zeros(rows) if zero else matrix[:, 0]*1.25+matrix[:, 1]*0.75
                        baseline = execute(compile_recovery(algorithm, matrix, policy), matrix, y)
                        package = compile_recovery(algorithm, matrix, policy, sparse_forward=True)
                        actual = execute(package, matrix, y)
                        expected = run(algorithm, matrix, y, policy, PROFILE,
                                       ls_solver='lsqr', solution_format=Format(24, 20))
                        # The existing X24 provider is reused; these algorithms never call LS.
                        self.assertEqual(expected.solver_trace, [])
                        np.testing.assert_array_equal(actual['x'], baseline['x'])
                        np.testing.assert_array_equal(actual['residual'], baseline['residual'])
                        np.testing.assert_array_equal(actual['x'], np.asarray(expected.raw_x)*4)
                        self.assertEqual(actual['support'], expected.support)
                        self.assertEqual(actual['status'], expected.status)
                        self.assertEqual(actual['outer'], baseline['outer'])
                        self.assertEqual(actual['inner'], baseline['inner'])

    def test_unsupported_policies_reject_without_truncation(self):
        matrix = lfsr32_matrix(0x12345678, 8, 16, scale=16384)/65536.0
        with self.assertRaises(ValueError):
            compile_greedy_qr('CoSaMP', matrix, Policy(3))
        with self.assertRaises(ValueError):
            compile_greedy_qr('HTP', matrix, Policy(2), max_refinements=3)
        with self.assertRaises(ValueError):
            compile_recovery('FISTA', matrix, Policy(2), sparse_forward=True)
        with self.assertRaises(ValueError):
            compile_recovery('IHT', matrix, Policy(9), sparse_forward=True)
        with self.assertRaises(ValueError):
            compile_recovery('MP', matrix, Policy(2,max_iterations=9), sparse_forward=True)


if __name__ == '__main__':
    unittest.main()
