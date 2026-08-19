# CSCGRA project status and optimization inventory

Updated: 2026-08-20

This is the top-level handoff document for the repository. It separates what
is present in the current RTL from experiments that were measured and removed.

Public/paper scope: `rtl/v2` is the only active architecture line. The frozen
v1 source is archived under `archive/v1`; no new optimization or release
result should depend on it.

## 1. Current signed-off checkpoint

| Item | Current value |
|---|---:|
| RTL branch | `codex/strict-pe0-timing` |
| RTL sign-off commit | `88f9411` |
| Target | `xczu7ev-ffvc1156-2-e`, 100 MHz |
| Full K-sweep | 348 PASS / 0 FAIL |
| Measured rows | 62 |
| Expected skips | CoSaMP and SP at K16 |
| Full-sweep cycles | 1,313,368 |
| K8 cycles | 374,962 |
| WNS / TNS | +0.850 ns / 0 ns |
| LUT / FF | 121,359 / 53,281 |
| LUTRAM / SRL | 2,144 / 6 |
| RAMB36 / DSP | 24 / 71 |

The current complete matrix is
`reports/releases/topk_append_ack_chain_k_sweep_20260817.csv`.

### Hardware-golden verification and routed baseline (2026-08-20)

`models/reference/hardware.py` is now the single generator/checker for both
the active Verilog golden and `sw/v2/src/cscgra_k_sweep_golden.h`. The static
SDK/TB contract check passes, and the corrected factor-cache model has a full
valid regression result of **348 PASS / 0 FAIL** (the two K16 CoSaMP/SP skips
remain intentional).

The new implementation run is fully routed with zero routing errors and a
reproducible checkpoint at
`logs/impl/v2/hardware_golden_impl_v2/cgra_top_impl_routed.dcp`. Synthesis
remains **+0.454 ns WNS**, but post-route timing is **−1.987 ns WNS** with
13,915 setup-failing endpoints. Therefore the routed checkpoint is a clean
physical baseline, not a 100-MHz timing sign-off; the next optimization pass
must target the post-route critical paths (LDLT border/PE wide arithmetic and
fanout) while preserving the golden/TB contract.

Evolution of the configured full sweep:

| Checkpoint | Cycles | Reduction to current |
|---|---:|---:|
| RTL v1 sign-off | 3,786,690 | 2,473,322 (-65.32%) |
| Initial factor-reuse v2 | 1,902,282 | 588,914 (-30.96%) |
| Current v2 | 1,313,368 | current |

## 2. Architectural invariants now implemented

- Controller-originated streaming transactions use PE0 as their physical
  ingress and propagate through registered PE0 -> PE1 -> PE2 -> PE3 links.
- Large arithmetic assigns distinct useful work to all four physical PE rows.
- The timing-critical payload, valid, mode, owner, and tag signals are
  registered together at the relevant PE boundaries.
- The LS controller keeps at most one active LS request.
- Optimization is retained only after correctness, cycle, OOC WNS, and
  resource comparison. A small cycle gain is not enough if LUT growth is
  proportionally larger.

Four-row ownership:

| Operation | PE0 | PE1 | PE2 | PE3 |
|---|---|---|---|---|
| Correlation | sample slot mod 4 = 0 | slot 1 | slot 2 | slot 3 |
| RHS | support lane mod 4 = 0 | lane 1 | lane 2 | lane 3 |
| Gram | column `j+0` | column `j+1` | column `j+2` | column `j+3` |
| LDLT border/solve | target row `i+0` | row `i+1` | row `i+2` | row `i+3` |
| Top-K wavefront | ingress/rank stage | registered continuation | registered continuation | final commit |

## 3. Retained optimizations in the current source

### Repository and reproducibility

- Refactored the mixed Vivado project into active `rtl/v2` and archived
  `archive/v1` source trees.
- Added versioned manifests and JSON configuration; canonical flows no longer
  glob generated Vivado directories.
- Separated tracked source/reports from ignored `work/` and `logs/` products.
- Preserved C software, golden models, research material, and legacy scripts
  in clearly owned directories.

### Timing-closed PE0 wavefront

- Ported strict PE0 ingress with registered south-link payload/tag pipelines.
- Added timing isolation for support depth, PE0 mesh context, residual data,
  correlation state, and LS RHS products.
- Preserved four distinct row roles instead of duplicating the same work on
  all rows.
- Added simulation assertions for transaction ordering and representative
  wide-product correctness.

Primary RTL: `rtl/v2/pe/pe_cluster_4x4.v`, `pe_tile.v`, `pearray.v`, and
`rtl/v2/control/sparse_loop_controller.v`.

### Correlation, residual, prune, and vector update

- Correlation accepts one measurement row per clock after startup and stripes
  full-precision accumulators across four rows.
- Synchronous SPM data is cached/prefetched; direct Phi scan runs at the
  signed-off doubled rate for N64, N128, and N256 schedules.
- Residual block-8 transactions are chained through the four rows; the first
  full block is preloaded during accumulator clear.
- Prune/threshold uses strict-PE0 block-8 streaming with tail masking.
- Correlation and vector update programs are fused where valid.
- Post-update x streams directly into top-K for IHT, GP, and HTP.
- Correlation streams into top-K for OMP, GOMP, SP, and CoSaMP through a
  lossless ready/valid boundary.
- Post-refine top-K scans only the candidate support rather than the full
  vector when the algorithm permits it.

### Exact top-K and support handling

- Exact top-K ranking is a four-row PE0-to-PE3 wavefront with deterministic
  tie behavior.
- Support/mesh ingress is register-isolated for timing.
- Non-sorted top-K support appends issue the next registered 10-bit index and
  3-bit path on the registered ACK edge. This removes 1,968 full-sweep cycles
  for only 57 LUT and no WNS loss.

Primary RTL: `rtl/v2/pe/pe_stream_topk_serial_service.v`,
`rtl/v2/solver/support_set_service.vh`, and
`rtl/v2/solver/sparse_kernel_service_engine.v`.

### Least-squares and LDLT solver

- Replaced the retained Gaussian-elimination path with regularized Cholesky
  LDLT and a shared radix-4 restoring divider.
- Decomposes signed 64x64 products into 16x16 limbs mapped onto existing PE
  multipliers; no second wide multiplier array was added.
- Uses READ4/WRITE4 across eight row banks while keeping RAMB36 at 24.
- Streams four-row LDLT border transactions with phase tags and a compact
  modulo-four scoreboard mapped into per-row LUTRAM.
- Overlaps LDLT border MUL1 and MUL2 safely with slot ownership protection.
- Reuses exact factors after configuration and exact support validation;
  prefix/set extensions preserve the old factor and compute only new borders.
- Chains stable preload, diagonal READ2, WRITE4 completion, back-solve READ4,
  and shared forward-solve tail transitions where timing and resource gates
  pass.
- Pipelines the four-row RHS product boundary for WNS margin.
- Overlaps Gram production/drain, retains a one-entry ACC4 queue, removes the
  final safe guard interval, and preloads the first residual block.

Primary RTL: `rtl/v2/control/sparse_loop_controller.v` and
`rtl/v2/solver/ls_matrix_service.v`.

### Verification and profiling infrastructure

- Canonical K-sweep covers eight M/N/K cases and eight algorithms.
- Reports cycles per algorithm rather than aggregate-only results.
- State profiling covers controller, top-K, support service, uop class, and
  internal wide-multiplier state.
- Golden vectors remain independent; they are not edited to make RTL pass.
- OOC flow records utilization and timing for a fixed part and 10 ns clock.
- Every canonical run gets an isolated run ID and metadata in ignored output
  directories.

## 4. Important measured trials not present in current RTL

These experiments are documented for provenance but were reverted:

| Trial | Decision |
|---|---|
| QR solver | Study only; not implemented. LDLT remains the active solver. |
| ACC4 two-column banking | Rejected: large LUT/LUTRAM/DSP growth. |
| RHS_WRITE4 inferred multi-write | Rejected: +9.73% LUT for -0.294% K8 cycles. |
| Bounded LS clear | Rejected: weak gain and large LUT growth; fine bound also failed correctness. |
| LDLT READ4 completion chaining | Rejected: resource growth exceeded cycle benefit. |
| Wide-multiplier COMMIT/FINAL fusion | Rejected: +5.71% LUT and WNS reduced to +0.205 ns. |
| Higher-radix divider | Not implemented: no idle divide-step bubble and excessive timing risk. |
| Factor-check INIT/DONE bypass | Rejected after timing/resource/profile study. |
| LS solve-setup shortcuts | Rejected after correctness or poor cost/benefit. |
| Correlation INIT bypass | Rejected; no safe resource-neutral saving. |
| Gram zero-guard removal | Rejected; unsafe queue/drain cadence. |
| Earlier READ2/READ4 fast-start forms | Rejected or superseded; do not reintroduce completion feedback. |

Detailed rejected-trial reports are indexed in `reports/README.md`.

## 5. Folder ownership

| Folder | Contents and authority |
|---|---|
| `rtl/v2` | Current synthesizable source of truth. |
| `archive/v1` | Frozen v1 RTL, verification, and software snapshot. |
| `verification/v2` | Active testbenches and compiled golden vectors. |
| `sw/v2` | Active bare-metal C and generated headers. |
| `models` | Reference/golden model source; not synthesizable RTL. |
| `scripts` | Canonical sim/synth/maintenance entrypoints. |
| `config` | Version-to-manifest/testbench/top/part mapping. |
| `reports/releases` | Reviewed sign-offs, rejected-trial reports, and cycle CSVs. |
| `docs` | Architecture, status, layout rules, and continuation notes. |
| `archive/research` | Reproducible experiments and paper-analysis assets; not release RTL. |
| `archive/fpga` | Historical board/platform notes; generated projects excluded. |
| `work` | Disposable tool state; ignored except README. |
| `logs` | Disposable raw logs/reports; ignored except README. |
| `CSCGRA_opt_architecture_opt2` | Ignored pre-refactor workspace if present locally; not authoritative or public source. |

## 6. Canonical verification

```powershell
.\scripts\run.ps1 -Flow sim -RtlVersion v2 -RunId current-full
.\scripts\run.ps1 -Flow sim -RtlVersion v2 -Cases 1 -ProfileStates -RunId current-k8-profile
.\scripts\run.ps1 -Flow synth -RtlVersion v2 -Top cgra_top -RunId current-ooc
```

Acceptance for future RTL changes:

1. focused correctness first;
2. K8 45 PASS / 0 FAIL and per-algorithm cycle comparison;
3. OOC WNS >= +0.2 ns, no DSP/BRAM growth unless explicitly approved;
4. cycle-reduction percentage must exceed LUT-growth percentage;
5. full K-sweep 348 PASS / 0 FAIL before commit/push.

## 7. Next controlled candidate

The next narrow registered boundary is sorted top-K append ACK to scan position
zero. K8 `S_SORT_WAIT` residency is 256 clocks. A trial may fold only the first
comparison into the ACK edge using the existing result list and used mask. It
must be stopped if it creates a wide new mux, harms WNS, or costs more LUT
percentage than cycle percentage.
