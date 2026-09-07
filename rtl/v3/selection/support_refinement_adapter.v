`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module support_refinement_adapter #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer LANES = 16,
    parameter integer WORK_MAX = 96,
    parameter integer SELECT_MAX = `RECON_K_MAX
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire scalar_state_clear,
    input wire abort_flush,
    input wire cycle_valid,
    input wire cycle_commit,
    input wire [4:0] resource_operation,
    input wire [5:0] resource_configuration_id,
    input wire [2:0] resource_input_select,
    input wire [2:0] resource_output_select,
    input wire resource_wait_for_result,
    input wire [1:0] resource_stream_boundary,
    input wire [5:0] vec_cfg_a_raw,
    input wire [10:0] signal_length,
    input wire [6:0] support_count,
    input wire [5:0] selected_count,
    input wire [SELECT_MAX*INDEX_W-1:0] selected_indices,
    input wire [WORK_MAX*INDEX_W-1:0] support_indices,
    input wire [WORK_MAX*DATA_W-1:0] support_coefficients,
    input wire [WORK_MAX*DATA_W-1:0] support_gradients,
    input wire [WORK_MAX-1:0] support_gradient_valid,
    input wire [LANES*DATA_W-1:0] dense_input,
    input wire vector_result_valid,
    input wire vector_result_ready,
    input wire stripe_response_valid,
    input wire [LANES*DATA_W-1:0] stripe_response_data,
    input wire cursor_restart_valid,
    input wire [2:0] cursor_restart_mask,
    output wire [10:0] masked_copy_base,
    output wire [5:0] vec_cfg_a,
    output wire fresh_refinement_active,
    output wire fresh_refinement_zero_estimate,
    output wire fresh_refinement_initial_residual,
    output wire masked_copy_mode,
    output wire [2:0] support_rebuild_mode,
    output wire support_coefficient_stripe_needed,
    output wire support_coefficient_stripe_read_enable,
    output wire [2:0] support_coefficient_stripe_read_index,
    output wire support_coefficient_stripe_buffer_valid,
    output wire [LANES*DATA_W-1:0] support_coefficient_stripe_buffer,
    output wire [LANES*DATA_W-1:0] masked_vector_result_data,
    output wire [LANES*DATA_W-1:0] selected_vector_result_data
);
    reg fresh_refinement_active_reg;
    reg [10:0] masked_copy_base_reg;
    reg stripe_read_pending_reg;
    reg stripe_buffer_valid_reg;
    reg [LANES*DATA_W-1:0] stripe_buffer_reg;

    wire fresh_refinement_marker = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_NOP) &&
        (resource_configuration_id == 6'd6) &&
        (resource_stream_boundary == `RECON_STREAM_BOUNDARY_FIRST);
    wire fresh_refinement_direction_start = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY) &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        !resource_wait_for_result &&
        (((resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
          (vec_cfg_a_raw == 6'd18)) ||
         ((resource_input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM) &&
          (resource_configuration_id == 6'd3)));
    wire fresh_refinement_cancel = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_SUPPORT_UNION);

    assign fresh_refinement_active = fresh_refinement_active_reg;
    assign masked_copy_base = masked_copy_base_reg;
    assign masked_copy_mode =
        (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY) &&
        (resource_input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM);
    assign support_rebuild_mode = !masked_copy_mode ? 3'd0 :
        (resource_configuration_id == 6'd1) ? 3'd1 :
        (resource_configuration_id == 6'd2) ? 3'd2 :
        (resource_configuration_id == 6'd3) ? 3'd3 :
        (resource_configuration_id == 6'd4) ? 3'd4 : 3'd0;
    assign fresh_refinement_zero_estimate = fresh_refinement_active &&
        masked_copy_mode && (resource_configuration_id == 6'd1);
    wire support_coefficient_stripe_mode = masked_copy_mode &&
        (resource_configuration_id == 6'd1) &&
        !fresh_refinement_zero_estimate;
    assign support_coefficient_stripe_needed =
        support_coefficient_stripe_mode &&
        (masked_copy_base < {4'd0, support_count});
    assign support_coefficient_stripe_read_enable = cycle_valid &&
        support_coefficient_stripe_needed && !stripe_read_pending_reg &&
        !stripe_buffer_valid_reg;
    assign support_coefficient_stripe_read_index = masked_copy_base[6:4];
    assign support_coefficient_stripe_buffer_valid = stripe_buffer_valid_reg;
    assign support_coefficient_stripe_buffer = stripe_buffer_reg;
    assign fresh_refinement_initial_residual = fresh_refinement_active &&
        (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY) &&
        (resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        (vec_cfg_a_raw == 6'd1);
    assign vec_cfg_a = fresh_refinement_initial_residual ? 6'd0 : vec_cfg_a_raw;

    support_vector_rebuilder #(
        .DATA_W(DATA_W), .INDEX_W(INDEX_W), .LANES(LANES),
        .WORK_MAX(WORK_MAX), .SELECT_MAX(SELECT_MAX)
    ) u_rebuilder (
        .rebuild_mode(support_rebuild_mode),
        .stripe_base(masked_copy_base),
        .signal_length(signal_length),
        .support_count(support_count),
        .selected_count(selected_count),
        .selected_indices(selected_indices),
        .support_indices(support_indices),
        .support_coefficients(support_coefficients),
        .support_coefficient_stripe_valid(stripe_buffer_valid_reg),
        .support_coefficient_stripe(stripe_buffer_reg),
        .support_gradients(support_gradients),
        .support_gradient_valid(support_gradient_valid),
        .dense_input(dense_input),
        .rebuilt_output(masked_vector_result_data)
    );

    assign selected_vector_result_data = fresh_refinement_zero_estimate ?
        {LANES*DATA_W{1'b0}} :
        masked_copy_mode ? masked_vector_result_data : dense_input;

    wire stripe_consume = vector_result_valid && vector_result_ready &&
        support_coefficient_stripe_needed;

    always @(posedge clk) begin
        if (!rst_n || scalar_state_clear || abort_flush ||
            !support_coefficient_stripe_mode ||
            (cursor_restart_valid && cursor_restart_mask[0])) begin
            stripe_read_pending_reg <= 1'b0;
            stripe_buffer_valid_reg <= 1'b0;
            stripe_buffer_reg <= {LANES*DATA_W{1'b0}};
        end else begin
            if (stripe_response_valid) begin
                stripe_read_pending_reg <= 1'b0;
                stripe_buffer_valid_reg <= 1'b1;
                stripe_buffer_reg <= stripe_response_data;
            end
            if (stripe_consume)
                stripe_buffer_valid_reg <= 1'b0;
            if (support_coefficient_stripe_read_enable)
                stripe_read_pending_reg <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || scalar_state_clear || abort_flush)
            fresh_refinement_active_reg <= 1'b0;
        else if (fresh_refinement_marker)
            fresh_refinement_active_reg <= 1'b1;
        else if (fresh_refinement_direction_start || fresh_refinement_cancel)
            fresh_refinement_active_reg <= 1'b0;
    end

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush)
            masked_copy_base_reg <= 11'd0;
        else begin
            if (cursor_restart_valid && cursor_restart_mask[0])
                masked_copy_base_reg <= 11'd0;
            if (masked_copy_mode && vector_result_valid && vector_result_ready)
                masked_copy_base_reg <= masked_copy_base_reg + 11'd16;
        end
    end
endmodule

`default_nettype wire
