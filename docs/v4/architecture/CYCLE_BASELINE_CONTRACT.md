# Mốc cycle V2/V3 và cách chọn tối ưu

## Quy tắc so sánh cập nhật theo yêu cầu người dùng

Bảng so sánh hiệu năng giữa các thuật toán phải giữ cùng M, N, K và **cùng
số vòng ngoài thực chạy**, kiểm bằng counter RTL. Cùng `max_iterations`
không đủ: một chương trình dừng ở vòng 1 và chương trình khác chạy 8 vòng
không được đặt cạnh nhau để kết luận thuật toán nào nhanh hơn.

Chế độ benchmark cố định 8 vòng dùng ngưỡng residual bằng 0 và tắt dừng SP
khi residual không giảm; phải xác nhận mỗi ca thực sự chạy đúng 8 vòng.
Đây là cấu hình đo được khai báo riêng, không đổi mặc định thuật toán hoặc
ngưỡng chất lượng. Số lần giải QR thực, yêu cầu LS logic, vòng CG bên trong
và SNR/NMSE vẫn phải báo cáo vì công việc trong một vòng khác nhau.

Các ca dừng sớm hoặc cần nhiều vòng hơn để đạt SNR được giữ trong bảng kiểm
chất lượng riêng, không dùng xếp hạng cycle giữa các thuật toán. Số đo V2/V3
khác số vòng thực chỉ là mốc lịch sử; không tính speedup công bằng từ chúng.
Cùng số vòng là điều kiện cần, chưa thay thế việc đối chiếu dữ liệu, solver,
định dạng số và ranh giới đo chu kỳ.

Ngày 2026-09-09. Đây là tiêu chí performance hiện hành, bổ sung cho
[streaming redesign](STREAMING_REDESIGN.md). Correctness, SNR và QR vẫn giữ
nguyên yêu cầu. Chỉ dùng Vivado xsim cho số đo RTL.

## Mốc đã đọc lại

K là số phần tử khác 0 của tín hiệu hoặc tham số sparsity của thuật toán;
không phải độ dài phép tương quan. Mỗi lần tính Phiᵀr vẫn phải xét N cột.
Ca v4 M128/N1024/K2 có số phần tử ma trận gấp 32 lần ca V2 M32/N128/K2.
Không chia cycle cho K hoặc so hai tổng khác kích thước để kết luận tốc độ.

[Profile RTL v4 trước tối ưu](../../../reports/v4/legacy_cycle_baselines_20260909/CYCLE_TRANSPORT_PROFILE.md)
đo GEMV chiếm 92–96% tổng chu kỳ sáu thuật toán ở M128/N1024. Ở snapshot đó,
forward mất 24777 chu kỳ, transpose 29449, cùng 4096 frame. Đây là số đo
dịch vụ thật của baseline cũ, không phải cycle pipeline hiện hành.

| Thuật toán | V2 M32/N128/K2 | V2 M64/N256/K8 | V3 M32/N64/K8, mapped PE ngày 08-09 |
|---|---:|---:|---:|
| MP | 2947 | 25673 | 8927 |
| IHT | 3355 | 28569 | 8430 |
| GP | 3355 | 28569 | 8941 |
| OMP | 3661 | 33954 | 15562 |
| GOMP | 2493 | 19311 | 8762 |
| CoSaMP | 6909 | 105952 | 65676 |
| SP | 6142 | 94667 | 19945 |
| HTP | 4533 | 39421 | 27974 |

Các cột có kích thước hoặc điều kiện dừng khác nhau, dùng làm mốc từng bộ
test, chưa phải bảng speedup. V2 dùng K vòng ngoài, riêng GOMP ceil(K/2).
V3 có dừng sớm; phải đọc actual iterations trong từng log.
Trong cột V3 ở đây, SP chạy 3 vòng, GOMP 4 vòng, các thuật toán còn lại 8 vòng.
GP V2 trong bảng là full-gradient/IHT-like, khác GP restricted line search v4.
Theo yêu cầu mới nhất, [GP phải đúng Gradient Pursuit](GRADIENT_PURSUIT.md);
cycle GP mặc định V2 không được dùng làm ngưỡng chấp nhận GP v4.

[Bảng truy xuất và source snapshot](../../../reports/v4/legacy_cycle_baselines_20260909/README.md)
lưu cycle, geometry, budget, actual iterations nếu có, SHA256 và kiểm log
cho từng dòng. V2 hiện còn báo cáo signoff; raw logs không còn ở đường dẫn
ghi trong báo cáo. V3 forced-eight OMP có CSV PASS nhưng log FAIL nên bị loại.
Các dòng forced-eight còn khớp log được giữ riêng; không trộn revision này
với mapped-PE ngày 08-09. Bảng architecture_cycle_simulation là mô hình ước
lượng, không dùng thay số đo RTL.

## Kết quả hiện hành sau sparse forward và pipeline

[Bảng K=8 mới nhất](../../../reports/v4/K8_COMPARISON.md) bổ sung đủ tám
thuật toán V2/V3 và ba thuật toán còn lại, cùng cấu hình, vòng thực, quality,
program/template và breakdown dịch vụ. V3 trong bảng mới dùng trọn suite
`p1_selection_policy_regression_20260908` cho cả M64/N256 và M32/N64;
các bảng phía trên giữ vai trò lịch sử, không trộn cycle giữa revision.
23 lượt xsim v4 đều khớp model/VM. QR đã kiểm trên support thực tới24,
nhưng OMP/CoSaMP/HTP vẫn cao cycle; không kết luận kiến trúc đã cân bằng.

[Sáu ca cùng geometry/budget](../../../reports/v4/pipeline_whole_program_comparison_20260909/README.md)
đã chạy lại bằng xsim. Mỗi cặp trước/sau v4 dùng cùng input và trả cùng
X/residual/support/status. V2 có operator, seed, precision và ranh giới đếm
khác, nên vẫn là mốc kiến trúc, chưa phải phép đo speedup tương đương.

| Thuật toán | V2 K2 M32/N128 | v4 hiện hành, 2 vòng | V2 K8 M64/N256 | v4 hiện hành, 8 vòng |
|---|---:|---:|---:|---:|
| MP | 2947 | 3468 | 25673 | 24052 |
| IHT | 3355 | 3725 | 28569 | 31314 |
| GP đúng gradient | Không có raw gate tương đương | 3866 | Không có raw gate tương đương | 26739 |

MP ca K8 thấp hơn mốc V2, nhưng MP/IHT K2 và IHT K8 còn cao hơn.
Ba lịch mới bật `sparse_forward=True`; default compiler vẫn giữ full Phi.
Ở M128/N1024/K2, hai vòng, [gate riêng](../../../reports/v4/pipeline_max_program_comparison_20260909/README.md)
ghi MP 25614, GP 26985, IHT 28854, FISTA 40723 chu kỳ. FISTA giữ cùng image;
ba thuật toán đầu kết hợp compiler sparse và pipeline.
11 ca nhỏ cùng image đều giảm 5,01–11,84%, chưa có thuật toán chậm hơn trong
phạm vi đó. ADMM/PDHG toàn N và QR support lớn chưa được đo lại ở gate mới.

[Khảo sát budget/chất lượng](../../../reports/v4/CYCLE_QUALITY_BUDGET.md) tách
ngưỡng 20 dB khỏi benchmark cố định số vòng. IHT K2 ở hai vòng và MP/IHT K8
ở tám vòng chưa đạt 20 dB ngay cả float; không dùng các số cycle đó để tuyên bố
đã đạt chất lượng ứng dụng. Khảo sát budget là numerical, không gán cycle RTL.

## Bộ đo bắt buộc

1. M32/N128/K2, budget 2: đối chiếu mốc V2 K nhỏ.
2. M64/N256/K8, budget 8: đối chiếu mốc V2/V3; GOMP thêm budget 4 khi so V2.
3. M32/N64/K8: đối chiếu bản V3 mapped PE có log nhất quán mới hơn.
4. M128/N1024 với K2/8/16/32: kiểm khả năng mở rộng sau các ca trên.
   Chỉ chạy thuật toán/support hợp lệ, không ép S96 cho mọi solve.

Chạy baseline và candidate cùng raw Phi/Y, seed, độ rộng bit, program policy,
mapping và điều kiện dừng. Ghi digest input, truth K, policy K, số vòng thực,
chuỗi support, số solve/correction/inner iterations và kết quả. Không tự tăng
K trong tên ca trong khi dữ liệu vẫn chỉ có hai phần tử khác 0.

Mốc cycle cố định số vòng và mốc đạt chất lượng là hai phép đo riêng.
Ví dụ IHT chạy hai vòng có thể chưa đạt 20 dB: PASS bit-exact với model
không chứng minh chất lượng ứng dụng đạt yêu cầu. Ở phép đo chất lượng,
ghi cycle tới SNR >=20 dB, SNR loss <=0,5 dB và NMSE ratio <=1,10 so với
float64, với policy đã thống nhất; không giảm số vòng hoặc nới ngưỡng để
làm đẹp cycle. Các fixture tổng hợp này không thay held-out ứng dụng.

Ghi riêng setup/preload, accepted START tới DONE, thời gian program, result
drain và từng dịch vụ. Cycle v4 bao gồm BUILD_B/GATHER/SCATTER/commit;
không chỉ báo GEMV nhanh nhất. V2 đếm seq_busy, V3 đếm engine_busy sau khi
preload context/Y; không nhận đồng nhất các ranh giới này. Hiện v4 Phi cache
gắn job identity, chưa chứng minh warm reuse qua job ID mới.

## Thứ tự tối ưu lấy từ kiến trúc cũ

**1. Giảm công việc forward theo support thực.** V2 đã dùng active support
khi dựng residual. V4 MP/IHT cần dùng B*x_S sau khi lưu X24; GP dùng cùng
B cho hướng gradient và residual khi support chưa đổi. Tính cả BUILD và
GATHER; nhánh support rỗng trả projection bằng 0. QR OMP/GOMP/HTP/SP có
thể dùng residual certificate sau lưu X24; CoSaMP prune sau solve nên cần
tính lại residual. Không thay bước Phiᵀr toàn N bằng restricted correlation.
Candidate compiler hiện yêu cầu support tiềm năng <=min(M,96) để dùng
sparse forward: K cho IHT, số vòng tăng support cho MP/GP. Nếu vượt giới hạn,
báo lỗi lựa chọn candidate rõ ràng; baseline full-Phi vẫn khả dụng, không cắt support.

Đối với các forward này, X ngoài support bằng 0. C18*S27 và N<=1024 cho
tổng trị tuyệt đối <2^53, an toàn trong ACC64. B giữ nguyên từng hệ số Phi;
giữ một lần round cuối giống baseline thì bỏ các tích bằng 0 không đổi
kết quả. Vẫn cần xsim kiểm nguyên vẹn X/residual/support/status.

**2. Gối đầu cấp Phi/vector cho cả nhóm thuật toán.** V2 đã cache/prefetch
word residual và tách issued/retired. V4 cần operand block reuse, hàng đợi
frame hữu hạn, tách cấp lệnh với thu kết quả và khai thác hai read credits
của RAM. Hàng đợi phải xử lý stall, tail, cancel và epoch cũ đúng. Không
công bố II1 từ tốc độ PE nếu endpoint vẫn nhận một grant mỗi ba chu kỳ.

**3. Giảm fold và lượt đi qua RAM.** Đo chi phí reduction, STORE và vector
services sau hai bước trên. V3 từng bỏ route thừa khi producer/store ở
cùng PE và gộp norm tại writeback. V4 chỉ nhận fusion nếu giữ đúng điểm
rounding, certificate và dùng cùng 32 PE. V3 có sidecar vector và square
pipeline riêng; phải tính các tài nguyên đó khi so.

Mỗi thay đổi báo cả 11 thuật toán: giảm, không đổi, tăng, hoặc chưa đo.
Chưa đo không được ghi là không đổi. Không chọn bằng trung bình bị CoSaMP
chi phối. Candidate cần giữ exact correctness trước; mọi hồi quy cycle
phải được giải thích bằng số đo từng thuật toán. Mục tiêu là tiến tới hoặc
vượt mốc V2/V3 tương ứng, không chỉ nhanh hơn baseline v4 đang chậm.

Timing margin và LUT/FF/BRAM/DSP là các phép đo sau correctness. Giữ mục
tiêu ZCU106 100 MHz; chưa có synth/impl v4. Cycle giảm không tự chứng minh
Fmax tăng hay tài nguyên giảm.
