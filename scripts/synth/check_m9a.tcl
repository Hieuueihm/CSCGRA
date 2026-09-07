if {$argc != 2} { error "usage: check_m9a.tcl <repo_root> <report_dir>" }
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
set include_dir [file join $repo_root rtl v3 include]
set constraint_file [file join $repo_root constraints v3 m9a_ooc.xdc]
set source_file [file join $repo_root rtl v3 selection topk_selection_unit.v]
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $include_dir] [current_fileset]
read_verilog -sv $source_file
read_xdc $constraint_file
synth_design -top topk_selection_unit -part $part_name -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} { error "no setup path for topk_selection_unit" }
set wns [get_property SLACK [lindex $timing_paths 0]]
if {$wns < 0.2} { error "topk_selection_unit WNS below +0.2 ns: $wns" }
if {$ram36_count != 0 || $ram18_count != 0 || $dsp_count != 0} {
    error "topk_selection_unit expected 0 BRAM/0 DSP, got $ram36_count/$ram18_count/$dsp_count"
}
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=topk_selection_unit"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "ramb36_count=$ram36_count"
puts $fp "ramb18_count=$ram18_count"
puts $fp "dsp48_count=$dsp_count"
close $fp
puts "M9a topk_selection_unit synthesis PASS: WNS=$wns BRAM36=$ram36_count BRAM18=$ram18_count DSP=$dsp_count"
close_project
