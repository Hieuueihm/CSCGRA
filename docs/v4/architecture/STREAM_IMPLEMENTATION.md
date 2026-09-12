# Lát streaming đã triển khai và bottleneck còn lại

Đọc cùng [contract](STREAM_RTL_CONTRACT.md), [sơ đồ](../diagrams/stream.mmd)
và [gate Vivado riêng](../../../reports/v4/STREAM_RTL_CORRECTNESS.md).
Đây là bước kiểm nền compute/memory/context trước khi ghép operator và thuật
toán. LSQR reference được giữ nguyên để đối chiếu.

## Phần đã làm được

Host nạp program và template, nạp các vector rồi START. `stream_engine` tự
thực hiện từng CALL, đọc RAM, phát frame qua đúng hai array 4×4, thu kết quả,
publish và tiến tới HALT. Có 32 context PE riêng; chương trình không cần host
chọn từng kernel hoặc phát từng frame trong lúc chạy.

PE có một multiplier 27×18 và accumulator signed64. Với nguồn cấp không
stall, C18 MAC nhận một frame mỗi chu kỳ; S27 MAC đầy đủ dùng hai pha nên nhận
một frame mỗi hai chu kỳ. Hai tốc độ này được kiểm ở fabric riêng. Không nhân
32 PE với clock mục tiêu để suy ra throughput của cả chương trình.

Pool vector dùng 16 bank ghép hai cổng, một read **hoặc** write 32 lane mỗi
clock. Capacity logic là 16384 S27; 15360 phần tử public và 1024 phần tử scratch.
Số RAMB36/DSP/LUT/FF thực tế chưa đo. Việc có 16 bank RTL không tự chứng minh
synthesis sẽ dùng đúng 16 RAMB36.

LAST_ACC và SUM_ACC duyệt 32 accumulator ở cuối CALL. LAST_ACC dùng một đường
làm tròn tuần tự, tránh bổ sung 32 bộ dịch rộng ngoài array. Mọi output vector
được giữ ở scratch tới khi CALL thành công, rồi copy và publish đồng bộ validity.

## Ví dụ đo cả đường dữ liệu

[Image ADD → DOT → HALT](../../../reports/v4/stream_program_example/README.md)
cộng hai vector 1024 phần tử, dùng kết quả cộng để tính dot product, rồi HALT.
Kết quả raw scalar là `108086391056891904`, Q44, tương ứng 6144.

| Counter trong ca không stall | Giá trị |
|---|---:|
| Accepted-job cycles | 598 |
| Frame vào / ra | 64 / 64 |
| Memory reads | 160 |
| Memory writes | 64 |
| Stall counter | 0 |

Cycle này loại thời gian host nạp image/input và thời gian host giữ done,
nhưng bao gồm kiểm source, dispatch, hai CALL, fold, scratch/copy và HALT.
598 không phải cycle sparse recovery hoặc LSQR; không so trực tiếp với ca
LSQR gần 900k clock trước đó. Clock 100 MHz là mục tiêu, chưa là timing đã đạt.

## Bottleneck hiện tại và bước xử lý

64 frame cần 128 lượt đọc hai toán hạng. ADD tạo 32 scratch writes, sau đó
32 scratch reads và 32 destination writes. Tổng 224 memory grants đã khớp
counter. Chỉ riêng số grant đã ngăn engine đạt tốc độ frame của fabric liên tục.

Engine đầu tiên có một cặp buffer A/B. Nó còn chờ phản hồi RAM và kiểm source
theo frame; `stall_cycles=0` chỉ nghĩa không bị chặn tại các handshake được đếm,
không nghĩa mọi clock đều làm phép tính. Các pha CHECK, FOLD, copy và chờ dữ
liệu vẫn tiêu tốn clock dù stall counter bằng zero.

Trước khi chọn cấu hình cuối, cần so buffer prefetch hai frame với bản này,
và so RAM compact với RAM ưu tiên bandwidth trên cùng các program. Kết quả
phải gồm cycle cả CALL, traffic, buffer/control và PPA thực tế. Tăng buffer
không tạo thêm cổng RAM; giảm số grant hoặc tái sử dụng operand vẫn cần mapping
R1/R4 và forwarding giữ đúng rounding.

Lát này chưa kiểm được tradeoff toàn 11 thuật toán. Các bước còn lại là nối
live Phi/B và shape-aware R1/R4, scalar/selection, loop/branch và các recovery
packages; chạy lại numerical/RTL end-to-end trước khi đánh giá synth/impl.
