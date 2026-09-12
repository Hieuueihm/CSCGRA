# Paper CSR, source v3 và mục tiêu v4 là ba đối tượng khác nhau

Ngày đọc: 2026-09-08. Paper local sáu trang có title **A Unified Architecture
for Multiple Compressive Sensing Recovery Algorithms**, dù filename còn là
CSR__A_Reconfigurable_Architecture...Copy_ (6).pdf. Nội dung đọc trực tiếp từ PDF;
text trích xuất phục vụ tra cứu nằm ở `work/v4/csr_paper.txt` (disposable).

| Vấn đề | Paper local | Source/docs v3 được đọc | Hướng v4 |
|---|---|---|---|
| Precision | Trang3 chọn 24-bit, 8.16; rationale định tính | D18F14/S27F19/A62 trong contract, nhiều candidate/report; không cùng math/profile với paper | Sweep D/C/S riêng trên operator và dữ liệu thực; chưa chốt bit |
| PE | Trang3 nói hai mảng4×4, ALU/RF/context/routing | Current mask32 full PE nhưng16 context broadcast vị trí; multiplier general ở sidecar | 32 tile contexts, general PE arithmetic và routing có schedule chứng minh |
| Matrix | LFSR signs, không lưu dense Phi | Runtime-scale/generator contracts đã đổi nhiều revision | Generator thay được, một sign cache; Threefry/LFSR đang so; dense hai orientation chỉ là reference |
| Solver | Trang4 Gaussian elimination/back substitution; thừa nhận nhạy fixed point | Matrix-free CGLS và certificates; khác solver paper | LSQR target có integer model; CGLS reference, shifted-CG riêng ADMM; chưa numerical qualification |
| Capacity | Trang5/6 skip CoSaMP/SP K16 | V3 phát triển working support96, nhưng report lịch sử không chứng nhận live source | Declare S96, fault khi quá capacity; không loại case rồi vẫn nói full support |
| Quality | Trang5/6 sparse synthetic, 100 common trials; output so golden24-bit | Có MRI/ECG/BrainWeb experiments, một số sparse oracle/source-domain proxies | Raw-signal y=Phi*s, A=Phi*Psi, application floors và quantization loss tách riêng |
| Performance | Có cycles/resources/Fmax/power trong draft | Nhiều run IDs/source revisions, dirty checkout | Chỉ so với source snapshot xác định; predicted model≠measured RTL≠post-route |
| Thuật toán | 8 MP/OMP/GOMP/CoSaMP/SP/IHT/HTP/GP | 8 mathematical references và nhiều corrective changes | Giữ8 + FISTA/ADMM/PDHG để kiểm tra ba hướng tối ưu khác; AMP conditional |

Điểm giữ từ paper: common kernels, hai mảng4×4, đổi program thay vì synth lại,
đánh giá quality cùng workloads. Điểm phải làm mạnh hơn: chứng cứ PE utilization,
operator thực cho từng ứng dụng, LS reliability, capacity, compare at matched
quality và novelty mechanism cụ thể.

Không lấy con số24-bit/power/Fmax trong paper làm kết quả v4, hoặc coi report
v3 ghi PASS là chứng nhận checkout hiện tại. Một README v3 còn ghi8 full +24
Phi-only PE đã lỗi thời so với generated mask hiện tại; audit phải đi tới source.
Chi tiết file/line nằm trong [V3_ARCHITECTURE_AUDIT.md](V3_ARCHITECTURE_AUDIT.md).

Paper TableII quy định GOMP dùng ceil(K/2) iterations; đây là budget thực nghiệm,
khác quy tắc general gOMP cho phép nhiều lần chọn L atoms. V4 lưu iteration/stop
policy trong từng case, không dùng budget như một định nghĩa lại thuật toán.
TableIII có IHT/GP trùng số; không suy ra công thức giống nhau từ bảng này.
Phải kiểm tra hai reference bằng oracle riêng và trace/decision thực.

File v3 trong project đang có nhiều chỉnh sửa chưa commit của người dùng. Việc
tạo v4 không reset, di chuyển, dọn hoặc chép các sửa đổi đó thành baseline mới.
