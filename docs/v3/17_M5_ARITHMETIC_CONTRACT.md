# 17 - M5 arithmetic resources contract

Ngày lập: 2026-08-25. Trạng thái: **M5 RTL COMPLETE tại leaf và M5 harness**.
Evidence Vivado/XSim/property/OOC nằm trong
[`M5_ARITHMETIC_RESOURCES_STATUS.md`](../../reports/v3/M5_ARITHMETIC_RESOURCES_STATUS.md).

Authority chain của contract này:

- numeric golden: `models/v3/hardware.py` (lớp `Arithmetic` và các helper
  `_solver_dot`, `_corr`, `_restricted_forward/_transpose`, `_norm_sq`);
- availability/latency/II authority:
  `compiler/v3/architecture_configuration.json` bảng `resource_operations` —
  RTL phải khớp đúng từng số; `implemented` mới được compiler đưa vào MMG/MRRG,
  còn `reserved_fault` chỉ có one-cycle fault response;
- encoding authority: resource context word 36 bit trong
  [08_CONTEXT_ISA.md](08_CONTEXT_ISA.md) §5, revision 8 (resource encoding không đổi);
- generated RTL masks: `RECON_RESOURCE_OPERATION_IMPLEMENTED_MASK` và
  `RECON_RESOURCE_OPERATION_RESERVED_FAULT_MASK` trong
  `architecture_guard_defs.vh`; certifier vẫn dùng LEGAL mask để image ngoài
  compiler có thể được trap deterministic tại runtime;
- transaction golden: `reports/v3/context_transaction_golden.json`.

## 1. Quyết định scope: SCALAR_RECIPROCAL / SCALAR_SQRT

Quyết định (đã duyệt 2026-08-25): **phương án (b) — không xây datapath cho op
không có golden**.

- `SCALAR_DIVIDE` (op 16): triển khai đầy đủ theo §3.2.
- `SCALAR_RECIPROCAL` (op 15) và `SCALAR_SQRT` (op 17): **giữ nguyên encoding**
  trong ISA revision 8 (doc 08 và generated disassembly ghi cả hai là reserved).
  `hardware.py` không định nghĩa reciprocal/sqrt và
  compiler chỉ emit `SCALAR_DIVIDE` (`reconstruction_graphs.py` map alpha/beta
  vào SCALAR_DIVIDE). Vì không có golden bit-exact, M5 **không có datapath**
  cho hai op này: `scalar_function_unit` decode chúng vào default arm và trả
  **fault response deterministic một cycle** (`RECON_CONTEXT_ERROR_RESOURCE_CONTRACT`
  qua đường error, một cycle, không side effect).
- Metadata đánh dấu hai op là `reserved_fault`, latency/II 1/1 và loại chúng
  khỏi operation list của physical `scalar_function_unit`. ISA/golden numeric
  không đổi; compiler cấm emit, còn RTL vẫn bắt image ngoài contract thành
  fault thay vì silent hole.
- Doc 13 §M5 sửa leaf test từ "reciprocal và divide" thành "divide"; fault path
  của hai op reserved là một directed negative test của M5.

## 2. Ánh xạ RTL leaf sang physical resource

| RTL leaf | Physical resource (JSON) | Operations |
| --- | --- | --- |
| `cluster_reduction_unit` (x2) + `global_reduction_merge` | `reduction_pipeline`, coupling `two_cluster_reduce_then_global_merge` | REDUCE_SUM, REDUCE_NORM_SQ, REDUCE_MAX_ABS |
| `scalar_function_unit` | `scalar_function_unit` | SCALAR_DIVIDE (+ trap RECIPROCAL/SQRT) |
| `scalar_register_file` | nguồn/đích `SCALAR_0`, `SCALAR_1` của input/output select; plane `scalar_broadcast` | đọc 2 port đồng thời, ghi 1 port |
| `shared_vector_arithmetic_unit` | `shared_vector_arithmetic_unit` | SHARED_VECTOR_DOT / NORM_SQ / SCALE / AXPY / COPY |
| `array_resource_router` | decode resource word + tag + ready/valid join | mọi op ở trên |

DOT/NORM dùng `clear_before`, `accumulate`, `commit_after` để cộng A62 qua
nhiều stripe. `SCALAR_DIVIDE` dùng RF0/RF1 khi `input_select=SCALAR_0`, đảo
thành RF1/RF0 khi `input_select=SCALAR_1`. AXPY dùng `configuration_id[0]=1`
cho dạng trừ `a - scalar*b`; giá trị 0 giữ dạng cộng.

`routine_start` chỉ bắt đầu một resource routine; không xóa scalar RF. Scalar
state sống xuyên các nested array launch của cùng refinement transaction và
chỉ bị xóa bởi `scalar_state_clear`, reset hoặc abort. M10 dùng RF0 cho
`gamma_reference`, RF1 cho `delta/alpha/gamma_new`; continuation tính
`beta=RF1/RF0` rồi ghi RF0.

Physical placement và kết nối được khóa như sau:

```text
cgra_cluster 0 -> cluster_reduction_unit 0 --+
                                                  -> global_reduction_merge
cgra_cluster 1 -> cluster_reduction_unit 1 --+             |
                                                            +-> scalar RF/broadcast

vector_scratchpad <-> shared_vector_arithmetic_unit
                           DOT / NORM / SCALE / AXPY / COPY

scalar RF <-> scalar_function_unit
                 DIVIDE datapath; RECIPROCAL/SQRT reserved trap
```

Reduction leaf đặt sát cluster; vector sidecar nối thẳng stripe S27 của
scratchpad; một SFU được dùng chung. Tất cả đều là scheduled resource node trong
MMG/MRRG, được issue bằng resource context 36 bit qua `array_resource_router`;
không leaf nào có algorithm FSM hoặc PC riêng.

**Ngoài scope M5**: ARGMAX, TOPK_*, SUPPORT_* thuộc `selection_unit` /
`support_state` (M9); DMA_PREFETCH/DRAIN đã có owner M2/M4.1;
REFINEMENT_CHECK thuộc `refinement_checker` (M10) — M5 chỉ chừa port so sánh
A62 mà nó sẽ dùng.

## 3. Numeric contract (bit-exact với `hardware.py`)

### 3.1 Rounding nguyên thủy

`round_shift(v, s)`: nearest ties-away-from-zero trên trị tuyệt đối:
`sign(v) * ((|v| + 2^(s-1)) >> s)`. Đây cũng là narrowing đã dùng ở
`dma_element_normalizer` (M2) — tái dùng đúng cấu trúc RTL abs/round/negate.
`_sat`: saturate signed hai biên, có đếm event.

### 3.2 SCALAR_DIVIDE — chia nguyên chính xác, KHÔNG xấp xỉ lặp

Semantics khóa theo `Arithmetic.round_div`/`solver_div`:

```text
den == 0        -> result = 0, event divide_by_zero (telemetry, KHÔNG fault)
q = (|num << 19| + floor(|den|/2)) / |den|   (chia nguyên đúng)
result = sat_S27( sign(num)^sign(den) ? -q : q )
```

- Toán hạng là **A62** (CGLS: `alpha = gamma/delta`, `beta = gamma'/gamma`;
  GP: dot/dot; MP: corr/norm là trường hợp hẹp S27/S27). Dividend danh nghĩa
  tới 81 bit.
- Latency contract: **28 cycle cố định, II=28** (JSON). Kiến trúc bắt buộc là
  **normalizing divider**: LZC hai toán hạng, so sánh exponent để phát hiện
  saturate/underflow trước khi lặp, radix-2 đúng 28 vòng cho phần quotient có
  nghĩa (26 bit magnitude + guard + round), rounding half-away bằng so sánh
  remainder (`2*rem >= |den|`), áp dấu và saturate S27 ở cuối.
- Newton-Raphson/Goldschmidt bị loại vĩnh viễn cho op này: không bit-exact với
  chia nguyên có rounding.
- `divide_by_zero` là **event counter** (CSR telemetry), không phải fault và
  không dừng routine — model trả 0 và chạy tiếp.

### 3.3 Multiply — folded 27x27, shift là thuộc tính của op

`solver_mul(a,b)`: tích signed đầy đủ 27x27 (54 bit, không cắt trung gian) →
`round_shift(., 19)` → sat S27. Fold một DSP48E2 thành 27x18 + 27x9 qua
post-adder cascade, II=2 — khớp II=2 của mọi op `SHARED_VECTOR_*`.

Shift sau tích **phụ thuộc op**, thực hiện tại điểm kết quả (sau accumulate,
trước saturate), không nằm trong transport:

| Phép trong model | Format | Shift |
| --- | --- | ---: |
| `solver_mul` (SCALE/AXPY) | S27 x S27 | 19 |
| `_restricted_forward/_transpose` (A/A^T) | D18 x S27 | 14 |
| `_corr` (correlation) | D18 x D18 | 9 |
| `data_to_solver` / `solver_to_data` | chuyển đổi | -5 / +5 |

Conversion D18<->S27 (`<<5` exact / `round_shift 5` + sat) là op ranh giới:
đặt tại codec/gateway path (pattern M4), FU không convert lại — tránh
double-rounding.

### 3.4 Reduction — cây 62-bit trần, saturate một lần

Model cộng nguyên không giới hạn rồi saturate **một lần** ở tổng cuối
(`a.acc`). Với kích thước khóa, tổng không thể tràn A62:

- dot S27 (work depth <= 96): 96 * 2^52 < 2^59;
- norm/sum D18 (M = 128): 128 * 2^34 = 2^41.

Vậy cây cộng 62-bit **không saturation trung gian** là bit-exact. Cấu trúc:
row 4:1 → cluster 4:1 (`cluster_reduction_unit`, stateless, pipeline từng
tầng) → `global_reduction_merge` (cộng hai cluster + **accumulator đa-beat duy
nhất**, tự đếm beat theo `count_select`, gate bằng `cycle_commit`). Latency 5,
II=1 khớp 5 tầng register. REDUCE_MAX_ABS tie-break: giá trị |.| bằng nhau →
giữ index nhỏ hơn (khớp `_rank` của model, ổn định tuyệt đối).

## 4. Interface ledger

### 4.1 Decode resource word (không legality check runtime)

Resource word đã được `context_write_certifier` chứng thực lúc nạp; router
decode thẳng field (doc 08 §5): `operation[4:0]`, `input_select[7:5]`,
`output_select[10:8]`, `configuration_id[16:11]`, `count_select[20:17]`,
`lane_mask[24:21]`, `stream_boundary[26:25]`, `clear_before[27]`,
`accumulate[28]`, `commit_after[29]`, `wait_for_ready[30]`,
`wait_for_result[31]`, `event_id[35:32]`.

### 4.2 Transaction protocol

- Request/response đều mang tag; **tag = {resource class, 1 bit sequence}** —
  compiler bảo đảm mỗi class chỉ một outstanding transaction.
- Side effect (accumulate, ghi scalar RF, phát event) chỉ tại `cycle_commit`.
- `wait_for_ready`/`wait_for_result` join vào pair-wide elastic stall qua
  router (skid buffer 1-deep cắt combinational loop, pattern
  `stream_context_router` M4).
- N1: certifier đã cấm `guaranteed_commit` đi cùng wait bits — FU không cần
  đường trả kết quả trong cùng context; response luôn hạ cánh ở context wait.
- N2: mở rộng reservation guard sang resource consumer — kiểm
  configuration-ID ownership tại write-time, không thêm comparator runtime.

### 4.3 Latency/II ledger (authority: JSON; RTL phải khớp đúng)

| Op | Latency | II | Ghi chú RTL |
| --- | ---: | ---: | --- |
| REDUCE_SUM / NORM_SQ / MAX_ABS | 5 | 1 | 5 tầng: row, cluster, merge, acc, out |
| SCALAR_DIVIDE | 28 | 28 | normalizing radix-2, không pipeline |
| SHARED_VECTOR_DOT / NORM_SQ | 6 | 2 | 16 lane folded DSP + 2 tầng reduce |
| SHARED_VECTOR_SCALE / AXPY | 4 | 2 | folded multiply + post-add |
| SHARED_VECTOR_COPY | 2 | 1 | qua codec, không arithmetic |
| RECIPROCAL / SQRT (reserved) | 1 | 1 | fault response, không datapath |

Sidecar rộng **16 lane = một stripe S27** (khớp băng thông stream M4), không
phải 32 lane theo PE; transport quyết định kích thước, không phải fabric.

## 5. Verification và OOC gate

1. Leaf TB replay tagged request từ `context_transaction_golden.json`, so
   bit-exact với vector sinh từ `hardware.py`; random backpressure trên
   ready/valid (pattern M2/M4); seed cố định ghi vào log.
2. Assertion trọng tâm: bảo toàn tag qua stall (không mất/đúp), latency đúng
   hợp đồng từng op (response đúng L cycle sau grant), commit-gating (không
   side effect khi không commit), divide-by-zero → 0 + event (không fault),
   op reserved → fault đúng code.
3. Directed corner: divide saturate hai biên, num/den A62 biên độ lớn nhất từ
   golden, MAX_ABS tie-break, accumulate đa-beat với stall giữa beat.
4. OOC từng leaf @150 MHz, WNS >= +0.2 ns; gate tài nguyên đặt **chính xác**
   ngay từ đầu (như M3 gate RAM): sidecar DSP48 = 16, các leaf khác DSP = 0;
   BRAM = 0 mọi leaf (không bộ nhớ mới — sidecar dùng port scratchpad M4).
5. Thứ tự bring-up: `cluster_reduction_unit` → `global_reduction_merge` →
   `scalar_register_file` → `scalar_function_unit` →
   `shared_vector_arithmetic_unit` → `array_resource_router` (tích hợp thật,
   không mock ở bước cuối).

## 6. Closure decisions

- Reserved scalar operation trả code
  `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT`; detail word là
  `{3'd1, operation[4:0], 8'd0}`.
- Reduction `lane_mask`, MAX_ABS tie-break và multi-beat accumulator đều có
  directed XSim test.
- Scalar state chỉ cần hai architected destination `SCALAR_0/SCALAR_1`; RF vì
  thế là `2 x A62`, hai combinational read port và một commit-gated write port,
  không tạo bank 16-entry không có địa chỉ trong ISA.
