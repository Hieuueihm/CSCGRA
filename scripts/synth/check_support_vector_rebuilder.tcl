if {$argc != 2} {
    error "usage: check_support_vector_rebuilder.tcl <repo_root> <report_dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir

create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root rtl v3 include]] \
    [current_fileset]
read_verilog -sv [file join $repo_root rtl v3 selection support_vector_rebuilder.v]
synth_design -top support_vector_rebuilder -part xczu7ev-ffvc1156-2-e \
    -mode out_of_context -flatten_hierarchy rebuilt

write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set summary_file [open [file join $report_dir summary.txt] w]
puts $summary_file "top=support_vector_rebuilder"
puts $summary_file "lut_count=$lut"
puts $summary_file "ff_count=$ff"
close $summary_file
puts "SUPPORT VECTOR REBUILDER OOC PASS LUT=$lut FF=$ff"
close_project
