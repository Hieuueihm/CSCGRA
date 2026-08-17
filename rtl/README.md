# RTL source

This is the only authoritative synthesizable RTL tree.

- `v1/`: frozen original optimized snapshot for reproducibility.
- `v2/`: active strict-PE0, four-row, factor-reuse implementation.

Each version is self-contained and has its own `files.f`. Do not compile RTL
from local `CSCGRA_opt_architecture*` directories or generated Vivado `*.srcs`
trees. Behavioral work goes to v2 unless a task explicitly targets v1.

Current v2 metrics and retained optimizations are summarized in
`docs/PROJECT_STATUS.md`.
