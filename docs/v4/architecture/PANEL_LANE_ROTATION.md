# Shared panel lane rotation

The September 12, 2026 candidate changes only combinational data selection in
`rtl/v4/dataflow/factor_panel_service.sv`. It does not add a PE, pipeline
register, programmable interconnect, command, or memory image. Existing
request masks, bank addresses, response validation, state transitions,
rounding and transaction handshakes remain unchanged.

## Mapping

Let `R_o(data)[lane] = data[(lane + o) mod 32]`, with each word 27 bits.
Five combinational stages conditionally rotate by 1, 2, 4, 8 and 16 words.
All stage slices and lane permutations are generate-time constants.
These are five logic stages, not five clock cycles.

For a response, rotate the bank bundle once and then use fixed lane wiring:

| Mode | Offset modulo 32 | Output lane reads rotated word |
| --- | --- | --- |
| Range | row_start + col_start | lane |
| Wide DOT/RANK | row_start + slot_row + col_position | lane |
| Narrow DOT | row_start + slot_row[2:0] + col_position | 8*(lane mod 4) + floor(lane/4) |
| Narrow RANK | row_start + 16*floor(slot_row/8) + slot_row[2:0] + col_position | 8*(lane mod 2) + floor(lane/2), lane < 16 |

The omitted narrow-DOT row-block term is a multiple of 32, so it cannot
change a bank index. Narrow-RANK's row-block term contributes only bit 4
of the five-bit offset. Invalid/tail lanes still use the original guards.
Upper narrow-RANK lanes are zero in the new helper bus and never consumed
by the existing valid-lane conditions.

For a write, select the result slot once. A narrow-RANK write first forms
the inverse fixed permutation for its 16 populated words, zeroing the
unused half. A five-stage rotation in the opposite direction then maps
these words to banks. The original per-bank request mask and write enable
still control consumption of this helper bus.

The final candidate also shares the rotations used to fill caches. A range
load rotates `vec_rsp_data` by `row_start mod 32`; each of the 128 fixed
cache destinations then reads its constant lane modulo 32. PROJECT DOT
and SCALE select their existing result bundle before one opposite rotation
by `(col_position - col_start) mod 32`, shared by all 96 fixed destinations.
The original block, span and mask guards still select which words are written.
No unwritten cache word is initialized or otherwise changed.

The rewritten paths remove repeated variable bit-part-selects from
`panel_rsp_data`, `slot_result`, and the three cache-write data paths.
Cache reads and bank-address arithmetic are outside that initial candidate's scope.

## B-cache read-window follow-up

The follow-up replaces the repeated 96-word B-cache reads for wide RANK,
narrow RANK and SCALE with one shared 32-word window. The existing 96
storage words and all cache writes remain unchanged; there is no additional
cache image, pipeline stage, PE or transaction.

For `delta = col_position - col_start`, let `offset = delta mod 32`.
Each fixed bank selects one of its three existing words using
`block = floor(delta/32) + (bank < offset)`. A five-stage combinational
rotation then reads bank `(lane + offset) mod 32`. Thus the output is
exactly `b_cache[delta + lane]`. Narrow RANK reads window word `lane/2`,
while wide RANK and SCALE read window word `lane`.

The signed 12-bit difference and signed block selection retain the old
out-of-range behavior for all known 11-bit column counters; an invalid
array index produces an unknown simulation word, not an alias to a valid
cache location. Legal feed spans remain controlled by the original guards.

`verification/v4/test_factor_panel_bcache_rtl.py` checks all 4,095 signed
counter differences with four data patterns (524,160 word comparisons),
including block boundaries and out-of-range words. It additionally checks
4,732 legal wide-RANK, narrow-RANK and SCALE feed/width/window combinations
against the original cache indexing and masks. Real-fabric and complete
program tests remain separate acceptance gates.

See `reports/v4/panel_bcache_20260912/` for this follow-up's source-bound
evidence and comparison against the accepted 63,880-LUT panel, rather than
against the older 474,749-LUT revision.

## Verification and limits

`verification/v4/test_factor_panel_rotation_rtl.py` checks the helper
networks against the original coordinate equations in XSim, including
all 32 offset residues, 32 row residues, four slots and four mapping modes
(65,536 whole-bundle comparisons, including both cache rotations). Protocol coverage comes separately
from the existing panel, narrow real-fabric, PROJECT, range and energy
tests, not from this combinational test alone.

Whole-program acceptance uses immutable PIO/DMA traces for ten algorithms,
M32/N64 and M64/N256, K8 and eight actual outer iterations. Every byte,
including cycle buckets, must match. The compiler mapping calibration
must be remeasured before updating its source binding.

See `reports/v4/panel_mux_20260912/` for source-bound evidence and the
OOC comparison. Standalone panel synthesis is not full `csr_top`
utilization, implementation, routed timing or board sign-off. OOC uses
the existing internal 10 ns clock with no external interface delays.
