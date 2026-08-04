# Tagged LDLT border-stream sign-off

Date: 2026-08-04

Baseline: exact factor-check/dead residual cleanup checkpoint `63c2b97`.

## Architecture

The LDLT border update no longer performs one complete wide multiply fill and
drain for every pivot `p`.  For each four-row target block it now:

1. preloads `L(i+r,p)` and the common `L(k,p)` operand into whole-word caches;
2. streams all first products `L(i+r,p)*L(k,p)` at one 64x64 transaction every
   two clocks;
3. retires each transaction by tag and stores its exact 64-bit intermediate;
4. streams the dependent second products against `D(p)` at the same rate;
5. performs the unchanged final inverse-D multiply and four-lane write.

Every transaction consists of two 16x16 limb tokens.  Only PE0 receives the
controller operands.  Valid, tag, part, sign, and operand bundles advance over
registered PE0 -> PE1 -> PE2 -> PE3 links; row `r` owns target lane `i+r`.
Products are registered before the 128-bit limb reduction, and a four-slot
scoreboard prevents transactions in flight from overwriting one another.

MUL1 and MUL2 remain separate passes, so the LDLT data dependency and fixed-
point arithmetic are unchanged.  QR is not present in this datapath.

## Sign-off result

| Metric | Factor-check clean | LDLT border stream | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1904294 | 1771732 | -132562 (-6.96%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.200 ns | +0.018 ns | -0.182 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 102261 | 118199 | +15938 |
| Logic LUT / LUTRAM | 100724 / 1536 | 116659 / 1536 | +15935 / 0 |
| FF | 39455 | 53554 | +14099 |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The design meets the 100 MHz out-of-context constraint with zero errors and
zero critical warnings.  The resource increase is the cost of the tagged
preload caches, product capture, four in-flight scoreboards, and exact 128-bit
retirement.  A direct per-row retirement experiment used less state but was
rejected after numerical mismatches; it is not part of this checkpoint.

## Per-algorithm aggregate cycles

| Algorithm | Factor-check clean | LDLT border stream | Delta |
| --- | ---: | ---: | ---: |
| OMP | 209384 | 199256 | -10128 |
| CoSaMP | 409852 | 349626 | -60226 |
| IHT | 202206 | 202206 | 0 |
| HTP | 317991 | 305177 | -12814 |
| SP | 322805 | 279137 | -43668 |
| GP | 204286 | 204286 | 0 |
| GOMP | 119198 | 113472 | -5726 |
| MP | 118572 | 118572 | 0 |

The complete case matrix is in
`reports/releases/ldlt_border_stream_k_sweep_20260804.csv`.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\sim\run_regression.ps1 -RtlVersion v2 `
  -RunId ldlt-border-stream-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId ldlt-border-ram-scoreboard-synth
```

Raw generated artifacts remain under ignored `logs/` and `work/` directories.
