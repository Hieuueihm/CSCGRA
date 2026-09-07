"""Bit-exact and semantic-boundary tests for the v3 hardware model."""

from __future__ import annotations

from dataclasses import asdict
import unittest

import numpy as np

from models.v3 import hardware, paper
from scripts.golden.generate_v3_phase_golden import suite


class HardwareGoldenTest(unittest.TestCase):
    @staticmethod
    def case() -> tuple[np.ndarray, np.ndarray, paper.Policy]:
        rng = np.random.default_rng(1)
        phi = rng.choice(np.asarray([-0.125, 0.125]), size=(16, 24))
        x = np.zeros(24)
        x[[1, 5, 9, 13]] = [0.5, -0.5, 0.25, -0.25]
        y = phi @ x
        return phi, y, paper.Policy(4, 4, residual_atol=2.0**-14, step_size=0.25)

    def test_all_algorithms_are_deterministic_and_in_range(self) -> None:
        phi, y, policy = self.case()
        for name in paper.ALGORITHMS:
            with self.subTest(name=name):
                first = hardware.run(name, phi, y, policy)
                second = hardware.run(name, phi, y, policy)
                self.assertEqual(asdict(first), asdict(second))
                self.assertEqual(first.events.data_saturation, 0)
                self.assertEqual(first.events.solver_saturation, 0)
                self.assertEqual(first.events.acc_overflow, 0)
                self.assertEqual(first.events.divide_by_zero, 0)
                self.assertEqual(first.events.refinement_breakdown, 0)
                self.assertTrue(first.phases)

    def test_paper_and_hardware_select_same_final_support_on_exact_case(self) -> None:
        phi, y, policy = self.case()
        for name in paper.ALGORITHMS:
            with self.subTest(name=name):
                mathematical = paper.run(name, phi, y, policy)
                fixed = hardware.run(name, phi, y, policy)
                common = len(set(mathematical.support) & set(fixed.support))
                minimum = min(policy.sparsity, len(mathematical.support), len(fixed.support))
                self.assertGreaterEqual(common, minimum)

    def test_hardware_preserves_paper_macro_phase_structure(self) -> None:
        phi, y, policy = self.case()
        internal = {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}
        for name in paper.ALGORITHMS:
            with self.subTest(name=name):
                mathematical = paper.run(name, phi, y, policy)
                fixed = hardware.run(name, phi, y, policy)
                expected = [
                    (phase.iteration, phase.name)
                    for phase in mathematical.phases
                ]
                observed = [
                    (phase.iteration, phase.name)
                    for phase in fixed.phases
                    if not phase.name.startswith("REFINEMENT_") and phase.name not in internal
                ]
                common = min(len(expected), len(observed))
                self.assertEqual(expected[:common], observed[:common])
                self.assertTrue(expected and observed)

    def test_cosamp_has_one_ls_transaction_before_prune(self) -> None:
        phi, y, policy = self.case()
        result = hardware.cosamp(phi, y, policy, hardware.NumericProfile(),
                                 hardware.RefinementPolicy())
        outer = [p.name for p in result.phases
                 if not p.name.startswith("REFINEMENT_")]
        first = outer[:6]
        self.assertEqual(first, ["PROXY", "IDENTIFY", "MERGE", "LS", "PRUNE", "RESIDUAL"])

    def test_default_solver_is_unregularized(self) -> None:
        self.assertEqual(hardware.RefinementPolicy().lambda_q, 0)
        self.assertEqual(hardware.RefinementPolicy().profile, "strict_paper")

    def test_failed_solver_never_commits_outer_state(self) -> None:
        phi, y, policy = self.case()
        result = hardware.omp(
            phi, y, policy, hardware.NumericProfile(),
            hardware.RefinementPolicy(max_iterations=0),
        )
        names = [phase.name for phase in result.phases]
        self.assertIn("REFINEMENT_ROLLBACK", names)
        self.assertNotIn("REFINEMENT_COMMIT", names)
        self.assertEqual(result.support, [])
        self.assertTrue(all(value == 0 for value in result.x))

    def test_gomp_exposes_two_k_capacity(self) -> None:
        phi, y, policy = self.case()
        policy = paper.Policy(policy.sparsity, policy.max_iterations,
                              residual_atol=0.0, step_size=policy.step_size,
                              group_size=policy.group_size)
        result = hardware.gomp(phi, y, policy, hardware.NumericProfile(),
                               hardware.RefinementPolicy())
        self.assertEqual(len(result.support), 2 * policy.sparsity)

    def test_three_profiles_are_explicit_and_deterministic(self) -> None:
        phi, y, policy = self.case()
        for profile in ("strict_paper", "balanced_variant", "fast_variant"):
            selected = hardware.RefinementPolicy(profile=profile)
            first = hardware.omp(phi, y, policy, hardware.NumericProfile(), selected)
            second = hardware.omp(phi, y, policy, hardware.NumericProfile(), selected)
            self.assertEqual(asdict(first), asdict(second))
            begin = next(p for p in first.phases if p.name == "REFINEMENT_BEGIN")
            self.assertEqual(begin.scalars["profile"], profile)

    def test_fast_profile_budgets_are_quality_qualified(self) -> None:
        expected = {"OMP": 3, "CoSaMP": 6, "HTP": 10, "SP": 7, "GOMP": 3}
        for algorithm, budget in expected.items():
            with self.subTest(algorithm=algorithm):
                self.assertEqual(
                    hardware._profile_budget("fast_variant", algorithm, 32),
                    budget,
                )

    def test_phi_data_accumulate_rounds_solver_input_before_accumulation(self) -> None:
        arithmetic = hardware.Arithmetic(hardware.NumericProfile(), hardware.Events())
        for coefficient, expected_data in (
                (16, 1), (-16, -1), (15, 0), (-15, 0),
                (442272, 13821), (-278560, -8705)):
            with self.subTest(coefficient=coefficient):
                result, accumulator, write, _, saturated = arithmetic.pe_execute(
                    "PHI_DATA_ACCUMULATE", coefficient, 0, accumulator=7,
                    phi_nonzero=True, phi_sign=True)
                self.assertEqual(result, 0)
                self.assertTrue(write)
                self.assertFalse(saturated)
                self.assertEqual(accumulator, 7 + (expected_data << 5))

    def test_strict_commit_requires_passed_post_d18_certificate(self) -> None:
        case = suite("smoke")[1]
        for algorithm in paper.ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = hardware.run(
                    algorithm, case["phi"], case["y"], case["policy"],
                    hardware.NumericProfile(),
                    hardware.RefinementPolicy(profile="strict_paper"),
                )
                for index, phase in enumerate(result.phases):
                    if phase.name != "REFINEMENT_COMMIT":
                        continue
                    certificate = result.phases[index - 1]
                    self.assertEqual(certificate.name, "REFINEMENT_CERTIFICATE")
                    self.assertTrue(certificate.scalars["post_d18"])
                    self.assertTrue(certificate.scalars["passed"])

    def test_full_certificate_is_periodic_not_per_step(self) -> None:
        case = suite("smoke")[1]
        interval = 8
        result = hardware.cosamp(
            case["phi"], case["y"], case["policy"], hardware.NumericProfile(),
            hardware.RefinementPolicy(
                profile="strict_paper", reliable_recompute_interval=interval),
        )
        steps = [p for p in result.phases if p.name == "REFINEMENT_STEP"]
        certificates = [
            p for p in result.phases if p.name == "REFINEMENT_CERTIFICATE"
        ]
        self.assertLess(len(certificates), len(steps))
        self.assertTrue(all(p.scalars["solver_transpose_computed"] for p in steps))

        since_certificate = 0
        in_refinement = False
        for phase in result.phases:
            if phase.name == "REFINEMENT_BEGIN":
                in_refinement = True
                since_certificate = 0
            elif phase.name == "REFINEMENT_STEP" and in_refinement:
                since_certificate += 1
                self.assertLessEqual(since_certificate, interval)
            elif phase.name == "REFINEMENT_CERTIFICATE" and in_refinement:
                since_certificate = 0
            elif phase.name in {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}:
                in_refinement = False


if __name__ == "__main__":
    unittest.main()
