`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module m8_resource_dispatcher #(
    parameter integer TAG_W = 3
)(
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire scalar_state_clear,
    input  wire algorithm_preload_seen,
    input  wire [5:0] selection_k,
    input  wire [6:0] active_work_count,
    input  wire [8:0] active_measurement_count,
    input  wire [1:0] active_refinement_profile,
    input  wire [7:0] active_refine_limit,
    input  wire [4:0] active_normal_residual_shift,
    input  wire [`RECON_ACC_W-1:0] active_residual_limit,
    input  wire cycle_valid,
    input  wire cycle_commit,
    input  wire [35:0] resource_ctx,
    output wire m5_cycle_valid,
    output wire m5_cycle_commit,
    input  wire m5_resource_in_ready,
    input  wire m5_resource_out_ready,
    input  wire m5_resource_contract_error,
    input  wire m5_scalar0_valid,
    input  wire signed [`RECON_ACC_W-1:0] m5_scalar0_data,
    input  wire m5_scalar1_valid,
    input  wire signed [`RECON_ACC_W-1:0] m5_scalar1_data,
    input  wire m5_refinement_breakdown,
    input  wire m5_refinement_saturation,
    input  wire transport_restart_ready,
    output wire transport_restart_valid,
    output wire [2:0] transport_restart_mask,
    input  wire candidate_valid,
    output wire candidate_ready,
    input  wire signed [`RECON_SOLVER_W-1:0] candidate_score,
    input  wire [9:0] candidate_index,
    input  wire candidate_saturated,
    output wire candidate_store_valid,
    input  wire candidate_store_ready,
    output wire [5:0] candidate_store_slot,
    output wire [9:0] candidate_store_column,
    output wire phi_cache_prepare_valid,
    input  wire phi_cache_prepare_ready,
    output wire phi_cache_prepare_from_candidates,
    output wire [6:0] phi_cache_prepare_support_count,
    output wire [6:0] phi_cache_prepare_preserve_count,
    output wire phi_cache_promote_valid,
    input  wire phi_cache_promote_ready,
    output wire [5:0] phi_cache_promote_candidate_slot,
    output wire [6:0] phi_cache_promote_support_slot,
    input  wire phi_cache_valid,
    input  wire phi_cache_fault,
    output wire phi_cache_invalidate,
    output wire phi_cache_refill_pending,
    output wire [6:0] phi_cache_refill_support_count,
    output wire phi_cache_refill_column_valid,
    input  wire phi_cache_refill_column_ready,
    output wire [6:0] phi_cache_refill_column_slot,
    output wire [9:0] phi_cache_refill_column,
    output wire resource_in_ready,
    output wire resource_out_ready,
    output wire resource_contract_error,
    output wire selection_fault_valid,
    output wire support_remap_event_valid,
    output wire support_remap_event_fault,
    output wire [6:0] support_remap_dropped_count,
    output wire [96*10-1:0] support_remap_dropped_indices,
    output wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients,
    output wire [1023:0] active_support_bitmap,
    output wire [96*10-1:0] active_support_indices,
    output wire [96*`RECON_SOLVER_W-1:0] active_support_coefficients,
    input  wire support_coefficient_stripe_read_enable,
    input  wire [2:0] support_coefficient_stripe_read_index,
    output wire support_coefficient_stripe_read_valid,
    output wire [16*`RECON_SOLVER_W-1:0]
        support_coefficient_stripe_read_coefficients,
    output wire [96*`RECON_SOLVER_W-1:0] active_support_gradients,
    output wire [95:0] active_support_gradient_valid,
    output wire [6:0] active_support_count,
    output wire refinement_event_valid,
    output wire refinement_certificate_pass,
    output wire refinement_restart_required,
    output wire refinement_recompute_required,
    output wire refinement_replacement_required,
    output wire refinement_iteration_advance,
    output wire [2:0] refinement_stop_reason,
    output wire termination_event_valid,
    output wire termination_residual_limit_reached,
    output wire [`RECON_ACC_W-1:0] termination_residual_sq,
    output wire [5:0] selection_count,
    output wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores,
    output wire [`RECON_K_MAX*10-1:0] result_indices
);
    localparam integer CANDIDATE_MAX = 64;
    localparam integer WORK_MAX = 96;
    localparam [1:0] OWNER_TOPK = 2'd0;
    localparam [1:0] OWNER_SUPPORT = 2'd1;
    localparam [1:0] OWNER_REFINEMENT = 2'd2;

    wire [4:0] operation = resource_ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                                               `RECON_RESOURCE_FIELD_OPERATION_W];
    wire wait_for_ready = resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire wait_for_result = resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire [2:0] input_select = resource_ctx[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                                                  `RECON_RESOURCE_FIELD_INPUT_SELECT_W];
    wire [2:0] output_select = resource_ctx[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
                                                    `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W];
    wire [5:0] configuration_id = resource_ctx[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +:
                                                      `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W];
    wire [1:0] stream_boundary = resource_ctx[`RECON_RESOURCE_FIELD_STREAM_BOUNDARY_LSB +:
                                                     `RECON_RESOURCE_FIELD_STREAM_BOUNDARY_W];
    wire [3:0] count_select = resource_ctx[`RECON_RESOURCE_FIELD_COUNT_SELECT_LSB +:
                                                  `RECON_RESOURCE_FIELD_COUNT_SELECT_W];
    wire [3:0] event_id = resource_ctx[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +:
                                              `RECON_RESOURCE_FIELD_EVENT_ID_W];
    reg selection_k_one_shot;
    reg omp_support_mode;
    wire [5:0] effective_selection_k = configuration_id[5] ?
        {1'b0, configuration_id[4:0]} : selection_k;

    wire m5_owned =
        ((operation >= `RECON_RESOURCE_OP_REDUCE_SUM) &&
         (operation <= `RECON_RESOURCE_OP_REDUCE_MAX_ABS)) ||
        ((operation >= `RECON_RESOURCE_OP_SCALAR_RECIPROCAL) &&
         (operation <= `RECON_RESOURCE_OP_SCALAR_SQRT)) ||
        ((operation >= `RECON_RESOURCE_OP_SHARED_VECTOR_DOT) &&
         (operation <= `RECON_RESOURCE_OP_SHARED_VECTOR_COPY));
    wire topk_owned = (operation == `RECON_RESOURCE_OP_TOPK_PUSH) ||
                      (operation == `RECON_RESOURCE_OP_TOPK_COMMIT);
    wire support_owned = (operation >= `RECON_RESOURCE_OP_SUPPORT_CLEAR) &&
                         (operation <= `RECON_RESOURCE_OP_SUPPORT_ROLLBACK);
    wire refinement_owned = operation == `RECON_RESOURCE_OP_REFINEMENT_CHECK;
    wire termination_check = refinement_owned && configuration_id[5];
    wire transaction_owned = topk_owned || support_owned || refinement_owned;
    wire [1:0] context_owner = support_owned ? OWNER_SUPPORT :
                               refinement_owned ? OWNER_REFINEMENT : OWNER_TOPK;
    wire nop_owned = operation == `RECON_RESOURCE_OP_NOP;
    wire restart_context = nop_owned &&
        (stream_boundary == `RECON_STREAM_BOUNDARY_FIRST) &&
        (configuration_id[5:3] == 3'b000) &&
        (configuration_id[2:0] != 3'b000) &&
        !wait_for_result;
    wire plain_nop = nop_owned && (configuration_id == 0) &&
        (stream_boundary == `RECON_STREAM_BOUNDARY_BODY) &&
        !wait_for_ready && !wait_for_result;
    wire issue_context = transaction_owned && !wait_for_result;
    wire response_context = transaction_owned && wait_for_result;
    wire push_context = operation == `RECON_RESOURCE_OP_TOPK_PUSH;
    wire pipelined_push_context = topk_owned && push_context && event_id[3];
    wire pipelined_push_issue_context = pipelined_push_context && issue_context;
    wire pipelined_push_wait_context = pipelined_push_context && response_context;
    wire support_scatter_stream = support_owned && issue_context &&
        (operation == `RECON_RESOURCE_OP_SUPPORT_SCATTER) &&
        (input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM);

    reg selection_epoch_pending;
    wire selection_epoch_start = selection_epoch_pending && cycle_valid &&
        topk_owned && issue_context && push_context;

    reg pending_valid;
    reg [1:0] pending_owner;
    reg [4:0] pending_operation;
    reg [TAG_W-1:0] pending_tag;
    reg pending_termination_check;
    wire pending_support = pending_owner == OWNER_SUPPORT;
    reg [1:0] pipelined_push_outstanding;
    reg pipelined_push_fault;

    wire topk_cycle_ready;
    wire topk_unit_response_valid;
    wire topk_unit_response_ready;
    wire [4:0] topk_unit_response_operation;
    wire [TAG_W-1:0] topk_unit_response_tag;
    wire topk_unit_response_fault;
    wire [5:0] topk_unit_response_count;
    reg [1:0] topk_response_fifo_count;
    reg [4:0] topk_response_fifo_operation0;
    reg [4:0] topk_response_fifo_operation1;
    reg [TAG_W-1:0] topk_response_fifo_tag0;
    reg [TAG_W-1:0] topk_response_fifo_tag1;
    reg topk_response_fifo_fault0;
    reg topk_response_fifo_fault1;
    reg [5:0] topk_response_fifo_count0;
    reg [5:0] topk_response_fifo_count1;
    wire topk_response_fifo_valid = topk_response_fifo_count != 0;
    wire topk_response_valid = topk_response_fifo_valid ||
        topk_unit_response_valid;
    wire [4:0] topk_response_operation = topk_response_fifo_valid ?
        topk_response_fifo_operation0 : topk_unit_response_operation;
    wire [TAG_W-1:0] topk_response_tag = topk_response_fifo_valid ?
        topk_response_fifo_tag0 : topk_unit_response_tag;
    wire topk_response_fault = topk_response_fifo_valid ?
        topk_response_fifo_fault0 : topk_unit_response_fault;
    wire [5:0] topk_response_count = topk_response_fifo_valid ?
        topk_response_fifo_count0 : topk_unit_response_count;

    wire [6:0] collector_count;
    wire [6:0] collector_read_slot;
    wire collector_read_valid;
    wire signed [`RECON_SOLVER_W-1:0] collector_read_value;
    wire [9:0] collector_read_index;
    wire [5:0] collector_read_symbol_slot;
    wire [6:0] collector_read_sorted_slot;
    wire [WORK_MAX*`RECON_SOLVER_W-1:0] collector_gradients;
    wire [WORK_MAX-1:0] collector_gradient_valid;
    assign active_support_gradients = collector_gradients;
    assign active_support_gradient_valid = collector_gradient_valid;
    wire collector_store_valid;
    wire [5:0] collector_store_slot;
    wire [9:0] collector_store_column;
    assign candidate_store_valid = collector_store_valid;
    assign candidate_store_slot = collector_store_slot;
    assign candidate_store_column = collector_store_column;

    wire support_cycle_ready;
    wire support_response_valid;
    wire [4:0] support_response_operation;
    wire [TAG_W-1:0] support_response_tag;
    wire support_response_fault;
    wire [6:0] support_response_count;
    wire support_response_member;
    wire [6:0] support_response_slot;
    wire [9:0] support_response_atom;
    wire signed [`RECON_SOLVER_W-1:0] support_response_coefficient;
    wire support_transaction_open;
    wire support_current_bank;
    wire support_candidate_member;
    wire [6:0] support_candidate_slot;
    wire support_append_gradient_valid;
    wire [6:0] support_append_gradient_slot;
    wire signed [`RECON_SOLVER_W-1:0] support_append_gradient_value;
    reg candidate_membership_valid;
    reg [9:0] candidate_membership_index;
    reg candidate_membership_member;
    reg [6:0] candidate_membership_slot;
    wire [6:0] support_current_count;
    wire [6:0] support_proposed_count;
    wire [6:0] support_view_count;
    wire support_proposal_view_active;
    assign active_support_count = support_view_count;
    wire [6:0] resident_work_count = (support_view_count != 0) ?
        support_view_count : active_work_count;
    wire [31:0] support_rollback_count;
    wire [31:0] support_rollback_cycles;
    wire [WORK_MAX*37-1:0] support_bank0_entries;
    wire [WORK_MAX*37-1:0] support_bank1_entries;
    wire [WORK_MAX-1:0] support_bank0_valid;
    wire [WORK_MAX-1:0] support_bank1_valid;

    wire refinement_request_ready;
    reg refinement_response_valid;
    reg [TAG_W-1:0] refinement_response_tag;
    reg refinement_response_pass;
    reg refinement_response_restart;
    reg refinement_response_breakdown;
    reg refinement_response_saturation;
    reg [2:0] refinement_response_stop_reason;
    reg refinement_response_step_advance;
    reg refinement_recompute_latched;
    reg refinement_replacement_latched;
    reg refinement_transaction_active;
    reg refinement_full_check_pending;
    reg refinement_pending_fast_boundary;
    reg refinement_balanced_fallback;
    reg [7:0] refinement_iterations;
    reg [`RECON_ACC_W-1:0] refinement_gamma_reference;
    reg refinement_algorithm_class_valid;
    reg [3:0] refinement_balanced_budget;
    reg [3:0] refinement_fast_budget;
    reg refinement_global_union_pending;

    wire candidate_membership_matches = candidate_membership_valid &&
        (candidate_membership_index == candidate_index);
    wire literal_group_support_mode = configuration_id[5] &&
        configuration_id[1];
    wire support_exclusion_enabled =
        (((input_select == `RECON_RESOURCE_INPUT_GLOBAL_REDUCTION) &&
          ((effective_selection_k == 6'd1) || omp_support_mode) &&
          !selection_k_one_shot) ||
         literal_group_support_mode) &&
        !configuration_id[0];
    wire support_gradient_capture_enabled = configuration_id[1] &&
        push_context;
    wire support_membership_lookup_enabled = support_exclusion_enabled ||
                                             support_gradient_capture_enabled;
    wire candidate_excluded = support_exclusion_enabled && push_context && candidate_valid &&
        candidate_membership_matches && candidate_membership_member;
    wire candidate_membership_ready = !support_membership_lookup_enabled ||
        !push_context || !candidate_valid ||
        candidate_membership_matches;
    wire [6:0] effective_candidate_limit =
        ((input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) ||
         configuration_id[5] || selection_k_one_shot) ?
        {1'b0, effective_selection_k} :
        ({1'b0, effective_selection_k} << 1);
    wire topk_payload_valid = !push_context || candidate_valid;
    wire pipelined_push_response_matches = topk_response_valid &&
        (topk_response_operation == `RECON_RESOURCE_OP_TOPK_PUSH) &&
        (topk_response_tag == event_id[TAG_W-1:0]);
    wire pipelined_push_response_ready = cycle_valid &&
        (pipelined_push_issue_context || pipelined_push_wait_context);
    wire pipelined_push_response_fire = pipelined_push_response_ready &&
        pipelined_push_response_matches;
    wire pipelined_push_has_capacity =
        (pipelined_push_outstanding < 2) || pipelined_push_response_matches;
    wire pipelined_push_drain_ready = (pipelined_push_outstanding == 0) ||
        ((pipelined_push_outstanding == 1) &&
         pipelined_push_response_matches);
    wire topk_request_ready = !pending_valid && topk_cycle_ready &&
        (!pipelined_push_issue_context || pipelined_push_has_capacity) &&
        topk_payload_valid && !candidate_saturated &&
        (!selection_epoch_pending || selection_epoch_start) &&
        candidate_membership_ready;
    wire support_finalize_wait = support_owned && issue_context &&
        (operation == `RECON_RESOURCE_OP_SUPPORT_COMMIT) &&
        phi_cache_refill_pending;
    wire support_payload_valid = !support_scatter_stream || candidate_valid;
    wire support_request_ready = !pending_valid && support_cycle_ready &&
        support_payload_valid && !candidate_saturated &&
        (!support_finalize_wait || phi_cache_valid || phi_cache_fault);
    wire refinement_payload_valid = m5_scalar1_valid &&
        (termination_check || m5_scalar0_valid);
    wire refinement_issue_format_valid =
        (input_select == (termination_check ?
         `RECON_RESOURCE_INPUT_SCALAR_1 :
         `RECON_RESOURCE_INPUT_SCALAR_0)) &&
        (output_select == `RECON_RESOURCE_OUTPUT_EVENT) &&
        (count_select == (termination_check ?
         `RECON_RESOURCE_COUNT_MEASUREMENT_COUNT :
         `RECON_RESOURCE_COUNT_ACTIVE_SUPPORT_COUNT));
    wire refinement_response_format_valid =
        (output_select == `RECON_RESOURCE_OUTPUT_EVENT);
    wire refinement_context_format_valid = issue_context ?
        refinement_issue_format_valid : refinement_response_format_valid;
    wire refinement_transaction_ready = !pending_valid &&
        refinement_request_ready && refinement_payload_valid &&
        refinement_issue_format_valid;
    wire request_ready = topk_owned ? topk_request_ready :
                         support_owned ? support_request_ready :
                         refinement_transaction_ready;

    wire selected_response_valid = pending_owner == OWNER_SUPPORT ?
        support_response_valid : pending_owner == OWNER_REFINEMENT ?
        refinement_response_valid : topk_response_valid;
    wire [4:0] selected_response_operation = pending_owner == OWNER_SUPPORT ?
        support_response_operation : pending_owner == OWNER_REFINEMENT ?
        `RECON_RESOURCE_OP_REFINEMENT_CHECK : topk_response_operation;
    wire [TAG_W-1:0] selected_response_tag = pending_owner == OWNER_SUPPORT ?
        support_response_tag : pending_owner == OWNER_REFINEMENT ?
        refinement_response_tag : topk_response_tag;
    wire selected_response_fault = pending_owner == OWNER_SUPPORT ?
        support_response_fault : pending_owner == OWNER_REFINEMENT ?
        (refinement_response_breakdown || refinement_response_saturation) :
        topk_response_fault;
    wire response_context_matches = pending_valid &&
        (operation == pending_operation) &&
        (context_owner == pending_owner) &&
        (event_id[TAG_W-1:0] == pending_tag);
    wire response_matches = response_context_matches && selected_response_valid &&
        (selected_response_operation == pending_operation) &&
        (selected_response_tag == pending_tag);
    wire issue_fire = cycle_valid && cycle_commit && issue_context && request_ready;
    wire response_fire = cycle_valid && cycle_commit && response_context;
    wire topk_response_pop = pipelined_push_response_fire ||
        (response_fire && response_matches && (pending_owner == OWNER_TOPK));
    assign topk_unit_response_ready = topk_response_fifo_count < 2;
    wire topk_response_push = topk_unit_response_valid && topk_unit_response_ready;
    wire topk_response_bypass = !topk_response_fifo_valid &&
        topk_response_push && topk_response_pop;
    wire topk_response_enqueue = topk_response_push && !topk_response_bypass;
    wire topk_response_dequeue = topk_response_pop && topk_response_fifo_valid;

    assign transport_restart_valid = cycle_valid && cycle_commit && restart_context;
    assign transport_restart_mask = configuration_id[2:0];
    assign m5_cycle_valid = cycle_valid && m5_owned;
    assign m5_cycle_commit = cycle_commit && m5_owned;
    assign candidate_ready = cycle_valid && cycle_commit && issue_context &&
        ((topk_owned && push_context && topk_request_ready) ||
         (support_scatter_stream && support_request_ready));

    assign resource_in_ready = !cycle_valid ||
        (m5_owned ? m5_resource_in_ready :
         transaction_owned ?
             (pipelined_push_wait_context ? pipelined_push_drain_ready :
              (issue_context && wait_for_ready) ? request_ready :
               (response_context && !wait_for_ready) ? response_context_matches : 1'b0) :
         restart_context ? transport_restart_ready :
         plain_nop ? 1'b1 : 1'b0);
    assign resource_out_ready = !cycle_valid ||
        (m5_owned ? m5_resource_out_ready :
         transaction_owned ?
             (pipelined_push_wait_context ? pipelined_push_drain_ready :
              (issue_context && wait_for_ready) ? 1'b1 :
               (response_context && !wait_for_ready) ? response_matches : 1'b0) :
         (restart_context || plain_nop) ? 1'b1 : 1'b0);

    wire malformed_transaction = transaction_owned && !pipelined_push_context &&
        ((!wait_for_result && !wait_for_ready) ||
         (wait_for_result && wait_for_ready) ||
          (wait_for_result && ((!pending_valid && !cycle_commit) ||
          (pending_valid && ((operation != pending_operation) ||
                             (context_owner != pending_owner) ||
                             (event_id[TAG_W-1:0] != pending_tag))))) ||
         (!wait_for_result && pending_valid && !cycle_commit));
    wire malformed_nop = nop_owned && !plain_nop && !restart_context;
    wire unavailable_owner = !nop_owned && !m5_owned && !transaction_owned;
    assign resource_contract_error = cycle_valid &&
        ((m5_owned && m5_resource_contract_error) || malformed_transaction ||
         unavailable_owner || malformed_nop ||
         (refinement_owned && !refinement_context_format_valid) ||
         (((topk_owned && issue_context && push_context) ||
           support_scatter_stream) && candidate_valid &&
          candidate_saturated));
    assign selection_fault_valid =
        (response_fire && response_matches &&
         (pending_owner != OWNER_REFINEMENT) && selected_response_fault) ||
        (cycle_valid && cycle_commit && pipelined_push_wait_context &&
         (pipelined_push_fault ||
          (pipelined_push_response_matches && topk_response_fault)));
    assign refinement_event_valid = response_fire && response_matches &&
        (pending_owner == OWNER_REFINEMENT) && !pending_termination_check;
    assign refinement_certificate_pass = refinement_response_pass;
    assign refinement_restart_required = refinement_response_restart;
    assign refinement_recompute_required = refinement_recompute_latched;
    assign refinement_replacement_required = refinement_replacement_latched;
    assign refinement_iteration_advance = refinement_event_valid &&
        refinement_response_step_advance;
    assign refinement_stop_reason = refinement_response_stop_reason;
    wire [`RECON_ACC_W-1:0] termination_residual_sq_data =
        m5_scalar1_data >> (2 * (`RECON_SOLVER_F - `RECON_DATA_F));
    assign termination_event_valid = response_fire && response_matches &&
        (pending_owner == OWNER_REFINEMENT) && pending_termination_check;
    assign termination_residual_limit_reached = refinement_response_pass;
    assign termination_residual_sq = termination_residual_sq_data;
    assign selection_count = topk_response_count;

    topk_selection_unit #(.TAG_W(TAG_W),
        .EXPOSE_RETAINED_VECTOR(0)) u_topk (
        .clk(clk), .rst_n(rst_n), .routine_start(1'b0),
        .selection_epoch_start(selection_epoch_start),
        .selection_k(effective_selection_k),
        .candidate_limit(effective_candidate_limit),
        .candidate_store_enable(
            input_select != `RECON_RESOURCE_INPUT_MEMORY_STREAM),
        .cycle_valid(cycle_valid && topk_owned && issue_context &&
                     topk_payload_valid && !candidate_saturated),
        .cycle_ready(topk_cycle_ready),
        .cycle_commit(cycle_commit && topk_owned && issue_context),
        .operation(operation), .request_tag(event_id[TAG_W-1:0]),
        .candidate_score(candidate_score), .candidate_index(candidate_index),
        .candidate_exclude(candidate_excluded),
        .response_valid(topk_unit_response_valid),
        .response_ready(topk_unit_response_ready),
        .response_operation(topk_unit_response_operation),
        .response_tag(topk_unit_response_tag),
        .response_fault(topk_unit_response_fault),
        .response_count(topk_unit_response_count),
        .result_scores(result_scores), .result_indices(result_indices),
        .retained_candidate_count(collector_count),
        .retained_candidate_values(),
        .retained_candidate_indices(),
        .retained_candidate_symbol_slots(),
        .retained_candidate_read_slot(collector_read_slot),
        .retained_candidate_read_valid(collector_read_valid),
        .retained_candidate_read_value(collector_read_value),
        .retained_candidate_read_index(collector_read_index),
        .retained_candidate_read_symbol_slot(collector_read_symbol_slot),
        .retained_candidate_read_sorted_slot(collector_read_sorted_slot),
        .candidate_store_valid(collector_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(collector_store_slot),
        .candidate_store_column(collector_store_column),
        .candidate_symbol_valid(1'b0), .candidate_symbol_payload(128'd0),
        .candidate_symbol_ready()
    );

    support_gradient_store u_gradient_store (
        .clk(clk), .rst_n(rst_n), .clear(selection_epoch_start),
        .gradient_valid(support_append_gradient_valid ||
                        (issue_fire && support_gradient_capture_enabled &&
                         candidate_membership_matches &&
                         candidate_membership_member)),
        .gradient_slot(support_append_gradient_valid ?
                       support_append_gradient_slot : candidate_membership_slot),
        .gradient_value(support_append_gradient_valid ?
                        support_append_gradient_value : candidate_score),
        .support_gradients(collector_gradients),
        .support_gradient_valid(collector_gradient_valid)
    );

    support_state_manager #(.TAG_W(TAG_W),
        .USE_INDEXED_CANDIDATE_READ(1)) u_support (
        .clk(clk), .rst_n(rst_n),
        .routine_start(routine_start && !support_proposal_view_active),
        .abort_transaction(1'b0),
        .certificate_fail(refinement_event_valid &&
                          !refinement_certificate_pass &&
                          !refinement_restart_required &&
                          (refinement_stop_reason == 3'd3)),
        .cycle_valid(cycle_valid && support_owned && issue_context),
        .cycle_ready(support_cycle_ready),
        .cycle_commit(cycle_commit && support_owned && issue_context),
        .operation(operation), .request_tag(event_id[TAG_W-1:0]),
        .request_slot(support_scatter_stream ?
                      candidate_index[6:0] : {1'b0, configuration_id}),
        .request_cache_from_candidates(
            input_select != `RECON_RESOURCE_INPUT_SUPPORT_STREAM),
        .request_candidate_coefficients(
            input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM),
        .request_zero_candidate_coefficient(
            input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM),
        .request_defer_activation(configuration_id[0]),
        .request_sort_by_index(configuration_id[1]),
        .request_scatter_active(!configuration_id[0]),
        .scatter_coefficient(candidate_score),
        .candidate_count(collector_count), .candidate_values({CANDIDATE_MAX*`RECON_SOLVER_W{1'b0}}),
        .candidate_indices({CANDIDATE_MAX*10{1'b0}}),
        .candidate_symbol_slots({CANDIDATE_MAX*6{1'b0}}),
        .candidate_read_slot(collector_read_slot),
        .candidate_read_valid(collector_read_valid),
        .candidate_read_value(collector_read_value),
        .candidate_read_index(collector_read_index),
        .candidate_read_symbol_slot(collector_read_symbol_slot),
        .candidate_read_sorted_slot(collector_read_sorted_slot),
        .membership_query_atom(candidate_index),
        .membership_query_member(support_candidate_member),
        .membership_query_slot(support_candidate_slot),
        .append_gradient_valid(support_append_gradient_valid),
        .append_gradient_slot(support_append_gradient_slot),
        .append_gradient_value(support_append_gradient_value),
        .response_valid(support_response_valid),
        .response_ready(response_fire && response_matches && pending_support),
        .response_operation(support_response_operation), .response_tag(support_response_tag),
        .response_fault(support_response_fault), .response_count(support_response_count),
        .response_member(support_response_member), .response_slot(support_response_slot),
        .response_atom(support_response_atom),
        .response_coefficient(support_response_coefficient),
        .transaction_open(support_transaction_open), .current_bank(support_current_bank),
        .current_count(support_current_count), .proposed_count(support_proposed_count),
        .view_count(support_view_count),
        .proposal_view_active(support_proposal_view_active),
        .rollback_count(support_rollback_count),
        .rollback_cycle_count(support_rollback_cycles),
        .bank0_entries(support_bank0_entries), .bank1_entries(support_bank1_entries),
        .bank0_slot_valid(support_bank0_valid), .bank1_slot_valid(support_bank1_valid),
        .active_support_bitmap(active_support_bitmap),
        .active_support_indices(active_support_indices),
        .active_support_coefficients(active_support_coefficients),
        .coefficient_stripe_read_enable(
            support_coefficient_stripe_read_enable),
        .coefficient_stripe_read_index(
            support_coefficient_stripe_read_index),
        .coefficient_stripe_read_valid(
            support_coefficient_stripe_read_valid),
        .coefficient_stripe_read_coefficients(
            support_coefficient_stripe_read_coefficients),
        .remap_event_valid(support_remap_event_valid),
        .remap_event_fault(support_remap_event_fault),
        .remap_dropped_count(support_remap_dropped_count),
        .remap_dropped_indices(support_remap_dropped_indices),
        .remap_dropped_coefficients(support_remap_dropped_coefficients),
        .cache_prepare_valid(phi_cache_prepare_valid),
        .cache_prepare_ready(phi_cache_prepare_ready),
        .cache_prepare_from_candidates(phi_cache_prepare_from_candidates),
        .cache_prepare_support_count(phi_cache_prepare_support_count),
        .cache_prepare_preserve_count(phi_cache_prepare_preserve_count),
        .cache_promote_valid(phi_cache_promote_valid),
        .cache_promote_ready(phi_cache_promote_ready),
        .cache_promote_candidate_slot(phi_cache_promote_candidate_slot),
        .cache_promote_support_slot(phi_cache_promote_support_slot),
        .cache_valid(phi_cache_valid), .cache_fault(phi_cache_fault),
        .cache_invalidate(phi_cache_invalidate),
        .cache_refill_pending(phi_cache_refill_pending),
        .cache_refill_support_count(phi_cache_refill_support_count),
        .cache_refill_column_valid(phi_cache_refill_column_valid),
        .cache_refill_column_ready(phi_cache_refill_column_ready),
        .cache_refill_column_slot(phi_cache_refill_column_slot),
        .cache_refill_column(phi_cache_refill_column)
    );

    assign refinement_request_ready = !refinement_response_valid;
    wire refinement_request_accept = cycle_valid && cycle_commit &&
        refinement_owned && issue_context && refinement_context_format_valid &&
        refinement_payload_valid && !pending_valid && refinement_request_ready;
    wire refinement_response_accept = response_fire && response_matches &&
        (pending_owner == OWNER_REFINEMENT);

    wire [`RECON_ACC_W-1:0] refinement_reference_comb =
        refinement_transaction_active ? refinement_gamma_reference :
        m5_scalar0_data;
    wire [4:0] refinement_certificate_shift =
        refinement_balanced_fallback ? `RECON_STRICT_NORMAL_RESIDUAL_SHIFT :
        active_normal_residual_shift;
    wire [`RECON_ACC_W-1:0] refinement_relative_limit;
    wire [`RECON_ACC_W-1:0] refinement_quantization_floor;
    wire [`RECON_ACC_W-1:0] refinement_certificate_limit;
    reg [3:0] refinement_profile_budget;
    reg [7:0] refinement_next_iteration;
    reg refinement_cheap_due;
    reg refinement_reliable_due;
    reg refinement_profile_due;
    reg refinement_final_due;

    certificate_limit_unit u_refinement_limit (
        .support_count(resident_work_count),
        .measurement_count(active_measurement_count),
        .normal_residual_shift(refinement_certificate_shift),
        .gamma_reference(refinement_reference_comb),
        .absolute_limit_enable(1'b0),
        .absolute_limit({`RECON_ACC_W{1'b0}}),
        .relative_limit(refinement_relative_limit),
        .quantization_floor(refinement_quantization_floor),
        .certificate_limit(refinement_certificate_limit)
    );

    always @* begin
        refinement_next_iteration = refinement_transaction_active ?
            refinement_iterations + 1'b1 : 8'd1;
        refinement_profile_budget = active_refinement_profile == 2'd1 ?
            (refinement_algorithm_class_valid ? refinement_balanced_budget :
             (algorithm_preload_seen ? 4'd3 :
              (selection_k == 2 ? 4'd4 :
               ((selection_k == 4) && (resident_work_count > 4) ? 4'd5 :
                (selection_k == 4 ? 4'd4 : 4'd3))))) :
            (refinement_algorithm_class_valid ? refinement_fast_budget :
             (algorithm_preload_seen ? 4'd10 :
              (selection_k == 2 ? 4'd3 :
               ((selection_k == 4) && (resident_work_count > 4) ? 4'd6 :
                (selection_k == 4 ? 4'd7 : 4'd3)))));
        refinement_cheap_due = m5_scalar1_data <= refinement_certificate_limit;
        refinement_reliable_due = refinement_next_iteration[2:0] == 3'd0;
        refinement_profile_due = (active_refinement_profile != 2'd0) &&
            !refinement_balanced_fallback &&
            (refinement_next_iteration >= refinement_profile_budget);
        refinement_final_due = (active_refine_limit != 0) &&
            (refinement_next_iteration >= active_refine_limit);
    end

    always @(posedge clk) begin
        if (!rst_n || scalar_state_clear) begin
            refinement_response_valid <= 1'b0;
            refinement_response_tag <= 0;
            refinement_response_pass <= 1'b0;
            refinement_response_restart <= 1'b0;
            refinement_response_breakdown <= 1'b0;
            refinement_response_saturation <= 1'b0;
            refinement_response_stop_reason <= 0;
            refinement_response_step_advance <= 1'b0;
            refinement_recompute_latched <= 1'b0;
            refinement_replacement_latched <= 1'b0;
            refinement_transaction_active <= 1'b0;
            refinement_full_check_pending <= 1'b0;
            refinement_pending_fast_boundary <= 1'b0;
            refinement_balanced_fallback <= 1'b0;
            refinement_iterations <= 0;
            refinement_gamma_reference <= 0;
            refinement_algorithm_class_valid <= 1'b0;
            refinement_balanced_budget <= 4'd3;
            refinement_fast_budget <= 4'd3;
            refinement_global_union_pending <= 1'b0;
        end else begin
            if (cycle_valid && cycle_commit && restart_context &&
                    (configuration_id == 6'd6)) begin
                refinement_algorithm_class_valid <= 1'b1;
                refinement_balanced_budget <= algorithm_preload_seen ?
                    4'd3 : 4'd4;
                refinement_fast_budget <= algorithm_preload_seen ?
                    4'd10 : 4'd7;
            end else if (!refinement_algorithm_class_valid && issue_fire &&
                    (operation == `RECON_RESOURCE_OP_SUPPORT_APPEND) &&
                    (input_select == `RECON_RESOURCE_INPUT_NONE)) begin
                refinement_algorithm_class_valid <= 1'b1;
                refinement_balanced_budget <= 4'd3;
                refinement_fast_budget <= 4'd3;
            end else if (!refinement_algorithm_class_valid && issue_fire &&
                    (operation == `RECON_RESOURCE_OP_SUPPORT_UNION) &&
                    (input_select == `RECON_RESOURCE_INPUT_GLOBAL_REDUCTION)) begin
                refinement_global_union_pending <= 1'b1;
            end else if (refinement_global_union_pending && issue_fire &&
                    (operation == `RECON_RESOURCE_OP_SUPPORT_COMMIT)) begin
                refinement_global_union_pending <= 1'b0;
                refinement_algorithm_class_valid <= 1'b1;
                if (input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM) begin
                    refinement_balanced_budget <= 4'd4;
                    refinement_fast_budget <= 4'd3;
                end else begin
                    refinement_balanced_budget <= 4'd5;
                    refinement_fast_budget <= 4'd6;
                end
            end else if (!refinement_algorithm_class_valid && issue_fire &&
                    (operation == `RECON_RESOURCE_OP_SUPPORT_UNION) &&
                    (input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
                    (configuration_id == 6'd2) && !algorithm_preload_seen) begin
                refinement_algorithm_class_valid <= 1'b1;
                refinement_balanced_budget <= 4'd5;
                refinement_fast_budget <= 4'd6;
            end
            if (refinement_response_accept)
                refinement_response_valid <= 1'b0;
            if (refinement_request_accept) begin
                refinement_response_valid <= 1'b1;
                refinement_response_tag <= event_id[TAG_W-1:0];
                refinement_response_pass <= 1'b0;
                refinement_response_restart <= 1'b0;
                refinement_response_breakdown <= m5_refinement_breakdown ||
                    m5_scalar0_data[`RECON_ACC_W-1] ||
                    m5_scalar1_data[`RECON_ACC_W-1];
                refinement_response_saturation <= m5_refinement_saturation;
                refinement_response_stop_reason <= 3'd0;
                refinement_response_step_advance <= 1'b0;
                refinement_recompute_latched <= 1'b0;
                refinement_replacement_latched <= 1'b0;
                if (termination_check) begin
                    refinement_response_pass <= !m5_refinement_breakdown &&
                        !m5_refinement_saturation &&
                        !m5_scalar1_data[`RECON_ACC_W-1] &&
                        (termination_residual_sq_data <= active_residual_limit);
                    refinement_response_stop_reason <= 3'd1;
                end else if (refinement_full_check_pending) begin
                    refinement_full_check_pending <= 1'b0;
                    if (!m5_refinement_breakdown && !m5_refinement_saturation &&
                            !m5_scalar1_data[`RECON_ACC_W-1] &&
                            (refinement_pending_fast_boundary ||
                             (m5_scalar1_data <= refinement_certificate_limit))) begin
                        refinement_response_pass <= 1'b1;
                        refinement_response_stop_reason <= 3'd1;
                        refinement_transaction_active <= 1'b0;
                    end else begin
                        refinement_response_restart <= 1'b1;
                        refinement_replacement_latched <= 1'b1;
                        refinement_response_stop_reason <= 3'd2;
                        if ((active_refinement_profile == 2'd1) &&
                                refinement_profile_due)
                            refinement_balanced_fallback <= 1'b1;
                    end
                end else begin
                    refinement_response_step_advance <= 1'b1;
                    refinement_iterations <= refinement_next_iteration;
                    if (!refinement_transaction_active) begin
                        refinement_transaction_active <= 1'b1;
                        refinement_gamma_reference <= m5_scalar0_data;
                        refinement_balanced_fallback <= 1'b0;
                    end
                    if (!refinement_algorithm_class_valid) begin
                        refinement_algorithm_class_valid <= 1'b1;
                        if (algorithm_preload_seen) begin
                            refinement_balanced_budget <= 4'd3;
                            refinement_fast_budget <= 4'd10;
                        end else if (selection_k == 2) begin
                            refinement_balanced_budget <= 4'd4;
                            refinement_fast_budget <= 4'd3;
                        end else if ((selection_k == 4) &&
                                     (resident_work_count > 4)) begin
                            refinement_balanced_budget <= 4'd5;
                            refinement_fast_budget <= 4'd6;
                        end else if (selection_k == 4) begin
                            refinement_balanced_budget <= 4'd4;
                            refinement_fast_budget <= 4'd7;
                        end
                    end
                    if (m5_refinement_breakdown || m5_refinement_saturation ||
                            m5_scalar0_data[`RECON_ACC_W-1] ||
                            m5_scalar1_data[`RECON_ACC_W-1]) begin
                        refinement_response_stop_reason <= 3'd3;
                    end else if ((active_refinement_profile == 2'd2) &&
                                 refinement_profile_due) begin
                        refinement_response_pass <= 1'b1;
                        refinement_response_stop_reason <= 3'd1;
                        refinement_transaction_active <= 1'b0;
                    end else if (refinement_cheap_due || refinement_reliable_due ||
                                 refinement_profile_due || refinement_final_due) begin
                        refinement_response_restart <= 1'b1;
                        refinement_recompute_latched <= 1'b1;
                        refinement_full_check_pending <= 1'b1;
                        refinement_pending_fast_boundary <=
                            (active_refinement_profile == 2'd2) &&
                            refinement_profile_due;
                        refinement_response_stop_reason <= 3'd2;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || scalar_state_clear) begin
            selection_k_one_shot <= 1'b0;
            omp_support_mode <= 1'b0;
        end else begin
            if (issue_fire &&
                    (operation == `RECON_RESOURCE_OP_SUPPORT_APPEND))
                omp_support_mode <= 1'b1;
            if (cycle_valid && cycle_commit && restart_context &&
                 (configuration_id == 6'd6))
                selection_k_one_shot <= 1'b1;
            else if (issue_fire &&
                     (operation == `RECON_RESOURCE_OP_TOPK_COMMIT))
                selection_k_one_shot <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || routine_start) begin
            pipelined_push_outstanding <= 0;
            pipelined_push_fault <= 0;
        end else begin
            case ({issue_fire && pipelined_push_issue_context,
                   pipelined_push_response_fire})
                2'b10: pipelined_push_outstanding <=
                    pipelined_push_outstanding + 1'b1;
                2'b01: pipelined_push_outstanding <=
                    pipelined_push_outstanding - 1'b1;
                default: pipelined_push_outstanding <=
                    pipelined_push_outstanding;
            endcase
            if (selection_epoch_start)
                pipelined_push_fault <= 0;
            if (pipelined_push_response_fire && topk_response_fault)
                pipelined_push_fault <= 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || routine_start || selection_epoch_start) begin
            topk_response_fifo_count <= 0;
            topk_response_fifo_operation0 <= `RECON_RESOURCE_OP_NOP;
            topk_response_fifo_operation1 <= `RECON_RESOURCE_OP_NOP;
            topk_response_fifo_tag0 <= 0;
            topk_response_fifo_tag1 <= 0;
            topk_response_fifo_fault0 <= 0;
            topk_response_fifo_fault1 <= 0;
            topk_response_fifo_count0 <= 0;
            topk_response_fifo_count1 <= 0;
        end else begin
            case ({topk_response_enqueue, topk_response_dequeue})
                2'b10: begin
                    topk_response_fifo_count <= topk_response_fifo_count + 1'b1;
                    if (topk_response_fifo_count == 0) begin
                        topk_response_fifo_operation0 <= topk_unit_response_operation;
                        topk_response_fifo_tag0 <= topk_unit_response_tag;
                        topk_response_fifo_fault0 <= topk_unit_response_fault;
                        topk_response_fifo_count0 <= topk_unit_response_count;
                    end else begin
                        topk_response_fifo_operation1 <= topk_unit_response_operation;
                        topk_response_fifo_tag1 <= topk_unit_response_tag;
                        topk_response_fifo_fault1 <= topk_unit_response_fault;
                        topk_response_fifo_count1 <= topk_unit_response_count;
                    end
                end
                2'b01: begin
                    topk_response_fifo_count <= topk_response_fifo_count - 1'b1;
                    if (topk_response_fifo_count == 2) begin
                        topk_response_fifo_operation0 <= topk_response_fifo_operation1;
                        topk_response_fifo_tag0 <= topk_response_fifo_tag1;
                        topk_response_fifo_fault0 <= topk_response_fifo_fault1;
                        topk_response_fifo_count0 <= topk_response_fifo_count1;
                    end
                end
                2'b11: begin
                    topk_response_fifo_operation0 <= topk_unit_response_operation;
                    topk_response_fifo_tag0 <= topk_unit_response_tag;
                    topk_response_fifo_fault0 <= topk_unit_response_fault;
                    topk_response_fifo_count0 <= topk_unit_response_count;
                end
                default: topk_response_fifo_count <= topk_response_fifo_count;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pending_valid <= 0;
            pending_owner <= OWNER_TOPK;
            pending_operation <= `RECON_RESOURCE_OP_NOP;
            pending_tag <= 0;
            pending_termination_check <= 1'b0;
            selection_epoch_pending <= 1'b1;
            candidate_membership_valid <= 1'b0;
            candidate_membership_index <= 10'd0;
            candidate_membership_member <= 1'b0;
            candidate_membership_slot <= 7'd0;
        end else begin
            if (routine_start)
                selection_epoch_pending <= 1'b1;
            else if (selection_epoch_start)
                selection_epoch_pending <= 1'b0;
            else if (response_fire && response_matches &&
                     (pending_owner == OWNER_TOPK) &&
                     (pending_operation == `RECON_RESOURCE_OP_TOPK_COMMIT))
                selection_epoch_pending <= 1'b1;
            if (routine_start || selection_epoch_start ||
                (issue_fire && push_context) || !candidate_valid) begin
                candidate_membership_valid <= 1'b0;
            end else if (support_membership_lookup_enabled && cycle_valid &&
                         topk_owned && issue_context &&
                         push_context && candidate_valid &&
                         !selection_epoch_pending &&
                         (!candidate_membership_valid ||
                          (candidate_membership_index != candidate_index))) begin
                candidate_membership_valid <= 1'b1;
                candidate_membership_index <= candidate_index;
                candidate_membership_member <= support_candidate_member;
                candidate_membership_slot <= support_candidate_slot;
            end
            if (issue_fire && !pipelined_push_issue_context) begin
                pending_valid <= 1;
                pending_owner <= context_owner;
                pending_operation <= operation;
                pending_tag <= event_id[TAG_W-1:0];
                pending_termination_check <= termination_check;
            end
            if (response_fire && response_matches)
                pending_valid <= 0;
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_pending_valid;
    reg f_response_fire;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;
        f_pending_valid <= pending_valid;
        f_response_fire <= response_fire && response_matches;
        if (rst_n && f_past_valid) begin
            assert(!(m5_cycle_valid && transaction_owned));
            if (cycle_commit)
                assert(resource_in_ready && resource_out_ready && !resource_contract_error);
            if (candidate_ready)
                assert((push_context || support_scatter_stream) &&
                       issue_context && cycle_valid);
            if (candidate_excluded)
                assert(!candidate_store_valid);
            if (transport_restart_valid)
                assert(restart_context && transport_restart_ready);
            if (f_pending_valid && !f_response_fire)
                assert(pending_valid);
            assert(pipelined_push_outstanding <= 2);
            assert(topk_response_fifo_count <= 2);
            if (topk_response_pop)
                assert(topk_response_valid);
        end
    end
`endif

    wire unused_support_observation = (|collector_gradients) || (|collector_gradient_valid) ||
        support_response_member || (|support_response_slot) || (|support_response_atom) ||
        (|support_response_coefficient) || support_transaction_open || support_current_bank ||
        (|support_current_count) || (|support_proposed_count) || (|support_rollback_count) ||
        support_proposal_view_active ||
        (|support_rollback_cycles) || (|support_bank0_entries) || (|support_bank1_entries) ||
        (|support_bank0_valid) || (|support_bank1_valid) || (|support_response_count);
endmodule

`default_nettype wire
