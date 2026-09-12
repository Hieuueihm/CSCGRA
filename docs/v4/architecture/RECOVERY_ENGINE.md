# Recovery integration and whole-result publication

This is the next integration boundary after the qualified live-operator and
kernel slices. Read [system contract](STREAM_SYSTEM_CONTRACT.md) and
[QR target](QR_SOLVER.md). It does not certify a complete recovery algorithm
merely because the top accepts a program. All RTL tests use Vivado xsim.

## Ownership

`recovery_engine` instantiates exactly one `program_sequencer`, one
`stream_kernel`, one `live_operator_memory`, one `arithmetic_service` and one
`result_store`. Only the kernel owns the vector pool and two 4x4 PE arrays.
No old LSQR/kernel/commit hierarchy is co-instantiated. QR factor primitives
will extend this shared path after the numerical gate; do not substitute a
mock QR or call LSQR to make an end-to-end recovery test pass.

The sequencer's scalar-template opcode16 path is defined by
[SCALAR_TEMPLATE.md](SCALAR_TEMPLATE.md): it dispatches through the kernel to
lane0 of the existing fabric and does not allocate RAM or vector scratch.
`result_store` commits X plus result metadata; residual remains workspace
vector-pool data and is not a result-store cache.

The top exposes the existing ordered program loader, idle vector-block host
port, idle Phi-fill descriptor, job START/DONE and committed result reads.
The first integration uses these native interfaces; an AXI/DMA board shell
is a later boundary. Loading vectors as S27 raw values does not implement an
ADC or host normalization unit. Test drivers must embed quantized D18 inputs
exactly and report their normalization exponent.

START captures M/N, Phi key/generation, positive C18 scale, job/tag/format,
instruction watchdog, output storage mode and input gain exponent. Mode1 is
X24F20 embedded in S27F22; mode2 is D18F14 embedded in S27F22. A separate flag
states whether an ordered active-support list is part of the result. Dense
proximal outputs have length N and do not require a 96-entry nonzero list.
Supported exponent range is -31..31 for this integration profile.

START requires a complete program, drained host responses and a published
Phi with matching M/N/key/generation/job/format. External loader, Phi writes
and vector host requests are locked while running. Completion is held until
accepted. Program loading and cold Phi fill are measured separately from
accepted-START-to-DONE job cycles. Reusing Phi across a different owner/job
requires an explicit future rebind contract; matching seeds alone is not one.

## Internal services

Kernel requests pass directly from the sequencer. The live metadata mux uses
the kernel's captured matrix selection. Phi commands use the START Phi
generation; B commands use the currently published B generation. B uses the
captured operator key and a fresh generation for each accepted rebuild.
Reject generation wrap before issuing a builder request; do not reuse a
wrapped token while claiming it is new.

For BUILD_B, pause kernel dispatch and use the kernel's idle host read port
to gather the explicit ordered index list from pool blocks. Validate raw
indices, uniqueness, N bounds and S=1..min(M,96). Preserve order. Capture
the service identity independently of later pins. Then call the real
support builder with the Phi descriptor and selected C18 scale. Hold the
tagged build response for the sequencer. No CPU takes iteration decisions.

The internal reader also drains results after program completion; it is
mutually exclusive with builder collection and external host access. Reads
validate exact masks, tags, fault codes and initialized lanes. Internal
errors terminate the job and flush pending core/scalar/operator service
ownership. Cancellation does not manufacture a completion response.

## Result policy

A program status in 0..5 with no service/program fault is eligible for
publication: residual tolerance, iteration limit, paper limit, no new atom,
stationary or residual non-decrease. The program must keep its last accepted
outer iterate in the output descriptor. Status6..8 and unknown statuses are
not publishable. A failed job preserves the previous committed job result.
This policy does not label an iteration-limited reconstruction converged.

The sequencer exposes held resolved base/capacity for result, residual and
support. Drain exactly N result elements. Validate descriptor capacity and
that every result value is an exact embedding of the captured storage mode:
low2 bits zero and checked signed24 for X24, or low8 bits zero and checked
signed18 for D18. Do not apply another unreported rounding during commit.
The residual descriptor remains workspace data; tests may read it after DONE.

If the job requests an active support list, collect and validate up to96
unique indices from its descriptor before publication. A zero-length list
is legal. A dense proximal job publishes no active-list payload, even if all
N coefficients are nonzero. The result metadata distinguishes these cases.

`result_store` keeps two banks of N<=1024 S27 words and matching metadata.
A 32-lane input buffer serializes valid elements into the inactive bank;
this adds a measured, once-per-job drain cost without demanding32 output RAM
write ports. Data RAM bits are not reset. A complete, checked candidate and
an explicit approve transaction switch the committed bank atomically.
Cancel/fault discards the candidate. A separate internal `abort` discards
candidate/status only, preserving an already accepted external committed
read. User `cancel` flushes that read as well. Reset invalidates both metadata sets.

The result read interface returns raw embedded S27, index, storage mode,
normalization exponent and job identity. A read response owns its bank and
metadata until accepted. Do not overwrite that bank while the response is
pending; beginning a conflicting candidate must wait. No output from a failed
candidate may leak through result reads.

## Required tests

Run real loaded generic programs through real kernel, scalar and builder
endpoints with no host iteration decisions. Include Phi then B reads after
multiple different support builds; maximum/tail vector lengths; scalar-bound
contexts and branches; aliasing; held endpoints; malformed metadata/index/
storage embeddings; cancel during build, compute, drain and held completion.
Check a prior committed result survives each failed/canceled replacement.

Selection/controller tests remain useful independent gates. Complete recovery
tests additionally compare each algorithm's raw X, residual, support order,
status, outer/inner counts and stored-solution certificates to its qualified
numerical contract. Synthesis/implementation follows applicable correctness,
using xczu7ev-ffvc1156-2-e and a 10ns clock; this contract creates no extra
user approval checkpoint.
