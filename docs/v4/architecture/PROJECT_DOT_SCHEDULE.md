# PROJECT_DOT schedule - Step 2

The source-qualified schedule is installed. Runtime/test installation is bound
by `reports/v4/project_dot_schedule_promotion_20260910/before_after_manifest.json`.
Documentation updates are recorded separately in `metadata_manifest.json`.
Full results are in `reports/v4/project_dot_final_20260910/README.md`.

## Selected schedule

`factor_panel_service` defaults to `PROJECT_DOT_SPLIT_ENABLE=1` and
`PROJECT_DOT_SPLIT_MIN_ROWS=24`. For PROJECT_DOT with 9 through 16 remaining
columns and at least 24 selected rows, it issues two ordered R4 DOT subpanels:
8 columns followed by the remaining 1 through 8 columns. Each column uses four
existing PE lanes. Other shapes, or a disabled split parameter, retain the
previous schedule. These are elaboration parameters, not a new program opcode,
export flag, ABI revision, or algorithm-specific controller.

The operation remains `w=F^T v`, `z=tau w`, then `F=F-v z^T`.
Each column keeps its original terminal rounding point. SCALE waits for both
DOT subpanels, and RANK waits for all SCALE values. Factor identity, ownership,
held requests/responses and cancellation/fault cleanup are preserved. The
design still uses exactly two 4x4 PE arrays, one vector pool and the existing
factor image. There is no additional PE or factor copy.

For 64 rows and 16 columns, DOT input frames decrease from 64 to 32. This is
not a twofold command or job speedup: configuration, terminal, memory and the
SCALE/RANK phases still contribute. The selected threshold comes from focused
A/B and whole-program measurements, not frame counts alone. Some individual
R24/R40 commands pay one extra cycle; there is no per-command speed guarantee.

## Qualification and measured benefit

The frozen g13e aggregate contains seven passing Vivado XSim tests in
1114.280 seconds: 38 shape A/B comparisons, selected stalls, second-DOT
cancel/fabric fault and recovery without reset, plus legacy panel and energy
coverage. Exact factor readback is checked. The final focused archive retains
the two legacy evidence records under distinct names with identical source
bytes; the earlier colliding archive is excluded, not acceptance evidence.

`pair_panel_schedule` rehashes frozen source, package, executable image, input
fixture and trace artifacts. Both active10 K8 suites execute eight outer
iterations and retain raw Phi/Y, X/residual, support, status, SNR/NMSE, logical
LS/refinement and physical INIT/EXTEND/BUILD/reuse counts.

| Geometry | Algorithm | Before | After | Reduction |
|---|---|---:|---:|---:|
| M32/N64/K8 | CoSaMP | 132671 | 132429 | 0.18% |
| M32/N64/K8 | SP | 45051 | 44897 | 0.34% |
| M64/N256/K8 | CoSaMP | 158527 | 157106 | 0.90% |
| M64/N256/K8 | SP | 64158 | 63556 | 0.94% |

The other eight algorithms retain their job cycles. Whole-program benefit is
below one percent and does not resolve the main CoSaMP cost. The Step 1
feature-10 opt-ins and compatibility default `balanced` are unchanged; this
runtime-only comparison uses identical images and configuration.

Five timing-fixture quality diagnostics remain below 20 dB at each geometry:
MP, IHT, HTP, FISTA and PDHG. This is not held-out application qualification.
No synthesis, implementation, PPA, timing/Fmax, board, AXI or bitstream claim
is made. Step 3 remains deferred.
