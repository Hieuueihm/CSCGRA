#!/usr/bin/env python3
"""Bit-exact authority for the 64-byte v3 run-configuration block revision 6."""
from __future__ import annotations
from dataclasses import dataclass
from enum import IntEnum
from fractions import Fraction
from typing import Sequence

MAGIC = 0x4352
REVISION = 6
WORD_COUNT = 16
BYTE_COUNT = 64
N_MAX, M_MAX, K_MAX, WORK_MAX = 1024, 128, 32, 96
UNIT_NORM_TOLERANCE = Fraction(1, 1024)
PHI_DATA_NORMALIZER_MAX_EXPONENT = 11

class RefinementProfile(IntEnum):
    STRICT_PAPER = 0
    BALANCED_VARIANT = 1
    FAST_VARIANT = 2

class MatrixKind(IntEnum):
    DENSE_RADEMACHER = 0
    FIXED_COLUMN_WEIGHT_EXPERIMENTAL = 1

class ResultMode(IntEnum):
    DENSE = 0
    SPARSE = 1
    BOTH = 2

class TerminationMode(IntEnum):
    NORMAL = 0
    FORCE_OUTER_ITERATIONS = 1

@dataclass(frozen=True)
class RunConfiguration:
    result_mode: int
    matrix_kind: int
    measurement_count: int
    signal_length: int
    sparsity: int
    outer_iteration_limit: int
    refinement_iteration_limit: int
    normal_residual_shift: int
    refinement_profile: int
    residual_threshold_acc62: int
    phi_seed: int
    measurement_address: int
    dense_result_address: int
    sparse_result_address: int
    user_tag: int
    phi_scale_mantissa_uq17: int
    phi_scale_exponent: int
    phi_column_weight: int
    require_unit_norm: int
    termination_mode: int = 0

def _signed_encode(value: int, width: int) -> int:
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    if not lo <= value <= hi:
        raise ValueError(f"signed value {value} does not fit {width} bits")
    return value & ((1 << width) - 1)

def _signed_decode(value: int, width: int) -> int:
    return value - (1 << width) if value & (1 << (width - 1)) else value

def validate(value: RunConfiguration) -> None:
    try:
        ResultMode(value.result_mode)
        MatrixKind(value.matrix_kind)
        RefinementProfile(value.refinement_profile)
        TerminationMode(value.termination_mode)
    except ValueError as exc:
        raise ValueError("invalid result, matrix, refinement or termination mode") from exc
    if not (1 <= value.measurement_count <= M_MAX
            and 1 <= value.signal_length <= N_MAX
            and 1 <= value.sparsity <= K_MAX):
        raise ValueError("M/N/K exceeds active K32 build")
    base_capacity = min(value.measurement_count, value.signal_length, WORK_MAX)
    if value.sparsity > base_capacity:
        raise ValueError("K exceeds M, N or physical work capacity")
    if not (1 <= value.outer_iteration_limit <= 0xffff
            and 1 <= value.refinement_iteration_limit <= 0xff):
        raise ValueError("iteration limits must be nonzero and encodable")
    if not 0 <= value.normal_residual_shift <= 31:
        raise ValueError("normal residual shift does not fit five bits")
    if not 0 <= value.residual_threshold_acc62 < (1 << 62):
        raise ValueError("residual threshold must be unsigned ACC62")
    for name, item in (("phi_seed", value.phi_seed),
                       ("measurement_address", value.measurement_address),
                       ("dense_result_address", value.dense_result_address),
                       ("sparse_result_address", value.sparse_result_address)):
        if not 0 <= item < (1 << 64):
            raise ValueError(f"{name} does not fit 64 bits")
    if value.measurement_address & 0xf:
        raise ValueError("measurement address must be 16-byte aligned")
    if value.result_mode in (ResultMode.DENSE, ResultMode.BOTH) and value.dense_result_address & 0xf:
        raise ValueError("dense result address must be 16-byte aligned")
    if value.result_mode in (ResultMode.SPARSE, ResultMode.BOTH) and value.sparse_result_address & 0xf:
        raise ValueError("sparse result address must be 16-byte aligned")
    if not 0 <= value.user_tag < (1 << 32):
        raise ValueError("user tag does not fit 32 bits")
    if not (1 << 17) <= value.phi_scale_mantissa_uq17 < (1 << 18):
        raise ValueError("Phi scale mantissa must use canonical UQ1.17 encoding")
    _signed_encode(value.phi_scale_exponent, 5)
    if value.phi_scale_exponent > PHI_DATA_NORMALIZER_MAX_EXPONENT:
        raise ValueError("Phi scale exponent makes the data normalizer shift non-positive")
    if value.matrix_kind != MatrixKind.DENSE_RADEMACHER:
        raise ValueError("matrix kind is encoded but unavailable in this build")
    if not 1 <= value.phi_column_weight <= 128:
        raise ValueError("Phi column weight must be 1..128")
    if value.phi_column_weight != value.measurement_count:
        raise ValueError("dense Rademacher requires column weight M")
    if value.require_unit_norm:
        scale = Fraction(value.phi_scale_mantissa_uq17, 1 << 17)
        if value.phi_scale_exponent >= 0:
            scale *= 1 << value.phi_scale_exponent
        else:
            scale /= 1 << -value.phi_scale_exponent
        column_norm_sq = value.measurement_count * scale * scale
        if abs(column_norm_sq - 1) > UNIT_NORM_TOLERANCE:
            raise ValueError("Phi scale does not satisfy required unit norm")

def pack(value: RunConfiguration) -> tuple[int, ...]:
    validate(value)
    words = [0] * WORD_COUNT
    words[0] = (MAGIC | REVISION << 16
                | int(value.result_mode) << 28 | int(value.matrix_kind) << 30)
    words[1] = (value.measurement_count | value.signal_length << 9
                | value.sparsity << 20)
    words[2] = (value.outer_iteration_limit
                | value.refinement_iteration_limit << 16
                | value.normal_residual_shift << 24
                | int(value.termination_mode) << 29
                | int(value.refinement_profile) << 30)
    words[4] = value.residual_threshold_acc62 & 0xffffffff
    words[5] = value.residual_threshold_acc62 >> 32
    for offset, item in ((6, value.phi_seed), (8, value.measurement_address),
                         (10, value.dense_result_address),
                         (12, value.sparse_result_address)):
        words[offset], words[offset + 1] = item & 0xffffffff, item >> 32
    words[14] = value.user_tag
    words[15] = (value.phi_scale_mantissa_uq17
                 | _signed_encode(value.phi_scale_exponent, 5) << 18
                 | (value.phi_column_weight - 1) << 23
                 | value.require_unit_norm << 30)
    return tuple(words)

def unpack(words: Sequence[int]) -> RunConfiguration:
    if len(words) != WORD_COUNT or any(item < 0 or item >= (1 << 32) for item in words):
        raise ValueError("run configuration must contain sixteen 32-bit words")
    if words[0] & 0xffff != MAGIC or (words[0] >> 16) & 0xff != REVISION:
        raise ValueError("run-configuration magic or revision mismatch")
    if ((words[0] >> 24) & 0xf) or words[1] >> 27 or words[3] or words[5] >> 30 or words[15] >> 31:
        raise ValueError("run-configuration reserved bits must be zero")
    u64 = lambda offset: words[offset] | words[offset + 1] << 32
    value = RunConfiguration(
        (words[0] >> 28) & 0x3, (words[0] >> 30) & 0x3,
        words[1] & 0x1ff,
        (words[1] >> 9) & 0x7ff, (words[1] >> 20) & 0x7f,
        words[2] & 0xffff, (words[2] >> 16) & 0xff,
        (words[2] >> 24) & 0x1f, (words[2] >> 30) & 0x3,
        words[4] | (words[5] & 0x3fffffff) << 32,
        u64(6), u64(8), u64(10), u64(12), words[14],
        words[15] & 0x3ffff, _signed_decode((words[15] >> 18) & 0x1f, 5),
        ((words[15] >> 23) & 0x7f) + 1, (words[15] >> 30) & 1,
        (words[2] >> 29) & 0x1)
    validate(value)
    return value
