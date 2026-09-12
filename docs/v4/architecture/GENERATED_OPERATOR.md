# Operator tự sinh cho v4: lựa chọn theo bài toán đo

**Đã chốt hướng triển khai tại [BASELINE.md](BASELINE.md): full compact sign
cache, B dense một-copy, LSQR và LFSR32 Galois right-shift v2.** Threefry2x32-20
được giữ làm reference/ablation; các benchmark đã chạy với Threefry phải giữ
nguyên provenance và không được dùng để tuyên bố LFSR vượt trội. Phần dưới giữ
phân tích các phương án, không đại diện cho nhiều baseline song song.

Generator contract của baseline là taps `0x80200003`, seed 32-bit, seed zero
thay bằng `DEADBEEF`, phát LSB của state hiện tại rồi mới Galois right-shift.
Model indexed jump-ahead chỉ phục vụ kiểm tái lập; full-cache hardware fill sinh
tuần tự theo stream. Cache/feeder dùng chung contract signs, coordinates,
shape và family/revision. Xem [prior art](THREEFRY_PRIOR_ART.md).

**Đưa generated operator thành ứng viên chính khi ứng dụng cho phép**, cùng
compact sign cache nếu cần giữ throughput cho các hướng đọc. Dense một-copy
là phương án general operator; không bắt mọi ứng dụng trả bộ nhớ cho dense A.
Đây là quyết định trước RTL; model LFSR/Threefry chạy được nhưng generated RTL
backend của v4 chưa có.
Audit nguồn v2/v3: [GENERATED_MATRIX_AUDIT.md](GENERATED_MATRIX_AUDIT.md).

## Ý tưởng dễ hiểu

Thay vì nạp hàng trăm nghìn coefficient, host nạp seed, kích thước, scale và
generator revision. FPGA tạo lại coefficient khi cần. Điều kiện bắt buộc là
thiết bị tạo measurement và bộ recovery sử dụng **cùng một ma trận**.
Không thay seed, scale hoặc cách đánh số row/column giữa các lần gọi operator.

V2 có LFSR tuần tự; contract v4 giữ state 32-bit với taps `0x80200003`, seed
zero thành `DEADBEEF`, và `index=column*M+row` theo column-major: đọc LSB hiện tại
rồi mới step. Khi `M` không chia hết32, row tail chỉ phát số sign hợp lệ; padding
không được tiêu thụ nên không làm lệch cột kế tiếp. Threefry2x32-20 của v3 vẫn
được giữ làm reference/ablation: seed 64 bit là key, column và row-pair là counter;
một invocation trả 64 signs của một cột, gearbox trả 32 signs/word. Cần giữ
known-answer vectors và mapping chính xác, không chỉ nói chung là random matrix.
Nguồn ý tưởng counter-based là
[Salmon et al., Random123](https://www.thesalmons.org/john/random123/papers/random123sc11.pdf).
Tính chất PRNG tốt không tự chứng minh RIP, conditioning hoặc chất lượng CS cho
mọi seed/operator/bài toán.

Generated operator giảm matrix DMA và lưu trữ coefficient. Nó thêm logic,
pipeline, buffers, thời gian sinh và chi phí chuyển thứ tự đọc. Không gọi toàn
thiết kế là zero-memory; y/x/state/context và LS workspace vẫn cần bộ nhớ.

V3 đã có cache sign words cho support, tối đa 96 active slots. Tận dụng ý tưởng
này, nhưng cache full-sign 8 bank bên dưới là proposal khác; model cache cũ gắn
Threefry, chưa có LFSR cache/feeder execution hoặc RTL v4 hoàn chỉnh.
Các báo cáo OOC cũ của v3 cho generator ghi 2.106 LUT, 1.887 FF, 0 BRAM, 0 DSP;
chúng cho thấy có tiền lệ trên xczu7ev, không chứng nhận source hiện tại hoặc
timing/area của toàn v4. Chi tiết nguồn và phạm vi ở tài liệu audit.

## Phân biệt hai trường hợp

### A trực tiếp là ma trận dấu

Nếu bài toán có `y = A*x`, `A[i,j] = scale*sign(seed,i,j)`, generator thay được
toàn bộ dense A. Với M128/N1024:

| Cách biểu diễn cùng operator dấu | Payload coefficient |
|---|---:|
| Dense C18 một-copy | 288 KiB |
| Sign1bit một-copy + scale | 16 KiB + metadata |
| Sinh theo yêu cầu | Seed/metadata + buffers; không giữ đủ sign matrix |

Generated trực tiếp chỉ đúng với domain x đã định nghĩa. Nếu x là các hệ số
biến đổi, thiết bị đo phải thực sự tạo `y=A*x` theo domain đó. Không thay các
phép đo vật lý `y=Phi*s` bằng một benchmark khác rồi gọi là cùng ứng dụng.

Với ±c, PE có thể dùng sign-add và scale thay general coefficient multiply.
Chỉ dịch scale ra cuối dot khi chứng minh đúng accumulator range và điểm round:
dense coefficient quantized ±c_q có thể factor c_q ra khỏi tổng integer chính
xác; rounding/saturation từng term hoặc từng partial sẽ thay điều kiện này.
Scale là metadata của operator, không tự đặt1/8 hoặc1/sqrt(M) theo thói quen.

Hai array vẫn gồm 32 full PE: sign-add là một chế độ thực thi, còn DOT, AXPY,
transform và scalar-product kernels vẫn cần arithmetic tổng quát. Với cùng
scale và đủ M hàng, mọi cột A dấu có norm bình phương M*c²; đây là thông tin
có thể khai thác để tránh lưu/tính norm riêng từng cột. Không áp dụng kết luận
này cho A=Phi*Psi tổng quát.

### Phi tự sinh nhưng A = Phi*Psi

ECG/ảnh/âm thanh thường được giả thiết thưa trong DWT/DCT; lúc đó recovery dùng
`A=Phi*Psi`. Sinh Phi không có nghĩa mỗi coefficient A cũng là một dấu.
Có hai phương án đúng về mô hình đo:

1. Giữ A general và dùng backend dense một-copy khi đó là phương án rẻ nhất.
2. Thực hiện operator theo hai bước trên PE:
   `Ax = Phi*(Psi*x)` và `Aᵀr = Psiᵀ*(Phiᵀ*r)`.

Phương án2 cần kernel transform/inverse-synthesis và **adjoint đúng** của nó,
buffer trung gian, scale và schedule. Với basis không orthonormal, adjoint
không được thay bằng inverse. DCT/DWT/Fourier cũng có chi phí, hệ số lọc/twiddle
và điều kiện biên riêng. Không gọi đó là tính năng v4 đã có.

Về số thực, hai cách biểu diễn cùng A. Về fixed point, `Q(Phi*Psi)` rồi GEMV
khác với lượng tử hóa các bước transform và generated multiply riêng. Cần
golden cho staged operator, kiểm adjoint/error, overflow và application quality
lại. Các study lịch sử phải giữ đúng operator/source của mình; các study
LFSR mới cũng chưa chứng nhận staged transform hoặc cache/feeder execution.

## Giữ throughput cho hai array

Mục tiêu là giao đủ32 coefficient/signs **đúng tọa độ yêu cầu** cho32PE.
Generator trả32signs trung bình mỗi cycle chưa đủ chứng minh throughput mọi
kernel. V3 sinh theo cột; đọc32cột của Aᵀr là yêu cầu khác đọc32row của Ax.
Tail, request gaps và pipeline feedback cũng phải tính.

Hai phương án cần đối chứng:

- Sinh trực tiếp, có FIFO/tile transpose buffer và prefetch theo kernel.
- Sinh một lần vào compact sign cache, dùng lại qua các vòng và jobs cùng seed.

Đề xuất cache dấu cho M128/N1024 có8 bank:

```text
word: 32 signs của một column, row_block liên tiếp
bank = column % 8
address = floor(column/8)*ceil(M/32) + row_block
```

Mỗi bank có512word×32bit. R1 forward đọc một word, trải32sign ra32PE.
R4 transpose với8column liên tiếp đọc8word ở8bank; mỗi word chọn4bit ứng với
`row=32*t+8*lane+u`. Có32sign hữu ích/issue, và8word có thể giữ qua8 giá trị u.
Đây là access proposal, chưa có buffer/feeder/RTL hoặc timing proof. R1 transpose
32column cần schedule/cache khác hoặc chọn R4; không tuyên bố8bank đáp ứng mọi
mode cũ. Chọn mode theo total cost đã tính, không chỉ số word cache.

Geometry512×32 có thể dùng một RAMB18 SDP512×36 mỗi bank theo
[AMD UG573](https://docs.amd.com/r/en-US/ug573-ultrascale-memory-resources/Block-RAM-Summary):
8RAMB18 tương đương4BRAM36 nếu placement ghép được hai nửa; dự trù8fullBRAM36
là cách conservative. Đây chỉ là cache dấu, chưa gồm generator/feeder/control.

Sinh đủ131072signs ở sustained32sign/cycle cần4096payload cycles, tương đương
40,96µs ở100MHz trước startup/stalls/tails. Đây là target arithmetic, không
phải latency v4 đã đo; source v3 có pipeline folded/gearbox cần audit thực tế.
Nạp seed qua AXI-Lite rất nhỏ nhưng thời gian sinh/cache fill vẫn thuộc cold job.

## LS solver dùng generated operator thế nào?

CGLS và LSQR cần hai phép B*v và Bᵀ*u, với B chứa các cột được chọn. Giao diện
kernel không nên phụ thuộc coefficient đến từ generator hay RAM; buffer/key
và format descriptor phải xác định rõ operator đang thực thi.

- **A là ma trận dấu:** cache chỉ các cột của B bằng sign có useful payload
  `M*S` bit; tại M128/S96 là1,5KiB trước port/geometry overhead. Có thể giữ B
  để nhiều vòng LS không phải tạo lại cùng các dấu.
- **A=Phi*Psi:** B thường chứa coefficient số thực tổng quát. Có thể cache B
  đã được tạo đúng theo operator, tại C18/M128/S96 là27KiB useful payload.
  Phải tính chi phí tạo từng cột B; không gọi đây là lấy một sign từ generator.
- **Không cache B:** scatter vector support vào N hệ số, chạy operator full,
  rồi gather khi cần. Đúng về toán nhưng có thể làm LS support nhỏ trả chi phí
  full N mỗi vòng. Không chọn chỉ vì tiết kiệm RAM.

OMP append một atom có thể reuse các cột B cũ và tạo cột mới; CoSaMP/SP thay
support cần generation/remap/rollback đúng. Trước khi tối ưu incremental phải
có full-rebuild oracle. Việc tạo B từ Phi/Psi có thể đắt khi support đổi liên
tục; đối chứng với dense một-copy phải tính preparation và reuse đầy đủ.

Vẫn chọn [LS solver theo PE + accuracy](LS_SOLVER_DECISION.md): CGLS baseline,
LSQR ưu tiên so sánh, QR/SVD oracle. Generated matrix không tự bảo đảm solver
đúng; giữ kiểm nghiệm sau X theo numeric contract, coefficient/prediction policy, conditioning, nhiều
seed và quality floors. Generator revision/seed/scale/shape/domain/ordered
support phải nằm trong cache key và report provenance.

## Phạm vi triển khai đề xuất

Các vai trò cần tách rõ khi chốt module, chưa thêm RTL path vào catalog:

| Vai trò | Trách nhiệm và state |
|---|---|
| Operator descriptor | Family, seed/revision, scale, shape, domain và numeric profile; khóa trong job |
| Sign generator | Tạo signs đúng coordinate, tags/masks, giữ payload khi backpressure |
| Sign cache / prefetch | Lưu sign words, valid/generation tags, fill/invalidate; không thực hiện LS arithmetic |
| Operator feeder | Chọn cache address, unpack/reorder signs, cấp đúng vector và lane mask theo R1/R4 |
| Transform programs | Chạy Psi và adjoint trên các PE; quản lý coefficient và buffer trung gian khi cần |
| Support builder/cache | Tạo B theo ordered support, công bố cache sau khi fill đúng; sign hoặc dense tùy family |
| LS microprogram | Dùng B/Bᵀ, DOT, AXPY và scalar unit chung; quyết định dừng và kiểm nghiệm sau lưu D |

Ba family cùng gọi operator/adjoint contract, nhưng chỉ bật family đã có model,
context và tests tương ứng:

| Family | Ưu tiên sử dụng | Trạng thái v4 |
|---|---|---|
| Generated sign A + compact cache | Measurement domain cho phép A dấu | Proposal; tham khảo v3, chưa port |
| Generated Phi + transform Psi + LS B cache | Giữ raw-signal measurement và basis phù hợp | Proposal; transform/golden/schedule chưa có |
| Dense A một-copy | Operator tổng quát hoặc preparation rẻ hơn factorized | Bank/integer prototype; chưa RTL |

Image packer hai-copy vẫn giữ làm reference, không mặc định là kiến trúc tối
ưu. Chọn family theo ứng dụng với dữ liệu đo không đổi; không thêm backend
không cần thiết vào bitstream để làm tốn area. RTL từng module giao Luna/Spark.

**Novelty chưa thể là “sinh ma trận từ seed”**: v2/v3 đã làm và counter-based
RNG là prior art. Hướng cần chứng minh là cách một operator contract, cache
dấu/support và context mapping phục vụ cả hai array qua các thuật toán khác
nhau, với quality giữ nguyên và total-job cost/resource tốt hơn các baseline.
Đó hiện là giả thuyết nghiên cứu, cần ablation và đối chiếu prior art trước claim.
