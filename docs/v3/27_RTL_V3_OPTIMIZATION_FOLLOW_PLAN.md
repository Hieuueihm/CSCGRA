# RTL v3 Optimization Follow Plan

Ngày lập: 2026-09-06
Trạng thái chung: `P1_IN_PROGRESS`

Tracker chính để follow sửa RTL v3, đóng numerical closure, tối ưu phần cứng và
tạo evidence cho paper. Cập nhật checkbox, report và kết luận sau mỗi gói.

## Nguyên tắc sign-off

- Không ghép correctness, cycles, PPA và power từ khác source snapshot.
- Tách RTL/fixed-model, fixed/float và application-quality thành ba gate.
- Không sửa golden, threshold hoặc chọn policy theo từng sample để tạo PASS.
- Mỗi tối ưu báo quality, regression, cycles, LUT/FF/BRAM/DSP và routed timing.
- OOC/post-synthesis PASS không thay final route, DRC/PDRC; LUT không suy ra energy.

## Baseline và dependency

- `B0`: production hiện tại, giữ numerical `423/432` làm mốc.
- `D22 candidate`: model `432/432`, D22/F18, S31/F23, ACC70; chưa là RTL PASS.
- `B1`: baseline đầu tiên đạt quality + bit-exact RTL + K32 E2E + full-M13 evidence.
- Thứ tự: `P0 -> P1/P2 -> B1 -> P3 -> P4 -> P5 -> P6`.
- Mọi A/B sau B1 dùng cùng numeric policy, workload và implementation constraints.

## P0 - Snapshot và profiling

Trạng thái: `COMPLETE`

- [x] Freeze RTL/include/filelist, compiler/model, context/golden và constraints.
- [x] Lưu dataset/seed manifest, tool versions, dirty và untracked inventory.
- [x] Verify đúng input, policy và threshold của D22 candidate.
- [x] Review stale canonical hashes và hai assertion cycle/revision cũ.
- [x] Thêm monitor phase/total cycles, useful PE work và resource stalls.
- [x] Thêm monitor Phi generate/cache/replay, selection, DMA và result drain.
- [x] Sanity-check counter tại `valid && ready`; tránh cộng stall chồng nhau.
- [x] Chạy B0 correctness với report path được truyền tường minh.
- [x] Chạy full-M13 synth/route B0 hoặc ghi rõ `OPEN/FAIL`.

Gate G0: snapshot reproduce được, counter hợp lệ, correctness/PPA status rõ ràng.

P0.1/P0.2 checkpoint, 2026-09-06:

- Frozen source is stored in
  `reports/v3/optimization_follow_20260906/p0/source_final`.
- Source-tree and archive SHA-256 values are authoritative in the frozen
  manifest and the external P0 snapshot report; do not copy them back into
  this tracked source document after freeze.
- Archive and manifest verification: PASS, zero changed files.
- Toolchain, dataset manifests and complete dirty/untracked inventory recorded
  in `reports/v3/optimization_follow_20260906/p0/SNAPSHOT.md`.
- Historical D22 `432/432` remains carry-in only; the P0.3 bound replay below
  is the current command, policy, threshold, source and input evidence.

P0.3 checkpoint, 2026-09-06:

- Bound D22 replay passed `432/432` application-quality checks against source
  SHA-256 `ad378a26cb8c9723775cd2e7a6f1d0a7b321aec8a36c9c60ca0ed33c7b5c3be4`.
- Input manifest, command, policy, thresholds and evidence hashes are recorded
  in `reports/v3/optimization_follow_20260906/p0/D22_PROVENANCE_AUDIT.md`.
- Support equality is `429/432`; three support-changing cases remain mandatory
  P1 work. D22 is not yet an RTL or bit-exact PASS.

P0.4 checkpoint, 2026-09-06:

- Regenerated smoke, scale and correctness phase goldens through the canonical
  generator after proving staged payload changes are metadata-only.
- Replaced the stale continuation-cycle literal with compiler authority and
  bound revision checks to context revision `9` and RTL minor revision `36`.
- Full V3 Python regression `141/141`, all three golden `--check` runs and the
  expanded reference-contract checker pass.

P0.5 checkpoint, 2026-09-06:

- Added a synthesizable run-level monitor for total/phase/execution cycles,
  array commits/stalls, issued non-NOP PE cycles/slots and exclusive resource
  stalls.
- Directed monitor, M5, M6 and M8 regressions pass; small and scale matrices
  both pass `24/24` with `0/48` cycle deltas and zero counter-invariant failures.
- Full semantics, evidence paths and hashes are recorded in
  `reports/v3/optimization_follow_20260906/p0/P05_EXECUTION_PROFILE_MONITOR.md`.

P0.6 checkpoint, 2026-09-07:

- Added thirteen synthesizable accepted-event counters for Phi generation,
  cache/replay, selection, AXI DMA and result drain.
- Directed M5/M6/M7/M8 and OMP smoke pass; small and scale matrices both pass
  `24/24`, with `0/48` cycle deltas and zero counter-audit violations.
- Full semantics, evidence paths and hashes are recorded in
  `reports/v3/optimization_follow_20260906/p0/P06_EXECUTION_EVENT_PROFILE_MONITOR.md`.

P0.7 checkpoint, 2026-09-07:

- Extended directed tests prove valid/ready acceptance, run-start reset
  priority, idle suppression and exclusive wait/stream/resource attribution.
- Reusable matrix audit passes `48/48`, with all thirteen event fields present,
  `0/48` cycle deltas and zero counter-contract violations.
- Full semantics, evidence paths and hashes are recorded in
  `reports/v3/optimization_follow_20260906/p0/P07_COUNTER_CONTRACT_AUDIT.md`.

P0.8 checkpoint, 2026-09-07:

- Froze the post-P0.7 source and replayed the production numeric policy with
  explicit cache, manifest, dataset-selection and output paths.
- B0 reproduces `423/432`; all numeric event totals are zero, source integrity
  passes before/after, and numerical correctness remains `FAIL/OPEN`.
- Full command, failure list, evidence paths and hashes are recorded in
  `reports/v3/optimization_follow_20260906/p0/P08_B0_CORRECTNESS_REPLAY.md`.

P0.9 checkpoint, 2026-09-07:

- Managed full-M13 preflight passes for Vivado 2018.1, 100 MHz constraints and
  the explicit P0.6 `48/48` RTL correctness evidence.
- Full synthesis/route is `OPEN_NOT_RUN` because B0 numerical correctness is
  `423/432 FAIL`; no LUT/FF/BRAM/DSP or timing claim is made.
- P0/G0 is complete with correctness and PPA status explicitly separated in
  `reports/v3/optimization_follow_20260906/p0/P09_FULL_M13_PPA_STATUS.md`.

Evidence: Snapshot=`reports/v3/optimization_follow_20260906/p0/source_p08_b0/manifest.json` | D22=`reports/v3/optimization_follow_20260906/p0/D22_PROVENANCE_AUDIT.md` | Canonical=`reports/v3/optimization_follow_20260906/p0/P04_CANONICAL_ASSERTION_AUDIT.md` | Profile=`reports/v3/optimization_follow_20260906/p0/P05_EXECUTION_PROFILE_MONITOR.md` | Events=`reports/v3/optimization_follow_20260906/p0/P06_EXECUTION_EVENT_PROFILE_MONITOR.md` | CounterAudit=`reports/v3/optimization_follow_20260906/p0/P07_COUNTER_CONTRACT_AUDIT.md` | Correctness=`B0_423_OF_432_FAIL_OPEN` | Synth/route=`OPEN_NOT_RUN` | Decision=`ENTER_P1`

## P1 - Numerical RTL closure

Trạng thái: `P1_8_HELDOUT_FAILURE_OPEN`

- [x] Tái chạy production và D22 trên cùng 432 check, threshold không đổi.
- [x] Đóng băng held-out blocks/seeds trước khi tune thêm.
- [x] Audit 7 case đổi selection và 2 case same-support; không mặc định lỗi Top-K.
- [x] Map D22/S31/ACC70 vào compiler và generated architecture parameters.
- [x] Audit multiply intermediate, accumulator, rounding, saturation và divide.
- [x] Suy lại certificate/floor trong `normal_residual_checker.v` theo numeric unit.
- [x] Định nghĩa scratchpad/DMA/result packing cho width mới.
- [x] Tăng revision và certifier compatibility nếu semantics thay đổi.
- [x] Regenerate candidate golden qua reference chain; không sửa tay.
- [x] Chạy directed packing tests và production transport/result guards.
- [ ] Đóng held-out quality `3888/3888` trên manifest đã khóa.
- [ ] Đóng candidate RTL/model bit-exact cho output, support và termination.
- [ ] Sau D22 RTL PASS, sweep mixed precision từng boundary một.

Gate G1: quality + held-out đạt; RTL khớp model kể cả output và termination.

P1.1 checkpoint, 2026-09-06:

- Froze one new source baseline and ran production and D22 sequentially with
  identical explicit cache, manifest, dataset axes, slices, block selection,
  geometry, Phi seed, algorithm set and unchanged quality thresholds.
- Production reproduces `423/432`; D22 reproduces `432/432`. Both match their
  prior result hashes, source verification passes before/after both runs and
  all numeric event totals remain zero.
- D22 support equality remains `429/432`; it is a model-quality candidate, not
  an RTL/model bit-exact PASS. Full evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P11_PRODUCTION_D22_NUMERIC_COMPARISON.md`.

P1.2 checkpoint, 2026-09-06:

- Froze 162 volume-qualified blocks from held-out slices `67/112` and three
  independently hash-derived 64-bit Phi seeds; slice `90` and seed `37` are
  excluded from this set.
- The manifest is candidate-independent, stores source/block hashes and freezes
  the unchanged application thresholds for 3888 planned evaluations per
  candidate.
- Deterministic regeneration is byte-identical and the full V3 Python
  regression passes `144/144`. Evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P12_HELDOUT_MANIFEST_FREEZE.md`.

P1.3 checkpoint, 2026-09-06:

- Reproduced all nine B0 failures and matched the independent floating oracle
  on all nine under a provenance-bound source snapshot.
- Seven first selection changes are caused by changed upstream LS/proxy/
  tentative magnitudes; the Top-K comparator consistently selects the larger
  fixed magnitude. Two cases have no first selection change and fail through
  coefficient/residual or termination precision.
- Exact D22 with residual shift 16 passes all `9/9`; D22 with old shift 14
  passes `8/9`, proving certificate-unit remapping is required. Full evidence
  is recorded in
  `reports/v3/optimization_follow_20260906/p1/P13_NUMERICAL_FAILURE_MECHANISM_AUDIT.md`.

P1.4 checkpoint, 2026-09-06:

- Added explicit active production and closure-candidate D22 numeric profiles
  to architecture authority; generated candidate D22/S31/ACC70/shift16 macros
  and compiler value types without activating the widened datapath.
- All 19 context images and the transaction/control goldens remain
  byte-identical; active macros remain D18/S27/ACC62. Metadata changes are
  limited to the new profile authority and derived architecture hash.
- Targeted tests pass `29/29`; full V3 Python regression passes `145/145`.
  Evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P14_D22_ARCHITECTURE_MAPPING.md`.

P1.5 checkpoint, 2026-09-06:

- Parameterized the exact folded multiplier for S27 and S31 using bounded
  27x18/27x14 primary products plus small signed cross-products; II and active
  production response latency remain unchanged.
- Widened only the internal shared dot/norm accumulation domain to 64/72 bits
  and added fail-closed ACC62/ACC70 saturation plus resource fault instead of
  silent wrap. This semantic change advances RTL minor revision 36 to 37.
  Local Phi L48 remains sufficient at N1024/M128 with a minimum six-bit margin
  for D22.
- Recorded profile-specific divide latency 15/17, verified 101-bit D22 divider
  work width, ties-away rounding, signed saturation and divide-by-zero through
  a candidate-only parameterized XSim bench without activating D22 macros.
- Candidate XSim, production M5 with assertions and current M8 integration all
  PASS under generated RTL minor revision 37. Architecture configuration schema
  v5 validates after adding profile-specific divide latency, and the full V3
  Python regression passes `147/147`. Evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P15_ARITHMETIC_BOUNDARY_AUDIT.md`.

P1.6 checkpoint, 2026-09-07:

- Added `certificate_limit_unit.v` as the single RTL authority for relative
  certificate limit, absolute floor, support floor and measurement floor. Both
  the normal checker and dispatcher use the same unit; duplicated literal
  floor/shift policy is removed.
- Generated production and D22 certificate macros from architecture authority.
  Production strict residual shift remains 14; the inactive D22 candidate uses
  shift 16. Both profiles have zero energy-domain scale delta.
- Made Phi normalization shift signed and fail-closed. The run-configuration
  contract now accepts data-normalizer exponents through 11 and rejects 12..15
  with error `0x43` at word 15. This advances run-configuration revision 5 to 6
  and RTL minor revision 37 to 38 without activating D22.
- Machine audit, M2/M7/M10 directed assertion XSim, M10 dispatcher integration,
  M8 functional integration/replay and full Python regression `148/148` PASS.
  Project consistency has no remaining revision/authority mismatch and reports
  only the five pre-existing M11 phase instruction-count items.
  Full evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P16_CERTIFICATE_NORMALIZER_CLOSURE.md`.

Evidence: Model=`P11_PRODUCTION_D22_NUMERIC_COMPARISON.md` | Held-out=`P12_HELDOUT_MANIFEST_FREEZE.md_IDENTITIES_FROZEN_NOT_RUN` | FailureAudit=`P13_NUMERICAL_FAILURE_MECHANISM_AUDIT.md` | Mapping=`P14_D22_ARCHITECTURE_MAPPING.md` | Arithmetic=`P15_ARITHMETIC_BOUNDARY_AUDIT.md` | Certificate=`P16_CERTIFICATE_NORMALIZER_CLOSURE.md` | RTL regression=`P16_M2_M7_M10_M8_PASS` | PPA delta=`NOT_MEASURED` | Decision=`CONTINUE_P1_7_PACKING`

P1.7 checkpoint, 2026-09-07:

- Defined candidate-only D22/S31/ACC70 packing authority: 3/word with 6 zero
  bits, 2/word with 10 zero bits and 1/word with 2 zero bits respectively.
- Added fail-closed candidate scratchpad and DMA leaves, ACC70 threshold
  transport, and a `DATA_W=31` result-writer instance without changing the
  active production hierarchy or revision 6 ABI.
- Candidate XSim, candidate result serialization, Python packing tests `5/5`,
  full Python regression `153/153`, production M4 and production M12 guards all
  PASS. Evidence is recorded in
  `reports/v3/optimization_follow_20260906/p1/P17_PACKING_CLOSURE.md`.
- Synthesis/timing/PPA remain not run. Candidate golden regeneration and full
  D22 RTL/model closure remain P1.8 work.

Evidence: Packing=`P17_PACKING_CLOSURE.md` | Contract=`runs/p17/p17_packing_contract.json` | CandidateXSim=`runs/p17/p17_candidate_packing_xsim.log` | Decision=`ENTER_P1_8_GOLDEN_AND_D22_RTL_CLOSURE`

P1.8 checkpoint, 2026-09-07:

- Candidate `quality_d22` golden regeneration and provenance audit pass: `26/26`
  serialized payloads and `208/208` structural traces. The single controlled
  CoSaMP solver-limit divergence remains diagnostic and is not hidden by a
  tolerance.
- The frozen held-out BrainWeb source-domain sweep covers `162` blocks × `3`
  Phi seeds × `8` algorithms = `3888` evaluations. It currently passes
  `3873/3888`; all `15` failures are CoSaMP, including one refinement rollback.
  Numeric event totals remain zero, but exact support is only `3861/3888` and
  the worst quality gaps are outside the application gate.
- G1 is therefore `OPEN`: D22 remains inactive, and no RTL/model closure,
  synthesis, timing, LUT/FF/BRAM/DSP or 100 MHz claim is made.
- Next checkpoint is a provenance-bound CoSaMP first-divergence audit followed
  by the already-defined candidate profile/policy sweep on the same frozen
  manifest. Thresholds, geometry, blocks and Phi seeds must not change.

Evidence: CandidateGolden=`reports/v3/optimization_follow_20260907/p1_8/P18_CANDIDATE_GOLDEN_AUDIT.md` | Heldout=`reports/v3/optimization_follow_20260907/p1_8/heldout_d22/summary.md` | Records=`reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl` | Decision=`HOLD_D22_AUDIT_COSAMP_FAILURES`

P1.8 audit checkpoint, 2026-09-07:

- The provenance-bound CoSaMP audit reproduces `15/15` held-out failures.
  First divergence is `PROXY_IDENTIFY` in `9/15` cases and `LS_PRUNE` in
  `6/15` cases; numeric event totals remain zero.
- The six existing numerical candidates were screened on the same failure set;
  none closes it. `quality_d22` remains `0/15` on this set. Increasing only
  the refinement budget to `256`, `512` or `1024` improves only `1/15` cases;
  `14/15` remain failing, so the blocker is not a missing iteration budget.
- This is a diagnostic PASS, not a quality PASS. No existing candidate is
  promoted, D22 remains inactive, and no RTL/model, synthesis, timing, LUT,
  FF, BRAM, DSP or 100 MHz claim is made.
- Next checkpoint is a separately named, hardware-realizable CoSaMP numerical
  policy candidate. It must pass the `15`-case screen, then the complete
  frozen `3888` sweep, before candidate golden regeneration and RTL closure.

P1.8 candidate experiment checkpoint, 2026-09-07:

- Candidate `cosamp_data_d27_shift18_r32` was tested in an isolated software
  harness. It raises the data/residual path to `D27/F23`, keeps `S31/F23` and
  `ACC70`, sets strict certificate shift `18` and reliable recompute interval
  `32`; algorithm ordering and the bounded `128`-step budget are unchanged.
- Result is `15/15` on the frozen CoSaMP failure set and `15/15` on controls,
  with zero numeric events and zero rollback. The complete frozen quality
  matrix is `3888/3888`; CoSaMP is `486/486` exact support. Global exact
  support is `3883/3888` due five unchanged non-CoSaMP baseline mismatches.
- Numerical quality gate is closed for the CoSaMP candidate. D22 remains
  inactive; proceed to candidate golden/model closure, then RTL closure.
- Evidence:
  `reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_d27_r32/`
  and `reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_full_v2/`.
  Next action is candidate golden/model closure; do not activate D22 yet.

Evidence: Audit=`reports/v3/optimization_follow_20260907/p1_8/P18_COSAMP_FAILURE_AUDIT.md` | Traces=`reports/v3/optimization_follow_20260907/p1_8/cosamp_failure_audit/summary.md` | ProfileScreen=`reports/v3/optimization_follow_20260907/p1_8/candidate_profile_screen/summary.md` | FullCandidate=`reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_full_v2/summary.md` | Decision=`CANDIDATE_QUALITY_CLOSED_ENTER_GOLDEN_MODEL_CLOSURE`

## P2 - K32 và capacity closure

Trạng thái: `NOT_STARTED`

- [ ] Lập bảng capacity theo phase: K, 2K, 3K union, prune và coefficients.
- [ ] Audit Top-K 64 entry, symbol-slot 6 bit và nơi nào thực sự cần 96 entry.
- [ ] Audit address/count/sentinel và ownership tại full capacity.
- [ ] Test index 1023, duplicate/exclusion, overlap min/max, eviction, epoch wrap.
- [ ] Test reset/restart và DMA/Phi/result backpressure dài.
- [ ] Chạy M16/N24/K4, M64/N256/K8 và M128/N1024/K32.
- [ ] Chạy K1/K16, legal tail geometry, 8 algorithms và valid profiles.
- [ ] Invalid geometry/profile phải reject đúng contract.
- [ ] So support, coefficients, output, residual, header, stop reason và iterations.

Gate G2: K32 E2E PASS, không overflow ngầm. `G0 + G1 + G2 = B1`.

Evidence: Capacity= | Regression= | B1 full-M13= | Decision=

## P3 - Top-K architecture A/B

Trạng thái: `BLOCKED_BY_B1`

- [ ] Xác nhận selection là bottleneck từ hierarchy/timing/stall của B1.
- [ ] Khóa tie-break, duplicate/exclusion, ordered-read và commit contract bằng test.
- [ ] Giữ stable candidate-Phi slot; không reuse khi consumer cũ chưa xong.
- [ ] A/B sorted insertion với partitioned exact Top-K + deterministic merge.
- [ ] A/B heap/tournament + ordered drain nếu leaf-level có lợi.
- [ ] Test K4/K8/K16/K32 và adversarial score streams.
- [ ] Đo insertion II, selection cycles và total reconstruction cycles.
- [ ] Leaf screen -> full-M13 synth -> route shortlist.

Gate G3: exact output/ownership và full-design Pareto. Mục tiêu screen, không phải
claim: `>=20%` LUT selection hoặc `>=5%` LUT M13; latency tăng chỉ chấp nhận nếu
area/energy tốt hơn rõ ràng.

Evidence: Variants= | Winner/rejection= | Full-M13 delta=

## P4 - PE, Phi và programmability ablation

Trạng thái: `BLOCKED_BY_B1`

- [ ] PE A/B: 32 full, 16+16, 8+24; mask đồng bộ RTL/compiler/certifier.
- [ ] Thử ít full PE hơn chỉ khi compiler map thành công.
- [ ] Phi A/B: regenerate-only, capture/replay, compressed stored symbols.
- [ ] Giữ cùng matrix/seed/precision; tính cache/generator/ports/refill/setup.
- [ ] Báo cold-start và steady-state tại cùng matrix reuse count.
- [ ] Nếu stored Phi spill external memory, tính traffic và latency.
- [ ] Single-program specialization thực sự vs eight-program fabric.
- [ ] Negative test full-only opcode trên Phi-only PE.
- [ ] Cross các winner để đo interaction; không cộng phần trăm tiết kiệm.

Gate G4: matched-quality full-M13 PPA/latency cho PE, reuse và programmability.

Evidence: PE= | Phi/cache= | Programmability= | Decision=

## P5 - Overlap và context

Trạng thái: `WAIT_FOR_PROFILE`

- [ ] Chỉ chọn stall chiếm tỷ lệ lớn từ P0/B1 profile.
- [ ] Thử skid/elastic/double buffer nhỏ trước khi pipeline rộng.
- [ ] Giữ atomic commit, tag/epoch và ready/valid contract.
- [ ] Test flush/reset/restart với outstanding operations và backpressure dài.
- [ ] Đo occupancy, useful overlap và total reconstruction latency.
- [ ] Rebuild context images và ghi occupancy/headroom.
- [ ] Ưu tiên routine/schedule reuse trước ISA compression hoặc tăng depth.

Gate G5: latency/energy tổng tốt hơn, không chỉ chuyển bottleneck.

Evidence: Profile target= | Variant= | Result= | Decision=

## P6 - Final sign-off và paper evidence

Trạng thái: `BLOCKED_BY_FINALIST`

- [ ] Bind mỗi row với source/variant, compiler/context/golden và input hashes.
- [ ] Báo quality, correctness, iterations, phase và total cycles.
- [ ] Báo LUT theo một định nghĩa, FF/BRAM/DSP và full-design scope.
- [ ] Báo routed WNS/TNS/WHS/THS, failing/unconstrained paths, DRC/PDRC.
- [ ] Mục tiêu 100 MHz setup/hold sạch; `+0.2 ns WNS` là margin, không phải fact.
- [ ] Dùng cùng implementation recipe; multi-seed nếu flow hỗ trợ.
- [ ] Power có activity/assumptions; không đủ thì ghi `NOT_MEASURED`.
- [ ] Tách estimated result khỏi board-measured result.
- [ ] Cập nhật system overview, architecture và paper plan theo winner.
- [ ] Ghi đúng scope: assertion simulation, source-domain MRI, fastMRI `NOT_RUN`.

Gate G6: B1 và winner reproduce được; claim chưa có evidence để `OPEN`.

## Change log

| Date | Phase | Change | Evidence | Decision |
| --- | --- | --- | --- | --- |
| 2026-09-06 | Plan | Tạo tracker tối ưu RTL v3 | Review source/report hiện có | Bắt đầu P0 |
| 2026-09-06 | P0.1 | Đóng flow-contract refactor và chuẩn bị byte snapshot | `reports/v3/optimization_follow_20260906/p0/` | Freeze rồi verify trước profiling |
| 2026-09-06 | P0.1/P0.2 | Freeze 427 files, toolchain, dataset và dirty inventory | `reports/v3/optimization_follow_20260906/p0/SNAPSHOT.md` | PASS; tiếp tục P0.3 D22 provenance |
| 2026-09-06 | P0.3 | Bind D22 command, input manifest, numeric policy và thresholds vào frozen source | `reports/v3/optimization_follow_20260906/p0/D22_PROVENANCE_AUDIT.md` | PASS model-quality 432/432; 3 support mismatch chuyển sang P1; chưa là RTL PASS |
| 2026-09-06 | P0.4 | Refresh canonical hashes và thay stale cycle/revision literals bằng authority | `reports/v3/optimization_follow_20260906/p0/P04_CANONICAL_ASSERTION_AUDIT.md` | PASS 141/141 và 3/3 golden reproducibility; tiếp tục counter monitor |
| 2026-09-06 | P1.1 | So sánh production và D22 trên cùng frozen source, 432 checks và threshold không đổi | `reports/v3/optimization_follow_20260906/p1/P11_PRODUCTION_D22_NUMERIC_COMPARISON.md` | Production 423/432; D22 432/432 model-quality; tiếp tục freeze held-out P1.2 |
| 2026-09-06 | P1.2 | Đóng băng held-out slices, blocks, Phi seeds và threshold trước tuning | `reports/v3/optimization_follow_20260906/p1/P12_HELDOUT_MANIFEST_FREEZE.md` | 162 blocks, 3 seeds, 3888 planned evaluations; regeneration và 144/144 tests PASS; tiếp tục P1.3 |
| 2026-09-06 | P1.3 | Phân loại 7 selection-changing và 2 non-selection B0 failures với exact D22 trace | `reports/v3/optimization_follow_20260906/p1/P13_NUMERICAL_FAILURE_MECHANISM_AUDIT.md` | 9/9 reproduced, oracle 9/9, D22 9/9; không sửa Top-K; tiếp tục D22 architecture mapping |
| 2026-09-06 | P1.4 | Map D22/S31/ACC70/shift16 thành closure candidate trong architecture, RTL macro và compiler type authority | `reports/v3/optimization_follow_20260906/p1/P14_D22_ARCHITECTURE_MAPPING.md` | Active production không đổi, 19/19 context image identical, 145/145 tests PASS; tiếp tục P1.5 arithmetic audit |
| 2026-09-06 | P1.5 | Đóng multiply/accumulator/rounding/saturation/divide contract cho production và D22 candidate | `reports/v3/optimization_follow_20260906/p1/P15_ARITHMETIC_BOUNDARY_AUDIT.md` | Schema v5; revision-37 candidate/M5/M8 PASS; Python 147/147; D22 chưa active; tiếp tục P1.6 certificate/floor |
| 2026-09-07 | P1.6 | Hợp nhất certificate/floor authority và khóa legal Phi exponent/normalizer shift | `reports/v3/optimization_follow_20260906/p1/P16_CERTIFICATE_NORMALIZER_CLOSURE.md` | Revision 38/6; M2/M7/M10/M8 và Python 148/148 PASS; D22 chưa active; tiếp tục P1.7 packing |
| 2026-09-07 | P1.7 | Đóng authority packing D22/S31/ACC70 cho scratchpad, DMA và result path | `reports/v3/optimization_follow_20260906/p1/P17_PACKING_CLOSURE.md` | Candidate packing PASS; D22 chưa active; tiếp tục P1.8 |
| 2026-09-07 | P1.8 | Audit candidate golden, held-out BrainWeb và CoSaMP first divergence/profile screen | `reports/v3/optimization_follow_20260907/p1_8/` | Golden PASS; held-out FAIL 3873/3888 với 15 lỗi CoSaMP; D22 giữ inactive; chưa synth |
| 2026-09-07 | P1.8 candidate | Thử policy `D27/F23/S31/F23/ACC70`, shift `18`, reliable interval `32` trên 15 lỗi, controls và full frozen matrix | `reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_d27_r32/` + `cosamp_policy_candidate_full_v2/` | CoSaMP `486/486`, quality `3888/3888`, zero events/rollback; exact support global `3883/3888` do 5 mismatch baseline ngoài CoSaMP; vào golden/model closure, D22 inactive |
