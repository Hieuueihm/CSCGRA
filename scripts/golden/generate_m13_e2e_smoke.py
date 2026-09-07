"""Generate the M13 end-to-end smoke golden package.

Produces `verification/v3/m13/generated/e2e_smoke_golden.vh` for the M13
testbench: three revision-4 run configurations, the D18-packed DDR image of
the smoke measurement vector, and expected terminal results for all eight
algorithms under strict, balanced and fast refinement profiles.  The strict
results are checked against the immutable hardware golden before emission.

Authorities used (no hand-encoded contracts):
- run-configuration words: `compiler.v3.run_configuration.pack`;
- quantization / D18->S27 conversion: `models.v3.hardware.Arithmetic`;
- program image metadata (ABI ids, phase lengths, scalar preloads):
  `reports/v3/m11_program_images.json`;
- stop codes: parsed from `rtl/v3/include/reconstruction_control_defs.vh`.
"""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib
import re
import sys
from dataclasses import replace

import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from compiler.v3 import run_configuration as rc  # noqa: E402
from compiler.v3 import context_isa as isa  # noqa: E402
from models.v3.hardware import (Arithmetic, Events, NumericProfile,  # noqa: E402
                                RefinementPolicy, run)
from scripts.golden.generate_v3_phase_golden import case_by_name  # noqa: E402

DEFAULT_CASE_NAME = "m16_n24_k4_seed1"
IMAGES = REPO / "reports/v3/m11_program_images.json"
CONTEXT_LIBRARY = REPO / "reports/v3/scheduled_context_library.json"
DEFS = REPO / "rtl/v3/include/reconstruction_control_defs.vh"
DEFAULT_OUT_VH = REPO / "verification/v3/m13/generated/e2e_smoke_golden.vh"
DEFAULT_OUT_JSON = REPO / "reports/v3/m13_e2e_smoke/golden_summary.json"

CFG_ADDR = 0x1000
MEAS_ADDR = 0x2000
DENSE_ADDR = 0x3000
SPARSE_ADDR = 0x4000
USER_TAG = 0xE2E00001
SUPPORT_SLOTS = 32

ABI_ORDER = ["omp", "cosamp", "iht", "htp", "sp", "gp", "gomp", "mp"]
TRACE_KEY = {"omp": "OMP", "cosamp": "CoSaMP", "iht": "IHT", "htp": "HTP",
             "sp": "SP", "gp": "GP", "gomp": "GOMP", "mp": "MP"}
PROFILE_ORDER = [
    ("strict_paper", rc.RefinementProfile.STRICT_PAPER, 14),
    ("balanced_variant", rc.RefinementProfile.BALANCED_VARIANT, 8),
    ("fast_variant", rc.RefinementProfile.FAST_VARIANT, 14),
]
STOP_NAME = {"residual_tolerance": "RECON_STOP_RESIDUAL_LIMIT",
             "max_iterations": "RECON_STOP_ITERATION_LIMIT",
             "paper_iteration_limit": "RECON_STOP_ITERATION_LIMIT",
             "support_stable": "RECON_STOP_SUPPORT_STABLE",
             "non_decrease": "RECON_STOP_NON_DECREASE",
             "residual_non_decrease": "RECON_STOP_NON_DECREASE"}


def stop_codes() -> dict[str, int]:
    text = DEFS.read_text(encoding="utf-8")
    codes = {}
    for name, value in re.findall(
            r"`define\s+(RECON_STOP_\w+)\s+4'h([0-9a-fA-F])", text):
        codes[name] = int(value, 16)
    if not codes:
        raise SystemExit("no RECON_STOP_ codes parsed from defs header")
    return codes


def to_u32(value: int) -> int:
    return value & 0xFFFFFFFF


def d18_lane(value: int) -> int:
    if not -(1 << 17) <= value < (1 << 17):
        raise SystemExit(f"value {value} exceeds D18")
    return to_u32(value)


def s27_lane(value: int) -> int:
    if not -(1 << 26) <= value < (1 << 26):
        raise SystemExit(f"value {value} exceeds S27")
    return to_u32(value)


def beats_from_lanes(lanes: list[int]) -> list[int]:
    while len(lanes) % 4:
        lanes.append(0)
    beats = []
    for base in range(0, len(lanes), 4):
        beat = 0
        for lane in range(4):
            beat |= lanes[base + lane] << (32 * lane)
        beats.append(beat)
    return beats


def vh_wide(name: str, width_per_item: int, items: list[int]) -> str:
    total = width_per_item * len(items)
    body = ", ".join(
        f"{width_per_item}'h{item:0{(width_per_item + 3) // 4}x}"
        for item in reversed(items))
    return f"localparam [{total - 1}:0] {name} = {{{body}}};"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case-name", default=DEFAULT_CASE_NAME)
    parser.add_argument("--golden", type=pathlib.Path)
    parser.add_argument("--out-vh", type=pathlib.Path, default=DEFAULT_OUT_VH)
    parser.add_argument("--out-json", type=pathlib.Path, default=DEFAULT_OUT_JSON)
    parser.add_argument(
        "--fixed-outer-iterations", type=int, default=0,
        help=("benchmark mode: disable residual stopping and force all "
              "algorithms to the requested outer-iteration limit"),
    )
    args = parser.parse_args()
    if args.fixed_outer_iterations < 0:
        raise SystemExit("--fixed-outer-iterations must be non-negative")
    golden_path = args.golden or (
        REPO / "verification" / "v3" / "golden" /
        f"{args.case_name}.hardware.json.gz")
    if not golden_path.is_absolute():
        golden_path = REPO / golden_path
    out_vh = args.out_vh if args.out_vh.is_absolute() else REPO / args.out_vh
    out_json = args.out_json if args.out_json.is_absolute() else REPO / args.out_json

    golden = json.loads(gzip.decompress(golden_path.read_bytes()))
    images = json.loads(IMAGES.read_text(encoding="utf-8"))
    codes = stop_codes()
    case = golden["case"]
    policy = dict(case["policy"])
    m, n, k = case["m"], case["n"], case["k"]
    model_case = case_by_name(args.case_name)
    model_policy = model_case["policy"]
    if args.fixed_outer_iterations:
        policy["max_iterations"] = args.fixed_outer_iterations
        policy["residual_atol"] = 0.0
        model_policy = replace(
            model_policy,
            max_iterations=args.fixed_outer_iterations,
            residual_atol=0.0,
            sp_stop_on_non_decrease=False,
        )
    expected_geometry = (
        model_case["m"], model_case["n"], model_case["k"], model_case["seed"])
    if (m, n, k, case["seed"]) != expected_geometry:
        raise SystemExit("selected model case does not match immutable golden")
    if model_case["name"] != case["name"] or case["name"] != args.case_name:
        raise SystemExit("selected case name does not match immutable golden")
    true_support = list(model_case["true_support"])
    restricted_phi = model_case["phi"][:, true_support]
    independent_ls = np.linalg.lstsq(
        restricted_phi, model_case["y"], rcond=None)[0]
    if not np.allclose(
            independent_ls, model_case["x_true"][true_support],
            atol=1e-12, rtol=0.0):
        raise SystemExit("planted coefficients fail independent NumPy LS")
    if float(np.linalg.cond(restricted_phi)) >= 10.0:
        raise SystemExit("restricted matrix is unexpectedly ill-conditioned")

    arithmetic = Arithmetic(NumericProfile(), Events())
    y_q = [arithmetic.quantize_data(float(v)) for v in case["y"]]

    atol = float(policy["residual_atol"])
    if atol > 0:
        threshold = arithmetic.quantize_data(atol)
        residual_limit = max(threshold * threshold, m)
    else:
        residual_limit = 0

    configuration = rc.RunConfiguration(
        result_mode=int(rc.ResultMode.BOTH),
        matrix_kind=int(rc.MatrixKind.DENSE_RADEMACHER),
        measurement_count=m,
        signal_length=n,
        sparsity=k,
        outer_iteration_limit=int(policy["max_iterations"]),
        refinement_iteration_limit=128,
        normal_residual_shift=14,
        refinement_profile=int(rc.RefinementProfile.STRICT_PAPER),
        residual_threshold_acc62=residual_limit,
        phi_seed=int(case["seed"]),
        measurement_address=MEAS_ADDR,
        dense_result_address=DENSE_ADDR,
        sparse_result_address=SPARSE_ADDR,
        user_tag=USER_TAG,
        phi_scale_mantissa_uq17=1 << 17,
        phi_scale_exponent=-3,
        phi_column_weight=m,
        require_unit_norm=0,
        termination_mode=int(
            rc.TerminationMode.FORCE_OUTER_ITERATIONS
            if args.fixed_outer_iterations else rc.TerminationMode.NORMAL),
    )
    cfg_words = []
    for _, profile_id, normal_shift in PROFILE_ORDER:
        cfg_words.extend(rc.pack(replace(
            configuration,
            normal_residual_shift=normal_shift,
            refinement_profile=int(profile_id),
        )))

    context_library = json.loads(CONTEXT_LIBRARY.read_text(encoding="utf-8"))
    memory_records = {
        int(record["id"]): record
        for record in context_library["memory_allocation"]["configurations"]
    }
    measurement_objects = {
        "measurement_y", "residual_current", "residual_proposed",
    }
    solver_measurement_objects = {
        "solver_d", "solver_r",
        "solver_d_even_stripes", "solver_d_odd_stripes",
        "solver_r_even_stripes", "solver_r_odd_stripes",
    }
    work_objects = {
        "solver_x", "solver_g", "solver_p", "phi_support_forward",
        "phi_support_transpose", "phi_support_refill",
    }
    signal_objects = {
        "iht_x_dense", "iht_gradient_dense", "iht_tentative_dense",
        "phi_dense", "phi_dense_no_capture",
    }
    work_count = min(3 * k, 96)
    padded_measurement_count = ((m + 31) // 32) * 32
    memory_words = [0] * 64
    memory_summary = {}
    for identifier, record in memory_records.items():
        memory = isa.unpack_memory_configuration(int(record["word"]))
        name = record["name"]
        if name in measurement_objects:
            count = m
        elif name in solver_measurement_objects:
            count = padded_measurement_count
        elif name in work_objects:
            count = work_count
        elif name in signal_objects:
            count = n
        else:
            raise SystemExit(f"unclassified memory configuration {name}")
        phi_row_pair_log2 = 0 if m <= 64 else 1
        specialized = replace(
            memory,
            element_count=count,
            bank_count_log2=(phi_row_pair_log2
                             if memory.memory_space ==
                             isa.MemorySpace.PHI_COORDINATE_STREAM
                             else memory.bank_count_log2),
        )
        memory_words[identifier] = isa.pack_memory_configuration(specialized)
        memory_summary[name] = {"id": identifier, "element_count": count}

    program_records = {}
    for record in images["programs"] if "programs" in images else images:
        if isinstance(record, str):
            record = images[record]
        program_records[record["algorithm"].lower()] = record

    phase_lengths = []
    scalar_needs = []
    scalar_values = []
    for name in ABI_ORDER:
        record = program_records[name]
        phase_lengths.append(int(record["phase_instruction_count"]
                                 if "phase_instruction_count" in record
                                 else record["instruction_count"]))
        scalars = record.get("scalars") or record.get("scalar_preloads") or []
        if isinstance(scalars, dict):
            scalars = [dict(register=key, value=value)
                       for key, value in scalars.items()]
        if len(scalars) > 1:
            raise SystemExit(f"{name}: more than one scalar preload")
        if scalars:
            entry = scalars[0]
            raw = entry.get(
                "value_s27f19_raw", entry.get("value", entry.get("raw")))
            if raw is None:
                raise SystemExit(f"{name}: scalar preload has no raw value")
            if name in {"iht", "htp"}:
                step_size = float(policy["step_size"])
                magnitude = int(np.floor(
                    abs(step_size) * (1 << NumericProfile().solver_f) + 0.5))
                raw = arithmetic.solver(
                    -magnitude if step_size < 0 else magnitude)
            scalar_needs.append(1)
            scalar_values.append(int(raw))
        else:
            scalar_needs.append(0)
            scalar_values.append(0)

    stop_values = []
    support_counts = []
    support_indices = []
    support_coeffs = []
    dense_lanes = []
    residual_lanes = []
    event_flags = []
    outer_iterations = []
    summary = {
        "profiles": {},
        "benchmark": {
            "fixed_outer_iterations": args.fixed_outer_iterations or None,
            "residual_stopping_disabled": bool(args.fixed_outer_iterations),
        },
    }
    for profile_index, (profile_name, _, _) in enumerate(PROFILE_ORDER):
        profile_summary = {}
        for algorithm_index, name in enumerate(ABI_ORDER):
            trace_policy = model_policy if args.fixed_outer_iterations else model_case["policy"]
            trace = run(
                TRACE_KEY[name], model_case["phi"], model_case["y"],
                trace_policy, NumericProfile(),
                RefinementPolicy(profile=profile_name),
            )
            if args.fixed_outer_iterations:
                trace_outer_iterations = args.fixed_outer_iterations
            elif trace.phases:
                iter_min = min(phase.iteration for phase in trace.phases)
                iter_max = max(phase.iteration for phase in trace.phases)
                trace_outer_iterations = iter_max - iter_min + 1
            else:
                trace_outer_iterations = 0
            outer_iterations.append(trace_outer_iterations)
            if args.fixed_outer_iterations:
                if trace_outer_iterations != args.fixed_outer_iterations:
                    raise SystemExit(
                        f"{profile_name}/{name}: executed "
                        f"{trace_outer_iterations} outer iterations, expected "
                        f"{args.fixed_outer_iterations}")
                if trace.stop_reason not in {"max_iterations", "paper_iteration_limit"}:
                    raise SystemExit(
                        f"{profile_name}/{name}: fixed-iteration benchmark "
                        f"stopped due to {trace.stop_reason}")
            if profile_index == 0 and not args.fixed_outer_iterations:
                immutable = golden["traces"][TRACE_KEY[name]]
                strict_fields = {
                    "stop_reason": trace.stop_reason,
                    "support": list(trace.support),
                    "x": list(trace.x),
                    "residual": list(trace.residual),
                }
                for field, actual in strict_fields.items():
                    if actual != immutable[field]:
                        raise SystemExit(
                            f"{name}: strict {field} diverges from immutable golden")
            reason = trace.stop_reason
            if reason not in STOP_NAME:
                raise SystemExit(f"{profile_name}/{name}: unmapped stop reason {reason}")
            stop_values.append(codes[STOP_NAME[reason]])
            support = [int(v) for v in trace.support]
            if len(support) > SUPPORT_SLOTS:
                raise SystemExit(
                    f"{profile_name}/{name}: support exceeds physical result capacity")
            support_counts.append(len(support))
            xs = [int(v) for v in trace.x]
            if len(xs) != n:
                raise SystemExit(f"{profile_name}/{name}: dense length mismatch")
            for slot in range(SUPPORT_SLOTS):
                if slot < len(support):
                    column = support[slot]
                    support_indices.append(column)
                    support_coeffs.append(s27_lane(xs[column] << 5))
                else:
                    support_indices.append(0)
                    support_coeffs.append(0)
            dense_lanes.extend(s27_lane(v << 5) for v in xs)
            residual_lanes.extend(d18_lane(int(v)) for v in trace.residual)
            events = trace.events
            flags = (int(events.data_saturation != 0)
                     | int(events.solver_saturation != 0) << 1
                     | int(events.acc_overflow != 0) << 2
                     | int(events.divide_by_zero != 0) << 3
                     | int(events.refinement_breakdown != 0) << 4)
            event_flags.append(flags)
            profile_summary[name] = {
                "program_id": algorithm_index,
                "stop_reason": reason,
                "stop_code": stop_values[-1],
                "outer_iterations_executed": trace_outer_iterations,
                "support": support,
                "residual": list(trace.residual),
                "events": {
                    "data_saturation": events.data_saturation,
                    "solver_saturation": events.solver_saturation,
                    "acc_overflow": events.acc_overflow,
                    "divide_by_zero": events.divide_by_zero,
                    "refinement_breakdown": events.refinement_breakdown,
                },
                "phase_instructions": phase_lengths[algorithm_index],
                "scalar_preload": scalar_values[algorithm_index]
                if scalar_needs[algorithm_index] else None,
            }
        summary["profiles"][profile_name] = profile_summary

    meas_beats = beats_from_lanes([d18_lane(v) for v in y_q])

    lines = [
        "// Generated by scripts/golden/generate_m13_e2e_smoke.py.",
        f"// Authority: {case['name']} hardware golden + run-config rev 5.",
        "// Do not edit by hand.",
        f"localparam [63:0] E2E_CFG_ADDR = 64'h{CFG_ADDR:x};",
        f"localparam [63:0] E2E_MEAS_ADDR = 64'h{MEAS_ADDR:x};",
        f"localparam [63:0] E2E_DENSE_ADDR = 64'h{DENSE_ADDR:x};",
        f"localparam [63:0] E2E_SPARSE_ADDR = 64'h{SPARSE_ADDR:x};",
        f"localparam [31:0] E2E_USER_TAG = 32'h{USER_TAG:08x};",
        f"localparam integer E2E_M = {m};",
        f"localparam integer E2E_N = {n};",
        f"localparam integer E2E_K = {k};",
        f"localparam integer E2E_TIMEOUT_CYCLES = "
        f"{max(20000, 64 * m * n * int(policy['max_iterations']))};",
        f"localparam integer E2E_BENCHMARK_MODE = "
        f"{1 if args.fixed_outer_iterations else 0};",
        f"localparam integer E2E_ARRAY_CONTEXT_COUNT = {context_library['array_context_count']};",
        "localparam integer E2E_ALG_COUNT = 8;",
        f"localparam integer E2E_PROFILE_COUNT = {len(PROFILE_ORDER)};",
        f"localparam integer E2E_CASE_COUNT = {len(PROFILE_ORDER) * len(ABI_ORDER)};",
        f"localparam integer E2E_SUPPORT_SLOTS = {SUPPORT_SLOTS};",
        f"localparam integer E2E_MEAS_BEATS = {len(meas_beats)};",
        f"localparam integer E2E_DENSE_BEATS = {n // 4};",
        vh_wide("E2E_CFG_WORDS", 32, cfg_words),
        vh_wide("E2E_MEMORY_CONFIGURATIONS", 64, memory_words),
        vh_wide("E2E_MEAS", 128, meas_beats),
        vh_wide("E2E_PHASE_LEN", 8, phase_lengths),
        vh_wide("E2E_SCALAR_NEED", 1, scalar_needs),
        vh_wide("E2E_SCALAR_VALUE", 62, scalar_values),
        vh_wide("E2E_STOP_CODE", 4, stop_values),
        vh_wide("E2E_OUTER_ITERATIONS", 16, outer_iterations),
        vh_wide("E2E_SUPPORT_COUNT", 8, support_counts),
        vh_wide("E2E_SUPPORT_INDEX", 10, support_indices),
        vh_wide("E2E_SUPPORT_COEFF", 32, support_coeffs),
        vh_wide("E2E_DENSE_LANES", 32, dense_lanes),
        vh_wide("E2E_RESIDUAL_LANES", 32, residual_lanes),
        vh_wide("E2E_EVENT_FLAGS", 5, event_flags),
    ]
    out_vh.parent.mkdir(parents=True, exist_ok=True)
    out_vh.write_text("\n".join(lines) + "\n", encoding="utf-8")

    out_json.parent.mkdir(parents=True, exist_ok=True)
    summary["case"] = {"name": case["name"], "m": m, "n": n, "k": k,
                       "seed": case["seed"],
                       "residual_threshold_acc62": residual_limit,
                       "outer_iteration_limit": policy["max_iterations"],
                       "timeout_cycles": max(
                           20000, 64 * m * n * int(policy["max_iterations"]))}
    summary["memory_configurations"] = memory_summary
    out_json.write_text(json.dumps(summary, indent=2) + "\n",
                        encoding="utf-8")
    print(f"generated {out_vh.relative_to(REPO)} and "
          f"{out_json.relative_to(REPO)}")


if __name__ == "__main__":
    main()
