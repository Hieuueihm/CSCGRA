`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module cgra_execution_fabric #(
    parameter [`RECON_PE_COUNT-1:0] FULL_PE_MASK = {`RECON_PE_COUNT{1'b1}}
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_PREDICATE_COUNT*`RECON_CLUSTER_COUNT-1:0]
                                        predicate_values,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,

    output wire                         vec_req_valid,
    output wire                         vec_cycle_commit,
    output wire                         vec_a_en,
    output wire                         vec_b_en,
    output wire                         vec_w_en,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W-1:0] vec_cfg_a,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W-1:0] vec_cfg_b,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_W-1:0] vec_cfg_w,
    input  wire                         vec_in_ready,
    input  wire                         vec_out_ready,
    input  wire                         vec_cfg_error,
    input  wire                         vec_access_conflict,

    input  wire                         vector_a_valid,
    input  wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] vector_a_data,
    input  wire                         vector_b_valid,
    input  wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] vector_b_data,
    input  wire                         scalar_a_valid,
    input  wire [`RECON_SOLVER_W-1:0]   scalar_a_data,
    input  wire                         scalar_b_valid,
    input  wire [`RECON_SOLVER_W-1:0]   scalar_b_data,
    output wire [`RECON_STREAM_FIELD_EXTERNAL_A_SELECT_W-1:0] ext_a_sel,
    output wire [`RECON_STREAM_FIELD_EXTERNAL_B_SELECT_W-1:0] ext_b_sel,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] external_input_a,

    output wire                         phi_command_valid,
    input  wire                         phi_command_ready,
    output wire [`RECON_STREAM_FIELD_PHI_COMMAND_W-1:0] phi_command,
    output wire [`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_W-1:0] phi_cfg_id,
    input  wire                         phi_cfg_valid,
    input  wire                         phi_symbol_valid,
    output wire                         phi_symbol_ready,
    input  wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] phi_nonzero,
    input  wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] phi_sign,

    output wire                         stream_in_ready,
    output wire                         stream_out_ready,
    output wire                         stream_contract_error,

    input  wire                         result_clear_event,
    input  wire                         result_capture_start_event,
    input  wire                         result_capture_valid,
    input  wire [4:0]                   result_capture_index,
    input  wire [`RECON_SOLVER_W-1:0]   result_capture_data,
    input  wire                         result_capture_low_complete,
    input  wire                         result_capture_high_complete,
    input  wire                         result_consume_d18_event,
    input  wire                         result_consume_s27_event,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] result_data,
    output wire                         result_low_valid,
    output wire                         result_high_valid,
    output wire                         result_s27_high_select,
    output wire                         result_busy,

    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] lane_result,
    output wire [`RECON_PE_COUNT*`RECON_LOCAL_ACC_W-1:0] lane_accumulator,
    output wire [`RECON_PE_COUNT*`RECON_ACC_W-1:0] reduction_lane_data,
    output wire [`RECON_PE_COUNT-1:0]   lane_result_valid,
    output wire [`RECON_CLUSTER_COUNT-1:0] saturation_event,
    output wire [`RECON_CLUSTER_COUNT-1:0] contract_error
);
    wire [`RECON_CLUSTER_COUNT-1:0] cluster_enable_mask =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_W];
    wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] external_input_b;
    wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] routed_phi_nonzero;
    wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] routed_phi_sign;

    stream_context_router u_router (
        .clk(clk),
        .rst_n(rst_n),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .stream_ctx(stream_ctx),
        .vec_req_valid(vec_req_valid),
        .vec_cycle_commit(vec_cycle_commit),
        .vec_a_en(vec_a_en),
        .vec_b_en(vec_b_en),
        .vec_w_en(vec_w_en),
        .vec_cfg_a(vec_cfg_a),
        .vec_cfg_b(vec_cfg_b),
        .vec_cfg_w(vec_cfg_w),
        .vec_in_ready(vec_in_ready),
        .vec_out_ready(vec_out_ready),
        .vec_cfg_error(vec_cfg_error),
        .vec_access_conflict(vec_access_conflict),
        .vector_a_valid(vector_a_valid),
        .vector_a_data(vector_a_data),
        .vector_b_valid(vector_b_valid),
        .vector_b_data(vector_b_data),
        .scalar_a_valid(scalar_a_valid),
        .scalar_a_data(scalar_a_data),
        .scalar_b_valid(scalar_b_valid),
        .scalar_b_data(scalar_b_data),
        .ext_a_sel(ext_a_sel),
        .ext_b_sel(ext_b_sel),
        .out_vec_a(),
        .out_vec_b(),
        .out_scalar(),
        .external_input_a(external_input_a),
        .external_input_b(external_input_b),
        .phi_command_valid(phi_command_valid),
        .phi_command_ready(phi_command_ready),
        .phi_command(phi_command),
        .phi_cfg_id(phi_cfg_id),
        .phi_cfg_valid(phi_cfg_valid),
        .phi_symbol_valid(phi_symbol_valid),
        .phi_symbol_ready(phi_symbol_ready),
        .phi_nonzero(phi_nonzero),
        .phi_sign(phi_sign),
        .out_phi_nonzero(routed_phi_nonzero),
        .out_phi_sign(routed_phi_sign),
        .stream_in_ready(stream_in_ready),
        .stream_out_ready(stream_out_ready),
        .stream_contract_error(stream_contract_error)
    );

    cgra_cluster_pair #(
        .FULL_PE_MASK(FULL_PE_MASK)
    ) u_clusters (
        .clk(clk),
        .rst_n(rst_n),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .cluster_enable_mask(cluster_enable_mask),
        .tile_ctx(tile_ctx),
        .predicate_values(predicate_values),
        .external_input_a(external_input_a),
        .external_input_b(external_input_b),
        .phi_nonzero(routed_phi_nonzero),
        .phi_sign(routed_phi_sign),
        .north_boundary_input({8*`RECON_SOLVER_W{1'b0}}),
        .south_boundary_input({8*`RECON_SOLVER_W{1'b0}}),
        .west_boundary_input({8*`RECON_SOLVER_W{1'b0}}),
        .east_boundary_input({8*`RECON_SOLVER_W{1'b0}}),
        .north_boundary_output(),
        .south_boundary_output(),
        .west_boundary_output(),
        .east_boundary_output(),
        .lane_result(lane_result),
        .lane_accumulator(lane_accumulator),
        .reduction_lane_data(reduction_lane_data),
        .lane_result_valid(lane_result_valid),
        .saturation_event(saturation_event),
        .contract_error(contract_error)
    );

    cgra_result_buffer u_result_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .clear_event(result_clear_event),
        .capture_start_event(result_capture_start_event),
        .capture_valid(result_capture_valid),
        .capture_index(result_capture_index),
        .capture_data(result_capture_data),
        .capture_low_complete(result_capture_low_complete),
        .capture_high_complete(result_capture_high_complete),
        .consume_d18_event(result_consume_d18_event),
        .consume_s27_event(result_consume_s27_event),
        .result_data(result_data),
        .low_valid(result_low_valid),
        .high_valid(result_high_valid),
        .s27_high_select(result_s27_high_select),
        .busy(result_busy)
    );
endmodule

`default_nettype wire
