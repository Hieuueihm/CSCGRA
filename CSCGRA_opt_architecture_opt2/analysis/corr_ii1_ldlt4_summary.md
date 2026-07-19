# Correlation II=1 and four-row LDLT summary

## Retained architecture

The correlation service now accepts one measurement row per clock after its
startup latch.  The complete synchronous-SPM residual word is cached and the
next word is prefetched while the current word is streaming, so changing SPM
banks does not add a per-element bubble.

Correlation work is striped across all four physical PE rows.  Row `r` owns
measurement indices whose stream slot is `r mod 4`, maintains a full-precision
partial sum, and contributes to the signed four-row reduction at writeback.
The request-edge clear accounts for the PE control register and prevents stale
state in the first column block without inserting a stream cycle.

The LS solver is changed from Gaussian elimination to regularized LDLT:

- diagonal factor terms use four PE rows for four `p` terms;
- off-diagonal factor updates use four PE rows for four target `i` rows;
- forward and backward triangular products use four `j` terms per batch;
- the diagonal solve processes four solution elements per batch;
- a signed 64x64 product is decomposed into sixteen unsigned 16x16 products,
  issued over the eight PE columns in two clocks, then reconstructed exactly;
- no separate 64x64 multiplier array is instantiated;
- `rhs` is reused for `z`, and `ge_x` is reused successively for `inv(D)`, `w`,
  and `x`, removing three redundant `MAX_K x 64` register arrays.

## Representative M=64, N=256, K=8 cycles

| Algorithm | Iterations | d75243b | Current | Delta | Improvement |
|---|---:|---:|---:|---:|---:|
| OMP | 8 | 65,045 | 47,447 | -17,598 | 27.06% |
| CoSaMP | 8 | 183,174 | 173,712 | -9,462 | 5.17% |
| IHT | 16 | 127,613 | 92,288 | -35,325 | 27.68% |
| HTP | 32 | 374,321 | 305,201 | -69,120 | 18.47% |
| SP | 8 | 188,308 | 178,919 | -9,389 | 4.99% |
| GP | 16 | 128,514 | 93,186 | -35,328 | 27.49% |
| GOMP | 4 | 35,453 | 26,677 | -8,776 | 24.75% |
| MP | 32 | 189,121 | 118,465 | -70,656 | 37.36% |
| **Total** | | **1,291,549** | **1,035,895** | **-255,654** | **19.79%** |

All eight final-golden checks pass.  Checkpoints are reported separately in
the simulator logs; for example HTP at 8 iterations is 77,657 cycles and its
32-iteration final result is 305,201 cycles.

## Full K sweep

The unchanged golden sweep covers 62 valid `(M,N,K,algorithm)` entries with
K=2, 4, 8, and 16.  Every entry passes.  Case 0 (K=16) reports `33 PASS, 0
FAIL`; the other seven cases each report `45 PASS, 0 FAIL`.

| Algorithm | Count | d75243b | Current | Delta | Improvement |
|---|---:|---:|---:|---:|---:|
| OMP | 8 | 322,706 | 256,601 | -66,105 | 20.48% |
| CoSaMP | 7 | 484,864 | 471,431 | -13,433 | 2.77% |
| IHT | 8 | 286,746 | 216,810 | -69,936 | 24.39% |
| HTP | 8 | 547,200 | 495,828 | -51,372 | 9.39% |
| SP | 7 | 415,583 | 397,866 | -17,717 | 4.26% |
| GP | 8 | 288,826 | 218,890 | -69,936 | 24.21% |
| GOMP | 8 | 176,683 | 144,026 | -32,657 | 18.48% |
| MP | 8 | 201,064 | 131,128 | -69,936 | 34.78% |
| **Total** | **62** | **2,723,672** | **2,332,580** | **-391,092** | **14.36%** |

## OOC synthesis at 100 MHz

Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.  Synthesis completes with
zero errors and zero critical warnings; all timing constraints are met.  The
critical path remains the shared radix-4 divider, not correlation or the PE
wide-multiply reconstruction.

| Metric | d75243b | Current | Delta |
|---|---:|---:|---:|
| Total LUT | 74,656 | 86,107 | +11,451 (+15.34%) |
| Logic LUT | 72,864 | 84,315 | +11,451 (+15.72%) |
| LUTRAM | 1,792 | 1,792 | 0 |
| FF | 24,819 | 27,604 | +2,785 (+11.22%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 105 | 82 | -23 (-21.90%) |
| WNS | +2.745 ns | +2.733 ns | -0.012 ns |

The trade is retained: the design spends LUT/FF on exact PE-limb scheduling
and LDLT state while removing 23 DSPs, preserving BRAM and 100 MHz timing, and
reducing the full-sweep cycle count by 14.36%.

## QR assessment

QR is numerically preferable when the selected sensing matrix is nearly rank
deficient because it avoids explicitly solving the normal equations and their
squared condition number.  It is not expected to reduce cycles on the current
architecture by simply replacing LDLT: the existing dataflow already produces
the Gram matrix and RHS, while direct QR would require streaming/storing MxK
data plus norm, square-root/reciprocal, and rotation updates.

For K <= 16, four-row LDLT remains the default cycle/resource choice.  A useful
future QR experiment is an optional four-row systolic Givens path with one
shared pipelined CORDIC/reciprocal unit, enabled only for a small/negative LDLT
pivot or a robustness mode.  QR should replace the default only after the same
62-entry sweep and OOC resource/timing comparison demonstrate a net benefit.

## Reproducibility

- Four-row 64x64 self-test: `WIDE_MUL_4ROW PASS cycles=3`.
- OMP correlation role counter: row0/row1/row2/row3 =
  `4096/4096/4096/4096` accepted samples.
- K=8 logs: `runs/opt2/corr_4row_ii1_smoke/` (local, ignored).
- K sweep logs: `runs/opt2/ldlt_4row_ksweep/` (local, ignored).
- Synthesis reports: `runs/opt2/synth_corr_ii1_ldlt4_cgra_top/` (local, ignored).
- Synthesis script: `scripts/run_synth_corr_ii1_ldlt4_cgra_top.tcl`.
