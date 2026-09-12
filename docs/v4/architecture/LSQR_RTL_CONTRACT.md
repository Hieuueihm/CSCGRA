# Autonomous resident LSQR — candidate integration

`lsqr_engine` connects the shared operator owner, measurement loader, one generic
kernel engine, one scalar service, loaded service sequencer and candidate commit
controller. There are exactly32 PEs (two existing4x4 arrays inside the kernel),
one Phi sign cache, one dense B cache, one kernel vector workspace and the
writer's existing candidate/committed banks. There is no second matrix/PE datapath
or host numerical work after START. This implements one resident LSQR solve,
not an outer sparse-recovery algorithm, transform, board interface or application
quality guarantee.

## Program and numerical authority

The loaded128-bit generic service program is separate from legacy tile64 and
Control256; those ABIs remain unchanged. Program load valid/ready, revision,
verified/depth, PC/word/last and image/fault ports are forwarded to
solver_sequencer while idle. The compiler's `lsqr_program()` emits the bounded
LSQR recurrence, branches, scalar commands and stored-X normal certificate. The
host supplies a verified program; RTL's flag is an attestation, not SHA hardware.

Existing IntegerLSQRKernels is the numerical oracle, with D18F14 input, C18F16
coefficients, S27F22 arithmetic, ACC64 sums and X24F20 storage. Scalar DIV/SQRT
and kernel vector operations retain their contracts. Certificate tolerance is
1e-5, checked as exact integer normal_energy*10^10 <= rhs_energy after NARROW_X.
The sequencer reports the actual certified candidate slot; the top snapshots
that slot and drains it. It does not assume the compiler's current slot10.

## Input publication and job capture

Operator Phi begin and direct dense B begin/fill match operator_memory. Direct
dense B is an explicit reference/debug path; generated jobs automatically run
support_builder against the captured ordered support. Both use the same B cache.

`measurement_loader` accepts y_begin(rows8,job16,fmt8), followed by consecutive
32-element y_fill blocks with block2, exact mask32, D18 data576 and last. Inactive
elements must be zero. It sign-extends each D18 raw value and shifts left8 into
kernel workspace slot0, with no extra rounding. It publishes top-level y_valid
only after a full correct fill and the kernel's successful host status. A bad
begin/fill leaves Y unpublished. Native measurement format must be1, rows1..128.
The accepted data must have absolute raw peak<=8192 (0.5 in D18F14); all-zero and
lower-amplitude debug inputs are allowed. This range check does not choose a
normalization gain or prove a relationship to original floating measurements.

Host normalization remains a precondition: choose the power-of-two gain and
quantize D before loading. start_exponent is captured metadata in[-31,31], not
another scale operation on Y. Committed X remains in the normalized domain;
external decoding applies X_raw/2^20 *2^(-exponent). Internal reciprocal exponent
used by NORMALIZE is separate and supplied by the service program.

START captures generated flag, rows8, original columns11, support count7,
ordered support960, scale18, Phi/B keys128 and generations32, job/tag16, fmt8,
signed exponent7, max_iterations8 and instruction_limit32. This slice accepts
rows1..128, columns1..1024, count1..96<=columns, fmt1, max_iterations1..128 and
nonzero instruction limit. Count0 is rejected explicitly. A sequential scan
checks every active support index against original columns. Commit controller
then verifies duplicate/tail support semantics before any solver execution.

Y ownership must match captured rows/job/format. Generated jobs require matching
Phi shape/key/generation/job/format, then build matching B. Direct dense jobs
require existing B shape/count/key/generation/job/format. Descriptor authorization
is checked before computation; changing live START fields cannot change a run.
Host writes are blocked from accepted START through held done retirement.
Held host load requests take priority over START, preventing load/start deadlock.

## Execution and publication

The top validates the job, opens and validates a candidate, optionally builds B,
starts the sequencer, and waits for its held completion. Commands then execute
entirely through RTL program PC, kernel and scalar valid/ready interfaces.
Faulting completion never approves the candidate. On certified success, debug
reads drain the captured candidate slot in32-element blocks into commit fill.
Writer backpressure holds the same kernel response until accepted. The final
positive decision publishes only after all candidate blocks were validated.
Commit status is accepted before top done becomes valid.

The held done interface carries fault/detail, committed flag, iteration count,
normal and RHS energies and accepted job/tag/format. Committed read ports expose
X24/index/exponent/identity via a held response and retain the prior commit while
a new candidate is constructed or rejected. done counts and metadata hold while
done_ready is low.

Top fault codes:0 success,1 header/support range,2 measurement ownership/range,
3 operator ownership,4 builder,5 sequencer,7 writer/candidate read,8 cancellation.
Code6 is unused. done_detail retains the source fault code where available;
sequencer codes distinguish arithmetic, kernel/scalar failure, watchdog,
certificate failure and nonconvergence. Completion energies/iteration count are
the sequencer's captured report, not a separately recomputed floating certificate.

## Reset, cancellation and commit boundary

Hard rst clears everything, including program and committed validity. User cancel
flushes sequencer commands, kernel workspace, scalar, operator readers/producers,
measurement publication and candidate ownership together. The verified service
program is retained by the sequencer across cancel. The writer preserves its
already committed bank. A cancelled active run produces held CANCEL completion
after cancel deasserts; any writer abort status is drained before accepting another
job, so it cannot block the next candidate. A reload is required for invalidated
operator/measurement data. Internal execution faults use the same backend flush
and candidate abort/drain path, preserving committed X.

Publication occurs on the accepted positive decision edge. Cancellation before
that edge discards the candidate. Cancellation after that edge cannot undo the
published bank: the top retains the pending writer status and reports committed
success after cancel deasserts. It must not report an uncommitted cancellation
while exposing newly committed data. Cancel while idle produces no synthetic job
completion; committed reads are flushed but their underlying data remain valid.

## Evidence and limits

Permanent `tb_lsqr_engine.sv` loads program/operator/Y, then performs no numerical
host actions after START. Python compares exact committed X, certificate energies,
iterations and failure classes against existing IntegerLSQRKernels. Tests include
dense analytic and X-rounding cases, zero RHS, live generated multi-iteration
problems, originalN1024/M128/S96 nonzero solve, alternate certified slot14,
nonconvergence, numerical overflow, invalid Y/header, held done/reads, preexisting
commit preservation, cancellation during build/solve/candidate drain and after
publication, and reload after abort. Real RTL execution uses Vivado only.

This is correctness qualification of the resident candidate profile. It does not
freeze numerical ABI, establish global SNR20 for application signals, or qualify
synthesis, implementation, RAM mapping, resources, frequency or board operation.
