set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set filelist_file [file join $repo_root rtl v4 files.f]
set top_file [file join $repo_root rtl v4 top csr_top.sv]
set work_dir [file join $repo_root work]
set default_out_dir [file join $work_dir "v4_ip_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]

proc assert_true {condition message} {
    if {!$condition} {
        error "Assertion failed: $message"
    }
}

proc assert_equal {actual expected message} {
    if {$actual ne $expected} {
        error "Assertion failed: $message (actual '$actual', expected '$expected')"
    }
}

proc append_unique {list_var value} {
    upvar 1 $list_var values
    if {[lsearch -exact $values $value] < 0} {
        lappend values $value
    }
}

proc read_text {path} {
    set channel [open $path r]
    fconfigure $channel -translation lf
    set contents [read $channel]
    close $channel
    return $contents
}

proc normalize_path {base path} {
    if {[file pathtype $path] eq "absolute"} {
        return [file normalize $path]
    }
    return [file normalize [file join $base $path]]
}

proc parse_filelist {path root sources_var include_dirs_var visited_var} {
    upvar 1 $sources_var sources
    upvar 1 $include_dirs_var include_dirs
    upvar 1 $visited_var visited

    set path [file normalize $path]
    assert_true [file isfile $path] "missing file list '$path'"
    if {[lsearch -exact $visited $path] >= 0} {
        return
    }
    lappend visited $path

    set tokens_by_line [split [read_text $path] "\n"]
    foreach raw_line $tokens_by_line {
        regsub {#.*$} $raw_line {} line
        set tokens [regexp -all -inline {[^	 \r\n]+} $line]
        for {set index 0} {$index < [llength $tokens]} {incr index} {
            set token [lindex $tokens $index]
            if {$token eq "-f"} {
                incr index
                assert_true [expr {$index < [llength $tokens]}] "missing file after -f in '$path'"
                set nested [normalize_path [file dirname $path] [lindex $tokens $index]]
                parse_filelist $nested $root sources include_dirs visited
                continue
            }
            if {[string first "+incdir+" $token] == 0} {
                set directory_text [string range $token [string length "+incdir+"] end]
                foreach directory_name [split $directory_text +] {
                    if {$directory_name eq ""} {
                        continue
                    }
                    set directory [normalize_path $root $directory_name]
                    assert_true [file isdirectory $directory] "missing include directory '$directory'"
                    append_unique include_dirs $directory
                }
                continue
            }
            set extension [string tolower [file extension $token]]
            assert_true [expr {[lsearch -exact [list .sv .v] $extension] >= 0}] \
                "unsupported file-list token '$token' in '$path'"
            set source [normalize_path $root $token]
            assert_true [file isfile $source] "missing file-list source '$source'"
            append_unique sources $source
        }
    }
}

proc collect_include_closure {path include_dirs_var headers_var visited_var} {
    upvar 1 $include_dirs_var include_dirs
    upvar 1 $headers_var headers
    upvar 1 $visited_var visited

    set path [file normalize $path]
    if {[lsearch -exact $visited $path] >= 0} {
        return
    }
    lappend visited $path

    set matches [regexp -all -inline {`include[[:space:]]+"([^"]+)"} [read_text $path]]
    foreach {whole include_name} $matches {
        set candidates [list [file join [file dirname $path] $include_name]]
        foreach directory $include_dirs {
            lappend candidates [file join $directory $include_name]
        }
        set resolved ""
        foreach candidate $candidates {
            set candidate [file normalize $candidate]
            if {[file isfile $candidate]} {
                set resolved $candidate
                break
            }
        }
        assert_true [expr {$resolved ne ""}] \
            "missing included header '$include_name' required by '$path'"
        append_unique headers $resolved
        collect_include_closure $resolved include_dirs headers visited
    }
}

proc require_hdl_port {contents name direction width} {
    if {$width == 1} {
        set pattern [format {%s[[:space:]]+(?:(?:wire|reg|logic)[[:space:]]+)?%s[[:space:]]*[,)]} \
            $direction $name]
    } else {
        set left [expr {$width - 1}]
        set pattern [format {%s[[:space:]]+(?:(?:wire|reg|logic)[[:space:]]+)?\[%d:0\][[:space:]]+%s[[:space:]]*[,)]} \
            $direction $left $name]
    }
    assert_true [regexp -nocase -- $pattern $contents] \
        "csr_top source port '$name' does not match $direction/$width"
}

proc get_or_create_bus_interface {core name bus_vlnv abstraction_vlnv mode description} {
    set interfaces [ipx::get_bus_interfaces $name -of_objects $core]
    assert_true [expr {[llength $interfaces] <= 1}] "duplicate bus interface '$name'"
    if {[llength $interfaces] == 0} {
        set interface [ipx::add_bus_interface $name $core]
    } else {
        set interface [lindex $interfaces 0]
    }
    set_property bus_type_vlnv $bus_vlnv $interface
    set_property abstraction_type_vlnv $abstraction_vlnv $interface
    set_property interface_mode $mode $interface
    set_property display_name $name $interface
    set_property description $description $interface
    return $interface
}

proc ensure_port_map {core interface logical_name physical_name} {
    set ports [ipx::get_ports $physical_name -of_objects $core]
    assert_true [expr {[llength $ports] == 1}] "missing top-level port '$physical_name'"

    set matches {}
    foreach port_map [ipx::get_port_maps -of_objects $interface] {
        if {[get_property logical_name $port_map] eq $logical_name} {
            lappend matches $port_map
        }
    }
    assert_true [expr {[llength $matches] <= 1}] "duplicate '$logical_name' map on '[get_property name $interface]'"
    if {[llength $matches] == 0} {
        set port_map [ipx::add_port_map $logical_name $interface]
    } else {
        set port_map [lindex $matches 0]
    }
    set_property logical_name $logical_name $port_map
    set_property physical_name $physical_name $port_map
}

proc ensure_bus_parameter {interface name value} {
    set parameters [ipx::get_bus_parameters $name -of_objects $interface]
    assert_true [expr {[llength $parameters] <= 1}] \
        "duplicate bus parameter '$name' on '[get_property name $interface]'"
    if {[llength $parameters] == 0} {
        set parameter [ipx::add_bus_parameter $name $interface]
    } else {
        set parameter [lindex $parameters 0]
    }
    set_property value $value $parameter
}

proc stage_local_sources {package_root project_files} {
    set source_dir [file join $package_root src]
    file mkdir $source_dir
    set local_files {}
    set basenames {}
    foreach source $project_files {
        set basename [file tail $source]
        assert_true [expr {[lsearch -exact $basenames $basename] < 0}] \
            "duplicate source/header basename '$basename' cannot be staged flat"
        lappend basenames $basename
        set destination [file join $source_dir $basename]
        if {[catch {file copy -force $source $destination} copy_error]} {
            error "failed to copy source/header '$source' into package source directory: $copy_error"
        }
        lappend local_files [file normalize $destination]
    }
    return $local_files
}

proc canonicalize_interrupt_interface {core} {
    set candidates {}
    foreach interface [ipx::get_bus_interfaces -of_objects $core] {
        set name [get_property name $interface]
        if {$name eq "INTERRUPT" || $name eq "irq"} {
            append_unique candidates $interface
        }
    }
    if {[llength $candidates] == 0} {
        return ""
    }

    set selected [lindex $candidates 0]
    foreach interface $candidates {
        if {[get_property name $interface] eq "INTERRUPT"} {
            set selected $interface
            break
        }
    }
    foreach interface $candidates {
        if {[string equal $interface $selected]} {
            continue
        }
        set duplicate_name [get_property name $interface]
        if {[catch {ipx::remove_bus_interface $duplicate_name $core} remove_error]} {
            error "failed to remove duplicate interrupt interface '$duplicate_name': $remove_error"
        }
    }
    if {[get_property name $selected] ne "INTERRUPT"} {
        set_property name INTERRUPT $selected
    }
    return $selected
}

proc rewrite_package_file_groups {core package_root project_files headers} {
    set group_names {xilinx_anylanguagesynthesis xilinx_anylanguagebehavioralsimulation}
    set groups {}
    foreach group_name $group_names {
        set matches [ipx::get_file_groups $group_name -of_objects $core]
        assert_true [expr {[llength $matches] == 1}] \
            "expected one packaged file group '$group_name'"
        lappend groups [lindex $matches 0]
    }

    set header_paths {}
    foreach header $headers {
        lappend header_paths [file normalize $header]
    }

    set previous_directory [pwd]
    foreach group $groups {
        foreach file [ipx::get_files -of_objects $group] {
            set file_name [get_property name $file]
            if {[catch {ipx::remove_file $file_name $group} remove_error]} {
                error "failed to remove packaged file '$file_name': $remove_error"
            }
        }
        assert_equal [llength [ipx::get_files -of_objects $group]] 0 \
            "failed to clear packaged file group '[get_property name $group]'"
        set_property dependency [list src] $group

        cd $package_root
        foreach source $project_files {
            set relative_name [file join src [file tail $source]]
            set file [ipx::add_file $relative_name $group]
            set extension [string tolower [file extension $source]]
            if {$extension eq ".sv"} {
                set_property type systemVerilogSource $file
                set_property is_include false $file
            } elseif {$extension eq ".v"} {
                set_property type verilogSource $file
                set_property is_include false $file
            } elseif {$extension eq ".vh"} {
                set_property type verilogSource $file
                set_property is_include true $file
            } else {
                error "unsupported packaged closure extension '$extension'"
            }
            assert_equal [string map {\\ /} [get_property name $file]] \
                [string map {\\ /} $relative_name] \
                "packaged file path for '[file tail $source]'"
            if {[lsearch -exact $header_paths [file normalize $source]] >= 0} {
                set include_value [string tolower [get_property is_include $file]]
                assert_true [expr {$include_value eq "true" || $include_value eq "1"}] \
                    "include flag for '[file tail $source]'"
            }
        }
        cd $previous_directory
    }
}

proc assert_relative_package_file_groups {core} {
    foreach group_name {xilinx_anylanguagesynthesis xilinx_anylanguagebehavioralsimulation} {
        set group [lindex [ipx::get_file_groups $group_name -of_objects $core] 0]
        set dependency [get_property dependency $group]
        foreach directory $dependency {
            assert_true [expr {[file pathtype $directory] eq "relative"}] \
                "packaged file-group dependency '$directory' is not relative"
        }
        foreach file [ipx::get_files -of_objects $group] {
            set file_name [string map {\\ /} [get_property name $file]]
            assert_true [expr {[file pathtype $file_name] eq "relative"}] \
                "packaged file '$file_name' is not relative"
            assert_true [string match {src/*} $file_name] \
                "packaged file '$file_name' is outside package src/"
        }
    }
}

proc ensure_memory_map {core bus_interface} {
    set memory_maps [ipx::get_memory_maps S_AXI -of_objects $core]
    assert_true [expr {[llength $memory_maps] <= 1}] "duplicate S_AXI memory map"
    if {[llength $memory_maps] == 0} {
        set memory_map [ipx::add_memory_map S_AXI $core]
    } else {
        set memory_map [lindex $memory_maps 0]
    }
    set_property display_name S_AXI_MEM $memory_map
    set_property description {4 KiB AXI4-Lite register window} $memory_map

    set blocks [ipx::get_address_blocks -of_objects $memory_map]
    assert_true [expr {[llength $blocks] <= 1}] "duplicate S_AXI address blocks"
    if {[llength $blocks] == 0} {
        set block [ipx::add_address_block Reg $memory_map]
    } else {
        set block [lindex $blocks 0]
        set_property name Reg $block
    }
    set_property display_name Reg $block
    set_property description {CSR register block} $block
    set_property base_address 0 $block
    set_property range 4096 $block
    set_property width 32 $block
    set_property access read-write $block
    set_property usage register $block
    set_property slave_memory_map_ref S_AXI $bus_interface

    assert_equal [get_property base_address $block] 0 {S_AXI base address}
    assert_equal [get_property range $block] 4096 {S_AXI map range}
    assert_equal [get_property width $block] 32 {S_AXI data width}
    assert_equal [get_property access $block] read-write {S_AXI block access}
    return $memory_map
}

proc assert_core_port {core name direction width} {
    set ports [ipx::get_ports $name -of_objects $core]
    assert_true [expr {[llength $ports] == 1}] "packaged port '$name' is missing or duplicated"
    set port [lindex $ports 0]
    assert_equal [get_property direction $port] $direction "direction of '$name'"
    if {$width > 1} {
        assert_equal [get_property size_left $port] [expr {$width - 1}] "left bound of '$name'"
        assert_equal [get_property size_right $port] 0 "right bound of '$name'"
    }
}

set out_dir ""
set part ""
for {set index 0} {$index < $argc} {incr index} {
    set argument [lindex $argv $index]
    switch -- $argument {
        -out_dir {
            incr index
            assert_true [expr {$index < $argc}] "-out_dir requires a path"
            set out_dir [lindex $argv $index]
        }
        -part {
            incr index
            assert_true [expr {$index < $argc}] "-part requires a device part"
            set part [lindex $argv $index]
        }
        -help - --help {
            puts "Usage: vivado -mode batch -source scripts/v4/package_csr_ip.tcl -tclargs -out_dir work/v4_ip_UNIQUE [-part PART]"
            exit 0
        }
        default {
            error "unknown argument '$argument'"
        }
    }
}

assert_true [file isfile $filelist_file] "missing V4 file list '$filelist_file'"
assert_true [file isfile $top_file] "missing csr_top source '$top_file'"

set top_contents [read_text $top_file]
set required_hdl_ports [list \
    [list s_axi_aclk input 1] \
    [list s_axi_aresetn input 1] \
    [list s_axi_awaddr input 12] \
    [list s_axi_awprot input 3] \
    [list s_axi_awvalid input 1] \
    [list s_axi_awready output 1] \
    [list s_axi_wdata input 32] \
    [list s_axi_wstrb input 4] \
    [list s_axi_wvalid input 1] \
    [list s_axi_wready output 1] \
    [list s_axi_bresp output 2] \
    [list s_axi_bvalid output 1] \
    [list s_axi_bready input 1] \
    [list s_axi_araddr input 12] \
    [list s_axi_arprot input 3] \
    [list s_axi_arvalid input 1] \
    [list s_axi_arready output 1] \
    [list s_axi_rdata output 32] \
    [list s_axi_rresp output 2] \
    [list s_axi_rvalid output 1] \
    [list s_axi_rready input 1] \
    [list irq output 1]]
set dma_hdl_ports [list \
    [list m_axi_awaddr output 64] \
    [list m_axi_awlen output 8] \
    [list m_axi_awsize output 3] \
    [list m_axi_awburst output 2] \
    [list m_axi_awlock output 1] \
    [list m_axi_awcache output 4] \
    [list m_axi_awprot output 3] \
    [list m_axi_awqos output 4] \
    [list m_axi_awvalid output 1] \
    [list m_axi_awready input 1] \
    [list m_axi_wdata output 128] \
    [list m_axi_wstrb output 16] \
    [list m_axi_wlast output 1] \
    [list m_axi_wvalid output 1] \
    [list m_axi_wready input 1] \
    [list m_axi_bresp input 2] \
    [list m_axi_bvalid input 1] \
    [list m_axi_bready output 1] \
    [list m_axi_araddr output 64] \
    [list m_axi_arlen output 8] \
    [list m_axi_arsize output 3] \
    [list m_axi_arburst output 2] \
    [list m_axi_arlock output 1] \
    [list m_axi_arcache output 4] \
    [list m_axi_arprot output 3] \
    [list m_axi_arqos output 4] \
    [list m_axi_arvalid output 1] \
    [list m_axi_arready input 1] \
    [list m_axi_rdata input 128] \
    [list m_axi_rresp input 2] \
    [list m_axi_rlast input 1] \
    [list m_axi_rvalid input 1] \
    [list m_axi_rready output 1]]
set required_hdl_ports [concat $required_hdl_ports $dma_hdl_ports]
foreach port_spec $required_hdl_ports {
    require_hdl_port $top_contents [lindex $port_spec 0] [lindex $port_spec 1] [lindex $port_spec 2]
}

set source_files {}
set include_dirs {}
set filelist_visited {}
parse_filelist $filelist_file $repo_root source_files include_dirs filelist_visited

set appended_sources [list \
    [file join $repo_root rtl v4 host host_command_bridge.sv] \
    $top_file]
foreach source $appended_sources {
    assert_true [file isfile $source] "missing appended host/top source '$source'"
    append_unique source_files [file normalize $source]
}

set headers {}
set include_visited {}
foreach source $source_files {
    collect_include_closure $source include_dirs headers include_visited
}
set project_files {}
foreach source [concat $source_files $headers] {
    append_unique project_files $source
}

if {$out_dir eq ""} {
    set out_dir $default_out_dir
} elseif {[file pathtype $out_dir] ne "absolute"} {
    set out_dir [file join $repo_root $out_dir]
}
set out_dir [file normalize $out_dir]
set expected_work_dir [file normalize $work_dir]
assert_equal [file normalize [file dirname $out_dir]] $expected_work_dir {package output parent}
assert_true [string match {v4_ip_*} [file tail $out_dir]] \
    "package output must be named work/v4_ip_*"
assert_true [expr {![file exists $out_dir]}] \
    "refusing existing package destination '$out_dir'"

file mkdir [file dirname $out_dir]
file mkdir $out_dir
set project_dir [file join $out_dir packager_project]
set local_project_files [stage_local_sources $out_dir $project_files]
if {$part eq ""} {
    create_project csr_top_ip $project_dir
} else {
    create_project csr_top_ip $project_dir -part $part
}

set added_files [add_files -norecurse -fileset sources_1 $local_project_files]
assert_true [expr {[llength $added_files] >= [llength $local_project_files]}] \
    {Vivado did not add the complete V4 source list}
set source_set [get_filesets sources_1]
set_property include_dirs [list [file join $out_dir src]] $source_set
set_property top csr_top $source_set
update_compile_order -fileset sources_1

set packaged_core [ipx::package_project -root_dir $out_dir -vendor user.org -library ip \
    -taxonomy /UserIP -import_files -set_current true]
set core [ipx::current_core]
if {$core eq ""} {
    set core $packaged_core
}
assert_true [expr {$core ne ""}] {ipx::package_project did not create a current core}
set_property vendor user.org $core
set_property library ip $core
set_property name csr_top $core
set_property version 1.0 $core
assert_equal [get_property vendor $core] user.org {core vendor}
assert_equal [get_property library $core] ip {core library}
assert_equal [get_property name $core] csr_top {core name}
assert_equal [get_property version $core] 1.0 {core version}
set_property display_name {CSR Control and Status} $core
set_property description {AXI4-Lite control and AXI4 payload DMA wrapper for the recovery engine} $core

stage_local_sources $out_dir $project_files
rewrite_package_file_groups $core $out_dir $project_files $headers
assert_relative_package_file_groups $core

set expected_core_ports {}
foreach port_spec $required_hdl_ports {
    set name [lindex $port_spec 0]
    set direction [lindex $port_spec 1]
    set width [lindex $port_spec 2]
    lappend expected_core_ports $name
    assert_core_port $core $name [string map {input in output out} $direction] $width
}
set actual_core_ports {}
foreach port [ipx::get_ports -of_objects $core] {
    lappend actual_core_ports [get_property name $port]
}
foreach name $actual_core_ports {
    assert_true [expr {[lsearch -exact $expected_core_ports $name] >= 0}] \
        "unexpected packaged top-level port '$name'"
}

set axi [get_or_create_bus_interface $core S_AXI \
    xilinx.com:interface:aximm:1.0 \
    xilinx.com:interface:aximm_rtl:1.0 slave \
    {AXI4-Lite 32-bit slave interface}]
foreach port_map_spec [list \
    [list AWADDR s_axi_awaddr] [list AWPROT s_axi_awprot] \
    [list AWVALID s_axi_awvalid] [list AWREADY s_axi_awready] \
    [list WDATA s_axi_wdata] [list WSTRB s_axi_wstrb] \
    [list WVALID s_axi_wvalid] [list WREADY s_axi_wready] \
    [list BRESP s_axi_bresp] [list BVALID s_axi_bvalid] \
    [list BREADY s_axi_bready] [list ARADDR s_axi_araddr] \
    [list ARPROT s_axi_arprot] [list ARVALID s_axi_arvalid] \
    [list ARREADY s_axi_arready] [list RDATA s_axi_rdata] \
    [list RRESP s_axi_rresp] [list RVALID s_axi_rvalid] \
    [list RREADY s_axi_rready]] {
    ensure_port_map $core $axi [lindex $port_map_spec 0] [lindex $port_map_spec 1]
}

set master [get_or_create_bus_interface $core M_AXI \
    xilinx.com:interface:aximm:1.0 \
    xilinx.com:interface:aximm_rtl:1.0 master \
    {AXI4 128-bit payload DMA master}]
foreach port_spec $dma_hdl_ports {
    set physical [lindex $port_spec 0]
    ensure_port_map $core $master [string toupper [string range $physical 6 end]] $physical
}
foreach {name value} {PROTOCOL AXI4 DATA_WIDTH 128 ADDR_WIDTH 64 MAX_BURST_LENGTH 8 NUM_READ_OUTSTANDING 1 NUM_WRITE_OUTSTANDING 1} {
    ensure_bus_parameter $master $name $value
}
set dma_space [ipx::get_address_spaces M_AXI -of_objects $core]
if {$dma_space eq ""} {set dma_space [ipx::add_address_space M_AXI $core]}
set_property range 18446744073709551616 $dma_space
set_property width 128 $dma_space
set_property master_address_space_ref M_AXI $master

set clock [get_or_create_bus_interface $core S_AXI_ACLK \
    xilinx.com:signal:clock:1.0 \
    xilinx.com:signal:clock_rtl:1.0 slave \
    {AXI clock}]
ensure_port_map $core $clock CLK s_axi_aclk

set reset [get_or_create_bus_interface $core S_AXI_ARESETN \
    xilinx.com:signal:reset:1.0 \
    xilinx.com:signal:reset_rtl:1.0 slave \
    {Active-low AXI reset}]
ensure_port_map $core $reset RST s_axi_aresetn
ensure_bus_parameter $reset POLARITY ACTIVE_LOW

set interrupt [canonicalize_interrupt_interface $core]
if {$interrupt eq ""} {
    set interrupt [get_or_create_bus_interface $core INTERRUPT \
        xilinx.com:signal:interrupt:1.0 \
        xilinx.com:signal:interrupt_rtl:1.0 master \
        {Level-high completion/error interrupt}]
}
assert_true [expr {$interrupt ne ""}] {canonical INTERRUPT bus interface is missing}
ensure_port_map $core $interrupt INTERRUPT irq
ensure_bus_parameter $interrupt SENSITIVITY LEVEL_HIGH

if {[catch {ipx::associate_bus_interfaces -busif S_AXI -clock S_AXI_ACLK -reset s_axi_aresetn $core} association_error]} {
    error "failed to associate S_AXI with S_AXI_ACLK/s_axi_aresetn: $association_error"
}
ipx::associate_bus_interfaces -busif M_AXI -clock S_AXI_ACLK -reset s_axi_aresetn $core
ensure_bus_parameter $clock ASSOCIATED_BUSIF S_AXI:M_AXI
ensure_bus_parameter $clock ASSOCIATED_RESET S_AXI_ARESETN
ensure_memory_map $core $axi

set all_interfaces [ipx::get_bus_interfaces -of_objects $core]
set expected_interfaces {S_AXI M_AXI S_AXI_ACLK S_AXI_ARESETN INTERRUPT}
set actual_interface_names {}
foreach interface $all_interfaces {
    set interface_name [get_property name $interface]
    lappend actual_interface_names $interface_name
    assert_true [expr {[lsearch -exact $expected_interfaces $interface_name] >= 0}] \
        "unexpected packaged bus interface '$interface_name'"
}
foreach interface_name $expected_interfaces {
    assert_true [expr {[llength [ipx::get_bus_interfaces $interface_name -of_objects $core]] == 1}] \
        "required bus interface '$interface_name' is missing or duplicated"
}
assert_equal [lsort -dictionary $actual_interface_names] [lsort -dictionary $expected_interfaces] \
    {exact packaged bus interface set}

set integrity_result PASS
if {[catch {ipx::check_integrity -verbose $core} integrity_error]} {
    error "ipx::check_integrity failed: $integrity_error"
}
ipx::save_core $core

set component_xml [file join $out_dir component.xml]
assert_true [file isfile $component_xml] "packaged component.xml is missing"
set component_text [read_text $component_xml]
set component_text_normalized [string map {\\ /} $component_text]
set component_text_lower [string tolower $component_text_normalized]
set repo_root_lower [string tolower [string map {\\ /} $repo_root]]
assert_true [expr {[string first $repo_root_lower $component_text_lower] < 0}] \
    {component.xml contains an external repository source path}
foreach source $project_files {
    set relative_name [string tolower [string map {\\ /} [file join src [file tail $source]]]]
    assert_true [expr {[string first $relative_name $component_text_lower] >= 0}] \
        "component.xml does not contain package-local file '[file tail $source]'"
}

set integrity_log [file join $out_dir integrity.log]
set integrity_channel [open $integrity_log w]
puts $integrity_channel {IP-XACT integrity: PASS}
puts $integrity_channel {VLNV: user.org:ip:csr_top:1.0}
puts $integrity_channel {BUS_INTERFACES: S_AXI M_AXI S_AXI_ACLK S_AXI_ARESETN INTERRUPT}
puts $integrity_channel {M_AXI: AXI4 data=128 address=64 max_burst=8 outstanding=1}
puts $integrity_channel {S_AXI_MAP: base=0 range=4096 width=32 access=read-write}
puts $integrity_channel "SOURCE_FILES: [llength $source_files]"
puts $integrity_channel "HEADER_FILES: [llength $headers]"
puts $integrity_channel "CHECK_INTEGRITY_RESULT: $integrity_result"
puts $integrity_channel {EXTERNAL_REPOSITORY_REFERENCES: NONE}
puts $integrity_channel {SYNTHESIS: NOT_RUN}
puts $integrity_channel {IMPLEMENTATION: NOT_RUN}
close $integrity_channel
assert_true [file isfile $integrity_log] "integrity log was not written"

puts "PASS: IP integrity checked"
puts "PASS: self-contained component written to $component_xml"
puts "PASS: integrity log written to $integrity_log"
puts "INFO: source files [llength $source_files], headers [llength $headers]"
puts "INFO: no synthesis or implementation was run"
