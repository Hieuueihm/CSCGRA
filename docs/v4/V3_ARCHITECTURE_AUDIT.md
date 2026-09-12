# Audit v3 và hợp đồng mapping ứng viên v4

Ngày 2026-09-08. Đọc source đang có trong workspace, gồm các thay đổi ABI15 mới
nhất. Không sửa v3, không chạy synthesis/implementation. Số chu kỳ v4 dưới đây
là mô hình lịch có thể replay; chưa có RTL v4, tần số, PPA hay số đo trên board.

## 1. Những gì v3 hiện tại thực sự có

| Thành phần | Source đang chạy | Ý nghĩa kiến trúc |
|---|---|---|
| 32 full PEs | `compiler/v3/architecture_configuration.json:37`; `rtl/v3/include/architecture_parameters.vh:41`; production instantiation tại `rtl/v3/integration/m13_compute_lifecycle_integration.v:693` | Mask hiện tại là `ffff` ở mỗi cluster. Các đoạn tài liệu cũ nói chỉ hàng đầu là full PE đã lỗi thời. |
| Hai mesh 4x4 | `rtl/v3/cgra/cgra_cluster_pair.v:6`, `:59`, `:82`; `rtl/v3/cgra/cgra_cluster.v:43` | N/E/S/W có register; hai cluster nối dọc bằng bốn cột. |
| Một context cho hai cluster | `rtl/v3/cgra/cgra_cluster_pair.v:20`, `:82`; `compiler/v3/architecture_configuration.json:41` | 16 tile words được broadcast cho cả hai cluster, cùng commit. Có 32 physical lanes nhưng chỉ 16 vị trí instruction khác nhau trong một context. |
| PE ALU không có MUL/MAC tổng quát | `rtl/v3/cgra/pe_alu.v:125`, `:171`, `:248` | ADD/SUB/compare/shift và Phi sign accumulation tồn tại. General multiply vẫn ở vector sidecar. |
| Sidecar 16 lanes, multiply II=2 | `rtl/v3/arithmetic/shared_vector_arithmetic_unit.v:7`, `:45`, `:63` | Exact wide multiply chia thành các partial products; đổi operation family phải drain pipeline. Peak general multiply issue là 8 element-products/cycle trước stall. Không được gọi đây là 32 MAC/cycle. |
| Bridge chỉ giữ một nhóm | `rtl/v3/cgra/pe_vector_bridge.v:27`, `:66`, `:72`, `:124` | Chuỗi EMPTY -> LOADED -> OPERANDS -> PENDING -> RESPONSE -> RESULT -> EMPTY; descriptor chọn đúng một cluster. Không có double-buffer/overlap hai nhóm trong bridge. |
| Scratchpad 8 x 72 x 512 | `rtl/v3/data_movement/vector_scratchpad.v:6`, `:42`, `:64`; `rtl/v3/data_movement/scratchpad_word_codec.v:51`, `:89` | Mỗi bank có hai port; mỗi word là 4 DATA18 hoặc 2 SOLVER27. Dữ liệu solver chỉ dùng 54/72 bit. Hai logical ports dùng chung bank, không đồng nghĩa hai reads + một write/cycle. |
| Điều khiển thuật toán nằm ở software | `compiler/v3/architecture_configuration.json:92`; `rtl/v3/reconstruction_control/reconstruction_phase_controller.v:11` | Không có algorithm-ID decode ở controller. Đây là điểm tốt cần giữ; vấn đề là primitive/ABI và mapping quá gắn với các service recovery. |
| Matrix mode hẹp | `compiler/v3/architecture_configuration.json:98`; `rtl/v3/cgra/pe_alu.v:171` | Mode được implement là dense Rademacher. Có vector từ nhiều dataset chưa chứng minh hỗ trợ sensing operator tự nhiên của MRI, channel estimation hay tomography. |

Các bằng chứng cycle mới nhất ở
`reports/v3/rtl_pe_cycle_opt_20260908/README.md` phải được ưu tiên hơn audit static
ngày 07-09. Compiler hiện bật `PE_REFINEMENT_UPDATE_ENABLED` và
`PE_COLOCATED_AXPY_ENABLED` tại `compiler/v3/scheduled_context_compiler.py:69`.
Hai chuỗi AXPY giữ x trong local RF, dùng shared SCALE, rồi PE ADD. Default
đã bỏ route/receive không cần thiết (`:802`); body II tối thiểu là 6 context
commits, không phải throughput wall-clock II=6 (`:806`).

Không nên đưa route trở lại chỉ để hình kiến trúc giống CGRA hơn. V3 đã đo được
việc đặt producer đúng PE sở hữu output giúp nhanh hơn. V4 cần route có tác dụng
thật: reduction, reuse giữa các stage, hoặc giữ intermediate qua một DDG có lợi.

## 2. Vì sao khó làm v3 rõ ràng hơn bằng thêm adapter

1. **Miền số gắn với đường đi.** Phi local accumulator là 48 bit, global
   accumulator 62 bit; data là D18F14 và solver S27F19
   (`rtl/v3/include/architecture_parameters.vh:9`). Narrowing có ở PE Phi data
   accumulation, shared multiply, capture normalizer, scratchpad codec và DMA.
   Chỉ đổi phép toán theo đại số mà không giữ boundary sẽ đổi thuật toán fixed point.
2. **Sự tổng quát của top-level không kéo theo tổng quát của mapping.** Phase
   controller là programmable nhưng cung cấp condition solver-specific
   (`rtl/v3/reconstruction_control/reconstruction_phase_controller.v:221`), còn
   compiler có các emitter riêng cho IHT/HTP/CoSaMP/SP/GP/GOMP/MP. Tên riêng ở
   software là bình thường; v4 cần hạ chúng về một tập kernel và typed buffers
   nhỏ, thay vì tăng số descriptor/adapter theo mỗi chương trình.
3. **32 full PEs chưa tạo throughput general arithmetic.** Primitive nhân vẫn
   shared, bridge tuần tự theo nhóm 16, và chuỗi mapped chỉ là một phần của sáu
   chương trình. GP/MP không dùng hai chuỗi đó. Thống kê instruction non-NOP,
   RF fields hay số route không thể thay cho useful-operation utilization.
4. **Mixed precision làm giảm bandwidth hiệu dụng.** Một bank stripe cho 32
   DATA18 lanes nhưng 16 SOLVER27 lanes. Sidecar, lane masks, serializers,
   support indices và result collectors phải hiểu nhiều cách đóng gói cùng lúc.
5. **Dữ liệu kiến trúc/tài liệu có nhiều thế hệ.** Numeric contract mô tả active
   profile cũ; architecture JSON có thêm D22/S31/A70 closure candidate
   (`compiler/v3/architecture_configuration.json:24`). Bridge mới vẫn có hardcoded
   bus 432/864 và slicing 27 bit (`rtl/v3/cgra/pe_vector_bridge.v:11`, `:98`).
   Đây là rào cản parameterization đã thấy trong source, chưa phải kết luận rằng
   active D18/S27 run hiện tại sai.

## 3. Correctness cần chặn trước khi tối ưu

| Rủi ro thực tế | Hợp đồng v4 cần có |
|---|---|
| `round(alpha*p)+x` bị đổi thành `round(alpha*p+x)` | Operation graph có explicit NARROW node và format tag. Tối ưu phải giữ node hoặc có kiểm chứng equivalence. |
| Reorder partial sum rồi saturate sớm | MAC và mesh reduction giữ đủ accumulator precision; chỉ narrow tại output boundary. Bắt overflow ở mọi partial sum, không chỉ kết quả cuối. |
| Link register/result register bị đọc cùng cycle vừa ghi | Replay từng chu kỳ với snapshot pre-edge; result chỉ thấy ở chu kỳ sau. RTL phải khớp cùng latency. |
| Tail mask và sparse support đổi thứ tự | Test các size quanh 4, 8, 16, 32; explicit output/reduction/index tags; deterministic support ordering và tie-break. |
| Memory read/write cùng bank hoặc stale port response | Ghi rõ số port và synchronous read latency; compiler kiểm tra bank occupancy. Ready/valid phải giữ cả tag, payload, mask. |
| Cancellation hoặc scalar result của run trước | Job epoch hoặc flush chứng minh được; accepted store không được rollback ngầm; mọi resource completion được retire đúng một lần. |
| LS solver thất bại mà vẫn báo reconstruction success | Float reference, fixed model và RTL đều phân biệt convergence, max iteration, breakdown, range fault; báo metric của mọi case, không bỏ case thất bại. |
| Hai profile không dùng cùng sensing matrix | Matrix/operator identity có shape, seed hoặc checksum, scaling và orientation; cùng A cho float/fixed/RTL. Adjoint check độc lập cho operator mới. |

Các hazard trong bảng là contract cần kiểm chứng; audit này không tuyên bố đã
tìm thấy output sai của một active v3 testcase cụ thể.

## 4. Ứng viên v4 gọn: controller, array, memory, scalar/support services

Một scalar microsequencer quản lý loop, branch và kernel dispatch. Một array PC
và atomic stall vẫn hợp lệ: context chứa **32 tile slots riêng**, cho phép mỗi
PE khác opcode/operand/route. SIMD chỉ là mode lặp cùng slot. Không cần hai
independent PCs để có spatial programmability; cũng không được gọi shared 16
slots là 32 independent contexts.

Mỗi PE có MAC/ADD/SUB/select/abs, local RF nhỏ, accumulator đủ rộng và registered
neighbor links bên trong từng4x4; baseline v4 không có inter-array mesh link.
V3 có connector dọc là hiện trạng audit ở phần1, không phải topology v4 được kế
thừa. Một controller không tính LS trực tiếp. CGLS/CG/gradient update
là chương trình dùng GEMV, DOT, AXPY và scalar ratio. Một scalar divider dùng
chung là hợp lý vì scalar dependence vốn nối tiếp. Top-K/argmax và support
gather/scatter có thể là services tổng quát có tag, output order và latency rõ.

Các kernel dùng lại giữa tám thuật toán:

| Kernel | Người dùng |
|---|---|
| `A*x`, `A^T*r`, restricted `A_S*x`, `A_S^T*r` | Cả tám; restricted operators chủ yếu cho OMP/CoSaMP/HTP/SP/GOMP và direction/line search GP/MP |
| AXPY / scale / subtract / copy | Tất cả qua update hoặc residual; IHT/HTP dense update, LS refinement, GP/MP step |
| DOT / norm / maxabs | Stop certificate, line search và LS ở nhiều thuật toán |
| Argmax / top-K / deterministic tie | MP/OMP/GP, IHT/HTP, CoSaMP/SP, GOMP |
| Union / prune / gather / scatter / commit | Sparse support management, không cần accelerator riêng cho từng tên thuật toán |

Việc thêm FISTA/ISTA/AMP/SOMP chỉ có ý nghĩa sau khi có reference đúng và một
operator/application hợp lý. Tăng số tên algorithm không tự chứng minh generality.

## 5. Mapping từ đầu: chọn trục song song theo shape support

Mô hình thực thi nằm ở `compiler/v4/mapping.py`. Gọi O là số output của `op(A)`,
K là chiều reduction. Đây là K của kernel GEMV, khác sparsity K trong paper.

Hai mode dùng **cùng 32 PEs và cùng matrix layout theo mỗi orientation**:

- **R=1:** mỗi PE giữ một output accumulator, 32 outputs/tile, một vector scalar
  broadcast/cycle, 32 matrix coefficients/cycle. Hợp cho `A_S*p` khi M lớn và
  support S nhỏ. Không cần route cho phép toán này.
- **R=4:** mỗi hàng vật lý giữ một output, 4 PEs chia reduction theo `k mod 4`,
  8 outputs/tile trên hai array. Bốn vector words/cycle broadcast theo column.
  Route thật trên mesh: `c1 -> c0`, `c3 -> c2`; ADD ở c0/c2; `c2 -> c1 -> c0`
  qua hai chu kỳ; ADD cuối ở c0. Tất cả partials giữ accumulator width.

Synchronous matrix reads đi trước MAC đúng một cycle. CLEAR cycle đồng thời
prefetch coefficient đầu; read tiếp theo pipeline với MAC trước đó. Từng event
chỉ consume coefficient đã tới input register, và output của một hop không
được dùng cho hop thứ hai trong cùng cycle. R2 chưa nằm trong MVP vì cần chốt
thêm port/steering contract; không suy R2 từ công thức utilization.

Với matrix và vector đã resident và datapath MAC II=1:

```text
R=1: C1 = ceil(O/32) * (K + 2)
R=4: C4 = ceil(O/8)  * (ceil(K/4) + 7)
R được chọn bởi min(C1,C4), có thể force R cho ablation.
Useful MACs = O*K
MAC-slot utilization = O*K / (32*C)
R4 link transfers = 4*O; scheduled reduction ADDs = 3*O
```

Các hằng số overhead gồm CLEAR, route/reduction và STORE. Không ẩn bằng overlap
chưa implement. Tail zero lanes vẫn có một số reduction ADD/route; chúng không
được tính là useful MAC. Các tỷ lệ này là compute schedule, chưa gồm DMA,
coefficient refill, context load, normalization, bandwidth stall hay support
packing. Chúng không phải end-to-end speedup.

| Kernel shape | Fixed R4 | Fixed R1 | Adaptive | Ý nghĩa |
|---|---:|---:|---:|---|
| restricted forward O=128, K=8 | 144 | 40 | 40, R1 | Tránh trả reduction overhead cho support nhỏ |
| restricted transpose O=8, K=128 | 39 | 130 | 39, R4 | Tránh chỉ dùng 8 PEs suốt một reduction dài |
| full forward O=128, K=1024 | 4208 | 4104 | 4104, R1 | Full matrix có nhiều outputs; route không phải lúc nào cũng giúp |

Đây là một giả thuyết kiến trúc có thể ablate: **shape/support-aware mapping +
layout dùng chung cho hai reduction modes + cache restricted operator**. Tính
mới phải kiểm tra literature và đo tổng traffic/cycle; MAC/RF/mesh hay chọn loop
axis riêng lẻ không phải novelty được xác lập ở đây.

## 6. Bank layout, steering và footprint

Layout cho logical matrix `op(A)`:

```text
bank(o,k) = (o + 8*k) mod 32
addr(o,k) = floor(o/32)*K + k
bank_depth = ceil(O/32)*K
```

R1 đọc 32 o liên tiếp ở một k: tất cả bank khác nhau. R4 đọc 8 o liên tiếp
bắt đầu tại bội 8 và 4 k liên tiếp bắt đầu tại bội 4: cũng đủ 32 bank khác nhau.
Mỗi bank chỉ cần 1 read/cycle cho coefficient feed. Đây là mapping đã test,
không phải giả định có thể dùng bank layout v3 mà không thay memory.

Không bắt buộc arbitrary 32x32 crossbar cho hai mode trên:

- R1 giữ `bank mod 8` và rotate bốn nhóm 8 banks theo `k mod 4`.
- R4 là fixed 8x4 transpose wiring cộng rotation bốn nhóm theo
  `floor(output_base/8) mod 4`.

Mode mux/rotation, registers, wire fanout và placement vẫn tốn tài nguyên, phải
được synth/route về sau. Không có số LUT/Fmax suy ra từ biểu thức bank.

Forward và transpose **khác orientation layout**. Có ba lựa chọn phải tính đủ:
giữ hai copies, repack lúc đổi orientation, hoặc cache hai views của support.
Mô hình hiện giữ một orientation mỗi schedule, không tự giả định transpose miễn phí.

M128/N1024 và coefficient width W, không padding ở hai full orientations:

| W | Một orientation payload | Hai orientations payload | BRAM36 theo bit capacity tối thiểu, hai copies |
|---|---:|---:|---:|
| 18 | 288 KiB | 576 KiB | 128 |
| 22 | 352 KiB | 704 KiB | 157 (ceil) |
| 27 | 432 KiB | 864 KiB | 192 |

Con số BRAM là lower bound theo bit capacity, chưa gồm organization widths,
banks, replication, ECC, vector/RF/context/cache. Ví dụ W22 vượt một 18-bit
mode có thể làm block count thực tế tăng hơn phép chia tổng số bit. Không dùng
bảng này thay utilization report của target FPGA.

Với support S8 và M128, full-bank uniform depth làm forward view chứa 128*8
words, nhưng transpose view O8/K128 padded tới 32*128 words, gấp 4 payload.
`Schedule.metrics` xuất cả payload words và padded words để không bỏ chi phí
này. Sparse bank allocation/packed cache là bước tối ưu riêng cần chứng minh
address generator và steering, không được lấy footprint packed rồi dùng schedule
uniform-depth mà thiếu implementation nối hai mô hình.

General dense matrix peak read là `32*W_A` bits/cycle ở SRAM. R1 cần một vector
word/cycle, R4 cần bốn; vector broadcast và local accumulation tránh đọc 64
independent operands mỗi cycle. Với `f` Hz, bandwidth nội bộ coefficient là
`32*W_A*f/8` bytes/s. Nếu fetch trực tiếp từ external interface rộng B bits,
lower bound refill là `ceil(O*K*W_A/B)` cycles với bus lý tưởng; bandwidth hữu
dụng thấp hơn sẽ tăng thời gian. Structured/sign operator có thể thay coefficient
SRAM feed nhưng phải báo đúng operator và generator/transform costs.

## 7. Fixed point quyết định datapath, không chỉ số bit của một typedef

Chưa chọn width v4 từ audit này. Mặc định accumulator_bits=64 trong mapping
chỉ là tham số của replay; không phải profile production được khóa. Sweep cần
đo SNR/MSE và failure rate trên split dữ liệu chưa dùng để tune, rồi chọn
Pareto giữa quality, multiplier decomposition, storage và bandwidth.

Với full-range signed operands width Wa/Wb và reduction length L, conservative
raw accumulator width là `Wa+Wb+ceil(log2(L))`; tighter bound chỉ dùng khi input
normalization/range certificate được kiểm chứng. Các accumulator cho dot
SOLVERxSOLVER, matrix COEFFxSOLVER và vector DATAxDATA có thể khác nhau nhưng
phải có format tags, precise narrowing, overflow events và golden thống nhất.

Source v3 đã mô tả primary product 27x18. 27x18 operands khớp một primary
product; 27x27 cần thêm high-part handling, và 31x22 vượt cả hai phía của
primary product. Exact resource/II là quyết định implementation:
time-multiplex partial products làm tăng II; parallel decomposition tăng
multiplier resources. Vì vậy chọn D22/S31 vì quality không thể tiếp tục khẳng
định 32 one-product MACs/cycle hoặc 32 DSP mà chưa hạ phép nhân và kiểm tra.

Nếu MAC có II>1, compile schedule hiện tại phải bị coi là **unsupported** cho
datapath đó hoặc được regenerate đúng stalls; không chỉ nhân report Fmax bằng
32. DOT/NORM và scalar divide cũng phải được kiểm chứng riêng trước full program.

## 8. Phần đã kiểm chứng và phần còn thiếu

`verification/v4/test_mapping.py` có 15 test methods, gồm 480 signed-integer
GEMV replay cases (80 geometries x 2 orientations x adaptive/R1/R4). Expected
result tính bằng direct integer matvec độc lập; replay thực sự đi qua bank
read registers, MAC, các link registers, ADD và STORE. Negative cases gồm
same-cycle multihop, false mesh edge/wrap, stale route value, bank/address
mismatch, duplicate PE/link, thiếu store, wrong shape/type và accumulator overflow.

```powershell
py -3 -m unittest verification.v4.test_mapping -v
py -3 -m compiler.v4.mapping --rows 128 --columns 8 --output reports/v4/mapping/support_forward.json
py -3 -m compiler.v4.mapping --rows 128 --columns 8 --transpose --output reports/v4/mapping/support_transpose.json
```

Chưa có RTL v4, loader ABI, fixed-point GEMV boundary lowering, arbitrary DDG
mapper, kernel fusion, support gather controller, adversarial context verifier,
vector scratchpad scheduling cho AXPY/DOT, or full eight-program mapped trace.
Restricted cache rebuild/transpose conversion costs chưa implement. Chỉ sau khi
các phần này khớp model và quality gate mới có cơ sở chạy synthesis/implementation.
