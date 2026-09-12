set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 1} { error "Usage: build_soc_test.tcl NEW_WORK_DIRECTORY" }
set output [file normalize [lindex $argv 0]]
if {[file dirname $output] ne [file join $root work] || ![string match soc_axi_* [file tail $output]]} {
    error "Output must be work/soc_axi_*"
}
set project_dir [file join $output project]
if {[file exists $project_dir]} { error "Refusing existing project directory" }
create_project soc_test $project_dir -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set channel [open [file join $root rtl v4 files.f] r]
set sources [read $channel]
close $channel
foreach line [split $sources "\n"] {
    set line [string trim $line]
    if {$line eq ""} { continue }
    if {[string first +incdir+ $line] == 0} {
        set_property include_dirs [list [file join $root [string range $line 8 end]]] [get_filesets sources_1]
    } else {
        add_files -norecurse [file join $root $line]
    }
}
create_bd_design soc
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.2 ps
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 1 CONFIG.PSU__USE__M_AXI_GP1 0 CONFIG.PSU__USE__M_AXI_GP2 0 CONFIG.PSU__MAXIGP0__DATA_WIDTH 32 CONFIG.PSU__USE__IRQ0 1] [get_bd_cells ps]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 bus
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] [get_bd_cells bus]
create_bd_cell -type module -reference csr_top accelerator
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 interrupt_controller
set_property -dict [list CONFIG.C_NUM_INTR_INPUTS 1 CONFIG.C_KIND_OF_INTR 0 CONFIG.C_HAS_FAST 0] [get_bd_cells interrupt_controller]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 interrupts
set_property -dict [list CONFIG.NUM_PORTS 2 CONFIG.IN1_WIDTH 7] [get_bd_cells interrupts]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero
set_property -dict [list CONFIG.CONST_WIDTH 7 CONFIG.CONST_VAL 0] [get_bd_cells zero]
create_bd_port -dir I -type clk sim_clk
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports sim_clk]
create_bd_port -dir I -type rst resetn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports resetn]
connect_bd_net [get_bd_ports sim_clk] [get_bd_pins ps/maxihpm0_fpd_aclk] [get_bd_pins bus/ACLK] [get_bd_pins bus/S00_ACLK] [get_bd_pins bus/M00_ACLK] [get_bd_pins bus/M01_ACLK] [get_bd_pins accelerator/s_axi_aclk] [get_bd_pins interrupt_controller/s_axi_aclk]
connect_bd_net [get_bd_ports resetn] [get_bd_pins bus/ARESETN] [get_bd_pins bus/S00_ARESETN] [get_bd_pins bus/M00_ARESETN] [get_bd_pins bus/M01_ARESETN] [get_bd_pins accelerator/s_axi_aresetn] [get_bd_pins interrupt_controller/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins bus/S00_AXI]
set accelerator_axi [get_bd_intf_pins -of_objects [get_bd_cells accelerator] -filter {VLNV =~ *aximm*}]
if {[llength $accelerator_axi] != 1} { error "Expected exactly one inferred AXI interface: $accelerator_axi" }
connect_bd_intf_net [get_bd_intf_pins bus/M00_AXI] $accelerator_axi
connect_bd_intf_net [get_bd_intf_pins bus/M01_AXI] [get_bd_intf_pins interrupt_controller/s_axi]
connect_bd_net [get_bd_pins accelerator/irq] [get_bd_pins interrupt_controller/intr]
connect_bd_net [get_bd_pins interrupt_controller/irq] [get_bd_pins interrupts/In0]
connect_bd_net [get_bd_pins zero/dout] [get_bd_pins interrupts/In1]
connect_bd_net [get_bd_pins interrupts/dout] [get_bd_pins ps/pl_ps_irq0]
assign_bd_address -offset 0xA0000000 -range 4K -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs -of_objects $accelerator_axi]
assign_bd_address -offset 0xA0010000 -range 64K -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs interrupt_controller/S_AXI/Reg]
validate_bd_design
save_bd_design
set design [get_files soc.bd]
generate_target simulation $design
set wrappers [make_wrapper -files $design -top]
add_files -norecurse $wrappers
set_property top soc_wrapper [get_filesets sources_1]
add_files -fileset sim_1 -norecurse [file join $root verification v4 host tb_soc_axi.sv]
set_property top tb_soc_axi [get_filesets sim_1]
set_property include_dirs [list [file join $root rtl v4 include]] [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -scripts_only
set channel [open [file join $output build_complete.txt] w]
puts $channel "PS_VIP + AXI_INTERCONNECT + CSR_TOP + AXI_INTC; no synthesis/implementation"
close $channel
puts "SOC BUILD SCRIPTS READY: $output"
