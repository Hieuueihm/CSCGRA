# Generic service-program sequencer candidate

`solver_sequencer` owns one 256x128 program RAM, 32 signed64 scalar registers,
one global PC and one outstanding service operation. It contains no PE array,
matrix/vector memory or scalar divider/root datapath. The top instantiates
`kernel_engine` and `scalar_service` and connects their tagged request/response
interfaces. The existing tile64/control256 sequencer is a separate reference;
this generic service ISA does not claim compatibility with that image format.

`config/v4_solver_program.json` defines fields, opcodes and faults.
`scripts/v4/generate_solver_interface.py` generates field offsets and constants.
Fields pack least-significant first in JSON order; words are numerical128-bit
hex values, not byte-reversed tile64 strings. `compiler/v4/solver_program.py`
encodes generic instructions and returns `(words, labels)` from `lsqr_program()`.
The returned 256 words pad unused addresses with FAIL. No runtime Python
branch decisions are required by the sequencer.

## Program load and run epoch

Idle `load_begin_valid/ready` captures revision1, trusted-host `load_verified`
and depth256. An accepted load begin invalidates the previous image. Exactly
256 `load_valid/ready` writes must follow at PC0..255 in order, with last only
on PC255. A malformed stream sets load_fault=LOAD and remains invalid; final
valid write atomically sets image_valid. The trusted bit is not RTL SHA256
verification. Program writes cannot be accepted while running or holding done.

Idle `start_valid/ready` snapshots rows1..128, columns1..96, key128,
generation32, job16/tag16, fmt8=1, maximum iterations1..128 and nonzero32-bit
instruction limit. Invalid start returns held LOAD/MODE failure. Start clears
all RF registers, sets R30 to the iteration budget and starts PC0. R0 stays
constant zero; R30 cannot be written by instructions. The compiler uses R25
for completed candidate updates. The iteration budget is tested by programmed
BR_GE; the independent watchdog counts instruction retirements and rejects a
next fetch once the selected limit is exhausted. External service stalls do
not consume retirements and are bounded by the simulation/host timeout policy.

All valid/ready outputs are suppressed during synchronous active-high reset
or cancel. Reset clears image validity, RF/control state and pending completion.
Cancel aborts the run and pending done/service handshakes, retaining a previously
complete image. Cancelling an incomplete image load leaves it invalid. The
top must broadcast the same cancellation epoch to kernel/scalar services and
discard their old responses. Operation tags increment only after a validated
service completion, starting at start_tag; done preserves the original job tag.

## Instruction validation and arithmetic

Runtime validation rejects unknown kinds/kernels/length modes, reserved or
unused per-kind fields, illegal register destinations, conflicting scalar/flag
writes and invalid immediate bits. No malformed instruction reaches a service.
Each fetch registers its word before execution. The instruction and operands
remain unchanged through request stalls and while awaiting its response.

KERNEL dispatches the selected generic opcode0..10 using the kernel ABI. A
vector result does not write an RF data register; ENERGY/SCALAR_MUL/
SCALAR_ENERGY require a nonzero writable scalar destination. Optional nonzero
flag_s receives response nonzero. Scalar parameters used by kernels must fit
S27; normalization shift must be0..63. Positive energy responses must fit
nonnegative signed64, and scalar multiplication responses must fit signed27.

DIV passes signed64 RF values with source_frac0 to the actual scalar leaf;
SQRT passes signed64 energy with source_frac44. Both request S27F22 fmt1.
Every response checks job/tag/fmt and service fault before writing RF. SQRT
also rejects a negative supposedly successful result. Numerical errors never
produce a success or a clipped RF value.

SET/MOV copy signed64 bits. NEG requires an S27 input and rejects negation of
the S27 minimum. RECIP_PREP requires a positive S27 norm and writes
`1 << bit_length(norm)` plus its exponent to separate RF destinations.
INC increments a nonnegative signed64 counter with overflow detection. These
are scalar bookkeeping operations, not duplicate vector multipliers. All
vector/scalar products remain generic PE kernels. Generic conditional branch
instructions use signed64 comparisons; target is an 8-bit PC. Fallthrough
from PC255 faults instead of wrapping silently.

Faults: NONE0, LOAD1, MODE2, PROGRAM3, NUMERIC4, IDENTITY5, KERNEL6, SCALAR7,
WATCHDOG8, CERTIFICATE9, NOT_CONVERGED10. Failed operations stop the run and
hold done until accepted. They do not approve candidate publication.

## Stored-candidate certificate and trace

CERT evaluates `normal_energy * 10000000000 <= rhs_energy` in a 98-bit
sequential constant shift/add accumulator over 34 cycles. Both energies must
be nonnegative signed64. It does not use a general scalar multiplier or a
rounded/overflowing narrow product. The Boolean result is written to a
separate destination register and latched as certificate approval.

Approval requires the preceding generic dataflow chain: NARROW_X to a candidate
slot, GEMV forward reading that slot, SUB subtracting that prediction, GEMV
transpose reading that residual, ENERGY reading that normal vector, then CERT
reading the returned energy register. A different intervening kernel breaks
the chain. Scalar/arithmetic RF mutations clear approval and the chain;
ordinary branches do not. CERT's result cannot alias either energy operand.
SUCCESS additionally requires the latched approval; setting an RF Boolean
cannot forge success. The trusted host remains responsible for loading the
intended model-validated program: these generic checks are not a proof that
an arbitrary host program computes the intended measurement residual.

`done_candidate_slot` identifies the original NARROW_X destination whose
certificate passed, even when subsequent kernels changed their destinations.
The top must drain this slot rather than infer a fixed slot number. The LSQR
compiler currently selects XC10. Done snapshots remain stable under stall;
normal/rhs energy outputs expose RF21/RF19 by the published solver allocation.
Done means certificate-approved candidate ready, not an atomic job commit.
The result controller still validates/drains X and requires explicit approval.

`trace_retire` pulses with `trace_pc` and `trace_word` identifying the same
retired instruction, independently of the internal next-fetch PC. Faulted
instructions do not claim a successful retirement. The permanent TB checks
each pulse against the loaded program word.

## Verification boundary

`py -3 -m unittest verification.v4.test_solver_rtl -v` compiles the permanent
`verification/v4/solver/tb_solver_sequencer.sv` with real scalar_service using
Vivado xvlog/xelab/xsim only. A separate integer-list interpreter calculates
generic kernel responses and expected request operands; the TB compares them,
inserts stalls and returns those results. Successful and bounded nonconvergent
LSQR cases compare raw stored X, iteration counts and both energies to the
unchanged `IntegerLSQRKernels` at tolerance1e-5. Fault tests include illegal
instructions/load streams, watchdog, certificate provenance, service identity,
negative SQRT, cancellation and held done. A certificate for another narrowed
slot and stale approval after an intervening SET are tested explicitly.

This focused test executes the real program PC and scalar RTL but models kernel
responses. Only the separate top integration with actual kernel_engine/operator
memory can establish end-to-end RTL LSQR correctness. No synthesis, implementation,
board or complete recovery-program qualification follows from this leaf gate.
