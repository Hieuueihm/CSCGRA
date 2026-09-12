# Resident context execution — candidate revision 1

This bounded backend connects actual Control256 PC execution, an idle-loaded
descriptor table, resident operand memories, and exactly 32 PEs. Its output is
a held **candidate result stream**, not vector scatter writeback, job commit,
support construction, scalar service or LSQR. The tile64/control256 ABI and
numeric arithmetic are unchanged. The old demonstration GEMV templates remain
unqualified; `compiler/v4/resident_program.py` generates separate executable
images through the existing compiler and verified stream exporter.

## Composition

`resident_engine` owns `context_engine`, `operator_controller` and
`resident_operands`. The controller owns `frame_fabric`, which instantiates
exactly two existing `pe_array` blocks. The resident path owns one existing
`operand_reader`, with its one feeder, vector store, B cache, and live Phi
generator/cache plus `phi_reader`. It does not instantiate `cgra_fabric` or
another feeder. The original raw-bundle fabric interface is preserved.

All blocks use clk and synchronous active-high rst/cancel. `read_allow[0:3]`
are matrix request, vector request, matrix response, vector response arbitration
grants. Grants may vary arbitrarily; both sides of each handshake see the same
grant. `link_ready` and candidate `result_ready` provide independent backpressure.
No bandwidth, RAM inference, synthesis or timing qualification is claimed.

## Descriptor publication and ownership

`config/v4_operator_exec.json` generates `operator_defs.vh`. Sixteen independent
descriptor slots each hold mode2, transpose1, rows8, cols11, vector base12,
plane2, scale18, key128, matrix generation32, vector generation32, job16 and
format8. Packing is low-bit-first in the JSON field order. The idle cfg handshake
requires revision1 and validates geometry, mode/direction, Phi positive signed
scale and legal plane. A bad write invalidates its slot and sets cfg_fault.
Descriptor revision is distinct from the unchanged tile/control revisions.

Loader/config commands have priority over START, even when both requests remain
valid. The integrated top blocks START during any resident fill and prevents
descriptor or resident begin acceptance while a run owns the backend. Descriptor
data and published memories are immutable throughout that run. Phi and B fill
geometry is captured on accepted begin; a reader shape mismatch faults before
source reads. A key does not authorize reinterpretation under another shape.
The Phi owner captures job/format; the cache captures key/generation. `phi_reader`
validates that identity and snapshots the accepted response envelope. It checks
the cache's returned generation/tag/mask instead of copying live request tags.
B/vector stores perform their published identity/range checks.

## Exact ADDRESS subset and counters

Only ADDRESS mode MATRIX (1) is accepted. immediate_address24 is a descriptor
slot index 0..15, with bits23:4 zero. It is not a byte address. VECTOR, RESULT,
SCRATCH and all other address modes are rejected by this candidate backend.

The signed stride16 must encode **+1**. Zero, negative values, and every other
positive stride are rejected before reading or executing the ADDRESS row.
There is no wrap, arbitrary seek, or implicit reset at LOOP_BEGIN. Each descriptor
owns registered output/reduction/step counters reset to zero at START. After
successful retirement of an ADDRESS row:

- R1 increments reduction by1; at reductions it resets reduction to0 and advances
  output by32.
- R4 increments step0..7; step7 resets to0 and advances the reduction base by32.
  At the reduction bound the base resets to0 and output advances by8.

Transpose selects outputs=cols, reductions=rows; forward selects outputs=rows,
reductions=cols. Phi modes enforce R1 forward/R4 transpose; B allows both modes
in both directions. Exhausted output counters reject the next ADDRESS, without
wrapping. No variable divider exists in this address progression. R4 all-tail
steps are legal and retain the reader's zero-mask/no-source-request behavior.
An ADDRESS success acknowledges the fully joined, checked frame; the same
job/tag/format ISSUE then executes that ADDRESS row once. A failed source never
issues its tile words. Only successful PE/PC retirement advances counters.

Non-ADDRESS rows issue no external operands and enable all tile slots. They
implement CLEAR, loops, routes, full-width accumulator reduction and STORE using
the existing context contract. The most recently accepted ADDRESS identifies
output indices: R1 tile t maps to out+t; R4 tile4g maps to out+g. R4 STORE output
is restricted to group leaders (tile%4==0); the compiler reduces all four lanes
with full-width ACC routes/ACC_ADD before storing. Tail output lanes are masked.
A STORE before any ADDRESS returns a backend fault, never a candidate write.

The executable GEMV generator uses nested PC loops: outer CLEAR per output
block, inner ADDRESS/MAC iterations, optional R4 route reduction, STORE, outer
loop end and HALT. Image size is7 rows for R1 and12 for R4 regardless of N.
Both inner and outer loop headers follow the existing replay-header semantics.
No testbench per-PC operand schedule or alternate numerical computation exists.

## Candidate retirement and lifecycle

Result payload includes32 S27 words, per-tile output index11, valid/store mask32,
job/tag/format and last. `last` echoes **the retiring control row's exec_last**;
it is not a job-end marker. A STORE followed by a distinct HALT has last=0.
Use the held done response to observe successful program termination. No
candidate data from a failed run is a committed job result.

On a successful STORE row, result acceptance, both PE-array retirements, and
sequencer response acceptance occur on the same clock edge. With result_ready=0
the payload and owned PE/PC state hold. If sequencer response eligibility is
blocked, result_valid is suppressed so a sink cannot accept duplicates or accept
an identity-rejected completion. Error completion is reported independently of
result_ready and does not assert result_valid. Non-store rows retire without a
candidate handshake. Results outside result_mask are not meaningful.

START pulses the existing execution epoch reset: controller counters/output
metadata and PE state clear, while descriptors and published resident RAM remain
valid. This supports restarts with the same job/format identity; cross-job cache
reauthorization or baseline cache reuse is not implemented. No producer flush is necessary on normal START: the single-outstanding
sequencer cannot finish while a reader transaction remains; reader errors drain
both sources before ADDRESS failure, and successful frames are consumed before
execution begins. Backend failures occur after read ownership is empty. Hard
rst/cancel resets reader and all producers together, invalidates descriptors,
context image and resident publication, and requires reload. RAM payload itself
is not reset. There is no retained committed-job guarantee.

## Verification

Permanent bench: `verification/v4/control/tb_resident_engine.sv`; Python tests:
`verification/v4/test_resident_rtl.py`. The bench loads all8448 records exported
after host hash/structure verification, generates Phi with live LFSR RTL, fills
B/vector stores, and starts actual RTL PC execution. It records accepted candidate
frames; Python checks independent coordinate/integer GEMV sums and final rounding.
R4 reductions occur in the PE mesh, not Python. The test oracle only checks them.

Coverage includes both Phi directions, all B R1/R4 directions, tiny/all-tail and
maximum dimensions, source/result stalls, forced completion blocking, duplicate
write detection, held START/load/config arbitration, bad identity/geometry/range,
unsupported modes/strides, hard reset/cancel while responses are unjoined, and
two runs from the same preloaded memories and descriptors. RTL validation uses Vivado xvlog/xelab/xsim only; Python remains the integer
oracle. Focused runner:
`py -3 scripts/v4/run_resident_rtl.py`. Full existing gates remain separately
required. No synthesis/implementation is run.
