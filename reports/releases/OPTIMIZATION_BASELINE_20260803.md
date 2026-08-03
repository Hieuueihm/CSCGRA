# CSCGRA optimization baseline and continuation map

Date: 2026-08-03

## 1. Git checkpoint

- Repository: `https://github.com/Hieuueihm/CSCGRA.git`
- Signed-off branch: `codex/clean-repository-layout`
- Layout/sign-off commit before this report: `396f02a5e9a00ea5b5e2cbf4f19dbf85248bb0c3`
- Factor-reuse RTL checkpoint: `96305d1265a23859630093698bd99af9db2c8080`
- Pre-layout tag: `pre-repo-layout-741c0f2`
- Target: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`, 100 MHz.

Generated Vivado workspaces and raw simulation/synthesis logs remain under
ignored `work/` and `logs/`. Source, compact measurements, regression vectors,
scripts, and this report are tracked by Git.

## 2. Signed-off correctness scope

The canonical K-sweep covers eight cases:

| Case | M | N | K | Valid algorithms |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 64 | 256 | 16 | 6 |
| 1 | 64 | 256 | 8 | 8 |
| 2 | 64 | 256 | 4 | 8 |
| 3 | 32 | 128 | 8 | 8 |
| 4 | 32 | 128 | 4 | 8 |
| 5 | 32 | 128 | 2 | 8 |
| 6 | 16 | 64 | 4 | 8 |
| 7 | 16 | 64 | 2 | 8 |

Both RTL versions pass `348 PASS, 0 FAIL`. Each has 62 result rows and two
expected skip rows. CoSaMP and SP at M=64/N=256/K=16 are skipped because the
current implementation needs 2K candidate support. The refactor comparison
matched M, N, K, algorithm, iteration count, cycle, status, PC, and nonzero
count for all 62 rows in both versions.

## 3. Complete configured K-sweep cycle matrix

The same data is available in machine-readable form at
`reports/releases/optimization_baseline_k_sweep_20260803.csv`.

### RTL v1

| M | N | K | OMP | CoSaMP | IHT | HTP | SP | GP | GOMP | MP | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 256 | 16 | 254745 | skip | 177402 | 489254 | skip | 178218 | 135502 | 132113 | 1367234 |
| 64 | 256 | 8 | 87629 | 296144 | 83011 | 124299 | 275346 | 83419 | 47128 | 66969 | 1063945 |
| 64 | 256 | 4 | 40355 | 94500 | 41286 | 50604 | 70803 | 41490 | 22067 | 34397 | 395502 |
| 32 | 128 | 8 | 34509 | 209689 | 29457 | 61296 | 191148 | 29737 | 19413 | 20505 | 595754 |
| 32 | 128 | 4 | 13859 | 54715 | 14349 | 19947 | 34378 | 14489 | 8021 | 10717 | 170475 |
| 32 | 128 | 2 | 6837 | 13322 | 7437 | 8967 | 11413 | 7507 | 4146 | 5823 | 65452 |
| 16 | 64 | 4 | 5987 | 40943 | 5877 | 10000 | 22318 | 5985 | 3687 | 3869 | 98666 |
| 16 | 64 | 2 | 2741 | 7353 | 3007 | 3929 | 5609 | 3061 | 1787 | 2175 | 29662 |

### RTL v2 factor-reuse

| M | N | K | OMP | CoSaMP | IHT | HTP | SP | GP | GOMP | MP | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 256 | 16 | 110785 | skip | 105466 | 173848 | skip | 106282 | 60894 | 60145 | 617420 |
| 64 | 256 | 8 | 44751 | 155245 | 47107 | 61807 | 135110 | 47515 | 25102 | 30985 | 547622 |
| 64 | 256 | 4 | 21573 | 54193 | 23350 | 28600 | 40349 | 23554 | 12507 | 16405 | 220531 |
| 32 | 128 | 8 | 17999 | 102846 | 19665 | 28499 | 86241 | 19945 | 10699 | 10633 | 296527 |
| 32 | 128 | 4 | 8133 | 30259 | 9469 | 11958 | 19220 | 9609 | 5053 | 5781 | 99482 |
| 32 | 128 | 2 | 4403 | 9003 | 5001 | 6182 | 7325 | 5071 | 2913 | 3355 | 43253 |
| 16 | 64 | 4 | 3717 | 21191 | 4453 | 5949 | 11736 | 4561 | 2479 | 2389 | 56475 |
| 16 | 64 | 2 | 1971 | 4911 | 2299 | 2936 | 3665 | 2353 | 1402 | 1435 | 20972 |

### Aggregate v1 to v2 improvement

| Algorithm | V1 cycles | V2 cycles | Reduction | Improvement |
| --- | ---: | ---: | ---: | ---: |
| OMP | 446662 | 213332 | 233330 | 52.24% |
| CoSaMP | 716666 | 377648 | 339018 | 47.30% |
| IHT | 361826 | 216810 | 145016 | 40.08% |
| HTP | 768296 | 319779 | 448517 | 58.38% |
| SP | 611015 | 303646 | 307369 | 50.30% |
| GP | 363906 | 218890 | 145016 | 39.85% |
| GOMP | 241751 | 121049 | 120702 | 49.93% |
| MP | 276568 | 131128 | 145440 | 52.59% |
| **Total** | **3786690** | **1902282** | **1884408** | **49.76%** |

## 4. Representative K=8 maximum-iteration phase profile

This profile uses M=64/N=256/K=8 with each algorithm's representative maximum
iteration configuration. It is distinct from the configured K-sweep row above.

| Algorithm | Iter | Correlation | Gram/RHS | LDLT factor | Forward | Diagonal | Backward | Other | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 17656 | 10948 | 1776 | 670 | 84 | 376 | 10880 | 44751 |
| CoSaMP | 8 | 17656 | 31584 | 34853 | 7238 | 322 | 3604 | 27424 | 129395 |
| IHT | 16 | 35312 | 0 | 0 | 0 | 0 | 0 | 46464 | 92285 |
| HTP | 32 | 70624 | 29684 | 4935 | 6496 | 448 | 3456 | 101193 | 236277 |
| SP | 8 | 17656 | 31584 | 34853 | 7238 | 322 | 3604 | 27988 | 135093 |
| GP | 16 | 35312 | 0 | 0 | 0 | 0 | 0 | 46464 | 93186 |
| GOMP | 4 | 8828 | 5500 | 1240 | 394 | 42 | 220 | 6506 | 25103 |
| MP | 32 | 70624 | 0 | 0 | 0 | 0 | 0 | 43872 | 118465 |

The direct LS factor-reuse gain at this profile is 951907 to 874555 cycles,
or 77352 cycles (8.13%). HTP benefits most: 284081 to 236277 cycles (16.83%).
IHT, GP, and MP do not invoke the retained LS-refine path, so factor reuse does
not reduce their representative cycles.

## 5. Timing and resource evolution

All rows below except the explicitly rejected strict-ingress experiment meet
the 100 MHz timing target.

| Checkpoint | Total LUT | FF | BRAM36 | DSP48 | WNS | Full K-sweep cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| RTL v1 sign-off | 80318 | 25602 | 16 | 102 | +3.487 ns | 3786690 |
| Balanced radix-4 LS | 73303 | 24768 | 24 | 102 | +2.152 ns | 3389961 |
| Streamed block-8 LS | 75213 | 24897 | 24 | 105 | +2.977 ns | 3102464 |
| Hybrid correlation bypass | 74656 | 24819 | 24 | 105 | +2.745 ns | 2723672 |
| Correlation II=1 + four-row LDLT | 86107 | 27604 | 24 | 82 | +2.733 ns | 2332580 |
| Four-row READ4/WRITE4 | 94063 | 31102 | 24 | 71 | +2.486 ns | not separately archived |
| Factor reuse, current v2 | 96755 | 32558 | 24 | 71 | +3.001 ns | 1902282 |
| Strict PE0 vertical trial on `main@5469d79` | 108803 | 36928 | 24 | 71 | **-2.458 ns** | separate trial |

Current v2 also has 1536 LUTRAM, a worst data path of 6.989 ns, zero synthesis
errors, and zero critical warnings. Current v1 has 6464 LUTRAM and a worst data
path of 6.503 ns.

## 6. Optimizations present in the signed-off v2 source

### Shared architecture and control

- Context storage was moved from asynchronous distributed LUTRAM to synchronous
  BRAM; sequencer prefetch hides the extra address-issue cycle.
- Hierarchy attributes that blocked cross-PE optimization were removed.
- Mesh context remains enabled because disabling it caused OMP/CoSaMP golden
  mismatches.
- Support path-0 comparison is limited to the valid 16-entry support width;
  the selected 2K path remains 32 entries where required.
- Safe controller wait/setup bubbles were removed only after full regression.
  Lower mesh waits that changed final GP/MP data were reverted.

### Four-row PE participation

The current factor-reuse checkpoint assigns useful work to all four physical
rows for large operations:

| Operation | PE row 0 | PE row 1 | PE row 2 | PE row 3 |
| --- | --- | --- | --- | --- |
| Correlation | sample slot `m mod 4 = 0` | slot 1 | slot 2 | slot 3 |
| RHS | support lane `i mod 4 = 0` | lane 1 | lane 2 | lane 3 |
| Gram | column `j_base+0` | `j_base+1` | `j_base+2` | `j_base+3` |
| LDLT/solve | factor lane `i_base+0` | lane 1 | lane 2 | lane 3 |

- Correlation accepts one measurement row per clock after startup and stripes
  full-precision partial sums across the four rows.
- Signed 64x64 LDLT products are decomposed into sixteen 16x16 limbs and mapped
  onto existing PE multipliers instead of adding a 64x64 multiplier array.
- `LS_OP_READ4` and `LS_OP_WRITE4` move four consecutive matrix rows per
  service request. Eight deep row banks keep BRAM36 usage at 24.
- Gram/RHS accumulation captures a 4x8 PE batch and drains four Gram columns
  across the row banks.

### LS solver

- Gaussian elimination was replaced by regularized Cholesky LDLT.
- The shared restoring divider processes four quotient bits per clock, reducing
  the step count from 32 to 16 without adding a second divider.
- Sparse row updates use streamed block-8 transactions with one shared
  pipelined multiplier and a tail-lane mask.
- RHS, inverse-diagonal, forward, diagonal, and backward storage are reused or
  distributed to avoid large duplicated register arrays and muxes.
- Factor reuse is accepted only after M/N/seed/Phi scale/Phi kind and support
  validation. A fingerprint is only a reject filter; an exact entry scan
  prevents collisions from authorizing reuse.
- Exact support hits rebuild RHS but skip matrix clear, Gram, and LDLT.
- Prefix/set-extension hits preserve the old factor triangle and compute only
  the Cholesky border for newly appended support entries.

### Correlation and sparse updates

- The synchronous SPM word is cached and the next word prefetched so bank
  changes do not add a per-element correlation bubble.
- The retained hybrid bypass consumes the existing PE multiplier result in the
  wait state and keeps the extra latch only at 8-row SPM bank boundaries.
- Block-8 prune/threshold processes eight lanes per step with tail masking.

## 7. Important architecture gap: strict PE0-only ingress

The current signed-off factor-reuse branch uses all four rows, but it predates
the stronger rule that every controller/SPM/external operand must physically
enter at PE0 and then advance PE0 -> PE1 -> PE2 -> PE3 through registered links.
Therefore four-row participation is present, but strict physical provenance is
not yet signed off in this branch.

`main@5469d79` implements the strict rule with payload/tag assertions and passes
the available functional regressions. It cannot be used as the release
baseline because OOC WNS is -2.458 ns. The critical path ends at the LDLT
`wide_mul_result_q` capture. The user requirement is positive WNS; a modest
cycle increase is acceptable. Consequently, the next work must port the
strict-ingress behavior in timing-closed stages rather than merge it as-is.

## 8. Explored but not retained

- Disabling mesh context: failed OMP/CoSaMP correctness.
- Mesh wait below the safe bound: GP/MP final golden mismatch.
- Parallel LS block-4: reached 146 DSPs and was rejected for poor balance.
- Full 8x4 matrix banking: reached 138747 LUT and 5888 LUTRAM and was rejected.
- First-upper-read back-solve shortcut: small cycle gain but about 4798 extra
  LUT versus the balanced candidate.
- Shared top-K lane absolute expression: no measurable cycle/resource/timing
  improvement.
- Removing the second accumulation wait: CoSaMP golden mismatch.
- Combinational wide-result adder tree for strict ingress: only +0.063 ns WNS
  improvement while adding 5053 LUT and 6946 FF; rejected.
- QR LS solver: not implemented. Incremental QR may improve robustness on
  ill-conditioned support matrices, but rotations, square root/reciprocal work,
  and additional state make it a poor first choice for cycle/resource
  optimization while verified LDLT reuse is already effective.

## 9. Ordered continuation backlog

### P0: strict PE0 ingress with positive WNS

1. Start from the current factor-reuse sign-off, not from the timing-failing
   `main@5469d79` result.
2. Port registered provenance in stages: correlation/residual, then top-K and
   factor check, then the wide LDLT path.
3. Keep payload, valid, operation, owner-row, and transaction tag registered
   together for every PE0 -> PE1 -> PE2 -> PE3 hop.
4. Pipeline the wide LDLT issue/result/sign-correction boundary. Accept one or
   more added cycles to reach WNS >= 0 ns at 100 MHz.
5. Require provenance assertions, 348/0 K-sweep, 62/62 record comparison, and
   positive WNS before keeping each stage.

### P1: reduce fill/drain overhead without lower-row ingress

- Stream multiple tagged LDLT border products before draining; use a small
  in-order per-row partial-sum queue.
- Chain tagged residual block-8 transactions so a new block can enter PE0 each
  cycle and PE3 retires them in order.
- These target the measured fill/drain overhead while preserving a single PE0
  ingress.

### P2: reduce cycles outside LS

- Fuse correlation with the following vector update for IHT and GP. Their
  current full-sweep improvement is lower than LS-heavy algorithms and factor
  reuse does not help them.
- Overlap scan-direct work with correlation writeback where address timing is
  safe.
- Reduce writeback mesh wait only through tagged result forwarding, not by
  lowering a fixed wait count without provenance.

### P3: exact top-K and factor-check cost reduction

- Serialize/reuse each row's insertion comparator or use a safe PE3 threshold
  while preserving exact score tie-breaking and full per-row capacity.
- Add an ordered support signature precheck at PE0; on a mismatch or possible
  collision, retain the exact vertical entry scan.

### P4: optional QR study

Evaluate QR only as a separate robustness experiment. Compare fixed-point
error, cycles per support update, LUT/FF/DSP/BRAM, and WNS against the retained
LDLT factor-reuse baseline. Do not replace LDLT unless QR wins a stated
robustness requirement while keeping correctness and positive WNS.

## 10. Sign-off commands for the next optimization

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId next-opt-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\maintenance\compare_regression.ps1 `
  -BaselineLog .\logs\sim\v2\layout-full-v2 `
  -CurrentLogDirectory .\logs\sim\v2\next-opt-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top -RunId next-opt-synth
```

Every future release report should provide cycles per algorithm, not only one
aggregate number, and must include correctness, WNS, and resource totals.
