# LS solve-setup trial report

Date: 2026-08-16

Baseline: shared forward-solve tail-completion checkpoint `d487050`.

## Objective

Profile the remaining LDLT factor-check/solve-setup bubbles and remove only a
controller-local bubble that keeps the signed-off architecture unchanged:

- exactly one LS matrix-service request active;
- PE0 remains the only arithmetic ingress;
- large arithmetic retains fixed PE0 -> PE1 -> PE2 -> PE3 row ownership;
- READ2 data and arithmetic latency remain unchanged.

The representative M64/N256/K8 profile showed that a new factor visits
`S_LDL_INIT` and then `S_LDL_DIAG_READ` before the first diagonal READ2.  The
three trials below targeted only this boundary.

## Results

| Trial | K8 correctness | K8 cycles | Delta | Total LUT | Delta LUT | FF | WNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline `d487050` | 45 PASS / 0 FAIL | 379662 | - | 123551 | - | 53423 | +0.605 ns |
| Completion-to-READ2 fast-start | 45 PASS / 0 FAIL | 379612 | -50 | 129950 | +6399 | 53533 | +0.594 ns |
| Final-RHS `S_LDL_INIT` bypass | 45 PASS / 0 FAIL | 379637 | -25 | 126862 | +3311 | 53323 | +0.447 ns |
| `S_LDL_INIT` as READ2 command | 45 PASS / 0 FAIL | 379637 | -25 | 126905 | +3354 | 53591 | +0.654 ns |

All trials passed OOC synthesis with zero timing failures, 24 RAMB36, and 71
DSP48.  None meets the resource-neutral objective.  Even the smallest change
costs 3311 LUT (+2.68%) for 25 clocks across the complete eight-algorithm K8
case (-0.0066%).  Consequently all three RTL variants are rejected and the
source is restored exactly to `d487050`.

## Per-algorithm K8 cycles

| Algorithm | Baseline | Fast-start | State-only variants |
| --- | ---: | ---: | ---: |
| OMP | 34470 | 34468 | 34469 |
| CoSaMP | 107216 | 107192 | 107204 |
| IHT | 28633 | 28633 | 28633 |
| HTP | 39611 | 39607 | 39609 |
| SP | 95851 | 95833 | 95842 |
| GP | 28633 | 28633 | 28633 |
| GOMP | 19575 | 19573 | 19574 |
| MP | 25673 | 25673 | 25673 |

The saved clocks equal the number of fresh-factor entries: 25 clocks for a
single-state collapse or 50 clocks when both setup and registered command
states are bypassed.  Exact/prefix factor reuse is unchanged.

## Reproduction artifacts

- Fast-start simulation: `logs/sim/v2/solve_first_diag_chain_k8_20260816`
- Fast-start synthesis: `logs/synth/v2/solve_first_diag_chain_ooc_20260816`
- State bypass simulation: `logs/sim/v2/solve_init_bypass_k8_20260816`
- State bypass synthesis: `logs/synth/v2/solve_init_bypass_ooc_20260816`
- Command-state merge simulation: `logs/sim/v2/solve_init_command_k8_20260816`
- Command-state merge synthesis: `logs/synth/v2/solve_init_command_ooc_20260816`

Raw generated artifacts remain ignored under `logs/` and `work/`.

## Decision and next target

Do not retry this first-diagonal solve-setup boundary.  The next investigation
may target factor-check only if it removes a state without adding next-response
seen-mask/fingerprint logic to the PE3 response path.  Otherwise retain the
current factor-check because its measured residency is too small to justify a
wide control cone.
