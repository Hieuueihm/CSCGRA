# Opt2 behavior-preserving refactor report

## Scope

- Base branch: `codex/factor-reuse-verified`
- Base commit: `e48d384134ce8e57d51e7ae735222895b2978cb9`
- Refactor branch: `codex/refactor-opt2-clean`
- Verification date: 2026-07-25
- Simulator/synthesis: Vivado 2018.1

The refactor changes source organization and automation only. It does not
change module ports, state encodings, opcodes, datapath equations, PE routing,
factor-reuse decisions, or algorithm scheduling.

## Cleanup performed

### RTL layout

- Moved the generated `lfsr_jump_padded` lookup from
  `sparse_loop_controller.v` into adjacent
  `sparse_loop_lfsr_jump.vh`.
- Moved the secondary `support_set_service` module from
  `sparse_kernel_service_engine.v` into adjacent
  `support_set_service.vh`.
- Verified both extracted blocks against the base commit: exact textual
  matches before adding explanatory comments/include guards.
- Reduced the hand-reviewed controller from 3,610 to 2,513 lines and the
  sparse service engine from 612 to 251 lines.
- Fixed one misleadingly indented conditional by adding an explicit
  `begin/end`; the controlled statement and cycle behavior are unchanged.
- Updated the module audit to scan both `.v` and included `.vh` definitions.

### Scripts and repository layout

- Replaced two duplicated K-sweep PowerShell drivers with
  `scripts/run_opt2_regression.ps1`.
- The canonical runner compiles/elaborates once in an isolated work directory,
  supports case/algorithm selection through plusargs, checks known error
  patterns, and writes CSV/text summaries.
- Removed 51 one-line root XSIM Tcl scripts that only duplicated `run/quit`.
- Moved three retained interactive debug Tcl files to `scripts/xsim/debug/`.
- Moved 25 scripts that intentionally target sibling projects to
  `scripts/legacy_cross_project/`.
- Changed 23 opt2 synthesis scripts from hard-coded absolute paths to paths
  derived from their own location.
- Changed current opt2 export/synchronization scripts to derive the repository
  path rather than naming another architecture directory.
- Added a project layout and canonical regression guide in `README.md`.

## Static verification

| Check | Result |
|---|---:|
| Extracted LFSR lookup exact match | PASS |
| Extracted support service exact match | PASS |
| Verilator lint parse/elaboration | PASS, 0 errors |
| Vivado `xvlog` of refactored owner files | PASS |
| Python syntax scan | PASS, 0 errors |
| PowerShell parser | PASS, 0 errors |
| Module audit | 23 modules found, 0 uninstantiated internal modules |

## Dynamic regression

### Dedicated M=64, N=256, K=16

Result: **33 PASS, 0 FAIL**.

| Algorithm | Cycles after refactor | Baseline | Match |
|---|---:|---:|---:|
| OMP | 110,785 | 110,785 | YES |
| IHT | 105,466 | 105,466 | YES |
| HTP | 173,848 | 173,848 | YES |
| GP | 106,282 | 106,282 | YES |
| GOMP | 60,894 | 60,894 | YES |
| MP | 60,145 | 60,145 | YES |

CoSaMP and SP retain the existing K=16 skip rule because they require 2K
candidate support.

### Full K-sweep

Cases cover K=2, K=4, K=8, and K=16 across the existing M/N configurations.

- Result: **348 PASS, 0 FAIL**
- Cycle/status/nonzero records: **62 baseline, 62 refactor**
- Record mismatches: **0**
- Known error-pattern matches: **0**

Local ignored-log SHA-256:

- Dedicated K16:
  `97D31F6D303D113B9A92889E7B28BA1BEFC205A8BABB66C7B7BBCB43FEF921F9`
- Full K-sweep:
  `3615A7323F30C3157AAF83FA4768F0CF0C032196E55F1C98A226AD0688144B50`

## Timing and resources

Fresh 100 MHz out-of-context synthesis completed with 0 errors. Every tracked
timing/resource metric matches the pre-refactor report.

| Metric | Before | After |
|---|---:|---:|
| WNS | +3.001 ns | +3.001 ns |
| Worst data-path delay | 6.989 ns | 6.989 ns |
| Total LUT | 96,755 | 96,755 |
| Logic LUT | 95,219 | 95,219 |
| LUTRAM | 1,536 | 1,536 |
| FF | 32,558 | 32,558 |
| BRAM36 | 24 | 24 |
| DSP48 | 71 | 71 |

Conclusion: the cleanup preserves correctness, cycle counts, timing, and
resource utilization for the verified opt2 factor-reuse architecture.
