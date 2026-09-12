set repo_root [file normalize [file join [file dirname [info script]] ../..]]
set part xczu7ev-ffvc1156-2-e
set top ""
set clock_ns 10.0
set out_dir ""

for {set index 0} {$index < $argc} {incr index} {
    set argument [lindex $argv $index]
    if {$argument in {-help --help}} {
        puts "Usage: vivado -mode batch -source scripts/v4/run_ooc_probe.tcl -tclargs -top TOP ?-part PART? ?-clock_ns 10.0? ?-out_dir work/v4_ooc_*?"
        exit 0
    }
    if {$argument ni {-top -part -clock_ns -out_dir}} { error "Unknown argument: $argument" }
    incr index
    if {$index >= $argc} { error "Missing value for $argument" }
    set value [lindex $argv $index]
    switch -- $argument {
        -top { set top $value }
        -part { set part $value }
        -clock_ns { set clock_ns $value }
        -out_dir { set out_dir $value }
    }
}
if {$top eq ""} { error "-top is required" }
if {![string is double -strict $clock_ns] || !($clock_ns > 0)} { error "-clock_ns must be positive" }
if {[llength [get_parts -quiet $part]] != 1} { error "Part not installed or not unique: $part" }
set work_dir [file join $repo_root work]
if {$out_dir eq ""} { set out_dir [file join $work_dir "v4_ooc_${top}_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"] }
if {[file pathtype $out_dir] ne "absolute"} { set out_dir [file join $repo_root $out_dir] }
set out_dir [file normalize $out_dir]
if {[file dirname $out_dir] ne $work_dir || ![string match v4_ooc_* [file tail $out_dir]]} { error "Output must be a direct child of work named v4_ooc_*" }
if {[file exists $out_dir]} { error "Refusing existing output directory: $out_dir" }

set source_files {}
set include_dirs {}
set filelist [open [file join $repo_root rtl v4 files.f] r]
foreach raw_line [split [read $filelist] "\n"] {
    regsub {#.*$} $raw_line {} line
    foreach token [regexp -all -inline {\S+} $line] {
        if {[string first +incdir+ $token] == 0} {
            foreach directory [split [string range $token 8 end] +] {
                set directory [file normalize [file join $repo_root $directory]]
                if {![file isdirectory $directory]} { error "Missing include directory: $directory" }
                lappend include_dirs $directory
            }
        } elseif {[file extension $token] in {.sv .v}} {
            set source [file normalize [file join $repo_root $token]]
            if {![file isfile $source]} { error "Missing RTL: $source" }
            lappend source_files $source
        }
    }
}
close $filelist
file mkdir $out_dir
set snapshot_dir [file join $out_dir source_snapshot]
file mkdir $snapshot_dir
set snapshot_sources {}
foreach source $source_files {
    set target [file join $snapshot_dir [file tail $source]]
    if {[file exists $target]} { error "Duplicate source basename: $source" }
    file copy $source $target
    lappend snapshot_sources $target
}
foreach directory $include_dirs {
    foreach header [glob -nocomplain -directory $directory *.vh *.svh] {
        set target [file join $snapshot_dir [file tail $header]]
        if {[file exists $target]} { error "Duplicate header basename: $header" }
        file copy $header $target
    }
}
set xdc [file join $out_dir probe.xdc]
set channel [open $xdc w]
puts $channel "create_clock -name clk -period $clock_ns \[get_ports clk\]"
close $channel
set channel [open [file join $out_dir run_config.txt] w]
puts $channel "part=$part\ntop=$top\nclock_ns=$clock_ns\nmode=out_of_context\ndirectives=Vivado defaults\nsource_count=[llength $source_files]"
close $channel
file copy [info script] [file join $out_dir run_ooc_probe.tcl]

create_project -in_memory -part $part
set_property include_dirs [list $snapshot_dir] [current_fileset]
read_verilog -sv $snapshot_sources
read_xdc $xdc
synth_design -top $top -part $part -mode out_of_context
write_checkpoint [file join $out_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out_dir timing.rpt]
puts "OOC PROBE COMPLETE: $out_dir"
exit 0
