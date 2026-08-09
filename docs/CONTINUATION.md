# Repository refactor continuation log

Last updated: 2026-08-09 (Asia/Saigon)

## Active optimization checkpoint

- Current sign-off checkpoint: correlation streaming for SP/CoSaMP, on top of
  post-update x streaming for IHT/HTP/GP and the lossless top-K handshake.
- Correctness: 348 PASS, 0 FAIL over cases 0 through 7 (K=2/4/8/16).
- Independently isolated aggregate cycles: 1554673, down 27183 (1.72%) from
  the preceding checkpoint. CoSaMP is 327268 cycles (-5.41%) and SP is 275875
  cycles (-2.98%); all other algorithm totals are unchanged.
- Timing: WNS +0.538 ns, TNS 0, zero failing endpoints at 100 MHz.
- Resources: 113051 LUT, 51078 FF, 24 RAMB36, 71 DSP48.
- Detailed report:
  `reports/releases/CORR_STREAM_SP_COSAMP_SIGNOFF_20260809.md`.
- Compact cycle data:
  `reports/releases/corr_stream_sp_cosamp_k_sweep_20260809.csv`.
- Architecture: the correlation/update transaction still enters only PE0 and
  advances through all four registered PE rows. SP streams K and CoSaMP streams
  2K correlation candidates into shadow path P1 before merging into P0.
  IHT/HTP/GP retain their signed-off post-update x streams, and residual retains
  one registered PE0 transaction per block.
- Independent algorithms now use full soft reset at the run boundary so SPM
  scratch cannot leak between cycle/correctness measurements. Reset time is
  outside the algorithm cycle counter.

The earlier proposed completion-driven LS read chaining was measured and
rejected.  Diagonal-gather chaining failed timing at WNS -0.299 ns.  Back-solve
READ4, direct divider initialization, and forward-solve READ2 retained positive
WNS but reduced the margin to +0.134, +0.152, and +0.176 ns for only 21, 20,
and 15 K2 cycles respectively.  Forward solve cannot use the existing READ4
operation because it needs four columns from one row bank, whereas READ4 reads
one column from four row banks.  No trial RTL is retained; details are in
`reports/releases/LS_READ_CHAIN_TRIALS_20260806.md`.

Do not add more LS completion/address mux fan-in without state-residency data
showing a material K8/K16 benefit. The next target is a support-limited
post-REFINE stream for SP/CoSaMP, replacing repeated `reduce_x_support` scans
while preserving exact 2K/3K candidate semantics and the one-token residual
boundary.
Every large arithmetic transaction must still enter PE0 and advance through
all four rows.  Full correctness, per-algorithm cycles, resources, positive
WNS, and a preferred margin of at least +0.2 ns remain release gates.

## Previous optimization checkpoint

- Branch: `codex/strict-pe0-timing`
- Latest pushed checkpoint: `cfedb27` (tagged LDLT border stream).
- Correctness: 348 PASS, 0 FAIL over cases 0 through 7 (K=2/4/8/16).
- Aggregate cycles: 1771732, down 132562 (6.96%) from the preceding
  factor-check-clean checkpoint and down 197447 (10.03%) from strict P0.
- Timing: WNS +0.018 ns, TNS 0, zero failing endpoints at 100 MHz.
- Resources: 118199 LUT, 53554 FF, 24 RAMB36, 71 DSP48.
- Detailed report:
  `reports/releases/LDLT_BORDER_STREAM_SIGNOFF_20260804.md`.
- Compact cycle data:
  `reports/releases/ldlt_border_stream_k_sweep_20260804.csv`.

Completed checkpoints on this branch are strict PE0 ingress/timing closure,
residual block-8 chaining, exact factor-check early rejection/dead-path
cleanup, and multi-transaction LDLT border streaming.  Correlation/vector
update fusion for IHT/GP and exact four-row top-K remain intact.  A replicated
eight-lane top-K eligibility mask was tested and rejected because it increased
area; it is not in source.

Strict PE0 provenance and positive WNS remain release gates.  The current
WNS margin is only +0.018 ns, so the next implementation should first reduce
LDLT scoreboard/cache routing or add a timing-isolation stage, accepting a
small cycle increase if needed.  Do not add another large datapath until that
margin is improved.

QR has been evaluated only as an optional robustness fallback and is not in
RTL.  The study and entry criteria are in
`reports/releases/QR_ROBUSTNESS_STUDY_20260804.md`.

### Residual chaining update

- Tagged residual block-8 chaining is signed off after the P0 checkpoint.
- Full K-sweep: 348 PASS, 0 FAIL.
- Aggregate cycles: 1904934, down 64245 (3.26%) from strict P0.
- Timing/resources: WNS +0.249 ns, 105383 LUT, 39884 FF, 24 RAMB36,
  71 DSP48.
- Detailed report: `reports/releases/RESIDUAL_CHAIN_SIGNOFF_20260804.md`.
- Next implementation target: multiple in-flight tagged LDLT border
  transactions, then exact top-K/factor-check cost reduction. (Completed;
  retained here as historical checkpoint context.)

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

## Latest optimization checkpoint: support-limited post-REFINE stream

SP and CoSaMP now replace K repeated post-REFINE full-vector reduce/append
scans with a lossless support-only stream into exact four-row top-K. Candidate
data enters only PE0; append results are reordered by ascending index to retain
the legacy LDLT support order.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Total: 1,554,673 -> 1,536,277 cycles (-18,396; -1.18%).
- CoSaMP: 327,268 -> 318,322 (-2.73%).
- SP: 275,875 -> 266,425 (-3.43%).
- Timing: WNS +0.129 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 115,178 total LUT, 51,312 FF, 24 RAMB36, 71 DSP48.
- Detailed report:
  `reports/releases/POST_REFINE_SUPPORT_STREAM_SIGNOFF_20260809.md`.
- Cycle matrix:
  `reports/releases/post_refine_support_stream_k_sweep_20260809.csv`.

Next work must preserve strict PE0 ingress and should first protect or improve
timing margin before adding logic to the LDLT/residual critical cone.

## Optimization continuation baseline

The consolidated performance data, implemented optimization inventory,
strict-PE0 architecture gap, rejected trials, and ordered next-work backlog are
recorded in `reports/releases/OPTIMIZATION_BASELINE_20260803.md`. The complete
configured v1/v2 cycle matrix is also available as
`reports/releases/optimization_baseline_k_sweep_20260803.csv`.
