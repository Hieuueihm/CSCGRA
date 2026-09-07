if {$argc != 2} { error "usage: analyze_m8_checkpoint.tcl <checkpoint> <report_dir>" }
set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
open_checkpoint $checkpoint
report_timing -delay_type max -max_paths 50 -nworst 50 \
    -file [file join $report_dir top50_timing.rpt]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $report_dir hierarchical_utilization.rpt]

proc report_endpoint_class {name pattern report_dir} {
    set endpoints [get_cells -quiet -hierarchical -filter \
        "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    set fp [open [file join $report_dir "${name}_summary.txt"] w]
    puts $fp "endpoint_count=[llength $endpoints]"
    if {[llength $endpoints] == 0} {
        puts $fp "status=NO_ENDPOINTS"
        close $fp
        return
    }
    set paths [get_timing_paths -quiet -delay_type max -max_paths 20 \
        -nworst 20 -to $endpoints]
    puts $fp "path_count=[llength $paths]"
    if {[llength $paths] == 0} {
        puts $fp "status=NO_PATHS"
    } else {
        set slack [get_property SLACK [lindex $paths 0]]
        puts $fp "worst_slack_ns=$slack"
        puts $fp "status=MEASURED"
        report_timing -delay_type max -max_paths 20 -nworst 20 \
            -to $endpoints -file [file join $report_dir "${name}_timing.rpt"]
    }
    close $fp
}

proc report_through_class {name pattern report_dir} {
    set through_nets [get_nets -quiet -hierarchical -filter "NAME =~ $pattern"]
    set fp [open [file join $report_dir "${name}_summary.txt"] w]
    puts $fp "net_count=[llength $through_nets]"
    if {[llength $through_nets] == 0} {
        puts $fp "status=NO_NETS"
        close $fp
        return
    }
    set paths [get_timing_paths -quiet -delay_type max -max_paths 20 \
        -nworst 20 -through $through_nets]
    puts $fp "path_count=[llength $paths]"
    if {[llength $paths] == 0} {
        puts $fp "status=NO_PATHS"
    } else {
        set slack [get_property SLACK [lindex $paths 0]]
        puts $fp "worst_slack_ns=$slack"
        puts $fp "status=[expr {$slack eq "Inf" || $slack eq "" ? "UNCONSTRAINED" : "MEASURED"}]"
        report_timing -delay_type max -max_paths 20 -nworst 20 \
            -through $through_nets -file [file join $report_dir "${name}_timing.rpt"]
    }
    close $fp
}

report_endpoint_class dispatcher_endpoints "*u_dispatcher*" $report_dir
report_endpoint_class scalar_rf_endpoints "*scalar_state*" $report_dir
report_through_class ready_join "*ready*" $report_dir
report_through_class commit_join "*cycle_commit*" $report_dir
set paths [get_timing_paths -delay_type max -max_paths 50 -nworst 50]
set fp [open [file join $report_dir top50_paths.tsv] w]
puts $fp "rank\tslack_ns\tlogic_levels\tsource\tdestination"
set rank 0
foreach path $paths {
    incr rank
    puts $fp [join [list $rank [get_property SLACK $path] \
        [get_property LOGIC_LEVELS $path] [get_property STARTPOINT_PIN $path] \
        [get_property ENDPOINT_PIN $path]] "\t"]
}
close $fp
close_design
