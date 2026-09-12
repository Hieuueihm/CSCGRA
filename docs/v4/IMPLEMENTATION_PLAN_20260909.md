# Kế hoạch đóng đợt tối ưu và kiểm chất lượng

Yêu cầu hiện hành: Astra Ultra lập kế hoạch, điều phối và review; GPT-5.6
Terra reasoning high viết code. Giữ các phần đã qua kiểm, không làm lại từ đầu.
RTL chỉ kiểm bằng Vivado xvlog/xelab/xsim. Chưa chạy synth/impl.

## 1. Bằng chứng và giới hạn đầu vào

- Giữ nguyên mọi báo cáo cũ, cả ca SNR thấp và lần chạy lỗi bộ kiểm thử.
- Mỗi lượt chạy dùng snapshot cố định và SHA256 của RTL, header, compiler,
  mô hình, TB, dữ liệu và script. Không sửa snapshot đang chạy.
- Phần cứng vẫn đúng hai array 4x4, 32 PE; solver support là Householder QR.
- Không đổi bộ bit D18F14/C18F16/S27F22/X24F20/ACC64 hoặc nới ngưỡng chấp nhận.

## 2. Khóa cách so sánh trước khi đọc kết quả

Bảng hiệu năng chính: cùng M/N/K, cùng Phi/Y, cùng **8 vòng ngoài thực**.
TB và VM đều phải xác nhận counter bằng 8. Riêng chế độ benchmark tắt dừng
residual bằng ngưỡng 0 và tắt dừng SP khi residual không giảm. Mọi tham số
khác được ghi nguyên văn. GOMP có thể có support16 dù K tín hiệu bằng8;
SP có solve khởi tạo; ADMM có các vòng CG bên trong. Phải ghi những khác biệt
này, không gọi đây là cùng lượng công việc nội bộ.

Bảng kiểm chất lượng riêng: ghi chính sách hội tụ, số vòng thực và SNR,
không xếp hạng cycle giữa các thuật toán chạy số vòng khác nhau. V2/V3 khác
dữ liệu, solver hoặc số vòng chỉ giữ làm mốc tham khảo, không gán speedup công bằng.

## 3. Đóng thay đổi kiến trúc

Ba phần đã có snapshot ứng viên: cộng tổng theo các mức bằng ACC adder hiện
có của PE; lệnh scalar template dùng PE lane0 không qua RAM; lịch QR loại
copy dư và tái sử dụng nghiệm đã chứng nhận khi **toàn bộ ordered support**
trùng trong cùng job. Độ sâu cache được chọn riêng cho từng thuật toán.

Điều kiện đưa vào project:

- Soát module ownership, nguồn cộng/nhân, mask/tail và điểm làm tròn.
- Gate phần tử: giá trị biên, overflow, operand không hợp lệ, stall, cancel,
  reset; scalar không đọc/ghi pool hoặc thay scratch; cache không vượt START.
- Gate đủ11 chương trình trên M32/N64 và M64/N256: X, residual, support,
  status, counter khớp mô hình; trace PC khớp VM của đúng image mới.
- Báo cáo riêng số yêu cầu LS logic và số FACTOR_INIT/BUILD thực trên RTL.
- Review manifest rồi mới copy đúng danh sách file đã kiểm vào cây chính.

Không suy ra LUT/BRAM/DSP, Fmax hoặc timing margin từ số chu kỳ mô phỏng.

## 4. Đóng chính sách chất lượng

Giữ ngưỡng chung: float và fixed SNR >=20dB, mất SNR <=0.5dB, tỷ số
NMSE_fixed/NMSE_float <=1.10; không có numeric fault. Kiểm dữ liệu gốc và
seed chưa dùng để chọn tham số. Phân biệt rõ dữ liệu tổng hợp với dataset
ứng dụng; không tuyên bố đã hiệu chuẩn toàn bộ ứng dụng cho paper.

- HTP và nhóm QR: bước/ngưỡng dừng phải export được; dùng ngưỡng dyadic
  tương ứng mức lượng tử đầu vào, giữ chứng nhận nghiệm LS hiện tại.
- IHT: giữ đúng fixed-step IHT; cấu hình M128/N256 được ghi riêng với chi phí
  thêm phép đo. Không đổi tên NIHT thành IHT để che ca thất bại ở M32/M64.
- FISTA/PDHG/ADMM: chọn bước và regularization theo operator/chính sách
  được khai báo. Chọn budget trên training, kiểm held-out sau đó. KKT chỉ là
  diagnostic khi chưa có runtime stop; không giả vờ đã triển khai dừng sớm.
- ADMM64 chỉ được đưa vào cấu hình sau khi training và held-out đạt gate;
  ADMM32 đạt trên một ca không đủ thay thế chính sách chung.

Oracle Python có thể chạy nhanh hơn bằng int64 **chỉ** khi chứng minh giới
hạn tổng tuyệt đối, giữ nguyên clip/round/events và có fallback. Backend là
tùy chọn, không đổi mặc định. Kết quả đối chiếu backend cũ/mới phải có trước
khi dùng cho lượt xsim dài. Tối ưu thời gian chạy simulator không phải giảm
cycle phần cứng; tùy chọn debug/O3 cũng phải ghi trong identity elaboration.

## 5. Hoàn thiện để người dùng tiếp tục

Terra chuẩn bị code, test và manifest; Astra review rồi tích hợp theo thứ tự
compute -> ABI/controller/VM -> compiler/profile -> harness/CLI -> tài liệu.
Giữ một lệnh export rõ ràng chọn profile balanced; lưu loader checksum và
revision yêu cầu. Cập nhật STATUS, sơ đồ module và báo cáo chính từ số đo thật.
Chỉ lặp lại test khi file thay đổi hoặc có nghi vấn cụ thể. Báo cáo cuối phải
nói rõ thuật toán vẫn chậm hơn mốc V3 hoặc miền dữ liệu còn chưa đạt chất lượng.
