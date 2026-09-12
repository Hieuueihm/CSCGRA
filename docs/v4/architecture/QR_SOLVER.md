# QR là solver LS của kiến trúc mới

## Feature4 QR append qualification

Profile `reuse` adds generic FACTOR_EXTEND(op19) under the existing program
revision2. OMP/GOMP prove an exact ordered support prefix and immutable Phi/Y;
BUILD_B advances the B generation, and EXTEND imports only new columns at the
next generation. Shrink/reorder/mismatch uses INIT. Corrections still apply
all reflectors and the stored-X certificate is unchanged. The generic backend
checks shape/identity; it does not infer support membership from dimensions.

[QR reuse contract](QR_REUSE.md) records the inert loaded template, generation,
mask and publication rules. [The paired XSim report](../../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md)
qualifies all20 fixed8 cases. Later resident/panel-chain/scalar-patch work is
separate; CPU AXI and board timing remain unimplemented/unqualified.

Theo yêu cầu làm rõ hiện hành, **solver đích là QR**. LSQR đã có trong source
được giữ làm đối chứng; program recovery mới không tự chuyển sang LSQR khi QR
khó hội tụ hoặc gặp ma trận xấu. Bit và chất lượng phải được kiểm lại cho QR.

**Numerical calibration đã PASS:** 583/583 support observations và 31/31 ca
outer recovery của OMP/GOMP/CoSaMP/SP/HTP. SNR fixed thấp nhất 21,622 dB,
SNR loss lớn nhất 0,040134 dB, NMSE ratio lớn nhất 1,009284. Không cần
refinement hoặc LSQR fallback. [Report và phạm vi](../../../reports/v4/QR_NUMERICAL.md)
ghi rõ cache numerical, trajectory thay đổi và dữ liệu chưa held-out.
Householder đã được hạ thành subroutine nạp được trong `program_sequencer`,
dùng `stream_kernel`, factor store và cùng 32 PE của recovery. Gate Vivado xsim
trên source đóng băng đã PASS cả năm program OMP/GOMP/CoSaMP/SP/HTP với
M16/N32/K2, budget ba và giới hạn refinement hai. X/residual/support/status,
trace PC/word và số service call giữ nguyên qua thay đổi pipeline.
[Gate full-program nhỏ](../../../reports/v4/pipeline_whole_program_comparison_20260909/README.md)
bao gồm cả 11 thuật toán; đây là qualification các fixture đã lưu, chưa phải
quality ứng dụng held-out hoặc khóa bit production.

[Bộ K8 tiếp theo](../../../reports/v4/K8_COMPARISON.md) đã kiểm cả năm
program QR ở M32/N64 và M64/N256, budget tám; thêm GOMP budget bốn ở
M64/N256. Support LS thực lớn nhất24, mọi ca QR dùng zero correction trong
giới hạn hai. Kết quả xsim khớp model/VM nhưng cycle còn cao: riêng CoSaMP
M64/N256 mất900360. Đây là bằng chứng cần tối ưu kernel vector/range/factor,
chưa phải chấp nhận performance hoặc qualification toàn bộ S96.

## Triển khai hiện hành

Program Householder với mỗi cột tạo
một phép phản xạ, cập nhật các cột còn lại và vế phải; sau đó giải hệ tam giác
trên R. Không lưu toàn bộ Q. LAPACK mô tả cách chứa R ở phần tam giác trên,
các vector phản xạ phía dưới đường chéo và hệ số tau riêng.
[DGEQRF](https://www.netlib.org/lapack/explore-html/d0/da1/group__geqrf_gade26961283814bb4e62183d9133d8bf5.html).

Householder được ưu tiên vì dot/norm và cập nhật vector dùng chung core 32 PE.
Givens thông thường ở M128/S96 cần 7632 phép quay khử phần tử; chi phí
tính hệ số quay bằng scalar service phải tính đầy đủ nếu đem so. Đây là suy
luận thiết kế, chưa phải kết quả Householder nhanh hơn trên FPGA.

Phản xạ dùng dạng v có phần tử đầu bằng1, beta trái dấu với phần tử đầu cột,
và tau=(beta-alpha)/beta. Cách chọn dấu này theo routine tạo reflector chuẩn.
[DLARFG](https://www.netlib.org/lapack/explore-html/d8/d0d/group__larfg_gadc154fac2a92ae4c7405169a9d1f5ae9.html).

Đường fixed point hiện hành dùng norm từ raw ENERGY, DIV có kiểm range và
NORMALIZE dùng reciprocal đã scale theo lũy thừa hai. Nhờ mẫu số chung, một
DIV phục vụ cả vector phản xạ, thay vì chia scalar từng phần tử. Mọi điểm làm
tròn được định nghĩa trong oracle QR và kiểm với program đã hạ; phép này
không mặc nhiên bit-exact với một chuỗi chia từng phần tử hoặc với LAPACK float.

## Bộ nhớ và sử dụng PE

Giữ B gốc C18 để tính residual/certificate. QR cần bản factor S27 có thể sửa;
không ghi đè B hoặc ép các cột đã biến đổi trở lại C18.

M128/S96 cần12288 phần tử S27 cho factor. Không lấy vùng này từ pool vector
đang giữ các vector toàn N của recovery. `factor_store` riêng đã triển khai với
16 bank TDP ghép cặp; phần nhân vẫn dùng đúng hai array4x4 hiện có.
`factor_service` thực hiện INIT từ B, READ/WRITE range hàng hoặc cột theo bundle
tối đa 32 phần tử, qua cùng pool và cơ chế publication của kernel. Program QR
điều khiển các primitive này; không có FSM thuật toán QR riêng.

```text
logical_bank    = (row + column) mod32
logical_address = row*3 + floor(column/32)
physical_bank   = logical_bank mod16
physical_port   = floor(logical_bank/16)
physical_word   = 512*physical_port + logical_address
```

Stride3 cố định theo capacity96 để bố trí factor không đổi khi support tăng
qua32 hoặc64. Layout đọc được hàng R và cột reflector; chỉ bố trí theo cột sẽ
làm bước thế ngược phải đọc lần lượt từng phần tử hàng. Đây là layout RTL đã
kiểm bằng xsim; số RAMB36 thực tế và timing sau synthesis/implementation chưa
được chứng nhận. [Hợp đồng factor](FACTOR_SERVICE.md) mô tả ownership, identity,
cancel và publication của các range.

O(S) tau, RHS đã biến đổi và metadata của ordered support cũng phải được tính.
**Reuse prefix giữa các support vẫn là đề xuất, chưa triển khai.** Với support
được nối thêm đúng prefix cũ, có thể giữ reflector/RHS của prefix
và xử lý các cột mới. Cần chứng minh key, M, scale, RHS và prefix đều trùng;
CoSaMP/SP/HTP đổi support không được reuse factor chỉ vì cùng số cột. Rebuild
là baseline hiện hành. Giữ factor để giải correction trong cùng một lần QR
là chức năng khác và đã có trong subroutine, giới hạn tối đa hai correction.

## Bằng chứng và phần còn lại

1. Oracle fixed point Householder, Q^T y và backsolve với rounding/range rõ.
2. Kiểm residual của factorization, orthogonality, rank/diagonal nhỏ, sai số
   hệ số so với SVD và certificate trên nghiệm đã lưu X24.
3. Nếu cần refinement, dùng lại chính factor QR để giải correction; có giới
   hạn và certificate thật. Không thêm LSQR làm fallback ngầm.
4. Replay support thực, rồi chạy lại greedy recovery/quality ứng dụng. 583
   support từ study LSQR là đầu vào kiểm tham khảo, chưa chứng minh phân bố
   support của recovery dùng QR sẽ giống nhau.
5. Lịch primitive/context đã nạp và chạy trên RTL thật bằng Vivado xsim trong
   gate năm program QR nhỏ nêu trên. M128/S96 có bằng chứng numerical/helper
   và kiểm leaf factor ở capacity tối đa; chưa có qualification full-program
   QR RTL tại S96. Không suy rộng từ kiểm bộ nhớ hoặc interpreter sang gate đó.

Pipeline đã tích hợp feeder bốn frame, cache hai vector block, endpoint hai
read credit và Phi cache consume/refill. Gate nhỏ giữ nguyên image và kết quả;
không đổi lịch Householder để tạo số cycle tốt hơn. Gate M128/N1024 riêng mới
bao gồm MP/GP/IHT/FISTA, không phải QR S96:
[phạm vi và số đo](../../../reports/v4/pipeline_max_program_comparison_20260909/README.md).
Cycle là START-to-DONE, chưa gồm cold Phi/program/Y preload. Chất lượng held-out,
bit production, synthesis/implementation, Fmax và PPA vẫn chờ gate tương ứng.

ADMM tiếp tục dùng shifted-CG cho hệ A^T A+rho I trong proximal model hiện có.
Điều đó không phải chọn LSQR làm solver LS: đây là hai bài toán khác nhau.
Các thuật toán không gọi support LS tiếp tục dùng chung operator/vector core.
