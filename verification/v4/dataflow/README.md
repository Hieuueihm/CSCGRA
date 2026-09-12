# Feeder and fabric RTL replay

Permanent benches:

- tb_operand_feeder.sv: aligned Phi R1/R4 and diagonal B permutation.
- tb_cgra_fabric.sv: feeder, both arrays and all32 committed PE states.
- io.json and fabric_io.json: packed stimulus order and trace widths.

Run from the repository root:

    py -3 -m unittest verification.v4.test_feeder_rtl verification.v4.test_fabric_rtl -v
    py -3 scripts/v4/run_rtl.py

The correctness backend is Vivado xvlog/xelab/xsim only. Set `VIVADO_BIN`
to the Vivado `bin` directory when needed; the default is
`C:/Xilinx/Vivado/2018.1/bin`. The unified runner records actual commands,
tool versions and source hashes in `reports/v4/rtl_correctness.json` and
`reports/v4/RTL_CORRECTNESS.md`. It never launches synthesis or implementation.

The SV PASS message alone only indicates end of stimulus; Python compares
the integer/cycle oracle against the trace before accepting the run.

Set V4_PE_KEEP=1 to retain unique work/v4_feeder_* directories (also used
by the fabric replay). Each contains vectors.hex, trace.txt, a sim.xsim.json descriptor and
the corresponding Vivado build directory.
The test drives packed tile words and a schedule, not a control256 program
loader/PC. See docs/v4/architecture/ARRAY_RTL_CONTRACT.md for that boundary.

[Historical feeder/fabric evidence](../../../reports/v4/FABRIC_RTL_CORRECTNESS.md)
preserves the earlier simulator run; current acceptance uses the unified Vivado gate.
