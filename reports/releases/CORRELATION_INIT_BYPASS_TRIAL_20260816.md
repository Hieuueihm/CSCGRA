# Correlation INIT bypass trial report

Date: 2026-08-16

Baseline: checkpoint `9306d2c`, with RTL behavior identical to the signed-off
`d487050` checkpoint.

## Objective

State profiling at M64/N256/K8 showed 1,860 clocks in `S_CORR_INIT`.  This
state runs once between consecutive eight-column correlation blocks and only
copies existing LFSR, row, residual-word, and accumulator state.  The trial
removed this bubble while preserving:

- strict PE0 arithmetic ingress;
- registered PE0 -> PE1 -> PE2 -> PE3 propagation;
- round-robin correlation ownership across all four PE rows;
- the existing one-row-per-clock `S_CORR_ACC` stream; and
- the `S_CORR_SCAN` synchronous-SPM settle clock.

## Implementations and results

| Implementation | K8 correctness | K8 cycles | Total LUT | Delta LUT | FF | WNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 45 PASS / 0 FAIL | 379662 | 123551 | - | 53423 | +0.605 ns |
| Direct per-branch setup | 45 PASS / 0 FAIL | 377802 | 131176 | +7625 (+6.17%) | 53374 | +0.391 ns |
| Shared post-case setup | 45 PASS / 0 FAIL | 377802 | 133713 | +10162 (+8.23%) | 53524 | +0.378 ns |

Both candidates removed exactly 1,860 K8 clocks (-0.49%).  OMP, CoSaMP,
IHT, HTP, SP, GP, and MP each saved 248 clocks; four-iteration GOMP saved 124.
No arithmetic, factor-check, top-K, residual, Gram, or LDLT state changed.

Both OOC runs passed timing with zero failing endpoints, 24 RAMB36, and 71
DSP48.  However, moving the LFSR/row setup onto the block-completion boundary
expanded wide register mux and XOR control cones.  Sharing the source-level
setup did not make Vivado share the mapped logic and increased LUT further.

## Decision

Reject both implementations.  A 0.49% cycle gain does not justify 6.17% to
8.23% additional LUT.  RTL was restored exactly to checkpoint `9306d2c`.
Do not revisit `S_CORR_INIT` bypass unless the LFSR architecture itself changes
and provides a registered next-block state without adding a new wide mux cone.

## Reproduction artifacts

- Direct K8 profile: `logs/sim/v2/corr_init_bypass_k8_20260816`
- Direct OOC: `logs/synth/v2/corr_init_bypass_ooc_20260816`
- Shared K8 profile: `logs/sim/v2/corr_init_shared_k8_20260816`
- Shared OOC: `logs/synth/v2/corr_init_shared_ooc_20260816`

Raw generated logs remain ignored under `logs/` and `work/`.
