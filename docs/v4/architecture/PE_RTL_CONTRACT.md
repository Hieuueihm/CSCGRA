# Retirement extension

pe_alu now accepts rsp_drop on response retirement; drop discards a pending ACC
write while retaining earlier committed state. Tie low for standalone execution.
See [array contract](ARRAY_RTL_CONTRACT.md).

# PE arithmetic and router: local contract v1

This primitive slice of the [V4 baseline](BASELINE.md) defines reusable
`pe_alu` and the catalogued `mesh_router`. The subsequent
[decoded tile](TILE_RTL_CONTRACT.md) adds RF8/predicates/operand selection.
This primitive contract does not define packed context decode,
the arrays or an LSQR program. The candidate 64-bit image in [CONTEXT.md](CONTEXT.md)
is unchanged; local decoded micro-op numbers are not binary tile opcodes.

## Build definitions and hierarchy

`config/v4_pe_interface.json` selects a non-production build candidate:
S27F22, C18F16, ACC64, matching the current numerical shortlist. These are not
permanent application qualification or runtime-switchable Q-formats. The
definition generator imports route selector values from the V4 context packer
and common tag widths from the Phi interface; no private opcode constants.

    future pe_array
      pe_tile (RF8/operand and predicate selection; see decoded tile contract)
        pe_alu
      mesh_router (one per tile, 32 total)

Use `py -3 scripts/v4/generate_pe_interface.py --check` to detect drift.
Names such as req/rsp, acc, prod, lo/hi and pending describe local ownership.
The target remains a 4x4 mesh per array; there is no inter-array neighbor edge.

## Shared transaction rules

Single clk, synchronous active-high rst, synchronous cancel with reset-like
local clearing. Ready/valid are suppressed during rst/cancel. Transfers happen
only at rising-edge valid && ready. One request outstanding, no same-edge
replacement on response retirement. Payload, tags and owned state hold under
response stall. All sources/tags are snapshotted; changing live inputs while
busy cannot alter an accepted request. rst/cancel overrides retirement.

Every request carries req_lane (tail validity), req_exec (predicate enable),
req_job[15:0], req_tag[15:0], req_fmt[7:0], req_last. rsp echoes all metadata;
rsp_exec reports req_lane && req_exec. Disabled requests retire as no-ops with
zero data/no fault and unchanged accumulator, even if inactive operands are
out of range. Masked opcodes are not validated by this execution primitive;
the future context loader must still validate the whole image structurally.
req_fmt is opaque scheduling metadata, not a runtime numerical profile switch.

## pe_alu ports and numerical semantics

Inputs: clk/rst/cancel, req_valid/req_op[4:0]/req_mode,
req_a[26:0], req_b[26:0], req_acc[63:0], req_sel,
common metadata, rsp_ready. Outputs: req_ready, rsp_valid,
rsp_data[26:0], rsp_acc[63:0], rsp_cmp[2:0], rsp_fault[3:0],
rsp_job/tag/fmt/last/lane/exec.
Read-only state_acc[63:0] and state_mode expose committed ACC to the tile operand
mux; they never expose an unretired candidate and do not add storage.

req_a/b are raw S-width bit patterns. mode=0 means S*C: b must be an exactly
sign-extended C18 integer for MUL/MAC. mode=1 means S*S. Raw values retain
their named fractional grids, and products are never prematurely narrowed.
One signed 27x18 multiplier is shared. S*S uses two accepted internal cycles:
b = unsigned low17 + signed high10 * 2^17, with a 45-bit low product and exact
wide merge before rounding/accumulation. No 27x27 multiplier is instantiated.
This is RTL structure, NOT a verified DSP count or timing claim.

| Local micro-op | Result and side effect |
|---|---|
| HOLD | zero data, unchanged ACC |
| MOV, SELECT | a, or (req_sel ? a : b), exact raw bits |
| ADD, SUB | signed S arithmetic; saturating diagnostic on overflow |
| ABS | unsigned magnitude in S bits, including abs(MIN)=2^26; no signed clipping |
| CMP_S, CMP_U | signed/unsigned raw compare; data=less; cmp bits 0/1/2 = less/equal/greater |
| AND, OR, XOR, NOT | bitwise operations across S bits; Boolean AND/OR/XOR use 0/1, logical NOT uses XOR with 1 |
| MUL | exact product, round once to S using C_F or S_F, saturate/fault if needed |
| MAC | exact product added to ACC, prefix overflow checked in 65 bits; data=0 |
| ACC_CLEAR | candidate zero ACC and selected mode |
| ACC_ADD | add req_acc (raw wide neighbor partial) to ACC, same mode, prefix checked |
| ACC_READ | round ACC once to S using its selected product mode |

Rounding is halfway away from zero, exactly `Arithmetic.round_shift` in the
V4 integer model. ACC has S_F+C_F or 2*S_F fractional bits. Reset/cancel clear
ACC and set mode=0. ACC_CLEAR explicitly selects mode. MAC, ACC_ADD and
ACC_READ with a different mode return MODE; they must not mix scales.

Fault priority on an enabled request: unknown OP, ACC mode mismatch, invalid
C sign-extension, then numerical fault. Codes: NONE=0, SAT=1 (S narrowing),
ACC=2 (wide prefix overflow), OP=3, MODE=4, COEFF=5. rsp_acc is the diagnostic
candidate (clipped on wide overflow); rsp_data is clipped on SAT. No faulted
request modifies persistent ACC. There is no hidden saturation-as-success.

Persistent ACC/mode commit ONLY when a successful response retires. During a
stalled response they remain unchanged; a pending update cannot leak through
reset/cancel. No new request can observe an unretired candidate. This local
retirement is not the outer x/support/residual commit controller.

## Exact schedule (before stalls)

If req is accepted at edge E, a single-cycle operation produces a registered
response during E..E+1, earliest response acceptance E+1. Minimum issue II=2.
Enabled valid S*S MUL/MAC takes a low-product issue at E and high-product merge
at E+1; response earliest acceptance E+2, minimum II=3. The internal second
cycle uses only captured fields, regardless of req_valid or response ready.
Bad/masked requests return a one-cycle response without executing multiplication.
The JSON schedule is executable-test input. Historical R1/R4 II=1 cost formulas
remain analytical reference and are NOT a cycle claim for these primitives.

## mesh_router ports and schedule

Parameter TILE_ID=0..31 determines legal N/E/S/W edges using local TILE_ID%16.
Inputs: clk/rst/cancel, req_valid, req_routes[11:0] (3 bits/direction, N lowest),
req_val/req_acc/req_res[63:0], req_src[2:0], common metadata,
out_ready[3:0], rsp_ready. Outputs: req_ready; out_valid[3:0],
out_data[255:0] (64 bits/direction, N lowest), out_sel[11:0],
out_job/tag/fmt/last; rsp_valid/fault/job/tag/fmt/last/lane/exec.

Route selectors are the existing V4 values NONE/VALUE/ACC/RESULT. req_src bits
0/1/2 indicate availability of these three data sources. Data are raw 64-bit
containers; scalar source preparation sign-extends S as needed, while ACC
retains full precision. No arithmetic or narrowing occurs in the router.
NONE produces no transfer and zero data/selector. All-NONE is a legal no-op
sideband; a context ROUTE instruction's nonempty requirement belongs to decode.

Validate ALL requested edges/selectors/sources before emitting any link. Faults
SEL=1, EDGE=2, SRC=3 have this priority; all outgoing transfers are suppressed
on any fault. Disabled lane/predicate requests similarly send nothing but
return success. Different requested directions may choose different sources.

Request at E registers links, which may transfer at E+1: one-cycle neighbor
hop. Each selected direction holds data/tag until its OWN ready; a consumed
direction is cleared and must not send duplicates while another stalls.
Completion becomes valid only once all selected links are accepted. With no
stalls: link acceptance E+1, completion acceptance E+2, minimum issue II=3.
No-op/fault has no links and earliest completion E+1. Completion can stall.
Cancel cannot undo links accepted on earlier edges: integration must cancel
all affected consumers/job tags together, not reuse a partially cancelled job.

## Verification and open work

Real RTL tests use fixed-point integer operations, boundary/random operands,
positive/negative half ties, split products, repeated/prefix-overflow MAC,
mode faults and post-fault rollback. Test response stalls, live-input mutation,
reset/cancel during both multiplier phases, pending ACC commits, tails and
predication. Router tests cover all 32 tile IDs, missing edges, malformed
selectors, missing sources, independent ready, exactly-once delivery and tags.
Keep a checked-in SV testbench in verification/v4/pe; vectors/logs belong in work.

The decoded tile now integrates RF8 and operands/predicates with arithmetic.
Array-level arithmetic/router issue remains for the feeder/two-array stage,
then context execution and support/B cache/scalar DIV-SQRT/LSQR.
Do not infer packed context execution from decoded tile tests.
No synthesis or implementation is run in this slice.
