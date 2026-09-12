# V4 — trạng thái bằng chứng

## 2026-09-12: B-cache read — giảm LUT, có đánh đổi timing/runtime

Đã cài cửa sổ đọc B-cache dùng chung trong `factor_panel_service`, không
đổi 96 word lưu trữ, cache write, PE, rounding, protocol hoặc cycle.
RTL SHA-256: `f6d1194196817c263541edb438e60aacedc63e4c9fafdb56a35d0922d3e6c236`.

OOC cùng cấu hình: LUT **63,880 → 57,470 (-10.03%)**, FF **17,078 → 17,091**.
WNS nội bộ **+2.767 → +2.004 ns**, TNS 0. **Synth chậm hơn trong lần đo này:
22:41 → 35:16**. Giữ ứng viên vì giảm area và không đổi cycle; không gọi
đây là cải thiện timing hoặc tốc độ synth. Baseline trước vẫn được lưu.

18 test XSim, 40/40 replay đủ 8 vòng và 18 test compiler/parser PASS.
Calibration 16 shape đo lại không đổi cycle; source/profile đã kiểm hash.
Xem `reports/v4/panel_bcache_20260912/README.md`. **Chưa có kết quả full-top,
implementation hoặc routed timing cho source mới.**

## 2026-09-12: panel mux — bit-exact và OOC hoàn tất

Đã cài ứng viên 2 của `factor_panel_service`: thay chọn slice động bằng
rotation tổ hợp dùng chung cho response, write và cache fill. Không thêm
PE/pipeline, không đổi rounding, protocol hay cycle. SHA-256 RTL:
`0f86b866d33d21fe8e711b0d555d877b082e66ca2e89d65e296e1258c9c73df7`.

Riêng panel OOC, cùng Vivado 2018.1/default/10 ns: LUT **474,749 → 63,880**,
FF **17,023 → 17,078**, RAMB/DSP vẫn 0; synth_design **94:05 → 22:41**.
WNS nội bộ OOC **+2.443 → +2.767 ns**, TNS 0; chưa phải routed timing/Fmax.

17 test XSim, 40/40 replay đủ mười thuật toán/two geometries/K8/actual8/
PIO-DMA và 18 test compiler/parser PASS; toàn bộ trace/cycle bucket khớp.
Calibration 16 shape đã đo lại, cycle giữ nguyên rồi mới cập nhật hash.
Ứng viên 1 bị dừng OOC chủ động, không có số physical cuối; không gọi FAIL.

**Chưa có kết quả full-top hoặc implementation cho source mới.** Xem
`reports/v4/panel_mux_20260912/README.md` và
`docs/v4/architecture/PANEL_LANE_ROTATION.md` để phân biệt bằng chứng cuối
với các lần thử trung gian và các mục lịch sử bên dưới.

## 2026-09-11: sửa slice DOT — bit-exact PASS, physical chưa xác nhận

`factor_panel_service` dùng mapping generate-time R1/R4 cho cả ba nơi đọc
DOT output, tránh sinh part-select ngoài bus 32 lane. Không đổi arithmetic,
rounding, pipeline, PE hay interconnect/mesh. 40 replay XSim đủ mười thuật
toán, hai kích thước, K8/actual8, PIO/DMA khớp từng byte với trace trước sửa;
tất cả cycle bucket giữ nguyên. Tám focused XSim test, hai calibration XSim
test và 18 compiler/parser test PASS. Calibration được đo lại rồi mới cập nhật.

Physical run mới không lặp lại lỗi slice trong log đã thu, nhưng chưa tạo
checkpoint/report cuối. Agent dừng run sau hơn một giờ không có log mới;
trạng thái `ABORTED_NO_LOG_PROGRESS`, không phải synth/impl PASS. Cảnh báo
RAM-to-register vẫn còn; chưa có PPA/timing mới. Xem
[bằng chứng](../../reports/v4/factor_panel_slice_fix_20260911/README.md) và
[giải thích sửa lỗi](architecture/FACTOR_PANEL_SLICE_FIX.md).

## AXI-Lite wrapper và registers — RTL gate PASS

`csr_top` nối AXI-Lite 32-bit/4 KiB với `host_command_bridge` và một `recovery_engine`.
Nạp image/Phi/vector, START/CANCEL, DONE/IRQ và đọc X/support đều qua MMIO.
Native regression PASS 3 tests; real-core AXI smoke PASS 379 assertions;
76 source/header/runner hashes khớp, 55 file RTL core cũ không đổi.
[Báo cáo](../../reports/v4/axi_ip_20260910/README.md),
[register map](architecture/AXI_REGISTER_MAP.md) và
[CPU status](architecture/CPU_INTERFACE_STATUS.md). Packaging có gate riêng;
không suy từ RTL PASS thành IP integrity hoặc board PASS. Chưa có DMA/AXI-HP,
synth/impl, timing/PPA hay bitstream.

## Step2: PROJECT_DOT R4 split — source-qualified, installed

Đã cài lịch DOT chia 9–16 cột thành 8 + phần còn lại khi có ít nhất 24 hàng,
với `PROJECT_DOT_SPLIT_ENABLE=1` và `PROJECT_DOT_SPLIT_MIN_ROWS=24`.
Các shape khác giữ lịch cũ; không đổi image, config, điểm làm tròn hay 32 PE.
Manifest [runtime/test](../../reports/v4/project_dot_schedule_promotion_20260910/before_after_manifest.json)
ghi hash trước/sau và V2/V3 không đổi; cập nhật tài liệu được ghi riêng trong
`metadata_manifest.json` cùng thư mục.

Finalization đã kiểm archive focused mới có đủ bảy record riêng biệt, gắn với
7 test XSim PASS của g13e (1114.280 s). Hai strict pair active10 M32/N64/K8 và
M64/N256/K8 giữ actual outer=8, raw X/R/support/status, quality và công việc QR.
CoSaMP giảm 132671→132429 và 158527→157106 cycle; SP giảm 45051→44897 và
64158→63556; tám thuật toán còn lại không đổi. Đây là lợi ích dưới 1%.

Xem [contract](architecture/PROJECT_DOT_SCHEDULE.md) và
[bảng đầy đủ](../../reports/v4/project_dot_final_20260910/README.md).
Step1 vẫn opt-in feature10, `balanced` vẫn là default; Step3 chưa triển khai.
Các quality fixture vốn dưới 20 dB vẫn FAIL; chưa synth/impl, timing/PPA hay board.

## Step1: FACTOR_ENERGY_TAP — source-qualified, installed

Step1 thêm `FACTOR_ENERGY_TAP` (opcode 25, feature 10) như một opt-in cho QR
`view`. Lệnh trả full tap factor chưa patch, raw ACC64 của tổng bình phương và
cờ tail-nonzero; compiler giữ beta/tau, NORMALIZE, factor write, QTy,
backsolve, certificate stored-X và refinement theo thứ tự cũ. Nó không thêm PE,
RAM public, controller QR hay thay đổi policy/vòng lặp.

Kích hoạt explicit của source-qualified closure:

```powershell
& $streamPython scripts/v4/export_recovery.py input.json work/v4/energy_program --qr-profile view --qr-panel-min-columns 1 --factor-energy-tap --target-kernel-revision 10
```

`balanced` vẫn là default tương thích. Evidence cuối tại
[`factor_energy_tap_final_20260910`](../../reports/v4/factor_energy_tap_final_20260910/README.md)
ghi các strict pair active-10 với outer=8 cho M32/N64/K8 và M64/N256/K8. Trạng
thái cài source được ghi tại promotion manifest cùng tên; chưa có claim PPA,
timing, synthesis, board hay production bitstream. Contract là
[FACTOR_ENERGY_TAP.md](architecture/FACTOR_ENERGY_TAP.md). Step2/3 không thuộc đợt này.

## Nguồn operand flow đã chọn và kiểm chứng

Bước 1 chọn R1/R4 theo shape đã đo và giữ fallback schedule; bước 2
`ROUNDED_AFFINE` giữ round product trước ADD/SUB; bước 3
`FACTOR_RANGE_TEMPLATE` ghép public range với factor private và trả raw ACC64/tap.
Bước 4 bitmap 32-bit cho TOPK sắp xếp/UNION không thứ tự đã source-qualified và
được chọn, với `BITMAP_ENUM_ENABLE` mặc định bật. Bước 5 tái dùng RANK slot sau
write ACK đã được đo nhưng bị loại: hai strict pair M32/M64 đều delta đúng 0
cycle, nên `ACK_SLOT_RECYCLE` không nằm trong runtime.

Kích hoạt image hiện chọn explicit `--operand-chains --factor-range-template`
với kernel revision 9. Evidence: [mapping](D:/vivado_pj/reports/v4/operand_flow_mapping_20260910/),
[affine](D:/vivado_pj/reports/v4/operand_flow_affine_comparison_20260910/),
[factor range](D:/vivado_pj/reports/v4/operand_flow_factor_range_comparison_20260910/),
[bitmap](D:/vivado_pj/reports/v4/operand_flow_bitmap_comparison_20260910/), và
[slot experiment M32](D:/vivado_pj/reports/v4/operand_flow_slot_experiment_m32_20260910/)
/[M64](D:/vivado_pj/reports/v4/operand_flow_slot_experiment_m64_20260910/).

Nguồn đã chọn và đã kiểm chứng; việc cài nguồn được ghi tại
[manifest operand flow](D:/vivado_pj/reports/v4/operand_flow_promotion_20260910/before_after_manifest.json)
và [báo cáo cuối](D:/vivado_pj/reports/v4/operand_flow_final_20260910/). Không có claim
PPA, timing, resource, synth/impl, bitstream hay AXI/MMIO/CPU interface.

## Lịch sử: context, GEMV và panel hẹp (trước operand flow)

Đợt tối ưu đã hoàn thành với Vivado XSim: 18 bài kiểm kernel ghép, các gate riêng cho sequencer/range/GEMV/panel, khảo sát 1/4/8 cột và 20 ca cuối cho đủ 10 thuật toán ở M32/N64/K8 và M64/N256/K8. Mỗi ca chạy đúng 8 vòng; raw X/R/support/status, SNR/NMSE và công việc LS được giữ nguyên. Không thuật toán nào chậm hơn baseline đầu đợt.

Chọn explicit `--qr-profile view --target-kernel-revision 7 --qr-panel-min-columns 1`; `balanced` vẫn là mặc định tương thích. Ngưỡng 1 là lựa chọn chung trong phạm vi khảo sát, có đánh đổi nhỏ cho OMP/GOMP được ghi rõ trong báo cáo.

[Báo cáo cuối](../../reports/v4/context_stream_final_20260910/README.md), [khảo sát ngưỡng](../../reports/v4/context_stream_threshold_survey_20260910/README.md), [manifest cài source](../../reports/v4/context_stream_promotion_20260910/before_after_manifest.json), [luồng thực thi](diagrams/context_stream_execution.mmd), [mapping panel](diagrams/panel_mapping.mmd).

Giữ đúng hai array 4×4 và một vector pool. Chưa có AXI/MMIO/DMA/CPU register map, synth/impl hoặc xác nhận timing/fit ZCU106. Các fixture fixed8 dưới 20 dB vẫn là quality FAIL, dù RTL khớp oracle; chưa khóa bit production hay hoàn tất dữ liệu ứng dụng held-out.

## Historical: five resident QR optimizations installed

Năm bước QR resident đã cài source và có closure Vivado XSim: 17 kernel tests, 14 sequencer tests/166 cases, 2 factor-panel leaf gates, 11 support groups/156 records, cùng 40 whole-program fixed8 cases cho profile `resident` và `compact` tại M32/N64/K8 và M64/N256/K8. Validator paired giữ raw Phi/Y/X/R, support, status, actual outer=8, counters và quality diagnostic.

Kích hoạt `compact` explicit bằng `--qr-profile compact --target-kernel-revision 6`; default compatibility vẫn `balanced`. Evidence: [five-step](../../reports/v4/five_optimizations_20260910/README.md), [A/B/C](../../reports/v4/resident_chain_comparison_20260910/resident_chain_comparison_vi.md), [RTL](../../reports/v4/scalar_insert_rtl_20260910/qualification.json), [numerical](../../reports/v4/scalar_insert_numerical_20260910/archive_manifest.json), [installation](../../reports/v4/scalar_insert_promotion_20260910/before_after_manifest.json).

Target vẫn là hai 4×4 PE arrays và một shared vector pool. AXI/MMIO/DMA/CPU register map chưa có; RF32×64 là internal. Không có board/PPA/timing/bit-lock claim. Fixed8 quality là diagnostic; float SNR dưới20dB không là application-quality pass.

## Historical: factor-panel active-10 fixed-eight evidence

The staged revision3 factor-panel candidate has source-clean Vivado xsim PASS
for 20 active-10 fixed-eight cases: M32/N64/K8 and M64/N256/K8, ten algorithms
per geometry, common raw Phi/Y within a geometry, and actual outer count eight.
The paired comparison requires exact raw X, residual, support, status and
fixed8 diagnostic-quality evidence. CoSaMP measured 252,684 cycles at
M64/N256/K8 and 210,512 at M32/N64/K8, each a 41.48% matched-boundary
reduction. The guarded result is in
[`factor_panel_comparison_20260909`](../../reports/v4/factor_panel_comparison_20260909/factor_panel_comparison_vi.md),
with source archives
[`factor_panel_final_fixed8_m64_20260909`](../../reports/v4/factor_panel_final_fixed8_m64_20260909/)
and
[`factor_panel_final_matched_m32_20260909`](../../reports/v4/factor_panel_final_matched_m32_20260909/).

The focused source-bound Vivado module gate is
[`factor_panel_rtl_20260909`](../../reports/v4/factor_panel_rtl_20260909/qualification.json):
PASS13 focused kernel tests covering 155 commands, five legacy factor replays,
and 44 legacy compute replays, and cascade/panel/bridge fault coverage. The design remains exactly
two 4x4 arrays, 32 existing PEs; factor panels do not add an array, multiplier
or public factor copy.

ADMM is historical reference-only and excluded from active-10; its round-two
quality work is `STOPPED_BY_SCOPE`. The staged candidate is source-qualified. Source installation is tracked in
[`factor_panel_promotion_20260909`](../../reports/v4/factor_panel_promotion_20260909/before_after_manifest.json).
PPA, timing, synthesis/implementation, board and production-bit qualification
remain pending. Activation remains
explicit: `--qr-profile panel --target-kernel-revision 3`; the compatibility
default remains `balanced`.

## Historical round-one promoted core and prior fixed-eight integration

The guarded core promotion is recorded in
[`unified_core_promotion_20260909`](../../reports/v4/unified_core_promotion_20260909/before_after_manifest.json).
The completed source-clean fixed-eight batches are
[`fair_fixed8_m32_complete_20260909`](../../reports/v4/fair_fixed8_m32_complete_20260909/summary.json)
and
[`fair_fixed8_m64_complete_20260909`](../../reports/v4/fair_fixed8_m64_complete_20260909/summary.json),
each PASS11. The primary table rejects any row without the same M/N/K, raw
Phi/Y digest, source-clean frozen snapshot, and actual outer counter of eight.
It reports policy, published support/nonzero coefficients, QR support, logical
LS requests, measured `FACTOR_INIT`, BUILD count, CG total, SNR, and status
without equating those internal workloads.

The quality table is separate and does not rank cycles across differing
termination policies. HTP 40445 cycles/2 outer/86.10 dB, IHT 85376/24/71.62,
greedy and MP/GP validations, FISTA component 636587/256/35.63, and PDHG
646096/256/35.43333 are retained with their own scopes. The FISTA parent FAIL
remains explicit. The historical [ADMM64 native xsim archive](../../reports/v4/quality_admm64_m64_20260909/summary.json)
passes its original M64/N256 planted fixture at 64 actual outer iterations,
4,520,495 accepted START-to-DONE cycles, 35.3712 dB fixed SNR, and zero numeric
events. Its fixed-model trace sums 956 inner-CG commits. This is separate from
the six numerical training/reserved signal-support cases under the same Phi;
it does not qualify an application dataset, timing/PPA, a bit lock, or a
cross-policy cycle ranking. It is not a round-two ADMM quality PASS; that job
stopped by scope.

Architecture ablations stay in within-algorithm appendices because natural SP
stopping differs from eight outer iterations. The promoted terminal ACC,
lane0 scalar, and compiler-emitted exact ordered-support/vector-pool reuse use
existing 32-PE hardware; no PPA, Fmax, general programmable mesh, or
production-lock conclusion follows. The scalar path is specified in
[SCALAR_TEMPLATE.md](architecture/SCALAR_TEMPLATE.md).

The native ADMM archive is byte-identical to its 129-file frozen run. Frozen
ADMM helper `6d9` versus live `4fe1` changes qualification-metadata guards
only; frozen recovery helper `ff8b` versus live `cb000` adds watchdog plumbing
qualified by separate differential Vivado xsim. The core RTL lineage remains
otherwise identical. QR-heavy configurations remain above legacy references in
many configurations, and ADMM64 is costly; application qualification,
synthesis/implementation, PPA, and production bit lock remain open.

## Historical gate record

The dated gate narrative below is retained for provenance. Current promoted-core and fixed-eight evidence is the section above.

Ngày 2026-09-09. **Đã chạy 11 chương trình thuật toán bằng context nạp thật
trên RTL; mỗi top dùng đúng hai array 4×4, tổng 32 PE.**
[Gate source đóng băng mới nhất](../../reports/v4/pipeline_whole_program_comparison_20260909/README.md)
gồm 11 ca nhỏ và sáu ca MP/GP/IHT cùng kích thước mốc V2. Gate riêng kiểm
[bốn chương trình M128/N1024](../../reports/v4/pipeline_max_program_comparison_20260909/README.md).
Phạm vi từng gate được giữ riêng; đây chưa phải qualification mọi cấu hình.
**Solver đích của phần mở rộng là [QR](architecture/QR_SOLVER.md), theo yêu cầu
làm rõ mới nhất. LSQR bên dưới là reference; không dùng làm fallback ngầm.**
ZCU106 `xczu7ev-ffvc1156-2-e`, 100 MHz vẫn là mục tiêu; chưa synth/impl,
khóa bit production hoặc xác nhận board.

Ưu tiên performance mới nhất: [bám mốc cycle V2/V3 theo cùng M/N/K và số vòng](architecture/CYCLE_BASELINE_CONTRACT.md).
Ca K2 M128/N1024 vừa báo là kiểm toàn N, không cùng kích thước ca K2 V2.
Đo lại các ca cũ, giảm forward theo support thực rồi tối ưu cấp Phi/vector
dùng chung; mọi số phải gồm BUILD, scalar và result commit.
Compiler [sparse forward đã qua xsim cùng cấu hình](../../reports/v4/sparse_forward_matched_rtl_audit_20260909/README.md).
[Pipeline dùng chung](architecture/OPERATOR_PIPELINE.md) đã được đưa vào RTL
live bằng đúng 14 file đã kiểm hash; gate riêng PASS 19 tests/34 replays.
Ở M128/N1024/K2, hai vòng ngoài, MP 114310→25614, GP 164775→26985,
IHT 117522→28854 và FISTA 141783→40723 chu kỳ. Ba ca đầu bật
`sparse_forward=True`; FISTA giữ nguyên image. Tất cả khớp raw X, residual,
support và status. Cycle gồm BUILD/commit, chưa gồm preload host/Phi lạnh.
11 ca nhỏ cùng image đều nhanh hơn 5,01–11,84%; chưa đạt hết mốc V2.
[GP giữ đúng
Gradient Pursuit](architecture/GRADIENT_PURSUIT.md), không lấy GP kiểu IHT
mặc định của V2 làm ngưỡng chấp nhận.

[Bộ K=8 đầy đủ](../../reports/v4/K8_COMPARISON.md) đã PASS **23 lượt xsim**:
11 thuật toán ở M64/N256, 11 thuật toán ở M32/N64, thêm GOMP bốn vòng ở
M64/N256. Đối chiếu tám thuật toán cũ với một suite V3 nhất quán; ghi cả
số vòng thực và khác biệt cấu hình. Ba thuật toán proximal vẫn có số riêng.
M64/N256: OMP 116592, CoSaMP 900360, HTP 212818 chu kỳ cho thấy QR/range/
factor còn tốn nhiều thời gian. Tất cả ca giữ ngưỡng relative fixed/float;
MP/IHT/HTP và ba proximal chưa đạt20dB ở budget tám ngay cả float.
Gate này mở rộng QR tới support thực tối đa24; chưa chứng nhận QR full-program S96.

Ưu tiên hiện hành là [thiết kế lại đường tính dùng chung](architecture/STREAMING_REDESIGN.md):
cân bằng cả 11 thuật toán, support thực, streaming R1/R4, ghép bank B hai cổng,
workspace toàn N và so solver nhỏ. Lát streaming đầu tiên đã triển khai phần
program/context, compute và RAM vector. Live Phi/B và R1/R4 đã nối vào
`stream_kernel`; 11 chương trình recovery đã qua gate nhỏ trên datapath thật.
QR support lớn, ma trận workload đầy đủ và host integration vẫn cần kiểm tiếp.
LSQR hiện tại giữ làm reference correctness.

[Phương án PPA và novelty](architecture/PPA_OPTIMIZATION.md) bổ sung cơ chế
control/routing cục bộ, reduction cuối vector, forwarding giữ rounding và
so workspace compact/bandwidth. Mục tiêu giảm cycle toàn chương trình, tăng
margin tại cùng 100 MHz và giảm tài nguyên được đo riêng; correctness vẫn là
gate trước synth/impl. Chưa có số đo PPA mới.

[Context execution](architecture/CONTEXT_EXECUTION.md) làm rõ: LSQR có program
nạp được nhưng kernel PE context còn tạo cố định; tile64/control256 là reference
riêng. Controller mới có program/template/descriptor/constant nạp được,
branch, CALL/RET, scalar và selection dùng chung. Bằng chứng controller với
mock services được tách khỏi kiểm chương trình chạy trên datapath thật.

`v4` là tên thư mục/version. Tên module theo chức năng; macro/include guard dùng
`CSR_`. Quy tắc được kiểm bởi `scripts/v4/project.py check`. Không sửa v2/v3.

## Phần mở rộng live operator và kernel

[Live operator PASS](../../reports/v4/live_operator_rtl_audit_20260909/README.md):
5 tests, 20 lượt xsim, 1.492.709 comparisons, 24 executed source hashes đã lưu.
Kiểm Phi/B thuận/chuyển vị, R1/R4, M128/N1024/S96, tail, tags, stalls và cancel.
Đây là gate trước tối ưu feeder. Bản hiện hành dùng bốn frame chờ, cache hai
block vector và hai read credits; xem [pipeline hiện hành](architecture/OPERATOR_PIPELINE.md).

[Shared kernel PASS](../../reports/v4/stream_kernel_rtl_audit_20260909/README.md):
11 tests, 77 source hashes ổn định. Phạm vi gồm TEMPLATE/GEMV/NORMALIZE/STORE/
SOFT, live Phi/B và tương thích wrapper CALL/HALT cũ. Nguồn được lưu trước
khi nối selection; gate này không tự chứng nhận các chỉnh sửa tiếp theo.

`stream_engine` hiện là wrapper revision1; `stream_kernel` giữ pool, fabric,
arbitration và publication. [Controller/scalar PASS](../../reports/v4/PROGRAM_SERVICES_RTL_CORRECTNESS.md)
gồm 13 tests, 37 source hashes; controller dùng mock services, scalar được
kiểm riêng bằng RTL. [Support-integrated core](../../reports/v4/stream_kernel_support_audit_20260909/)
đã qua 14 tests trên 81 source hashes. Gate tiếp theo cho
[SLICE/REPLACE_RANGE](../../reports/v4/stream_kernel_range_audit_20260909/README.md)
đã PASS 21 tests, 65 source hashes, 69 lượt xsim; source archive được giữ riêng.
[Contract support](architecture/SUPPORT_SERVICE.md) tách selection order,
ordered append, sorted union, cardinality và độ dài vector xuất.

RESCALE raw64 Q44 → S27F22 cùng kiểm controller/range đã qua
[5 tests tập trung bằng Vivado](../../reports/v4/rescale_range_control_rtl.json),
bao gồm ties có dấu, overflow, stall và cancel.
[Native integration và result store](../../reports/v4/native_recovery_rtl_audit_20260909/README.md)
đã PASS 4 tests/15 replays, 40 source hashes, gồm live builder/operator,
scalar/branch và atomic result. Gate tiếp theo cho
[native và sáu program đầy đủ](../../reports/v4/complete_recovery_rtl_audit_20260909/README.md)
đã PASS 8 tests/36 replays trong source tree đóng băng, 54 source hashes.
Gồm MP/GP/IHT/FISTA/PDHG/ADMM, raw X/residual/support/status và PC trace;
PASS này không bao gồm các thay đổi compiler/controller tiếp theo cho QR.

Catalog đã chuyển top dự kiến sang `csr_top -> recovery_engine -> stream_kernel`.
LSQR là reference root riêng. [Sơ đồ recovery](diagrams/recovery.mmd) và
[sơ đồ QR](diagrams/qr.mmd) ghi rõ factor store/transfer và program QR đã triển khai.
[QR numerical đã PASS](../../reports/v4/QR_NUMERICAL.md): 583/583 support và
31/31 ca recovery dùng QR, không refinement hoặc LSQR fallback. SNR thấp nhất
21,622 dB, SNR loss lớn nhất 0,040134 dB, NMSE ratio lớn nhất 1,009284.
Sau [lượt QR thăm dò trước](../../reports/v4/qr_recovery_rtl_exploration_20260909/README.md),
gate mới đã đóng băng nguồn và kiểm lại năm chương trình OMP/GOMP/CoSaMP/SP/HTP
ở M16/N32/K2: kết quả và PC trace khớp model. Bằng chứng nằm trong
[gate 17 ca](../../reports/v4/pipeline_whole_program_comparison_20260909/README.md).
Chưa kiểm đầy đủ RTL QR ở support 96 hoặc dữ liệu ứng dụng held-out.

[Factor RAM](../../reports/v4/factor_store_rtl_audit_20260909/README.md) đã qua
5 tests xsim, 23 source hashes; có hai response credits và đọc full32 bank.
Worker INIT/READ/WRITE đã qua [gate riêng](../../reports/v4/factor_service_audit_20260909/README.md)
và [gate nối kernel](../../reports/v4/stream_kernel_factor_audit_20260909/README.md)
18 tests/66 source hashes. Phép chuyển hàng/cột dùng cả bundle32. Program
Householder và các vòng recovery có gate nhỏ riêng nêu trên; PASS transport
không tự chứng nhận mọi kích thước QR.

## Snapshot streaming đầu tiên

[Contract](architecture/STREAM_RTL_CONTRACT.md) khóa revision 1 cho ABI,
pipeline/credits, memory ports và phép tính chính xác. Nguồn cấu hình là
[v4_stream_interface.json](../../config/v4_stream_interface.json); macro RTL
và compiler dùng cùng authority. Đây không phải khóa bit production.

| Module | Trách nhiệm |
|---|---|
| `stream_engine` trong snapshot đầu | RAM arbitration, kiểm source validity, ghép frame, scratch, fold/narrow và publish theo CALL |
| `stream_program_control` | Nạp program128/template, kiểm image, PC CALL/HALT, identity và done |
| `stream_vector_store` | 16 bank TDP ghép cặp; 512 block × 32 S27; một read **hoặc** write/clock, hai read credits |
| `stream_fabric` | Cấu hình và hoàn tất đồng bộ hai array |
| `stream_array` | Một nhóm 4×4 PE với frame barrier |
| `stream_pe` | Context riêng; MOV/ADD/SUB/MUL/MAC; một multiplier 27×18, ACC64 |

Sơ đồ: [stream.mmd](diagrams/stream.mmd). Top mới được elaborate riêng, không
gắn thêm 32 PE vào LSQR cũ. Có 480 block public và 32 block scratch; đây là
RAM vector, không phải implementation mới của cache ma trận B.
Đọc [kết quả và bottleneck](architecture/STREAM_IMPLEMENTATION.md) để phân
biệt tốc độ fabric, chi phí memory và cycle của cả program ví dụ.

Sau START, program tự gọi template và tiến tới HALT. Mỗi template có 32 context
PE riêng. [Ví dụ ADD → DOT → HALT](../../reports/v4/stream_program_example/README.md)
có input/setup và disassembly để đọc. Output vector chỉ được publish khi toàn
CALL thành công; cancel/fault làm invalid các block đích của CALL đó. Các CALL
trước trên block khác vẫn giữ kết quả; chưa có rollback toàn program.

Gate dành riêng cho lát mới được xuất bởi `scripts/v4/run_stream_rtl.py`;
xem [evidence streaming](../../reports/v4/STREAM_RTL_CORRECTNESS.md) cho test,
source hashes và lệnh Vivado thực tế. Gate này không thay thế regression của
LSQR reference hoặc xác nhận chất lượng của 11 ứng dụng.

**Gate streaming PASS: 16 tests, 37 lượt xsim, 0 failure/error/skip; 62 source
hashes ổn định.** Ba test kiểm compiler/ABI bằng Python; phần RTL dùng 4 lượt
xvlog, 4 lượt xelab và 37 lượt xsim thực tế. [Snapshot đã lưu](../../reports/v4/stream_rtl_audit_20260909/manifest.json)
giữ đúng source của gate. [Kiểm bảo toàn](../../reports/v4/stream_reference_preservation.json)
xác nhận 72 RTL/header/TB cũ không đổi so với snapshot LSQR trước lượt này;
đây là kiểm source, không biến lượt LSQR bị ngắt thành PASS.

## LSQR reference đã nối trước đó

[Sơ đồ LSQR](diagrams/lsqr.mmd), [catalog module](architecture/MODULES.md) và
[contract tích hợp](architecture/LSQR_INTEGRATION.md) mô tả cùng một hierarchy.

| Module | Trách nhiệm |
|---|---|
| `lsqr_engine` | Giữ descriptor của job, khóa host khi chạy, điều phối build → solve → drain X → approve → done |
| `operator_memory` | Một LFSR/Phi cache 8 bank, một B dense 32 bank; phân quyền load/build/read |
| `support_builder` | Kiểm ordered support, dựng B cho Psi=I, publish khi đủ dữ liệu |
| `measurement_loader` | Kiểm stream D18 đã chuẩn hóa, nhúng chính xác sang S27 bằng dịch trái 8 bit |
| `solver_sequencer` | Một PC, program 256×128 và scalar RF 32×64; thực thi LSQR bằng lệnh kernel/scalar |
| `kernel_engine` | GEMV, vector/scalar arithmetic, ENERGY, NORMALIZE, NARROW_X; ghi vector tạm rồi publish |
| `kernel_fabric` | Sử dụng đúng hai `pe_array` 4×4; nhận raw ACC, không thêm array cho LS |
| `vector_workspace` | 16 vector × 128 S27, 32 bank, hai cổng đọc và một cổng ghi |
| `scalar_service` | DIV/SQRT dùng chung, kiểm range/zero/tag, giữ response khi stall |
| `commit_controller` / `result_writeback` | Kiểm support và X, hai bank candidate/committed, chỉ publish sau approval |

Chương trình có 84 lệnh, phần còn lại trong 256 word điền FAIL. Nạp image xong,
RTL tự thực hiện toàn bộ vòng LSQR; Python không quyết định từng bước sau START.
[Image để nạp và đọc](../../reports/v4/lsqr_program/program.txt) được xuất bằng:

```powershell
py -3 -m compiler.v4.solver_program --output reports/v4/lsqr_program
```

Certificate tính trên **nghiệm đã lưu X24**, với
`energy(B^T(y-BX)) × 10^10 <= energy(B^T y)`. Sequencer trả đúng slot đã được
chứng nhận; top đọc slot đó để commit. Fault/cancel trước approval giữ kết quả
cũ. Cancel sau cạnh publish giữ kết quả mới và báo committed success.

Phạm vi LSQR: M≤128, support 1..96, original N≤1024; LFSR/Psi=I hoặc B dense
được nạp làm reference. Host chuẩn hóa Y trước D18 và cung cấp exponent [-31,31].
RTL kiểm peak raw≤8192 và metadata, không tự suy ra gain từ tín hiệu gốc.
Đây là LS trên support đã cho; chưa phải chương trình sparse recovery đầy đủ.

## Evidence và bảo toàn phần cũ

RTL chỉ kiểm bằng **Vivado xvlog → xelab → xsim**. Python sinh stimulus và đối
chiếu integer oracle. Lượt 227 tests trên 40 module test đã bị ngắt khi chuyển
sang xem lại kiến trúc. [Snapshot nguồn](../../reports/v4/rtl_lsqr_audit_20260909/manifest.json)
giữ để đối chiếu, không có evidence PASS cho toàn bộ snapshot này.
[Gate chung](../../reports/v4/RTL_CORRECTNESS.md) vẫn là report cũ và chỉ có
hiệu lực cho snapshot cũ.

Bản Vivado baseline trước đó đạt 210 tests/12 checks, không failure/error/skip,
258 RTL replays, 132 xvlog/132 xelab/258 xsim; 204 source hashes ổn định.
[Snapshot baseline](../../reports/v4/rtl_vivado_audit_20260909/manifest.json)
giữ nguyên nguồn và evidence đó. Bản audit cũ hơn 190 tests là lịch sử trước yêu
cầu xsim-only, không thay thế kết quả Vivado.

So với bản Vivado 210 tests đã lưu, toàn bộ 55 RTL/header/TB cũ được bảo toàn:
18 file nguyên byte, 37 file chỉ thay chính xác `V4_` thành `CSR_`, không có
thay đổi khác. [Audit đổi tên](../../reports/v4/rtl_lsqr_audit_20260909/namespace_migration.json)
ghi cả hash trước/sau và phép thay trên byte; không tuyên bố các file đã đổi tên
vẫn nguyên byte.

`resident_engine` và `cgra_fabric` vẫn được kiểm như reference độc lập. Chúng
không nằm cạnh `kernel_engine` trong hierarchy LSQR, nên không cộng thành 64 PE.
Backend resident dùng tile64/control256; LSQR dùng service ISA riêng. Các
[R1/R4 resident measurements](architecture/RESIDENT_PERFORMANCE.md) giữ đúng
phạm vi reference, không đại diện cho throughput LSQR.

## Numerical vẫn là calibration, chưa khóa bit

[Kết quả ứng dụng trước đổi solver](../../reports/v4/LFSR_APPLICATION_TUNING.md) giữ nguyên:
65/65 ca fixed được chọn đạt trên grid 77 ca; 12 ca ECG còn chưa qualified.
SNR khôi phục tín hiệu gốc phải ≥20 dB cho cả float và fixed, SNR loss ≤0,5 dB,
NMSE ratio ≤1,10 và không numeric fault trên từng ca.

- Synthetic: 33/33 ca, 11 thuật toán × 3 seed.
- ECG/db4: 10/10 ca của GOMP, CoSaMP, SP, FISTA, ADMM; sáu thuật toán còn lại
  chưa qua policy chung ở float trên hai cửa sổ.
- Camera/Haar: 22/22 ca, 11 thuật toán × 2 patch.
- Trên 65 ca đã chọn: SNR loss tối đa 0,14665 dB, NMSE ratio tối đa 1,03435.
- 583/583 lần LS trên support thực qua diagnostic SVD; condition number tối đa
  13,091, coefficient relative error tối đa 1,469e-4, support tối đa 96.

Các số trong danh sách trên thuộc calibration LSQR cũ. QR đã kiểm lại riêng
31 ca thuộc năm thuật toán gọi support LS: synthetic 15, ECG 6, camera 10;
tất cả đạt ngưỡng. Raw X thay đổi trên cả 31 ca và một trajectory CoSaMP đổi,
nên không dùng PASS LSQR thay cho QR. Sai số hệ số QR lớn nhất trên 583 support
là 1,063e-5. Xem [report QR](../../reports/v4/QR_NUMERICAL.md).

Giữ candidate **D18F14/C18F16/S27F22/X24F20/ACC64**; proximal reference vẫn lưu D.
Hai cửa sổ ECG cùng bản ghi và hai patch cùng ảnh chưa phải source-held-out.
Transform và mean/scale trong study do host thực hiện; chưa chứng nhận raw-signal
Phi×Psi trên FPGA. Generic B gần suy biến vẫn có ca pass normal residual nhưng
sai hệ số. Không bỏ ca đó hoặc coi certificate là bound sai số hệ số.
Chi tiết: [numeric contract](architecture/NUMERIC_CONTRACT.md),
[application profiles](architecture/APPLICATION_PROFILES.md),
[khảo sát LS trước](../../reports/v4/LFSR_NUMERICAL_CONTRACT.md).

## Công việc còn lại

1. Mở rộng các gate 11 chương trình nhỏ, K8 và bốn ca toàn N đã PASS: QR trên
   support lớn hơn24, ADMM/PDHG toàn N1024 sau pipeline mới và các policy ứng dụng thực.
2. Kiểm stored-X certificate, giới hạn rank/condition và lỗi/cancel của chương
   trình QR ở phạm vi mở rộng; giữ nguyên giới hạn và không fallback LSQR.
3. Tiếp tục giảm reduction và factor traffic theo cycle toàn chương trình;
   báo riêng từng thuật toán. Đề xuất local reduction
   trong [STREAM_REDUCTION_PROPOSAL.md](architecture/STREAM_REDUCTION_PROPOSAL.md)
   chưa phải routed CGRA RTL đã triển khai hoặc novelty/PPA được chứng minh.
4. Hoàn tất policy ứng dụng và dữ liệu source-held-out trước khi khóa bit.
   AMP và PDHG-TV vẫn chỉ là hướng mở rộng, không tính vào program đã chạy.
5. Tích hợp host/AXI/DMA cho ZCU106. Chỉ synth/impl sau các gate correctness
   cần thiết, rồi mới xác nhận tài nguyên, timing 100 MHz và board throughput.

Payload logical hiện tại: Phi 16 KiB, B 27 KiB, pool 512×32×27 bit = 54 KiB;
factor S27 thêm 40,5 KiB ở M128/S96, cộng program/constants/templates,
result banks và metadata. Số byte không suy ra trực tiếp số BRAM do padding,
bank/cổng và inference. [ZCU106](architecture/ZCU106.md) ghi layout và
[inventory Vivado](../../reports/v4/zcu106_device_inventory_20260909/README.md)
xác nhận part có trong môi trường; chưa có claim fit/PPA.

Bottleneck còn lại là Phi nhiều pass ở một số mapping, pool một read hoặc
write/clock, central reduction 32 chu kỳ/group và support/factor traffic.
Feeder đã chồng lấp bốn frame và tái sử dụng operand vector; phần fold chưa đổi.
[Contract tích hợp](architecture/STREAM_SYSTEM_CONTRACT.md) tách rõ cadence,
workspace và quyền sở hữu. Đủ 32 lane trong một MAC frame chưa đồng nghĩa
hiệu suất PE cao trên toàn bộ chu kỳ.

```powershell
py -3 scripts/v4/project.py generate
py -3 scripts/v4/project.py check
py -3 scripts/v4/run_rtl.py --test-timeout 7200
```

Astra Ultra điều phối, Astra Medium viết code theo yêu cầu hiện hành. Các
report cũ giữ nguyên provenance; không dùng PASS cũ cho source đã đổi.


## Historical: factor-panel candidate (revision3)

actor_panel_service is implemented in the staged candidate. A source-bound CoSaMP M64/N256/K8 actual-outer8 smoke recorded 252684 cycles and matched its own VM/X/R/support/status evidence. This is preliminary candidate evidence only: final active10 two-geometry gates, source freeze and promotion decision remain pending. No timing, PPA or production-promotion claim follows.

