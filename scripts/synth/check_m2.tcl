if {$argc != 2} {
    error "usage: check_m2.tcl <repo_root> <report_dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set report_root [file normalize [lindex $argv 1]]
file mkdir $report_root
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m2_ooc.xdc]
set rtl_sources [list \
    [file join $repo_root rtl v3 reconstruction_control configuration_fetch_unit.v] \
    [file join $repo_root rtl v3 reconstruction_control configuration_check_unit.v] \
    [file join $repo_root rtl v3 reconstruction_control active_configuration_store.v] \
    [file join $repo_root rtl v3 reconstruction_control reconstruction_configuration_unit.v] \
    [file join $repo_root rtl v3 data_movement axi_read_burst_engine.v] \
    [file join $repo_root rtl v3 data_movement axi_write_burst_engine.v] \
    [file join $repo_root rtl v3 data_movement dma_request_arbiter.v] \
    [file join $repo_root rtl v3 data_movement dma_element_normalizer.v] \
    [file join $repo_root rtl v3 data_movement memory_dma_engine.v]]

foreach top_name {reconstruction_configuration_unit memory_dma_engine dma_element_normalizer} {
    set report_dir [file join $report_root $top_name]
    file mkdir $report_dir
    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]
    set_property include_dirs [list $include_dir] [current_fileset]
    read_verilog -sv $rtl_sources
    read_xdc $constraint_file
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt
    write_checkpoint -force [file join $report_dir post_synth.dcp]
    report_utilization -file [file join $report_dir utilization.rpt]
    report_timing_summary -delay_type max -max_paths 10 \
        -file [file join $report_dir timing_summary.rpt]
    report_drc -file [file join $report_dir drc.rpt]
    check_timing -verbose -file [file join $report_dir check_timing.rpt]
    set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    if {[llength $timing_paths] == 0} {
        error "Vivado produced no setup timing path for $top_name"
    }
    set wns [get_property SLACK [lindex $timing_paths 0]]
    set fp [open [file join $report_dir summary.txt] w]
    puts $fp "part=$part_name"
    puts $fp "top=$top_name"
    puts $fp "clock_period_ns=6.667"
    puts $fp "clock_uncertainty_ns=0.200"
    puts $fp "post_synth_wns_ns=$wns"
    close $fp
    if {$wns < 0.0} {
        error "post-synthesis setup timing failed for $top_name: WNS=$wns ns"
    }
    puts "M2 $top_name synthesis PASS: WNS=$wns ns"
    close_project
}
