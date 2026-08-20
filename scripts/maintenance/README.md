# Maintenance scripts

- `check_layout.ps1`: validates manifests, golden hashes, and rejects stale active-project paths.
- `check_reference_contract.py`: enforces the canonical -> hardware -> RTL
  dependency direction and verifies active generated-golden ownership.
- `compare_regression.ps1`: compares regression result sets.
- `audit_rtl.py`: static RTL inventory/audit helper.

These scripts inspect or validate the tracked project layout. They are not RTL
compile sources.
