`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module m9b_support_subsystem #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer CANDIDATE_MAX = 64,
    parameter integer WORK_MAX = 96,
    parameter integer TAG_W = 3
)(
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire abort_transaction,
    input  wire certificate_fail,
    input  wire [6:0] candidate_limit,
    input  wire candidate_valid,
    output wire candidate_ready,
    input  wire signed [DATA_W-1:0] candidate_value,
    input  wire [INDEX_W-1:0] candidate_index,
    output wire candidate_store_valid,
    input  wire candidate_store_ready,
    output wire [5:0] candidate_store_slot,
    output wire [INDEX_W-1:0] candidate_store_column,
    input  wire gradient_valid,
    input  wire [6:0] gradient_slot,
    input  wire signed [DATA_W-1:0] gradient_value,
    input  wire cycle_valid,
    output wire cycle_ready,
    input  wire cycle_commit,
    input  wire [4:0] operation,
    input  wire [TAG_W-1:0] request_tag,
    input  wire [6:0] request_slot,
    input  wire signed [DATA_W-1:0] scatter_coefficient,
    output wire response_valid,
    input  wire response_ready,
    output wire [4:0] response_operation,
    output wire [TAG_W-1:0] response_tag,
    output wire response_fault,
    output wire [6:0] response_count,
    output wire response_member,
    output wire [6:0] response_slot,
    output wire [INDEX_W-1:0] response_atom,
    output wire signed [DATA_W-1:0] response_coefficient,
    output wire remap_done_valid,
    output wire remap_fault,
    output wire [6:0] dropped_count,
    output wire [WORK_MAX*INDEX_W-1:0] dropped_indices,
    output wire [WORK_MAX*DATA_W-1:0] dropped_coefficients,
    output wire transaction_open,
    output wire current_bank,
    output wire [6:0] current_count,
    output wire [6:0] proposed_count,
    output wire [31:0] rollback_count,
    output wire [31:0] rollback_cycle_count
);
    wire [6:0] candidate_count;
    wire [CANDIDATE_MAX*DATA_W-1:0] candidate_values;
    wire [CANDIDATE_MAX*INDEX_W-1:0] candidate_indices;
    wire [CANDIDATE_MAX*6-1:0] candidate_symbol_slots;
    wire [WORK_MAX*DATA_W-1:0] support_gradients;
    wire [WORK_MAX-1:0] support_gradient_valid;

    proxy_candidate_collector #(.DATA_W(DATA_W), .INDEX_W(INDEX_W),
        .CANDIDATE_MAX(CANDIDATE_MAX), .SUPPORT_MAX(WORK_MAX)) u_collector (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .selection_epoch_start(1'b0),
        .candidate_limit(candidate_limit), .candidate_store_enable(1'b1),
        .candidate_valid(candidate_valid),
        .candidate_ready(candidate_ready), .candidate_value(candidate_value),
        .candidate_index(candidate_index), .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .gradient_valid(gradient_valid), .gradient_slot(gradient_slot),
        .gradient_value(gradient_value), .candidate_count(candidate_count),
        .candidate_values(candidate_values), .candidate_indices(candidate_indices),
        .candidate_symbol_slots(candidate_symbol_slots),
        .support_gradients(support_gradients),
        .support_gradient_valid(support_gradient_valid)
    );

    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank0_entries;
    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank1_entries;
    wire [WORK_MAX-1:0] bank0_slot_valid;
    wire [WORK_MAX-1:0] bank1_slot_valid;
    wire manager_remap_event_valid;
    wire manager_remap_event_fault;

    support_state_manager #(.DATA_W(DATA_W), .INDEX_W(INDEX_W),
        .CANDIDATE_MAX(CANDIDATE_MAX), .WORK_MAX(WORK_MAX), .TAG_W(TAG_W)) u_manager (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .abort_transaction(abort_transaction), .certificate_fail(certificate_fail),
        .cycle_valid(cycle_valid), .cycle_ready(cycle_ready),
        .cycle_commit(cycle_commit), .operation(operation), .request_tag(request_tag),
        .request_slot(request_slot), .request_cache_from_candidates(1'b1),
        .request_candidate_coefficients(1'b0),
        .request_zero_candidate_coefficient(1'b0),
        .request_defer_activation(1'b0),
        .request_sort_by_index(1'b0),
        .request_scatter_active(1'b0),
        .scatter_coefficient(scatter_coefficient),
        .candidate_count(candidate_count), .candidate_values(candidate_values),
        .candidate_indices(candidate_indices), .candidate_symbol_slots(candidate_symbol_slots),
        .membership_query_atom({INDEX_W{1'b0}}), .membership_query_member(),
        .membership_query_slot(),
        .append_gradient_valid(), .append_gradient_slot(),
        .append_gradient_value(),
        .response_valid(response_valid),
        .response_ready(response_ready), .response_operation(response_operation),
        .response_tag(response_tag), .response_fault(response_fault),
        .response_count(response_count), .response_member(response_member),
        .response_slot(response_slot), .response_atom(response_atom),
        .response_coefficient(response_coefficient),
        .transaction_open(transaction_open), .current_bank(current_bank),
        .current_count(current_count), .proposed_count(proposed_count),
        .view_count(), .proposal_view_active(),
        .rollback_count(rollback_count), .rollback_cycle_count(rollback_cycle_count),
        .bank0_entries(bank0_entries), .bank1_entries(bank1_entries),
        .bank0_slot_valid(bank0_slot_valid), .bank1_slot_valid(bank1_slot_valid),
        .active_support_bitmap(),
        .active_support_indices(),
        .active_support_coefficients(),
        .coefficient_stripe_read_enable(1'b0),
        .coefficient_stripe_read_index(3'd0),
        .coefficient_stripe_read_valid(),
        .coefficient_stripe_read_coefficients(),
        .remap_event_valid(manager_remap_event_valid),
        .remap_event_fault(manager_remap_event_fault),
        .remap_dropped_count(dropped_count),
        .remap_dropped_indices(dropped_indices),
        .remap_dropped_coefficients(dropped_coefficients),
        .cache_prepare_valid(), .cache_prepare_ready(1'b1),
        .cache_prepare_from_candidates(),
        .cache_prepare_support_count(), .cache_prepare_preserve_count(),
        .cache_promote_valid(), .cache_promote_ready(1'b1),
        .cache_promote_candidate_slot(), .cache_promote_support_slot(),
        .cache_valid(1'b1), .cache_fault(1'b0), .cache_invalidate(),
        .cache_refill_pending(), .cache_refill_support_count(),
        .cache_refill_column_valid(), .cache_refill_column_ready(1'b0),
        .cache_refill_column_slot(), .cache_refill_column()
    );

    assign remap_done_valid = manager_remap_event_valid;
    assign remap_fault = manager_remap_event_fault;

    wire unused_internal = (|support_gradients) || (|support_gradient_valid) ||
                           (|bank0_slot_valid) || (|bank1_slot_valid);
endmodule

`default_nettype wire
