# V3 numerical baseline provenance

The baseline is a byte snapshot, not a release or numerical PASS. Old reports
and generated goldens are never overwritten to make a candidate pass.

## Freeze and run

Use the Python executable recorded in the manifest. From the repository root:

    python scripts/maintenance/v3_baseline_provenance.py freeze --baseline reports/v3/BASELINE_TAG/source
    python scripts/maintenance/v3_baseline_provenance.py verify --baseline reports/v3/BASELINE_TAG/source
    python scripts/maintenance/v3_baseline_provenance.py run --baseline reports/v3/BASELINE_TAG/source --run-dir reports/v3/BASELINE_TAG/runs/brainweb --evidence reports/v3/BASELINE_TAG/brainweb/results.json -- python scripts/numeric/v3_brainweb_sweep.py --offline --require-manifest --out-dir reports/v3/BASELINE_TAG/brainweb

The source ZIP captures tracked and untracked v3 RTL, compiler, model,
verification/goldens, architecture/context reports, contracts, constraints and
supporting scripts. Source inventory hashes are checked before and after each
command. Git HEAD alone is not source identity in a dirty checkout.

Each run records its command, working directory, Python/package environment,
source tree digest, exit code, stdout/stderr hashes and requested output hashes.
Source drift, command failure, missing output or pre-existing output prevents
a PASS. Use a new output directory for every attempt. Dataset bytes remain in
the offline cache and are checked against the frozen source manifest; the ZIP
does not redistribute the medical datasets. The local ZIP is ignored by Git
and must be retained separately for reproducibility.

## Reference goldens

Generate current-source smoke/scale packages into a fresh baseline directory,
then use the unchanged semantic checks against that directory:

    python scripts/golden/generate_v3_phase_golden.py --suite smoke --out-dir reports/v3/BASELINE_TAG/golden
    python scripts/golden/generate_v3_phase_golden.py --suite scale --out-dir reports/v3/BASELINE_TAG/golden
    python scripts/maintenance/check_v3_reference_contract.py --golden-dir reports/v3/BASELINE_TAG/golden

Wrap each command with the provenance runner when recording evidence. These
packages are staging evidence only; they do not silently replace the canonical
verification/v3/golden directory or validate RTL against the new package.

## Numerical failures

The diagnostic runner replays the failed samples selected by a frozen BrainWeb
result, verifies dataset checksums, and retains source blocks, measurement
vectors and per-phase traces. It compares the floating reference against the
independent oracle. Precision, gain and certificate variants are diagnostic
only; none is a supported RTL configuration or a new production profile.

A successful failure-reproduction audit means the failures were reproduced,
not that they were fixed. Do not loosen quality thresholds, change seeds,
selectively exclude failed patches, or merge different-source PASS results.
Numerical closure requires a separately named candidate, the entire frozen
432-case sweep, broader validation and matching RTL regression before promotion.
