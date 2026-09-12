`ifndef CSR_MEMORY_DEFS_VH
`define CSR_MEMORY_DEFS_VH
`include "pe_interface.vh"
`define CSR_MEM_PLANES 3
`define CSR_MEM_BANKS 32
`define CSR_MEM_V_DEPTH 128
`define CSR_MEM_V_AW 7
`define CSR_MEM_V_LEN 4096
`define CSR_MEM_B_ROWS 128
`define CSR_MEM_B_COLS 96
`define CSR_MEM_B_DEPTH 384
`define CSR_MEM_B_AW 9
`define CSR_MEM_FAULT_NONE 0
`define CSR_MEM_FAULT_SHAPE 1
`define CSR_MEM_FAULT_STREAM 2
`define CSR_MEM_FAULT_KEY 3
`define CSR_MEM_FAULT_RANGE 4
`define CSR_MEM_FAULT_PLANE 5
`define CSR_MEM_FAULT_UNINIT 6
`define CSR_MEM_FAULT_SOURCE 7
`define CSR_MEM_FAULT_TAG 8
`endif
