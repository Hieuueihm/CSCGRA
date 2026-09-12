# Baseline LSQR lịch sử — dùng để đối chiếu

**Đã được thay thế ở lựa chọn solver:** kiến trúc đích hiện hành dùng
[QR](QR_SOLVER.md) trên [shared stream kernel](STREAM_SYSTEM_CONTRACT.md).
`config/v4_design.json` và nội dung dưới giữ tham số baseline để tái lập các
study cũ; không được dùng trường LSQR trong đó để sinh chương trình đích mới.

**Cập nhật 2026-09-09:** người dùng yêu cầu xem lại kiến trúc trước khi viết
tiếp RTL, ưu tiên cycle và cân bằng toàn bộ thuật toán. [STREAMING_REDESIGN.md](STREAMING_REDESIGN.md)
là phương án đang đánh giá. Tài liệu dưới và config vẫn mô tả baseline hiện
tại để đối chiếu; không phải xác nhận rằng dataflow/solver này đã tối ưu.

Quyết định thiết kế ngày 2026-09-08, theo yêu cầu chốt một phương án để triển
khai. Tài liệu này và `architecture_decision` trong config ghi quyết định của
baseline tại thời điểm đó, thay cho danh sách candidate trước baseline.
**Đã chọn kiến trúc; chưa chứng nhận numerical, RTL, timing hoặc board.**

**Generator đã được người dùng chốt:** LFSR32 Galois right-shift v2 với taps
`0x80200003`, seed 32-bit (seed zero thay bằng `DEADBEEF`), phát LSB hiện tại
rồi mới step. Threefry2x32-20 được giữ làm reference/ablation và provenance
của các benchmark cũ; không dùng các benchmark Threefry để tuyên bố LFSR tốt hơn.
Độ rộng bit vẫn chưa chốt. Mỗi build chỉ cần một implementation; descriptor
phải khớp family/revision của build và measurement encoder.
[Prior art](THREEFRY_PRIOR_ART.md).

Giao diện phần cứng chung là `start_fill(descriptor)` rồi stream sign words có
column/row-block/mask/tag. Sau fill, cache chịu trách nhiệm đọc ngẫu nhiên cho
A/Aᵀ/support. LFSR sinh tuần tự trong full-cache fill; model indexed jump-ahead
chỉ dùng để kiểm tính tái lập, không áp đặt jump-ahead hardware runtime. Contract
tọa độ là `index = column*M + row`, phát LSB hiện tại rồi step; matrix tail chỉ
phát các hàng hợp lệ và **không tiêu thụ padding** trước cột kế tiếp. Với scale
chưa lượng tử hóa, Phi có dấu `±1/sqrt(M)`; coefficient quantization quyết định
giá trị C thực tế. Cold-fill, startup/stall và LUT/FF vẫn chưa được đo.

## 1. Quyết định

| Phần | Phương án triển khai |
|---|---|
| Board | ZCU106, xczu7ev-ffvc1156-2-e, mục tiêu core 100 MHz |
| Compute | Hai array 4×4, tổng 32 full PE; một sequencer, 32 context slots mỗi issue |
| Measurement | Phi dấu `±1/sqrt(M)` trước C quantization; LFSR32 Galois right-shift là generator đã chốt |
| Matrix chính | Sinh đủ Phi khi operator đổi; giữ một compact sign cache 8 bank, không có full dense A/Aᵀ trong baseline bitstream |
| Operator | A=Phi*Psi; Psi=I cho profile thực thi đầu tiên; Psi và adjoint là chương trình trên cùng PE khi application yêu cầu |
| LS matrix | Một cache dense B=A[:, ordered_support], không giữ bản transpose thứ hai |
| LS solver | LSQR làm implementation target trên PE; scalar service chung có DIV và SQRT |
| Generator reference | Threefry2x32-20 chỉ giữ cho reference/ablation; không phải generator baseline |
| Reference | CGLS software hiện tại và oracle SVD/QR; dense một-copy là phương án đối chứng/build khác |
| Numerical | Shortlist D18F14/C18F16/S27F22/X24F20/ACC64; chưa freeze bit; xem NUMERIC_CONTRACT |

Chọn LSQR để có một hướng hiện thực cụ thể; không tuyên bố đã đo được LSQR
nhanh hơn hoặc chính xác hơn CGLS fixed point. Nếu không qua gate, phải ghi
quyết định sửa kiến trúc, không âm thầm nới tiêu chí hoặc đổi thuật toán.

## 2. Luồng vận hành

1. Host nạp descriptor: seed, generator revision, scale, M/N, transform/profile
   và context image. y/x/context vẫn dùng DMA; không DMA full dense A.
2. Khi operator key đổi, invalidate và sinh đầy đủ Phi vào sign cache. Chỉ
   publish cache khi toàn bộ payload hợp lệ; reuse qua các vòng/job cùng key.
3. Context gọi operator thuận/chuyển vị qua feeder. R1 forward có 32 output;
   R4 transpose có 8 output × 4 reduction lanes trên hai array. Tails được mask.
4. Khi thuật toán thay support, support builder xây lại B theo ordered slots,
   rồi publish. LS chỉ quét B/Bᵀ và vector state; không sinh lại full Phi mỗi vòng.
5. LSQR chạy GEMV, DOT, AXPY, SCALE trên PE, gửi SQRT/DIV tới scalar service
   dùng chung. Candidate phải qua kiểm nghiệm sau lưu X trước outer commit.

Cache B **luôn dùng coefficient dense trong baseline**, kể cả Phi là dấu.
Support builder khi Psi=I chỉ cần lấy dấu và chuyển thành coefficient ±scale
đúng numeric contract. Cách này cho LS một format và một layout nhất quán.
Packed-sign B, incremental append và zero-cache regeneration là tối ưu đối
chứng về sau, không phải ba implementation phải viết ngay.

## 3. Bộ nhớ và bottleneck

Với M128/N1024, Phi có 16 KiB sign payload. Layout cache:

```text
bank = column % 8
address = floor(column/8)*ceil(M/32) + row_block
word = 32 consecutive row signs of one column
```

Mỗi bank 512×32. Mục tiêu inference là một RAMB18 SDP mỗi bank; dùng 8 BRAM36
làm dự trù conservative khi chưa có synthesis. Feeder R4 đọc 8 columns ở 8 bank,
mỗi word lấy 4 row bits theo `32*t+8*lane+u`. Không yêu cầu R1 transpose cấp 32
columns tức thời từ 8 bank. M32/tails và LS support nhỏ cần lịch có mask/cost riêng.

Cache B một-copy dùng layout diagonal theo support slot:

```text
bank = (row + support_slot) % 32
address = row*ceil(S/32) + floor(support_slot/32)
```

Tại C18/M128/S96, B có 27 KiB payload, dự trù 32 BRAM36 theo whole-bank
allocation; half-BRAM packing chưa được chứng nhận. Hai chiều dùng cùng B.
Prototype dense một-copy đã có bank/integer replay; gather, feeder, context và
pipeline cho cache B vẫn phải triển khai/kiểm chứng.

Subtotal ba nhóm ở cấu hình khảo sát là 8 Phi + 32 B + 36 context = **76 BRAM36**.
Đây chưa là tổng tài nguyên: chưa gồm vector LUTRAM, transform coefficients,
scalar/selection state, FIFO, loader/shell, routing hoặc precision tăng sau sweep.
Report board_budget.json cũ được giữ và đánh dấu là **dense reference**, không
đại diện cho baseline mới. Context depth 256 còn phải kiểm tra đủ chương trình.

Bottleneck cần xử lý rõ:

- Generator: fill một lần và reuse; tính cold-fill, startup, stall vào job cost.
- Hai hướng operator: cache bank layout + feeder/registered reduction; không
  suy useful PE throughput từ raw sign output rate.
- LS: B resident, GEMV/DOT/AXPY trên 32 PE; đo scalar SQRT/DIV stalls và số vòng.
- Support đổi: full rebuild đúng trước; tính preparation để tránh giấu chi phí.
- Phi/Psi: transform có kernel, buffer và coefficient cost; không có dense A
  nghĩa là phải trả chi phí transform, không có phép toán miễn phí.

## 4. Correctness và phạm vi application

Thiết bị đo và recovery phải dùng cùng Phi, scale, tọa độ và domain. Với
`s=Psi*x`, chạy `Ax=Phi*(Psi*x)` và `Aᵀr=Psiᵀ*(Phiᵀ*r)`. Adjoint không tự
đồng nghĩa inverse. Profile Psi=I là mốc kiểm chứng đầu tiên, không đại diện
cho dataset cần DCT/DWT hoặc cho mọi ứng dụng trong paper.

Trong fixed point, operator staged có rounding nên không được giả định tuyến
tính chính xác: tạo B bằng cách chạy basis vectors rồi cache có thể khác với
chạy full staged operator trên vector support. Trước nhận một profile Psi khác I,
phải định nghĩa golden riêng cho tạo B, matvec và adjoint, đo sai khác với cùng
real A và ảnh hưởng ở outer algorithm; không dùng certificate trên B để che
sai khác operator. Nếu không đạt quality thì profile đó chưa được hỗ trợ.

LSQR không regularization, x0=0. Reference cũ kiểm sau D; đường khảo sát mới
kiểm sau nghiệm lưu X riêng, xuyên suốt outer commit, theo
[numeric contract](NUMERIC_CONTRACT.md). Oracle SVD/QR kiểm prediction/objective
và coefficient theo conditioning/rank; normal residual nhỏ một mình chưa đủ.
Breakdown, overflow, budget exhaustion không được coi là success. Giữ rollback.

Quality gate: mất tối đa 0,5 dB SNR, NMSE tối đa 1,10× float64, cùng ngưỡng tuyệt
đối từng ứng dụng được freeze trước held-out; nhiều seed và conditioning cases.
Profile bit chưa chọn cuối. [Kết quả numerical hiện hành](../../../reports/v4/LFSR_APPLICATION_TUNING.md)
xác nhận 65 ca fixed được chọn và 583 lần LS trên support thực; normalization
và nghiệm lưu X đã được kiểm trong phạm vi này. Grid đầy đủ đạt 65/77 ca;
conditioning ngoài phạm vi đã kiểm và dữ liệu held-out vẫn cần đánh giá.
Model không phải chứng nhận RTL hoặc held-out application. Khảo sát generated
cũ được giữ nguyên trong reports để truy vết quyết định.

Chuẩn hóa theo lũy thừa hai trước lượng tử hóa đưa peak vào (0.25,0.5], giữ e
trong job metadata và chỉ undo scale ở đầu ra host. Scalar LSQR dùng một
reciprocal mantissa kèm exponent cho mỗi normalize, rồi SCALE trên PE; không
cần một DIV cho mỗi phần tử. Đây mới là số học model, chưa đo scalar latency.

## 5. Thứ tự công việc đã xác định

1. Model generated operator, sign-cache indexing và LSQR integer đã có; nối
   chúng với feeder/context execution để kiểm cùng arithmetic và stall semantics.
2. Dùng khảo sát LS/outer hiện có để hoàn thiện scale, stop và storage contracts;
   xác lập Psi từng application rồi thêm transform/golden trên cùng PE.
3. Sweep bit trên calibration/held-out protocol; đóng numeric và error contracts.
4. Compiler/context execution replay cho kernel và full program, tính fill,
   B rebuild, scalar stalls, context capacity và total-job cycles.
5. Kiểm RTL/TB hiện có và giữ phần đạt; Astra Ultra điều phối, agent Astra
   Medium triển khai phần thiếu theo yêu cầu hiện hành. Simulation/correctness
   trước synth, impl và board; xem STATUS.md để biết phạm vi đã có bằng chứng.

Novelty là giả thuyết về tổ chức operator/cache/context dùng tốt hai array
qua nhiều algorithm/application ở cùng quality; sinh matrix từ seed riêng lẻ
không phải novelty. Mọi kết luận cần ablation và đối chiếu prior art.
