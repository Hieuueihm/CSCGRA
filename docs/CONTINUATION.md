# Repository refactor continuation log

Last updated: 2026-08-03 (Asia/Saigon)

## Checkpoint

- Working branch: `codex/clean-repository-layout`
- Pre-refactor tag: `pre-repo-layout-741c0f2`
- Baseline commit: `741c0f2b5a01f8e3da6b2765170f2e7870d8cd79`
- Refactor type: repository layout and tooling only; no RTL logic edits

## Completed

- Split synthesizable RTL into independent `rtl/v1` and `rtl/v2` trees.
- Organized RTL by control, datapath, interconnect, memory, PE, solver, and top.
- Compared every moved RTL file against the baseline Git blob: zero byte
  mismatches.
- Moved testbenches/golden vectors to `verification/v1` and `verification/v2`.
- Moved bare-metal C sources to `sw/v1` and `sw/v2`.
- Moved golden models to `models/golden`.
- Moved reviewed project results to `reports/v1` and `reports/v2`.
- Moved historical experiments to `research`.
- Isolated old scripts under `scripts/legacy`.
- Added canonical simulation and synthesis entrypoint `scripts/run.ps1`.
- Added version configs and RTL manifests.
- Separated generated work and raw logs into ignored `work/` and `logs/`.
- Moved local pre-refactor generated trees to
  `work/legacy_pre_refactor`; nothing was deleted.
- PowerShell parser: zero errors in active scripts.
- Layout/path validation: PASS.
- Active source/manifests contain no hard-coded `D:/vivado_pj` or stale
  `CSCGRA.srcs/sources` path.
- RTL audit: v2 has zero uninstantiated internal modules. V1 reports the
  historical standalone `pe_tile` definition as uninstantiated.

## Completed dynamic smoke test

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -Cases 0 -RunId layout-smoke-v2
```

Result:

- M=64, N=256, K=16
- 33 PASS, 0 FAIL
- OMP: 110785 cycles
- IHT: 105466 cycles
- HTP: 173848 cycles
- GP: 106282 cycles
- GOMP: 60894 cycles
- MP: 60145 cycles
- CoSaMP/SP skip behavior unchanged because the case requires 2K candidate
  support.
- Raw log:
  `logs/sim/v2/layout-smoke-v2/case0_all.log`
- Raw log SHA256:
  `3A05D6B9EF7ECB214C6F4428680DB0500EB573ADE072655E3ECEA7FFC8C9F047`

The raw log is intentionally ignored; this file preserves the sign-off
summary.

## Completion update: 2026-08-03

The remaining sign-off work is complete:

- RTL v1 full regression: 348 PASS, 0 FAIL.
- RTL v2 full regression: 348 PASS, 0 FAIL.
- V1 comparison with `clean_check_run1_k_sweep_by_case`: 62/62 result rows
  and 2/2 skip rows match exactly.
- V2 comparison with `refactor_case0_v2/full_sweep.log`: 62/62 result rows
  and 2/2 skip rows match exactly.
- Compared fields: M, N, K, algorithm, iteration, cycle, status, PC, and NZ.
- V1 OOC synthesis: WNS +3.487 ns, data path 6.503 ns; resource totals match
  the pre-refactor `synth_incr_cgra_top` report exactly.
- V2 OOC synthesis: WNS +3.001 ns, data path 6.989 ns; resource totals match
  the factor-reuse baseline exactly.
- Both synthesis runs completed with 0 errors and 0 critical warnings.

Vivado 2018.1 compatibility was added to the canonical OOC runner by setting
the fileset `include_dirs` property before `read_verilog`. The first attempt
using the newer `read_verilog -include_dirs` option stopped before reading RTL
and was replaced by a successful clean retry.

Detailed final results are in
`reports/releases/REPOSITORY_LAYOUT_SIGNOFF_20260803.md`. No correctness,
cycle, timing, or resource work remains for the layout refactor.

## Optimization continuation baseline

The consolidated performance data, implemented optimization inventory,
strict-PE0 architecture gap, rejected trials, and ordered next-work backlog are
recorded in `reports/releases/OPTIMIZATION_BASELINE_20260803.md`. The complete
configured v1/v2 cycle matrix is also available as
`reports/releases/optimization_baseline_k_sweep_20260803.csv`.
