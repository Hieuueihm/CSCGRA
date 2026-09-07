`ifndef RECONSTRUCTION_CONTROL_DEFS_VH
`define RECONSTRUCTION_CONTROL_DEFS_VH

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"

// Architecture revision 3. The AXI4-Lite map is intentionally small: run
// parameters live in one 64-byte run-configuration block, not duplicated CSR state.
`define RECON_IP_ID                    32'h4353_4733
`define AXI_RESP_OKAY                   2'b00
`define AXI_RESP_SLVERR                 2'b10
`define AXI_RESP_DECERR                 2'b11

`define RECON_STOP_NONE                 4'h0
`define RECON_STOP_RESIDUAL_LIMIT       4'h1
`define RECON_STOP_ITERATION_LIMIT      4'h2
`define RECON_STOP_SUPPORT_STABLE       4'h3
`define RECON_STOP_NON_DECREASE         4'h4
`define RECON_STOP_ABORTED              4'he
`define RECON_STOP_ERROR                4'hf

`define RECON_ERROR_CLASS_NONE          4'h0
`define RECON_ERROR_CLASS_RUN_CONFIGURATION 4'h1
`define RECON_ERROR_CLASS_DMA_READ      4'h2
`define RECON_ERROR_CLASS_DMA_WRITE     4'h3
`define RECON_ERROR_CLASS_NUMERIC       4'h4
`define RECON_ERROR_CLASS_SOLVER        4'h5
`define RECON_ERROR_CLASS_CONTEXT       4'h6

// Compact CSR map. All unspecified aligned addresses return DECERR.
`define RECON_CSR_IDENTIFICATION         12'h000
`define RECON_CSR_VERSION                12'h004
`define RECON_CSR_CAPABILITY             12'h008
`define RECON_CSR_BUILD_LIMITS           12'h00c
`define RECON_CSR_COMMAND                12'h010
`define RECON_CSR_EVENT_CONTROL          12'h014
`define RECON_CSR_STATUS                 12'h018
`define RECON_CSR_ERROR_INFO             12'h01c
`define RECON_CSR_ERROR_DETAIL           12'h020
`define RECON_CSR_RUN_CONFIGURATION_LO   12'h024
`define RECON_CSR_RUN_CONFIGURATION_HI   12'h028
`define RECON_CSR_PROGRESS               12'h02c
`define RECON_CSR_TOTAL_CYCLES_LO        12'h030
`define RECON_CSR_TOTAL_CYCLES_HI        12'h034

`endif
