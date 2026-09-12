# Chọn LS solver để dùng tốt 32 PE và giữ độ chính xác

**Numeric contract mới cho LFSR:** [NUMERIC_CONTRACT.md](NUMERIC_CONTRACT.md)
tách input D khỏi nghiệm X và kiểm sau X, giữ normalized domain xuyên suốt job.
Các phân tích so CGLS/LSQR cùng D dưới đây giữ vai trò reference lịch sử;
không gán kết quả Threefry/D-storage cho shortlist LFSR/X-storage mới.

**Quyết định hiện hành: [QR](QR_SOLVER.md) là solver đích.** Phần so sánh
CGLS/LSQR dưới đây giữ làm khảo sát lịch sử; LSQR không phải fallback trong
recovery mới. Chất lượng QR và cycle toàn chương trình phải được kiểm riêng.

Ngày 2026-09-08. Đây là quyết định khảo sát trước khi chốt RTL. CGLS và LSQR
đều có fixed-point numerical model; `recovery.run(..., ls_solver='lsqr')` là
đường chạy opt-in, còn CGLS mặc định được giữ làm software reference. Chưa có
solver RTL hoặc số đo timing/synth. Hợp đồng đang chạy vẫn nằm trong
[SOLVER.md](SOLVER.md).

**Giữ CGLS làm baseline kiểm chứng, đưa LSQR lên ứng viên so sánh đầu tiên;
chọn solver theo tổng chu kỳ của cả job sau khi vượt điều kiện chất lượng.**
Không chọn chỉ vì CGLS ít phép chia/căn hơn, hoặc vì LSQR có tên gọi ổn định hơn.
Hai lựa chọn đều có thể dùng GEMV, DOT và AXPY trên cùng 32 PE của hai mảng 4×4.
Householder QR có pivot là đối chứng thứ ba cần xét khi số vòng lặp lớn, support
khó, hoặc có lợi thế cập nhật factor qua nhiều lần LS.

## 1. Bằng chứng hiện tại nói được gì

[Model](../../../models/v4/recovery.py), [isolation study](../../../scripts/v4/solver_study.py)
và [report](../../../reports/v4/solver_study.json) đang giải LS không regularization,
khởi tạo bằng zero, tối đa 128 vòng, kiểm normal residual sau khi lưu hệ số về D.
Study chỉ có 9 trường hợp synthetic: M32, support8, noise30dB, ba profile.
Sáu trường hợp được certificate chấp nhận, ba trường hợp compact bị từ chối;
điều này chưa xác lập chất lượng application.

Trường hợp near-collinear D18/C18/S27 có `cond(B) ≈ 1975.75`,
`B = A[:, support]`. Sau 2 vòng, normal relative residual `6.704e-5` đạt điều
kiện nhỏ hơn `1e-4`, nhưng coefficient relative error so với SVD của B/y đã lượng tử
hóa là `0.996869`, trong khi prediction relative error khoảng `0.008865`.
Vì các cột gần giống nhau, hai bộ hệ số rất khác có thể tạo ra dự đoán gần nhau.
Certificate này chưa đủ để chứng minh hệ số tương đương nghiệm LS reference.

Noise cũng làm nghiệm LS không regularization nhạy ở hướng singular value nhỏ.
Trong chính case trên, hệ số CGLS sớm gần truth hơn hệ số SVD; điều đó không tự
chứng minh solver tuân thủ cùng nghiệm LS. Thay bằng LSQR hoặc QR có thể cải
thiện sai số tính toán, nhưng không khôi phục thông tin mà conditioning/noise
đã làm mất. Không tự thêm ridge, giảm rank hay early-stop theo noise để biến
một solver khác thành kết quả của thuật toán hiện hành.

Ngay cả SVD oracle chỉ round về D cũng vượt normal tolerance ở 4/9 trường hợp.
Đổi recurrence không tự sửa được giới hạn lưu hệ số này. Bound trong SOLVER.md
là upper bound cho sai số round không clipping; nó không chứng minh mọi nghiệm
trên lưới D đều bất khả thi.

LSQR fixed-point model đã hoàn tất trong [models/v4/lsqr.py](../../../models/v4/lsqr.py)
và chỉ được gọi khi truyền `ls_solver='lsqr'`; CGLS vẫn là đường mặc định. Báo cáo
[lsqr_stop_study.json](../../../reports/v4/lsqr_stop_study.json) được ghi tăng dần
cho các paired rows trên generated Threefry `M128/s96`; artifact đã hoàn tất 15
rows, với 12 accepted rows cho mỗi solver. Ở wide_control/seed23, tightening
normal rtol từ `1e-4` xuống `1e-5` giữ accepted nhưng coefficient error so với
quantized SVD giảm từ `0.0014388` xuống `7.87e-5` với CGLS và từ `0.0015468`
xuống `8.48e-5` với LSQR. Đây là bằng chứng stop-policy bounded, không phải
quality hay throughput claim. Kết quả bounded đã hoàn tất nằm trong
[input_scale_study.json](../../../reports/v4/input_scale_study.json): trên ba seed
`23,47,101`, raw `amp=0.001` đều hết 128 bước với `ls_not_converged` và còn
candidate chẩn đoán; power-of-two scale đều accepted ở 6/5/5 bước, với `e=12`,
`gain=4096`, không có arithmetic event. Sau chia lại gain, SNR fixed lần lượt là
39.9158, 41.5263 và 42.0063 dB. Đây là bằng chứng calibration cho input range và
LSQR, chưa phải application floor, held-out result hay policy RTL; exponent output
chưa được truyền trong RTL hiện tại.

## 2. So sánh công bằng: recurrence, certificate và phần chưa tính

Gọi `s = |support| ≤ 96`, `M ≤ 128`, J là số bước đã chạy, V là số lần kiểm
certificate bằng residual tính lại từ `x_D`. Một GEMV restricted cần `M*s`
phép nhân cộng hữu ích; đây là số phép toán, chưa phải chu kỳ phần cứng.

| Lựa chọn | Kernel tính nghiệm | Kiểm nghiệm sau D | Chi phí/phụ thuộc phải bổ sung |
|---|---|---|---|
| CGLS matrix-free | Mỗi vòng tiếp tục: một `B*p`, một `Bᵀ*r`, hai DOT năng lượng, hai DIV và các AXPY | Mỗi lần thêm `B*x_D`, `Bᵀ*r_cert`, DOT và SUB | Init, store, scalar stall, wide products, gather, route/reduce, vòng thất bại |
| LSQR matrix-free | Mỗi bước bidiagonalization: một `B*v`, một `Bᵀ*u`, hai vector norm/normalize, AXPY và scalar rotations | Cùng V lần, cùng hai GEMV + DOT/SUB mỗi lần | Init, SQRT/RSQRT hoặc norm tương đương, DIV/reciprocal, rotation precision; reorthogonalization nếu phiên bản chọn dùng |
| Householder QR / QR có pivot | Với `M ≥ s`, factor mới có chi phí bậc `M*s²`; tiếp theo áp dụng `Qᵀ*y` và giải tam giác | Candidate cuối vẫn phải kiểm sau D | Buffer factor/reflector, pivot/rank policy, norm/DIV, triangular dependencies, rebuild/update và hoán vị hệ số |

Tài liệu [Paige–Saunders, Algorithm 583, trang 196](https://web.stanford.edu/group/SOL/software/lsqr/lsqr-toms82b.pdf)
ghi cả CGLS và LSQR đều cần một tích A và một tích Aᵀ mỗi vòng; công việc vector
của LSQR lớn hơn. Bảng đó không gồm certificate sau D, bộ nhớ banked hay chu kỳ
PE của v4. Không dùng số operation trong bài báo như số cycle trên ZCU106.

Với đúng model CGLS hiện tại, certificate chạy cả lúc init và sau mỗi candidate.
Khi pass ở vòng `J > 0`, tổng chính xác là **`4J + 2` GEMV và `2J − 1` DIV**:
ba GEMV init, bốn GEMV mỗi vòng chưa pass, ba ở vòng pass cuối. Chưa tính outer
residual. LSQR có hai GEMV recurrence mỗi bước; nếu cũng kiểm sau D mỗi bước,
thì thường cần thêm hai GEMV mỗi bước. Không so “LSQR hai GEMV” với “CGLS bốn
GEMV” rồi suy ra nhanh gấp đôi.

Một certificate sau D có cùng định nghĩa và cùng cost kernel với cả hai solver.
Ở thí nghiệm đầu, giữ chính sách kiểm mỗi bước để tách ảnh hưởng recurrence.
Thí nghiệm thứ hai mới xét kiểm có điều kiện: dùng residual estimate rẻ để
quyết định lúc chạy certificate, luôn kiểm candidate trước khi accept và tại
điểm kết thúc budget nếu có candidate. Mỗi solver phải báo rõ rule, V và mọi
chi phí; rule mới là policy có version, không được coi bằng baseline mặc định.
Residual estimate của LSQR không thay thế certificate trên `x_D`.

[Stanford SOL CGLS](https://web.stanford.edu/group/SOL/software/cgls/) khuyến nghị
LSQR/LSMR khi shift không âm. [Stanford SOL LSQR](https://web.stanford.edu/group/SOL/software/lsqr/)
mô tả bidiagonalization có tính chất số tốt hơn cách CG trên normal equations.
Đó là cơ sở ưu tiên khảo sát LSQR. CGLS hiện tại dùng `B*p` trung gian, không tạo
Gram và không phải bản CG ngây thơ nhân trực tiếp Gram. Sự khác biệt giữa hai
recurrence trong fixed point cụ thể vẫn phải đo; không suy ra một số vòng hoặc
một mức tăng chính xác cho LSQR từ tài liệu này.

## 3. Phần dùng chung trên hai mảng 4×4

Một support đã chọn nghĩa là LS chỉ đọc các cột B tương ứng. CGLS và LSQR đều
luân phiên quét B theo hai hướng; khác biệt chủ yếu là vector nào đang được
nhân, recurrence scalar và policy dừng. Vì vậy ưu tiên đầu tư vào ba kernel:

- **GEMV:** chọn R1/R4 theo số output, reduction, tail và traffic thực. Forward
  và transpose dùng chung 32 PE; các bước phụ thuộc nhau không chạy đồng thời
  chỉ vì có hai mảng. Support gather/pack và cache invalidation phải được tính.
- **DOT/norm:** PE tạo partial rộng, reduction/capture gộp trước khi round.
  Kiểm bound ở mọi prefix/tree. Energy dài M hay s phải giữ rộng hơn vector;
  tránh narrow tổng bình phương về 24 bit chỉ để đồng nhất datapath.
- **AXPY/SCALE:** dùng lại lanes PE và vector planes. Có thể fuse phép nhân
  cộng chỉ khi giữ đúng điểm round/overflow đã định nghĩa, không đổi số học
  của model dưới tên tối ưu schedule.

Scalar service dùng chung trả kết quả có tag. Baseline cần DIV; LSQR đòi hỏi
norm/rotation, do đó phải khảo sát thêm SQRT+DIV hoặc RSQRT+multiply với xử lý
scale, zero và sai số được kiểm chứng. Chỉ quyết định cách hiện thực sau đối
chứng chất lượng/cost; không cần 32 divider hoặc 32 căn bậc hai. Một scalar unit
chậm có thể để PE chờ, nên reuse PE cao không tự bảo đảm job nhanh.

Trong model LSQR, chuẩn vector được tính bằng integer SQRT có làm tròn rõ ràng.
Chuẩn hóa dùng mantissa/exponent: chọn `e=bit_length(norm)`, thực hiện một DIV
trên mantissa đã chuẩn hóa rồi áp dụng exponent tại điểm rescale vector. DIV,
SQRT, Givens scalar và mọi vector vẫn đi qua format/overflow policy đã khai báo;
đây là arithmetic contract của model, chưa phải sơ đồ scalar unit RTL.

Giữ D (hệ số lưu), C (operator), S (vector/recurrence) và ACC/scalar intermediate
là các vai trò precision riêng. S27×S27 có thể cần nhiều product issues khi PE
dùng multiplier 27×18; DOT/AXPY phải trả phần này. Gamma/delta, norm, tỷ lệ và
Givens rotation cần khảo sát dynamic range/guard bits riêng; không khóa toàn bộ
LS ở 24 bit, cũng không tăng mọi vector lên width lớn chỉ vì một scalar cần nó.

## 4. Khi QR đáng thử

Householder QR cho phép các DOT và update của reflector chạy trên PE, nhưng
factorization phải ghi lại phần ma trận đang cập nhật. Có thể giữ reflectors
trong buffer factor, không cần tạo toàn bộ Q; vẫn phải tính storage và port
cho buffer này, R, pivot và workspace. Với `M ≥ s`, factor QR không pivot có
leading work khoảng `2*M*s² − 2*s³/3` real FLOP khi một multiply và một add
được đếm riêng. Đây là ước lượng arithmetic của phép factor, không gồm solve,
certificate hay đổi thành cycle bằng phép chia 32.

Trailing matrix nhỏ dần và triangular solve có phụ thuộc nối tiếp. Điều đó có
thể giảm mức sử dụng 32 PE, nhất là support nhỏ; cần schedule để biết mức giảm.
Tuy nhiên support nhỏ cũng làm factorization rẻ, nên không loại QR chỉ vì
utilization thấp. Support khó làm CGLS/LSQR chạy nhiều vòng có thể đảo thứ hạng.

OMP thêm từng atom có thể hưởng lợi từ cập nhật QR theo cột với chi phí bậc
`M*s` cho một append, kèm kiểm numerical stability. CoSaMP/SP có merge, prune,
reorder và xóa cột; phải rebuild hoặc có thuật toán update/downdate và cache
generation được kiểm chứng. Không dùng factor cũ qua thay đổi support mà chưa
remap/kiểm đúng. Mọi factor scratch vẫn phải rollback cùng outer transaction.

QR có pivot một mình chưa định nghĩa đầy đủ nghiệm minimum norm khi thiếu
rank. Cần rank threshold và bước complete orthogonal factorization, hoặc SVD
oracle; [LAPACK DGELSY](https://www.netlib.org/lapack/explore-html/dc/d8b/group__gelsy_ga6d1d46ead18df76e993cd4eda6dc1bbb.html)
là ví dụ dùng complete orthogonal factorization để giải minimum-norm LS.
Miền `s > M` cũng có thể xuất hiện trong giới hạn M/s đã nêu: QR tam giác vuông
full-column-rank ở trên không áp dụng; phải có policy LQ/COD/rank-aware riêng.

## 5. Điều kiện chọn trước khi chốt RTL

Đối chứng phải giữ **CGLS mặc định và LSQR opt-in** trên cùng B/y quantized,
ordered support, x0=0, LS không regularization, budget, format và chính sách
kiểm sau D. LSQR đã được implement ở mức numerical model; các sweep đang chạy
chỉ là calibration và phải được đọc theo `complete`/provenance trước khi dùng.
QR float/rank-aware là oracle và đối chứng cost trước, QR fixed point là ablation
khi có dấu hiệu đáng lợi.

Chốt đánh giá thành các điều kiện độc lập trước held-out:

1. **Nghiệm lưu hợp lệ:** certificate tính lại sau D, không arithmetic event,
   không che breakdown/zero denominator. So cả certificate arithmetic của
   model với phép đánh giá float64 trên cùng dữ liệu quantized.
2. **Tuân thủ nghiệm LS:** ghi objective, prediction error và coefficient
   error so với SVD `lstsq(rcond=None)` trên B/y quantized. Khi full rank và
   yêu cầu tương đương hệ số, đặt coefficient tolerance trước thử nghiệm.
   Khi rank-deficient, prediction/objective đủ mô tả fit nhưng không đủ cho
   coefficient equality: nếu yêu cầu minimum norm, phải so với minimum-norm
   oracle. CoSaMP/SP prune theo hệ số nên thay nghiệm có thể đổi support dù
   prediction gần nhau. Không bỏ kiểm hệ số chỉ vì normal certificate pass.
3. **Chất lượng application:** kiểm full outer algorithms với budget/failure
   policy cố định và dữ liệu held-out theo [NUMERICAL_PROTOCOL.md](../NUMERICAL_PROTOCOL.md).
   Giữ giới hạn đã nhận: mất tối đa 0,5 dB SNR và NMSE tối đa 1,10 lần float;
   application floor vẫn phải xác lập. Rank/conditioning/noise và operator/input
   quantization phải được báo riêng; chín case hiện tại chưa đủ chốt ngưỡng.
4. **Tổng cost và lỗi:** ghi số LS calls, J, V, factor rebuild/update, gather,
   coefficient/vector traffic, mesh/reduction, scalar waits, stores, outer
   residual và rollback. Báo mean, tail, worst case và tỷ lệ thất bại theo
   từng nhóm; không làm solver “nhanh” bằng cách tính ít case thành công hơn.

Hàm mục tiêu triển khai là giảm `C_job = C_prepare + C_outer + tổng C_LS +
C_commit/rollback` trong tập ứng viên đạt cùng các điều kiện chất lượng và lỗi,
với ràng buộc DSP/BRAM/LUT/clock của board. Trước có RTL chỉ báo kernel counts,
memory traffic và schedule estimate có giả thiết; sau đó mới đo cycles và
synth/impl. Phải giữ nguyên committed `(support, x_D, residual)` khi LS thất
bại, hết budget hoặc SP rollback; không trả candidate cuối như thành công.

Nếu LSQR vượt quality/cost ở phép so này, thay baseline có version và cập nhật
scalar/context contract. Nếu CGLS vẫn rẻ hơn và đủ chất lượng, giữ CGLS. Nếu cả
hai không đáp ứng hệ số/rank policy, khảo sát QR/COD cùng precision; không nới
ngưỡng hoặc thêm regularization âm thầm để đạt kết quả mong muốn.
