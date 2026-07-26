set root "D:/vivado_pj/CSCGRA_opt_architecture"
set outdir "$root/runs/impl_ooc_cgra_top"
file mkdir $outdir
create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
read_verilog [glob "$root/CSCGRA.srcs/sources_1/new/*.v"]
synth_design -top cgra_top -part xczu7ev-ffvc1156-2-e -mode out_of_context -flatten_hierarchy rebuilt -directive RuntimeOptimized
create_clock -period 10.000 -name clk [get_ports clk]
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
report_route_status -file "$outdir/cgra_top_route_status.rpt"
report_utilization -file "$outdir/cgra_top_impl_util.rpt" -hierarchical
report_timing_summary -file "$outdir/cgra_top_impl_timing.rpt" -delay_type min_max -max_paths 20 -report_unconstrained
report_drc -file "$outdir/cgra_top_impl_drc.rpt"
write_checkpoint -force "$outdir/cgra_top_impl_routed.dcp"
exit
