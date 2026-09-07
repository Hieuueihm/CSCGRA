# 21 - M9b support management contract

Ngày lập: 2026-08-27. Trạng thái: implementation gate đang mở; capability vẫn
`planned` cho tới khi normal/property XSim và OOC đều PASS.

## 1. Authority và ownership

- RTL owner: `support_state_manager`; storage owner: `support_workspace`.
- Candidate owner: `proxy_candidate_collector`; coefficient rename owner:
  `support_coefficient_remapper`.
- Resource opcodes: `SUPPORT_CLEAR`, `SUPPORT_APPEND`, `SUPPORT_UNION`,
  `SUPPORT_MEMBERSHIP`, `SUPPORT_GATHER`, `SUPPORT_SCATTER`, `SUPPORT_COMMIT`,
  `SUPPORT_ROLLBACK`.
- Hardware không decode program/algorithm ID. Context chọn opcode, count source,
  candidate slot và output route.
- Baseline: N1024, K32, candidate 2K=64, work 3K=96, index 10 bit, coefficient
  S27.

## 2. Transactional state

- Committed và proposed nằm ở hai bank. Consumer chỉ thấy committed bank.
- `SUPPORT_CLEAR` mở transaction rỗng. `SUPPORT_APPEND` tạo proposed từ
  committed rồi thêm một candidate. `SUPPORT_UNION` tạo proposed bằng union
  committed với candidate snapshot.
- Duplicate atom không tạo slot mới; first existing coefficient giữ ownership.
- List, bitmap và slot map đổi cùng một accepted write. Count không vượt 96.
- `SUPPORT_COMMIT` chỉ đổi bank-select tại một cạnh clock. Không có partial
  visibility.
- `SUPPORT_ROLLBACK`, abort giữa transaction hoặc certificate fail chỉ hủy
  proposed bank; không copy dữ liệu dở vào committed bank.
- Mỗi rollback tăng `rollback_count`; `rollback_cycle_count` tăng đúng một vì
  rollback là constant-time.

## 3. Opcode payload

- Resource word không chứa atom 10 bit. Candidate atom/value đến từ snapshot
  collector/TOP-K; `configuration_id` chọn candidate slot 0..63.
- `SUPPORT_APPEND`: candidate tại slot được chọn.
- `SUPPORT_UNION`: toàn bộ `candidate_count` record, theo exact rank order.
- Candidate payload chỉ có nghĩa tại slot `[0, candidate_count)`; tail ngoài
  count không architected và consumer phải gate bằng count.
- `SUPPORT_MEMBERSHIP`: atom tại slot được chọn; response trả membership và
  committed slot.
- `SUPPORT_GATHER`: `configuration_id` là support slot; trả atom/coefficient.
- `SUPPORT_SCATTER`: ghi coefficient input vào proposed slot; atom/list không
  đổi.
- `SUPPORT_CLEAR`, `COMMIT`, `ROLLBACK` không có payload.

## 4. Candidate và Phi-symbol capture

- Collector giữ tối đa 64 record `{index,value}` theo total order M9a:
  magnitude giảm dần, tie dùng index tăng dần.
- Physical candidate slot ổn định; rank list chỉ ánh xạ rank sang physical slot.
- Candidate vào retained 2K phát đúng một `candidate_store` token tới M7 Phi
  cache. Eviction tái sử dụng physical slot; không lưu full proxy N phần tử.
- Active-support gradient giữ theo support slot tối đa 96.
- Commit với `input_select=SUPPORT_STREAM` mở prepare/refill hai pha. Proposed
  bank giữ nguyên trong khi software context START Phi support-list; finalize
  commit chỉ flip bank sau khi cache báo valid.
- Commit mặc định vẫn dùng candidate-symbol promotion. Hardware không decode
  algorithm ID; context chọn promotion hoặc proposal-list refill.

## 5. Coefficient remap

- Atom có trong committed support nhận coefficient cũ.
- Atom mới nhận zero trước `SUPPORT_SCATTER`/refinement.
- Atom bị drop xuất hiện đúng một lần trong dropped list cùng coefficient cũ.
- Remap không mutate committed state; commit vẫn thuộc support manager.

## 6. Fault và abort

- Slot ngoài range, candidate count >64, workspace overflow, commit khi không có
  transaction hoặc scatter ngoài proposed count trả fault; committed state giữ
  nguyên.
- `routine_start` hủy request/proposed transaction đang dở nhưng không xóa
  committed support. Full-run initialization dùng `SUPPORT_CLEAR` + commit.
- Opcode không thuộc M5/M9a/M9b phải fail closed; không được ready rồi drop.

## 7. Exit gate

- Directed K32/2K/3K, append/union/prune, duplicate, membership, gather/scatter.
- Mid-transaction abort, certificate-fail rollback, rollback storm, pointer-swap
  atomicity và counter exact.
- Assertions: no duplicate, count bound, bitmap/list/slot-map consistency,
  response stability, committed state chỉ đổi do accepted commit.
- Vivado 2018.1 normal XSim, assertion-enabled XSim, FORMAL compile/elaboration.
- ZCU106 OOC 150 MHz; WNS >= +1.000 ns; DSP=0; support subsystem BRAM <=1.
- Chỉ sau toàn bộ evidence mới flip tám opcode sang `implemented/measured`, rồi
  regenerate architecture package đúng một lần.

## 8. Directive policy

- Mọi leaf, integration và implementation gate dùng Vivado default.
- Không truyền `-directive` cho synthesis, optimization, placement hoặc route.
