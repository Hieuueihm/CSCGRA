# v3 CGRA microarchitecture

Trạng thái: **M6 RTL COMPLETE tại homogeneous CGRA boundary**. Baseline
nearest-neighbor mesh đã khóa; express-link encoding bị reject atomically và
không có trong datapath. Đây là leaf/pair OOC evidence, chưa phải full-chip
integration hoặc post-route sign-off.

## 1. Hai cluster vật lý, một machine logic

```text
                     shared array_context_pc
                              |
             +----------------+----------------+
             |                                 |
       cluster 0, 4x4                    cluster 1, 4x4
       lanes 0..15                       lanes 16..31
             |                                 |
       cluster reduction                 cluster reduction
             +---------------+-----------------+
                             |
                    global reduction merge
```

Corresponding tile `(row,column)` nhận cùng tile context 36 bit. Dữ liệu khác
nhau nhưng opcode, source select và route select giống nhau. Một context stall
giữ PC, loop counters, stream positions, RF writes và resource side effect của
cả hai cluster.

`cluster_enable_mask` có thể chạy cluster 0 hoặc 1 cho tail nhỏ hơn 32 lane;
cluster bị disable không update state. Đây không phải independent execution:
cluster còn lại vẫn dùng cùng PC và không có phase/kernel stream riêng.

## 2. Cluster topology

```text
                north registered links
            +------+------+------+------+
memory row0 | PE00 | PE01 | PE02 | PE03 | resource row0
memory row1 | PE10 | PE11 | PE12 | PE13 | resource row1
memory row2 | PE20 | PE21 | PE22 | PE23 | resource row2
memory row3 | PE30 | PE31 | PE32 | PE33 | resource row3
            +------+------+------+------+
                south registered links
```

Mỗi tile có nearest-neighbor N/E/S/W registered link. Baseline router là static
circuit-switched: không packet, arbitration, per-hop FIFO hoặc combinational
multi-hop. Memory row I/O, reduction-up và scalar-broadcast-down là ba plane
riêng, không đi qua general mesh. Không có direct route xuyên hai cluster.

General distance-2 express link không thuộc M6 baseline. Encoding dành trước
vẫn tồn tại để không phải đổi context width, nhưng certifier/compiler cấm
emit và `pe_tile` phát `contract_error` mà không commit state nếu gặp nó.

## 3. `pe_tile`

### 3.1. Datapath

```text
local RF / N E S W / accumulator / external
                 | source mux A/B
                 v
         homogeneous ALU / Phi sign gate
                 |
          48-bit local accumulator
                 |
        predicate + RF write gate
                 |
registered switchbox
```

Base ALU ở mọi tile hỗ trợ NOP, pass, add/sub, abs, min/max, compare, select,
shift/logic, saturating add/sub, accumulator read/clear và Phi zero/sign gate.
Opcode quyết định fixed-point/rounding contract; không có generic mode bit có
thể làm cùng opcode mang hai numerical meaning.

M6 khóa semantics bit-exact: ADD/SUB và left SHIFT saturate về S27;
right SHIFT là arithmetic; ABS của S27 minimum saturate về maximum.
`SATURATING_ADD/SUB` cập nhật accumulator L48 rồi saturating-narrow kết quả
route/RF về S27. `PHI_SIGN_SCALE` chỉ zero/sign, không nhân scale trong PE.
Revision 7 thêm `PHI_ACCUMULATE`: zero/sign S27 và cộng trực tiếp vào L48
trong một cycle, không tạo S27/RF intermediate và không dùng DSP. General
S27xS27 MAC vẫn thuộc shared vector unit M5.

Phi symbol path có hai declared operator boundary:

```text
D18 correlation     : align exact `data_raw << 5` vào F19, sign/gate,
                      reduce rồi runtime-scale một lần ở full-dot output
S27 A forward       : runtime-scale một scalar trước 32-lane broadcast
S27 A^T transpose   : sign/gate và cộng raw F19, runtime-scale sau reduction
```

Không scale/round từng lane trước reduction. Runtime scale placement, final
round và saturation follow
[03_DATA_AND_NUMERIC_CONTRACT.md](03_DATA_AND_NUMERIC_CONTRACT.md).

### 3.2. Local RF

- `8x27`, two logical read/one write;
- synchronous state update, combinational read target for FPGA LUTRAM/FF
  implementation;
- no active/shadow bank and no runtime bank-swap state;
- predicate false suppresses RF/accumulator/route-state side effects declared
  by the opcode.

Predicate bit 0 là `ALWAYS`; compiler/context image phải drive bit này bằng 1.
Ba bit còn lại là predicate runtime. Predicate invert nằm trong tile context.

Mapper reserves RF address and port per cycle. Spill/fill đi qua vector stream,
không truy cập RF trực tiếp từ DMA.

### 3.3. Local accumulator

48 bit đủ cho compiled local partial bound; A62 exact collector nằm ở reduction
resource. Compiler phải emit bound cho mỗi accumulation interval. Context không
được kéo dài interval nếu bound vượt 48 bit; phải flush sang cluster/global
collector trước.

### 3.4. Homogeneous capability boundary

Mọi `pe_tile` có cùng opcode, latency và route capability. PE không chứa
general S27 multiplier và không có `HAS_MUL` theo column. Phi multiplication là
zero/sign gate nên vẫn chạy ở cả 32 PE.

General multiply, dot, norm, scale và AXPY chạy trong
`shared_vector_arithmetic_unit` với 16 logical lane đồng nhất. Sidecar nhận S27
stripe trực tiếp từ scratchpad và trả tagged vector/scalar result qua
`array_resource_router`. Compiler chỉ model một shared resource, không model
vị trí DSP trong array.

## 4. Lane mapping

```text
lane_id = cluster_id*16 + row_id*4 + column_id
```

- Phi nonzero/sign bit `lane_id` đi đúng tile đó.
- D18 stripe: bank `(cluster,row)` chứa bốn column element.
- S27 stripe: mỗi bank chứa hai element; tám bank tạo 16 element cho vector
  sidecar, không nối theo column capability.
- Reduction lane mask `[3:0]` áp dụng theo row group; cluster mask áp dụng theo
  cluster.

Mapping này giữ wiring local: mỗi 72-bit bank word chỉ chạy dọc một row, không
fanout toàn fabric.

## 5. Context delivery

Cycle read address là `{active_image_bank,array_context_pc}`.

```text
tile plane 0 -> tile positions 0 and 1, both clusters
tile plane 1 -> tile positions 2 and 3, both clusters
...
tile plane 7 -> tile positions 14 and 15, both clusters
plane 8 low/high -> array-control / stream
plane 9 -> resource at array_context_pc
plane 10 -> phase instruction at independent phase_pc
```

Hai 36-bit plane cuối map vào hai RAMB18 độc lập. Với tám tile-pair RAMB36 và
một array/stream RAMB36, context store dùng 9 RAMB36 + 2 RAMB18 = 10 RAMB36
equivalent như M3 OOC report.

RAM output được register trước decode. Vì vậy context fetch latency baseline là
một cycle và nằm trong architecture hash. Không có 684-bit central decode bus;
tile plane output được floorplan gần hai corresponding tile.

## 6. Atomic cycle commit

Một context cycle chỉ commit khi:

```text
context_valid
and all enabled vector reads valid
and Phi word valid when CONSUME
and resource request ready when wait_for_ready
and vector/resource outputs ready
and no abort outside safe point
```

Nếu false:

- `array_context_pc` và loop counters giữ;
- vector configuration address không advance;
- Phi gearbox không pop;
- PE RF/accumulator/switchbox không write;
- resource request không được accept một phần.

Router phải tạo một `cycle_commit` chung thay vì AND các enable rải rác trong
từng module.

## 7. Loop control

Array-control word có bốn counter vật lý chọn bởi `loop_counter_select`.
Limit đến từ immediate hoặc run parameter M/N/K/2K/3K/iteration. Next-PC modes:

- sequential;
- unconditional jump;
- counted loop;
- predicate-select;
- wait event;
- return to reconstruction control sequencer.

`routine_done` chỉ pulse trên committed cycle. `safe_abort_point` chỉ có ý
nghĩa trên committed cycle; abort không cắt giữa vector-sidecar transaction, TOP-K replace
hoặc support atomic update.

## 8. Static scheduling/MRRG rules

Compiler phải model:

- context fetch latency 1;
- ALU/result-route latency theo opcode;
- every registered hop latency 1;
- RF ports 2R1W;
- 32 PE có cùng capability và không có placement-specific opcode;
- D18 Phi path 32 lane; S27 vector sidecar 16 element/stripe;
- Phi request II=2, response word rate=1/cycle after fill;
- vector bank two-port conflicts;
- reduction/SFU/TOP-K latency, II và FIFO depth;
- pair-wide stall boundary.

Không có dynamic issue, scoreboard hoặc packet router trong PE fabric.

## 9. Timing partition target

Pipeline boundaries M6 được đặt tại:

1. context RAM output;
2. PE source mux/combinational arithmetic -> result/accumulator register;
3. registered switchbox output; mỗi mesh hop thêm một cycle;
4. mỗi reduction tree level;
5. TOP-K 32-way compare tree;
6. Phi folded round stage/feedback;
7. stream/resource skid buffer.

Không cho đường combinational đi từ AXI/CSR tới PE data path hoặc xuyên hai
cluster. Fanout lớn như scalar, predicate và context enable phải có replicated
register theo cluster/row khi implementation yêu cầu.

## 10. Formal properties khi viết RTL

- corresponding tile ở hai cluster luôn nhận cùng context word/PC;
- `!cycle_commit` kéo theo toàn bộ architectural state ổn định;
- disabled cluster không write RF/accumulator/memory/resource;
- corresponding tile ở hai cluster nhận cùng context word; mọi PE cùng
  opcode/latency capability;
- predicate false suppresses declared state writes;
- route source hợp lệ, không tạo combinational loop;
- local accumulator không overflow dưới compiler-provided bound;
- vector-sidecar S27xS27 bằng signed mathematical product trước narrowing;
- one accepted context cycle tạo tối đa một resource request/event ID.

## 11. M6 verification evidence

- `models/v3/hardware.py` là golden bit-exact cho toàn bộ legal tile opcode;
- Vivado/XSim PASS cho ALU golden, 32-lane shared context, RF replay,
  predicate/cluster mask, pair-wide stall, Phi sign/zero, bốn hướng route,
  registered four-hop route và illegal express/reserved operation;
- FORMAL-guarded assertions compile/elaborate và chạy trong directed XSim;
  đây không phải mathematical proof;
- ZCU106 OOC @150 MHz sau tối ưu operand routing: `pe_tile` 1,465 LUT/194 FF,
  WNS +2.122 ns; `cgra_cluster` 24,332 LUT/3,104 FF, WNS +2.126 ns;
  `cgra_cluster_pair` 48,487 LUT/6,208 FF, WNS +2.126 ns, 0 DSP/0 BRAM;
- compiler map bốn Phi kernel ở II `2/2/2/2`; residual update giảm II
  `3 -> 2`, template library giảm `21 -> 20` context và RF tạm `1/8 -> 0/8`.

Chi tiết và đường dẫn evidence nằm trong
`reports/v3/M6_CGRA_ARRAY_STATUS.md`.
