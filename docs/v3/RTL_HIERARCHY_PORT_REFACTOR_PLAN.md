# V3 RTL Hierarchy, Port, and Coding-Style Refactor Plan

Date: 2026-09-05

## 1. Objective

Refactor the V3 RTL into a functional hierarchy that is easier to understand,
verify, synthesize, and debug without changing algorithm behavior, fixed-point
arithmetic, handshake latency, or cycle count.

The refactor must establish:

- one clear owner for every stateful resource;
- one-way dependency from platform to primitive;
- short and consistent public interfaces;
- explicit request/response and stream boundaries between subsystems;
- small controllers and datapath engines instead of milestone-sized modules;
- current-source correctness evidence before timing or resource sign-off.

This is an incremental migration. Compatibility wrappers remain in place until
all production instantiations and tests use the new functional hierarchy.

## 2. Current Baseline and Constraints

The V3 tree currently contains approximately 79 RTL files, 73 modules, and
21,344 lines. Several integration modules combine orchestration, resource
ownership, datapath routing, status collection, and debug logic in one file.

The largest refactor targets are:

| Current module | Approximate size | Primary issue |
| --- | ---: | --- |
| `m8_operator_harness` | 1,911 lines | Owns most datapath subsystems and cross-coupled control |
| `support_state_manager` | 1,028 lines | Selection state, storage, remap, and lifecycle coupling |
| `m8_resource_dispatcher` | 951 lines | Decode, arbitration, resource control, and status coupling |
| `m13_compute_lifecycle_integration` | 748 lines | Runtime and datapath integration mixed together |
| `vector_stream_engine` | 626 lines | Stream control and memory movement mixed together |
| `m12_lifecycle_top` | 603 lines | Lifecycle policy mixed with compatibility integration |

Current-source small-matrix correctness is closed for the Phase 1 source. The
`m16_n24_k4_seed1` matrix passed all 8 algorithms and 3 profiles. Scale-matrix
correctness remains pending and every later phase must regenerate evidence from
its own source state.

The following constraints apply to every migration patch:

1. Golden artifacts are immutable during RTL debug.
2. No tolerance is added to mask RTL/golden mismatches.
3. No arithmetic and structural refactor are combined in one patch.
4. No interface latency, ordering, or backpressure behavior changes unless the
   change is separately specified and cycle-regressed.
5. No synthesis, placement, or routing directives are used to hide RTL issues.
6. Full M13 synthesis does not begin until correctness is closed against the
   current source hash.

## 3. Target Hierarchy

```text
zcu106_reconstruction_top
└── reconstruction_accelerator_core
    ├── host_control_subsystem
    │   ├── axil_register_bank
    │   ├── configuration_loader_aperture
    │   └── host_status_adapter
    ├── reconstruction_runtime
    │   ├── configuration_manager
    │   ├── microcode_store
    │   ├── microcode_sequencer
    │   ├── lifecycle_controller
    │   └── termination_controller
    ├── reconstruction_datapath
    │   ├── scratchpad_subsystem
    │   │   ├── scratchpad_port_arbiter
    │   │   ├── vector_stream_engine
    │   │   └── vector_scratchpad
    │   ├── phi_stream_subsystem
    │   │   ├── phi_stream_provider
    │   │   ├── phi_support_cache
    │   │   ├── phi_symbol_generator
    │   │   └── phi_operator_normalizer
    │   ├── cgra_execution_fabric
    │   │   ├── context_router
    │   │   ├── cgra_cluster_pair
    │   │   ├── column_connector
    │   │   └── heterogeneous_pe_array
    │   ├── vector_arithmetic_subsystem
    │   │   ├── array_resource_router
    │   │   ├── reduction_pipeline
    │   │   ├── scalar_function_unit
    │   │   └── scalar_register_file
    │   ├── sparse_selection_subsystem
    │   │   ├── candidate_collector
    │   │   ├── topk_selector
    │   │   ├── support_workspace
    │   │   ├── support_state_controller
    │   │   └── coefficient_remapper
    │   └── refinement_subsystem
    │       ├── restricted_refinement_controller
    │       └── normal_residual_checker
    ├── memory_service_subsystem
    ├── result_writeback_subsystem
    └── debug_monitor_subsystem
```

The required dependency direction is:

```text
platform -> core -> subsystem -> engine/controller -> primitive
```

A lower layer must never instantiate or depend on a higher layer. A subsystem
may only access another subsystem through its public interface.

## 4. Ownership Rules

1. A stateful resource has exactly one owner module.
2. The owner performs arbitration and exposes a public interface.
3. Clients do not access an owner's internal RAM, cursor, counter, or state.
4. Configuration state belongs to runtime/configuration modules, not datapath
   primitives.
5. Datapath status is observed by the debug subsystem; debug logic does not
   control datapath behavior.
6. Compatibility wrappers may translate old ports but may not duplicate state.

Initial ownership allocation:

| Resource | Owner |
| --- | --- |
| Phi provider and support cache | `phi_stream_subsystem` |
| Scratchpad banks and port arbitration | `scratchpad_subsystem` |
| PE context and connector routing | `cgra_execution_fabric` |
| Scalar and reduction resources | `vector_arithmetic_subsystem` |
| Candidate/support state | `sparse_selection_subsystem` |
| Restricted LS/refinement state | `refinement_subsystem` |
| Algorithm phase and microcode PC | `reconstruction_runtime` |
| Result memory and completion writeback | `result_writeback_subsystem` |

## 5. Module Rename Map

Renames are introduced through wrappers. The old module remains available until
all production and verification instantiations have migrated.

| Current module | Functional module |
| --- | --- |
| `m13_zcu106_shell_core` | `zcu106_reconstruction_core` |
| `m13_compute_lifecycle_integration` | `reconstruction_accelerator_core` |
| `m12_lifecycle_top` | `reconstruction_runtime` |
| `m8_operator_harness` | `reconstruction_datapath` |
| `m8_resource_dispatcher` | `compute_resource_dispatcher` |
| `m5_arithmetic_subsystem` | `vector_arithmetic_subsystem` |
| `m9b_support_subsystem` | `sparse_selection_subsystem` |
| `m13_loader_aperture` | `configuration_loader_aperture` |
| `stream_context_router` | `context_router` |
| `proxy_candidate_collector` | `candidate_collector` |

Files with multiple primary modules are split after their public interfaces are
stable:

- `pe_alu.v`: split `pe_alu` and `phi_pe_alu`;
- `pe_tile.v`: split `pe_tile` and `phi_pe_tile`;
- `proxy_candidate_collector.v`: split collector and
  `support_gradient_store`.

## 6. Port and Signal Conventions

### 6.1 Request and response

```text
cmd_valid, cmd_ready, cmd_op, cmd_tag, cmd_data
rsp_valid, rsp_ready, rsp_tag, rsp_status, rsp_data
```

Use a subsystem prefix only when two interfaces of the same type exist in one
scope. Do not repeat the module name in every port.

### 6.2 Streams

```text
in_valid, in_ready, in_data, in_last, in_tag
out_valid, out_ready, out_data, out_last, out_tag
```

For structured Phi symbols, use `out_mask`, `out_sign`, `out_col`, `out_row`,
and `out_tag` instead of a packed bus while the payload remains internal to V3.

### 6.3 Cache replay

```text
cache_req_valid, cache_req_ready, cache_req_slot, cache_req_row, cache_req_tag
cache_rsp_valid, cache_rsp_ready, cache_rsp_mask, cache_rsp_sign
cache_rsp_col, cache_rsp_row, cache_rsp_tag
```

### 6.4 State and events

- Sequential state: `_q`.
- Combinational next state: `_d`.
- Accepted handshake: `*_fire`.
- One-cycle event: `*_event`.
- Sticky error: `*_fault_q` or `*_error_q`.
- Active mode predicate: `*_active` or `*_enable`.
- Counts describe quantity; indices and addresses describe location.

### 6.5 Width and type rules

1. Widths use architecture macros or named localparams.
2. Signed arithmetic ports and registers explicitly declare `signed`.
3. No unsized constants in arithmetic or comparisons.
4. Fixed-point format is documented at the subsystem boundary.
5. Conversions, shifts, saturation, and rounding occur in named modules or
   named expressions, never inside an unrelated control predicate.

## 7. Coding-Style Rules

1. Keep one primary module per file.
2. Prefer modules below 400 lines and controllers below 250 lines.
3. Split state update, next-state calculation, and datapath calculation.
4. Avoid ternary expressions nested beyond one level.
5. Avoid `if` nesting beyond approximately three levels; extract named
   predicates, events, or helper modules.
6. Use one assignment location for each register.
7. Group declarations by interface or owned resource, not by creation order.
8. Decode packed contexts once into named fields at the boundary.
9. Replace milestone names in new code; compatibility modules may retain them.
10. Do not add synthesis attributes unless they are required for a verified
    primitive contract and documented with an inference test.

## 8. Debug and Status Contract

Every major subsystem exposes a compact status interface:

```text
status_busy
status_done
status_fault
status_code
status_state
status_progress
```

Additional trace signals are collected by `debug_monitor_subsystem`, including:

- algorithm ID, profile, iteration, phase PC, and array PC;
- active command and accepted command event;
- outstanding request count and oldest request tag;
- cache state, replay request, replay response, and FIFO occupancy;
- stream valid/ready/fire events;
- saturation, contract, ordering, and timeout sources.

Debug signals are observational. They must not feed functional control paths.

## 9. Migration Phases

### Phase 0: Baseline and guards

- Record source hash and dirty-file list.
- Confirm generated golden ownership and freshness checks.
- Reproduce the smallest current correctness failure.
- Keep historical results labeled as stale, not PASS.

Exit gate: deterministic reproduction and preserved failure evidence.

### Phase 1: Phi ownership and interface cleanup

- Add `phi_stream_subsystem` as a compatibility owner for the existing
  `phi_stream_provider` and `support_phi_symbol_cache`.
- Move internal/external cache selection, refill, capture, and replay wiring out
  of `m8_operator_harness`.
- Rename the public replay interface to `cache_req_*` and `cache_rsp_*` inside
  the new subsystem while preserving old top-level ports.
- Keep provider/cache state machines and latency unchanged.
- Isolate and fix the cache replay deadlock only after the structural patch
  passes directed tests.

Exit gate: M7 directed PASS, M8 directed PASS, OMP strict single-case PASS.

### Phase 2: Scratchpad subsystem

- Extract scratchpad ownership, preload arbitration, stream ports, and conflict
  reporting.
- Decode scratchpad requests at one boundary.
- Keep RAM primitive and read latency unchanged.

Exit gate: scratchpad directed tests, M8 directed tests, OMP/CoSaMP guards.

### Phase 3: CGRA execution fabric

- Extract context router, cluster pair, column connector, PE array, and result
  capture.
- Make connector ownership and physical replica mapping explicit.
- Split Phi-specific PE modules into separate files.

Exit gate: CGRA directed tests, context-image regression, 8-algorithm small
matrix.

### Phase 4: Arithmetic subsystem

- Rename and isolate scalar, vector, and reduction services.
- Separate arbitration from arithmetic datapaths.
- Preserve reduction order and fixed-point saturation behavior.

Exit gate: arithmetic directed tests, strict coefficient comparison, small
matrix `24/24`.

### Phase 5: Selection and refinement

- Split collector, Top-K, support workspace, support state, remap, and
  refinement ownership.
- Replace dense cross-module buses with indexed request/response access where
  already cycle-equivalent.
- Remove duplicate support/coefficient state only after equivalence evidence.

Exit gate: selection/refinement directed tests and both correctness matrices.

### Phase 6: Runtime and core hierarchy

- Replace M12/M13 integration names with runtime/core wrappers.
- Keep C/microcode ownership contract: software loads configuration and
  microcode; the sequencer controls execution.
- Move debug aggregation out of functional controllers.

Exit gate: current-source small `24/24`, scale `24/24`, and production medical
quality gate.

### Phase 7: Compatibility removal

- Migrate all testbenches and scripts to functional top names.
- Remove old milestone wrappers only after no production or verification
  dependency remains.
- Update source manifest and documentation.

Exit gate: lint, elaboration, complete correctness matrix, and clean dependency
audit.

### Phase 8: Cycle, LUT/FF, and timing optimization

- Measure cycle count per algorithm, profile, and geometry.
- Optimize RTL structure before adding physical implementation constraints.
- Infer reusable RAM/FIFO modules instead of flattening storage into LUTs.
- Synthesize at 100 MHz only after correctness closure.
- Report cycles, latency, LUT, FF, BRAM, DSP, WNS, WHS, DRC, and PDRC together.

Exit gate: current-source correctness plus final routed 100 MHz reports.

## 10. Regression Ladder

Run the narrowest applicable checks after every patch:

1. Compile/lint the changed subsystem.
2. Run its directed tests.
3. Run M8 integration tests for datapath changes.
4. Run OMP strict `m16_n24_k4_seed1` as the first production guard.
5. Run OMP `3/3` and CoSaMP `3/3`.
6. Run the small 8 algorithms x 3 profiles matrix (`24/24`).
7. Run the scale 8 algorithms x 3 profiles matrix (`24/24`).
8. Run medical MRI/ECG quality gates when numeric behavior changes.

No later gate can compensate for a failed earlier gate.

## 11. Review Checklist

Before merging each phase:

- Does every register have one owner and one assignment location?
- Are all cross-subsystem paths public interfaces?
- Are valid/ready paths free of accidental combinational loops?
- Are request and response tags preserved under backpressure?
- Are fixed-point widths, signedness, shifts, and saturation unchanged?
- Are all state and event names consistent with `_q`, `_d`, and `*_fire`?
- Are new module names functional rather than milestone-based?
- Do directed tests and required correctness gates use the current source hash?
- Are cycle deltas explained rather than silently accepted?
- Are synthesis and timing claims based on final reports only?

## 12. Immediate Execution Order

1. Keep Phase 1 Phi ownership closed behind `phi_stream_subsystem`.
2. Extract scratchpad arbitration and memory ownership into
   `scratchpad_subsystem`.
3. Update manifests and white-box verification paths without legacy aliases.
4. Run M8 directed regressions.
5. Run the small 8-algorithm x 3-profile matrix.
6. Run the scale matrix only after Phase 2 is stable.
7. Continue with CGRA execution-fabric extraction after both Phase 2 gates.

## 13. Execution Status

Status on 2026-09-05:

- Plan and hierarchy rules documented.
- Added `phi_stream_subsystem` as the owner of the existing Phi provider and
  support cache.
- Moved Phi mode, capture policy, refill slot, and candidate release state out
  of `m8_operator_harness`.
- Replaced provider/cache integration wiring with short command, stream,
  cache-request, cache-response, and status port groups.
- Updated the V3 manifest and M7/M8 simulation, formal-compile, and OOC source
  lists.
- Full V3 parse and `m8_operator_harness` elaboration completed successfully.
- M7 directed regression passed.
- M8 operator-harness and nested-operator tests passed.
- M8 nested-sequencer passed after separating functional support membership
  bitmap state from optional debug bitmap exposure in `support_workspace`.
- `support_vector_rebuilder` now uses explicit selected/support match stages and
  a readable mode `case` instead of a nested output ternary.
- Small production matrix `m16_n24_k4_seed1` passed 24/24: 8 algorithms x 3
  profiles, with strict coefficient comparison and unchanged golden artifacts.
- Added `scratchpad_subsystem` as the owner of preload/init/stream arbitration,
  conflict detection, registered loader acknowledgement, and
  `vector_scratchpad`.
- M8 operator, nested-operator, and nested-sequencer regressions pass after the
  scratchpad extraction.
- Phase 2 small and scale matrices both pass 24/24 with zero cycle delta against
  their pre-extraction baselines.
- Added `cgra_execution_fabric` as the owner of stream-context routing, cluster
  enable decode, the two-cluster array, and its physical column connector.
- M4 transport/DMA, M6 PE/cluster, and all M8 directed regressions pass after
  the CGRA wrapper migration.
- Phase 3 small and scale matrices both pass 24/24 with zero cycle delta against
  the Phase 2 baselines.
- Added `cgra_result_buffer` under `cgra_execution_fabric`; the harness now
  emits explicit clear, capture, low/high completion, and D18/S27 consume
  events instead of owning result-buffer registers.
- The M6 directed test verifies all 32 payload lanes, low/high completion,
  two-phase S27 consumption, and D18 consume priority.
- Result-buffer small and scale matrices both pass 24/24 with zero cycle delta
  against the pre-extraction CGRA wrapper baseline.
- Split `phi_pe_alu` and `phi_pe_tile` into dedicated source files without
  changing either datapath; M6 property elaboration, M6, M8, and both matrix
  gates pass.
- Added `scalar_state_subsystem` as the owner of scalar preload arbitration,
  scalar register state, algorithm scalar capture, and gamma/beta shadow state.
- Corrected `array_resource_router` reduction auto-retire so only
  `TOPK_STATE` responses retire automatically; scalar reduction writeback now
  remains available until the explicit consume contract.
- M5 directed and embedded-property runs pass after the scalar extraction and
  router contract correction.
- Scalar-state small and scale matrices both pass 24/24 with zero cycle delta
  against the Phi PE split baselines.
- Added `cgra_result_capture_adapter` as the owner of solver-to-residual
  conversion, D18/S27 format selection, capture payload generation, and ordered
  consume events.
- Capture-adapter small and scale matrices both pass 24/24 with zero cycle
  delta against the scalar-state baselines.
- Added `reduction_pipeline` as the owner of both cluster reduction trees and
  the global merge; `m5_arithmetic_subsystem` now sees one compact reduction
  request/response boundary.
- M5 directed regression and property elaboration pass after the reduction
  extraction; reduction latency remains five cycles.
- M8 operator, nested-operator, nested-sequencer, and resident replay tests pass
  through the new functional hierarchy.
- M6 PE, result-buffer, cluster-pair, and connector regression remains PASS.
- Reduction-pipeline small and scale matrices both pass 24/24 with zero cycle
  delta against the capture-adapter baselines.
- Added `shared_vector_pipeline` as the functional boundary for the shared
  vector datapath with compact `req_*`/`rsp_*` ports; the legacy M5 wrapper
  remains only for integration compatibility.
- Shared-vector-pipeline small and scale matrices both pass 24/24 with zero
  cycle delta against the reduction-pipeline baselines.

Next checkpoint:

1. Keep `support_refinement_adapter` as the owner of fresh-refinement state,
   support-vector rebuild, stripe fetch buffering, and masked-copy position.
2. Extract vector candidate serialization and support-index remapping from
   `m8_operator_harness` behind a functional candidate-stream boundary.
3. Split column completion, reduction-column queueing, and normalized candidate
   queueing into a column-flow subsystem.
4. Replace milestone-facing integration ports only after all production and
   verification users have migrated to functional interfaces.
5. Re-run M5, M6, M8, and both `24/24` matrices after each structural patch.

Checkpoint on 2026-09-05:

- Added `rtl/v3/selection/support_refinement_adapter.v`.
- Moved fresh-refinement tracking, support rebuild mode decode, coefficient
  stripe request/buffer state, and masked-copy cursor ownership out of
  `m8_operator_harness`.
- Updated M13 white-box debug paths to the functional subsystem hierarchy;
  no production debug aliases were added.
- `m8_operator_harness` is reduced from 1,805 to 1,751 lines.
- M5 arithmetic/resource-router, M6 CGRA, and all M8 directed tests pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the `shared_vector_pipeline` checkpoint is 0/24 for both
  matrices.
- No synthesis, implementation, timing, or resource claim is made at this
  checkpoint.

Candidate-stream follow-up on 2026-09-05:

- Added `rtl/v3/selection/candidate_stream_adapter.v`.
- Moved TOP-K/support-scatter mode decode, candidate serialization, and
  support-slot-to-atom remapping out of `m8_operator_harness`.
- Updated M13 white-box paths to `u_candidate_stream.u_serializer`; no legacy
  candidate aliases were retained for debug.
- `m8_operator_harness` is now 1,728 lines.
- All M8 directed tests pass, including resident replay for all eight
  algorithms.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the support/refinement adapter checkpoint is 0/24 for
  both matrices.
- The next owner to extract is column completion, reduction-column queueing,
  normalizer response capture, and normalized candidate buffering.

Column-flow follow-up on 2026-09-05:

- Added `rtl/v3/phi/phi_column_flow.v` as the owner of Phi stream ordering,
  completed-column state, reduction-column queueing, reduction response
  capture, and normalized-candidate buffering.
- Moved candidate arbitration and release events behind the same functional
  boundary while preserving vector-candidate priority and D18/S27 ordering.
- Updated the M8 and M13 white-box checks to follow `u_column_flow`; no legacy
  state aliases were added to `m8_operator_harness`.
- Added the subsystem to `rtl/v3/files.f`, the M8 simulation source list, and
  the M8 OOC synthesis source list.
- `m8_operator_harness` is reduced from 1,728 to 1,567 lines.
- M5 arithmetic/resource-router, M6 CGRA, and all M8 directed tests pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the candidate-stream checkpoint is 0/24 for both
  matrices.
- No synthesis, implementation, timing, LUT, FF, BRAM, or DSP claim is made
  at this checkpoint.

Next checkpoint:

1. Audit the remaining `m8_operator_harness` responsibilities and group them
   by functional ownership rather than phase or milestone numbering.
2. Migrate milestone-facing integration ports only where all callers can move
   to a compact request/response or event interface in the same patch.
3. Preserve the M5, M6, M8, small-matrix, scale-matrix, and zero-cycle-delta
   gates for every subsequent extraction.

Remaining-ownership audit follow-up on 2026-09-05:

- Added `rtl/v3/debug/operator_fault_monitor.v` as the owner of pending and
  sticky operator-fault state. The existing one-cycle event-to-sticky latency
  and 16-bit detail encoding are unchanged.
- Added `rtl/v3/data_movement/vector_ingress_adapter.v` as the owner of
  support-scalar serialization, D18-to-solver expansion, transpose pair/gather
  assembly, scalar routing, and vector transport commit qualification.
- Moved the coefficient canonicalization function and transpose assertions to
  the vector-ingress owner.
- Updated M8/M13 white-box paths to `u_fault_monitor` and
  `u_vector_ingress`; no compatibility registers remain in the harness.
- `m8_operator_harness` is reduced from 1,567 to 1,380 lines.
- M5 arithmetic/resource-router, M6 CGRA, and all M8 directed tests pass.
- Fault-monitor small and scale matrices both pass 24/24 with zero cycle delta
  against the column-flow checkpoint.
- Vector-ingress small and scale matrices both pass 24/24 with zero cycle
  delta against the fault-monitor checkpoint.
- No synthesis, implementation, timing, or resource claim is made.

Next ownership boundaries:

1. Extract normalized-result writeback state: memory-mode pending, 16-lane
   scalar pack, pack index, output count, and transpose write release.
2. Extract Phi-lane normalization and fused norm accumulation after writeback
   ownership is stable.
3. Keep resident work-count state in the harness until its lifecycle owner is
   identified across routine start, abort, and support updates.

Normalized-writeback follow-up completed on 2026-09-06:

- Added `rtl/v3/data_movement/normalized_result_writeback.v` as the owner of
  reduction-memory pending state, 16-lane S27 packing, pack/output counters,
  scalar pending state, and transpose write mode/final/release generation.
- Kept the D18/S27 write order and the normalizer-to-memory ready/valid
  contract unchanged.
- Moved M13 white-box writeback checks to `u_normalized_writeback`; no debug
  compatibility registers were retained in `m8_operator_harness`.
- `m8_operator_harness` was reduced from 1,380 to 1,359 lines.
- M5 arithmetic/resource-router, M6 CGRA, and all M8 directed tests pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the vector-ingress checkpoint is 0/24 for both matrices.

Phi-lane normalization follow-up completed on 2026-09-06:

- Added `rtl/v3/phi/phi_lane_normalization_flow.v` as the owner of normalizer
  input arbitration, 32-lane capture/issue/drain sequencing, residual capture
  metadata, forward-row tracking, square-product staging, gamma/residual norm
  accumulation, and fused-scalar ready/valid state.
- Moved the `phi_operator_normalizer` instance into the functional subsystem;
  column normalization, transpose-memory normalization, and lane normalization
  still share the same pipeline and arbitration priority.
- Updated M8 and M13 white-box paths to `u_phi_lane_flow`; no legacy Phi-lane
  state aliases were added for verification.
- `m8_operator_harness` is reduced from 1,359 to 1,251 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm resident replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the normalized-writeback checkpoint is 0/24 for both
  matrices.
- No synthesis, implementation, timing, LUT, FF, BRAM, DSP, or route claim is
  made for either checkpoint.

Next ownership boundary:

1. Audit the remaining 1,251-line harness and isolate resident work-count and
   any remaining lifecycle-coupled state behind explicit functional events.
2. Migrate long milestone-facing ports only when every caller can move in the
   same patch without compatibility aliases.
3. Preserve M5, M6, M8, small/scale 24/24, and zero-cycle-delta gates before
   starting synthesis or timing/resource optimization.

Resident-execution-state checkpoint completed on 2026-09-06:

- Added `rtl/v3/reconstruction_control/resident_execution_state.v` as the
  owner of scalar-preload acknowledgement, algorithm-preload history, and the
  resident work-count snapshot.
- Preserved the original independent reset semantics: preload history resets
  only with `rst_n`/`scalar_state_clear`, while resident work count updates on
  reset, abort, or routine start with support-count priority at routine start.
- Removed `resident_work_count_reg`, `scalar_preload_ready_q`, and
  `algorithm_preload_seen` procedural ownership from `m8_operator_harness`.
- `m8_operator_harness` is reduced from 1,251 to 1,234 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm resident replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the Phi-lane checkpoint is 0/24 for both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Next checkpoint:

1. Extract the 16-bank `scratchpad_word_codec` array and vector write payload
   selection into a vector-codec/write subsystem.
2. Preserve D18 half selection, S27 write packing, normalized scalar packing,
   write-valid/error vectors, and `write_payload_ready` combinational timing.
3. Re-run the complete correctness and zero-cycle-delta gates before moving
   fault encoding or top-level flow control.

Vector-codec/write checkpoint completed on 2026-09-06:

- Added `rtl/v3/data_movement/vector_codec_write_subsystem.v` as the owner of
  eight-bank vector A/B decoding, eight-bank write packing, D18/S27 payload
  selection, per-bank valid/error reporting, and write-payload readiness.
- Preserved all 24 `scratchpad_word_codec` instances and the original mux
  priority: transpose scalar pack, CGRA low/high S27 halves, shared-vector
  result, and D18 CGRA/lane-result selection.
- Updated M8/M13 white-box debug paths to `u_vector_codec`; no verification
  aliases were added to the harness.
- `m8_operator_harness` is reduced from 1,234 to 1,190 lines.
- M5 arithmetic/resource-router, M6 CGRA, M8 operator/nested/replay tests pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the resident-state checkpoint is 0/24 for both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Next checkpoint:

1. Split fault-event combinational encoding from sticky fault storage.
2. Split stream/resource readiness and cache-capture blocking into explicit
   operator flow control after fault encoding is independently verified.
3. Keep fault bit ordering, one-cycle event-to-sticky latency, backpressure,
   and cycle count unchanged.

Fault-event and operator-flow checkpoint completed on 2026-09-06:

- Added `rtl/v3/debug/operator_fault_event_encoder.v` as the combinational
  owner of operator fault qualification, transpose configuration checks,
  padded measurement count, and the existing 16-bit fault-detail encoding.
- Added `rtl/v3/integration/operator_flow_control.v` as the combinational owner
  of cache-capture blocking and stream/resource ready qualification.
- Kept `operator_fault_monitor` limited to the existing one-cycle pending and
  sticky fault state; no fault latency or bit position changed.
- Updated M8/M13 white-box paths to `u_fault_encoder` without compatibility
  aliases.
- `m8_operator_harness` is 1,192 lines after replacing the flattened equations
  with explicit subsystem interfaces.
- M5 arithmetic/resource-router, M6 CGRA, M8 operator/nested/replay tests pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the vector-codec checkpoint is 0/24 for both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Next checkpoint:

1. Audit every remaining `m8_operator_harness` port against its production and
   verification callers.
2. Rename only complete functional groups whose callers can migrate in the
   same patch; do not retain milestone-name compatibility aliases.
3. Prefer compact functional names inside subsystems before changing the
   externally visible harness contract.

Lifecycle/scalar-load port checkpoint completed on 2026-09-06:

- Renamed the first complete public port group on `m8_operator_harness`:
  `abort_flush` to `run_abort`, `routine_start` to `run_start`,
  `scalar_state_clear` to `scalar_clear`, `scalar_preload_*` to
  `scalar_load_*`, and `resident_work_count` to `resident_count`.
- Renamed the one-bit scalar register selector from `address` to `select` so
  the interface describes its actual function rather than implying a memory
  address.
- Migrated the production caller and all three M8 callers in the same patch;
  no compatibility aliases or duplicate nets were retained in the harness.
- Updated M13 white-box diagnostics to follow `run_start` and
  `resident_count` directly.
- Internal subsystem contracts were intentionally left unchanged; this patch
  normalizes only the external harness boundary and does not propagate naming
  churn through otherwise stable functional modules.
- `m8_operator_harness` remains 1,192 lines; no register, mux, handshake,
  latency, fixed-point operation, or instruction behavior changed.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the fault/flow checkpoint is 0/24 for both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_lifecycle_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_lifecycle_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Normalize the complete active-configuration input group without changing
   packed configuration data or decode ownership.
2. Migrate the production caller and all M8 testbench callers atomically,
   without compatibility aliases.
3. Re-run M5, M6, M8, both 24/24 matrices, and zero-cycle-delta comparison
   before moving to the Phi cache/replay port group.

Active-configuration port checkpoint completed on 2026-09-06:

- Renamed the complete runtime configuration group on `m8_operator_harness`
  to `cfg_seed`, `cfg_measurement_count`, `cfg_signal_length`,
  `cfg_work_count`, `cfg_selection_k`, `cfg_normal_residual_shift`,
  `cfg_refinement_profile`, `cfg_refine_limit`, `cfg_residual_limit`,
  `cfg_phi_scale_mantissa_uq17`, and `cfg_phi_scale_exponent`.
- Removed the redundant `active_` and ambiguous unprefixed normalizer names at
  the harness boundary while retaining every original width and value.
- Migrated `m13_compute_lifecycle_integration` and all three direct M8 callers
  in the same patch; no compatibility aliases were introduced.
- Internal owners still receive the same configuration values on the same
  cycle; packed vector/Phi configuration words and decode semantics did not
  change.
- `m8_operator_harness` remains 1,192 lines; no datapath, register, latency,
  handshake, fixed-point, or microcode behavior changed.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the lifecycle/scalar-load port checkpoint is 0/24 for
  both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_config_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_config_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Normalize the external Phi support/cache replay group to explicit
   request/response names while preserving internal cache ownership.
2. Keep response tags, replay slot ordering, ready/valid timing, and cache
   validity semantics unchanged; do not add compatibility aliases.
3. Re-run the full gate and compare cycles against this configuration-port
   checkpoint before changing scratch preload or result/status ports.

Phi support/cache request-response port checkpoint completed on 2026-09-06:

- Renamed the support-column input stream to `phi_support_valid`,
  `phi_support_ready`, and `phi_support_col`.
- Renamed the external cache replay request channel to
  `phi_cache_req_valid`, `phi_cache_req_ready`, `phi_cache_req_slot`,
  `phi_cache_req_row`, and `phi_cache_req_tag`.
- Renamed the external cache response channel to `phi_cache_rsp_valid`,
  `phi_cache_rsp_ready`, `phi_cache_rsp_mask`, `phi_cache_rsp_sign`,
  `phi_cache_rsp_col`, `phi_cache_rsp_row`, and `phi_cache_rsp_tag`.
- Renamed the external validity state to `phi_cache_ext_valid`, separating it
  from the internal cache-valid status owned by `phi_stream_subsystem`.
- Migrated the production caller, all direct M8 callers, and M13 white-box
  diagnostics in the same patch without compatibility aliases.
- Kept `phi_stream_subsystem` request/response ownership unchanged; no FIFO,
  register, tag, slot, row, ready/valid, or cache-valid behavior changed.
- `m8_operator_harness` remains 1,192 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the active-configuration port checkpoint is 0/24 for
  both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_phi_interface_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_phi_interface_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Normalize scratch initialization and dual-port preload as complete
   `scratch_init_*` and `scratch_load_*` interfaces.
2. Preserve bank masks, packed address/data lane ordering, conflict reporting,
   and ready/valid timing without compatibility aliases.
3. Re-run the full gate and compare cycles against this Phi-interface
   checkpoint before changing stream/resource or result/status ports.

Scratch initialization/load port checkpoint completed on 2026-09-06:

- Kept the initialization request channel as `scratch_init_*` and renamed its
  payload from `scratch_init_data` to `scratch_init_wr_data`.
- Renamed the dual-port preload contract from `scratch_preload_*` to
  `scratch_load_*`.
- Renamed each preload `mask` to `bank_mask` and each write payload to
  `wr_data`, making the eight-bank packed interface explicit.
- Migrated `m13_compute_lifecycle_integration`, all three direct M8 callers,
  and M13 white-box diagnostics atomically without compatibility aliases.
- Preserved P0/P1 priority, eight 9-bit packed addresses, eight 72-bit packed
  data words, bank-bit ordering, write enables, conflict reporting, and
  combinational ready/valid behavior.
- Internal `scratchpad_subsystem` ports remain unchanged; only the public
  harness contract was normalized.
- `m8_operator_harness` remains 1,192 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and eight-algorithm replay pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the Phi support/cache interface checkpoint is 0/24 for
  both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_scratch_interface_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_scratch_interface_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Audit the remaining execution/context and stream/resource boundary ports;
   rename only one complete functional group per patch.
2. Preserve packed context widths, ready qualification, fault blocking, and
   cycle-commit semantics without compatibility aliases.
3. Re-run the full gate before normalizing result/status outputs or starting
   M8 OOC synthesis.

Packed-context port checkpoint completed on 2026-09-06:

- Renamed the complete packed context input group on `m8_operator_harness` to
  `ctx_tile`, `ctx_array`, `ctx_stream`, `ctx_resource`, and
  `ctx_predicates`.
- Migrated the production M13 caller and all direct M8 callers atomically
  without compatibility aliases.
- Preserved every packed width, bit position, signedness interpretation,
  context decode expression, predicate ordering, and cycle qualification.
- Internal sequencer, router, execution-fabric, and dispatcher contracts remain
  unchanged; this checkpoint only normalizes the public harness boundary.
- `m8_operator_harness` remains 1,192 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and all eight resident algorithm replay
  paths pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the scratch initialization/load checkpoint is 0/24 for
  both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_context_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_context_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Normalize only the execution handshake as `execution_active`,
   `cycle_valid`, and `cycle_commit`, including caller-side signal ownership.
2. Preserve start/abort behavior, stall qualification, fault blocking, commit
   timing, and resident-state updates without changing stream/resource ports.
3. Re-run the full gate and compare cycles against this packed-context
   checkpoint before changing any ready/status output group.

Execution-handshake port checkpoint completed on 2026-09-06:

- Confirmed `m8_operator_harness` already exposes the functional handshake as
  `execution_active`, `cycle_valid`, and `cycle_commit`.
- Removed the remaining caller-side milestone name by renaming the public M13
  output and its owned signal from `array_execution_active` to
  `execution_active`.
- Migrated `m13_zcu106_shell_core` and the direct M13 verification caller in
  the same patch without a compatibility alias.
- Preserved sequencer ownership, launch/start behavior, abort handling, image
  locking, stall qualification, fault blocking, commit timing, and resident
  state updates; no combinational or sequential logic was changed.
- Stream/resource ready outputs remain unchanged for their dedicated
  checkpoint.
- `m8_operator_harness` remains 1,192 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and all eight resident algorithm replay
  paths pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the packed-context checkpoint is 0/24 for both matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_execution_handshake_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_execution_handshake_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Next checkpoint:

1. Normalize only the public stream/resource readiness outputs into explicit
   functional channel names.
2. Preserve ready polarity, fault gating, cache-capture blocking, dispatcher
   ownership, and sequencer stall timing without compatibility aliases.
3. Re-run the full gate and compare cycles against this execution-handshake
   checkpoint before changing result, event, or status outputs.

Stream/resource flow-contract port checkpoint completed on 2026-09-06:

- Renamed the public harness outputs to `stream_input_ready`,
  `stream_output_ready`, `resource_req_ready`, and `resource_rsp_valid`.
- Renamed the matching `operator_flow_control` outputs and migrated the M13
  production caller plus all direct M8 callers without compatibility aliases.
- Corrected the misleading resource-response suffix: the wait-for-result
  contract observes response validity, not a downstream ready signal.
- Preserved active-high polarity, cache-capture blocking, D18 split and
  candidate buffering qualification, fault gating, dispatcher ownership, and
  sequencer stall/commit timing.
- Internal router and arithmetic subsystem ports remain unchanged where their
  local contracts still use the original input/output terminology.
- `m8_operator_harness` remains 1,192 lines.
- M5 arithmetic/resource-router, M6 PE/result-buffer/cluster-pair, M8 operator,
  nested operators, nested sequencer, and all eight resident algorithm replay
  paths pass.
- Small `m16_n24_k4_seed1`: 24/24 PASS.
- Scale `m64_n256_k8_seed41`: 24/24 PASS.
- Cycle delta against the execution-handshake checkpoint is 0/24 for both
  matrices.
- No synthesis, implementation, timing, or resource claim is made.

Evidence:

- `reports/v3/m13_correctness_sweep_port_flow_readiness_small_20260906/results.json`
- `reports/v3/m13_correctness_sweep_port_flow_readiness_scale_20260906/results.json`
- `work/m5_property_xsim/m5_console.log`
- `work/m6_property_xsim/m6_console.log`
- `reports/v3/m8_vivado/m8_xsim.log`

Further refactor work is superseded by
`docs/v3/27_RTL_V3_OPTIMIZATION_FOLLOW_PLAN.md`; optimization P0 snapshot and
profiling now take priority over additional result/status renaming.
