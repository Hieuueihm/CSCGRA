# Scalar arithmetic RTL replay

Run from the repository root:

```
py -3 scripts/v4/run_scalar_rtl.py
py -3 -m unittest verification.v4.test_scalar_rtl -v
```

Requires Python with NumPy (the LSQR model dependency), Vivado xvlog/xelab/xsim. The evidence runner uses only the actual Vivado simulator tools. Set VIVADO_BIN to the Vivado bin directory; the default is C:/Xilinx/Vivado/2018.1/bin. It checks generated definitions and hashes source inputs before/after the run. It never calls synthesis or implementation.

`tb_scalar_service.sv` is a permanent file-driven bench. Python emits request/control pin vectors, runs real Vivado xsim RTL, and compares req_ready plus all response signals before and after every rising edge. The first pre-reset snapshot is intentionally excluded because registers have not yet been reset. The integer oracle is direct arbitrary-precision rational nearest rounding/isqrt, independent of the RTL bit-iteration algorithm.

Tests cover signed64 minima and denominator signs, exact positive/negative half ties and adjacent values, S27 result limits, full-width random ratios and energies, perfect squares and rounding thresholds, zero denominators, negative energies, unsupported opcode/format/fraction and fault precedence. Busy and stalled-response request pins change to catch missing snapshots. Reset/cancel is injected at every iterative/finalize position and into pending responses, simultaneously with valid/ready; fresh operations verify recovery and absence of ghost completions. Timing is checked on every edge.

Two actual LSQR numerical solves are instrumented in a test subclass (the model source is unchanged). The resulting norm, normalized reciprocal, Givens c/s, step and direction calls must match the independent oracle and are replayed through RTL. Operands, metadata, results and names are captured in `reports/v4/scalar_rtl_correctness.json`. These are scalar-call traces, not LSQR RTL execution.

Set `V4_SCALAR_KEEP=1` to retain generated replay vectors, simulation and traces under `work/v4_scalar_*`. Normal runs record input/trace SHA256 hashes and remove temporary work directories. The standalone evidence excludes full V4 integration, scalar RF and LSQR execution, and does not establish timing/resource results.
