# CFG, DDG and context compilation flow

Trạng thái: **M3.6 compiler gate đã hoàn thành cho bốn modulo-array kernel**.
Typed SSA, local RF allocation, concrete eight-bank allocation và bit-exact
context template emission đã được nối sau MMG. Resource/hierarchical lowering
đã phân loại; resident phase-program composition cho đủ tám thuật toán vẫn mở.

Mục tiêu là tạo một đường truy vết duy nhất từ công thức paper đến context chạy
trên CGRA:

```text
paper algorithm
  -> canonical phase CFG
  -> phase operation IR
  -> canonical routine DDG
  -> candidate-II time-expanded MRRG
  -> MMG placement/routing constraints
  -> validated modulo mapping
  -> context image + phase manifest
  -> hardware phase golden
  -> RTL trace comparison
```

Không viết tay context bằng cách nhìn waveform. Không dùng state machine v2 làm
đầu vào cho compiler.

## 1. Hai cấp graph

### 1.1. Reconstruction phase CFG

CFG cấp cao giữ semantics của paper: initialize, correlation, select, support
merge, restricted refinement, prune, residual và stop. Node tham chiếu array-routine entry và
named object; node không chứa cycle-level PE control. Vì phase program chạy
in-order; target revision tiếp tục không mang per-instruction object-version mask.

### 1.2. Array-routine DDG

Mỗi loop đều hạ xuống DDG có node operation và edge dependency. M3.5 đã khóa:

- operation, physical resource class, latency, II và occupancy lấy duy nhất từ
  `architecture_configuration.json`;
- iteration distance;
- dedicated-plane/mesh route class;
- số physical instance phải chiếm; vector array operation chiếm một bundle 16
  paired-context tile, tương ứng 32 PE vật lý.

M3.6 gắn type rõ ràng vào mọi SSA edge: D18F14, S27F19, local accumulator
L48F19, A62F19/F38, Phi symbol, index, predicate và aggregate sparse state.
Mapper không được tự suy đoán Q-format. Revision 7 fuse
`PHI_SIGN_SCALE -> SATURATING_ADD` thành `PHI_ACCUMULATE`; loop-carried partial
sum ở accumulator L48 và không còn cần RF tạm trên mỗi PE.

Branch đều được phân loại:

- regular guard: if-convert thành predicate;
- loop exit: array-control context;
- rare/fault path: event trả về reconstruction control sequencer;
- data-dependent unbounded loop: không map vào modulo kernel cho tới khi có
  bound và progress property.

## 2. Canonical phase CFG của tám thuật toán

| Thuật toán | CFG paper profile |
| --- | --- |
| OMP | INIT -> CORR -> ARGMAX_EXCLUDE -> APPEND -> LS_K -> RESIDUAL -> STOP/LOOP |
| CoSaMP | INIT -> CORR -> TOP_2K -> UNION_K_2K -> LS_3K -> PRUNE_K -> RESIDUAL -> STOP/LOOP |
| IHT | INIT -> RESIDUAL -> CORR -> GRADIENT_STEP -> TOP_K -> SPARSE_COMMIT -> STOP/LOOP |
| HTP | INIT -> RESIDUAL -> CORR -> TENTATIVE_STEP -> TOP_K -> LS_K -> RESIDUAL -> STOP/LOOP |
| SP | INIT_SELECT_K -> LS_K -> RESIDUAL -> CORR -> TOP_K -> UNION_2K -> LS_2K -> PRUNE_K -> LS_K -> RESIDUAL -> NON_DECREASE_ROLLBACK/LOOP |
| GP | INIT -> RESIDUAL -> CORR -> SUPPORT_POLICY -> RESTRICT_GRADIENT -> PHI_DIRECTION -> DOTS -> LINE_SEARCH -> VECTOR_UPDATE -> RESIDUAL -> STOP/LOOP |
| gOMP | INIT -> CORR -> TOP_L_EXCLUDE -> APPEND -> LS_LK -> RESIDUAL -> STOP/LOOP |
| MP | INIT -> CORR_NORMALIZED -> ARGMAX -> RANK1_UPDATE -> RESIDUAL_PROJECTION -> STOP/LOOP |

`LS_3K` nghĩa là depth runtime tối đa 96, không phải ma trận 96x96. Compiler
hiện tại hạ toàn bộ LS node thành unified `restricted_refinement` theo
[11_LS_SOLVER_ARRAY_BLUEPRINT.md](11_LS_SOLVER_ARRAY_BLUEPRINT.md). Direct
factorization chỉ là build reference riêng.

## 3. Operation IR tối thiểu

IR không dùng tên thuật toán trong opcode. Các operation family là:

| Family | Primitive operation |
| --- | --- |
| stream | LOAD, STORE, PHI, PHI_TRANSPOSE, INDEX, MASK |
| arithmetic | ADD, SUB, ABS, SHIFT, SAT_NARROW; MUL/MAC bind vào vector sidecar |
| vector | AXPY, SCALE, COPY, CLEAR |
| reduction | DOT, NORM_SQ, SUM, MAX_ABS, ARGMAX, TOPK_INSERT |
| sparse | MEMBERSHIP, MERGE_UNIQUE, GATHER, SCATTER, PRUNE |
| scalar | COMPARE, SELECT, DIVIDE; RECIPROCAL/SQRT là reserved fault encoding |
| control | PREDICATE, LOOP, WAIT_EVENT, EMIT_EVENT, BARRIER |

`CORR`, `LS` và `RESIDUAL` là kernel names, không phải hardware opcode.

## 4. Kernel lowering

Các kernel quan trọng được hạ như sau:

### 4.1. Correlation

```text
for n:
  lane_acc[0:31] = 0
  for m_block:
    symbols[0:31] = phi_generator(seed, n, m_block)
    lane_acc[lane] += phi_apply_symbol_align(symbols[lane], residual[32*m_block+lane])
  score[n] = phi_scale_once(global_reduce(cluster_reduce(lane_acc)))
```

V3 IR candidate dùng operation `PHI_APPLY_SYMBOL`, không giữ `MUL` giả. D18
align F14->F19 bằng shift-left 5 exact; runtime `alpha` chỉ được áp một lần tại
operator boundary. Forward đặt scale trước scalar broadcast, transpose/
correlation đặt scale sau full reduction.
Pipelined reduction nhận partial vector
của column trước trong khi PE bắt đầu column kế tiếp, nên không cộng reduction
latency vào steady-state `ceil(M*N/32)` nếu reduction II=1.

### 4.2. Unified restricted refinement

```text
g = capture_active_support_gradient(current_proxy)
p = g
repeat q hoặc tới certificate:
    d = Phi_S * p
    alpha = dot(g,g) / dot(d,d)
    x = x + alpha*p
    r = r - alpha*d
    g_next = Phi_S^T * r
    gamma_next = dot(g_next,g_next)
    if gamma/interval/profile boundary yêu cầu:
        recompute r_D18, g_D18 và full certificate
    else:
        beta = dot(g_next,g_next) / dot(g,g)
        p = g_next + beta*p
```

`Phi_S` sign được replay từ active-support cache. Dot/AXPY bind vào one shared
vector sidecar; Phi operator bind vào homogeneous CGRA. Initial gradient được
fuse với correlation; strict commit luôn phụ thuộc full post-D18 certificate.
Workspace tăng từ K lên 2K/3K chỉ tăng loop trip count và
memory depth; không tạo Gram matrix bình phương theo support depth.

### 4.3. Exact selection

Score được tạo theo tile, rồi đi qua compare/reduction node có tie-break index
nhỏ nhất. TOP-K K32 giữ tối đa 64 entry nhưng dùng 32 comparator lane và
replace/rescan 1..2 cycle, không sort N phần tử hoặc tạo chain 64 comparator.

## 5. Mapping qua MRRG và MMG

Mapper thực hiện theo thứ tự:

1. normalize CFG và tạo SSA;
2. if-convert regular control;
3. tạo DDG có latency và iteration distance;
4. tính `ResMII` từ PE, vector sidecar, memory port, reduction/SFU và route link;
5. tính `RecMII` từ recurrence, đặc biệt vector-sidecar/scalar feedback;
6. thử II từ `max(ResMII, RecMII)`;
7. time-expand base MRRG theo candidate II;
8. tạo MMG candidate `(operation, physical resource bundle, absolute time,
   modulo slot, stage)` và constraint dependency/resource/route;
9. solve đúng một candidate mỗi operation, reserve mọi link theo modulo slot;
10. chạy validator độc lập trên mapping và architecture hash;
11. allocate local RF/route latch cho live range;
12. emit prologue/body/epilogue hoặc body-only predicated schedule;
13. cycle-accurate simulation context image trước khi sinh golden.

Route reservation là bắt buộc. Một schedule chỉ place đủ operation nhưng route
không thành công phải bị reject.

## 6. Compiler artifacts

Mỗi build tạo:

- `architecture.json`: tile, port, latency, link, memory bank và capability;
- `mrrg_base.json`: physical graph có 16 paired-context tile/32 physical lane;
- `modulo_mapping_graphs.json`: candidate-II MRRG summary, MMG, selected mapping
  và route reservation cho bốn inner kernel;
- `scheduled_context_library.json`: typed SSA, RF allocation, memory allocation,
  kernel entry PC và packed context words;
- `context_images/array_plane_0..9.mem`: 20 context theo physical plane;
- `context_images/memory_configurations.mem`: 64 configuration word;
- `phase_cfg.json`: graph paper-level có source citation;
- `array_routine_ddg.json`: operation/dependency graph;
- `mapping.json`: PE/cycle/route/RF assignment;
- target-revision distributed plane `.mem` files và disassembly dễ review;
- `phase_manifest.json`: routine entry, trip counts, expected phase order;
- `hardware_phase_golden.json.gz`: snapshots ở phase boundaries.

Mỗi file chứa `architecture_hash`, `algorithm_contract_hash`, numeric profile và
tool revision. Hash mismatch là hard error, không warning.

## 7. Golden và RTL check

Verification chạy theo chuỗi:

1. paper model kiểm tra output toán học;
2. hardware model kiểm tra fixed-point và phase semantics;
3. context simulator kiểm tra schedule cycle-accurate;
4. RTL phát trace `{sequence, phase, routine_entry, context_pc, checksum}`;
5. checker so phase order, boundary data checksum, final sparse support và x;
6. formal kiểm tra protocol, bounds, route exclusivity và liveness bounded.

Golden không được regenerate trong lúc debug RTL. Mọi thay đổi phase CFG hoặc
numeric contract phải qua review rồi mới tạo golden version mới.

## 8. Trạng thái gate trước PE RTL

- đạt: tám phase CFG có explicit lowering classification;
- đạt: correlation, residual update, Phi forward và Phi transpose DDG lấy timing
  từ architecture authority và map được trên shared-context array pair;
- đạt: MMG validator kiểm tra MII, physical resource, shared resource-context
  issue slot, dependency latency, route existence/capacity và architecture hash;
- đạt: typed SSA cover mọi edge của chín routine DDG;
- đạt: fused Phi MAC bỏ RF intermediate; bốn modulo kernel dùng 0/8
  local RF entry cho đường Phi accumulation;
- đạt: bank allocation dùng 38/512 word mỗi bank, tối đa hai access/bank/cycle,
  không cấp phát `proxy[N]`, `rhs_cache[N]` hay dense `x[N]`;
- đạt: 20 context prologue/body/drain/epilogue round-trip bit-exact và sinh đủ
  mười physical plane `.mem`;
- còn mở: AXPY/norm/TOP-K/support/solver là resource/hierarchical transaction,
  không được giả làm modulo PE kernel;
- còn mở: compose resident phase program cho đủ tám thuật toán và chạy context
  cycle simulator với datapath M4+;
- context simulator khớp hardware golden ở các phase boundary;
- disassembly không chứa operation/route write ngoài capability;
- cycle estimate tách compute, route, memory stall và phase-switch overhead.

Các gate typed SSA/RF/bank/context trước PE đã đóng. M4 phải hiện thực đúng stream
và bank contract này; không được thay layout trong RTL rồi sửa compiler theo sau.
