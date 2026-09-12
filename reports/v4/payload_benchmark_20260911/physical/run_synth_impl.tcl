set repo_root [file normalize [file join [file dirname [info script]] ../..]]
set part xczu7ev-ffvc1156-2-e
set clock_ns 10.0
set stage impl
set out_dir ""
set check_only 0

for {set index 0} {$index < $argc} {incr index} {
    set argument [lindex $argv $index]
    if {$argument in {-help --help}} {
        puts "Usage: vivado -mode batch -source scripts/v4/run_synth_impl.tcl -tclargs ?-stage synth|impl? ?-part PART? ?-clock_ns 10.0? ?-out_dir work/v4_impl_NAME? ?-check_only?"
        exit 0
    }
    if {$argument eq "-check_only"} { set check_only 1; continue }
    if {$argument ni {-stage -part -clock_ns -out_dir}} { error "Unknown argument: $argument" }
    incr index
    if {$index >= $argc} { error "Missing value for $argument" }
    set value [lindex $argv $index]
    switch -- $argument {
        -stage { set stage $value }
        -part { set part $value }
        -clock_ns { set clock_ns $value }
        -out_dir { set out_dir $value }
    }
}
if {$stage ni {synth impl}} { error "-stage must be synth or impl" }
if {![string is double -strict $clock_ns] || !($clock_ns > 0 && $clock_ns < 1000000)} {
    error "-clock_ns must be a positive finite period below 1000000 ns"
}
if {[llength [get_parts -quiet $part]] != 1} { error "Part not installed or not unique: $part" }
set work_dir [file join $repo_root work]
if {$out_dir eq ""} {
    set out_dir [file join $work_dir "v4_impl_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
}
if {[file pathtype $out_dir] ne "absolute"} { set out_dir [file join $repo_root $out_dir] }
set out_dir [file normalize $out_dir]
if {[file dirname $out_dir] ne $work_dir || ![string match v4_impl_* [file tail $out_dir]]} {
    error "Output must be a new direct child of work named v4_impl_*"
}
if {[file exists $out_dir]} { error "Refusing existing output directory: $out_dir" }

set source_files {}
set include_dirs {}
set filelist [open [file join $repo_root rtl v4 files.f] r]
set filelist_text [read $filelist]
close $filelist
foreach raw_line [split $filelist_text "\n"] {
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
        } else {
            error "Unsupported file-list token: $token"
        }
    }
}
if {[llength $source_files] == 0} { error "Empty source file list" }
if {$check_only} {
    puts "PREFLIGHT PASS: part=$part top=csr_top clock_ns=$clock_ns stage=$stage sources=[llength $source_files]"
    puts "No synthesis, implementation or output directory created."
    exit 0
}

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
file copy [info script] [file join $out_dir run_synth_impl.tcl]
set constraints [file join $out_dir csr_top_ooc.xdc]
set channel [open $constraints w]
puts $channel "create_clock -name s_axi_aclk -period $clock_ns \[get_ports s_axi_aclk\]"
close $channel
set channel [open [file join $out_dir run_config.txt] w]
puts $channel "part=$part\ntop=csr_top\nclock_ns=$clock_ns\nstage=$stage\nmode=out_of_context\ndirectives=Vivado defaults\ninterface_timing=not constrained; internal-clock baseline only\nbitstream=not requested"
close $channel

create_project -in_memory -part $part
set_property include_dirs [list $snapshot_dir] [current_fileset]
read_verilog -sv $snapshot_sources
read_xdc $constraints
synth_design -top csr_top -part $part -mode out_of_context
write_checkpoint [file join $out_dir post_synth.dcp]
report_utilization -file [file join $out_dir synth_utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out_dir synth_timing_summary.rpt]
if {$stage eq "synth"} {
    puts "SYNTH FLOW COMPLETE: $out_dir (not timing sign-off)"
    exit 0
}
opt_design
place_design
route_design
write_checkpoint [file join $out_dir post_route.dcp]
report_utilization -file [file join $out_dir impl_utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out_dir impl_timing_summary.rpt]
report_drc -file [file join $out_dir impl_drc.rpt]
report_route_status -file [file join $out_dir impl_route_status.rpt]
check_timing -verbose -file [file join $out_dir impl_check_timing.rpt]
puts "ROUTE FLOW COMPLETE: $out_dir (inspect final timing/DRC/route reports; not board sign-off)"
