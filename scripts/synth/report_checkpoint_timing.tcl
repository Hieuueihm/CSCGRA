if {$argc != 3} {
    error "usage: report_checkpoint_timing.tcl <checkpoint> <report_dir> <period_ns>"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]

file mkdir $report_dir
open_checkpoint $checkpoint
reset_timing
create_clock -name core_clock -period $period_ns [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks core_clock]
set_property HD.CLK_SRC BUFGCE_X0Y120 [get_ports clk]

report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    error "no setup path in checkpoint"
}
set wns [get_property SLACK [lindex $timing_paths 0]]

set summary_file [open [file join $report_dir summary.txt] w]
puts $summary_file "checkpoint=$checkpoint"
puts $summary_file "clock_period_ns=$period_ns"
puts $summary_file "clock_uncertainty_ns=0.200"
puts $summary_file "post_synth_wns_ns=$wns"
close $summary_file

puts "CHECKPOINT TIMING REPORT PASS period=$period_ns WNS=$wns"
close_project
