if {$argc != 2} { error "usage: finish_m13_zcu106.tcl <project_file> <run_dir>" }
set project_file [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set report_dir [file join $run_dir reports]
set artifact_dir [file join $run_dir artifacts]
file mkdir $report_dir
file mkdir $artifact_dir

open_project $project_file
set synth_status [get_property STATUS [get_runs synth_1]]
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
        ![string match "*Complete*" $synth_status]} {
    error "synth_1 is not complete: $synth_status"
}
open_run synth_1
report_utilization -hierarchical -file \
    [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -delay_type max -max_paths 50 -file \
    [file join $report_dir post_synth_timing.rpt]
close_design

launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" ||
        ![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
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
puts $summary "part=xczu7ev-ffvc1156-2-e"
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
