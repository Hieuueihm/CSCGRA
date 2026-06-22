set script_dir [file dirname [file normalize [info script]]]
set_param general.maxThreads 8
set root_dir {D:/vivado_pj}
set run_dir [file join $root_dir CSCGRA_opt runs bd_zcu106_soc_opt_current]
set proj_dir [file join $run_dir vivado_zcu106_soc]
set report_dir [file join $run_dir reports]
set artifact_dir [file join $run_dir artifacts]
file mkdir $run_dir
file mkdir $proj_dir
file mkdir $report_dir
file mkdir $artifact_dir
create_project cscgra_zcu106_soc_opt $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]
catch {set_property board_part xilinx.com:zcu106:part0:2.6 [current_project]}
set rtl_dir [file join $root_dir CSCGRA_opt CSCGRA.srcs sources_1 new]
set rtl_files [glob -nocomplain -directory $rtl_dir *.v]
if {[llength $rtl_files] == 0} { error "No RTL files found in $rtl_dir" }
add_files -norecurse $rtl_files
update_compile_order -fileset sources_1
create_bd_design cscgra_soc_bd
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells ps]
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__USE__M_AXI_GP1 {0} \
  CONFIG.PSU__USE__S_AXI_GP0 {1} \
  CONFIG.PSU__USE__IRQ0 {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] [get_bd_cells ps]
create_bd_cell -type module -reference cgra_soc_top cgra
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins cgra/ap_clk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins cgra/ap_rst_n]
foreach ps_clk_pin {maxihpm0_fpd_aclk maxihpm1_fpd_aclk saxihpc0_fpd_aclk} {
  set ps_clk [get_bd_pins -quiet ps/$ps_clk_pin]
  if {[llength $ps_clk] > 0} { connect_bd_net [get_bd_pins ps/pl_clk0] $ps_clk }
}
set pl_freq [get_property CONFIG.FREQ_HZ [get_bd_pins ps/pl_clk0]]
if {$pl_freq eq ""} { set pl_freq 99990005 }
set_property CONFIG.FREQ_HZ $pl_freq [get_bd_pins cgra/ap_clk]
set_property CONFIG.ASSOCIATED_BUSIF {s_axi_control:m_axi_gmem} [get_bd_pins cgra/ap_clk]
foreach cgra_intf {s_axi_control m_axi_gmem} {
  set intf [get_bd_intf_pins -quiet cgra/$cgra_intf]
  if {[llength $intf] > 0} { set_property CONFIG.FREQ_HZ $pl_freq $intf }
}
connect_bd_net [get_bd_pins cgra/interrupt] [get_bd_pins ps/pl_ps_irq0]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_ctrl_sc
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_ctrl_sc]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins axi_ctrl_sc/aclk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins axi_ctrl_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_ctrl_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_sc/M00_AXI] [get_bd_intf_pins cgra/s_axi_control]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_gmem_sc
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_gmem_sc]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins axi_gmem_sc/aclk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins axi_gmem_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins cgra/m_axi_gmem] [get_bd_intf_pins axi_gmem_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gmem_sc/M00_AXI] [get_bd_intf_pins ps/S_AXI_HPC0_FPD]
assign_bd_address
validate_bd_design
save_bd_design
generate_target all [get_files [file join $proj_dir cscgra_zcu106_soc_opt.srcs sources_1 bd cscgra_soc_bd cscgra_soc_bd.bd]]
make_wrapper -files [get_files [file join $proj_dir cscgra_zcu106_soc_opt.srcs sources_1 bd cscgra_soc_bd cscgra_soc_bd.bd]] -top
add_files -norecurse [file join $proj_dir cscgra_zcu106_soc_opt.gen sources_1 bd cscgra_soc_bd hdl cscgra_soc_bd_wrapper.v]
set_property top cscgra_soc_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synth_1 did not complete" }
open_run synth_1
report_utilization -file [file join $report_dir synth_util.rpt]
report_utilization -hierarchical -hierarchical_depth 8 -file [file join $report_dir synth_util_hier.rpt]
report_timing_summary -file [file join $report_dir synth_timing_summary.rpt]
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "impl_1 did not complete" }
open_run impl_1
report_utilization -file [file join $report_dir impl_util.rpt]
report_utilization -hierarchical -hierarchical_depth 8 -file [file join $report_dir impl_util_hier.rpt]
report_timing_summary -file [file join $report_dir impl_timing_summary.rpt]
report_power -file [file join $report_dir impl_power.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $artifact_dir cscgra_zcu106_soc_opt.xsa]
write_checkpoint -force [file join $artifact_dir cscgra_zcu106_soc_opt_routed.dcp]
close_project
