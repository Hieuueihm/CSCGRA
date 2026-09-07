if {$argc != 2} {
    error "usage: check_support_coefficient_stripe_store.tcl <repo_root> <report_dir>"
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
    [file join $repo_root rtl v3 memory support_coefficient_stripe_store.v]]

synth_design -top support_coefficient_stripe_store -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks clk]

write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]

set ram36_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set ram18_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set lut_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns "unavailable"
if {[llength $timing_paths] != 0} {
    set measured_wns [get_property SLACK [lindex $timing_paths 0]]
    if {$measured_wns ne ""} {
        set wns $measured_wns
    }
}

set summary_file [open [file join $report_dir summary.txt] w]
puts $summary_file "part=$part_name"
puts $summary_file "clock_period_ns=10.000"
puts $summary_file "clock_uncertainty_ns=0.200"
puts $summary_file "post_synth_wns_ns=$wns"
puts $summary_file "lut_count=$lut_count"
puts $summary_file "ff_count=$ff_count"
puts $summary_file "ramb36_count=$ram36_count"
puts $summary_file "ramb18_count=$ram18_count"
puts $summary_file "rtl_memory_directives=none"
close $summary_file

if {$ram36_count != 0 || $ram18_count != 16} {
    error "stripe store BRAM gate failed: expected 0/16, got $ram36_count/$ram18_count"
}
if {$wns ne "unavailable" && $wns < 0.0} {
    error "stripe store misses 100 MHz: WNS=$wns ns"
}

puts "Support coefficient stripe store PASS WNS=$wns LUT=$lut_count FF=$ff_count BRAM36=$ram36_count"
close_project
