"""Diagnostic replay; never changes production numeric contracts or goldens."""
from __future__ import annotations
import argparse
from dataclasses import asdict, replace
import json
from pathlib import Path
import sys
from unittest.mock import patch
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v3 import hardware, numerical_candidate, paper, phi_generator
from scripts.numeric.v3_brainweb_sweep import load_volume
from scripts.numeric import v3_mri_quality_common as quality
from verification.v3 import independent_float_oracle

def scalar_json(value):
    if isinstance(value, np.generic):
        return value.item()
    raise TypeError(type(value).__name__)

def run(baseline_path, output):
    baseline = json.loads(baseline_path.read_text())
    expected_geometry = {"m": quality.BLOCK_M, "n": quality.BLOCK_N,
                         "k": quality.BLOCK_SPARSITY, "phi_seed": quality.BLOCK_PHI_SEED}
    if baseline["geometry"] != expected_geometry or baseline["numeric_profile"] != asdict(quality.PROFILE):
        raise ValueError("Baseline numeric profile or geometry differs from the audit contract")
    if baseline["refinement_policy"] != asdict(quality.REFINEMENT):
        raise ValueError("Baseline refinement policy differs from the audit contract")
    output.mkdir(parents=True, exist_ok=False)
    phi = phi_generator.matrix(quality.BLOCK_PHI_SEED, quality.BLOCK_M, quality.BLOCK_N)
    policy = quality.policy_for(phi)
    records = []
    for case in baseline["cases"]:
        failures = [(sample, algorithm) for sample in case["fixed_float"]["samples"]
                    for algorithm, result in sample["algorithms"].items() if not result["pass"]]
        if not failures:
            continue
        path = ROOT / case["provenance"]["file"]
        if quality.sha256_file(path) != case["provenance"]["sha256"]:
            raise ValueError("Source checksum mismatch")
        volume, _ = load_volume(path)
        samples = dict(quality.deterministic_content_blocks(
            [(index, volume[index]) for index in baseline["selection"]["fixed_slices"]],
            baseline["selection"]["fixed_blocks_per_volume"]))
        for sample, algorithm in failures:
            original = samples[sample["name"]]
            target = quality.topk_sparse(quality.mri_dct_forward(original.reshape(-1)))
            scale = 0.75 / max(float(np.max(np.abs(target))), 1e-30)
            if not np.isclose(scale, sample["normalization_scale"], rtol=1e-14, atol=0):
                raise ValueError("Source sample normalization did not reproduce")
            measurement = phi @ (target * scale)
            reference = paper.run(algorithm, phi, measurement, policy)
            independent = independent_float_oracle.run(algorithm, phi, measurement, policy)
            oracle_match = (np.allclose(reference.x, independent.x, atol=1e-12, rtol=1e-12)
                            and np.allclose(reference.residual, independent.residual, atol=1e-12, rtol=1e-12)
                            and tuple(reference.support) == independent.support
                            and reference.stop_reason == independent.stop_reason)
            def metrics(trace, fractional_bits=0):
                coefficients = np.asarray(trace.x) / (1 << fractional_bits) / scale
                return quality.image_metrics(original, quality.mri_dct_inverse(coefficients).reshape(8, 8))
            reference_metrics = metrics(reference)
            arithmetic = hardware.Arithmetic(quality.PROFILE, hardware.Events())
            quantized = np.asarray([arithmetic.quantize_data(float(value)) for value in measurement]) / (1 << quality.PROFILE.data_f)
            candidates = [("float_quantized_input", paper.run(algorithm, phi, quantized, policy), 0)]
            profiles = {"production": quality.PROFILE,
                        "solver31_diagnostic": replace(quality.PROFILE, solver_w=31, solver_f=23, acc_w=70),
                        "data22_solver31_diagnostic": replace(quality.PROFILE, data_w=22, data_f=18, solver_w=31, solver_f=23, acc_w=70)}
            for name, profile in profiles.items():
                candidates.append((name, hardware.run(algorithm, phi, measurement, policy, profile, quality.REFINEMENT), profile.data_f))
            d22_profile, d22_refinement = numerical_candidate.configuration("quality_d22")
            candidates.append((
                "quality_d22",
                hardware.run(
                    algorithm, phi, measurement, policy,
                    d22_profile, d22_refinement,
                ),
                d22_profile.data_f,
            ))
            variants = {}
            original_limit = hardware._refinement_certificate_limit
            def tighter_limit(*args):
                _, relative, floor = original_limit(*args)
                floor = max(1, floor // 16)
                return max(relative, floor), relative, floor
            with patch.object(hardware, "_refinement_certificate_limit", tighter_limit):
                candidates.append(("tight_certificate_diagnostic", hardware.run(algorithm, phi, measurement, policy, quality.PROFILE, quality.REFINEMENT), quality.PROFILE.data_f))
            for divisor in (4, 16, 64):
                def candidate_limit(*args):
                    _, relative, floor = original_limit(*args)
                    floor = max(1, floor // divisor)
                    return max(relative, floor), relative, floor
                with patch.object(hardware, "_refinement_certificate_limit", candidate_limit):
                    for amplitude in (2, 4):
                        candidates.append((f"gain{amplitude}_floor{divisor}_diagnostic",
                                           hardware.run(algorithm, phi, measurement * amplitude, policy,
                                                        quality.PROFILE, quality.REFINEMENT),
                                           quality.PROFILE.data_f + amplitude.bit_length() - 1))
            for amplitude in (2, 4):
                candidates.append((f"amplitude{amplitude}_diagnostic", hardware.run(algorithm, phi, measurement * amplitude, policy, quality.PROFILE, quality.REFINEMENT), quality.PROFILE.data_f))
            for name, trace, fractional_bits in candidates:
                amplitude = 2 if name == "amplitude2_diagnostic" else 4 if name == "amplitude4_diagnostic" else 1
                measured = metrics(trace, fractional_bits + (amplitude.bit_length() - 1))
                gap = reference_metrics["snr_db"] - measured["snr_db"]
                ratio = quality._ratio(measured["mse"], reference_metrics["mse"])
                drop = reference_metrics["ssim"] - measured["ssim"]
                events = asdict(trace.events) if isinstance(trace, hardware.Trace) else {}
                passed = (gap <= quality.APPLICATION_SNR_GAP_MAX_DB and ratio <= quality.APPLICATION_MSE_RATIO_MAX
                          and ratio <= quality.APPLICATION_NMSE_RATIO_MAX and drop <= quality.APPLICATION_SSIM_DROP_MAX and not any(events.values()))
                names = {"SELECT", "SELECT_GROUP", "INIT_SELECT", "MERGE", "PRUNE"}
                expected_phases = [phase for phase in reference.phases if phase.name in names]
                actual_phases = [phase for phase in trace.phases if phase.name in names]
                divergence = next(({"reference": asdict(expected), "candidate": asdict(actual)}
                                   for expected, actual in zip(expected_phases, actual_phases)
                                   if (expected.name, expected.iteration, expected.support, expected.candidates) !=
                                   (actual.name, actual.iteration, actual.support, actual.candidates)), None)
                variants[name] = {"pass": bool(passed), "snr_gap_db": float(gap), "mse_ratio": float(ratio), "ssim_drop": float(drop),
                                  "first_selection_divergence": divergence,
                                  "events": events, "stop_reason": trace.stop_reason, "support": trace.support,
                                  "refinement_outcomes": [phase.scalars for phase in trace.phases if phase.name in {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}]}
                (output / f"{case['id']}_{algorithm}_{name}.json").write_text(json.dumps(asdict(trace), indent=2, default=scalar_json) + "\n")
            (output / f"{case['id']}_{algorithm}_reference.json").write_text(json.dumps(asdict(reference), indent=2, default=scalar_json) + "\n")
            records.append({"case": case["id"], "sample": sample["name"], "algorithm": algorithm, "source_sha256": case["provenance"]["sha256"],
                            "block_sha256": quality.sha256_array(original), "variants": variants,
                            "independent_float_oracle_match": bool(oracle_match),
                            "normalization_scale": scale, "measurement": measurement.tolist(),
                            "source_block": original.tolist(),
                            "production_failure_reproduced": not variants["production"]["pass"]})
            print(case["id"], algorithm, {name: record["pass"] for name, record in variants.items()}, flush=True)
    passed = bool(records) and all(record["independent_float_oracle_match"]
                                  and record["production_failure_reproduced"] for record in records)
    result = {"baseline_sha256": quality.sha256_file(baseline_path), "diagnostic_only": True,
              "production_contract_changed": False, "failure_reproduction_pass": passed,
              "numerical_failures_closed": False, "cases": records}
    (output / "results.json").write_text(json.dumps(result, indent=2, default=scalar_json) + "\n")
    return passed

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    arguments = parser.parse_args()
    raise SystemExit(0 if run(arguments.baseline, arguments.out_dir) else 1)
