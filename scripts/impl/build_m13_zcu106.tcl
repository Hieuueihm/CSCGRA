if {$argc != 2} { error "usage: build_m13_zcu106.tcl <repo_root> <run_dir>" }
set repo_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set package_project_dir [file join $run_dir package_project]
set packaged_ip_dir [file join $run_dir packaged_ip]
set project_dir [file join $run_dir project]
set report_dir [file join $run_dir reports]
set artifact_dir [file join $run_dir artifacts]
file mkdir $package_project_dir
file mkdir $packaged_ip_dir
file mkdir $project_dir
file mkdir $report_dir
file mkdir $artifact_dir

set part_name xczu7ev-ffvc1156-2-e
create_project m13_zcu106_core $package_project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root rtl v3 include]] \
    [current_fileset]
set manifest [open [file join $repo_root rtl v3 files.f] r]
set rtl_sources [list]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "+*" $line]} { continue }
    lappend rtl_sources [file join $repo_root $line]
}
close $manifest
add_files -norecurse $rtl_sources
set header_sources [glob -nocomplain -directory \
    [file join $repo_root rtl v3 include] *.vh]
add_files -norecurse $header_sources
set_property file_type SystemVerilog [get_files $rtl_sources]
set_property file_type {Verilog Header} [get_files $header_sources]
set_property top m13_zcu106_shell_core [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $packaged_ip_dir -vendor gbmhi.local \
    -library v3 -taxonomy /UserIP -import_files -set_current true -force
set packaged_core [ipx::current_core]
set_property name m13_zcu106_shell_core $packaged_core
set_property version 1.0 $packaged_core
set_property display_name {M13 ZCU106 Compute Core} $packaged_core
set_property description \
    {M13 lifecycle, loader, context compute and DDR integration} $packaged_core
ipx::infer_bus_interfaces {} $packaged_core
foreach bus_interface {s_axi_control s_axi_loader m_axi_gmem} {
    if {[llength [ipx::get_bus_interfaces -quiet $bus_interface \
            -of_objects $packaged_core]] != 1} {
        error "cannot infer packaged interface $bus_interface"
    }
    ipx::associate_bus_interfaces -busif $bus_interface -clock ap_clk \
        -reset ap_rst_n $packaged_core
}
ipx::create_xgui_files $packaged_core
ipx::update_checksums $packaged_core
ipx::save_core $packaged_core
close_project

create_project m13_zcu106 $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $packaged_ip_dir] [current_project]
update_ip_catalog
foreach board_part {
    xilinx.com:zcu106:part0:2.6
    xilinx.com:zcu106:part0:1.2
    xilinx.com:zcu106:part0:1.1
    xilinx.com:zcu106:part0:1.0
} {
    if {[catch {set_property board_part $board_part [current_project]}] == 0} {
        break
    }
}

create_bd_design m13_zcu106_bd
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} [get_bd_cells ps]
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP0 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] [get_bd_cells ps]

create_bd_cell -type ip \
    -vlnv gbmhi.local:v3:m13_zcu106_shell_core:1.0 compute
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* ps_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* control_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] \
    [get_bd_cells control_sc]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* memory_sc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] \
    [get_bd_cells memory_sc]

connect_bd_net [get_bd_pins ps/pl_clk0] \
    [get_bd_pins compute/ap_clk] \
    [get_bd_pins ps_reset/slowest_sync_clk] \
    [get_bd_pins control_sc/aclk] \
    [get_bd_pins memory_sc/aclk]
connect_bd_net [get_bd_pins ps/pl_resetn0] \
    [get_bd_pins ps_reset/ext_reset_in]
connect_bd_net [get_bd_pins ps_reset/peripheral_aresetn] \
    [get_bd_pins compute/ap_rst_n] \
    [get_bd_pins control_sc/aresetn] \
    [get_bd_pins memory_sc/aresetn]
foreach ps_clock_pin {
    maxihpm0_fpd_aclk
    maxihpm1_fpd_aclk
    maxihpm0_lpd_aclk
    saxihpc0_fpd_aclk
} {
    set pin [get_bd_pins -quiet ps/$ps_clock_pin]
    if {[llength $pin] != 0} {
        connect_bd_net [get_bd_pins ps/pl_clk0] $pin
    }
}

set pl_frequency [get_property CONFIG.FREQ_HZ [get_bd_pins ps/pl_clk0]]
if {$pl_frequency eq ""} { set pl_frequency 100000000 }
foreach interface_name {s_axi_control s_axi_loader m_axi_gmem} {
    set interface_pin [get_bd_intf_pins compute/$interface_name]
    set_property CONFIG.FREQ_HZ $pl_frequency $interface_pin
}

connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins control_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins control_sc/M00_AXI] \
    [get_bd_intf_pins compute/s_axi_control]
connect_bd_intf_net [get_bd_intf_pins control_sc/M01_AXI] \
    [get_bd_intf_pins compute/s_axi_loader]
connect_bd_intf_net [get_bd_intf_pins compute/m_axi_gmem] \
    [get_bd_intf_pins memory_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins memory_sc/M00_AXI] \
    [get_bd_intf_pins ps/S_AXI_HPC0_FPD]
connect_bd_net [get_bd_pins compute/interrupt] [get_bd_pins ps/pl_ps_irq0]

set lifecycle_segments [get_bd_addr_segs -quiet -of_objects \
    [get_bd_intf_pins compute/s_axi_control]]
set loader_segments [get_bd_addr_segs -quiet -of_objects \
    [get_bd_intf_pins compute/s_axi_loader]]
if {[llength $lifecycle_segments] != 1} {
    error "expected one lifecycle address segment"
}
if {[llength $loader_segments] != 1} {
    error "expected one loader address segment"
}
set ps_data_space [get_bd_addr_spaces ps/Data]
assign_bd_address -target_address_space $ps_data_space \
    -offset 0xA0000000 -range 4K $lifecycle_segments
assign_bd_address -target_address_space $ps_data_space \
    -offset 0xA0010000 -range 4K $loader_segments
assign_bd_address

validate_bd_design
save_bd_design
set bd_file [get_files [file join $project_dir m13_zcu106.srcs sources_1 bd \
    m13_zcu106_bd m13_zcu106_bd.bd]]
generate_target all $bd_file
make_wrapper -files $bd_file -top
set wrapper_file [file join $project_dir m13_zcu106.gen sources_1 bd \
    m13_zcu106_bd hdl m13_zcu106_bd_wrapper.v]
if {![file exists $wrapper_file]} {
    set wrapper_file [file join $project_dir m13_zcu106.srcs sources_1 bd \
        m13_zcu106_bd hdl m13_zcu106_bd_wrapper.v]
}
if {![file exists $wrapper_file]} { error "BD wrapper not found" }
add_files -norecurse $wrapper_file
set_property top m13_zcu106_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1

set timing_constraints [file join $repo_root constraints v3 m13_zcu106.xdc]
add_files -fileset constrs_1 -norecurse $timing_constraints
set_property PROCESSING_ORDER LATE [get_files $timing_constraints]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
        ![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "synth_1 failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -hierarchical -file \
    [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -delay_type max -max_paths 50 -file \
    [file join $report_dir post_synth_timing.rpt]
close_design

launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" ||
        ![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "impl_1 failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -hierarchical -file \
    [file join $report_dir post_route_utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 100 -file \
    [file join $report_dir post_route_timing.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
set pdrc_checks [get_drc_checks -quiet PDRC*]
if {[llength $pdrc_checks] != 0} {
    report_drc -checks $pdrc_checks -file \
        [file join $report_dir post_route_pdrc.rpt]
}
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_clock_utilization -file \
    [file join $report_dir post_route_clock_utilization.rpt]
report_route_status -file [file join $report_dir post_route_status.rpt]
write_checkpoint -force [file join $artifact_dir m13_zcu106_routed.dcp]

set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} { error "no routed setup path" }
set wns [get_property SLACK [lindex $timing_paths 0]]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $hold_paths] == 0} { error "no routed hold path" }
set whs [get_property SLACK [lindex $hold_paths 0]]
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set ramb36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ramb18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
set summary [open [file join $report_dir summary.txt] w]
puts $summary "part=$part_name"
puts $summary "top=m13_zcu106_bd_wrapper"
puts $summary "lifecycle_base=0xA0000000"
puts $summary "loader_base=0xA0010000"
puts $summary "target_clock_mhz=100"
puts $summary "clock_period_ns=10.000"
puts $summary "clock_uncertainty_ns=0.200"
puts $summary "post_route_wns_ns=$wns"
puts $summary "post_route_whs_ns=$whs"
puts $summary "setup_wns_gate_min_ns=0.2"
puts $summary "hold_whs_gate_min_ns=0.0"
puts $summary "lut_count=$lut"
puts $summary "ff_count=$ff"
puts $summary "ramb36_count=$ramb36"
puts $summary "ramb18_count=$ramb18"
puts $summary "dsp48_count=$dsp"
puts $summary "synthesis_directives=none"
puts $summary "optimization_directives=none"
puts $summary "placement_directives=none"
puts $summary "routing_directives=none"
close $summary
if {$wns < 0.2 || $whs < 0.0} {
    error "routed timing failed: WNS=$wns WHS=$whs"
}
close_project
