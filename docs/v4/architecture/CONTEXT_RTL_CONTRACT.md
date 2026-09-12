# Packed tile64 decoder and scalar execution v1

Update: this file specifies standalone ROUTING=0 behavior. Arrays opt into
ROUTING=1 under [ARRAY_RTL_CONTRACT.md](ARRAY_RTL_CONTRACT.md). The scalar
ABI remains available; route execution is no longer universally unimplemented.
rsp_drop is a new explicit retirement input: tie low for this standalone
contract; arrays assert it on global failure to preserve committed state.

Scope: connect actual compiler-generated 64-bit tile words to the existing
[decoded pe_tile](TILE_RTL_CONTRACT.md). This does not decode the separate
256-bit control word, execute loops/DMA, or coordinate array routing. The
packed ISA revision/field widths and enum values in [CONTEXT.md](CONTEXT.md)
remain unchanged. TILE_FIELDS in compiler/v4/context_image.py is now the shared
field-width authority for pack/unpack and generated RTL constants.

## Hierarchy and byte order

    planned pe_array
      pe_context (one outstanding packed transaction)
        context_decode (combinational validation and local-op translation)
        pe_tile (RF8, predicates, operand selection and pe_alu)
      mesh_router (array issue coordination remains planned)

There are 32 instances each of pe_context and context_decode in the intended
system. Both are functional implemented blocks; no empty top/array stub.
req_word is the numerical little-endian decoded integer: opcode at bits 5:0.
The compiler's tile_NN.hex lines are byte strings in emitted byte order, NOT
ready-to-readmemh numerical words. For each line use
int.from_bytes(bytes.fromhex(line), 'little') before driving req_word.
Tests export/load a complete compiler image and drive words converted this way.
Do not reverse bytes in the packer to accommodate a testbench.

## Decoder validity versus executable subset

context_decode validates ALL fields even on a false tail or predicate:
revision, reserved bits, known opcode/source/format/route enums, LINK selector
0..3 and physical input edge, output edges, NOP zero payload, HALT no routes,
ROUTE nonempty and source A in ACC/LINK/NONE. WORD=11 for malformed encoding,
EDGE=12 for illegal physical edges, REV=14 for wrong revision. Priority:
REV, WORD, EDGE, then EXEC=13 for structurally valid but unsupported semantics.
Thus invalid programs cannot hide in masked lanes. V4 source/tile arithmetic
faults 0..10 retain their existing meaning after successful decoding.

Any nonzero route field returns EXEC at this scalar wrapper (including legal
ALU+route words). The decoder still exposes decoded routes for verification.
No ALU/RF/ACC/predicate write or link occurs on that response. Do not silently
drop routes, commit arithmetic before checking routes, or claim R4 execution.
Array-wide atomic issue/route completion is a later gate. R4 template words are
checked here for structural/unsupported status, not executed as a GEMV program.

## Explicit scalar semantics (execution-subset revision v1)

These rules qualify a documented subset of the existing candidate encoding;
the generic packer remains structural and can encode unsupported words.

| Packed opcode | Local operation and supported flags |
|---|---|
| NOP | HOLD, completely zero payload as before |
| CLEAR | ACC_CLEAR; acc_write=1, rf_write=0; format FIXED or NONE; source fields ignored after structural validation |
| READ, MOV | MOV source A; acc_write=0; optional RF write; NONE/SIGNED/UNSIGNED/FIXED/ADDRESS are raw transfer labels |
| STORE | MOV source A (ACC source rounds once under tile contract); acc_write=0; optional RF write; emits rsp_store, no memory write inside this block |
| MAC | MAC; FIXED, acc_write=1; optional RF write of local data result (zero) |
| MUL | MUL; FIXED, acc_write=0; optional RF write |
| ADD, SUB | signed S ADD/SUB; acc_write=0; SIGNED or FIXED |
| ADD with acc_write=1 | only source A=ACC, B=LINK and FIXED; translates ACC_ADD using the selected full-width ingress link and its valid bit |
| CMP | CMP_S for SIGNED/FIXED, CMP_U for UNSIGNED/ADDRESS; acc_write=0; predicate field 0..2 selects destination, writes less-than; optional RF write of 0/1 |
| SELECT | raw SELECT; acc_write=0; predicate field is selection code, not execution guard |
| HALT | local zero-payload HOLD; returns rsp_halt; actual program stop belongs to sequencer |
| ROUTE or any route sideband | EXEC until integrated array routing exists |

For opcodes other than CMP/SELECT, predicate field is the existing decoded
guard code (0=always, 1..3=P0..P2, 4..6=negated predicates, 7=never).
CMP executes on an active lane and writes less-than to P0/P1/P2; SELECT executes
on an active lane and chooses using the same code table. No new reserved-bit
encoding is invented for other predicate operations or ABS/Boolean micro-ops.
Those decoded-tile capabilities remain unavailable in this packed subset.

req_mode remains an explicit sideband from the future locked operator/kernel
descriptor: 0=S*C, 1=S*S. Do not infer precision from vague format enums.
For FIXED MUL/MAC in mode 0 the packed convention is A=coefficient, B=state,
matching the existing READ(MATRIX)->RF, MAC(RF,VECTOR) template. Decoder swaps
source kind/index A/B to local ALU S*C. Mode 1 does not swap. Both use the same
per-word immediate. The wrapper does not quantize or guess coefficient values.

Full-width ADD(ACC,LINK) uses req_wlinks[idx*64 +:64] and req_link_valid[idx],
not a truncated S-width link. Other LINK operands use req_links[idx*27 +:27].
The future ingress/feeder must supply the correct raw format and matching tags;
all source fields belong to one atomic request, not independently timed streams.

## pe_context boundary and retirement

Parameter TILE_ID=0..31. Inputs clk/rst/cancel; req_valid, req_word[63:0],
req_rev[7:0], req_mode; req_mat/req_vec[26:0], req_links[107:0],
req_wlinks[255:0], req_mat_valid, req_vec_valid, req_link_valid[3:0];
req_lane, req_job[15:0], req_tag[15:0], req_fmt[7:0], req_last; rsp_ready.
Outputs req_ready, rsp_valid, rsp_data[26:0], rsp_acc[63:0], rsp_cmp[2:0],
rsp_fault[3:0], rsp_job/tag/fmt/last/lane/exec plus rsp_store/rsp_halt.
req_fmt is opaque format provenance, separate from the packed operation format.

No extra register stage: normal response latency 1, S*S MUL/MAC latency 2,
minimum II 2/3, no same-edge replacement. Decoder errors take latency 1 through
an inert tile request and preserve all architectural state. Their rsp_exec=0,
store/halt=0. Successful STORE/HALT flags are meaningful only with rsp_valid;
they are gated by executed lane/guard and no fault. A STORE transfers data with
the response handshake; the downstream writeback must be its consumer.
HALT is an event only; this local block may accept later requests if the
external sequencer continues. Neither event causes an unacknowledged side effect.

Hold response/flags/tags under stall. RF/predicates/ACC commit together only on
successful retirement. Reset/cancel overrides all transfers and clears the tile,
including a pending two-cycle operation or an unretired STORE/HALT response.

## Verification

Use a fixed verification/v4/pe/tb_pe_context.sv and an independent Python model
that calls compiler unpack_tile and structural edge validation before translating
to TileModel. Test all opcodes, all raw enum/reserved mutations, flags/formats,
operand swapping, guard/compare/select, wide links, byte order, stalls, tail,
reset/cancel, error rollback and all 32 positions. Export/load a full context
image; replay a straight-line scalar program from tile hex, with externally
supplied operands. Existing R1/R4 template checks must retain NOT_EXECUTED and
NOT_PROVEN; individual words passing is not control-flow/program qualification.
No synthesis/implementation, full-array GEMV or LSQR claim follows.
