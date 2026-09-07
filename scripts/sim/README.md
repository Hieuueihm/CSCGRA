# Simulation scripts

Run the complete v3 M1-M7 model, simulation and property regression with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_v3_m1_m7.ps1 -SkipSynthesis
```

Python discovery prefers `CSCGRA_PYTHON`, an active virtual environment,
`.venv`, then installed Python 3 launchers. The selected interpreter must have
the modules in `requirements-v3.txt`.

`run_regression.ps1` is the canonical XSim regression worker. Normally invoke
it through `scripts/run.ps1`, which selects the RTL version from `config/`,
creates an isolated run directory under `work/`, and writes raw logs under
`logs/`.

Do not add generated XSim products to this directory.

Focused v3 Vivado/XSim gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/sim/run_axilite_control.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m2.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m3.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m4.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m1_m4_integration.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m5.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m6.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m7.ps1 -EnableProperties
```

`run_m3.ps1` regenerates the compiler-owned M3 image before compiling the RTL
and fails on either a testbench `FAIL:` marker or an `Assertion violation`.

`run_m1_m4_integration.ps1` is the first cross-milestone XSim gate. It keeps
the production top untouched and verifies CSR START, shared DMA ownership,
run-configuration commit, phase/context execution, preload residency and one
bit-exact vector read in one scenario.

`run_m6.ps1` regenerates the Python-owned PE opcode vectors and checks the
homogeneous two-cluster fabric with Vivado/XSim. It does not invoke another RTL
simulator.

`run_m7.ps1` regenerates Threefry/normalizer vectors and checks generator
latency/II, gearbox conservation, cache fill/capture/promote/replay, provider
modes, backpressure, STOP flush and embedded assertions.
