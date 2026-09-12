# Control256/image execution candidate v1

This implements idle image loading, synchronous context storage and a single
global PC sequencer. It does not implement host DMA/SHA hardware, the memory
scheduler/joiner, vector/B stores, support builder, scalar service or LSQR.
The external execution port can connect to cgra_fabric. Its operand provider
and result capture still belong to a backend adapter, not hidden TB magic.

## Binary compatibility and trusted loader boundary

CONTROL_FIELDS is the shared tuple used by the unchanged compiler pack/unpack
and generated control_defs.vh. There is no ISA layout/enum/revision change.
The full image remains256 rows of32 tile64 words and one control256 word.
Before asserting begin_verified, the trusted host must call load_image to
validate manifest revision/geometry, SHA256 of every file, and structural
tile/control validity. The RTL flag is an attestation, not a SHA implementation
or protection against a malicious host. Transport integrity beyond the RTL
stream checks belongs to the host/AXI boundary.

The loader consumes row-major records: for PC0..255, banks0..31 are tile
words in low64 bits with high192 zero; bank32 is control256. Both are numerical
little-endian decoded words, not the literal numeric interpretation of a .hex
line. Final last is permitted only on PC255/bank32. Exact ordering rejects
missing, duplicate, premature-last and out-of-range records. A begin handshake
invalidates the old image, including on an invalid header. Only all8448 correct
records publish the new generation. No partial image can execute. Header
checks revision1, depth256 and verified=1. Loading occurs only while idle.

context_store owns32 separate64-bit banks and a256-bit control bank, with no
reset of RAM payload. Reset/invalidate clears only response ownership. Reads
take1 cycle and hold under stall; no same-edge replacement. Unpublished or
generation-mismatched reads return FETCH with zero data. Physical BRAM and
timing are not claimed. Loader/store/sequencer resets and invalidations must
be wired together; context_engine supplies this composition and load/start
arbitration. A held begin request has priority over start, preventing races.

## Executable control subset

Each successfully fetched row executes its32 tile slots exactly once, including
NOP, loop, WAIT, ADDRESS and HALT control rows. Control effects commit only
after a successful tagged execution response. A rejected control row never
issues tile slots. flags/repeat/immediate must be zero. Fields irrelevant to
the selected kind must also be zero. Unsupported proposals return EXEC;
unknown enum/reserved/zero LOOP_BEGIN count return WORD. REV has first priority.

- NOP: next PC.
- LOOP_BEGIN: count1..65535, loop_target=PC+1. Push begin-PC and remaining count
  unless revisiting the current top loop header. Revisited headers execute
  their tile slots again but do not reset the loop count. At most4 nested loops.
- LOOP_END: loop_target must equal top begin-PC. If remaining>1, decrement
  and revisit that header; otherwise pop and continue. Unmatched/overflow
  stack faults before issuing tiles. This explicitly supports re-executing
  CLEAR at an outer loop header; it is not a generic jump past initialization.
- BRANCH: predicate0 always,1..3=P0..P2,4..6=inverse,7 never. Snapshot the
  external scalar predicate inputs at decode; branch_target when true,
  otherwise PC+1. Branching with a nonempty loop stack is rejected in v1.
- WAIT: wait until the same predicate function becomes true, then issue once.
  These are external scalar predicates, not an implicit reduction of PE flags.
- ADDRESS: tagged descriptor request mode MATRIX/VECTOR/RESULT/SCRATCH,
  immediate_address24 and signed raw stride16. Wait for matching job/tag
  completion before issuing tiles. The backend owns descriptor meaning,
  address arithmetic/overflow and memory transactions; this block does not
  pretend one descriptor encodes all simultaneous operand streams.
- HALT: execute its row, then return held done. HALT with an open loop faults.

The existing demonstration GEMV templates combine address fields on LOOP_BEGIN
and use an unresolved R4 address/tail convention. Those templates remain
unsupported rather than being silently reinterpreted. New bounded scalar/route
images in verification prove control execution; they do not qualify full GEMV
images, memory scheduling or LSQR.

## Lifecycle, timing, failures and tags

context_engine arbitrates load/start. Start snapshots PC, job, format,
published generation and a nonzero retired-instruction limit, and starts a
fresh backend epoch via exec_cancel. PC, loop stack and retired count advance
only after response handshake. exec_tag starts0 and increments once per
retired row. Tag wrap is rejected before issuing a reused tag; at most65536
rows per run in this candidate. PC255 can HALT/branch/loop-back, never wrap
silently. The instruction limit is a retired-row budget, not a wall-clock
timeout: WAIT or an unavailable backend may stall indefinitely until cancel.

Fetch response PC/generation, address completion job/tag, and execution
completion job/tag/format are validated. A bad execution completion is NOT
accepted: the sequencer latches failure and asserts exec_cancel in DONE on
the following cycle. This avoids combinational valid/cancel feedback when
connected to the fabric. Failure/cancel clears the backend epoch; results from
earlier retired rows are not a committed job result. System commit_controller
must still own final publication. Successful HALT leaves PE state observable
until the next start/cancel. done holds until accepted; no same-edge restart.

Base schedule: start -> fetch request -> synchronous response -> validate ->
issue -> wait for backend -> fetch next row or held done. WAIT and ADDRESS add
explicit phases. Inputs and output metadata hold while their valid is stalled.
Reset/cancel suppress transactions and discard loader/fetch/run state; cancel
invalidates the image and requires reload. No synthesis or implementation.
