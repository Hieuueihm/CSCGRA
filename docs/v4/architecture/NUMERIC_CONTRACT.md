# Hợp đồng numerical: LFSR, chuẩn hóa, lưu nghiệm và dừng LS

LFSR đã được người dùng chọn. Tài liệu này định nghĩa đường dữ liệu numerical
đang khảo sát; các độ rộng trong bảng là shortlist, chưa là profile production.
Model có thể chạy; chưa có RTL, context execution hoặc chứng nhận application.

## 1. Chuẩn hóa một lần cho cả job

Host lấy `p=max(abs(y))` từ measurement đầu vào, trước lượng tử hóa D. Nếu p>0,
chọn số nguyên e duy nhất sao cho `0.25 < 2^e*p <= 0.5`. Nếu y=0, chọn e=0.
Model dùng frexp/ldexp để xử lý đúng cả giá trị nằm ngay biên lũy thừa hai.
Phạm vi e của baseline là [-31,31]; vượt phạm vi thì reject, không clip.

```text
y_normalized = 2^e * y
y_D = quantize_D(y_normalized)
```

Phi/B giữ nguyên scale của operator. Không tự trừ mean, đổi seed, đổi basis hoặc
chuẩn hóa lại giữa các lần LS. Khi ứng dụng có mean/basis riêng, metadata đó là
một hợp đồng riêng. Chuẩn hóa không phục hồi bit đã mất ở ADC trước đó.

Toàn bộ residual, LS state và nghiệm x trong accelerator ở miền normalized.
Kết quả host giải mã bằng `x_original = 2^-e * decode_X(raw_x)`; không round lại
về D trước khi trả kết quả. Nếu sau này ứng dụng đòi một format output khác,
phải bổ sung quantization/quality gate cho bước đó.

Metadata đi cùng job/output: normalization revision, e có dấu, numeric profile
id và raw X format. Sáu bit có dấu đủ chứa e của baseline, nhưng định dạng AXI
descriptor chưa được pack hoặc chạy trong RTL. Vector/context không tự đoán e.

Absolute residual tolerance đổi thành `2^e*atol`. Với LASSO objective
`0.5*||Ax-y||² + lambda*||x||1`, dùng `lambda_normalized=2^e*lambda`, giữ step và
rho; objective mới bằng `2^(2e)` lần objective gốc khi `x_normalized=2^e*x`.
Relative normal tolerance không đổi. Các stop rules khác phải kiểm riêng.

## 2. Tách D, C, S, X và ACC

| Miền | Vai trò | Shortlist sau khảo sát |
|---|---|---|
| D | Measurement tại biên vào | D18F14 |
| C | Coefficient Phi/B sau lượng tử hóa | C18F16 |
| S | Vector/scalar arithmetic, RF và vector planes | S27F22 |
| X | Hệ số nghiệm đã commit, dùng cả cho LS và outer | X24F20 |
| ACC | Tích/tổng rộng trước điểm rescale | ACC64 |

F là số bit phần lẻ, tổng width đã gồm bit dấu. D18F14 và X24F20 đều có range
xấp xỉ [-8,8), nhưng bước lượng tử X nhỏ hơn D 64 lần. S27F22 có range [-16,16),
ít headroom hơn S27F19 [-128,128); phải giữ lỗi overflow thay vì giả định đủ range.
Chuẩn hóa y không bảo đảm x nhỏ khi B gần singular.

Mỗi lần lưu: `S -> round/saturate X -> embed chính xác vào S`. X phải là tập
con của S về cả range và fractional grid; model reject X không thỏa điều này.
Certificate, prune/ranking, residual và outer commit đều đọc cùng x_X. X không
phải buffer LS tạm rồi âm thầm narrow lại về D ở outer.

Trong model, vector planes vẫn mang S-width; X là điểm round có ý nghĩa semantic.
X24 không tự tạo thêm 24-bit PE hoặc một LS datapath khác. So với S27F19, S27F22
giữ nguyên operand widths và full-range ACC bound: S27×S27 dot dài1024 cần64bit.
Đổi fractional split vẫn cần rescale/round constants trong context và RTL.
Không suy ra LUT/DSP/timing từ số width này khi chưa synth.

API nghiên cứu: `IntegerLSQRKernels(..., solution_format=Format(24,20))` và
`recovery.run(..., ls_solver='lsqr', solution_format=...)`. Input D vẫn lấy từ
Profile. `Result.raw_x_format` ghi format thật; mặc định cũ không truyền X vẫn
dùng D. Proximal reference hiện chưa có X riêng, nên báo cáo phải ghi storage D.

## 3. Dừng LS trên nghiệm đã lưu

LSQR giữ `x0=0`, không regularization; budget128 là khảo sát. Sau mỗi candidate,
store X trước, tính lại residual và normal từ cùng B/y đã quantize:

```text
r_X = y_q - B_q*x_X
g_X = B_q^T*r_X
h   = B_q^T*y_q
accept_runtime = ||g_X||² <= tolerance²*||h||² AND no arithmetic fault
```

Model tính các GEMV ở S với round points rõ ràng, DOT rộng có kiểm prefix;
không gọi đây là certificate exact-real của B_q. Ngoài solver, study tính lại
normal bằng float64 để phát hiện trường hợp rounding làm runtime pass sai ngưỡng.
Tolerance1e-5 là candidate sau khảo sát, so với reference1e-4. Không đặt epsilon
tùy ý vào denominator hoặc tự nới tolerance theo seed.

Mọi saturation, divide-by-zero, breakdown chưa được certificate chấp nhận hoặc
hết budget đều là failed LS. Candidate thất bại chỉ dùng chẩn đoán; outer giữ
nguyên committed support/x/residual. Zero measurement có nghiệm zero rõ ràng.

Normal nhỏ không đủ bảo đảm hệ số đúng khi B gần phụ thuộc tuyến tính. Vì vậy
gate numerical ngoài solver còn kiểm coefficient error với SVD trên **cùng B_q,
y_q**, prediction/objective, input/operator error và chất lượng trong đơn vị gốc.
Ngưỡng coefficient relative1e-3 hiện là diagnostic; SNR loss≤0,5dB và
NMSE≤1,10× float giữ như đã thống nhất. Không đưa SVD/truth vào runtime solver.
User đã bổ sung floor ứng dụng: **SNR khôi phục≥20 dB cho cả float và fixed**,
tính trên tín hiệu gốc sau inverse transform và undo normalization. Gate này
đồng thời với relative quality/no-fault; không phải ngưỡng input SNR hoặc PSNR.
Centered SNR vẫn báo riêng, chưa có yêu cầu ngưỡng20 dB cho centered metric.

SVD được round về X để chẩn đoán storage floor. Khi không clipping, upper bound
`||B^T B||2 * sqrt(s) * LSB_X/2` chặn perturbation normal do rounding oracle;
bound này không chứng minh mọi nghiệm trên grid X đều bất khả thi. Tăng bit,
thêm vòng hoặc normal certificate một mình không đóng được rank/conditioning gate.

## 4. Bằng chứng và phần còn thiếu

[Application tuning mới](../../../reports/v4/LFSR_APPLICATION_TUNING.md) giữ
nguyên shortlist bit, đạt65/65 ca fixed được chọn và583/583 quan sát LS trên
support thực. Grid đầy đủ77 ca vẫn giữ12 ca ECG chưa được xác nhận do policy
chung chưa đạt ở float. Transform hiện chạy trên host trong encoder miền hệ
số; chưa dùng kết quả này để suy ra raw-signal Phi*Psi hoặc bit production.

[Study LFSR](../../../scripts/v4/lfsr_numeric_contract_study.py) tách normalization,
X precision, S fraction và tolerance; mọi failure được giữ. Seed23/47/101 dùng
calibration; seed211/509/997 dùng matrix validation. Đây không phải patient/scene
held-out. Các generic dense rank-stress case ghi riêng, không giả là Phi LFSR.

[Báo cáo hoàn tất](../../../reports/v4/LFSR_NUMERICAL_CONTRACT.md): shortlist
đạt 32/32 generated LS cases và 82/82 outer rows theo relative quality/no-fault
ở budget cố định. Generic near-collinear B vẫn fail coefficient diagnostic;
normal certificate không thay thế kiểm conditioning. Proximal reference vẫn
lưu D, chưa dùng X riêng.

Phải kiểm tiếp full programs với floor SNR20 dB đã chọn và dữ liệu held-out,
operator/transform/adjoint, memory lifetimes, contexts và RTL. Khóa bit sau
numerical qualification; synth/impl sau RTL correctness.
[Sơ đồ numerical](../diagrams/numeric_contract.mmd) diễn tả các biên format.
