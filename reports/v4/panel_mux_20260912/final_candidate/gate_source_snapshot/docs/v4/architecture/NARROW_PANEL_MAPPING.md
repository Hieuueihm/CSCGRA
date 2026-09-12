# Narrow factor-panel mapping — design candidate

Status: focused Vivado XSim qualification passed, including actual PE terminal/cascade arithmetic and complete factor readback. See [source archive](../../../reports/v4/context_stream_narrow_rtl_20260910/README.md). The existing wide-panel path,32 PEs, factor banks and R4/cascade links are retained. Whole-program threshold selection is separate.

For a trailing width C<=8, factor bank=(absolute_row+absolute_column) mod32 permits packing rows spaced8 apart without a bank collision. Adjacent rows would collide for several columns and must not be packed that way.

DOT: for block=0,32,64,96 and residue=0..min(8,L-block)-1, lane4*c+r owns row=block+residue+8*r and column=c, with c<C and r<4. Mask rows outside L. Existing R4 terminal combines rawACC from lanes4*c..4*c+3 and rounds22 once per column after all frames; do not round partials. Include common row_start/col_position only at address formation.

RANK update: for block=0,16,... and residue=0..min(8,L-block)-1, low lane2*c+r owns row=block+residue+8*r, c<C,r<2. Corresponding high lane16+2*c+r subtracts its checked rounded product through existing cascade. Factor reads and writes use the same inverse lane-to-bank map. No new multiply/subtract units or factor copies.

Every issued slot records its frame geometry, and issue/feed/retire/ack/last counters use frame count, not logical row_count. Dot all columns, scale all q, then rank all columns remains mandatory. Output q order is packed c; no partial factor publication after fault/cancel.

The root enumerated all2048 combinations L1..128,C1..8,DOT/RANK: each rectangle element occurs exactly once and each frame has distinct factor banks. Evidence: work/narrow_mapping_geometry_proof.json. Translation by row_start+col_position modulo32 preserves uniqueness. Legal signed S27 products over<=128 rows have absolute sum<=2^59; ACC64 grouping is exact and cannot introduce partial-ACC overflow. Checked S27 output/rounding faults still require RTL tests.

This geometry proof does not establish cycle improvement, resource use, timing margin, synthesis or board fit. Compare old/new focused panels with identical data, tails, stalls and fault/cancel coverage; then choose the compiler panel threshold using whole-program fixed8 results across all10 algorithms.
