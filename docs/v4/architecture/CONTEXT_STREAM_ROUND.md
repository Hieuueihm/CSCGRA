# Context and stream optimization round — 2026-09-10

Status: focused scalar/control/range, GEMV prefetch and narrow-panel gates have passed. The combined kernel suite passed18 tests. Threshold1/4/8 surveys at both geometries passed; common threshold1 is selected with explicit OMP/GOMP tradeoffs. Final active10 acceptance and installation are recorded in STATUS and the final report.
Baseline: installed compact profile / kernel feature6, source hashes in stage origin_manifest.json; fixed8 archives scalar_insert_compact_m32_20260910 and scalar_insert_compact_m64_20260910. Installation is source-guarded and recorded in reports/v4/context_stream_promotion_20260910.

## Ordered work and ownership

1. Exploit existing op21 at reflector heads/tau/beta and sweep trailing-panel width threshold. New opt-in streamed profile; preserve compact images and compatibility defaults. Compiler owner: Terra quality.
2. Remove intermediate slices through a generic command-scoped range view over loaded TEMPLATE operands, with exact unchanged PE round/ACC behavior and packed output. Kernel, ABI, VM and compiler must agree before use. Avoid persistent aliases over mutable vectors; no copy-on-write store. Retain read operands when identity and write invalidation permit. Root contract, then sequential Terra ownership.
3. Measure and improve common GEMV transport, preserving ordered delivery, terminal reduction and all flow-control contracts. Four frame credits/two matrix credits and tile caches already exist; do not equate more buffering with throughput. Terra panel.
4. Adapt trailing factor-panel mapping to rectangle geometry on exactly32 existing PEs, with arithmetic-order equivalence. Select thresholds using paired whole-program results; benefits to CoSaMP alone do not establish a balanced architecture. Terra report after sequencer range validation, in parallel with Terra panel kernel work.
5. Single synchronous instruction prefetch and safe control reuse. No speculative service effects, skipped ACC reset, stale register-dependent branches, duplicate program RAM or changed watchdog/fault semantics. Terra report initially owns sequencer.

## Range command and compiler profile

Feature7 opcode22 RANGE_TEMPLATE retains TEMPLATE context, format and rounding semantics. `index` is the A element offset and `aux_length` is the B element offset; the authoritative field, capacity and increment rules are in [RANGE_TEMPLATE.md](RANGE_TEMPLATE.md). Selected RAM lanes are translated into one or two physical providers per packed frame, with tag/mask validation before use. Unused sources require no read. Output scratch/remap commit is unchanged; no persistent alias handle or copy-on-write store is introduced.

The command supports EACH, LAST_ACC and SUM_ACC with their distinct output capacities. Source capacity is checked using the highest actually selected packed position, widened arithmetic and the descriptor increment modes. The reader has two transient cache entries per frame, not a command-wide resident-vector cache.

The explicit `view` compiler profile uses backsolve DOT(A,D[j:]) removes SLICE P; QTy DOT(V,Y[j:]) and SUB(Y[j:],P) remove SLICE W. Existing REPLACE_RANGE for publishing updated Y remains. Keep stored-X certificate, refinement bound, rank/overflow handling, scalar formats and loaded algorithm control identical. The command must not infer QR/algorithm identity.

## Qualification and promotion

Only Vivado xvlog/xelab/xsim for RTL. Per-change tests cover partial/unaligned tails, aliases, selected validity, stalls, reset/cancel, malformed contexts and errors. Numerical/compiler tests may run Python; VMs share Arithmetic and are not independent arithmetic implementations.

Freeze final source before whole-program runs, then compare active10 at M32/N64/K8 and M64/N256/K8, actual8 iterations, identical rawPhi/Y and policies. Validate rawX/R/support/status, logicalLS/refinement/certificate and numeric events. Report per-algorithm job cycles and service cycles, including regressions; distinguish control/drain time from idle. Threshold sweeps must keep other source/image policies fixed. Archive source hashes and raw logs. Existing v3 data is a historical anchor unless workload and measurement boundaries match.

Do not promote an unmeasured regression merely because the mean improves. Fixed8 fixtures with float SNR<20dB remain diagnostic; do not claim application qualification. No production bit-lock, synthesis/implementation, timing, resource or board-fit claim. CPU AXI/MMIO/DMA and register map remain separate outstanding integration work.

## Observations during implementation

The validated-vector-response fanout experiment was rejected: on the same directed XSim fixture, vector join moved13 to12 clocks but ordered command completion stayed16 clocks. Added routing has no demonstrated throughput benefit, so the production feeder was restored to its origin hash. Preserve work/fanout_experiment as negative evidence.

Current FISTA M64 baseline has512 accepted frames per GEMV: forward551 service clocks and transpose975. Forward is already close to one accepted frame/clock. The next transport candidate prefetches future output-group frames into the existing four-entry feeder during current-group terminal/drain. It separates issue coordinates from compute/write coordinates and blocks future-frame consumption after delivered_last until the next group launch. All PE ACC and rounding boundaries stay serialized as before.

First whole-program increment: streamed threshold8 plus retire-time fetch, original feeder. Both source-frozen runs passed all10 algorithms at actual8 iterations. The evidence is reports/v4/context_stream_quick_20260910. Later range-only integration attempts are retained separately: one failed elaboration because the full-system source list omitted range_reader; a corrected but deeply nested run failed filename transport at time0. The retry uses a short frozen root and unchanged qualified runtime bytes. Neither failed attempt supplies performance evidence.
