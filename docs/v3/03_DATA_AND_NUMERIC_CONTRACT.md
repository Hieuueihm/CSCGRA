# v3 - Data and numeric contract

Trạng thái: **width/rounding profile đã khóa; runtime-Phi-scale certificate đang
được mở lại từ run-configuration revision 2 và giữ trong target revision 3**. RTL phải dùng đúng contract này và
không được suy `alpha=1/8` từ opcode hoặc controller state.

Tài liệu này là nguồn sự thật duy nhất cho width, binary point, rounding,
saturation và range fault của v3. Không được lặp lại hằng số khác giá trị trong
controller, PE, SFU, testbench hoặc model.

## 1. Profile đã khóa

| Miền | Width | Format | Miền biểu diễn | Dùng cho |
| --- | ---: | --- | --- | --- |
| `data_t` | 18 | signed Q3.14 | `[-8, 7.99993896484375]` | y, x, residual, PE lane |
| `solver_t` | 27 | signed Q7.19 | `[-128, 127.99999809265137]` | refinement state, scalar, correlation score, Top-K score |
| `acc_t` | 62 | signed raw | binary point theo opcode | MAC, dot, reduction, wide-limb collector |

Tên profile normative là:

```text
D18F14_S27F19_A62
```

Ba width là compile-time constant. Software chỉ cấu hình dữ liệu và thuật
toán, không cấu hình Q-format.

## 2. Lý do chọn profile

Sweep nhiều tầng so sánh DATA 16/17/18/20/24 bit, SOLVER 24/26/27/28/32/40
bit và accumulator tương ứng trên historical matrix-free PCG tại LS dimension `S=32`,
`S=64` và `S=96`, sau đó kiểm tra end-to-end cả tám thuật toán.

- DATA18 giữ vector-sidecar mixed multiply ở operand width 18-bit; DATA20/24 không đem
  lại cải thiện quyết định support đáng kể trong sweep.
- SOLVER27 giữ range Q7, cho thêm một fractional bit so với S26, đạt toàn bộ
  numerical gate và vừa trực tiếp operand 27-bit của mixed multiply 27x18.
- SOLVER28 chỉ cải thiện nhỏ residual/iteration nhưng vượt operand 27-bit;
  S24 không đạt normal-residual gate.
- ACC62 có 2.415 bit positive headroom cho worst-case dot 96 phần tử Q7.19.

Profile `D18F14/S28F20/A64` được giữ làm high-margin debug/fallback; profile
`D18F14/S32F24/A72` là high-precision debug. Cả hai không phải production.

## 3. Miền chuẩn hóa và runtime Phi scale

Build được certificate cho:

```text
N <= 1024
M <= 128
K <= 32
work_dimension <= 96
Phi = alpha * S
S[m,n] thuộc {-1,+1} cho dense production candidate
alpha lấy từ active run parameter register
|x_true[n]| <= 0.75
```

Gọi `d_phi` là exact nonzero count/cột (`d_phi=M` cho dense). Bound bảo thủ trở
thành tham số theo run configuration:

```text
|y[m]|          <= K * alpha * x_limit
|Phi^T r[n]|    <= d_phi * alpha * residual_limit
column_norm_sq   = d_phi * alpha^2
```

Case cũ `K=32`, `d_phi=M=128`, `alpha=1/8`, `x_limit=0.75` trả lại
`|y|<=3`, `|residual|<=6`, `|Phi^T r|<=96`. Đây chỉ là một certificate point,
không phải architecture invariant. Mỗi miền `(K,d_phi,alpha,input_limit)` mới
phải có bound/sweep tương ứng; scale register không phải giấy phép bỏ qua range.

Host phải normalize dữ liệu trước DMA. Shell kiểm tra range của y; mọi
saturation nội bộ hoặc input ngoài contract đặt sticky `numeric_range_fault`.
Job không được báo success nếu fault này xuất hiện.

Symbol matrix production candidate được xác định bit-exact bởi
`Threefry2x32-20(seed,column,row_block)`. RTL không nhận hoặc lưu word D18 của
Phi. Blueprint revision 2 tách symbol và runtime scale như sau:

```text
signed_sum_DATA   = sum(+/- (data_raw << 5)) ở F19
signed_sum_SOLVER = sum(+/- solver_raw) ở F19
Phi-dot           = scale_once(signed_sum, alpha), rồi narrow một lần
```

Phép align DATA `<<5` là exact. Không round từng term trước khi cộng. Scale
mantissa/exponent được áp một lần ở boundary theo
[12_RIP_AWARE_PHI_GENERATOR.md](12_RIP_AWARE_PHI_GENERATOR.md), dùng cùng
round-nearest/ties-away và saturation contract như mọi narrowing boundary.

Current `models/v3/phi_generator.py`, phase golden và numeric report vẫn encode
revision-1 `+/-1/8`; chúng là evidence cũ và phải được regenerate sau khi
run-configuration/scale contract freeze. Không sửa golden trước khi paper/hardware
model đã nhận cùng matrix profile.

## 4. Binary point theo opcode

`acc_t` không có một binary point cố định:

| Phép toán | Operand | Raw accumulator fraction | Narrow về |
| --- | --- | ---: | --- |
| Vector-sidecar multiply/dot | DATA x DATA | 28 | DATA hoặc SOLVER theo context |
| General DATA x SOLVER | DATA x SOLVER | 33 | SOLVER |
| Generated Phi x DATA | symbol x DATA | exact align F14 -> F19, scale boundary | SOLVER |
| Generated Phi dot SOLVER | sum signed raw SOLVER | 19, rồi runtime scale once | SOLVER |
| Refinement dot | SOLVER x SOLVER | 38 | scalar SOLVER sau divide/ratio |
| Add/sub cùng miền | cùng format | giữ nguyên | cùng format |

Context/opcode phải mang accumulator-format tag. Formal phải chứng minh tag,
valid và payload đi cùng pipeline; không được suy binary point từ controller
state ở cuối datapath.

## 5. Rounding và saturation

Quy tắc normative:

1. Accumulate toàn bộ ở precision raw của `acc_t`.
2. Chỉ round một lần tại boundary narrow đã định nghĩa.
3. Round-to-nearest, tie away from zero.
4. Narrow bằng signed saturation, không wrap.
5. `abs(MIN)` trả về `MAX` và đặt saturation event.
6. Divide-by-zero hoặc denominator không dương trong refinement đặt breakdown fault;
   không thay denominator bằng 1 một cách im lặng.

Với right shift `s>0`, magnitude được cộng `2^(s-1)` trước shift rồi khôi phục
dấu. RTL và model phải dùng cùng công thức cho số âm; không dùng trực tiếp
`(negative + half) >>> s` vì đó không phải ties-away-from-zero.

## 6. Accumulator bound bắt buộc

Q7.19 có raw positive max `2^26-1`. Với dot dài tối đa 96:

```text
DOT_RAW_MAX = 96 * (2^26 - 1)^2
            = 432,345,551,342,665,824
ACC62_MAX   = 2^61 - 1
            = 2,305,843,009,213,693,951
headroom    = log2(ACC62_MAX / DOT_RAW_MAX)
            = 2.415 bit
```

Bound này phủ toàn miền solver không-saturation, không cần một giả thiết ẩn
như `|solver vector|<=8`. Tại dot length 128, ACC62 vẫn còn xấp xỉ 2 bit
headroom. Nếu sau này `work_dimension` vượt 128, generator phải tính lại bound.

## 7. Historical PCG width-sweep evidence

Sweep hiện tại dùng:

- `N=1024`, `M=128`, `K=32`;
- LS dimension 32/64/96;
- random và near-correlated support matrices;
- 32 seeds, tổng 160 case cho mỗi profile;
- paper-equivalent least squares `lambda=0`, 50 dB measurement noise;
- fixed-point PCG certificate `||r||/||b|| <= 2^-14`, tối đa 128 iteration.

Kết quả cho profile production:

| Metric | Kết quả |
| --- | ---: |
| Converged | 160 / 160 |
| Max iteration | 98 |
| Max random-case relative solution error | `1.080e-3` |
| Max all-case relative solution error | `7.305e-3` |
| Max all-case normal residual | `6.723e-5` |

Đây là evidence khóa width, không phải certificate cho target restricted
refinement. M0 bổ sung sweep strict/balanced/fast và post-D18 certificate trước
RTL shared vector arithmetic unit.
| Min fixed-vs-float Top-32 overlap | 32 / 32 |
| DATA saturation | 0 |
| SOLVER saturation | 0 |
| Observed ACC overflow | 0 |
| Analytic ACC bound | PASS, 2.42-bit headroom |

Nguồn tái lập:

- `scripts/numeric/v3_numeric_sweep.py`
- `reports/v3/numeric_width_s27_lambda0/results.json`
- `reports/v3/numeric_width_s27_lambda0/summary.md`
- `reports/v3/end_to_end_solver27_stress32/summary.md`

Certificate này khóa width và arithmetic policy tại scale point `1/8`. Nó chưa
certificate toàn miền runtime scale và chưa thay thế bit-exact end-to-end
regression của tám thuật toán, RTL formal proof, synthesis hoặc post-route timing.

`lambda>0` chỉ được dùng trong một profile regularized riêng; không được đưa
vào paper golden hoặc production hardware golden vì sẽ đổi bài toán LS mà các
paper gốc định nghĩa.

## 8. Formal và assertion phải có trong RTL sau này

- accumulator không overflow cho mọi transaction tuân theo declared bound;
- mọi narrow overflow tạo đúng saturated value và increment event đúng một lần;
- rounding positive/negative đối xứng và đúng ở tie;
- score không narrow về DATA trước exact Top-K;
- data/format tag không lệch valid qua pipeline;
- runtime Phi scale bất biến trong run và chỉ round một lần/operator boundary;
- `d_phi*alpha^2` unit-norm check khớp run-configuration policy;
- divide-by-zero và refinement non-positive denominator không commit coefficient;
- `numeric_range_fault` sticky đến software acknowledge hoặc START hợp lệ kế tiếp;
- build ID/CSR phản ánh đúng profile `D18F14_S27F19_A62`.

## 9. Điều kiện mở lại quyết định width

Chỉ mở lại profile nếu có ít nhất một thay đổi:

- `K_MAX > 32`, `WORK_MAX > 96` hoặc `M_MAX > 128`;
- matrix scale/kind hoặc certified scale range thay đổi;
- input normalization thay đổi;
- refinement/divider arithmetic thay đổi;
- synthesis chứng minh profile hiện tại không đạt timing/resource và candidate
  mới vẫn pass đầy đủ numerical + formal + bit-exact gates.
