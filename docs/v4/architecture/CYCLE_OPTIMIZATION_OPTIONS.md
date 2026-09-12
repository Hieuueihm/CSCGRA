# Các lựa chọn tối ưu cycle sau factor panel

## Current measured closure

Các năm bước đã cài source. Báo cáo hiện hành là [A/B/C resident-chain comparison](../../../reports/v4/resident_chain_comparison_20260910/resident_chain_comparison_vi.md) và [five-step evidence](../../../reports/v4/five_optimizations_20260910/README.md). Các lựa chọn bên dưới là lịch sử/next-step planning, không thay evidence matched fixed8 hiện tại.

## Historical and future options

Ngày 2026-09-10. Tài liệu này ghi các lựa chọn kỹ thuật để đánh giá; không là
cam kết cycle, timing, PPA, resource fit hoặc production qualification. Mọi
thay đổi tiếp theo phải giữ chương trình generic, đúng kết quả fixed-point,
các điểm rounding hiện có, identity/fault/cancel/commit và đúng **32 PE**.

Điểm đo hiện tại là CoSaMP M=64/N=256/K=8 fixed8 ở archive
`factor_panel_final_fixed8_m64_20260909`: 252,684 cycles. Các khoản profiler
liên quan là TEMPLATE 46,169 cycles / 1,958 calls, factor panel 36,704
cycles, REPLACE_RANGE 30,144 cycles, TOPK 18,232 cycles (7.2%) và SLICE
11,564 cycles. Chúng là các interval đã đo, không phải cách gán mọi phần còn
lại cho idle hoặc cho một pipeline chưa được profile.

## Historical candidate record: support within a command

Phần support của candidate đang được qualify lại dùng transport generic trong
phạm vi lệnh. TOPK với `k>1` có thể giữ một winner hợp lệ cho mỗi block 32
word và refresh đúng block đã mất winner; k=1 và các ca break-even hẹp đi theo
lịch cũ. SLICE và
REPLACE_RANGE chỉ dùng tối đa hai block operand đã xác thực **trong một
lệnh**, xóa cache khi command/cancel/reset và không đọc lane ngoài mask cần
cho command. Toàn candidate còn có compiler/backend FACTOR_EXTEND cho
OMP/GOMP. Nó không giữ cross-command vector residency, không có full vector
mirror, PE/multiplier mới hay classifier thuật toán.

Focused XSim đã kiểm tails, mask/tag/fault, held payload, cancel, alias và
length/K tới 1024. Whole-program acceptance cho QR reuse vẫn pending tại thời
điểm ghi tài liệu này; không thay các row qualified bằng cycle diagnostic.

## Historical next-step options

| Ưu tiên | Hướng generic | Ràng buộc phải giữ | Cách đánh giá |
|---|---|---|---|
| 1 | Incremental QR hiện candidate: OMP/GOMP append ordered-prefix dùng FACTOR_EXTEND. | Không có QR downdate hoặc reuse khi support thay đổi tùy ý; dot phụ thuộc reflector vẫn cần hai passes, thứ tự accumulation/rounding và invalidation theo Phi/Y/job/key giữ nguyên. | Pair cùng raw Phi/Y/X/R, support, policy và outer thực; báo physical QR/INIT/EXTEND cùng cycle. |
| 2 | Context-chain resident operands/views/masked write: loaded generic context mô tả view, lane mask và chain giữa các op. | Không tạo full matrix/vector copy; source/destination alias, held request/response, fault/cancel và scratch publication vẫn atomic. | Directed XSim tails/alias/stall/fault trước, sau đó fixed8 all-algorithm archive. |
| 3 | Tăng residency của reflector panel hiện có giữa các generic panel calls. | Factor ownership/private validity, certificate và 32 PE hiện có giữ nguyên; không hardwire QR FSM. | Profile riêng PANEL/FACTOR_READ/WRITE và chứng minh X/R/support không đổi. |
| 4 | Resident backsolve scalar writes bằng generic scalar/template contexts. | Các scalar round points, write order, cancellation và final certificate phải giữ nguyên. | So sánh trace scalar/context và bounded tails trước whole-program. |
| 5 | Block-winner TOPK hiện candidate. | Tie rule, abs-most-negative, exclusion, sorted output, all-zero và k>valid phải đúng; k=1/nhỏ được phép legacy. | Ghi reads/cycles cho N64 K1/K2/K3 và N256 K2, rồi check full support oracle. |

Context-chain/residency là hướng **tương lai** và khác với cache command-local
candidate. Chỉ context đã loaded, generic op descriptors, operand view và
masked write được xem xét; không có bổ sung ma trận đầy đủ, copy factor đầy đủ
hay phần cứng phân loại thuật toán. Mọi tăng data residency phải có ownership
key/generation/job cùng invalidation rõ ràng trước khi mutation/publication.

## Fairness và báo cáo

Cycle chỉ được đặt cạnh nhau khi geometry, raw Phi/Y, truth, fixed policy và
outer thực giống nhau. Nếu program image thay đổi, báo riêng digest và lý do;
với internal work khác nhau phải ghi QR calls, logical solve/correction, inner
iterations và service intervals. Fixed8 quality là diagnostic, không thay
held-out application quality; không tạo speedup với V2/V3 boundaries khác.

Báo cáo trạng thái hiện tại: [M64/N256/K8 v4 và V3](../../../reports/v4/m64_n256_k8_vs_v3_status_20260910.md).
