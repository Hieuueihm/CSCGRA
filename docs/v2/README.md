# CSCGRA opt2

This directory documents the v2 architecture. The factor-reuse checkpoint
`96305d1` is its historical baseline; the current signed-off source adds
strict PE0 ingress and timing-closed four-row wavefront pipelines.

## Layout

- `CSCGRA.srcs/sources_1/new/`: synthesizable RTL.
- `tests/run1/`: current K-sweep and large-case regression testbenches.
- `tests/`: shared golden data and focused unit/integration testbenches.
- `scripts/`: reproducible simulation, synthesis, export, and audit tools.
- `scripts/xsim/debug/`: retained interactive XSIM debug scripts.
- `scripts/legacy_cross_project/`: provenance-only tools that target sibling
  projects and are not part of the opt2 flow.
- `sdk_app/`: software-side test application and exported golden data.
- `analysis/`: compact checked-in result summaries.
- `runs/`: generated logs, reports, snapshots, and checkpoints; ignored by Git.

The large generated LFSR jump table and the support-set service live in
`*.vh` files next to their owning RTL. They are included by
`sparse_loop_controller.v` and `sparse_kernel_service_engine.v`; they are not
independent compilation units.

## Canonical regression

Run all configured K cases:

```powershell
.\scripts\run_opt2_regression.ps1
```

Run only M=64, N=256, K=16:

```powershell
.\scripts\run_opt2_regression.ps1 -Cases 0
```

Run selected algorithms for a case:

```powershell
.\scripts\run_opt2_regression.ps1 -Cases 1 -Algorithms 0,2,3,5,6,7
```

The runner compiles and elaborates once, runs every requested selection from
the same snapshot, rejects known failure patterns, and writes a summary under
`runs/opt2_regression/`.

## Refactor invariants

Cleanup changes must preserve:

1. algorithm results and golden-vector checks;
2. reported cycle counts for a fixed test configuration;
3. the factor-reuse behavior of checkpoint `96305d1`;
4. the four-row PE participation already present in large LS operations;
5. strict PE0 -> PE1 -> PE2 -> PE3 operand provenance; and
6. the current validated 100 MHz timing result (`WNS = +0.109 ns`).

See `FACTOR_REUSE_CORRECTNESS_REPORT.md` for the signed-off regression matrix,
cycle counts, timing, resources, and local log checksums.

The superseding strict-ingress report is
`reports/releases/STRICT_PE0_TIMING_SIGNOFF_20260804.md`.
