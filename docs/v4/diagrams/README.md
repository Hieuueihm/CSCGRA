# Sơ đồ v4

Generated from the `.mmd` sources in this directory; edit those sources and run
`py -3 scripts/v4/project.py generate`. Each diagram identifies implemented, planned or reference scope.
These are logical architecture/dataflow diagrams, not placed-and-routed layouts.

Source references: [system contract](../ARCHITECTURE_SPEC.md),
[module catalog](../architecture/MODULES.md), [status](../STATUS.md).

## Current recovery target: shared stream kernel, live operator and loaded programs

[Mermaid source](recovery.mmd)

```mermaid
flowchart TB
  host[Host - load program / templates / vector data / descriptor]
  top[csr_top - AXI4-Lite 32-bit registers]
  bridge[host_command_bridge - native snapshots and mailboxes]
  recovery[recovery_engine - 10 active programs passed fixed8 gates]
  control[program_sequencer - loaded branches and subroutines]
  kernel[stream_kernel - shared pool, kernel dispatch and publication]
  subgraph compute[Only compute fabric in target]
    left[4x4 stream_array - 16 PEs]
    right[4x4 stream_array - 16 PEs]
  end
  pool[Vector pool - 16 paired TDP banks, logical block ownership]
  support[support_service - selection and support operations]
  scalar[arithmetic_service - shared DIV / SQRT / RESCALE]
  live[live_operator_memory - Phi/B endpoint with two read credits and elastic Phi cache]
  feeder[operator_frame_feeder - four frame slots, two vector blocks, R1/R4]
  qr[factor_service / factor_store - private factor access and prefix append]
  panel[factor_panel_service - loaded dot and rank update on shared 32 PEs]
  commit[result_store - whole-result publication gate passed]
  scope[Active10 M32/N64/K8 and M64/N256/K8, actual outer8; maximum-N gate MP/GP/IHT/FISTA only]
  pending[QR S96 full-program RTL, held-out quality and physical qualification pending]
  host -->|AXI-Lite MMIO and IRQ| top
  top --> bridge -->|Native ready-valid| recovery
  recovery --> control
  control -->|Generic commands, no algorithm-ID FSM| kernel
  control <--> scalar
  control -->|Build ordered support| live
  kernel <--> pool
  kernel <--> support
  kernel <--> feeder
  live <--> feeder
  feeder <--> pool
  kernel <--> left
  kernel <--> right
  qr <--> kernel
  panel <--> kernel
  panel <--> qr
  recovery --> commit -->|Result read via MMIO| top
  recovery -.-> scope
  scope -.-> pending
```

## Queued Phi/B transport: four frames, shared cache and paired memory

[Mermaid source](operator_pipeline.mmd)

```mermaid
flowchart LR
    P[Loaded program and contexts] --> K[Kernel: captured command and frame order]
    K --> F[Feeder: four ordered frame slots]
    F --> E[Matrix endpoint: two ordered read credits]
    E --> R[Phi reader: ordered requests and responses]
    R --> S[Eight unchanged raw sign banks]
    S --> T[Round-2 qualified: two command-local raw 32x8 sign-tile entries
Eligible R1-forward or R4-transpose
At most one validated hit per clock]
    T --> F
    S -->|unfavorable live-Phi mode only| F
    E --> B[One unchanged B store: 16 paired banks]
    B --> F
    V[Shared vector pool] --> O[Operand cache: two 32-lane blocks]
    O --> F
    V --> U[Round-2 support range transport
Per output 32-lane block: <=3 distinct providers; one outstanding read
common word-offset align and masked merge]
    U --> W[Scratch only; kernel publishes atomically]
    F --> A[Two 4x4 arrays: exactly 32 PEs]
    A --> D[Existing PEACC + fixed registered reduction links]
    D --> W
    W --> V
    C[Captured TEMPLATE context] -.unused or exact alias schedule.-> O
```

## QR target: shared PEs, implicit reflectors and stored-X certificate

[Mermaid source](qr.mmd)

```mermaid
flowchart TB
  program["Loaded QR program\ncompiler owns QR loops"]
  builder["Build B from ordered support"]
  init["FACTOR_INIT through factor_service\nvalidated B import bridge"]
  factor["factor_store\nprivate S27 factors"]
  bridge["factor_service bridge\nexisting private store"]
  panel["factor_panel_service\nsource-qualified candidate ops17/18"]
  kernel["stream_kernel\nexclusive panel fabric mux"]
  fabric["stream_fabric\nexisting two 4x4 arrays = 32 PEs"]
  cascade["cascade16: MUL16 then SUB16\nno new PE or multiplier"]
  scalar["DIV / SQRT / RESCALE"]
  cert["stored-X certificate"]
  program --> builder --> init --> factor
  program --> kernel
  program --> panel
  factor <--> bridge <--> panel
  panel -->|exclusive fabric owner:\nMATVEC MAC32 / RANK1 cascade16| kernel --> fabric
  fabric --> cascade
  program <--> scalar
  kernel --> cert --> program
  status["Source-qualified Vivado candidate: 20 fixed8 active10 PASS\nCoSaMP M64 252684, M32 210512 cycles; 41.48% reduction\nsource installation tracked by promotion manifest; no PPA/timing/production-bit claim"]
  panel -.-> status
  legend["Legend: solid arrows are control/data ownership; factor_service is the only B-to-factor-store import bridge; dashed arrow is qualification status"]
  legacy["ADMM and LSQR are historical references; no fallback"]
```

## Separately elaborated stream first slice: loadable programs and per-PE contexts

[Mermaid source](stream.mmd)

```mermaid
flowchart TB
  host["Host / recovery_engine\nloads revision2 program image"]
  sequencer["program_sequencer\nloaded generic ops"]
  kernel["stream_kernel\nshared vector pool and exclusive fabric mux"]
  panel["factor_panel_service\nsource-qualified candidate ops17/18"]
  bridge["factor_service bridge\nprivate factor_store"]
  fabric["stream_fabric\nexisting two 4x4 arrays = 32 PEs"]
  normal["flow0 parallel32"]
  cascade["flow1 cascade16\nMUL then SUB"]
  host --> sequencer --> kernel
  kernel --> fabric
  kernel --> panel --> bridge
  panel -->|exclusive ownership only during panel command| fabric
  fabric --> normal
  fabric --> cascade
  note["Source-qualified Vivado candidate: 20 fixed8 active10 PASS\nCoSaMP M64 252684 / M32 210512 cycles; 41.48% reduction\nsource installation tracked by promotion manifest; no PPA/timing/production-bit claim"]
  panel -.-> note
  legend["Legend: solid arrows denote instantiated control/data flow; panel and normal paths share one fabric, never duplicate arrays"]
```

## Historical LSQR reference: shared operator, 32 PEs and certified commit

[Mermaid source](lsqr.mmd)

```mermaid
flowchart TB
  HOST["Host preload: service program, normalized D18 Y, matrix/support descriptor"]
  TOP["lsqr_engine: job ownership, start/done and abort"]
  MEM["operator_memory: exclusive load / build / compute read"]
  PHI["LFSR32 + one 8-bank Phi sign cache"]
  BUILD["support_builder: ordered Psi=I columns"]
  B["One B cache: 128 x 96 C18, 32 banks"]
  PC["solver_sequencer: one PC, 256 x 128 program, 32 x 64 scalar RF"]
  K["kernel_engine: generic vector/matrix operations; atomic destination"]
  WS["vector_workspace: 16 x 128 S27; 32 banks"]
  READER["One operand_reader + feeder"]
  FAB["kernel_fabric"]
  A0["4 x 4 PE array: 16 PEs"]
  A1["4 x 4 PE array: 16 PEs"]
  SCALAR["One DIV / SQRT scalar_service"]
  CERT["Stored-X certificate: r = y - B X; g = B^T r; energy(g) x 10^10 <= energy(B^T y)"]
  COMMIT["commit_controller + result_writeback: two 96-entry candidate/committed banks"]
  OUT["Committed X24 + support + exponent + tags"]
  HOST --> TOP
  TOP --> MEM
  MEM --> PHI
  PHI --> BUILD
  BUILD --> B
  TOP --> PC
  PC --> K
  PC --> SCALAR
  K <--> WS
  B --> READER
  READER --> FAB
  K --> FAB
  FAB --> A0
  FAB --> A1
  A0 --> K
  A1 --> K
  K --> PC
  SCALAR --> PC
  PC --> CERT
  CERT -->|"certified candidate slot"| TOP
  WS -->|"exact stored candidate"| COMMIT
  TOP -->|"explicit approval"| COMMIT
  COMMIT --> OUT
  NOTE["Scope: bounded LS solve. Resident GEMV is a separate reference. Full recovery/AXI top and board timing remain pending."]
```

## Separately elaborated resident GEMV reference

[Mermaid source](resident.mmd)

```mermaid
flowchart TB
  subgraph resident["Separate resident GEMV reference: 32 PEs, one feeder"]
    HOST["Verified context image + descriptor configuration"] --> ENGINE["resident_engine"]
    ENGINE --> CONTEXT["context_engine\nloader / store / one PC sequencer"]
    CONTEXT -->|ADDRESS + tile64 words| OP["operator_controller\ndescriptor cursors / response ownership"]
    OP -->|coordinates + identity| MEMORY["resident_operands"]
    subgraph stores["Live resident stores and operand path"]
      PHIGEN["phi_sign_generator"] --> PHICACHE["phi_sign_cache\n8 sign banks"]
      PHICACHE --> PHIREAD["phi_reader\ncaptured read envelope"]
      BCACHE["support_matrix_cache\none dense B copy"] --> READER["operand_reader\noperand_plan + one operand_feeder"]
      VECTOR["vector_store"] --> READER
      PHIREAD --> READER
    end
    MEMORY --> stores
    READER -->|expanded 32-lane frame| OP
    OP --> FABRIC["frame_fabric\nno feeder"]
    FABRIC --> A0["pe_array 0: 16 PEs"]
    FABRIC --> A1["pe_array 1: 16 PEs"]
    A0 -->|atomic shared retirement| SINK["Indexed candidate STORE stream\nbackpressure; no outer commit"]
    A1 --> SINK
  end
  REF["cgra_fabric: separate raw-bundle reference root\nits feeder/arrays are not extra target resources"]
  NOTE["The LSQR target uses operator_memory + kernel_engine; see lsqr.mmd\nFull csr_top/recovery and board qualification remain pending"]
```

## Historical baseline: generated cache và LSQR

[Mermaid source](baseline.mmd)

```mermaid
flowchart LR
  H["Host: seed, scale, profile, contexts, y"] --> J["Job + operator controller"]
  J --> G["Selected LFSR32 Galois generator\ntaps 0x80200003; LSB then step"]
  G --> C["One Phi sign cache: 8 banks / 16 KiB"]
  C --> F["Sign / dense / vector feeder"]
  F --> P["Two 4x4 full PE arrays"]
  X["Vector/state memory"] <--> P
  Q["32 tile contexts: GEMV, DOT, AXPY, LSQR, optional Psi/adjoint"] --> P
  P <--> S["One shared scalar service: DIV / SQRT"]
  C --> U["Support builder: full rebuild"]
  P -. "Phi/Psi columns when qualified" .-> U
  U --> B["One dense B cache: selected columns only"]
  B --> F
  P --> K["Post-storage check + atomic commit"]
```

## Numerical: chuẩn hóa và nghiệm lưu X

[Mermaid source](numeric_contract.mmd)

```mermaid
flowchart TB
  Y["Measurement y: original units"] --> N["Host: choose e from y only<br/>peak after scaling in (0.25, 0.5]"]
  N --> D["Quantize input D<br/>e stays in job metadata"]
  L["Selected LFSR32<br/>seed + shape + scale"] --> P["One Phi sign cache"]
  P --> B["Ordered support B<br/>one dense C cache"]
  D --> PE["Two 4x4 arrays: 32 full PEs<br/>LSQR GEMV / DOT / AXPY in S"]
  B --> PE
  SC["Shared DIV / SQRT"] <--> PE
  PE --> X["Round to persistent X<br/>exact X-to-S embedding"]
  X --> CHECK["Recompute residual and normal<br/>from stored X"]
  B --> CHECK
  CHECK -->|"pass and no fault"| COMMIT["Commit support + X + residual<br/>all in normalized domain"]
  CHECK -->|"not passed, budget remains"| PE
  CHECK -->|"fault or exhausted budget"| FAIL["Failed LS<br/>preserve prior committed state"]
  COMMIT --> OUT["Host output: decode raw X<br/>multiply by 2^-e"]
```

## ZCU106: CPU, DDR và accelerator

[Mermaid source](zcu106.mmd)

```mermaid
flowchart LR
  PC["PC: prepare A / context / benchmark"] --> CPU
  subgraph PS["ZCU106 processing system"]
    CPU["Arm CPU: buffers and jobs"] <--> DDR["PS DDR: inputs, images, outputs"]
    HP["S_AXI_HP0_FPD"] <--> DDR
  end
  subgraph PL["Programmable logic: proposed 100 MHz domain"]
    CTRL["AXI-Lite job control"] --> CORE["csr_top: two 4x4 PE arrays"]
    DMA["128-bit AXI master / DMA"] <--> RAM["Resident A / transpose A; vector and context stores"]
    RAM <--> CORE
  end
  CPU -->|"HPM control path"| CTRL
  DMA <-->|"preload and result transfer"| HP
  CORE -->|"done / fault interrupt"| CPU
```

## System reference và đường dữ liệu

[Mermaid source](system.mmd)

```mermaid
flowchart TB
  H[Existing native job loading
Host/AXI top planned] --> R[recovery_engine
job, status and publication ownership]
  R --> Q[program_sequencer
loaded PC, branches, templates and scalar RF]
  Q --> K[stream_kernel
one vector pool and one stream_fabric]
  K --> F[operator_frame_feeder
four ordered frames and operand cache]
  F --> M[live_operator_memory
existing Phi/B ownership and read credits]
  M --> S[Eight unchanged raw Phi sign banks]
  S --> T[Round-2 qualified transport
two command-local raw 32x8 tiles
only favorable live-Phi modes]
  M --> B[One unchanged B store: 16 paired banks]
  B --> F
  M -->|unfavorable live-Phi mode only| F
  T --> F
  K --> U[support_service
per output 32-lane block: <=3 distinct providers
one outstanding read; kernel scratch publication]
  U --> V[shared vector pool
480 public + 32 scratch blocks]
  V --> F
  F --> A[stream_fabric
two 4x4 arrays: exactly 32 PEs]
  A --> D[existing PEACC
fixed registered reduction links]
  D --> V
  K --> W[kernel-owned scratch publication]
  W --> R
  R --> P[result_store
recovery_engine-owned checked publication]
  N[Round-2 source-clean xsim qualified
22 fixed8 program rows; kernel16/support7/Phi boundary
No timing, resource or fit conclusion] -.scope.-> T
  N -.scope.-> U
```

## Matrix image reference hai orientation

[Mermaid source](matrix.mmd)

```mermaid
flowchart LR
  S["Original signal s"] --> Y["y = Phi*s + noise"]
  PH["Physical measurement operator Phi"] --> Y
  PH --> A["Host constructs A = Phi*Psi"]
  PS["Synthesis basis Psi"] --> A
  A --> AQ["Quantize A once to C format"]
  AQ --> AF["Pack forward orientation: 32 banks"]
  AQ --> AT["Transpose SAME integers; pack: 32 banks"]
  AF --> M["Manifest: shape / format / hashes / bank geometry"]
  AT --> M
  M --> L["Idle-only loader; verify before publish"]
  Y --> YQ["Normalize and quantize y separately"]
  YQ --> PE["PE execution"]
  L --> PE
  PE --> XR["Recovered coefficients"]
  XR --> SR["Host inverse transform and undo scale"]
```

## Candidate một-copy đọc hai hướng

[Mermaid source](matrix_single.mmd)

```mermaid
flowchart LR
  A["Same quantized A: one copy"] --> L["Idle loader; DMA framing still pending"]
  L --> B["32 diagonal banks: bank=(row+column) mod32"]
  B --> F["Per-bank addresses + 32-lane rotation"]
  F --> P["Two 4x4 arrays: R1 or chunked R4"]
  V["Vector banks: 1 or4 source values per issue"] --> P
  P --> O["Ax or transpose-A*x"]
  B -. "support gather candidate" .-> S["One-copy packed B cache; pipeline unproven"]
  S -.-> F
```

## Candidate tự sinh: cache dấu, transform và LS

[Mermaid source](generated_operator.mmd)

```mermaid
flowchart LR
  H["Host: seed, scale, shape, operator revision"] --> G["Selected LFSR32 stream generator\ncolumn-major col*M+row; LSB then step"]
  G --> C["Compact sign cache or prefetched tiles"]
  C --> F["Direction-aware feeder: signs + vector operands"]
  X["Vector/state memory"] --> F
  F --> P["Two full 4x4 PE arrays"]
  K["Context programs: sign GEMV, DOT, AXPY, LS"] --> P
  T["Optional Psi / adjoint programs and coefficients"] -. "factorized operator only" .-> P
  P --> X
  P -. "construct selected A columns" .-> B["LS support cache: signs or dense coefficients"]
  C -. "direct sign A: select support" .-> B
  B --> F
  D["Alternative: one-copy general dense A"] -.-> F
  N["Threefry2x32-20: reference/ablation\nLFSR indexed jump-ahead is model-only"]
```

## Compiler, context image và PE execution

[Mermaid source](context.mmd)

```mermaid
flowchart TB
  ALG["Algorithm mathematical program"] --> KG["Kernel graph + buffer lifetimes"]
  KG --> MP["Mapping: R1/R4, ports, RF, legal routes"]
  MP --> SC["Latency-aware schedule + loop templates"]
  SC --> ISA["Candidate ISA fields: 32 tile words + control"]
  ISA --> BIN["Pack binary image + disassembly + manifest"]
  BIN --> VAL["Validate fields / capacity / checksums"]
  VAL --> LD["Load when accelerator idle"]
  LD --> CM["32 context banks and one control bank"]
  CM --> SQ["Sequencer fetch / issue / retire"]
  SQ --> PE["Each PE receives its own context slot"]
  PE --> TR["Observed execution trace"]
  TR --> EQ["Compare with scheduled integer reference"]
  SC --> EQ
```

## CGLS reference và post-storage certificate

[Mermaid source](solver.mmd)

```mermaid
flowchart TB
  B["LS request: support, A, y, numeric policy"] --> P["Validate / obtain packed support matrices"]
  P --> I["Initialize CGLS: x=0, r=y, g=A_S^T*r, d=g"]
  I --> Q["Forward q=A_S*d; delta=dot(q,q)"]
  Q --> AL["Wide ratio alpha=gamma/delta"]
  AL --> U["Candidate x+=alpha*d; recursive r-=alpha*q"]
  U --> N["Round candidate to stored D format"]
  N --> CE["Exact policy: recompute r_D and A_S^T*r_D"]
  CE --> OK{"Post-storage certificate passes?"}
  OK -- Yes --> C["Publish coefficients only if no numeric fault"]
  OK -- No --> T{"Budget / breakdown / fault?"}
  T -- Yes --> F["Fail / rollback; keep last committed job state"]
  T -- No --> G["g_new=A_S^T*r; gamma_new=dot(g_new,g_new)"]
  G --> BT["beta=gamma_new/gamma; d=g_new+beta*d"]
  BT --> Q
```

## Context-stream execution: loaded QR commands, range transport and scalar insertion

[Mermaid source](context_stream_execution.mmd)

```mermaid
flowchart LR
    image["Loaded program, descriptors, contexts"] --> seq["Sequencer: read successor at retirement"]
    seq --> kernel["Kernel: validate, dispatch, commit"]
    pool["One public vector pool"] --> view["Command range reader: offset, mask, align"]
    pool --> feeder["GEMV feeder: ordered frames and validated operand reuse"]
    phi["Live LFSR Phi / selected B"] --> feeder
    kernel --> view
    kernel --> feeder
    kernel --> panel["Factor panel worker: mapping by rectangle width"]
    factor["Private factor store"] <--> panel
    pool --> panel
    view --> pe["Two 4x4 PE arrays: loaded contexts, fixed reduction links"]
    feeder --> pe
    panel <--> pe
    pe --> scratch["Scratch result handles"]
    scratch --> commit["Validate masks, swap ownership, publish"]
    kernel --> commit
    commit --> pool
```

## Factor-panel mapping: shared 32 PEs and private factor transport

[Mermaid source](panel_mapping.mmd)

```mermaid
flowchart TB
    shape["Factor rectangle: L rows, C columns"] --> select{"Trailing width C <= 8?"}
    select -- No --> wide["Existing mapping: one row per frame"]
    select -- Yes --> dot["DOT: four rows per column, rows spaced by 8"]
    dot --> acc["Four raw ACC64 values per column"]
    acc --> r4["Existing R4 terminal: sum raw ACC, round once"]
    r4 --> q["Complete all dot panels, then scale all q"]
    q --> rank["RANK: two rows per column, rows spaced by 8"]
    rank --> cascade["Low 16 PE: multiply and round; high 16 PE: subtract"]
    cascade --> store["Checked private factor write, wait for all acknowledgments"]
    wide --> store
    bank["bank = (row + column) mod 32; distinct banks in each frame"] -.-> dot
    bank -.-> rank
```
