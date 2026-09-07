# v3 context ISA

Trạng thái: **context format revision 8 đã khóa và có RTL M3/M6/M10**. Software authority là
`compiler/v3/context_isa.py`; `context_isa_defs.vh` và disassembly được generate
từ cùng source. Placement-specific multiply và `PCG_*` không còn hợp lệ.

## 1. Context bundle

Mỗi committed array cycle đọc đồng thời:

| Word | Số lượng | Width | Logical total |
| --- | ---: | ---: | ---: |
| tile context | 16 | 36 | 576 |
| array-control | 1 | 36 | 36 |
| stream | 1 | 36 | 36 |
| resource | 1 | 36 | 36 |
| **cycle total** |  |  | **684 bit** |

Phase program dùng instruction 36 bit ở `phase_pc` riêng. Có một
`array_context_pc`; 16 tile context được broadcast tới corresponding tile của
hai cluster.

## 2. Tile context, 36 bit

| Bits | Field | Width |
| ---: | --- | ---: |
| 4:0 | `operation` | 5 |
| 7:5 | `source_a` | 3 |
| 10:8 | `source_b` | 3 |
| 13:11 | `rf_read_a` | 3 |
| 16:14 | `rf_read_b` | 3 |
| 19:17 | `rf_write_address` | 3 |
| 20 | `rf_write_enable` | 1 |
| 22:21 | `predicate_select` | 2 |
| 23 | `predicate_invert` | 1 |
| 26:24 | `route_north_select` | 3 |
| 29:27 | `route_east_select` | 3 |
| 32:30 | `route_south_select` | 3 |
| 35:33 | `route_west_select` | 3 |

`source_a/source_b`: ZERO, LOCAL_RF, NORTH, EAST, SOUTH, WEST, ACCUMULATOR,
EXTERNAL.

Mỗi route select: HOLD, PE_RESULT, NORTH, EAST, SOUTH, WEST,
RESERVED_EXPRESS, EXTERNAL. `RESERVED_EXPRESS` là illegal trong mesh-only
baseline; chỉ được gán nghĩa sau mapper gate nếu distance-2 express chứng minh
có lợi. Route output là registered state; HOLD giữ state cũ.

Opcode set trong revision 8:

| Code | Operation | Placement |
| ---: | --- | --- |
| 0 | NOP | all PE |
| 1 | PASS | all |
| 2/3 | ADD/SUB | all |
| 4 | ABS | all |
| 5/6 | MIN/MAX | all |
| 7/8/9 | CMP_EQ/CMP_LT/CMP_LE | all |
| 10 | SELECT | all |
| 11 | SHIFT | all |
| 12/13/14 | AND/OR/XOR | all |
| 15 | PHI_ACCUMULATE | all, fused sign/zero + L48 accumulate, no DSP |
| 16 | RESERVED_VECTOR_RESOURCE | illegal ở mọi PE |
| 17 | ACCUMULATOR_READ | all |
| 18/19 | SATURATING_ADD/SUB | all |
| 20 | PHI_APPLY_SYMBOL | all, no DSP |
| 21 | ACCUMULATOR_CLEAR | all |

Opcode định nghĩa input/output fixed-point và latency trong architecture
manifest. Không có hidden narrowing mode.

`PHI_APPLY_SYMBOL` nhận `{nonzero,sign}` và trả `0`, `+operand` hoặc `-operand`;
opcode không chứa `alpha`. Với D18 correlation, operand được align exact `<<5`
từ F14 sang F19 trước sign/gate. Runtime scale là resource boundary riêng:
pre-broadcast cho `A*p`, post-reduction cho correlation/`A^T*u`. Opcode không
round hoặc scale từng lane.

`PHI_ACCUMULATE` là accumulator-only operation:

```text
term = nonzero ? (sign ? -operand_a : operand_a) : 0
L48_next = saturate_L48(L48 + term)
S27_result = 0
```

Sign/zero và cộng L48 hoàn thành trong một context cycle. Không narrow
term qua S27 lần hai và không ghi RF tạm; compiler phải đặt `rf_write_enable=0`.
Opcode này thay cặp `PHI_APPLY_SYMBOL -> SATURATING_ADD` trong operator
correlation/forward/transpose.

General S27xS27 multiply/MAC không phải tile opcode. Chỉ sign-MAC của Phi
nằm trong PE; general multiply gọi vector sidecar qua resource word. Cả 32
PE vẫn có cùng legality map.

## 3. Array-control context, 36 bit

| Bits | Field |
| ---: | --- |
| 7:0 | `next_pc` |
| 10:8 | `next_pc_mode` |
| 12:11 | `loop_counter_select` |
| 13 | `loop_counter_reset` |
| 14 | `loop_counter_increment` |
| 18:15 | `loop_limit_select` |
| 26:19 | `loop_limit_immediate` |
| 29:27 | `predicate_select` |
| 30 | `predicate_invert` |
| 32:31 | `cluster_enable_mask` |
| 33 | `routine_done` |
| 34 | `safe_abort_point` |
| 35 | `guaranteed_commit` |

`next_pc_mode`: SEQUENTIAL, JUMP, COUNTED_LOOP, PREDICATE_SELECT, WAIT_EVENT,
RETURN_TO_PHASE. Encoding 6-7 illegal.

`loop_limit_select`: IMMEDIATE, M, N, K, 2K, 3K, outer limit, refinement iteration limit,
RUN_PARAMETER_0, RUN_PARAMETER_1, `ceil(M/16)`, `ceil(active_work_count/16)`.
`run_param1` mang active work count; encoding 12-15 illegal.

`cluster_enable_mask=0` là illegal context. Mask 01/10 chỉ dùng tail routine;
không tạo independent execution.

`guaranteed_commit=1` chỉ hợp lệ khi compiler chứng minh context không phụ
thuộc stream/resource ready và không dùng `WAIT_EVENT`. Reservation guard kiểm
tra lại điều kiện này trước commit; sequencer bỏ elastic-ready join cho context
đã được chứng minh.

## 4. Stream context, 36 bit

| Bits | Field |
| ---: | --- |
| 0 | `vector_read_a_enable` |
| 1 | `vector_read_b_enable` |
| 2 | `vector_write_enable` |
| 8:3 | `vector_configuration_a` |
| 14:9 | `vector_configuration_b` |
| 20:15 | `vector_configuration_write` |
| 22:21 | `external_a_select` |
| 24:23 | `external_b_select` |
| 26:25 | `phi_command` |
| 32:27 | `phi_configuration_id` |
| 33 | `advance_vector_streams` |
| 34 | `stall_on_input` |
| 35 | `stall_on_output` |

External select: ZERO, VECTOR_A, VECTOR_B, SCALAR_BROADCAST.

Phi command:

- IDLE: không đổi Phi stream;
- START: capture configuration ID và khởi tạo coordinate request queue;
- CONSUME: cycle commit pop đúng một 32-symbol mask/sign response;
- STOP: flush transaction sau safe boundary.

Vector configuration chỉ được dùng khi enable tương ứng bằng 1. Configuration address
chỉ advance khi `advance_vector_streams && cycle_commit`. Stream word cho phép
vector và Phi hoạt động cùng cycle, là điều kiện cần để map `Phi^T*r` hiệu quả.
Canonical encoding đặt configuration ID bằng 0 khi stream tương ứng disable;
`phi_configuration_id` chỉ khác 0/được decode ở command START, còn CONSUME/STOP
dùng transaction đã active.

## 5. Resource context, 36 bit

| Bits | Field |
| ---: | --- |
| 4:0 | `operation` |
| 7:5 | `input_select` |
| 10:8 | `output_select` |
| 16:11 | `configuration_id` |
| 20:17 | `count_select` |
| 24:21 | `lane_mask` |
| 26:25 | `stream_boundary` |
| 27 | `clear_before` |
| 28 | `accumulate` |
| 29 | `commit_after` |
| 30 | `wait_for_ready` |
| 31 | `wait_for_result` |
| 35:32 | `event_id` |

Resource operations revision 8 giữ exact encoding cũ trong generated disassembly:

```text
NOP
REDUCE_SUM, REDUCE_NORM_SQ, REDUCE_MAX_ABS, ARGMAX
TOPK_PUSH, TOPK_COMMIT
SUPPORT_CLEAR, SUPPORT_APPEND, SUPPORT_UNION, SUPPORT_MEMBERSHIP
SUPPORT_GATHER, SUPPORT_SCATTER, SUPPORT_COMMIT, SUPPORT_ROLLBACK
SCALAR_RECIPROCAL_RESERVED, SCALAR_DIVIDE, SCALAR_SQRT_RESERVED
DMA_PREFETCH, DMA_DRAIN
SHARED_VECTOR_DOT, SHARED_VECTOR_NORM_SQ, SHARED_VECTOR_SCALE
SHARED_VECTOR_AXPY, SHARED_VECTOR_COPY, REFINEMENT_CHECK
```

Input select: NONE, EAST_EDGE, CLUSTER_REDUCTION, MEMORY_STREAM,
SUPPORT_STREAM, SCALAR_0, SCALAR_1, GLOBAL_REDUCTION.

Output select: DISCARD, SCALAR_0, SCALAR_1, MEMORY_STREAM, SUPPORT_STREAM,
TOPK_STATE, PE_SCALAR_BROADCAST, EVENT.

Count select: immediate, M, N, K, 2K, 3K, active support, active work,
configuration length, refinement iteration limit. `lane_mask` chọn bốn row group; cluster mask nằm
trong array-control.

`SCALAR_RECIPROCAL` và `SCALAR_SQRT` không có datapath trong active build vì
không có golden bit-exact. Hai encoding được giữ ổn định cho revision tương lai;
compiler hiện tại cấm emit chúng và resource router trả fault deterministic nếu
image ngoài contract vẫn issue. Exact numeric code nằm trong
`compiler/v3/context_isa.py`; availability/latency nằm trong
`compiler/v3/architecture_configuration.json`.

## 6. Phase instruction, 36 bit

| Bits | Field |
| ---: | --- |
| 2:0 | `operation` |
| 10:3 | `array_entry_pc` |
| 14:11 | `condition_select` |
| 15 | `condition_invert` |
| 23:16 | `target_pc` |
| 27:24 | `event_id` |
| 31:28 | `terminal_code` |
| 32 | `safe_abort_point` |
| 33 | `trace_emit` |
| 35:34 | reserved = 0 |

Operations:

- NOP;
- LAUNCH_ARRAY;
- WAIT_CONDITION;
- BRANCH;
- COMPLETE;
- RAISE_ERROR.

Default next phase là `phase_pc+1`. BRANCH nhảy `target_pc` khi selected
condition XOR invert đúng, ngược lại fall-through. WAIT giữ PC tới khi condition
đúng. LAUNCH chuyển `array_entry_pc` trực tiếp cho array sequencer; không có
kernel-entry table và không có hai kernel ID.

Condition sources: ALWAYS, ARRAY_ROUTINE_DONE, RESOURCE_EVENT, DMA_DONE,
RESIDUAL_LIMIT, ITERATION_LIMIT, SUPPORT_STABLE, RESIDUAL_DECREASED,
SOLVER_CONVERGED, SOLVER_FAULT, ABORT_PENDING, ERROR_PENDING.

Version mask đã bị bỏ từ revision 4 và tiếp tục không có trong target revision.
Một static CFG chạy in-order và atomic
support/result commit đủ để bảo đảm ownership; giữ mask trong mọi instruction
chỉ tăng phase word mà không thêm parallel issue.

## 7. Memory configuration, 64 bit

| Bits | Field |
| ---: | --- |
| 15:0 | `base_word_address` |
| 31:16 | `element_count` |
| 43:32 | `element_stride_words` |
| 46:44 | `bank_base` |
| 48:47 | `bank_count_log2` |
| 51:49 | `bank_mode` |
| 54:52 | `element_format` |
| 57:55 | `packing_mode` |
| 58 | `read_enable` |
| 59 | `write_enable` |
| 60 | `atomic_commit` |
| 62:61 | `memory_space` |
| 63 | reserved = 0 |

Memory spaces: VECTOR_SCRATCHPAD, SUPPORT_WORKSPACE, EXTERNAL_DMA_WINDOW,
PHI_COORDINATE_STREAM.

Formats: D18, S27, A62, INDEX10, BITMAP1, RAW32, RAW64. Packing: one, two,
four, six, seven hoặc raw72. Bank mode: linear, cyclic, broadcast,
cluster-local hoặc ping-pong.

Khi `memory_space=PHI_COORDINATE_STREAM`, field overlay là:

| Bits | Phi meaning |
| ---: | --- |
| 15:0 | sequential first column hoặc support-list base word |
| 31:16 | number of columns/support entries |
| 43:32 | column/list stride |
| 46:44 | first row-pair |
| 48:47 | row-pair count as log2 (1/2/4/8) |
| 51:49 | 0 sequential, 1 support-list generator, 2 repeat-one-column, 3 active-support-cache replay; 4..7 illegal |
| 54:52 | support index format when mode 1 |
| 57:55 | support-list packing when mode 1 |
| 58 | stream enable, phải bằng 1 |
| 60:59 | phải bằng 0 |
| 62:61 | 3 |
| 63 | 0 |

Seed lấy từ `active_configuration_store`, không duplicate trong table.

## 8. Physical packing

- Tile pair `(2p,2p+1)` tạo một RAM word 72 bit ở plane `p`.
- `{array_control,stream}` tạo plane 8 word 72 bit.
- Resource dùng plane 9 word 36 bit; phase dùng plane 10 word 36 bit. Cả hai
  index bằng `{image_bank,address}`.
- Hai bank x 256 entry map thành 9 RAMB36 cho tám tile-pair plane và một
  array/stream plane, cộng 2 RAMB18 cho resource/phase: tổng 10 RAMB36
  equivalent đúng report M3.
- Context mới phải ghi `0..7 -> 9 -> 8`; plane 8 commit atomic bundle và tăng
  high-water mark. Sau khi load/patch, explicit finalize scan mọi target và
  fallthrough; bank chỉ executable khi scan thành công. Phase plane 10 tăng
  high-water mark độc lập. Khi run active chỉ inactive bank được patch;
  finalize chỉ được chấp nhận lúc lifecycle idle.

## 9. Decode/error rules

- Undefined enum, reserved bit khác 0 hoặc zero cluster mask là image error.
- Illegal opcode/location là context error trước side effect.
- Configuration permission/space/packing mismatch là context error.
- Compiler manifest revision 8 mang architecture hash. Baseline resident image
  phải bị build reject nếu manifest/constants mismatch. M3 loader bảo vệ
  ordering, hole, active-bank write và CFG closure; CRC/package compatibility
  của resident eight-algorithm image vẫn là gate M11 trước bank switch.
- Mapper/disassembler phải round-trip mọi word bit-exact trước khi image được
  phép đi vào RTL verification.
