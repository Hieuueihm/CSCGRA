# V4 synthesis and implementation baseline

Prepared flow: scripts/v4/run_synth_impl.tcl. This is an out-of-context (OOC)
run of the complete csr_top IP, including host_command_bridge and recovery_engine.
It does not build the processor subsystem or generate a board bitstream.

Defaults follow the V4 architecture target: xczu7ev-ffvc1156-2-e, 10 ns (100 MHz).
Override the part and clock explicitly if the actual target differs.

## Commands (PowerShell)

Run from D:\vivado_pj. Use a new output name for each run; existing directories
are refused rather than overwritten. Synthesis/implementation are not launched
by preparing these files.

~~~powershell
Set-Location D:\vivado_pj
$vivado = 'C:\Xilinx\Vivado\2018.1\bin\vivado.bat'
$stamp = Get-Date -Format yyyyMMdd_HHmmssfff

# Validate arguments, installed part and source paths only; no synthesis.
& $vivado -mode batch -nolog -nojournal -source scripts/v4/run_synth_impl.tcl -tclargs -check_only

# Synthesis only.
& $vivado -mode batch -log "work/v4_synth_$stamp.log" -journal "work/v4_synth_$stamp.jou" -source scripts/v4/run_synth_impl.tcl -tclargs -stage synth -out_dir "work/v4_impl_synth_$stamp"

# Alternatively: synthesis followed by placement and routing in a fresh run.
& $vivado -mode batch -log "work/v4_route_$stamp.log" -journal "work/v4_route_$stamp.jou" -source scripts/v4/run_synth_impl.tcl -tclargs -stage impl -out_dir "work/v4_impl_route_$stamp"
~~~

The implementation command includes synthesis; running the synthesis-only command
first is optional, and its checkpoint is not reused by the implementation command.
Options: -part PART, -clock_ns PERIOD, -stage synth|impl, -out_dir DIRECTORY.

## Deliberately minimal flow

- synth_design -mode out_of_context, opt_design, place_design, route_design.
- No custom directive/strategy, phys_opt_design, retiming, pblock, clock location,
  DONT_TOUCH, timing exception, or DRC severity override is added.
- A generated XDC supplies only create_clock on s_axi_aclk.
- Input/output delays, board pins and processor integration are not specified.
  Thus interface paths are not fully constrained: this is an internal-clock OOC
  baseline, not complete SoC timing or board sign-off. Do not hide those paths
  with blanket false paths. Add real interface constraints during integration.
- Each run copies RTL/headers and this script into its output directory before
  synthesis, and records the selected settings and generated XDC.

## Outputs and acceptance

post_synth.dcp and, for implementation, post_route.dcp are retained.
Reports cover utilization, timing (including unconstrained paths), DRC,
route status and check_timing. Inspect final WNS/TNS, hold timing, routing
completeness, DRC and unconstrained paths; a FLOW COMPLETE line is not sign-off.
No synthesis/implementation PPA or timing result is claimed by this preparation.
