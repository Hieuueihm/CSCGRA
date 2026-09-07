# RTL v3 architecture workspace

Thư mục này là nơi thiết kế lại kiến trúc v3 từ đầu. V3 đã có mathematical
golden, bit-accurate hardware golden, phase-level vectors và compact
register/control source. M0-M4 đã hoàn thành ở leaf boundary và M4.1 đã đóng
DMA preload/residency seam. Non-production integration harness M1-M4 cũng đã
PASS Vivado/XSim và OOC synthesis; run-configuration
ingress, AXI DMA spine, context stores, load-time certification, hai cấp sequencer và
scratchpad/stream transport đã qua Vivado. M5 shared reduction, scalar divide
và vector arithmetic cũng đã qua XSim/property/OOC. M6 đã hoàn thành 32
homogeneous PE, local RF/L48 và registered nearest-neighbor mesh; Phi generator
vẫn thuộc M7. DFG/MMG compiler gate đã map bốn inner kernel; M3.6 đã emit
typed/RF/bank-allocated context library và loại bỏ full-proxy dependency khỏi
correlation.
Trạng thái golden/verification nằm tại
[`reports/v3/GOLDEN_STATUS.md`](../../reports/v3/GOLDEN_STATUS.md).
Biên bản hierarchy, naming và register cleanup nằm tại
[`reports/v3/RTL_CLEANUP_STATUS.md`](../../reports/v3/RTL_CLEANUP_STATUS.md).
Kế hoạch refactor hierarchy, ownership, module và port hiện hành nằm tại
[`RTL_HIERARCHY_PORT_REFACTOR_PLAN.md`](RTL_HIERARCHY_PORT_REFACTOR_PLAN.md).
Nghiên cứu lựa chọn width và candidate DSP-friendly nằm tại
[`reports/v3/FIXED_POINT_SELECTION_STUDY.md`](../../reports/v3/FIXED_POINT_SELECTION_STUDY.md).

## Trình tự thiết kế

1. [00 - Tổng quan hệ thống](00_SYSTEM_OVERVIEW.md): top-level, ranh giới các
   khối, luồng dữ liệu và ánh xạ tám thuật toán.
2. [01 - CGRA block design specification](01_BLOCK_DESIGN_SPEC.md): ownership,
   memory, pipeline, timing/resource budget và FPGA-to-ASIC abstraction.
3. [02 - Paper algorithm contract](02_ALGORITHM_CONTRACT.md): công thức,
   paper provenance, phase chuẩn và golden chain của tám thuật toán.
   Danh mục citation/PDF đầy đủ nằm tại
   [references/README.md](references/README.md).
4. [03 - Data and numeric contract](03_DATA_AND_NUMERIC_CONTRACT.md): profile
   production `D18F14/S27F19/A62`, rounding, saturation và range contract.
5. [04 - Memory and interfaces](04_MEMORY_AND_INTERFACES.md): AXI4-Lite CSR,
   reconstruction lifecycle, memory map và handshake chi tiết.
6. [05 - Reconstruction register map](05_RECONSTRUCTION_REGISTER_MAP.md):
   software-visible CSR, snapshot semantics, validation và telemetry.
7. [06 - CGRA microarchitecture](06_CGRA_MICROARCHITECTURE.md): PE, distributed
   context/VLIW, interconnect và FPGA/ASIC rules.
8. [07 - CFG, DDG and context compilation](07_CFG_DDG_AND_CONTEXT_COMPILATION.md):
   paper phase graph, operation IR, MRRG mapping và context/golden artifacts.
9. [08 - Context ISA/VLIW](08_CONTEXT_ISA.md): encoding 36 bit cho tile,
   array-control, stream, resource và phase; đây là contract compiler/RTL.
10. [09 - Scalable datapath and memory](09_SCALABLE_DATAPATH_AND_MEMORY.md):
    capacity K32, resource/bandwidth model và seam mở rộng không trả trước
    phần cứng K64.
11. [10 - Detailed implementation blueprint](10_DETAILED_IMPLEMENTATION_BLUEPRINT.md):
    module tree, interface ledger, routine schedule, state/formal và milestone.
12. [11 - Unified restricted-refinement blueprint](11_LS_SOLVER_ARRAY_BLUEPRINT.md):
    warm-start matrix-free refinement, PE đồng nhất, vector sidecar, proxy reuse,
    cycle/capacity model và numerical gate trước RTL.
13. [12 - RIP-aware generated-Phi architecture](12_RIP_AWARE_PHI_GENERATOR.md):
    matrix ensemble/seed qualification, runtime scale register và placement
    scale không làm nghẽn 32 lane.
14. [13 - Module implementation plan](13_MODULE_IMPLEMENTATION_PLAN.md): module
    tree cuối cùng, dependency graph, milestone và verification gate.
15. [14 - Complete architecture cycle simulator](14_ARCHITECTURE_CYCLE_SIMULATOR.md):
    functional trace, resource reservation, cycle breakdown và timing assumptions.
16. [15 - Novelty roadmap](15_NOVELTY_ROADMAP.md): sáu cơ chế N1-N6 cho paper
    (guaranteed-commit, load-time certification, candidate-symbol capture, cadence
    controller, transactional sparse state, speculative phase overlap), gắn
    vào milestone M3-M11 kèm bảng định vị prior art.
17. [17 - M5 arithmetic resources contract](17_M5_ARITHMETIC_CONTRACT.md):
    quyết định scope reciprocal/sqrt, numeric contract bit-exact theo
    `hardware.py`, interface/latency ledger và verification gate cho M5.
18. [18 - M8 realignment gate plan](18_M8_REALIGNMENT_GATE_PLAN.md): gate A-E
    thực thi re-audit 2026-08-26 — sửa timing authority, kéo M9a TOP-K lên
    trước M8, operator harness, reconciliation tài liệu.
19. [19 - M9a TOP-K selection contract](19_M9A_TOPK_SELECTION_CONTRACT.md): exact `_rank` order, K32 transaction protocol, latency/II và verification gate.
20. [20 - M8 operator integration contract](20_M8_OPERATOR_INTEGRATION_CONTRACT.md): nested operator replay, runtime tails và M8 gate.
21. [21 - M9b support management contract](21_M9B_SUPPORT_MANAGEMENT_CONTRACT.md): candidate 2K, transactional K/3K workspace, remap và atomic commit/rollback.
22. [22 - V3 paper plan](22_V3_PAPER_PLAN.md): câu chuyện/tiêu đề, contribution
    map C1-C6 gắn evidence, related-work hai trục, results gating theo
    milestone và honesty rules cho paper v3.
23. [25 - MRI evaluation protocol](25_MRI_EVALUATION_PROTOCOL.md): BrainWeb
    normal/MS full-factorial sweep, fastMRI manifest/checksum policy,
    MSE/NMSE/SNR/PSNR/SSIM, statistical reporting and paper-safe claim limits.
23. RTL được triển khai theo từng interface/routine đã duyệt. M1-M7, M3.5 và
    integration harness M1-M4 đã pass Vivado/XSim/property execution; chưa phải
    full sign-off.
24. [Public CGRA implementation review](../../reports/v3/CGRA_OPEN_SOURCE_IMPLEMENTATION_REVIEW.md):
    đối chiếu các generator, RTL system và mapper công khai; khóa control,
    interconnect, memory, shared-resource và compiler contract cho M3-M6.
25. [M3 context/control status](../../reports/v3/M3_CONTEXT_CONTROL_STATUS.md):
    RTL, exact cycle trace, assertion coverage và ZCU106 OOC evidence của M3.
26. [M3.5 DFG/MMG status](../../reports/v3/M35_DFG_MMG_STATUS.md): physical
    resource authority, candidate-II MMG, selected mappings và compiler limits.
27. [M3.6 typed/context status](../../reports/v3/M36_TYPED_CONTEXT_STATUS.md):
    typed SSA, RF lifetime, bank allocation và physical context-plane emission.
28. [M4 stream transport status](../../reports/v3/M4_STREAM_TRANSPORT_STATUS.md):
    8-bank scratchpad, stream prefetch/commit, packing, assertions và ZCU106
    OOC evidence.
29. [M4.1 DMA preload status](../../reports/v3/M41_DMA_SCRATCHPAD_STATUS.md):
    DMA-to-scratchpad D18/S27, runtime residency, assertion và OOC evidence.
30. [M1-M4 integration harness](../../reports/v3/M1_M4_INTEGRATION_HARNESS_STATUS.md):
    CSR START, shared DMA, active configuration, phase/context và scratchpad
    vector read trong một harness thật nhưng không thay production top.
31. [M5 arithmetic status](../../reports/v3/M5_ARITHMETIC_RESOURCES_STATUS.md):
    reduction hai cluster, scalar divide, vector DOT/NORM/SCALE/AXPY/COPY,
    resource router, latency/II và ZCU106 OOC evidence.
32. [M6 homogeneous CGRA status](../../reports/v3/M6_CGRA_ARRAY_STATUS.md):
    32 PE, local RF/L48, registered mesh, bit-exact opcode tests, assertions và
    ZCU106 OOC evidence.

## Quy tắc v3

- `models/v3/paper.py` là nguồn sự thật toán học theo paper;
  `models/v3/hardware.py` chỉ được phép hiện thực hóa contract đó bằng số cố
  định. RTL không tự định nghĩa biến thể thuật toán.
- Tám thuật toán là tám context program chạy trên cùng CGRA fabric; không tạo
  một datapath cố định riêng cho từng thuật toán hoặc từng solver.
- Reconstruction control sequencer giữ run protocol và chạy paper CFG; array
  context sequencer replay static schedule. Không khối nào
  issue PE operation động theo kiểu controller-centric.
- Baseline là hai CGRA cluster 4x4 theo hướng mở rộng ADRES. Đây không phải một
  pipeline 4x8 registered wavefront và không kế thừa module hierarchy từ v2.
- Hai cluster dùng shared synchronous context theo MRCA 2.0: một PC, 16 tile
  context broadcast theo vị trí, không hỗ trợ hai kernel độc lập trong baseline.
- Mọi interface mảng dùng địa chỉ hoặc stream `valid/ready`, không trải thành
  hàng chục cổng scalar.
- Index, count và work-depth là ba miền kiểu riêng.
- SP giải workspace tối đa 2K; CoSaMP giải workspace tối đa 3K trước khi prune.
- Build hiện tại chỉ có `K_MAX=32`, `M_MAX=128`, `LS_WORK_MAX=96`. K64 chỉ là
  seam build-time tương lai, không phải runtime profile và không được allocate
  state trong baseline nếu FPGA primitive hiện tại không cấp sẵn capacity đó.
- LS architecture dùng unified restricted refinement trên matrix-free `A/A^T`;
  strict/balanced/fast là profile tách biệt. Hardware golden restricted
  refinement chỉ được thay sau numerical sweep và review riêng.
- `Phi=alpha*S`: production candidate dùng dense signed Rademacher sinh theo
  coordinate; `alpha` là active run register, không hard-code `1/8`. Một matrix
  profile chỉ được claim sau matrix-quality và fixed-point sweep tương ứng.
- Mỗi thay đổi phải được đánh giá cùng lúc về correctness, cycle,
  LUT/FF/BRAM/DSP và post-route timing.
