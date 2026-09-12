# Chọn fixed point cho v4 bằng bằng chứng

Đường numerical mới dùng LFSR đã chọn và [numeric contract](architecture/NUMERIC_CONTRACT.md):
normalization trước D, nghiệm X riêng, cùng X cho certificate/outer/output.
Các bảng và study cũ giữ nguyên provenance; D không còn bắt buộc là format x.

Trạng thái: protocol và calibration screen ban đầu; fixed-point LSQR đã có model
opt-in, CGLS mặc định vẫn là reference; **chưa chọn profile tối ưu**.
User đã chọn **SNR khôi phục tối thiểu 20 dB** cho cả float và fixed trên từng
ca ứng dụng, đồng thời mất tối đa0,5 dB SNR và NMSE tối đa1,10 lần float;
ZCU106, mục tiêu100 MHz. Đây là SNR đầu ra so với tín hiệu gốc, không phải SNR
nhiễu measurement hoặc PSNR ảnh. Trên tín hiệu có năng lượng khác0, 20 dB tương
đương NMSE≤0,01. Authority: `numerical.application_quality` trong config.

## Những thứ phải cố định trước sweep quyết định

Mỗi dataset manifest ghi file/version/SHA256, source URL, record/subject/scene,
train-calibration-validation-test membership, measurement operator, basis,
normalization, noise realization, dimensions và policy từng algorithm. Các cửa
sổ của cùng patient/record không được chia ngẫu nhiên vào calibration và test.
Tối ưu lambda/K/step/budget trên calibration, khóa trước held-out.

Tín hiệu gốc s → measurement `y=Phi*s+noise`; nếu `s=Psi*x` thì solver dùng
`A=Phi*Psi`. Báo cáo reconstruction sau inverse transform và undo normalization.
Không thay s bằng K-sparse approximation trước sensing trong application track.
Synthetic exact-sparse vẫn hữu ích cho correctness, nhưng là track riêng.
Không chỉ chạy mỗi algorithm trên application đẹp nhất: có matrix so sánh chung
và showcase có giải thích suitability; xem [benchmark protocol](BENCHMARK_PROTOCOL.md).

## Ba câu hỏi phải kiểm riêng

1. **Algorithm conformance:** công thức, init, support, stop, LS và rollback có
   đúng reference độc lập không? Các model float v4 có tests với oracle độc lập
   và nghiệm LASSO analytic/coordinate descent; bộ tests hiện còn nhỏ.
2. **Quantization loss:** cùng policy và input, fixed giảm chất lượng bao nhiêu
   so với float64? Một support giống nhau không đủ để pass. Support khác nhau
   cũng không tự là sai nếu cả quality và semantics pass.
3. **Application adequacy:** cả float và fixed có đạt SNR/NMSE/PSNR/PRD hoặc
   downstream metric cần thiết không? Fixed gần một nghiệm float kém không có
   nghĩa ứng dụng dùng được.

SNR = `10log10(sum(s²)/sum((s-shat)²))`; MSE = `sum(error²)/N`;
NMSE = `sum(error²)/sum(s²)`. Trên cùng ground truth, NMSE ratio1,10 tương đương
SNR loss khoảng0,414 dB, nên nó chặt hơn điều kiện0,5 dB; lưu cả hai theo yêu cầu.
Nếu có mean/DC side-information, báo thêm centered-signal SNR để tránh DC lớn
che lỗi phần tín hiệu biến thiên. Metadata scale/mean cũng là chi phí encoder.
Centered SNR là diagnostic riêng; không tự áp thêm ngưỡng20 dB cho nó. Không
dùng trung bình nhiều ca để che một ca dưới20 dB hoặc bỏ các ca thất bại.

Reference MSE=0 hoặc gần0: tỷ số relative có thể vô hạn/rất lớn. Model gate hiện
không âm thầm clip denominator. Một absolute-error/noise-floor protocol riêng
phải được chọn **trước test**, ghi rõ lý do và không tùy chỉnh để cứu profile.
Zero-energy signal cần test absolute error riêng. NaN/Inf input bị reject.

## Search space và mục tiêu tối ưu

Không chỉ thử một Q-format chung:

| Miền | Tìm kiếm ban đầu | Đại lượng cần đo |
|---|---|---|
| D: measurement/output |14/16/18/20/24 bit; integer/fraction split từ bound normalize | Input clipping, quantization floor, reconstruction fidelity |
| C: general matrix |14/16/18 bit, range bao gồm ±1 | Operator error, column norms, spectral bound, support decision |
| S: state/proxy/scalars |24/27/32 bit; fraction và range sweep riêng | CG/CGLS stability, ratio dynamic range, residual drift |
| ACC |Tính từ full-range/declared bounds cho mọi dot/prefix/reduction tree | Bit-bound proof, runtime overflow, wide merge/cascade cost |
| Scalar ratios |Numerator/denominator wide, output S | Zero/negative denominator, truncation, underflow, saturation |

Mỗi sweep kiểm tra D, C, S độc lập quanh shortlist rồi xác minh tổ hợp end-to-end;
đổi đồng thời ba width không chứng minh lỗi do DATA width. Khảo sát thêm integer
headroom vs fractional precision, không chỉ tăng tổng width.
`D18/C18/S27/A64` là ứng viên kỹ thuật khớp multiplier, **chưa production**.
`S32` làm control cho precision tốt hơn nhưng S×S/C×S có chi phí DSP/issue khác.

Trước synthesis, chỉ xếp Pareto theo quality và cost proxy: total stored bits,
multiplier operand decomposition, issue count, accumulator width, context bits.
“Tối ưu” ở giai đoạn này nghĩa là nhỏ nhất trong search space thỏa gates, không
phải optimal FPGA area/timing toàn cục. Sau correctness, synth các điểm Pareto
hợp lệ để quyết định theo LUT/DSP/BRAM/timing thực.

## Solver phải có certificate hợp lý với quantization

Pursuit: ordinary LS lambda=0. Fixed model mặc định dùng CGLS; LSQR là đường
opt-in qua `recovery.run(..., ls_solver='lsqr')`. Cả hai dùng normal residual
certificate sau lưu nghiệm: LSQR dùng X riêng nếu được cấu hình, CGLS reference
vẫn dùng D. ADMM: shifted-CG với rho>0 đúng phương pháp,
không tái sử dụng phép regularization đó cho OMP/CoSaMP/SP/HTP/gOMP.

Initial screen dùng relative normal tolerance1e-4 và budget128. Đây là **policy
khảo sát**, chưa phải chứng minh tolerance tối ưu cho mọi D. D hẹp có output
quantization floor: certificate quá chặt có thể fail dù application loss vẫn
nhỏ. Cần phân tích bound `||A_Sᵀ A_S delta_x||` từ LSB/coefficient range và liên hệ
với error budget, rồi freeze certificate/floor trước held-out. Không tùy chỉnh
floor theo seed thất bại hoặc đặt denominator=1 để tránh breakdown.

Phải báo riêng: coefficient/output quantization; input/operator quantization;
inner solver convergence; outer algorithm convergence; domain approximation.
Các lỗi này không được gom thành một chỉ số support-match duy nhất.

Các calibration bounded hiện có phải giữ ranh giới này. [input_scale_study.json](../../reports/v4/input_scale_study.json)
đã hoàn tất trên generated Threefry `M128/s8`, ba seed `23,47,101`, baseline
D18/C18/S27/A64 và cùng ordered support. Raw `amp=0.001` đều không được
accepted sau 128 LSQR bước; power-of-two input scale với `e=12`, `gain=4096`
đều accepted ở 6/5/5 bước, không có arithmetic event. Sau chia lại gain, SNR
fixed là 39.9158, 41.5263 và 42.0063 dB. Exponent này cần được giữ như output
metadata; RTL hiện tại chưa mang nó, nên các bit ADC mất trước normalization
không thể khôi phục. Kết quả chỉ là calibration/proposal, chưa freeze policy,
chưa có application floor hay held-out evidence.

[lsqr_stop_study.json](../../reports/v4/lsqr_stop_study.json) là sweep paired CGLS/LSQR
trên generated `M128/s96`, được ghi incremental để audit; artifact đã hoàn tất
15 rows, mỗi solver accepted 12 rows. Ở wide_control/seed23, rtol `1e-4` vẫn
accepted nhưng coefficient error quantized-SVD là 0.0014388 (CGLS) và 0.0015468
(LSQR); với `1e-5`, là `7.87e-5` và `8.48e-5`. Đây chỉ là bounded evidence về
early stopping, không phải application quality hoặc production default.

Fixed arithmetic hiện dùng Python integer, accumulate chính xác rồi narrow một
lần. `dot_raw` chỉ kiểm tra tổng cuối: chứng minh prefix/tree không overflow
thuộc contract hardware và phải bổ sung trước gọi model là bit-exact RTL oracle.
Routing model có thể kiểm tra từng partial sum; hai tầng hiện chưa nối thành
end-to-end arithmetic/cycle simulator.

LSQR model dùng Golub--Kahan: mỗi bước có `Bv` và `Bᵀu`, các chuẩn vector,
Givens rotation và AXPY. SQRT dùng integer rounding; chuẩn hóa vector dùng
mantissa/exponent (`e=bit_length(norm)`), một DIV trên mantissa rồi rescale theo
exponent. Đây là arithmetic model để so sánh solver, chưa phải RTL schedule,
throughput hay quyết định width.

## Coverage tối thiểu trước freeze

- All11 programs trên tập calibration/validation/test được đóng băng; không
  đổi phương pháp hoặc stop policy để vừa golden RTL.
- M/N/K, supported-support boundaries, tails, low amplitude, near-ties, noisy,
  ill-conditioned/rank-deficient support, correlated/coherent operators.
- Multiple noise levels và matrix seeds; source-level split cho real data.
- Per-case pass/fail, worst-case/p50/p95, failure rates và confidence intervals;
  không chỉ average SNR hoặc chọn vài patch high-variance.
- FISTA/ADMM/PDHG: objective/KKT/dual gap và actual quantized step constraints;
  plain FISTA không bắt buộc objective giảm từng iteration.
- Overflow/saturation/divide-by-zero/inner failure là failed job, không chỉ telemetry.

## Screen đang có trong repository

`scripts/v4/numeric_screen.py` chạy3 cấu hình đại diện trên synthetic exact-sparse,
một camera patch và một ECG segment; đo cả11 thuật toán. Đó là smoke calibration,
không phải held-out application benchmark và không thể kết luận width tối ưu.
Source arrays, operator/basis/measurement hashes và policies nằm trong JSON.
Không có application floor đã freeze, nên `paper_claim_ready=false`,
`selected_production_profile=null`, `synthesis_allowed=false` dù các row pass.

```powershell
py -3 scripts/v4/numeric_screen.py --suite applications --output reports/v4/numeric_screen.json
```

Script screen trả exit0 khi **thực hiện xong khảo sát**, kể cả candidate thất bại;
không được dùng exitcode đó làm release gate. Đọc `rows[].screen_pass`, summary,
completeness và provenance. Bất kỳ gate synth sau này phải fail nếu required
artifact thiếu, sai hash, incomplete, NOT_RUN hoặc chưa có held-out/app floors.
