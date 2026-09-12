# Matrix memory: throughput, DMA và quyết định đang xét lại

Quyết định lưu hai bản dense A/Aᵀ được **mở lại trước RTL freeze**. Image ABI,
mapping.py và board_budget.json hiện có vẫn là reference hai orientation. Không
đổi tên chúng thành kết quả của layout mới. Ứng viên ưu tiên để kiểm chứng là
**một bản A, 32 bank chéo**, dùng chung cho cả hai phép nhân.

## 32 bank không có nghĩa là 32 bản sao hoặc đúng 32 BRAM

Bank là các phần dữ liệu khác nhau có thể đọc song song. Với M128/N1024/C18,
một ma trận có 288 KiB coefficient, chia 32 bank thì mỗi bank là 4096×18.
Mỗi bank cần hai BRAM36 ở geometry này; một orientation là 64 BRAM36, hai
orientation là 128 BRAM36. Số bank phục vụ bandwidth, số coefficient và việc
nhân đôi dữ liệu quyết định phần lớn capacity. Giảm bank không tự giảm một nửa
dung lượng matrix; thường làm bank sâu hơn và giảm số coefficient đọc/cycle.

[AMD UG573](https://docs.amd.com/r/en-US/ug573-ultrascale-memory-resources/Block-RAM-Summary)
mô tả các mode BRAM và hai cổng. Dùng true dual-port để đọc hai coefficient/bank
là một lựa chọn khác, nhưng phải chứng minh địa chỉ/collision, đường tới PE và
cách nạp khi idle; không suy ra giảm32bank xuống16bank sẽ tự giảm tổng BRAM.

## Throughput có hai phần cần phân biệt

Khi coefficient đã resident và truy cập không xung đột, 32 bank là cách giúp
32 PE có dữ liệu. Synchronous-read latency có thể pipeline; độ trễ đọc khác
với initiation interval. Throughput cuối còn phụ thuộc đường mux/địa chỉ,
feedback accumulator, scalar phases và clock sau route.

Khi matrix thay thường xuyên hoặc ít được tái sử dụng, thời gian preload có
thể chiếm phần lớn job. DMA giảm công việc CPU nhưng không xóa lượng byte phải
chuyển hoặc bộ nhớ đích. Với bus đề xuất128bit/100MHz:

| Đại lượng M128/N1024/C18 | Hai copy gửi qua DMA | Một copy |
|---|---:|---:|
| Matrix payload nếu pack sát18bit | 576 KiB | 288 KiB |
| Data beats128bit | 36.864 | 18.432 |
| Preload ở trần1,6GB/s, bỏ overhead | 368,64 µs | 184,32 µs |
| Preload ở giả định50% trần, bỏ chi phí khác | 737,28 µs | 368,64 µs |
| Nếu ABI dùng32bit/coefficient | 1024 KiB | 512 KiB |

Đây là tính toán payload, không phải DMA benchmark. ABI hiện chưa triển khai;
HEX trên disk không phải DMA frame. Nạp A một lần rồi tạo bản transpose trong
PL giảm DMA của reference hai-copy nhưng vẫn tốn capacity và thời gian repack.

Một dense GEMV có131072 MAC, lý tưởng cần4096 MAC-issue cycles với32PE, tức
40,96µs ở100MHz, chưa gồm clear/drain/reduction/narrow/stalls. Do đó không được
báo throughput warm chỉ dựa vào MAC khi job thực có matrix preload mới.

Nếu operator dùng lại cho J jobs thì phần preload trung bình là T_load/J.
Các vòng LS còn dùng lại B trong cùng một job. Phải báo cả cold operator,
warm operator và total job, với số reuse thật của từng ứng dụng. Xem
[24 kịch bản payload](../../../reports/v4/matrix_dma_scenarios.json), tái tạo bằng
[matrix_dma_study.py](../../../scripts/v4/matrix_dma_study.py).

Đọc coefficient trực tiếp từ một cổng DDR128bit/100MHz cũng có giới hạn:32PE
cần32×18=576bit/cycle cho một vector độc lập, cổng chỉ có128bit/cycle trước
overhead. Không có reuse hoặc compression, bound cấp coefficient chỉ22,2%
công suất32MAC/cycle. Tiling/ping-pong giấu được một phần latency, không phá
giới hạn bandwidth; batch nhiều vector cùng A có thể reuse coefficient nhưng
tăng state và latency từng job. Cần một mapping/buffer contract khác.

## Một bản A đọc được cả hai hướng

Đề xuất layout:

```text
Q       = ceil(N/32)
bank    = (row + column) mod 32
address = row*Q + floor(column/32)
```

32 phần tử liên tiếp trong một cột nằm ở32bank khác nhau;32 phần tử liên tiếp
trong một hàng cũng vậy. Vì thế đổi hướng nhân có thể đổi địa chỉ/hoán vị
coefficient, không cần lưu thêm ma trận transpose.

R1 giữ32 output độc lập. R4 giữ8 output×4PE nhưng chia reduction thành các
nhóm32 phần tử; mỗi PE nhận một đoạn8 phần tử trong nhóm. Tại một issue,
`k=32*t+8*lane+u` với lane0..3,u0..7 tạo32bank khác nhau khi ghép8 output.
M128/N1024 và M128/S96 không bị padding thêm ở chiều reduction chia32;
support nhỏ hoặc tails khác cần cost riêng. R1 vẫn là ứng viên cho forward
restricted có reduction ngắn. Không tuyên bố schedule này tối ưu mọi shape.

Đánh đổi phải tính thật:

- Feeder cũ chỉ xoay các nhóm8 lane; layout mới cần rotation theo từng lane,
  có thể dùng barrel permutation32word và static lane transpose.
- Phép Ax cần nhiều địa chỉ bank khác nhau. Công thức affine đơn giản nhưng
  fanout/mux/pipeline vẫn tốn tài nguyên và có thể đổi latency.
- R4 đổi thứ tự cộng. Phải kiểm mọi partial/prefix/reduction tree, không chỉ
  tổng cuối. Bounds full-range hiện có có thể bảo vệ mọi thứ tự khi được áp dụng
  đúng; không tăng width hoặc gọi bit-exact theo cảm tính.

Xem [review địa chỉ và số học](SINGLE_MATRIX_REVIEW.md) và
[prototype](../../../compiler/v4/single_matrix.py). Prototype chỉ kiểm
bank-access và integer replay; chưa là compiler context hay pipeline RTL.

## Ảnh hưởng tới LS cache và tài nguyên

Support không liên tiếp nên không áp trực tiếp lịch dense lên arbitrary atom
IDs: nhiều IDs có thể trùng bank residue. Giữ bước gom support thành B có các
slot liên tiếp là cách để CGLS hoặc LSQR chạy GEMV đều đặn.

Một cache B theo layout chéo có thể phục vụ cả B/Bᵀ. Với mỗi support slot s
trỏ đến atom j[s], chép32row: sourcebank=(row+j)%32, destbank=(row+s)%32. Đây là
hoán vị không xung đột, một pass có `S*ceil(M/32)` payload issues; M128/S8 là32,
so với288 của two-pass reference. Mới là proof của payload access; chưa có
gather pipeline, startup/drain, cache-generation/commit replay hay RTL.

| Phương án ba nhóm RAM | Matrix chính | Support cache dự trù | Context | Tổng BRAM36 |
|---|---:|---:|---:|---:|
| Reference hai copy | 128 | 64 | 36 | 228 |
| Chỉ đổi matrix chính sang một copy | 64 | 64 | 36 | 164 |
| Một copy cả matrix và support cache | 64 | 32 | 36 | 132 |

Hai hàng cuối là candidate budgets trên ZCU106, chưa gồm vector LUTRAM,
selection/norm/FIFO/loader và logic routing mới. Hàng132 còn phụ thuộc việc
hiện thực/kiểm chứng cache một copy. Không ghi đè report228 của reference.

## Sinh coefficient hoặc dùng operator có cấu trúc

Nếu **chính A** chỉ nhận ±c, có thể lưu sign1bit/coefficient (128×1024 bit =
16KiB useful payload) và scale, hoặc nghiên cứu generator seed/index. Layout
và BRAM granularity vẫn phải tính; generator phải tạo cùng coefficient cho
Ax, Aᵀr và arbitrary support, không chỉ stream được một thứ tự thuận.
[Counter-based RNG](https://www.thesalmons.org/john/random123/papers/random123sc11.pdf)
là hướng tham khảo cho truy cập theo chỉ số, chưa là backend đã implement hay
được qualification về CS/statistics/quality.

Nếu chỉ Phi là ±1 nhưng A=Phi*Psi tổng quát, một sign không biểu diễn được
coefficient A. Cần thực hiện riêng Psi và Phi cùng các adjoint, hoặc lưu A.
Không thay operator để làm phần cứng nhỏ rồi dùng số quality của operator cũ.
Operator partial Fourier/transform có thể dùng tính cấu trúc thay dense matrix,
nhưng cần kernel, complex arithmetic/normalization và application protocol riêng.
[Candes–Romberg](https://authors.library.caltech.edu/records/ve4nf-w2r12)
phân tích vai trò sparsity/incoherence; không coi mọi operator thay thế là tương
đương cho mọi ứng dụng.

## Quyết định tiếp theo

Ưu tiên [generated operator và compact sign cache](GENERATED_OPERATOR.md) ở các
ứng dụng cho phép ma trận đo tự sinh, có kiểm chứng Phi/Psi và quality riêng.
Đối với dense A tổng quát, tiếp tục kiểm chứng một-copy vì giữ nguyên operator
và giảm capacity/DMA; reference hai-copy giữ làm đối chứng. Chỉ chọn phần cứng
sau khi feeder/context/gather chạy đúng, có cost toàn job và đạt timing.
Solver được chọn cùng memory/mapping theo [LS decision](LS_SOLVER_DECISION.md):
tổng cycles nhỏ nhất trong các phương án đạt accuracy, không chỉ số PE active.
