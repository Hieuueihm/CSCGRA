`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Verification/OOC shell around the production M5 subsystem.
module m5_arithmetic_ooc (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         routine_start,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire [35:0]                  resource_ctx,
    input  wire [15:0]                  reduction_lane_valid,
    input  wire [16*`RECON_ACC_W-1:0]   cluster0_lane_data,
    input  wire [16*`RECON_ACC_W-1:0]   cluster1_lane_data,
    input  wire [159:0]                 cluster0_lane_index,
    input  wire [159:0]                 cluster1_lane_index,
    input  wire [`RECON_SHARED_VECTOR_LANES-1:0] vector_lane_valid,
    input  wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0] vector_a,
    input  wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0] vector_b,
    input  wire                         vector_result_ready,
    output wire                         vector_result_valid,
    output wire [`RECON_SHARED_VECTOR_LANES-1:0] vector_result_lane_valid,
    output wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0]
                                                vector_result_data,
    output wire                         scalar0_valid,
    output wire signed [`RECON_ACC_W-1:0] scalar0_data,
    output wire                         scalar1_valid,
    output wire signed [`RECON_ACC_W-1:0] scalar1_data,
    output wire                         scalar_broadcast_valid,
    output wire signed [`RECON_SOLVER_W-1:0] scalar_broadcast_data,
    output wire                         reduction_result_valid,
    output wire signed [`RECON_ACC_W-1:0] reduction_result_data,
    output wire [9:0]                   reduction_result_index,
    output wire                         reduction_result_fault,
    output wire                         event_valid,
    output wire [3:0]                   event_id,
    output wire [9:0]                   result_index,
    output wire                         divide_by_zero_event,
    output wire                         saturation_event,
    output wire                         fault_valid,
    output wire [7:0]                   fault_code,
    output wire [15:0]                  fault_detail,
    output wire                         resource_in_ready,
    output wire                         resource_out_ready,
    output wire                         resource_contract_error
);
    wire reduction_result_ready = 1'b1;
    wire scalar_preload_ready;
    wire fused_scalar_ready;
    m5_arithmetic_subsystem u_subsystem (
        .scalar_state_clear(routine_start),
        .scalar_preload_valid(1'b0),
        .scalar_preload_ready(scalar_preload_ready),
        .scalar_preload_address(1'b0),
        .scalar_preload_data({`RECON_ACC_W{1'b0}}),
        .fused_scalar_valid(1'b0),
        .fused_scalar_ready(fused_scalar_ready),
        .fused_scalar_address(1'b0),
        .fused_scalar_data({`RECON_ACC_W{1'b0}}),
        .fused_scalar_is_gamma(1'b0),
        .reduction_lane_valid_pair({2{reduction_lane_valid}}), .*
    );
endmodule

`default_nettype wire
