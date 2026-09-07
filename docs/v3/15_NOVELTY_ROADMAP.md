# v3 novelty roadmap: cơ chế kiến trúc cho paper

Trạng thái: **N1 và control-layer N2 đã có RTL/evidence M3; N3 generator/cache
và cycle-model phần M7 đã có evidence; N3 TOP-K/M9 cùng N4-N6 vẫn là
planning input**. N2 chỉ hoàn tất toàn hệ thống sau khi scratchpad/resource
router M4-M5 dùng cùng generated guard; chưa được claim coverage cho block chưa
tồn tại. Tài liệu này bổ sung cho
[13_MODULE_IMPLEMENTATION_PLAN.md](13_MODULE_IMPLEMENTATION_PLAN.md) và đối
chiếu prior art trong
[CGRA_OPEN_SOURCE_IMPLEMENTATION_REVIEW.md](../../reports/v3/CGRA_OPEN_SOURCE_IMPLEMENTATION_REVIEW.md)
và [MRCA2_ARCHITECTURE_REVIEW.md](../../reports/v3/MRCA2_ARCHITECTURE_REVIEW.md).

## 1. Nguyên tắc bất biến

1. Fabric giữ bảo thủ. Không packet router, không per-column PC, không
   single-cycle multi-hop kiểu HyCUBE, không cluster PC thứ hai. Các hướng này
   đã bị review bác và phá contract một-`array_context_pc` đã khóa.
2. Novelty đến từ cách fabric tương tác với các resource đặc thù compressed
   sensing (generated Phi, transactional support, certificate) và từ co-design
   compiler/RTL kiểm chứng được, không từ phức tạp hóa interconnect.
3. N1-N5 là semantics-neutral: không đổi paper/hardware golden, không đổi
   threshold, không đổi numeric contract. N6 và **mọi** thay đổi threshold là
   numerical-contract revision: bắt buộc sweep, regenerate golden và hash-chain
   audit theo quy tắc trong
   [GOLDEN_STATUS.md](../../reports/v3/GOLDEN_STATUS.md).
4. Mỗi cơ chế phải báo cùng lúc correctness, total/phase cycles, LUT, FF, BRAM,
   DSP, WNS/TNS và DRC như mọi optimization candidate khác của repo. Một cơ chế
   chỉ được giữ nếu số đo end-to-end biện minh được chi phí của nó.

## 2. Tổng quan sáu cơ chế

| ID | Cơ chế | Milestone | Ngữ nghĩa số học | Golden | Trạng thái hiện tại |
| --- | --- | --- | --- | --- | --- |
| N1 | Guaranteed-commit elastic-static context machine | M3 | không đổi | giữ nguyên | RTL + directed evidence |
| N2 | Load-time context certification sinh từ `architecture_configuration.json` | M3/M4/M5 | không đổi | giữ nguyên | write certifier + scratchpad residency hook có RTL; resource hook chờ M5 |
| N3 | Candidate-symbol capture tại TOP-K insert (bỏ Phi fill pass) | M7-M9 | không đổi | giữ nguyên | M7 cache/model complete; M9 collector pending |
| N4 | Certificate cadence controller trong RTL | M10 | không đổi (policy đã khóa ở M0) | giữ nguyên | blueprint |
| N5 | Transactional sparse state: atom renaming + atomic commit/rollback | M9 | không đổi | giữ nguyên | blueprint |
| N6 | Speculative phase overlap dưới pending certificate | sau M11 | **đổi** (variant profile mới) | regenerate + audit | research gate |

## 3. Chi tiết từng cơ chế

### N1 - Guaranteed-commit elastic-static context machine (M3)

V3 nằm giữa hai cực của literature: static thuần (ADRES/CGRA-ME) và elastic
thuần (STRELA). `cycle_commit` toàn cục join nhiều valid/ready là lớp lai chưa
được formalize. N1 biến nó thành cơ chế đặt tên được và đo được.

Cơ chế:

- context array-control word thêm một bit `guaranteed_commit`;
- compiler chỉ được set bit khi chứng minh tĩnh cycle không thể stall: không
  enabled vector read, không Phi `CONSUME`, không resource `wait_for_ready`,
  không output cần ready;
- RTL bypass commit-join cho các cycle đó, cắt cone fanout của enable;
- một assertion (build `FORMAL`) kiểm tra bit này không bao giờ gặp điều kiện
  stall thật; vi phạm là compiler bug, raise attributed error.

Deliverables:

1. field trong context ISA trước khi ISA freeze (đây là lý do N1 phải vào M3);
2. compiler pass chứng minh và emit bit, kèm report tỷ lệ cycle được đánh dấu;
3. hai đường commit trong `array_context_sequencer`;
4. formal property + directed XSim test bit on/off.

Exit gate: chạy cùng routine library với bit bật/tắt phải bit-exact và
cycle-identical; OOC so sánh WNS/LUT của enable cone hai phiên bản; assertion
không fire trên toàn bộ image hợp lệ.

Paper claim: *elastic-commit static CGRA* — static schedule với commit đàn hồi
chỉ tại các cycle thật sự cần join, chi phí join còn lại được chứng minh bằng
compiler.

### N2 - Load-time context certification sinh từ architecture configuration (M3)

Mọi CGRA công khai tin mapper: schedule sai bank/port/resource thì hỏng im
lặng. M3 đã bắt buộc `architecture_configuration.json` là source of truth; N2
cho generator sinh legality constants để phần cứng chứng nhận context ngay lúc
nạp image, trước khi context có thể đi vào execution path.

Cơ chế:

- generator emit một include chứa reservation constants và checker logic:
  scratchpad bank/port conflict, resource double-booking, route capacity,
  context field range;
- `context_write_certifier` từ chối plane bất hợp lệ trước khi RAM write;
  transaction `0..7,9,8` chỉ tăng high-water mark. Một lệnh finalize riêng scan
  toàn bộ target/fallthrough và chỉ đánh dấu bank certified nếu CFG đóng;
- sequencer từ chối launch image chưa certified; full-bundle guard vẫn tồn tại
  trong FORMAL/test để kiểm tra equivalence. Entry PC được kiểm tra một lần khi
  launch; execution path không còn per-cycle bounds comparator;
- vi phạm tạo attributed error, không silent corruption.

Deliverables:

1. schema mở rộng và validator từ chối field không hợp lệ;
2. generator emit checker include; cấm bản chép tay;
3. hook certification trong context loader/sequencer, scratchpad và
   `array_resource_router`;
4. error code map và directed test tiêm context image cố tình hỏng.

Exit gate: mock-array XSim bắt đúng mã lỗi cho từng lớp vi phạm, kể cả CFG edge
và entry ngoài image; execution trace giữ II=1; overhead LUT/FF/WNS được báo
riêng. M3 hiện đạt integrated post-synthesis WNS `+2.976 ns`, tăng từ
`+0.281 ns` mà không đổi 9 commit/4 stall.

Paper claim: *load-certified statically-scheduled CGRA* — một mô tả kiến trúc
sinh đồng thời RTL constants, MRRG compiler collateral và hardware loader
certificate mà không đặt wide legality guard vào execution critical path.

### N3 - Candidate-symbol capture tại TOP-K insert (M7-M9)

Blueprint hiện tính `C_phi(S) = ceil(M*S/32)` cycle riêng cho support-cache
fill. Nhưng correlation đã stream đúng những symbol đó theo thứ tự column;
với `M=128`, mỗi column chiếm bốn cycle 32-symbol và điểm số TOP-K của nó có
ngay sau khi symbol cuối đi qua.

Cơ chế:

- một skid buffer bốn word 32-bit giữ sign word của column đang stream;
- khi TOP-K insert/replace một candidate, skid buffer được copy vào candidate
  symbol store theo candidate slot; eviction là overwrite slot;
- khi support commit, slot được promote sang active-support cache qua
  `support_slot_map`, không chạy lại Threefry;
- atom giữ lại từ support cũ đã có symbol trong cache; dedicated fill pass chỉ
  còn cho trường hợp không đi qua correlation (nếu có).

Storage bound: candidate 2K=64 column x `ceil(M/32)`=4 word x 32 bit =
8,192 bit, vừa trong budget RAMB hiện có của Phi cache.

Deliverables:

1. cập nhật cycle simulator để model capture và đo fill-pass elimination trên
   từng thuật toán/profile;
2. RTL skid + capture + promote/invalidate path trong M7 cache và M9 collector;
3. conservation property: captured word bit-equal với generator replay cùng
   coordinate; invalidate đúng trên mọi support mutation/rollback/fault.

Exit gate: transaction golden pass; cycle đo được giảm đúng phần `C_phi(S)`
fill trên các thuật toán có LS; không tăng RecMII của correlation schedule.

M7 evidence: cycle simulator revision 3 có switch bật/tắt capture và regression
chứng minh delta tổng cycle đúng tổng số generator word bị loại; duration của
`full_correlation_and_candidate_capture` không đổi. RTL đã có skid bốn word,
candidate store 64 slot, active store 96 slot, promote/replay/invalidate. M9 còn
phải nối TOP-K insertion và đóng conservation ở operator-level transaction.

Paper claim: *single-generator multi-view operator streaming* — sensing
operator sinh tại chỗ phục vụ đồng thời correlation trực tiếp và LS replay mà
không lưu full matrix và không chạy lại PRNG.

### N4 - Certificate cadence controller (M10)

Kết quả M0 (`certificate_cadence_optimization.md`) đo được K32 strict giảm
30.3% (CoSaMP), 29.8% (SP), 17.1% (HTP) tổng cycle nhờ gamma-recurrence trigger
và `reliable_recompute_interval=8`. Hiện nó chỉ tồn tại trong cycle simulator.
N4 đưa nó thành đơn vị kiến trúc trong RTL.

Cơ chế:

- một khối cadence bên trong `restricted_refinement_state` giữ gamma
  recurrence, interval counter và trigger đã khóa ở M0; không PC riêng, không
  phát PE opcode;
- telemetry counter: số full D18 replacement đã chạy/đã skip, exposed qua
  status path hiện có;
- policy/threshold là M0-locked data: N4 **không** được đổi chúng. Đổi
  threshold là numerical-contract revision theo mục 1.

Deliverables: RTL block + tagged event, XSim phase trace so với hardware
golden, telemetry so với cycle simulator trên cùng run.

Exit gate: phase-level hardware golden pass tại S=1..32, 64, 96; cycle đo trong
XSim khớp con số simulation study trong sai số fill/drain đã khai báo.

Paper claim: *certificate-gated lazy verification trong fixed-point hardware* —
giảm số pass ma trận mà không nới điều kiện strict commit.

### N5 - Transactional sparse state: atom renaming (M9)

`support_slot_map` + delta list khi prune về bản chất là register renaming áp
cho atom: atom logic (column index) được rename sang physical slot; commit là
atomic pointer swap; rollback không copy dữ liệu dở.

Cơ chế: implement đúng blueprint M9/M10 hiện có, nhưng formalize thành contract
kiểm chứng được:

- mọi mutation của support/coefficient/residual đi qua proposed state;
- một atomic commit/rollback token duy nhất; không tồn tại thời điểm nào
  consumer đọc được partial state;
- rollback cost là hằng số nhỏ đo được (pointer swap + invalidate), có counter.

Deliverables:

1. `support_state_manager`/`support_coefficient_remapper` theo blueprint;
2. property set: no-partial-visibility, abort tại safe point giữ nguyên
   committed state, slot-map/bitmap/list consistency, không duplicate atom;
3. directed test: mid-transaction abort, certificate-fail rollback, prune
   remap, rollback storm.

Exit gate: K32/2K/3K corner pass; toàn bộ property elaborate và assertion pass
trong XSim; rollback cost được báo bằng số cycle đo.

Paper claim: *transactional sparse state với atom renaming* — semantics
commit/rollback nguyên tử cho trạng thái thuật toán trên CGRA, điều mà các
CGRA framework công khai không model.

### N6 - Speculative phase overlap dưới pending certificate (sau M11)

Vì đã có ping-pong committed/proposed (N5), control sequencer có thể bắt đầu
correlation của outer iteration kế tiếp trên proposed state trong khi
certificate của LS đang chạy; certificate fail thì rollback bằng cơ chế sẵn có.

Ràng buộc cứng:

- đây là **variant profile tường minh mới**, không phải hidden replacement;
  strict path phải bit-exact như trước;
- cần run-configuration revision (encoding profile hiện dùng 2 bit với 3 giá trị)
  và là numerical-contract revision: sweep, regenerate golden cho profile mới,
  review diff, hash-chain audit — theo đúng quy tắc GOLDEN_STATUS.md;
- chỉ bắt đầu sau khi tám base program M11 đã sign-off, vì cần misspeculation
  đo trên chương trình thật.

Exit gate: golden riêng cho profile mới pass; report misspeculation rate và
cycle win theo từng thuật toán; chứng minh strict/balanced/fast không đổi
bit nào.

Paper claim: *certificate-shadowed phase speculation* — control speculation
trên CGRA với rollback bằng transactional state sẵn có.

## 4. Bảng định vị prior art cho paper

| Trục | OpenCGRA / CGRA-ME / ADRES-class | OpenEdgeCGRA | STRELA | HyCUBE / Morpher | v3 |
| --- | --- | --- | --- | --- | --- |
| Operator delivery | ma trận là dữ liệu DMA/memory | DMA + bank pointers | streaming memory nodes | DMA | on-fabric generated `Phi=alpha*S`, candidate-symbol capture, không full-matrix store (N3) |
| Commit model | fully static | static theo column PC | fully elastic valid/ready | static + multi-hop | global atomic cycle-commit với guaranteed-commit bypass được compiler chứng minh (N1) |
| Niềm tin vào mapper | mapper được tin tuyệt đối | mapper được tin | elastic che lỗi timing, không che lỗi reservation | mapper được tin | load-time certification sinh từ cùng architecture configuration (N2) |
| Trạng thái thuật toán | trong software host | trong software | trong software | trong software | transactional sparse state, atom renaming, atomic commit/rollback trong fabric (N5) |
| Kiểm soát số học | không có | không có | không có | không có | certificate-gated commit + cadence controller fixed-point (N4) |
| Speculation | không | không | không | không | certificate-shadowed phase speculation, variant profile (N6) |

Wording bắt buộc khi viết paper: Rademacher ensemble chỉ được nói
*high-probability RIP* kèm empirical seed screening; Vivado XSim assertion
không được gọi là formal proof; cycle từ simulator phải ghi rõ là architecture
estimate cho tới khi có RTL measurement.

## 5. Thứ tự thực hiện và phụ thuộc

```text
M3: N1 (trước context ISA freeze) + N2 (cùng architecture_configuration gate)
M7: N3 phần generator/cache
M9: N5, rồi N3 phần candidate capture/promote
M10: N4
sau M11 sign-off: N6 (revision riêng, golden riêng)
```

N1 và context-layer N2 đã chốt trong M3 vì cả hai đụng context
ISA/architecture configuration trước freeze. M4.1 đã nối runtime residency vào
scratchpad consumer; N2 còn nối resource reservation tại M5. N3 phụ
thuộc TOP-K/collector của M9 cho phần capture nhưng phần skid/cache thuộc M7.
N6 là mục cuối cùng và là mục duy nhất được phép đổi golden.

## 6. Những gì tài liệu này không cho phép

- Không packet router, per-column PC, multi-hop crossbar, cluster PC thứ hai.
- Không đổi threshold/interval/floor nào của M0 dưới danh nghĩa N4.
- Không enable express link bằng tài liệu này; express link vẫn theo decision
  gate riêng trong CGRA review (so sánh mesh-only trước ISA freeze).
- Không claim cơ chế nào là implemented/measured cho tới khi có XSim/OOC
  evidence được ghi vào report v3 tương ứng.
