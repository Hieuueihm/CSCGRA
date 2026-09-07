# 18 - M8 realignment và gate plan A-E

Ngày lập: 2026-08-26. Trạng thái: **kế hoạch thực thi, chưa có việc nào claim
DONE**. Nguồn sự thật về maturity là
`reports/v3/M1_M7_ARCHITECTURE_REAUDIT_2026-08-26.md`; doc này chuyển các
finding của re-audit thành gate có thứ tự, bước cụ thể và exit criteria.

Bối cảnh: M0-M7 COMPLETE ở biên leaf; sản phẩm thật hiện là spine M1-M4 đã
tích hợp cộng ba đảo leaf M5/M6/M7 chưa nối. Ba blocker trước M8:

1. cycle simulator đứng trên timing cũ (không phải số đo);
2. M8 correlation phụ thuộc TOP-K nhưng TOP-K nằm ở M9 (compiler đã block
   kernel correlation vì `TOPK_PUSH` planned);
3. margin tích hợp mỏng: harness M1-M4 WNS +0.643 ns trước khi gắn M5/M6/M7.

## Gate A - Timing authority repair — COMPLETE 2026-08-26

1. **A1**: loại bỏ timing literal trong `models/v3/architecture_simulator.py`
   (ví dụ `reduction_latency_cycles = 4` trong khi measured là 5; scalar
   divide 8 trong khi measured 28/28; vector sidecar latency/II lệch JSON).
   Simulator phải đọc latency/II từ architecture authority
   (`compiler/v3/architecture_configuration.json` /
   `reports/v3/architecture_latency_ii.json`, các op `timing_status:
   measured`) thay vì giữ default rời — một nguồn sự thật, hết drift.
2. **A2**: re-run toàn bộ complete-architecture cycle simulation
   (`scripts/sim/v3_architecture_cycles.py`, 72 case K4/K8/K32) và
   regenerate `reports/v3/architecture_cycle_simulation/*`.
3. **A3**: diff kết luận certificate cadence
   (`certificate_cadence_optimization.md`). Nếu cadence policy thay đổi →
   đây là M0-authority event: regenerate architecture package + hai golden
   suite + hash-chain audit theo Regeneration rule của
   `reports/v3/GOLDEN_STATUS.md`. Nếu không đổi → ghi rõ "cadence
   conclusions hold under measured timing" kèm bảng so sánh.
4. **A4**: cập nhật phần timing assumptions của doc 14 và viết
   `reports/v3/TIMING_AUTHORITY_REPAIR_STATUS.md`.

Exit gate A: simulator không còn literal timing lệch measured JSON; 72 case
regenerated; cadence diff được review và kết luận ghi thành văn.

## Gate B - M9a: kéo TOP-K selection lên trước M8 — COMPLETE 2026-08-26

Lý do kiến trúc: theo N3, correlation full-N phải đổ qua normalizer vào TOP-K
để không lưu full proxy — consumer của M8 chính là TOP-K. Tách M9 thành:

- **M9a (làm ngay, trước/song song M8)**: `topk_selection_unit` + collector
  interface tối thiểu đủ làm correlation consumer;
- **M9b (giữ nguyên lịch M9)**: support workspace/state manager/remapper,
  transactional sparse state (N5), candidate-symbol capture đầy đủ (N3).

Các bước:

1. **B1**: contract doc kiểu doc 17 cho M9a (numeric + interface + latency
   ledger). Semantics khóa theo `models/v3/hardware.py` `_rank`: chọn theo
   `-|value|`, **tie-break index nhỏ hơn thắng**, deterministic tuyệt đối;
   K tối đa 32, ngõ vào stream S27 normalized + index; `TOPK_PUSH` latency
   2 / II 1, `TOPK_COMMIT` latency 1 (đã khóa trong JSON); tagged
   transaction, side effect chỉ tại `cycle_commit`; chừa capture port cho
   N3 (đóng tại M9b, ghi rõ unimplemented).
2. **B2**: RTL leaf + TB replay transaction golden + random backpressure +
   property elaboration + OOC (dự kiến DSP 0, BRAM 0 — sorter K32 bằng
   LUT/FF; đặt gate chính xác trong TCL như tiền lệ M3/M5). Flip
   `TOPK_PUSH`/`TOPK_COMMIT` sang `status: implemented` trong architecture
   configuration — một lần regeneration duy nhất cho cả gate.
3. **B3**: compiler mở khóa kernel correlation; chạy lại compiler gate
   M3.6: **4/4 kernel executable** thay vì 3/4.

Exit gate B: TOP-K leaf PASS sim/assertion/property/OOC; mask/JSON
regenerated một lần; compiler map đủ bốn kernel với route reservation hợp lệ.

## Gate C - M8 operator harness — COMPLETE 2026-08-26

1. **C1**: harness tích hợp nối thật M4 stream + M5 sidecar/reduction + M6
   cluster pair + M7 Phi + M9a TOP-K. Timing plan bắt buộc trước khi nối:
   register slice tại các seam `array_resource_router`/sidecar/reduction
   merge, pblock theo cluster; gate WNS trung gian cho harness mở rộng
   >= +0.5 ns, gate cuối M8 >= +1.0 ns (tiền lệ integrated gate M3).
2. **C2**: exit gate M8 giữ nguyên doc 13: transaction golden trên tail
   M/S, random stall, production seed; **cycle == compiler schedule** ngoài
   declared fill/drain — điều kiện này chỉ có nghĩa sau Gate A.

Evidence đóng gate: sequencer replay PC 10-29, tail `M=33/S=3`, verification seed 23,
random dependency stalls, normal/property XSim PASS; OOC WNS +1.029 ns với
89,408 LUT, 20,564 FF, 20 DSP và 16 RAMB36.

## Gate D - Documentation reconciliation batch (P1, song song Gate C)

Gộp một lần sửa, một lần review:

1. `reports/v3/MRCA2_ARCHITECTURE_REVIEW.md`: ghi supersession — "multiply
   lanes ở column 0-1" đã bị thay bằng PE đồng nhất + sidecar 16 lane
   (doc 01/06 là authority).
2. Thống nhất plane numbering resource/phase giữa doc 00/01 và doc 06 §5;
   thống nhất wording express-link (config switch và datapath hard-reject là
   hai lớp của cùng một chính sách); cập nhật trạng thái N2 resource hook
   trong doc 15 (đã đóng ở M5); các STATUS còn cite minor 29 → 30.
3. Cập nhật BRAM scaling JSON từ số đo (re-audit: model ~20 vs đo ~31
   non-Phi, +55%).
4. Paper positioning: bổ sung review thật cho RipTide/SNAFU/Pillars (cùng
   vùng trade-off hybrid elastic) hoặc thu hẹp câu chữ claim trong review
   doc — không claim breadth chưa đọc.

## Gate E - M9b/M10 trở đi

Theo roadmap doc 13 hiện hành, cộng một mục P2 phải đóng trước M11: directed
test chứng minh load path cho hằng số thuật toán (IHT step size, gOMP group
size, SP workspace policy) qua run-configuration revision 4.

## Quy tắc thực thi chung

- Mỗi gate tuân thủ convention doc 13 §6: RTL + assertion + `files.f`,
  XSim qua script chuẩn, property elaboration, OOC + gate tài nguyên chính
  xác, status report — không claim thiếu evidence.
- Mọi thay đổi mask/ISA/JSON trong một gate gộp thành **một** lần
  regeneration + hash audit.
- Thứ tự bắt buộc: A → B → C; D song song C; E sau C.
