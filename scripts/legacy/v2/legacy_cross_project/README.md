# Legacy cross-project scripts

These scripts intentionally target sibling workspaces such as `CSCGRA_opt`,
`CSCGRA_noisy_mu`, `CSCGRA_gp_opt`, or external analysis directories. They are
retained for provenance, but they are not part of the opt2 build or regression
flow.

New opt2 automation must derive the repository path from the script location
and belong in the parent `scripts/` directory.

The migrated `run_8alg_*`, `regenerate_mp_gp_golden.py`, and
`regression_summary.*` files are historical model experiments. The canonical
K-sweep generator is now `models/golden/generate_k_sweep_golden.py`; these
legacy files must not be used to regenerate public v2 golden data.
