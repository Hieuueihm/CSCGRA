# Payload DMA contract

Initial bounded implementation: AXI4-Lite remains the control plane. One
128-bit AXI4 master transfers raw signed S27 values stored as sign-extended
little-endian 32-bit words. Program/context images and LFSR Phi descriptors
remain on the existing PIO path; this is not an arbitrary dense-Phi loader.

## Register map

The DMA window is separate from the legacy host mailbox map. All registers are
32-bit, aligned byte offsets within the same 4 KiB control aperture.

| Offset | Name | Access/reset | Meaning |
|---|---|---|---|
| 0x300 | ID | RO/0x00010080 | DMA revision and data width identity |
| 0x304 | CONTROL | WO/read zero | START=1, CANCEL=2, ACK=4; exactly one command |
| 0x308 | STATUS | RO | Bits 0..4: busy, done, error, start_eligible, input_tainted |
| 0x30c | MODE | RW/0 | Bit0: 0 upload, 1 download |
| 0x310 | ADDR_LO | RW/0 | Bus address bits 31..0 |
| 0x314 | ADDR_HI | RW/0 | Bus address bits 63..32 |
| 0x318 | COUNT | RW/0 | Bits 10..0; 1..1024 elements required at START |
| 0x31c | BLOCK | RW/0 | Bits 8..0; upload vector-block base, ignored for download |
| 0x320 | TAG | RW/0 | Bits 15..0; native request tag |
| 0x324 | IRQ | RW/0 | Bit0 enable; bit1 read-only DONE/pending |
| 0x328 | ERROR | RO/0 | Low four bits, error codes below |
| 0x32c | BYTES | RO/0 | Completed native upload bytes / successful write-response bytes |
| 0x330 | CYCLES | RO/0 | DMA active clocks, not core cycles |
| 0x334 | READ_BEATS | RO/0 | Accepted AXI read beats |
| 0x338 | WRITE_BEATS | RO/0 | Accepted AXI write beats |
| 0x33c | STALLS | RO/0 | Active clocks waiting on an AXI or native endpoint |

Descriptor writes merge enabled bytes; strobed nonzero reserved bits are
rejected. Zero-strobe descriptor writes are no-ops. START rejects invalid
descriptors with AXI SLVERR and a legacy wrapper error, without starting DMA.
Counters reset on accepted START, retain on ACK and wrap at 32 bits.
DMA DONE/error persist until CONTROL.ACK; ACK while busy is rejected. DMA IRQ
is `enable && done`, ORed with the legacy IRQ. Legacy ACK.IRQ does not clear
DMA DONE, and DMA ACK does not clear any legacy mailbox or wrapper error.

Error codes: 0 success, 1 invalid descriptor (engine guard), 2 AXI RRESP error,
3 AXI BRESP error, 4 cancellation, 5 native fault, 6 response identity or
RLAST protocol error, 7 payload not sign-extended S27.

An upload error or cancellation taints its block/count. START remains rejected
until a complete retry of the same descriptor succeeds, or reset clears the
taint. DOWNLOAD output is invalid after a failed or cancelled transfer.

## Commands and ownership

UPLOAD reads DDR into consecutive native vector blocks; DOWNLOAD reads the
committed result store starting at result index zero and writes DDR. Descriptors
carry a 64-bit 16-byte-aligned address, element count 1..1024 and upload block
base. The upload end block must be below 480, excluding kernel scratch.
DOWNLOAD count must not exceed the committed result length. No automatic core
START is performed. DMA starts only while the native core and PIO bridge are
idle, with no load in progress or mailbox awaiting acknowledgement. While DMA
owns native host/result ports, PIO commands and descriptor mutation are rejected.

One burst is outstanding, INCR only, size=4 (16 bytes), maximum eight beats.
Bursts never cross a 4 KiB boundary. No IDs, exclusive access, cacheable
transactions, scatter/gather, coherency, address translation or clock crossing.
Both buses use s_axi_aclk and the common active-low boundary reset. Read tails
fetch the rounded-up 16-byte beat; host allocation must include that padding.
Write tails use WSTRB to leave bytes beyond the requested count unchanged.

## Completion and errors

VALID and payload remain stable until READY. CANCEL stops new native requests
and new AXI bursts, but never withdraws a pending AXI address/data offer or
abandons an accepted response. Accepted bursts drain before BUSY clears.
Native operations already offered also complete; global reset is a system-level
bus reset and must reset the connected interconnect/slave as well. An endpoint
which never responds may therefore keep BUSY asserted after cancel.

Only a clean complete read block is published to the vector pool. Earlier
blocks or DDR writes are not rolled back on later errors. Progress reports
completed native writes / successful B responses, not atomic job completion.
Software must treat output buffers from failed/cancelled downloads as invalid.
Upload errors/cancel require a complete retry before using the input.
The retry must match block/count, but may use a corrected DDR address or tag.
PIO writes cannot clear input taint. During DMA ownership, legacy CANCEL
cancels/drains DMA only; it does not invalidate Phi or reset the native endpoint.
Outside DMA ownership, the original legacy CANCEL semantics still apply.

DMA counters measure active clocks, accepted read/write beats and endpoint-wait
clocks; these are not native compute cycles or a DDR/controller throughput claim.
DMA DONE/error is sticky with a separate IRQ enable and W1C acknowledgement.
No synthesis, implementation, board, coherent-driver or application sign-off
is implied by a passing simulation.

## Reproduction

Run the source-bound XSim checks from the repository root:
`python -m unittest verification.v4.test_payload_dma_rtl -v`
and `python -m unittest verification.v4.test_host_dma_rtl -v`. The latter
exercises AXI-Lite control, the AXI4 DDR model, native vector upload, real-core
START/result handling and native result download.

## Host sequence and integration limits

1. Load program/context and Phi descriptors through PIO and ACK their mailboxes.
2. Allocate a 16-byte-aligned device-visible buffer with padded read tail. Pack
   sign-extended S27 words, and perform the platform-required DMA cache clean
   and memory ordering before START. A CPU virtual address is not a bus address.
3. Program UPLOAD descriptor, START, wait for DONE/IRQ, inspect ERROR and BYTES,
   then DMA ACK. Retry the full same block/count after failure before core START.
4. Program/start the core normally. Read DONE, committed metadata and support
   through AXI-Lite; ACK DONE and other legacy mailboxes before DOWNLOAD.
5. Program DOWNLOAD, START and wait for successful DMA completion. Perform the
   platform-required cache invalidation/order before consuming DDR output.

This is a single-clock, non-coherent master. The integrator must connect the
master to a compatible memory interconnect/controller, constrain accessible
addresses, provide common reset recovery, and supply any width conversion.
No CPU/PS VIP, physical DDR, OS DMA API, board or all-ten-algorithm DMA execution
is established by the bounded generic-program integration test.

## Matched full-program measurement

The separate September 11 benchmark now runs all ten algorithms through PIO and
DMA at M32/N64/K8 and M64/N256/K8, with actual eight iterations: 40 XSim
simulations PASS. Native cycles and raw X/residual/support/status remain exact.
See `PAYLOAD_BENCHMARK.md` and `reports/v4/payload_benchmark_20260911/README.md`
for disjoint timing buckets and the simulated-memory limits. The subsequent
physical run failed synthesis elaboration in the unchanged factor-panel RTL;
no PPA/Fmax or implementation result is available.
