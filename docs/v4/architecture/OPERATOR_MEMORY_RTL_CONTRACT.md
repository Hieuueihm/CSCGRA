# Shared operator memory ownership — candidate

`operator_memory` composes exactly one LFSR Phi generator, one Phi sign cache,
one dense B cache, the existing support builder, and the existing Phi reader
identity adapter. It instantiates no PE, vector RAM, second matrix copy, numerical
solver or controller PC. Its purpose is to share the live operators between
host loading, support construction and a kernel read port without response theft.
Existing Phi, memory and support-builder contracts remain authoritative.

## Ports and publication

Host `p_begin_*` matches the resident Phi interface: seed32, rows8, cols11,
key128, generation32, job16, fmt8 and valid/ready. Generator family/revision remain
the generated LFSR constants; operation tag is0. Accepted shape/job/format are
captured alongside the cache's accepted key/generation. Metadata outputs
`p_rows/cols/key/generation/job/fmt` are meaningful when `p_valid` is high.

Host `b_begin_*` and `b_fill_*` use the existing B-cache ABI: support-slot-major
32-row blocks, exact masks/last, zero padding. Direct dense loading is a reference
and fault-testing path; generated builds use the same physical B cache.
`b_rows/cols/key/generation/job/fmt` capture the actual accepted B begin, whether
host or builder. They are meaningful when `b_valid` is high. Metadata is not a
certificate, cryptographic key check or cross-job reauthorization.

`build_req_*` / `build_rsp_*` are the unchanged support_builder fields, including
the full packed ordered support, positive scale, source/destination keys and
generations and completion identity/counters. The owner additionally verifies
the accepted builder job/format against the captured Phi owner. On mismatch it
denies Phi identity to the builder, yielding PHI_KEY and invalid B. Shape/key/gen
validation remains inside the builder using captured owner metadata, never live
request reconstruction. Builder full-rebuild semantics invalidate old B even
when the accepted build is malformed.

The shared kernel interface matches operand_reader: `mat_valid/ready/dense`,
mask32, addresses288, key128, generation32, `mem_job/tag/fmt`, then held
`mat_rsp_valid/ready`, data576, masks256, mask32, generation/job/tag/fmt and fault4.
Dense selects B; Phi signs occupy low256 data bits with eight masks. The Phi
adapter snapshots read identity, validates published key/gen/job/fmt and checks
returned cache tag/gen/mask. B checks its own accepted identity and address bounds.
Read responses echo the accepted request. Inactive/fault data follow the existing
memory contract. Published shape must be validated by the kernel job owner before
forming bank addresses; this raw bank request has no shape input.

## Exclusive ownership and arbitration

One owner state covers idle, Phi fill, host B fill, support build or kernel read.
At idle the grant order is host Phi begin, host B begin, build request, kernel
read. A held higher-priority request may delay lower-priority work. There is no
same-edge replacement or speculative grant. Host fills own the resource through
publication/abort. Builder ownership starts on request acceptance and ends only
when its held completion is accepted. Even if the B cache has internally
published its final fill, a kernel cannot read it until builder retirement.

`compute_active` blocks acceptance of new host begin and builder requests. During
compute, held load/build requests do not starve kernel reads. The signal does not
cancel an existing owner or interrupt an accepted fill/build/read: that owner
must drain normally. A system should assert compute_active after builder response
retirement. B fill data only handshakes while the host B-fill owner is selected.

Kernel read ownership captures dense/source choice at request acceptance and
remains until response acceptance. Changing live dense/key/tag/address inputs
cannot reroute a response. A held kernel response prevents build acceptance,
which is essential because builder acceptance invalidates B. The pending Phi
adapter/cache response is fully drained before a builder can use the raw cache.
No invalidation substitutes for draining another live caller's response.

## Faults and cancellation

Read and build faults preserve their existing codes. There is no new private
fault encoding. Host publication faults remain visible through p_fault and
b_load_fault. Metadata valid outputs distinguish successfully published contents
from residual descriptor registers after a failed fill.

All blocks share synchronous active-high rst/cancel. Cancel flushes owner,
builder, Phi adapter/generator/cache and B cache, suppresses handshakes, discards
pending responses and invalidates published contents. No completion is fabricated
after cancellation. RAM payloads themselves are not reset. `builder_phi_invalidate`
is wired to both Phi cache and generator, so identity loss with an outstanding
builder read flushes that producer domain before a subsequent reload/build.
The builder's B cancel reaches the sole B cache on acceptance and abort.

This does not preserve a committed B copy, perform vector writeback or establish
job-level commit. Those are separate owners. No synthesis, implementation, BRAM
mapping, timing or throughput claim is made.

## Verification

`verification/v4/memory/tb_operator_memory.sv` uses the real LFSR/cache/builder/B
composition and existing operand_plan RTL to address all R1/R4 directions.
`verification/v4/test_operator_memory_rtl.py` checks every returned active bank
against independent indexed-LFSR or dense coordinate values and verifies complete
matrix coverage. It includes tiny and128x96 builds, original Phi width1024,
tail masks, seed0, scale extrema, direct dense fill, held reads/build completions,
compute locking, read-before-build draining, live request mutation, wrong
job/format/shape/key/generation, duplicate/out-of-range support, corrupted response
tags followed by rebuild, pending-read identity loss, and reset/cancel reload.
Only Vivado xvlog/xelab/xsim executes RTL; Python generates/checks integer data.
