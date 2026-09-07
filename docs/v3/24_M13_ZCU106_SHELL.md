# M13 ZCU106 shell

Date: 2026-08-31

`m13_zcu106_shell_core` is the board-facing boundary around the M13 compute
integration. It exposes two independent AXI4-Lite slaves, one 128-bit AXI4 DDR
master and one interrupt.

| PS address | Interface | Contract |
|---:|---|---|
| `0xA0000000` | lifecycle CSR | fixed 14-register M12 map |
| `0xA0010000` | loader | M13 loader map |

Both apertures have a 4 KiB decode range. The loader is not an alias or an
extension of the lifecycle CSR block.

The shell sets predicate zero to the architected `ALWAYS` value in each CGRA
cluster. External auxiliary DMA traffic is disabled. Current eight-program
phase images do not reference the reserved `DMA_DONE` phase condition, so the
legacy external completion seam is held inactive. RTL does not decode program
IDs.

`scripts/impl/build_m13_zcu106.ps1` creates the ZCU106 PS, reset network, one
two-output control SmartConnect, one DDR SmartConnect and the generated block
design wrapper. It runs synthesis, placement and routing, then emits timing,
utilization, DRC, PDRC, methodology, clock and route-status reports.

No synthesis, optimization, placement or routing directive is set by the
flow.
