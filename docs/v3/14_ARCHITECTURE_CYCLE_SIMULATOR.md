# v3 complete-architecture cycle simulator

Trạng thái: **functional + transaction-level cycle model revision 4**. Functional
trace vẫn lấy từ hardware model; timing của mọi operation M1-M7 được lấy trực
tiếp từ `compiler/v3/architecture_configuration.json`. Đây không phải XSim
cycle measurement của full system, synthesis hoặc timing sign-off.

## 1. Boundary được mô phỏng

Một run bao gồm:

```text
run-configuration fetch -> validation -> y preload -> context activate
-> paper/hardware phase trace
-> Phi/cache/CGRA/shared-resource transactions
-> dense/sparse result drain -> terminal completion
```

Functional decision, support, refinement step, restart và certificate lấy trực
tiếp từ `models/v3/hardware.py`. Mỗi transaction reserve một hoặc nhiều
resource; resource độc lập có thể overlap, resource chung bắt buộc serialize.

## 2. Timing authority

`timing_contract_from_architecture_configuration()` gọi
`architecture_configuration.load()` và `operation_timing()`. Operation M1-M7
bắt buộc có `status=implemented`, `timing_status=measured` và evidence; thiếu
hoặc hạ xuống modeled làm simulator fail-closed. Sau Gate B, TOP-K cũng dùng
measured M9a authority từ cùng JSON.

| Operation | Latency | II | Authority |
| --- | ---: | ---: | --- |
| REDUCE_* | 5 | 1 | measured M5 |
| SCALAR_DIVIDE | 28 | 28 | measured M5 |
| SHARED_VECTOR_DOT/NORM | 6 | 2 | measured M5 |
| SHARED_VECTOR_SCALE/AXPY | 4 | 2 | measured M5 |
| SHARED_VECTOR_COPY | 2 | 1 | measured M5 |
| PHI_SIGN_WORD | 21 | 2 | measured M7 |
| PHI_NORMALIZE | 4 | 1 | measured M7 |
| TOPK_PUSH | 2 | 1 | measured M9a |
| TOPK_COMMIT | 1 | 1 | measured M9a |

Core equations:

```text
correlation = ceil(M*N/32) + PHI_SIGN_WORD.latency
              + REDUCE_SUM.latency + PHI_NORMALIZE.latency
vector(op,L) = op.latency + (ceil(L/16)-1) * op.II
topk(C)      = TOPK_PUSH.latency + (C-1) * TOPK_PUSH.II
               + TOPK_COMMIT.latency
A hoặc A^T   = ceil(M*S/32) + 5
```

Các latency/II không còn được lặp thành literal trong simulator. Clock và AXI
wait vẫn là runtime override vì không phải operation latency.

## 3. Resource được model

- shared phase/context sequencer;
- hai cluster 4x4 như một 32-lane synchronous array;
- Threefry Phi generator, normalizer và active-support Phi cache;
- 8-bank scratchpad read/write boundary;
- shared vector arithmetic 16 lane;
- cluster/global reduction và scalar divide;
- measured M9a TOP-K timing; modeled support/refinement checker;
- AXI read/write và dense/sparse result writer.

M9a TOP-K leaf có RTL/OOC evidence; M9b support, M10 refinement và M12 result
writer chưa có RTL. Transaction dùng các resource còn lại vẫn là architecture
estimate, không được claim là measured implementation.

## 4. Cách chạy

```powershell
py -3 scripts/sim/v3_architecture_cycles.py --no-transactions
```

Chạy riêng K32 strict:

```powershell
py -3 scripts/sim/v3_architecture_cycles.py --suites scale `
  --profiles strict_paper --no-transactions
```

Preview trước official regeneration:

```powershell
py -3 scripts/sim/v3_architecture_cycles.py --out-dir work/v3_cycle_preview
```

## 5. Gate A evidence

Official regeneration ngày 2026-08-26 tạo đúng 72 run: 3 case × 3 profile ×
8 algorithm. Preview và official output byte-identical. Phase invocation,
certificate cadence, stop reason, final support và numeric event không đổi; chỉ
timing-derived cycle totals đổi. Vì cadence policy không đổi, smoke/scale phase
golden và reference hash-chain không được regenerate.

Không dùng report này để claim FPGA throughput cuối cùng. M8 phải đối chiếu
compiler schedule với connected RTL harness và báo cùng resource/WNS evidence.
