# Phi generator and cache transport contract

Current cache transport revision is `phi_stream_cache_v2_elastic`. Generator
family/revision, sign order, layout and numeric interpretation are unchanged.
The archived v1 cache forbids consume/refill at the same edge; v2 permits it.
The native owner integrates these leaves through a two-credit `phi_reader`;
see [operator pipeline](OPERATOR_PIPELINE.md). This does not freeze production
numeric precision or change packed program/context fields.

## Shared definitions

`config/v4_phi_interface.json` selects the local interface. Run
`py -3 scripts/v4/generate_phi_interface.py` to generate
`rtl/v4/include/phi_interface.vh` from it and `config/v4_design.json`.
`--check` detects definition drift. Sign bit 1 means +1, 0 means -1;
quantized scale belongs to the later feeder/support builder, not sign RAM.

Limits: rows 1..128 (8 bits), columns 1..1024 (11 bits). Words have 32 signs;
eight banks each have 512 words. Column index is 10 bits, row-block index 2
bits, bank address 9 bits. Local family=1/revision=2 identifies selected LFSR.
Job/op/format tags are 16/16/8 bits, generation 32 bits, read tag 16 bits.
Cache key is an opaque 128-bit identity assigned by the later controller to
the full locked descriptor, not a truncated hash assumed collision-free.

One `clk`, synchronous active-high `rst`. Transfers occur at rising edge on
valid && ready. All payload/tags/owned state hold under stall. Priority is
reset, explicit cancel, ordinary operation. Ready is low during reset/cancel.
Reset/cancel can discard stalled work; it must never reappear. Commands offered
while busy must be held and are not faults. No RAM array reset or clearing.
Generator out_valid and cache rsp_valid are suppressed during reset/cancel,
so an otherwise-ready consumer cannot accept a cancelled response at that edge.

Sticky fault codes: NONE=0, DESCRIPTOR=1, FILL=2, READ=3. Clear on reset/cancel
or accepted new start/begin. `done` and `published` are one-cycle pulses.

## Generator interface and schedule

Inputs: clk/rst/cancel, start_valid, start_family[7:0], start_revision[7:0],
start_seed[31:0], start_rows[7:0], start_columns[10:0], start_job_tag[15:0],
start_op_tag[15:0], start_format_tag[7:0], start_generation[31:0], out_ready.
Outputs: start_ready, busy, out_valid, out_signs[31:0], out_mask[31:0],
out_column[9:0], out_row_block[1:0], out_job_tag[15:0], out_op_tag[15:0],
out_format_tag[7:0], out_generation[31:0], out_last, done, fault_code[3:0].

Idle accepts a descriptor. Reject bad family/revision/shape with DESCRIPTOR,
no payload/done, remaining idle. Seed zero substitutes DEADBEEF. Galois
right-shift taps 80200003: emit current LSB then step. Stream index is
column*rows+row, lane 0 earliest. Tail high signs/mask are zero; padding does
NOT consume state before the next column. Last marks only the final matrix
word. Every word carries snapshotted tags; live input changes cannot affect it.

Start accepted at edge E produces first valid word during E..E+1, earliest
transfer E+1. Unstalled output sustains one word per cycle, including column
boundaries. LFSR/coordinate advance only on accepted output. Final acceptance
drops busy and pulses done. No same-edge replacement start. Abort cancels
without done/fault. Full M128/N1024 is 4096 payload transfers; this is an RTL
schedule, not a measured 100 MHz timing/throughput claim.

## Cache interface and schedule

Inputs: clk/rst/invalidate; begin_valid, begin_rows[7:0], begin_columns[10:0],
begin_job_tag[15:0], begin_op_tag[15:0], begin_format_tag[7:0],
begin_generation[31:0], begin_key[127:0]; fill_valid, fill_signs[31:0],
fill_mask[31:0], fill_column[9:0], fill_row_block[1:0], fill_job_tag[15:0],
fill_op_tag[15:0], fill_format_tag[7:0], fill_generation[31:0], fill_last;
rd_valid, rd_bank_mask[7:0], rd_addresses[71:0], rd_generation[31:0],
rd_tag[15:0], rsp_ready.
Outputs: begin_ready, filling, fill_ready, cache_valid, published,
cache_key[127:0], cache_generation[31:0], fault_code[3:0], rd_ready, rsp_valid,
rsp_signs[255:0], rsp_masks[255:0], rsp_bank_mask[7:0], rsp_generation[31:0],
rsp_tag[15:0], rsp_fault[3:0].

Begin accepts only when not filling and no response is pending; it invalidates
old publication and snapshots shape/tags/key. Bad shape raises DESCRIPTOR.
Begin takes priority over reads: rd_ready is low whenever begin_valid is high.
The caller starts generator/cache atomically only when both ready; the later
controller must cancel both if either faults. No production wrapper stub is
claimed by this slice.

Fill accepts only while filling. Validate exact column/row-block order, all
four tags, exact mask, zero padding signs and exact last. Duplicates, missing
or early last, wrong tags/coordinates/masks/padding raise FILL, stop fill and
leave cache invalid. Never write the rejected word. No timeout is inferred
when a producer stops providing data. Layout:

    bank = column % 8
    address = (column / 8) * ceil(rows / 32) + row_block

Only the accepted, validated final word publishes atomically: cache_valid=1,
published pulse, filling=0. There is no host publish path to expose partial RAM.

Reads accept only for a published cache when the response register is empty
or its old response is being accepted. One response credit with same-edge
consume/refill permits isolated read II=1 under no stall. A held response
blocks replacement; filling and begin still exclude reads. At most one address/bank,
bank 0 in low packed bits (address bank*9, output bank*32). Require nonzero
bank mask, matching generation, and every selected address to map to an actual
column/row block of this shape, including holes in the last column group.

Request accepted at E produces registered response during E..E+1 (one
synchronous RAM read), earliest response acceptance E+1. Hold until ready.
Unselected banks return zero; selected banks return data plus tail mask.
Invalid request returns READ and zero signs/masks, echoes requested bank mask,
generation/tag, and sets sticky READ. Suppress RAM reads for invalid requests.
Published cache remains intact for retry. A subsequent successful response
has rsp_fault=NONE even if sticky status holds READ. Reads before publish stall.

Invalidate/reset clear publication, fill, pending response and sticky fault;
RAM contents remain unspecified/inaccessible until full rebuild. Key/generation
are meaningful only while cache_valid. Generation reuse/wrap requires draining
old requesters; the later controller owns full descriptor identity and reuse.

## Correctness gates and subsequent work

Compare each valid sign with independent indexed integer oracle
`models/v4/lfsr_operator.py:indexed_sign`; reconstruct cache words/layout from
that oracle. Never adjust numerical goldens to match RTL. Cover seed zero,
max shape, row/column tails, random stalls, held state/payload/tags, reset and
abort/invalidate mid-flight, refill, descriptor errors, every corrupt fill
field, read holes/generation errors, publication and simultaneous priorities.
Record simulator, commands, results and source SHA256. Model tests are not RTL
tests. No synth/impl until required correctness gates pass.

Next: lock PE arithmetic/router latency, rounding/overflow and integer replay;
then feeder and two arrays; then context, support builder/dense B cache, shared
DIV/SQRT and LSQR with stored-X certificate and commit/rollback. Each requires
its own executable schedule/contract; sign-only success cannot qualify them.
