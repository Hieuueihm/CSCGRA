set_param general.maxThreads 8
set root_dir {D:/vivado_pj}
set base [file join $root_dir CSCGRA_opt runs bd_zcu106_soc_opt_current]
set proj "$base/vivado_zcu106_soc/cscgra_zcu106_soc_opt.xpr"
set impl_dir "$base/vivado_zcu106_soc/cscgra_zcu106_soc_opt.runs/impl_1"
set art "$base/artifacts"
set rpt "$base/reports_manual"
file mkdir $art
file mkdir $rpt
open_project $proj
open_checkpoint "$impl_dir/cscgra_soc_bd_wrapper_physopt.dcp"
route_design
report_route_status -file "$rpt/route_status_manual.rpt"
report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained -file "$rpt/timing_summary_manual_routed.rpt"
report_utilization -file "$rpt/utilization_manual_routed.rpt"
report_drc -file "$rpt/drc_manual_routed.rpt"
write_checkpoint -force "$art/cscgra_zcu106_soc_opt_routed.dcp"
write_bitstream -force "$art/cscgra_zcu106_soc_opt.bit"
write_hw_platform -fixed -include_bit -force -file "$art/cscgra_zcu106_soc_opt.xsa"
exit
