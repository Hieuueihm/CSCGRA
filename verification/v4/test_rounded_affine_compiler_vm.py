"""Feature8 compiler/VM tests for the explicit ROUNDED_AFFINE command.

These are integer schedule checks, not RTL qualification.  Both VMs share the
project Arithmetic implementation, so their agreement is control-path evidence;
the scalar expected values below use a local round-away/clip calculation.
"""
import unittest

import numpy as np

from compiler.v4.recovery_emit import PROFILE, Program, compile_recovery
from compiler.v4.recovery_program import ABI, decode, load_records
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from models.v4.fixed import Format
from models.v4.proximal import Policy as ProximalPolicy
from models.v4.recovery import Policy, run
from models.v4.proximal import run as proximal_run
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as execute_reference


def round_away(value, shift=22):
    quotient, remainder = divmod(abs(int(value)), 1 << shift)
    if remainder * 2 >= 1 << shift:
        quotient += 1
    return -quotient if value < 0 else quotient


def checked_state(value):
    return max(-(1 << 26), min((1 << 26) - 1, int(value)))


class RoundedAffineCompilerVmTests(unittest.TestCase):
    matrix = np.ones((3, 3), dtype=float) * .25

    def direct_package(self, *, scalar=None, subtract=False, distinct_operands=True, scalar_register=None):
        policy = Policy(1, max_iterations=1)
        p = Program('GP', self.matrix, policy, None, operand_chains=True)
        p.vec('C', 3)
        if distinct_operands:
            # Build X=round22(Y*0.5) and C=Y+X.  This proves the command
            # reads all three inputs instead of accidentally reusing Y.
            p.set(1, 1 << 21)
            p.scale_op('X', 'Y', 1, length=3)
            p.op('add', 'C', 'Y', 'X', length=3)
            default_scalar_register = 2
        else:
            p.op('copy', 'X', 'Y', length=3)
            p.op('copy', 'C', 'Y', length=3)
            default_scalar_register = 1
        if scalar is None:
            p.affine('X', 'C', 'X', y='Y', subtract=subtract, length=3)
        else:
            scalar_register = default_scalar_register if scalar_register is None else scalar_register
            if scalar_register:
                p.set(scalar_register, scalar)
            elif scalar != 0:
                raise ValueError('R0 scalar test requires canonical zero')
            p.affine('X', 'C', 'X', scalar=scalar_register, subtract=subtract, length=3)
        p.halt('MAX_ITERATIONS')
        package = p.finish()
        package.update(operand_chains=True, operand_chains_emitted=True,
                       required_kernel_revision=8,
                       required_kernel_features=['ROUNDED_AFFINE'])
        return package

    def expected_direct(self, measurement, scalar=None, subtract=False, distinct_operands=True):
        # Measurement enters D18F16 then is embedded to S27F22 by the VM.
        raw = [int(round(value * (1 << 16))) << 6 for value in measurement]
        x = [round_away(value * (1 << 21)) for value in raw] if distinct_operands else raw
        c = [checked_state(value + item) for value, item in zip(raw, x)] if distinct_operands else raw
        right = raw if scalar is None else [scalar] * len(raw)
        return [checked_state(c_value - round_away(x_value * y_value) if subtract else
                              c_value + round_away(x_value * y_value))
                for c_value, x_value, y_value in zip(c, x, right)]

    def assert_same_execution(self, left, right, *, include_trace=True):
        for key in ('x', 'residual', 'support', 'status', 'outer', 'inner') + (('trace',) if include_trace else ()):
            self.assertEqual(list(left[key]) if hasattr(left[key], 'tolist') else left[key],
                             list(right[key]) if hasattr(right[key], 'tolist') else right[key], key)

    def test_scalar_add_and_sub_follow_raw_round22_formula(self):
        measurement = np.array([.125, -.1875, .0625])
        for scalar, subtract in ((-3145728, False), (3145728, True)):
            with self.subTest(scalar=scalar, subtract=subtract):
                package = self.direct_package(scalar=scalar, subtract=subtract)
                actual = execute(package, self.matrix, measurement)
                reference = execute_reference(package, self.matrix, measurement)
                self.assertEqual(list(actual['x']), self.expected_direct(measurement, scalar, subtract))
                self.assert_same_execution(actual, reference)
                calls = [decode(word) for word in package['program'] if decode(word)['kind'] == ABI['kinds']['KERNEL']]
                affine = [call for call in calls if call['kernel'] == 23]
                self.assertEqual(len(affine), 1)
                self.assertEqual(affine[0]['a_s'], 0)
                self.assertEqual(affine[0]['b_s'], 2)

    def test_scalar_r0_zero_is_a_legal_bound_operand(self):
        measurement = np.array([.125, -.1875, .0625])
        package = self.direct_package(scalar=0, scalar_register=0)
        actual = execute(package, self.matrix, measurement)
        self.assertEqual(list(actual['x']), self.expected_direct(measurement, scalar=0))
        affine = [decode(word) for word in package['program']
                  if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == 23]
        self.assertEqual(affine[0]['b_s'], 0)

    def test_vector_b_and_compact_template_are_exact(self):
        measurement = np.array([.125, -.1875, .0625])
        package = self.direct_package()
        actual = execute(package, self.matrix, measurement)
        self.assertEqual(list(actual['x']), self.expected_direct(measurement))
        affine_template = next(t for t in package['templates'] if t['name'] == 'affine_add_vector')
        self.assertEqual(affine_template['descriptor'], 7)
        self.assertEqual(affine_template['bind_a'], 0)
        self.assertEqual(affine_template['bind_b'], 0)
        self.assertEqual(affine_template['contexts'][:16], [296] * 16)
        self.assertEqual(affine_template['contexts'][16:], [290] * 16)

    def test_affected_algorithms_match_legacy_and_reference_vm(self):
        matrix = np.array([[.25, -.25, .25], [-.25, .25, .25], [.25, .25, -.25],
                           [.25, -.25, -.25]], dtype=float)
        measurement = np.array([.125, -.0625, .09375, -.03125])
        for algorithm in ('GP', 'IHT', 'FISTA', 'PDHG'):
            policy = ProximalPolicy(max_iterations=3) if algorithm in ('FISTA', 'PDHG') else Policy(2, max_iterations=3)
            with self.subTest(algorithm=algorithm):
                legacy = compile_recovery(algorithm, matrix, policy)
                chained = compile_recovery(algorithm, matrix, policy, operand_chains=True)
                self.assertFalse(legacy['operand_chains'])
                self.assertTrue(chained['operand_chains_emitted'])
                self.assertEqual(chained['required_kernel_revision'], 8)
                old = execute(legacy, matrix, measurement)
                new = execute(chained, matrix, measurement)
                # Feature8 intentionally changes PC/retired command shape;
                # recovery outputs and solver-visible counters must not move.
                self.assert_same_execution(new, old, include_trace=False)
                self.assert_same_execution(new, execute_reference(chained, matrix, measurement))
                expected = (proximal_run(algorithm, matrix, measurement, policy, PROFILE)
                            if algorithm in ('FISTA', 'PDHG') else
                            run(algorithm, matrix, measurement, policy, PROFILE,
                                ls_solver='lsqr', solution_format=Format(24, 20)))
                self.assertEqual(list(new['x']), [round(float(value) * 2 ** 22) for value in expected.x])
                self.assertEqual(list(new['residual']), [round(float(value) * 2 ** 22) for value in expected.residual])

    def test_unaffected_programs_do_not_add_affine_template_or_revision(self):
        matrix = np.ones((4, 5), dtype=float) * .25
        for algorithm, policy in (('MP', Policy(2, max_iterations=2)), ('ADMM', ProximalPolicy(max_iterations=2))):
            with self.subTest(algorithm=algorithm):
                package = compile_recovery(algorithm, matrix, policy, operand_chains=True)
                self.assertTrue(package['operand_chains'])
                self.assertFalse(package['operand_chains_emitted'])
                self.assertEqual(package['required_kernel_revision'], 1)
                self.assertNotIn(23, [decode(word)['kernel'] for word in package['program'] if decode(word)['kind'] == ABI['kinds']['KERNEL']])

    def test_mixed_upper_context_is_rejected_before_execution(self):
        package = self.direct_package()
        template = next(t for t in package['templates'] if t['name'] == 'affine_add_vector')
        template['contexts'][17] = 291
        with self.assertRaisesRegex(AssertionError, 'mixed upper'):
            execute(package, self.matrix, np.array([.125, -.1875, .0625]))

    def test_s27_product_overflow_is_a_fault_not_a_clipped_pass(self):
        package = self.direct_package(scalar=(1 << 26) - 1, distinct_operands=False)
        with self.assertRaisesRegex(ArithmeticError, 'numeric_fault'):
            execute(package, self.matrix, np.array([1.5, -1.5, .5]))

    def test_explicit_false_preserves_all_active_compiler_images(self):
        # This is a compiler-image guard only.  It is intentionally not a
        # substitute for the source-bound fixed8 whole-program XSim pairing.
        for rows, columns in ((32, 64), (64, 256)):
            matrix = np.ones((rows, columns), dtype=float) * .01
            for algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'MP', 'GP', 'IHT', 'HTP', 'FISTA', 'PDHG'):
                with self.subTest(rows=rows, columns=columns, algorithm=algorithm):
                    policy = (ProximalPolicy(max_iterations=8) if algorithm in ('FISTA', 'PDHG') else
                              Policy(8, max_iterations=8, residual_atol=0))
                    if algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'):
                        default = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view')
                        explicit = compile_greedy_qr(algorithm, matrix, policy, qr_profile='view', operand_chains=False)
                    else:
                        default = compile_recovery(algorithm, matrix, policy,
                                                   sparse_forward=algorithm in ('MP', 'GP', 'IHT'))
                        explicit = compile_recovery(algorithm, matrix, policy,
                                                    sparse_forward=algorithm in ('MP', 'GP', 'IHT'), operand_chains=False)
                    for key in ('program', 'templates', 'vectors', 'constants'):
                        self.assertEqual(explicit[key], default[key], key)
                    self.assertEqual(load_records(explicit), load_records(default))


if __name__ == '__main__':
    unittest.main()
