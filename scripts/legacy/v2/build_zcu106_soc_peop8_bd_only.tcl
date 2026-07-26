set script_dir [file dirname [file normalize [info script]]]
set_param general.maxThreads 8
set root_dir [file normalize [file join $script_dir ..]]
if {[info exists ::env(CSCGRA_SOC_RUN_DIR)]} {
  set run_dir [file normalize $::env(CSCGRA_SOC_RUN_DIR)]
} else {
  set run_dir [file join $root_dir runs bd_zcu106_soc_peop8_bd_only]
}
set proj_dir [file join $run_dir vivado_zcu106_soc]
set report_dir [file join $run_dir reports]
set artifact_dir [file join $run_dir artifacts]
file mkdir $run_dir
file mkdir $proj_dir
file mkdir $report_dir
file mkdir $artifact_dir

create_project cscgra_zcu106_soc_peop8 $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]
foreach bp {xilinx.com:zcu106:part0:2.6 xilinx.com:zcu106:part0:1.2 xilinx.com:zcu106:part0:1.1 xilinx.com:zcu106:part0:1.0} {
  if {[catch {set_property board_part $bp [current_project]}] == 0} { break }
}

set rtl_dir [file join $root_dir CSCGRA.srcs sources_1 new]
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
  CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1} \
  CONFIG.PSU__UART0__PERIPHERAL__IO {MIO 18 .. 19} \
  CONFIG.PSU__CRL_APB__UART0_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__CRL_APB__UART0_REF_CTRL__FREQMHZ {100} \
  CONFIG.PSU__CRL_APB__UART0_REF_CTRL__DIVISOR0 {15} \
  CONFIG.PSU__CRL_APB__UART0_REF_CTRL__DIVISOR1 {1} \
  CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
  CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 20 .. 21} \
  CONFIG.PSU__CRL_APB__UART1_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__CRL_APB__UART1_REF_CTRL__FREQMHZ {100} \
  CONFIG.PSU__CRL_APB__UART1_REF_CTRL__DIVISOR0 {15} \
  CONFIG.PSU__CRL_APB__UART1_REF_CTRL__DIVISOR1 {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__DIVISOR0 {10} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__DIVISOR1 {1} \
] [get_bd_cells ps]

create_bd_cell -type module -reference cgra_soc_top cgra
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* ps_reset

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins cgra/ap_clk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins ps_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins ps_reset/ext_reset_in]
connect_bd_net [get_bd_pins ps_reset/peripheral_aresetn] [get_bd_pins cgra/ap_rst_n]
foreach ps_clk_pin {maxihpm0_fpd_aclk maxihpm1_fpd_aclk maxihpm0_lpd_aclk saxihpc0_fpd_aclk} {
  set ps_clk [get_bd_pins -quiet ps/$ps_clk_pin]
  if {[llength $ps_clk] > 0} { connect_bd_net [get_bd_pins ps/pl_clk0] $ps_clk }
}
set pl_freq [get_property CONFIG.FREQ_HZ [get_bd_pins ps/pl_clk0]]
if {$pl_freq eq ""} { set pl_freq 100000000 }
foreach cgra_intf {s_axi_control m_axi_gmem} {
  set intf [get_bd_intf_pins -quiet cgra/$cgra_intf]
  if {[llength $intf] > 0} { set_property CONFIG.FREQ_HZ $pl_freq $intf }
}
connect_bd_net [get_bd_pins cgra/interrupt] [get_bd_pins ps/pl_ps_irq0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_ctrl_sc
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_ctrl_sc]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins axi_ctrl_sc/aclk]
connect_bd_net [get_bd_pins ps_reset/peripheral_aresetn] [get_bd_pins axi_ctrl_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_ctrl_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_sc/M00_AXI] [get_bd_intf_pins cgra/s_axi_control]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_gmem_sc
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_gmem_sc]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins axi_gmem_sc/aclk]
connect_bd_net [get_bd_pins ps_reset/peripheral_aresetn] [get_bd_pins axi_gmem_sc/aresetn]
connect_bd_intf_net [get_bd_intf_pins cgra/m_axi_gmem] [get_bd_intf_pins axi_gmem_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gmem_sc/M00_AXI] [get_bd_intf_pins ps/S_AXI_HPC0_FPD]

assign_bd_address
set cgra_seg [get_bd_addr_segs -quiet */SEG_cgra_reg0]
if {[llength $cgra_seg] == 0} { error "Cannot find cgra AXI-Lite address segment SEG_cgra_reg0" }
set_property range 16K $cgra_seg
set_property offset 0xA0000000 $cgra_seg
validate_bd_design
save_bd_design
generate_target all [get_files [file join $proj_dir cscgra_zcu106_soc_peop8.srcs sources_1 bd cscgra_soc_bd cscgra_soc_bd.bd]]
make_wrapper -files [get_files [file join $proj_dir cscgra_zcu106_soc_peop8.srcs sources_1 bd cscgra_soc_bd cscgra_soc_bd.bd]] -top
set wrapper_file [file join $proj_dir cscgra_zcu106_soc_peop8.gen sources_1 bd cscgra_soc_bd hdl cscgra_soc_bd_wrapper.v]
if {![file exists $wrapper_file]} { set wrapper_file [file join $proj_dir cscgra_zcu106_soc_peop8.srcs sources_1 bd cscgra_soc_bd hdl cscgra_soc_bd_wrapper.v] }
if {![file exists $wrapper_file]} { error "BD wrapper not found: $wrapper_file" }
add_files -norecurse $wrapper_file
set_property top cscgra_soc_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
close_project


