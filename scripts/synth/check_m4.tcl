if {$argc < 2} {
    error "usage: check_m4.tcl <repo_root> <report_dir> ?top ...?"
}

set repo_root [file normalize [lindex $argv 0]]
set report_root [file normalize [lindex $argv 1]]
file mkdir $report_root
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m4_ooc.xdc]
set rtl_sources [list \
    [file join $repo_root rtl v3 data_movement vector_scratchpad.v] \
    [file join $repo_root rtl v3 data_movement vector_stream_engine.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_word_codec.v] \
    [file join $repo_root rtl v3 data_movement dma_element_normalizer.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_preload_engine.v] \
    [file join $repo_root rtl v3 data_movement scratchpad_residency_tracker.v] \
    [file join $repo_root rtl v3 cgra stream_context_router.v] \
    [file join $repo_root verification v3 m4 m4_vector_transport_ooc.sv]]

set top_names [list vector_stream_engine m4_vector_transport_ooc \
    vector_scratchpad scratchpad_word_codec stream_context_router \
    scratchpad_preload_engine scratchpad_residency_tracker]
if {$argc >= 3} {
    set top_names {}
    foreach top_argument [lrange $argv 2 end] {
        foreach top_name [split $top_argument ","] {
            lappend top_names $top_name
        }
    }
}

foreach top_name $top_names {
    set report_dir [file join $report_root $top_name]
    file mkdir $report_dir
    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]
    set_property include_dirs [list $include_dir] [current_fileset]
    read_verilog -sv $rtl_sources
    if {$top_name ni {vector_scratchpad scratchpad_word_codec stream_context_router}} {
        read_xdc $constraint_file
    }
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt
    write_checkpoint -force [file join $report_dir post_synth.dcp]
    report_utilization -file [file join $report_dir utilization.rpt]
    report_timing_summary -delay_type max -max_paths 10 \
        -file [file join $report_dir timing_summary.rpt]
    report_drc -file [file join $report_dir drc.rpt]
    check_timing -verbose -file [file join $report_dir check_timing.rpt]
    set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
    set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
    set dsp_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
    set wns "not_clocked"
    if {$top_name ni {vector_scratchpad scratchpad_word_codec stream_context_router}} {
        set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
        if {[llength $timing_paths] == 0} {
            error "Vivado produced no setup timing path for $top_name"
        }
        set wns [get_property SLACK [lindex $timing_paths 0]]
        if {$wns < 0.2} {
            error "post-synthesis WNS margin is below 0.2 ns for $top_name: WNS=$wns ns"
        }
    }
    if {$top_name eq "m4_vector_transport_ooc" && $dsp_count != 0} {
        error "M4 address/control path unexpectedly inferred DSP48=$dsp_count"
    }
    if {$top_name in {scratchpad_preload_engine \
            scratchpad_residency_tracker} && $dsp_count != 0} {
        error "M4.1 preload control unexpectedly inferred DSP48=$dsp_count"
    }
    if {$top_name in {vector_scratchpad m4_vector_transport_ooc} &&
            ($ram36_count != 16 || $ram18_count != 0)} {
        error "M4 scratchpad mapping changed: RAMB36=$ram36_count RAMB18=$ram18_count"
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
    puts "M4 $top_name synthesis PASS: WNS=$wns RAMB36=$ram36_count RAMB18=$ram18_count DSP=$dsp_count"
    close_project
}
