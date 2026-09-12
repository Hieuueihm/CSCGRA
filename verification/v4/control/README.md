# Control/image execution benches

- tb_control_decode.sv: exact field extraction, reserved/enum/unsupported faults.
- tb_context_store.sv: synchronous reads, stalls, generation/validity and reset.
- tb_context_engine.sv: loader/store/sequencer with a tagged delayed backend model.
- tb_context_fabric.sv: actual cgra_fabric; full images execute using RTL PC/loop.

The JSON IO maps define packed stimulus order and trace field widths. Python
compares the integer/cycle models with RTL traces before and after every edge.
The standalone engine bench uses a backend protocol model; the fabric bench
really instantiates both arrays. It supplies no matrix/vector memory operands,
so scalar/RF/route/control programs are qualified, not autonomous GEMV/LSQR.

Run from the repository root:

    py -3 -m unittest verification.v4.test_control_rtl -v
    py -3 scripts/v4/run_rtl.py

The correctness backend is Vivado xvlog/xelab/xsim only. Set `VIVADO_BIN`
to the Vivado `bin` directory when needed; the default is
`C:/Xilinx/Vivado/2018.1/bin`. The unified runner records actual commands,
tool versions and source hashes in `reports/v4/rtl_correctness.json` and
`reports/v4/RTL_CORRECTNESS.md`. It never launches synthesis or implementation.

Export an already-written compiler image for the trusted host loader:

    py -3 scripts/v4/export_control_stream.py IMAGE_DIR OUTPUT_DIR --generation 123

This verifies image hashes/structure first. loader.txt contains numerical
PC, bank,256-bit data and last fields in hex. loader_header.json records the
verified revision/depth/generation and stream SHA256. Host software must protect
the verified stream through transport; the RTL does not calculate SHA256.
The loader's begin_verified is an explicit trusted-host attestation.

Set V4_PE_KEEP=1 to retain work/v4_feeder_* vector/trace files,
sim.xsim.json descriptors and Vivado build directories (the shared replay
helper uses that directory prefix for these benches).
SV PASS means stimulus finished; only the Python comparisons qualify the run.
Never interpret this gate as synth/impl, full job commit or LSQR sign-off.
