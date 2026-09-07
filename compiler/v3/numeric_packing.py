#!/usr/bin/env python3
"""Bit-exact packing authority for inactive V3 numeric candidates.

The active ABI remains D18/S27/ACC62.  This module describes the candidate
leaves without changing the active ISA or run-configuration revision.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence
import json
from pathlib import Path

SCRATCH_WORD_W = 72
DMA_BEAT_W = 128
DMA_ELEMENT_W = 32


@dataclass(frozen=True)
class PackingProfile:
    name: str
    width: int
    signed: bool
    elements_per_word: int

    @property
    def padding_width(self) -> int:
        return SCRATCH_WORD_W - self.width * self.elements_per_word

    def __post_init__(self) -> None:
        if self.width < 1 or self.width > SCRATCH_WORD_W:
            raise ValueError("element width must fit a scratchpad word")
        if self.elements_per_word < 1:
            raise ValueError("elements_per_word must be positive")
        if self.padding_width < 0:
            raise ValueError("profile does not fit a scratchpad word")

    @property
    def min_value(self) -> int:
        return -(1 << (self.width - 1)) if self.signed else 0

    @property
    def max_value(self) -> int:
        return ((1 << (self.width - 1)) - 1
                if self.signed else (1 << self.width) - 1)

    def check_value(self, value: int) -> None:
        if not self.min_value <= value <= self.max_value:
            raise ValueError(f"{value} does not fit {self.name} ({self.width} bits)")


D22 = PackingProfile("D22", 22, True, 3)
S31 = PackingProfile("S31", 31, True, 2)
ACC70 = PackingProfile("ACC70", 70, True, 1)


def _encode(value: int, width: int, signed: bool) -> int:
    if signed:
        low = -(1 << (width - 1))
        high = (1 << (width - 1)) - 1
    else:
        low, high = 0, (1 << width) - 1
    if not low <= value <= high:
        raise ValueError(f"{value} does not fit {width}-bit {'signed' if signed else 'unsigned'} value")
    return value & ((1 << width) - 1)


def pack_scratch_word(profile: PackingProfile, values: Sequence[int]) -> int:
    if len(values) > profile.elements_per_word:
        raise ValueError(f"{profile.name} accepts at most {profile.elements_per_word} elements")
    word = 0
    for slot, value in enumerate(values):
        word |= _encode(value, profile.width, profile.signed) << (slot * profile.width)
    return word


def unpack_scratch_word(profile: PackingProfile, word: int, count: int | None = None) -> tuple[int, ...]:
    if not 0 <= word < (1 << SCRATCH_WORD_W):
        raise ValueError("scratch word must be exactly 72 bits")
    if word >> (profile.width * profile.elements_per_word):
        raise ValueError(f"{profile.name} scratch padding is not zero")
    count = profile.elements_per_word if count is None else count
    if not 0 <= count <= profile.elements_per_word:
        raise ValueError("invalid scratch element count")
    values = []
    mask = (1 << profile.width) - 1
    for slot in range(count):
        encoded = (word >> (slot * profile.width)) & mask
        if profile.signed and encoded & (1 << (profile.width - 1)):
            encoded -= 1 << profile.width
        values.append(encoded)
    return tuple(values)


def normalize_dma_beat(profile: PackingProfile, values: Sequence[int], valid_count: int | None = None) -> tuple[int, ...]:
    """Validate externally serialized signed 32-bit lanes before narrowing."""
    if profile.width > DMA_ELEMENT_W:
        raise ValueError("ACC70 is not a 32-bit DMA element")
    if len(values) > 4:
        raise ValueError("a DMA beat has four lanes")
    valid_count = len(values) if valid_count is None else valid_count
    if not 0 <= valid_count <= 4 or valid_count > len(values):
        raise ValueError("invalid DMA valid count")
    result = []
    for value in values[:valid_count]:
        if not -(1 << 31) <= value < (1 << 31):
            raise ValueError("DMA lane is not a signed 32-bit value")
        profile.check_value(value)
        result.append(value)
    return tuple(result)


def pack_acc70_threshold_beat(value: int) -> int:
    if not 0 <= value < (1 << 70):
        raise ValueError("ACC70 threshold is unsigned 70 bits")
    return value


def unpack_acc70_threshold_beat(beat: int) -> int:
    if not 0 <= beat < (1 << DMA_BEAT_W):
        raise ValueError("threshold beat must be exactly 128 bits")
    if beat >> 70:
        raise ValueError("ACC70 threshold beat padding is not zero")
    return beat & ((1 << 70) - 1)


def pack_candidate_threshold_words(value: int) -> tuple[int, int, int]:
    """Draft revision-7 run-config extension: words 3..5 carry ACC70.

    Word 3[5:0] carries bits 69:64; word 4 carries bits 31:0 and word 5
    carries bits 63:32.  Word 3[31:6] remains reserved and zero.
    Revision 6 does not consume this encoding.
    """
    if not 0 <= value < (1 << 70):
        raise ValueError("ACC70 threshold is unsigned 70 bits")
    return ((value >> 64) & 0x3f, value & 0xffffffff, (value >> 32) & 0xffffffff)


def unpack_candidate_threshold_words(words: Sequence[int]) -> int:
    if len(words) != 3 or any(not 0 <= word < (1 << 32) for word in words):
        raise ValueError("candidate threshold requires three 32-bit words")
    if words[0] >> 6:
        raise ValueError("candidate threshold reserved bits are not zero")
    return words[1] | (words[2] << 32) | ((words[0] & 0x3f) << 64)


def contract_document() -> dict:
    return {
        "contract_revision": 1,
        "active_abi_unchanged": True,
        "active_profiles": {"data": "D18", "solver": "S27", "accumulator": "ACC62"},
        "candidate_profiles": {
            profile.name: {
                "width": profile.width,
                "signed": profile.signed,
                "elements_per_72bit_word": profile.elements_per_word,
                "padding_bits_per_word": profile.padding_width,
            }
            for profile in (D22, S31, ACC70)
        },
        "scratchpad": {
            "word_bits": SCRATCH_WORD_W,
            "bit_order": "slot0 at lsb; slots packed tightly; padding at msb",
            "padding_policy": "zero",
            "overflow_policy": "reject",
        },
        "dma": {
            "beat_bits": DMA_BEAT_W,
            "d22_s31": "four signed 32-bit lanes; full 4-byte keep per valid lane",
            "acc70": "candidate threshold beat only; unsigned bits [69:0], bits [127:70] zero",
            "overflow_policy": "reject before narrowing",
        },
        "result": {
            "dense": "signed coefficient sign-extended to 32 bits",
            "sparse": "little record {index_u32, coefficient_s32}",
            "candidate_solver_width": 31,
        },
        "acc70_threshold": {
            "active_revision": 6,
            "active_revision_consumes": False,
            "draft_revision": 7,
            "draft_extension_words": "high6, low32, middle32",
            "draft_extension_does_not_change_revision_6": True,
        },
    }


def write_contract(path: str | Path) -> None:
    Path(path).write_text(json.dumps(contract_document(), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write_contract(args.output)
