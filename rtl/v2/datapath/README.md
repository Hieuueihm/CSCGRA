# RTL v2 datapath helpers

- `lfsr_phi.v`: deterministic fixed-point sensing-matrix/Phi generation.
- `reduce_scan.v`: generic scan/reduction helper used outside the specialized
  sparse PE wavefronts.

These files are synthesizable and included through `rtl/v2/files.f`.
