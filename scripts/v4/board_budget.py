"""Produce a prospective ZCU106 resource budget for the v4 architecture.

This is a geometry/accounting model, not a Vivado report.  The fixed target is
the v4 resident tile from ``config/v4_design.json``: M=128, N=1024 and S=96.
The default numerical candidate is D18F14/C18F16/S27F19/A64.  The model keeps
the physical BRAM36 allocation separate from payload capacity; this matters
for the 4096-deep, 18-bit coefficient banks and for the small support banks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "config" / "v4_design.json"
DEFAULT_OUTPUT = ROOT / "reports" / "v4" / "board_budget.json"

# Static device capacity for the ZU7EV.  The URLs are retained in the report
# so a later implementation review can audit the source of these values.
DEVICE = {
    "board": "ZCU106",
    "part": "xczu7ev-ffvc1156-2-e",
    "lut6": 230_400,
    "ff": 460_800,
    "bram36": 312,
    "uram": 96,
    "dsp48e2": 1_728,
}

PROFILE = {
    "data_bits": 18,
    "data_fraction_bits": 14,
    "coefficient_bits": 18,
    "coefficient_fraction_bits": 16,
    "state_bits": 27,
    "state_fraction_bits": 19,
    "accumulator_bits": 64,
}

SOURCES = [
    {
        "id": "ds891",
        "url": "https://docs.amd.com/api/khub/documents/sbPbXcMUiRSJ2O5STvuGNQ/content",
        "use": "ZU7EV device resource capacities",
    },
    {
        "id": "ug573",
        "url": "https://docs.amd.com/r/en-US/ug573-ultrascale-memory-resources/Block-RAM-Summary",
        "use": "UltraScale memory primitive geometry and BRAM36/BRAM18 accounting",
    },
    {
        "id": "ug1244",
        "url": "https://docs.amd.com/api/khub/documents/FiJhhOVPF8Ijqstd8bPc6A/content",
        "use": "ZCU106 platform reference",
    },
]


def ceil_div(numerator: int, denominator: int) -> int:
    if numerator < 0 or denominator <= 0:
        raise ValueError("ceil_div requires a non-negative numerator and positive denominator")
    return (numerator + denominator - 1) // denominator


def _require_int(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{name} must be an integer")
    return value


def _validate_target_config(config: dict[str, Any]) -> None:
    target = config.get("target", {})
    limits = config.get("limits", {})
    board = target.get("board")
    part = target.get("part")
    period = target.get("clock_period_ns")
    if board != DEVICE["board"] or part != DEVICE["part"]:
        raise ValueError(
            f"budget geometry is for {DEVICE['board']}/{DEVICE['part']}; "
            f"config has {board}/{part}"
        )
    if period != 10.0:
        raise ValueError(f"expected 10.0 ns (100 MHz) target clock, got {period!r}")

    dimensions = {
        "m": _require_int(limits.get("m"), "limits.m"),
        "n": _require_int(limits.get("n"), "limits.n"),
        "working_support": _require_int(limits.get("working_support"), "limits.working_support"),
    }
    expected = {"m": 128, "n": 1024, "working_support": 96}
    if dimensions != expected:
        raise ValueError(
            "this budget intentionally covers the current fixed resident geometry "
            f"{expected}, got {dimensions}"
        )


def load_target(config_path: Path) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_target_config(config)
    return config


def _bram36_count_for_width(depth: int, width: int, *, depth_4096_width_9: bool = False) -> int:
    """Count BRAM36 primitives for the explicitly used matrix geometry.

    The current coefficient bank is exactly 4096 words deep.  A 4096x18 bank
    can be represented as two 4096x9 width slices, or as two depth-cascaded
    2048x18 primitives; both use two BRAM36.  Other memories use the documented
    wide shallow arrangements below and do not call this helper.  Keeping the
    cases explicit avoids implying a universal packing model before RTL exists.
    """
    if not depth_4096_width_9 or depth != 4096:
        raise ValueError(
            "only the current 4096-word coefficient-bank geometry is supported; "
            f"got depth={depth}, explicit_geometry={depth_4096_width_9}"
        )
    if width <= 0:
        raise ValueError("BRAM bank width must be positive")
    return ceil_div(width, 9)


def _repo_display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve())).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_budget(
    config: dict[str, Any],
    profile: dict[str, int] | None = None,
    *,
    config_path: Path | None = None,
    script_path: Path | None = None,
) -> dict[str, Any]:
    _validate_target_config(config)
    profile = dict(PROFILE if profile is None else profile)
    for key, value in profile.items():
        _require_int(value, f"profile.{key}")
        if key.endswith("_fraction_bits"):
            if value < 0:
                raise ValueError(f"profile.{key} must be non-negative")
        elif value <= 0:
            raise ValueError(f"profile.{key} must be positive")
    for width_key, frac_key in (
        ("data_bits", "data_fraction_bits"),
        ("coefficient_bits", "coefficient_fraction_bits"),
        ("state_bits", "state_fraction_bits"),
    ):
        if profile[frac_key] < 0 or profile[frac_key] >= profile[width_key]:
            raise ValueError(
                f"profile.{frac_key} must satisfy 0 <= fraction < {width_key}"
            )

    # The current bank geometry is 4K x C.  C is the BRAM36 18-bit-side
    # contract; wider values require a new banking/primitive design.
    c_bits = profile["coefficient_bits"]
    if c_bits > 18:
        raise ValueError(
            f"coefficient width C={c_bits} exceeds the current 4096x18 bank geometry; "
            "choose a new physical memory contract before budgeting"
        )
    if profile["data_bits"] > 18:
        raise ValueError("candidate data width D must fit the current 27x18 DSP operand side")
    if profile["state_bits"] > 27:
        raise ValueError("candidate state width S exceeds the current 27x18 DSP operand side")

    limits = config["limits"]
    m = limits["m"]
    n = limits["n"]
    support = limits["working_support"]
    matrix_banks = config["memory"]["coefficient_banks_per_orientation"]
    vector_banks_per_plane = config["memory"]["vector_banks_per_plane"]
    vector_planes = config["memory"]["vector_planes"]
    pe_count = config["array"]["full_processing_elements"]
    context_depth = config["context"]["issue_depth"]
    tile_bits = config["context"]["tile_slot_bits"]
    control_bits = config["context"]["control_bits_per_issue"]

    if matrix_banks != 32 or vector_banks_per_plane != 32 or vector_planes != 3:
        raise ValueError("current v4 budget expects 32 matrix banks, 32 vector banks/plane, and 3 planes")
    if pe_count != 32 or context_depth != 256 or tile_bits != 64 or control_bits != 256:
        raise ValueError("current v4 budget expects 32 PEs and the documented 256-word context geometry")

    # Matrix layout: ceil(M/32)*N = 4096 addresses per bank.  A 4K BRAM36
    # configuration is 4K x 9, so C18 consumes two physical BRAM36 per bank.
    matrix_bank_depth = ceil_div(m, matrix_banks) * n
    matrix_bram36_per_bank = _bram36_count_for_width(
        matrix_bank_depth, c_bits, depth_4096_width_9=True
    )
    matrix_orientation_count = 2
    matrix_bram36 = matrix_banks * matrix_orientation_count * matrix_bram36_per_bank
    matrix_payload_bits = matrix_orientation_count * m * n * c_bits

    # Support cache uses the same 32-bank layout for A_S and A_S^T.  A 384x18
    # bank fits one BRAM18, but the baseline deliberately reserves one whole
    # BRAM36 per bank/orientation until primitive packing is explicit in RTL.
    support_bank_depth = ceil_div(m, matrix_banks) * support
    support_payload_bits = matrix_orientation_count * m * support * c_bits
    support_bram36_conservative = matrix_banks * matrix_orientation_count
    support_bram18_packed_equivalent = ceil_div(
        matrix_banks * matrix_orientation_count, 2
    )

    # Context geometry follows the architecture contract: one BRAM36 per
    # 256x64 tile bank in the wide shallow arrangement, plus four for 256x256
    # control.  Payload capacity alone would undercount this allocation.
    context_tile_bram36 = pe_count
    context_control_bram36 = 4
    context_bram36 = context_tile_bram36 + context_control_bram36
    context_tile_payload_bits = context_depth * pe_count * tile_bits
    context_control_payload_bits = context_depth * control_bits

    conservative_bram36 = matrix_bram36 + support_bram36_conservative + context_bram36
    packed_bram36 = matrix_bram36 + support_bram18_packed_equivalent + context_bram36
    bram36_available_after_conservative = DEVICE["bram36"] - conservative_bram36
    bram36_available_after_packed = DEVICE["bram36"] - packed_bram36

    vector_words_per_bank = ceil_div(config["memory"]["vector_elements_per_plane"], vector_banks_per_plane)
    vector_bits = vector_planes * vector_banks_per_plane * vector_words_per_bank * profile["state_bits"]
    # A LUT6 can hold at most 64 one-bit RAM values in the raw capacity model.
    # This is a lower-bound capacity equivalent, not a synthesis LUT count:
    # ports, replication, address decode, and SLICEM placement are unknown.
    vector_lut6_capacity_equivalent = ceil_div(vector_bits, 64)

    # CxD maps to one DSP48E2 for this candidate.  SxS is 27x27 and needs two
    # 27x17/27x10 products per PE when kept parallel; serializing the products
    # can reuse one DSP per PE at the cost of another issue in the schedule.
    cd_dsp_parallel = pe_count
    ss_dsp_parallel = 2 * pe_count if profile["state_bits"] == 27 else None
    ss_dsp_serialized = pe_count if profile["state_bits"] == 27 else None

    return {
        "schema_version": 1,
        "status": "prospective_architecture_budget_no_rtl_or_fit_proof",
        "target": {
            "board": DEVICE["board"],
            "part": DEVICE["part"],
            "clock_frequency_mhz": 100,
            "clock_period_ns": 10.0,
            "config": _repo_display_path(config_path) if config_path else "in-memory config",
        },
        "profile": {
            "name": (
                f"D{profile['data_bits']}F{profile['data_fraction_bits']}"
                f"_C{profile['coefficient_bits']}F{profile['coefficient_fraction_bits']}"
                f"_S{profile['state_bits']}F{profile['state_fraction_bits']}"
                f"_A{profile['accumulator_bits']}"
            ),
            **profile,
        },
        "resident_geometry": {
            "m": m,
            "n": n,
            "working_support": support,
            "pe_count": pe_count,
            "matrix_banks_per_orientation": matrix_banks,
            "resident_orientations": ["A", "transpose_A"],
            "vector_planes": vector_planes,
            "vector_banks_per_plane": vector_banks_per_plane,
            "vector_words_per_bank": vector_words_per_bank,
        },
        "device_resources": DEVICE,
        "resources": {
            "bram36": {
                "coefficient_store": {
                    "bank_depth_words": matrix_bank_depth,
                    "bank_width_bits": c_bits,
                    "physical_bram36_per_bank": matrix_bram36_per_bank,
                    "orientations": matrix_orientation_count,
                    "banks_total": matrix_banks * matrix_orientation_count,
                    "bram36_total": matrix_bram36,
                    "payload_bits": matrix_payload_bits,
                    "geometry_note": "4096x18 uses two BRAM36: width-split 4096x9 or depth-cascaded 2048x18",
                },
                "support_matrix_cache": {
                    "bank_depth_words": support_bank_depth,
                    "bank_width_bits": c_bits,
                    "orientations": matrix_orientation_count,
                    "banks_total": matrix_banks * matrix_orientation_count,
                    "conservative_full_bram36_per_bank": 1,
                    "conservative_full_bram36_total": support_bram36_conservative,
                    "bram18_packed_equivalent_per_orientation": matrix_banks // 2,
                    "bram18_packed_equivalent_total": support_bram18_packed_equivalent,
                    "payload_bits": support_payload_bits,
                    "packing_status": "possible_geometry_only_unproven_until_explicit_primitive_RTL",
                },
                "context_store": {
                    "tile_bank_geometry": f"{context_depth}x{tile_bits} x {pe_count} banks",
                    "tile_bram36": context_tile_bram36,
                    "control_bank_geometry": f"{context_depth}x{control_bits}",
                    "control_bram36": context_control_bram36,
                    "bram36_total": context_bram36,
                    "tile_payload_bits": context_tile_payload_bits,
                    "control_payload_bits": context_control_payload_bits,
                },
                "fixed_baseline": {
                    "coefficient_store_bram36": matrix_bram36,
                    "support_cache_conservative_bram36": support_bram36_conservative,
                    "context_store_bram36": context_bram36,
                    "conservative_baseline_bram36": conservative_bram36,
                    "conservative_used_fraction": conservative_bram36 / DEVICE["bram36"],
                    "conservative_remaining_bram36": bram36_available_after_conservative,
                    "bram18_packed_baseline_bram36_equivalent": packed_bram36,
                    "bram18_packed_used_fraction": packed_bram36 / DEVICE["bram36"],
                    "bram18_packed_remaining_bram36_equivalent": bram36_available_after_packed,
                    "reserve_before_fifo_selection_and_other_logic": bram36_available_after_conservative,
                },
            },
            "vector_lutram": {
                "physical_geometry": f"{vector_planes} planes x {vector_banks_per_plane} banks x {vector_words_per_bank} words x {profile['state_bits']} bits",
                "capacity_bits": vector_bits,
                "raw_lut6_capacity_equivalent_lower_bound": vector_lut6_capacity_equivalent,
                "coarse_slicem_ram_budget_bits": 6_200_000,
                "coarse_budget_fraction": vector_bits / 6_200_000,
                "estimate_status": "capacity_equivalent_only_no_exact_LUT_or_placement_claim",
            },
            "dsp48e2": {
                "coefficient_times_data_32_pe_parallel": cd_dsp_parallel,
                "state_times_state_32_pe_parallel": ss_dsp_parallel,
                "state_times_state_32_pe_serialized_reuse": ss_dsp_serialized,
                "device_capacity": DEVICE["dsp48e2"],
                "accumulator_note": "A64 exceeds the 48-bit DSP accumulator; logic/cascade extension is required",
                "resource_status": "DSP counts are operation-width mapping estimates, not synthesis utilization",
            },
            "lut_ff_uram": {
                "lut6": None,
                "ff": None,
                "uram": 0,
                "status": "unbudgeted_until_RTL; vector LUTRAM entry is reported separately as a raw capacity equivalent",
            },
        },
        "assumptions": [
            "The report is fixed to the current resident M128/N1024/S96 geometry and rejects other config limits.",
            "A and transpose_A are separate physical 32-bank stores generated from one quantized matrix.",
            "Coefficient bank depth is ceil(128/32)*1024=4096 words; C18 requires two BRAM36 per bank, either width-split 4096x9 or depth-cascaded 2048x18.",
            "Support A_S and A_S^T use separate 32-bank stores with depth ceil(128/32)*96=384 and width C18.",
            "The conservative support baseline reserves one full BRAM36 per support bank. BRAM18 packing is a geometry possibility only and needs explicit RTL primitive packing and collision verification.",
            "Context storage uses the documented 32 BRAM36 tile banks plus four BRAM36 control width slices.",
            "Vector stores use the proposed distributed_RAM_128_words_per_bank organization. The LUT6 figure is a 64-bit raw capacity lower bound, not a LUT utilization or placement result.",
            "C18xD18 uses one 27x18 DSP48E2 operand mapping per PE. S27xS27 decomposes into two products per PE: serialized reuse uses one DSP and two issue cycles, while parallelization uses two DSPs; merge/feedback timing remains unproven. A64 extension is outside the DSP accumulator.",
            "No FIFO, selection, scalar service, routing, feeder, DMA, shell, control, or general LUT/FF overhead is included in the fixed baseline.",
        ],
        "open_items": [
            "Numerical profile and widths are not frozen.",
            "No v4 RTL exists; synthesis, placement, routing, and 100 MHz timing are unproven.",
            "Support BRAM18 packing, true port/collision behavior, FIFO depth, selection storage, and SLICEM placement require RTL measurement.",
            "Full program context capacity and end-to-end cycle behavior remain unproven.",
        ],
        "sources": SOURCES,
        "provenance": {
            "architecture_scope": "legacy_dense_dual_orientation_reference_only_not_selected_generated_cache_baseline",
            "config_path": _repo_display_path(config_path) if config_path else "in-memory config",
            "config_sha256": _sha256(config_path) if config_path else None,
            "script_path": _repo_display_path(script_path or Path(__file__)),
            "script_sha256": _sha256(script_path or Path(__file__)),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    config = load_target(args.config)
    report = build_budget(config, config_path=args.config, script_path=Path(__file__))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote v4 ZCU106 legacy dense-reference budget to {args.output}")
    print(
        "BRAM36 dense reference (not selected generated baseline): "
        f"{report['resources']['bram36']['fixed_baseline']['conservative_baseline_bram36']}/"
        f"{DEVICE['bram36']} conservative; "
        f"{report['resources']['bram36']['fixed_baseline']['bram18_packed_baseline_bram36_equivalent']}/"
        f"{DEVICE['bram36']} with hypothetical BRAM18 support packing"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
