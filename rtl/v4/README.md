# RTL v4

The implemented source list is `files.f`. Read the
[current status](../../docs/v4/STATUS.md),
[module catalog](../../docs/v4/architecture/MODULES.md) and
[current recovery hierarchy](../../docs/v4/diagrams/recovery.mmd).

The target uses QR support LS on the shared stream kernel. Loaded QR programs,
factor storage/transport and native result publication have source-qualified
evidence; see the [current status](../../docs/v4/STATUS.md) for the exact scope
and remaining boundaries. The [context-stream execution](../../docs/v4/diagrams/context_stream_execution.mmd)
and [factor-panel mapping](../../docs/v4/diagrams/panel_mapping.mmd) diagrams show
the current command and PE ownership. Existing LSQR is a separately elaborated
historical reference with no fallback in new recovery programs. The CPU/host wrapper
remains planned outside this RTL target.

| Group | Responsibility |
|---|---|
| `operator` | Selected LFSR32 Phi generator |
| `memory` | Shared Phi/B ownership, sign cache, one dense B, vector pool, factor and result stores |
| `compute` | PE arithmetic/RF/predicates, two arrays, generic transactional kernels |
| `control` | Loaded program/scalar RF, kernel lifecycle and publication; old LSQR/resident references |
| `dataflow` | Operand reader/feeder, support builder/selection, range and factor transfers; historical loader |
| `services` | Shared fixed-point DIV/SQRT/RESCALE service; historical scalar reference |
| `include` | Generated candidate interface definitions |

`lsqr_engine` owns one `operator_memory`, one `kernel_engine`, one scalar service,
one generic `solver_sequencer`, a measurement loader and one commit controller.
Only `kernel_fabric` instantiates the two 4×4 arrays in this hierarchy. The
`resident_engine` and `cgra_fabric` wrappers are separately elaborated references.
Their resources are not added to the new recovery target. Its planned path
is `csr_top -> recovery_engine -> stream_kernel -> stream_fabric`, containing
exactly two `stream_array` instances. See the catalog for implemented versus
planned modules; `files.f` is a source inventory, not one physical hierarchy.

Names describe functions. `v4` appears only in directory/version labels;
generated macro names and include guards use `CSR_`.

RTL acceptance uses **Vivado xvlog/xelab/xsim only**:

```powershell
py -3 scripts/v4/run_rtl.py --test-timeout 7200
```

The runner checks generated definitions/project consistency, runs the full test
discovery once and saves actual commands, logs, image scopes and source hashes
in [unified evidence](../../reports/v4/RTL_CORRECTNESS.md). `VIVADO_BIN` overrides
the default `C:/Xilinx/Vivado/2018.1/bin`. Older runner names redirect here.
Permanent SV benches live under `verification/v4/<group>/`; Python drives and
checks integer oracles. Earlier simulator reports are historical only.

Before editing, follow [AGENTS.md](AGENTS.md) and the module's contract. No empty
top stubs are added. A bounded LS solve does not imply complete recovery programs,
host/AXI integration, synthesis/implementation or board qualification. Source-bound
test results and remaining scope are recorded in the status and evidence links.
