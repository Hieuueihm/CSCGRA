if {$argc != 2} { error "usage: report_m9b_manager_checkpoint.tcl <checkpoint> <report_dir>" }
set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
open_checkpoint $checkpoint
report_timing_summary -delay_type max -max_paths 10 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $paths] == 0} { error "no setup path for support_state_manager" }
set wns [get_property SLACK [lindex $paths 0]]
if {$wns < 1.0} { error "support_state_manager WNS below +1.0 ns: $wns" }
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set r36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set r18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
if {$dsp != 0 || $r18 != 0 || $r36 > 1} {
    error "support_state_manager resource gate failed: DSP=$dsp RAMB36=$r36 RAMB18=$r18"
}
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=xczu7ev-ffvc1156-2-e"
puts $fp "top=support_state_manager"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "lut_count=$lut"
puts $fp "ff_count=$ff"
puts $fp "ramb36_count=$r36"
puts $fp "ramb18_count=$r18"
puts $fp "dsp48_count=$dsp"
close $fp
puts "M9B MANAGER CHECKPOINT PASS WNS=$wns LUT=$lut FF=$ff BRAM36=$r36"
close_design
