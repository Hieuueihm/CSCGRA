#!/usr/bin/env python3
"""Enforce the paper -> fixed-point -> phase-golden ownership chain for v3."""

from __future__ import annotations

import ast
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
PAPER = ROOT / "models" / "v3" / "paper.py"
HARDWARE = ROOT / "models" / "v3" / "hardware.py"
PHI_GENERATOR = ROOT / "models" / "v3" / "phi_generator.py"
GENERATOR = ROOT / "scripts" / "golden" / "generate_v3_phase_golden.py"
RECONSTRUCTION_GRAPHS = ROOT / "compiler" / "v3" / "reconstruction_graphs.py"
CONTEXT_ISA = ROOT / "compiler" / "v3" / "context_isa.py"
RUN_CONFIGURATION = ROOT / "compiler" / "v3" / "run_configuration.py"
GOLDEN = ROOT / "verification" / "v3" / "golden"
SOURCES_README = ROOT / "docs" / "v3" / "references" / "README.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"v3 reference contract FAIL: {message}")


def imported_modules(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    result: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            result.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            result.add(node.module)
    return result


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--golden-dir", type=Path, default=GOLDEN)
    args = parser.parse_args()
    golden = args.golden_dir.resolve()
    for path in (PAPER, PHI_GENERATOR, HARDWARE, GENERATOR,
                 RECONSTRUCTION_GRAPHS, CONTEXT_ISA, RUN_CONFIGURATION,
                 SOURCES_README):
        require(path.is_file(), f"missing {path}")

    paper_imports = imported_modules(PAPER)
    require(
        not any(name.startswith(("models.v3.hardware", "rtl", "verification"))
                for name in paper_imports),
        "paper model imports a downstream implementation",
    )

    hardware_imports = imported_modules(HARDWARE)
    require("models.v3.paper" in hardware_imports, "hardware model does not import paper contract")
    require(
        not any(name.startswith(("models.reference", "models.golden", "rtl", "verification"))
                for name in hardware_imports),
        "hardware model imports v2, legacy golden, RTL, or verification source",
    )

    sys.path.insert(0, str(ROOT))
    from models.v3 import hardware, paper

    require(tuple(paper.ALGORITHMS) == tuple(hardware.ALGORITHMS),
            "paper/hardware algorithm order differs")
    require(hardware.RefinementPolicy().lambda_q == 0,
            "default hardware LS is regularized; paper profile requires lambda=0")
    require(hardware.RefinementPolicy().profile == "strict_paper",
            "default hardware golden is not strict paper refinement")
    profile = hardware.NumericProfile()
    require(
        (profile.data_w, profile.data_f, profile.solver_w,
         profile.solver_f, profile.acc_w) == (18, 14, 27, 19, 62),
        "active numeric profile is not D18F14_S27F19_A62",
    )
    sources_text = SOURCES_README.read_text(encoding="utf-8")
    for algorithm, source in paper.PAPER_SOURCES.items():
        require(source in sources_text,
                f"paper source README is missing {algorithm} DOI: {source}")

    expected_sources = {
        "models/v3/paper.py": digest(PAPER),
        "models/v3/phi_generator.py": digest(PHI_GENERATOR),
        "models/v3/hardware.py": digest(HARDWARE),
        "compiler/v3/reconstruction_graphs.py": digest(RECONSTRUCTION_GRAPHS),
        "compiler/v3/context_isa.py": digest(CONTEXT_ISA),
        "compiler/v3/run_configuration.py": digest(RUN_CONFIGURATION),
        "generator": digest(GENERATOR),
    }
    for suite in ("smoke", "scale", "correctness"):
        path = golden / f"manifest.{suite}.json"
        require(path.is_file(), f"missing {path}")
        manifest = json.loads(path.read_text(encoding="utf-8"))
        require(manifest.get("source_sha256") == expected_sources,
                f"{path.name} was not generated from current sources")
        for entry in manifest.get("files", []):
            artifact = golden / entry["path"]
            require(artifact.is_file(), f"missing golden artifact {artifact.name}")
            require(digest(artifact) == entry["sha256"],
                    f"golden artifact hash mismatch: {artifact.name}")

        manifest_names = {entry["path"] for entry in manifest.get("files", [])}
        paper_files = sorted(
            golden / entry["path"]
            for entry in manifest.get("files", [])
            if entry.get("kind") == "paper"
        )
        for paper_path in paper_files:
            hardware_path = paper_path.with_name(paper_path.name.replace(".paper.", ".hardware."))
            require(hardware_path.name in manifest_names,
                    f"manifest is missing hardware pair for {paper_path.name}")
            with gzip.open(paper_path, "rt", encoding="utf-8") as stream:
                paper_payload = json.load(stream)
            with gzip.open(hardware_path, "rt", encoding="utf-8") as stream:
                hardware_payload = json.load(stream)
            case_payload = paper_payload["case"]
            phi_contract = case_payload.get("phi_generator", {})
            require("phi" not in case_payload,
                    f"golden stores full Phi instead of generator contract: {paper_path.name}")
            require(
                phi_contract.get("algorithm") == "threefry2x32_20"
                and phi_contract.get("revision") == 1
                and phi_contract.get("seed") == case_payload.get("seed")
                and phi_contract.get("counter_mapping") == "column_row_pair",
                f"invalid generated-Phi contract: {paper_path.name}",
            )
            for algorithm, paper_trace in paper_payload["traces"].items():
                hardware_trace = hardware_payload["traces"][algorithm]
                paper_support = set(paper_trace["support"])
                hardware_support = set(hardware_trace["support"])
                if suite == "smoke":
                    require(paper_trace["support"] == hardware_trace["support"],
                            f"smoke final support mismatch: {paper_path.name}/{algorithm}")
                else:
                    denominator = max(1, min(len(paper_support), len(hardware_support)))
                    overlap = len(paper_support & hardware_support) / denominator
                    require(overlap >= 0.75,
                            f"{suite} support overlap below 0.75: {paper_path.name}/{algorithm}")
                require(not any(p["name"] == "REFINEMENT_ROLLBACK"
                                for p in hardware_trace["phases"]),
                        f"strict hardware golden rolled back: {paper_path.name}/{algorithm}")

    print("v3 reference contract PASS: paper -> bit-accurate hardware -> phase golden")


if __name__ == "__main__":
    main()
