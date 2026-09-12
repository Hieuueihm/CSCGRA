# v4 benchmark protocol: numerical quality before RTL/PPA

Status: **research protocol / proposed application assignments, 2026-09-08**.
This document defines experiments; it does not report completed downloads,
reconstruction measurements, an optimal word length, or hardware results.
The eight algorithm IDs and mathematical semantics come from
[the v3 algorithm contract](../v3/02_ALGORITHM_CONTRACT.md) and its
[primary references](../v3/references/README.md). Preserve those semantics in v4.

Current sequencing: **architecture contract first**, with this protocol supplying
operator, memory, precision and verification requirements. Numerical experiments
qualify that architecture before its formats are frozen; they do not justify
starting full RTL or synthesis ahead of an architecture review.

The immediate architecture implications are: support dense/composed `Phi*Psi`
alongside generated-sign operators; define transpose streaming and support-index
gather; account for matrix/transform bandwidth; schedule A/A^T and restricted LS
on the 32 PEs; handle dimensions not divisible by 32; and retain complex/group
semantics as an explicit extension until qualified. These requirements are more
important than forcing eight applications into the first implementation.

## 1. What the paper can establish

The useful claim is that one reconfigurable architecture executes several sparse
recovery methods across different signal domains, with measured quality and
quality-adjusted cost. Assigning one dataset to each algorithm alone does not
establish that an algorithm is especially suitable, nor does it establish a fair
algorithm comparison. Most of these methods solve the same mathematical problem.

Use two linked experiments:

1. **Common comparison:** all eight algorithms on the same signals, operators,
   measurements, noise draws and train/validation/test split. Publish failures.
2. **Application showcase:** one distinct application highlighted per algorithm,
   selected using validation results under a frozen quality/latency objective.
   Keep the complete common comparison available. A proposed assignment that
   loses on validation may be changed, with the decision recorded before test.

The assignments below are **engineering hypotheses**, not conclusions of the
cited papers. An eight-application requirement must not force eight claims of
unique or best suitability. The immediate project should establish strong ECG,
image and speech results first; wearable, vibration and spectral/channel tasks
provide broader coverage after their own adapters are validated.

## 2. Eight concrete candidate showcases

`s` is the uncompressed physical-domain signal; `Psi` is a synthesis transform;
`x` is its coefficient vector. Unless stated otherwise, real-data measurements
are `y = Phi*s + e` and the reconstruction operator is `A0 = Phi*Psi`.
The noise grid in section 4 applies to every row. All transforms below are
proposed experiment settings, not prescribed by the dataset owners.

| ID / proposed algorithm | Application and official dataset | Signal, transform and operator | Motivation, limits and access |
| --- | --- | --- | --- |
| A1 / OMP | ECG telemetry: [MIT-BIH Arrhythmia v1.0.0](https://physionet.org/content/mitdb/1.0.0/) | First ECG channel, original physical units/rate, non-overlapping 512-sample windows. Orthonormal `db4` DWT, level 4, periodization; `Phi` Rademacher. Score reconstructed ECG, not only wavelet coefficients. | Sequential support growth and LS give an interpretable sparsity/quality curve. This is not evidence that OMP beats all ECG decoders. Direct public files and ZIP; ODC-BY. Decoder and record/channel validation still needed. |
| A2 / MP | Speech compression: [LibriSpeech SLR12](https://www.openslr.org/12/) | Mono waveform at its released rate, 512-sample frames. Common track: orthonormal DCT-II. Separate showcase variant: a frozen real time-frequency dictionary; use actual compressed atom norms. Rademacher `Phi`. | MP's original [time-frequency dictionary paper](https://doi.org/10.1109/78.258082) is the closest direct algorithm/application match in this list. Audio sparse approximation is not automatically good CS recovery after projection; dictionary variant must be named. Direct archives, CC-BY 4.0; FLAC adapter needed. |
| A3 / CoSaMP | Block image sensing: [Berkeley BSDS](https://www2.eecs.berkeley.edu/Research/Projects/CS/vision/bsds/) | Prefer BSDS500 official train/val/test if downloadable; otherwise explicitly version as BSDS300, never label it BSDS500. Fixed RGB-to-gray conversion, 16x16 non-overlapping patches, separable orthonormal DCT-II, Rademacher `Phi`. Use all complete patches under a predeclared image cap. | CoSaMP explicitly addresses compressible signals and inaccurate samples; its temporary enlarged support exercises LS/prune. No guaranteed advantage for natural images. Public academic/research download is advertised; BSDS500 target page failed the research fetch, so artifact access/checksum is **not yet verified**. |
| A4 / IHT | Wearable inertial telemetry: [UCI HAR, dataset 240](https://archive.ics.uci.edu/dataset/240/human+activity+recognition+using+smartphones) | Released `Inertial Signals` waveform arrays, each axis separately, N=128, orthonormal DCT-II, Rademacher `Phi`. Do not use the 561 engineered features as a raw sensor signal. | Low-memory operator/adjoint iterations make this a plausible streaming workload. It is a breadth experiment, not a canonical CS performance benchmark. Public ZIP; original windows are preprocessed and overlap. Retain subject IDs and official subject-separated split. |
| A5 / HTP | Bearing vibration telemetry: [CWRU Bearing Data Center](https://engineering.case.edu/bearingdatacenter/download-data-file) | 12 kHz drive-end fault recordings, `DE_time`, 512-sample non-overlapping windows. Orthonormal `db4` DWT, level 4, periodization; Rademacher `Phi`. Report waveform and envelope-spectrum error. | Threshold plus support LS can test whether debiasing helps impulsive compressible signals. This is a hypothesis; periodic fault vibration is not necessarily highly sparse in this basis. Official MATLAB downloads are advertised. Store source terms; an explicit redistribution license was not established by this review. |
| A6 / SP | Multispectral camera compression: [CAVE multispectral database](https://cave.cs.columbia.edu/repository/Multispectral), [creator technical report](https://cave.cs.columbia.edu/old/publications/pdfs/Yasuma_TR08.pdf) | Non-overlapping 4x4x31 spatial-spectral blocks, N=496; separable orthonormal 3-D DCT, Rademacher `Phi`. Keep all 31 bands; do not count a fabricated padded band as data. Reassemble before spectral-angle/PSNR scoring. | SP support replacement and post-prune LS provide a distinct test of spectral compressibility and LS accuracy. Not a claim that SP exploits joint sparsity: ordinary SP does not. Creator report verifies 31-band acquisition; catalog is public, but scene-archive links/license and complete payload were **not verified** here. Planned until resolved. |
| A7 / GP | EEG telemetry: [PhysioNet EEG Motor Movement/Imagery v1.0.0](https://physionet.org/content/eegmmidb/1.0.0/) | Channels C3/Cz/C4 selected by EDF labels, runs 1,2,4,8,12, windows N=512; orthonormal DCT-II baseline, real Gabor dictionary only as a separately frozen variant. Rademacher `Phi`. Score waveform and 8-30 Hz band-power error. | Restricted gradient and line search trade repeated LS for more iterations. GP-specific superiority on EEG is unestablished. Preserve reselection. Public EDF files/ZIP, ODC-BY; adapter and run/channel checks required. |
| A8 / gOMP | Pilot-based channel estimation: [DeepMIMO](https://www.deepmimo.net/), [dataset paper](https://arxiv.org/abs/1902.06435) | Freeze scenario `asu_campus_3p5`, release/package hash, single-user 64-antenna BS channel, one subcarrier; angular DFT synthesis, fixed randomized pilot/combiner operator. Sweep 16/24/32 observed complex measurements. Score complex channel NMSE and beamforming-gain loss. | Multiple selections per iteration are attractive for multipath, but performance on off-grid correlated atoms must be measured. Ray-traced data are **simulated**, not over-the-air measurements. Official download/generator API is documented; scenario payload and adapter are planned. Complex semantics require separate qualification below. |

The MIT-BIH and EEG owners explicitly provide unauthenticated download routes.
LibriSpeech publishes download archives and license. UCI provides downloadable
sensor windows. These four can be acquired immediately without a new data-access
application; this document does not assert they are already in the repository.
CWRU is an immediate adapter candidate with source/terms recording. BSDS, CAVE
and DeepMIMO remain planned until the exact artifacts, transforms and manifests
are validated. Missing data must remain `NOT_RUN`, never count as passing rows.

ECG is a well-established CS application, but a relevant original
[EPFL ECG study](https://infoscience.epfl.ch/record/165139/files/TBME2011-9A0AAd01.pdf)
used basis-pursuit denoising; it does **not** establish OMP as the optimal ECG
algorithm. The same distinction applies between a domain's CS literature and
the particular showcase algorithm proposed here.

### Mathematical evidence for the eight methods

| Method | Primary source | What the source supports here |
| --- | --- | --- |
| MP | [Mallat & Zhang, 1993](https://doi.org/10.1109/78.258082) | Greedy approximation in time-frequency dictionaries; normalize selection by atom norm. |
| OMP | [Tropp & Gilbert, 2007](https://doi.org/10.1109/TIT.2007.909108) | Sparse recovery from random measurements, successive support selection and orthogonal projection. |
| CoSaMP | [Needell & Tropp, 2009](https://authors.library.caltech.edu/records/qwm56-fvw26) | Stable recovery of compressible signals from inaccurate measurements under stated matrix assumptions. |
| IHT | [Blumensath & Davies, 2009](https://arxiv.org/abs/0805.0510) | Operator/adjoint-based hard thresholding, low memory, and conditional robustness. |
| HTP | [Foucart, 2011](https://foucart.github.io/publi/HTP_Final.pdf) | Hard thresholding followed by restricted LS, with conditional recovery/stability. |
| SP | [Dai & Milenkovic, 2009](https://arxiv.org/abs/0803.0811) | Support replacement and conditional recovery for sparse/compressible signals with noise. |
| GP | [Blumensath & Davies, 2008](https://www.pure.ed.ac.uk/ws/portalfiles/portal/17821386/Gradient_Pursuits.pdf) | Restricted gradient pursuit and line search as a computational alternative to orthogonal pursuit. |
| gOMP | [Wang, Kwon & Shim, 2012](https://arxiv.org/abs/1111.6664) | Select several new indices each iteration; conditional recovery, not an application-specific winner. |

## 3. Operators must match the claimed application

Keep two explicitly named tracks:

- `coefficient_domain`: compute real `x=Psi^T*s`, measure `y=B*x+e` with a
  Bernoulli `B`, reconstruct `x`, then synthesize `s`. This is useful for initial
  numerical screening and generated-sign hardware. It includes a transform at
  the encoder and cannot alone support a claim about direct raw-signal sensing.
- `signal_domain`: measure `y=Phi*s+e`, reconstruct through `A0=Phi*Psi`. Even
  when `Phi` is Bernoulli, `A0` generally contains dense coefficients. The
  architecture must execute or store this composed operator, and account for
  transform/matrix traffic. A sign-only datapath is not sufficient evidence.

Never replace a real signal by its best K-term approximation before forming
measurements in the main application experiment. That removes model mismatch
and creates an easier synthetic problem. A separate `oracle_k_sparse` control
may do so, with both truncation error and total reconstruction error reported.

For real nonuniform atom norms, define `c_j=||A0[:,j]||2`, reject zero columns,
`C=diag(c)`, `A=A0*C^-1`, `z=C*x`, and reconstruct `s_hat=Psi*C^-1*z_hat`.
Apply exactly the same convention to every algorithm and to float/fixed runs.
Quantization may perturb equal norms: either implement correct normalized
selection in the fixed model or bound/report the effect of the chosen normalized
matrix representation. Do not silently reuse MP's v3 equal-norm shortcut on a
generic dense matrix. Column scaling also changes coefficient magnitudes, so
record whether K/best-K diagnostics refer to `x` or `z`.

For DeepMIMO, use the exact real embedding of a complex system:

```text
[ Re(y) ]   [ Re(A)  -Im(A) ] [ Re(x) ]   [ Re(e) ]
[ Im(y) ] = [ Im(A)   Re(A) ] [ Im(x) ] + [ Im(e) ]
```

Running ordinary real gOMP on this embedding is a valid real sparse-recovery
experiment but **is not identical** to complex gOMP selecting by complex modulus:
real/imaginary coefficients may be selected independently. Label it
`gomp_real_embedded`, count real dimensions/support/operations, and evaluate
complex channel quality after reassembly. If paired complex-atom selection is
required, create an explicit complex/group variant and golden contract. Do not
claim eight original algorithm IDs support complex data solely by splitting I/Q.
DeepMIMO API and channel-format authority are the official
[download API](https://www.deepmimo.net/docs/api/database.html) and
[scenario specification](https://www.deepmimo.net/docs/resources/specs.html).

## 4. Frozen splits, normalization and experiment grid

1. Save dataset version, URL, retrieval date, byte count, SHA-256, source terms,
   adapter hash, exact channel IDs, original sampling rate and unit conversion.
   Save every accepted/excluded record and deterministic reason. Split source
   entities **before** extracting windows/patches; no adjacent windows or patches
   from one source entity may leak across calibration/validation/test.
2. Use official splits where available. For LibriSpeech, subdivide `dev-clean`
   speakers into calibration/validation and hold `test-clean` speakers for test;
   keep `test-other` as a declared stress domain. For UCI HAR preserve official
   test subjects and split training subjects into calibration/validation.
   For BSDS500 use train/val/test unchanged. A BSDS300 alternative has a separate
   manifest with training images subdivided and official test retained.
3. For MIT-BIH group by patient, including
   [records 201/202 from the same tape](https://www.physionet.org/physiobank/database/html/mitdbdir/records.htm)
   in one group; for EEG group by subject; for CAVE by scene. Hash each
   stable group ID with a fixed project seed, sort hashes, allocate 60/20/20
   percent with rounded counts recorded in the manifest. MIT-BIH record/patient
   metadata must be verified before claiming patient-independent testing.
   For CWRU use 0/1 HP for calibration, 2 HP for validation and 3 HP for held-out
   load testing; same original recording never crosses splits. For DeepMIMO split
   contiguous spatial regions with a guard region, not random neighboring users.
4. No normalization from held-out population statistics. Use deterministic
   preprocessing and calibration-only global bounds, or a per-block encoder
   scale genuinely available at acquisition. If subtracting an acquired block
   mean or transmitting an exponent, store/quantize it, restore physical units,
   and count its bits in compression ratio. Never scale from unknown recovered
   coefficient maxima, oracle support or test reconstruction error.
5. Preliminary common grid: `M/N in {0.25,0.375,0.5,0.75}` and
   `K/N in {1/32,1/16,1/8}`, integer dimensions fixed in the manifest. Rows with
   invalid/wide supports such as CoSaMP union exceeding M must be recorded as
   outside the current certified solver profile or handled by a correctly
   qualified rank-deficient LS solver; never silently clipped. Add N=1024
   scaling cases after adapters work at the native sizes above. N=496 and
   nonmultiples of 32 explicitly test array tails.
6. Paired measurement noise: no added noise, 40, 30 and 20 dB, where
   `input_SNR = 10 log10(||Phi*s||2^2/||e||2^2)`. Generate a seeded Gaussian draw
   then rescale it to the requested norm. Retain native recording noise; no-added
   noise means no synthetic addition, not a noiseless physical recording.
   Stress only: 10 dB, impulsive measurement errors and coherent columns.
7. Separate seeds for source-window sampling, matrix generation, coefficients
   and noise. Freeze at least 10 matrix/noise seeds for the full study; smoke
   runs may use fewer but are not paper evidence. Do not remove a difficult
   seed because an empirical RIP/coherence screen or algorithm fails. Such a
   screen may define a named deployment profile with rejection cost reported.
8. Select basis, K, iteration limits, GP line-search safeguards, IHT/HTP step
   size, gOMP group size and LS tolerance on calibration/validation only.
   Report oracle best-K approximation as a bound/diagnostic, never as a way to
   select a different K using the ground truth of each test example.

All eight real algorithms run all available real rows A1-A7 in the common
matrix. A8 is included only for qualified real-embedded or complex variants,
clearly separated. Synthetic exact-sparse Gaussian/Rademacher and coherent-matrix
cases remain a ninth shared control, not an eighth real application substitute.
Publish raw case IDs and an 8-by-application table even when entries fail.

## 5. Metrics and acceptance gates

For physical-domain truth `s`, float reconstruction `sf`, fixed reconstruction
`sq`, and `n` original samples:

```text
MSE(sq)   = sum(|s-sq|^2) / n
NMSE(sq)  = sum(|s-sq|^2) / sum(|s|^2)
SNR(sq)   = -10*log10(NMSE(sq))
PRD(sq)   = 100*sqrt(NMSE(sq))
QERR      = sum(|sq-sf|^2) / sum(|s|^2)
SNR_loss  = SNR(sf) - SNR(sq)
PSNR(sq)  = 10*log10(peak^2/MSE(sq))
```

Peak is the fixed image range after the documented input conversion, never each
reconstruction's maximum. For ECG also report mean-removed `PRDN` with its own
denominator; do not interchange PRD/PRDN. Zero-energy signals and exact-zero
errors need explicit tagged values (`zero_energy`, `perfect`), not silently
dropped rows or JSON infinity. Compute metrics on unrounded physical outputs;
if display clipping is applied, report both unclipped and clipped quality.

Fixed-point degradation limits below follow the initial v4 design targets.
The user selected a **minimum reconstruction SNR of 20 dB for both float and
fixed on every application case**, in addition to relative degradation limits.
For nonzero-energy truth this is NMSE <=0.01. It is output reconstruction SNR,
not measurement/input SNR or image PSNR. This replaces the earlier proposed
15 dB speech/vibration floor and a PSNR-only image floor. These are project
targets, not clinical standards or achieved results. Other application-specific
metrics remain to be frozen before the full test. The numerical configuration
must be the single machine-readable authority; keep this protocol synchronized.

| Gate | Required evidence |
| --- | --- |
| Application reconstruction quality, user-selected floor | Float AND fixed full-original-signal reconstruction SNR >=20 dB on each case, plus relative/no-fault gates. Report all pass/fail counts and the entire grid; pooled averages cannot replace the per-case floor. Centered SNR remains a separately reported diagnostic; no unrequested centered 20 dB gate. Image PSNR/SSIM remain secondary metrics, never substitutes for SNR. Freeze showcase eligibility/pass-rate and secondary-metric policies before held-out testing. |
| Fixed degradation | On each nondegenerate case whose float NMSE >=1e-6: SNR loss <=0.5 dB and `NMSE_fixed <=1.1*NMSE_float`, with no fixed-only application-threshold failure. The NMSE ratio is the tighter limit (about 0.414 dB). Evaluate separately for each algorithm, application and noise stratum; pooled means cannot hide a bad row. |
| Near-exact float cases | If float NMSE <1e-6, avoid an unstable ratio against nearly zero error: require QERR <=1e-6 and report achieved fixed SNR/floor. Keep these cases in the absolute-quality report. |
| Numerical correctness | Zero undetected overflow, saturation, divide-by-zero, invalid support, unreported solver breakdown or failed certificate committed as success. Injected-fault tests must produce the declared rollback/failure result. |
| RTL conformance | Exact integer phase/state agreement with the frozen bit-accurate reference. Float/fixed support differences are measured numerical effects, not automatically RTL bugs; RTL/fixed differences are bugs. |

Application secondary metrics are ECG QRS timing/amplitude preservation, speech
segmental SNR, image SSIM, EEG band-power error, wearable downstream classifier
accuracy change with a frozen classifier, bearing envelope-spectrum peak error,
CAVE spectral angle, and channel beamforming-gain loss. Define their exact
implementations before claiming preserved utility. They cannot be replaced by
SNR alone when the paper claims downstream performance. Do not make clinical
preservation claims from reconstruction metrics.

Report per-source-entity statistics and 95% paired bootstrap confidence intervals
over patients/speakers/images/subjects/scenes/recordings/spatial regions, not over
millions of correlated windows. Give median, p5 quality/p95 error, worst case,
pass count, failure count, exclusions and total case count. Separate algorithm
nonconvergence, fixed numeric faults, unavailable data and unsupported operators.

## 6. How to select fixed-point bits and avoid flattering comparisons

Use a staged experiment with immutable case manifests:

1. Float64 paper implementations and independent tiny-matrix/LS oracles verify
   semantics. Compare every real signal against its float reconstruction first.
   If float quality fails, changing bits cannot solve that application mismatch.
2. Quantize inputs/operator only, retain float compute: quantify acquisition and
   matrix representation loss.
3. Sweep bit-accurate arithmetic, including accumulators, scalar ratios, LS
   stopping/certificates, rounding and explicit overflow behavior. The sweep
   must actually round each intended operation/store. Casting only the final
   float answer is not a fixed-point implementation.
4. Select the smallest Pareto-feasible formats on validation subject to every
   quality/correctness gate. Explore shared storage width with wider
   accumulators/scalars before assuming one Q format everywhere. A bit-count or
   multiply-width proxy is a provisional cost model, not measured LUT/DSP/power.
5. Freeze formats, transforms, iteration/LS policies and case hashes. Run the
   complete held-out suite once. A failed gate means another design revision
   and transparently recorded reevaluation; never relabel the failed test as
   validation without a new held-out set.
6. Only then proceed to complete RTL verification, synthesis and implementation.
   Final optimality is among the enumerated candidate configurations on the
   stated board/tool/version, never an unconstrained global optimum.

Use both a generous convergence budget and quality-vs-cost curves. Equal outer
iteration counts are unfair: GP/MP, IHT, OMP, SP and CoSaMP do different work.
Count applications of A/A^T, restricted LS work, matrix bytes, Top-K work, scalar
divides, kernel/total cycles and time-to-quality. Include timeouts and quality
failures on plots. Keep gOMP's support capacity and correct group selection;
do not cut its support to K solely to match other algorithms' storage.

For the two 4x4 arrays, report useful arithmetic per PE per active cycle,
end-to-end useful-op utilization `useful_PE_op_slots/(32*total_cycles)`, stalled
cycles by reason, inter-array traffic, padding/masked slots and sidecar work.
Define multiply-accumulate's slot accounting once. A busy sidecar with idle PEs
does not demonstrate array utilization. Quality-matched cost is required before
claiming an algorithm or schedule advantage.

## 7. Sensible expansion beyond eight

Prioritize **FISTA, ADMM and PDHG**: accelerated proximal gradient,
augmented-Lagrangian splitting with an SPD inner solve, and primal-dual
splitting. Use the same LASSO objective and validation-selected lambda for the
FISTA/ADMM-LASSO/PDHG-LASSO conformance and fair solver comparison. The preferred
future PDHG application showcase is **anisotropic-TV image reconstruction**, described
below. Count one PDHG family, for eleven target algorithm entries overall.
ISTA is a FISTA-family ablation, not another family counted separately; more
OMP variants are not the priority.
Exact equations, source papers, step constraints, kernel/state needs and
optional AMP qualification are in
[ALGORITHM_EXPANSION.md](ALGORITHM_EXPANSION.md).
Do not compare K and lambda as if they were the same parameter. A new RTL
algorithm requires its own golden contract. Exploratory unweighted-LASSO
FISTA/ADMM/PDHG numerical models exist in
[proximal.py](../../models/v4/proximal.py), with
[numerical tests](../../verification/v4/test_proximal.py). Weighted LASSO,
PDHG-TV, their compiled CGRA/RTL schedules and real-dataset application results
remain future qualification work; existing numerical models do not establish
those hardware or application claims.

For `PDHG_TV_ANISO_NEUMANN`, reuse the BSDS source-image split, grayscale
conversion, physical image target and pixel-domain measurements `y=Phi*s+e`.
Initially reconstruct independent 16x16 sensed patches with true patch-boundary
Neumann differences and explicitly report seam artifacts. The variable is the
pixel image x, with objective `0.5*||Phi*x-y||2^2+lambda*||D*x||1`; D comprises
horizontal/vertical nonperiodic unit-grid forward differences. Do not insert
the LASSO synthesis transform into this TV operator. If later running whole-image
TV on tiled hardware, internal tile seams require halos and cannot become
artificial Neumann boundaries.

This TV showcase is a **different-prior quality/cost comparison**, not the
identical-objective LASSO comparison. Choose lambda independently on validation;
report PSNR/SSIM, TV objective, KKT residuals and total cycles. A match to image
quality alone is not solver correctness. Add a piecewise-constant synthetic
phantom as a sanity control, without replacing the public image test set or
discarding texture-heavy images that are difficult for TV.

The proposed architectural purpose is concrete two-dimensional mesh work: D uses east/
south values and D^T uses west/north dual values on each physical 4x4 tile.
Inter-array/inter-tile halos travel through scheduled scratchpad accesses;
there is no invented direct edge between the arrays. Include halo traffic,
registered-route latency, masks and snapshot barriers. The equations, explicit
adjoint, conservative `tau*sigma*(||Phi||2^2+8)<1` condition and TV-specific
certificate requirements are in [ALGORITHM_EXPANSION.md](ALGORITHM_EXPANSION.md).
No TV numerical solver or halo schedule is implemented in this pass. A legal
cycle schedule and measured traffic/utilization must demonstrate that the
two-dimensional mapping is useful before it becomes an architectural result.

MRI is a strong additional application for these baselines, but it is not an
immediate anonymous download in this project: the
[NYU fastMRI portal](https://fastmri.med.nyu.edu/) requires an application and
Data Sharing Agreement. This research run has not obtained access. A future
single-coil task would use actual undersampled k-space `P*F*Psi`, patient-level
splits, fixed masks, complex arithmetic and image NMSE/PSNR/SSIM, following the
[dataset paper](https://arxiv.org/abs/1811.08839). A synthetic phantom may verify
that operator now, but it must not be called a fastMRI dataset result.
