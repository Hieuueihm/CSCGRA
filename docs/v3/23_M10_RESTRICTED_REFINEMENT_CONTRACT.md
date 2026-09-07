# M10 unified restricted-refinement contract

Status: **COMPLETE**. Contract, resident context layout, property replay and
default-Vivado integration OOC are closed; M11 gate is open.

## Scope

M10 adds two control sidecars without adding a solver PC:

- `normal_residual_checker`: tagged post-D18 integer comparison;
- `restricted_refinement_state`: cadence, restart, commit/rollback, telemetry.

Phi forward/transpose, vector arithmetic, scalar divide, and scratchpad remain
owned by M5/M8. Support mutation remains owned by M9b.

## Locked numeric contract

```text
strict_normal_residual_shift = 14
reliable_recompute_interval = 8
cheap_certificate_guard_bits = 0
relative_limit = ceil(gamma_reference / 2^(2*normal_residual_shift))
quant_floor = max(2^14, active_support_count * 2^11)
certificate_limit = max(relative_limit, quant_floor)
certificate_pass = normal_residual_sq <= certificate_limit
```

`delta <= 0`, `gamma <= 0`, saturation, an invalid profile/tag, or support
count above 96 fails closed. Thresholds are not synthesis parameters.

## Transaction protocol

1. Control sends `begin`: profile, support count, profile iteration limit,
   maximum iterations, shift, `gamma_reference`, event tag.
2. Each completed recurrence sends `step`: `gamma`, `gamma_new`, `delta`, and
   numeric fault flags.
3. State requests a certificate when the cheap threshold hits, eight steps
   elapse, a profile boundary arrives, or the strict final boundary arrives.
4. Datapath recomputes true residual/transpose post-D18 and submits the result
   to `normal_residual_checker`.
5. Checker returns a tagged pass/fail. Strict commit requires pass. Failure
   restarts or rolls back at the terminal boundary.

Valid payload remains stable while ready is low. Only one certificate may be
outstanding per transaction.

The executable resource protocol uses separate issue and wait contexts; no
context sets both `wait_for_ready` and `wait_for_result`. RF0 holds
`gamma_reference`, RF1 holds `delta/alpha/gamma_new` on the certificate path.
The continuation tail computes `beta=RF1/RF0` into RF0, updates `p`, then
recomputes `norm(g_new)` into RF0 for the next recurrence. This avoids a third
scalar register. Residual AXPY uses `configuration_id[0]=1` for subtraction.

The resident revision-8 image uses these array entry PCs:

| Routine | Entry PC | Context count |
| --- | ---: | ---: |
| restricted refinement transpose | 30 | 7 |
| restricted refinement initialize | 37 | 7 |
| restricted refinement pre-transpose | 44 | 15 |
| restricted refinement certificate | 59 | 9 |
| restricted refinement continuation | 68 | 12 |

The M10 resident array image ends at PC79 with 80 contexts. M11 extends the
shared library to 85 contexts with the software-owned OMP append/commit segment. Scalar RF and Phi
support cache persist across these phase-launched segments. Explicit
`scalar_state_clear` and `phi_cache_clear` own transaction-boundary cleanup;
`routine_start` does not destroy nested state.

## Profile behavior

- `STRICT_PAPER`: pass commits; failure restarts before the final boundary,
  then rolls back at the final boundary.
- `BALANCED_VARIANT`: boundary failure switches once to strict and restarts.
- `FAST_VARIANT`: fixed-q boundary commits without breakdown or saturation;
  certificate telemetry is still recorded.

Checker/state never mutate support or coefficients. `certificate_fail_pulse`
only requests M9b rollback of proposed state.

## Telemetry

- full checks requested/completed/skipped;
- reliable residual replacements;
- certificate failures;
- committed and rolled-back transactions.

Counters saturate at `2^32-1`. `routine_start` does not clear telemetry.

## Directive policy

Every synthesis and OOC stage uses the default Vivado flow. Do not pass
`-directive` for leaf, integration, dispatcher, N3, M8, or later gates.

## Exit gate

- XSim normal/property pass at S=1, 32, 64, 96;
- ceil rounding, quant-floor dominance, cheap/interval/final triggers pass;
- pass, restart, breakdown, saturation, tag mismatch, abort, stall stability;
- leaf OOC WNS `>= +1.0 ns`;
- dispatcher replay and support rollback pass before capability flip.
