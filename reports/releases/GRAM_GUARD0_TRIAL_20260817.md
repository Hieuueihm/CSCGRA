# Gram ACC4 zero-guard trial report

Date: 2026-08-17

Baseline: documentation checkpoint `417bfa5`, with RTL behavior identical to
the signed-off `d487050` checkpoint.

## Objective

The retained `OP_ACC4` one-entry queue accepts a pending Gram transaction while
the active four-column transaction drains.  This trial changed only
`gram_drain_wait_q` from one to zero to test whether the registered
`S_GRAM_PE_WAIT` boundary alone was sufficient.  No register, mux, arithmetic
unit, or LS request slot was added.

Strict PE0 ingress, PE0 -> PE1 -> PE2 -> PE3 propagation, and the fixed Gram
role of physical row `r` owning column `acc_j + r` were unchanged.

## Result

The trial was stopped during the M64/N256/K8 smoke run after CoSaMP produced
multiple `X_MISM` failures.  OMP completed correctly and fell from 34,470 to
33,702 cycles (-768); its `S_GRAM_ACC_WAIT` residency fell from 1,536 to 768.
CoSaMP fell from 107,216 to 103,608 cycles, but its Gram request was captured
before the next four-row PE product was stable and the final x vector was
incorrect.

The queue itself can accept an early pending request, but that does not make
the producer payload valid one clock earlier.  The retained guard is therefore
a required registered PE-product settle interval, not a removable controller
bubble.

## Decision

Reject the trial immediately on correctness.  No synthesis or full K-sweep is
needed for a functionally invalid candidate.  RTL was restored exactly to
checkpoint `417bfa5` behavior.

Do not retry `gram_drain_wait_q = 0` unless a new registered ACC4 producer
payload is introduced.  Such a payload is wide and would require an explicit
resource/timing trade-off rather than qualifying as a resource-neutral change.

The remaining residual and top-K profile states are active work or producer
waits: residual INIT/WAIT performs preload and pipeline fill/drain, while top-K
CAPTURE waits for correlation and ISSUE emits real PE0 tokens.  They should not
be collapsed by moving residual sums or LFSR generation onto completion edges.

## Reproduction artifact

- Interrupted K8 profile: `logs/sim/v2/gram_guard0_k8_20260817`

Raw generated logs remain ignored under `logs/` and `work/`.
