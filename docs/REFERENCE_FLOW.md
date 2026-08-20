# Reference-to-RTL contract

This project uses one strictly forward correctness chain:

```text
models/reference/canonical.py
        |
        | explicit numerical/architectural conversion
        v
models/reference/hardware.py
        |
        | generated, bit-exact hardware golden
        v
rtl/v2 + verification/v2
        |
        | correctness is frozen first
        v
timing, cycle, resource and synthesizability optimization
```

There are exactly two authoritative executable reference sources. Files under
`models/golden` are frozen input data, generated artifacts, audits, or legacy
provenance; they are not a third source of algorithm truth.

## Gate 1: canonical algorithm

`models/reference/canonical.py` owns the mathematical algorithms. It uses
floating-point arithmetic and has no Q format, LDLT schedule, PE topology,
support-memory limit, RTL state, or generated-golden dependency.

A canonical change is accepted only when its iteration sequence agrees with
the cited algorithm definition and its standalone tests pass. A mismatch at a
later stage never authorizes changing the canonical result to match hardware.

## Gate 2: hardware Python

`models/reference/hardware.py` is a deliberate hardware realization of the
canonical equations. It owns all implementation-visible numerical choices:

- signed 24-bit Q16 data, saturation and truncation/rounding points;
- fixed iteration and support capacities;
- normal equations, diagonal regularization and LDLT least-squares solve;
- factor reuse and ordering rules;
- deterministic top-K tie breaking; and
- the input-vector and generated-golden formats.

Every departure from the canonical algorithm must be named as a hardware
constraint or an approved architecture variant. Fixed point, LDLT and bounded
storage are valid transformations; silently replacing one algorithm with a
different algorithm is not.

The hardware model is the sole generator of:

- `verification/v2/run1/k_sweep_golden_hardware.vh`; and
- `sw/v2/src/cscgra_k_sweep_golden.h`.

Both generated files are immutable during RTL debug. If RTL fails, fix RTL or
reject the RTL trial. Change `hardware.py` only after reviewing a forward
change from the canonical definition.

## Gate 3: RTL correctness

The default v2 regression consumes only the hardware golden and requires
bit-exact output (`tolerance = 0`). RTL is correct only after all in-scope
algorithms and K cases pass. Phase traces may explain a mismatch, but they may
not become an alternative golden.

Architectural invariants remain part of correctness:

- data enters the arithmetic fabric at PE0 and propagates toward lower rows;
- large operations assign useful work to all four PE rows;
- only one LS request is active; and
- registered control/data boundaries do not change fixed-point semantics.

## Gate 4: implementation optimization

Timing, cycle, area and synthesizability work starts only after Gates 1--3
pass. Each candidate is kept only after, in this order:

1. hardware-golden regression passes;
2. per-algorithm cycle counts are recorded;
3. synthesis completes with unchanged intended DSP/BRAM use, unless a tradeoff
   is approved; and
4. routed timing is measured, with the project target `WNS >= +0.2 ns`.

An optimization cannot change `canonical.py`, `hardware.py`, or generated
golden values merely to recover a PASS.

## Current migration status

| Algorithm | canonical -> hardware semantics | RTL -> hardware | Status |
| --- | --- | --- | --- |
| OMP | fixed Q16 + LDLT | exact hardware golden | active |
| CoSaMP | Q16 + LDLT; merge capped at 16 | exact hardware golden for supported cases | documented capacity variant |
| IHT | Q16, `mu = 1/8` | exact hardware golden | active |
| HTP | Q16, `mu = 1/8`, LDLT | exact hardware golden | active |
| SP | Q16 + LDLT; merge capped at 16 | exact hardware golden for supported cases | documented capacity variant |
| GP | restricted Q16 gradient + projected line search | exact hardware golden | active |
| gOMP | Q16 + LDLT | exact hardware golden | active |
| MP | Q16 normalized projection | exact hardware golden | active |

CoSaMP/SP K16 remain outside the current 16-entry candidate/LS capacity. They
must remain explicit capacity variants unless that storage/LS dimension is
expanded and revalidated.

The latest end-to-end result is recorded in
`reports/v2/reference_contract_signoff_20260820.md`: exact regression passes,
OOC synthesis passes, and routed setup timing remains open at WNS -0.356 ns.

## Required checks

```powershell
python scripts/maintenance/check_reference_contract.py
python models/reference/hardware.py --check --c-output sw/v2/src/cscgra_k_sweep_golden.h
python models/golden/audit_algorithm_semantics.py --output models/golden/canonical_audit.md
.\scripts\run.ps1 -Flow sim -RtlVersion v2
```
