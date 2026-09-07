#!/usr/bin/env python3
"""Generate candidate phase goldens through the V3 canonical model chain."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3.context_isa import CONTEXT_FORMAT_REVISION
from compiler.v3.run_configuration import REVISION as RUN_CONFIGURATION_REVISION
from models.v3 import hardware, numerical_candidate, paper, phi_generator
from scripts.golden.generate_v3_phase_golden import (
    CASE_SPECS, SP_TRACE_INIT, SP_TRACE_ITERATION, TRACE_PATTERNS,
    compressed_json, json_bytes, macro_names, make_case, sha256,
    validate_trace,
)


def suite(name: str) -> list[dict]:
    names = {
        "smoke": ("m16_n24_k4_seed1", "m32_n64_k8_seed7"),
        "scale": ("m128_n1024_k32_seed23",),
        "correctness": tuple(CASE_SPECS),
    }[name]
    return [make_case(name, *CASE_SPECS[name][:4],
                      max_iterations=CASE_SPECS[name][4]) for name in names]


def _pattern_prefix_valid(algorithm: str, names: list[str]) -> bool:
    if algorithm == "SP":
        if tuple(names[:len(SP_TRACE_INIT)]) != SP_TRACE_INIT:
            return False
        names = names[len(SP_TRACE_INIT):]
        pattern = SP_TRACE_ITERATION
    else:
        pattern = TRACE_PATTERNS[algorithm]
    full_length = (len(names) // len(pattern)) * len(pattern)
    for offset in range(0, full_length, len(pattern)):
        if tuple(names[offset:offset + len(pattern)]) != pattern:
            return False
    remainder = names[full_length:]
    return tuple(remainder) == pattern[:len(remainder)]


def _pattern_full_valid(algorithm: str, names: list[str]) -> bool:
    if algorithm == "SP":
        if tuple(names[:len(SP_TRACE_INIT)]) != SP_TRACE_INIT:
            return False
        remainder = names[len(SP_TRACE_INIT):]
        if remainder and remainder[-1] == "ROLLBACK":
            remainder = remainder[:-1]
        return len(remainder) % len(SP_TRACE_ITERATION) == 0 and all(
            tuple(remainder[offset:offset + len(SP_TRACE_ITERATION)]) == SP_TRACE_ITERATION
            for offset in range(0, len(remainder), len(SP_TRACE_ITERATION))
        )
    pattern = TRACE_PATTERNS[algorithm]
    return bool(names) and len(names) % len(pattern) == 0 and all(
        tuple(names[offset:offset + len(pattern)]) == pattern
        for offset in range(0, len(names), len(pattern))
    )


def _no_new_atom_terminal_valid(algorithm: str, names: list[str]) -> bool:
    if algorithm not in {"OMP", "GOMP"} or not names:
        return False
    pattern = TRACE_PATTERNS[algorithm]
    complete_length = ((len(names) - 1) // len(pattern)) * len(pattern)
    return (
        tuple(names[:complete_length]) == pattern * (complete_length // len(pattern))
        and tuple(names[complete_length:]) == ("PROXY",)
    )


def validate_candidate_trace(case: dict, algorithm: str, trace: object) -> None:
    """Validate full traces plus controlled solver/no-new-atom terminals."""
    phases = trace.phases
    expected_seq = list(range(len(phases)))
    if [phase.seq for phase in phases] != expected_seq:
        raise RuntimeError(f'{case["name"]}/candidate/{algorithm}: non-contiguous phase seq')
    if len(trace.support) != len(set(trace.support)):
        raise RuntimeError(f'{case["name"]}/candidate/{algorithm}: duplicate final support')
    if any(index < 0 or index >= case["n"] for index in trace.support):
        raise RuntimeError(f'{case["name"]}/candidate/{algorithm}: support index out of range')
    faults = asdict(trace.events)
    active = {name: count for name, count in faults.items() if count != 0}
    if active:
        raise RuntimeError(f'{case["name"]}/candidate/{algorithm}: numeric faults {active}')
    names = macro_names("hardware", trace)
    rollback = [phase for phase in phases if phase.name == "REFINEMENT_ROLLBACK"]
    if rollback:
        if len(rollback) != 1 or not trace.stop_reason.startswith("solver_"):
            raise RuntimeError(f'{case["name"]}/candidate/{algorithm}: uncontrolled rollback')
        if not _pattern_prefix_valid(algorithm, names):
            raise RuntimeError(
                f'{case["name"]}/candidate/{algorithm}: invalid solver-limit prefix {names}'
            )
    elif trace.stop_reason == "no_new_atom":
        if not _no_new_atom_terminal_valid(algorithm, names):
            raise RuntimeError(
                f'{case["name"]}/candidate/{algorithm}: invalid no-new-atom terminal {names}'
            )
    elif not _pattern_full_valid(algorithm, names):
        raise RuntimeError(
            f'{case["name"]}/candidate/{algorithm}: invalid macro-phase grammar {names}'
        )


def phase_payload(case: dict, kind: str, profile_name: str) -> dict:
    phi, y, policy = case["phi"], case["y"], case["policy"]
    numeric_profile, refinement_policy = numerical_candidate.configuration(profile_name)
    traces = {}
    for algorithm in paper.ALGORITHMS:
        trace = (paper.run(algorithm, phi, y, policy) if kind == "paper" else
                 hardware.run(algorithm, phi, y, policy,
                              numeric_profile, refinement_policy))
        if kind == "hardware":
            validate_candidate_trace(case, algorithm, trace)
        else:
            validate_trace(case, kind, algorithm, trace)
        traces[algorithm] = asdict(trace)
    payload = {
        "schema": "cscgra-v3-candidate-phase-golden-v1",
        "kind": kind,
        "numeric_candidate": profile_name,
        "case": {
            "name": case["name"], "m": case["m"], "n": case["n"],
            "k": case["k"], "seed": case["seed"],
            "true_support": case["true_support"],
            "x_true": case["x_true"].tolist(), "y": case["y"].tolist(),
            "phi_generator": {
                "algorithm": "threefry2x32_20", "revision": 1,
                "seed": case["seed"], "counter_mapping": "column_row_pair",
                "positive_when_bit_is_one": True, "amplitude": 0.125,
            },
            "policy": asdict(policy),
        },
        "paper_sources": paper.PAPER_SOURCES,
        "context_format_revision": CONTEXT_FORMAT_REVISION,
        "run_configuration_revision": RUN_CONFIGURATION_REVISION,
        "traces": traces,
    }
    if kind == "hardware":
        payload["numeric_profile"] = asdict(numeric_profile)
        payload["refinement_policy"] = asdict(refinement_policy)
    return payload


def generate(out_dir: Path, suite_name: str, profile_name: str) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for case in suite(suite_name):
        for kind in ("paper", "hardware"):
            name = f'{case["name"]}.{kind}.json.gz'
            path = out_dir / name
            path.write_bytes(compressed_json(
                phase_payload(case, kind, profile_name)))
            files.append({"path": name, "sha256": sha256(path),
                          "kind": kind, "case": case["name"]})
    manifest = {
        "schema": "cscgra-v3-candidate-phase-manifest-v1",
        "suite": suite_name,
        "numeric_candidate": profile_name,
        "authority_chain": [
            "primary papers", "models/v3/paper.py",
            "models/v3/phi_generator.py", "models/v3/hardware.py",
            "models/v3/numerical_candidate.py",
            "compiler/v3/reconstruction_graphs.py", "RTL phase checker",
        ],
        "source_sha256": {
            "models/v3/paper.py": sha256(ROOT / "models" / "v3" / "paper.py"),
            "models/v3/phi_generator.py": sha256(
                ROOT / "models" / "v3" / "phi_generator.py"),
            "models/v3/hardware.py": sha256(ROOT / "models" / "v3" / "hardware.py"),
            "models/v3/numerical_candidate.py": sha256(
                ROOT / "models" / "v3" / "numerical_candidate.py"),
            "compiler/v3/reconstruction_graphs.py": sha256(
                ROOT / "compiler" / "v3" / "reconstruction_graphs.py"),
            "compiler/v3/context_isa.py": sha256(
                ROOT / "compiler" / "v3" / "context_isa.py"),
            "compiler/v3/run_configuration.py": sha256(
                ROOT / "compiler" / "v3" / "run_configuration.py"),
            "generator": sha256(Path(__file__)),
        },
        "files": files,
    }
    (out_dir / f"manifest.{suite_name}.json").write_bytes(json_bytes(manifest))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("smoke", "scale", "correctness"),
                        default="smoke")
    parser.add_argument("--profile", choices=numerical_candidate.NAMES,
                        default="quality_d22")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if args.check:
        with tempfile.TemporaryDirectory() as temp:
            generated = Path(temp)
            manifest = generate(generated, args.suite, args.profile)
            expected_manifest = out_dir / f"manifest.{args.suite}.json"
            if not expected_manifest.exists():
                raise SystemExit(f"missing {expected_manifest}")
            expected = json.loads(expected_manifest.read_text(encoding="utf-8"))
            if manifest != expected:
                raise SystemExit("candidate manifest mismatch")
            for entry in manifest["files"]:
                if ((generated / entry["path"]).read_bytes() !=
                        (out_dir / entry["path"]).read_bytes()):
                    raise SystemExit(f'candidate golden mismatch: {entry["path"]}')
        print(f"v3 {args.profile} candidate {args.suite} golden: PASS")
    else:
        manifest = generate(out_dir, args.suite, args.profile)
        print(f'generated {len(manifest["files"])} files in {out_dir}')


if __name__ == "__main__":
    main()
