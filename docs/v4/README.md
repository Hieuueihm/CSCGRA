# CSR v4

## Wrapper AXI-Lite và register map

Top `csr_top` đã có source nối MMIO với native recovery engine; xem
[CPU status](architecture/CPU_INTERFACE_STATUS.md),
[register map](architecture/AXI_REGISTER_MAP.md),
[packaging](architecture/IP_PACKAGING.md) và
[báo cáo kiểm chứng riêng](../../reports/v4/axi_ip_20260910/README.md).
Chưa có DMA/AXI-HP, synth/impl hay board validation. Các ghi chú chưa có AXI
trong những đợt tối ưu bên dưới là lịch sử trước khi thêm wrapper.

## Hiện hành: context, GEMV và panel hẹp

Đợt tối ưu đã hoàn thành với Vivado XSim: 18 bài kiểm kernel ghép, các gate riêng cho sequencer/range/GEMV/panel, khảo sát 1/4/8 cột và 20 ca cuối cho đủ 10 thuật toán ở M32/N64/K8 và M64/N256/K8. Mỗi ca chạy đúng 8 vòng; raw X/R/support/status, SNR/NMSE và công việc LS được giữ nguyên. Không thuật toán nào chậm hơn baseline đầu đợt.

Chọn explicit `--qr-profile view --target-kernel-revision 7 --qr-panel-min-columns 1`; `balanced` vẫn là mặc định tương thích. Ngưỡng 1 là lựa chọn chung trong phạm vi khảo sát, có đánh đổi nhỏ cho OMP/GOMP được ghi rõ trong báo cáo.

[Báo cáo cuối](../../reports/v4/context_stream_final_20260910/README.md), [khảo sát ngưỡng](../../reports/v4/context_stream_threshold_survey_20260910/README.md), [manifest cài source](../../reports/v4/context_stream_promotion_20260910/before_after_manifest.json), [luồng thực thi](diagrams/context_stream_execution.mmd), [mapping panel](diagrams/panel_mapping.mmd).

Giữ đúng hai array 4×4 và một vector pool. Chưa có AXI/MMIO/DMA/CPU register map, synth/impl hoặc xác nhận timing/fit ZCU106. Các fixture fixed8 dưới 20 dB vẫn là quality FAIL, dù RTL khớp oracle; chưa khóa bit production hay hoàn tất dữ liệu ứng dụng held-out.

## Historical: QR append and shared support transport, 2026-09-10

Feature4 profile `reuse` passed source-clean Vivado XSim for all20 fixed-eight
cases (M32/N64/K8 and M64/N256/K8). Every algorithm runs exactly8 outer
iterations. Paired raw X/residual/support/status, logical LS/correction counters,
numeric events and diagnostic quality match the factor-panel baseline.
At M64: OMP39600, GOMP72250, CoSaMP241442, SP102871 cycles. No active algorithm
regressed in these pairs. OMP/GOMP each use1 INIT and7 EXTEND instead of8 INIT;
this reuses reflector arithmetic, not merely faster factor loading.

See [paired report](../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md),
[source-bound RTL gates](../../reports/v4/qr_reuse_rtl_20260909/qualification.json),
and [source installation](../../reports/v4/qr_reuse_promotion_20260910/before_after_manifest.json).
Fixed8 SNR below20dB remains a quality failure even when RTL matches the model.
ADMM is historical reference-only. Production bits, synth/impl, timing and board
qualification remain open. CPU AXI/register integration is not implemented;
see [CPU status](architecture/CPU_INTERFACE_STATUS.md).

Block remapping, compact loaded panel continuation and direct scalar vector
updates are separate in-progress candidates. They are not qualified by this
report. The compatibility default remains `balanced`; use
`--qr-profile reuse --target-kernel-revision 4` explicitly.

V4 được thiết kế lại từ đầu theo thứ tự **kiến trúc rõ → numerical/correctness →
RTL correctness → synth → impl**. V3 và paper CSR là đầu vào tham khảo; không
chép các kết quả cũ thành trạng thái v4.

## Factor-panel active-10 fixed-eight evidence

The staged revision3 factor-panel QR candidate completed source-clean Vivado
xsim PASS for all 20 active-10 fixed-eight cases: M32/N64/K8 and M64/N256/K8,
with common raw Phi/Y within each geometry and actual outer count eight. Raw
X, residual, support, status and fixed8 diagnostic quality match the paired
baseline exactly. CoSaMP is 252,684 cycles at M64/N256/K8 and 210,512 cycles
at M32/N64/K8, a 41.48% reduction at each matched boundary. See the final
[comparison](../../reports/v4/factor_panel_comparison_20260909/factor_panel_comparison_vi.md)
and focused [RTL qualification](../../reports/v4/factor_panel_rtl_20260909/qualification.json).

The active policy remains eight greedy/hard-threshold programs plus FISTA and
PDHG. ADMM is historical reference-only and its round-two quality job remains
`STOPPED_BY_SCOPE`. Source installation is tracked in
[`factor_panel_promotion_20260909`](../../reports/v4/factor_panel_promotion_20260909/before_after_manifest.json);
the evidence does not qualify an application, synth/impl, timing, resources,
fit, board deployment or a production bit lock. Panel generation remains
explicit opt-in: `--qr-profile panel --target-kernel-revision 3`; the default
compatibility profile remains `balanced`.

**Ưu tiên 2026-09-09:** [kiến trúc dùng chung cho cả bộ thuật toán](architecture/STREAMING_REDESIGN.md)
đã có lát RTL streaming đầu tiên: nạp program/template, RAM vector ghép bank
và đúng hai array 4×4. Đọc [contract](architecture/STREAM_RTL_CONTRACT.md),
[sơ đồ](diagrams/stream.mmd), [image ví dụ](../../reports/v4/stream_program_example/README.md)
và [gate Vivado riêng](../../reports/v4/STREAM_RTL_CORRECTNESS.md).
Lượt regression LSQR trước đó đã dừng; gate streaming không thay thế nó.

[Numeric contract mới](architecture/NUMERIC_CONTRACT.md) giải thích chuẩn hóa
theo lũy thừa hai, tách input D khỏi nghiệm X và kiểm điều kiện dừng sau lưu X.
[Profile ECG/db4 và ảnh/Haar](architecture/APPLICATION_PROFILES.md) giải thích
measurement theo miền hệ số, hai lớp chuẩn hóa và đường khôi phục tín hiệu gốc.

**Bắt đầu bằng [STREAM_SYSTEM_CONTRACT.md](architecture/STREAM_SYSTEM_CONTRACT.md)
và [QR_SOLVER.md](architecture/QR_SOLVER.md): LFSR32/cache dấu cùng hai array
4x4 (32 PE) phục vụ active-10 qua program/context nạp được.**
[BASELINE.md](architecture/BASELINE.md) ghi LSQR historical reference và
provenance LFSR/cache, không phải khuyến nghị solver hiện hành. Threefry2x32-20
được giữ làm reference/ablation; độ rộng bit vẫn chưa freeze.
Xem [kết quả ứng dụng mới: SNR≥20 dB](../../reports/v4/LFSR_APPLICATION_TUNING.md):
65/65 ca fixed được chọn đạt trên grid77 ca; còn12 ca ECG chưa được xác nhận.
[Khảo sát LFSR, normalization và nghiệm X trước đó](../../reports/v4/LFSR_NUMERICAL_CONTRACT.md)
giữ nguyên provenance.
[Khảo sát Threefry trước đó](../../reports/v4/GENERATED_NUMERICAL_SUMMARY.md)
và [paper về Threefry](architecture/THREEFRY_PRIOR_ART.md) giữ làm tài liệu tham khảo.

Đọc [ARCHITECTURE_SPEC.md](ARCHITECTURE_SPEC.md) để hiểu các quyết định
phần cứng, mapping 32 PE, bandwidth, bottlenecks và cách kiểm chứng novelty.
Luồng tích hợp mới nối bộ dựng B, scalar RF/DIV/SQRT và các kernel trên đúng
32 PE để chạy LSQR, kiểm certificate trên X24 rồi commit kết quả. Gate chung
cho source mới chưa hoàn tất; xem [trạng thái hiện hành](STATUS.md),
[sơ đồ LSQR](diagrams/lsqr.mmd) và [evidence Vivado](../../reports/v4/RTL_CORRECTNESS.md).
Backend resident GEMV cũ giữ làm reference riêng. Bản audit 210 tests trước đó
chỉ áp dụng cho snapshot đã lưu, không tự xác nhận các source mới.
Các báo cáo simulator cũ giữ làm lịch sử; không thay thế gate hiện hành.

Muốn bắt đầu từ ý tưởng dễ hiểu: [V4 chạy trên ZCU106 thế nào?](architecture/ZCU106.md)
giải thích measurement matrix, LS solver, luồng PS/DDR/PE và ngân sách BRAM.

**Tài liệu khảo sát dẫn tới quyết định trên:** [operator tự sinh và cache dấu](architecture/GENERATED_OPERATOR.md)
khi mô hình đo cho phép, dựa trên [audit generator v2/v3](architecture/GENERATED_MATRIX_AUDIT.md).
Với operator tổng quát, so [dense một-copy và DMA/throughput](architecture/MATRIX_TRADEOFF.md).
[LS chọn theo PE + accuracy](architecture/LS_SOLVER_DECISION.md). Hai-copy/CGLS
đang là reference chạy được. Generated operator, một-copy và LSQR đã có model
software; phạm vi RTL đã kiểm và phần tích hợp/transform còn thiếu được ghi ở
[STATUS.md](STATUS.md).
Khảo sát LFSR đã mở rộng sang ECG/db4 và camera/Haar, kiểm583 LS trên support
thực. [Đánh giá lại DCT cũ](../../reports/v4/LFSR_SNR20_REASSESSMENT.md) vẫn là
evidence lịch sử. Dữ liệu held-out, transform/context và phạm vi deployment
vẫn chưa đủ để khóa bit production.

| Thứ tự đọc | Nội dung |
|---|---|
| 1. [MATRIX.md](architecture/MATRIX.md) | Phân biệt Phi/Psi/A; quantize một lần, bank A/Aᵀ, support gather |
| 2. [SOLVER.md](architecture/SOLVER.md) | CGLS/shifted-CG, oracle QR/SVD, sai số, chi phí và failure policy |
| 3. [CONTEXT.md](architecture/CONTEXT.md) | 32 context slots, candidate ISA, pack/load và giới hạn kiểm chứng |
| 4. [MODULES.md](architecture/MODULES.md) | Tên module, hierarchy, state ownership và đường dẫn RTL dự kiến |
| 5. [Sơ đồ](diagrams/README.md) | System, matrix, solver và context; nguồn chỉnh sửa là các file `.mmd` |
| 6. [PROJECT_GUIDE.md](PROJECT_GUIDE.md) | Cấu trúc thư mục, nguồn authoritative, lệnh chạy, quy tắc triển khai |

File cấu hình: [v4_design.json](../../config/v4_design.json) và
[v4_modules.json](../../config/v4_modules.json). Catalog module và gallery sơ đồ
được sinh tự động, có lệnh kiểm tra drift và liên kết tài liệu.

| Cần hiểu gì | Tài liệu |
|---|---|
| Những gì thực sự đã làm, còn thiếu | [STATUS.md](STATUS.md) |
| Paper gốc khác v3/v4 thế nào | [PAPER_AND_V3_REVIEW.md](PAPER_AND_V3_REVIEW.md) |
| Audit source hiện tại, file/line cụ thể | [V3_ARCHITECTURE_AUDIT.md](V3_ARCHITECTURE_AUDIT.md) |
| Thêm FISTA, ADMM, PDHG; không tăng số bằng OMP variants | [ALGORITHM_EXPANSION.md](ALGORITHM_EXPANSION.md) |
| Dataset, application, operator, splits, fairness | [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md) |
| Chọn D/C/S/ACC, quality và solver certificates | [NUMERICAL_PROTOCOL.md](NUMERICAL_PROTOCOL.md) |
| Prior art và điều kiện để claim novelty | [NOVELTY_POSITIONING.md](NOVELTY_POSITIONING.md) |
| Screen nhỏ đã chạy, cả PASS và FAIL | [CALIBRATION_SUMMARY.md](../../reports/v4/CALIBRATION_SUMMARY.md) |

Code chạy được hiện tại:

- [fixed.py](../../models/v4/fixed.py): arithmetic raw integer, round/saturate/events.
- [generated_operator.py](../../models/v4/generated_operator.py): Threefry2x32-20
  reference/ablation, cache dấu 8 bank, A/Aᵀ/support và raw integer checks cho Psi=I.
- [lfsr_operator.py](../../models/v4/lfsr_operator.py): generator baseline LFSR32
  recurrence v2, taps `0x80200003`, seed zero→`DEADBEEF`, LSB-then-step và
  column-major `col*M+row`; indexed jump-ahead chỉ là model kiểm tái lập.
- [normalization.py](../../models/v4/normalization.py): chuẩn hóa measurement
  trước D bằng lũy thừa hai, lưu exponent và hoàn nguyên đầu ra tại host.
- [lsqr.py](../../models/v4/lsqr.py): LSQR integer, scalar norm/DIV/SQRT,
  certificate sau lưu X (mặc định D) và thống kê kernel; oracle độc lập cho LSQR RTL.
- [recovery.py](../../models/v4/recovery.py):8 greedy/hard-threshold programs, float và integer kernels.
- [proximal.py](../../models/v4/proximal.py):FISTA, ADMM-LASSO, PDHG-LASSO; cùng objective, ba strategy.
- [mapping.py](../../compiler/v4/mapping.py):resident GEMV schedule R1/R4, bank layout,
  synchronous reads và registered-route integer replay. Đây chưa là full compiler.
- [matrix_image.py](../../compiler/v4/matrix_image.py): đóng gói/import hai orientation
  từ cùng raw matrix; kiểm signed width, tail, transpose, hash và source metadata.
- [single_matrix.py](../../compiler/v4/single_matrix.py): model dense một-copy,
  chứng minh truy cập bank và replay integer; B cache/reader RTL hiện dùng cùng
  layout được mô tả trong memory/resident contracts.
- [context_image.py](../../compiler/v4/context_image.py): candidate ISA packer,
  disassembly và validator; template R1/R4 chưa có execution equivalence.
- [resident_program.py](../../compiler/v4/resident_program.py): image GEMV R1/R4
  riêng với 7/12 rows, nạp qua loader rồi chạy PC/ADDRESS và 32 PE thật.
- [solver_study.py](../../scripts/v4/solver_study.py): isolation study với oracle
  SVD/QR, conditioning và certificate sau khi lưu nghiệm ở D precision.
- [generated_numeric_study.py](../../scripts/v4/generated_numeric_study.py): sweep
  CGLS/LSQR, fixed-vs-float 11 programs và cửa sổ application; giữ mọi failure.
- [verification/v4](../../verification/v4):oracle, analytic solutions, quality và mapping tests.

Chạy kiểm tra từ repository root (`py -3` trên máy này dùng Python có NumPy):

```powershell
py -3 scripts/v4/run_rtl.py --test-timeout 7200
py -3 scripts/v4/project.py check
py -3 -m compiler.v4.mapping --rows 128 --columns 8 --output reports/v4/support8_schedule.json
py -3 scripts/v4/numeric_screen.py --suite applications --output reports/v4/numeric_screen.json
```

The source-bound native recovery core is now promoted under the guarded
[core-promotion manifest](../../reports/v4/unified_core_promotion_20260909/before_after_manifest.json).
It is not a frozen numeric profile, synthesis/implementation result, application
qualification, or board sign-off. A screen PASS does not replace those gates.
Follow the current [RTL instructions](../../rtl/v4/AGENTS.md): Astra Ultra
coordinates and reviews; GPT-5.6 Terra high implements code while preserving
qualified RTL/TB behavior.

## Fixed-eight reporting and staged optimization evidence

The primary optimization report accepts a cross-algorithm cycle row only when
all eleven programs share M/N/K and raw Phi/Y digests within a geometry and
each recorded **actual** outer count is eight. Its table records original
benchmark policy, actual support, maximum QR support, physical `FACTOR_INIT`,
logical LS requests, total inner CG steps, fixed SNR, and status. Equal outer
counts do not make internal work equal: SP has an initial solve, GOMP may hold
16 entries at K=8, and ADMM owns inner CG work.

Quality-policy results remain a separate validation table. They have different
termination policies and iteration counts and are not cycle-ranked. The FISTA
component in `quality_htp_fista_m64_20260909` is valid component evidence,
while its parent invocation stays FAIL because the HTP harness call raised a
TypeError; use `quality_htp_m64_20260909` for the corrected HTP gate. PDHG is
reported only from its completed source-clean gate. ADMM64 numerical held-out
policy validation passed. Its separate [native RTL gate](../../reports/v4/quality_admm64_m64_20260909/summary.json)
now passes one original M64/N256 planted fixture: 64 actual outer iterations,
4,520,495 accepted START-to-DONE cycles, fixed/float SNR 35.3712/35.3699 dB,
NMSE ratio 0.999698, and zero numeric events. Its 956 trace-summed inner-CG
commits and single-fixture scope are quality evidence, not a cross-policy cycle
ranking, application qualification, PPA result, or production bit lock.

The promoted compute changes keep the existing two 4x4 arrays (32 PE): terminal
ACC folding uses existing PEACC and fixed registered reduction links, scalar
opcode16 uses lane0 without RAM, and compiler-emitted QR reuse keys exact
ordered support before it reuses certified program/vector-pool state. See the
[scalar-template contract](architecture/SCALAR_TEMPLATE.md).
These statements make no new array, full-mesh, area, Fmax, timing, or
production-bit-lock claim.

Legacy V2/V3 values remain references in `reports/v4/K8_COMPARISON.md` and
`reports/v4/k8_legacy_configuration_20260909.md`. Their Phi/data, solvers,
iteration behavior, numeric formats, and counting boundaries differ, so raw
ratios are not fair speedups and do not appear in the primary table.
