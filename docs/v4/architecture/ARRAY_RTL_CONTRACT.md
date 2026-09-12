# Two-array execution, candidate v1

This extends the packed scalar contract with opt-in ROUTING=1 in pe_array.
Standalone pe_context/context_decode default to ROUTING=0 and still reject
route-bearing words. Binary tile64 layout and compiler revision are unchanged.
This is not a control256 decoder, loader, PC/loop engine, support cache or LSQR.

## Hierarchy and issue

    cgra_fabric
      operand_feeder
      pe_array ARRAY_ID=0,1
        pe_context TILE_ID=16*ARRAY_ID+position, ROUTING=1 (16 each)
          context_decode
          pe_tile -> pe_alu + two pe_operand
        mesh_router (16 each)

One outstanding 32-word issue. The caller provides 32 numerical tile words
(convert compiler little-endian hex byte strings before driving), revision,
ALU mode, enable mask and aligned feeder request. The two arrays cannot issue
or retire independently through this fabric. Each array is a4x4 row-major
mesh with no inter-array links. ARRAY_ID is an elaboration constant0 or1.

req_operands=1 runs the feeder and intersects its tail mask with req_enable.
req_operands=0 bypasses memory operands for CLEAR, reduction, immediate/RF
operations and HALT. Matrix/vector validity is then false, not valid zero.
That distinction is essential: a last MAC tail mask must not disable an
earlier reduction lane's accumulated partial during later ROUTE/ADD phases.
The caller supplies the appropriate output-group enable mask for reduction.
Invalid packed words are checked even on disabled lanes. A feeder fault
returns rsp_feed_fault and no array issue occurs; tile fault fields are zero.

## Atomic execution and link lifetime

The arrays hold all32 tile responses without accepting any until both arrays
finish. Each checks all local arithmetic/decode faults and route sources
before launching its routers. Directional link_ready can stall each router
output independently. Accepted transfers enter private staged ingress slots;
they are not visible to the next instruction or to committed link state.
At the single fabric rsp_valid && rsp_ready edge, either all tile RF/predicate/
ACC changes and staged links commit, or none do. A fault in either array
asserts rsp_drop to both arrays. rsp_drop discards a completed ALU/tile response
without resetting previously committed state. Primitive standalone users must
tie rsp_drop=0. Reset/cancel instead clear the whole local execution epoch,
including previously committed RF/ACC/predicates/links, as in the older contract.

Faulted responses expose candidate data/ACC for diagnostics; rsp_store,
rsp_exec and rsp_halt are suppressed globally. Do not publish candidate data
without a successful response handshake. STORE/HALT are backpressured events,
not an autonomous RAM write or program stop. All response payloads are stable
once valid while the consumer stalls. No same-edge replacement.

Committed ingress slots retain their value until overwritten or reset/cancel;
reads do not consume them. The compiler owns producer-before-consumer scheduling
and liveness. Job and format must match the consumer; op_tag identifies the
current response and need not equal the producer's earlier instruction tag.
There is no generation/producer-tag scoreboard in this execution boundary.
Changing an operator epoch under a reused job/format therefore requires cancel
or an external flush protocol; the future sequencer/loader must enforce it.
Scalar LINK reads require signed64 data to fit S27; wide ADD and ROUTE forwarding
use all64 bits. Wide reductions never silently truncate to S27.

## Route values and supported subset

- ACC selects the pre-instruction ACC64 snapshot, not an uncommitted new MAC.
- RESULT selects signed-extended scalar rsp_data, not ACC64. MAC scalar data
  is zero under the existing ALU contract; use a later ROUTE ACC for its sum.
- VALUE is supported only for ROUTE with source ACC or a valid LINK; it carries
  the full64-bit snapshot. ROUTE NONE with VALUE reports SOURCE on active lanes.
- ROUTE executes a guarded HOLD, with no RF/ACC writes; nonzero write flags
  report EXEC. The existing edge/encoding/revision checks still apply.
- Other scalar opcodes can combine ACC/RESULT routes with their existing
  supported flags. VALUE sidebands on non-ROUTE words remain EXEC.
- HALT cannot carry routes; no new ISA encoding or algorithm classifier is added.

## Conservative schedule and evidence scope

An accepted fabric request captures the feeder result after1 edge. The following
edge issues both arrays. Local scalar responses take1 or2 edges. Each array
then validates the complete response set, issues routers, waits for all links
and returns its done indication. Even a no-route issue pays the router phases.
Minimum acceptance-to-response latency is5 edges for single-cycle/no-route,
6 for a full one-hop issue or a two-cycle/no-route issue; stalls extend it.
Commit occurs on a subsequent response handshake. This is correctness-first,
not the older analytical II1 schedule and not a measured synth/timing claim.

The fixed fabric TB observes all32 committed ACC/RF/valid/predicate banks on
every edge. The integer/cycle oracle checks independent link stalls, atomic
cross-array failure, reset/cancel after partial delivery, wide R4 reduction,
simultaneous ALU/RESULT routing, vertical links, job/format mismatch and tails.
Driven Phi forward and transpose programs compare final integer sums against
indexed LFSR signs. These use compiler-packed tile words with an external test
schedule; they do NOT execute the packed control256 loops or qualify the
existing full compiler image templates. Dense B feeder permutation is tested;
resident B scheduling, support build and LSQR integration have separate
contracts and tests. This array test alone does not qualify those layers;
see [LSQR integration](LSQR_INTEGRATION.md) and the current unified evidence.
