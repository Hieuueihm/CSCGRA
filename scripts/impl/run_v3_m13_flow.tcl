if {$argc != 4} {
    error "usage: run_v3_m13_flow.tcl <repo_root> <run_dir> <stage> <jobs>"
}

set repo_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set requested_stage [string tolower [lindex $argv 2]]
set jobs [lindex $argv 3]
set report_dir [file join $run_dir reports]
set checkpoint_dir [file join $run_dir checkpoints]
set status_path [file join $run_dir flow_status.txt]
set part_name xczu7ev-ffvc1156-2-e
set top_name m13_compute_lifecycle_integration
set setup_gate_ns 0.200
set hold_gate_ns 0.000

file mkdir $run_dir
file mkdir $report_dir
file mkdir $checkpoint_dir

proc write_flow_status {path state stage detail} {
    set status_file [open $path w]
    puts $status_file "state=$state"
    puts $status_file "stage=$stage"
    puts $status_file "detail=$detail"
    puts $status_file "timestamp=[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]"
    close $status_file
}

proc read_manifest_sources {repo_root} {
    set manifest_path [file join $repo_root rtl v3 files.f]
    if {![file exists $manifest_path]} {
        error "source manifest not found: $manifest_path"
    }
    set manifest [open $manifest_path r]
    set rtl_sources [list]
    while {[gets $manifest line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "+*" $line]} { continue }
        set source_path [file normalize [file join $repo_root $line]]
        if {![file exists $source_path]} {
            close $manifest
            error "RTL source not found: $source_path"
        }
        lappend rtl_sources $source_path
    }
    close $manifest
    if {[llength $rtl_sources] == 0} {
        error "source manifest is empty: $manifest_path"
    }
    return $rtl_sources
}

proc load_m13_design {repo_root part_name} {
    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]
    set_property include_dirs [list [file join $repo_root rtl v3 include]] \
        [current_fileset]
    source [file join $repo_root scripts synth load_v3_xpm_memory.tcl]
    read_verilog -sv [read_manifest_sources $repo_root]
    read_xdc [file join $repo_root constraints v3 m13_ooc.xdc]
}

proc report_common {report_dir prefix} {
    report_utilization -file [file join $report_dir ${prefix}_utilization.rpt]
    report_utilization -hierarchical -hierarchical_depth 8 \
        -file [file join $report_dir ${prefix}_utilization_hierarchical.rpt]
    report_timing_summary -delay_type min_max -max_paths 100 \
        -report_unconstrained \
        -file [file join $report_dir ${prefix}_timing_summary.rpt]
    check_timing -verbose -file [file join $report_dir ${prefix}_check_timing.rpt]
    report_clock_interaction -file \
        [file join $report_dir ${prefix}_clock_interaction.rpt]
    report_drc -file [file join $report_dir ${prefix}_drc.rpt]
}

proc report_routed {report_dir} {
    report_common $report_dir post_route
    set pdrc_checks [get_drc_checks -quiet PDRC*]
    if {[llength $pdrc_checks] != 0} {
        report_drc -checks $pdrc_checks \
            -file [file join $report_dir post_route_pdrc.rpt]
    }
    report_methodology -file [file join $report_dir post_route_methodology.rpt]
    report_clock_utilization -file \
        [file join $report_dir post_route_clock_utilization.rpt]
    report_route_status -file [file join $report_dir post_route_status.rpt]
}

proc worst_slack {delay_type} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} { error "no $delay_type timing path found" }
    return [get_property SLACK [lindex $paths 0]]
}

proc write_summary {path stage part_name top_name setup_gate_ns hold_gate_ns enforce_gate} {
    set wns [worst_slack max]
    set whs not_applicable
    if {$stage eq "post_route"} { set whs [worst_slack min] }
    set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
    set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
    set ramb36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
    set ramb18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
    set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
    set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]
    set drc_critical_warnings [llength [get_drc_violations -quiet \
        -filter {SEVERITY == {Critical Warning}}]]
    set setup_pass [expr {$wns >= $setup_gate_ns}]
    set hold_pass not_applicable
    if {$stage eq "post_route"} { set hold_pass [expr {$whs >= $hold_gate_ns}] }
    set summary [open $path w]
    foreach {key value} [list \
            completion_stage $stage part $part_name top $top_name \
            target_clock_mhz 100 clock_period_ns 10.000 \
            clock_uncertainty_ns 0.200 setup_wns_ns $wns hold_whs_ns $whs \
            setup_wns_gate_min_ns $setup_gate_ns \
            hold_whs_gate_min_ns $hold_gate_ns setup_gate_pass $setup_pass \
            hold_gate_pass $hold_pass lut_primitive_count $lut \
            ff_primitive_count $ff ramb36_primitive_count $ramb36 \
            ramb18_primitive_count $ramb18 dsp48_primitive_count $dsp \
            drc_error_count $drc_errors \
            drc_critical_warning_count $drc_critical_warnings \
            synthesis_directives none optimization_directives none \
            placement_directives none routing_directives none] {
        puts $summary "$key=$value"
    }
    close $summary
    if {$enforce_gate && !$setup_pass} {
        error "setup WNS below +$setup_gate_ns ns: $wns"
    }
    if {$enforce_gate && $stage eq "post_route" && !$hold_pass} {
        error "hold WHS below $hold_gate_ns ns: $whs"
    }
    if {$enforce_gate && $drc_errors != 0} {
        error "DRC contains $drc_errors errors"
    }
}

proc newest_checkpoint_stage {checkpoint_dir} {
    foreach stage {post_route post_place post_opt post_synth} {
        if {[file exists [file join $checkpoint_dir ${stage}.dcp]]} {
            return $stage
        }
    }
    return none
}

if {$requested_stage ni {parsecheck synth implement all reportonly}} {
    error "unsupported stage: $requested_stage"
}
if {![string is integer -strict $jobs] || $jobs < 1} {
    error "jobs must be a positive integer"
}
set_param general.maxThreads $jobs
if {$requested_stage eq "parsecheck"} {
    write_flow_status $status_path PASS parsecheck {TCL parsed and arguments validated}
    puts "V3 M13 FLOW PARSECHECK PASS"
    return
}

write_flow_status $status_path RUNNING startup "requested_stage=$requested_stage"
set flow_code [catch {
    set checkpoint_stage [newest_checkpoint_stage $checkpoint_dir]
    if {$requested_stage eq "synth" && $checkpoint_stage ne "none"} {
        if {$checkpoint_stage ne "post_synth"} {
            error "synth stage cannot use later checkpoint: $checkpoint_stage"
        }
        open_checkpoint [file join $checkpoint_dir post_synth.dcp]
    } elseif {$requested_stage in {implement reportonly} ||
            ($requested_stage eq "all" && $checkpoint_stage ne "none")} {
        if {$checkpoint_stage eq "none"} {
            error "$requested_stage requires an existing checkpoint"
        }
        open_checkpoint [file join $checkpoint_dir ${checkpoint_stage}.dcp]
    } else {
        write_flow_status $status_path RUNNING read_design {reading RTL and constraints}
        load_m13_design $repo_root $part_name
        write_flow_status $status_path RUNNING synth_design {synthesis running}
        synth_design -top $top_name -part $part_name -mode out_of_context \
            -flatten_hierarchy rebuilt
        write_checkpoint -force [file join $checkpoint_dir post_synth.dcp]
        write_flow_status $status_path CHECKPOINT post_synth \
            {post-synthesis checkpoint written}
        report_common $report_dir post_synth
        set synth_gate [expr {$requested_stage eq "synth"}]
        write_summary [file join $report_dir summary.txt] post_synth \
            $part_name $top_name $setup_gate_ns $hold_gate_ns $synth_gate
        set checkpoint_stage post_synth
    }

    if {$requested_stage eq "synth"} {
        if {![file exists [file join $report_dir post_synth_utilization.rpt]]} {
            report_common $report_dir post_synth
            write_summary [file join $report_dir summary.txt] post_synth \
                $part_name $top_name $setup_gate_ns $hold_gate_ns 1
        }
        write_flow_status $status_path PASS post_synth {synthesis complete}
    } elseif {$requested_stage eq "reportonly"} {
        if {$checkpoint_stage eq "post_route"} {
            report_routed $report_dir
        } else {
            report_common $report_dir $checkpoint_stage
        }
        set report_gate [expr {$checkpoint_stage eq "post_route"}]
        write_summary [file join $report_dir summary.txt] $checkpoint_stage \
            $part_name $top_name $setup_gate_ns $hold_gate_ns $report_gate
        write_flow_status $status_path PASS $checkpoint_stage \
            {reports regenerated from checkpoint}
    } else {
        if {$checkpoint_stage eq "post_synth"} {
            if {![file exists [file join $report_dir post_synth_utilization.rpt]]} {
                report_common $report_dir post_synth
                write_summary [file join $report_dir summary.txt] post_synth \
                    $part_name $top_name $setup_gate_ns $hold_gate_ns 0
            }
            write_flow_status $status_path RUNNING opt_design {logic optimization running}
            opt_design
            write_checkpoint -force [file join $checkpoint_dir post_opt.dcp]
            write_flow_status $status_path CHECKPOINT post_opt {post-opt checkpoint written}
            report_common $report_dir post_opt
            set checkpoint_stage post_opt
        }
        if {$checkpoint_stage eq "post_opt"} {
            if {![file exists [file join $report_dir post_opt_utilization.rpt]]} {
                report_common $report_dir post_opt
            }
            write_flow_status $status_path RUNNING place_design {placement running}
            place_design
            write_checkpoint -force [file join $checkpoint_dir post_place.dcp]
            write_flow_status $status_path CHECKPOINT post_place \
                {post-place checkpoint written}
            report_common $report_dir post_place
            set checkpoint_stage post_place
        }
        if {$checkpoint_stage eq "post_place"} {
            if {![file exists [file join $report_dir post_place_utilization.rpt]]} {
                report_common $report_dir post_place
            }
            write_flow_status $status_path RUNNING route_design {routing running}
            route_design
            write_checkpoint -force [file join $checkpoint_dir post_route.dcp]
            write_flow_status $status_path CHECKPOINT post_route \
                {post-route checkpoint written}
            set checkpoint_stage post_route
        }
        if {$checkpoint_stage ne "post_route"} {
            error "implementation did not reach post_route: $checkpoint_stage"
        }
        report_routed $report_dir
        write_summary [file join $report_dir summary.txt] post_route \
            $part_name $top_name $setup_gate_ns $hold_gate_ns 1
        write_flow_status $status_path PASS post_route \
            {implementation and timing gates complete}
    }
} flow_message flow_options]

if {$flow_code != 0} {
    write_flow_status $status_path FAIL $requested_stage $flow_message
    puts stderr "V3 M13 FLOW FAILED: $flow_message"
    return -options $flow_options $flow_message
}
puts "V3 M13 FLOW PASS stage=$requested_stage"
