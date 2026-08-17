# LDLT border MUL1/MUL2 phase-overlap sign-off

Date: 2026-08-17

Branch: `codex/strict-pe0-timing`

Baseline: `a280326798b675ec1a9e1bd2942e0d1b749eb2ce`

## Retained architecture

The LDLT border scheduler now starts the in-order MUL2 stream when each
modulo-four scoreboard slot has retired its final MUL1 owner. A one-bit phase
tag travels with every token through PE0 -> PE1 -> PE2 -> PE3 and classifies
completion as either a MUL1 cache write or a MUL2 accumulator update.

The implementation retains the existing multiplier datapath and four-entry
scoreboard. It adds only phase/control metadata and a four-bit slot-ready mask.
All traffic still enters at PE0, the four PE rows retain their distinct target
row roles, and only one LS request can be active. No multiplier, DSP, BRAM, or
wide ACC4 payload FIFO was added.

## Trial history and alias protection

The first direct overlap reused the four scoreboard slots without an ownership
guard. It was rejected immediately after simulation detected MUL1 reference
mismatches: MUL2 tag 0 could overwrite the slot still owned by MUL1 tag 4.

A phase-separated eight-slot scoreboard then passed K8, but was rejected:
although it saved 2,789 K8 cycles, it added 3,104 LUT (+2.50%), so resource
growth exceeded the 0.74% cycle reduction.

The retained implementation preserves the compact four-slot scoreboard. A
slot becomes ready for MUL2 only when its final MUL1 owner completes. A
simulation-only 64x64 reference-product assertion checks phase ordering and
representative-row values, without affecting synthesized logic.

## Correctness and cycles

- K8: 45 PASS / 0 FAIL.
- Full K-sweep: 348 PASS / 0 FAIL, 62 measured records.
- The two K16 SP/CoSaMP cases remain the expected capacity skips.
- K8 total: 376,764 -> 375,362 (-1,402; -0.372%).
- Full total: 1,319,534 -> 1,315,336 (-4,198; -0.318%).
- K8 OMP: 33,966 -> 33,920 (-46).
- K16 OMP: 83,006 -> 82,728 (-278).

Full-sweep reductions by algorithm:

| Algorithm | Baseline | New | Saved |
|---|---:|---:|---:|
| OMP | 163,500 | 163,124 | 376 |
| CoSaMP | 269,597 | 267,729 | 1,868 |
| IHT | 125,244 | 125,244 | 0 |
| HTP | 209,348 | 208,952 | 396 |
| SP | 223,566 | 222,222 | 1,344 |
| GP | 125,244 | 125,244 | 0 |
| GOMP | 93,775 | 93,561 | 214 |
| MP | 109,260 | 109,260 | 0 |

The complete matrix is in
`reports/releases/ldlt_border_phase_overlap_k_sweep_20260817.csv`.

## Timing and resources

Out-of-context implementation at 100 MHz:

| Metric | Baseline | New | Delta |
|---|---:|---:|---:|
| WNS | +0.658 ns | +0.850 ns | +0.192 ns |
| Total LUT | 124,019 | 121,302 | -2,717 |
| Logic LUT | 121,871 | 119,152 | -2,719 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 4 | 6 | +2 |
| FF | 53,506 | 53,281 | -225 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

TNS is zero and there are no failing endpoints. The cycle reduction is
accompanied by lower LUT/FF use, WNS remains above +0.2 ns, and DSP/BRAM are
unchanged. The candidate therefore meets every retention criterion.

## Reproduction logs

- K8: `logs/sim/v2/ldlt_border_phase_slotmask_k8_20260817`
- Full sweep: `logs/sim/v2/ldlt_border_phase_slotmask_full_20260817`
- OOC: `logs/synth/v2/ldlt_border_phase_slotmask_ooc_20260817`

Raw simulation and implementation products remain ignored; the source,
cycle matrix, and this sign-off report are versioned.

## Next direction

Do not restore the phase-separated doubled scoreboard: its LUT cost has been
measured and rejected. If more LDLT-border overlap is needed, profile the
remaining dependency stalls first. The next controlled architectural study may
be two-column ACC4 drain using column banking; it must preserve registered
payload isolation and be accepted only after K8, full-sweep, resource, and WNS
comparison. A wide multi-entry ACC4 payload FIFO is still lower priority.
