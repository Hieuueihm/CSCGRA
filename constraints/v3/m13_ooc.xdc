create_clock -name core_clock -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks core_clock]
set_property HD.CLK_SRC BUFGCE_X0Y120 [get_ports clk]
