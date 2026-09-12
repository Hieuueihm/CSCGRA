# Transactional stored-X result publication

`commit_controller` validates one candidate job and publishes through its child
`result_writeback`. The latter owns two banks of 96 raw X24F20 coefficients,
ordered support indices and metadata. It has a private trusted start/write/publish
interface; external callers use the controller. There is no vector-workspace
writeback or numerical certificate computation inside these modules.

Definitions come from `config/v4_commit_interface.json` through
`scripts/v4/generate_commit_interface.py` and `commit_interface.vh`. Only the
current S27F22/X24F20 candidate is supported. Changing that geometry requires
explicit generator/datapath review; this is not a production numeric freeze.

## External request and status

All signals use rising `clk`, synchronous active-high `rst` and `cancel`.
Each request is accepted only on valid/ready. Tags are job16, operation tag16,
format8; the sole supported format id is 1.

`begin_valid/ready` snapshots `begin_rows` (8 bits, M=1..128), `begin_count`
(7 bits, 0..96), packed `begin_support` (96 little-lane-first 10-bit indices),
job/tag/fmt and signed7 `begin_exponent` (-31..31). Support order is preserved;
indices must be unique in active slots and unused packed slots must be zero.
Indices are operator columns in 0..1023, not measurement rows; no index<rows
constraint is imposed. Count zero is an empty complete candidate and still
requires a successful explicit decision. No fill is legal for count zero.

`fill_valid/ready` accepts `fill_block` (2 bits), `fill_mask` (32), packed
`fill_data` (32 signed27 values), `fill_last` and fill job/tag/fmt. Blocks must
arrive exactly 0,1,2 as needed. The mask must contain exactly all remaining
active lanes in that block; every inactive lane's data must be zero. Last must
match the exact final block. No holes, extra blocks or identity changes are
accepted. Values must already be stored-X values embedded in S: low two bits
zero and signed raw S in [-33554432,33554428]. The leaf extracts bits25:2 as
signed24. It never rounds or clips a value at publication: the certificate
must have checked this same stored-X grid earlier.

`decision_valid/ready` takes `decision_approve` plus decision job/tag/fmt.
Approval is an explicit upstream attestation that the stored-X certificate
succeeded and all preceding numerical/kernel operations were fault-free.
The controller requires a complete candidate and matching identity before it
publishes. A negative approval or early decision discards the candidate and
returns a fault. There is no inferred success from final fill. If decision
valid and fill valid are asserted together, decision has priority and fill
ready is low; an early decision therefore fails instead of consuming a final
fill on the same edge. Producers must obey readiness.

`status_valid/ready` holds `status_fault`, `status_committed` and accepted
job/tag/fmt. Successful decision returns NONE and committed=1; any failure
returns committed=0. A malformed begin returns its supplied identity; later
faults return the snapshotted accepted job identity. No new candidate begins
until the prior status retires; there is no same-edge replacement. Job-failure
status is independent of the previously committed result, which remains readable.

| Fault | Code | Meaning/precedence |
|---|---:|---|
| NONE | 0 | Explicit successful publication |
| MODE | 1 | Begin rows/count/format/exponent invalid |
| SUPPORT | 2 | Duplicate index or nonzero inactive support slot |
| IDENTITY | 3 | Fill/decision tags differ from accepted begin |
| STREAM | 4 | Block/mask/last/padding error, extra fill or incomplete decision |
| NUMERIC | 5 | Active lane not on stored-X grid or outside X range |
| CERTIFICATE | 6 | Complete matching candidate explicitly rejected |
| CANCEL | 7 | Active accepted candidate cancelled |
| READ | 8 | No committed result or read slot outside committed count |

Begin checks MODE before SUPPORT. Fill checks IDENTITY before STREAM (including
padding) before NUMERIC. Decision checks IDENTITY before STREAM before
CERTIFICATE. Every malformed fill is validated in full before any lane writes.

## Atomicity and held reads

Start/fill target the bank opposite the committed pointer. Only a successful
decision changes that pointer. Candidate failure/cancel does not invalidate,
overwrite or change metadata of the committed bank. A later candidate may
reuse the old bank only after the pointer has moved away from it.

`read_valid/ready` queries `read_slot` (7 bits). A valid query snapshots raw X24,
support index10, signed exponent7, job/tag/fmt and fault into a dedicated held
response. Invalid queries return READ and zero data/metadata. The response
is valid immediately after the acceptance edge and retires on a later edge
with `rsp_valid && rsp_ready`; no same-edge replacement is supported.

The response is an actual payload snapshot, not a live bank mux. It remains
unchanged even if a new result publishes and the old bank is reused while
the response is stalled. Read and successful decision on the same edge see
the old committed pointer for that read. `committed_valid/count/rows` describe
the current committed bank and can change independently of an older held read.
These state outputs do not indicate a new job completion by themselves.

After a valid begin, support validation scans all 96 packed slots, one per
cycle, using a 1024-bit seen-index bitmap. Fill and decision remain unready
during this check, including for count zero. A duplicate/tail error stops the
scan and produces SUPPORT status; cancel also stops the scan. This avoids a
96-by-96 combinational comparator network. Private candidate metadata may be
written at begin, but cannot be published before validation succeeds.

Start, fill and decision each take one accepted edge; a decision's status
and pointer publication appear after that edge. A status fault appears after
the offending accepted edge. Committed reads have one registered response
stage, minimum request initiation interval two edges. Fill accepts one block
per edge while ready. These are functional schedules, not timing/resource claims.

Reset takes precedence over everything and clears all validity and response
state, including committed validity; RAM contents need not be reset. Cancel
suppresses all visible ready/valid signals while asserted, discards the active
candidate and flushes the read response. If a candidate was active, CANCEL
status becomes visible after deassertion and is held until retired. Cancel
preserves a pre-existing status if no candidate was active, including a success
already published before cancel. Consequently cancellation after publication
does not roll back committed data or retract a completed status. Repeated
cancel cycles do not produce duplicate statuses.

## Validation

Run `py -3 -m unittest verification.v4.test_commit_rtl -v` for the focused
Vivado xvlog/xelab/xsim suite, or `py -3 scripts/v4/run_rtl.py` after integration
into the full source manifest. `VIVADO_BIN` may select the installed Vivado bin;
the default is C:/Xilinx/Vivado/2018.1/bin. No synthesis/implementation runs.

Permanent bench `verification/v4/commit/tb_commit_controller.sv` uses the
checked-in IO schema; the independent Python list oracle compares every
interface output before/after each edge. Coverage includes zero through maximum
support sizes, random signed coefficients and index order, X extrema/grid/range,
all domain/identity/stream faults, rejected/early decisions, status stalls,
concurrent reads/publication, held reads across two subsequent bank swaps,
and cancellation/reset before/after final fill and publication. Test metadata
retains actual tool commands and source hashes through the common xsim helper.
Set `V4_COMMIT_KEEP=1` to retain vectors, traces and `.xsim.json` artifacts.
