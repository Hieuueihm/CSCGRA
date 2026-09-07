#!/usr/bin/env python3
"""Run the v3 functional + architecture cycle simulator and emit reports."""
from __future__ import annotations

import argparse
from dataclasses import asdict, replace
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import architecture_simulator, hardware, paper
from scripts.golden.generate_v3_phase_golden import make_case, suite


PROFILE_NAMES = ("strict_paper", "balanced_variant", "fast_variant")


def run_one(case: dict, algorithm: str, profile: str,
            result_mode: str,
            timing: architecture_simulator.TimingContract) -> architecture_simulator.SimulationResult:
    refinement = hardware.RefinementPolicy(profile=profile)
    trace = hardware.run(algorithm, case["phi"], case["y"], case["policy"],
                         hardware.NumericProfile(), refinement)
    return architecture_simulator.simulate(
        trace, case_name=case["name"], measurement_count=case["m"],
        signal_length=case["n"], sparsity=case["k"], profile=profile,
        result_mode=result_mode, timing=timing)


def markdown(payload: dict) -> str:
    rows = payload["runs"]
    lines = [
        "# v3 complete-architecture cycle simulation", "",
        "Functional decisions come from the bit-accurate hardware model. Cycles",
        f'come from the revision-1 transaction/resource timing contract at {payload["timing_contract"]["clock_hz"] / 1e6:g} MHz',
        "with zero external AXI wait-state. These are pre-RTL architecture estimates,",
        "not Vivado/XSim measured cycles or timing sign-off.", "",
        "| Case | Profile | Algorithm | Total | Compute | Steps | Correlation | Refinement | Certificate | Selection/support | I/O | us @clock |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in rows:
        category = item["category_cycles"]
        io_cycles = item["ingress_cycles"] + item["egress_cycles"]
        lines.append(
            f'| {item["case_name"]} | `{item["profile"]}` | {item["algorithm"]} | '
            f'{item["total_cycles"]:,} | {item["compute_cycles"]:,} | '
            f'{item["phase_invocations"].get("REFINEMENT_STEP", 0):,} | '
            f'{category.get("correlation", 0):,} | {category.get("refinement", 0):,} | '
            f'{category.get("certificate", 0):,} | '
            f'{category.get("selection_support", 0):,} | {io_cycles:,} | '
            f'{item["estimated_microseconds"]:.3f} |')
    lines.extend(["", "## Per-case/profile totals", "",
                  "| Case | Profile | Eight-algorithm cycles |",
                  "| --- | --- | ---: |"])
    grouped: dict[tuple[str, str], int] = {}
    for item in rows:
        key = (item["case_name"], item["profile"])
        grouped[key] = grouped.get(key, 0) + item["total_cycles"]
    for (case_name, profile), cycles in grouped.items():
        lines.append(f"| {case_name} | `{profile}` | {cycles:,} |")
    k32_strict = [item for item in rows
                  if item["dimensions"] == {"M": 128, "N": 1024, "K": 32}
                  and item["profile"] == "strict_paper"]
    if k32_strict:
        lines.extend(["", "## K32 strict bottleneck", "",
                      "| Algorithm | Dominant category | Cycles | Share of total |",
                      "| --- | --- | ---: | ---: |"])
        for item in k32_strict:
            categories = item["category_cycles"]
            candidates = {
                "correlation": categories.get("correlation", 0),
                "refinement+certificate": (categories.get("refinement", 0)
                                             + categories.get("certificate", 0)),
                "selection/support": categories.get("selection_support", 0),
                "other compute": sum(categories.get(name, 0) for name in
                                     ("residual", "matrix_operator", "vector_update")),
            }
            dominant, cycles = max(candidates.items(), key=lambda pair: pair[1])
            lines.append(f'| {item["algorithm"]} | {dominant} | {cycles:,} | '
                         f'{100 * cycles / item["total_cycles"]:.1f}% |')
    lines.extend([
        "", "## Locked assumptions", "",
        "- One shared context stream drives both 4x4 clusters.",
        "- PHI_ACCUMULATE performs sign/zero plus L48 accumulation in one PE cycle.",
        "- Full correlation uses 32 sign/apply lanes and fuses candidate capture.",
        "- Shared vector arithmetic sustains eight S27 multiply results/cycle.",
        "- Active-support Phi cache is filled once per refinement transaction.",
        "- Every refinement step computes solver-domain recurrence gamma; full post-D18 certificate runs on the cheap-gamma trigger, reliable interval, profile boundary, or final strict step.",
        "- Dense result writer builds one 32-bit value/cycle into 128-bit DMA beats; output mode is `"
        + payload["result_mode"] + "`.",
        "- AXI setup is six cycles/transfer and every beat is accepted immediately.",
        "", (("Full transaction timelines and per-resource utilization are in `results.json`."
               if payload["transactions_included"] else
               "Per-resource utilization is in `results.json`; rerun without `--no-transactions` for full timelines.")), "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suites", nargs="*", choices=("smoke", "scale"),
                        default=["smoke", "scale"])
    parser.add_argument("--profiles", nargs="+", choices=PROFILE_NAMES,
                        default=list(PROFILE_NAMES))
    parser.add_argument("--algorithms", nargs="+", choices=tuple(paper.ALGORITHMS),
                        default=list(paper.ALGORITHMS))
    parser.add_argument("--result-mode", choices=("dense", "sparse", "both"),
                        default="both")
    parser.add_argument("--out-dir", type=Path,
                        default=Path("reports/v3/architecture_cycle_simulation"))
    parser.add_argument("--no-transactions", action="store_true",
                        help="omit the detailed timeline from results.json")
    parser.add_argument("--clock-mhz", type=float, default=150.0)
    parser.add_argument("--axi-wait-cycles-per-beat", type=int, default=0)
    parser.add_argument("--custom", nargs=5, type=int,
                        metavar=("M", "N", "K", "OUTER", "SEED"),
                        help="add one generated-Phi custom case")
    args = parser.parse_args()
    if args.clock_mhz <= 0 or args.axi_wait_cycles_per_beat < 0:
        parser.error("clock must be positive and AXI wait cycles must be nonnegative")
    if not args.suites and not args.custom:
        parser.error("select at least one suite or provide --custom")

    cases = [case for suite_name in args.suites for case in suite(suite_name)]
    if args.custom:
        m, n, k, outer, seed = args.custom
        cases.append(make_case(f"custom_m{m}_n{n}_k{k}_outer{outer}_seed{seed}",
                               m, n, k, seed, max_iterations=outer))
    timing = replace(
        architecture_simulator.timing_contract_from_architecture_configuration(),
        clock_hz=int(args.clock_mhz * 1_000_000),
        external_axi_wait_cycles_per_beat=args.axi_wait_cycles_per_beat,
    )
    runs = []
    for case in cases:
        for profile in args.profiles:
            for algorithm in args.algorithms:
                result = run_one(case, algorithm, profile, args.result_mode, timing)
                runs.append(result.payload(include_transactions=not args.no_transactions))
                print(case["name"], profile, algorithm, result.total_cycles)
    payload = {
        "schema": "cscgra-v3-complete-architecture-cycle-simulation-v1",
        "timing_contract": asdict(timing),
        "result_mode": args.result_mode,
        "transactions_included": not args.no_transactions,
        "runs": runs,
    }
    out = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    (out / "summary.md").write_text(markdown(payload), encoding="utf-8")


if __name__ == "__main__":
    main()
