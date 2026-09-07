#!/usr/bin/env python3
"""Compare an RTL-emitted phase trace against an exact v3 hardware golden."""

from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path
from typing import Any


def load(path: Path) -> Any:
    data = path.read_bytes()
    if path.suffix == ".gz":
        data = gzip.decompress(data)
    return json.loads(data.decode("utf-8"))


def first_difference(expected: Any, observed: Any, path: str = "root") -> str | None:
    if type(expected) is not type(observed):
        return f"{path}: type {type(observed).__name__}, expected {type(expected).__name__}"
    if isinstance(expected, dict):
        if set(expected) != set(observed):
            missing = sorted(set(expected) - set(observed))
            extra = sorted(set(observed) - set(expected))
            return f"{path}: keys missing={missing} extra={extra}"
        for key in expected:
            difference = first_difference(expected[key], observed[key], f"{path}.{key}")
            if difference:
                return difference
        return None
    if isinstance(expected, list):
        if len(expected) != len(observed):
            return f"{path}: length {len(observed)}, expected {len(expected)}"
        for index, (left, right) in enumerate(zip(expected, observed)):
            difference = first_difference(left, right, f"{path}[{index}]")
            if difference:
                return difference
        return None
    if expected != observed:
        return f"{path}: {observed!r}, expected {expected!r}"
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--golden", type=Path, required=True)
    parser.add_argument("--observed", type=Path, required=True)
    parser.add_argument("--algorithm", choices=("OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"))
    args = parser.parse_args()
    golden = load(args.golden)
    observed = load(args.observed)
    expected_traces = golden["traces"]
    observed_traces = observed.get("traces", observed)
    algorithms = [args.algorithm] if args.algorithm else list(expected_traces)
    for algorithm in algorithms:
        if algorithm not in observed_traces:
            raise SystemExit(f"phase trace FAIL: missing algorithm {algorithm}")
        difference = first_difference(expected_traces[algorithm], observed_traces[algorithm],
                                      f"traces.{algorithm}")
        if difference:
            raise SystemExit("phase trace FAIL: " + difference)
    print("phase trace PASS: " + ", ".join(algorithms))


if __name__ == "__main__":
    main()

