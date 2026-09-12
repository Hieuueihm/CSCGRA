# Loadable service program and arithmetic contract

## Feature4 QR append qualification

Profile `reuse` adds generic FACTOR_EXTEND(op19) under the existing program
revision2. OMP/GOMP prove an exact ordered support prefix and immutable Phi/Y;
BUILD_B advances the B generation, and EXTEND imports only new columns at the
next generation. Shrink/reorder/mismatch uses INIT. Corrections still apply
all reflectors and the stored-X certificate is unchanged. The generic backend
checks shape/identity; it does not infer support membership from dimensions.

[QR reuse contract](QR_REUSE.md) records the inert loaded template, generation,
mask and publication rules. [The paired XSim report](../../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md)
qualifies all20 fixed8 cases. Later resident/panel-chain/scalar-patch work is
separate; CPU AXI and board timing remain unimplemented/unqualified.

The revision-two interface is defined by `config/v4_program_interface.json` and its generated `program_interface.vh`. It is distinct from the legacy LSQR service program and revision-one stream image. `program_sequencer` contains one 1024-word, 128-bit program store, one 32-by-64-bit scalar register file, 32 vector descriptors, up to 16 loaded 32-PE templates, 1024 constants, one PC, and a four-entry return stack. It contains no algorithm-specific recovery state machine.

An idle verified load begins by invalidating the previous image. The ordered package contains program words, each template's descriptor/binding metadata followed by 32 contexts, vector base/capacity descriptors, then constants. Only the final package item asserts `last`. A complete valid load publishes the image atomically. Reset clears it. Cancel preserves a previously complete image, invalidates an incomplete load, and silently flushes the running command and held completion. Load, run, and held completion cannot overlap.

R0 is constant zero. Instructions validate their reserved and unused fields, register destinations, branch targets, stack use, and service parameters. ADD64/SUB64 use a 65-bit signed intermediate and fault on overflow. Scalar parameters consumed as S27 must fit that format. The watchdog bounds retired instructions. Kernel, arithmetic, and builder responses must match the captured job, operation tag, and format. Commands and completion remain stable until accepted; reset and cancel suppress visible valid/ready handshakes.

CERT compares two nonnegative RF energies multiplied by unsigned 64-bit loaded constants. Two 128-bit shift/add accumulators execute the exact comparison over 64 steps. No scalar multiplier outside the shared PE array is introduced. RESCALE is instruction kind 24 and selects arithmetic opcode 2 with input fraction 44. Scalar products remain loaded MAC operations on that same PE array.

| Arithmetic operation | Accepted input interpretation | Request-to-response latency |
|---|---|---:|
| DIV, opcode 0 | signed64 numerator/denominator; source fraction 0 or signed -10 | 28 cycles; early mode/zero/guaranteed-range fault 1 |
| SQRT, opcode 1 | nonnegative signed64 raw energy, fraction 44 | 33 cycles; mode/negative fault 1 |
| RESCALE, opcode 2 | signed64 fraction44 to signed S27F22 | 1 cycle |

All rounding is nearest, halfway away from zero. DIV performs an exact high-part overflow test followed by 27 restoring quotient rounds. RESCALE rounds the unsigned magnitude by 22 bits and then applies the sign, including signed-minimum and rounded-overflow cases. Overflow is an inert zero-data range fault, never clipping. Opcode 3 and unsupported fractions fault. SQRT/RESCALE ignore operand B. Responses occupy the leaf until accepted; with continuously ready output the minimum initiation intervals are the listed latency plus two cycles. There is one outstanding operation and no scalar RF inside `arithmetic_service`. The older `scalar_service` remains unchanged.

SLICE and REPLACE_RANGE transport unaligned pool ranges without arithmetic. Both validate full source capacity N and widened `start + L <= N`; `start=N` is legal only for L=0. SLICE requires destination capacity L and ignores the auxiliary descriptor capacity. REPLACE_RANGE requires packed auxiliary capacity L and destination capacity N. Their support metadata, K and flags must be zero. Other adjunct operations preserve their existing packed/dense capacity distinctions.

Held completion includes resolved output, residual and support bases/capacities, so the top does not duplicate the descriptor store. Defaults refer to descriptors 0/1/2 where loaded, otherwise descriptor 0. HALT_STATUS validates explicit handles. FAIL is an intentional algorithm-status termination with no controller fault; the compiler must maintain the last accepted candidate and the top must apply its publication policy. An arbitrary trusted loaded program reaching HALT is not hardware proof of a QR certificate.

`compiler/v4/recovery_emit.py` emits complete MP, GP, IHT, FISTA, PDHG and shifted-CG ADMM candidate programs. Greedy storage is X24F20; proximal storage is D18F14, both reembedded into S27F22. Proximal output is dense N with support count zero. `compiler/v4/greedy_qr_emit.py` links the five restricted-solve outer programs to `compiler/v4/qr_program.py`, a loaded Householder QR subroutine. No LSQR fallback is linked. Generic instruction interpretation has been compared with the fixed-point numerical models; that is distinct from real-service RTL execution.

GEMV mapping defaults to a per-operation shape/direction cost estimate, with explicit R1/R4 overrides for ablations. The estimate enumerates the feeder's striped tail frames and active Phi passes and includes an approximate R4 fold cost. Package metadata records both alternatives. It is not a measured whole-program latency or a production PPA decision.

RTL reproduction uses the bundled Python with `scripts/v4/run_rtl.py` and Vivado xsim only (`VIVADO_BIN` may select the installed Vivado bin directory). Focused RESCALE/range evidence is `reports/v4/rescale_range_control_rtl.json`. No synthesis, implementation timing, board, or full eleven-algorithm qualification follows from this leaf/controller contract.


FACTOR_INIT/READ/WRITE use the same kernel command channel and published dense B identity. INIT requires length M, zero range/index/flags, and S in 1..96. READ/WRITE require a nonempty range of at most 128 words, widened coordinate bounds, and only the actually consumed packed source or produced destination capacity. Their auxiliary-length RF operand is a coordinate start, not an auxiliary-vector capacity. See FACTOR_SERVICE.md for retained-image and fault rules.

The QR subroutine consumes S in R28, preserves R16..R31 except R25, and clobbers R1..R15. It returns R15=1 only after the exact stored-X24 normal certificate; R25 counts the initial solve and completed correction solves. The caller supplies output and optional certificate-residual descriptors. Ten scratch descriptors use 32 public blocks; factors reside in the separate retained store. Correction limit is explicit 0..2, with 2 the calibrated candidate limit. The certificate tolerance is the caller policy, represented by exact unsigned64 constants; unrepresentable constants reject export. Failure transfers to caller labels, preserving its last accepted result. Generic LS_NOT_CONVERGED corresponds to the numerical model's qr_not_converged; NUMERIC_FAULT covers rank failure. Neither status implies a legacy LSQR execution.

The generic instruction interpreter tests complete five-algorithm schedules against the separate Householder model, including zero measurement, tail-zero reflectors, explicit correction bounds and failed-certificate preservation. These are numerical schedule tests, not real-service RTL recovery evidence. The factor controller mock-service test independently checks normalized request fields and capacities.
