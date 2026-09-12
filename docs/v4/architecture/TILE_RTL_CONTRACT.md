# Retirement extension

The array integration adds rsp_drop: a response handshake with drop=1 discards
the pending RF/predicate/ACC updates without resetting committed state. Standalone
users tie drop=0. See [array contract](ARRAY_RTL_CONTRACT.md).

# Decoded pe_tile contract v1

This slice adds RF8, three local predicates and operand selection around the
existing [pe_alu](PE_RTL_CONTRACT.md), following [V4 baseline](BASELINE.md).
It is a decoded execution endpoint. The subsequent [packed scalar wrapper](CONTEXT_RTL_CONTRACT.md)
translates a documented subset of the candidate 64-bit [context image](CONTEXT.md)
into this ABI; packed layout and numerical profile are unchanged.

## Hierarchy and definitions

    pe_tile (RF8, validity bits, predicates, retirement)
      src_a: pe_operand
      src_b: pe_operand
      alu: pe_alu (persistent ACC and multiply pipeline)

mesh_router remains a sibling in the planned pe_array, not duplicated inside
the tile. There are 32 tiles, 64 operand mux instances, 32 ALUs and 32 routers.
Constants come from config/v4_tile_interface.json, V4 context operand enums,
the selected array geometry and the existing candidate S27F22/C18F16/ACC64 build.
Regenerate with scripts/v4/generate_tile_interface.py; --check detects drift.

## Ports

Inputs: clk/rst/cancel; req_valid, req_op[4:0], req_mode;
req_a_kind[3:0], req_b_kind[3:0], req_a_idx[2:0], req_b_idx[2:0];
req_imm[15:0], req_mat[26:0], req_vec[26:0], req_links[107:0],
req_mat_valid, req_vec_valid, req_link_valid[3:0]; req_wide[63:0], req_wide_valid;
req_guard[2:0], req_sel[2:0]; req_rf_we, req_dst[2:0],
req_pred_we, req_pred_dst[1:0], req_pred_src[2:0];
req_lane, req_job[15:0], req_tag[15:0], req_fmt[7:0], req_last; rsp_ready.
Outputs: req_ready, rsp_valid, rsp_data[26:0], rsp_acc[63:0], rsp_cmp[2:0],
rsp_fault[3:0], rsp_job/tag/fmt/last/lane/exec.
TILE_ID parameter is 0..31 and determines local N/E/S/W edge availability.

Tags/format are opaque and snapshotted. req_mode retains the ALU meaning:
0 for S*C accumulator scale, 1 for S*S. req_fmt is not a runtime Q-format switch.
All ingress operand fields form one atomic request snapshot; a missing required
external source returns a fault, not an implicit wait. The future feeder must
assert the request only with its required sources ready.

## RF and predicates

RF is eight S-width words with eight validity bits. Reset/cancel zero the data
and clear validity. Reading an unwritten RF is UNINIT, not a silent zero.
Only successful, enabled response retirement writes rsp_data to the captured
req_dst and marks it valid. The destination may equal a source: reads use the
old committed value; there is no forwarding of an unretired candidate.

Three predicate bits reset false. Guard and SELECT controls independently use
0=ALWAYS, 1=P0, 2=P1, 3=P2, 4=!P0, 5=!P1, 6=!P2, 7=NEVER.
Execution requires req_lane && guard. SELECT chooses A when its req_sel control
evaluates true, otherwise B. Neither control updates predicates by itself.
Captured predicate destination must be 0..2 when write is enabled.
Predicate write sources: 0=rsp_data[0], 1=less, 2=equal, 3=greater,
4=!rsp_data[0], 5=false, 6=true; 7 is invalid. These selectors describe local
retirement, not new packed context encodings. Boolean programs use 0/1 raw
values with AND/OR/XOR; logical NOT is XOR with 1 or predicate NOT_DATA.

RF, predicates and ALU ACC update at the SAME successful response handshake.
During any stall, all persistent state and pending write metadata hold. Failed
or masked responses change none of them. Reset/cancel overrides retirement,
clears all local state and suppresses ready/valid immediately while asserted.
This is local commit, not the outer x/support/residual transaction controller.

## Operand sources

Source numbers are imported unchanged from compiler/v4/context_image.py:

| Kind | Meaning |
|---|---|
| NONE | raw zero, always available |
| ACC | committed wide ACC rounded once to S, using committed ACC mode; out-of-S-range is ACC_RANGE |
| RF | RF[idx], requires valid bit |
| MATRIX | req_mat raw bits, requires req_mat_valid; caller supplies C sign-extension for S*C |
| VECTOR | req_vec raw bits, requires req_vec_valid; feeder aligns D into S beforehand |
| IMMEDIATE | signed 16-bit raw immediate sign-extended to S; no implicit multiplication by 2^S_F |
| LINK | req_links[idx*27 +: 27], idx N/E/S/W=0/1/2/3; requires real edge and valid link |
| PREDICATE | raw 0/1 from local predicate idx 0..2 |

The standalone router carries 64-bit raw containers. The later ingress capture
must supply exact S-bit link payloads here without silently truncating a wide
ACC partial. Wide partials use req_wide and req_wide_valid for ACC_ADD instead.
No wide-to-S conversion is inferred at the tile boundary.

Read only operands used by the micro-op. MOV/ABS/NOT use A; binary arithmetic,
comparison, SELECT and Boolean ops use A+B; MUL/MAC use A+B; ACC_ADD uses only
wide; HOLD/ACC_CLEAR/ACC_READ use neither A nor B. SELECT validates both A and B.
Unused fields are not read or validated. False guard/tail suppresses all local
execution checks, but the future loader must still validate the entire image.

Fault priority for enabled requests: invalid local predicate write destination
or source, source A, source B, missing wide operand, then ALU opcode/mode/numeric
fault. Additional codes: SOURCE=6 (enum/missing matrix/vector/wide), UNINIT=7,
PRED=8, LINK=9, ACC_RANGE=10. Existing ALU codes 0..5 retain their meaning.
An ingress fault is transported through an inert ALU request, so it cannot
execute MAC/CLEAR or corrupt ACC. rsp_exec still echoes lane && guard; rsp_data
is zero and rsp_acc shows unchanged committed ACC for ingress faults.

## Schedule and correctness

No extra pipeline stage: valid single operation or ingress fault accepted at E
produces response during E..E+1, earliest retirement E+1, minimum II=2.
Valid enabled S*S MUL/MAC: response during E+1..E+2, earliest retirement E+2,
minimum II=3. Snapshot RF operands/guard/SELECT at acceptance; live ingress
changes cannot alter a two-cycle product or a stalled response.

The permanent verification/v4/pe/tb_pe_tile.sv observes RF data/validity,
predicates and ACC before/after every edge. Compare against V4 integer arithmetic
and a transactional state model. Cover all RF indices, source kinds, guards,
predicate updates, read-after-write, uninitialized reads, source errors, local
edge errors, signed immediate/ACC rounding, MAC and rollback, simultaneous
RF/predicate/ACC commits, stalls, tails and reset/cancel during either multiply
phase. Exercise all 32 TILE_ID values and retain vectors on request.

Not qualified here: packed context decode, program scheduling, routing/ALU
atomic issue across an array, feeder, two arrays, LSQR or timing/area. The
analytical II=1 GEMV formulas are not measurements of this decoded tile.
No synthesis/implementation is run in this slice.
