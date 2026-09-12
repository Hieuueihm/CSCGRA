# Psi=I support builder — candidate RTL contract

`support_builder` owns one full ordered-support rebuild of dense B from the
existing live Phi sign cache. It uses no PE transform, algorithm PC, duplicate
transpose cache, scalar service or LSQR. C18F16 remains the selected build
candidate; this does not qualify a production numerical profile.

## Request and ownership

One request captures rows1..128, original Phi columns1..1024, support count1..96,
96 packed10-bit indices (slot0 low), positive signed C18 raw scale1..131071,
Phi key128/generation32, B key128/generation32 and completion job16/tag16/fmt8.
Inactive support slots are ignored. The request has a single handshake; it is
not an unbounded support stream. Validation visits one active support slot per
cycle using a1024-bit duplicate bitmap. Duplicate or out-of-range columns fail
before any Phi read or B begin. The caller assigns B key to the complete ordered
support/operator/scale identity; hardware does not calculate or authenticate it.

The caller must arbitrate exclusive ownership of Phi reads and B begin/fill/read
from request acceptance through completion retirement. In particular, it must
not submit an unrelated Phi response or start another Phi fill while building.
`req_ready` requires no preexisting Phi response. Phi cache does not export its
shape, job or format. `phi_rows/phi_cols` MUST be supplied by the same owner that
captured the successful cache fill descriptor, bound to `phi_key/generation`.
They are not independently authenticated by the RAM. The owner must authorize
that descriptor for the requesting job/format before request submission.
Do not manufacture these fields from changing builder request pins.

On acceptance `b_cancel` explicitly invalidates any old B and discards B's pending
read/fill state. Even an invalid rebuild request leaves the previous B invalid.
This is full rebuild semantics, not retained-old-B rollback or outer job commit.
Upstream arbitration must therefore drain users before accepting the rebuild.

## Gather and fill

After prevalidation the builder handshakes B begin and verifies loading/no fault.
It gathers one Phi bank word at a time in support-slot-major, row-block-major
order: bank=column%8, address=(column/8)*ceil(rows/32)+block. The accepted request
uses the captured generation and a16-bit word ordinal starting at0 as read tag.
There is exactly one outstanding Phi read, and at most384 reads per rebuild;
no tag wrap is possible in a transaction.

The response must echo exactly the selected bank mask, generation and ordinal;
its source fault must be zero. The complete256-bit masks must match the expected
single-bank tail mask, and all signs outside that mask must be zero. A response
is consumed before its words are used. Only active row bits expand to signed
C18F16 `+scale` for1 and `-scale` for0; padding coefficients remain zero. No
padding sign is consumed and no rounding occurs. B fill carries captured shape,
slot/block, exact mask and final-word flag into the existing diagonal-bank RAM.
The RAM alone publishes after its validated final fill. Builder checks publication
and load status on the next edge before asserting successful completion.
Upstream B readers remain excluded until successful completion retirement.

Combinational valid/ready are suppressed on rst/cancel. Phi requests, B begin,
B fill and the final response hold their owned payload under backpressure.
Live request mutation cannot change accepted work. No same-edge replacement.

## Failure and cancellation

Faults are generated from `config/v4_builder_exec.json`: SHAPE1 (shape/count or
nonpositive scale), SUPPORT2, PHI_KEY3, SOURCE4 and B5. Shape validation has
priority at the first CHECK cycle, then live Phi identity, then support index.
Any change/loss of bound Phi publication/key/generation/shape during a build
aborts. A rejected Phi response has already been drained. If identity changes
with an outstanding read, the ABORT state asserts `phi_invalidate` for one edge
and explicitly flushes the attached cache's pending response/publication; wire
this to the same Phi owner cancellation domain, including its generator.
No stale outstanding response is reused by a subsequent build.

Every failure passes through ABORT, asserting B cancel for an edge, before held
completion becomes valid. Therefore partial B is invalid and B is not stuck
loading on completion. Load faults and unexpected loading/publication state are
propagated as B. There is no timeout if a producer or consumer stops handshaking.

Synchronous rst clears builder and B; all attached modules must share rst.
Synchronous cancel clears builder/B and asserts Phi invalidation; its owning
producer domain must flush together. Neither cancel nor reset emits a completion.
Previously committed B is deliberately invalidated. Request and response job/tag/
format refer to the builder transaction; Phi read tags are independent ordinals.

## Schedule and evidence

`rsp_words` counts accepted B fill attempts (including a word rejected by B);
`rsp_cycles` counts edges after accepted request through entry into DONE, excluding
completion stalls. Counters and completion identity hold while rsp_valid stalls.
Without stalls, success takes `support_count + 2 + 4*word_count` edges, where
word_count=support_count*ceil(rows/32). M128/S96 therefore takes1634 edges plus
any read/fill/begin stalls; cold Phi fill is separate and is counted by the TB.
No throughput at100MHz, BRAM inference or FPGA timing claim is made.

Permanent `verification/v4/memory/tb_support_builder.sv` connects real LFSR
generator, Phi RAM, builder and B RAM. Python generates expectations with the
independent indexed LFSR integer oracle, then reads every coordinate in both
row-major and transpose traversal through the same diagonal B layout. Coverage
includes M1/7/33/65/128, N1024, support96, ordered permutations, seed zero, both
coefficient signs including scale extrema, independently gated channels,
request mutation, response stalls, malformed support/shape/scale, key/generation/
shape mismatch, corrupt response tag/mask/bank/source, B partial-fill rejection,
reset/cancel across phases and completion, and pending-read identity-loss cleanup.

Run `py -3 scripts/v4/run_support_builder_rtl.py` for the bounded RTL replay,
definition drift check, strict lint and source-hash evidence. The root V4 full
regression remains a separate integration gate. No control-memory, transform,
application, synthesis or implementation qualification follows from this slice.
