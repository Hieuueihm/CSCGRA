# v3 block design specification

Trạng thái: **M0-M7 đã hoàn thành ở milestone boundary**. Hiện đã có M1 AXI4-Lite/CSR, M2
DMA/run-configuration và M3 context stores, reservation guard cùng hai cấp
sequencer; M3.5-M3.6 đã có physical-resource authority, MMG, typed SSA,
RF/bank allocation và emitted context cho bốn inner kernel; M4 memory/stream,
M5 arithmetic, M6 homogeneous CGRA và M7 generated Phi đều có Vivado evidence.
Correlation/operator attachment và sparse/LS datapath còn là interface
contract. Chưa có datapath/full-design sign-off.

## 1. Target

| Thuộc tính | Baseline |
| --- | --- |
| FPGA | ZCU106, `XCZU7EV-2FFVC1156` |
| Bring-up / architecture clock | 100 MHz / 150 MHz target |
| Build capacity | `N=1024`, `M=128`, `K=32`, candidate 64, work 96 |
| CGRA | 2 cluster x 4 row x 4 column, one shared context PC |
| Numeric | D18F14 / S27F19 / A62 |
| Context | 684 logical bit/cycle, 10 RAMB36 physical |
| Vector memory | 8 bank x 72 bit x 512 word, true dual port |
| Phi | one symbol generator + runtime normalizer + active-support symbol cache |
| Vector arithmetic | 16 equivalent sidecar lanes, không gắn theo PE location |

150 MHz và mọi resource count ngoài capacity model chỉ là target cho tới khi có
Vivado OOC và final route report.

## 2. Module tree cuối cùng

```text
top
|- axilite_slave
|- reconstruction_csr
|- reconstruction_configuration_unit
|  |- configuration_fetch_unit
|  |- configuration_check_unit
|  `- active_configuration_store
|- reconstruction_phase_controller
|- context_image_store
|- array_context_sequencer
|- stream_context_router
|- memory_configuration_store
|- vector_stream_engine
|- vector_scratchpad
|- memory_dma_engine
|  |- dma_request_arbiter
|  |- axi_read_burst_engine
|  |- axi_write_burst_engine
|  `- dma_element_normalizer
|- cgra_cluster[2]
|  |- pe_tile[4][4]
|  |  |- pe_alu
|  |  |- pe_local_register_file
|  |  `- registered_switchbox
|  |- scratchpad_word_codec[4]
|  `- cluster_reduction_unit
|- phi_symbol_generator
|  |- phi_request_queue
|  |- threefry2x32_folded_pipeline
|  |- phi_symbol_builder
|  `- phi_response_gearbox
|- support_phi_symbol_cache
|- phi_apply_symbol_lane[32]
|- phi_operator_normalizer
|- array_resource_router
|- global_reduction_merge
|- shared_vector_arithmetic_unit
|- topk_selection_unit
|- proxy_candidate_collector
|- support_state_manager
|- support_coefficient_remapper
|- support_workspace
|- scalar_function_unit
|- scalar_register_file
|- restricted_refinement_state
|- normal_residual_checker
`- reconstruction_result_writer
```

Không có `kernel_0`, `kernel_1`, per-cluster scheduler, direct LDLT engine,
hard LS engine hoặc algorithm-specific controller. Resource-only routine vẫn đi qua cùng
`array_context_pc`; 16 tile word là NOP trong routine đó.

## 3. Control hierarchy

### `axilite_slave`

Chỉ giữ protocol state cần thiết để ghép AW/W độc lập và giữ B/R response khi
backpressure. Nó không include CSR offset và không tạo reconstruction state.

### `reconstruction_csr`

Chỉ sở hữu:

- một run-configuration address 64 bit;
- hai IRQ-enable bit và hai sticky pending bit;
- terminal stop/support summary;
- first-error record.

START và ABORT là pulse. Run-configuration address không có shadow/active duplicate;
write address bị từ chối khi busy và fetcher capture address cùng START.

### `configuration_fetch_unit`

Nhận một request `{valid,ready,address[63:0]}`, phát đúng bốn read beat 128 bit
và trả một payload 512 bit. Nó không decode field. AXI error kết thúc fetch và
trả beat index/response cho CSR error record.

### `configuration_check_unit`

Kiểm tra revision, reserved bit, M/N/K, 2K/3K, iteration, gOMP capacity,
destination và alignment. Chỉ khi toàn bộ 16 word hợp lệ mới phát
`parameter_commit`. Không cập nhật một phần.

### `active_configuration_store`

Giữ đúng một active run configuration đã canonicalize. Đây là internal state, không
phải CSR bank. Module chỉ xuất các view hẹp:

- dimensions/policy cho sequencer;
- seed/coordinate limit, matrix kind, column weight và scale cho Phi;
- ba address và result mode cho DMA/result writer;
- threshold/scalars cho scalar register file.

Nó giữ ổn định từ `parameter_commit` tới terminal event.

### `reconstruction_phase_controller`

Một protocol FSM duy nhất nhận START/ABORT, yêu cầu và giữ active run
configuration, kiểm tra active context image đã finalize, sau đó fetch/execute
phase context từ PC0. Nó sở hữu một `phase_pc[7:0]` nhưng không nhận algorithm ID
hoặc program selector. Software/compiler quyết định nội dung image. Branch dựa
trên predicate/event; LAUNCH chỉ chuyển `array_entry_pc` cho array sequencer. Static
CFG đảm bảo thứ tự object, nên phase word không cần live-in/live-out version
mask. Completion/error giải phóng active configuration và đi thẳng về CSR.

FSM chỉ mã hóa protocol
`IDLE -> REQUEST_CONFIGURATION -> WAIT_CONFIGURATION -> PHASE_FETCH <-> PHASE_EXECUTE`.
Nó không chứa case theo algorithm và không phát PE opcode; mọi flow do
compiler-generated phase CFG quyết định.

### `array_context_sequencer`

Một `array_context_pc[7:0]`, bốn loop counter, predicate input và một
pair-wide stall. PC/counter giữ nguyên nếu bất kỳ input/output bắt buộc nào
backpressure. `cluster_enable_mask` chỉ dùng tail/half-width routine; nó không
tạo PC thứ hai.

## 4. Context store

| Physical plane | Mode | Payload |
| --- | --- | --- |
| 0..7 | `72x512` | hai tile context 36 bit/plane, bank+PC address |
| 8 | `72x512` | array-control 36 + stream 36 |
| 9 | TDP `36x1024` | resource lower half; phase upper half |

Bank 0 được compiler đưa vào bitstream. Bank 1 có cùng physical RAM và được giữ
cho atomic image replacement về sau; baseline chưa expose image-loader CSR.
Việc không có loader ở milestone đầu không làm xuất hiện register tạm.

## 5. PE map

Mỗi tile có cùng một capability:

- ALU signed 27 bit, compare/select, saturating add/sub và Phi zero/sign gate;
- RF `8x27`, hai read/một write logical port;
- local accumulator 48 bit;
- bốn predicate bit;
- registered N/E/S/W route.

RF có một bank duy nhất; bỏ active/shadow local RF để không thêm bank-swap state
khó kiểm soát. Mapper phải tính RF port và lifetime trong MRRG.

PE không chứa general multiplier và không có location capability mask. General
D18/S27 multiply, dot, norm và AXPY đi qua `shared_vector_arithmetic_unit` với 16
logical lane đồng nhất. Mỗi lane có cùng latency/handshake; FPGA tool hoặc
technology wrapper quyết định mapping DSP. S27 vector memory cấp đúng 16
element/stripe nên sidecar không tạo bandwidth giả.

Không có direct PE link xuyên cluster. Cross-cluster value chỉ đi qua
`global_reduction_merge`, scalar broadcast hoặc scratchpad. Điều này cắt đường
routing dài giữa hai 4x4 fabric và giữ floorplan FPGA/ASIC rõ ràng.

## 6. Stream và sidecar split

Một stream context điều khiển đồng thời:

- vector read A;
- vector read B;
- vector write;
- external operand mux A/B;
- Phi START/CONSUME/STOP.

Một resource context độc lập điều khiển reduction, exact TOP-K, support set,
shared scalar/vector arithmetic và DMA phase operation. Vì hai word được đọc cùng PC,
`Phi^T*r` có thể trong cùng cycle đọc `r`, nhận symbol Phi, sign/gate ở PE và
reduce; không cần preload RF hoặc context đặc biệt theo algorithm.

## 7. Auxiliary architecture

- `cluster_reduction_unit`: 16 input, registered 4-way tree rồi merge; output
  A62 + tag.
- `global_reduction_merge`: hai cluster result, exact signed add/compare.
- `topk_selection_unit`: 64 entry state cho K32, 32 comparator lane,
  valid-ready candidate FIFO. Sau replace, quét tối đa 2 group để tìm worst.
- `proxy_candidate_collector`: giữ Top-2K record và gradient tại active support;
  không lưu full proxy N phần tử.
- `support_state_manager`: current/proposed bitmap, slot map, list
  append/union/membership và atomic commit/rollback; work capacity đúng 96.
- `shared_vector_arithmetic_unit`: 16 lane equivalent cho dot/norm/scale/AXPY,
  dùng chung bởi LS, GP, IHT và MP.
- `restricted_refinement_state` và `normal_residual_checker`: chỉ giữ
  recurrence/certificate state, không tạo solver PC thứ tư.
- `scalar_function_unit`: một shared iterative divider với tagged
  request/result; reciprocal/sqrt chỉ giữ encoding reserved và trả one-cycle
  contract fault, không có datapath trong active build.
- `scalar_register_file`: hai architected state `SCALAR_0/SCALAR_1`, mỗi state
  A62 để giữ gamma/delta không bị narrow; two read/one commit-gated write,
  broadcast phần S27 tới 32 PE khi context yêu cầu.

## 8. Implementation order

Thứ tự module và exit gate normative nằm tại
[13_MODULE_IMPLEMENTATION_PLAN.md](13_MODULE_IMPLEMENTATION_PLAN.md). Tóm tắt:

```text
authority sync
 -> AXI/run configuration
 -> context + scratchpad
 -> arithmetic leaves + homogeneous CGRA + Phi
 -> correlation/A/A^T
 -> selection/support
 -> restricted refinement
 -> MP/IHT/GP/OMP/gOMP/HTP/CoSaMP/SP
 -> result/abort
 -> full implementation reports
```

Không pipeline arithmetic chỉ để hết warning nếu latency contract/compiler
schedule chưa được đổi đồng thời.

## 9. Portability

Core RTL không instantiate primitive Xilinx trực tiếp. RAM, DSP multiply,
clock-enable và FIFO đi qua wrapper có latency/handshake cố định. ASIC backend
được thay wrapper nhưng context image chỉ dùng lại nếu architecture hash gồm RF
latency, route latency, stream latency và resource II không đổi.
