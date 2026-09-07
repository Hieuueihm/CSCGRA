# v3 scalable datapath and capacity model

Trạng thái: **K32-only architecture estimate**. Cycle/resource dưới đây chưa
phải RTL/Vivado measurement.

## 1. Active build duy nhất

| N | M | Kmax | Top-2K | LS work 3K |
| ---: | ---: | ---: | ---: | ---: |
| 1024 | 128 | 32 | 64 | 96 |

Run configuration của build này reject `K>32`, `M>128` hoặc work depth vượt 96. Không
có K64 runtime mode và không dùng số K64 để claim resource/verification v3.

## 2. Scaling principle

Các resource đắt không phụ thuộc K:

- hai cluster 4x4, tổng 32 base PE;
- one 16-lane homogeneous vector-arithmetic sidecar;
- 32 Phi symbol sign/gate lane;
- một reduction tree, một runtime Phi normalizer II=1, một scalar ratio unit;
- context store và router topology cố định.

Các state phụ thuộc K chỉ tăng tuyến tính:

- retained candidate depth `2K`;
- work support/coefficient depth `3K`;
- solver vectors dài S;
- active-support Phi cache `M*S` sign bit ở dense build; sparse extension thêm
  một nonzero bit/coordinate.

Không có Gram/triangular matrix `SxS`, vì vậy không có state x4/x9 hoặc factor
arithmetic x8/x27 khi support đi từ 32 lên 64/96.

## 3. Matrix-free LS datapath

LS dùng hai primitive:

```text
q = A_S * p
s = A_S^T * u
```

Phi support symbols được fill một lần vào cache rồi replay. Một operator
pass cần lower bound:

```text
C_op = ceil(M*S/32)
```

| Support S | Một A hoặc A^T pass |
| ---: | ---: |
| 32 | 128 cycle |
| 64 | 256 cycle |
| 96 | 384 cycle |

CGLS-RR là recurrence trong unified refinement. Với 16 folded sidecar lane, vector update đạt
trung bình 8 S27 element/cycle. Một divider target khoảng 30 cycle cho mỗi
scalar ratio:

```text
C_iter_floor = 2*C_op + ceil((M+2*S)/8) + 2*L_div
```

| M,S | CGLS iteration floor |
| --- | ---: |
| 128,32 | 340 cycle |
| 128,64 | 604 cycle |
| 128,96 | 868 cycle |

Thêm hằng nhỏ cho fill/drain/router. Cache fill một lần/LS là `C_op + khoảng
21`; post-D18 certificate xấp xỉ `2*C_op`. Iteration distribution lấy từ
restricted-refinement sweep, không ngoại suy từ historical PCG.

Chi tiết solver, certificate và reliable restart nằm tại
[11_LS_SOLVER_ARRAY_BLUEPRINT.md](11_LS_SOLVER_ARRAY_BLUEPRINT.md).

## 4. Phi traffic

### Correlation toàn N

Correlation vẫn dùng generated symbol stream trực tiếp:

```text
ceil(M*N/32) = 4096 cycle
```

Sau pipeline fill, một score xuất hiện mỗi `M/32=4` cycle.

### LS trên active support

Worst-case CoSaMP:

```text
M*S = 128*96 = 12,288 sign bit
dense cache = 384 word x 32 bit = 1 RAMB18E2
sparse seam = 384 word x 64 bit = 1 RAMB36E2
```

Cache chỉ valid trong một LS transaction; support mutation/abort/terminal làm
invalidate. Không lưu full Phi `128x1024` và không có Phi DMA.

## 5. PE và memory bandwidth

Mỗi cluster row nối cố định một bank 72 bit tới bốn PE:

- D18: bốn value/port/row, tổng 32 lane;
- S27: hai value/bank word, tổng 16 element mỗi vector stripe;
- hai port đọc hai S27 operand trong folded-multiply read slot;
- write dùng slot kế tiếp hoặc bounded output FIFO, không giả 2R1W.

Vì memory roof là 16 S27 element/stripe, vector sidecar dùng 16 logical lane.
Cả 32 PE chỉ cần homogeneous ALU/sign-gate/accumulate cho Phi operator. Runtime
scale dùng một shared normalizer ngoài lane path: pre-broadcast cho forward,
post-reduction cho transpose/correlation.

Router là static registered mesh cho traffic tổng quát; row memory,
reduction-up và scalar-broadcast-down là dedicated planes. Không có packet NoC,
full crossbar hoặc general cross-cluster link.

## 6. TOP-K và support capacity K32

| Operation | Retained/work depth | 32-lane scan cost |
| --- | ---: | ---: |
| identify Top-2K | 64 | 2 cycle/accepted replacement |
| prune to K | 32 | 1 cycle/accepted replacement |
| CoSaMP work support | 96 | linear list/bitmap state |

Không allocate depth128/192 trong logical K32 state chỉ để phục vụ một profile
chưa tồn tại. Physical BRAM slack do primitive granularity có thể được để trống
nhưng không được expose qua run configuration.

## 7. Baseline capacity estimate

| Resource group | K32 target | Ghi chú |
| --- | ---: | --- |
| PE | 32 | fixed |
| vector multiply lane | 16 logical | one homogeneous sidecar; tool mapping đo bằng OOC |
| Phi runtime normalizer | 1 pipeline | target II=1; OOC quyết định 1 DSP+fabric hay 2 DSP |
| context RAMB36 | 10 | current context-plane estimate |
| vector scratchpad RAMB36 | 8 | bandwidth floor, `8x72x512` |
| support Phi cache | 1 RAMB18 | dense `384x32`; sparse-capable build dùng RAMB36 |
| full Phi BRAM/URAM | 0/0 | generated |
| Gram/LDLT memory | 0 | forbidden baseline |

Configuration store, support metadata, FIFO và trace phải được sizing riêng sau
liveness/port analysis; không làm tròn mọi small state thành một RAMB36 trong
blueprint rồi gọi đó là resource lock.

## 8. Future K64 seam, không phải profile hiện tại

Nếu sau này tạo build `K=64`, CoSaMP cần `S=192`; practical overdetermined
profile phải tăng M lên ít nhất 256. Các seam rẻ được giữ:

- support count/slot 8 bit;
- row-block 3 bit;
- solver iteration count 8 bit;
- support-cache address 11 bit;
- loop lấy limit từ active count, không unroll theo K;
- PE, vector sidecar, router, reduction và scalar interface không đổi.

Future delta dự kiến chỉ là state tuyến tính: TOP-K 64->128, work 96->192 và
support Phi cache khoảng 1->3 RAMB18. Vector scratchpad hiện có depth estimate
đủ cho M256/S192 nhưng compiler phải chứng minh allocation lại.

Per-iteration matrix traffic tăng gần 4 lần vì `M*S` tăng 4 lần. Đây là lower
bound dữ liệu; số iteration phụ thuộc conditioning, không mặc định tăng 2 lần.
Numeric profile D18F14/S27F19/A62 cũng phải sweep lại trước khi build K64.

## 9. Gate trước RTL

PE/router RTL chỉ bắt đầu sau khi:

1. strict/bounded restricted refinement chạy trên cùng fixed-point `A/A^T` operator;
2. restart/certificate policy được khóa;
3. all K32 positive cases pass post-D18 certificate;
4. mapper chứng minh scratchpad port schedule và router RecMII;
5. ISA/run configuration dùng generic `solver/refinement_*`, không còn PCG hoặc PE capability theo vị trí;
6. runtime Phi scale sweep chứng minh normalizer II=1 và không đổi RecMII;
7. matrix-quality manifest nêu đúng RIP order/probabilistic claim;
8. architecture hash, hardware golden và phase schema được review đồng bộ.
