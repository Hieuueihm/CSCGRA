# Repository refactor continuation log

Last updated: 2026-08-10 (Asia/Saigon)

## Active optimization checkpoint

- Current sign-off checkpoint: direct-Phi scan128 for N=256, on top of the
  one-entry `OP_ACC4` queue and earlier four-row Gram batch overlap.
- Correctness: 348 PASS, 0 FAIL over cases 0 through 7 (K=2/4/8/16).
- Aggregate cycles: 1,354,843, down 40,960 (2.93%) from the ACC4 queue
  checkpoint. OMP is 167,584, CoSaMP 280,562, HTP 214,356, SP 232,921,
  GOMP 96,088, IHT/GP 127,036 each, and MP 109,260.
- Timing: WNS +0.726 ns, TNS 0, zero failing endpoints at 100 MHz.
- Resources: 125,293 LUT, 53,593 FF, 24 RAMB36, 71 DSP48.
- Detailed report:
  `reports/releases/PHI_SCAN128_SIGNOFF_20260810.md`.
- Compact cycle data:
  `reports/releases/phi_scan128_k_sweep_20260810.csv`.
- Architecture: scan128 only regenerates Phi values for N=256.  PE0-only
  ingress, the ACC4 pending queue, and fixed four-row Gram ownership are
  unchanged. N<=128 keeps its previous two-clock SPM-settle schedule.

The next optimization must keep the same PE0 -> PE1 -> PE2 -> PE3 provenance.
Profile before changing another wide datapath: correlation is already PE0
limited at II=1, and direct-Phi scan cannot safely collapse to one clock because
the synchronous SPM settle interval must remain.  Prefer a measured LDLT,
top-K, or residual control optimization, or compact the ACC4 queue payload
without reintroducing a matrix-write bubble.  Full correctness, per-algorithm
cycles, resources, positive WNS, and a preferred margin of at least +0.2 ns
remain release gates.

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

- Split synthesizable RTL into active `rtl/v2` and archived `archive/v1/rtl`
  trees.
- Organized RTL by control, datapath, interconnect, memory, PE, solver, and top.
- Compared every moved RTL file against the baseline Git blob: zero byte
  mismatches.
- Moved active testbenches/golden vectors to `verification/v2`; the v1 set is
  archived under `archive/v1/verification`.
- Moved active bare-metal C sources to `sw/v2`; the v1 set is archived under
  `archive/v1/sw`.
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

## Latest timing checkpoint: registered LS RHS products

The four-row LS multiplier result is captured at the existing second PE wait
boundary before RHS accumulation.  This breaks the previous PE/DSP-to-RHS
critical path without adding any controller or algorithm cycle.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Cycle matrix: identical to the support-limited post-REFINE checkpoint;
  aggregate remains 1,536,277 cycles.
- Timing: WNS +0.383 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 115,132 total LUT, 112,984 logic LUT, 51,470 FF, 24 RAMB36,
  71 DSP48.
- Strict ingress and row ownership are unchanged: PE0 is the sole ingress and
  RHS lane `i` is owned by physical row `i mod 4`.
- Detailed report:
  `reports/releases/RHS_TIMING_ISOLATION_SIGNOFF_20260810.md`.

The next bounded cycle target is to overlap preparation of a following
four-column Gram transaction with the final drain cycles of the current
transaction.  Keep one LS request active at a time and re-run full K-sweep and
OOC timing before accepting it.

## Latest cycle checkpoint: overlapped Gram batches

The next four-column Gram PE transaction is prepared during the final two
matrix-drain writes.  The registered LS request reaches the service only after
the previous transaction returns idle, so request ownership and write order
remain exact.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,536,277 -> 1,514,273 (-22,004; -1.43%).
- OMP: 195,088 (-2.09%); CoSaMP: 310,482 (-2.46%); HTP: 239,874
  (-0.91%); SP: 260,713 (-2.14%); GOMP: 109,840 (-1.86%).
- IHT, GP, and MP are unchanged because they do not use this Gram schedule.
- Timing/resources remain unchanged: WNS +0.383 ns, TNS 0, 115,132 LUT,
  51,470 FF, 24 RAMB36, 71 DSP48.
- Strict PE0 ingress remains intact; physical row `r` owns Gram column
  `acc_j + r`, so all four rows participate.
- Detailed report: `reports/releases/GRAM_BATCH_OVERLAP_SIGNOFF_20260810.md`.
- Cycle matrix: `reports/releases/gram_batch_overlap_k_sweep_20260810.csv`.

The next large measured states are correlation accumulation and direct Phi
support scan (states 36 and 77, each 16,384 cycles in the representative K=8
CoSaMP/SP profiles).  Any parallel scan must originate at PE0, propagate
through all four physical rows, and preserve exact support/factor order.

## Latest scan checkpoint: two-window direct Phi regeneration

Direct Phi/support regeneration now covers 64 columns per controller clock for
N=128/256 using fixed LFSR jump matrices.  N<=64 retains the original
32-column schedule because its second scan clock is also a required
synchronous-SPM settle interval.

- Correctness: 348 PASS / 0 FAIL in one unified final run, 62 cycle records,
  2 expected K16 skips.
- Aggregate cycles: 1,514,273 -> 1,418,017 (-96,256; -6.36%).
- OMP: 178,960 (-8.27%); CoSaMP: 294,610 (-5.11%); IHT/GP: 130,620
  each (-5.82%); HTP: 223,746 (-6.72%); SP: 244,841 (-6.09%);
  GOMP: 101,776 (-7.34%); MP: 112,844 (-6.67%).
- Timing: WNS +0.681 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 118,494 total LUT (+2.92%), 51,458 FF, 24 RAMB36, 71 DSP48.
- Strict PE0 ingress and four-row LS/Gram ownership remain unchanged.
- Detailed report: `reports/releases/PHI_SCAN64_SIGNOFF_20260810.md`.
- Cycle matrix: `reports/releases/phi_scan64_k_sweep_20260810.csv`.

Correlation state 36 remains at its PE0-limited II=1 and should not be widened
by injecting directly into lower rows.  The bounded one-entry `OP_ACC4` request
queue proposed here remains implemented under the current scan128 checkpoint.

## Latest scan checkpoint: four-window direct Phi regeneration

N=256 direct Phi/support regeneration now covers 128 columns per controller
clock using four independent 32-column windows. N=128 remains scan64 and N=64
remains scan32 to retain two SPM-settle clocks.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,395,803 -> 1,354,843 (-40,960; -2.93%).
- Timing: WNS +0.726 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 125,293 LUT, 53,593 FF, 24 RAMB36, 71 DSP48.
- Strict PE0 ingress, four-row arithmetic ownership, LDLT, and ACC4 queue
  behavior are unchanged.
- Detailed report: `reports/releases/PHI_SCAN128_SIGNOFF_20260810.md`.
- Cycle matrix: `reports/releases/phi_scan128_k_sweep_20260810.csv`.

## Optimization continuation baseline

The consolidated performance data, implemented optimization inventory,
strict-PE0 architecture gap, rejected trials, and ordered next-work backlog are
recorded in `reports/releases/OPTIMIZATION_BASELINE_20260803.md`. The complete
configured v1/v2 cycle matrix is also available as
`reports/releases/optimization_baseline_k_sweep_20260803.csv`.

## Latest residual checkpoint: guarded first-block preload

Profiling showed that LDLT factor control is comparatively small and exact
top-K issue is already PE0-limited at II=1, while residual wait state 50 costs
1,280-5,632 clocks per algorithm in the representative K8 case.  The accepted
change preloads a full first residual block during accumulator initialization,
then injects it at PE0 on the first wait clock.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,354,843 -> 1,344,523 (-10,320; -0.76%).
- OMP: 166,912 (-672); CoSaMP: 278,578 (-1,984); IHT/GP: 125,244
  each (-1,792); HTP: 212,564 (-1,792); SP: 231,049 (-1,872);
  GOMP: 95,672 (-416); MP: 109,260 (unchanged).
- Timing: WNS +0.624 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 123,173 LUT, 53,420 FF, 24 RAMB36, 71 DSP48.
- Strict PE0 ingress and four-row modulo-4 ownership are unchanged.
- An all-K preload trial was rejected after 23 K4 mismatches.  The accepted
  `active_k_count >= 8` guard preserves the required settle clock for partial
  K2/K4 blocks while still accelerating expanded CoSaMP/SP supports.
- Direct-Phi scan256 in one clock remains explicitly rejected because it risks
  removing the synchronous-SPM settle interval and widening the timing cone.
- Detailed report:
  `reports/releases/RESIDUAL_FIRST_PRELOAD_SIGNOFF_20260810.md`.
- Cycle matrix:
  `reports/releases/residual_first_preload_k_sweep_20260810.csv`.

The next safe target should stay controller-local: profile repeated LDLT
diagonal/READ4 handshakes or factor-check issue gaps without increasing the
number of active LS requests.  Do not widen correlation or direct-Phi scan;
both are already bounded by PE0 ingress or SPM settling.

## Latest LDLT checkpoint: chained diagonal READ2

Profile state 61 was a pure command/padding bubble between diagonal READ2
transactions.  The accepted change launches each following READ2 from the
previous completion pulse and zero-fills inactive tail lanes together.  The
matrix service still has at most one active request.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,344,523 -> 1,336,899 (-7,624; -0.57%).
- OMP: 166,644 (-268); CoSaMP: 274,962 (-3,616); HTP: 211,740
  (-824); SP: 228,401 (-2,648); GOMP: 95,404 (-268).
- IHT, GP, and MP are cycle-identical because they do not use this LDLT
  diagonal-gather schedule.
- K8 profile state 61 falls to zero, while diagonal READ2 wait and both PE
  multiply phases retain identical cycle counts.
- Timing: WNS +0.678 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 125,666 LUT, 53,417 FF, 24 RAMB36, 71 DSP48.
- Strict PE0 ingress and fixed four-row arithmetic ownership are unchanged.
- Detailed report:
  `reports/releases/LDLT_DIAG_READ2_CHAIN_SIGNOFF_20260811.md`.
- Cycle matrix:
  `reports/releases/ldlt_diag_read2_chain_k_sweep_20260811.csv`.

Factor-check remains intentionally unchanged: its measured cost is small, and
skipping its final state would extend next-value seen-mask/fingerprint logic.
The next safe cycle target should profile LDLT diagonal command/write-to-divide
transitions or exact-reuse solve setup, still retaining one active LS request
and the PE0-only ingress rule.

## Latest LDLT checkpoint: WRITE4 completion chaining

LDLT WRITE4 completion now launches the following READ4 row block, prefix
pivot READ4, or normal-pivot diagonal READ2 directly.  Four-lane setup is folded
into the same completion edge, while initial entry still uses the original
setup state.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,336,899 -> 1,334,819 (-2,080; -0.16%).
- OMP: 166,448 (-196); CoSaMP: 274,058 (-904); HTP: 211,534 (-206);
  SP: 227,737 (-664); GOMP: 95,294 (-110).
- IHT, GP, and MP remain cycle-identical.
- K8 profile confirms that all saved clocks come from state 59/80; READ4,
  border multiply, final multiply, and WRITE4 wait counts are unchanged.
- Timing: WNS +0.662 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 127,248 LUT, 53,611 FF, 24 RAMB36, 71 DSP48.
- Exactly one LS request remains active; PE0-only ingress and fixed four-row
  arithmetic ownership are unchanged.
- Detailed report:
  `reports/releases/LDLT_WRITE4_COMPLETION_CHAIN_SIGNOFF_20260812.md`.
- Cycle matrix:
  `reports/releases/ldlt_write4_completion_chain_k_sweep_20260812.csv`.

This checkpoint spends 1,582 additional LUT and 194 FF for a 0.16% cycle
reduction.  Prefer a resource-neutral optimization next.  Candidate work is a
carefully registered READ4 service fast-complete path or removal of a narrow
solve-setup bubble; do not extend another wide next-block control cone.

## Latest LDLT checkpoint: back-solve READ4 fast-complete

Back-substitution READ4 now uses a narrow service-boundary state decode.  The
matrix service accepts the command on the existing READ-to-WAIT edge using
registered row/column sources, cutting one wait clock per READ4 while retaining
the single launch state.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,334,819 -> 1,331,717 (-3,102; -0.232%).
- OMP: 166,140 (-308); CoSaMP: 273,045 (-1,013); HTP: 210,758
  (-776); SP: 226,906 (-831); GOMP: 95,120 (-174).
- IHT, GP, and MP remain cycle-identical.
- K8 profile retains 844 READ4 command clocks while READ4 wait falls from
  2,532 to 1,688 clocks, exactly one saved clock per command.
- Timing: WNS +0.586 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 122,435 LUT, 53,488 FF, 24 RAMB36, 71 DSP48.
- A direct launch from BACK_PREP/BACK_UPDATE was rejected despite identical
  cycle savings because it raised LUT to 131,977.
- Exactly one LS request remains active; PE0-only ingress and fixed four-row
  arithmetic ownership are unchanged.
- Detailed report:
  `reports/releases/BACKSOLVE_READ4_FAST_COMPLETE_SIGNOFF_20260816.md`.
- Cycle matrix:
  `reports/releases/backsolve_read4_fast_complete_k_sweep_20260816.csv`.

The next optimization should remain resource-neutral.  Profile a narrow
forward/back solve transition or factor-check handshake, and reject any change
that duplicates command setup across multiple PE/control states.

## Latest LDLT checkpoint: shared forward-solve tail completion

The unit-lower forward solve now completes a partial four-lane block on the
last valid READ2 response instead of visiting `S_ELIM_ROW` once per inactive
tail lane.  Diagonal gather and forward solve share one tail-limit comparator
and coefficient-lane zero-fill decode; READ2 stays on the registered LS command
path.

- Correctness: 348 PASS / 0 FAIL, 62 cycle records, 2 expected K16 skips.
- Aggregate cycles: 1,331,717 -> 1,328,836 (-2,881; -0.216%).
- OMP: 165,788 (-352); CoSaMP: 272,157 (-888); HTP: 210,098
  (-660); SP: 226,126 (-780); GOMP: 94,919 (-201).
- IHT, GP, and MP remain cycle-identical.
- K8 saves 742 inactive tail-write clocks; valid READ2 latency remains three
  clocks per request.
- Timing: WNS +0.605 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 123,551 LUT, 53,423 FF, 24 RAMB36, 71 DSP48.
- Direct READ2 fast-start variants were rejected at 127,270--128,434 LUT.
- Exactly one LS request remains active; PE0-only ingress and fixed four-row
  arithmetic ownership are unchanged.
- Detailed report:
  `reports/releases/FORWARD_SOLVE_SHARED_TAIL_COMPLETION_SIGNOFF_20260816.md`.
- Cycle matrix:
  `reports/releases/forward_solve_shared_tail_completion_k_sweep_20260816.csv`.

The next cycle optimization should not revisit forward READ2 fast-start.  Its
cycle benefit is measured, but its service-boundary mux cost is too high.  A
safer next target is a resource-neutral factor-check or solve-setup control
bubble whose operands are already registered; retain one active LS request and
the PE0 -> PE1 -> PE2 -> PE3 ingress rule.

## Latest rejected study: LS solve-setup bubbles

Three implementations of the fresh-factor `S_LDL_INIT` -> first diagonal
READ2 boundary were profiled and synthesized.  All passed the eight-algorithm
K8 smoke test and timing, but all failed the resource-neutral acceptance rule.

- Direct completion-to-READ2 saved 50 K8 clocks but added 6399 LUT.
- Bypassing `S_LDL_INIT` saved 25 clocks but added 3311 LUT.
- Reusing `S_LDL_INIT` as the READ2 command state saved 25 clocks but added
  3354 LUT.
- Best timing among the trials was +0.654 ns, but the cycle/resource ratio is
  not acceptable; no RTL trial was retained.
- Source has been restored exactly to checkpoint `d487050` behavior.
- Detailed report:
  `reports/releases/LS_SOLVE_SETUP_TRIALS_20260816.md`.

Do not revisit the fresh-factor first-diagonal setup boundary.  The next safe
candidate is a strictly state-only factor-check transition; reject it if it
adds final-response seen-mask/fingerprint logic or materially grows LUT.  The
current signed-off baseline remains 1328836 full-sweep cycles, +0.605 ns WNS,
123551 LUT, 53423 FF, 24 RAMB36, and 71 DSP48.

## Latest rejected study: factor-check known-miss DONE bypass

The strictly state-only factor-check candidate has now also been implemented,
profiled, and synthesized.  It bypassed DONE only for reuse-impossible requests
identified in INIT; the possible-reuse scan, PE3 response, seen-mask, ordered
match, and fingerprint logic were untouched.

- K8 correctness: 45 PASS / 0 FAIL.
- K8 cycles: 379662 -> 379642 (-20, -0.0053%).
- Savings: OMP -1, CoSaMP -9, HTP -1, SP -8, GOMP -1.
- Timing: WNS +0.648 ns, TNS 0, no failing endpoints.
- Resources: 125698 LUT (+2147, +1.74%), 53411 FF, 24 RAMB36, 71 DSP48.
- Decision: rejected; RTL restored to the `d487050` signed-off behavior.
- Detailed report:
  `reports/releases/FACTOR_CHECK_STATE_ONLY_TRIAL_20260816.md`.

Do not revisit factor-check INIT/DONE or the fresh-factor solve-setup boundary.
Both have now been measured and fail the resource-neutral requirement.  Keep
the signed-off baseline at 1328836 full-sweep cycles, +0.605 ns WNS, 123551
LUT, 53423 FF, 24 RAMB36, and 71 DSP48 while selecting a higher-residency
target outside these control paths.

## Latest rejected study: correlation INIT bypass

The next high-residency candidate, `S_CORR_INIT`, was implemented in both
direct and shared-control forms.  Both preserved strict PE0 ingress, all four
PE row roles, and the synchronous-SPM settle state.

- K8 correctness: 45 PASS / 0 FAIL for both implementations.
- K8 cycles: 379662 -> 377802 (-1860, -0.49%).
- Direct form: 131176 LUT (+7625, +6.17%), WNS +0.391 ns.
- Shared form: 133713 LUT (+10162, +8.23%), WNS +0.378 ns.
- Both retain 24 RAMB36 and 71 DSP48 with zero timing failures.
- Decision: rejected; RTL restored exactly to checkpoint `9306d2c`.
- Detailed report:
  `reports/releases/CORRELATION_INIT_BYPASS_TRIAL_20260816.md`.

Do not revisit factor-check INIT/DONE, fresh-factor solve-setup, or correlation
INIT bypass.  The next candidate must have high measured residency without
moving LFSR generation or another wide datapath cone onto a completion edge.
Prefer an existing registered handshake/control bubble in residual, Gram, or
top-K service; require a cycle gain materially larger than its LUT percentage.

## Latest rejected study: Gram ACC4 zero guard

The final registered Gram guard was changed from one to zero without adding
logic.  OMP passed and saved 768 K8 clocks, but CoSaMP produced multiple final
`X_MISM` failures, so the run was stopped and no synthesis was performed.

- The ACC4 pending queue can accept a request early, but its four-row PE
  producer payload is not stable without the retained guard clock.
- RTL is restored exactly to checkpoint `417bfa5` behavior.
- Detailed report: `reports/releases/GRAM_GUARD0_TRIAL_20260817.md`.

Do not retry Gram guard zero without adding a registered wide ACC4 payload.
Residual INIT/WAIT now represents preload plus real pipeline fill/drain, and
top-K CAPTURE/ISSUE represents producer wait plus real PE0 tokens.  Neither is
a remaining resource-neutral handshake bubble.  Avoid moving residual wide
sums or LFSR generation onto a completion edge merely to collapse a state.

## Latest signed-off optimization: bounded Gram final-batch overlap

The global Gram guard-zero trial remains rejected, but its root cause enabled a
safe bounded schedule.  Only the final ACC4 batch of each measurement row now
uses guard zero; every consecutive batch retains guard one.  The following
direct-Phi scan and RHS interval drains the one-entry queue before another Gram
request can arrive.

- Full correctness: 348 PASS / 0 FAIL, 62 cycle records, with the 2 expected
  K16 SP/CoSaMP capacity skips.
- Aggregate cycles: 1,328,836 -> 1,319,534 (-9,302; -0.700%).
- K8 cycles: 379,662 -> 376,764 (-2,898; -0.763%).
- OMP K8: 34,470 -> 33,966; OMP K16: 84,014 -> 83,006.
- Timing: WNS +0.658 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 124,019 LUT, 53,506 FF, 24 RAMB36, 71 DSP48.
- Total LUT rises 0.379%, below the 0.700% full-sweep cycle reduction; FF rises
  by 83, while BRAM/DSP remain unchanged.
- Strict PE0 ingress, PE0 -> PE1 -> PE2 -> PE3 propagation, four-row ownership,
  registered LS commands, and one active LS request remain unchanged.
- Detailed report:
  `reports/releases/GRAM_FINAL_BATCH_OVERLAP_SIGNOFF_20260817.md`.
- Cycle matrix:
  `reports/releases/gram_final_batch_overlap_k_sweep_20260817.csv`.

Do not convert the remaining consecutive Gram batches to guard zero: the
producer can issue every three clocks while the matrix service drains in four.
If further ACC4 overlap is needed, it requires an explicitly sized registered
payload queue and a measured LUT/FF/WNS tradeoff.  Prefer profiling a different
high-residency registered boundary before paying that cost.

## Latest signed-off optimization: LDLT border phase overlap

The LDLT border scheduler now overlaps MUL1 drain with MUL2 issue using a
one-bit phase tag and a four-bit modulo-slot ready mask.  This keeps the compact
four-entry scoreboard while preventing MUL2 tag `p` from overwriting a slot
still owned by MUL1 tag `p+4`.  All tokens still enter at PE0 and propagate
through PE1, PE2, and PE3; four target-row roles and the one-active-LS-request
rule are unchanged.

- Full correctness: 348 PASS / 0 FAIL, with the 2 expected K16 SP/CoSaMP
  capacity skips.
- Aggregate cycles: 1,319,534 -> 1,315,336 (-4,198; -0.318%).
- K8 cycles: 376,764 -> 375,362 (-1,402; -0.372%).
- OMP K8: 33,966 -> 33,920; OMP K16: 83,006 -> 82,728.
- Timing: WNS +0.850 ns, TNS 0, no failing endpoints at 100 MHz.
- Resources: 121,302 LUT, 53,281 FF, 24 RAMB36, 71 DSP48.
- Detailed report:
  `reports/releases/LDLT_BORDER_PHASE_OVERLAP_SIGNOFF_20260817.md`.
- Cycle matrix:
  `reports/releases/ldlt_border_phase_overlap_k_sweep_20260817.csv`.

Do not use the tested phase-separated doubled scoreboard: it passed K8 but
added 3,104 LUT for only 0.74% K8 cycle reduction.  The next possible
architectural study is two-column ACC4 drain with column banking, after first
profiling its remaining control/dependency stalls.  Keep registered payload
isolation, strict PE0 ingress, one active LS request, WNS >= +0.2 ns, and reject
any candidate whose LUT-growth percentage exceeds its cycle reduction.

## Latest rejected study: ACC4 two-column drain

The proposed two-column ACC4 drain was profiled and implemented in two forms.
The direct column-parity-bank form passed K8 at 45 PASS / 0 FAIL and reduced
375,362 -> 369,878 cycles (-5,484; -1.461%).  It was nevertheless rejected:
OOC used 143,154 LUT (+18.01%), 3,680 LUTRAM, and 75 DSP, versus the signed-off
121,302 LUT, 2,144 LUTRAM, and 71 DSP.  WNS remained positive at +0.621 ns.

A packed 112-bit adjacent-column word also passed OMP K8 at 33,632 cycles, but
two independently enabled partial writes prevented distributed-RAM inference
and expanded the LS service into large logic partitions.  Its OOC run was
stopped before final reporting.  Both RTL trials were removed; checkpoint
`0ae1557` behavior is restored.

Detailed report:
`reports/releases/ACC4_TWO_COLUMN_BANKING_TRIAL_20260817.md`.

Do not retry two-column drain with ordinary inferred LUTRAM.  It needs either
duplicated banks/adders or an explicit true-dual-port memory primitive.  A BRAM
implementation may be studied only if the no-BRAM-growth criterion is relaxed.
The next optimization should return to a registered high-residency controller
or datapath boundary outside the ACC4 storage write port.

## Latest rejected study: bounded LS matrix clear

`S_LS_CLEAR_WAIT` was the next registered boundary studied outside ACC4.  A
fine active-column bound failed OMP K8 (5 PASS / 6 FAIL) because factor/prefetch
behavior can observe columns beyond the current active prefix before masking.

A conservative row-page bound kept every column clear and skipped only rows
8--15 when K<=8.  OMP K8 passed and saved 16 clocks, but OOC grew from 121,302
to 127,128 LUT (+4.80%) for only about 0.107% projected K8 reduction.  WNS was
+0.472 ns, FF 53,416, RAMB36 24, and DSP48 71.  It was rejected before full
regression and all RTL was restored to checkpoint `f5cdbe3` behavior.

Detailed report:
`reports/releases/LS_BOUNDED_CLEAR_TRIALS_20260817.md`.

Do not revisit active-column or row-page-bounded clear.  Also avoid the already
rejected completion-driven forward READ2 paths.  The next target must have
materially more registered residency than clear and remain outside the ACC4
write port.

## Latest rejected study: RHS_WRITE4

Four serialized RHS writes were combined into one registered `RHS_WRITE4`
request using the low 256 bits of the existing `rhs4_product_q` hold and the
existing `lane_add4` interface. OMP K8 passed at 5 PASS / 0 FAIL, and the full
K8 suite passed at 45 PASS / 0 FAIL. K8 cycle count fell from 375,362 to
374,258 (-1,104; -0.294%); OMP fell from 33,920 to 33,848.

The implementation kept one active LS request, did not change ACC4, and left
DSP/BRAM unchanged. OOC WNS was positive at +0.501 ns. It was nevertheless
rejected because four independently enabled writes expanded total LUT from
121,302 to 133,109 (+11,807; +9.73%), while FF rose from 53,281 to 53,613.
This exceeds the cycle benefit by more than 33 times. A full K-sweep was not
run after the resource gate failed, and all RTL was restored to the signed-off
baseline.

Detailed report:
`reports/releases/RHS_WRITE4_TRIAL_20260817.md`.

Do not retry RHS_WRITE4 with ordinary inferred multi-write RTL. The next
candidate must avoid widening a memory write port and should target a
high-residency registered controller/datapath boundary while preserving strict
PE0 ingress, four-row PE participation, one active LS request, and WNS >=
+0.2 ns.

## Latest rejected study: LDLT READ4 completion chaining

The high-residency LDLT row-preload READ4 boundary was evaluated in two forms.
A direct address fast-start passed K8 at 45 PASS / 0 FAIL and reduced 375,362
to 372,602 cycles (-0.735%), but expanded total LUT from 121,302 to 127,673
(+5.25%). WNS remained positive at +0.394 ns.

A narrower form pre-registered p+1 in the existing LS command address hold and
fed only the completion-qualified start into the service. It also passed K8 at
45 PASS / 0 FAIL and reduced `S_LDL_ROW_P_WAIT` from 9,126 to 6,661 clocks.
K8 total became 372,897 (-2,465; -0.657%). OOC WNS was +0.603 ns, but LUT still
rose to 123,077 (+1.46%), FF to 53,381, and the run emitted one LUTNM shape
critical warning. RAMB36 remained 24 and DSP remained 71 in both trials.

Both variants failed the resource-versus-cycle gate and were removed before a
full K-sweep. RTL is restored exactly to checkpoint `3152554`.

Detailed report:
`reports/releases/LDLT_READ4_CHAIN_TRIALS_20260817.md`.

Do not retry completion-feedback fast-start on LDLT READ4, direct or
pre-registered. The next candidate should be a registered stage inside the
wide-multiply or divider controller, not another matrix-memory handshake or
multi-write path. Preserve strict PE0 ingress, all four PE-row roles, one
active LS request, and WNS >= +0.2 ns.

## Latest rejected study: wide-multiplier registered stage

Verification now profiles internal wide-multiplier state residency.  Baseline
K8 passed at 45 PASS / 0 FAIL and exposed 3,096 non-vertical FINAL-stage
completion opportunities.  The divider's 5,248 divide-step clocks were all
active arithmetic clocks, so it had no removable registered bubble.

A trial fused non-vertical wide-multiply COMMIT and FINAL.  It preserved the
existing four simultaneous PE-row products, left the strict vertical
PE0 -> PE1 -> PE2 -> PE3 path unchanged, and did not alter any memory port.
K8 passed at 45 PASS / 0 FAIL and fell from 375,362 to 372,266 cycles
(-3,096; -0.825%), exactly matching the profile.

The trial was rejected after OOC. WNS was only +0.205 ns, while total LUT grew
from 121,302 to 128,228 (+5.71%) and FF from 53,281 to 53,635. RAMB36 remained
24 and DSP remained 71. The LUT growth was 6.9 times the cycle-reduction
percentage. A full K-sweep was not run, and RTL was restored exactly to
checkpoint `d4a3bfd`. The verification-only profiler is retained.

Detailed report:
`reports/releases/WIDE_MULTIPLIER_REGISTERED_STAGE_TRIAL_20260817.md`.

Do not retry non-vertical COMMIT/FINAL fusion, increase divider radix, feed
completion back into READ4, or widen memory ports. The next target must be a
high-residency boundary with an already narrow local registered payload, while
preserving strict PE0 ingress, distinct work on all four PE rows, one active LS
request, and WNS >= +0.2 ns.

## Latest retained optimization: top-K append ACK chaining

The non-sorted top-K result path now presents the next locally registered
10-bit index and 3-bit support path on the registered `append_done` edge.  This
removes the empty re-issue clock between support writes without widening a
memory port.  The final ACK transitions directly to DONE.

The ranking wavefront remains strict PE0 -> PE1 -> PE2 -> PE3.  No LS request,
READ4 feedback, divider, wide multiplier, DSP, BRAM, or four-row arithmetic
role changed.

Results:

- K8: 45 PASS / 0 FAIL; 375,362 -> 374,962 cycles (-400; -0.107%).
- Full sweep: 348 PASS / 0 FAIL with two expected K16 skips;
  1,315,336 -> 1,313,368 cycles (-1,968; -0.150%).
- OOC WNS: +0.850 ns, unchanged.
- LUT: 121,302 -> 121,359 (+57; +0.047%).
- FF/RAMB36/DSP: unchanged at 53,281/24/71.

Detailed report and complete cycle matrix:

- `reports/releases/TOPK_APPEND_ACK_CHAIN_SIGNOFF_20260817.md`
- `reports/releases/topk_append_ack_chain_k_sweep_20260817.csv`

The next narrow registered boundary is the sorted append ACK -> first scan
position transition. K8 `S_SORT_WAIT` residency is 256 clocks. Any trial must
reuse the existing result-list mux, preserve WNS >= +0.2 ns, and be rejected if
its LUT growth exceeds the smaller cycle benefit.

## Architectural refactor checkpoint: versioned support tuples

`support_set_service.vh` now keeps explicit tuple metadata beside the legacy
support index store:

- one valid bit per `{path, slot}` tuple;
- an 8-bit tuple version and per-path version counter;
- every append, sorted shift, merge insert, and candidate copy goes through a
  common tuple write operation;
- candidate metadata and error clear invalidate slots explicitly before the
  next operation.

The legacy `support_mem` index remains the functional source for this
checkpoint, while the valid/version state is consumed by the support-lane
membership mask. This makes writeback/invalidate semantics explicit without
changing the current sparse-loop schedule or widening a memory port. It is the
safe first step toward a tuple register file; replacing dense support scans can
be evaluated only after the LS issue boundary is isolated.

Verification after the change:

- K2 standard sweep: 45 PASS / 0 FAIL;
- K2 per-iteration sweep: 45 PASS / 0 FAIL;
- K4 per-iteration sweep: 45 PASS / 0 FAIL.

The full 348-record sweep and synthesis/implementation timing are not claimed
for this checkpoint until they are rerun after the remaining architectural
changes.

## Architectural refactor checkpoint: LS issue engine boundary

`ls_issue_engine.v` now sits between `sparse_loop_controller` and the existing
`ls_matrix_service`. It is deliberately a one-entry issue boundary:

- accepts a command only while the previous request is inactive;
- forwards an accepted command in the same cycle, so no schedule bubble is
  introduced;
- returns the existing service completion and ACC4 credit unchanged;
- rejects accidental overlapping starts instead of allowing a row-bank
  collision.

The row-banked LDLT/ACC4 datapath, single active LS request rule, and strict
PE0 ingress are unchanged. This gives the next ISA migration a stable place to
move dependency/issue tracking without modifying the arithmetic service.

Verification after the boundary extraction:

- K2 standard sweep: 45 PASS / 0 FAIL;
- K4 per-iteration sweep: 45 PASS / 0 FAIL;
- cycle records match the tuple checkpoint exactly (K2 OMP 2,142 cycles;
  K4 OMP 4,102 cycles).

Full K-sweep and synthesis/implementation timing remain pending.

## Rejected trial: extracted Phi column-stream module

A trial moved the existing 32/64/128-column LFSR-jump scan from the controller
into a reusable `phi_column_stream` module. The K2 sweep remained green, but
K4 exposed fixed-point `x` mismatches in GP/HTP paths (for example alg1 and
alg2 at N=64) and a one-cycle schedule change. The trial was deleted and the
controller restored to the signed-off inline scan. No Phi extraction is part
of the retained checkpoint until a direct bit-exact equivalence test is added.

## Functional sign-off after retained refactor layers

The retained tuple metadata, LS issue boundary, and issued-stream telemetry
were rerun across all sweep cases:

- case 0 (N=256, K=16): 33 PASS / 0 FAIL, with the existing two 2K-capacity
  CoSaMP/SP skips;
- cases 1-7: 315 PASS / 0 FAIL;
- aggregate: **348 PASS / 0 FAIL** over the executed algorithm/case records.

Cycle records are unchanged from the preceding sign-off (for example OMP K8
40,644 cycles and OMP K16 99,404 cycles). This is functional sign-off only;
synthesis/implementation and WNS still need to be rerun on this checkpoint.

## Architectural refactor checkpoint: issued-stream phase accounting

Phase counters now increment on `packet_valid_w` and the phase carried by the
registered packet at the PE3 boundary, rather than on the raw context decode.
`phase_opcode` follows the same issued token when one is valid. This removes
the four-cycle packet-flight ambiguity from CSR telemetry and makes the phase
cycle report suitable for per-algorithm/program ablation. It does not gate or
retime any solver operation.
## Architectural refactor checkpoint: packet/phase boundary

The first controller-centric refactor layer is now present in `rtl/v2`:

- `phase_packet_pipe.v` carries narrow `{phase, mode, owner, version, idx,
  data}` metadata through four registered stages, preserving PE0 ingress and
  PE0→PE1→PE2→PE3 ordering. Wide arithmetic payloads remain on existing buses.
- `phase_isa_decoder.v` normalizes each legacy context word into phase,
  engine owner and dependency mask before packetization; existing context
  encodings remain backward-compatible.
- `support_relation_unit.v` normalizes EXACT, PREFIX, TRUNCATE and safe
  SWAP-LAST factor outcomes before the existing LDLT issue states.
- `phase_token_scheduler.v` owns phase-cycle counters, exposed through CSR
  addresses `0x074..0x088` for correlation, top-K, support, solve, residual,
  and vector phases.

This is an interface extraction checkpoint, not yet the final migration of all
algorithm scheduling out of `sparse_loop_controller`. The next step is to make
the context stream carry explicit phase dependencies and let the extracted
engines issue their own completion tokens.

## Implementation checkpoint after the retained refactor

The retained RTL was run through the OOC implementation flow as
`arch_refactor_impl` after the 348-record functional sweep. The run completed
placement, physical optimization, routing, DRC, route-status verification and
checkpoint generation with no implementation errors.

- post-route setup WNS: **+0.153 ns** at a 100 MHz, 10 ns constraint;
- post-route TNS: 0.000 ns, with 0 failing setup endpoints;
- post-route hold slack: +0.048 ns, with 0 failing hold endpoints;
- all 166,123 routable nets fully routed; 0 routing-error nets;
- implemented utilization: 123,353 LUTs, 52,004 FFs, 24 RAMB36 and 77 DSP48;
- worst post-route path remains the unpipelined PE MAC DSP path, with 9.470 ns
  data-path delay (3.526 ns logic, 5.944 ns routing).

Vivado reports the 100 MHz requirement as met, but +0.153 ns is below the
project's conservative +0.2 ns margin target. Therefore this is a routed
timing checkpoint, not final timing sign-off. The next RTL timing step should
register/isolate the state/operand boundary feeding the PE MAC while keeping
the strict PE0 ingress and one-request LS contract; top-K mesh mode and Phi
column-stream extraction remain deferred until that margin is recovered.
