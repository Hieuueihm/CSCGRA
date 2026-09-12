"""Contract edges for the v4 LSQR implementation.

These tests intentionally cover paths that ordinary successful solves do not
exercise: constructor-time numeric faults, report lifetime, and a scalar
format whose fractional width differs from the vector state format.
"""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Format, Profile
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy


class LSQRContractEdgeTests(unittest.TestCase):
    def test_constructor_fault_is_checked_before_empty_support_success(self):
        profile = Profile(Format(8, 4), Format(8, 4), Format(12, 6), 8)
        backend = IntegerLSQRKernels(
            np.array([[100.0]]), np.array([0.0]),
            Policy(1, ls_max_iterations=2), profile,
        )
        self.assertTrue(any(backend.events.values()))
        with self.assertRaises(ArithmeticError):
            backend.least_squares([])
        self.assertEqual(backend.last_ls_report["status"], "numeric_fault")

    def test_completed_report_is_snapshot_when_backend_is_used_after_solve(self):
        profile = Profile(Format(18, 14), Format(18, 16), Format(27, 19), 64)
        backend = IntegerLSQRKernels(
            np.eye(2), np.array([0.5, -0.25]),
            Policy(2, ls_max_iterations=4), profile,
        )
        backend.least_squares([0, 1])
        snapshot = deepcopy(backend.last_ls_report)
        # A later kernel call must not rewrite the report for the completed LS.
        backend.mv(backend.y)
        self.assertEqual(backend.last_ls_report, snapshot)

    def test_reciprocal_normalization_handles_scalar_fraction_different_from_state(self):
        profile = Profile(Format(24, 20), Format(24, 20), Format(32, 24), 72)
        scalar = Format(28, 12)
        backend = IntegerLSQRKernels(
            np.eye(3), np.ones(3),
            Policy(1, ls_max_iterations=2), profile, scalar_format=scalar,
        )
        vector = np.array([3_000_000, -4_000_000, 0], dtype=object)
        norm = backend._sqrt_energy(
            backend.dot(vector, vector), profile.state.frac
        )
        normalized = backend._vector_div_norm(vector, norm)
        self.assertLess(abs(np.linalg.norm(backend.decode(normalized)) - 1.0), 2e-3)
        self.assertEqual(backend.scalar_format, scalar)
        self.assertEqual(backend.last_ls_report["scalar_format"], "S28F12")

    def test_reciprocal_normalization_preserves_smallest_nonzero_norm(self):
        profile = Profile(Format(24, 20), Format(24, 20), Format(32, 24), 72)
        backend = IntegerLSQRKernels(
            np.eye(1), np.ones(1),
            Policy(1, ls_max_iterations=1), profile,
            scalar_format=Format(28, 12),
        )
        # norm=1 is the smallest nonzero raw scalar. The normalized
        # vector should remain representable instead of being treated as zero.
        normalized = backend._vector_div_norm(
            np.array([1], dtype=object), 1
        )
        # state F24 and scalar F12 imply a raw-state result of 2**12.
        self.assertEqual(normalized.tolist(), [4096])
        self.assertFalse(any(backend.events.values()))


if __name__ == "__main__":
    unittest.main()
