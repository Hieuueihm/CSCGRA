# ACC4 two-column drain banking trial

Date: 2026-08-17

Baseline: LDLT border phase-overlap checkpoint `0ae1557`.

## Objective

The trial attempted to drain ACC4 Gram columns 0/1 and 2/3 in two clocks,
instead of one column per clock. The controller could then remove its remaining
one-clock guard because registered ACC4 commands are produced no faster than
once every three clocks.

Strict PE0 ingress, PE0 -> PE1 -> PE2 -> PE3 propagation, the fixed four-row
Gram ownership, the registered service interface, and one active LS request
were preserved. No source-side ACC4 FIFO entry was added.

## Residency profile

The signed-off K8 profile showed 4,992 removable guard clocks:

| Algorithm | ACC4 issues | Gram-wait cycles | Removable guard |
|---|---:|---:|---:|
| OMP | 768 | 1,024 | 256 |
| CoSaMP | 3,584 | 6,144 | 2,560 |
| HTP | 256 | 384 | 128 |
| SP | 2,944 | 4,864 | 1,920 |
| GOMP | 384 | 512 | 128 |

IHT, GP, and MP do not use this Gram/LS path and were expected to remain
cycle-identical.

## Trial A: direct column-parity banks

Each of the eight row banks was split by column parity. Two independent bank
writes updated adjacent Gram columns each clock. The matrix address removed the
column parity bit, and READ2/READ4 selected the appropriate parity bank.

Correctness and cycles:

- K8: 45 PASS / 0 FAIL.
- K8 total: 375,362 -> 369,878 (-5,484; -1.461%).
- OMP: 33,920 -> 33,632 (-288).
- CoSaMP: 105,504 -> 102,720 (-2,784).
- HTP: 39,453 -> 39,289 (-164).
- SP: 94,251 -> 92,155 (-2,096).
- GOMP: 19,295 -> 19,143 (-152).
- IHT, GP, and MP were cycle-identical.

The reduction is 492 clocks larger than the guard profile because both parity
banks clear in parallel, shortening matrix clear intervals as well.

OOC result:

| Metric | Baseline | Trial | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.621 ns | -0.229 ns |
| Total LUT | 121,302 | 143,154 | +21,852 (+18.01%) |
| Logic LUT | 119,152 | 139,469 | +20,317 |
| LUTRAM | 2,144 | 3,680 | +1,536 |
| SRL | 6 | 5 | -1 |
| FF | 53,281 | 53,287 | +6 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 75 | +4 |

Timing still passed, but LUT growth was more than twelve times the K8 cycle
reduction percentage and DSP increased. The trial was rejected without a full
K-sweep.

## Trial B: packed adjacent-column word

A second implementation kept eight row banks and packed two adjacent 56-bit
columns into one 112-bit word. OMP K8 remained correct and cycle-identical to
Trial A at 33,632 clocks.

Vivado could not retain the distributed-RAM inference when two independently
enabled 56-bit partial writes targeted the same 112-bit word. RTL optimization
split the LS memory/update path into very large logic partitions, so the OOC
run was stopped before final reporting. This form cannot meet the resource
criterion and was also rejected.

## Decision and reproduction artifacts

Both implementations were removed. RTL is restored exactly to checkpoint
`0ae1557`; the signed-off baseline remains 1,315,336 full-sweep cycles,
+0.850 ns WNS, 121,302 LUT, 53,281 FF, 24 RAMB36, and 71 DSP.

Ignored raw artifacts:

- `logs/sim/v2/acc4_colbank2_omp_k8_20260817`
- `logs/sim/v2/acc4_colbank2_k8_20260817`
- `logs/synth/v2/acc4_colbank2_ooc_20260817`
- `logs/sim/v2/acc4_pairword_omp_k8_20260817`
- `logs/synth/v2/acc4_pairword_ooc_20260817` (intentionally interrupted)

Do not retry two-column ACC4 drain using ordinary inferred distributed RAM.
It requires either duplicated write banks/adders or partial-word writes that
destroy RAM inference. A future revisit would need an explicit technology
memory primitive or permission to spend an additional true-dual-port BRAM;
neither matches the current no-BRAM/no-DSP-growth criteria.
