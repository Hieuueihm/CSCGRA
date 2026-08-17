# Flow configuration

`rtl-v1.json` and `rtl-v2.json` map a version name to its RTL manifest,
verification root, default testbench/top, FPGA part, and clock period.

The `baseline` object records the historical layout-migration baseline; it is
not automatically updated for every optimization checkpoint. Current signed-
off metrics are authoritative in `docs/PROJECT_STATUS.md` and the latest file
under `reports/releases`.

Canonical scripts read these files. Keep paths repository-relative and do not
point them at generated Vivado projects or ignored legacy workspaces.
