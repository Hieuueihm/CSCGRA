"""Reproducible payload-only DMA/compute scenarios, not measured throughput."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def study() -> dict:
    m, n, coefficient_bits = 128, 1024, 18
    frequency_hz, bus_bits, pe_count = 100_000_000, 128, 32
    scenarios = []
    for bits_per_coefficient in (coefficient_bits, 32):
        for efficiency in (1.0, 0.5):
            for jobs_per_operator in (1, 10, 100):
                for gemv_passes_per_job in (2, 20):
                    row = dict(bits_per_coefficient=bits_per_coefficient,
                               assumed_dma_efficiency=efficiency,
                               jobs_per_operator=jobs_per_operator,
                               dense_gemv_passes_per_job=gemv_passes_per_job)
                    compute_s = gemv_passes_per_job * (m*n/pe_count) / frequency_hz
                    for copies, name in ((2, "dual"), (1, "single")):
                        payload_bytes = copies*m*n*bits_per_coefficient//8
                        beats = copies*m*n*bits_per_coefficient//bus_bits
                        load_s = beats/(frequency_hz*efficiency)
                        row[name] = dict(matrix_transfer_bytes=payload_bytes,
                                         matrix_payload_beats=beats,
                                         matrix_preload_us=load_s*1e6,
                                         amortized_matrix_preload_us=load_s*1e6/jobs_per_operator,
                                         payload_stage_time_per_job_us=(load_s/jobs_per_operator+compute_s)*1e6)
                    row["resident_mac_payload_time_per_job_us"] = compute_s*1e6
                    scenarios.append(row)
    return {
        "status": "analytic_payload_scenarios_not_full_job_latency_or_RTL_throughput",
        "shape": {"m": m, "n": n, "coefficient_bits": coefficient_bits},
        "proposed_frequency_hz": frequency_hz, "dma_bus_bits": bus_bits,
        "proposed_pe_count": pe_count,
        "peak_resident_coefficient_bytes_per_second": pe_count*coefficient_bits/8*frequency_hz,
        "ideal_dma_bytes_per_second": bus_bits/8*frequency_hz,
        "streaming_single_vector_mac_capacity_fraction_upper_bound_tightly_packed": bus_bits/(pe_count*coefficient_bits),
        "assumptions": [
            "Both orientations of the reference image are sent over DMA; host or PL generating the second copy is a different scenario.",
            "A changed operator requires a new preload; jobs_per_operator specifies explicit reuse.",
            "All GEMV passes are full dense128x1024 and have ideal32 useful MAC per cycle. Restricted LS costs are not approximated by these rows.",
            "The 18-bit framing is a tight bit-packed lower-bound scenario;32-bit coefficient framing includes alignment overhead. Neither is an implemented DMA ABI.",
            "Efficiency1.0 and0.5 are assumptions for sensitivity, not measured sustained bandwidth.",
            "Preload precedes compute; no overlap or extra matrix ping-pong buffers are assumed.",
            "The single-copy layout must still demonstrate feeder/routing timing and full-program numeric equivalence.",
        ],
        "excluded": ["context/vector/result DMA", "host operator construction", "gather/cache preparation",
                     "GEMV clear/drain/reduction", "DOT/vector/scalar instructions", "LS certificates",
                     "address/route pipeline latency", "stalls", "driver overhead"],
        "formulas": {
            "matrix_preload_seconds": "copies*M*N*framing_bits/(128*100e6*efficiency)",
            "resident_mac_payload_seconds": "passes*M*N/(32*100e6)",
            "payload_stage_time_per_job": "matrix_preload/jobs_per_operator + resident_mac_payload_seconds",
        },
        "scenarios": scenarios,
        "provenance": {"script": "scripts/v4/matrix_dma_study.py",
                       "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT/"reports/v4/matrix_dma_scenarios.json")
    args = parser.parse_args()
    report = study()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(f"Wrote {len(report['scenarios'])} payload-only DMA scenarios: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
