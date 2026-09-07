#!/usr/bin/env python3
"""Deterministic M0 capacity/cycle contract for the v3 dual-cluster CGRA.

Values are architectural capacity and utilization lower bounds, not synthesis
or routed-timing claims. K=64 is a compatibility seam, not allocated state in
the active K=32 build.
"""
from __future__ import annotations
import argparse
from dataclasses import asdict, dataclass
import json
from math import ceil
from pathlib import Path

DATA_W, SOLVER_W, LOCAL_ACC_W, ACC_W = 18, 27, 48, 62
CLUSTER_COUNT, PE_PER_CLUSTER = 2, 16
PE_COUNT = CLUSTER_COUNT * PE_PER_CLUSTER
PREDICATE_COUNT = 4
SHARED_VECTOR_ARITHMETIC_LANES = 16
SHARED_VECTOR_MULTIPLY_II = 2
SHARED_VECTOR_RESULTS_PER_CYCLE = 8
MEMORY_LANES, MEMORY_WORD_W = 8, 72
PHI_GENERATOR_INSTANCES, PHI_SIGNS_PER_CYCLE = 1, PE_COUNT
PHI_GENERATOR_OUTPUT_W, PHI_GENERATOR_INITIATION_INTERVAL = 64, 2
PHI_GENERATOR_TARGET_LATENCY = 21
BRAM36_BITS = 36 * 1024
CONTEXT_DEPTH = 256
TILE_CONTEXT_W = ARRAY_CONTROL_CONTEXT_W = STREAM_CONTEXT_W = 36
RESOURCE_CONTEXT_W = PHASE_INSTRUCTION_W = 36
TOPK_PHYSICAL_DEPTH, TOPK_COMPARE_LANES = 64, 32
AXI_DATA_W, TARGET_CLOCK_HZ = 128, 150_000_000

@dataclass(frozen=True)
class ScalingProfile:
    name: str
    signal_length: int
    measurement_count: int
    sparsity: int

@dataclass(frozen=True)
class ScalingEstimate:
    profile: ScalingProfile
    index_width: int
    candidate_depth: int
    work_depth: int
    topk_physical_depth: int
    context_bram36: int
    configuration_bram36: int
    vector_scratchpad_bram36: int
    support_workspace_bram36: int
    total_non_phi_bram36: int
    phi_generator_instances: int
    phi_generator_output_width: int
    phi_generator_initiation_interval: int
    phi_generator_target_latency: int
    phi_signs_per_cycle: int
    shared_vector_arithmetic_lanes: int
    shared_vector_multiply_ii: int
    shared_vector_results_per_cycle: int
    phi_stored_bits: int
    phi_storage_bram36: int
    phi_storage_uram: int
    internal_vector_bandwidth_bytes_per_second: int
    internal_phi_sign_bandwidth_bits_per_second: int
    equivalent_phi_data_bandwidth_bytes_per_second: int
    single_axi_bandwidth_bytes_per_second: int
    correlation_lane_cycle_lower_bound: int
    refinement_k_operator_cycle_lower_bound: int
    refinement_2k_operator_cycle_lower_bound: int
    refinement_3k_operator_cycle_lower_bound: int
    support_workspace_bits: int
    topk_state_bits: int
    topk_comparator_lanes: int
    topk_candidate_scan_cycles: int
    topk_prune_scan_cycles: int
    shared_vector_work_cycle_lower_bound: int
    vector_and_refinement_scratch_bits: int

BASELINE = ScalingProfile("k32_m128_n1024", 1024, 128, 32)

def _ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator

def estimate(profile: ScalingProfile) -> ScalingEstimate:
    n, m, k = profile.signal_length, profile.measurement_count, profile.sparsity
    if min(n, m, k) <= 0:
        raise ValueError("N, M and K must be positive")
    candidate, work = 2 * k, 3 * k
    if work > min(m, n):
        raise ValueError("3K restricted-refinement workspace exceeds M or N")
    if candidate > TOPK_PHYSICAL_DEPTH:
        raise ValueError("TOP-2K exceeds active K=32 selection capacity")
    index_w, slot_w = max(1, (n - 1).bit_length()), max(1, work.bit_length())
    context_bram, configuration_bram = 10, 1
    support_bits = ((k + candidate + work) * index_w + 2 * n
                    + (k + work) * SOLVER_W + n * slot_w)
    support_bram = max(1, ceil(support_bits / BRAM36_BITS))
    topk_state_bits = TOPK_PHYSICAL_DEPTH * (SOLVER_W + index_w)
    # y/current/proposed residual in D18; d[M] and x/g/p[3K] in S27.
    # No full proxy, dense x, RHS, Gram, LDLT or QR state is allocated.
    vector_bits = 3 * m * DATA_W + (m + 3 * work) * SOLVER_W
    stripe_bits = MEMORY_LANES * BRAM36_BITS
    vector_bram = MEMORY_LANES * ceil(vector_bits / stripe_bits)
    def operator_cycles(depth: int) -> int:
        return _ceil_div(2 * m * depth, PHI_SIGNS_PER_CYCLE)
    vector_bw = MEMORY_LANES * MEMORY_WORD_W * TARGET_CLOCK_HZ // 8
    return ScalingEstimate(
        profile, index_w, candidate, work, TOPK_PHYSICAL_DEPTH,
        context_bram, configuration_bram, vector_bram, support_bram,
        context_bram + configuration_bram + vector_bram + support_bram,
        PHI_GENERATOR_INSTANCES, PHI_GENERATOR_OUTPUT_W,
        PHI_GENERATOR_INITIATION_INTERVAL, PHI_GENERATOR_TARGET_LATENCY,
        PHI_SIGNS_PER_CYCLE, SHARED_VECTOR_ARITHMETIC_LANES,
        SHARED_VECTOR_MULTIPLY_II, SHARED_VECTOR_RESULTS_PER_CYCLE,
        0, 0, 0, vector_bw, PHI_SIGNS_PER_CYCLE * TARGET_CLOCK_HZ,
        PHI_SIGNS_PER_CYCLE * DATA_W * TARGET_CLOCK_HZ // 8,
        AXI_DATA_W * TARGET_CLOCK_HZ // 8, _ceil_div(m * n, PE_COUNT),
        operator_cycles(k), operator_cycles(candidate), operator_cycles(work),
        support_bits, topk_state_bits, TOPK_COMPARE_LANES,
        _ceil_div(candidate, TOPK_COMPARE_LANES),
        _ceil_div(k, TOPK_COMPARE_LANES),
        _ceil_div(work, SHARED_VECTOR_RESULTS_PER_CYCLE), vector_bits)

def payload() -> dict:
    value = estimate(BASELINE)
    return {
        "schema": "cscgra-v3-architecture-scaling-v7",
        "warning": "cycle values are architectural lower bounds, not RTL measurements",
        "active_build": "K32 only",
        "future_seam": {"k64": "reserved widths only; no K64 state allocated"},
        "architecture": {
            "macroblock_count": 6,
            "cluster_count": CLUSTER_COUNT,
            "pe_count": PE_COUNT,
            "pe_isa": "homogeneous_no_general_multiply",
            "cluster_execution": "shared_synchronous_context",
            "tile_context_width": TILE_CONTEXT_W,
            "array_control_context_width": ARRAY_CONTROL_CONTEXT_W,
            "stream_context_width": STREAM_CONTEXT_W,
            "resource_context_width": RESOURCE_CONTEXT_W,
            "cycle_context_width": PE_PER_CLUSTER * TILE_CONTEXT_W
                + ARRAY_CONTROL_CONTEXT_W + STREAM_CONTEXT_W + RESOURCE_CONTEXT_W,
            "phase_instruction_width": PHASE_INSTRUCTION_W,
            "context_ramb36": 10,
            "context_image_banks": 2,
            "memory_lanes": MEMORY_LANES,
            "memory_word_width": MEMORY_WORD_W,
            "shared_vector_arithmetic_lanes": SHARED_VECTOR_ARITHMETIC_LANES,
            "shared_vector_multiply_ii": SHARED_VECTOR_MULTIPLY_II,
            "shared_vector_results_per_cycle": SHARED_VECTOR_RESULTS_PER_CYCLE,
            "phi_generator": "threefry2x32_20_counter_addressed",
            "phi_generator_instances": PHI_GENERATOR_INSTANCES,
            "phi_generator_output_width": PHI_GENERATOR_OUTPUT_W,
            "phi_generator_initiation_interval": PHI_GENERATOR_INITIATION_INTERVAL,
            "phi_generator_target_latency": PHI_GENERATOR_TARGET_LATENCY,
            "phi_signs_per_cycle": PHI_SIGNS_PER_CYCLE,
            "topk_physical_depth": TOPK_PHYSICAL_DEPTH,
            "topk_comparator_lanes": TOPK_COMPARE_LANES,
            "target_clock_hz": TARGET_CLOCK_HZ,
        },
        "profiles": [asdict(value)],
    }

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    text = json.dumps(payload(), indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    else:
        print(text, end="")

if __name__ == "__main__":
    main()
