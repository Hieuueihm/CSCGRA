import gzip
import json
import tempfile
from types import SimpleNamespace
import unittest
from pathlib import Path

from models.v3 import hardware
from models.v3 import numerical_candidate, paper
from scripts.golden.generate_v3_candidate_phase_golden import (
    generate, make_case, validate_candidate_trace,
)


class CandidatePhaseGoldenTest(unittest.TestCase):
    def test_d22_generation_is_deterministic_and_bit_exact(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_manifest = generate(Path(first), "smoke", "quality_d22")
            second_manifest = generate(Path(second), "smoke", "quality_d22")
            self.assertEqual(first_manifest, second_manifest)
            self.assertEqual(first_manifest["numeric_candidate"], "quality_d22")
            for entry in first_manifest["files"]:
                first_bytes = (Path(first) / entry["path"]).read_bytes()
                second_bytes = (Path(second) / entry["path"]).read_bytes()
                self.assertEqual(first_bytes, second_bytes)
                with gzip.open(Path(first) / entry["path"], "rt", encoding="utf-8") as stream:
                    payload = json.load(stream)
                self.assertEqual(payload["numeric_candidate"], "quality_d22")
                self.assertEqual(set(payload["traces"]), set(paper.ALGORITHMS))
                if entry["kind"] == "hardware":
                    profile, refinement = numerical_candidate.configuration("quality_d22")
                    self.assertEqual(payload["numeric_profile"]["data_w"], profile.data_w)
                    self.assertEqual(payload["numeric_profile"]["acc_w"], profile.acc_w)
                    self.assertEqual(payload["refinement_policy"]["strict_normal_residual_shift"],
                                     refinement.strict_normal_residual_shift)

    def test_partial_trace_without_controlled_terminal_is_rejected(self):
        case = make_case("m16_n24_k4_seed1", 16, 24, 4, 1)
        trace = SimpleNamespace(
            phases=[
                hardware.Phase(0, 0, "PROXY"),
                hardware.Phase(1, 0, "SELECT"),
            ],
            support=[],
            events=hardware.Events(),
            stop_reason="max_iterations",
        )
        with self.assertRaisesRegex(RuntimeError, "invalid macro-phase grammar"):
            validate_candidate_trace(case, "OMP", trace)

    def test_no_new_atom_terminal_is_explicitly_allowed(self):
        case = make_case("m16_n24_k4_seed1", 16, 24, 4, 1)
        trace = SimpleNamespace(
            phases=[hardware.Phase(0, 0, "PROXY")],
            support=[],
            events=hardware.Events(),
            stop_reason="no_new_atom",
        )
        validate_candidate_trace(case, "OMP", trace)


if __name__ == "__main__":
    unittest.main()
