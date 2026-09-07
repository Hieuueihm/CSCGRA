if {$argc != 3} { error "usage: check_m12.tcl <repo_root> <report_dir> <top>" }
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set top_name [lindex $argv 2]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root rtl v3 include]] [current_fileset]
if {$top_name eq "reconstruction_result_writer"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 data_movement reconstruction_result_writer.v]]
} elseif {$top_name eq "m12_result_dma_integration"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 data_movement axi_read_burst_engine.v] \
        [file join $repo_root rtl v3 data_movement axi_write_burst_engine.v] \
        [file join $repo_root rtl v3 data_movement dma_request_arbiter.v] \
        [file join $repo_root rtl v3 data_movement memory_dma_engine.v] \
        [file join $repo_root rtl v3 data_movement reconstruction_result_writer.v] \
        [file join $repo_root rtl v3 integration m12_result_dma_integration.v]]
} elseif {$top_name eq "m12_lifecycle_top"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 host_interface axi4lite_slave.v] \
        [file join $repo_root rtl v3 host_interface reconstruction_csr.v] \
        [file join $repo_root rtl v3 reconstruction_control configuration_fetch_unit.v] \
        [file join $repo_root rtl v3 reconstruction_control configuration_check_unit.v] \
        [file join $repo_root rtl v3 reconstruction_control active_configuration_store.v] \
        [file join $repo_root rtl v3 reconstruction_control reconstruction_configuration_unit.v] \
        [file join $repo_root rtl v3 reconstruction_control reconstruction_phase_controller.v] \
        [file join $repo_root rtl v3 data_movement axi_read_burst_engine.v] \
        [file join $repo_root rtl v3 data_movement axi_write_burst_engine.v] \
        [file join $repo_root rtl v3 data_movement dma_request_arbiter.v] \
        [file join $repo_root rtl v3 data_movement memory_dma_engine.v] \
        [file join $repo_root rtl v3 data_movement reconstruction_result_writer.v] \
        [file join $repo_root rtl v3 integration m12_result_dma_integration.v] \
        [file join $repo_root rtl v3 integration m12_lifecycle_top.v]]
} else {
    error "unsupported M12 top: $top_name"
}
read_verilog -sv $rtl_sources
read_xdc [file join $repo_root constraints v3 m10_ooc.xdc]
synth_design -top $top_name -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $paths] == 0} { error "no setup path for $top_name" }
set wns [get_property SLACK [lindex $paths 0]]
if {$wns < 1.0} { error "$top_name WNS below +1.0 ns: $wns" }
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set r36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set r18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
if {$top_name ne "m12_lifecycle_top" &&
    ($r36 != 0 || $r18 != 0 || $dsp != 0)} {
    error "$top_name expected register/LUT-only implementation"
}
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=$top_name"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "wns_gate_min_ns=1.0"
puts $fp "wns_gate_pass=1"
puts $fp "lut_count=$lut"
puts $fp "ff_count=$ff"
puts $fp "ramb36_count=$r36"
puts $fp "ramb18_count=$r18"
puts $fp "dsp48_count=$dsp"
close $fp
puts "M12 OOC PASS top=$top_name WNS=$wns LUT=$lut FF=$ff"
close_project
