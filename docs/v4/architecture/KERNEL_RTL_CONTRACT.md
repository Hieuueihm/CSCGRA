# Generic kernel RTL contract

## Feature4 QR append qualification

Profile `reuse` adds generic FACTOR_EXTEND(op19) under the existing program
revision2. OMP/GOMP prove an exact ordered support prefix and immutable Phi/Y;
BUILD_B advances the B generation, and EXTEND imports only new columns at the
next generation. Shrink/reorder/mismatch uses INIT. Corrections still apply
all reflectors and the stored-X certificate is unchanged. The generic backend
checks shape/identity; it does not infer support membership from dimensions.

[QR reuse contract](QR_REUSE.md) records the inert loaded template, generation,
mask and publication rules. [The paired XSim report](../../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md)
qualifies all20 fixed8 cases. Later resident/panel-chain/scalar-patch work is
separate; CPU AXI and board timing remain unimplemented/unqualified.

`kernel_engine` is a single-command integer execution engine. `kernel_fabric`
contains exactly two existing `pe_array` instances (32 full PEs). It adds no
multiplier. Existing qualified PE, array, feeder and reader RTL is unchanged.
This engine replaces, rather than accompanies, the resident datapath in a solver
hierarchy. A parent sequencer supplies each command; there is no algorithm PC here.

## Command interface

All `req_*` fields are captured on `req_valid && req_ready`. One request is
outstanding. Responses hold fault/data/nonzero/job/tag/fmt until acceptance.
Format is 1. Job ownership must match source slots. Format/job are not inferred
from live inputs after acceptance. Src/dst IDs are 4 bits, length is 1..128,
rows are 1..128, columns are 1..96. Scalar commands ignore length/source/dest.
For GEMV the output length comes from rows/columns and transpose; the source
must contain at least the reduction length. The parent authenticates the B
shape against its accepted resident descriptor; key/generation/job/format are
also checked on each matrix transaction by the real operand reader/cache.

| Opcode | Command | Exact integer result |
|---|---|---|
| 0 | ZERO | zero vector |
| 1 | COPY | source A |
| 2 | ADD | A+B, S27 range checked |
| 3 | SUB | A-B, S27 range checked |
| 4 | SCALE | ties-away round(A * scalar_a / 2^22) |
| 5 | NORMALIZE | ties-away round(A * scalar_a / 2^shift), exactly once |
| 6 | GEMV_B | ties-away round(sum(B_C18 * A_S27) / 2^16) |
| 7 | ENERGY | sum(A_S27 squared), raw positive signed64 |
| 8 | NARROW_X | ties-away round(A / 4), signed24 range check, then multiply by 4 |
| 9 | SCALAR_MUL | ties-away round(scalar_a * scalar_b / 2^22), signed27 extended64 |
| 10 | SCALAR_ENERGY | scalar_a squared + scalar_b squared, raw positive signed64 |

NORMALIZE shift is the internal norm bit-length exponent. It is independent
of the external measurement block exponent. Raw MAC products are shifted once;
there is no intermediate S27 rounding. ENERGY captures raw PE accumulators,
then uses one registered 65-bit add per active lane. Each prefix must fit
nonnegative signed64. SCALAR_ENERGY uses two PE products and two reduction clocks.
All products run through the existing PE multiplier. Additional arithmetic is
addition, comparisons and shifts only. No frequency or PPA claim is made.

`rsp_data` carries scalar results only; `rsp_nonzero` indicates any nonzero
vector result (or nonzero scalar result). Faults: 1 descriptor/op/format,
2 missing/short/wrong-owner source, 3 PE arithmetic fault, 4 conversion/reduction
range fault, 5 matrix/operand response fault. Fault response payload has no
numerical meaning. Scalar faults do not invalidate an unrelated destination.

## Workspace and publication

`vector_workspace` has 16 slots of 128 S27 elements: 32 banks, each 64 words,
two registered read ports and one write port. There is no RAM reset loop.
Slot validity, length, and kernel owner metadata gate visibility. Command
results collect in a 128-element candidate staging register bank. Only after
all blocks succeed does the engine invalidate the destination, write its
candidate blocks, and publish its length/owner. Debug access is blocked during
this interval. A response is made valid after publication. Source/destination
aliases are safe because all source reads precede candidate publication.
Any failed vector command invalidates its destination, including an old value;
a failed scalar command preserves all slots. Cancel/reset invalidates every
slot and flushes readers, PE state and responses. The parent must also cancel
the external memory endpoint as part of the same epoch.

The host can begin a load only while idle. It supplies slot, length, job/tag/fmt;
job/format bind the slot, while host tag is informational and is not retained.
Accepted begin immediately invalidates that slot. Fill blocks must be ordered
0..ceil(length/32)-1, with an exact tail mask, zero padding and exact last flag.
Only the final good block publishes. A bad block returns to idle with host_fault
and leaves the slot invalid. host_fault stays until the next begin/reset/cancel.
No command or debug request may interleave a host load.

Debug reads are idle-only block transactions with held data/mask/fault. Unloaded
slots return fault2 and zero data/mask. A block beyond the valid vector length
returns zero data/mask. A pending debug response blocks command/host acceptance.

## Matrix issue and retirement

The unchanged operand_reader and operand_feeder implement R1 GEMV in both
directions. Each frame broadcasts one workspace scalar to 32 outputs, selects
actual banked C18 matrix coefficients, then retires one PE MAC. ACC is cleared
once per output group and rounded to S27 only after the final reduction term.
Expected matrix frames are ceil(O/32)*K, with O and K selected by transpose.
The matrix interface is exactly the operand_reader mat_* interface. Requests
and responses are single-outstanding; tags, masks, generation and descriptor
errors propagate. A bad complete reader response is consumed before failure;
no pending reader response survives into a following command.

## Verification scope

`verification/v4/test_kernel_rtl.py` invokes only real Vivado xvlog/xelab/xsim.
The permanent TB `verification/v4/compute/tb_kernel.sv` uses real support_matrix_cache, reader, feeder and both arrays.
Python arbitrary-integer vectors independently cover all non-GEMV commands,
including signed extrema, ties, dynamic shifts and range faults. SV independent
coordinate loops provide GEMV expectations. Shapes include 1x1, 33x17,
17x33-transpose, and 128x96 in both directions, with expected frame counts.
Tests include aliases, tails, held responses, request/response stalls, stale
key/generation, a matrix fault after a staged output group, recovery, and cancel
at execution, commit and held response. This qualifies the generic kernel only;
LSQR sequencing, certificate decisions and external commit are parent integration.
