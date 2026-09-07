#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import run_configuration
from models.v3.hardware import _refinement_certificate_limit

OUTPUT = (ROOT / "reports" / "v3" / "optimization_follow_20260906" /
          "p1" / "p16_certificate_normalizer_contract.json")


def certificate_values(profile: dict, shift: int, support: int,
                       measurement: int, gamma: int) -> dict:
    limit, relative, floor = _refinement_certificate_limit(
        gamma, shift, support, measurement,
        profile["solver_fraction_bits"], profile["data_fraction_bits"])
    energy_shift = 2 * (
        (profile["solver_fraction_bits"] - 19) -
        (profile["data_fraction_bits"] - 14))
    return {
        "energy_scale_shift": energy_shift,
        "relative_limit": relative,
        "quantization_floor": floor,
        "certificate_limit": limit,
    }


def main() -> None:
    configuration = architecture.load()
    profiles = {
        item["name"]: item
        for item in configuration["numeric_profiles"]["profiles"]
    }
    cases = []
    for profile in profiles.values():
        shift = profile["strict_normal_residual_shift"]
        for measurement, support in ((16, 1), (32, 32), (64, 64), (128, 96)):
            gamma = (5 << (2 * shift)) + 1
            values = certificate_values(
                profile, shift, support, measurement, gamma)
            expected_floor = max(
                1 << 14,
                measurement << 10 if measurement > 32 else 0,
                support << (11 if measurement <= 32 else 12),
            ) << values["energy_scale_shift"]
            assert values["relative_limit"] == 6
            assert values["quantization_floor"] == expected_floor
            assert values["certificate_limit"] == max(6, expected_floor)
            cases.append({
                "profile": profile["name"],
                "normal_residual_shift": shift,
                "measurement_count": measurement,
                "support_count": support,
                **values,
            })

    normalizer = {}
    for profile in profiles.values():
        delta = profile["solver_fraction_bits"] - profile["data_fraction_bits"]
        solver_shifts = {exponent: 17 - exponent for exponent in range(-16, 16)}
        data_shifts = {
            exponent: 17 - exponent - delta for exponent in range(-16, 16)
        }
        max_data_exponent = max(
            exponent for exponent, shift in data_shifts.items() if shift > 0)
        assert min(solver_shifts.values()) > 0
        assert max_data_exponent == run_configuration.PHI_DATA_NORMALIZER_MAX_EXPONENT
        normalizer[profile["name"]] = {
            "format_fraction_delta": delta,
            "minimum_solver_shift": min(solver_shifts.values()),
            "minimum_legal_data_shift": min(
                shift for shift in data_shifts.values() if shift > 0),
            "maximum_legal_data_exponent": max_data_exponent,
            "first_illegal_data_exponent": max_data_exponent + 1,
        }

    checker = (ROOT / "rtl" / "v3" / "refinement" /
               "normal_residual_checker.v").read_text()
    dispatcher = (ROOT / "rtl" / "v3" / "integration" /
                  "m8_resource_dispatcher.v").read_text()
    normalizer_rtl = (ROOT / "rtl" / "v3" / "phi" /
                      "phi_operator_normalizer.v").read_text()
    for stale in ("15'd16384", "11'b0", "12'b0", "10'b0"):
        assert stale not in checker
        assert stale not in dispatcher
    assert "certificate_limit_unit" in checker
    assert "certificate_limit_unit" in dispatcher
    assert "invalid_shift1" in normalizer_rtl
    assert "saturated2 <= 1'b1" in normalizer_rtl

    payload = {
        "schema": "cscgra-v3-p16-certificate-normalizer-contract-v1",
        "status": "PASS",
        "architecture_schema": configuration["schema"],
        "rtl_minor_revision": configuration["rtl_minor_revision"],
        "run_configuration_revision": run_configuration.REVISION,
        "active_profile": configuration["numeric_profiles"]["active"],
        "closure_candidate": configuration["numeric_profiles"]["closure_candidate"],
        "candidate_strict_shift": profiles["quality_d22"][
            "strict_normal_residual_shift"],
        "certificate_cases": cases,
        "normalizer": normalizer,
        "structural_checks": {
            "single_certificate_limit_rtl_authority": True,
            "checker_literal_floor_removed": True,
            "dispatcher_literal_floor_removed": True,
            "normalizer_invalid_shift_fails_closed": True,
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
