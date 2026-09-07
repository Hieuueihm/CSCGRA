"""A frozen baseline must fail closed on source drift and stale evidence."""
from pathlib import Path
import sys
import tempfile
import unittest

from scripts.maintenance import v3_baseline_provenance as provenance


class BaselineProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "rtl/v3").mkdir(parents=True)
        (self.root / "rtl/v3/files.f").write_text("rtl/v3/top.v\n")
        self.source = self.root / "rtl/v3/top.v"
        self.source.write_text("module top; endmodule\n")
        self.baseline = self.root / "baseline"
        provenance.freeze(self.root, self.baseline)

    def test_roundtrip_and_existing_snapshot_rejected(self):
        self.assertTrue(provenance.verify(self.root, self.baseline)["pass"])
        with self.assertRaises(FileExistsError):
            provenance.freeze(self.root, self.baseline)

    def test_modified_source_rejected(self):
        self.source.write_text("changed")
        result = provenance.verify(self.root, self.baseline)
        self.assertFalse(result["pass"])
        self.assertIn("rtl/v3/top.v", result["changed_files"])

    def test_added_source_rejected(self):
        (self.source.parent / "added.v").write_text("new")
        self.assertFalse(provenance.verify(self.root, self.baseline)["pass"])

    def test_deleted_source_rejected(self):
        self.source.unlink()
        self.assertFalse(provenance.verify(self.root, self.baseline)["pass"])

    def test_archive_corruption_rejected(self):
        with (self.baseline / "sources.zip").open("ab") as stream:
            stream.write(b"corrupt")
        self.assertFalse(provenance.verify(self.root, self.baseline)["pass"])

    def test_failed_command_is_not_pass(self):
        result = provenance.run_bound(self.root, self.baseline, self.root / "run",
                                      [sys.executable, "-c", "raise SystemExit(3)"], [])
        self.assertEqual(result["exit_code"], 3)
        self.assertFalse(result["pass"])
        self.assertTrue(result["after"]["pass"])

    def test_missing_artifact_is_not_pass(self):
        result = provenance.run_bound(self.root, self.baseline, self.root / "run",
                                      [sys.executable, "-c", "pass"], [Path("missing.json")])
        self.assertFalse(result["pass"])

    def test_preexisting_artifact_rejected(self):
        artifact = self.root / "old.json"
        artifact.write_text("old")
        with self.assertRaisesRegex(ValueError, "pre-existing"):
            provenance.run_bound(self.root, self.baseline, self.root / "run",
                                 [sys.executable, "-c", "pass"], [artifact])

    def test_command_source_mutation_is_not_pass(self):
        result = provenance.run_bound(self.root, self.baseline, self.root / "run",
                                      [sys.executable, "-c", "from pathlib import Path; Path('rtl/v3/top.v').write_text('changed')"], [])
        self.assertFalse(result["pass"])
        self.assertFalse(result["after"]["pass"])

    def test_success_binds_generated_artifact(self):
        result = provenance.run_bound(self.root, self.baseline, self.root / "run",
                                      [sys.executable, "-c", "from pathlib import Path; Path('result.json').write_text('{}')"],
                                      [Path("result.json")])
        self.assertTrue(result["pass"])
        self.assertEqual(result["evidence_sha256"]["result.json"],
                         provenance.digest_file(self.root / "result.json"))


if __name__ == "__main__":
    unittest.main()
