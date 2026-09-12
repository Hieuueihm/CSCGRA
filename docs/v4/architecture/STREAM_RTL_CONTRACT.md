# First streaming RTL slice — revision 1

Authority: [machine-readable ABI](../../../config/v4_stream_interface.json),
generated [RTL constants](../../../rtl/v4/include/stream_interface.vh), and
[context execution design](CONTEXT_EXECUTION.md). This contract freezes the
first slice's interfaces; it does **not** freeze production numerical widths.

## What this slice implements

A host loads a program and kernel templates, initializes vector RAM, and issues
START. A hardware PC executes CALL/HALT without host decisions between CALLs.
Each template supplies 32 independently encoded PE contexts, one for each PE
in exactly two 4×4 arrays. The same PEs execute vector arithmetic, lane-wise
accumulation and dot products. There is no algorithm ID decoder or separate
dot-product multiplier array.

This slice accepts explicit operand vectors in RAM. Live Phi/B generation,
R1/R4 matrix traversal, scalar DIV/SQRT, branches, full local RF/mesh routing,
selection, LSQR and complete recovery programs remain subsequent integration.
It must not be described as eleven algorithms already running on the new RTL.
The existing bounded LSQR implementation remains a separate reference root.

| Module | Owns | Does not own |
|---|---|---|
| `stream_program_control` | Image loading, validation, immutable program/templates, PC, one outstanding CALL, identity checks | Arithmetic or RAM ports |
| `stream_engine` | Source validity, memory arbitration, frame join, scratch, result fold/narrow, CALL publication | Algorithm-specific iteration decisions |
| `stream_vector_store` | Sixteen paired TDP banks and two reserved read credits | Public validity or whole-command transactions |
| `stream_fabric` | Atomic configuration/command issue and retirement across two arrays | Program PC or global vector addresses |
| `stream_array` | Alignment of sixteen lane responses under backpressure | Inter-array mesh or additional arithmetic units |
| `stream_pe` | Selected operands, exact arithmetic, product pipeline and signed64 accumulator | Algorithm-specific state |

## Program and template ABI

All packed words are unsigned containers. Fields below are listed least
significant first. Reserved bits must be zero. Unknown opcodes, unsupported
combinations, out-of-range indices and nonzero reserved bits cause faults;
they are never silently interpreted as another operation.

| Program128 field | Bits | Offset |
|---|---:|---:|
| kind | 8 | 0 |
| template | 4 | 8 |
| src_a | 9 | 12 |
| src_b | 9 | 21 |
| dst | 9 | 30 |
| frame_count | 8 | 39 |
| tail_mask | 32 | 47 |
| reserved | 49 | 79 |

CALL=1, HALT=2. HALT has zero payload. CALL references a loaded template,
contains 1..32 frames, and has nonzero tail_mask. All frames except the last
use mask `0xffffffff`. A frame contains 32 logical lanes; 32 frames therefore
cover 1024 entries. Address ranges are checked using frame count and each
increment flag before a CALL executes. Program fall-through without HALT is
a fault. Capacity is 256 program words and 16 templates.

| Template descriptor32 field | Bits | Offset |
|---|---:|---:|
| inc_a, inc_b, inc_dst | 1 each | 0, 1, 2 |
| output_kind | 2 | 3 |
| shift | 6 | 5 |
| reserved | 21 | 11 |

| Per-PE context64 field | Bits | Offset |
|---|---:|---:|
| op | 5 | 0 |
| mode | 1 | 5 |
| src_a | 2 | 6 |
| src_b | 2 | 8 |
| immediate, signed two's complement | 27 | 10 |
| reserved | 27 | 37 |

Sources A=0, B=1, IMM=2, ZERO=3 select the two frame operands, the signed
immediate or zero. MOV=1, ADD=2, SUB=3, MUL=8 and MAC=9 reuse the existing PE
opcode values. **This context64 is a new ABI**, not the legacy tile64 encoding;
program128 is also distinct from the existing solver service-program128.
Revision, format and capability validation prevent accidental cross-loading.

| Output | Accepted contexts | Result |
|---|---|---|
| EACH=0 | MOV/ADD/SUB/MUL; descriptor shift=0 | S27 vector for every frame |
| LAST_ACC=1 | All 32 contexts MAC | Each lane's final raw accumulator rounded by shift 0..63, checked into S27 |
| SUM_ACC=2 | All 32 contexts MAC; descriptor shift=0 | Checked sum of all 32 raw accumulators, signed64 scalar |

LAST_ACC's output mask is the union of accepted frame masks. SUM_ACC includes
all earlier active contributions, including lanes inactive in the final tail.
An inactive last-frame lane must not erase its previous accumulator.

## Loading and identity

Accepted BEGIN invalidates the previous image. Supply all program words in
index order, then each template in ID order: descriptor at lane 0 (upper 32
bits zero), followed by contexts at lanes 1..32. Program `last` is asserted
only for the final program word; template `last` only for the last context
of the entire package. BEGIN gives revision, verified bit and word/template
counts. The verified bit represents trusted host verification, not RTL SHA256.

`image_valid` is asserted only after the complete package passes validation.
The load status is held until accepted; START cannot pass an outstanding load
status, partial load, running program or held completion. Images are immutable
during execution. A malformed load cannot execute a partially replaced image.

START captures job16/tag16/format8. CALL and all completions carry this identity;
mismatches fault. Completion payloads remain stable while stalled. HALT
completes only after previous CALLs retire. Cancel silently flushes execution,
pending responses and completion; a previously completed image is retained.
Cancel during an incomplete load leaves the image invalid. Synchronous reset
clears image and control validity.

## RAM ports, validity and aliasing

The pool is 512 blocks × 32 lanes × S27 = 16384 logical words. Blocks 0..479
are public; blocks 480..511 are internal scratch. Neither host nor program
references may address scratch. No automatic assignment of whole-algorithm
vector lifetimes is claimed by this physical capacity.

Logical lane `l` maps to physical bank `l % 16`, port `l / 16`, and physical
word `(l / 16)*512 + block`. Thus each bank has a 1024×36 geometry with 27
bits used and disjoint address halves for the two ports. This is a proposed
BRAM inference organization, not a measured RAMB36 utilization report.

The pool grants **one 32-element read OR write per clock**. It has no free
2R1W access. Two read credits include the synchronous RAM stage and queued
responses. The first response becomes valid after the second edge, counting
the accepting request edge as the first. Writes do not produce leaf responses;
top-level host transactions acknowledge both reads and writes. Masked reads
return zero on inactive lanes. A write after a read request must not change
that read's captured value. Reset/cancel flush credits and responses, not RAM
bits. Top-level validity is cleared on reset, so retained bits cannot become
initialized data accidentally.

The host accesses public RAM only when idle; a held host transaction prevents
START. Host writes mark the corresponding lane validity. A read of any
requested invalid lane returns a fault and no usable data. Program source
validity is checked for the lanes actually selected by contexts; MOV ignores
its unused second operand.

All vector CALL outputs are staged in scratch. All source reads complete
before scratch is copied to the destination, so source/destination overlap
is supported. Validity is replaced at destination **block** granularity:
destination blocks are invalidated before copying and published only when the
complete CALL succeeds. Failed or cancelled vector CALLs invalidate all lanes
of affected destination blocks, including their old data. Unwritten old lanes
in those blocks do not remain valid after successful publication either.
For EACH with inc_dst=0, copies occur in frame order; the last write to an
active lane wins; the published mask is the union of writes to that block.
SUM_ACC does not modify vector destinations.

This is **atomic publication per vector CALL**, not rollback of an entire
program. Earlier successful CALLs remain visible if a later CALL fails or is
cancelled. Full recovery/LS result publication still needs the existing
certification and outer commit semantics when integrated later.

## Exact arithmetic

Format 1 uses candidate S27F22 and C18F16 operands with signed64 raw
accumulation. D18F14 and stored X24F20 belong to the wider numerical design;
this slice does not implement acquisition or stored-X certification.

MOV copies the selected S27 value. ADD/SUB use widened intermediate arithmetic
and reject S27 overflow. MUL rounds the exact product by 16 in C18 mode or 22
in full S27 mode, then rejects S27 overflow. Rounding is nearest, with ties
away from zero. Overflow cannot produce a successful clipped result.

In mode 0 the selected B operand must be a valid sign extension of C18.
Mode 1 multiplies signed S27 by signed S27 through one 27×18 multiplier per
PE: B is split into unsigned low17 and signed high10, whose products are
combined exactly. A second multiplier must not be added to claim II=1.

MAC adds each exact raw product into a zero-initialized signed64 lane
accumulator with checked prefix overflow. Rounding is deferred to the defined
output boundary; SUM_ACC retains raw scaling. The final fold itself checks
signed64 overflow. Faults remain sticky until command retirement or cancel.
Fabric outputs are speculative until its successful completion; the engine
must not publish early frames of a command that later faults.

The engine processes final accumulator lanes sequentially: one shared checked
narrow path for LAST_ACC or a checked scalar fold for SUM_ACC. LAST_ACC does
not add 32 parallel variable-width shifters outside the PEs. Both operations
visit 32 lanes once after the fabric finishes; this overhead is counted in
kernel latency. It is a resource/timing design choice, not measured PPA.

## Pipeline and cycle evidence

Acceptance is `valid && ready`. Producers hold data, masks and identity while
stalled. Buffer capacity is reserved before accepting a beat, including work
already in pipeline stages. Cancel/reset reject new beats on that edge and
flush every endpoint; delayed responses cannot enter a subsequent command.

The first compute candidate uses P1 accumulation and an elastic product/result
pipeline. C18 throughput aims for one accepted frame per cycle; full S27 uses
two multiplier phases. Actual acceptance intervals and stall behavior must be
measured with xsim before either rate is claimed. Array barriers must align
mixed lane operations and prevent one PE advancing to another frame alone.

Top-level memory scheduling, source joins, scratch and commit have their own
cycle costs. Fabric II is not kernel latency, full-algorithm cycles or a board
clock measurement. Two input reads plus one scratch write already consume
three pool grants per generic binary vector frame, before publication traffic.
Counters report accepted-job clocks, input/output frames, memory reads/writes
and stalls so this cost remains visible.

The initial engine has one A/B frame-buffer pair. It overlaps PE execution
with subsequent reads, but does not promise to hide every RAM response bubble.
The measured engine schedule must be compared against the port-grant bound
before selecting prefetch depth for the live Phi/B integration.

## Acceptance before extending the architecture

Use Vivado xvlog/xelab/xsim only for RTL qualification. Python may encode images
and provide independent integer oracles. Record exact source hashes, executed
commands, outputs and scope. Required cases include ordered/malformed loading,
two distinct loaded images, independently selected PE contexts, 1024 entries,
tails, overflow, identity mismatch, backpressure, reset/cancel, invalid reads,
aliasing and fault-safe CALL publication.

Leaf acceptance does not qualify the integrated engine. This slice does not
prove reduced whole-program cycles, ZCU106 timing, resource use, production
bit widths or application quality. Those remain later gates described in
[streaming redesign](STREAMING_REDESIGN.md) and [PPA evaluation](PPA_OPTIMIZATION.md).
