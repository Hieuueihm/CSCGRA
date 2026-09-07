"""Screen globally defined numerical candidates against frozen failed inputs."""
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
from models.v3 import hardware, paper, phi_generator
from scripts.numeric import v3_mri_quality_common as quality


def candidates():
    for data_f in (16, 17):
        for solver_f in (19, 20, 21, 22):
            for shift in (16, 18):
                yield {"name": f"same_width_d18f{data_f}_s27f{solver_f}_r{shift}",
                       "gain": 1, "extra_bits": 0, "relative_shift": shift,
                       "floor_shift": 2*(data_f-14),
                       "profile": {"data_f": data_f, "solver_f": solver_f}}
    for gain in (1, 2, 4):
        for shift in (16, 18):
            for floor_shift in (4, 6):
                yield {"name": f"d18_gain{gain}_relative{shift}_floor{floor_shift}",
                       "gain": gain, "extra_bits": 0, "relative_shift": shift,
                       "floor_shift": floor_shift}
    for extra in (2, 4, 6):
        for shift in (16, 18, 20):
            yield {"name": f"d{18+extra}_relative{shift}_precision_floor",
                   "gain": 1, "extra_bits": extra, "relative_shift": shift,
                   "floor_shift": 2 * extra}


def run(candidate, samples):
    extra = candidate["extra_bits"]
    profile = replace(quality.PROFILE, data_w=18+extra, data_f=14+extra,
                      solver_w=27+extra, solver_f=19+extra, acc_w=62+2*extra)
    profile = replace(profile, **candidate.get("profile", {}))
    refinement = replace(quality.REFINEMENT, strict_normal_residual_shift=candidate["relative_shift"])
    phi = phi_generator.matrix(quality.BLOCK_PHI_SEED, quality.BLOCK_M, quality.BLOCK_N)
    policy = quality.policy_for(phi)
    original_limit = hardware._refinement_certificate_limit
    def certificate_limit(*args):
        _, relative, floor = original_limit(*args)
        floor = max(1, floor >> candidate["floor_shift"])
        return max(relative, floor), relative, floor
    records = []
    with patch.object(hardware, "_refinement_certificate_limit", certificate_limit):
        for sample in samples:
            algorithm = sample["algorithm"]
            original = np.asarray(sample["source_block"])
            measurement = np.asarray(sample["measurement"])
            gain = candidate["gain"]
            scale = sample["normalization_scale"]
            floating = paper.run(algorithm, phi, measurement, policy)
            fixed = hardware.run(algorithm, phi, measurement * gain, policy, profile, refinement)
            def metrics(coefficients):
                return quality.image_metrics(original, quality.mri_dct_inverse(coefficients).reshape(8, 8))
            floating_metrics = metrics(np.asarray(floating.x) / scale)
            fixed_metrics = metrics(np.asarray(fixed.x) / (1 << profile.data_f) / scale / gain)
            gap = floating_metrics["snr_db"] - fixed_metrics["snr_db"]
            ratio = quality._ratio(fixed_metrics["mse"], floating_metrics["mse"])
            drop = floating_metrics["ssim"] - fixed_metrics["ssim"]
            events = asdict(fixed.events)
            passed = (gap <= quality.APPLICATION_SNR_GAP_MAX_DB
                      and ratio <= min(quality.APPLICATION_MSE_RATIO_MAX, quality.APPLICATION_NMSE_RATIO_MAX)
                      and drop <= quality.APPLICATION_SSIM_DROP_MAX and not any(events.values()))
            records.append({"case": sample["case"], "algorithm": algorithm, "pass": bool(passed),
                            "snr_gap_db": float(gap), "mse_ratio": float(ratio), "ssim_drop": float(drop),
                            "stop_reason": fixed.stop_reason, "events": events,
                            "refinement_steps": sum(phase.name == "REFINEMENT_STEP" for phase in fixed.phases)})
    return {"candidate": candidate, "numeric_profile": asdict(profile), "refinement_policy": asdict(refinement),
            "passed": sum(record["pass"] for record in records), "total": len(records), "records": records}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=False)
    samples = json.loads(args.inputs.read_text())["cases"]
    results = []
    for candidate in candidates():
        result = run(candidate, samples)
        results.append(result)
        print(candidate["name"], result["passed"], "/", result["total"], flush=True)
        (args.out_dir / "results.json").write_text(json.dumps({"diagnostic_only": True, "candidates": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
