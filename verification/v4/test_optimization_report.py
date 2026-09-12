import importlib.util
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "v4" / "report_optimization.py"
SPEC = importlib.util.spec_from_file_location("report_optimization", SCRIPT)
REPORT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = REPORT
SPEC.loader.exec_module(REPORT)


def case(name: str, outer: int = 8) -> dict:
    return {
        "algorithm": name,
        "requested_outer_iterations": 8,
        "outer_iterations": outer,
        "raw_phi_sha256": "phi", "raw_y_sha256": "y",
        "job_cycles": 100, "accepted_support_size": 8,
        "maximum_ls_support": 8, "solver_invocations": 1,
        "total_committed_inner_iterations": 0,
        "status": "max_iterations",
        "quality": {"fixed": {"snr_db": 25.0}},
        "policy": {"max_iterations": 8},
    }


def summary(sp_outer: int = 8) -> dict:
    cases = [case(name, sp_outer if name == "SP" else 8) for name in REPORT.ALGORITHMS]
    return {
        "status": "PASS", "failures": 0, "errors": 0,
        "changed_sources": [], "untracked_imports": [],
        "source_sha256": {"rtl/v4/example.sv": "hash"},
        "config": {"rows": 64, "columns": 256, "sparsity": 8,
                   "expected_phi_sha256": "phi", "expected_y_sha256": "y"},
        "cases": cases,
    }


class ReportValidationTest(unittest.TestCase):
    def write_summary(self, root: Path, data: dict) -> Path:
        report = root / "report"
        report.mkdir()
        (report / "summary.json").write_text(json.dumps(data), encoding="utf-8")
        return report

    def test_accepts_exact_eight_and_renders_required_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.write_summary(Path(directory), summary())
            geometry = REPORT.load_geometry(report)
            rendered = REPORT.render([geometry], [])
        self.assertIn("Physical FACTOR_INIT", rendered)
        self.assertIn("Logical LS requests", rendered)
        self.assertIn("Actual outer", rendered)
        self.assertIn("M=64, N=256, K=8", rendered)

    def test_rejects_natural_stop_even_when_budget_is_eight(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.write_summary(Path(directory), summary(sp_outer=1))
            with self.assertRaisesRegex(REPORT.EvidenceError, "actual_outer=8"):
                REPORT.load_geometry(report)

    def test_rejects_missing_import_audit_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = summary()
            del evidence["untracked_imports"]
            report = self.write_summary(Path(directory), evidence)
            with self.assertRaisesRegex(REPORT.EvidenceError, "untracked_imports proof is absent"):
                REPORT.load_geometry(report)

    def quality_case(self) -> dict:
        return {
            "algorithm": "FISTA", "rows": 64, "columns": 256,
            "returncode": 0, "stdout": "run PASS\n", "status": "max_iterations",
            "job_cycles": 123, "outer_iterations": 8,
            "quality": {
                "threshold_pass": True, "snr_loss_db": 0.1, "nmse_ratio": 1.01,
                "fixed": {"snr_db": 30.0, "nmse": 0.001},
                "floating": {"snr_db": 30.1, "nmse": 0.0009},
            },
            "fixed_numeric_events": {
                "saturation": 0, "accumulator_overflow": 0, "divide_by_zero": 0,
            },
        }

    def write_quality(self, root: Path, summary: dict, *, readme: str | None = None) -> Path:
        report = root / "quality"
        report.mkdir()
        snapshot = report / "source_snapshot" / "rtl" / "v4"
        snapshot.mkdir(parents=True)
        source = snapshot / "example.sv"
        source.write_text("module example; endmodule\n", encoding="utf-8")
        summary["source_sha256"] = {"rtl/v4/example.sv": hashlib.sha256(source.read_bytes()).hexdigest()}
        (report / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
        if readme is not None:
            (report / "README.md").write_text(readme, encoding="utf-8")
        return report

    def quality_summary(self, case: dict | None = None) -> dict:
        return {
            "status": "PASS", "failures": 0, "errors": 0,
            "changed_sources": [], "untracked_imports": [],
            "cases": [self.quality_case() if case is None else case],
        }

    def test_rejects_false_quality_threshold_and_missing_floating_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            bad = self.quality_case()
            bad["quality"]["threshold_pass"] = False
            del bad["quality"]["floating"]
            report = self.write_quality(Path(directory), self.quality_summary(bad))
            with self.assertRaisesRegex(REPORT.EvidenceError, "quality threshold did not pass"):
                REPORT.load_quality(report)

    def test_rejects_quality_numeric_event_and_unclean_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            bad = self.quality_case()
            bad["fixed_numeric_events"]["saturation"] = 1
            source_bad = self.quality_summary(bad)
            source_bad["changed_sources"] = ["rtl/v4/example.sv"]
            report = self.write_quality(Path(directory), source_bad)
            with self.assertRaisesRegex(REPORT.EvidenceError, "changed_sources is not explicitly clean"):
                REPORT.load_quality(report)
            source_bad["changed_sources"] = []
            (report / "summary.json").write_text(json.dumps(source_bad), encoding="utf-8")
            with self.assertRaisesRegex(REPORT.EvidenceError, "nonzero saturation"):
                REPORT.load_quality(report)

    def test_rejects_recorded_pass_when_metrics_contradict_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            bad = self.quality_case()
            bad["quality"]["threshold_pass"] = True
            bad["quality"]["fixed"]["snr_db"] = 19.9
            report = self.write_quality(Path(directory), self.quality_summary(bad))
            with self.assertRaisesRegex(REPORT.EvidenceError, "SNR must both be >=20 dB"):
                REPORT.load_quality(report)

    def test_accepts_documented_component_parent_only_with_valid_case(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = self.quality_summary()
            summary.update({"status": "FAIL", "errors": 1})
            readme = "HTP failed before simulation. The single entry in `summary.json.cases` is valid component evidence."
            report = self.write_quality(Path(directory), summary, readme=readme)
            rows = REPORT.load_quality(report)
        self.assertEqual(rows[0]["parent_status"], "component PASS; parent FAIL retained")


if __name__ == "__main__":
    unittest.main()
