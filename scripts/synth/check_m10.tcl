if {$argc != 3} { error "usage: check_m10.tcl <repo_root> <report_dir> <top>" }
set repo_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set top_name [lindex $argv 2]
file mkdir $report_dir
set part_name "xczu7ev-ffvc1156-2-e"
if {$top_name eq "normal_residual_checker"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 refinement certificate_limit_unit.v] \
        [file join $repo_root rtl v3 refinement normal_residual_checker.v]]
} elseif {$top_name eq "restricted_refinement_state"} {
    set rtl_sources [list [file join $repo_root rtl v3 refinement restricted_refinement_state.v]]
} elseif {$top_name eq "m8_resource_dispatcher"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 memory recon_sdp_ram.v] \
        [file join $repo_root rtl v3 memory recon_1w2r_ram.v] \
        [file join $repo_root rtl v3 memory support_coefficient_stripe_store.v] \
        [file join $repo_root rtl v3 selection topk_selection_unit.v] \
        [file join $repo_root rtl v3 selection proxy_candidate_collector.v] \
        [file join $repo_root rtl v3 selection support_workspace.v] \
        [file join $repo_root rtl v3 selection support_state_manager.v] \
        [file join $repo_root rtl v3 selection support_coefficient_remapper.v] \
        [file join $repo_root rtl v3 refinement certificate_limit_unit.v] \
        [file join $repo_root rtl v3 refinement normal_residual_checker.v] \
        [file join $repo_root rtl v3 integration m8_resource_dispatcher.v]]
} elseif {$top_name eq "m10_refinement_integration"} {
    set rtl_sources [list \
        [file join $repo_root rtl v3 refinement certificate_limit_unit.v] \
        [file join $repo_root rtl v3 refinement normal_residual_checker.v] \
        [file join $repo_root rtl v3 refinement restricted_refinement_state.v] \
        [file join $repo_root rtl v3 integration m10_refinement_integration.v]]
} else {
    error "unsupported M10 top: $top_name"
}
create_project -in_memory -part $part_name
source [file join $repo_root scripts synth load_v3_xpm_memory.tcl]
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root rtl v3 include]] [current_fileset]
read_verilog -sv $rtl_sources
read_xdc [file join $repo_root constraints v3 m10_ooc.xdc]
if {$top_name eq "m8_resource_dispatcher"} {
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt
} else {
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt
}
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $paths] == 0} { error "no setup path for $top_name" }
set wns [get_property SLACK [lindex $paths 0]]
if {$wns < 1.0} { error "$top_name WNS below +1.0 ns: $wns" }
set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
set ff [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
set r36 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]]
set r18 [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}]]
if {$dsp != 0 || $r18 != 0 ||
    (($top_name ne "m8_resource_dispatcher") && ($r36 != 0)) ||
    (($top_name eq "m8_resource_dispatcher") && ($r36 > 1))} {
    error "$top_name expected register/LUT-only implementation"
}
set fp [open [file join $report_dir summary.txt] w]
puts $fp "part=$part_name"
puts $fp "top=$top_name"
puts $fp "clock_period_ns=6.667"
puts $fp "clock_uncertainty_ns=0.200"
puts $fp "post_synth_wns_ns=$wns"
puts $fp "lut_count=$lut"
puts $fp "ff_count=$ff"
puts $fp "ramb36_count=$r36"
puts $fp "ramb18_count=$r18"
puts $fp "dsp48_count=$dsp"
close $fp
puts "M10 OOC PASS top=$top_name WNS=$wns LUT=$lut FF=$ff BRAM36=$r36"
close_project
