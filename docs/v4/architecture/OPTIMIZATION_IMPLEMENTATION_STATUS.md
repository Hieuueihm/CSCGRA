# Các đợt tối ưu đã triển khai

## Đợt context và luồng dữ liệu

| Hướng | Cơ chế đã kiểm | Bằng chứng |
|---|---|---|
| Scalar/context | SCALAR_INSERT cho đầu reflector, tau, beta | Gate phần mềm và 20 ca scalar/control |
| Bỏ slice trung gian | RANGE_TEMPLATE/op22, đọc offset và kiểm mask/tag | Sequencer/range/kernel, 20 ca range riêng |
| GEMV | Nạp trước nhóm kế tiếp trong hàng đợi 4 frame hiện có | A/B, fault/cancel/reset/recovery và chương trình đầy đủ |
| Panel hẹp | C≤8: bốn hàng DOT, hai hàng RANK; giữ bank và rounding | Mock/bridge, PE thật và khảo sát ngưỡng 1/4/8 |
| Điều khiển | Đọc successor vào buffer hiện có tại retire | Trace/RF/lifecycle và chương trình đầy đủ |

[Báo cáo cuối](../../../reports/v4/context_stream_final_20260910/README.md) có đủ 10 thuật toán, hai cấu hình K8/8 vòng, quality và mọi đánh đổi của ngưỡng chung 1. Kích hoạt `view`, kernel revision 7, panel minimum 1; default `balanced` giữ nguyên. [Manifest cài đặt](../../../reports/v4/context_stream_promotion_20260910/before_after_manifest.json).

## Đợt resident QR trước đó

Ngày 2026-09-10. Năm bước dưới đây đã được cài source và source-qualified bằng evidence được liên kết. Các kết quả chỉ là Vivado XSim/matched fixed8; không là synthesis, timing, PPA, board hay production-bit qualification.

| Bước | Cơ chế generic | Trạng thái và evidence |
|---|---|---|
| 1 | FACTOR_EXTEND giữ QR ordered prefix, fallback INIT khi không còn prefix | Completed; [five-step report](../../../reports/v4/five_optimizations_20260910/README.md) và A/B/C paired report |
| 2 | Ownership remap cho full-vector scratch commit | Completed; full destination validity/fault/cancel semantics giữ nguyên |
| 3 | FACTOR_PROJECT_UPDATE: dot → scale → rank (MUL + SUB) trong private factor cache | Completed; [scalar RTL qualification](../../../reports/v4/scalar_insert_rtl_20260910/qualification.json) và factor leaf gates |
| 4 | SCALAR_INSERT generic từ scalar RF vào một lane, full-vector scratch commit | Completed; 17 kernel + 14 sequencer/166 cases + support evidence |
| 5 | Block-winner TOPK và command-local range provider | Completed; 11 support groups/156 records |

Tất cả dùng đúng hai array 4×4 (32 PE) và một vector pool. Không có AXI-Lite/MMIO/DMA/CPU register map; scalar RF32×64 là state nội bộ. Cấu hình active dùng `--qr-profile compact --target-kernel-revision 6`; `balanced` vẫn là default. [A/B/C comparison](../../../reports/v4/resident_chain_comparison_20260910/resident_chain_comparison_vi.md) giữ fairness raw Phi/Y/X/R/support/status/outer=8. Fixed8 quality là diagnostic và không thay held-out application gate.
