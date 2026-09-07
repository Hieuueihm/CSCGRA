if {$argc < 2} {
    error "usage: check_m7.tcl <repo_root> <report_dir> ?top ...?"
}
set repo_root [file normalize [lindex $argv 0]]
set report_root [file normalize [lindex $argv 1]]
file mkdir $report_root
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m7_ooc.xdc]
set rtl_sources [list \
    [file join $repo_root rtl v3 phi phi_request_queue.v] \
    [file join $repo_root rtl v3 phi threefry2x32_folded_pipeline.v] \
    [file join $repo_root rtl v3 phi phi_symbol_builder.v] \
    [file join $repo_root rtl v3 phi phi_response_gearbox.v] \
    [file join $repo_root rtl v3 phi phi_symbol_generator.v] \
    [file join $repo_root rtl v3 phi support_phi_symbol_cache.v] \
    [file join $repo_root rtl v3 phi phi_stream_provider.v] \
    [file join $repo_root rtl v3 phi phi_stream_subsystem.v] \
    [file join $repo_root rtl v3 phi phi_operator_normalizer.v]]
set top_names [list threefry2x32_folded_pipeline phi_symbol_generator \
    support_phi_symbol_cache phi_stream_provider phi_operator_normalizer]
if {$argc >= 3} {
    set top_names {}
    foreach top_argument [lrange $argv 2 end] {
        foreach top_name [split $top_argument ","] { lappend top_names $top_name }
    }
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
    set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
    set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
    set dsp_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
    set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    if {[llength $timing_paths] == 0} { error "no setup path for $top_name" }
    set wns [get_property SLACK [lindex $timing_paths 0]]
    if {$wns < 0.2} { error "$top_name WNS below +0.2 ns: $wns" }
    if {$top_name in {threefry2x32_folded_pipeline phi_symbol_generator phi_stream_provider}} {
        if {$ram36_count != 0 || $ram18_count != 0 || $dsp_count != 0} {
            error "$top_name unexpected hard resources: BRAM36=$ram36_count BRAM18=$ram18_count DSP=$dsp_count"
        }
    }
    if {$top_name eq "support_phi_symbol_cache"} {
        if {$ram36_count != 1 || $ram18_count != 0 || $dsp_count != 0} {
            error "$top_name expected 1 RAMB36/0 RAMB18/0 DSP, got $ram36_count/$ram18_count/$dsp_count"
        }
    }
    if {$top_name eq "phi_operator_normalizer" &&
        ($ram36_count != 0 || $ram18_count != 0 || $dsp_count != 4)} {
        error "$top_name expected 0 RAMB36/0 RAMB18/4 DSP, got $ram36_count/$ram18_count/$dsp_count"
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
    puts "M7 $top_name synthesis PASS: WNS=$wns BRAM36=$ram36_count BRAM18=$ram18_count DSP=$dsp_count"
    close_project
}
