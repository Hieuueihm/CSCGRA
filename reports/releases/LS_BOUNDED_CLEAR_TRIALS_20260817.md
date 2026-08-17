# LS bounded-clear trial report

Date: 2026-08-17

Baseline: rejected ACC4 study checkpoint `f5cdbe3`, whose RTL is identical to
the signed-off LDLT border phase-overlap checkpoint `0ae1557`.

## Profile and objective

After rejecting two-column ACC4 banking, the next registered boundary outside
the ACC4 write path was `S_LS_CLEAR_WAIT`. At K8 it occupies 875 clocks across
the LS algorithms:

| Algorithm | Clear-wait clocks |
|---|---:|
| OMP | 35 |
| CoSaMP | 420 |
| HTP | 70 |
| SP | 315 |
| GOMP | 35 |

The matrix service always clears both 16-address row pages, even when K<=8 can
only address the low row page. Two bounded-clear forms were evaluated. Neither
changed ACC4 storage, PE0 ingress, four-row PE ownership, or LS arithmetic.

## Trial A: active-column bound

The controller passed active K with `OP_CLEAR`; the service cleared only active
columns and only the row pages needed by that K.

OMP K8 failed immediately:

- 5 PASS / 6 FAIL;
- final vector had six `X_MISM` entries and zero recovered nonzeros;
- no synthesis was run.

Some columns outside the current active support are still observed by
prefetch/factor-reuse behavior before masking. Clearing only the active-column
prefix therefore changed subsequent support/factor evolution. This schedule is
not safe and must not be retried.

Raw log: `logs/sim/v2/ls_bounded_clear_omp_k8_20260817`.

## Trial B: low-row-page bound

The conservative form still cleared all 16 columns. For K<=8 it skipped only
the high row page, which cannot be addressed; K>8 and standalone `row_a=0`
commands retained the full 32-address clear.

OMP K8 passed and reduced 33,920 -> 33,904 cycles (-16). All other profiled
state counts were identical except `S_LS_CLEAR_WAIT`, which fell from 35 to 19.
The expected all-algorithm K8 gain was only 400 clocks (about 0.107%), so OOC
was run before a full K8 regression.

OOC result:

| Metric | Baseline | Trial | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.472 ns | -0.378 ns |
| Total LUT | 121,302 | 127,128 | +5,826 (+4.80%) |
| Logic LUT | 119,152 | 124,979 | +5,827 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 5 | -1 |
| FF | 53,281 | 53,416 | +135 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

Timing passed, but LUT growth was roughly 45 times the projected K8 cycle
reduction percentage. The candidate was rejected without full K8/full-sweep
regression.

Raw artifacts:

- `logs/sim/v2/ls_page_clear_omp_k8_20260817`
- `logs/synth/v2/ls_page_clear_ooc_20260817`

## Decision

Both trials were removed. RTL is restored exactly to checkpoint `f5cdbe3`.
The signed-off baseline remains 1,315,336 full-sweep cycles, +0.850 ns WNS,
121,302 LUT, 53,281 FF, 24 RAMB36, and 71 DSP.

Do not revisit active-column or row-page-bounded clear. The remaining clear
residency is too small to justify adding active-K control to the LS service.
The next candidate must have materially greater registered residency and stay
outside both the ACC4 memory write path and completion-driven READ2 fast-start
paths already rejected in earlier studies.
