"""Independent checks for LSQR solution-format storage.

These tests exercise X storage in the normalized solver domain.  Any job
normalization exponent belongs to host-side decode and is intentionally not
reconstructed here; the raw X format and state embedding are checked exactly.
"""

from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Arithmetic, Format, Profile
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy, run


class SolutionStorageTests(unittest.TestCase):
    def setUp(self):
        self.profile = Profile(
            Format(18, 14), Format(18, 16), Format(27, 19), 64
        )
        self.policy = Policy(
            sparsity=2, max_iterations=3, ls_max_iterations=16,
            residual_atol=0.0, ls_normal_rtol=1e-4,
        )

    def test_default_solution_format_is_D_and_explicit_D_is_unchanged(self):
        matrix = np.eye(2)
        measurement = np.array([0.5, -0.25])
        implicit = run(
            "OMP", matrix, measurement, self.policy, self.profile,
            ls_solver="lsqr",
        )
        explicit = run(
            "OMP", matrix, measurement, self.policy, self.profile,
            ls_solver="lsqr", solution_format=self.profile.data,
        )
        np.testing.assert_array_equal(implicit.x, explicit.x)
        np.testing.assert_array_equal(implicit.residual, explicit.residual)
        self.assertEqual(implicit.support, explicit.support)
        self.assertEqual(implicit.status, explicit.status)
        self.assertEqual(implicit.raw_x, explicit.raw_x)
        self.assertEqual(implicit.raw_x_format, {
            "width": self.profile.data.width,
            "frac": self.profile.data.frac,
        })

    def test_raw_X_roundtrip_and_certificate_use_stored_X(self):
        # X22F18 retains four more fractional bits than input D18F14.
        solution_format = Format(22, 18)
        matrix = np.array([[1.0, 0.3], [0.2, 1.0]])
        measurement = np.array([0.1234, -0.3212])
        backend = IntegerLSQRKernels(
            matrix, measurement, self.policy, self.profile,
            solution_format=solution_format,
        )
        candidate = backend.least_squares([0, 1])
        report = backend.last_ls_report
        self.assertEqual(backend.solution_format, solution_format)
        self.assertTrue(report["certificate_history"][-1]["passed"])

        # The report stores the embedded state raw value after X quantization.
        expected_x = np.array([
            backend.arithmetic.rescale(
                backend.arithmetic.rescale(int(value), self.profile.state.frac, solution_format),
                solution_format.frac, self.profile.state,
            )
            for value in report["last_pre_storage"]
        ], dtype=object)
        np.testing.assert_array_equal(report["last_candidate"], expected_x.tolist())

        # Result.raw_x is X raw, and decoding it in X reproduces normalized
        # result.x.  This is the host-side representation boundary.
        result = run(
            "OMP", matrix, measurement, self.policy, self.profile,
            ls_solver="lsqr", solution_format=solution_format,
        )
        decoded_x = Arithmetic(self.profile).decode(result.raw_x, solution_format)
        np.testing.assert_array_equal(decoded_x, result.x)
        self.assertTrue(any(int(raw) % (1 << (solution_format.frac - self.profile.data.frac))
                            for raw in result.raw_x))
        self.assertEqual(result.raw_x_format, {
            "width": solution_format.width, "frac": solution_format.frac,
        })
        np.testing.assert_array_equal(
            backend.decode(candidate),
            Arithmetic(self.profile).decode(report["last_candidate"], self.profile.state),
        )

    def test_narrow_X_overflow_is_numeric_fault_and_outer_state_rolls_back(self):
        # Normalized y peak control does not bound x for B=diag(.01, 1): the
        # first coefficient is about 50 in the normalized domain.
        matrix = np.diag([0.01, 1.0])
        measurement = np.array([0.5, 0.0])
        narrow_x = Format(10, 8)  # embeds in S but represents only about +/-2
        result = run(
            "OMP", matrix, measurement,
            Policy(sparsity=1, max_iterations=2, ls_max_iterations=8,
                   residual_atol=0.0, ls_normal_rtol=1e-4),
            self.profile, ls_solver="lsqr", solution_format=narrow_x,
        )
        self.assertEqual(result.status, "numeric_fault")
        self.assertGreater(result.events["saturation"], 0)
        self.assertEqual(result.support, [])
        np.testing.assert_array_equal(result.x, np.zeros(2))
        self.assertFalse(any(item["phase"] == "COMMIT" for item in result.trace))
        self.assertTrue(result.solver_trace)

    def test_certificate_observes_injected_coarse_stored_candidate(self):
        class ForcedCoarseStore(IntegerLSQRKernels):
            def store(self, value):
                self.injected_pre_storage = np.array([int(v) for v in value], dtype=object)
                return np.zeros(len(value), dtype=object)

        backend = ForcedCoarseStore(
            np.eye(2), np.array([0.5, 0.0]),
            Policy(sparsity=2, ls_max_iterations=1, ls_normal_rtol=1e-4),
            self.profile, solution_format=Format(22, 18),
        )
        with self.assertRaises(ArithmeticError):
            backend.least_squares([0, 1])
        report = backend.last_ls_report
        self.assertNotEqual(report["last_pre_storage"], report["last_candidate"])
        self.assertFalse(report["certificate_history"][-1]["passed"])
        self.assertGreater(report["certificate_history"][-1]["normal_energy_raw"], 0)

    def test_solution_format_must_embed_in_state_and_run_rejects_non_LSQR(self):
        # More fractional bits than S cannot be embedded exactly.
        with self.assertRaises(ValueError):
            IntegerLSQRKernels(
                np.eye(2), np.ones(2), self.policy, self.profile,
                solution_format=Format(24, 20),
            )
        # Same fractional position but too much signed range after rescale.
        with self.assertRaises(ValueError):
            IntegerLSQRKernels(
                np.eye(2), np.ones(2), self.policy, self.profile,
                solution_format=Format(27, 18),
            )
        with self.assertRaises(ValueError):
            run(
                "OMP", np.eye(2), np.ones(2), self.policy, self.profile,
                solution_format=Format(18, 14),
            )
        with self.assertRaises(ValueError):
            run(
                "OMP", np.eye(2), np.ones(2), self.policy,
                solution_format=Format(18, 14),
            )


if __name__ == "__main__":
    unittest.main()
