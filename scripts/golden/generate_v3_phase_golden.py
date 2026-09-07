#!/usr/bin/env python3
"""Generate reproducible paper and bit-exact phase goldens for v3 RTL."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "verification" / "v3" / "golden"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper, phi_generator
from compiler.v3.reconstruction_graphs import (
    SP_TRACE_INIT,
    SP_TRACE_ITERATION,
    TRACE_PATTERNS,
)
from compiler.v3.context_isa import CONTEXT_FORMAT_REVISION
from compiler.v3.run_configuration import REVISION as RUN_CONFIGURATION_REVISION


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_case(
    name: str, m: int, n: int, k: int, seed: int,
    max_iterations: int | None = None,
) -> dict:
    rng = np.random.default_rng(seed)
    phi = phi_generator.matrix(seed, m, n)
    support = sorted(int(v) for v in rng.choice(n, size=k, replace=False))
    x = np.zeros(n)
    pattern = np.asarray([0.75, -0.625, 0.5, -0.375, 0.25, -0.1875, 0.125, -0.0625])
    x[support] = np.resize(pattern, k)
    y = phi @ x
    spectral_sq = float(np.linalg.norm(phi, ord=2) ** 2)
    step_size = float(0.9 / spectral_sq)
    return {
        "name": name,
        "m": m,
        "n": n,
        "k": k,
        "seed": seed,
        "true_support": support,
        "phi": phi,
        "x_true": x,
        "y": y,
        "policy": paper.Policy(
            sparsity=k,
            max_iterations=k if max_iterations is None else max_iterations,
            residual_atol=2.0**-14,
            step_size=step_size,
            group_size=2,
        ),
    }


CASE_SPECS = {
    "m16_n24_k4_seed1": (16, 24, 4, 1, None),
    "m32_n64_k8_seed7": (32, 64, 8, 7, None),
    "m64_n128_k16_seed11": (64, 128, 16, 11, None),
    "m96_n256_k24_seed17": (96, 256, 24, 17, 16),
    "m128_n512_k32_seed19": (128, 512, 32, 19, 16),
    "m128_n1024_k32_seed23": (128, 1024, 32, 23, 4),
    "m128_n256_k8_seed29": (128, 256, 8, 29, None),
    "m64_n256_k8_seed41": (64, 256, 8, 41, None),
    "m32_n1024_k8_seed31": (32, 1024, 8, 31, None),
    "m128_n256_k32_seed37": (128, 256, 32, 37, 16),
}

SUITE_CASE_NAMES = {
    "smoke": (
        "m16_n24_k4_seed1",
        "m32_n64_k8_seed7",
    ),
    "scale": (
        "m128_n1024_k32_seed23",
    ),
    "correctness": tuple(CASE_SPECS),
}


def case_by_name(name: str) -> dict:
    try:
        m, n, k, seed, max_iterations = CASE_SPECS[name]
    except KeyError as exc:
        raise ValueError(f"unknown case {name}") from exc
    return make_case(name, m, n, k, seed, max_iterations=max_iterations)


def suite(name: str) -> list[dict]:
    try:
        names = SUITE_CASE_NAMES[name]
    except KeyError as exc:
        raise ValueError(f"unknown suite {name}") from exc
    return [case_by_name(case_name) for case_name in names]


def json_bytes(value: object) -> bytes:
    def convert(item: object) -> object:
        if isinstance(item, np.generic):
            return item.item()
        raise TypeError(f"not JSON serializable: {type(item).__name__}")

    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       allow_nan=False, default=convert) + "\n").encode("utf-8")


def compressed_json(value: object) -> bytes:
    return gzip.compress(json_bytes(value), compresslevel=9, mtime=0)


def macro_names(kind: str, trace: object) -> list[str]:
    internal = {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}
    return [
        phase.name for phase in trace.phases
        if kind == "paper"
        or (not phase.name.startswith("REFINEMENT_") and phase.name not in internal)
    ]


def valid_macro_grammar(algorithm: str, names: list[str]) -> bool:
    if algorithm == "SP":
        if tuple(names[:len(SP_TRACE_INIT)]) != SP_TRACE_INIT:
            return False
        remainder = names[len(SP_TRACE_INIT):]
        if remainder and remainder[-1] == "ROLLBACK":
            remainder = remainder[:-1]
        return bool(names) and len(remainder) % len(SP_TRACE_ITERATION) == 0 and all(
            tuple(remainder[offset:offset + len(SP_TRACE_ITERATION)]) == SP_TRACE_ITERATION
            for offset in range(0, len(remainder), len(SP_TRACE_ITERATION))
        )
    pattern = TRACE_PATTERNS[algorithm]
    return bool(names) and len(names) % len(pattern) == 0 and all(
        tuple(names[offset:offset + len(pattern)]) == pattern
        for offset in range(0, len(names), len(pattern))
    )


def validate_trace(case: dict, kind: str, algorithm: str, trace: object) -> None:
    """Reject invalid positive-regression traces before they become golden."""
    phases = trace.phases
    expected_seq = list(range(len(phases)))
    actual_seq = [phase.seq for phase in phases]
    if actual_seq != expected_seq:
        raise RuntimeError(f'{case["name"]}/{kind}/{algorithm}: non-contiguous phase seq')
    if len(trace.support) != len(set(trace.support)):
        raise RuntimeError(f'{case["name"]}/{kind}/{algorithm}: duplicate final support')
    if any(index < 0 or index >= case["n"] for index in trace.support):
        raise RuntimeError(f'{case["name"]}/{kind}/{algorithm}: support index out of range')
    names = macro_names(kind, trace)
    if not valid_macro_grammar(algorithm, names):
        raise RuntimeError(
            f'{case["name"]}/{kind}/{algorithm}: illegal paper macro-phase grammar {names}'
        )
    if kind == "hardware":
        faults = asdict(trace.events)
        active = {name: count for name, count in faults.items() if count != 0}
        if active:
            raise RuntimeError(f'{case["name"]}/{algorithm}: numeric faults {active}')
        if any(phase.name == "REFINEMENT_ROLLBACK" for phase in phases):
            raise RuntimeError(f'{case["name"]}/{algorithm}: unexpected refinement rollback')


def phase_payload(case: dict, kind: str) -> dict:
    phi, y, policy = case["phi"], case["y"], case["policy"]
    traces = {}
    for algorithm in paper.ALGORITHMS:
        trace = (paper.run(algorithm, phi, y, policy) if kind == "paper"
                 else hardware.run(algorithm, phi, y, policy))
        validate_trace(case, kind, algorithm, trace)
        traces[algorithm] = asdict(trace)
    payload = {
        "schema": "cscgra-v3-phase-golden-v3",
        "kind": kind,
        "case": {
            "name": case["name"], "m": case["m"], "n": case["n"],
            "k": case["k"], "seed": case["seed"],
            "true_support": case["true_support"],
            "x_true": case["x_true"].tolist(),
            "y": case["y"].tolist(),
            "phi_generator": {
                "algorithm": "threefry2x32_20",
                "revision": 1,
                "seed": case["seed"],
                "counter_mapping": "column_row_pair",
                "positive_when_bit_is_one": True,
                "amplitude": 0.125,
            },
            "policy": asdict(policy),
        },
        "paper_sources": paper.PAPER_SOURCES,
        "context_format_revision": CONTEXT_FORMAT_REVISION,
        "run_configuration_revision": RUN_CONFIGURATION_REVISION,
        "traces": traces,
    }
    if kind == "hardware":
        payload["numeric_profile"] = asdict(hardware.NumericProfile())
        payload["refinement_policy"] = asdict(hardware.RefinementPolicy())
    return payload


def generate(out_dir: Path, suite_name: str) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for case in suite(suite_name):
        for kind in ("paper", "hardware"):
            name = f'{case["name"]}.{kind}.json.gz'
            path = out_dir / name
            path.write_bytes(compressed_json(phase_payload(case, kind)))
            files.append({"path": name, "sha256": sha256(path), "kind": kind,
                          "case": case["name"]})
    manifest = {
        "schema": "cscgra-v3-phase-manifest-v3",
        "suite": suite_name,
        "authority_chain": [
            "primary papers",
            "models/v3/paper.py",
            "models/v3/phi_generator.py",
            "models/v3/hardware.py",
            "compiler/v3/reconstruction_graphs.py",
            "RTL phase checker",
        ],
        "source_sha256": {
            "models/v3/paper.py": sha256(ROOT / "models" / "v3" / "paper.py"),
            "models/v3/phi_generator.py": sha256(
                ROOT / "models" / "v3" / "phi_generator.py"
            ),
            "models/v3/hardware.py": sha256(ROOT / "models" / "v3" / "hardware.py"),
            "compiler/v3/reconstruction_graphs.py": sha256(
                ROOT / "compiler" / "v3" / "reconstruction_graphs.py"
            ),
            "compiler/v3/context_isa.py": sha256(
                ROOT / "compiler" / "v3" / "context_isa.py"
            ),
            "compiler/v3/run_configuration.py": sha256(
                ROOT / "compiler" / "v3" / "run_configuration.py"
            ),
            "generator": sha256(Path(__file__)),
        },
        "files": files,
    }
    (out_dir / f"manifest.{suite_name}.json").write_bytes(json_bytes(manifest))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=tuple(SUITE_CASE_NAMES), default="smoke")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if args.check:
        with tempfile.TemporaryDirectory() as temp:
            generated = Path(temp)
            manifest = generate(generated, args.suite)
            expected_manifest = out_dir / f"manifest.{args.suite}.json"
            if not expected_manifest.exists():
                raise SystemExit(f"missing {expected_manifest}")
            expected = json.loads(expected_manifest.read_text(encoding="utf-8"))
            if manifest != expected:
                raise SystemExit("manifest mismatch")
            for entry in manifest["files"]:
                if (generated / entry["path"]).read_bytes() != (out_dir / entry["path"]).read_bytes():
                    raise SystemExit(f'phase golden mismatch: {entry["path"]}')
        print(f"v3 {args.suite} phase golden: PASS")
    else:
        manifest = generate(out_dir, args.suite)
        print(f'generated {len(manifest["files"])} files in {out_dir}')


if __name__ == "__main__":
    main()
