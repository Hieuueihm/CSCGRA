`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module m8_operator_harness #(
    parameter integer USE_INTERNAL_PHI_CACHE = 1,
    parameter [15:0] CGRA_FULL_PE_MASK = 16'hffff
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         run_abort,
    input  wire                         run_start,
    input  wire                         scalar_clear,
    input  wire                         scalar_load_valid,
    output wire                         scalar_load_ready,
    input  wire                         scalar_load_select,
    input  wire signed [`RECON_ACC_W-1:0] scalar_load_data,
    input  wire                         phi_cache_clear,
    input  wire                         execution_active,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] ctx_tile,
    input  wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] ctx_array,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] ctx_stream,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] ctx_resource,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0] ctx_predicates,

    input  wire [63:0]                  cfg_seed,
    input  wire [8:0]                   cfg_measurement_count,
    input  wire [10:0]                  cfg_signal_length,
    input  wire [6:0]                   cfg_work_count,
    input  wire [5:0]                   cfg_selection_k,
    input  wire [4:0]                   cfg_normal_residual_shift,
    input  wire [1:0]                   cfg_refinement_profile,
    input  wire [7:0]                   cfg_refine_limit,
    input  wire [`RECON_ACC_W-1:0]     cfg_residual_limit,
    input  wire [`RECON_PHI_SCALE_MANTISSA_W-1:0] cfg_phi_scale_mantissa_uq17,
    input  wire [`RECON_PHI_SCALE_EXPONENT_W-1:0] cfg_phi_scale_exponent,

    input  wire                         cfg_a_valid,
    input  wire [63:0]                  cfg_a_data,
    input  wire                         cfg_b_valid,
    input  wire [63:0]                  cfg_b_data,
    input  wire                         cfg_w_valid,
    input  wire [63:0]                  cfg_w_data,
    input  wire                         phi_cfg_valid,
    input  wire [63:0]                  phi_cfg_data,

    input  wire                         phi_support_valid,
    output wire                         phi_support_ready,
    input  wire [`RECON_PHI_COLUMN_W-1:0] phi_support_col,
    output wire                         phi_cache_req_valid,
    input  wire                         phi_cache_req_ready,
    output wire [6:0]                   phi_cache_req_slot,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_cache_req_row,
    output wire [`RECON_PHI_TAG_W-1:0] phi_cache_req_tag,
    input  wire                         phi_cache_rsp_valid,
    output wire                         phi_cache_rsp_ready,
    input  wire [31:0]                  phi_cache_rsp_mask,
    input  wire [31:0]                  phi_cache_rsp_sign,
    input  wire [`RECON_PHI_COLUMN_W-1:0] phi_cache_rsp_col,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_cache_rsp_row,
    input  wire [`RECON_PHI_TAG_W-1:0] phi_cache_rsp_tag,
    input  wire                         phi_cache_ext_valid,

    input  wire                         scratch_init_valid,
    output wire                         scratch_init_ready,
    input  wire [2:0]                   scratch_init_bank,
    input  wire [8:0]                   scratch_init_addr,
    input  wire [71:0]                  scratch_init_wr_data,

    input  wire                         scratch_load_active,
    input  wire                         scratch_load_p0_valid,
    output wire                         scratch_load_p0_ready,
    input  wire                         scratch_load_p0_write,
    input  wire [7:0]                   scratch_load_p0_bank_mask,
    input  wire [71:0]                  scratch_load_p0_addr,
    input  wire [575:0]                 scratch_load_p0_wr_data,
    input  wire                         scratch_load_p1_valid,
    output wire                         scratch_load_p1_ready,
    input  wire                         scratch_load_p1_write,
    input  wire [7:0]                   scratch_load_p1_bank_mask,
    input  wire [71:0]                  scratch_load_p1_addr,
    input  wire [575:0]                 scratch_load_p1_wr_data,
    output wire                         scratch_load_conflict,

    output wire                         stream_input_ready,
    output wire                         stream_output_ready,
    output wire                         resource_req_ready,
    output wire                         resource_rsp_valid,
    output wire                         operator_fault,
    output wire [15:0]                  operator_fault_detail,
    output wire                         profile_phi_generate_fire,
    output wire                         profile_phi_replay_request_fire,
    output wire                         profile_phi_replay_response_fire,
    output wire                         profile_phi_cache_fill_fire,
    output wire                         profile_phi_output_fire,
    output wire                         profile_selection_fire,
    output wire                         support_remap_event_valid,
    output wire                         support_remap_event_fault,
    output wire [6:0]                   support_remap_dropped_count,
    output wire [96*10-1:0]             support_remap_dropped_indices,
    output wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients,
    output wire                         refinement_event_valid,
    output wire                         refinement_certificate_pass,
    output wire                         refinement_restart_required,
    output wire                         refinement_recompute_required,
    output wire                         refinement_replacement_required,
    output wire                         refinement_iteration_advance,
    output wire [2:0]                   refinement_stop_reason,
    output wire                         termination_event_valid,
    output wire                         termination_residual_limit_reached,
    output wire [`RECON_ACC_W-1:0]     termination_residual_sq,
    output wire [6:0]                   resident_count,
    output wire [6:0]                   final_support_count,
    output wire [96*10-1:0]             final_support_indices,
    output wire [96*`RECON_SOLVER_W-1:0] final_support_coefficients,
    output wire [5:0]                   selection_count,
    output wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores,
    output wire [`RECON_K_MAX*10-1:0]    result_indices,
    output wire [`RECON_PHI_COLUMN_W-1:0] observed_phi_column,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] observed_phi_row_block
);
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer ACC_W = `RECON_ACC_W;
    localparam integer STRIPE_W = `RECON_VECTOR_MEMORY_BANKS *
                                   `RECON_MEMORY_BANK_WORD_W;

    function [31:0] measurement_lane_mask;
        input [8:0] measurement_count;
        integer mask_lane;
        begin
            measurement_lane_mask = 32'd0;
            for (mask_lane = 0; mask_lane < 32; mask_lane = mask_lane + 1)
                if (mask_lane < measurement_count)
                    measurement_lane_mask[mask_lane] = 1'b1;
        end
    endfunction

    wire [4:0] resource_operation =
        ctx_resource[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                     `RECON_RESOURCE_FIELD_OPERATION_W];
    wire resource_wait_for_ready =
        ctx_resource[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire resource_wait_for_result =
        ctx_resource[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire resource_clear_before =
        ctx_resource[`RECON_RESOURCE_FIELD_CLEAR_BEFORE_LSB];
    wire [2:0] resource_input_select =
        ctx_resource[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_INPUT_SELECT_W];
    wire [2:0] resource_output_select =
        ctx_resource[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W];

    wire vec_req_valid;
    wire vec_cycle_commit;
    wire vec_a_en;
    wire vec_b_en;
    wire vec_w_en;
    wire [5:0] vec_cfg_a_raw;
    wire [5:0] vec_cfg_b;
    wire [5:0] vec_cfg_w;
    wire raw_vec_in_ready;
    wire raw_vec_out_ready;
    wire vec_cfg_error;
    wire vec_access_conflict;
    wire physical_vec_a_valid;
    wire physical_vec_b_valid;
    wire [STRIPE_W-1:0] physical_vec_a;
    wire [STRIPE_W-1:0] physical_vec_b;
    wire stream_a_metadata_valid;
    wire [2:0] stream_a_element_format;
    wire [2:0] stream_a_packing_mode;
    wire [15:0] stream_a_element_count;
    wire stream_b_metadata_valid;
    wire [2:0] stream_b_element_format;
    wire [2:0] stream_b_packing_mode;
    wire [31:0] phi_nonzero;
    wire [31:0] phi_sign;
    wire phi_symbol_valid;
    wire phi_symbol_fire;
    assign profile_phi_output_fire = phi_symbol_fire;
    wire [`RECON_PHI_COLUMN_W-1:0] phi_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_row_block;
    wire [`RECON_PHI_TAG_W-1:0] phi_tag;
    wire phi_command_valid;
    wire phi_command_ready;
    wire [1:0] phi_command;
    wire [5:0] phi_cfg_id;
    wire phi_busy;
    wire phi_done;
    wire phi_cfg_error;
    wire router_phi_symbol_ready;
    wire phi_cache_valid;
    wire phi_cache_fault;
    wire phi_capture_ready;
    wire [2:0] phi_mode;
    wire phi_refill_active;
    wire phi_capture_enable;
    wire candidate_store_valid;
    wire candidate_store_ready;
    wire [5:0] candidate_store_slot;
    wire [`RECON_PHI_COLUMN_W-1:0] candidate_store_column;
    wire phi_cache_prepare_valid;
    wire phi_cache_prepare_ready;
    wire phi_cache_prepare_from_candidates;
    wire [6:0] phi_cache_prepare_support_count;
    wire [6:0] phi_cache_prepare_preserve_count;
    wire phi_cache_promote_valid;
    wire phi_cache_promote_ready;
    wire [5:0] phi_cache_promote_candidate_slot;
    wire [6:0] phi_cache_promote_support_slot;
    wire phi_cache_invalidate;
    wire phi_cache_refill_pending;
    wire [6:0] phi_cache_refill_support_count;
    wire phi_cache_refill_column_valid;
    wire phi_cache_refill_column_ready;
    wire [6:0] phi_cache_refill_column_slot;
    wire [9:0] phi_cache_refill_column;
    wire phi_release_event;
    wire [`RECON_PHI_COLUMN_W-1:0] phi_release_event_col;
    wire phi_refill_start = cycle_valid &&
        (resource_operation == `RECON_RESOURCE_OP_SUPPORT_COMMIT) &&
        (resource_input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM) &&
        (ctx_stream[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                    `RECON_STREAM_FIELD_PHI_COMMAND_W] ==
         `RECON_PHI_COMMAND_START);
    wire router_stream_in_ready;
    wire router_stream_out_ready;
    wire stream_contract_error;
    wire [1:0] ext_a_sel;
    wire [1:0] ext_b_sel;
    wire [32*DATA_W-1:0] external_input_a;

    wire stream_p0_valid;
    wire stream_p0_ready;
    wire stream_p0_write;
    wire [7:0] stream_p0_mask;
    wire [71:0] stream_p0_addr;
    wire [575:0] stream_p0_wr_data;
    wire stream_p0_rd_valid;
    wire [7:0] stream_p0_rd_mask;
    wire [575:0] stream_p0_rd_data;
    wire stream_p1_valid;
    wire stream_p1_ready;
    wire stream_p1_write;
    wire [7:0] stream_p1_mask;
    wire [71:0] stream_p1_addr;
    wire [575:0] stream_p1_wr_data;
    wire stream_p1_rd_valid;
    wire [7:0] stream_p1_rd_mask;
    wire [575:0] stream_p1_rd_data;
    wire scratchpad_conflict;
    wire cursor_restart_valid;
    wire [2:0] cursor_restart_mask;
    wire cursor_restart_ready;

    wire stream_scratch_conflict;
    scratchpad_subsystem u_scratchpad_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .execution_active(execution_active),
        .init_valid(scratch_init_valid),
        .init_ready(scratch_init_ready),
        .init_bank(scratch_init_bank),
        .init_addr(scratch_init_addr),
        .init_data(scratch_init_wr_data),
        .preload_active(scratch_load_active),
        .preload_p0_valid(scratch_load_p0_valid),
        .preload_p0_ready(scratch_load_p0_ready),
        .preload_p0_write(scratch_load_p0_write),
        .preload_p0_mask(scratch_load_p0_bank_mask),
        .preload_p0_addr(scratch_load_p0_addr),
        .preload_p0_data(scratch_load_p0_wr_data),
        .preload_p1_valid(scratch_load_p1_valid),
        .preload_p1_ready(scratch_load_p1_ready),
        .preload_p1_write(scratch_load_p1_write),
        .preload_p1_mask(scratch_load_p1_bank_mask),
        .preload_p1_addr(scratch_load_p1_addr),
        .preload_p1_data(scratch_load_p1_wr_data),
        .preload_conflict(scratch_load_conflict),
        .stream_p0_valid(stream_p0_valid),
        .stream_p0_ready(stream_p0_ready),
        .stream_p0_write(stream_p0_write),
        .stream_p0_mask(stream_p0_mask),
        .stream_p0_addr(stream_p0_addr),
        .stream_p0_wr_data(stream_p0_wr_data),
        .stream_p0_rd_valid(stream_p0_rd_valid),
        .stream_p0_rd_mask(stream_p0_rd_mask),
        .stream_p0_rd_data(stream_p0_rd_data),
        .stream_p1_valid(stream_p1_valid),
        .stream_p1_ready(stream_p1_ready),
        .stream_p1_write(stream_p1_write),
        .stream_p1_mask(stream_p1_mask),
        .stream_p1_addr(stream_p1_addr),
        .stream_p1_wr_data(stream_p1_wr_data),
        .stream_p1_rd_valid(stream_p1_rd_valid),
        .stream_p1_rd_mask(stream_p1_rd_mask),
        .stream_p1_rd_data(stream_p1_rd_data),
        .stream_conflict(stream_scratch_conflict),
        .status_conflict(scratchpad_conflict)
    );

    wire [32*DATA_W-1:0] expanded_vec_a;
    wire [32*DATA_W-1:0] expanded_vec_b;
    wire [15:0] sidecar_valid_a;
    wire [15:0] sidecar_valid_b;
    wire [16*DATA_W-1:0] sidecar_vec_a;
    wire [16*DATA_W-1:0] sidecar_vec_b;
    wire [575:0] vector_write_data;
    wire vector_result_valid;
    wire [15:0] vector_result_lane_valid;
    wire [16*DATA_W-1:0] vector_result_data;
    wire [1023:0] active_support_bitmap;
    wire [96*10-1:0] active_support_indices;
    wire [96*DATA_W-1:0] active_support_coefficients;
    wire support_coefficient_stripe_response_valid;
    wire [16*DATA_W-1:0] support_coefficient_stripe_response_coefficients;
    wire [96*DATA_W-1:0] active_support_gradients;
    wire [95:0] active_support_gradient_valid;
    wire [6:0] active_support_count;
    assign final_support_count = active_support_count;
    assign final_support_indices = active_support_indices;
    assign final_support_coefficients = active_support_coefficients;
    wire [5:0] resource_configuration_id =
        ctx_resource[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +:
                     `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W];
    wire [4:0] active_tile_operation = ctx_tile[4:0];
    wire [1:0] resource_stream_boundary =
        ctx_resource[`RECON_RESOURCE_FIELD_STREAM_BOUNDARY_LSB +:
                     `RECON_RESOURCE_FIELD_STREAM_BOUNDARY_W];
    wire [5:0] vec_cfg_a;
    wire masked_copy_mode;
    wire [16*DATA_W-1:0] selected_vector_result_data;
    wire support_coefficient_stripe_needed;
    wire support_coefficient_stripe_read_enable;
    wire [2:0] support_coefficient_stripe_read_index;
    wire support_coefficient_stripe_buffer_valid;
    wire m5_vector_result_ready;
    support_refinement_adapter u_support_refinement (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .scalar_state_clear(scalar_clear), .abort_flush(run_abort),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .resource_operation(resource_operation),
        .resource_configuration_id(resource_configuration_id),
        .resource_input_select(resource_input_select),
        .resource_output_select(resource_output_select),
        .resource_wait_for_result(resource_wait_for_result),
        .resource_stream_boundary(resource_stream_boundary),
        .vec_cfg_a_raw(vec_cfg_a_raw), .signal_length(cfg_signal_length),
        .support_count(active_support_count), .selected_count(selection_count),
        .selected_indices(result_indices),
        .support_indices(active_support_indices),
        .support_coefficients(active_support_coefficients),
        .support_gradients(active_support_gradients),
        .support_gradient_valid(active_support_gradient_valid),
        .dense_input(vector_result_data),
        .vector_result_valid(vector_result_valid),
        .vector_result_ready(m5_vector_result_ready),
        .stripe_response_valid(support_coefficient_stripe_response_valid),
        .stripe_response_data(support_coefficient_stripe_response_coefficients),
        .cursor_restart_valid(cursor_restart_valid),
        .cursor_restart_mask(cursor_restart_mask),
        .masked_copy_base(), .vec_cfg_a(vec_cfg_a),
        .fresh_refinement_active(),
        .fresh_refinement_zero_estimate(),
        .fresh_refinement_initial_residual(),
        .masked_copy_mode(masked_copy_mode),
        .support_rebuild_mode(),
        .support_coefficient_stripe_needed(support_coefficient_stripe_needed),
        .support_coefficient_stripe_read_enable(
            support_coefficient_stripe_read_enable),
        .support_coefficient_stripe_read_index(
            support_coefficient_stripe_read_index),
        .support_coefficient_stripe_buffer_valid(
            support_coefficient_stripe_buffer_valid),
        .support_coefficient_stripe_buffer(),
        .masked_vector_result_data(),
        .selected_vector_result_data(selected_vector_result_data)
    );
    wire [7:0] write_pack_valid;
    wire [7:0] write_pack_error;
    wire [16*DATA_W-1:0] reduction_scalar_pack;
    wire [3:0] reduction_pack_index;
    wire [10:0] reduction_output_count;
    wire reduction_scalar_pending;
    wire normalizer_memory_mode;
    wire reduction_memory_write_context;
    wire transpose_write_mode;
    wire transpose_write_final;
    wire transpose_write_release;
    wire transpose_normalizer_ready;
    wire cgra_result_low_valid;
    wire cgra_result_high_valid;
    wire cgra_s27_write_phase;
    wire [32*DATA_W-1:0] cgra_result_buffer;
    wire phi_lane_normalize_active;
    wire phi_lane_residual_mode;
    wire [5:0] phi_lane_issue_count;
    wire [5:0] phi_lane_output_count;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_lane_row_block;
    wire [32*`RECON_LOCAL_ACC_W-1:0] phi_lane_accumulator_buffer;
    wire [32*DATA_W-1:0] phi_lane_measurement_buffer;
    wire fused_scalar_valid;
    wire fused_scalar_ready;
    wire fused_scalar_is_gamma;
    wire signed [ACC_W-1:0] fused_scalar_data;
    wire [32*DATA_W-1:0] lane_result;
    wire [31:0] lane_result_valid;

    wire write_is_d18;
    wire write_is_s27;
    wire cgra_result_available;
    wire cgra_result_buffer_busy;
    wire signed [DATA_W-1:0] normalizer_output_data;
    wire [`RECON_PHI_TAG_W-1:0] normalizer_output_tag;
    wire cgra_result_capture_start;
    wire cgra_result_capture_valid;
    wire [4:0] cgra_result_capture_index;
    wire [DATA_W-1:0] cgra_result_capture_data;
    wire cgra_result_capture_low_complete;
    wire cgra_result_capture_high_complete;
    wire cgra_result_consume_d18;
    wire cgra_result_consume_s27;
    cgra_result_capture_adapter u_result_capture (
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .vec_w_en(vec_w_en),
        .write_format(cfg_w_data[54:52]),
        .capture_start(phi_lane_capture_context),
        .normalizer_output_fire(phi_lane_normalizer_output_fire),
        .normalizer_output_tag(normalizer_output_tag),
        .normalizer_output_data(normalizer_output_data),
        .residual_mode(phi_lane_residual_mode),
        .row_block(phi_lane_row_block),
        .measurement_count(cfg_measurement_count),
        .measurement_buffer(phi_lane_measurement_buffer),
        .result_low_valid(cgra_result_low_valid),
        .result_high_valid(cgra_result_high_valid),
        .result_s27_high_select(cgra_s27_write_phase),
        .write_is_d18(write_is_d18),
        .write_is_s27(write_is_s27),
        .result_available(cgra_result_available),
        .capture_start_event(cgra_result_capture_start),
        .capture_valid(cgra_result_capture_valid),
        .capture_index(cgra_result_capture_index),
        .capture_data(cgra_result_capture_data),
        .capture_low_complete(cgra_result_capture_low_complete),
        .capture_high_complete(cgra_result_capture_high_complete),
        .consume_d18(cgra_result_consume_d18),
        .consume_s27(cgra_result_consume_s27)
    );
    vector_codec_write_subsystem u_vector_codec (
        .physical_a_valid(physical_vec_a_valid), .physical_a(physical_vec_a),
        .format_a(stream_a_element_format),
        .packing_a(stream_a_packing_mode),
        .physical_b_valid(physical_vec_b_valid), .physical_b(physical_vec_b),
        .format_b(stream_b_element_format),
        .packing_b(stream_b_packing_mode), .write_enable(vec_w_en),
        .write_config_valid(cfg_w_valid), .write_format(cfg_w_data[54:52]),
        .write_packing(cfg_w_data[57:55]), .write_is_d18(write_is_d18),
        .write_is_s27(write_is_s27),
        .cgra_result_available(cgra_result_available),
        .cgra_s27_high_select(cgra_s27_write_phase),
        .cgra_result(cgra_result_buffer), .lane_result(lane_result),
        .transpose_write_mode(transpose_write_mode),
        .scalar_pending(reduction_scalar_pending),
        .reduction_memory_context(reduction_memory_write_context),
        .scalar_pack(reduction_scalar_pack),
        .vector_result(selected_vector_result_data),
        .vector_result_ready(m5_vector_result_ready),
        .expanded_a(expanded_vec_a), .expanded_b(expanded_vec_b),
        .sidecar_valid_a(sidecar_valid_a),
        .sidecar_valid_b(sidecar_valid_b), .sidecar_a(sidecar_vec_a),
        .sidecar_b(sidecar_vec_b), .write_pack_valid(write_pack_valid),
        .write_pack_error(write_pack_error), .write_data(vector_write_data),
        .write_payload_ready(write_payload_ready)
    );

    wire vector_reduction_stream_begin = cycle_valid &&
        !resource_wait_for_result && resource_clear_before &&
        ((resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_DOT) ||
         (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ));
    wire write_payload_ready;
    assign m5_vector_result_ready = cycle_valid && vec_w_en && write_is_s27 &&
                                    !cgra_result_buffer_busy &&
                                    !phi_lane_normalize_active &&
                                     !transpose_write_mode &&
                                     (!support_coefficient_stripe_needed ||
                                      support_coefficient_stripe_buffer_valid) &&
                                     raw_vec_out_ready;

    vector_stream_engine u_stream_engine (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .cursor_restart_valid(cursor_restart_valid),
        .cursor_restart_mask(cursor_restart_mask),
        .cursor_restart_ready(cursor_restart_ready),
        .req_valid(vec_req_valid), .cycle_commit(vec_transport_commit),
        .vec_a_en(vec_a_en), .vec_b_en(vec_b_en), .vec_w_en(vec_w_en),
        .vec_a_restart(vector_reduction_stream_begin && vec_a_en),
        .vec_b_restart(vector_reduction_stream_begin && vec_b_en),
        .vec_cfg_a(vec_cfg_a), .vec_cfg_b(vec_cfg_b), .vec_cfg_w(vec_cfg_w),
        .cfg_a_valid(cfg_a_valid), .cfg_a(cfg_a_data),
        .cfg_b_valid(cfg_b_valid), .cfg_b(cfg_b_data),
        .cfg_w_valid(cfg_w_valid), .cfg_w(cfg_w_data),
        .vec_w_data(vector_write_data),
        .stream_in_ready(raw_vec_in_ready),
        .stream_out_ready(raw_vec_out_ready),
        .cfg_error(vec_cfg_error), .access_conflict(vec_access_conflict),
        .vec_a_valid(physical_vec_a_valid), .vec_a_data(physical_vec_a),
        .vec_a_metadata_valid(stream_a_metadata_valid),
        .vec_a_element_format(stream_a_element_format),
        .vec_a_packing_mode(stream_a_packing_mode),
        .vec_a_element_count(stream_a_element_count),
        .vec_b_valid(physical_vec_b_valid), .vec_b_data(physical_vec_b),
        .vec_b_metadata_valid(stream_b_metadata_valid),
        .vec_b_element_format(stream_b_element_format),
        .vec_b_packing_mode(stream_b_packing_mode),
        .sp0_valid(stream_p0_valid), .sp0_ready(stream_p0_ready),
        .sp0_write(stream_p0_write), .sp0_bank_mask(stream_p0_mask),
        .sp0_addr(stream_p0_addr), .sp0_wr_data(stream_p0_wr_data),
        .sp0_rd_valid(stream_p0_rd_valid),
        .sp0_rd_bank_mask(stream_p0_rd_mask), .sp0_rd_data(stream_p0_rd_data),
        .sp1_valid(stream_p1_valid), .sp1_ready(stream_p1_ready),
        .sp1_write(stream_p1_write), .sp1_bank_mask(stream_p1_mask),
        .sp1_addr(stream_p1_addr), .sp1_wr_data(stream_p1_wr_data),
        .sp1_rd_valid(stream_p1_rd_valid),
        .sp1_rd_bank_mask(stream_p1_rd_mask), .sp1_rd_data(stream_p1_rd_data),
        .sp_conflict(1'b0)
    );

    phi_stream_subsystem #(
        .USE_INTERNAL_CACHE(USE_INTERNAL_PHI_CACHE)
    ) u_phi_stream (
        .clk(clk),
        .rst_n(rst_n),
        .clear(run_start),
        .abort(run_abort),
        .seed(cfg_seed),
        .measurement_count(cfg_measurement_count),
        .signal_length(cfg_signal_length),
        .work_count(resident_count),
        .support_count(resident_count),
        .cmd_valid(phi_command_valid),
        .cmd_ready(phi_command_ready),
        .cmd_op(phi_command),
        .cmd_cfg_id(phi_cfg_id),
        .cfg_valid(phi_cfg_valid),
        .cfg_data(phi_cfg_data),
        .support_valid(phi_support_valid),
        .support_ready(phi_support_ready),
        .support_col(phi_support_col),
        .refill_pending(phi_cache_refill_pending),
        .refill_start(phi_refill_start),
        .refill_support_count(phi_cache_refill_support_count),
        .refill_support_valid(phi_cache_refill_column_valid),
        .refill_support_ready(phi_cache_refill_column_ready),
        .refill_support_col(phi_cache_refill_column),
        .cache_req_valid(phi_cache_req_valid),
        .cache_req_ready(phi_cache_req_ready),
        .cache_req_slot(phi_cache_req_slot),
        .cache_req_row(phi_cache_req_row),
        .cache_req_tag(phi_cache_req_tag),
        .cache_rsp_valid(phi_cache_rsp_valid),
        .cache_rsp_ready(phi_cache_rsp_ready),
        .cache_rsp_mask(phi_cache_rsp_mask),
        .cache_rsp_sign(phi_cache_rsp_sign),
        .cache_rsp_col(phi_cache_rsp_col),
        .cache_rsp_row(phi_cache_rsp_row),
        .cache_rsp_tag(phi_cache_rsp_tag),
        .cache_ext_valid(phi_cache_ext_valid),
        .cache_invalidate(phi_cache_invalidate || phi_cache_clear || run_abort),
        .cache_prepare_valid(phi_cache_prepare_valid),
        .cache_prepare_ready(phi_cache_prepare_ready),
        .cache_prepare_from_candidates(phi_cache_prepare_from_candidates),
        .cache_prepare_support_count(phi_cache_prepare_support_count),
        .cache_prepare_preserve_count(phi_cache_prepare_preserve_count),
        .cache_candidate_valid(candidate_store_valid),
        .cache_candidate_ready(candidate_store_ready),
        .cache_candidate_slot(candidate_store_slot),
        .cache_candidate_col(candidate_store_column),
        .cache_release_event(phi_release_event),
        .cache_release_event_col(phi_release_event_col),
        .cache_promote_valid(phi_cache_promote_valid),
        .cache_promote_ready(phi_cache_promote_ready),
        .cache_promote_candidate_slot(phi_cache_promote_candidate_slot),
        .cache_promote_support_slot(phi_cache_promote_support_slot),
        .cache_capture_ready(phi_capture_ready),
        .cache_fill_fire(profile_phi_cache_fill_fire),
        .event_generate_request_fire(profile_phi_generate_fire),
        .event_replay_request_fire(profile_phi_replay_request_fire),
        .event_replay_response_fire(profile_phi_replay_response_fire),
        .out_valid(phi_symbol_valid),
        .out_ready(router_phi_symbol_ready),
        .out_mask(phi_nonzero),
        .out_sign(phi_sign),
        .out_col(phi_column),
        .out_row(phi_row_block),
        .out_tag(phi_tag),
        .out_fire(phi_symbol_fire),
        .status_busy(phi_busy),
        .status_done(phi_done),
        .status_cfg_error(phi_cfg_error),
        .status_mode(phi_mode),
        .status_refill_active(phi_refill_active),
        .status_capture_enable(phi_capture_enable),
        .status_cache_valid(phi_cache_valid),
        .status_cache_busy(),
        .status_cache_fault(phi_cache_fault)
    );

    wire scalar_broadcast_valid;
    wire signed [DATA_W-1:0] scalar_broadcast_data;
    wire vector_topk_support_slot_mode;
    wire vector_support_scatter_mode;
    wire vector_candidate_mode;
    wire vector_candidate_valid;
    wire signed [DATA_W-1:0] vector_candidate_score;
    wire [9:0] vector_candidate_index;
    wire vector_candidate_fault;
    wire vector_candidate_final_lane;
    wire dispatcher_candidate_ready;
    candidate_stream_adapter u_candidate_stream (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .cycle_valid(cycle_valid), .resource_operation(resource_operation),
        .resource_wait_for_result(resource_wait_for_result),
        .resource_input_select(resource_input_select),
        .resource_configuration_id(resource_configuration_id),
        .vec_a_en(vec_a_en), .stream_metadata_valid(stream_a_metadata_valid),
        .stream_element_format(stream_a_element_format),
        .stream_packing_mode(stream_a_packing_mode),
        .signal_length(cfg_signal_length), .work_count(resident_count),
        .stripe_valid(physical_vec_a_valid),
        .stripe_lane_valid(sidecar_valid_a), .stripe_data(sidecar_vec_a),
        .support_indices(active_support_indices),
        .candidate_ready(dispatcher_candidate_ready),
        .mode_active(vector_candidate_mode),
        .support_scatter_mode(vector_support_scatter_mode),
        .topk_support_slot_mode(vector_topk_support_slot_mode),
        .candidate_valid(vector_candidate_valid),
        .candidate_score(vector_candidate_score),
        .candidate_index(vector_candidate_index),
        .candidate_fault(vector_candidate_fault),
        .candidate_final_lane(vector_candidate_final_lane)
    );
    wire support_scalar_mode;
    wire d18_split_mode;
    wire d18_split_valid;
    wire [15:0] d18_split_lane_valid;
    wire [16*DATA_W-1:0] d18_split_solver_data;
    wire scalar_router_a_valid;
    wire signed [DATA_W-1:0] scalar_router_a_data;
    wire scalar_router_b_valid;
    wire signed [DATA_W-1:0] scalar_router_b_data;
    wire [32*DATA_W-1:0] router_vector_a;
    wire router_vector_a_valid;
    wire vec_transport_commit;
    vector_ingress_adapter u_vector_ingress (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort),
        .restart(cursor_restart_valid && cursor_restart_mask[0]),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .vector_cycle_commit(vec_cycle_commit),
        .vector_a_enable(vec_a_en), .vector_b_enable(vec_b_en),
        .vector_write_enable(vec_w_en),
        .stream_a_metadata_valid(stream_a_metadata_valid),
        .stream_a_format(stream_a_element_format),
        .stream_a_packing(stream_a_packing_mode),
        .stream_b_metadata_valid(stream_b_metadata_valid),
        .stream_b_format(stream_b_element_format),
        .stream_b_packing(stream_b_packing_mode),
        .external_a_select(ext_a_sel), .resource_operation(resource_operation),
        .tile_operation(active_tile_operation), .phi_mode(phi_mode),
        .measurement_count(cfg_measurement_count),
        .work_count(resident_count),
        .physical_a_valid(physical_vec_a_valid),
        .physical_b_valid(physical_vec_b_valid), .expanded_a(expanded_vec_a),
        .sidecar_a_valid(sidecar_valid_a), .sidecar_b_valid(sidecar_valid_b),
        .sidecar_a(sidecar_vec_a), .sidecar_b(sidecar_vec_b),
        .scalar_broadcast_valid(scalar_broadcast_valid),
        .scalar_broadcast_data(scalar_broadcast_data),
        .candidate_mode(vector_candidate_mode),
        .candidate_valid(vector_candidate_valid),
        .candidate_ready(dispatcher_candidate_ready),
        .candidate_final_lane(vector_candidate_final_lane),
        .transpose_write_mode(transpose_write_mode),
        .transpose_write_release(transpose_write_release),
        .support_mode(support_scalar_mode), .d18_mode(d18_split_mode),
        .d18_valid(d18_split_valid), .d18_lane_valid(d18_split_lane_valid),
        .d18_solver_data(d18_split_solver_data),
        .scalar_a_valid(scalar_router_a_valid),
        .scalar_a_data(scalar_router_a_data),
        .scalar_b_valid(scalar_router_b_valid),
        .scalar_b_data(scalar_router_b_data),
        .vector_a_valid(router_vector_a_valid),
        .vector_a_data(router_vector_a),
        .transport_commit(vec_transport_commit)
    );
    wire [32*`RECON_LOCAL_ACC_W-1:0] lane_accumulator;
    wire [32*ACC_W-1:0] reduction_lane_data;
    wire [1:0] cgra_saturation;
    wire [1:0] cgra_contract_error;
    cgra_execution_fabric #(
        .FULL_PE_MASK(CGRA_FULL_PE_MASK)
    ) u_cgra_fabric (
        .clk(clk),
        .rst_n(rst_n),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .array_ctx(ctx_array),
        .tile_ctx(ctx_tile),
        .predicate_values(ctx_predicates),
        .stream_ctx(ctx_stream),
        .vec_req_valid(vec_req_valid),
        .vec_cycle_commit(vec_cycle_commit),
        .vec_a_en(vec_a_en),
        .vec_b_en(vec_b_en),
        .vec_w_en(vec_w_en),
        .vec_cfg_a(vec_cfg_a_raw),
        .vec_cfg_b(vec_cfg_b),
        .vec_cfg_w(vec_cfg_w),
        .vec_in_ready(raw_vec_in_ready),
        .vec_out_ready(raw_vec_out_ready && write_payload_ready),
        .vec_cfg_error(vec_cfg_error),
        .vec_access_conflict(vec_access_conflict),
        .vector_a_valid(router_vector_a_valid),
        .vector_a_data(router_vector_a),
        .vector_b_valid(physical_vec_b_valid),
        .vector_b_data(expanded_vec_b),
        .scalar_a_valid(scalar_router_a_valid),
        .scalar_a_data(scalar_router_a_data),
        .scalar_b_valid(scalar_router_b_valid),
        .scalar_b_data(scalar_router_b_data),
        .ext_a_sel(ext_a_sel),
        .ext_b_sel(ext_b_sel),
        .external_input_a(external_input_a),
        .phi_command_valid(phi_command_valid),
        .phi_command_ready(phi_command_ready),
        .phi_command(phi_command),
        .phi_cfg_id(phi_cfg_id),
        .phi_cfg_valid(phi_cfg_valid),
        .phi_symbol_valid(phi_symbol_valid),
        .phi_symbol_ready(router_phi_symbol_ready),
        .phi_nonzero(phi_nonzero),
        .phi_sign(phi_sign),
        .stream_in_ready(router_stream_in_ready),
        .stream_out_ready(router_stream_out_ready),
        .stream_contract_error(stream_contract_error),
        .result_clear_event(run_start || run_abort),
        .result_capture_start_event(cgra_result_capture_start),
        .result_capture_valid(cgra_result_capture_valid),
        .result_capture_index(cgra_result_capture_index),
        .result_capture_data(cgra_result_capture_data),
        .result_capture_low_complete(cgra_result_capture_low_complete),
        .result_capture_high_complete(cgra_result_capture_high_complete),
        .result_consume_d18_event(cgra_result_consume_d18),
        .result_consume_s27_event(cgra_result_consume_s27),
        .result_data(cgra_result_buffer),
        .result_low_valid(cgra_result_low_valid),
        .result_high_valid(cgra_result_high_valid),
        .result_s27_high_select(cgra_s27_write_phase),
        .result_busy(cgra_result_buffer_busy),
        .lane_result(lane_result),
        .lane_accumulator(lane_accumulator),
        .reduction_lane_data(reduction_lane_data),
        .lane_result_valid(lane_result_valid),
        .saturation_event(cgra_saturation),
        .contract_error(cgra_contract_error)
    );

    wire [159:0] cluster0_lane_index;
    wire [159:0] cluster1_lane_index;
    genvar lane_index;
    generate
        for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin : g_index
            assign cluster0_lane_index[lane_index*10 +: 10] = lane_index;
            assign cluster1_lane_index[lane_index*10 +: 10] = lane_index + 16;
        end
    endgenerate

    wire m5_cycle_valid;
    wire m5_cycle_commit;
    wire m5_resource_in_ready;
    wire m5_resource_out_ready;
    wire m5_resource_contract_error;
    wire reduction_result_valid;
    wire signed [ACC_W-1:0] reduction_result_data;
    wire [9:0] reduction_result_index;
    wire reduction_result_fault;
    wire m5_saturation_event;
    wire m5_fault_valid;
    wire [7:0] m5_fault_code;
    wire [15:0] m5_fault_detail;
    wire m5_scalar0_valid;
    wire signed [ACC_W-1:0] m5_scalar0_data;
    wire m5_scalar1_valid;
    wire signed [ACC_W-1:0] m5_scalar1_data;
    wire normalizer_input_ready;
    wire reduction_response_ready;
    wire reduction_accept;
    wire column_normalizer_request_valid;
    wire signed [ACC_W-1:0] column_normalizer_request_data;
    wire [`RECON_PHI_TAG_W-1:0] column_normalizer_request_tag;
    wire [`RECON_PHI_SCALE_MANTISSA_W-1:0]
        column_normalizer_request_mantissa;
    wire [`RECON_PHI_SCALE_EXPONENT_W-1:0]
        column_normalizer_request_exponent;
    wire column_normalizer_request_is_data18;
    wire normalized_candidate_ready;
    wire selected_candidate_valid;
    wire signed [DATA_W-1:0] selected_candidate_score;
    wire [9:0] selected_candidate_index;
    wire selected_candidate_saturated;
    assign profile_selection_fire = selected_candidate_valid &&
        dispatcher_candidate_ready;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] completed_row_major_row_block;
    wire phi_stream_order_error_now;
    wire phi_order_error;
    wire reduction_source_missing;

    wire scalar_preload_ready_raw;
    wire algorithm_preload_seen;
    resident_execution_state u_resident_state (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort), .scalar_state_clear(scalar_clear),
        .scalar_preload_valid(scalar_load_valid),
        .scalar_preload_accept(scalar_preload_ready_raw),
        .configured_work_count(cfg_work_count),
        .active_support_count(active_support_count),
        .scalar_preload_ready(scalar_load_ready),
        .algorithm_preload_seen(algorithm_preload_seen),
        .resident_work_count(resident_count)
    );

    m5_arithmetic_subsystem u_m5 (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .scalar_state_clear(scalar_clear),
        .scalar_preload_valid(scalar_load_valid),
        .scalar_preload_ready(scalar_preload_ready_raw),
        .scalar_preload_address(scalar_load_select),
        .scalar_preload_data(scalar_load_data),
        .fused_scalar_valid(fused_scalar_valid),
        .fused_scalar_ready(fused_scalar_ready),
        .fused_scalar_address(1'b1),
        .fused_scalar_data(fused_scalar_data),
        .fused_scalar_is_gamma(fused_scalar_is_gamma),
        .cycle_valid(m5_cycle_valid), .cycle_commit(m5_cycle_commit),
        .resource_ctx(ctx_resource),
        .reduction_lane_valid_pair(
            measurement_lane_mask(cfg_measurement_count)),
        .cluster0_lane_data(reduction_lane_data[0 +: 16*ACC_W]),
        .cluster1_lane_data(reduction_lane_data[16*ACC_W +: 16*ACC_W]),
        .cluster0_lane_index(cluster0_lane_index),
        .cluster1_lane_index(cluster1_lane_index),
        .vector_lane_valid(d18_split_mode ? d18_split_lane_valid :
                          (sidecar_valid_a | sidecar_valid_b)),
        .vector_a(d18_split_mode ? d18_split_solver_data : sidecar_vec_a),
        .vector_b(sidecar_vec_b),
        .vector_result_ready(m5_vector_result_ready),
        .reduction_result_ready(reduction_response_ready),
        .vector_result_valid(vector_result_valid),
        .vector_result_lane_valid(vector_result_lane_valid),
        .vector_result_data(vector_result_data),
        .scalar0_valid(m5_scalar0_valid), .scalar0_data(m5_scalar0_data),
        .scalar1_valid(m5_scalar1_valid), .scalar1_data(m5_scalar1_data),
        .scalar_broadcast_valid(scalar_broadcast_valid),
        .scalar_broadcast_data(scalar_broadcast_data),
        .reduction_result_valid(reduction_result_valid),
        .reduction_result_data(reduction_result_data),
        .reduction_result_index(reduction_result_index),
        .reduction_result_fault(reduction_result_fault),
        .event_valid(), .event_id(), .result_index(),
        .divide_by_zero_event(), .saturation_event(m5_saturation_event),
        .fault_valid(m5_fault_valid), .fault_code(m5_fault_code),
        .fault_detail(m5_fault_detail),
        .resource_in_ready(m5_resource_in_ready),
        .resource_out_ready(m5_resource_out_ready),
        .resource_contract_error(m5_resource_contract_error)
    );

    wire phi_consume_context =
        ctx_stream[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                   `RECON_STREAM_FIELD_PHI_COMMAND_W] ==
        `RECON_PHI_COMMAND_CONSUME;
    wire phi_stop_context =
        ctx_stream[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                   `RECON_STREAM_FIELD_PHI_COMMAND_W] ==
        `RECON_PHI_COMMAND_STOP;
    wire phi_start_fire = phi_command_valid && phi_command_ready &&
        (phi_command == `RECON_PHI_COMMAND_START);
    assign observed_phi_column = phi_column;
    assign observed_phi_row_block = phi_row_block;
    wire normalizer_output_valid;
    wire normalizer_output_ready;
    wire phi_lane_capture_context;
    wire phi_lane_normalizer_input_valid;
    wire signed [`RECON_LOCAL_ACC_W-1:0] phi_lane_selected_accumulator;
    wire normalizer_output_saturated;
    wire normalized_candidate_fire;
    wire phi_lane_normalizer_output_fire;
    phi_lane_normalization_flow u_phi_lane_flow (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort), .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .tile_operation(active_tile_operation),
        .phi_start_fire(phi_start_fire), .phi_start_mode(phi_cfg_data[51:49]),
        .phi_mode(phi_mode), .phi_row_block(phi_row_block),
        .completed_row_block(completed_row_major_row_block),
        .measurement_count(cfg_measurement_count),
        .work_count(resident_count), .lane_accumulator(lane_accumulator),
        .measurement_vector(external_input_a),
        .column_request_valid(column_normalizer_request_valid),
        .column_request_data(column_normalizer_request_data),
        .column_request_tag(column_normalizer_request_tag),
        .column_request_mantissa(column_normalizer_request_mantissa),
        .column_request_exponent(column_normalizer_request_exponent),
        .column_request_is_data18(column_normalizer_request_is_data18),
        .normalizer_memory_mode(normalizer_memory_mode),
        .memory_output_ready(transpose_normalizer_ready),
        .vector_candidate_mode(vector_candidate_mode),
        .candidate_output_ready(normalized_candidate_ready),
        .memory_output_count(reduction_output_count),
        .fused_scalar_ready(fused_scalar_ready),
        .normalizer_input_ready(normalizer_input_ready),
        .normalizer_output_valid(normalizer_output_valid),
        .normalizer_output_ready(normalizer_output_ready),
        .normalizer_output_data(normalizer_output_data),
        .normalizer_output_tag(normalizer_output_tag),
        .normalizer_output_saturated(normalizer_output_saturated),
        .normalized_candidate_fire(normalized_candidate_fire),
        .capture_event(phi_lane_capture_context),
        .lane_input_valid(phi_lane_normalizer_input_valid),
        .lane_output_fire(phi_lane_normalizer_output_fire),
        .lane_active(phi_lane_normalize_active),
        .residual_mode(phi_lane_residual_mode),
        .issue_count(phi_lane_issue_count),
        .output_count(phi_lane_output_count),
        .row_block(phi_lane_row_block),
        .accumulator_buffer(phi_lane_accumulator_buffer),
        .measurement_buffer(phi_lane_measurement_buffer),
        .selected_accumulator(phi_lane_selected_accumulator),
        .fused_scalar_valid(fused_scalar_valid),
        .fused_scalar_is_gamma(fused_scalar_is_gamma),
        .fused_scalar_data(fused_scalar_data)
    );

    wire dispatcher_resource_in_ready;
    wire dispatcher_resource_out_ready;
    wire dispatcher_contract_error;
    wire selection_fault_valid;
    m8_resource_dispatcher u_dispatcher (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .scalar_state_clear(scalar_clear),
        .algorithm_preload_seen(algorithm_preload_seen),
        .selection_k(cfg_selection_k), .active_work_count(resident_count),
        .active_measurement_count(cfg_measurement_count),
        .active_refinement_profile(cfg_refinement_profile),
        .active_refine_limit(cfg_refine_limit),
        .active_normal_residual_shift(cfg_normal_residual_shift),
        .active_residual_limit(cfg_residual_limit),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .resource_ctx(ctx_resource),
        .m5_cycle_valid(m5_cycle_valid), .m5_cycle_commit(m5_cycle_commit),
        .m5_resource_in_ready(m5_resource_in_ready),
        .m5_resource_out_ready(m5_resource_out_ready),
        .m5_resource_contract_error(m5_resource_contract_error),
        .m5_scalar0_valid(m5_scalar0_valid), .m5_scalar0_data(m5_scalar0_data),
        .m5_scalar1_valid(m5_scalar1_valid), .m5_scalar1_data(m5_scalar1_data),
        .m5_refinement_breakdown(m5_fault_valid),
        .m5_refinement_saturation(m5_saturation_event),
        .transport_restart_ready(cursor_restart_ready),
        .transport_restart_valid(cursor_restart_valid),
        .transport_restart_mask(cursor_restart_mask),
        .candidate_valid(selected_candidate_valid),
        .candidate_ready(dispatcher_candidate_ready),
        .candidate_score(selected_candidate_score),
        .candidate_index(selected_candidate_index),
        .candidate_saturated(selected_candidate_saturated),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .phi_cache_prepare_valid(phi_cache_prepare_valid),
        .phi_cache_prepare_ready(phi_cache_prepare_ready),
        .phi_cache_prepare_from_candidates(phi_cache_prepare_from_candidates),
        .phi_cache_prepare_support_count(phi_cache_prepare_support_count),
        .phi_cache_prepare_preserve_count(phi_cache_prepare_preserve_count),
        .phi_cache_promote_valid(phi_cache_promote_valid),
        .phi_cache_promote_ready(phi_cache_promote_ready),
        .phi_cache_promote_candidate_slot(phi_cache_promote_candidate_slot),
        .phi_cache_promote_support_slot(phi_cache_promote_support_slot),
        .phi_cache_valid(phi_cache_valid),
        .phi_cache_fault(phi_cache_fault),
        .phi_cache_invalidate(phi_cache_invalidate),
        .phi_cache_refill_pending(phi_cache_refill_pending),
        .phi_cache_refill_support_count(phi_cache_refill_support_count),
        .phi_cache_refill_column_valid(phi_cache_refill_column_valid),
        .phi_cache_refill_column_ready(phi_cache_refill_column_ready),
        .phi_cache_refill_column_slot(phi_cache_refill_column_slot),
        .phi_cache_refill_column(phi_cache_refill_column),
        .resource_in_ready(dispatcher_resource_in_ready),
        .resource_out_ready(dispatcher_resource_out_ready),
        .resource_contract_error(dispatcher_contract_error),
        .selection_fault_valid(selection_fault_valid),
        .support_remap_event_valid(support_remap_event_valid),
        .support_remap_event_fault(support_remap_event_fault),
        .support_remap_dropped_count(support_remap_dropped_count),
        .support_remap_dropped_indices(support_remap_dropped_indices),
        .support_remap_dropped_coefficients(support_remap_dropped_coefficients),
        .active_support_bitmap(active_support_bitmap),
        .active_support_indices(active_support_indices),
        .active_support_coefficients(active_support_coefficients),
        .support_coefficient_stripe_read_enable(
            support_coefficient_stripe_read_enable),
        .support_coefficient_stripe_read_index(
            support_coefficient_stripe_read_index),
        .support_coefficient_stripe_read_valid(
            support_coefficient_stripe_response_valid),
        .support_coefficient_stripe_read_coefficients(
            support_coefficient_stripe_response_coefficients),
        .active_support_gradients(active_support_gradients),
        .active_support_gradient_valid(active_support_gradient_valid),
        .active_support_count(active_support_count),
        .refinement_event_valid(refinement_event_valid),
        .refinement_certificate_pass(refinement_certificate_pass),
        .refinement_restart_required(refinement_restart_required),
        .refinement_recompute_required(refinement_recompute_required),
        .refinement_replacement_required(refinement_replacement_required),
        .refinement_iteration_advance(refinement_iteration_advance),
        .refinement_stop_reason(refinement_stop_reason),
        .termination_event_valid(termination_event_valid),
        .termination_residual_limit_reached(
            termination_residual_limit_reached),
        .termination_residual_sq(termination_residual_sq),
        .selection_count(selection_count),
        .result_scores(result_scores), .result_indices(result_indices)
    );

    wire reduction_issue_context = cycle_valid &&
        (resource_operation == `RECON_RESOURCE_OP_REDUCE_SUM) &&
        resource_wait_for_ready && !resource_wait_for_result;
    phi_column_flow u_column_flow (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort), .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .phi_start_fire(phi_start_fire),
        .phi_consume_context(phi_consume_context),
        .phi_stop_context(phi_stop_context),
        .phi_symbol_valid(phi_symbol_valid), .phi_symbol_fire(phi_symbol_fire),
        .phi_refill_active(phi_refill_active), .phi_mode(phi_mode),
        .phi_column(phi_column), .phi_row_block(phi_row_block),
        .measurement_count(cfg_measurement_count),
        .work_count(resident_count),
        .reduction_issue_context(reduction_issue_context),
        .reduction_result_valid(reduction_result_valid),
        .reduction_result_data(reduction_result_data),
        .normalizer_input_ready(normalizer_input_ready),
        .normalizer_memory_mode(normalizer_memory_mode),
        .phi_lane_normalize_active(phi_lane_normalize_active),
        .normalizer_mantissa(cfg_phi_scale_mantissa_uq17),
        .normalizer_exponent(cfg_phi_scale_exponent),
        .normalized_candidate_fire(normalized_candidate_fire),
        .normalized_candidate_score(normalizer_output_data),
        .normalized_candidate_saturated(normalizer_output_saturated),
        .vector_candidate_mode(vector_candidate_mode),
        .vector_candidate_valid(vector_candidate_valid),
        .vector_candidate_fault(vector_candidate_fault),
        .vector_candidate_score(vector_candidate_score),
        .vector_candidate_index(vector_candidate_index),
        .dispatcher_candidate_ready(dispatcher_candidate_ready),
        .reduction_result_ready(reduction_response_ready),
        .reduction_accept(reduction_accept),
        .reduction_column_available(),
        .reduction_source_missing(reduction_source_missing),
        .normalizer_request_valid(column_normalizer_request_valid),
        .normalizer_request_data(column_normalizer_request_data),
        .normalizer_request_tag(column_normalizer_request_tag),
        .normalizer_request_mantissa(column_normalizer_request_mantissa),
        .normalizer_request_exponent(column_normalizer_request_exponent),
        .normalizer_request_is_data18(
            column_normalizer_request_is_data18),
        .normalized_candidate_ready(normalized_candidate_ready),
        .selected_candidate_valid(selected_candidate_valid),
        .selected_candidate_score(selected_candidate_score),
        .selected_candidate_index(selected_candidate_index),
        .selected_candidate_saturated(selected_candidate_saturated),
        .candidate_release_event(phi_release_event),
        .candidate_release_column(phi_release_event_col),
        .completed_row_major_row_block(completed_row_major_row_block),
        .order_error_now(phi_stream_order_error_now),
        .order_error(phi_order_error)
    );
    wire reduction_to_memory_accept = reduction_accept &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM);
    normalized_result_writeback u_normalized_writeback (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort), .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .vector_write_enable(vec_w_en),
        .write_format(cfg_w_data[54:52]),
        .resource_operation(resource_operation),
        .resource_wait_for_result(resource_wait_for_result),
        .resource_output_select(resource_output_select), .phi_mode(phi_mode),
        .signal_length(cfg_signal_length), .work_count(resident_count),
        .reduction_accept(reduction_to_memory_accept),
        .normalizer_output_valid(normalizer_output_valid),
        .normalizer_output_data(normalizer_output_data),
        .normalizer_memory_mode(normalizer_memory_mode),
        .normalizer_ready(transpose_normalizer_ready),
        .reduction_memory_context(reduction_memory_write_context),
        .write_mode(transpose_write_mode),
        .write_final(transpose_write_final),
        .write_release(transpose_write_release),
        .scalar_pending(reduction_scalar_pending),
        .scalar_pack(reduction_scalar_pack),
        .pack_index(reduction_pack_index),
        .output_count(reduction_output_count)
    );
    wire [8:0] padded_measurement_count;
    wire fault_event;
    wire [15:0] fault_event_detail;
    operator_fault_event_encoder u_fault_encoder (
        .measurement_count(cfg_measurement_count),
        .stream_contract_error(stream_contract_error),
        .dispatcher_contract_error(dispatcher_contract_error),
        .phi_config_error(phi_cfg_error),
        .cgra_contract_error(cgra_contract_error),
        .cgra_saturation(cgra_saturation),
        .m5_saturation_event(m5_saturation_event),
        .m5_fault_valid(m5_fault_valid),
        .reduction_result_valid(reduction_result_valid),
        .reduction_result_fault(reduction_result_fault),
        .lane_normalizer_output_fire(phi_lane_normalizer_output_fire),
        .normalizer_output_saturated(normalizer_output_saturated),
        .selection_fault_valid(selection_fault_valid),
        .write_pack_error(write_pack_error),
        .scratch_init_valid(scratch_init_valid),
        .scratch_preload_active(scratch_load_active),
        .scratch_preload_p0_valid(scratch_load_p0_valid),
        .scratch_preload_p1_valid(scratch_load_p1_valid),
        .execution_active(execution_active),
        .support_scalar_mode(support_scalar_mode),
        .stream_a_element_count(stream_a_element_count),
        .resident_work_count(resident_count),
        .stream_scratch_conflict(stream_scratch_conflict),
        .vector_candidate_mode(vector_candidate_mode),
        .vector_support_scatter_mode(vector_support_scatter_mode),
        .vector_topk_support_slot_mode(vector_topk_support_slot_mode),
        .signal_length(cfg_signal_length),
        .vector_candidate_fault(vector_candidate_fault), .phi_mode(phi_mode),
        .phi_consume_context(phi_consume_context), .vec_a_enable(vec_a_en),
        .external_a_select(ext_a_sel), .config_a_valid(cfg_a_valid),
        .config_a_data(cfg_a_data),
        .reduction_source_missing(reduction_source_missing),
        .phi_stream_order_error_now(phi_stream_order_error_now),
        .phi_order_error(phi_order_error), .phi_cache_fault(phi_cache_fault),
        .padded_measurement_count(padded_measurement_count),
        .fault_event(fault_event), .fault_event_detail(fault_event_detail)
    );
    operator_fault_monitor u_fault_monitor (
        .clk(clk), .rst_n(rst_n), .routine_start(run_start),
        .abort_flush(run_abort), .fault_event(fault_event),
        .fault_event_detail(fault_event_detail),
        .fault_active(operator_fault), .fault_detail(operator_fault_detail)
    );
    operator_flow_control u_flow_control (
        .operator_fault(operator_fault),
        .phi_capture_enable(phi_capture_enable), .cycle_valid(cycle_valid),
        .phi_consume_context(phi_consume_context),
        .phi_symbol_valid(phi_symbol_valid), .phi_capture_ready(phi_capture_ready),
        .d18_split_mode(d18_split_mode), .d18_split_valid(d18_split_valid),
        .vector_candidate_mode(vector_candidate_mode),
        .vector_candidate_valid(vector_candidate_valid),
        .router_stream_in_ready(router_stream_in_ready),
        .router_stream_out_ready(router_stream_out_ready),
        .dispatcher_resource_in_ready(dispatcher_resource_in_ready),
        .dispatcher_resource_out_ready(dispatcher_resource_out_ready),
        .stream_input_ready(stream_input_ready),
        .stream_output_ready(stream_output_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid)
    );

`ifdef FORMAL
    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid) begin
            if (cycle_commit)
                assert(stream_input_ready && stream_output_ready &&
                       resource_req_ready && resource_rsp_valid);
            if (scratch_init_valid)
                assert(!execution_active);
            if (scratch_load_active || scratch_load_p0_valid ||
                    scratch_load_p1_valid)
                assert(!execution_active);
            if (dispatcher_candidate_ready)
                assert(cycle_commit && selected_candidate_valid);
        end
    end
`endif
endmodule

`default_nettype wire
