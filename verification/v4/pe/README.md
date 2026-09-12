# PE primitive testbenches

Permanent SV sources:

- `tb_pe_alu.sv` instantiates arithmetic and exposes persistent ACC/mode for edge-by-edge checks.
- `tb_mesh_router.sv` instantiates a router with parameter TILE_ID; regression runs all 0..31.
- `tb_pe_tile.sv` instantiates the decoded RF8/predicate tile and probes all persistent architectural state.
- `tb_pe_context.sv` drives compiler-packed words through context_decode and pe_tile, using context_io.json field order.
- `io.json` records packed stimulus and trace field order for the local candidate build.
- `../test_pe_rtl.py` builds stimuli from the integer model and checks real simulator traces.

Run from the repository root:

    py -3 scripts/v4/run_rtl.py

The correctness backend is Vivado xvlog/xelab/xsim only. Set `VIVADO_BIN`
to the Vivado `bin` directory when needed; the default is
`C:/Xilinx/Vivado/2018.1/bin`. The unified runner records actual commands,
tool versions and source hashes in `reports/v4/rtl_correctness.json` and
`reports/v4/RTL_CORRECTNESS.md`. It never launches synthesis or implementation.

To keep generated stimulus files, traces and Vivado elaboration artifacts for debugging:

```powershell
$env:V4_PE_KEEP = '1'
py -3 -m unittest verification.v4.test_pe_rtl -v
py -3 -m unittest verification.v4.test_tile_rtl -v
py -3 -m unittest verification.v4.test_context_rtl -v
Remove-Item Env:V4_PE_KEEP
```

The PE suite uses `work/v4_pe_*`, the tile suite uses `work/v4_tile_*`,
and the context suite uses `work/v4_context_*`. Retained runs contain stimulus,
traces, `*.xsim.json` descriptors and their Vivado build directories. Without
V4_PE_KEEP, only the temporary run directories are removed; the SV benches remain.
Context runs also retain compiler images when V4_PE_KEEP is set. Compiler tile
HEX lines are byte strings: convert with int.from_bytes(bytes.fromhex(line), 'little');
do not feed those lines directly into a numerical-word readmemh loader.

For a retained replay, `scripts/v4/xsim.py` provides `compile_rtl` and
`run_rtl`; the Python test drivers show the exact top, parameters, sources
and plusargs. A `*.xsim.json` file describes an elaborated Vivado snapshot
and its working directory; it is not a simulator executable.

Each .hex line is one cycle of packed stimulus. Benches emit before-edge and after-edge observations;
the first pre-reset observation is deliberately not checked. A standalone
bench PASS only means stimulus completed; numerical pass requires the Python
trace comparison. Unknown values on checked fields fail. No synthesis runs here.
