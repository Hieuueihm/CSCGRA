`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module phi_lane_normalization_flow #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer LOCAL_ACC_W = `RECON_LOCAL_ACC_W,
    parameter integer ROW_W = `RECON_PHI_ROW_BLOCK_W,
    parameter integer TAG_W = `RECON_PHI_TAG_W,
    parameter integer MANTISSA_W = `RECON_PHI_SCALE_MANTISSA_W,
    parameter integer EXPONENT_W = `RECON_PHI_SCALE_EXPONENT_W
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire cycle_valid,
    input wire cycle_commit,
    input wire [4:0] tile_operation,
    input wire phi_start_fire,
    input wire [2:0] phi_start_mode,
    input wire [2:0] phi_mode,
    input wire [ROW_W-1:0] phi_row_block,
    input wire [ROW_W-1:0] completed_row_block,
    input wire [8:0] measurement_count,
    input wire [6:0] work_count,
    input wire [32*LOCAL_ACC_W-1:0] lane_accumulator,
    input wire [32*DATA_W-1:0] measurement_vector,
    input wire column_request_valid,
    input wire signed [ACC_W-1:0] column_request_data,
    input wire [TAG_W-1:0] column_request_tag,
    input wire [MANTISSA_W-1:0] column_request_mantissa,
    input wire [EXPONENT_W-1:0] column_request_exponent,
    input wire column_request_is_data18,
    input wire normalizer_memory_mode,
    input wire memory_output_ready,
    input wire vector_candidate_mode,
    input wire candidate_output_ready,
    input wire [10:0] memory_output_count,
    input wire fused_scalar_ready,
    output wire normalizer_input_ready,
    output wire normalizer_output_valid,
    output wire normalizer_output_ready,
    output wire signed [DATA_W-1:0] normalizer_output_data,
    output wire [TAG_W-1:0] normalizer_output_tag,
    output wire normalizer_output_saturated,
    output wire normalized_candidate_fire,
    output wire capture_event,
    output wire lane_input_valid,
    output wire lane_output_fire,
    output reg lane_active,
    output reg residual_mode,
    output reg [5:0] issue_count,
    output reg [5:0] output_count,
    output reg [ROW_W-1:0] row_block,
    output reg [32*LOCAL_ACC_W-1:0] accumulator_buffer,
    output reg [32*DATA_W-1:0] measurement_buffer,
    output wire signed [LOCAL_ACC_W-1:0] selected_accumulator,
    output reg fused_scalar_valid,
    output reg fused_scalar_is_gamma,
    output reg signed [ACC_W-1:0] fused_scalar_data
);
    reg norm_active;
    reg norm_is_gamma;
    reg product_valid;
    reg product_last;
    reg product_is_gamma;
    reg signed [2*DATA_W-1:0] product;
    reg [ACC_W-1:0] norm_accumulator;
    reg [ROW_W-1:0] forward_row_block;

    wire signed [ACC_W-1:0] lane_input_data =
        {{(ACC_W-LOCAL_ACC_W){selected_accumulator[LOCAL_ACC_W-1]}},
         selected_accumulator};
    wire selected_input_valid = lane_active ? lane_input_valid :
        column_request_valid;
    wire signed [ACC_W-1:0] selected_input_data = lane_active ?
        lane_input_data : column_request_data;
    wire [TAG_W-1:0] selected_input_tag = lane_active ?
        {{(TAG_W-5){1'b0}}, issue_count[4:0]} : column_request_tag;
    wire selected_input_is_data18 = !lane_active &&
        column_request_is_data18;
    wire lane_input_fire = lane_input_valid && normalizer_input_ready;
    wire [8:0] lane_output_row =
        {1'b0, forward_row_block, 5'd0} +
        {{(9-TAG_W){1'b0}}, normalizer_output_tag};
    wire lane_norm_fire = norm_active && !norm_is_gamma &&
        lane_output_fire && (lane_output_row < measurement_count);
    wire transpose_norm_fire = norm_active && norm_is_gamma &&
        normalizer_output_valid && memory_output_ready;
    wire norm_sample_fire = lane_norm_fire || transpose_norm_fire;
    wire norm_sample_last = lane_norm_fire ?
        (lane_output_row + 9'd1 == measurement_count) :
        (memory_output_count + 11'd1 == {4'd0, work_count});
    wire [ACC_W-1:0] extended_product =
        {{(ACC_W-(2*DATA_W)){1'b0}}, product};

    assign capture_event = cycle_valid && cycle_commit &&
        ((tile_operation == `RECON_TILE_OP_PHI_ACCUMULATOR_CAPTURE) ||
         (tile_operation == `RECON_TILE_OP_PHI_RESIDUAL_CAPTURE));
    assign lane_input_valid = lane_active && (issue_count < 6'd32);
    assign selected_accumulator = accumulator_buffer[
        issue_count[4:0]*LOCAL_ACC_W +: LOCAL_ACC_W];
    assign normalizer_output_ready = lane_active ? 1'b1 :
        normalizer_memory_mode ? memory_output_ready :
        (!vector_candidate_mode && candidate_output_ready);
    assign normalized_candidate_fire = normalizer_output_valid &&
        normalizer_output_ready && !lane_active && !normalizer_memory_mode;
    assign lane_output_fire = lane_active && normalizer_output_valid &&
        normalizer_output_ready;

    phi_operator_normalizer u_normalizer (
        .clk(clk), .rst_n(rst_n), .input_valid(selected_input_valid),
        .input_ready(normalizer_input_ready), .input_data(selected_input_data),
        .input_placement(1'b0), .input_tag(selected_input_tag),
        .scale_mantissa_uq17(column_request_mantissa),
        .scale_exponent(column_request_exponent),
        .input_is_data18(selected_input_is_data18),
        .output_valid(normalizer_output_valid),
        .output_ready(normalizer_output_ready),
        .output_data(normalizer_output_data), .output_placement(),
        .output_tag(normalizer_output_tag),
        .output_saturated(normalizer_output_saturated)
    );

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            lane_active <= 1'b0;
            residual_mode <= 1'b0;
            issue_count <= 6'd0;
            output_count <= 6'd0;
            row_block <= {ROW_W{1'b0}};
            accumulator_buffer <= {32*LOCAL_ACC_W{1'b0}};
            measurement_buffer <= {32*DATA_W{1'b0}};
            norm_active <= 1'b0;
            norm_is_gamma <= 1'b0;
            product_valid <= 1'b0;
            product_last <= 1'b0;
            product_is_gamma <= 1'b0;
            product <= {(2*DATA_W){1'b0}};
            norm_accumulator <= {ACC_W{1'b0}};
            forward_row_block <= {ROW_W{1'b0}};
            fused_scalar_valid <= 1'b0;
            fused_scalar_is_gamma <= 1'b0;
            fused_scalar_data <= {ACC_W{1'b0}};
        end else begin
            if (fused_scalar_valid && fused_scalar_ready)
                fused_scalar_valid <= 1'b0;
            if (phi_start_fire &&
                ((phi_start_mode == 3'd3) || (phi_start_mode == 3'd5))) begin
                norm_active <= 1'b1;
                norm_is_gamma <= phi_start_mode == 3'd3;
                norm_accumulator <= {ACC_W{1'b0}};
                forward_row_block <= {ROW_W{1'b0}};
            end
            if (lane_norm_fire && (normalizer_output_tag[4:0] == 5'd31))
                forward_row_block <= forward_row_block + 1'b1;
            product_valid <= norm_sample_fire;
            if (norm_sample_fire) begin
                product <= $signed(normalizer_output_data) *
                           $signed(normalizer_output_data);
                product_last <= norm_sample_last;
                product_is_gamma <= norm_is_gamma;
            end
            if (product_valid) begin
                if (product_last) begin
                    norm_active <= 1'b0;
                    fused_scalar_valid <= 1'b1;
                    fused_scalar_is_gamma <= product_is_gamma;
                    fused_scalar_data <= norm_accumulator + extended_product;
                end else begin
                    norm_accumulator <= norm_accumulator + extended_product;
                end
            end
            if (capture_event) begin
                lane_active <= 1'b1;
                residual_mode <= tile_operation ==
                    `RECON_TILE_OP_PHI_RESIDUAL_CAPTURE;
                issue_count <= 6'd0;
                output_count <= 6'd0;
                row_block <= (phi_mode == 3'd5) ? completed_row_block :
                    phi_row_block;
                accumulator_buffer <= lane_accumulator;
                measurement_buffer <= measurement_vector;
            end else begin
                if (lane_input_fire)
                    issue_count <= issue_count + 1'b1;
                if (lane_output_fire) begin
                    if (output_count == 6'd31) begin
                        lane_active <= 1'b0;
                        output_count <= 6'd0;
                    end else begin
                        output_count <= output_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
