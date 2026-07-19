# Fixed-point reciprocal Newton-Raphson evaluation

## Decision

Keep the current four-bit-per-clock restoring divider.  A fixed-point
Newton-Raphson reciprocal that reuses the existing four-row 64x64 multiplier
is slower on the measured workload and is not bit-exact until it performs more
multiplies than the 16-cycle divider can amortize.

## Measured divider opportunity

The final K=8 profiler reports 5,248 `S_DIV_STEP` cycles across all eight
algorithms, or 0.62% of the 850,747-cycle suite.  At 16 clocks per divide this
is 328 divide operations.  LDLT pivot reciprocals account for 4,736 cycles
(296 divides); MP accounts for the remaining 512 cycles (32 divides).

Even an idealized four-cycle replacement could save at most 3,936 suite
cycles, or 0.46%, before control overhead.  This is the upper bound, not the
result achievable with the shared multiplier.

## Sample and fixed-point model

The RTL was simulated with temporary divider tracing to collect:

- 120 LDLT pivots from representative CoSaMP M=64, N=256, K=8 runs.  Their
  numerator is `2^48`; observed positive denominators span approximately
  11.0e9 to 17.2e9.
- 32 signed MP divisions.  Their denominator is the constant `2^18` for this
  configuration.

`scripts/evaluate_nr_reciprocal.py` parses those local XSim logs and compares
the RTL's nearest/ties-up signed quotient with a Q2.62 reciprocal model.  The
model normalizes the denominator to `[1,2)`, uses the linear seed
`24/17 - (8/17)d`, and applies rounded Newton-Raphson iterations.

| NR iterations | 64x64 multiplies | Shared-multiplier minimum | Mismatches / 152 | Maximum error |
|---:|---:|---:|---:|---:|
| 0 | 1 | 6 cycles | 152 | 3,269 LSB |
| 1 | 3 | 18 cycles | 150 | 192 LSB |
| 2 | 5 | 30 cycles | 21 | 1 LSB |
| 3 | 7 | 42 cycles | 11 | 1 LSB |
| 4 | 9 | 54 cycles | 0 | 0 LSB |

Three iterations are sufficient for the sampled LDLT pivots, but still need
seven dependent multiplies and at least 42 controller cycles.  Four iterations
are required when the signed MP samples are included, raising the minimum to
54 cycles.  The measured shared wide multiply occupies one issue clock plus
five wait clocks; normalization, seed generation, and state transitions are
not included in those lower bounds.

The serial reciprocal dependency also prevents batching four independent
pivots over the four PE rows: pivot `k+1` cannot be formed before pivot `k` has
updated the border.  A dedicated low-latency multiplier could reduce latency,
but would add DSP/LUT cost for a theoretical suite gain below 0.5% and would no
longer satisfy the intended resource/cycle balance.

## Reproducibility

Run the model against the locally generated traces:

```powershell
python scripts\evaluate_nr_reciprocal.py `
  runs\opt2\nr_div_samples_cosamp\xsim.log `
  runs\opt2\nr_div_samples_mp\xsim.log
```

The detailed output is recorded in
`analysis/nr_reciprocal_evaluation.csv`.  The temporary trace statements were
removed from the production RTL after collecting the samples.

## Follow-up outside the LS critical path

The measured MP denominator is a power of two, so that specific operation can
be replaced by a signed rounded shift without a reciprocal unit.  It can save
up to 512 state cycles in this suite, but it does not accelerate the LDLT
solver and should be treated as a separate MP-only optimization.
