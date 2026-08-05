# LS read-chain trial report

Date: 2026-08-06

Retained checkpoint: `cf949d6` (stable LS command chain).

## Decision

No RTL change from these trials is retained.  The signed-off checkpoint remains
the better stability/performance balance at 100 MHz:

- 348 PASS, 0 FAIL over K=2/4/8/16.
- 1,774,300 aggregate cycles.
- WNS +0.309 ns, TNS 0, zero failing endpoints.
- 113,628 LUT, 50,762 FF, 24 RAMB36, and 71 DSP48.

Each trial below kept exactly one LS matrix-service request active.  Large
multiply work still entered PE0 and moved through PE0 -> PE1 -> PE2 -> PE3,
with one result lane owned by each physical PE row.  All smoke regressions used
case 7 (M=16, N=64, K=2) and completed with 45 PASS / 0 FAIL.

## Measured trials

| Trial | K2 cycle delta | WNS | LUT | FF | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| LDLT diagonal-gather completion chaining | -60 | -0.299 ns | 112,763 | 50,477 | Reject: timing failure |
| Back-solve READ4 completion chaining | -21 | +0.134 ns | 114,924 | 50,455 | Reject: weak margin, +1,296 LUT |
| Direct LDLT divider initialization | -20 | +0.152 ns | 115,896 | 50,455 | Reject: weak margin, +2,268 LUT |
| Forward-solve READ2 completion chaining | -15 | +0.176 ns | 112,840 | 50,642 | Reject: margin loss exceeds tiny cycle gain |

The signed-off K2 reference is 19,690 cycles across the eight algorithms.

### Per-algorithm K2 cycles

| Algorithm | Stable reference | Diagonal gather | Back READ4 | Divider init | Forward READ2 |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 1,839 | 1,835 | 1,838 | 1,837 | 1,839 |
| CoSaMP | 4,642 | 4,606 | 4,631 | 4,632 | 4,630 |
| IHT | 2,159 | 2,159 | 2,159 | 2,159 | 2,159 |
| HTP | 2,810 | 2,806 | 2,808 | 2,808 | 2,810 |
| SP | 3,393 | 3,381 | 3,387 | 3,389 | 3,390 |
| GP | 2,213 | 2,213 | 2,213 | 2,213 | 2,213 |
| GOMP | 1,339 | 1,335 | 1,338 | 1,337 | 1,339 |
| MP | 1,295 | 1,295 | 1,295 | 1,295 | 1,295 |

## Forward-solve READ4 feasibility

The current matrix banking cannot implement the forward substitution read as a
single READ4 command.  Forward solve needs `L(i,j..j+3)`: four columns in one
row bank.  Existing READ4 returns `L(i..i+3,j)`: four consecutive row banks at
one column.  Changing this would require a transpose/replicated store or a new
multi-column memory path, which is not a low-risk command-chain optimization.

The measured forward trial therefore chained the existing READ2 operations
from `ls_done`.  It preserved the four-row multiply after the reads, but the
15-cycle K2 reduction did not justify reducing WNS margin from +0.309 ns to
+0.176 ns.

## Timing observation and next direction

All positive-WNS trials still ended on the residual
`write_idx -> residual_acc` path.  Completion-driven command/address selection
changes netlist placement enough to consume 0.133-0.175 ns of the preferred
margin even when the modified LS logic is not itself the reported critical
path.  Diagonal-gather chaining was worse and produced negative WNS.

Do not continue broadening the LS completion mux for single-digit or low
double-digit K2 savings.  The next checkpoint should first collect state
residency at K=8 and K=16, then target a datapath-local bubble with a larger
cycle share.  Suitable candidates are exact factor-check/top-K control or a
timing-isolated residual control stage; any change must preserve strict PE0
ingress, participation of all four PE rows, full K-sweep correctness, and
positive WNS with a preferred margin of at least +0.2 ns.

Raw simulation and synthesis artifacts are retained under ignored `logs/` and
`work/` directories and are intentionally not committed.
