# Canonical RTL migration plan

This note is the gate between the current RTL-compatible sign-off and a
textbook/canonical sign-off.  The active regression uses the independent
fixed-point canonical GP reference. `verification/v2/run1/k_sweep_golden_mu3.vh`
is retained only as a legacy baseline for algorithms that have not migrated.
CoSaMP/SP K16 remain intentionally deferred because that capacity is not
required.

## Baseline captured before changing RTL

Vivado 2018.1, `rtl/v2`, `tb_run1_k_sweep`, case 0 `(M,N,K)=(64,256,16)`:

| Algorithm | RTL operation sequence | Result |
| --- | --- | --- |
| GP | `OP_CORR_UPDATE` (dense `x += A^T r >> mu_shift`), then top-K/prune and residual | 56,977 cycles, 6 PASS / 0 FAIL checks |
| CoSaMP | 2K proxy/merge through the candidate service, capped at 16 entries, LS dimension 16 | K16 is intentionally skipped |
| SP | K proxy/merge through the same 16-entry service, LS dimension 16 | K16 is intentionally skipped |

The baseline run is recorded in `logs/sim/v2/canonical_gp_baseline/` and must
not be interpreted as a canonical GP result.  The positive-WNS sign-off
checkpoint remains unchanged.

The initial pre-migration canonical differential run (`-CanonicalGolden`) on
the same case completed in 56,977 cycles but produced `6 PASS / 17 FAIL`
checks, with mismatches at dense indices 38, 42, 74, 82, 84, 87, 91, and 107.
That result is retained as the baseline showing why the old RTL path could
not be relabeled as canonical GP.

## Required GP change

The canonical reference in `canonical_algorithms.py` performs, per iteration,
and `canonical_fixed.py` carries the same steps into the signed-24-bit Q16
numerical contract:

1. correlation `g = A^T r`;
2. append the best new atom to the support;
3. restrict the direction to the active support, `d_S = g_S`;
4. stream `c = A d` through the four PE rows, with every token entering PE0;
5. accumulate `alpha = (r^T c)/(c^T c)` in registered scalar stages;
6. stream `x <- x + alpha*d` and update `r`.

The historical `OP_GRAD_STEP`/`OP_CORR_UPDATE` path does not provide steps 3--5:
it updates the full vector with a fixed right shift and prunes afterwards.
Changing only the opcode name or the golden values would therefore be
incorrect.  The implementation is now provided by separate
`OP_GP_PROJECT`/`OP_GP_UPDATE` operations, selected only by `TB_CANONICAL_GP`;
the existing hardware path remains reproducible.

The design must preserve:

- PE0-only ingress and registered PE0 -> PE1 -> PE2 -> PE3 propagation;
- participation of all four PE rows for `A*d`, `r^T c`, and `c^T c`;
- one active LS request (the GP mode does not use LS, but must not overlap an
  existing LS transaction);
- a registered boundary before scalar completion feedback; and
- no new wide arithmetic on the completion edge.

The canonical golden is generated for all algorithms by
`models/golden/generate_canonical_k_sweep.py` from `canonical_fixed.py`, not
from RTL output or `generate_k_sweep_golden.py`. The canonical GP sweep covers
all eight configured cases and reports 48/48 checks PASS with zero `X_MISM`
records. Cases 0--7 complete in 75,297;
38,369; 20,129; 15,489; 8,209; 4,561; 3,785; and 2,125 cycles.

## Abstract RTL checkpoint

Before changing additional RTL, `models/golden/abstract_rtl.py` provides a
phase-level controller model driven only by the frozen fixed canonical source.
`run_abstract_rtl.py --check` verifies all eight algorithms across all eight
configured cases and records phase payload digests in
`abstract_rtl_trace_manifest.json`. The intended migration order is canonical
fixed state → abstract phase state → real PE/controller state. A real RTL
mismatch is fixed in RTL (or explicitly documented as a hardware variant); it
is never hidden by changing the canonical golden.

OOC synthesis `canonical_gp_synth1` reports WNS `+0.454 ns`, 129,816 LUTs,
53,610 FFs, 24 BRAM36, and 77 DSP48.  Relative to the latest post-update-X
GP checkpoint this is +16,765 LUT, +2,532 FF, no BRAM delta, and +6 DSP48.
The timing gate passes, but the resource delta is why this mode remains opt-in
until an explicit area trade-off is accepted.

## Deferred CoSaMP/SP K16 change

The canonical algorithms do not impose the current 16-entry merge limit.
For K16, CoSaMP can require a union of up to `3K = 48` atoms and SP can
require up to `2K = 32` atoms before pruning.  The current RTL has both:

- a 16-entry candidate/support capacity in `support_set_service.vh`; and
- `MAX_K=16` RHS/Gram/factor memories and LS dimensions in
  `sparse_loop_controller.v` and `ls_matrix_service.v`.

Therefore, changing only the candidate RAM depth cannot make K16 canonical.
The capacity extension must be an explicitly measured architecture variant
(support RAM, candidate metadata, LS matrix/factor storage, address widths,
and controller counters).  It must be evaluated separately for resource,
cycle, and WNS impact before it can replace the current sign-off.

## Sign-off gates for switching the active GP golden

The canonical include may replace the active include only after all gates pass:

1. dedicated canonical-GP RTL testbench passes all eight cases and K values;
2. fixed-point tolerance and support checks are documented against the
   canonical reference;
3. full regression has zero functional failures;
4. WNS remains at least `+0.2 ns` and no DSP/BRAM increase is accepted without
   an explicit trade-off; and
5. the active golden manifest/hash is regenerated and reviewed.

The default GP sign-off now calls GP the **fixed-point canonical RTL path**.
The dense-gradient implementation is available only as a legacy baseline;
CoSaMP/SP K16 remain hardware variants and are not part of this migration.

The full `-CanonicalAll` audit confirms that OMP, IHT, HTP, SP, GP, gOMP, and
MP match the canonical include for all valid configured cases. CoSaMP remains
non-canonical in case 1 (10 mismatches) and case 3 (16 mismatches); K16
CoSaMP/SP are skipped by design because of the 16-entry support capacity.
