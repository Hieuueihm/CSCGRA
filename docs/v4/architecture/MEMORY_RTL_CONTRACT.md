# Resident memory and operand read path — candidate

Scope: full-fill resident stores and a single-outstanding read planner/joiner.
This is not yet an operator scheduler, control ADDRESS adapter, support builder,
transactional writeback or LSQR implementation. V4 BASELINE, design geometry
and FEEDER_RTL_CONTRACT remain authoritative. No ABI/numeric production freeze.

## Hierarchy and geometry

- vector_store: three S27F22 planes, each 32 banks x128 words (4096 elements).
  Logical index maps to bank=index%32, address=index/32.
  Two independently registered read ports can address the same plane.
  Implementation expresses two read ports plus one fill write port per bank;
  physical RAM mapping/replication and bandwidth are not synthesis-qualified.
- support_matrix_cache: one dense C18F16 B copy, up to128 rows x96 support slots.
  bank=(row+slot)%32; address=row*ceil(slots/32)+slot/32; 384 words/bank.
  Transpose uses the same copy. No duplicate transpose memory is maintained.
- operand_reader owns operand_plan and operand_feeder; it captures a descriptor,
  issues matrix/vector reads independently, validates and joins responses, then
  emits one expanded 32-tile coefficient/vector frame.
- This is a standalone integration candidate. cgra_fabric already owns a feeder
  and consumes raw bundles, not these expanded frames. The target catalog edge
  is functional, not a claim of a connected top or a second production feeder.

## Fill, publication and identity

begin_valid/ready captures shape and identity. Vector identity is plane, length,
generation32, job16, format8; B adds an opaque ordered-support key128 and shape.
Key creation and descriptor authorization belong to the caller, not the RAM.
Begin invalidates its destination before loading. Vector fills consecutive
32-element blocks. B fills support-slot-major, consecutive 32-row blocks within
each slot; fill data is row-lane order and is rotated into diagonal banks.
Every accepted word must have the exact block/slot, tail mask and last flag;
inactive data bits must be zero. Only a complete valid fill publishes data.
Invalid order, padding or last aborts loading and leaves the destination invalid.
No incremental scatter updates, candidate allocation or job-level commit exists.

begin_ready requires no load and no held response (both vector ports empty).
There is no same-edge response replacement. B reads are blocked while loading.
Vector reads can continue during fill: other published planes remain readable;
reading the invalidated target returns KEY. Begin_valid suppresses new reads.
Published data is immutable until the next begin for that destination.

## Reads and join timing

Each store read has one registered-cycle latency and holds its response until
accepted. Requests carry bank masks/addresses, generation, job, tag16 and format;
B also carries key. Inactive bank addresses are ignored; returned inactive data
is zero. Unpublished or mismatched identity returns KEY, illegal vector plane
returns PLANE, active index outside published shape returns RANGE. Fault data
and mask are zero; response identity echoes the accepted request.

Planner modes and alignments exactly follow FEEDER_RTL_CONTRACT. R1 broadcasts
one vector reduction value; R4 gathers four reduction lanes. vec_base offsets
the reduction index and must keep active indices below4096. Matrix addresses
are nine bits; Phi uses the low eight banks and its own row-block layout.
An all-tail R4 step is legal and skips both zero-mask source requests.

Reader accepts one transaction, captures all descriptor fields, then independently
holds matrix/vector requests until accepted. Responses can arrive in either order.
It checks exact masks and generation/job/tag/format before submitting to feeder.
A source failure still drains the other outstanding source; it cannot cancel only
one producer and silently reuse an old response. Matrix fault has priority over
vector fault once both are received. Tag/identity echo mismatch maps to TAG;
source fault/missing mask or feeder failure maps to SOURCE. Initial plan errors
map to SHAPE/RANGE and illegal vector plane to PLANE. Codes are generated from
config/v4_memory_exec.json; reserved codes are not additional implemented checks.

Coefficients remain signed C18F16, sign-extended into S27 ports, NOT shifted to
F22; vector values remain S27F22. last is captured schedule metadata, not proof
of final job completion. The response holds all data, mask and tags under stall.

## Phi adapter and cancellation

The uniform matrix response carries dense bank data or Phi signs in its low256
bits plus eight sign masks. Current live-RAM integration covers dense B only.
phi_sign_cache has generation/tag metadata but not this full job/format envelope.
A future adapter must own the accepted descriptor and validate its identity;
it must not reconstruct response tags from changing live request pins.

Synchronous active-high rst or cancel clears descriptors, pending requests and
responses, not RAM contents. Reader and attached producers must flush together;
all resident stores then require reload. No retained committed-job guarantee.

## Verification

Permanent benches and IO schemas: verification/v4/memory/.
Coordinate dictionary integer oracles drive before/after-edge comparisons.
The RAM integration bench directly connects B/vector stores to reader, with
independent request/response gates and coordinate-based frame assertions for
R1/R4 both directions, tiny/tail/max shapes, faults, stalls and reset/cancel.
Phi response-protocol tests use modeled source responses, not a live cache.
Run `py -3 scripts/v4/run_rtl.py` for full V4 tests using only Vivado
xvlog/xelab/xsim, with actual commands, versions and source hashes in
`reports/v4/rtl_correctness.json`. Set `VIVADO_BIN` to the Vivado `bin`
directory if needed; the default is `C:/Xilinx/Vivado/2018.1/bin`. Retained
runs use `*.xsim.json` elaboration descriptors and Vivado build directories.
No synthesis or implementation is performed.

[Historical memory evidence](../../../reports/v4/MEMORY_RTL_CORRECTNESS.md)
records the earlier simulator gate; current acceptance uses the unified Vivado run.

