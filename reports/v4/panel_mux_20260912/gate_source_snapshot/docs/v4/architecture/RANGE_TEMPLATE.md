# RANGE_TEMPLATE — feature7 implementation contract

Status: source-qualified in focused Vivado XSim and matched fixed8 programs at both geometries. See [focused gates](../../../reports/v4/context_stream_focused_20260910/README.md) and [range-only comparison](../../../reports/v4/context_stream_view_20260910/README.md). Installation is tracked by the current STATUS page.

Opcode22 is a command-scoped read view with ordinary loaded TEMPLATE PE arithmetic. Program record revision stays2; images emitting opcode22 require kernel feature7. Existing opcodes/profile images preserve their semantics. No persistent alias handle is created and no algorithm-specific behavior is inferred.

## Request and validation

* length L is1..1024; frame_count=ceil(L/32); tail_mask is the contiguous L tail. index is source A element offset; aux_length is source B element offset, each0..1023. They are offsets, not slice output lengths.
* The descriptor uses increment A/B/destination (low3bits=7), standard output kinds EACH/LAST_ACC/SUM_ACC and existing shift/context restrictions. Existing mode/opcode/64-bit reserved/context checks remain. Scalar input binding and IMM/ZERO semantics follow TEMPLATE.
* Source A/B capacity is checked only for selected RAM elements: offset plus the existing template_need for that source, in widened arithmetic. A statically unused RAM source requires offset0 and performs no validity/read. Source descriptor indices remain valid indices; descriptor0 is not a reserved null vector.
* dense, transpose, r4, flags, store_mode, k, support_length, support/aux descriptor indices, shift register value and unused target are canonical0. Sequencer outputs unused support_base/aux_base buses literal0, independent of descriptor0.base. Scalar outputs/flag outputs follow ordinary TEMPLATE. Destination capacity is checked against actual output: L for EACH, min(L,32) for LAST_ACC, and zero elements for scalar SUM_ACC (the destination descriptor index must still exist). Source capacity arithmetic must reject signed/high-bit offsets before truncation to11bits.
* The raw kernel also rejects offset plus highest selected packed position above1024 (the maximum possible source descriptor capacity), then validates public address bounds and exact selected physical validity masks after translating each packed lane to source offset+32*frame+lane. Source mask checks apply to selected lanes only, not unused lanes fetched in the same physical block.

## Transport and arithmetic

A packed32-lane source may span at most two public blocks. Form each selected physical provider mask, read it through existing public logical-to-physical mapping, verify response mask/tag, then assemble the operand. Zero unselected packed lanes. Sources sharing a provider may combine masks; any cache reuse must require matching identity/address and sufficient validated masks. A source-provider cache is command-local initially. No scalar numeric operation is added outside existing PEs.

Feed exactly the same packed element sequence and masks to the same contexts as explicit SLICE followed by TEMPLATE. Keep product, partial ACC, terminal reduction, rounding, checked S27 and fault points unchanged. A scalar result never publishes a vector. Vector output stays packed at destination with the existing scratch, invalidation and atomic publication/remap contract. Source/destination aliasing reads all operands under pre-command mappings; never expose partially updated destination. Cancellation/fault flush pending reads/PE work and retain the existing destination invalidation semantics.

## First compiler uses

Under a new explicit range-enabled profile (distinct from current compact and streamed), replace backsolve SLICE(P,D,j,L); DOT(A,P) with RANGE_TEMPLATE DOT(A offset0,D offsetj). For QTy updates, replace SLICE(W,Y,j,L); DOT(V,W) with range DOT(V0,Yj), retain RESCALE and scalar tau multiplication, then use range SUB(Yj,P0) into packed W and the existing REPLACE_RANGE publication of Y. Keep factor, support, stored-X certificate, correction/refinement and iteration logic unchanged. Unused slices/descriptors may be retained for compatibility unless removal is separately tested.

## Required gates

Compare zero-offset against TEMPLATE and unaligned offset1/31/32/33/95 plus L1/31/32/33/64/96/128/max1024 where capacity permits. Include partial selected masks, scalar-bound/unused sources, shared-provider A/B, alias dst=A/B, exact final public block479 bounds, wide overflow bounds, malformed flags/context/descriptor, missing valid lane, stale tags, stalls, reset/cancel during read and commit. Compare independent integer expectations and explicit SLICE+TEMPLATE results using Vivado XSim. VMs and compiler require matching positive/negative validation, preserving rawX/R/support/status/certificate under actual8 whole-program runs. Shared Arithmetic is not independent numerical evidence.
