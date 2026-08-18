# CSCGRA

This repository keeps source code separate from disposable Vivado/XSim output.
The repository keeps one active architecture line and one frozen historical
snapshot:

- `rtl/v2`: active strict-PE0, four-row, factor-reuse architecture.
- `rtl/v1`: frozen provenance baseline; it is not part of the paper's active
  design or canonical optimization flow.

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
| `rtl/v2` | Active synthesizable RTL | Yes |
| `rtl/v1` | Frozen historical RTL baseline | Yes |
| `verification/` | Testbenches, golden vectors, and file lists | Yes |
| `sw/` | C applications and generated headers | Yes |
| `models/` | Golden/reference models | Yes |
| `scripts/` | Canonical flows and archived legacy scripts | Yes |
| `docs/` | Architecture and historical documentation | Yes |
| `reports/` | Reviewed baseline/release summaries | Yes |
| `research/` | Reproducible experiments and analysis source | Yes |
| `work/` | Vivado/XSim/Verilator working directories | No |
| `logs/` | Raw simulation, synthesis, and implementation logs | No |

Pre-refactor local project directories are ignored and are not compiled by the
canonical flow. They are not the source of truth and are excluded from the
public checkout.

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
