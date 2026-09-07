# 16 - M4 execution plan và roadmap M5-M13

Ngày lập plan: 2026-08-25.
Trạng thái hiện tại: **M0-M4 leaf + M4.1 preload integration COMPLETE**. Phase
A và Phase B đã đóng ngày 2026-08-25; M5 và M6 đã hoàn thành sau
kế hoạch này; M7 là bước kế tiếp.

Tài liệu authority: [13_MODULE_IMPLEMENTATION_PLAN.md](13_MODULE_IMPLEMENTATION_PLAN.md)
(scope/exit gate), [04_MEMORY_AND_INTERFACES.md](04_MEMORY_AND_INTERFACES.md) và
[09_SCALABLE_DATAPATH_AND_MEMORY.md](09_SCALABLE_DATAPATH_AND_MEMORY.md)
(data contract), [15_NOVELTY_ROADMAP.md](15_NOVELTY_ROADMAP.md) (novelty gate).

## 0. Hiện trạng M4 (điểm xuất phát)

### Đã có

| Hạng mục | Bằng chứng |
| --- | --- |
| `rtl/v3/data_movement/vector_scratchpad.v` | 8 bank x 512 x 72 bit TDP, conflict detect, data array không reset |
| `rtl/v3/data_movement/vector_stream_engine.v` | 3 logical stream -> tối đa 2 physical port, advance gate bằng `stream_cycle_commit` |
| `rtl/v3/data_movement/scratchpad_word_codec.v` | pack/unpack D18/S27/index/raw, không rounding |
| `rtl/v3/cgra/stream_context_router.v` | decode stream context 36 bit, join ready/valid pair-wide, Phi command port |
| Cả bốn module trong `rtl/v3/files.f`, có block `` `ifdef FORMAL `` | đã kiểm tra |
| `verification/v3/m4/tb_m4_stream_transport.sv` | directed + 2000-cycle randomized self-check cho D18/S27/index/raw, conflicts, bounds và router |
| `verification/v3/m4/m4_vector_transport_ooc.sv` | harness synth engine+scratchpad |
| `scripts/sim/run_m4.ps1`, `scripts/formal/check_m4_properties.ps1`, `scripts/synth/check_m4.ps1/.tcl`, `constraints/v3/m4_ooc.xdc` | flow đầy đủ |
| OOC synth 2026-08-25 (`reports/v3/m4_vivado/`) | RTL minor 22: `vector_stream_engine` 635 LUT/154 FF, WNS +3.520 ns; `m4_vector_transport_ooc` 703 LUT/172 FF, WNS +3.200 ns, 16 RAMB36, 0 DSP |

### Khoảng trống Phase A đã đóng

Danh sách dưới đây là gap tại thời điểm lập plan; toàn bộ mục 1-5 đã được đóng
và ghi evidence trong `reports/v3/M4_STREAM_TRANSPORT_STATUS.md`. Mục 6 là
Phase B M4.1, đã được đóng riêng và không làm thay đổi claim M4 leaf.

1. TB chưa cover **S27 packing** (2 phần tử/bank -> 16/stripe) và **index10
   packing** (7/bank); exit gate doc 13 yêu cầu "D18/S27/index packing".
2. Chưa có **random backpressure** thực sự (LFSR ready deassert); TB hiện chỉ có
   một scenario hold-stable directed.
3. Chưa có negative test **memory-configuration bounds** (địa chỉ vượt
   base/length của configuration ID phải bị chặn/flag, không silent wrap).
4. Chưa có `reports/v3/M4_*_STATUS.md`; không có log XSim PASS được lưu làm
   evidence trong tree.
5. Tài liệu stale: `docs/v3/README.md`, `rtl/v3/README.md`,
   `reports/v3/GOLDEN_STATUS.md` (mục Open gates), doc 13 dòng 3 và bảng §7 vẫn
   ghi scratchpad/stream "chưa có".
6. Integration nợ từ M2: "nối DMA vào scratchpad ở M4" chưa thực hiện; `top.v`
   vẫn là control-only seam của M1.
7. Doc 13 §4 mermaid gán nhãn M5/M6/M7 lệch với tiêu đề §5 (mermaid: M5=PE,
   M6=Phi, M7=arithmetic; §5: M5=arithmetic, M6=CGRA, M7=Phi). Cần sửa mermaid
   theo §5 khi cập nhật docs.

## 1. Phase A - Đóng leaf M4 — COMPLETE 2026-08-25

### A1. Bổ sung coverage vào `tb_m4_stream_transport.sv`

Thêm các directed + randomized scenario, giữ nguyên message
`M4 STREAM TRANSPORT PASS` mà `run_m4.ps1` đang grep:

1. **S27 round-trip**: ghi stripe S27 qua gateway (2/bank, 16/stripe), đọc lại,
   so bit-exact từng phần tử; xác nhận bit-copy không rounding.
2. **Index10 round-trip**: 7 index/bank, kiểm tra phần tử thứ 7 và padding bits.
3. **Raw72 passthrough**: ghi/đọc nguyên word 72 bit.
4. **Random backpressure**: LFSR điều khiển deassert `ready` phía consumer và
   stall phía producer trong >= 2000 cycle stream liên tục; checker xác nhận
   (a) không mất/đúp phần tử, (b) address chỉ advance khi `stream_cycle_commit`,
   (c) thứ tự bảo toàn. Seed cố định ghi vào log để tái lập.
5. **Bounds negative**: memory configuration với `base+length` chạm biên 512
   word; truy cập vượt biên phải raise error/flag theo contract doc 04, không
   wrap silent.
6. **3-way access stall** (đã có atomic stall test - mở rộng với random mix
   R+R/R+W qua nhiều configuration ID).

### A2. Chạy simulation và lưu evidence

```powershell
scripts\sim\run_m4.ps1                    # directed + random
scripts\sim\run_m4.ps1 -EnableProperties  # assertion-enabled
```

Lưu log PASS (đường dẫn log + tóm tắt) để trích vào status report; không claim
PASS nếu không có log.

### A3. Property elaboration

```powershell
scripts\formal\check_m4_properties.ps1
```

Sáu top M4/M4.1 phải compile/elaborate sạch. Ghi rõ trong report: đây là property
elaboration, không phải mathematical proof (rule doc 13 §6).

### A4. OOC synthesis re-run sau khi TB/RTL thay đổi

```powershell
scripts\synth\check_m4.ps1
```

Gate: WNS >= +0.2 ns cho top có clock @150 MHz; `m4_vector_transport_ooc`
RAMB36 = 16, DSP = 0. Cập nhật `reports/v3/m4_vivado/*/summary.txt`.

### A5. Viết `reports/v3/M4_STREAM_TRANSPORT_STATUS.md`

Theo format M1-M3: scope, module list, interface contract đã khóa, bảng test
scenario + kết quả, assertion coverage, OOC number (LUT/FF/RAMB/DSP/WNS),
open item (DMA seam - xem Phase B), ngày và tool version.

### A6. Cập nhật tài liệu stale (chỉ sau khi A2-A4 PASS)

- `reports/v3/GOLDEN_STATUS.md`: thêm dòng M4 vào bảng evidence; sửa mục
  "Open gates" (bỏ "scratchpad/stream chưa tồn tại").
- `docs/v3/README.md`: sửa đoạn mở đầu ("Scratchpad/stream ... chưa bắt đầu");
  thêm link M4 status report vào danh mục.
- `rtl/v3/README.md`: thêm bốn module M4.
- Doc 13: sửa dòng trạng thái đầu file, bảng §7 (M4 -> "có"), và mermaid §4
  theo tiêu đề §5.

### Definition of done Phase A

- [x] A1 merged, tất cả scenario PASS trong XSim (default + `-EnableProperties`)
- [x] Property elaboration sáu top PASS
- [x] OOC PASS với gate WNS/RAMB/DSP
- [x] `M4_STREAM_TRANSPORT_STATUS.md` tồn tại với evidence thật
- [x] Docs/README/GOLDEN_STATUS đồng bộ, không claim quá bằng chứng

## 2. Phase B - M4.1: DMA <-> scratchpad seam — COMPLETE 2026-08-25

M2 status ghi next-action "nối scratchpad ở M4". Không cần `top.v` full; làm
một integration harness mỏng để trả nợ contract:

1. [x] Wiring có kiểm soát: `memory_dma_engine` -> `dma_element_normalizer` ->
   `scratchpad_word_codec` (write path) -> `vector_scratchpad`; chiều
   đọc lại đi qua `vector_stream_engine`. AXI result drain giữ ở M12.
2. [x] TB directed `verification/v3/m4/tb_m4_dma_scratchpad.sv`: load một stripe
   D18 và một stripe S27 từ AXI memory model qua DMA vào scratchpad, đọc lại
   qua stream engine, so bit-exact; thêm random backpressure trên AXI AR/R.
   AXI AW/W/B đã được cover ở M2 và result drain chưa thuộc M4.1.
3. [x] Residency hook (novelty N2): xác nhận consumer bị chặn khi stripe chưa
   DMA xong; context không cho phép stall phải phát reservation violation.
4. [x] Hai leaf mới đã vào `files.f` và OOC.
5. [x] Evidence nằm tại `reports/v3/M41_DMA_SCRATCHPAD_STATUS.md`.

Final compute/preload arbitration được dời tường minh sang M8; result drain
thuộc M12, không phải nợ ngầm của preload seam.

## 3. Roadmap M5-M13

Thứ tự theo tiêu đề §5 doc 13 (authority). Mỗi milestone tuân thủ convention:
contract -> RTL + assertion + `files.f` -> XSim directed/backpressure qua
`scripts/sim/run_mN.ps1` -> property elaboration -> OOC + XDC -> status report
`reports/v3/` -> cập nhật GOLDEN_STATUS/README.

### M5 - Arithmetic resources độc lập (sau M4; cần stripe S27 từ scratchpad)

- Modules: `cluster_reduction_unit`, `global_reduction_merge`,
  `scalar_register_file`, `scalar_function_unit`,
  `shared_vector_arithmetic_unit`, `array_resource_router`.
- Leaf test bit-exact với `models/v3/hardware.py`: A62 sum/norm, folded S27
  multiply, AXPY và divide. `SCALAR_RECIPROCAL`/`SCALAR_SQRT` là reserved
  one-cycle fault, không có datapath và compiler cấm emit. Mọi request/result
  mang tag; variable latency không mất transaction (dùng
  `context_transaction_golden.json`).
- Exit gate: transaction golden PASS; OOC báo latency/II/resource/WNS từng
  leaf. Novelty N2 mở rộng reservation guard sang resource consumer.

### M6 - CGRA đồng nhất (sau M3+M4; có thể chồng lấn cuối M5)

**COMPLETE 2026-08-25.**

- Thứ tự bring-up: `pe_alu` -> `pe_local_register_file` ->
  `registered_switchbox` -> `pe_tile` -> one row -> `cgra_cluster` 4x4 ->
  `cgra_cluster_pair`.
- Ràng buộc: 32 PE đồng nhất, cùng opcode decode/latency; không `HAS_MUL`,
  không column capability, không Xilinx primitive trong PE RTL.
- Exit gate: opcode/rounding/predicate/router test PASS; two-cluster shared-PC
  stall assertion PASS; OOC một PE, một cluster, cluster pair.
- Evidence: `reports/v3/M6_CGRA_ARRAY_STATUS.md`; revision-7 fused Phi MAC;
  pair OOC WNS +2.126 ns, 48,487 LUT/6,208 FF, 0 DSP/0 BRAM.

### M7 - Generated Phi path (chỉ phụ thuộc M0 -> **song song được với M5/M6**)

- Thứ tự: `threefry2x32_folded_pipeline` -> `phi_request_queue` ->
  `phi_symbol_builder` -> `phi_response_gearbox` -> `phi_symbol_generator` ->
  `support_phi_symbol_cache` -> `phi_stream_provider` ->
  `phi_operator_normalizer`.
- Golden: `models/v3/phi_generator.py`. `stream_context_router` đã có sẵn Phi
  command port từ M4.
- Exit gate: Threefry KAT, coordinate determinism, two-response conservation,
  backpressure stability, cache fill/replay/invalidate, runtime scale
  bit-exact; OOC xác nhận 1 word/cycle sau fill, normalizer II=1.
- Novelty N3: skid buffer + cache capture/promote interface đóng ở đây; phần
  capture theo TOP-K insert dời M9.

### M8 - Correlation và matrix operators (cần M4+M5+M6+M7 - integration checkpoint lớn nhất)

- Integrate: correlation `Phi^T*r` toàn N, `Phi_T*p`, `Phi_T^T*u`, residual
  update, fused dot/norm collection.
- Exit gate: transaction golden trên tail M/S, random stall, production seed;
  cycle count phải khớp compiler schedule ngoài declared fill/drain.
- Đây là nơi `top.v` bắt đầu được nối thật (M1 seam + M2 DMA + M3 sequencer +
  M4 stream + M5/M6/M7 datapath). Compiler follow-on của M3.6 (compose
  resident eight-program image) phải chốt **sau khi** stream contract M4 lock,
  **trước** M8 integration test.

### M9 - Selection và support ownership (sau M8)

- `topk_selection_unit`, `proxy_candidate_collector`, `support_workspace`,
  `support_state_manager`, `support_coefficient_remapper`.
- Test: tie-break deterministic, no duplicate, append/union/prune,
  current/proposed rollback, slot-map consistency; K32/2K/3K corner PASS;
  mutation chỉ qua atomic commit. Novelty N5 + N3 capture đóng ở đây.

### M10 - Unified restricted refinement (sau M9; cần M5)

- Bring-up: q=1 exact-line-search -> two-step restarted recurrence -> bounded
  q -> strict certificate -> warm-start proxy reuse -> support drop/remap.
- Golden: restricted refinement sweep artifacts của M0.

### M11 - Eight algorithm phase programs (sau M10)

- Tám context program OMP/CoSaMP/IHT/HTP/SP/GP/gOMP/MP chạy trên cùng fabric;
  so với immutable phase golden revision 3. Novelty N4/N6 gắn ở đây.

### M12 - Result writer + DMA drain/abort semantics (sau M11; cần M2)

### M13 - ZCU106 full synth/place/route + timing closure (cuối cùng)

- Chuyển từ OOC sang full implementation; budget doc 01; mọi claim timing chỉ
  sau post-route.

## 4. Trình tự thực thi đề xuất

```text
[1] Phase A  - đóng M4 leaf            (ngắn, ưu tiên cao nhất)
[2] Phase B  - M4.1 DMA seam + N2      (COMPLETE)
[3] M5 arithmetic  ----+
[3'] M7 Phi (song song)+--> [4] M6 CGRA (COMPLETE) --> [5] M8 correlation checkpoint
[6] M9 -> M10 -> M11 -> M12 -> M13     (tuần tự)
```

- M7 chỉ phụ thuộc M0 nên có thể chạy song song với M5/M6 nếu có bandwidth;
  nếu làm tuần tự thì ưu tiên M5 trước (M6 cần resource router của M5 để test
  cluster-level spill/fill thực tế).
- Trước M8, chạy lại compiler gate: compose resident eight-program image từ
  `scheduled_context_library.json` với stream contract M4 đã lock.
- Không milestone nào được claim DONE nếu thiếu status report + evidence log,
  theo rule doc 13 §6.
