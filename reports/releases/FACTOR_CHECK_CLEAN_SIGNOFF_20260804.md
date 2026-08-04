# Exact factor-check early-reject and residual cleanup sign-off

Date: 2026-08-04

Baseline: tagged residual block-8 checkpoint `e72458c`.

## Result

The exact support scan is still mandatory for every possible factor-reuse
candidate.  It is now bypassed only when reuse is already impossible before
the scan starts: the sensing configuration differs, the requested support is
smaller than the cached factor, or the effective request is empty.  The DONE
path already copies the requested support on a miss, so the bypass changes no
reuse decision and does not weaken the exact collision check.

The unreachable pre-wavefront residual states and their 512-bit product hold
register were also removed.  State numbers for all live states were preserved.
This makes synthesis deterministic enough to remove the obsolete datapath and
reduces area without changing the tagged PE0 -> PE1 -> PE2 -> PE3 residual
flow.

| Metric | Residual chain | Factor-check clean | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1904934 | 1904294 | -640 (-0.034%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.249 ns | +0.200 ns | -0.049 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 105383 | 102261 | -3122 |
| Logic LUT / LUTRAM | 103846 / 1536 | 100724 / 1536 | -3122 / 0 |
| FF | 39884 | 39455 | -429 |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

Synthesis completed with zero errors and zero critical warnings.

## Per-algorithm aggregate cycles

| Algorithm | Residual chain | Factor-check clean | Delta |
| --- | ---: | ---: | ---: |
| OMP | 209424 | 209384 | -40 |
| CoSaMP | 410164 | 409852 | -312 |
| IHT | 202206 | 202206 | 0 |
| HTP | 317991 | 317991 | 0 |
| SP | 323057 | 322805 | -252 |
| GP | 204286 | 204286 | 0 |
| GOMP | 119234 | 119198 | -36 |
| MP | 118572 | 118572 | 0 |

The complete case matrix is in
`reports/releases/factor_check_clean_k_sweep_20260804.csv`.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\sim\run_regression.ps1 -RtlVersion v2 `
  -RunId factor-clean-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId factor-clean-synth
```

Raw generated artifacts remain in ignored `logs/` and `work/`.  The attempted
eight-lane top-K eligibility mask was rejected because it replicated support
comparators and increased area; exact top-K behavior remains unchanged.
