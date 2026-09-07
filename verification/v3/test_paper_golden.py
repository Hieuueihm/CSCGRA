"""Semantic regression for the paper-authoritative v3 golden."""

from __future__ import annotations

import unittest

import numpy as np

from models.v3 import paper
from scripts.golden.generate_v3_phase_golden import suite
from verification.v3 import independent_float_oracle


def matrix(seed: int = 7, m: int = 16, n: int = 24) -> np.ndarray:
    rng = np.random.default_rng(seed)
    phi = rng.normal(size=(m, n))
    return phi / np.linalg.norm(phi, axis=0)


class PaperGoldenTest(unittest.TestCase):
    def test_correctness_suite_matches_independent_oracle(self) -> None:
        for case in suite("correctness"):
            for name in paper.ALGORITHMS:
                with self.subTest(case=case["name"], name=name):
                    result = paper.run(name, case["phi"], case["y"], case["policy"])
                    oracle = independent_float_oracle.run(
                        name, case["phi"], case["y"], case["policy"])
                    self.assertEqual(tuple(result.support), oracle.support)
                    self.assertEqual(result.stop_reason, oracle.stop_reason)
                    np.testing.assert_allclose(result.x, oracle.x, atol=1e-12, rtol=1e-12)
                    np.testing.assert_allclose(
                        result.residual, oracle.residual, atol=1e-12, rtol=1e-12)
                    np.testing.assert_allclose(
                        result.residual,
                        case["y"] - case["phi"] @ np.asarray(result.x),
                        atol=1e-12,
                        rtol=1e-12,
                    )

    def test_all_algorithms_execute(self) -> None:
        phi = matrix()
        x = np.zeros(phi.shape[1])
        x[[1, 7, 13, 20]] = [1.0, -0.75, 0.5, -0.25]
        y = phi @ x
        policy = paper.Policy(sparsity=4, max_iterations=4, step_size=0.25)
        self.assertEqual(set(paper.ALGORITHMS), set(paper.PAPER_SOURCES))
        for name in paper.ALGORITHMS:
            with self.subTest(name=name):
                result = paper.run(name, phi, y, policy)
                self.assertTrue(result.phases)
                self.assertEqual(result.algorithm, name)
                self.assertEqual(len(result.x), phi.shape[1])
                self.assertEqual(len(result.residual), phi.shape[0])

    def test_cosamp_prunes_without_second_ls(self) -> None:
        phi = matrix(seed=11)
        y = np.random.default_rng(3).normal(size=phi.shape[0])
        result = paper.cosamp(phi, y, paper.Policy(4, 1))
        names = [phase.name for phase in result.phases]
        self.assertEqual(names, ["PROXY", "IDENTIFY", "MERGE", "LS", "PRUNE", "RESIDUAL"])
        estimate = np.asarray(next(p for p in result.phases if p.name == "LS").vectors["estimate"])
        pruned = np.asarray(next(p for p in result.phases if p.name == "PRUNE").vectors["x"])
        support = result.support
        np.testing.assert_array_equal(pruned[support], estimate[support])

    def test_sp_has_explicit_initialization_and_rollback_policy(self) -> None:
        phi = matrix(seed=13)
        y = np.random.default_rng(4).normal(size=phi.shape[0])
        result = paper.sp(phi, y, paper.Policy(4, 3))
        self.assertEqual(
            [phase.name for phase in result.phases[:4]],
            ["INIT_PROXY", "INIT_SELECT", "INIT_LS", "INIT_RESIDUAL"],
        )
        checks = [p for p in result.phases if p.name == "RESIDUAL_CHECK"]
        self.assertTrue(checks)
        for phase in checks:
            if phase.scalars["accepted"]:
                self.assertLess(phase.scalars["new_norm2"], phase.scalars["old_norm2"])

    def test_gomp_does_not_trim_last_group_to_k(self) -> None:
        phi = matrix(seed=19, m=12, n=32)
        y = np.random.default_rng(9).normal(size=phi.shape[0])
        result = paper.gomp(phi, y, paper.Policy(3, 3, group_size=2))
        groups = [phase for phase in result.phases if phase.name == "SELECT_GROUP"]
        self.assertEqual(len(groups), 3)
        self.assertTrue(all(len(phase.candidates) == 2 for phase in groups))
        self.assertEqual(len(result.support), 6)

    def test_gp_allows_reselection(self) -> None:
        rng = np.random.default_rng(0)
        phi = rng.normal(size=(8, 12))
        phi /= np.linalg.norm(phi, axis=0)
        y = rng.normal(size=8)
        result = paper.gp(phi, y, paper.Policy(4, 8))
        selections = [phase for phase in result.phases if phase.name == "SELECT"]
        self.assertTrue(any(bool(phase.scalars["reselected"]) for phase in selections))

    def test_mp_selection_is_column_normalized(self) -> None:
        phi = np.asarray([[10.0, 1.0], [0.0, 1.0]])
        y = np.asarray([1.0, 2.0])
        result = paper.mp(phi, y, paper.Policy(1, 1))
        # Raw atom 0 wins (10 versus 3),
        # normalized scores are 1 and 3/sqrt(2), so paper MP selects atom 1.
        selected = next(p for p in result.phases if p.name == "UPDATE").candidates
        self.assertEqual(selected, [1])


if __name__ == "__main__":
    unittest.main()
