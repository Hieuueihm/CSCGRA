# Documentation index

Use this directory for architecture, project status, refactor rules, and
version-specific design notes. Raw Vivado/XSim output does not belong here.

## Start here

- `PROJECT_STATUS.md`: current source-of-truth inventory of implemented
  optimizations, rejected trials, sign-off metrics, and folder ownership.
- `REPOSITORY_LAYOUT.md`: source/generated-data separation and version policy.
- `CONTINUATION.md`: chronological engineering handoff log and next candidate.
- `architecture/`: focused audits that apply across checkpoints.
- `v1/`: documentation for the frozen RTL v1 line.
- `v2/`: documentation for the active RTL v2 line.

Release-quality measurements and cycle matrices live in `reports/releases`.
When a historical document conflicts with `PROJECT_STATUS.md` or the latest
release report, use the newer signed-off document.
