# Tổ chức project v4

## QR profile navigation

`balanced` vẫn là compatibility default. `compact` feature6 đã cài source và
phải được chọn explicit. Command exporter nhận file JSON nguồn rồi thư mục
output, không nhận `--algorithm`/`--output` riêng:

```powershell
$streamPython = 'C:\Users\gbmhi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $streamPython scripts/v4/export_recovery.py input.json work/v4/compact_program --qr-profile compact --target-kernel-revision 6
```

`streamed` là biến thể feature6, dùng SCALAR_INSERT cho tau, beta và
head của reflector QR:

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/streamed_program --qr-profile streamed --target-kernel-revision 6
```

`view` là profile feature7. Nó kế thừa streamed và dùng
RANGE_TEMPLATE cho các QR slice command-scoped; chỉ dùng với runtime feature7
matching:

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/view_program --qr-profile view --target-kernel-revision 7 --qr-panel-min-columns 1
```

`--operand-chains` là opt-in feature8 riêng cho four non-QR programs
GP, IHT, FISTA và PDHG. Nó thay các cặp `SCALE` rồi `ADD`/`SUB` đã chọn
bằng `ROUNDED_AFFINE`, vẫn giữ round22 của product trước phép cộng/trừ.
Khi chọn cờ này, export cần runtime revision8; `balanced` và cờ mặc định
vẫn không phát opcode mới. QR programs không có site affine và giữ load image
của profile QR tương ứng.

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/affine_program --qr-profile view --qr-panel-min-columns 1 --operand-chains --target-kernel-revision 8
```

Sơ đồ luồng command là [rounded_affine.mmd](diagrams/rounded_affine.mmd).

Feature9 chọn `FACTOR_RANGE_TEMPLATE` cho QR range/tap. Runtime được chọn explicit
với cả hai cờ, revision 9; bitmap SORT trong `support_service` mặc định bật:

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/factor_range_program --qr-profile view --qr-panel-min-columns 1 --operand-chains --factor-range-template --target-kernel-revision 9
```

Step1 `FACTOR_ENERGY_TAP` là opt-in feature10 đã source-qualified. Nó thay hai pass
`ENERGY` trong phần dựng reflector QR bằng factor-private full tap, raw ACC64
square sum và tail predicate; thứ tự beta/tau/NORMALIZE/certificate không đổi.
Activation cần runtime revision10:

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/energy_program --qr-profile view --qr-panel-min-columns 1 --factor-energy-tap --target-kernel-revision 10
```

Xem [FACTOR_ENERGY_TAP.md](architecture/FACTOR_ENERGY_TAP.md) cho ABI,
[STATUS.md](STATUS.md) và
[báo cáo final](../../reports/v4/factor_energy_tap_final_20260910/README.md)
cho evidence M32/N64/K8 và M64/N256/K8, outer=8. Promotion manifest ghi trạng
thái cài source; `balanced` vẫn là default. Đợt Step1 này không bao gồm Step2/3.

Step2 `PROJECT_DOT` đã cài riêng bằng runtime/test promotion có kiểm hash.
`factor_panel_service` mặc định `PROJECT_DOT_SPLIT_ENABLE=1` và
`PROJECT_DOT_SPLIT_MIN_ROWS=24`: DOT 9–16 cột được chia 8 + phần còn lại dùng
R4 từ 24 hàng; shape khác giữ fallback. Đây là parameter lúc elaboration,
không phải cờ exporter mới. Image, revision, opt-in Step1 và điểm làm tròn
không đổi. Tắt `PROJECT_DOT_SPLIT_ENABLE` chỉ để đo A/B lịch cũ.

[Contract Step2](architecture/PROJECT_DOT_SCHEDULE.md),
[kết quả active10 actual8](../../reports/v4/project_dot_final_20260910/README.md)
và [manifest cài runtime/test](../../reports/v4/project_dot_schedule_promotion_20260910/before_after_manifest.json)
ghi phạm vi kiểm chứng; `metadata_manifest.json` bên cạnh ghi cập nhật tài liệu.
Lợi ích whole-program dưới 1%, không phải giảm một nửa cycle. Step3 vẫn hoãn;
không có claim synth/impl, timing/PPA hoặc quality ứng dụng held-out.

Nguồn đã chọn và đã kiểm chứng; việc cài nguồn được ghi tại
[manifest operand flow](D:/vivado_pj/reports/v4/operand_flow_promotion_20260910/before_after_manifest.json)
và [báo cáo cuối](D:/vivado_pj/reports/v4/operand_flow_final_20260910/). Xem
[OPERAND_FLOW_ROUND.md](architecture/OPERAND_FLOW_ROUND.md) cho thứ tự bước,
rounding và evidence. Không có claim PPA, timing, resource, synth/impl,
bitstream hay AXI/MMIO/CPU interface.

Việc chọn cờ không tự là evidence RTL hay quality/fixed8 qualification.

Ngưỡng chung 1 được chọn sau khảo sát 1/4/8 ở M32/N64/K8 và M64/N256/K8; không phải ngưỡng tối ưu cho mọi bài toán. `streamed` và `view` có evidence nguồn đã đóng băng. [Báo cáo cuối](../../reports/v4/context_stream_final_20260910/README.md) ghi cả các đánh đổi OMP/GOMP và quality FAIL của fixture. [Manifest cài đặt context-stream lịch sử](../../reports/v4/context_stream_promotion_20260910/before_after_manifest.json) ghi snapshot context-stream trước đó. Không có claim board/PPA/timing/bit-lock.

## Historical project organization

Điểm vào duy nhất ở root là [V4.md](../../V4.md); trang đọc chính là
[README.md](README.md). Giữ namespace `*/v4` trong repo hiện tại, không di chuyển
v2/v3 hoặc sửa các flow đang chạy của chúng. Chưa tạo một Vivado project chứa
module rỗng để biểu diễn tiến độ.

```text
V4.md                           entry point
config/
  v4_design.json                target, capacities, design choices, open gates
  v4_modules.json               module names, ownership, paths, hierarchy
  v4_stream_interface.json      revision-one streaming program/context ABI
docs/v4/
  README.md                     read order
  ARCHITECTURE_SPEC.md          system decisions and tradeoffs
  architecture/
    ZCU106.md                   board integration, memory budget, plain-language walkthrough
    BASELINE.md                 selected LFSR/cache/32-PE/LSQR architecture
    NUMERIC_CONTRACT.md         normalization exponent, input D, stored solution X and LS stop
    MATRIX.md                   matrix artifact and data contract
    SOLVER.md                   LS mathematical/numeric/resource contract
    CONTEXT.md                  candidate binary context format and limits
    MODULES.md                  generated module catalog
    STREAM_RTL_CONTRACT.md       first streaming slice: ABI, credits, RAM and exact arithmetic
  diagrams/
    *.mmd                       editable diagram sources
    README.md                   generated diagram gallery
  STATUS.md                     executed evidence and unimplemented work
  ...                           numerical/benchmark/algorithm/prior-art studies
models/v4/                      arithmetic and algorithm semantics
  normalization.py              per-job power-of-two scale, before input quantization
  lfsr_operator.py              selected generator recurrence and coordinate oracle
  lsqr.py                       integer LSQR with explicit solution storage format
compiler/v4/
  matrix_image.py               host-side matrix packaging
  mapping.py                    resident GEMV schedule and replay
  context_image.py              candidate binary packer/validator
  resident_program.py           executable bounded R1/R4 GEMV images
  solver_program.py             84-instruction LSQR service program, padded to 256 words
  stream_program.py             first-slice CALL/HALT + independent PE templates; separate ABI
rtl/v4/                         implemented functional modules, see files.f/catalog
verification/v4/                permanent SV testbenches and independent Python oracles
scripts/v4/                     reproducible checks and studies
  run_rtl.py                    unified Vivado-only correctness gate
  run_stream_rtl.py             focused streaming acceptance; separate source-bound report
  xsim.py                       shared xvlog/xelab/xsim backend and command provenance
reports/v4/                     reviewed run artifacts + manifests
work/v4/                        disposable tool output and exploratory runs
```

## Quy tắc giữ project dễ hiểu

- Tên module nói chức năng: `context_sequencer`, `support_gather`, `pe_tile`.
  Không đặt tên theo milestone M4/M8/M13, thuật toán hoặc một đợt sửa timing.
- Một state có một owner. LS sở hữu state thông qua program/buffer descriptors;
  không có thêm một controller với bản sao riêng của x/support/residual.
- `models` định nghĩa phép tính; `compiler` chọn placement/ports/lệnh; `rtl`
  thực thi lệnh; `verification` so sánh. Không cho RTL tự định nghĩa lại golden.
- Matrix image và context image là artifact khác nhau, có manifest riêng.
  Phi/A/basis, numeric format, shape và generation/hash phải đi cùng dữ liệu.
- `config/v4_modules.json` là nguồn tên/path/hierarchy. MODULES.md được sinh từ
  JSON; không chỉnh hai bản bằng tay.
- `.mmd` là nguồn sơ đồ. Gallery được sinh và kiểm drift; thêm module/đổi interface
  phải sửa catalog/contract và sơ đồ tương ứng trong cùng thay đổi.
- Contract chuyên đề làm authority cho chi tiết matrix/solver/ISA. System spec
  liên kết tới chúng; không giữ nhiều bảng bit-field cùng tuyên bố authoritative.
- Report phải ghi model/source hash và phạm vi. Không dùng tên PASS hoặc số test
  cũ để đại diện cho source đã thay đổi. Calibration không phải RTL sign-off.
- RTL testbench nằm tại `verification/v4/<group>/`, Python driver/oracle ở
  `verification/v4/test_*_rtl.py`. `rtl/v4/files.f` chỉ liệt kê modules đã
  implement; không thêm stub vào build.

## Lệnh hằng ngày

Tên `v4` chỉ nằm ở thư mục/version. Tên module mô tả chức năng; macro và
include guard dùng `CSR_`. Catalog và lệnh `project.py check` kiểm quy tắc này.
Đường LSQR mới nằm trong [LSQR_INTEGRATION.md](architecture/LSQR_INTEGRATION.md)
và [lsqr.mmd](diagrams/lsqr.mmd). `resident_engine` được giữ làm reference riêng.

```powershell
py -3 scripts/v4/project.py generate
py -3 scripts/v4/project.py check
py -3 scripts/v4/run_rtl.py --test-timeout 7200
py -3 -m compiler.v4.solver_program --output reports/v4/lsqr_program
py -3 scripts/v4/board_budget.py --output reports/v4/board_budget.json
py -3 scripts/v4/matrix_dma_study.py
py -3 -m compiler.v4.single_matrix --output reports/v4/single_matrix_study.json
py -3 scripts/v4/single_matrix_validation.py
py -3 -m compiler.v4.matrix_image --coefficient-frac 16 --output reports/v4/matrix_example
py -3 -m compiler.v4.context_image --reduction-lanes 1 --output reports/v4/context_r1
py -3 -m compiler.v4.context_image --reduction-lanes 4 --output reports/v4/context_r4
py -3 scripts/v4/solver_study.py --output reports/v4/solver_study.json
```

Xem [CONTEXT.md](architecture/CONTEXT.md) cho export/import context candidate.
Chương trình LSQR dùng service ISA riêng. Lệnh `solver_program` xuất
`program.hex` để nạp, `program.txt` để đọc từng lệnh và `program.json` ghi
labels, trường giải mã và hashes. Image có 256 word 128-bit; phần sau 84 lệnh
được điền FAIL. Không nạp image này vào loader tile64/control256.
Image đóng gói thành công chưa có nghĩa đã chạy đúng program trên PE. Trước
RTL, cần context interpreter/trace equivalence và kernel coverage đầy đủ.

Lát streaming đầu tiên có [contract](architecture/STREAM_RTL_CONTRACT.md),
[sơ đồ](diagrams/stream.mmd) và [image ví dụ](../../reports/v4/stream_program_example/README.md).
`stream_engine` được elaborate riêng, gồm đúng hai `stream_array` với tổng
32 `stream_pe`. Các array LSQR/reference không nằm thêm trong top này.
Program128/context64 của streaming không tương thích service128 hoặc tile64
chỉ vì cùng số bit. Dùng compiler và loader đúng revision.

Nếu Python launcher `py -3` không tìm thấy interpreter trên máy hiện tại,
dùng runtime đang có (Vivado vẫn là backend RTL):

```powershell
$streamPython = 'C:\Users\gbmhi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $streamPython scripts/v4/generate_stream_interface.py --check
& $streamPython scripts/v4/project.py check
& $streamPython scripts/v4/run_stream_rtl.py
```

Khảo sát numerical LFSR có lệnh riêng; dùng output directory mới để giữ evidence
cũ cùng source hashes:

```powershell
py -3 scripts/v4/lfsr_numeric_contract_study.py --configs norm_D18_S27F22_X24_t5 --output work/v4/lfsr_calibration.json
py -3 scripts/v4/lfsr_numeric_contract_study.py --split matrix_validation --configs norm_D18_S27F22_X24_t5 --output work/v4/lfsr_matrix_validation.json
py -3 scripts/v4/lfsr_outer_contract_study.py --state-width 27 --state-frac 22 --solution-width 24 --solution-frac 20 --ls-normal-rtol 1e-5 --output work/v4/lfsr_outer.json
```

`matrix_validation` dùng seed khác calibration, chưa là application held-out.
Script exit0 nghĩa hoàn tất khảo sát; đọc numerical/quality gates và mọi failure.

Khảo sát chất lượng ứng dụng SNR≥20 dB có ba lớp riêng. `application_tuning`
chỉnh policy trên DCT/synthetic giữ measurement cũ; `basis_feasibility` kiểm
đổi basis có kiểm soát; `wavelet_tuning` chọn một policy dùng chung cho mỗi
domain/algorithm trên db4 ECG và Haar camera. Sau đó mới chạy fixed trên các
policy đã chọn. Mọi ca float thất bại vẫn nằm trong report, không biến mất khỏi
denominator khi chỉ các policy đạt được chuyển sang fixed.

```powershell
py -3 scripts/v4/lfsr_application_tuning.py --output work/v4/application_float.json
py -3 scripts/v4/lfsr_basis_feasibility.py --output work/v4/basis_float.json
py -3 scripts/v4/lfsr_wavelet_tuning.py --output work/v4/wavelet_float.json
py -3 scripts/v4/lfsr_application_fixed_validation.py --float-report work/v4/application_float.json --domains synthetic --accelerated --output work/v4/synthetic_fixed.json
py -3 scripts/v4/lfsr_application_fixed_validation.py --float-report work/v4/wavelet_float.json --accelerated --output work/v4/wavelet_fixed.json
```

`--accelerated` chỉ tăng tốc model arithmetic với guard số nguyên và fallback
arbitrary precision, đã kiểm tương đương reference; không đổi thuật toán/bit
hoặc dự báo tốc độ FPGA. Có thể bỏ cờ để chạy reference. Các study có source
hashes phải chạy với source/config giữ nguyên tới khi hoàn tất; archive đúng
source bằng `scripts/v4/archive_numeric_sources.py` trước khi sửa code.
Xem [profile ứng dụng](architecture/APPLICATION_PROFILES.md) để hiểu ranh giới
encoder, biến đổi host, mean/scale và SNR full/centered.

## Triển khai và kiểm RTL

Kiểm thử RTL chỉ dùng **Vivado xsim**, qua `xvlog`, `xelab`, `xsim`; không dùng
Icarus/vvp hoặc Verilator cho acceptance hiện hành. Python vẫn sinh dữ liệu và
đối chiếu golden. Các báo cáo simulator trước đó giữ làm bằng chứng lịch sử.
`run_rtl.py` chạy discovery toàn bộ model/RTL tests một lần, kiểm generated
definitions và project, lưu command/log/source hashes tại
[RTL_CORRECTNESS.md](../../reports/v4/RTL_CORRECTNESS.md). Các runner RTL cũ là
entry point tương thích dẫn về gate này; không còn chạy simulator khác.
Mặc định tool nằm tại `C:/Xilinx/Vivado/2018.1/bin`; đặt biến `VIVADO_BIN` nếu
cài ở nơi khác. File `.xsim.json` mô tả snapshot Vivado; không phải RTL output.

Yêu cầu hiện hành: Astra Ultra điều phối; agent Astra Medium viết code.
Kiểm tra RTL và TB đã có trước, giữ nguyên phần đạt rồi triển khai phần thiếu.
Quy tắc nằm trong [rtl/v4/AGENTS.md](../../rtl/v4/AGENTS.md). Agent điều phối
chốt architecture, chia phạm vi sở hữu và review tích hợp, giữ source/profile/ABI
nhất quán. Agent viết code dùng bản sao làm việc riêng; chỉ tích hợp các file
đã review, không ghi đè toàn bộ workspace hoặc sửa v3.

Thứ tự dự kiến: arithmetic/PE → router + memory ports → context fetch/issue →
GEMV + writeback → scalar/selection/gather → solver microprograms →11 algorithm
programs → host integration. Mỗi bước phải có correctness evidence trước bước sau;
synth/impl chỉ mở khi các gate correctness yêu cầu đã đạt.
