# Reference models

The repository has two version-scoped reference chains.

For the active v3 redesign, the authoritative files are:

1. `v3/paper.py`: independent floating-point definitions tied to the primary
   papers.
2. `v3/hardware.py`: the bit-accurate D18F14/S28F20/A64 realization and phase
   trace generator. It must preserve the paper algorithm; its PCG solver uses
   `lambda=0`.

The required v3 direction is paper -> hardware Python -> phase golden -> RTL.
See [`docs/v3/02_ALGORITHM_CONTRACT.md`](../docs/v3/02_ALGORITHM_CONTRACT.md).

For the maintained v2 implementation, the authoritative files remain:

1. `reference/canonical.py` is the independent floating-point mathematical
   definition of the eight algorithms.
2. `reference/hardware.py` is the fixed-point/LDLT hardware realization and
   the sole generator of the active Verilog and C golden outputs.

The required v2 direction is canonical -> hardware Python -> RTL. See
[`docs/REFERENCE_FLOW.md`](../docs/REFERENCE_FLOW.md) for the gates and current
algorithm status.

`golden/` contains frozen input vectors, generated/audit artifacts and legacy
migration tools. In particular, `canonical_fixed.py` and `abstract_rtl.py` are
historical provenance, not additional active references. Models are not
synthesizable source and are never compiled into RTL.
