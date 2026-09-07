if {$argc != 2} {
    error "usage: check_m1_m4_integration.tcl <repo_root> <report_dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m4_ooc.xdc]
set sources [list \
    [file join $repo_root rtl v3 host_interface axi4lite_slave.v] \
    [file join $repo_root rtl v3 host_interface reconstruction_csr.v] \
    [file join $repo_root rtl v3 reconstruction_control configuration_fetch_unit.v] \
    [file join $repo_root rtl v3 reconstruction_control configuration_check_unit.v] \
    [file join $repo_root rtl v3 reconstruction_control active_configuration_store.v] \
    [file join $repo_root rtl v3 reconstruction_control reconstruction_configuration_unit.v] \
    [file join $repo_root rtl v3 reconstruction_control reconstruction_phase_controller.v] \
    [file join $repo_root rtl v3 context_control context_write_certifier.v] \
    [file join $repo_root rtl v3 context_control context_image_store.v] \
    [file join $repo_root rtl v3 context_control memory_configuration_store.v] \
    [file join $repo_root rtl v3 context_control context_reservation_guard.v] \
    [file join $repo_root rtl v3 context_control array_context_sequencer.v] \
    [file join $repo_root rtl v3 data_movement axi_read_burst_engine.v] \
    [file join $repo_root rtl v3 data_movement axi_write_burst_engine.v] \
    [file join $repo_root rtl v3 data_movement dma_request_arbiter.v] \
    [file join $repo_root rtl v3 data_movement dma_element_normalizer.v] \
    [file join $repo_root rtl v3 data_movement memory_dma_engine.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_preload_engine.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_residency_tracker.v] \
    [file join $repo_root rtl v3 data_movement vector_scratchpad.v] \
    [file join $repo_root rtl v3 data_movement vector_stream_engine.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_word_codec.v] \
    [file join $repo_root rtl v3 cgra stream_context_router.v] \
    [file join $repo_root verification v3 integration m1_m4_integration_harness.sv]]

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $include_dir] [current_fileset]
read_verilog -sv $sources
read_xdc $constraint_file
synth_design -top m1_m4_integration_harness -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]

set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    error "Vivado produced no setup timing path for M1-M4 integration"
}
set wns [get_property SLACK [lindex $timing_paths 0]]
set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
if {$wns < 0.2} {
    error "M1-M4 post-synthesis WNS is below 0.2 ns: WNS=$wns ns"
}
if {$dsp_count != 0} {
    error "M1-M4 control/transport harness unexpectedly inferred DSP48=$dsp_count"
}

set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=m1_m4_integration_harness"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "ramb36_count=$ram36_count"
puts $fp "ramb18_count=$ram18_count"
puts $fp "dsp48_count=$dsp_count"
close $fp
puts "M1-M4 synthesis PASS: WNS=$wns RAMB36=$ram36_count RAMB18=$ram18_count DSP=$dsp_count"
close_project
