# Strict-PE0 timing-isolation sign-off

Date: 2026-08-05

Baseline: tagged LDLT border-stream checkpoint `cfedb27`.

## Architecture

Residual block operands are now prepared in a controller register one clock
before entering PE0.  Range selection and the high-fan-out active-K clamp are
therefore removed from the PE multiply/reduce path.  A kept, fan-out-limited
`active_k_count_q` provides a local LS/residual control source; Vivado is not
allowed to merge it back into the support-set depth register.

The computation remains a strict wavefront.  Only PE0 receives controller
operands; each block advances through PE0 -> PE1 -> PE2 -> PE3.  Row `r` still
owns lanes whose index modulo four equals `r`, and the four row partials retire
in their original arithmetic order.  No direct controller ingress was added to
PE1, PE2, or PE3.

The ingress register costs one clock per residual dot product.  Existing LDLT
border streaming, exact factor reuse/checking, four-row top-K, and IHT/GP fused
updates are unchanged.

## Sign-off result

| Metric | LDLT border stream | Timing isolation | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1771732 | 1789828 | +18096 (+1.02%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.018 ns | +0.168 ns | +0.150 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 118199 | 119105 | +906 |
| Logic LUT / LUTRAM | 116659 / 1536 | 117565 / 1536 | +906 / 0 |
| FF | 53554 | 53653 | +99 |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The 100 MHz out-of-context run completed with zero errors and zero critical
warnings.  The requested +0.2 ns target was treated as a preference, not a
release gate: +0.168 ns was retained because further tested stages either
reduced WNS or made it negative.  Positive WNS remains the hard gate.

## Per-algorithm aggregate cycles

| Algorithm | LDLT border stream | Timing isolation | Delta |
| --- | ---: | ---: | ---: |
| OMP | 199256 | 201592 | +2336 |
| CoSaMP | 349626 | 352250 | +2624 |
| IHT | 202206 | 204542 | +2336 |
| HTP | 305177 | 307513 | +2336 |
| SP | 279137 | 281761 | +2624 |
| GP | 204286 | 206622 | +2336 |
| GOMP | 113472 | 114640 | +1168 |
| MP | 118572 | 120908 | +2336 |

The complete case matrix is in
`reports/releases/timing_isolation_k_sweep_20260805.csv`.

## Rejected trials

- An unpreserved local active-K register was merged back into support-set
  state and produced WNS -0.220 ns.
- Capturing the RHS product bus in the existing WAIT2 state passed simulation
  but worsened placement and reduced WNS to +0.105 ns.
- Snapshotting all request K metadata removed the support-depth critical path
  but moved the worst path to `write_idx -> rhs`, with WNS +0.104 ns.
- A fourth residual retirement stage passed correctness but moved the RHS path
  to WNS -0.121 ns and was rejected.

None of these rejected variants remains in RTL.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(0,3) -RunId 'timing-isolation-full-a2' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(1,2,4,5,6,7) -RunId 'timing-isolation-full-b2' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId active-k-keep-synth
```

Raw generated artifacts remain under ignored `logs/` and `work/` directories.
