# Reference models

Only two executable files are authoritative:

1. `reference/canonical.py` is the independent floating-point mathematical
   definition of the eight algorithms.
2. `reference/hardware.py` is the fixed-point/LDLT hardware realization and
   the sole generator of the active Verilog and C golden outputs.

The required direction is canonical -> hardware Python -> RTL. See
[`docs/REFERENCE_FLOW.md`](../docs/REFERENCE_FLOW.md) for the gates and current
algorithm status.

`golden/` contains frozen input vectors, generated/audit artifacts and legacy
migration tools. In particular, `canonical_fixed.py` and `abstract_rtl.py` are
historical provenance, not additional active references. Models are not
synthesizable source and are never compiled into RTL.
