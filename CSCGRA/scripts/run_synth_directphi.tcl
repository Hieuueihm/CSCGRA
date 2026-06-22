set root "D:/vivado_pj/CSCGRA_opt"
set outdir "$root/runs/synth_directphi"
file mkdir $outdir
create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
read_verilog [glob "$root/CSCGRA.srcs/sources_1/new/*.v"]
read_xdc -quiet "$outdir/clock.xdc"
synth_design -top cgra_soc_top -part xczu7ev-ffvc1156-2-e -flatten_hierarchy rebuilt -directive default
report_utilization -file "$outdir/cgra_soc_top_util.rpt" -hierarchical
report_timing_summary -file "$outdir/cgra_soc_top_timing.rpt" -delay_type max -max_paths 10
report_dsp_utilization -file "$outdir/cgra_soc_top_dsp.rpt"
write_checkpoint -force "$outdir/cgra_soc_top_synth.dcp"
exit
