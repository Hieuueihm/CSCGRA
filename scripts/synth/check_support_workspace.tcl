if {$argc != 2} {
    error "usage: check_support_workspace.tcl <repo_root> <report_dir>"
}
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
create_project -in_memory -part $part_name
source [file join $repo_root scripts synth load_v3_xpm_memory.tcl]
set_property include_dirs [list [file join $repo_root rtl v3 include]] \
    [current_fileset]
read_verilog -sv [list \
    [file join $repo_root rtl v3 memory recon_sdp_ram.v] \
    [file join $repo_root rtl v3 memory recon_1w2r_ram.v] \
    [file join $repo_root rtl v3 memory support_coefficient_stripe_store.v] \
    [file join $repo_root rtl v3 selection support_workspace.v]]
synth_design -top support_workspace -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt
report_utilization -hierarchical \
    -file [file join $report_dir utilization.rpt]
set lut_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set lutram_count [llength [get_cells -quiet -hier -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256*}]]
set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set fp [open [file join $report_dir summary.txt] w]
puts $fp "lut_count=$lut_count"
puts $fp "ff_count=$ff_count"
puts $fp "lutram_primitive_count=$lutram_count"
puts $fp "ramb36_count=$ram36_count"
puts $fp "ramb18_count=$ram18_count"
close $fp
close_project
