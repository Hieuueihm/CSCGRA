if {$argc < 2} {
    error "usage: check_m5.tcl <repo_root> <report_dir> ?top ...?"
}
set repo_root [file normalize [lindex $argv 0]]
set report_root [file normalize [lindex $argv 1]]
file mkdir $report_root
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m5_ooc.xdc]
set rtl_sources [list \
    [file join $repo_root rtl v3 arithmetic cluster_reduction_unit.v] \
    [file join $repo_root rtl v3 arithmetic global_reduction_merge.v] \
    [file join $repo_root rtl v3 arithmetic reduction_pipeline.v] \
    [file join $repo_root rtl v3 arithmetic scalar_register_file.v] \
    [file join $repo_root rtl v3 arithmetic scalar_state_subsystem.v] \
    [file join $repo_root rtl v3 arithmetic scalar_function_unit.v] \
    [file join $repo_root rtl v3 arithmetic shared_vector_arithmetic_unit.v] \
    [file join $repo_root rtl v3 arithmetic shared_vector_pipeline.v] \
    [file join $repo_root rtl v3 arithmetic array_resource_router.v] \
    [file join $repo_root rtl v3 arithmetic m5_arithmetic_subsystem.v] \
    [file join $repo_root verification v3 m5 m5_arithmetic_ooc.sv]]
set top_names [list cluster_reduction_unit global_reduction_merge reduction_pipeline \
    scalar_register_file scalar_function_unit shared_vector_arithmetic_unit \
    shared_vector_pipeline \
    array_resource_router m5_arithmetic_ooc]
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
    if {$ram36_count != 0 || $ram18_count != 0} {
        error "$top_name unexpectedly inferred BRAM: $ram36_count/$ram18_count"
    }
    if {$top_name in {shared_vector_arithmetic_unit m5_arithmetic_ooc}} {
        if {$dsp_count != 16} { error "$top_name DSP48 count is $dsp_count, expected 16" }
    } elseif {$dsp_count != 0} {
        error "$top_name unexpectedly inferred DSP48=$dsp_count"
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
    puts "M5 $top_name synthesis PASS: WNS=$wns BRAM36=$ram36_count BRAM18=$ram18_count DSP=$dsp_count"
    close_project
}
