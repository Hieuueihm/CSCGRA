# QR robustness-mode study (no RTL implementation)

Date: 2026-08-04

## Decision

Keep the signed-off Cholesky LDLT solver as the default and cached LS path.
Do not replace it with QR for normal operation.  If robustness testing later
shows real fixed-point failures, add QR as an explicit fallback mode that
restarts the LS solve from `Phi_S` and `y`; never reinterpret an LDLT cache as
a QR factor.

No QR RTL, opcode, or default control behavior is introduced by this study.

## Why QR is present only as a robustness option

The current solver forms the regularized normal matrix and stores its lower
triangle in the eight-bank, 56-bit `ls_matrix_service`.  The controller then
uses 64-bit D/inverse-D state and tagged 64x64 limb multiplies for LDLT.  This
is efficient for `MAX_K=16`, especially because exact/prefix factor reuse can
avoid refactorization.

The numerical weakness is inherent to normal equations: the effective
condition number is squared.  In fixed point, nearly dependent selected
columns can therefore produce a very small, zero, or negative D pivot even
when the original rectangular system still has a useful least-squares
solution.  QR acts directly on the rectangular selected matrix and is the
appropriate comparison for those cases, but it requires substantially more
data movement plus norm/rotation arithmetic and cannot use the existing LDLT
factor cache.

## Candidate QR mappings

| Method | Robustness | Fit to strict PE0 ingress | Cost/risk | Decision |
| --- | --- | --- | --- | --- |
| Givens rotations | Strong; works directly on selected columns | Best fit. Rotation tokens can enter PE0 and advance through four registered row stages | Needs vectoring/rotation (CORDIC or reciprocal-square-root), rotation metadata, and triangular storage | Preferred QR prototype |
| Householder | Strongest conventional choice for batch QR | Poorer fit. Column norms and reflector application require reductions, buffering, and repeated vector broadcasts | High controller/memory pressure; difficult to keep all four PE rows continuously useful | Do not start here |
| Modified Gram-Schmidt | Better than classical Gram-Schmidt but weaker than Givens/Householder | Streamable, but reorthogonalization adds another global pass | Simpler arithmetic, yet robustness benefit may be insufficient for the extra cycles | Reference model only |

For a Givens implementation, every large operation must obey the same
provenance rule as the signed-off datapaths:

```text
PE0 ingress: row pair + column/rank tag + rotation phase
  -> PE1: registered continuation / next rotation owner
  -> PE2: registered continuation / next rotation owner
  -> PE3: final triangular/RHS retirement in tag order
```

The four rows should own fixed rotation stages or rank groups; lower rows must
never consume controller operands directly.  A transaction scoreboard is
required if multiple rotations are in flight.

## Expected performance

For `m=64, k=16`, triangularization requires 888 potential subdiagonal Givens
rotations before accounting for applying each rotation to the remaining
columns and RHS.  A bit-serial 16-step CORDIC would therefore be much slower
than the current LDLT path unless rotations are deeply pipelined across all
four rows.  Householder has attractive arithmetic counts in software but its
norm reductions and reflector broadcasts conflict with the strict single-
ingress mesh.

Consequently QR is unlikely to beat the current `1,771,732`-cycle full sweep
in the normal, well-conditioned cases.  Its value is recovering cases where
LDLT loses accuracy or rejects a pivot, not lowering the default cycle count.

## Fallback trigger contract

An automatic fallback must not be enabled until thresholds are derived from
quantized tests.  Candidate diagnostics are:

- non-positive D pivot after regularization;
- `abs(D[k])` below a scale-relative threshold derived from the largest prior
  diagonal, not a hard-coded absolute constant;
- coefficient saturation or residual stagnation after the LDLT solve;
- an explicit software robustness flag for controlled experiments.

On a trigger, the controller must discard the partial factorization, rebuild
the selected rectangular `Phi_S` stream from the support/seed configuration,
and start QR from PE0.  LDLT exact/prefix reuse remains disabled for that QR
request.  A future QR cache needs its own format identifier, support signature,
dimension, seed, scale, and numerical-mode metadata.

## Required evidence before QR RTL

1. Add a high-precision and bit-accurate QR golden model without changing the
   current LDLT goldens.
2. Create adversarial selected-column tests: repeated/highly correlated
   columns, dynamic-range extremes, small pivots, noisy RHS, and K=16.
3. Show cases where QR materially improves coefficient/residual correctness
   over LDLT; ordinary K-sweep parity alone is not justification.
4. Prototype a four-row tagged Givens/CORDIC service with robustness mode off
   by default.
5. Require default-mode cycles to remain unchanged, full regression to stay
   `348 PASS / 0 FAIL`, WNS to remain positive at 100 MHz, and resource growth
   to be reported separately for the optional mode.

Until this evidence exists, QR remains research-only and LDLT remains the
signed-off solver.
