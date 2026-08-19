# Reports

This directory contains reviewed, compact summaries that are useful for
regression and release comparison. Raw tool logs belong under `logs/` and are
not tracked.

- `v1/history` and `v2/history`: reports migrated from the previous projects.
- `v1/baselines` and `v2/baselines`: preserved baseline measurements.
- `releases`: signed-off release summaries, including the current optimization
  baseline, complete K-sweep cycle matrix, and continuation priorities.

## Current authoritative release

- `v2/hardware_golden_signoff.md` — latest hardware-golden verification and
  routed implementation baseline. RTL simulation is 348 PASS / 0 FAIL; synthesis
  is +0.454 ns WNS; routed implementation is fully routed but −1.987 ns WNS and
  remains a timing-fail baseline for the next optimization pass.
- `releases/TOPK_APPEND_ACK_CHAIN_SIGNOFF_20260817.md`
- `releases/topk_append_ack_chain_k_sweep_20260817.csv`

Current metrics are 348 PASS / 0 FAIL, 1,313,368 full-sweep cycles, +0.850 ns
WNS, 121,359 LUT, 53,281 FF, 24 RAMB36, and 71 DSP.

## Retained optimization reports

The current RTL cumulatively includes the signed-off work documented by:

- strict PE0/timing: `STRICT_PE0_TIMING_SIGNOFF_20260804.md`,
  `TIMING_ISOLATION_SIGNOFF_20260805.md`, and
  `SUPPORT_MESH_TIMING_ISOLATION_SIGNOFF_20260807.md`;
- residual/prune: `RESIDUAL_CHAIN_SIGNOFF_20260804.md`,
  `STRICT_PE0_PRUNE_BLOCK8_SIGNOFF_20260806.md`, and
  `RESIDUAL_FIRST_PRELOAD_SIGNOFF_20260810.md`;
- correlation/update/top-K streaming: `FUSED_CORR_UPDATE_PROGRAM_SIGNOFF_20260806.md`,
  `STREAM_TOPK_OMP_GOMP_SIGNOFF_20260807.md`,
  `CORR_TOPK_READY_VALID_SIGNOFF_20260809.md`,
  `POST_UPDATE_X_IHT_GP_SIGNOFF_20260809.md`,
  `POST_UPDATE_X_HTP_SIGNOFF_20260809.md`,
  `CORR_STREAM_SP_COSAMP_SIGNOFF_20260809.md`, and
  `POST_REFINE_SUPPORT_STREAM_SIGNOFF_20260809.md`;
- LS/LDLT/Gram: `LDLT_BORDER_STREAM_SIGNOFF_20260804.md`,
  `FACTOR_CHECK_CLEAN_SIGNOFF_20260804.md`,
  `LDLT_SCOREBOARD_LUTRAM_SIGNOFF_20260805.md`,
  `LDLT_PRELOAD_CHAIN_SIGNOFF_20260805.md`,
  `STABLE_LS_COMMAND_CHAIN_SIGNOFF_20260805.md`,
  `RHS_TIMING_ISOLATION_SIGNOFF_20260810.md`,
  `GRAM_BATCH_OVERLAP_SIGNOFF_20260810.md`,
  `ACC4_QUEUE_SIGNOFF_20260810.md`,
  `LDLT_DIAG_READ2_CHAIN_SIGNOFF_20260811.md`,
  `LDLT_WRITE4_COMPLETION_CHAIN_SIGNOFF_20260812.md`,
  `BACKSOLVE_READ4_FAST_COMPLETE_SIGNOFF_20260816.md`,
  `FORWARD_SOLVE_SHARED_TAIL_COMPLETION_SIGNOFF_20260816.md`,
  `GRAM_FINAL_BATCH_OVERLAP_SIGNOFF_20260817.md`, and
  `LDLT_BORDER_PHASE_OVERLAP_SIGNOFF_20260817.md`;
- direct scan: `PHI_SCAN64_SIGNOFF_20260810.md` and
  `PHI_SCAN128_SIGNOFF_20260810.md`;
- latest narrow handshake: `TOPK_APPEND_ACK_CHAIN_SIGNOFF_20260817.md`.

## Rejected or study-only reports

The following are evidence, not active features:

- `QR_ROBUSTNESS_STUDY_20260804.md`;
- `LS_READ_CHAIN_TRIALS_20260806.md`;
- `LS_SOLVE_SETUP_TRIALS_20260816.md`;
- `FACTOR_CHECK_STATE_ONLY_TRIAL_20260816.md`;
- `CORRELATION_INIT_BYPASS_TRIAL_20260816.md`;
- `GRAM_GUARD0_TRIAL_20260817.md`;
- `ACC4_TWO_COLUMN_BANKING_TRIAL_20260817.md`;
- `LS_BOUNDED_CLEAR_TRIALS_20260817.md`;
- `RHS_WRITE4_TRIAL_20260817.md`;
- `LDLT_READ4_CHAIN_TRIALS_20260817.md`;
- `WIDE_MULTIPLIER_REGISTERED_STAGE_TRIAL_20260817.md`.

Do not infer that a feature exists merely because a trial report exists. Check
`docs/PROJECT_STATUS.md` and the report's Decision section.
