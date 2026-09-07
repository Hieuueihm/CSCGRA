from __future__ import annotations

import json
from pathlib import Path
import unittest

from compiler.v3 import context_isa as isa
from compiler.v3 import m3_control_image


ROOT = Path(__file__).resolve().parents[2]


class M3ControlImageTests(unittest.TestCase):
    def test_generated_artifacts_are_current(self) -> None:
        report = ROOT / "reports" / "v3" / "m3_control_image.json"
        include = (ROOT / "verification" / "v3" / "m3" / "generated" /
                   "m3_control_image.vh")
        self.assertEqual(json.loads(report.read_text(encoding="utf-8")),
                         m3_control_image.payload())
        self.assertEqual(include.read_text(encoding="utf-8"),
                         m3_control_image.sv_include())

    def test_normal_trace_covers_m3_control_semantics(self) -> None:
        image = m3_control_image.payload()
        trace = image["normal_array_trace"]
        self.assertEqual([event["relative_cycle"] for event in trace],
                         list(range(1, 14)))
        self.assertEqual([event["pc"] for event in trace],
                         [0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 5, 6])
        self.assertEqual(sum(event["event"] == "commit" for event in trace), 9)
        self.assertEqual(sum(event["event"] == "stall" for event in trace), 4)
        self.assertEqual(image["normal_phase_trace"], [0, 1, 2, 3, 4])

    def test_every_bundle_matches_current_context_revision(self) -> None:
        self.assertEqual(isa.CONTEXT_FORMAT_REVISION, 9)
        image = m3_control_image.payload()
        for entry in image["array_contexts"]:
            control = isa.unpack_array_control(entry["array_control_word"])
            stream = isa.unpack_stream(entry["stream_word"])
            resource = isa.unpack_resource(entry["resource_word"])
            isa.validate_context_bundle(control, stream, resource)
        for entry in image["phase_instructions"]:
            isa.unpack_phase(entry["word"])


if __name__ == "__main__":
    unittest.main()
