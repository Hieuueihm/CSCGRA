# Giao diện CPU, AXI và registers

Payload transfers are supported through the separate DMA window and AXI4 master
interface. Program/context/Phi descriptors remain on the legacy PIO path; DMA
does not auto-start the core.

## RTL đã triển khai

Top IP là `csr_top` tại `rtl/v4/top/csr_top.sv`. Top có một cổng
AXI4-Lite slave 32-bit data, 12-bit byte address (4 KiB), clock
`s_axi_aclk`, reset active-low `s_axi_aresetn` và IRQ mức cao. Nó nối
`host_command_bridge` với đúng một `recovery_engine` hiện hành; không thay RTL
thuật toán, không thêm PE hay solver riêng.

[Register map](AXI_REGISTER_MAP.md) là hợp đồng offset/bitfield/reset/access.
Header RTL tương ứng là `rtl/v4/include/host_registers.vh`. Không dùng các
địa chỉ này như CPU physical addresses: PS/AXI interconnect cấp base address,
các giá trị dưới đây là offset từ base.

| Offset | Nhóm |
|---|---|
| 0x000–0x018 | Version, status, IRQ, ACK/W1C, command, error, event |
| 0x020–0x04c | START descriptor: M/N, scale, key/generation, job/tag, format, watchdog |
| 0x050–0x06c | Program/context image loader, counts, 128-bit item staging |
| 0x070–0x090 | Phi descriptor staging |
| 0x0a0–0x128 | Host vector request, mask/tag, 32 raw S27 lanes |
| 0x140–0x15c | Committed-result request and response mailbox |
| 0x160–0x1e8 | Vector response mailbox |
| 0x200–0x214 | DONE snapshot, fault/detail, iterations, coherent 64-bit cycles |
| 0x220–0x2bc | Committed metadata and support list |
| 0x2c0–0x2d8 | Image/Phi/command state |
| 0x300–0x33c | Payload DMA descriptor, control, sticky DONE/error/IRQ and counters |

## Cách CPU vận hành

CPU có thể nạp image và vector, tạo Phi, START, nhận DONE, đọc X và support
hoàn toàn qua MMIO; không cần testbench kéo native port để vận hành IP.
PIO payload được staging bằng nhiều write32 rồi một command doorbell; payload
lớn có thể dùng DMA theo `PAYLOAD_DMA.md`. Command
và response là hai giai đoạn: B=OKAY xác nhận wrapper nhận command, không phải
thuật toán đã xong. Poll mailbox/status hoặc dùng IRQ; đọc dữ liệu trước khi
ACK mailbox. CANCEL không tạo DONE và không được làm mất B/R AXI đã nhận.

AW/W được giữ độc lập; B/R giữ payload khi stall. Byte strobes có hiệu lực;
truy cập lệch hàng, offset không hỗ trợ hoặc thao tác bị khóa trả SLVERR.
Program `verified` là attestation từ host, không phải SHA256 phần cứng.
DONE/cycle count được chụp đồng bộ. Đọc COMMITTED nhiều word chỉ khi job đã
xong và chưa START job tiếp theo để không ghép metadata của hai job.

## Phạm vi và bằng chứng

Native core regression, AXI real-core smoke và IP packager là ba gate riêng.
Báo cáo source-bound tại `reports/v4/axi_ip_20260910/README.md` ghi rõ kết quả
cuối cùng; chỉ có file RTL hoặc component.xml không tự là correctness PASS.
DMA có gate riêng tại `reports/v4/payload_dma_20260911/README.md`: standalone
DMA, AXI DMA với generic program/core thật, regression PIO và IP integrity.
Đo toàn chương trình PIO/DMA đủ 10 thuật toán × 2 geometry × 8 vòng thực tại
`reports/v4/payload_benchmark_20260911/README.md`: 40 mô phỏng XSim PASS, tách
setup/load/compute/writeback/total và counter stall DMA. Gate synth thực tế
chưa qua lỗi part-select trong factor-panel; chưa có PPA/implementation PASS.
[Hướng dẫn IP packaging](IP_PACKAGING.md) mô tả command, output và kiểm integrity.

Đường control vẫn là programmed-I/O trên AXI-Lite; payload lớn dùng AXI4 master
DMA bounded theo `PAYLOAD_DMA.md`. Chưa có AXI-HP, driver Linux hay coherency
contract. Các bulk-AXI khác trong v4_design.json vẫn là proposal. Performance
counter trong wrapper là job_cycles từ native engine;
module performance_counters tổng quát vẫn planned/reference, không nằm trong
csr_top. RF32x64 của sequencer vẫn là state nội bộ, không ánh xạ thành CPU RF.

Không có claim synthesis, implementation, timing/Fmax, resource fit ZCU106,
board validation hoặc bitstream. Thuật toán và quality fixture giữ giới hạn
qualification đã ghi trước đó.
