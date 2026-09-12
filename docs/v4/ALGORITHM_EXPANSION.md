# v4 algorithm expansion: three different optimization strategies

Status, 2026-09-08: **exploratory unweighted LASSO numerical models exist** for
FISTA, ADMM and PDHG in [proximal.py](../../models/v4/proximal.py), with numerical
tests in [test_proximal.py](../../verification/v4/test_proximal.py). They are not
compiled CGRA programs or RTL implementations. The weighted-LASSO generalization,
PDHG-TV model, two-dimensional stencil schedule and application measurements
below remain **proposed contracts and qualification work**. This document does
not claim those targets have been implemented or benchmarked.

Prioritize FISTA, ADMM and PDHG beyond the eight existing
algorithms. **PDHG anisotropic-TV image reconstruction is the preferred future PDHG
application showcase; the existing exploratory PDHG-LASSO model is its common-objective conformance
baseline. Count one PDHG family, for eleven target algorithm entries overall.**
ISTA is a reference ablation within FISTA's proximal-gradient family,
not an extra family counted to increase the algorithm total. More OMP variants
are not the priority. AMP is an optional later probabilistic/message-passing
family, with explicit matrix and convergence qualifications.

The three LASSO profiles deliberately share an objective first: differences in
hardware work and convergence can then be compared without changing the
reconstruction problem. The PDHG-TV showcase adds a different image prior and
two-dimensional stencil workload; it must be evaluated as a different objective,
not folded into the identical-LASSO solver comparison.

## 1. Common objective and coordinate convention

Use real synthesis LASSO initially:

```text
P(x) = 0.5*||A*x - y||_2^2 + lambda*sum_j w_j*|x_j|
lambda > 0; all w_j > 0; default w_j = 1
S_a(v)_j = sign(v_j)*max(|v_j|-a_j, 0)
sign(0)=0; equality |v_j|=a_j yields exactly zero
```

The factor 0.5 is part of the contract; sources sometimes use the squared
residual without 0.5, changing gradient/step constants by a factor of two.
Use `A=Phi*Psi` for raw-signal measurements and reconstruct `s=Psi*x`.
Synthesis LASSO with an overcomplete Psi is not the same objective as analysis
LASSO on the original signal; do not exchange them silently.

If columns are normalized with `A=A0*C^-1`, `z=C*x`, then preserving the original
penalty `lambda*||x||_1` requires `w_j=1/c_j` in z coordinates. Alternatively,
declare standardized-coordinate LASSO with w=1 as the common objective. Choose
one convention for all three solvers. The same lambda is meaningful only with
the same A/y scaling and weights. Per-block signal scaling by c also changes
the corresponding lambda: if x and y are divided by c, lambda is divided by c
to preserve the same optimization problem. Save these transformations.

Primary algorithm authorities are
[Beck & Teboulle, 2009](https://www.tau.ac.il/~becka/FISTA.pdf),
[Boyd et al., 2011, sections 3 and 6.4](https://web.stanford.edu/~boyd/papers/pdf/admm_distr_stats.pdf),
and [Chambolle & Pock, 2011](https://doi.org/10.1007/s10851-010-0251-1),
with an [author preprint](https://www.cmap.polytechnique.fr/preprint/repository/685.pdf).
The equations below instantiate those methods for this project's stated LASSO;
the memory plans and application assignments are engineering proposals.

## 2. FISTA: accelerated proximal gradient

ID `FISTA_LASSO_CONSTSTEP`; initialize x0=0, z1=x0, t1=1. For k=1,2,...:

```text
g_k     = A^T*(A*z_k-y)
x_k     = S_(lambda*w/L)(z_k - g_k/L)
t_(k+1) = (1 + sqrt(1 + 4*t_k^2))/2
beta_k  = (t_k-1)/t_(k+1)
z_(k+1) = x_k + beta_k*(x_k-x_(k-1))
```

Require `L >= ||A||_2^2` for the smooth part of this objective. Start with fixed
L and plain FISTA; restart, monotone FISTA and backtracking need separate named
profiles. Plain FISTA's objective need not decrease on every iteration, so the
SP reject-on-non-decrease rule must not be reused here. The primary paper's
objective-rate guarantee applies to its exact-arithmetic assumptions, not
automatically to a rounded implementation. [FISTA primary paper](https://www.tau.ac.il/~becka/FISTA.pdf).

The t/beta sequence depends only on iteration number and can be precomputed on
the host, then stored as explicitly quantized metadata with a maximum-iteration
length/hash. The runtime need not contain a square-root unit for this profile.
Float golden uses the specified recurrence; fixed golden uses the exact table
values consumed by RTL. Do not silently treat those two as bit-identical math.

Kernel requirements: one full A and one full A^T application per iteration,
residual subtraction, soft threshold, vector scaling/AXPY and momentum state.
Plan approximately three N-vectors (current/previous/extrapolated x) plus
M-residual and operator workspace, with safe buffer reuse proved by scheduling.
Top-K, growing support and restricted LS are absent. Full streaming operations
test R1-style mapping; threshold/momentum fusion tests local RF and bandwidth.

Proposed showcase: BSDS image blocks or CAVE spatial-spectral blocks with fixed
DCT/wavelet synthesis, then ECG as an additional shared comparison. Image
inverse problems directly motivate the original FISTA study; this does not
establish it as the winner on these datasets. Prioritize public image/ECG data
before a gated MRI dataset.

## 3. ADMM-LASSO: variable splitting and an SPD inner solve

ID `ADMM_LASSO_FIXEDRHO`; initialize x0=z0=u0=0; rho>0 fixed. Split x=z:

```text
(A^T*A + rho*I)*x_(k+1) = A^T*y + rho*(z_k-u_k)
z_(k+1) = S_(lambda*w/rho)(x_(k+1)+u_k)
u_(k+1) = u_k + x_(k+1)-z_(k+1)
```

u is the **scaled** dual variable. Do not substitute an unscaled-dual update.
The system is SPD for rho>0, including rank-deficient A. A matrix-free CG
implementation applies `v -> A^T*(A*v)+rho*v`; it does not need to materialize
the N-by-N Gram matrix. Precompute A^T*y per job. A direct-factorization float
oracle remains useful for tiny matrices. [Boyd et al., LASSO derivation](https://web.stanford.edu/~boyd/papers/pdf/admm_distr_stats.pdf).

The positive rho here is the augmented-Lagrangian splitting penalty. It does
not change the target LASSO optimum when ADMM converges, and is not a license to
regularize the ordinary restricted LS in OMP/SP/CoSaMP/HTP. Those existing
paper profiles retain their own lambda=0 LS contract. Distinct solver opcode or
an explicit descriptor flag must prevent accidental cross-use.

For a first fixed-point profile, choose rho on validation and keep it constant.
If later changing rho adaptively, rescale u to preserve the unscaled dual
rho*u, and identify that policy as a new profile. Warm-starting inner CG from
the previous x must be declared. A fixed small number of inner CG steps is a
bounded inexact variant; general ADMM convergence cannot be claimed just from
the exact-update theorem. Inexact solves need a justified error schedule
(summable in the cited general result) or a separately qualified finite-budget
contract. [Boyd et al., inexact minimization, section 3.4.4](https://web.stanford.edu/~boyd/papers/pdf/admm_distr_stats.pdf).

Use both ADMM residuals:

```text
r_primal = x_(k+1)-z_(k+1)
r_dual   = rho*(z_(k+1)-z_k)
eps_pri  = sqrt(N)*atol + rtol*max(||x_(k+1)||2, ||z_(k+1)||2)
eps_dual = sqrt(N)*atol + rtol*||rho*u_(k+1)||2
```

Terminate only when both residual tests, the inner-solve policy and the common
LASSO quality/convergence gate pass. Return z as the declared sparse primal
candidate and evaluate `P(z)` and its common certificate. Squared-norm tests
may avoid runtime square roots if the exact equivalent bounds and rounding
are specified. Fixed coefficients/rho must remain representable and positive.

Kernel requirements: full-domain CG (different from support-restricted CGLS),
A/A^T passes per inner step, dot products, ratios, AXPY, soft threshold and
dual-state update. Three primal/split/dual N-vectors plus CG vectors and M
temporary storage must fit. This is deliberately a harder test of reduction,
scalar dependencies and memory residency than FISTA.

Proposed showcase: ECG/wearable waveform reconstruction with correlated dense
`Phi*Psi`, compared against exactly the same LASSO solved by FISTA/PDHG.
Repeated frames sharing A may amortize operator preparation, but cold and warm
costs must both be reported. No claim of ADMM-specific superiority is assumed.

## 4. PDHG-LASSO: primal-dual splitting without an inner LS solve

ID `PDHG_LASSO_CP1`; take `F(v)=0.5*||v-y||2^2`,
`G(x)=lambda*sum w_j*|x_j|`, with the saddle coupling `<A*x,p>`.
Then `F*(p)=0.5*||p||2^2 + <p,y>` and
`prox_(sigma*F*)(v)=(v-sigma*y)/(1+sigma)`. Initialize x0=xbar0=0, p0=0:

```text
p_(k+1)    = (p_k + sigma*A*xbar_k - sigma*y)/(1+sigma)
x_(k+1)    = S_(tau*lambda*w)(x_k - tau*A^T*p_(k+1))
xbar_(k+1) = x_(k+1) + theta*(x_(k+1)-x_k)
```

Use tau>0, sigma>0, `tau*sigma*||A||2^2 < 1`, and theta=1 for the initial
basic Chambolle-Pock profile. Set a deliberate margin before quantizing steps.
This is a specialization of the primary primal-dual algorithm, not a claim
that its accelerated variants apply automatically. Its general convex rate
statement concerns an appropriate gap/ergodic sequence; do not demand a
monotonically decreasing primal objective at every raw iterate.
[Chambolle-Pock primary preprint](https://www.cmap.polytechnique.fr/preprint/repository/685.pdf).

Precompute `1/(1+sigma)` and scalar products in host metadata; neither an inner
CG nor a per-iteration divide is needed for fixed steps. Use p_(k+1), not stale
p_k, in the primal step. Kernel needs: one A and one A^T, two affine vector
updates, soft threshold and extrapolation. State includes N primal/current-old
or extrapolated buffers and one M dual vector. The mathematical dual vector is
not the same quantity as ADMM's N-dimensional split multiplier u.

Use this LASSO profile for common-objective conformance and solver comparison.
The preferred application showcase is the explicit anisotropic-TV profile below.

### 4.1 PDHG anisotropic-TV: preferred image and mesh showcase

ID `PDHG_TV_ANISO_NEUMANN`; target BSDS grayscale image reconstruction from
compressed **pixel-domain** measurements. This is a proposed program/contract,
not a claim that a TV program already runs on the physical PE arrays. The
objective is:

```text
min_x 0.5*||A*x-y||2^2 + lambda*||D*x||1
||D*x||1 = sum_(i,j) (|D_h*x[i,j]| + |D_v*x[i,j]|)
```

Here x contains image pixels and A=Phi. Unlike synthesis LASSO, the variable is
not a transform coefficient vector and A is not Phi*Psi. The same measured y
can still be used to compare physical reconstruction quality with a LASSO
profile using its own Phi*Psi operator. Equal lambda does not make those two
different priors equivalent. Do not add positivity or [0,1] projection to x in
this profile: that would add a constraint to the objective.

Let `K*x=(A*x,D*x)`, `F(v,w)=0.5*||v-y||2^2+lambda*||w||1`, and `G(x)=0`.
The conjugate separates into a quadratic data term and a box indicator:

```text
F*(p,q) = 0.5*||p||2^2 + <p,y> + indicator_(||q||inf<=lambda)(q)
prox_(sigma*F*)(v,w) = ((v-sigma*y)/(1+sigma), clip(w,-lambda,+lambda))
```

This is a direct specialization of the general
[Chambolle-Pock algorithm](https://doi.org/10.1007/s10851-010-0251-1).
[Sidky, Jorgensen & Pan's primary reconstruction paper](https://arxiv.org/abs/1111.5632)
provides related data-plus-TV primal-dual imaging derivations; this contract
specifically chooses **anisotropic** componentwise TV, not an isotropic
Euclidean-norm projection. Initialize x0=xbar0=0, p0=0, qh0=qv0=0:

```text
p_(k+1)    = (p_k + sigma*(A*xbar_k-y))/(1+sigma)
q_(k+1)    = clip(q_k + sigma*D*xbar_k, -lambda, +lambda)
x_(k+1)    = x_k - tau*(A^T*p_(k+1) + D^T*q_(k+1))
xbar_(k+1) = 2*x_(k+1)-x_k
```

The dual projection radius is lambda, **not** sigma*lambda. Use both new dual
vectors in the primal update. No soft threshold is applied to x in this TV
profile. Fixed-point clipping is an intended proximal operation; distinguish
it from unintended arithmetic saturation, which remains a fault.

### 4.2 Discrete gradient, adjoint and stability bound

For H-by-W unit-spaced pixels, zero-based indexing, and no periodic wrap:

```text
D_h*x[i,j] = x[i,j+1]-x[i,j] if j<W-1, else 0
D_v*x[i,j] = x[i+1,j]-x[i,j] if i<H-1, else 0

D^T*q[i,j] = incoming_h - outgoing_h + incoming_v - outgoing_v
incoming_h = q_h[i,j-1] if j>0, else 0
outgoing_h = q_h[i,j]   if j<W-1, else 0
incoming_v = q_v[i-1,j] if i>0, else 0
outgoing_v = q_v[i,j]   if i<H-1, else 0
```

D^T is the adjoint, often called negative divergence. The sign must match
`<D*x,q>=<x,D^T*q>`. Last-column q_h and last-row q_v correspond to zero gradient
rows; keep them zero and ignore them in D^T, including boundary-fault tests.
Treat H=1/W=1 without special wraparound behavior. Record pixel spacing; using
1/h-scaled differences changes the norm bound and the effective regularization.

Each one-dimensional unit-grid forward difference has squared spectral norm
at most 4, hence `||D||2^2<=8`. Also
`||K||2^2<=||A||2^2+||D||2^2`. A conservative basic-profile condition is:

```text
tau > 0; sigma > 0; theta=1
tau*sigma*(A_norm_upper_squared + 8) < 1
```

Derivation: `||K*x||2^2=||A*x||2^2+||D*x||2^2`, bounded termwise by the stated
operator norms. This bound is conservative, not the exact norm of the stacked
operator. It applies when the same sigma is used for both dual blocks. Separate
data/TV step sizes require an appropriate scaled-operator bound. Verify the
inequality after quantization and use margin. These exact-arithmetic conditions
do not replace fixed-point convergence/quality tests.

An independent numerical algebra check in this research turn formed explicit D
for shapes 1x1, 1x5, 5x1, 2x2, 3x5, 4x4 and 8x8. The stencil adjoint matched
matrix D^T within 9e-16, and the largest squared norm was approximately 7.696,
below 8. This checks the formula only; it is not an implemented TV solver or
an RTL/dataset benchmark. Persist these cases in the numerical-model tests.

### 4.3 Actual mesh work and halo contract

Map physical 4x4 PE tiles to contiguous image pixels during gradient/adjoint
phases. East/south neighbor values form forward differences; west/north dual
values form the adjoint. Use registered N/E/S/W routes, explicit launch/arrival
cycles, and local RF lifetime rules. This exercises two-dimensional mesh paths
beyond the horizontal reductions used in R4 GEMV.

The two arrays have no implied direct mesh edge between them. Exchange
inter-array and inter-tile halos through the banked scratchpad and scheduled
load/store phases. Count halo reads/writes, bank service, route cycles and
barriers; do not count a scratchpad transfer as a same-cycle neighbor hop.
All stencil outputs consume the required old xbar or new q snapshot; an
in-place sweep that consumes partially updated neighbors changes the algorithm.

Neumann zeros occur only at the mathematical image/problem boundary.
Boundaries of a 4x4 hardware tile **inside** that image need real neighbor halos.
If the benchmark reconstructs independently sensed 16x16 patches, each patch
may be its own declared Neumann-bounded problem; disclose patch-edge artifacts.
Whole-image TV and patch-independent TV are different benchmark profiles.

Per iteration: one full A and A^T pass, D and D^T stencils, quadratic data prox,
componentwise clip, primal AXPY and extrapolation. Maintain x/current-extrapolated
state, M data-dual values, two N TV-dual components and halo buffers. There is no
inner CG or data-dependent square root for anisotropic TV; fixed
`1/(1+sigma)` can be host metadata. Isotropic TV would require a different prox
and potentially vector magnitude/reciprocal support, so it is out of this ID.

### 4.4 TV-specific correctness and stopping

Check gradient/adjoint identities and constant-image D*x=0; compare a ramp and
edge impulse with explicit matrices; include H=1/W=1, corners, internal tile
boundaries and the inter-array seam. Verify the clip box and all phase buffer
lifetimes. Test denoising A=I, lambda=0 as a separately declared boundary case,
and small dense sensing against an independent convex TV optimizer.

Useful KKT diagnostics are:

```text
data relation:       p - (A*x-y)
stationarity:        A^T*p + D^T*q
dual box violation:  max(0, ||q||inf-lambda)
TV complementarity:  lambda*||D*x||1 - <q,D*x>
```

Freeze their absolute/relative scales and tolerances before testing, together
with iterate-change and iteration-budget rules. For feasible q the last
quantity is nonnegative and is zero at the appropriate TV subgradient relation.
The true TV dual objective is `-0.5*||p||2^2-<p,y>` **only when** both box
feasibility and `A^T*p+D^T*q=0` hold. A merely small stationarity residual does
not make a finite primal-dual gap a certified bound. Do not reuse the
LASSO residual-rescaling certificate: its dual constraint is different.
Report KKT residuals, achieved objective and image quality until a valid TV gap
certificate is implemented. PSNR/SSIM alone is not solver correctness.

## 5. Common stepsize, correctness and stopping policy

Host metadata must include objective ID, lambda, weights, coordinate scaling,
L/tau/sigma/rho, norm bound/method, iterations, stopping thresholds, warm-start
policy, arithmetic formats and coefficient-table hashes. Validate the step
constraints using the **quantized operator and scalar values** actually used.
A few power iterations usually estimate a norm from below and cannot by
themselves certify a safe upper bound. Conservative alternatives include
`||A||2^2 <= ||A||F^2` or `||A||2^2 <= ||A||1*||A||inf`; tighter validated bounds
may improve speed. Their cost and conservatism must be reported.

For a shared LASSO certificate, create a dual-feasible p from the physical
residual `v=A*x-y`. For weighted LASSO define
`a=max_j |(A^T*v)_j|/(lambda*w_j)`,
`p=v/max(1,a)`, treating all-zero v explicitly. Then:

```text
dual_feasible: |(A^T*p)_j| <= lambda*w_j for every j
D(p) = -0.5*||p||2^2 - <p,y>
gap  = P(x)-D(p)
```

This follows directly from the LASSO Fenchel dual. Check feasibility again
after quantization; rescaling in finite precision is not an automatic proof.
Use a predeclared normalized gap tolerance, numerical slack and iteration cap;
compute SNR/MSE separately. A small optimization gap does not imply correct
support or a good application model. A post-quantization LS normal-residual
certificate alone does not certify the complete LASSO problem.

Required golden cases: A=I (solution `S_(lambda*w)(y)`), diagonal A with known
solution, lambda at/above `max_j |A^T*y|/w_j` (zero optimum), y=0, correlated
columns, rank-deficient A, small dense cases checked by an independent convex
solver, and high-dynamic-range inputs. Do not require equal coefficients for
nonunique minimizers; compare objective/certificates and application outputs.
Trace every vector update and all commit/fault decisions against bit-accurate
models before RTL acceptance. A checkpointed certificate's extra operator passes
belong in cycle/traffic counts.

## 6. Fair benchmark and hardware interpretation

Run all three on the same real dataset/operator/noise cases and **identical
objective/lambda/weights**, with lambda chosen by validation and frozen. Report
objective gap versus A/A^T calls, cycles and energy, and time to the application
quality target. Do not compare one outer ADMM iteration with one FISTA/PDHG
iteration as equal work. Extra ADMM CG calls and all certificates count.
Lambda sensitivity is a separate grid; the hard-K algorithms solve a different
constraint/model, so compare their quality/cost Pareto curves rather than
pretending K=lambda.

The new LASSO methods mostly operate on full vectors. They may therefore **not**
benefit from support packing or adaptive small-support R4 mapping. This is
useful coverage: the architecture should efficiently execute both full-domain
proximal methods and support-restricted pursuit methods. Do not invent support
pruning inside the new algorithms just to make an architectural feature look
universal; it changes their semantics. PDHG-TV adds a separate mesh-stencil
showcase; count it as a profile of the same PDHG family, not a twelfth algorithm.

Implementation order: FISTA establishes soft threshold and momentum; PDHG-LASSO
establishes the dual-stream conformance baseline, followed by PDHG-TV gradient,
adjoint and halo qualification for the preferred image showcase; ADMM follows
when the full-domain SPD inner solver and stopping contract are ready. The
algorithm IDs can remain 9/10/11 or named symbols according to the global
descriptor contract; this document does not allocate opcodes independently.

## 7. Optional AMP: a fourth family with a real Onsager term

Authority: Donoho, Maleki & Montanari, *Message-passing algorithms for compressed
sensing*, 2009, [author PDF](https://web.stanford.edu/~montanar/RESEARCH/FILEPAP/mpacs.pdf)
and [arXiv](https://arxiv.org/abs/0907.3574). Initial real-valued AMP profile uses
zero-mean iid Gaussian `A_ij ~ N(0,1/M)`, x0=0, r0=y. One equivalent index order:

```text
v_t       = x_t + A^T*r_t
x_(t+1)   = S_(theta_t)(v_t)
b_t       = (1/M)*sum_j 1[|v_t[j]| > theta_t]
r_(t+1)   = y - A*x_(t+1) + b_t*r_t
```

The last term is the Onsager correction; deleting it is not AMP. The derivative
at the threshold tie is fixed to zero for hardware determinism. Freeze the
threshold policy: e.g. theta_t=alpha*||r_t||2/sqrt(M), with alpha selected on
validation, or an explicit supplied schedule. Include its norm/scalar cost.
Fixed-theta AMP is not automatically LASSO with lambda=theta; at a suitable
fixed point the relation involves the Onsager coefficient. Keep AMP outside the
identical-lambda convergence comparison until that calibration is specified.

Its operator assumptions differ from general convex FISTA/ADMM/PDHG. Published
work documents difficulty on ill-conditioned/nonzero-mean transforms and studies
damping under particular conditions:
[Rangan et al., 2014](https://arxiv.org/abs/1402.3210). Do not claim that ordinary
AMP converges for arbitrary composed/structured sensing operators or that any
ad hoc damping makes it safe. Start with synthetic iid-Gaussian controls, then
real-signal compression under that declared ensemble. A damped/normalized/GAMP
variant needs its own equations and validation.

Kernel additions are derivative/active-count reduction, Onsager scalar-vector
update and a threshold schedule. These are meaningfully different from IHT,
but adding AMP solely to increase the algorithm count is not the current goal.
