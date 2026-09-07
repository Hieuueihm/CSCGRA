`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module candidate_stream_adapter #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer LANES = `RECON_SHARED_VECTOR_LANES,
    parameter integer WORK_MAX = 96
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire cycle_valid,
    input wire [4:0] resource_operation,
    input wire resource_wait_for_result,
    input wire [2:0] resource_input_select,
    input wire [5:0] resource_configuration_id,
    input wire vec_a_en,
    input wire stream_metadata_valid,
    input wire [2:0] stream_element_format,
    input wire [2:0] stream_packing_mode,
    input wire [10:0] signal_length,
    input wire [6:0] work_count,
    input wire stripe_valid,
    input wire [LANES-1:0] stripe_lane_valid,
    input wire [LANES*DATA_W-1:0] stripe_data,
    input wire [WORK_MAX*INDEX_W-1:0] support_indices,
    input wire candidate_ready,
    output wire mode_active,
    output wire support_scatter_mode,
    output wire topk_support_slot_mode,
    output wire candidate_valid,
    output wire signed [DATA_W-1:0] candidate_score,
    output wire [INDEX_W-1:0] candidate_index,
    output wire candidate_fault,
    output wire candidate_final_lane
);
    wire solver_stream = vec_a_en && stream_metadata_valid &&
        (stream_element_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (stream_packing_mode == `RECON_PACKING_MODE_TWO);
    wire topk_candidate_mode = cycle_valid &&
        (resource_operation == `RECON_RESOURCE_OP_TOPK_PUSH) &&
        !resource_wait_for_result &&
        (resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
        solver_stream;
    assign topk_support_slot_mode = topk_candidate_mode &&
        (resource_configuration_id == 6'd1);
    assign support_scatter_mode = cycle_valid &&
        (resource_operation == `RECON_RESOURCE_OP_SUPPORT_SCATTER) &&
        !resource_wait_for_result &&
        (resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
        solver_stream;
    assign mode_active = topk_candidate_mode || support_scatter_mode;

    wire source_active = mode_active;
    wire source_valid;
    wire source_ready = mode_active && candidate_ready;
    wire signed [DATA_W-1:0] source_score;
    wire [INDEX_W-1:0] source_index;
    wire source_fault;
    wire source_release;
    wire [INDEX_W:0] element_count =
        (support_scatter_mode || topk_support_slot_mode) ?
        {{(INDEX_W-6){1'b0}}, work_count} : signal_length;

    vector_candidate_serializer #(
        .DATA_W(DATA_W), .LANES(LANES), .INDEX_W(INDEX_W)
    ) u_serializer (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .source_active(source_active), .element_count(element_count),
        .stripe_valid(stripe_valid), .stripe_lane_valid(stripe_lane_valid),
        .stripe_data(stripe_data), .stripe_release(source_release),
        .candidate_valid(source_valid), .candidate_ready(source_ready),
        .candidate_score(source_score), .candidate_index(source_index),
        .candidate_fault(source_fault), .stream_done()
    );

    assign candidate_valid = mode_active && source_valid;
    assign candidate_score = source_score;
    assign candidate_index = topk_support_slot_mode ?
        support_indices[source_index*INDEX_W +: INDEX_W] : source_index;
    assign candidate_fault = source_fault;
    assign candidate_final_lane = source_release;
endmodule

`default_nettype wire
