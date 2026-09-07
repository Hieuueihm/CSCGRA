# 20 - M8 matrix-operator integration contract

Ngày khóa: 2026-08-26. Trạng thái: **implementation contract; Gate C chưa
COMPLETE cho tới khi XSim/property/OOC evidence pass**.

## 1. Ownership

M8 nối M4 stream/scratchpad, M5 arithmetic, M6 cluster pair, M7 generated
Phi và M9a TOP-K. M8 biết **operator transaction**, không decode program ID
hoặc algorithm ID. Software vẫn sở hữu phase program và finalized context
image; phase entry PC luôn do software cung cấp.

## 2. Iteration contract

Một Phi symbol chứa 32 measurement rows. Đặt:

```text
R = ceil(M / 32)
```

Context image dùng loop counter 0 cho inner dimension, counter 1 cho outer
dimension. `run_param0` mang `R`; `run_param1` mang active support/work count
khi operator cần dimension software-defined. Không dùng product loop limit và
không thêm algorithm controller.

| Operator | Inner counter 0 | Outer counter 1 | Output boundary |
| --- | --- | --- | --- |
| `Phi^T*r` correlation | `R` row blocks | `N` columns | one normalized TOP-K push/column |
| `Phi*p` support forward | support/work count | `R` row blocks | one S27 stripe/row block |
| `Phi_T^T*u` support transpose | `R` row blocks | support/work count | one normalized S27 value/support slot |
| residual update | support/work count | `R` row blocks | one D18 residual stripe/row block |

Each outer iteration has an explicit setup context that resets the inner loop,
clears PE accumulators, and restarts only the vector cursor(s) whose logical
object is replayed. A cursor restart is legal only with no held/in-flight
scratchpad response.

## 3. Correlation schedule

Canonical sequence:

```text
START Phi + TOP-K routine_start
for column in 0..N-1:
    clear PE accumulators; restart residual cursor; reset inner counter
    repeat R:
        consume residual stripe + one Phi symbol; PHI_ACCUMULATE
    issue REDUCE_SUM(clear_before=1, accumulate=1, commit_after=1)
    wait reduction response; accept into phi_operator_normalizer
    wait normalized response; issue TOPK_PUSH(score, registered phi_column)
    wait TOPK_PUSH response
TOPK_COMMIT; wait response
STOP Phi; routine_done
```

Reduction request occurs in a context after the final `PHI_ACCUMULATE`, never
on the same edge. Candidate index is the registered `phi_column` of the
completed column. All symbols consumed inside one inner loop must carry the
same column; row blocks must be contiguous from zero through `R-1`.

## 4. Response and stall contract

- Provider/vector/Phi state advances only on `cycle_commit`.
- Reduction, normalizer, TOP-K requests use ready/valid and retain payload on
  stall.
- Every response-producing resource issue has an explicit wait context.
- No outer-loop counter increments before the matching TOP-K/writeback
  response commits.
- Tail rows above M are zero by Phi generator and D18 lane-valid masking.
- Abort flushes provider/pipelines and may complete only at declared safe
  boundaries; no partial TOP-K/support mutation is exposed.

## 5. Compiler fail-closed checks

Compiler rejects an executable operator template when any condition holds:

1. Phi consume count is not the declared nested product.
2. A reduction result consumer exists without `commit_after=1` and an explicit
   reduction response wait.
3. Correlation lacks normalizer producer, registered column index, TOP-K push
   response wait, or final TOP-K commit response wait.
4. Replayed vector objects lack an outer-iteration cursor restart.
5. A writeback context can commit before its producer response is valid.

## 6. Evidence gate

Gate C requires transaction-golden tests for M tails, support tails, random
backpressure, production seeds, exact candidate index/score order, exact
committed context count plus declared provider/reduction/normalizer fill/drain,
property compile/elaboration, and OOC WNS >= +1.0 ns.
