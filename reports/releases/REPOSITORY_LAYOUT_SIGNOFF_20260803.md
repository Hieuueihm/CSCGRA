# Repository layout refactor sign-off

Date: 2026-08-03
Branch: `codex/clean-repository-layout`
Layout checkpoint before final sign-off: `96a92fcfa67f0cf350eb95475ca32fa47f76c878`

## Scope

This sign-off verifies that moving the source into versioned RTL,
verification, software, scripts, reports, and work/log areas did not change
hardware behavior. RTL logic was not modified by this continuation.

## Static validation

- Repository layout/path validation: PASS.
- Active PowerShell scripts: zero parser errors.
- RTL manifests: all entries exist.
- Active source contains no hard-coded `D:/vivado_pj` or generated
  `CSCGRA.srcs/sources` path.
- V2 module audit: zero uninstantiated internal modules.
- V1 module audit: only the historical standalone `pe_tile` definition is
  reported as uninstantiated.

## Simulation regression

| RTL | Cases | PASS | FAIL | Result rows | Skip rows | Baseline mismatches |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| v1 | 8 | 348 | 0 | 62 | 2 | 0 |
| v2 | 8 | 348 | 0 | 62 | 2 | 0 |

V1 baseline:
`work/legacy_pre_refactor/CSCGRA_opt_architecture/runs/clean_check_run1_k_sweep_by_case`.

V2 baseline:
`work/legacy_pre_refactor/CSCGRA_opt_architecture_opt2/runs/refactor_case0_v2/full_sweep.log`.

The comparison covers M, N, K, algorithm, iteration, cycle, status, PC, and
nonzero count. CoSaMP/SP skip behavior for M=64, N=256, K=16 also matches.

### M=64, N=256, K=16 cycle reference

| Algorithm | v1 cycles | v2 cycles |
| --- | ---: | ---: |
| OMP | 254745 | 110785 |
| IHT | 177402 | 105466 |
| HTP | 489254 | 173848 |
| GP | 178218 | 106282 |
| GOMP | 135502 | 60894 |
| MP | 132113 | 60145 |

CoSaMP and SP are skipped for this case because they require 2K candidate
support.

## OOC synthesis at 100 MHz

| Metric | RTL v1 | RTL v2 |
| --- | ---: | ---: |
| WNS | +3.487 ns | +3.001 ns |
| Data path delay | 6.503 ns | 6.989 ns |
| Total LUT | 80318 | 96755 |
| Logic LUT | 73854 | 95219 |
| LUTRAM | 6464 | 1536 |
| FF | 25602 | 32558 |
| BRAM36 | 16 | 24 |
| DSP48 | 102 | 71 |
| Synthesis errors | 0 | 0 |
| Critical warnings | 0 | 0 |

V1 metrics match the pre-refactor `synth_incr_cgra_top` reports exactly. V2
metrics match the pre-refactor factor-reuse reports exactly.

## Conclusion

The repository-wide layout refactor is behavior-preserving and reproducible
for both RTL versions. Correctness, cycle count, positive WNS, and synthesized
resource totals are signed off. Generated workspaces and raw logs remain
outside the tracked source tree.
