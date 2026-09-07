# 25 - V3 MRI source-domain evaluation protocol

Date: 2026-09-02

## 1. Objective and claim boundary

This protocol separates two error sources:

1. **Source/oracle loss** caused by blockwise orthonormal `8x8` DCT
   sparsification with `K=8` retained coefficients.
2. **Fixed-point degradation** between the V3 fixed-point model and the
   floating-point paper model for the same sensing matrix, sparse target,
   algorithm and refinement policy.

The current V3 acquisition operator is a real signed-Bernoulli `M x N` matrix.
BrainWeb and fastMRI are therefore evaluated as MRI **source images**. fastMRI
complex k-space is inverse-transformed into a magnitude or root-sum-of-squares
image before entering the V3 source-domain path.

Allowed claim:

> The V3 `D18F14/S27F19/A62` fixed-point implementation preserves the
> floating-point reconstruction quality on the evaluated synthetic, simulated
> and, after official-data closure, real-MRI source images.

Not allowed without a different RTL operator and additional evidence:

- direct raw-k-space or Fourier-domain RTL reconstruction;
- clinical-grade reconstruction or diagnostic equivalence;
- radiologist validation;
- generalization to fastMRI while its official-data gate is `NOT_RUN`;
- treating algorithm-patch evaluations as independent patients or volumes.

## 2. Data sources

### 2.1 Shepp-Logan

- Analytical phantom from `skimage.data.shepp_logan_phantom`.
- Deterministic synthetic baseline.
- Evidence: `reports/v3/mri_paper_quality_gate`.

### 2.2 BrainWeb

- Provider: BrainWeb Simulated Brain Database, McGill University.
- Anatomical models: normal brain and brain with MS lesions.
- Modalities: T1, T2 and proton density (PD).
- Slice thickness: `1 mm`; in-plane sampling is `1x1 mm`.
- Noise: `0%`, `3%`, `9%` (`pn0`, `pn3`, `pn9`).
- RF/intensity non-uniformity: `0%`, `20%`, `40%`
  (`rf0`, `rf20`, `rf40`).
- Full-factorial coverage: `2 x 3 x 3 x 3 = 54` volumes.
- Source slices are fixed before inspection: `45, 67, 90, 112, 135`.
- Fixed-point sampling uses frozen slices, the central 50% field-of-view ROI,
  and deterministic variance quantiles of non-constant `8x8` blocks. This
  excludes empty/background borders without selecting only high-variance blocks.
- Every compressed volume is frozen by SHA-256 in
  `config/v3_brainweb_sweep_manifest.json`.

The authoritative evidence is the second offline run with
`--require-manifest`. The initial download-and-capture run alone is not
provenance closure.

### 2.3 fastMRI

- Only official NYU fastMRI HDF5 downloads may populate the evidence manifest.
- Each entry freezes file path, SHA-256, anatomy, acquisition, split and
  deterministic slice indices.
- Each entry requires `official_download_attested=true`.
- Required HDF5 schema: `kspace`, `ismrmrd_header`, and either
  `reconstruction_rss` or `reconstruction_esc`.
- Multicoil data uses inverse FFT plus root-sum-of-squares.
- Single-coil data uses inverse FFT plus magnitude.
- The derived source is center-cropped to the official reference geometry.
- Derived-versus-official metrics expose loader, centering and geometry errors;
  they do not imply direct k-space RTL operation.

The default paper-coverage floor requires 20 files, 100 frozen slices, and both
knee and brain anatomy. This is engineering coverage, not a clinical sample-size
justification.

## 3. Frozen numeric contract

- Algorithms: OMP, CoSaMP, IHT, HTP, SP, GP, GOMP and MP.
- Quality geometry: `M=32`, `N=64`, `K=8`.
- Transform: orthonormal 2-D DCT-II on `8x8` blocks.
- Numeric profile: data `D18F14`, state `S27F19`, accumulator `A62`.
- Refinement policy: `strict_paper`.
- Floating authority: `models/v3/paper.py`.
- Fixed-point authority: `models/v3/hardware.py`.

No threshold may be relaxed and no golden value may be edited to make RTL pass.

## 4. Preprocessing and sampling

1. Convert the source to a real magnitude image.
2. Center-crop to a square field of view.
3. Normalize intensities to `[0, 1]`.
4. Resize to `256x256` with anti-aliasing for source/oracle metrics.
5. Split into non-overlapping `8x8` blocks and retain the eight largest DCT
   coefficients with deterministic magnitude/index tie-breaking.
6. For fixed-versus-floating tests, center values around zero, restrict sampling
   to the central 50% field-of-view ROI, sort non-constant blocks by variance,
   and choose fixed quantiles of that distribution.
7. Scale each sparse coefficient target so `max(abs(x_K)) = 0.75` before the
   sensing matrix and undo the same scale after reconstruction. This is the
   production fixed-point input-normalization contract, not a per-algorithm
   tuning step.

Absolute source quality uses every frozen source slice. Fixed-point evaluation
uses an explicit bounded subset because eight iterative algorithms run for each
selected block.

## 5. Metrics and statistics

For reference `x`, estimate `x_hat` and error `e=x-x_hat`:

- `MSE = mean(e^2)`.
- `NMSE = sum(e^2) / sum(x^2)`.
- `SNR = 10 log10(sum(x^2) / sum(e^2))` dB.
- `PSNR = 10 log10(data_range^2 / MSE)` dB.
- `SSIM` uses scikit-image structural similarity and measured data range.

Reports preserve count, mean, median, standard deviation, P05, P95, minimum and
maximum, plus per-volume, per-slice, per-block and per-algorithm JSON/CSV rows.

## 6. Fixed-point pass criteria

Every algorithm-block evaluation must satisfy:

- application SNR loss `<= 0.5 dB`;
- fixed/floating application MSE ratio `<= 1.10`;
- fixed/floating application NMSE ratio `<= 1.10`;
- application SSIM drop `<= 0.005`;
- zero saturation, overflow, divide-by-zero and refinement-breakdown events.

Fixed-versus-floating SSIM is reported but is not an absolute gate on `8x8`
patches because SSIM is unstable when both patches have low dynamic range. The
gated SSIM quantity is the change against the same original block.

Support equality is reported but software fixed-point quality can accept an
alternative finite-point support only when all reconstruction-quality thresholds
pass. RTL correctness remains an exact frozen algorithm/profile contract.

## 7. Evidence interpretation

- A **volume** is one BrainWeb volume or fastMRI acquisition.
- A **slice** is one frozen two-dimensional image.
- A **block** is one `8x8` fixed-point input.
- An **algorithm evaluation** is one algorithm on one block.
- `432/432` means 54 blocks times eight algorithms, not 432 images, subjects or
  acquisitions.

The whole-image `N=1024/K=32` test is a stress diagnostic only. It retains
3.125% of one global DCT and mixes severe sparsification loss with arithmetic
quality; it is not the MRI image-quality authority.

## 8. Reproduction

```powershell
# Download and freeze the full BrainWeb matrix.
D:\Holography\pybuild\python.exe scripts/numeric/v3_brainweb_sweep.py --write-manifest

# Authoritative offline BrainWeb rerun.
D:\Holography\pybuild\python.exe scripts/numeric/v3_brainweb_sweep.py --offline --require-manifest

# Official fastMRI evaluation after populating its manifest.
D:\Holography\pybuild\python.exe scripts/numeric/v3_fastmri_source_quality_gate.py --data-root D:\datasets\fastmri --require-data

# Deterministic synthetic/single-BrainWeb baseline.
D:\Holography\pybuild\python.exe scripts/numeric/v3_mri_paper_quality_gate.py --skip-global-stress
```

## 9. Evidence paths

- `reports/v3/mri_paper_quality_gate`.
- `reports/v3/brainweb_sweep`.
- `config/v3_brainweb_sweep_manifest.json`.
- `reports/v3/fastmri_source_quality_gate`.
- `config/v3_fastmri_source_manifest.json`.
- `reports/v3/GOLDEN_STATUS.md`.

## 10. Project gate order

MRI evidence does not replace RTL correctness. Closure order remains:

1. validate mathematical and fixed-point golden;
2. close exact RTL correctness `8 algorithms x 3 profiles = 24/24`;
3. optimize RTL structure for `100 MHz` with minimal directives;
4. report cycles and `runtime_us = cycles / 100` at 100 MHz.
