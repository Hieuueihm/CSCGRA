set root [file normalize [file join [file dirname [info script]] ..]]
set outdir "$root/runs/opt2/synth_seq_prefetch_cgra_top"
file mkdir $outdir
create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
read_verilog [glob "$root/CSCGRA.srcs/sources_1/new/*.v"]
synth_design -top cgra_top -part xczu7ev-ffvc1156-2-e -mode out_of_context -flatten_hierarchy rebuilt -directive RuntimeOptimized
create_clock -period 10.000 -name clk [get_ports clk]
report_utilization -file "$outdir/cgra_top_util.rpt" -hierarchical
report_timing_summary -file "$outdir/cgra_top_timing.rpt" -delay_type max -max_paths 10
exit
