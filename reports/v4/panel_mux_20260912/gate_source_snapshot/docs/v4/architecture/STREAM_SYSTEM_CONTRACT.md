# Shared streaming system integration contract

Continuation after the [accepted first slice](STREAM_RTL_CONTRACT.md).
Current user steering: **QR is the target least-squares solver. LSQR remains
comparison/reference only; it is not a fallback in the new recovery programs.**
This document defines module ownership before coding. Source-bound Vivado
evidence is required for each extension and the complete recovery programs.
The previous streaming snapshot remains the reference for unchanged behavior.

Current promoted transport uses the [queued operator pipeline](OPERATOR_PIPELINE.md):
four frame slots, two vector blocks, two ordered matrix credits, and elastic
Phi reads. The packed algorithm/context ABI and integer arithmetic are unchanged.

## Round-two source-clean evidence

The fixed-eight suites at M32/N64/K8 and M64/N256/K8 completed PASS11 with
common raw Phi/Y per geometry, raw X/residual/support/status comparison and
actual outer count eight. The active set is MP, OMP, GOMP, CoSaMP, SP, IHT,
HTP, GP, FISTA and PDHG. ADMM's measured fixed-eight rows are archived
reference only; round-two ADMM quality is `STOPPED_BY_SCOPE`, not PASS.

| Geometry | Active-10 cycles (MP, GP, IHT, OMP, GOMP, CoSaMP, SP, HTP, FISTA, PDHG) | ADMM reference |
|---|---|---:|
| M64/N256/K8 | 15,806; 17,549; 23,036; 68,110; 153,814; 431,824; 133,885; 35,377; 20,362; 20,694 | 409,442 |
| M32/N64/K8 | 6,370; 7,351; 7,988; 48,742; 115,570; 359,756; 91,662; 18,222; 5,106; 5,560 | 103,109 |

See the root-generated [round-two comparison](../../../reports/v4/cycle_round2_comparison_20260909/round2_comparison_vi.md). These xsim gates do not establish application quality, synthesis/implementation, timing, resources, fit, board deployment or a production bit lock.

Round two adds only command-local transport scheduling: two raw sign-tile
entries for favorable live-Phi modes, context-local TEMPLATE operand
suppression/reuse, and analytic range gathering. It is qualified by the final
source-clean fixed-eight and module gates; that does not make a timing,
resource, fit, synthesis, board or application-quality claim.

## Physical ownership

`recovery_engine` is the new independently elaborated integration root. It
contains one `program_sequencer`, one `stream_kernel`, one
`live_operator_memory` and `arithmetic_service`. `stream_kernel` owns the
only vector pool and the only `stream_fabric`: two 4x4 arrays, exactly32 PEs.
Its `operator_frame_feeder` shares that pool read port with vector kernels.
Neither old `kernel_engine` nor another fabric is co-instantiated.

`stream_engine` remains a compatible CALL/HALT revision-one wrapper over the
external-command `stream_kernel`. Its original loader, host and completion
behavior must pass the existing tests after extraction. Full-program control
uses a separate service ISA and must not reinterpret a legacy image silently.

| New module | Ownership |
|---|---|
| `paired_support_store` | Exact existing B-cache protocol, with sixteen TDP18 banks and two reserved read credits |
| `live_operator_memory` | Existing LFSR/Phi-cache/builder semantics, one paired B store, exclusive fill/build/compute ownership |
| `operator_frame_feeder` | Independent dense/trans/R1/R4 coordinates, live matrix/vector response join and masked frame delivery; no PEs |
| `stream_kernel` | Captured generic command, one pool/fabric, vector/GEMV/reduction and transactional destination publication; terminal ACC uses existing PEACC with fixed registered reduction links |
| `support_service` | Shared-pool block selection, ordered/sorted support operations and scratch candidates. For each output 32-lane block, SLICE/REPLACE_RANGE uses at most three required physical providers, one outstanding read, common-offset alignment and scratch; see [support contract](SUPPORT_SERVICE.md). |
| `program_sequencer` | Loaded program/templates/descriptors/constants, PC, scalar RF, subroutines/branches, service identities and scalar-template opcode16 dispatch; see [scalar-template contract](SCALAR_TEMPLATE.md) |
| `arithmetic_service` | Exact signed64 DIV with source fraction0/-10 and SQRT44; shared response protocol |
| `recovery_engine` | Host/job ownership, operator build services, shared scalar service, whole-result publication and counters |

## Live matrix and mapping

Reuse LFSR32 recurrence, sign order, seed/key/generation and C18 scale exactly.
Phi has M<=128, N<=1024. B has M<=128, actual support1..96; reject overflow,
never truncate support. The initial live operator is Phi in the coefficient
domain, Psi=I at the accelerator interface. Arbitrary raw-signal transforms
must not be claimed implemented by loading transformed measurements alone.

For B keep logical bank `(row+slot)%32`, address
`row*ceil(S/32)+slot/32`. Physical bank is logicalbank%16, port logicalbank/16,
address `512*port+logicaladdress`. Both halves fit within1024x18; fill and
compute remain exclusive. Keep all18 coefficient bits and exact metadata.
RAM data is not cleared by reset; publication metadata is invalidated.

The feeder accepts dense, transpose and R4 independently. R1 assigns32 outputs
to32 lanes. R4 assigns8 outputs to groups of four PEs, with reduction offsets
0,8,16,24 plus step0..7 in an aligned reduction tile. Four partials are added
as checked signed64 integers **before one round16**, preserving GEMV rounding.

### Round-2 command-local Phi tiles

The qualified transport retains two raw **32-row × 8-column** live-Phi sign
tiles for the duration of one command. Only R1-forward and R4-transpose are eligible;
dense commands and all unfavorable Phi directions use the existing bank/reader
path. The entries retain the same key, generation, job/tag and lane-mask
identity that qualified the raw bank response. They do not alter the eight sign
banks, generate an alternate Phi copy, or change LFSR seed/sign order. At most
one validated eligible hit can be admitted per clock. That local condition does
not establish a full feeder or kernel initiation interval.

### Round-2 template and range transport

A loaded template continues to own operand selection and binding masks. The
candidate suppresses a pool request only when the captured context marks that
operand unused; if two consumed operands name the same validated source, it may
reuse that captured response. Tails, lane masks, identities, faults, stalls and
cancel remain visible under the original context. This is scheduling around the
loaded context, never template rewriting or arithmetic specialization.

SLICE and REPLACE_RANGE retain their public capacity bound `N <= 1024` and
validate every required source lane. For each output 32-lane block, their analytic plan has at most three
distinct physical 32-lane providers: one source block plus up to two unaligned auxiliary
blocks, or two source blocks for SLICE. Equal physical source/aux addresses
union their required masks in first-used order. Reads remain serial with exactly
one outstanding pool request. After each accepted tagged/masked response, the
candidate uses common unsigned word-offset alignment and a masked merge to form
one scratch block. `stream_kernel` alone copies scratch and publishes after
successful completion, preserving source/destination aliases and rollback.

Phi R1-forward and R4-transpose need one eight-bank sign-cache read pass per
frame. Phi R1-transpose and R4-forward require four passes. All B mappings use
one32-bank logical read per frame. Compiler mapping must include these costs;
all four legal Phi modes do not have identical throughput.

The new vector interface uses block9 public addresses and lane masks, not
truncated legacy per-bank7-bit addresses. Each frame gathers one scalar or
four entries from one aligned32-entry vector block. Wire vector operands into
the S27 side and coefficients into the C18-checked B side of the streaming PE.
The feeder has no private copy of the full vector pool or complete matrix.

Track request credits including every in-flight RAM response. Report achieved
frame acceptance intervals; a FIFO around a serialized endpoint does not
prove II1. Multi-pass Phi traffic and buffer/port limits are part of kernel
cycles, not omitted startup costs.

## External kernel boundary

Commands capture operation6, the loaded2048-bit PE contexts and descriptor32,
public src_a/src_b/dst block9, length11, rows8/columns11, dense/trans/R4,
scalar_a/scalar_b S27 and per-lane scalar binding masks32, shift6, count11,
coefficient scale18, matrix key128/generation32, job/tag16 and format8.
Legacy frame_count8 and tail_mask32 remain available for revision-one calls.
Responses hold fault/detail4, scalar64, nonzero, job/tag16 and format8.
Additional support-service lengths are explicit; no value is guessed from an
algorithm name. The sole RF belongs to the sequencer, which resolves scalars.

`SCALAR_TEMPLATE = 16` is a captured generic command from
`program_sequencer` through `stream_kernel` to lane0 of the existing
`stream_fabric`. It uses no separate RAM, scratch vector, cache request, or
algorithm-specific RTL. Its exact one-lane shape, bindings, range checks,
rounding, fault and held-response rules are in
[SCALAR_TEMPLATE.md](SCALAR_TEMPLATE.md). The existing PEACC uses fixed
registered reduction links; this is neither general programmable mesh routing
nor a new terminal arithmetic block.

Arithmetic uses candidate S27F22/C18F16 and ACC64. Preserve exact NORMALIZE
raw multiply followed by its dynamic shift; a round22 MUL followed by another
round is not equivalent. Signed DOT and ENERGY use loaded MAC/SUM templates.
SOFT, selection and support operations share pool ports and do not introduce
an extra multiplier array. The candidate range merge changes no arithmetic and
adds no PE; it is a tagged pool-to-scratch transport operation. Stable selection
ties prefer smaller original index.
Ordered append versus sorted union are distinct operations; OMP order must
not silently become sorted order. Dense proximal output may contain1024
nonzeros and is not constrained by the96-entry restricted-LS support limit.

TOPK should scan32 lanes per public RAM block through a pipelined argmax tree,
with excluded/selected masks and deterministic original-index ties. Repeating
block scans K times costs K*ceil(N/32) read grants, not K*N scalar reads.
For the live constant-magnitude Phi columns, the quantized column norms are
identical M*scale^2, so normalized MP/OMP ranking is exactly the same order as
raw absolute correlation. This equivalence is not claimed for arbitrary A.

## Program and numerical obligations

Programs contain genuine hardware branches/subroutines and generic service
requests. They are not replay lists calculated from running a reconstruction
on the host. Constants depending only on configured policy/iteration, such
as the existing FISTA momentum coefficient table, may be precomputed.

The service ISA has one32x64 scalar RF, up to32 logical vector descriptors,
bounded CALL/RET, signed comparisons, instruction watchdog and indexed constant
loads. Vector descriptors resolve bases/capacities in the existing pool;
lifetime analysis must prove non-overlap for concurrently live values rather
than allocate every vector a full1024-element slot.

Keep the selected storage formats: greedy recovery stores X24F20 and re-embeds
into S27; proximal candidates store D18F14 and re-embed. A new QR numerical
backend must qualify these widths; LSQR's earlier evidence does not qualify QR.
S27 identity storage is a distinct mode, not the default replacement.
The QR certificate must run on stored X24; QR rank checks, factor errors and
any bounded refinement are specified separately in [QR design](QR_SOLVER.md).
There is no promise of bit-identical results/iterations to LSQR. Historical ADMM retains shifted CG for A^T A+rho I; it is reference-only in the round-two policy, with no new ADMM quality PASS.
MP correlation/norm division needs signed source-fraction -10; scalar division
must support this exact scaling without an approximate reciprocal.

Full-program evidence compares raw X, residual, support order, status, outer
and inner iteration counts, certificate and rollback decisions against the
corresponding numerical model with an independent arithmetic oracle. QR has
its own declared rounding contract; old LSQR trajectories are comparisons.
Tests must run after one START without
host iteration decisions. Eleven names or isolated phase replay do not
constitute eleven completed recovery implementations.

## Qualification order

1. Live Phi/B, four legal mappings, maximum/tail shapes, identity/fault/stall/
   cancel and raw reduction through the shared32-PE kernel in Vivado xsim.
2. Generic control, selection/support, scalar modes and complete recovery
   packages, with program-level arithmetic and transaction correctness.
3. Application quality gates remain SNR>=20dB, loss<=0.5dB and NMSE ratio<=1.10;
   calibration is not held-out production bit qualification.
4. Only after applicable correctness gates, synth/impl on
   xczu7ev-ffvc1156-2-e at10ns and report real resource/timing/cycle tradeoffs.
   The user's existing authorization covers these later steps; no extra
   permission checkpoint is introduced by this contract.
