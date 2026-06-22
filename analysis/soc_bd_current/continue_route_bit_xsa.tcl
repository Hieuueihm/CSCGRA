set_param general.maxThreads 8
set proj "D:/vivado_pj/analysis/soc_bd_current/vivado_zcu106_soc/cscgra_zcu106_soc_current.xpr"
set out_dir "D:/vivado_pj/analysis/soc_bd_current"
set report_dir "$out_dir/reports_manual"
set artifact_dir "$out_dir/artifacts"
file mkdir $report_dir
file mkdir $artifact_dir
open_project $proj
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "impl_1 route_design did not complete" }
open_run impl_1
report_utilization -file [file join $report_dir impl_util.rpt]
report_timing_summary -file [file join $report_dir impl_timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
write_checkpoint -force [file join $artifact_dir cscgra_zcu106_soc_current_routed.dcp]
write_bitstream -force [file join $artifact_dir cscgra_zcu106_soc_current.bit]
write_hw_platform -fixed -include_bit -force -file [file join $artifact_dir cscgra_zcu106_soc_current.xsa]
close_project
exit
