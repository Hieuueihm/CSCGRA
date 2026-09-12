"""Focused unit tests for the V4 SoC AXI fixture sidecar."""

import json
import tempfile
import unittest
from pathlib import Path

from verification.v4.soc_axi_fixtures import ACTIVE_ALGORITHMS
from verification.v4.soc_axi_fixtures import build_case, render_fixture, write_fixture


class SocAxiFixtureTests(unittest.TestCase):
    def test_all_active_algorithms_build_json_serializable_cases(self):
        for algorithm in ACTIVE_ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                case = build_case(algorithm)
                self.assertEqual(case["schema"], "soc_axi_fixture_v1")
                self.assertEqual(case["case"]["rows"], 16)
                self.assertEqual(case["case"]["columns"], 32)
                self.assertEqual(case["case"]["iterations_requested"], 8)
                self.assertEqual(case["phi"]["scale_raw"], 16384)
                self.assertTrue(case["measurement"]["values_state"][0])
                self.assertEqual(len(case["measurement"]["truth_support"]), 2)
                self.assertTrue(case["package"]["program"])
                self.assertEqual(
                    case["host"]["load_begin"]["program_count"],
                    len(case["package"]["program"]),
                )
                self.assertEqual(
                    case["package"]["load_records"], case["load_records"]
                )
                self.assertEqual(case["load_records"][-1]["last"], 1)
                self.assertEqual(case["expected"]["exponent"], 0)
                json.dumps(case, allow_nan=False)

    def test_fixture_contains_direct_load_records_and_physical_block_metadata(self):
        case = build_case("MP")
        text = render_fixture(case)
        lines = text.splitlines()
        self.assertEqual(lines[0], "SOC_AXI_FIXTURE_V1")
        self.assertIn("LOAD kind=0 index=0", text)
        self.assertIn("LOAD_BEGIN revision=2", text)
        self.assertIn("PHI_BEGIN seed=", text)
        self.assertIn("START rows=16 columns=32", text)
        self.assertIn("PROG pc=0", text)
        self.assertIn("BLOCK vector=", text)
        self.assertIn("LANE vector=", text)
        self.assertIn("EXPECT status=", text)
        self.assertEqual(lines[-1], "END")
        block = build_case("MP", rows=32)["preload"]["writes"][0]
        self.assertEqual(len(f"{block['packed']:0216x}"), 216)
        self.assertEqual(block["lanes"][0]["bank"], 0)
        self.assertEqual(block["lanes"][0]["port"], 0)
        self.assertEqual(block["lanes"][0]["word"], block["block"])
        self.assertEqual(block["lanes"][16]["bank"], 0)
        self.assertEqual(block["lanes"][16]["port"], 1)
        self.assertEqual(block["lanes"][16]["word"], 512 + block["block"])

    def test_write_fixture_is_deterministic_and_supports_n_alias(self):
        first = build_case("CoSaMP", n=32)
        second = build_case("CoSaMP", columns=32)
        self.assertEqual(first, second)
        with tempfile.TemporaryDirectory() as directory:
            path = write_fixture(first, Path(directory) / "cosamp.fixture")
            self.assertEqual(path.read_text(encoding="ascii"), render_fixture(second))

    def test_admm_is_explicitly_rejected(self):
        with self.assertRaisesRegex(ValueError, "ADMM"):
            build_case("ADMM")


if __name__ == "__main__":
    unittest.main()
