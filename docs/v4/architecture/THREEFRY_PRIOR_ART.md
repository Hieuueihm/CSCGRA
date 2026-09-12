# Threefry prior art và vị trí của v4

Ngày kiểm tra: 2026-09-08. Đây là bounded literature/source audit cho câu hỏi
"đã có paper dùng Threefry chưa?". Kết luận không phải tuyên bố absence proof.

## Kết luận ngắn

Có prior art chắc chắn cho Threefry như một counter-based PRNG, gồm cả biến thể
`Threefry2x32-20`. Chưa tìm thấy trong các truy vấn giới hạn bên dưới một paper
gốc dùng Threefry để sinh measurement/sensing matrix cho compressed sensing,
hoặc một paper FPGA CS trực tiếp dùng Threefry. Vì vậy novelty của v4 không nên
đặt ở việc "phát minh Threefry". Vị trí an toàn là dùng một PRNG đã được kiểm
chứng làm primitive để tạo map sign theo tọa độ, sau đó tự chứng minh chất lượng
CS (coherence/RIP proxy, conditioning, SNR/NMSE và recovery) và chi phí phần cứng.

KAT của generator chỉ chứng minh đúng hàm Threefry đã chọn; BigCrush/Crush chỉ
là bằng chứng chất lượng PRNG. Không kết quả nào trong hai nhóm này tự suy ra
RIP, conditioning, hay recovery của một ma trận hữu hạn sau khi dùng bit output
để tạo Bernoulli/Rademacher signs.

## Paper và source xác nhận

* Salmon, Moraes, Dror & Shaw, “Parallel Random Numbers: As Easy as 1, 2, 3”,
  SC’11, pp. 1–12, DOI
  [10.1145/2063384.2063405](https://doi.org/10.1145/2063384.2063405), bản PDF của
  tác giả tại
  [thesalmons.org/john/random123/papers/random123sc11.pdf](https://www.thesalmons.org/john/random123/papers/random123sc11.pdf).
  Paper định nghĩa Threefry-N×W-R là phiên bản giảm vòng và đơn giản hóa key
  schedule từ Threefish (PDF pp. 5–6), rồi báo cáo Crush/BigCrush, period và
  khả năng chạy song song cho PRNG. Table 2 báo cáo Threefry-2×64-13/20,
  4×64-12/20 và 4×32-12/20; **không báo cáo Threefry-2×32**. Vì vậy không nên
  viết rằng SC’11 đã benchmark chính xác `Threefry2x32-20`.

* Source chính thức
  [DEShawResearch/Random123](https://github.com/DEShawResearch/random123) và
  [threefry.h](https://raw.githubusercontent.com/DEShawResearch/random123/main/include/Random123/threefry.h)
  xác nhận API `Threefry2x32`, `Threefry4x32`, `Threefry2x64`, `Threefry4x64`.
  Header đặt `THREEFRY2x32_DEFAULT_ROUNDS` bằng 20, nêu rằng từ 13 vòng trở lên
  chưa biết lỗi thống kê (ghi chú tại thời điểm 2011), và định nghĩa rõ các
  rotation constants 2×32 `(13,15,26,6,17,29,16,24)` cùng parity
  `0x1BD11BDA`. Đây là căn cứ để gọi thiết kế hiện tại là một **Random123
  Threefry2x32-20 implementation**, không phải kết quả mới của paper gốc.

* README chính thức mô tả Random123 là C/C++/CUDA/OpenCL counter-based RNG,
  stateless theo `(counter,key)`, dành cho statistical applications và Monte
  Carlo; đồng thời cảnh báo không dùng cho cryptography. Đây là evidence cho
  deterministic random-access/parallel implementation, không phải CS matrix
  quality. AMD's official
  [rocRAND generator documentation](https://rocmdocs.amd.com/projects/rocRAND/en/latest/conceptual/generator-types.html)
  cũng liệt kê ThreeFry 2×32-20 như một counter-based PRNG trên device; đó là
  library/platform precedent, không phải paper CS.

## CS và hardware comparison

Các công trình tìm được dùng Bernoulli/binary matrices và LFSR/shift-register
hoặc lưu ma trận; chúng không dùng Threefry. Chúng chỉ nên làm comparison về
hardware design space:

* Yu, Zhao, Tian, Guo, Huang & Gu, “An Improved Measurement Matrix Generator
  for Compressed Sensing of ECG Signals”, *Electronics* 11(22), 3784 (2022),
  DOI [10.3390/electronics11223784](https://doi.org/10.3390/electronics11223784).
  Bài báo dùng serial sparse-binary measurement matrix từ LFSR+latches, thực
  hiện CS circuit trong SMIC 55 nm và báo cáo PRD 1.32%; đây là precedent cho
  generator phần cứng và quality evaluation theo workload, không phải bằng
  chứng Threefry hoặc FPGA.

* Cambareri, Mangia, Pareschi, Rovatti & Setti, “A Case Study in Low-Complexity ECG Signal Encoding: How
  Compressing is Compressed Sensing?”, *IEEE Signal Processing Letters* (2015),
  DOI [10.1109/LSP.2015.2428431](https://doi.org/10.1109/LSP.2015.2428431),
  [author PDF](https://iris.polito.it/bitstream/11583/2696594/1/LSP2428431.pdf).
  Đây là digital multiplierless CS encoder với Bernoulli ±1 matrix và single
  accumulator; hữu ích để so cách biểu diễn/chi phí sign matrix, không nói
  Threefry hay FPGA generator.

* Yuan, Song, Sun & Guo, “Compressive Sensing Measurement Matrix Generator
  Based on Improved SC-Array LDPC Code”, *Circuits, Systems & Signal
  Processing* 35 (2016) 977–992, DOI
  [10.1007/s00034-015-0100-y](https://doi.org/10.1007/s00034-015-0100-y).
  Bài báo dùng cycle-shift registers để sinh structured CS matrix và so sánh
  recovery; đây là precedent cho structured shift-register hardware, không
  phải Threefry.

Một paper phần cứng có Threefish (cipher ancestor) là Nieto-Ramírez &
Nieto-Londoño, “Threefish-256 algorithm implementation on reconfigurable
hardware”, *ITECKNE* 11(2), 149–156 (2014), DOI
[10.15332/iteckne.v11i2.725](https://doi.org/10.15332/iteckne.v11i2.725). Paper
này triển khai encryption Threefish-256 trên Virtex-5; không được dùng như
bằng chứng FPGA Threefry hoặc CS.

## Truy vấn và phạm vi

Ngày 2026-09-08 đã chạy các truy vấn: `"Threefry" "compressed sensing"`,
`"Threefry" "measurement matrix"`, `"Threefry2x32" compressed sensing`,
`"Threefry" sensing matrix FPGA`, `Threefry Rademacher matrix compressed
sensing`, `Threefry Bernoulli matrix sparse recovery`, và `Threefry FPGA random
number generator hardware`. Kết quả trực tiếp và có thể kiểm tra được là
Random123/SC’11, library/runtime uses, cùng các paper CS dùng LFSR hoặc
structured matrices; không có direct Threefry-CS hit trong phạm vi này. Cách
viết đúng là “chưa tìm thấy trong bounded search”, không phải “chưa ai từng
dùng”.

## Liên hệ với evidence cục bộ

Paper CSR local được audit trong [PAPER_AND_V3_REVIEW.md](../PAPER_AND_V3_REVIEW.md)
mô tả LFSR signs. Threefry thuộc source v3 phát triển sau đó; không gán nó cho
paper local. Baseline v4 cache đầy đủ Phi nên random-access generation không
phải yêu cầu bắt buộc của phần cứng generator: `start_fill` và tagged sign-word
stream đủ, rồi cache phục vụ hai hướng và support. Đây là lý do LFSR tuần tự
cần được đối chứng area/cold-fill một cách thực chất.

`GENERATED_OPERATOR.md` và `GENERATED_MATRIX_AUDIT.md` đang diễn đạt đúng
ranh giới: v3 map `seed,row,column` thành deterministic Threefry2x32-20 signs,
nhưng PRNG quality không tự chứng minh RIP/conditioning. Báo cáo cũ
`reports/v3/phi_qualification/summary.md` chỉ là empirical seed screen (23, 47,
101; seed 47 qua gate cũ; worst coherence 0.421875; 72 cases), không phải
chứng minh Threefry nói chung và không được lọc seed để làm mất ý nghĩa study.
Nghiên cứu v4 nên chạy các seed đã thống nhất, báo cáo quality gate độc lập với
KAT, và giữ rõ rằng chọn LSQR là quyết định triển khai cần validation SNR/NMSE,
throughput và nghiệm LS trước RTL.
