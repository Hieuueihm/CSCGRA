#!/usr/bin/env python3
"""Build the P1.5 fixed-point arithmetic contract without activating D22."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import random
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3 import architecture_configuration as architecture


def signed_width_for_peak(peak: int) -> int:
    return max(1, int(peak).bit_length() + 1)


def signed_value(value: int, width: int) -> int:
    masked = value & ((1 << width) - 1)
    return masked - (1 << width) if masked & (1 << (width - 1)) else masked


def reconstructed_product(left: int, right: int, width: int) -> int:
    left_chunk_width = 27
    right_chunk_width = 18
    left_low = signed_value(left, left_chunk_width)
    right_low = signed_value(right, right_chunk_width)
    left_high = (left >> left_chunk_width) + (
        1 if left & (1 << (left_chunk_width - 1)) else 0
    )
    right_high = (right >> right_chunk_width) + (
        1 if right & (1 << (right_chunk_width - 1)) else 0
    )
    return (
        left_low * right_low
        + (left_high * right_low << left_chunk_width)
        + (left_low * right_high << right_chunk_width)
        + (left_high * right_high << (left_chunk_width + right_chunk_width))
    )


def multiplier_check(width: int) -> dict[str, int | bool]:
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    values = [minimum, minimum + 1, -1, 0, 1, maximum - 1, maximum]
    rng = random.Random(0xD220000 + width)
    pairs = [(left, right) for left in values for right in values]
    pairs.extend((rng.randint(minimum, maximum), rng.randint(minimum, maximum))
                 for _ in range(4096))
    mismatches = sum(
        reconstructed_product(left, right, width) != left * right
        for left, right in pairs
    )
    return {"cases": len(pairs), "mismatches": mismatches,
            "exact": mismatches == 0}


def profile_contract(profile: dict[str, object], n_max: int, m_max: int,
                     k_max: int, local_acc_width: int) -> dict[str, object]:
    solver_width = int(profile["solver_width"])
    solver_fraction = int(profile["solver_fraction_bits"])
    data_width = int(profile["data_width"])
    data_fraction = int(profile["data_fraction_bits"])
    accumulator_width = int(profile["accumulator_width"])
    encoded_peak = 1 << (solver_width - 1)
    product_peak = encoded_peak * encoded_peak
    dot_peak = n_max * product_peak
    accumulator_max = (1 << (accumulator_width - 1)) - 1
    forward_peak = n_max * encoded_peak
    transpose_peak = m_max * encoded_peak
    data_rescaled_peak = (1 << (data_width - 1)) << (solver_fraction - data_fraction)
    data_forward_peak = n_max * data_rescaled_peak
    data_transpose_peak = m_max * data_rescaled_peak
    normalizer_data_shift_min = 17 - 15 - (solver_fraction - data_fraction)
    normalizer_solver_shift_min = 17 - 15
    certificate_scale_shift = 2 * (
        (solver_fraction - 19) - (data_fraction - 14)
    )
    return {
        "identity": {key: profile[key] for key in (
            "id", "name", "status", "data_width", "data_fraction_bits",
            "solver_width", "solver_fraction_bits", "accumulator_width",
            "scalar_divide_latency", "strict_normal_residual_shift")},
        "multiply": {
            "operand_format": f"S{solver_width}F{solver_fraction}",
            "full_product_width": 2 * solver_width,
            "full_product_fraction_bits": 2 * solver_fraction,
            "reused_primary_multiplier": {"left_width": 27, "right_width": 18},
            "reused_cross_multiplier": {
                "left_width": solver_width - 26, "right_width": 18},
            "high_phase_effective_right_width": solver_width - 17,
            "decomposition_supported": 27 <= solver_width <= 35,
            "directed_and_random_check": multiplier_check(solver_width),
            "narrow_rounding": "nearest_ties_away",
            "narrow_saturation": f"S{solver_width}F{solver_fraction}",
        },
        "global_dot_norm": {
            "n_max": n_max,
            "internal_width": 2 * solver_width + math.ceil(math.log2(n_max)),
            "required_width_for_encoded_extreme": signed_width_for_peak(dot_peak),
            "architectural_result_width": accumulator_width,
            "encoded_extreme_fits_result": dot_peak <= accumulator_max,
            "maximum_encoded_extreme_terms_without_saturation":
                accumulator_max // product_peak,
            "overflow_policy": "saturate_at_ACC_boundary_and_raise_resource_fault",
        },
        "local_phi_accumulator": {
            "width": local_acc_width,
            "forward_terms": n_max,
            "forward_required_width": signed_width_for_peak(forward_peak),
            "forward_margin_bits": local_acc_width - signed_width_for_peak(forward_peak),
            "transpose_terms": m_max,
            "transpose_required_width": signed_width_for_peak(transpose_peak),
            "transpose_margin_bits": local_acc_width - signed_width_for_peak(transpose_peak),
            "data_forward_required_width": signed_width_for_peak(data_forward_peak),
            "data_forward_margin_bits":
                local_acc_width - signed_width_for_peak(data_forward_peak),
            "data_transpose_required_width": signed_width_for_peak(data_transpose_peak),
            "data_transpose_margin_bits":
                local_acc_width - signed_width_for_peak(data_transpose_peak),
            "overflow_policy": "signed_saturating_with_tile_saturation_event",
        },
        "divide": {
            "numerator_width": accumulator_width,
            "denominator_width": accumulator_width,
            "result_width": solver_width,
            "fraction_bits": solver_fraction,
            "work_width": accumulator_width + solver_width,
            "derived_latency": math.ceil(solver_width / 2) + 1,
            "authority_latency": int(profile["scalar_divide_latency"]),
            "rounding": "nearest_ties_away",
            "saturation": f"S{solver_width}F{solver_fraction}",
            "divide_by_zero": "zero_result_plus_event_no_contract_fault",
        },
        "phi_normalizer": {
            "mantissa_format": "UQ1.17",
            "signed_mantissa_width": 19,
            "product_width": accumulator_width + 19,
            "encoded_exponent_range": [-16, 15],
            "minimum_solver_input_right_shift": normalizer_solver_shift_min,
            "minimum_data_input_right_shift": normalizer_data_shift_min,
            "arbitrary_data_exponent_requires_guard": normalizer_data_shift_min <= 0,
            "rounding": "nearest_ties_away_when_right_shift_is_positive",
            "saturation": f"S{solver_width}F{solver_fraction}",
        },
        "certificate": {
            "energy_scale_shift": certificate_scale_shift,
            "base_absolute_floor": 1 << 14,
            "support_floor_shifts": {"m_le_32": 11, "m_gt_32": 12},
            "measurement_floor_shift": 10,
            "strict_normal_residual_shift":
                int(profile["strict_normal_residual_shift"]),
        },
    }


def build_audit() -> dict[str, object]:
    configuration = architecture.load()
    profiles = configuration["numeric_profiles"]["profiles"]
    n_max, m_max, k_max, local_acc_width = 1024, 128, 32, 48
    contracts = {
        str(profile["name"]): profile_contract(
            profile, n_max, m_max, k_max, local_acc_width
        ) for profile in profiles
    }
    vector_rtl = (ROOT / "rtl/v3/arithmetic/shared_vector_arithmetic_unit.v").read_text()
    scalar_rtl = (ROOT / "rtl/v3/arithmetic/scalar_function_unit.v").read_text()
    structural_checks = {
        "parameterized_fraction_width": "parameter integer FRACTION_W" in vector_rtl,
        "bounded_primary_multiplier":
            "primary_product = left_low * selected_right" in vector_rtl and
            "cross_product = left_high * selected_right" in vector_rtl,
        "nmax_internal_dot_width":
            re.search(r"DOT_INTERNAL_W\s*=\s*PRODUCT_W\s*\+\s*\$clog2", vector_rtl)
            is not None,
        "dot_boundary_fault":
            "rsp_fault = dot_out_valid && narrowed_dot_output[ACC_W]" in vector_rtl,
        "radix4_width_driven_iteration": "iteration_bit <= OUT_W-1" in scalar_rtl,
    }
    production = contracts[configuration["numeric_profiles"]["active"]]
    candidate = contracts[configuration["numeric_profiles"]["closure_candidate"]]
    gates = {
        "multiplier_exact": all(
            contract["multiply"]["directed_and_random_check"]["exact"]
            for contract in contracts.values()
        ),
        "divider_latency_authoritative": all(
            contract["divide"]["derived_latency"] ==
            contract["divide"]["authority_latency"]
            for contract in contracts.values()
        ),
        "candidate_local_phi_headroom_positive": min(
            candidate["local_phi_accumulator"]["forward_margin_bits"],
            candidate["local_phi_accumulator"]["transpose_margin_bits"],
            candidate["local_phi_accumulator"]["data_forward_margin_bits"],
            candidate["local_phi_accumulator"]["data_transpose_margin_bits"],
        ) > 0,
        "certificate_unit_invariant":
            production["certificate"]["energy_scale_shift"] == 0 and
            candidate["certificate"]["energy_scale_shift"] == 0,
        "rtl_structural_checks": all(structural_checks.values()),
    }
    return {
        "schema": "cscgra-v3-p15-arithmetic-contract-v1",
        "status": "PASS_WITH_EXPLICIT_SATURATION_BOUNDARY",
        "active_profile": configuration["numeric_profiles"]["active"],
        "closure_candidate": configuration["numeric_profiles"]["closure_candidate"],
        "limits": {"n_max": n_max, "m_max": m_max, "k_max": k_max},
        "contracts": contracts,
        "structural_checks": structural_checks,
        "gates": gates,
        "open_items": [
            "D22 remains inactive until certificate and packing checkpoints close.",
            "Encoded-extreme N1024 dot/norm exceeds ACC70; RTL saturates and faults.",
            "Arbitrary data-format Phi exponents can request non-positive shifts; the "
            "run-configuration/certificate checkpoint must bind the legal range.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    audit = build_audit()
    if not all(audit["gates"].values()):
        raise SystemExit("P1.5 arithmetic contract gate failed")
    rendered = json.dumps(audit, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = args.output if args.output.is_absolute() else ROOT / args.output
        if args.check:
            if not output.exists() or output.read_text(encoding="utf-8") != rendered:
                raise SystemExit(f"stale P1.5 audit: {output}")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(rendered, encoding="utf-8", newline="\n")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
