# Đường cấp dữ liệu Phi/B có hàng đợi

Bản ghi transport đã được kiểm Vivado trước round-2, ngày 2026-09-09:
[19 tests transport/kernel](../../../reports/v4/operator_pipeline_rtl_audit_20260909/README.md),
[17 ca toàn chương trình](../../../reports/v4/pipeline_whole_program_comparison_20260909/README.md)
và [bốn ca toàn N](../../../reports/v4/pipeline_max_program_comparison_20260909/README.md).
Giữ cùng hai array 4x4, phép toán và context của thuật toán. Chưa synth/impl
hoặc khẳng định timing/tài nguyên.

## Round-two source-clean evidence

The fixed-eight suites at M32/N64/K8 and M64/N256/K8 completed PASS11 with
common raw Phi/Y per geometry, raw X/residual/support/status comparison and
actual outer count eight. The active set is MP, OMP, GOMP, CoSaMP, SP, IHT,
HTP, GP, FISTA and PDHG. ADMM's measured fixed-eight rows are archived
reference only; round-two ADMM quality is `STOPPED_BY_SCOPE`, not PASS.

| Geometry | Active-10 cycles (MP, GP, IHT, OMP, GOMP, CoSaMP, SP, HTP, FISTA, PDHG) | ADMM reference |
|---|---|---:|
| M64/N256/K8 | 15,806; 17,549; 23,036; 68,110; 153,814; 431,824; 133,885; 35,377; 20,362; 20,694 | 409,442 |
| M32/N64/K8 | 6,370; 7,351; 7,988; 48,742; 115,570; 359,756; 91,662; 18,222; 5,106; 5,560 | 103,109 |

See the root-generated [round-two comparison](../../../reports/v4/cycle_round2_comparison_20260909/round2_comparison_vi.md). These xsim gates do not establish application quality, synthesis/implementation, timing, resources, fit, board deployment or a production bit lock.

## Round-two qualified transport scope

The mechanisms below are source-bound xsim-qualified by the completed fixed-eight suites and final module gates. They retain the dated transport/program reports above as provenance.

| Candidate path | Exact scope | Kept invariant |
|---|---|---|
| Phi tile reuse | Two command-local entries hold **raw 32-row × 8-column sign tiles** only for favorable live-Phi mappings: R1 forward and R4 transpose. A validated same-tile hit may be accepted at most once per clock. | The underlying eight sign banks, LFSR/sign order, tags and masks remain authoritative; the existing reader/bank route handles a miss and may prefetch eligible tile banks. The entries store only raw sign tiles, not expanded coefficients or an additional full Phi/B matrix. |
| Dense or unfavorable Phi | Dense commands and the other live-Phi directions continue through the existing reader/bank route. | No throughput inference applies outside the favorable modes. |
| TEMPLATE operand issue | A captured template emits no operand request for a source its loaded context does not consume; an exactly aliased consumed source may reuse the captured validated read. | Context words, bindings, valid masks, tail, arithmetic and cancellation semantics stay verbatim. No context is rewritten to create reuse. |
| SLICE/REPLACE_RANGE | For **each output 32-lane block** of a public range up to 1024 elements, the analytic plan uses at most three distinct 32-lane source providers, gathered one read at a time, then aligned and merged into scratch. | Required-lane tag/mask/fault checks, held transactions, source/aux aliases and atomic publication remain required. |

The updated round-two diagram is [operator_pipeline.mmd](../diagrams/operator_pipeline.mmd).
One eligible tile hit per cycle is a cache-local admission rule, not a claim of
one full frame or command per cycle. No timing, resource, BRAM, DSP or fit
claim follows.

| Thành phần | Vai trò và giới hạn |
|---|---|
| `stream_kernel` | Tách tọa độ frame đã cấp và frame đã nhận; kiểm thứ tự, chờ cả nhóm hoàn tất rồi mới reset ACC |
| `operator_frame_feeder` | Bốn slot frame theo thứ tự; ghép dữ liệu ma trận/vector, hai request ma trận đang chờ, kiểm tags/mask |
| Cache operand trong feeder | Hai block vector, mỗi block 32 S27; dùng lại trong cùng lệnh, xóa validity khi bắt đầu lệnh mới |
| `live_operator_memory` | Hai read credits; giữ Phi/B mode tới khi drain, fill/build có quyền riêng |
| `phi_reader` | Hai slot request/response có thứ tự; kiểm key, job, format, generation, tag và lỗi |
| `phi_sign_cache` | Cùng tám bank dấu; một response register, cho nhận đọc mới khi response cũ được nhận ở cùng cạnh clock |
| `paired_support_store` | Giữ nguyên B gốc và layout 16 bank TDP, hai read credits |
| `stream_fabric` | Hai array, đúng 32 PE; rounding/ACC không đổi; terminal ACC dùng PEACC hiện có và fixed registered reduction links |

[Sơ đồ](../diagrams/operator_pipeline.mmd). Không có bản Phi hay B thứ hai.
Slot và operand cache thêm state/mux; mức LUT/FF cụ thể phải đo sau correctness.

## Giữ correctness khi nhiều request đang chạy

Một request đã valid phải giữ nguyên payload tới khi ready hoặc cancel.
Selector không được đổi sang frame cũ vừa nhận response trong lúc một request
khác đang chờ. Matrix/vector có khóa request được đưa ra để giữ quy tắc này.
Frame trả theo thứ tự; tag nội bộ ghép số frame và pass. Command mới chỉ bắt
đầu sau khi command trước drain; cache operand không được giữ data qua lệnh
ghi cùng địa chỉ. Stall không được làm mất, lặp hoặc ghi đè response.

Host yêu cầu fill/build trong lúc compute_active phải chờ, còn các read của
compute tiếp tục. Khi compute nhường quyền, drain read credits trước khi đổi
mode hoặc fill/build. Chặn read chỉ vì host giữ VALID có thể gây deadlock.
Cancel/fault phải hủy toàn bộ frame, read credits và scratch chưa publish;
kết quả đã commit trước đó được giữ theo contract native.

## Cách đo tác dụng

- A: bốn slot và cache vector, vẫn endpoint đọc tuần tự.
- B: thêm hai read credits trong feeder/wrapper; Phi reader/cache còn cũ nên
  phần này chủ yếu giúp B.
- C: thêm Phi reader hai slot và cache đọc elastic; đo riêng hiệu quả Phi.

Đếm accepted frames, matrix/vector grants, stall, service và toàn chương
trình. II1 của cache là khả năng nhận riêng cache khi không stall, không phải
II1 toàn engine. R1/R4 có số pass khác nhau; fold32 vẫn là phần cần tối ưu.
Mọi bước giữ cùng raw X/residual/support/status. [GP](GRADIENT_PURSUIT.md)
giữ gradient/line search, không đổi thành IHT để giảm cycle.
