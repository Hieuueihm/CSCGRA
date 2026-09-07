# 19 - M9a TOP-K selection contract

Status update 2026-08-26: Gate B COMPLETE. Evidence: `reports/v3/M9A_TOPK_SELECTION_STATUS.md`.

Ngày lập: 2026-08-26. Phạm vi: leaf `topk_selection_unit` được kéo lên
trước M8 để làm consumer cho correlation; support state M9b chưa thuộc contract.

## 1. Authority và ownership

- Semantic authority: `models/v3/hardware.py::_rank`.
- Resource opcodes: `TOPK_PUSH` và `TOPK_COMMIT`.
- RTL owner: `rtl/v3/selection/topk_selection_unit.v`.
- Transaction golden: `reports/v3/m9a_topk_transaction_golden.json`.
- K build-time tối đa 32; index 10 bit; score signed S27 normalized.
- M5 `array_resource_router` không sở hữu selection. M8 operator harness phải
  dispatch resource context tới M5 arithmetic hoặc M9a selection owner.

## 2. Exact order

Total order:

1. absolute magnitude lớn hơn đứng trước;
2. magnitude bằng nhau thì index nhỏ hơn đứng trước.

Đây là key `(-abs(value), index)` của `_rank`. Min-negative S27 được so bằng
magnitude 27 bit, không overflow signed negate. Mỗi index chỉ xuất hiện một lần.
Push lặp index bị ignore; first accepted value giữ ownership. `_rank` luôn có đúng
một value cho mỗi implicit index, nên duplicate là replay ngoài semantic domain và
không được phép tạo duplicate state.

## 3. Transaction protocol

- Request chỉ được nhận tại `cycle_valid && cycle_commit && cycle_ready`.
- `routine_start` atomically clear state và latch `selection_k`.
- `TOPK_PUSH`: latency 2, II 1 khi response không backpressure.
- `TOPK_COMMIT`: chỉ nhận khi push pipeline rỗng; latency 1.
- Response giữ operation/tag/fault/count và toàn bộ ordered state khi stalled.
- Invalid K=0 hoặc K>32 trả fault; không mutation.
- State mutation của push chỉ bắt nguồn từ request đã được cycle commit chấp nhận.
- Commit không mutate ranking; nó xuất tagged terminal acknowledgement.

## 4. Output và N3 seam

`result_scores` và `result_indices` là K32 flattened ordered state, slot 0 tốt
nhất. M9b/proxy collector sẽ sở hữu support-state transfer và atomic sparse
commit. `candidate_symbol_*` chỉ là interface seam N3; ready hard-zero, payload
không được nhận, không claim candidate-symbol capture implemented.

## 5. Verification gate

- Golden replay gồm 48 push, K32 capacity, duplicate update, equal-magnitude tie,
  min-negative S27 và deterministic random seed.
- Directed exact latency 2/1 và II1.
- Random response backpressure, response/state stability, no loss/duplicate tag.
- Non-committed request không tạo response hoặc mutation.
- FORMAL-guarded assertions: count bound, exact order, no duplicate, stable stall,
  state-change authorization. Vivado elaboration không phải mathematical proof.
- ZCU106 OOC 150 MHz; gate WNS >= +0.200 ns; DSP=0, RAMB36=0, RAMB18=0.

Capability chỉ được flip sang implemented/measured sau khi XSim/property/OOC có
evidence. M9a complete không đồng nghĩa M9 support ownership complete.
