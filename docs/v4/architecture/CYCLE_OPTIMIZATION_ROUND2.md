# Đợt tối ưu cycle tiếp theo — 09-09-2026

Scope active round-two là tám greedy/hard-threshold cùng FISTA và PDHG. ADMM là reference lịch sử; round-two ADMM quality đã `STOPPED_BY_SCOPE`, không phải PASS. Astra lập kế hoạch và review; Terra high viết code.
Các thử nghiệm RTL chỉ dùng Vivado xvlog/xelab/xsim.

## Mốc và nguyên nhân đã đo

M64/N256/K8, cùng Phi/Y và đúng 8 vòng ngoài thực:

| Thuật toán | Cycle trước đợt này | SLICE + REPLACE_RANGE | FACTOR_READ + WRITE |
|---|---:|---:|---:|
| OMP | 85,546 | 26,924 | 6,516 |
| GOMP | 188,558 | 54,068 | 21,600 |
| CoSaMP | 498,045 | 101,814 | 74,288 |
| SP | 157,332 | 36,068 | 16,416 |
| ADMM (historical reference) | 415,499 | 0 | 0 |

Nguồn: `reports/v4/fair_fixed8_m64_complete_20260909/summary.json`.
Đây là tổng thời gian dịch vụ đã đo, không phải lượng cycle chắc chắn bỏ được.
ADMM dùng GEMV 281,636 cycle và TEMPLATE 114,148 cycle. Gate chất lượng
ADMM64 cũ là mốc calibration reference: 4,520,495 cycle, 64 vòng ngoài, 956 vòng CG tổng cộng; không phải PASS quality round-two.

## Thiết kế được chọn để triển khai từng phần

1. **Analytic three-provider range transport:** SLICE/REPLACE_RANGE derives
   the first/last source blocks and exact required masks for one output block,
   then compacts at most three physical providers in first-used order. Equal
   source/aux addresses union masks. The service keeps exactly one outstanding
   pool read; after validated responses, common unsigned word-offset alignment
   and a masked merge write one scratch block. Public length remains <=1024,
   ABI/rounding/publication do not change. This is the QR-facing candidate.
2. **TEMPLATE unused/aliased operand scheduling:** a request is suppressed only
   for an operand marked unused by its captured loaded context. Exactly aliased
   consumed operands may reuse one validated response. Context bits, masks,
   tails, faults, hold and cancel behavior remain unchanged; no PE changes.
3. **Command-local raw Phi tile reuse:** two entries retain raw 32-row × 8-column
   sign tiles only for favorable R1-forward and R4-transpose live-Phi modes.
   A validated same-tile hit can be accepted at most once per clock. The eight
   underlying sign banks, LFSR order, cold miss and identity checks remain.
   Dense and unfavorable Phi modes use the old route; this is not a full-Phi
   cache or a general throughput claim.

Các phần chạy trong snapshot riêng, manifest lấy từ cây hiện hành. Không
sửa cây chính hoặc snapshot đang xsim. Chỉ tích hợp file đã review và qua
gate tương ứng. Pipelining factor transport là đề xuất sau nếu profile mới vẫn
cho thấy lợi ích đáng kể.

Không thêm khối QR hardwired hoặc PE phụ. Các phép Householder, chứng nhận
nghiệm và điều khiển thuật toán tiếp tục do chương trình/context điều khiển.
Không giảm budget/đổi ngưỡng để ghi nhận speedup. Mọi thay đổi warm-start
hoặc hệ CG ADMM bị loại khỏi map round-two này và cần qualification riêng.

## Gate chấp nhận

- Xsim module: dữ liệu biên, mask, unaligned range, alias, backpressure,
  held response, cancel/restart và lỗi identity. Các lỗi cũ vẫn phải bị bắt.
- Tích hợp: đối chiếu full X/R/support/status, số vòng ngoài/CG, numeric
  events, program policy và digest Phi/Y với mốc đã lưu.
- Bảng chính báo cáo active-10 cho mỗi geometry cùng 8 vòng ngoài. ADMM được
  giữ reference riêng; toàn bộ 22 row đã đo (11 mỗi geometry) vẫn được lưu.
  Không suy ra thuật toán chưa đo là không bị chậm.
- Gate chất lượng giữ SNR fixed/float >=20 dB, mất <=0.5 dB và NMSE ratio
  <=1.10. Dữ liệu ứng dụng và bit production vẫn chưa được khóa.
- Mục tiêu board vẫn ZCU106 100 MHz. Cycle xsim không chứng minh LUT,
  BRAM, DSP, timing margin hoặc fit; chưa chạy synth/impl trong đợt này.

## Completed round-two evidence

The source-clean final fixed-eight archives
[`cycle_round2_final_fixed8_m32_20260909`](../../../reports/v4/cycle_round2_final_fixed8_m32_20260909/)
and
[`cycle_round2_final_fixed8_m64_20260909`](../../../reports/v4/cycle_round2_final_fixed8_m64_20260909/)
each completed PASS11 under common Phi/Y per geometry and actual outer eight.

| Algorithm | M64/N256/K8 | M32/N64/K8 |
|---|---:|---:|
| MP | 15,806 | 6,370 |
| GP | 17,549 | 7,351 |
| IHT | 23,036 | 7,988 |
| OMP | 68,110 | 48,742 |
| GOMP | 153,814 | 115,570 |
| CoSaMP | 431,824 | 359,756 |
| SP | 133,885 | 91,662 |
| HTP | 35,377 | 18,222 |
| FISTA | 20,362 | 5,106 |
| PDHG | 20,694 | 5,560 |
| ADMM (archived reference only) | 409,442 | 103,109 |

The primary comparison is active-10 only; ADMM is separately reference-only.
Fixed-eight quality is unchanged: low diagnostic SNR is not an application
quality PASS. ADMM round-two quality is `STOPPED_BY_SCOPE`, while the older
native archive remains reference calibration. The pre-round2 table stays dated
provenance and is not relabeled. No timing, resource, BRAM, DSP, fit, synthesis,
implementation, board or production-bit-lock claim is accepted.

## Residual bottlenecks and next proposal

The M64 fixed-eight profile still concentrates material time outside the new
transport: CoSaMP TEMPLATE 156,385/431,824 cycles (36.21%), FACTOR_READ 46,476
(10.76%), REPLACE_RANGE 30,144 (6.98%) and FACTOR_WRITE 27,812 (6.44%).
TEMPLATE is also 47,916/153,814 (31.15%) for GOMP, 16,632/68,110 (24.42%)
for OMP and 37,962/133,885 (28.35%) for SP. A separately verified proposal for
QR-template dispatch and vector/factor transport is next; QR throughput and
algorithm balance are not solved or claimed in this round.
