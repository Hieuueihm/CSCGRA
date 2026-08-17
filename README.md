# CSCGRA

This repository keeps source code separate from disposable Vivado/XSim output.
The RTL is intentionally preserved as two independent, reproducible versions:

- `rtl/v1`: original optimized architecture snapshot.
- `rtl/v2`: active strict-PE0, four-row, factor-reuse architecture.

## Current signed-off RTL v2

The current RTL checkpoint is `88f9411` on
`codex/strict-pe0-timing`:

- full K-sweep: 348 PASS / 0 FAIL, with two expected K16 capacity skips;
- 62 measured algorithm/case rows and 1,313,368 total cycles;
- K8 total: 374,962 cycles;
- 100 MHz OOC: WNS +0.850 ns, TNS 0;
- 121,359 LUT, 53,281 FF, 24 RAMB36, and 71 DSP.

Start with [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for the complete
implemented-optimization inventory, rejected-trial list, ownership map, and
current sign-off evidence.

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

`CSCGRA_opt_architecture_opt2/` and the other pre-refactor project directories
may still exist locally, but they are ignored archives. They are not compiled
by the canonical flow and are not the source of truth.

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
versioning rules, and each major folder's README for its local contents.
