# Shared scalar arithmetic leaf candidate

`rtl/v4/services/scalar_service.sv` implements one tagged, one-outstanding DIV/SQRT service. It owns arithmetic working registers and a held response. Scalar RF, LSQR recurrence, control256 decoding, scalar operand selection and context integration are not implemented by this leaf. The catalog's eventual scalar-service ownership is broader than this implemented subset.

The machine-readable source is `config/v4_scalar_interface.json`; `scripts/v4/generate_scalar_interface.py` generates `rtl/v4/include/scalar_interface.vh`. The generator rejects changes to the bounded profile and checks the shared PE profile and Phi tag widths. This is an explicitly selected build candidate, not a production format freeze or an arbitrary fixed-point engine.

## Request and response

All state uses rising `clk`, synchronous active-high `rst`. A request is accepted on an edge with `req_valid && req_ready`. Inputs are `req_op` (2 bits), signed64 `req_a/req_b`, `req_source_frac` (8 bits), and tags `req_job` (16), `req_tag` (16), `req_fmt` (8). A producer holds a pending request stable until acceptance. Later input changes cannot affect an accepted operation.

`req_fmt=1` selects precisely the scalar S27F22 candidate in the JSON config; this is a local arithmetic-leaf format identifier, not a claim that an existing packed context format id has this meaning. Every other format id is rejected. `req_source_frac` has the following operation-specific interpretation:

| Operation | Opcode | Inputs | Required source frac | Raw result |
|---|---:|---|---:|---|
| DIV | 0 | signed64 numerator a, signed64 denominator b | 0: numerator frac minus denominator frac | nearest(a * 2^22 / b), ties away from zero |
| SQRT | 1 | signed64 nonnegative energy a; b ignored | 44: fractional bits of the energy itself | nearest(sqrt(a)), half up |

LSQR `_div` currently uses source_frac=0, including its bounded normalized reciprocal numerator `2**bit_length(norm)` (which can be 2^27). `_sqrt_energy(energy,22)` passes raw energy with 44 fractional bits; the adapter request therefore has req_source_frac=44, not the numerical helper's vector_frac=22. Square root with another vector fraction or scalar output fraction is unsupported. `models/v4/fixed.py::Arithmetic.ratio` and `models/v4/lsqr.py` define the integer rounding reference. No existing numerical models are modified.

Responses have `rsp_valid/rsp_ready`, signed27 `rsp_data`, a 3-bit `rsp_fault`, and all three echoed tags. They remain stable until a retirement edge with `rsp_valid && rsp_ready`, or reset/cancel. Data on every fault response is zero; consumers must gate successful writes on fault=NONE. There is no architectural register write or result commit inside this leaf. Tags can be visible while busy but have response meaning only when valid. Retiring clears the output payload. There is no same-edge request replacement when retiring a response.

| Fault | Code | Condition |
|---|---:|---|
| NONE | 0 | Result representable in signed27 |
| MODE | 1 | Unsupported opcode, format or source frac |
| ZERO | 2 | DIV denominator zero |
| NEGATIVE | 3 | SQRT energy negative |
| RANGE | 4 | Rounded result outside [-2^26,2^26-1] |

MODE takes precedence over operand-domain faults. Range is checked after rounding, including asymmetric signed limits. The numerical model clips and records saturation; this leaf instead returns RANGE and inert zero. These agree on successful values and on rejecting a failed numerical operation, not on diagnostic clipped payloads.

## Datapath and timing

DIV converts each signed64 input to an unsigned64 magnitude, preserving abs(-2^63)=2^63. It processes the 86-bit scaled numerator with one restoring divide bit per cycle, a 65-bit remainder and unsigned64 denominator. It computes all quotient bits, rounds the magnitude when twice the remainder is at least the denominator, then checks the full 87-bit rounded magnitude against the sign-dependent range before applying the sign. A large intermediate quotient cannot silently wrap into a valid result.

SQRT processes two radicand bits per cycle for 32 cycles with restoring square-root subtraction. The resulting floor root q and remainder r satisfy energy=q*q+r. For integer energy, nearest half-up rounds upward exactly when r>q: the midpoint inequality is 4*r>=4*q+1. Integer energy cannot land exactly on a half-integer root midpoint. A 33-bit rounded root is range-checked before narrowing.

There are no combinational divide/modulo, floating-point, real, square-root system functions or multiplier operators in the RTL datapath. The two algorithms share the request/response service and cannot execute concurrently; this does not claim a single physical adder, inferred implementation resources or post-route timing.

Let acceptance be edge t. Latency below means rsp_valid becomes high after edge t+L. With rsp_ready continuously high the response retires at t+L+1 and the next request can be accepted at t+L+2. The module never accepts a request on its response-retirement edge.

| Path | Iterations | L | Minimum initiation interval |
|---|---:|---:|---:|
| DIV, including range fault | 86 | 87 | 89 |
| SQRT, including range fault | 32 | 33 | 35 |
| MODE/ZERO/NEGATIVE | 0 | 1 | 3 |

The finalize cycle performs rounding and range checking. Output backpressure extends the initiation interval without changing arithmetic latency. Input readiness is low while working, while a response is pending, and whenever rst/cancel is asserted. Reset or cancel takes priority over both handshakes and computation: on that edge it flushes working state and any response, clears payload/tags, and emits no completion. If rst/cancel is deasserted afterward, a new request may be accepted on the following edge. Both visible req_ready and rsp_valid are combinationally suppressed while rst/cancel is asserted, preventing a consumer from observing a handshake before the synchronous flush edge. Working registers and payload clear synchronously on that edge.

## Verification and boundary

Permanent TB and tests are described in `verification/v4/scalar/README.md`. The independent Python oracle computes direct arbitrary-integer rational division and math.isqrt midpoint comparisons; it does not mirror the iterative RTL. A cycle model checks every response field and ready/valid before and after edges, including precise timing, reset/cancel at every iteration and held-output stability. Two successful numerical LSQR solves supply real scalar-call operands/results, recorded in the evidence JSON and replayed through the same RTL.

Run `py -3 scripts/v4/run_scalar_rtl.py` for source-stable standalone evidence, generated definition checks and actual Vivado xvlog/xelab/xsim compile, elaboration and simulation. See `reports/v4/SCALAR_RTL_CORRECTNESS.md` and its JSON for actual results/hashes. This runner does not replace the broader V4 regression gate. No synthesis or implementation is performed, and no full LSQR or scalar RF RTL qualification follows from these leaf tests.
