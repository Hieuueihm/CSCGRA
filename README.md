# CSCGRA

This repository keeps source code separate from disposable Vivado/XSim output.
The repository keeps one active architecture line and one frozen historical
snapshot:

- `rtl/v2`: active strict-PE0, four-row, factor-reuse architecture.
- `archive/v1/rtl`: frozen provenance baseline; it is not part of the paper's
  active design or canonical optimization flow.

## Current RTL v2 validation state

The active correctness contract is:

```text
canonical Python -> hardware Python (Q16/LDLT) -> exact RTL golden -> RTL v2
```

The current working checkpoint passes 348 checks with 0 failures; CoSaMP and
SP at K16 are explicit capacity exclusions. OOC synthesis passes at +0.374 ns,
but routed WNS is -0.356 ns, so it is not yet the 100 MHz timing sign-off.
See [docs/REFERENCE_FLOW.md](docs/REFERENCE_FLOW.md) for the ownership rules and
[reports/v2/reference_contract_signoff_20260820.md](reports/v2/reference_contract_signoff_20260820.md)
for exact correctness, cycle, resource, and routed-timing evidence.

Start with [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for the complete
implemented-optimization inventory, rejected-trial list, ownership map, and
current sign-off evidence.

## Repository layout

| Path | Purpose | Tracked by Git |
| --- | --- | --- |
| `rtl/v2` | Active synthesizable RTL | Yes |
| `verification/v2` | Active testbenches, golden vectors, and file lists | Yes |
| `sw/v2` | Active C applications and generated headers | Yes |
| `models/` | Golden/reference models | Yes |
| `scripts/` | Canonical flows and maintenance scripts | Yes |
| `docs/` | Architecture and historical documentation | Yes |
| `reports/` | Reviewed baseline/release summaries | Yes |
| `archive/` | Frozen v1, research, and old platform material | Yes |
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
