if {$argc != 3} {
    error "usage: report_combinational_checkpoint_timing.tcl <checkpoint> <report_dir> <period_ns>"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]

file mkdir $report_dir
open_checkpoint $checkpoint
reset_timing
create_clock -name virtual_clock -period $period_ns
set_clock_uncertainty 0.200 [get_clocks virtual_clock]
set_input_delay 0.000 -clock virtual_clock [all_inputs]
set_output_delay 0.000 -clock virtual_clock [all_outputs]

report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    error "no combinational input-to-output path in checkpoint"
}
set wns [get_property SLACK [lindex $timing_paths 0]]
set data_path_delay [get_property DATAPATH_DELAY [lindex $timing_paths 0]]

set summary_file [open [file join $report_dir summary.txt] w]
puts $summary_file "checkpoint=$checkpoint"
puts $summary_file "virtual_clock_period_ns=$period_ns"
puts $summary_file "clock_uncertainty_ns=0.200"
puts $summary_file "input_output_wns_ns=$wns"
puts $summary_file "input_output_data_path_delay_ns=$data_path_delay"
close $summary_file

puts "COMBINATIONAL CHECKPOINT TIMING PASS period=$period_ns WNS=$wns delay=$data_path_delay"
close_project
