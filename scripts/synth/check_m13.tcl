if {$argc != 2} { error "usage: check_m13.tcl <repo_root> <report_dir>" }
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root rtl v3 include]] [current_fileset]
source [file join $repo_root scripts synth load_v3_xpm_memory.tcl]
set manifest [open [file join $repo_root rtl v3 files.f] r]
set rtl_sources [list]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "+*" $line]} { continue }
    lappend rtl_sources [file join $repo_root $line]
}
close $manifest
read_verilog -sv $rtl_sources
read_xdc [file join $repo_root constraints v3 m13_ooc.xdc]
synth_design -top m13_compute_lifecycle_integration -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set timing_check_fp [open [file join $report_dir check_timing.rpt] r]
set timing_check_text [read $timing_check_fp]
close $timing_check_fp
if {[regexp {There (is|are) [1-9][0-9]* combinational loop} $timing_check_text]} {
    error "M13 integration contains a combinational timing loop"
}
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $paths] == 0} { error "no setup path for M13 integration" }
set wns [get_property SLACK [lindex $paths 0]]
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set r36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set r18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
set pass [expr {$wns >= 0.2}]
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=m13_compute_lifecycle_integration"
puts $fp "clock_period_ns=10.000"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "wns_gate_min_ns=0.2"
puts $fp "wns_gate_pass=$pass"
puts $fp "lut_count=$lut"
puts $fp "ff_count=$ff"
puts $fp "ramb36_count=$r36"
puts $fp "ramb18_count=$r18"
puts $fp "dsp48_count=$dsp"
puts $fp "synthesis_directives=none"
puts $fp "implementation_directives=none"
close $fp
if {!$pass} { error "M13 integration WNS below +0.2 ns: $wns" }
puts "M13 OOC PASS WNS=$wns LUT=$lut FF=$ff RAMB36=$r36 RAMB18=$r18 DSP=$dsp"
close_project
