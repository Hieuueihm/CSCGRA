# Profile ứng dụng đang khảo sát: ECG db4 và ảnh Haar

Hai profile này là **ứng viên numerical theo miền hệ số biến đổi**. Chúng giữ
nguyên tín hiệu gốc và dùng LFSR đã chọn, nhưng thay DCT bằng basis phù hợp hơn.
Tài liệu này mô tả hợp đồng đầu vào/đầu ra và các profile calibration.
[Báo cáo fixed mới](../../../reports/v4/LFSR_APPLICATION_TUNING.md) xác nhận
32/32 ca wavelet đã chọn đạt; chưa xác nhận dữ liệu held-out, bit production
hoặc chi phí phần cứng.

## 1. Profile cụ thể và phạm vi

| Thành phần | ECG | Ảnh |
|---|---|---|
| Dữ liệu calibration | Hai cửa sổ 256 mẫu bắt đầu tại 3600 và 7200, cùng excerpt record 208 từ `scipy.datasets.electrocardiogram` | Hai patch 16×16 tại hàng/cột 192/240 và 64/64 từ `skimage.data.camera` |
| Basis được chọn cho cả domain | Wavelet db4 một chiều, level 5 | Haar hai chiều, level 4 |
| Biên và cách lưu hệ số | `periodization`; `pywt.coeffs_to_array`, thứ tự C | `periodization`; `pywt.coeffs_to_array`, thứ tự C |
| Kích thước đang chạy | M=128, N=256 | M=128, N=256 |
| Tín hiệu trước sensing | Đầy đủ 256 mẫu sau trừ mean và nhân scale | Đầy đủ 256 pixel sau trừ mean và nhân scale |
| Miền của ma trận LFSR | Hệ số db4 | Hệ số Haar |

Đổi basis là thay đổi được khai báo của profile encoder. Không đổi cửa sổ,
seed, số measurement hoặc giảm tín hiệu thành K hệ số trước khi tạo measurement.
Các phép biến đổi đều được kiểm orthogonality và khôi phục đúng tín hiệu gốc
trong sai số float. Transform contract, hash đầu vào và phiên bản thư viện nằm
trong báo cáo.

M=128/N=256 nằm trong giới hạn dự kiến M≤128/N≤1024 của v4. Grid dùng K cấu hình
16/24/32, LS support và danh sách support có chỉ mục không được vượt 96. MP/GP
trong model hiện tại không ép số phần tử nghiệm bằng K cấu hình; vì vậy study
kiểm support thực tế thay vì chỉ đọc tham số K. FISTA/ADMM/PDHG dùng vector dense
dài N, không diễn giải mọi hệ số khác zero thành một slot của danh sách 96 phần tử.

## 2. Có hai lớp chuẩn hóa, với hai mục đích khác nhau

Gọi s là vector tín hiệu gốc, T là phép phân tích orthonormal và Ψ=Tᵀ là phép
tổng hợp ngược. Với ảnh, các phép biến đổi hai chiều vẫn được ghi theo vector
256 phần tử trong công thức dưới đây.

**Lớp ứng dụng** giữ đúng tiền xử lý đã dùng trong các cửa sổ calibration:

```text
mu = mean(s)
c  = 0.5 / max(max(abs(s - mu)), 1e-12)
u  = c * (s - mu)
x  = T * u                         # toàn bộ N hệ số, không cắt best-K
y  = R * x + n                     # R là ma trận dấu LFSR M×N
```

R có coefficient `±1/sqrt(M)` trước lượng tử hóa. Encoder và recovery phải
thống nhất seed, taps, revision, M/N, thứ tự `column*M+row` và scale. Chỉ nạp
seed là đủ mô tả phần ma trận dấu; không đủ mô tả toàn bộ profile ứng dụng.

Mean mu và scale c là side information của ứng dụng. Model hiện tại tính và
lưu chúng trên host bằng float. Chúng phải đến được bên decoder; không tự coi
chi phí tính, truyền, lưu hoặc lượng tử hóa metadata này bằng zero. Khối tín
hiệu hằng cũng cần một chính sách cụ thể trước khi triển khai ứng dụng; các
cửa sổ đang khảo sát không chứng nhận trường hợp đó.

**Lớp job numerical** chỉ đưa measurement vào khoảng biểu diễn phù hợp, theo
[NUMERIC_CONTRACT.md](NUMERIC_CONTRACT.md):

```text
g = 2^e, chọn từ max(abs(y)) trước lượng tử hóa D
y_normalized = g * y
                    ┌─────────────────────────────────────────┐
y_normalized -> D -> │ recovery với cùng R; tính nghiệm g*x_hat │ -> raw output
                    └─────────────────────────────────────────┘
```

Với y khác zero, chọn e để `0.25 < max(abs(g*y)) <= 0.5`; y=0 dùng e=0.
Không lấy x thật hoặc tín hiệu s để chọn e. Sau khi chọn e, giữ một miền
normalized cho toàn bộ vòng lặp, residual và các lần LS của job.

Lớp job không thay mean, basis, R hoặc seed. Với LASSO, lambda cũng nhân g;
absolute residual tolerance nhân g, còn relative LS tolerance giữ nguyên.
Chi tiết round points, X storage và giới hạn exponent theo numerical contract.
Proximal model hiện vẫn lưu D; không suy rằng các chương trình đó đã dùng X.

Đường trả kết quả trên host theo thứ tự ngược:

```text
x_hat = 2^-e * decode(raw_output, actual_output_format)
u_hat = Psi * x_hat
s_hat = u_hat / c + mu
```

Metadata cần đủ để giải mã gồm profile/basis, shape, biên wavelet, level, cách
pack hệ số, mu, c, e, actual output format và operator descriptor. Đây là danh
sách semantic cần giữ, chưa phải layout AXI descriptor hoặc context đã pack.

## 3. Measurement được ghép cặp khi so basis như thế nào?

Study basis giữ nguồn, M/N, LFSR seed và **cùng hướng nhiễu ngẫu nhiên** cho từng
cửa sổ. Biên độ nhiễu được đặt lại theo norm của measurement sạch của basis đó
để input measurement SNR luôn là 30 dB. Vì đổi basis làm x và `R*x` thay đổi,
không gọi vector y giữa DCT và wavelet là giống nhau.

Điều không thay đổi là cách ghép cặp nguồn/seed/hướng nhiễu và chính sách noise
30 dB, không phải giá trị measurement. Riêng nhánh DCT được kiểm tái tạo lại
measurement của study cũ trong sai số float. Hash R, y, x đầy đủ, s và hướng
nhiễu được giữ để tái lập mỗi ca.

Best-K trong [báo cáo basis](../../../reports/v4/lfsr_basis_feasibility.json)
chỉ trả lời: nếu biết hệ số thật và giữ K hệ số lớn nhất thì riêng sai số xấp xỉ
đã là bao nhiêu. Nó không cấp support cho thuật toán, không được dùng tạo y,
không thay phép đo và không phải chất lượng recovery đạt được.

## 4. Đọc SNR đúng miền

Ngưỡng người dùng đã chọn là **SNR khôi phục trên tín hiệu gốc ≥20 dB cho cả
float và fixed**. Đồng thời fixed mất không quá 0,5 dB so với float, NMSE không
quá 1,10× float và không có lỗi số học. Input measurement SNR=30 dB ở study là
điều kiện thí nghiệm khác với output reconstruction SNR≥20 dB.

```text
full SNR     = 10*log10( ||s||²      / ||s - s_hat||² )
centered SNR = 10*log10( ||s-mu||²   / ||s - s_hat||² )
```

Vì mean được truyền riêng và cộng lại ở decoder, năng lượng DC đóng góp vào
tử số full SNR. Một ảnh có mean lớn nhưng texture yếu có thể đạt full SNR cao
trong khi phần texture được khôi phục kém hơn. Centered SNR dùng cùng sai số
ở mẫu/pixel gốc để cho thấy chất lượng phần biến thiên; không tự trừ lại mean
của nghiệm nhằm làm giảm sai số.

Cả hai metric đều được báo. Hiện tại ngưỡng 20 dB áp dụng cho full SNR; chưa có
ngưỡng 20 dB cho centered SNR. Cần diễn tả rõ điều này khi viết paper, cùng chi
phí side information, thay vì dùng full SNR để tuyên bố phần texture hoặc hình
dạng ECG đều đã đạt chất lượng tương đương.

## 5. Bằng chứng float hiện có

[Khảo sát basis, 48 ca](../../../reports/v4/lfsr_basis_feasibility.json) so sánh
DCT/Haar/db4/sym4 trên hai ECG và patch texture, với OMP32, SP32 và hai lambda
FISTA. Ví dụ SP32/db4 đạt full SNR khoảng 24,44/23,55 dB trên hai ECG. Với patch
texture, FISTA/Haar lambda 0,001, budget 256 đạt khoảng 28,60 dB. Đây là các ca
minh họa trong grid, không phải lựa chọn policy cuối của study kế tiếp.

[Grid wavelet, 360 ca](../../../reports/v4/lfsr_wavelet_float_tuning.json) giữ
db4 cho cả domain ECG và Haar cho cả domain camera, rồi khảo sát đủ 11 thuật
toán. Mỗi domain/thuật toán dùng một policy chung cho cả hai cửa sổ. Quy tắc
chọn ưu tiên policy có SNR thấp nhất giữa hai cửa sổ ≥20,5 dB và budget nhỏ,
sau đó mới xét nhóm ≥20 dB; capacity phải đạt.

Kết quả float có 16/22 cặp domain/thuật toán đạt margin 20,5 dB: cả 11 thuật
toán trên camera, và GOMP/CoSaMP/SP/FISTA/ADMM trên ECG. Các ca chưa đạt và các
ca vượt capacity vẫn nằm trong JSON. Hoàn thành budget không được gọi là chứng
minh hội tụ. Hai domain này cũng chưa đáp ứng mục tiêu mỗi thuật toán có một
ứng dụng khác nhau cho paper.

Basis và policy đều đã được chọn từ calibration. Hai ECG thuộc cùng excerpt,
hai patch thuộc cùng một ảnh; đây chưa là patient-held-out hoặc scene-held-out.
Sau bước chọn float, đã kiểm fixed trên32 ca của16 policy được chọn: cả32 ca
đạt SNR≥20 dB cùng relative quality/no-fault/LS/capacity, ghi trong báo cáo mới.
Sáu policy ECG còn lại chưa đủ điều kiện chung cho cả hai cửa sổ và không được
chuyển sang fixed. Kết quả chưa đủ để khóa bit hoặc tuyên bố v4 đã chạy trên ZCU106.

## 6. Ranh giới với sensing trực tiếp tín hiệu vật lý

Thí nghiệm hiện tại đo `y=R*x+n` sau khi host đã có toàn bộ tín hiệu và biến đổi
thành x. Recovery chỉ thấy ma trận R dấu. Nó có thể dùng generated operator
trực tiếp mà không chạy wavelet trong mỗi GEMV.

Nếu hệ thống thực tế đo tín hiệu thời gian/ảnh bằng `y_physical=Phi*s+n`, cùng
định nghĩa x và side information ở trên cho:

```text
s   = Psi*x/c + mu*ones(N)
y_u = c * (y_physical - Phi*(mu*ones(N)))
    = Phi*Psi*x + c*n
```

Operator của recovery lúc đó là `A=Phi*Psi`. Không thể thay A bằng R dấu rồi
tuyên bố đang khôi phục cùng phép đo vật lý. Mean/scale cũng phải có tại nơi
cần dùng và được xử lý nhất quán như công thức; không chỉ trừ mean trong một
vector mà bỏ qua ảnh hưởng lên measurement.

Với profile physical-signal đó, đường dự kiến là:

```text
A*x   = Phi * (Psi*x)
A^T*r = Psi^T * (Phi^T*r)
```

Baseline hướng tới chạy các phép này trên cùng hai array 4×4. Tuy nhiên, kernel
transform/adjoint, bộ lọc wavelet fixed, điều kiện biên, pack/unpack hệ số, buffer
trung gian, xây B theo support, lifetime bộ nhớ và context execution **chưa
được triển khai hoặc chứng nhận bởi các study ở đây**. Chi phí host transform
của coefficient-domain profile cũng chưa được tính vào latency/energy end-to-end.

Haar có cấu trúc cộng/trừ đơn giản hơn db4 về mặt toán học, nhưng chưa có số
LUT/DSP/BRAM hoặc timing v4 để kết luận hiệu quả trên ZCU106. Chỉ sau khi xác
định boundary của encoder thật và kiểm đúng staged operator, ta mới tính tổng
chi phí, ánh xạ context lên 32 PE và chuyển sang RTL correctness, synth, impl.

Xem thêm [BASELINE.md](BASELINE.md), [GENERATED_OPERATOR.md](GENERATED_OPERATOR.md)
và [NUMERIC_CONTRACT.md](NUMERIC_CONTRACT.md). Các script tái lập là
[basis builder](../../../scripts/v4/lfsr_basis_feasibility.py) và
[wavelet grid](../../../scripts/v4/lfsr_wavelet_tuning.py).
