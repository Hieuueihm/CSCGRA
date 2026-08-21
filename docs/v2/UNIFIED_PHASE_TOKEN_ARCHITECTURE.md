# Unified phase-token architecture extensions

This document records the five architecture extensions implemented after the
`88f9411` v2 sign-off. They are intentionally separated from the frozen
sign-off numbers until the complete regression and timing gates pass.

## Invariants

- Arithmetic transactions still enter at PE0 and propagate through
  PE1 -> PE2 -> PE3.
- Correlation, residual, Gram, LDLT, update, prune, and top-K continue to give
  distinct useful work to all four PE rows.
- There is still at most one active least-squares request.
- The fixed 24-bit Q16 hardware golden remains generated only from
  `models/reference/hardware.py`; RTL never generates or edits its oracle.
- No additional multiplier, divider, DSP, BRAM, or matrix-memory write port is
  introduced by these extensions.

## 1. Delta-support LDLT reuse

The factor checker now distinguishes four safe relationships between the new
ordered support and the cached factor:

| Relationship | Action |
| --- | --- |
| Exact | Reuse the complete cached factor. |
| Prefix extension | Keep the old leading factor and build only new borders. |
| Prefix truncation | Solve from the already exact leading principal block. |
| Last-entry replacement | Keep the first `K-1` rows, clear one Gram border, and rebuild the replacement border. |

An arbitrary interior removal or permutation still falls back to a complete
rebuild. This conservative fallback is part of correctness, not a missing
fast path. `LS_OP_CLEAR_ROW` clears one lower-triangle border serially through
the existing bank write port, so the optimization does not infer a new port.

Primary RTL:

- `rtl/v2/control/sparse_loop_controller.v`
- `rtl/v2/solver/ls_matrix_service.v`

## 2. Dual sparse state and lazy dense writeback

The controller keeps the active solution as ordered `(index, coefficient)`
tuples. After an LS solve it clears only indices that left the support and
writes only the new support tuples. It no longer sweeps all `N` dense entries
for each refine operation. Dense scratchpad state remains coherent for the
existing consumers, so this is an architectural scheduling optimization and
does not change the algorithm.

The independent hardware Python model records sparse tuple writes and dropped
index clears in `ArchitectureStats` while preserving the frozen numeric
golden.

## 3. Phase-token pseudo-instruction scheduler

`phase_token_scheduler.v` centralizes phase-level handshakes that were
previously distributed through the service engine. Its compact pseudo-op
decode covers correlation, update, support selection, refine, LS, residual,
and prune phases. It owns the legal fusion/defer rules for:

- correlation -> top-K;
- post-update x -> top-K;
- post-refine support -> top-K; and
- deferred LS completion while a fused consumer is active.

The token also maintains narrow support, vector, and matrix version counters.
These counters are registered metadata for future dependency checks; the
current RTL does not place them on a wide arithmetic completion edge.

Primary RTL:

- `rtl/v2/control/phase_token_scheduler.v`
- `rtl/v2/solver/sparse_kernel_service_engine.v`

## 4. Exact hierarchical top-K for `N=1024`, `K=32`

The existing exact four-row top-K wavefront remains deterministic: larger
absolute score wins and the smaller index breaks a tie. Counter and sentinel
widths now represent all 32 retained entries without wrapping. The sparse
index width can be configured to 11 bits, and direct LFSR jump masks are
provided for 512 and 1024 columns.

The support service exposes 32 solution entries and a physically distinct
64-entry candidate path. The signed-off default remains `N=256`, `K<=16` so
the frozen golden is unchanged.

Evidence currently available:

- exact top-32 over 1024 streamed scores: unit simulation PASS;
- support capacity 32 and candidate capacity 64: unit simulation PASS;
- complete `cgra_top` with `IDX_W=11`, `SPARSE_MAX_N=1024`,
  `SPARSE_MAX_K=32`: elaboration/smoke simulation PASS.

This is not yet a claim of a routed N=1024/K=32 implementation or a complete
eight-algorithm K32 golden sweep. CoSaMP/SP candidate semantics beyond the
signed-off K16 contract remain outside the current end-to-end sign-off.

## 5. Shared block-4 Gram/LDLT border engine

Gram accumulation and LDLT border construction retain one shared four-row
datapath. Four target rows are issued as one block, each PE row owns a distinct
target, and the block drains through the existing ACC4 banking. The new delta
factor modes reuse this same block-4 border engine instead of instantiating a
second solver.

The scalable matrix address is now derived from `MAX_K`; it no longer embeds a
16x16 address layout. A one-entry ACC4 queue and the existing phase-tagged
MUL1/MUL2 overlap remain unchanged.

## Verification gates

The extensions are retained only if all applicable gates pass:

1. independent hardware golden check;
2. focused capacity/top-K/matrix unit tests;
3. K8: 45 PASS / 0 FAIL with per-algorithm cycles;
4. full supported sweep: 348 PASS / 0 FAIL, including the two documented K16
   skips;
5. default OOC timing `WNS >= +0.2 ns`; and
6. no unintended DSP/BRAM increase.

Current functional evidence (run IDs `unified5_k8_fixed` and
`unified5_remaining_fixed`):

- K8: 45 PASS / 0 FAIL;
- complete supported sweep: 348 PASS / 0 FAIL, including the two documented
  K16 skips;
- 62 per-algorithm cycle records: 1,321,345 total cycles;
- the comparable pre-extension working-tree runs totalled 1,429,084 cycles,
  so the net reduction is 107,739 cycles (7.54%);
- K8 SP: 97,995 -> 67,949 cycles (-30.66%);
- K8 CoSaMP: 109,280 -> 99,419 cycles (-9.02%).

The default routed timing/resource gate is still required before this becomes
a release checkpoint.
