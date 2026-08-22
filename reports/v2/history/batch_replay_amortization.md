# Batch multi-signal factor amortization (v1: single-program replay)

This checkpoint adds the first cross-signal reuse capability: after a leader
OMP program finishes its K-iteration loop, the same program streams in B-1
additional measurement vectors with the shared sensing matrix and solves
each one on the **retained exact LDLT factor**.  Each follower replays
`SOP_REFINE_SPARSE`, which hits `FACTOR_REUSE_EXACT`: no correlation, no
top-K, no Gram accumulation, and no factorization — only the RHS rebuild,
forward/diagonal/backward solve, coefficient writeback, and residual update.

## Mechanism

- The class-7 DMA context word gains a 16-bit element-offset field
  (`ctx[31:16]`, decoded in `ctx_decoder.v`) that is added to the CSR DDR
  base (`cgra_top.v`).  One program can therefore load y_1..y_3 at offsets
  `b*M` and store x_0..x_3 at offsets `b*N` without host reprogramming.
  Legacy programs decode offset 0 and are unchanged.
- The batch program is: OMP leader loop -> store x_0 -> for b in 1..3:
  [load y_b -> REFINE_SPARSE (exact-hit replay) -> store x_b].
- The follower contract is a shared-support model: every signal is solved
  on the leader's final support with the leader's cached factor order.  This
  is the standard common-support (MMV-style) recovery model.
- `models/reference/hardware.py` gained `make_batch_signal` (follower
  y_b = Q16(Phi x_b) with x_b sparse from the case LFSR, seed b-derived;
  the frozen input file is untouched) and `batch_replay` (the exact-hit
  replay semantics on the leader factor).  The golden emits
  `hwgold_y_batch` and `hwgold_x_batch`; the C header emits
  `ksgold_y_batch`/`ksgold_x_batch`.

## Measured amortization (all 8 cases, bit-exact)

`BATCH_REPLAY_RESULT` records from `+CASE=n +BATCH_REPLAY=1` runs
(cycle counter includes the follower DMA y-in and x-out transfers):

| Case | M/N/K | Leader cycles | Per-follower cycles | Amortization | Batch checks |
|---|---|---:|---:|---:|---|
| 0 | 64/256/16 | 99,020 | 4,122 | 24.0x | 1280 PASS / 0 FAIL |
| 1 | 64/256/8 | 40,260 | 2,786 | 14.5x | 1280 PASS / 0 FAIL |
| 2 | 64/256/4 | 19,198 | 2,570 | 7.5x | 1280 PASS / 0 FAIL |
| 3 | 32/128/8 | 17,924 | 1,614 | 11.1x | 640 PASS / 0 FAIL |
| 4 | 32/128/4 | 8,046 | 1,366 | 5.9x | 640 PASS / 0 FAIL |
| 5 | 32/128/2 | 4,242 | 1,288 | 3.3x | 640 PASS / 0 FAIL |
| 6 | 16/64/4 | 4,006 | 764 | 5.2x | 320 PASS / 0 FAIL |
| 7 | 16/64/2 | 2,046 | 686 | 3.0x | 320 PASS / 0 FAIL |

For B=4 signals, effective throughput gain is 3.0x-3.3x over solving the
four signals as independent programs (case 1: 48,618 total cycles for four
solutions vs 4 x 40,260 = 161,040 independent).  The amortization ratio
scales with K because the leader's per-iteration correlation, top-K, Gram,
and factorization work is exactly the work each follower skips.

Every follower solution is checked bit-exact (tolerance 0) against the
replayed-factor golden; the canonical 348-check sweep is unchanged when the
plusarg is absent (33 + 7 x 45 = 348 PASS / 0 FAIL in
`logs/sim/v2/batch_replay_full_sweep`).

Fixing the DMA `addr_dim` field to its real position (`ctx[51:48]`, was
previously encoded at `ctx[31:28]` and ignored) also shortens every
canonical program's Y/R prologue loads from N to M words: M64/N256 programs
save 384 cycles (OMP K16 99,404 -> 99,020; K8 40,644 -> 40,260).  All 348
checks still pass bit-exact.

## Gates

| Gate | Result |
|---|---|
| Canonical full sweep (no plusarg) | 348 PASS / 0 FAIL |
| OOC synthesis WNS | +2.085 ns (TNS 0.000) |
| OOC LUT / FF | 128,914 / 52,403 (base 128,913 / 52,402: +1 LUT, +1 FF) |
| DSP / BRAM | 77 / 24, unchanged |

## Scope and limits

- v1 leader is OMP; the shared-support contract is exact for common-support
  batch workloads (multi-channel ECG, multi-antenna radar, video blocks).
  Divergent-support followers (CoSaMP/SP-style pruning per signal) are
  future work (factor-tree caching).
- IHT/GP/MP contain no LS phase and are out of the batch claim.
- The follower cost still includes the REFINE residual tail; skipping it on
  replay is a further cycle candidate.

## Reproducibility

- Batch runs: `logs/sim/v2/batch_replay_focus/case{0..7}_batch.log`
  (`xsim tb_batch_focus -runall -testplusarg "CASE=n" -testplusarg
  "BATCH_REPLAY=1"`).
- Canonical sweep: `logs/sim/v2/batch_replay_full_sweep` (no plusarg).
- OOC synthesis: `logs/synth/v2/batch_replay_ooc`.

Primary RTL: `rtl/v2/control/ctx_decoder.v`, `rtl/v2/top/cgra_top.v`.
Golden: `models/reference/hardware.py` (sole generator).
TB: `verification/v2/run1/tb_run1_k_sweep.v` (`BATCH_REPLAY` plusarg).
