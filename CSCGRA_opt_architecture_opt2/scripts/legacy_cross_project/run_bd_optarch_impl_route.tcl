open_project D:/vivado_pj/bd_optarch/vivado_zcu106_soc/cscgra_zcu106_soc_opt_architecture.xpr
reset_run cscgra_soc_bd_cgra_0_synth_1
reset_run synth_1
launch_runs impl_1 -to_step route_design -jobs 6
wait_on_run impl_1
open_run impl_1
report_timing_summary -file D:/vivado_pj/CSCGRA_opt_architecture/analysis/pe_core_pipe_bd_timing_summary_routed.rpt -delay_type max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets
report_utilization -file D:/vivado_pj/CSCGRA_opt_architecture/analysis/pe_core_pipe_bd_utilization_routed.rpt
close_project
