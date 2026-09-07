# N=1024, K=32 exact sparse-workspace architecture

## Decision

Do not scale the current multi-read register/LUTRAM arrays by changing only
`SPARSE_MAX_N` and `SPARSE_MAX_K`. Use separate architectural limits:

- `INDEX_W = 10`: indices 0 through 1023;
- `SIZE_W = 11`: counts 0 through 1024;
- `K_SOL_MAX = 32`: final sparse solution;
- `K_CAND_MAX = 64`: CoSaMP candidate set;
- `K_WORK_MAX = 96`: maximum exact least-squares union;
- `WORK_AW = 7`: support/LS row and column address width.

SP uses at most `2*K = 64` working columns. CoSaMP selects `2*K` proxy
indices and unions them with the previous `K`, so its least-squares problem
uses at most `3*K = 96` columns. Pruning to K occurs only after that solve.

## Support workspace

Replace the two fixed paths and the 32 individual support outputs with:

1. a 32-entry solution list;
2. one 96-entry working list;
3. a 1024-bit membership bitmap banked by `index[2:0]`;
4. addressed read ports with valid/ready handshakes.

Seed the working list with the old solution, then append top-K candidates only
when the membership bit is clear. CoSaMP streams 64 candidates and SP streams
32 candidates into the same union builder. No separate 64-entry candidate copy
is required. LS does not require sorted indices; sort only the final 32 entries
if the external result contract requires canonical order.

The eight bitmap banks are 128 bits each. Eight consecutive correlation lanes
therefore perform independent membership reads without an all-entry comparator
scan. This removes the current `8 * MAX_CANDIDATE` comparison cone.

## Optional direct-LS workspace

For the deterministic direct-solver build, replace the mirrored eight-bank
distributed matrix with one in-place,
true-dual-port BRAM workspace. Store only the lower triangle because the Gram
matrix is symmetric and LDLT overwrites that same triangle.

Use a 96-entry row-base ROM and compute:

`address = row_base[row] + col`, for `row >= col`.

The row-base ROM avoids a runtime multiply. The BRAM output must be registered.
READ4/WRITE4 operations become two dual-port beats; Gram accumulation uses a
small four-entry register tile followed by a two-cycle flush. This preserves
the existing arithmetic while trading memory bandwidth for cycles.

At 56 bits per entry, the information payload is:

| Working dimension | Algorithm/use | Lower-triangle entries | Payload bits | Raw BRAM36 minimum |
| ---: | --- | ---: | ---: | ---: |
| 32 | K=32 direct LS | 528 | 29,568 | 1 |
| 64 | SP at K=32 | 2,080 | 116,480 | 4 |
| 96 | CoSaMP at K=32 | 4,656 | 260,736 | 8 |

Primitive width/depth packing and dual-port scheduling will make the practical
count slightly higher. Budget 2, 5-6, and 9-10 BRAM36 respectively, then confirm
with synthesis. RHS, D, coefficient and support vectors are linear in K and can
share one additional BRAM workspace across mutually exclusive phases.

The production `PCG_STREAM` build does not allocate this triangular workspace.
Its solver vectors and the length-M temporary are expected to fit in roughly
2-3 BRAM36 primitives; synthesis must confirm packing and port replication.

## Cycle optimization architecture

The 4x/8x and 9x/27x ratios describe the optional direct-solver build. They are
not acceptable scaling targets for the production matrix-free solver.

### Primary solver: matrix-free PCG

The scalable build uses preconditioned conjugate gradient (PCG) to solve the
same regularized normal equations as the current LDLT path:

`(Phi_S^T * Phi_S + lambda*I) * x = Phi_S^T * y`.

It never constructs the full Gram matrix. Each iteration streams
`t = Phi_S*p`, then `q = Phi_S^T*t + lambda*p`, followed by PCG dot products
and vector updates. Because every sensing entry is `+scale` or `-scale`, both
matrix-vector passes use add/subtract reductions. Wide multipliers are needed
only for O(d) vector updates and reuse the existing PE array. Storage is a small
set of length-d vectors plus one length-M temporary: O(M+d), not O(d^2).

At eight sign-add lanes and `M=128`, the initial cycle budgets are:

| Work dimension | Two Phi passes/iteration | Complete iteration target | 16 iterations | 24 iterations | 32 iterations |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 1,024 | <=1.2k | <=19.2k | <=28.8k | <=38.4k |
| 64 | 2,048 | <=2.3k | <=36.8k | <=55.2k | <=73.6k |
| 96 | 3,072 | <=3.4k | <=54.4k | <=81.6k | <=108.8k |

These are architecture budgets, not synthesis measurements. For the same
iteration count, d=96 is about 2.8x d=32 instead of 27x. Map the previous
K-entry solution into the new 2K/3K union and initialize new positions to zero;
this warm start is mathematically neutral and should reduce average iteration
count. Restart the conjugate direction periodically to limit fixed-point loss
of orthogonality.

Start with scalar diagonal scaling. In signed-binary mode every Gram diagonal
is `M*scale^2 + lambda`, so this costs one reciprocal and no matrix storage. If
the d=96 sweep needs fewer iterations, add an 8x8 block-Jacobi preconditioner.
The twelve lower-triangular blocks require 432 values, or 24,192 bits at 56
bits/value: approximately one BRAM36 rather than a full 96x96 matrix.

Convergence is part of correctness. A solve commits only when:

`norm_inf(Phi_S^T*(y-Phi_S*x) - lambda*x) <= atol + rtol*reference_norm`.

Recompute this residual directly at each restart. If the coefficient margin
around the K-th prune rank is small, continue iterating because solver error
could change support selection. Reaching `max_iter` without the residual
certificate raises `ls_not_converged`; it must not silently prune an
uncertified vector. Positive regularization makes the system SPD, but the
fixed-point implementation still requires guard bits, saturation checks,
restart, and adversarial condition-number sweeps.

### Optional direct build: exact sign-signature Gram engine

The generated sensing matrix contains only `+scale` and `-scale` entries. Cache
the M sign bits of each column as `signature[column]`. For every selected pair:

`G[i,j] = scale^2 * (M - 2*popcount(signature[i] xor signature[j]))`.

This is algebraically identical to the row-by-row Gram sum; it is not an
approximation. Gate this path on the signed-binary matrix mode and retain the
existing multiply-accumulate path for any future general-valued matrix mode.
The fixed-point implementation must align `scale^2` and saturation exactly with
the current Gram output contract.

Store all 1024 signatures globally instead of rebuilding the 96 active ones on
each iteration. At `M_MAX=128` this costs 131,072 bits, approximately four
BRAM36 primitives when implemented as four 32-bit banks. A reused 32-bit
XOR-popcount datapath processes one Gram pair in four beats:

| Dimension | Lower-triangle pairs | Popcount beats |
| ---: | ---: | ---: |
| 32 | 528 | 2,112 |
| 64 | 2,080 | 8,320 |
| 96 | 4,656 | 18,624 |

RHS construction remains linear in `M*d` because the measurement values are
general. It runs concurrently where BRAM and PE ports allow. This removes the
`M*d^2` multiply loop from Gram construction without changing the LS problem.

### Optional direct build: tiled factorization engine

The current streamed LDLT border already accepts a new four-row group every two
clocks, but each dot-product term still performs both `L(i,p)*L(k,p)` and then
`*D[p]`. More banking alone therefore cannot remove the cubic-cycle growth.

Cache one weighted pivot row `W[k,p] = L[k,p]*D[p]` before updating row k.
The diagonal and every border row then use one product `L[i,p]*W[k,p]`, rather
than recomputing two dependent products for every `(i,k,p)` term. This preserves
LDLT in exact arithmetic, needs only d cached values, and avoids a square-root
unit. Its fixed-point multiplication order changes, so it still requires a new
numerical contract and regression vectors.

Use two banked 8x8 local tiles and burst them to the compact triangular BRAM.
Do not replicate the complete matrix into multi-read banks: the earlier full
bank experiment increased LUT/LUTRAM sharply. The PE array remains shared, and
the tiles only provide enough independent rows to sustain the existing two
64-bit-products-per-cycle issue rate.

Do not start with arbitrary update/downdate across iterations; permutation and
downdate stability make that a second-stage optimization.

The product counts and initial architecture targets are:

| Dimension | Weighted-LDLT products | Raw issue lower bound at 2/cycle | Gram+RHS target | Factor target | Solve target | Total LS target |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 5,952 | 2,976 | <=4k | <=10k | <=2k | <=16k |
| 64 | 45,696 | 22,848 | <=12k | <=47k | <=8k | <=67k |
| 96 | 152,000 | 76,000 | <=25k | <=118k | <=12k | <=155k |

These are design budgets for the deterministic direct build, not synthesis
measurements. Phase counters must report Gram, factor, forward, backward, and
total LS cycles separately.

### Reuse and optional modes

Retain the existing exact support/configuration factor-cache hit and prefix
extension paths in the direct build. They can remove a complete factorization
when the union stops changing, but must not be included in worst-case claims.
Use compile-time `LS_MODE=PCG_STREAM` for the scalable production image and
`LS_MODE=DIRECT_WLDLT` for deterministic reference/conditioning sweeps; do not
instantiate both datapaths in the area-optimized image.

## Required RTL migration

1. Split index width from size/count width throughout CSR, addrgen, DMA and the
   sparse controller. Do not widen every index datapath to 11 bits.
2. Replace five-bit LS row/column fields and fixed 32-wire support interfaces
   with `WORK_AW` addressed interfaces.
3. Derive work capacity from algorithm mode and K instead of the legacy five-bit
   context depth field, which cannot encode 64 or 96.
4. Extend the padded LFSR jump contract to 1024 and represent `n_size=1024`
   without truncation.
5. Add canonical CoSaMP/SP programs that solve before pruning, and remove the
   K=16 capacity skips only after those tests pass.
6. Add `pcg_stream_solver` with addressed vector BRAMs, eight sign-add lanes,
   reused wide vector-update arithmetic, restart, and residual-check states.
7. Add `LS_MODE` as a synthesis-time selection so unused direct or PCG storage
   and control are eliminated, not merely clock-gated.
8. Add per-solve counters for iteration count, Phi passes, vector cycles,
   residual checks, restarts, and convergence/breakdown reason.
9. Sweep d=32/64/96 over random and adversarial supports against a high-precision
   software solve before selecting `atol`, `rtol`, restart period, and max_iter.

## Formal properties

- `solution_depth <= K_SOL_MAX` and `work_depth <= K_WORK_MAX`;
- every list index is less than `n_size`;
- no duplicate valid working-list entries;
- list membership and bitmap membership are coherent;
- every direct-LS request satisfies `row < work_depth`, `col <= row`, and the
  triangular address is in range;
- BRAM read data is consumed only after the registered response is valid;
- pruning commits exactly K or fewer entries and cannot occur before the union
  solve completes;
- for signed-binary sensing mode, every popcount Gram result equals the
  row-by-row reference sum for all legal `M`, indices, seeds, and scales;
- the signature cache is invalidated whenever `M`, matrix seed, scale, or matrix
  kind changes;
- each PCG Phi/Phi-transpose pass consumes exactly `M*work_depth` legal sign
  terms and produces one result per addressed output;
- PCG cannot commit without `residual_pass`; `max_iter` without convergence
  raises `ls_not_converged`;
- zero/non-positive PCG denominators and arithmetic overflow raise the defined
  breakdown response instead of updating a vector;
- warm-start coefficients map only to matching support indices, and all new
  union entries start at zero;
- PCG and direct reference requests use the same complete support, RHS, scale,
  and regularizer;
- phase-cycle counters advance only while their corresponding LS phase is busy.
