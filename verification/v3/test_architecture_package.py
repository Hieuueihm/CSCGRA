from __future__ import annotations
import json
from pathlib import Path
import unittest
from compiler.v3 import generate_architecture_package as package
from compiler.v3 import m3_control_image

ROOT = Path(__file__).resolve().parents[2]

class ArchitecturePackageTests(unittest.TestCase):
    def test_generated_rtl_definitions_are_current(self) -> None:
        expected = {
            "architecture_parameters.vh": package.architecture_parameters(),
            "context_isa_defs.vh": package.context_defs(),
            "architecture_guard_defs.vh": package.architecture_guard_defs(),
            "run_configuration_defs.vh": package.run_configuration_defs(),
        }
        for name, content in expected.items():
            path = ROOT / "rtl" / "v3" / "include" / name
            self.assertEqual(path.read_text(encoding="utf-8"), content)

    def test_context_transaction_golden_is_bit_exact(self) -> None:
        path = ROOT / "reports" / "v3" / "context_transaction_golden.json"
        self.assertEqual(json.loads(path.read_text(encoding="utf-8")),
                         package.transaction_golden())
        golden = package.transaction_golden()
        self.assertEqual(len(golden["cycles"]), 10)
        self.assertEqual(
            len(golden["continuation_tail"]),
            len(dict(
                package.context_compiler.restricted_refinement_resource_segments()
            )["restricted_refinement_continuation"]),
        )
        self.assertEqual(package.transaction_golden()["blocked_stages"], [])
        for context in golden["cycles"] + golden["continuation_tail"]:
            resource = package.isa.unpack_resource(context["resource_word"])
            self.assertFalse(resource.wait_for_ready and resource.wait_for_result)
        check_wait = next(context for context in golden["cycles"]
                          if context["stage"] == "post_d18_check_wait")
        self.assertEqual(package.isa.unpack_resource(
            check_wait["resource_word"]).output_select,
            package.isa.ResourceOutput.EVENT)

    def test_generated_context_authority_tracks_current_revision(self) -> None:
        definitions = package.context_defs()
        self.assertIn("RECON_TILE_FIELD_OPERATION_LSB", definitions)
        self.assertIn("RECON_STREAM_FIELD_PHI_COMMAND_LSB", definitions)
        parameters = package.architecture_parameters()
        configuration = package.architecture.load()
        self.assertRegex(
            parameters,
            rf"`define RECON_CONTEXT_FORMAT_REVISION\s+8'd{package.isa.CONTEXT_FORMAT_REVISION}\b",
        )
        self.assertRegex(
            parameters,
            rf"`define RECON_RTL_MINOR_REVISION\s+8'd{configuration['rtl_minor_revision']}\b",
        )
        self.assertRegex(parameters, r"`define RECON_CANDIDATE_DATA_W\s+22\b")
        self.assertRegex(parameters, r"`define RECON_CANDIDATE_DATA_F\s+18\b")
        self.assertRegex(parameters, r"`define RECON_CANDIDATE_SOLVER_W\s+31\b")
        self.assertRegex(parameters, r"`define RECON_CANDIDATE_SOLVER_F\s+23\b")
        self.assertRegex(parameters, r"`define RECON_CANDIDATE_ACC_W\s+70\b")
        self.assertRegex(
            parameters,
            r"`define RECON_CANDIDATE_SCALAR_DIVIDE_LATENCY\s+17\b",
        )
        disassembly = package.disassembly()
        self.assertIn("Undefined tile encoding 16", disassembly)
        self.assertNotIn("encodings 15 and 16", disassembly)

    def test_generated_phi_authority_tracks_m7_contract(self) -> None:
        definitions = package.architecture_parameters()
        self.assertIn("RECON_RTL_MINOR_REVISION", definitions)
        self.assertRegex(
            definitions,
            r"`define RECON_PHI_SIGNS_PER_CYCLE\s+32",
        )
        self.assertIn("RECON_RUN_CONFIGURATION_REVISION                 8'd6", definitions)
        self.assertIn("RECON_CANDIDATE_STRICT_NORMAL_RESIDUAL_SHIFT     5'd16", definitions)
        self.assertIn("RECON_CERT_ABSOLUTE_FLOOR                        16384", definitions)
        self.assertIn("RECON_PHI_REQUEST_QUEUE_DEPTH", definitions)
        self.assertIn("RECON_PHI_NORMALIZER_LATENCY", definitions)

    def test_m3_image_is_part_of_generated_package(self) -> None:
        report = ROOT / "reports" / "v3" / "m3_control_image.json"
        include = (ROOT / "verification" / "v3" / "m3" / "generated" /
                   "m3_control_image.vh")
        self.assertEqual(json.loads(report.read_text(encoding="utf-8")),
                         m3_control_image.payload())
        self.assertEqual(include.read_text(encoding="utf-8"),
                         m3_control_image.sv_include())

if __name__ == "__main__":
    unittest.main()
