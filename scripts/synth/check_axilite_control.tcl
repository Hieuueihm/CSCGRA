if {$argc != 2} {
    error "usage: check_axilite_control.tcl <repo_root> <report_dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir

set part_name "xczu7ev-ffvc1156-2-e"
set top_name "m1_control_top"
set include_dir [file join $repo_root rtl v3 include]
set rtl_sources [list \
    [file join $repo_root rtl v3 host_interface axi4lite_slave.v] \
    [file join $repo_root rtl v3 host_interface reconstruction_csr.v] \
    [file join $repo_root rtl v3 top m1_control_top.v]]
set constraint_file [file join $repo_root constraints v3 axilite_control_ooc.xdc]

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $include_dir] [current_fileset]
read_verilog $rtl_sources
read_xdc $constraint_file

synth_design -top $top_name -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt

write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]

set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    error "Vivado produced no setup timing path"
}
set wns [get_property SLACK [lindex $timing_paths 0]]
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=$top_name"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
close $fp

if {$wns < 0.0} {
    error "post-synthesis setup timing failed: WNS=$wns ns"
}
puts "AXI-Lite reconstruction control Vivado synthesis PASS: WNS=$wns ns"
