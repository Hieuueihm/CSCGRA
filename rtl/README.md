# RTL source

This is the active authoritative synthesizable RTL tree.

- `v2/`: strict-PE0, four-row, factor-reuse implementation.

The frozen v1 tree is archived under `archive/v1/rtl` and is not a canonical
optimization target.

Use `rtl/v2/files.f`. Do not compile RTL from local
`CSCGRA_opt_architecture*` directories or generated Vivado `*.srcs` trees.
Behavioral work goes to v2.

Current v2 metrics and retained optimizations are summarized in
`docs/PROJECT_STATUS.md`.
