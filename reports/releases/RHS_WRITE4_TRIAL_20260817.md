# RHS_WRITE4 trial report

Date: 2026-08-17

Baseline: documentation checkpoint `a6c0b8b`, whose RTL is identical to the
signed-off LDLT border phase-overlap checkpoint `0ae1557`.

## Objective and implementation

The trial replaced four serialized `OP_RHS_WRITE` commands with one registered
`OP_RHS_WRITE4` command. The controller reused the low 256 bits of the existing
registered `rhs4_product_q` hold and muxed them into the low four words of the
existing `lane_add4` payload. The matrix service wrote the four valid RHS words
in one request.

The trial did not alter ACC4 storage or arithmetic, did not add multipliers or
memory primitives, and preserved the one-active-LS-request rule. It also did
not change strict PE0 ingress or the PE0 -> PE1 -> PE2 -> PE3 dataflow used by
the large PE operations.

## Correctness and cycle result

OMP K8 profiling passed at 5 PASS / 0 FAIL. The complete K8 suite then passed
at 45 PASS / 0 FAIL.

| Algorithm | Baseline cycles | RHS_WRITE4 cycles | Delta |
|---|---:|---:|---:|
| OMP | 33,920 | 33,848 | -72 |
| CoSaMP | 105,504 | 105,072 | -432 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,453 | 39,309 | -144 |
| SP | 94,251 | 93,837 | -414 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,295 | 19,253 | -42 |
| MP | 25,673 | 25,673 | 0 |
| **K8 total** | **375,362** | **374,258** | **-1,104 (-0.294%)** |

For OMP K8, `S_RHS_INIT_WAIT` fell from 116 to 44 clocks. All other profiled
state counts were unchanged. The gain therefore came from the intended RHS
command residency and did not move work into another controller state.

Raw simulation artifacts:

- `logs/sim/v2/rhs_write4_omp_k8_20260817`
- `logs/sim/v2/rhs_write4_k8_20260817`

## OOC result

| Metric | Baseline | RHS_WRITE4 | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.501 ns | -0.349 ns |
| Total LUT | 121,302 | 133,109 | +11,807 (+9.73%) |
| Logic LUT | 119,152 | 130,959 | +11,807 (+9.91%) |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 6 | 0 |
| FF | 53,281 | 53,613 | +332 (+0.62%) |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

Timing passed the +0.2 ns requirement and DSP/BRAM did not grow. However, the
four independently enabled RHS writes converted a narrow serialized memory
port into a costly multi-write structure. The 9.73% LUT increase is more than
33 times the 0.294% K8 cycle reduction.

Raw synthesis artifacts:
`logs/synth/v2/rhs_write4_ooc_20260817`.

## Decision

RHS_WRITE4 is rejected. A full K-sweep was intentionally not run because the
candidate already failed the agreed resource-versus-cycle gate after passing
K8 correctness and OOC timing. All RTL changes were removed; the retained
source is exactly the signed-off baseline behavior.

Do not retry RHS_WRITE4 using four ordinary RTL writes to `rhs_mem`. A future
wide RHS path would need explicitly banked/duplicated storage or a suitable
multi-port primitive, which conflicts with the current no-BRAM-growth and
resource-neutral priorities. The next study should target a high-residency
controller/datapath boundary without widening an inferred memory write port.
