# Frozen Golden Models for 8 Algorithms

Source frozen from D:\vivado_pj\analysis\m64n256k16 on 2026-06-22.

Configuration:
- M = 64
- N = 256
- K = 16
- GOLD_ALGS = 8
- Algorithms / alg_idx:
  - 0: OMP
  - 1: gOMP
  - 2: CoSaMP
  - 3: SP
  - 4: IHT
  - 5: HTP
  - 6: GP
  - 7: MP

Files:
- golden_cases.vh: frozen function-based fixed-point golden for per-iter support/x/residual checks.
- golden_cases_array.vh: frozen array-form companion include.

Hashes:
- golden_cases.vh SHA256: $hash
- golden_cases_array.vh SHA256: $hash2

Rules:
- Treat these files as read-only golden references.
- RTL/TB must follow this golden; do not regenerate/modify to fit RTL failures.
- OMP regression uses slow/reference context flow unless explicitly testing fast mode separately.
