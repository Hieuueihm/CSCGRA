if {$argc != 3} { error "Usage: run_ooc.tcl <v1|v2> <top> <log-dir>" }

set rtl_version [lindex $argv 0]
set top_name [lindex $argv 1]
set log_dir [file normalize [lindex $argv 2]]
if {$rtl_version ni {v1 v2}} { error "Unsupported RTL version: $rtl_version" }

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
if {$rtl_version eq "v1"} {
    set rtl_root [file join $repo_root archive v1 rtl]
} else {
    set rtl_root [file join $repo_root rtl v2]
}
set filelist_path [file join $rtl_root files.f]
set part_name "xczu7ev-ffvc1156-2-e"
set clock_period_ns 10.000

set file_handle [open $filelist_path r]
set rtl_files {}
while {[gets $file_handle line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} { continue }
    lappend rtl_files [file normalize [file join $repo_root $line]]
}
close $file_handle

set include_dirs [list [file join $rtl_root control] [file join $rtl_root solver]]
file mkdir $log_dir
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs $include_dirs [current_fileset]
read_verilog $rtl_files
synth_design -top $top_name -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt -directive RuntimeOptimized
create_clock -period $clock_period_ns -name clk [get_ports clk]
opt_design -directive Explore
place_design -directive Explore
report_timing_summary -file [file join $log_dir "${top_name}_post_place_timing.rpt"] \
    -delay_type max -max_paths 20 -report_unconstrained
phys_opt_design -directive Explore
route_design -directive Explore
report_route_status -file [file join $log_dir "${top_name}_route_status.rpt"]
report_utilization -file [file join $log_dir "${top_name}_impl_utilization.rpt"] -hierarchical
report_timing_summary -file [file join $log_dir "${top_name}_impl_timing.rpt"] \
    -delay_type min_max -max_paths 20 -report_unconstrained
report_drc -file [file join $log_dir "${top_name}_impl_drc.rpt"]
write_checkpoint -force [file join $log_dir "${top_name}_impl_routed.dcp"]
exit
