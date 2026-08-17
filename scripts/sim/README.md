# Simulation scripts

`run_regression.ps1` is the canonical XSim regression worker. Normally invoke
it through `scripts/run.ps1`, which selects the RTL version from `config/`,
creates an isolated run directory under `work/`, and writes raw logs under
`logs/`.

Do not add generated XSim products to this directory.
