# Compact reconstruction register map

Trạng thái: **compact CSR map revision 3 và run-configuration revision 6 đã khóa
trong M0**. Revision 3 giữ nguyên runtime-Phi fields
của revision 2 và dùng hai reserved bit cho explicit refinement profile; không
thêm CSR mới.

Thuật ngữ khóa: cấu hình của một lần chạy luôn dùng `run_configuration`; tên cũ
không còn xuất hiện trong module, signal, CSR macro hoặc Python authority.
`memory_configuration` trong context ISA là entry điều khiển stream nội bộ và là
một khái niệm khác.

AXI4-Lite chỉ làm control/status. Toàn bộ tham số một lần chạy nằm trong một
run-configuration block 64 byte ở DDR và được DMA đọc trước khi array chạy. Thiết kế này
loại shadow/active CSR riêng cho M, N, K, seed, threshold, solver và ba địa chỉ
I/O; chỉ còn một cặp register giữ địa chỉ run configuration.

## 1. Quy tắc truy cập

- data width 32 bit, address word-aligned;
- `RO` write trả `SLVERR`; address chưa map/misaligned trả `DECERR`;
- `RW` hỗ trợ byte strobe;
- `W1P` tạo pulse một cycle;
- pending event là sticky, hardware event thắng software clear;
- fetcher capture run-configuration address cùng START pulse; address write bị từ chối
  trong khi engine busy nên không cần shadow/active pointer duplicate;
- run configuration phải aligned 64 byte; START khi busy hoặc address misaligned trả
  `SLVERR`;
- không có software-reset CSR.

## 2. Toàn bộ CSR map

| Offset | Register | Access | Nội dung |
| ---: | --- | --- | --- |
| `0x000` | `IDENTIFICATION` | RO | `0x43534733` (`CSG3`) |
| `0x004` | `VERSION` | RO | architecture, RTL minor, context format, run-configuration revision |
| `0x008` | `CAPABILITY` | RO | run-configuration size, lane count, numeric profile và feature bits |
| `0x00c` | `BUILD_LIMITS` | RO | N_MAX, M_MAX, K_MAX |
| `0x010` | `COMMAND` | WO/W1P | bit 0 START, bit 1 ABORT |
| `0x014` | `EVENT_CONTROL` | RW/RW1C | pending và IRQ enable |
| `0x018` | `STATUS` | RO | lifecycle, completion/error và final summary |
| `0x01c` | `ERROR_INFO` | RO | first error class/code/phase/run-configuration word |
| `0x020` | `ERROR_DETAIL` | RO | detail phụ thuộc error class |
| `0x024` | `RUN_CONFIGURATION_ADDRESS_LO` | RW | run-configuration address low |
| `0x028` | `RUN_CONFIGURATION_ADDRESS_HI` | RW | run-configuration address high |
| `0x02c` | `PROGRESS` | RO | phase, outer iteration, solver iteration |
| `0x030` | `TOTAL_CYCLES_LO` | RO | total cycle low |
| `0x034` | `TOTAL_CYCLES_HI` | RO | total cycle high |

Tổng cộng 14 address, trong đó chỉ ba address chứa state writable:
`EVENT_CONTROL` và hai word run-configuration address. `COMMAND` chỉ sinh pulse.

### `VERSION`

```text
[31:24] architecture revision = 3
[23:16] RTL minor revision = 38
[15:8]  context format revision = 9
[7:0]   run-configuration revision = 6
```

### `CAPABILITY`

```text
[31:24] run-configuration bytes = 64
[23:18] PE lanes = 32
[17:14] numeric profile ID = 1 (D18F14/S27F19/A62)
[13]    trace compiled in
[12]    abort supported
[11]    sparse result
[10]    dense result
[9]     matrix-free certified LS
[8]     internal counter-addressed Phi
[7:0]   algorithm mask
```

### `BUILD_LIMITS`

```text
[10:0]  N_MAX
[19:11] M_MAX
[26:20] K_MAX
[31:27] reserved
```

2K/3K được suy ra từ K và kiểm tra với M/N; không cần capability register riêng.

### `EVENT_CONTROL`

```text
[0] completion pending, write 1 clear
[1] error pending, write 1 clear
[8] completion IRQ enable, RW
[9] error IRQ enable, RW
```

Byte strobe tách pending byte 0 và enable byte 1, nên clear event không vô tình
đổi IRQ enable. `irq = done_pending & done_enable | error_pending & error_enable`.

### `STATUS`

```text
[0]     engine busy
[1]     run-configuration fetch active
[2]     array execution active
[3]     result writeback active
[4]     abort pending
[5]     completion pending
[6]     error pending
[7]     IRQ asserted
[11:8]  stop reason
[18:12] final support count
[31:19] reserved
```

### `ERROR_INFO`

```text
[3:0]   error class
[11:4]  error code
[19:12] phase ID
[24:20] run-configuration word index, hoặc 0 nếu không liên quan
[31:25] reserved
```

DMA fault không cần hai CSR address riêng. `ERROR_DETAIL` trả
`memory_configuration_id`, burst offset và AXI response đủ để tái tạo địa chỉ từ
memory-configuration table.

## 3. Run-configuration block revision 6

Run configuration gồm đúng 16 word 32 bit, aligned 64 byte, được đọc bằng bốn beat
AXI4 128 bit trước khi cấp quyền chạy context.

| Word | Field | Layout |
| ---: | --- | --- |
| 0 | header | `[15:0] magic=0x4352`, `[23:16] revision=6`, `[27:24] reserved=0`, `[29:28] result_mode`, `[31:30] matrix_kind` |
| 1 | dimensions | `[8:0] M`, `[19:9] N`, `[26:20] K`, `[31:27] reserved` |
| 2 | iteration policy | `[15:0] outer_limit`, `[23:16] solver_iteration_limit`, `[28:24] solver_normal_residual_shift`, `[29] reserved=0`, `[31:30] refinement_profile` |
| 3 | reserved | `[31:0] reserved=0`; algorithm constants belong to context/memory configuration |
| 4 | residual threshold low | ACC62 raw `[31:0]` |
| 5 | residual threshold high | ACC62 raw `[61:32]`, `[31:30] reserved` |
| 6-7 | generated-Phi seed | 64-bit Threefry key |
| 8-9 | measurement address | 64-bit input y base |
| 10-11 | dense result address | 64-bit dense x base |
| 12-13 | sparse result address | 64-bit `{index, coefficient}` base |
| 14 | user tag | copied to result-memory header, không tạo CSR sequence bank |
| 15 | matrix numeric | `[17:0] phi_scale_mantissa_UQ1_17`, signed `[22:18] phi_scale_exponent`, `[29:23] phi_column_weight_minus_1`, `[30] require_unit_norm`, `[31] reserved=0` |

`result_mode`: 0 dense, 1 sparse, 2 both, 3 invalid. Address của destination
không được chọn có thể bằng 0. Mọi address được kiểm tra alignment trước DMA.

`refinement_profile`: 0 `STRICT_PAPER`, 1 `BALANCED_VARIANT`, 2
`FAST_VARIANT`, 3 invalid. Profile chỉ chọn policy generic đã được context sử dụng; algorithm mapping và
constants thuộc software-compiled context image, không thuộc RTL program table.

`matrix_kind`: 0 dense signed Rademacher. Encoding 1 remains reserved for the
fixed-column-weight experimental backend and is rejected until its capability
status becomes implemented; encodings 2-3 are invalid. Scale được latch
thành `phi_scale_active`; nó không phải CSR live có thể đổi giữa run:

```text
alpha = UQ1.17(phi_scale_mantissa) * 2^phi_scale_exponent
d_phi = phi_column_weight_minus_1 + 1
```

Dense mode bắt buộc `d_phi=M`. `K` ở word 1 là signal sparsity và độc lập với
`d_phi/alpha`. Chi tiết normalization/RIP policy nằm tại
[12_RIP_AWARE_PHI_GENERATOR.md](12_RIP_AWARE_PHI_GENERATOR.md).

## 4. Run-configuration ownership

```text
AXI4-Lite run-configuration address
    -> reconstruction_configuration_unit
       -> configuration_fetch_unit
       -> configuration_check_unit
       -> active_configuration_store
    -> reconstruction_phase_controller / memory_dma_engine
       / phi_symbol_generator / phi_operator_normalizer
```

- run-configuration fetcher là client read-only của DMA arbiter và chỉ chạy khi array idle;
- validator kiểm tra magic/revision/reserved/range/workspace/address;
- active run configuration chỉ có một bản, giữ ổn định đến completion/error;
- run-configuration fault phát error event; START write đã hoàn thành trước đó không
  cần chờ AXI DMA;
- 64-byte startup traffic là hằng số, không tăng theo M/N/K và không thể thành
  steady-state bottleneck.

## 5. Validation bắt buộc

- M/N/K khác 0 và không vượt build limits;
- SP 2K và CoSaMP 3K không vượt M/N/work capacity;
- outer/solver limits khác 0;
- refinement profile legal; base strict golden luôn dùng profile 0;
- IHT/HTP có gradient step khác 0;
- gOMP group size là `word3[31:27]+1`; `L*K` phải không vượt M, N và physical
  work capacity (baseline cho phép tới L=3 khi K=32);
- residual threshold high chỉ dùng 30 bit của ACC62;
- current-build matrix capability phải implemented; hiện chỉ dense Rademacher;
- scale mantissa dùng canonical UQ1.17 `[1,2)`; signed exponent phải không lớn
  hơn 11 để data-normalizer shift luôn dương. Exponent 12..15 bị từ chối với
  error code `0x43`, word 15;
- dense mode có column weight bằng M;
- `require_unit_norm` kiểm tra `d_phi*alpha^2` trong declared tolerance;
- production strict mode chỉ chấp nhận qualified seed policy của build;
- result mode hợp lệ và address được chọn aligned;
- run-configuration/context/program revision khớp active image.

Detailed phase counters, saturation counters và từng DMA stall counter không còn
là CSR. Chúng đi vào optional trace stream khi debug build bật trace; production
chỉ giữ `PROGRESS`, first error và `TOTAL_CYCLES`.
