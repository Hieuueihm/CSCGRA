# Compiler mapping on the existing V4 datapath

This is the bounded compiler step, before new fusion, DMA or interconnect.
No PE, datapath, memory layout, opcode, arithmetic or rounding location changes.

## Selection contract

`compiler/v4/recovery_emit.py` selects an explicit R1/R4 override first. Auto
selection consults `config/v4_gemv_mapping_calibration.json` only for an exact
shape and orientation, choosing the lower measured command count (R1 on ties).
The profile binds 47 source/header hashes. Matching auto entries reject stale
or missing sources rather than silently advertising a calibrated choice.
Explicit overrides remain available for remeasurement and ablation.

Calibrated live-Phi shapes are M32/N64 and M64/N256, both orientations.
The standalone selector also accepts a caller-proven dense `support_columns`
for forward M32 or M64 and S in {1,2,4,8,16,24}. Normal recovery emission does
not know S statically: it remains in the support-length scalar register.
It therefore retains the labelled legacy fallback for dense commands. Global
N is never presented as known dense S; there is no runtime mapping branch.
Other unmeasured shapes retain the legacy estimate. That estimate is a feeder
heuristic, not a cycle predictor; runtime-width estimates remain diagnostic.

## Bank and frame planning

`compiler/v4/live_mapping.py` describes the existing layouts, not an invented
swizzle or a new programmable memory layout:

| Memory | Logical bank | Logical address | Bit |
| --- | --- | --- | --- |
| Phi signs | column % 8 | (column // 8) * ceil(M/32) + row // 32 | row % 32 |
| Dense B | (row + column) % 32 | row * ceil(S/32) + column // 32 | full C18 |

Dense bank pairs share 16 physical memories: memory=bank%16, port=bank//16,
physical address=port*512+logical address. Transpose changes traversal, not
storage dimensions. Program metadata includes fixed-layout descriptors and
the runtime support register; the emitted payload and loader format do not change.

`frame_plan` and `frame_schedule` expose lane masks, addresses, striped R4
tails and logical bank passes. Same-bank/same-word requests are broadcasts;
different addresses in the same pass are rejected. These planning APIs are
diagnostic: the RTL feeder still generates the actual schedule. Tile-cache
coalescing, stalls and setup are not physical transaction counts in this model.

## Evidence and limits

See `reports/v4/compiler_mapping_20260911/` for immutable XSim calibration,
final regression results and hash evidence. Its 32 measured commands and eight
fault/cancel commands are command-level tests under deterministic stalls.
The separate 60-image fixture covers active10 x two shapes x auto/R1/R4;
the historical 20-image fixture remains unchanged. Image equality is not a
full-program RTL run with eight actual outer iterations.

| Phi geometry | Direction | R1 cycles | R4 cycles | Auto |
| --- | --- | ---: | ---: | --- |
| 32 x 64 | forward | 96 | 298 | R1 |
| 32 x 64 | transpose | 291 | 168 | R4 |
| 64 x 256 | forward | 607 | 2117 | R1 |
| 64 x 256 | transpose | 2101 | 920 | R4 |

These are alternative mapping costs, not before/after speedups from this
change. The qualified program images are unchanged. No new whole-program
cycle reduction, Fmax, LUT/FF/BRAM/DSP or SoC end-to-end sign-off is claimed.
Fusion is the next separate step; DMA and interconnect are not implemented here.
