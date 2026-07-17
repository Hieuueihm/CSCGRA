# PE-core PEOP refactor checkpoint

Date: 2026-07-02
Project: D:\vivado_pj\CSCGRA_opt_architecture

## Current checkpoint

The wrapper-style/side-helper direction is removed. The current direction is true PE-core/PE-tile PEOP infrastructure:

- `pe_core` owns row-role PEOP hooks using:
  - `ROW_ID`
  - `GLOBAL_COL`
  - `peop_mode`
  - `peop_base_idx`
  - `peop_limit`
  - `peop_threshold`
  - `peop_shift`
- `pe_tile` pipelines PEOP config into `pe_core`.
- `pe_cluster_4x4` passes row/column identity into each PE:
  - `.ROW_ID(r)`
  - `.GLOBAL_COL(GLOBAL_C)`
- `pearray` now has real PEOP input ports and passes them to both clusters.
- `pearray` exposes `peop_row2_data` from physical Row2 PE outputs.
- `cgra_top` currently drives PEOP inputs to neutral defaults, so behavior remains baseline until controller issue is enabled.

## PEOP logic currently present inside pe_core

Initial inactive PEOP hooks:

- Row2 + `PEOP_UPDATE`: saturating add/shift style update.
- Row2 + `PEOP_PRUNE`: abs/threshold/range mask style compute.
- Row3 + `PEOP_RESID_COMMIT`: residual-style subtract/saturate placeholder.

These hooks are inactive while `peop_mode = 4'd0` from `cgra_top`.

## Validation completed

Compile/elab:

```text
XVLOG_XELAB_PASS
```

SNR K8 smoke simulation after exposing `peop_row2_data`:

```text
OMP    cycles=78833  PASS
CoSaMP cycles=216766 PASS
IHT    cycles=128253 PASS
HTP    cycles=398673 PASS
SP     cycles=221900 PASS
GP     cycles=117777 PASS
GOMP   cycles=42531  PASS
MP     cycles=233729 PASS

runs 8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL
```

## Next safe step

Do not add a side datapath wrapper in `pearray`.

Next work should connect controller-issued PEOP gradually:

1. Add PEOP issue outputs from `sparse_loop_controller` through `sparse_kernel_service_engine` and `cgra_top` into the existing `pearray` PEOP ports.
2. Start only with behavior-equivalent Row2 update mode for `OP_IHT_UPDATE` / `OP_GRAD_STEP`.
3. Use `peop_row2_data` as the candidate replacement for the old controller-side `pe_update_block_w`.
4. Run `xvlog/xelab`, then SNR K8.
5. Only after SNR K8 is stable, run selected k-sweep cases and then full k-sweep.
