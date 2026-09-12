# Resident execution: measured cycles and open bottlenecks

The current backend establishes a bounded correctness baseline. The values below
are from the Vivado 2018.1 [resident gate](../../../reports/v4/resident_rtl_correctness.json).
They are simulation clock counts under deliberate backpressure, not measured
100 MHz hardware throughput. The [unified gate](../../../reports/v4/RTL_CORRECTNESS.md)
qualifies the integrated source; no synthesis or implementation has run.

## What the measurements include

Each case starts twice from preloaded context, descriptors and resident memories.
JSON totals sum both runs; this table reports one run. Cycles include execution
and imposed arbitration/output stalls, but exclude context load, Phi cold fill,
B construction/fill, vector load, host DMA and committed result writeback.
The bench does not stall mesh links in these integrated cases; separate router
and fabric tests exercise link backpressure.

| Case | Mode/direction | Operand frames/run | Retired context rows/run | Cycles/run |
|---|---|---:|---:|---:|
| Phi or B 33×35 | R1 forward | 70 | 217 | 2,535 |
| Phi or B 33×35 | R4 transpose | 80 | 281 | 2,997 |
| B 33×35 | R1 transpose | 66 | 205 | 2,395 |
| B 33×35 | R4 forward | 80 | 281 | 3,060 |
| 1×1 | R1 | 1 | 7 | 75 |
| 1×1 | R4 | 8 | 33 | 328 |
| Phi 128×1024 | R4 transpose | 4,096 | 13,313 | 152,342 |
| B 128×96 | R4 forward | 384 | 1,281 | 14,582 |

For outputs O and reduction length K, expected operand frames are:

- R1: `ceil(O/32) * K`.
- R4: `ceil(O/8) * ceil(K/32) * 8`.
- Useful arithmetic slots: `O*K / (32*operand_frames)`.

The two maximum cases fill 100% of the scheduled MAC slots. This describes
useful work within MAC frames, **not PE activity across all execution cycles**.
For 1×1 the fractions are 3.125% in R1 and 0.390625% in R4; seven R4 frames
have zero active lanes. Thus R4 is not universally the faster mode.

## Bottlenecks supported by current evidence

The compact compiler repeats three control rows per operand frame, then the
outer-loop work. For output groups G and F frames per group, retired rows are
`G*(3*F+3)+1` in R1 and `G*(3*F+8)+1` in R4. The maximum Phi transpose executes
4,096 MAC rows but 13,313 rows in total. Of those, 8,321 are loop/control/HALT
rows with all tile operations NOP, which still pass through the arrays.
The serialized PC/read/frame handshake therefore adds substantial control work.

The trace does not yet isolate which pipeline state dominates total cycles.
Its request-stall counter combines matrix/vector request blocking; it excludes
response arbitration and join latency. For maximum Phi, each run observes 4,734
request-stall cycles, 254 sink-stall cycles and four forced completion-block
cycles. Those counters alone do not explain all 152,342 cycles.

## Next optimization work and required evidence

1. Measure cycles per sequencer and reader state; separate matrix/vector request
   and response stalls, join latency, active MAC lanes, zero-mask frames,
   array completion skew, route stalls and sink stalls. Count cold setup costs
   separately before publishing total-job throughput.
2. Consider retiring validated all-NOP control rows without array traversal.
   Preserve row validation, tags, loop/branch behavior, cancellation and faults.
3. Select R1/R4 using measured total costs. Specialize small/tail cases only
   with an explicit descriptor/cursor contract: simply shortening today's R4
   loop would misalign later output groups.
4. Evaluate one-frame prefetch and overlap of context/memory access with PE
   execution. Preserve source identity, bounded outstanding ownership and
   atomic retirement; compare identical numerical results and injected faults.

The selected architecture avoids a full dense A transfer and stores one B copy.
That choice does not by itself solve these control/feeding bottlenecks. Resource,
timing and novelty claims still need complete-job measurements and ablations.
