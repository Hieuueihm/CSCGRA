if {$argc != 2} {
    error "usage: check_memory_primitives.tcl <repo_root> <report_dir>"
}
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
create_project -in_memory -part $part_name
source [file join $repo_root scripts synth load_v3_xpm_memory.tcl]
read_verilog -sv [list \
    [file join $repo_root rtl v3 memory recon_sdp_ram.v] \
    [file join $repo_root rtl v3 memory recon_1w2r_ram.v] \
    [file join $repo_root rtl v3 memory recon_epoch_slot_map.v] \
    [file join $repo_root verification v3 memory recon_memory_primitive_synth_top.v]]
synth_design -top recon_memory_primitive_synth_top -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt
report_utilization -hierarchical \
    -file [file join $report_dir utilization.rpt]
set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set lut_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set fp [open [file join $report_dir summary.txt] w]
puts $fp "ramb36_count=$ram36_count"
puts $fp "ramb18_count=$ram18_count"
puts $fp "lut_count=$lut_count"
puts $fp "rtl_memory_directives=none"
close $fp
if {$ram36_count + $ram18_count == 0} {
    error "memory primitives did not infer any block RAM"
}
close_project
