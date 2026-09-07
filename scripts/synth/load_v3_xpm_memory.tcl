set v3_xpm_memory_source [file join $::env(XILINX_VIVADO) \
    data ip xpm xpm_memory hdl xpm_memory.sv]
if {![file exists $v3_xpm_memory_source]} {
    error "XPM memory source not found: $v3_xpm_memory_source"
}
read_verilog -sv $v3_xpm_memory_source
