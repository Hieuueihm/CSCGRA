"""Phase-program compiler for the CSCGRA unified sparse execution ISA.

Emits the 64-bit context-word programs the sequencer executes.  The encoders
mirror `verification/v2/run1/tb_run1_k_sweep.v` one-to-one, and
`check_phase_compiler.py` proves byte-identical equivalence against the
testbench's own `build_program` for every canonical algorithm/K pair.

The per-algorithm bodies are the paper's phase graphs: each program is a
linear phase schedule with one CF_LOOP iteration edge; dependencies between
phases are carried implicitly by the sequencer order and decoded into the
phase/engine/dependency-mask triple by `rtl/v2/control/phase_isa_decoder.v`.
"""

from __future__ import annotations

import argparse
from pathlib import Path

SOP_REFINE = 0x80
SOP_CORR = 0x81
SOP_IHT_UPDATE = 0x82
SOP_RESID = 0x83
SOP_PRUNE_X = 0x84
SOP_MP_UPDATE = 0x85
SOP_REFINE_SPARSE = 0x86
SOP_CORR_UPDATE = 0x88
SOP_GP_PROJECT = 0x89
SOP_GP_UPDATE = 0x8A

ALG_NAMES = ["OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"]
VEC_X, VEC_R, VEC_Y = 0, 1, 2


def _set(word: int, hi: int, lo: int, value: int) -> int:
    mask = ((1 << (hi - lo + 1)) - 1) << lo
    return (word & ~mask) | ((value << lo) & mask)


def sparse_op_ctx(sparse_op: int, is_last: bool = False) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 8)
    w = _set(w, 27, 20, sparse_op)
    return _set(w, 47, 44, 6) if is_last else w


def reduce_argmax_ctx(is_last: bool = False) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 4)
    w = _set(w, 55, 52, 1)
    w = _set(w, 51, 48, 2)
    w = _set(w, 43, 41, 3)
    w = _set(w, 34, 32, 3)
    w = _set(w, 27, 24, 4)
    return _set(w, 47, 44, 6) if is_last else w


def reduce_argmax_mp_ctx(is_last: bool = False) -> int:
    return _set(reduce_argmax_ctx(is_last), 34, 32, 0)


def stream_topk_ctx(count: int, path: int, exclude_support: bool,
                    allow_tiny: bool, is_last: bool) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 5)
    w = _set(w, 31, 31, 1)
    w = _set(w, 30, 30, 1 if allow_tiny else 0)
    mode = 2 if exclude_support else (3 if allow_tiny else 1)
    w = _set(w, 27, 24, mode)
    w = _set(w, 22, 20, path)
    w = _set(w, 15, 11, count & 0x1F)
    return _set(w, 47, 44, 6) if is_last else w


def post_update_x_topk_ctx(count: int, path: int, is_last: bool) -> int:
    return _set(stream_topk_ctx(count, path, False, True, is_last), 29, 29, 1)


def post_refine_support_topk_ctx(count: int, path: int, is_last: bool) -> int:
    return _set(stream_topk_ctx(count, path, False, True, is_last), 28, 28, 1)


def candidate_ctx(ctrl: int, path: int = 0, is_last: bool = False,
                  depth: int = 0) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 6)
    w = _set(w, 22, 20, path)
    w = _set(w, 19, 16, ctrl)
    if ctrl == 4:
        w = _set(w, 15, 11, depth & 0x1F)
    return _set(w, 47, 44, 6) if is_last else w


def candidate_append_result_ctx(is_last: bool = False) -> int:
    return candidate_ctx(1, is_last=is_last)


def candidate_meta_depth_ctx(path: int, depth: int, is_last: bool = False) -> int:
    return candidate_ctx(4, path, is_last, depth)


def candidate_select_path_ctx(path: int, is_last: bool = False) -> int:
    return candidate_ctx(6, path, is_last)


def candidate_merge_path_ctx(path: int, is_last: bool = False) -> int:
    return candidate_ctx(2, path, is_last)


def candidate_copy_to_p0_ctx(path: int, is_last: bool = False) -> int:
    return candidate_ctx(14, path, is_last)


def dma_ctx(vec_id: int, addr_dim: int, ddr_write: bool, is_last: bool,
            elem_offset: int = 0) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 7)
    w = _set(w, 51, 48, addr_dim & 0xF)
    w = _set(w, 43, 41, vec_id & 7)
    w = _set(w, 31, 16, elem_offset & 0xFFFF)
    w = _set(w, 0, 0, 1 if ddr_write else 0)
    return _set(w, 47, 44, 6) if is_last else w


def ctrl_loop_rel_ctx(rel_off: int, count: int, loop_id: int,
                      is_last: bool = False) -> int:
    w = _set(0, 63, 60, 1)
    w = _set(w, 59, 56, 9)
    w = _set(w, 43, 40, 3)
    w = _set(w, 33, 28, rel_off & 0x3F)
    w = _set(w, 27, 20, count & 0xFF)
    w = _set(w, 19, 18, loop_id & 3)
    return _set(w, 47, 44, 6) if is_last else w


def build_program(alg_id: int, k_param: int) -> list[int]:
    """Byte-identical port of tb_run1_k_sweep.v build_program."""
    words: list[int] = []

    def emit(word: int) -> None:
        words.append(word)

    def select_append() -> None:
        emit(stream_topk_ctx(1, 0, True, False, False))
        emit(sparse_op_ctx(SOP_CORR, False))

    def mp_select_append() -> None:
        emit(sparse_op_ctx(SOP_CORR, False))
        emit(reduce_argmax_mp_ctx(False))
        emit(candidate_append_result_ctx(False))

    emit(dma_ctx(VEC_X, 0, False, False))
    emit(dma_ctx(VEC_R, 1, False, False))
    emit(dma_ctx(VEC_Y, 1, False, False))
    body_start = len(words)
    if alg_id == 0:  # OMP
        select_append()
        emit(sparse_op_ctx(SOP_REFINE_SPARSE, False))
    elif alg_id == 1:  # CoSaMP
        emit(candidate_meta_depth_ctx(1, 0))
        emit(stream_topk_ctx(k_param << 1, 1, False, False, False))
        emit(sparse_op_ctx(SOP_CORR, False))
        emit(candidate_select_path_ctx(1))
        emit(candidate_merge_path_ctx(0))
        emit(candidate_meta_depth_ctx(1, 0))
        emit(post_refine_support_topk_ctx(k_param, 1, False))
        emit(sparse_op_ctx(SOP_REFINE, False))
        emit(candidate_copy_to_p0_ctx(1))
        emit(sparse_op_ctx(SOP_REFINE, False))
    elif alg_id == 2:  # IHT
        emit(candidate_meta_depth_ctx(1, 0))
        emit(post_update_x_topk_ctx(k_param, 1, False))
        emit(sparse_op_ctx(SOP_CORR_UPDATE, False))
        emit(candidate_copy_to_p0_ctx(1))
        emit(sparse_op_ctx(SOP_PRUNE_X, False))
        emit(sparse_op_ctx(SOP_RESID, False))
    elif alg_id == 3:  # HTP
        emit(candidate_meta_depth_ctx(1, 0))
        emit(post_update_x_topk_ctx(k_param, 1, False))
        emit(sparse_op_ctx(SOP_CORR_UPDATE, False))
        emit(candidate_copy_to_p0_ctx(1))
        emit(sparse_op_ctx(SOP_PRUNE_X, False))
        emit(sparse_op_ctx(SOP_REFINE, False))
    elif alg_id == 4:  # SP
        emit(candidate_meta_depth_ctx(1, 0))
        emit(stream_topk_ctx(k_param, 1, False, False, False))
        emit(sparse_op_ctx(SOP_CORR, False))
        emit(candidate_select_path_ctx(1))
        emit(candidate_merge_path_ctx(0))
        emit(candidate_meta_depth_ctx(1, 0))
        emit(post_refine_support_topk_ctx(k_param, 1, False))
        emit(sparse_op_ctx(SOP_REFINE, False))
        emit(candidate_copy_to_p0_ctx(1))
        emit(sparse_op_ctx(SOP_REFINE, False))
    elif alg_id == 5:  # GP
        emit(stream_topk_ctx(1, 0, True, False, False))
        emit(sparse_op_ctx(SOP_CORR, False))
        emit(sparse_op_ctx(SOP_GP_PROJECT, False))
        emit(sparse_op_ctx(SOP_GP_UPDATE, False))
        emit(sparse_op_ctx(SOP_RESID, False))
    elif alg_id == 6:  # GOMP
        emit(stream_topk_ctx(2, 0, True, False, False))
        emit(sparse_op_ctx(SOP_CORR, False))
        emit(sparse_op_ctx(SOP_REFINE, False))
    elif alg_id == 7:  # MP
        mp_select_append()
        emit(sparse_op_ctx(SOP_MP_UPDATE, False))
    else:
        raise ValueError(f"unknown algorithm id {alg_id}")
    if k_param > 1:
        rel = body_start - len(words)
        emit(ctrl_loop_rel_ctx(rel, k_param, 0))
    emit(dma_ctx(VEC_X, 0, True, True))
    return words


def loop_iter_count(alg_id: int, k: int) -> int:
    """Iteration-edge count the canonical TB uses per algorithm."""
    return (k + 1) // 2 if alg_id == 6 else k


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("algorithm", help="name or id 0..7")
    parser.add_argument("k", type=int)
    parser.add_argument("--hex", action="store_true",
                        help="print one 16-digit hex word per line")
    args = parser.parse_args()
    alg_id = (ALG_NAMES.index(args.algorithm) if args.algorithm in ALG_NAMES
              else int(args.algorithm))
    words = build_program(alg_id, args.k)
    if args.hex:
        for word in words:
            print(f"{word:016X}")
    else:
        print(f"# {ALG_NAMES[alg_id]} K={args.k}: {len(words)} context words")
        for idx, word in enumerate(words):
            print(f"{idx:3d}: {word:016X}")


if __name__ == "__main__":
    main()
