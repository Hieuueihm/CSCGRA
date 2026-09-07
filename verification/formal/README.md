# Formal verification

This directory contains the formal safety layer for the active `rtl/v2`
source. The single project status is [CURRENT_STATUS.md](../../reports/v2/CURRENT_STATUS.md).

The properties are compiled only when `FORMAL` is defined, so the canonical
Vivado 2018.1 synthesis and simulation filelist is unchanged. The harnesses
leave datapath values arbitrary and constrain only interface contracts.

Current proof tasks:

- `dma`: legal FSM/channel combinations, burst bounds, and read-error drain;
- `factor`: support/tag bounds and normalized-support capacity; and
- `matrix`: matrix/RHS bounds and service-state safety; and
- `wide`: wide-multiplier FSM and token consistency.

Run all proofs with SymbiYosys/Yosys/Boolector:

```powershell
.\scripts\run.ps1 -Flow formal -RunId current-formal
```

If the formal toolchain is not installed, syntax-elaborate every harness with:

```powershell
.\scripts\formal\run_formal.ps1 -Task all -LintOnly
```

A syntax pass is not a proof. Release status remains `UNVALIDATED` until all
four SymbiYosys tasks complete successfully for the recorded RTL SHA-256.
