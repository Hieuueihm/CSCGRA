# Factor panels on the shared arrays

Source-qualified Vivado candidate, 2026-09-09. Root plans/reviews; Terra high
implements. The staged candidate passed the focused module gate and 20 matched
active-10 fixed-eight whole programs. Source installation is tracked in
[`factor_panel_promotion_20260909`](../../../reports/v4/factor_panel_promotion_20260909/before_after_manifest.json).
ADMM remains reference-only; PPA, timing, board and production-bit qualification
remain pending.

## Reason for this change

The comparison boundary follows [CYCLE_BASELINE_CONTRACT.md](CYCLE_BASELINE_CONTRACT.md): acceptance is a matched before/after fixed-eight run with identical geometry, raw Phi/Y, precision, policy and actual iteration count.  Existing V2/V3 tables remain historical anchors only; this candidate does not derive a cross-version speedup from them.

The M64/N256/K8 fixed-eight CoSaMP baseline is 431824 cycles. Its six physical
factorizations perform 1500 serial trailing-column updates. The exact seven-
service sequence READ, DOT, RESCALE, scalar MUL, vector MUL, SUB, WRITE takes
207000 service cycles, excluding instruction dispatch. The respective measured
totals are 37500, 39000, 3000, 15000, 42000, 45000 and 25500 cycles.
More factor caching does not eliminate these updates. Existing exact-result
reuse already handles the two repeated supports.

The candidate replaces sufficiently wide trailing updates with generic matrix
panel operations. It preserves the column-wise Householder algorithm and all
rounding boundaries. Narrow tails retain the serial path. Initial threshold:
eight trailing columns, to be selected from measured whole-program results.
Matched final fixed-eight evidence measured CoSaMP at 252,684 cycles for
M64/N256/K8 and 210,512 cycles for M32/N64/K8. Each is a 41.48% reduction
from its paired baseline; raw X, residual, support, status and fixed8
diagnostic quality are exact matches. The comparison is
[`factor_panel_comparison_20260909`](../../../reports/v4/factor_panel_comparison_20260909/factor_panel_comparison_vi.md).

## Operations and numerical contract

Add kernel operations FACTOR_MATVEC=17 and FACTOR_RANK1=18, candidate revision3.
Existing operation16 is SCALAR_TEMPLATE. No existing opcode changes value.

Both operations capture M=`rows`, S=`support_length`, row_start=`aux_length`,
row_count=`length`, col_start=`index`; column_count=S-col_start. Require dense
factor identity, 1<=M<=128, 1<=S<=96, nonempty valid row/column ranges, fmt1,
flags0 and exact key/generation/job/format agreement. Sources are packed:
source A is row_count S27 values; RANK1 source B is column_count S27 values.
Prevalidate/cache every required source block before any factor mutation.

FACTOR_MATVEC returns packed S27 q into the normal kernel scratch/publication
path: q[c]=round22(sum_r factor[row_start+r,col_start+c]*A[r]). Each product is
exact S27xS27; each column uses an ACC64 and deterministic increasing row order.
Retain ACC overflow and terminal S27 range faults. The loaded contexts are 32
ordinary full-S27 MAC lanes, with per-lane terminal rounding (existing mode3).
For valid S27 values and at most128 rows, the absolute sum is bounded by
128*(2^26)^2=2^59, below the signed ACC64 limit. Thus replacing the prior
32-lane partial-sum tree by one row-ordered column accumulator preserves the
exact sum; the final round22 and S27 range check still apply.
Process columns in internal panels of at most32; the command covers the whole
requested trailing column range, including up to96 columns.

The loaded program next performs the existing TEMPLATE SCALE on q with tau.
This is the separately rounded S27 tau*q operation, with existing range checks.

FACTOR_RANK1 updates only the selected private factor rectangle:
factor[r,c] = checked_S27(factor[r,c] - round22(A[r]*B[c])). It returns no public
vector. Multiplication must round/check before subtraction; a fused unrounded
multiply-subtract is forbidden. Internal panels have at most16 columns.
All partial factor writes remain private. On cancel or any operand, fabric,
identity, mask, tag or store fault, invalidate the private factor image. A
subsequent solve must rebuild; no partial result reaches result_store.

## Fabric flow and state ownership

Use exactly the existing two16-PE arrays and existing multipliers. Add an
optional internal `cmd_flow[1:0]` to stream_fabric, enabled by a parameter
CASCADE_ENABLE default0. Flow0 is existing parallel32 behavior. Flow1 is
cascade16 and requires terminal mode0 and loaded low16 MUL/high16 SUB contexts,
mode1, direct A/B selectors. Invalid enabled flow/configuration faults before
execution. Legacy callers with the parameter off ignore an unconnected port.

Cascade input low16 in_a/in_b are the two MUL operands. High16 in_a contains
the original factor values; high16 in_b is unused. Low/high input masks must
match. A bounded FIFO keeps old values/mask/last alongside array0 work. On
array0 output acceptance, array1 receives old value as A and rounded product
as B. An additional bounded metadata queue aligns array0 per-lane faults with
array1 output. A nonzero MUL fault wins over the SUB fault; do not bitwise-OR
numeric fault codes. Final outputs occupy low16; upper data/masks/faults are
zero. Last, output hold, done and abort behavior remain transactional. No
additional multiplier, PE, factor image or public vector memory is introduced.

`factor_panel_service` owns captured operation/ranges, cached V/Q operands,
row-panel scheduling and fabric handshakes, but contains no QR iteration,
support selection, certificate or host algorithm decisions. It uses the same
fabric through a kernel ownership mux. Four bounded row slots may overlap
factor reads, PE execution and write acknowledgements; use counters/credits,
not an unbounded queue. Retain old factor values until cascade admission.

Keep factor_store's existing single read-or-write request port and two response
credits initially; do not add mixed per-port transactions or another store.
factor_service provides an optional exclusive tagged stream access bridge to
its existing private factor_store. Default disable preserves leaf callers.
Only the idle legacy service may grant the panel owner. Check current factor
ownership, shape and live B identity, retain all request/response tags, drain
responses before release, and invalidate on panel failure/cancel. Bank mapping
is (row+column) mod32, address=row*3+floor(column/32). For each row, at most32
contiguous columns are conflict-free. External coordinates remain bounded;
an address within384 alone does not establish a valid M/S coordinate.

The kernel extends its existing adjunct vector-source and candidate interfaces
to the panel service. MATVEC allocates ceil(column_count/32) scratch blocks and
publishes with existing validation/copy semantics; RANK1 allocates no public
output. Panel fabric ownership cannot overlap ordinary kernel fabric commands.
recovery_engine continues to own result_store and full-result publication.

## Compiler and qualification

Change only QR's trailing-column update region. At runtime when trailing width
meets the selected threshold, emit MATVEC -> existing SCALE -> RANK1. Otherwise
emit the original serial column loop. Keep reflector construction, Q^T y,
backsolve, exact support/result caching, certificates, refinements, support
ordering and all outer/termination policies unchanged. Program/context images
must drive the operations after one START; no host-computed QR trajectory.
If policy-derived maximum working support proves that no panel can meet the
threshold, omit the panel branch entirely and retain the old serial image.
Do not use observed signal/support trajectories to make this compile decision.

The VM implements the two generic operations with an independent integer
oracle. The original fixed QR model is unchanged. New package/PC traces may
differ from the baseline; each new RTL trace must match its own loaded VM
program, while X/R/support/status/model trajectory/certificates/numeric events
must match the old mathematical result exactly.

Source-bound Vivado qualification is recorded in
[`factor_panel_rtl_20260909`](../../../reports/v4/factor_panel_rtl_20260909/qualification.json):
PASS13 focused kernel tests covering 155 commands, five legacy factor replays,
and 44 legacy compute replays, and cascade/panel/bridge fault coverage. The final source-clean
fixed-eight runs pass all ten active algorithms at M32/N64/K8 and M64/N256/K8.
The comparison preserves actual program cycles, support sizes, physical
factorization count, logical LS calls, quality and mathematical identity; it
does not equate changed instruction counts with changed algorithm iterations.
Only xvlog/xelab/xsim supplied RTL acceptance evidence. No synth/impl,
resource/timing/fit, board or production bit-lock claim follows.

### Candidate activation

The source-qualified candidate remains explicit opt-in; its source installation
is tracked by the promotion manifest above. For a qualified QR input
specification, export the panel image explicitly:

```
python -X utf8 scripts/v4/export_recovery.py INPUT.json OUTPUT_DIR --qr-profile panel --qr-panel-min-columns 8 --target-kernel-revision 3
```

`reference` and `balanced` remain the compatibility profiles.  `panel` leaves
an OMP or HTP image serial when its policy-derived maximum support cannot
exceed the threshold; its exported metadata records that disabled reason.
