# 8-Algorithm Validation Baseline

Date: 2026-06-20
Branch: codex/pe-dominant-ls-scratchpad
Commit: eb77bb4 Fix full support merge truncation for CoSaMP

## Status

The current RTL baseline satisfies the validation gates required before attempting the row-streaming PE refactor.

## Evidence

### Smoke small, case0

| Algorithm | TB | Result |
|---|---|---|
| OMP | tb_omp_smoke_case0 | 53 PASS, 0 FAIL |
| gOMP | tb_gomp_smoke_case0 | 56 PASS, 0 FAIL |
| CoSaMP | tb_cosamp_smoke_case0 | 53 PASS, 0 FAIL |
| SP | tb_sp_smoke_case0 | 53 PASS, 0 FAIL |
| IHT | tb_iht_smoke_case0 | 53 PASS, 0 FAIL |
| HTP | tb_htp_smoke_case0 | 53 PASS, 0 FAIL |
| GP | tb_gp_smoke_case0 | 53 PASS, 0 FAIL |
| MP | tb_mp_smoke_case0 | 53 PASS, 0 FAIL |

### Paper-core per-iteration exact

| Algorithm | Evidence |
|---|---|
| OMP | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| gOMP | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| CoSaMP | case0 318 PASS, case1 816 PASS, case2 1472 PASS, case3 1616 PASS; all 0 FAIL |
| SP | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| IHT | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| HTP | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| GP | case0/case1/case2/case3 per-iter exact: 0 FAIL |
| MP | case0/case1/case2/case3 per-iter exact: 0 FAIL |

### Large target

| Test | Result |
|---|---|
| OMP M64/N256/K16 | 338 PASS, 0 FAIL; 298,720 cycles |

### Synth constraints

| Top | LUT | FF | BRAM36 | DSP | WNS |
|---|---:|---:|---:|---:|---:|
| cgra_top OOC, xczu7ev-ffvc1156-2-e, 100 MHz | 86,885 | 23,554 | 16 | 102 | +2.393 ns |

## Notes

- CoSaMP case2/case3 were fixed by changing full-set sorted support merge to insert a smaller incoming candidate and drop the largest existing entry instead of skipping all candidates once depth reaches MAX_K.
- Row-streaming CORR trials that overloaded `sparse_rhs_product_bus` were reverted because they broke OMP smoke. The next implementation must use explicit CORR accumulator ports/valids.
