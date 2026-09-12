# Physical gate - September 11, 2026

- Actual Vivado 2018.1 synthesis run, default directives, `xczu7ev-ffvc1156-2-e`, 10 ns OOC clock. The preceding check-only preflight passed.
- Synthesis failed during RTL elaboration; opt/place/route were not reached.
- First fatal error: `Synth 8-524`, `factor_panel_service.sv:340`, part-select `[890:864]` outside `fabric_out_data[863:0]`. The R4 expression uses `comb_lane*4` while the containing loop also elaborates higher lane indices. No RTL fix was made in this measurement run.
- `Synth 8-4767` warnings also dissolve factor-store RAM banks into registers; no resource conclusion can be drawn before successful synthesis.
- The 76 RTL/header hashes in `evidence.json` match the cycle-qualified run. Source copies are retained in the parent `source_snapshot/`; the actual physical-run snapshot remains in `work/v4_impl_payload_20260911/source_snapshot/`.
- LUT/FF/BRAM/DSP, WNS/TNS, Fmax and routing/DRC qualification are unavailable, not zero or historical substitutes.
- The flow has only an internal OOC clock constraint; interface/board timing and actual maximum-frequency search are outside its scope.

## Reproduce after a separately verified fix

```text
C:\Xilinx\Vivado\2018.1\bin\vivado.bat -mode batch -source scripts/v4/run_synth_impl.tcl -tclargs -stage impl -clock_ns 10.0
```

Use a fresh output directory and preserve this failed run. First make any HDL
indexing/inference correction pass focused XSim and the required full-program
bit-exact regressions; do not change the golden results to match a fix.
