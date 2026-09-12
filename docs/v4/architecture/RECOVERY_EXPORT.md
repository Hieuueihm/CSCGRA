# Native recovery program export

## Feature4 QR append qualification

Profile `reuse` adds generic FACTOR_EXTEND(op19) under the existing program
revision2. OMP/GOMP prove an exact ordered support prefix and immutable Phi/Y;
BUILD_B advances the B generation, and EXTEND imports only new columns at the
next generation. Shrink/reorder/mismatch uses INIT. Corrections still apply
all reflectors and the stored-X certificate is unchanged. The generic backend
checks shape/identity; it does not infer support membership from dimensions.

[QR reuse contract](QR_REUSE.md) records the inert loaded template, generation,
mask and publication rules. [The paired XSim report](../../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md)
qualifies all20 fixed8 cases. Later resident/panel-chain/scalar-patch work is
separate; CPU AXI and board timing remain unimplemented/unqualified.

Run from the project root with the project Python runtime:

```powershell
python -m scripts.v4.export_recovery input.json work/exported_omp --qr-profile balanced --target-kernel-revision 2
```

## Explicit profile navigation

`balanced` remains the compatibility default. It does not select any staged
range transport. The installed `compact` profile remains explicit at kernel
revision6. The `streamed` profile also requires revision6 and uses the
existing SCALAR_INSERT command for QR reflector tau, beta, and head values.

The `view` profile requires kernel revision7. It retains the streamed
scalar publications and emits command-scoped RANGE_TEMPLATE reads for the QR
backsolve and QTy slice uses. Export it explicitly only against a matching
feature7 runtime:

```powershell
python -m scripts.v4.export_recovery input.json work/exported_view --qr-profile view --target-kernel-revision 7 --qr-panel-min-columns 1
```

`qr_panel_min_columns` is an input schedule threshold. The measured common choice is1 for M32/N64/K8 and M64/N256/K8, actual8 iterations; it does not change the default `balanced` profile. [Final source-bound evidence and tradeoffs](../../../reports/v4/context_stream_final_20260910/README.md) and [installation manifest](../../../reports/v4/context_stream_promotion_20260910/before_after_manifest.json) record qualification. Application quality, production bits and board timing remain separate gates.

## Feature8 operand-chain opt-in

`--operand-chains` is separate from QR profile selection. It requests the
feature8 `ROUNDED_AFFINE` command only at the existing non-QR sites in GP, IHT,
FISTA, and PDHG. Its result is `C +/- round22(X*Y)`: the product retains the
old S27 rounding boundary before the loaded ADD or SUB, and no intermediate
product is published to the vector pool. It requires a matching revision8
runtime:

```powershell
python -m scripts.v4.export_recovery input.json work/exported_affine --qr-profile view --qr-panel-min-columns 1 --operand-chains --target-kernel-revision 8
```

The flag defaults to false. MP and all QR programs retain their established
program images because they contain no selected affine site; the package still
records the requested suite option. The [command-flow diagram](../diagrams/rounded_affine.mmd)
is descriptive. Export and software checks are not RTL, fixed8, application
quality, board timing, or production-bit qualification.

Example `input.json`:

```json
{
  "algorithm": "OMP",
  "operator": {"kind": "lfsr32", "seed": 305419896, "rows": 64, "columns": 256, "scale_raw": 8192},
  "policy": {"sparsity": 8, "max_iterations": 8},
  "qr_max_refinements": 2
}
```

The exporter writes the existing native program/package and ordered loader records. `load.txt` uses explicit LF bytes matching `load_sha256`. The host publishes the matching live Phi and loads the measurement vector identified by the package before START. The generated program owns all iterations; this command does not generate a host loop or preload arbitrary matrices.

The new CLI defaults to `balanced`: compact QR scheduling,
[scalar-template arithmetic](SCALAR_TEMPLATE.md) using kernel revision 2, and
per-job exact certified-result caches (OMP/GOMP 0, CoSaMP/SP 2, HTP 1 entries).
Cache identities compare the complete ordered support; every START clears cache
validity. The cache is compiler-emitted generic program/vector-pool state, not
a hardware cache module or request boundary. Existing Python compiler callers
retain the `reference` default. Use `--qr-profile reference
--target-kernel-revision 1` for the previous schedule. An incompatible revision
is rejected.

For MP/GP/IHT, select the separately qualified sparse forward implementation with `--sparse-forward` or an input `sparse_forward` field. Other algorithms reject that option. Policies are explicit input values and are never adjusted by the exporter. Export success does not certify recovery quality for a particular signal.

FISTA/ADMM/PDHG accept the existing proximal-policy fields. QR algorithms accept at most two refinement attempts. The package records required kernel features, schedule profile, operator identity parameters, and input/exporter hashes.
