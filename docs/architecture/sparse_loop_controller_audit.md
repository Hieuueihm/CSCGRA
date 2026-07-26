# Sparse Loop Controller Datapath Audit

Date: 2026-06-19
Branch: codex/no-refine-cache-trial
Current RTL baseline: e720c66 Prune legacy sparse phi scan

## Current Evidence

Recent OOC snapshots used for this audit:

| Block | LUT | FF | DSP | WNS | Worst path |
|---|---:|---:|---:|---:|---|
| sparse_loop_controller | 191,636 | 30,100 | 29 | -8.856 ns | support_cache -> phi_cache |
| score_select_service | 17,019 | 1,354 | 0 | -34.837 ns | sel_mem -> sel_score CE |
| sparse_kernel_service_engine | 224,425 | 24,502 | 29 | -27.362 ns | corr_stream_data -> score_select |

The controller is still a datapath-heavy block. The current goal cannot be reached by local LUT trimming; major datapaths must move out.

## Keep In sparse_loop_controller

These are legitimate thin-controller responsibilities:

| Item | Current RTL | Keep Reason |
|---|---|---|
| FSM/micro-op dispatch | state, active_op, op_sel | Required to launch sparse kernels and report done |
| Loop counters | write_idx, acc_i, acc_j, resid_i, solve_i/j/k, corr_row/col | Keep only as sequencing counters; data math should move out |
| Address generation/control | rd_addr, wr_addr, wr_en, write_limit | Controller may issue addresses to SPM/scratchpads |
| Handshake/status | busy, done, result | Required service boundary |
| Kernel mode bookkeeping | phase_residual, active_k, sparse op select | Controller metadata only |

## Move To PE Array / PE-Resident Kernels

These are compute datapaths currently inside the controller or SKSE that should move into PE fabric.

| Datapath | Current RTL Symptom | Target Owner | Reason |
|---|---|---|---|
| CORR accumulation | corr_acc_lane, corr_stream_data_q, S_CORR_* | PE streaming MAC + PE-chain reducer | Scores should be produced and reduced in lane pipeline, not central selector |
| RHS accumulation | rhs[], S_ACC_RHS, pe_rhs_product_bus consumed by controller | PE-local accumulator with flush | PE already computes products; accumulation state should live in PE/lane kernel |
| Gram accumulation | ge_mat[][] updates in S_ACC_GRAM/S_GRAM_PE_WAIT* | PE tile/block Gram kernel | Current controller owns Gram matrix update and muxing |
| Residual accumulation | residual_acc, residual_block_sum, S_WR_ACC/S_RESID_PE_WAIT* | PE row/lane residual kernel | Sum Phi_S*x should be row-parallel in PE lanes |
| LS row update | ge_mul_a/b/c, ge_mul_p, S_ELIM_MUL/S_ELIM_UPDATE | PE-assisted LS row-update kernel | Controller should sequence rows/factors; PE lanes update row entries |
| Back-sub dot product | ge_acc, S_BACK_ACC/S_BACK_MUL | PE lane dot-product kernel | Controller currently performs vector dot accumulation |
| MP update arithmetic | mp_score_q, mp_den_q, mp_x_new_q, S_MP_* | Small arithmetic service or PE scalar lane | Not loop-control; it is datapath |

## Move To Dedicated Services

These should not live in sparse_loop_controller, but may remain as services outside PE array.

| Datapath | Current RTL Symptom | Target Owner | Notes |
|---|---|---|---|
| TopK/Argmax | score_select_service centralized sel_mem/sel_score | PE streaming reducer service | Phase 1. Must preserve exact tie-break: larger abs wins, equal score lower index wins |
| Support state | support_cache[], support_build_cache[] mirrors support service | support scratchpad/service | Controller should query/read support entries, not hold a full mirror when possible |
| Pivot/reciprocal/divider | div_abs_num/den/rem/quot, div_iter, S_DIV_STEP | small arithmetic service | Controller launches reciprocal/divide; service returns exact fixed-point result |
| LS compact storage | ge_mat[][], ge_rhs[], ge_x[], coeff_mem[] | LS scratchpad/service | Must replace old arrays, not duplicate them |
| Refine cache | rhs_build_cache, ge_mat_build_cache, refine_* cache metadata | LS/refine service | Cache policy belongs near LS service, not sparse-loop controller |

## Delete / Parameter-Off In Paper Build

| Item | Current Status | Action |
|---|---|---|
| MMP/MPLS multipath remnants | support service already reduced to 2 paths | Keep 2-path only for OMP/SP/CoSaMP temporary path1; do not restore 8-path beam fabric |
| Legacy non-Bernoulli Phi scan | S_SCAN removed; phi_kind paper flow is direct LFSR | Keep removed unless a new golden explicitly requires nonzero phi_kind |
| Debug/event display paths | TB-only displays exist outside RTL; verify no synth-visible debug counters enabled | Keep ENABLE_DEBUG_COUNTERS=0; remove any synth-visible debug if found |
| Old cache/scratchpad duplicate path | XPM/scratchpad trial reverted because it increased LUT | Do not re-add unless old ge_mat/cache arrays are removed simultaneously |

## Phase 2 TopK Migration Plan

Do not rewrite selector in one shot. Previous stream-only rewrite failed OMP per-iter because iter0 selected 14 instead of 8.

Required staged approach:

1. Add a PE-chain Top1 service path only for OMP/MP.
2. Feed it the exact same corr_stream block ordering as current score_select_service.
3. Preserve exact tie-break and tiny-score behavior:
   - use abs(score)
   - larger abs wins
   - equal score lower index wins
   - obey support exclusion only for modes that currently set it
4. Gate old score_select_service off for Top1 only after OMP/MP per-iter passes.
5. Extend to TopK only after Top1 is exact.

Suggested service boundary:

```text
sparse_loop_controller CORR stream
  -> PE/TopK reducer service
      input: valid, done, base_idx, lane_valid[7:0], score[7:0]
      output: candidate_valid, candidate_idx, candidate_rank/path
  -> support scratchpad append primitive
```

## Phase 3 Accumulation Migration Plan

Start with RHS because it is closest to correlation:

1. Controller launches RHS kernel with row range and support depth.
2. PE lanes hold rhs_acc[j] across M rows.
3. At end, PE flushes rhs_acc[j] into LS compact scratchpad.
4. Remove controller rhs[] accumulation only after OMP/SP/CoSaMP/IHT smoke pass.

Then Gram:

1. PE tile computes lower-triangle Gram blocks.
2. Flush compact lower-triangle layout to LS scratchpad/service.
3. Remove ge_mat controller build path.

Then residual:

1. PE lanes compute partial sums for each row.
2. PE flushes residual r[row].
3. Remove residual_acc/residual_block_sum controller datapath.

## Phase 4 LS Row Update Migration Plan

Keep exact LS math but move vector row update:

```text
controller/service:
  choose pivot row/col
  request exact reciprocal/division service
  compute factor for target row
  launch PE_ROW_UPDATE(row_i, row_k, factor)

PE lanes:
  row_i[j] = row_i[j] - factor * row_k[j]
```

Only after this passes should ge_mul_a/ge_mul_b/ge_mul_p and S_ELIM_MUL/S_ELIM_UPDATE be deleted from controller.

## Immediate Next Patch Recommendation

The next code patch should not target sparse_loop_controller directly. It should introduce a replacement service boundary for Top1:

- create a small `pe_stream_topk_service` or extend `pearray` result path for Top1 candidate reduction;
- connect it in SKSE beside score_select_service;
- use it only for OMP/MP Top1 context;
- after OMP/MP pass, remove the equivalent Top1 path from score_select_service.

This is the first aligned move toward a thin controller because it removes reducer ownership from SKSE/controller path instead of trimming controller arrays.

## Full cgra_top Hierarchy Audit

OOC command: `python analysis/fast_flow/fast_flow.py ooc cgra_top`
Report time: 2026-06-19 06:56
Part: `xczu7ev-ffvc1156-2-e`

| Instance | LUT | FF | BRAM36 | DSP | Interpretation |
|---|---:|---:|---:|---:|---|
| cgra_top total | 287,746 | 47,706 | 16 | 94 | Far above 120k-150k target |
| u_sparse_kernel_service_engine | 224,714 | 32,520 | 0 | 29 | Dominant block; must be shrunk/repartitioned |
| u_sparse_loop_controller | 211,319 | 30,494 | 0 | 29 | Actual main problem; controller still owns datapath |
| u_score_select | 11,582 | 1,347 | 0 | 0 | Centralized TopK/Argmax; timing-critical |
| u_support_service | 2,768 | 372 | 0 | 0 | Already small after path pruning |
| u_reduce_scan | 253 | 305 | 0 | 0 | Small; not a priority |
| u_pearray | 54,965 | 13,021 | 0 | 64 | PE array is much smaller than SKSE; architecture is not PE-dominant yet |
| u_spm | 1,299 | 0 | 16 | 0 | Storage is not the LUT problem |
| u_csr | 3,700 | 554 | 0 | 0 | Not a priority |
| u_configmem | 1,567 | 64 | 0 | 0 | Not a priority |
| u_dma | 221 | 391 | 0 | 0 | Not a priority |

Current top-level timing worst path:

```text
WNS = -27.219 ns
source = u_sparse_kernel_service_engine/u_sparse_loop_controller/corr_stream_data_q_reg[12]/C
destination = u_sparse_kernel_service_engine/u_score_select/sel_mem_reg[0][0]/CE
```

Conclusion: the first architecture cut must target the `CORR -> TopK` path. Moving TopK/Argmax into a pipelined PE/service reduction tree is both resource-aligned and timing-aligned. The 4x8 PE array should implement a staged reduction shape for Top1/TopK, e.g. `16 -> 8 -> 4 -> 2 -> 1` for score candidates, with registers between stages.

## TopK Phase-1 Design Requirement

Previous full rewrite of `score_select_service` failed exact OMP per-iter because it selected index 14 instead of 8 at iter0. Therefore the replacement must be introduced as a separately testable reducer and only then remove the centralized path.

Required exact behavior for Top1:

```text
candidate score = abs(corr_score)
invalid lanes ignored
zero/tiny behavior must match current ctx bit behavior
if score_a > score_b: choose a
if score_a == score_b: choose lower index
support exclusion only when current mode requests it
```

Recommended implementation boundary:

```text
corr_stream_valid/base_idx/lane_valid/score[8]
  -> pe_stream_topk_service
       stage0: lane-pair compare inside/near PE columns
       stage1: 8 -> 4 registered
       stage2: 4 -> 2 registered
       stage3: 2 -> 1 registered
  -> candidate_idx/value valid
  -> support service append primitive
```

Do not delete `score_select_service` until:

1. OMP Top1 per-iter passes.
2. MP Top1 per-iter/smoke passes.
3. OMP M64/N256/K16 remains under 250k cycles.
4. OOC top/SKSE timing improves or LUT drops substantially.

After Top1 is exact, extend the same reducer to TopK by inserting each block winner into a small ranked list or by running multiple ranked lanes, then migrate SP/CoSaMP/HTP.
