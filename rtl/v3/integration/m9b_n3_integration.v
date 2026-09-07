`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module m9b_n3_integration (
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire [8:0] measurement_count,
    input  wire [5:0] selection_k,
    input  wire cycle_valid,
    input  wire cycle_commit,
    input  wire [35:0] resource_ctx,
    output wire m5_cycle_valid,
    output wire m5_cycle_commit,
    input  wire m5_resource_in_ready,
    input  wire m5_resource_out_ready,
    input  wire m5_resource_contract_error,
    input  wire transport_restart_ready,
    output wire transport_restart_valid,
    output wire [2:0] transport_restart_mask,
    input  wire candidate_valid,
    output wire candidate_ready,
    input  wire signed [`RECON_SOLVER_W-1:0] candidate_score,
    input  wire [9:0] candidate_index,
    input  wire candidate_saturated,
    input  wire capture_valid,
    output wire capture_ready,
    input  wire [9:0] capture_column,
    input  wire [2:0] capture_row_block,
    input  wire [31:0] capture_nonzero,
    input  wire [31:0] capture_sign,
    input  wire replay_valid,
    output wire replay_ready,
    input  wire [6:0] replay_slot,
    input  wire [2:0] replay_row_block,
    input  wire [7:0] replay_tag,
    output wire replay_response_valid,
    input  wire replay_response_ready,
    output wire [31:0] replay_nonzero,
    output wire [31:0] replay_sign,
    output wire [9:0] replay_column,
    output wire [6:0] replay_response_slot,
    output wire [2:0] replay_response_row_block,
    output wire [7:0] replay_response_tag,
    output wire cache_valid,
    output wire cache_busy,
    output wire cache_fault,
    output wire resource_in_ready,
    output wire resource_out_ready,
    output wire resource_contract_error,
    output wire selection_fault_valid,
    output wire support_remap_event_valid,
    output wire support_remap_event_fault,
    output wire [6:0] support_remap_dropped_count,
    output wire [96*10-1:0] support_remap_dropped_indices,
    output wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients,
    output wire [96*10-1:0] active_support_indices,
    output wire [96*`RECON_SOLVER_W-1:0] active_support_coefficients,
    output wire [6:0] active_support_count,
    output wire [5:0] selection_count,
    output wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores,
    output wire [`RECON_K_MAX*10-1:0] result_indices
);
    wire candidate_store_valid;
    wire candidate_store_ready;
    wire [5:0] candidate_store_slot;
    wire [9:0] candidate_store_column;
    wire cache_prepare_valid;
    wire cache_prepare_ready;
    wire cache_prepare_from_candidates;
    wire [6:0] cache_prepare_support_count;
    wire [6:0] cache_prepare_preserve_count;
    wire cache_promote_valid;
    wire cache_promote_ready;
    wire [5:0] cache_promote_candidate_slot;
    wire [6:0] cache_promote_support_slot;
    wire cache_invalidate;
    wire cache_refill_pending;
    wire [6:0] cache_refill_support_count;
    wire cache_refill_column_valid;
    wire [6:0] cache_refill_column_slot;
    wire [9:0] cache_refill_column;
    wire [9:0] rounded_measurement_count = {1'b0, measurement_count} + 10'd31;
    wire [2:0] row_block_count = rounded_measurement_count[7:5];

    m8_resource_dispatcher u_dispatcher (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .selection_k(selection_k), .active_work_count(7'd0),
        .active_measurement_count(measurement_count),
        .active_normal_residual_shift(5'd14),
        .active_residual_limit({`RECON_ACC_W{1'b0}}),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .resource_ctx(resource_ctx),
        .m5_cycle_valid(m5_cycle_valid), .m5_cycle_commit(m5_cycle_commit),
        .m5_resource_in_ready(m5_resource_in_ready),
        .m5_resource_out_ready(m5_resource_out_ready),
        .m5_resource_contract_error(m5_resource_contract_error),
        .m5_scalar0_valid(1'b0), .m5_scalar0_data(62'sd0),
        .m5_scalar1_valid(1'b0), .m5_scalar1_data(62'sd0),
        .m5_refinement_breakdown(1'b0), .m5_refinement_saturation(1'b0),
        .transport_restart_ready(transport_restart_ready),
        .transport_restart_valid(transport_restart_valid),
        .transport_restart_mask(transport_restart_mask),
        .candidate_valid(candidate_valid), .candidate_ready(candidate_ready),
        .candidate_score(candidate_score), .candidate_index(candidate_index),
        .candidate_saturated(candidate_saturated),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .phi_cache_prepare_valid(cache_prepare_valid),
        .phi_cache_prepare_ready(cache_prepare_ready),
        .phi_cache_prepare_from_candidates(cache_prepare_from_candidates),
        .phi_cache_prepare_support_count(cache_prepare_support_count),
        .phi_cache_prepare_preserve_count(cache_prepare_preserve_count),
        .phi_cache_promote_valid(cache_promote_valid),
        .phi_cache_promote_ready(cache_promote_ready),
        .phi_cache_promote_candidate_slot(cache_promote_candidate_slot),
        .phi_cache_promote_support_slot(cache_promote_support_slot),
        .phi_cache_valid(cache_valid), .phi_cache_fault(cache_fault),
        .phi_cache_invalidate(cache_invalidate),
        .phi_cache_refill_pending(cache_refill_pending),
        .phi_cache_refill_support_count(cache_refill_support_count),
        .phi_cache_refill_column_valid(cache_refill_column_valid),
        .phi_cache_refill_column_ready(1'b0),
        .phi_cache_refill_column_slot(cache_refill_column_slot),
        .phi_cache_refill_column(cache_refill_column),
        .resource_in_ready(resource_in_ready),
        .resource_out_ready(resource_out_ready),
        .resource_contract_error(resource_contract_error),
        .selection_fault_valid(selection_fault_valid),
        .support_remap_event_valid(support_remap_event_valid),
        .support_remap_event_fault(support_remap_event_fault),
        .support_remap_dropped_count(support_remap_dropped_count),
        .support_remap_dropped_indices(support_remap_dropped_indices),
        .support_remap_dropped_coefficients(support_remap_dropped_coefficients),
        .active_support_bitmap(),
        .active_support_indices(active_support_indices),
        .active_support_coefficients(active_support_coefficients),
        .support_coefficient_stripe_read_enable(1'b0),
        .support_coefficient_stripe_read_index(3'd0),
        .support_coefficient_stripe_read_valid(),
        .support_coefficient_stripe_read_coefficients(),
        .active_support_gradients(), .active_support_gradient_valid(),
        .active_support_count(active_support_count),
        .refinement_event_valid(), .refinement_certificate_pass(),
        .refinement_restart_required(), .refinement_stop_reason(),
        .termination_event_valid(),
        .termination_residual_limit_reached(), .termination_residual_sq(),
        .selection_count(selection_count), .result_scores(result_scores),
        .result_indices(result_indices)
    );

    support_phi_symbol_cache u_cache (
        .clk(clk), .rst_n(rst_n), .invalidate(cache_invalidate || routine_start),
        .measurement_count(measurement_count),
        .prepare_valid(cache_prepare_valid), .prepare_ready(cache_prepare_ready),
        .prepare_from_candidates(cache_prepare_from_candidates),
        .prepare_support_count(cache_prepare_support_count),
        .prepare_preserve_count(cache_prepare_preserve_count),
        .prepare_row_block_count(row_block_count),
        .fill_valid(1'b0), .fill_ready(), .fill_slot(7'd0),
        .fill_row_block(3'd0), .fill_column(10'd0),
        .fill_nonzero(32'd0), .fill_sign(32'd0),
        .capture_valid(capture_valid), .capture_ready(capture_ready),
        .capture_column(capture_column), .capture_row_block(capture_row_block),
        .capture_nonzero(capture_nonzero), .capture_sign(capture_sign),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .candidate_release_valid(1'b0),
        .candidate_release_column(10'd0),
        .promote_valid(cache_promote_valid), .promote_ready(cache_promote_ready),
        .promote_candidate_slot(cache_promote_candidate_slot),
        .promote_support_slot(cache_promote_support_slot),
        .replay_valid(replay_valid), .replay_ready(replay_ready),
        .replay_slot(replay_slot), .replay_row_block(replay_row_block),
        .replay_tag(replay_tag),
        .replay_response_valid(replay_response_valid),
        .replay_response_ready(replay_response_ready),
        .replay_nonzero(replay_nonzero), .replay_sign(replay_sign),
        .replay_column(replay_column),
        .replay_response_slot(replay_response_slot),
        .replay_response_row_block(replay_response_row_block),
        .replay_response_tag(replay_response_tag),
        .cache_valid(cache_valid), .cache_busy(cache_busy), .cache_fault(cache_fault)
    );
endmodule

`default_nettype wire
