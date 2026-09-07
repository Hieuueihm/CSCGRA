if {$argc < 2 || $argc > 3} {
    error "usage: check_m3.tcl <repo_root> <report_dir> ?comma_separated_tops?"
}

set repo_root [file normalize [lindex $argv 0]]
set report_root [file normalize [lindex $argv 1]]
file mkdir $report_root
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m3_ooc.xdc]
set_msg_config -id {Synth 8-3331} -limit 5
set rtl_sources [list \
    [file join $repo_root rtl v3 context_control context_write_certifier.v] \
    [file join $repo_root rtl v3 context_control context_image_store.v] \
    [file join $repo_root rtl v3 context_control memory_configuration_store.v] \
    [file join $repo_root rtl v3 context_control context_reservation_guard.v] \
    [file join $repo_root rtl v3 context_control array_context_sequencer.v] \
    [file join $repo_root rtl v3 reconstruction_control reconstruction_phase_controller.v] \
    [file join $repo_root verification v3 m3 m3_context_execution_ooc.sv]]

set top_names [list context_image_store memory_configuration_store \
    array_context_sequencer reconstruction_phase_controller \
    m3_context_execution_ooc]
if {$argc == 3} {
    set top_names [split [lindex $argv 2] ","]
}

foreach top_name $top_names {
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
    set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
    set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
    set dsp_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
    if {$top_name eq "context_image_store" &&
            ($ram36_count != 9 || $ram18_count != 2)} {
        error "context image mapping changed: RAMB36=$ram36_count RAMB18=$ram18_count"
    }
    if {$top_name eq "memory_configuration_store" &&
            ($ram36_count != 4 || $ram18_count != 0)} {
        error "memory configuration mapping changed: RAMB36=$ram36_count RAMB18=$ram18_count"
    }
    if {$top_name eq "m3_context_execution_ooc" &&
            ($ram36_count != 9 || $ram18_count != 1)} {
        error "integrated M3 image mapping changed: RAMB36=$ram36_count RAMB18=$ram18_count"
    }
    set fp [open [file join $report_dir summary.txt] w]
    puts $fp "part=$part_name"
    puts $fp "top=$top_name"
    puts $fp "clock_period_ns=6.667"
    puts $fp "clock_uncertainty_ns=0.200"
    puts $fp "post_synth_wns_ns=$wns"
    puts $fp "ramb36_count=$ram36_count"
    puts $fp "ramb18_count=$ram18_count"
    puts $fp "dsp48_count=$dsp_count"
    close $fp
    set minimum_wns 0.2
    if {$top_name eq "m3_context_execution_ooc"} {
        set minimum_wns 1.0
    }
    if {$wns < $minimum_wns} {
        error "post-synthesis WNS margin is below $minimum_wns ns for $top_name: WNS=$wns ns"
    }
    puts "M3 $top_name synthesis PASS: WNS=$wns ns"
    close_project
}
