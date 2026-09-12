# V4 memory verification

Permanent SystemVerilog benches:

- tb_vector_store.sv: three planes/two ports, publication, tail and faults.
- tb_support_matrix_cache.sv: one-copy diagonal B storage and identity/ranges.
- tb_operand_plan.sv: mode/orientation address schedule and bounds.
- tb_operand_reader.sv: split-response joins with modeled matrix/vector sources.
- tb_ram_reader.sv: actual vector_store + support_matrix_cache + operand_reader.

IO JSON files define the packed stimulus/trace layout. Tests compare integer
models before and after every edge. RAM integration additionally asserts frames
from row/column coordinates, not from the bank permutation under test.

Run from the repository root:

    py -3 scripts/v4/run_rtl.py

The correctness backend is Vivado xvlog/xelab/xsim only. Set `VIVADO_BIN`
to the Vivado `bin` directory when needed; the default is
`C:/Xilinx/Vivado/2018.1/bin`. The unified runner records actual commands,
tool versions and source hashes in `reports/v4/rtl_correctness.json` and
`reports/v4/RTL_CORRECTNESS.md`. It never launches synthesis or implementation.

Set V4_PE_KEEP=1 to retain unique work/v4_feeder_* stimulus/trace directories,
including sim.xsim.json descriptors and the corresponding Vivado builds.
The prefix is inherited from the shared Replay helper, not the tested DUT name.
No control ADDRESS/fabric adapter, live Phi adapter or synth/impl is claimed.

