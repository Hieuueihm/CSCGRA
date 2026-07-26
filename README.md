# CSCGRA

This repository keeps source code separate from disposable Vivado/XSim output.
The RTL is intentionally preserved as two independent, reproducible versions:

- `rtl/v1`: original optimized architecture snapshot.
- `rtl/v2`: current factor-reuse architecture and optimization baseline.

## Repository layout

| Path | Purpose | Tracked by Git |
| --- | --- | --- |
| `rtl/v1`, `rtl/v2` | Versioned synthesizable RTL | Yes |
| `verification/` | Testbenches, golden vectors, and file lists | Yes |
| `sw/` | C applications and generated headers | Yes |
| `models/` | Golden/reference models | Yes |
| `scripts/` | Canonical flows and archived legacy scripts | Yes |
| `docs/` | Architecture and historical documentation | Yes |
| `reports/` | Reviewed baseline/release summaries | Yes |
| `research/` | Reproducible experiments and analysis source | Yes |
| `work/` | Vivado/XSim/Verilator working directories | No |
| `logs/` | Raw simulation, synthesis, and implementation logs | No |

Pre-refactor local workspaces and generated artifacts are retained under
`work/legacy_pre_refactor` in this checkout. That archive is ignored and does
not appear in a fresh clone.

## Canonical commands

Run the full K-sweep for RTL v2:

```powershell
.\scripts\run.ps1 -Flow sim -RtlVersion v2
```

Run selected cases or algorithms:

```powershell
.\scripts\run.ps1 -Flow sim -RtlVersion v2 -Cases 0 -Algorithms 0
```

Run out-of-context synthesis:

```powershell
.\scripts\run.ps1 -Flow synth -RtlVersion v2 -Top cgra_top
```

Every invocation creates an isolated directory under `work/` and stores raw
logs under `logs/`. Running a flow must not dirty the Git worktree.

See [docs/REPOSITORY_LAYOUT.md](docs/REPOSITORY_LAYOUT.md) for ownership and
versioning rules.
