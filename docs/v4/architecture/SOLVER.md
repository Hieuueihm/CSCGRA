# LS solver: quyết định, dữ liệu và bằng chứng

**Contract hiện hành cho đường LSQR/LFSR mới:** [NUMERIC_CONTRACT.md](NUMERIC_CONTRACT.md)
quy định normalization trước D, nghiệm X riêng và kiểm sau X, không narrow lại
về D ở outer commit. Các phần sau D bên dưới mô tả reference cũ.

Trạng thái: đặc tả trước RTL; Python numerical models và isolation studies đã
có. LSQR là model fixed-point opt-in; CGLS mặc định được giữ làm reference.
Chưa freeze width/tolerance, chưa có solver RTL hoặc kết quả synth/impl.

[Quyết định chọn solver](LS_SOLVER_DECISION.md) đặt LSQR làm ứng viên so sánh
ưu tiên với CGLS; chọn theo tổng cycles ở cùng accuracy. Hợp đồng CGLS dưới
đây là reference model, chưa phải lựa chọn solver cuối cho RTL.

Đọc [ZCU106 walkthrough](ZCU106.md) trước nếu cần giải thích LS qua ví dụ
chọn 8 cột, rồi tính 8 hệ số trên cùng 32 PE.

## 1. Chọn gì và vì sao

**Baseline pursuit: CGLS không regularization, chạy bằng context trên cùng 32 PE.**
OMP/gOMP/CoSaMP/SP/HTP gọi `min ||A_S x-y||₂`, với support S đã quyết định
bởi outer algorithm. MP/IHT/GP không tự gọi LS chỉ vì cùng dùng PE.
Không tạo Gram `A_SᵀA_S`, inverse hay một LS datapath 32 multiplier khác.
Lý do chọn baseline là reuse GEMV, DOT, AXPY, DIV và support cache; đây là
quyết định kiến trúc có điều kiện, không phải kết luận CGLS ổn trên mọi dataset.
[Stanford SOL CGLS](https://web.stanford.edu/group/SOL/software/cgls/) mô tả
operator theo hai phép `A*v`, `Aᵀ*u`; chính tác giả khuyến nghị LSQR/LSMR khi
shift không âm. Vì vậy phải có đối chứng robustness trước khi freeze solver.

**ADMM-LASSO dùng shifted-CG riêng:**
`(AᵀA+rho*I)x = Aᵀy+rho*(z-u)`, với `rho>0` của ADMM.
Operator được tính bằng hai GEMV và một vector update, không lập Gram.
Nếu A thiếu rank, shift vẫn làm operator SPD trong số thực; quantized rho phải
dương và arithmetic phải pass. Không đưa rho vào pursuit để cứu breakdown.
FISTA/PDHG không cần inner LS. Tái dùng kernel không đồng nghĩa đổi objective.

| Lựa chọn | Vai trò v4 | Điều phải đo/chứng minh |
|---|---|---|
| CGLS matrix-free | Baseline pursuit trước RTL | Quality, conditioning, iterations, certificate cost, failure rate |
| Householder QR, rank-aware SVD | Oracle độc lập; QR candidate ablation nếu support nhỏ/khó | QR factor/update O(MS²), storage, pivot/rank policy, sqrt/divide/rotation cost |
| LSQR | Alternative fixed-point opt-in qua `recovery.run(..., ls_solver='lsqr')` | Bidiagonalization, norm/sqrt/rotation precision, total cycles và cùng quality |
| Gram + Cholesky/inverse | Không chọn baseline | O(MS²) formation, S² storage và sai số formation; inverse không cần thiết để giải LS |

Với full rank trong số thực, `kappa₂(A_SᵀA_S)=kappa₂(A_S)²`. Không lưu Gram
tránh sai số khi *tạo và lượng tử hóa Gram*, nhưng không loại bỏ conditioning
của bài toán hay bảo đảm hội tụ trong số vòng bằng S ở fixed point.
QR tránh tạo normal matrix; rank-deficient cần rank-revealing QR hoặc SVD,
không dùng `solve(R,...)` trên R singular. Study dùng NumPy SVD `lstsq` với
`rcond=None`; QR kiểm chéo chỉ khi full rank. SciPy cũng cung cấp các
[LAPACK least-squares drivers](https://docs.scipy.org/doc/scipy/reference/generated/scipy.linalg.lstsq.html)
để làm oracle độc lập khi mở rộng kiểm chứng.

[LSQR của Paige–Saunders](https://web.stanford.edu/group/SOL/software/lsqr/)
dùng Golub–Kahan, có tính chất số tốt hơn cách CG trên normal equations,
đặc biệt với A ill-conditioned. Đây là lý do khảo sát LSQR, **không** phải
bảo đảm fixed LSQR hẹp bit sẽ pass. LSQR đã có numerical model fixed-point;
QR vẫn chỉ là oracle/candidate và chưa có implementation v4.
Startup thấp của CGLS so với factorization chỉ có lợi nếu tổng số vòng/cost thấp.

## 2. Recurrence và hợp đồng arithmetic

Viết `B=A_S`, số cột `s=|S|`; tất cả phép toán dưới đây là trên B và y đã
quantize. Init `x=0`, `r=y`, `g=Bᵀr`, `p=g`, `gamma=gᵀg`.
Một vòng:

```text
q = B p                  # M x s GEMV
delta = q.T q            # raw wide DOT, length M
alpha = gamma / delta    # wide numerator/denominator -> S scalar
x = x + alpha p          # length s, state S
r = r - alpha q          # length M, state S
x_D = store_D(x)         # candidate; committed x chưa đổi
certificate(x_D)         # residual mới từ y, không dùng recursive r
g_new = B.T r            # s x M GEMV, chỉ khi certificate chưa pass
gamma_new = g_new.T g_new
beta = gamma_new/gamma
p = g_new + beta p
gamma = gamma_new
```

`gamma/delta/gamma_new` giữ raw ACC có scale `2*F_S`, không narrow năng
lượng về S trước DIV; ratio mới round sang S. Divider phải xử lý cả numerator
đã dịch F_S bit (A64/F19 có thể cần 83 bit), hoặc thuật toán quotient tương
đương có chứng minh. Không đặt denominator=1 khi zero/underflow/breakdown.
Accumulator bound phải đúng mọi prefix/tree; Python `dot_raw` mới kiểm tổng cuối.

S27×S27 cần ít nhất hai product issues/PE nếu dùng một multiplier 27×18:
tách một operand thành low17 unsigned + high10 signed, merge product rộng rồi
narrow một lần. DOT và alpha/beta vector scale phải tính chi phí này.
AXPY/SUB clipping, phép round, scalar overflow, tail mask phải khớp model.
Hai DIV phụ thuộc recurrence tạo stall; không được coi divider latency bằng 0.

Model LSQR opt-in dùng Golub--Kahan với `x0=0`: chuẩn hóa `y` thành `u`, nhân
`Bᵀu` thành `v`, rồi mỗi bước thực hiện lần lượt `Bv` và `Bᵀu` mới, hai chuẩn,
Givens rotation, AXPY và candidate store. Chuẩn được tính bằng integer SQRT;
`_vector_div_norm` dùng mantissa/exponent (`e=bit_length(norm)`), một DIV trên
mantissa rồi rescale vector với exponent. Đây là mô hình số học fixed-point đã
chạy được, chưa phải lịch cycle hay thiết kế scalar unit RTL.

## 3. Mapping, traffic và certificate là bottleneck thực

| Microkernel với M128/s8 | Mapping khảo sát | Phụ thuộc |
|---|---|---|
| `Bp`, `Bx_D` | R1: 32 output, mỗi PE một row | p hoặc x_D đã sẵn sàng |
| `Bᵀr`, `Bᵀr_cert` | R4: 8 output, mỗi hàng 4 PE reduce M | forward/update hoặc certificate residual hoàn tất |
| DOT dài M/s | PE partials + mesh/capture reduction | wide merge, không truncate partial |
| AXPY hai vector | 32 lane theo tail | alpha/beta đã được DIV trả về |
| STORE_D/certificate | scratch riêng | cả forward và transpose đọc cùng support generation |

Hai array cùng chạy R1/R4 của **một kernel**. Không gán array0 forward và array1
transpose đồng thời khi transpose đang phụ thuộc kết quả forward.

**Baseline correctness giữ certificate sau D ở mọi vòng như model hiện tại.**
Mỗi vòng chưa hội tụ tốn **4 GEMV**, không phải 2: projected forward, certificate
forward+transpose, và gradient transpose. Model còn có 3 GEMV khởi tạo; khi pass
ở vòng J>0, tổng chính xác là `4J+2` GEMV và `2J-1` DIV (chưa gồm outer residual).
Vòng cuối đã pass bỏ `g_new/beta`. Mỗi GEMV đọc Ms coefficient word, nên riêng
matrix traffic baseline xấp xỉ `4J*Ms*C_width` bit, cộng init/preparation.
Không lấy 32 MAC/cycle nhân trực tiếp ra full-job throughput.

Hướng tối ưu sau khi có bằng chứng: dùng recursive gamma làm bộ lọc rẻ, chỉ
gọi post-D certificate khi có triển vọng hoặc hết budget. Điều đó có thể đổi
vòng dừng và lượng tử hóa các bước tiếp theo; phải tạo policy version mới,
so sánh termination/quality và freeze lại. Hiện **chưa** dùng mẹo này để báo
cycle thấp, chưa đổi model hay lặng lẽ nới tolerance.

Support cache key = matrix generation + **ordered support** + numeric profile
+ orientation; miss phải tính pack. Với layout baseline, full rebuild cần
`s*ceil(M/32)` forward và `s*ceil(M/4)` transpose payload issues: M128/s8 là
288 cycles trước startup/drain/control. Direct forward + packed transpose là
ablation bắt buộc vì direct forward vốn có thể cấp 32 rows/cycle.
Cache chỉ hòa vốn nếu `reuse_count*(C_direct-C_packed) >= P_pack`, với delta>0;
count gồm cả certificate reads. Không reuse sau support reorder dù tập atom giống.

## 4. Chứng nhận nghiệm và floor do D storage

Reference policy hiện tại: `||Bᵀ(y-Bx_D)||₂ <= 1e-4*||Bᵀy||₂`, budget128.
Model tính certificate bằng S arithmetic và compare raw energies chính xác;
study còn tính cùng đại lượng bằng float64 trên B/y/x quantized để thấy sai số
của phép đánh giá certificate. Hai kết quả không được gọi là giống nhau mặc định.
SNR/NMSE và application floor là gate riêng, không thay bằng certificate.

Đặt `x_D=x+delta_x`, `Delta_D=2^-F_D`. **Nếu không clipping**, round-to-nearest
cho `|delta_x| <= Delta_D/2` theo từng phần tử. Với B/y cố định:

```text
g(x_D) = g(x) - B.T B delta_x
|g(x_D)-g(x)| <= |B.T B| (Delta_D/2 * ones(s))
||g(x_D)||_2 <= ||g(x)||_2 + || |B.T B| (Delta_D/2 * ones(s)) ||_2
```

Đây là upper bound của **phần round D**, không phải lower bound chứng minh
không thể có nghiệm D nào khác đạt tolerance, và không bao gồm sai số CGLS.
Có clipping thì bound không còn áp dụng. Có thể dùng bound để thiết kế một
absolute+relative certificate trước held-out; không gắn floor theo seed fail.

Operator/input phải phân tích riêng. Với `B=A+E`, `y_q=y+e`, cùng một x:
`g_q(x)-g_original(x) = Aᵀe + Eᵀ(y-Ax) + Eᵀe - AᵀEx - EᵀEx`.
Đánh giá norm theo bounds của E/e/x/residual rồi cộng sai số GEMV/S arithmetic
nếu cần bound cho hardware certificate. Không gộp operator error vào Delta_D.
RHS norm bằng 0 cần quy tắc absolute riêng; không thay denominator bằng epsilon.
Normal residual nhỏ cũng không chặn coefficient error khi singular value nhỏ;
rank-deficient phải so thêm prediction/objective và minimum-norm oracle policy.

## 5. Isolation study đã chạy: failure được giữ nguyên

Chạy `py -3 scripts/v4/solver_study.py`; report nằm tại
`reports/v4/solver_study.json`. Seed20260918, M32/N13, support8 cố định,
noise30dB; ba loại support × ba profile tái dùng từ numeric screen, không sửa
`models/v4/recovery.py`. Đây là synthetic solver calibration, chưa là dataset
application benchmark. CGLS mặc định gọi `IntegerKernels.least_squares`, còn
`recovery.run(..., ls_solver='lsqr')` gọi model LSQR riêng; failed candidate chỉ
dùng chẩn đoán, tuyệt đối không trở thành accepted output.

| Bằng chứng | Kết quả |
|---|---|
| Tổng 9 rows | 6 certificate pass, 3 compact fail; 0 arithmetic events |
| Well-conditioned, compact D16F12 | Pre-D normal4.05e-5; post-D2.609e-4 ⇒ `ls_not_converged` |
| Cùng failed candidate | Synthetic coefficient SNR loss0.0218dB, NMSE ratio1.00503 so với float original LS |
| Near-collinear D18, kappa≈1976 | Normal6.704e-5 pass nhưng coefficient relative error≈0.9969 so với quantized SVD |
| SVD oracle chỉ round về D | 4/9 vượt relative normal1e-4; componentwise rounding bounds đều được kiểm |

D16 fail ở case đầu không chứng minh D16 vô dụng cho application. Case gần
collinear cũng cho thấy early CGLS khác SVD mạnh dù certificate pass; noise làm
unregularized SVD coefficient nhạy, nên SNR tốt hơn reference không tự chứng minh
algorithm conformance. Không chọn width/solver/tolerance từ chín cases này.
Study ghi condition/rank, SVD+QR agreement, coefficient/prediction error,
operator/input error, full certificate history, events và source/input hashes.
Sáu tests kiểm bound ở các đỉnh hypercube, observer equivalence, D-floor failure,
conditioning counterexample, rank-deficient oracle và zero denominator.

Hai artifact calibration bổ sung phải được đọc cùng cờ hoàn tất. `lsqr_stop_study`
đã ghi đủ 15 paired CGLS/LSQR rows trên generated `M128/s96`; mỗi solver có 12
accepted rows. Ở wide_control/seed23, rtol `1e-4` vẫn accepted nhưng coefficient
error quantized-SVD là 0.0014388 (CGLS) và 0.0015468 (LSQR); với `1e-5`, các số
này là `7.87e-5` và `8.48e-5`. Đây là bằng chứng bounded về early stopping.
`input_scale_study` đã hoàn tất trên ba seed `23,47,101`, baseline D18/C18/S27/A64 và support8 có
`amp=0.001`: raw đều `ls_not_converged` sau 128 bước, còn power-of-two
`e=12/gain=4096` đều accepted ở 6/5/5 bước, không có arithmetic event. Sau chia
lại gain, SNR fixed là 39.9158/41.5263/42.0063 dB. Đây là bằng chứng bounded
cho range và solver calibration; chưa có application floor, held-out claim,
width tối ưu hay RTL normalization policy. Output exponent hiện chưa có trong RTL.

## 6. State ownership và lỗi

Outer controller sở hữu committed `(support,x_D,residual)`. Selection tạo support
candidate; gather tạo cache generation tương ứng. LS subprogram chỉ sở hữu
scratch S vectors `x,p,g` dài s, `r,q` dài M và scratch riêng cho certificate.
Feeder/vector allocator chịu trách nhiệm plane/port conflicts; context compiler
không được alias committed buffers vào scratch trong khi còn khả năng rollback.
SP có thể solve union, prune rồi solve lại: cả chuỗi vẫn là một outer transaction.

Chỉ COMMIT sau LS certificate, final outer residual và mọi arithmetic gate pass.
Budget exhausted/breakdown/certificate fail trả `ls_not_converged`; numeric event
trả `numeric_fault`. Cả support/x/residual giữ nguyên generation trước đó.
SP non-decreasing residual rollback nguyên bộ; không chỉ restore x.
ADMM inner solution giữ S precision, certificate theo shifted operator trước
soft-threshold/store z_D; committed z/dual phải atomic. Không áp dụng post-D
certificate pursuit cho primal S của ADMM bằng cách thay tên hàm.

Trước RTL: freeze quality-aware certificate, failure policy, scratch allocation,
DIV/ACC bounds và full cost context; sau đó triển khai module bằng Luna/Spark
theo yêu cầu người dùng, kiểm bit-exact rồi mới synth/impl.
