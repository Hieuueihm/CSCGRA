# Wide-multiplier registered-stage trial

Date: 2026-08-17

Baseline: checkpoint `d4a3bfd`, with the signed-off K8 total of 375,362
cycles, OOC WNS of +0.850 ns, 121,302 LUT, 53,281 FF, 24 RAMB36, and 71 DSP.

## Profile

The K-sweep testbench now records the internal `wide_mul_state_q` residency in
addition to the controller, top-K, support, and uop profiles.  A baseline K8
run passed at 45 PASS / 0 FAIL.

The divider was not selected.  Its 5,248 K8 clocks in the divide-step state are
all active arithmetic clocks: each performs four restoring-division steps.
Removing a registered bubble is therefore not possible, while increasing the
radix would deepen the subtract/select path and put WNS at risk.

The non-vertical wide-multiply FINAL stage had 3,096 K8 completion
opportunities.  They were distributed as follows:

| Algorithm | Completion opportunities |
|---|---:|
| OMP | 100 |
| CoSaMP | 1,440 |
| IHT | 0 |
| HTP | 216 |
| SP | 1,274 |
| GP | 0 |
| GOMP | 66 |
| MP | 0 |
| **Total** | **3,096** |

## Trial: fuse non-vertical COMMIT and FINAL

For non-vertical operations, the trial committed the four final products and
asserted done directly in `WIDE_MUL_COMMIT`.  It reused the existing four-row
multiplier datapath and did not add a multiplier.  Each physical PE row still
owned one 64x64 product.  The vertical path, including strict
PE0 -> PE1 -> PE2 -> PE3 propagation, was unchanged.  Memory interfaces and
the single-active-LS-request rule were also unchanged.

K8 passed at 45 PASS / 0 FAIL:

| Algorithm | Baseline | Trial | Delta |
|---|---:|---:|---:|
| OMP | 33,920 | 33,820 | -100 |
| CoSaMP | 105,504 | 104,064 | -1,440 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,453 | 39,237 | -216 |
| SP | 94,251 | 92,977 | -1,274 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,295 | 19,229 | -66 |
| MP | 25,673 | 25,673 | 0 |
| **K8 total** | **375,362** | **372,266** | **-3,096 (-0.825%)** |

The cycle reduction exactly matched the profiled completion opportunities, so
the trial did not merely move residency into another controller state.

OOC result:

| Metric | Baseline | Trial | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.205 ns | -0.645 ns |
| Total LUT | 121,302 | 128,228 | +6,926 (+5.71%) |
| Logic LUT | 119,152 | 126,078 | +6,926 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 6 | 0 |
| FF | 53,281 | 53,635 | +354 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

Raw artifacts:

- `logs/sim/v2/wide_internal_baseline_k8_20260817`
- `logs/sim/v2/wide_nonvertical_commit_fuse_k8_20260817`
- `logs/synth/v2/wide_nonvertical_commit_fuse_ooc_20260817`

## Decision

The trial was rejected.  It technically met the +0.2 ns timing floor and kept
DSP/BRAM unchanged, but the 5.71% LUT increase was 6.9 times the 0.825% K8
cycle reduction.  The fused final adder/sign logic also consumed nearly all of
the signed-off timing margin.  A full K-sweep was intentionally not run after
the OOC resource gate failed.  All RTL was restored exactly to checkpoint
`d4a3bfd`; only the verification-only internal profiler is retained.

Do not retry non-vertical COMMIT-to-FINAL fusion or increase divider radix.
The next candidate should target a high-residency boundary whose registered
payload is already narrow and local.  It must not feed completion back into
READ4, widen a memory port, or place wide arithmetic on a completion edge.
