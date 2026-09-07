# CSCGRA architecture revision 3 - AXI4-Lite reconstruction control interface.
create_clock -name aclk -period 6.667 [get_ports aclk]
set_clock_uncertainty 0.200 [get_clocks aclk]
set_property HD.CLK_SRC BUFGCE_X0Y120 [get_ports aclk]

# OOC interface budget. These delays keep register-to-port paths visible
# without assuming a specific Zynq processing-system interconnect instance.
set_input_delay  -clock aclk 0.500 [get_ports -filter {DIRECTION == IN && NAME != aclk}]
set_output_delay -clock aclk 0.500 [all_outputs]
