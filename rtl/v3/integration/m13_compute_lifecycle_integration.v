`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "reconstruction_control_defs.vh"

module m13_compute_lifecycle_integration #(
    parameter integer AXIL_AW = 12,
    parameter integer TAG_W = 8,
    parameter integer TRACE_ENABLE = 0
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [AXIL_AW-1:0] s_axi_awaddr,
    input  wire s_axi_awvalid,
    output wire s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0] s_axi_wstrb,
    input  wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input  wire s_axi_bready,
    input  wire [AXIL_AW-1:0] s_axi_araddr,
    input  wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input  wire s_axi_rready,
    output wire irq,

    input  wire [AXIL_AW-1:0] s_loader_axi_awaddr,
    input  wire s_loader_axi_awvalid,
    output wire s_loader_axi_awready,
    input  wire [31:0] s_loader_axi_wdata,
    input  wire [3:0] s_loader_axi_wstrb,
    input  wire s_loader_axi_wvalid,
    output wire s_loader_axi_wready,
    output wire [1:0] s_loader_axi_bresp,
    output wire s_loader_axi_bvalid,
    input  wire s_loader_axi_bready,
    input  wire [AXIL_AW-1:0] s_loader_axi_araddr,
    input  wire s_loader_axi_arvalid,
    output wire s_loader_axi_arready,
    output wire [31:0] s_loader_axi_rdata,
    output wire [1:0] s_loader_axi_rresp,
    output wire s_loader_axi_rvalid,
    input  wire s_loader_axi_rready,

    input  wire [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0]
        predicate_values,

    input  wire compute_dma_done,

    input  wire [1:0] aux_req_valid,
    output wire [1:0] aux_req_ready,
    input  wire [1:0] aux_req_write,
    input  wire [2*64-1:0] aux_req_addr,
    input  wire [2*16-1:0] aux_req_bytes,
    input  wire [2*TAG_W-1:0] aux_req_tag,
    input  wire [1:0] aux_wr_valid,
    output wire [1:0] aux_wr_ready,
    input  wire [2*128-1:0] aux_wr_data,
    input  wire [2*16-1:0] aux_wr_keep,
    input  wire [1:0] aux_wr_last,
    output wire [1:0] aux_rd_valid,
    input  wire [1:0] aux_rd_ready,
    output wire [2*128-1:0] aux_rd_data,
    output wire [1:0] aux_rd_last,
    output wire [2*2-1:0] aux_rd_resp,
    output wire [2*TAG_W-1:0] aux_rd_tag,
    output wire [1:0] aux_done_valid,
    input  wire [1:0] aux_done_ready,
    output wire [2*TAG_W-1:0] aux_done_tag,
    output wire [1:0] aux_done_error,
    output wire [2*2-1:0] aux_done_resp,
    output wire [2*9-1:0] aux_done_beat,

    output wire [63:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input  wire m_axi_arready,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0] m_axi_rresp,
    input  wire m_axi_rlast,
    input  wire m_axi_rvalid,
    output wire m_axi_rready,
    output wire [63:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input  wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,
    input  wire [1:0] m_axi_bresp,
    input  wire m_axi_bvalid,
    output wire m_axi_bready,

    output wire engine_busy,
    output wire phase_active,
    output wire execution_active,
    output wire writeback_active,
    output wire [2:0] lifecycle_state,
    output wire active_image_ok,
    output wire [8:0] active_context_count,
    output wire operator_fault,
    output wire [15:0] operator_fault_detail,
    output wire [63:0] profile_total_cycles,
    output wire [63:0] profile_phase_cycles,
    output wire [63:0] profile_execution_cycles,
    output wire [63:0] profile_array_commit_cycles,
    output wire [63:0] profile_array_stall_cycles,
    output wire [63:0] profile_useful_pe_cycles,
    output wire [63:0] profile_useful_pe_slots,
    output wire [63:0] profile_resource_stall_cycles,
    output wire [63:0] profile_phi_generate_requests,
    output wire [63:0] profile_phi_replay_requests,
    output wire [63:0] profile_phi_replay_responses,
    output wire [63:0] profile_phi_cache_fills,
    output wire [63:0] profile_phi_output_symbols,
    output wire [63:0] profile_selection_accepts,
    output wire [63:0] profile_dma_read_requests,
    output wire [63:0] profile_dma_read_beats,
    output wire [63:0] profile_dma_write_requests,
    output wire [63:0] profile_dma_write_beats,
    output wire [63:0] profile_dma_write_responses,
    output wire [63:0] profile_result_drain_cycles,
    output wire [63:0] profile_result_drain_beats,
    output wire [6:0] final_support_count,
    output wire [`RECON_K_MAX*10-1:0] final_support_indices,
    output wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0]
        final_support_coefficients
);
    wire phase_rd_en;
    wire [7:0] phase_rd_addr;
    wire phase_rd_resp_valid;
    wire phase_rd_valid;
    wire [7:0] phase_rd_pc;
    wire [35:0] phase_word;
    wire array_launch_valid;
    wire array_launch_ready;
    wire sequencer_launch_ready;
    wire [7:0] array_entry_pc;
    wire [3:0] array_event_id;
    wire array_done_valid;
    wire array_done_ready;
    wire [3:0] array_done_event_id;
    wire array_done_aborted;
    wire array_fault_valid;
    wire array_fault_ready;
    wire [7:0] array_fault_code;
    wire [7:0] array_fault_pc;
    wire [31:0] array_fault_detail;
    wire compute_abort_pending;

    wire img_finalize_valid;
    wire img_finalize_ready;
    wire img_finalize_bank;
    wire img_finalize_resp_valid;
    wire img_finalize_resp_ready;
    wire img_finalize_resp_error;
    wire [7:0] img_finalize_resp_code;
    wire [31:0] img_finalize_resp_detail;
    wire img_wr_valid;
    wire img_wr_ready;
    wire img_wr_bank;
    wire [3:0] img_wr_plane;
    wire [7:0] img_wr_addr;
    wire [2*`RECON_TILE_CONTEXT_W-1:0] img_wr_data;
    wire img_wr_resp_valid;
    wire img_wr_resp_ready;
    wire img_wr_resp_error;
    wire [7:0] img_wr_resp_code;
    wire [31:0] img_wr_resp_detail;
    wire mem_cfg_wr_valid;
    wire mem_cfg_wr_ready;
    wire mem_cfg_wr_bank;
    wire [5:0] mem_cfg_wr_id;
    wire [63:0] mem_cfg_wr_data;
    wire mem_cfg_wr_resp_valid;
    wire mem_cfg_wr_resp_ready;
    wire mem_cfg_wr_resp_error;
    wire [7:0] mem_cfg_wr_resp_code;
    wire [31:0] mem_cfg_wr_resp_detail;
    wire scalar_state_clear;
    wire scalar_preload_valid;
    wire scalar_preload_ready;
    wire scalar_preload_address;
    wire signed [`RECON_ACC_W-1:0] scalar_preload_data;
    wire scratch_init_valid;
    wire scratch_init_ready;
    wire [2:0] scratch_init_bank;
    wire [8:0] scratch_init_addr;
    wire [71:0] scratch_init_data;
    wire preload_valid;
    wire preload_ready;
    wire [63:0] preload_src_addr;
    wire [5:0] preload_cfg_id;
    wire [63:0] preload_cfg;
    wire preload_done_valid;
    wire preload_done_ready;
    wire [5:0] preload_done_cfg_id;
    wire preload_done_error;
    wire [7:0] preload_done_code;
    wire preload_active;
    wire loader_busy;

    wire active_cfg_valid;
    wire [1:0] active_result_mode;
    wire [1:0] active_matrix_kind;
    wire [8:0] active_measurement_count;
    wire [4:0] active_measurement_row_blocks;
    wire [10:0] active_signal_length;
    wire [6:0] active_sparsity;
    wire [15:0] active_outer_limit;
    wire [7:0] active_refine_limit;
    wire [4:0] active_normal_residual_shift;
    wire active_termination_mode;
    wire [1:0] active_refinement_profile;
    wire [61:0] active_residual_limit;
    wire [63:0] active_phi_seed;
    wire [63:0] active_measurement_address;
    wire [63:0] active_dense_result_address;
    wire [63:0] active_sparse_result_address;
    wire [31:0] active_user_tag;
    wire [17:0] active_phi_scale_mantissa_uq17;
    wire [4:0] active_phi_scale_exponent;
    wire [7:0] active_phi_column_weight;
    wire active_require_unit_norm;

    wire array_ctx_rd_en;
    wire [7:0] array_ctx_rd_addr;
    wire array_ctx_rd_resp_valid;
    wire array_ctx_rd_valid;
    wire [7:0] array_ctx_rd_pc;
    wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] stored_tile_ctx;
    wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] stored_array_ctx;
    wire [`RECON_STREAM_CONTEXT_W-1:0] stored_stream_ctx;
    wire [`RECON_RESOURCE_CONTEXT_W-1:0] stored_resource_ctx;
    wire cycle_valid;
    wire cycle_commit;
    wire cycle_stalled;
    wire [7:0] array_pc;
    wire [`RECON_CLUSTER_COUNT-1:0] cluster_mask;
    wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx;
    wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx;
    wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx;
    wire [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx;
    wire stream_input_ready;
    wire stream_output_ready;
    wire resource_req_ready;
    wire resource_rsp_valid;
    wire [6:0] resident_work_count;
    wire run_start_pulse;
    wire profile_phi_generate_fire;
    wire profile_phi_replay_request_fire;
    wire profile_phi_replay_response_fire;
    wire profile_phi_cache_fill_fire;
    wire profile_phi_output_fire;
    wire profile_selection_fire;
    wire [96*10-1:0] operator_support_indices;
    wire [96*`RECON_SOLVER_W-1:0] operator_support_coefficients;
    wire support_remap_event_valid;
    wire support_remap_event_fault;
    wire refinement_event_valid;
    wire refinement_certificate_pass;
    wire refinement_restart_required;
    wire refinement_recompute_required;
    wire refinement_replacement_required;
    wire refinement_iteration_advance;
    wire [2:0] refinement_stop_reason;
    wire termination_event_valid;
    wire termination_residual_limit_reached;
    wire [`RECON_ACC_W-1:0] termination_residual_sq;
    wire residual_limit_reached;
    wire iteration_limit_reached;
    wire support_stable;
    wire residual_decreased;
    wire solver_converged;
    wire [15:0] outer_iter;
    wire [7:0] solver_iter;
    wire [3:0] resource_ctx_event =
        resource_ctx[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +:
                     `RECON_RESOURCE_FIELD_EVENT_ID_W];
    wire resource_valid = support_remap_event_valid || refinement_event_valid;
    wire [3:0] resource_event = resource_ctx_event;
    wire resource_ready;
    wire solver_fault = support_remap_event_fault || operator_fault;
    wire exec_error_pending = operator_fault;
    wire [3:0] exec_error_class = `RECON_ERROR_CLASS_SOLVER;
    wire [7:0] exec_error_code = 8'h01;
    wire [31:0] exec_error_detail = {16'd0, operator_fault_detail};
    wire image_locked = engine_busy || execution_active ||
        preload_active || preload_valid;
    wire active_context_image_ok = active_image_ok && !loader_busy &&
        !preload_active && !preload_valid;
    wire launch_fire = array_launch_valid && array_launch_ready;
    assign array_launch_ready = sequencer_launch_ready && !preload_active;

    assign final_support_indices = operator_support_indices[
        0 +: `RECON_K_MAX*10];
    assign final_support_coefficients = operator_support_coefficients[
        0 +: `RECON_K_MAX*`RECON_SOLVER_W];

    wire [5:0] cfg_a_id_raw =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_LSB +: 6];
    wire [5:0] cfg_b_id =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_LSB +: 6];
    wire [5:0] cfg_w_id =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_LSB +: 6];
    wire [5:0] phi_cfg_id =
        stream_ctx[`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_LSB +: 6];
    wire [4:0] resource_operation =
        resource_ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                     `RECON_RESOURCE_FIELD_OPERATION_W];
    wire [2:0] resource_input_select =
        resource_ctx[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_INPUT_SELECT_W];
    wire [2:0] resource_output_select =
        resource_ctx[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W];
    wire resource_wait_for_result =
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire [5:0] resource_configuration_id =
        resource_ctx[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +:
                     `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W];
    wire [1:0] resource_stream_boundary =
        resource_ctx[`RECON_RESOURCE_FIELD_STREAM_BOUNDARY_LSB +:
                     `RECON_RESOURCE_FIELD_STREAM_BOUNDARY_W];
    reg fresh_refinement_active;
    wire fresh_refinement_marker = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_NOP) &&
        (resource_configuration_id == 6'd6) &&
        (resource_stream_boundary == `RECON_STREAM_BOUNDARY_FIRST);
    wire fresh_refinement_direction_start = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY) &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        !resource_wait_for_result &&
        (((resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
          (cfg_a_id_raw == 6'd18)) ||
         ((resource_input_select == `RECON_RESOURCE_INPUT_SUPPORT_STREAM) &&
          (resource_configuration_id == 6'd3)));
    wire fresh_refinement_cancel = cycle_valid && cycle_commit &&
        (resource_operation == `RECON_RESOURCE_OP_SUPPORT_UNION);
    wire fresh_refinement_initial_residual = fresh_refinement_active &&
        (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY) &&
        (resource_input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        (cfg_a_id_raw == 6'd1);
    wire [5:0] cfg_a_id = fresh_refinement_initial_residual ?
        6'd0 : cfg_a_id_raw;
    always @(posedge clk) begin
        if (!rst_n || scalar_state_clear || compute_abort_pending)
            fresh_refinement_active <= 1'b0;
        else if (fresh_refinement_marker)
            fresh_refinement_active <= 1'b1;
        else if (fresh_refinement_direction_start || fresh_refinement_cancel)
            fresh_refinement_active <= 1'b0;
    end
    wire cfg_a_valid;
    wire [63:0] cfg_a_data;
    wire cfg_b_valid;
    wire [63:0] cfg_b_data;
    wire cfg_w_valid;
    wire [63:0] cfg_w_data;
    wire phi_cfg_valid;
    wire [63:0] phi_cfg_data;

    wire preload_engine_ready;
    wire preload_load_begin;
    wire [5:0] preload_load_begin_id;
    wire preload_load_commit;
    wire [5:0] preload_load_commit_id;
    wire preload_dma_req_valid;
    wire preload_dma_req_ready;
    wire preload_dma_req_write;
    wire [63:0] preload_dma_req_addr;
    wire [15:0] preload_dma_req_bytes;
    wire [TAG_W-1:0] preload_dma_req_tag;
    wire preload_dma_rd_valid;
    wire preload_dma_rd_ready;
    wire [127:0] preload_dma_rd_data;
    wire preload_dma_rd_last;
    wire [1:0] preload_dma_rd_resp;
    wire [TAG_W-1:0] preload_dma_rd_tag;
    wire preload_dma_done_valid;
    wire preload_dma_done_ready;
    wire [TAG_W-1:0] preload_dma_done_tag;
    wire preload_dma_done_error;
    wire [1:0] preload_dma_done_resp;
    wire preload_sp0_valid;
    wire preload_sp0_ready;
    wire preload_sp0_write;
    wire [7:0] preload_sp0_mask;
    wire [71:0] preload_sp0_addr;
    wire [575:0] preload_sp0_data;
    wire preload_sp1_valid;
    wire preload_sp1_ready;
    wire preload_sp1_write;
    wire [7:0] preload_sp1_mask;
    wire [71:0] preload_sp1_addr;
    wire [575:0] preload_sp1_data;
    wire preload_sp_conflict;

    wire [1:0] lifecycle_aux_req_valid = {
        aux_req_valid[1], preload_dma_req_valid};
    wire [1:0] lifecycle_aux_req_ready;
    wire [1:0] lifecycle_aux_req_write = {
        aux_req_write[1], preload_dma_req_write};
    wire [127:0] lifecycle_aux_req_addr = {
        aux_req_addr[127:64], preload_dma_req_addr};
    wire [31:0] lifecycle_aux_req_bytes = {
        aux_req_bytes[31:16], preload_dma_req_bytes};
    wire [2*TAG_W-1:0] lifecycle_aux_req_tag = {
        aux_req_tag[2*TAG_W-1:TAG_W], preload_dma_req_tag};
    wire [1:0] lifecycle_aux_wr_valid = {aux_wr_valid[1], 1'b0};
    wire [1:0] lifecycle_aux_wr_ready;
    wire [255:0] lifecycle_aux_wr_data = {aux_wr_data[255:128], 128'd0};
    wire [31:0] lifecycle_aux_wr_keep = {aux_wr_keep[31:16], 16'd0};
    wire [1:0] lifecycle_aux_wr_last = {aux_wr_last[1], 1'b0};
    wire [1:0] lifecycle_aux_rd_valid;
    wire [1:0] lifecycle_aux_rd_ready = {
        aux_rd_ready[1], preload_dma_rd_ready};
    wire [255:0] lifecycle_aux_rd_data;
    wire [1:0] lifecycle_aux_rd_last;
    wire [3:0] lifecycle_aux_rd_resp;
    wire [2*TAG_W-1:0] lifecycle_aux_rd_tag;
    wire [1:0] lifecycle_aux_done_valid;
    wire [1:0] lifecycle_aux_done_ready = {
        aux_done_ready[1], preload_dma_done_ready};
    wire [2*TAG_W-1:0] lifecycle_aux_done_tag;
    wire [1:0] lifecycle_aux_done_error;
    wire [3:0] lifecycle_aux_done_resp;
    wire [17:0] lifecycle_aux_done_beat;

    assign preload_ready = preload_engine_ready && !engine_busy;
    assign preload_dma_req_ready = lifecycle_aux_req_ready[0];
    assign preload_dma_rd_valid = lifecycle_aux_rd_valid[0];
    assign preload_dma_rd_data = lifecycle_aux_rd_data[127:0];
    assign preload_dma_rd_last = lifecycle_aux_rd_last[0];
    assign preload_dma_rd_resp = lifecycle_aux_rd_resp[1:0];
    assign preload_dma_rd_tag = lifecycle_aux_rd_tag[TAG_W-1:0];
    assign preload_dma_done_valid = lifecycle_aux_done_valid[0];
    assign preload_dma_done_tag = lifecycle_aux_done_tag[TAG_W-1:0];
    assign preload_dma_done_error = lifecycle_aux_done_error[0];
    assign preload_dma_done_resp = lifecycle_aux_done_resp[1:0];
    assign aux_req_ready = {lifecycle_aux_req_ready[1], 1'b0};
    assign aux_wr_ready = {lifecycle_aux_wr_ready[1], 1'b0};
    assign aux_rd_valid = {lifecycle_aux_rd_valid[1], 1'b0};
    assign aux_rd_data = {lifecycle_aux_rd_data[255:128], 128'd0};
    assign aux_rd_last = {lifecycle_aux_rd_last[1], 1'b0};
    assign aux_rd_resp = {lifecycle_aux_rd_resp[3:2], 2'd0};
    assign aux_rd_tag = {lifecycle_aux_rd_tag[2*TAG_W-1:TAG_W],
        {TAG_W{1'b0}}};
    assign aux_done_valid = {lifecycle_aux_done_valid[1], 1'b0};
    assign aux_done_tag = {lifecycle_aux_done_tag[2*TAG_W-1:TAG_W],
        {TAG_W{1'b0}}};
    assign aux_done_error = {lifecycle_aux_done_error[1], 1'b0};
    assign aux_done_resp = {lifecycle_aux_done_resp[3:2], 2'd0};
    assign aux_done_beat = {lifecycle_aux_done_beat[17:9], 9'd0};

    m13_loader_aperture #(.AXIL_AW(AXIL_AW)) u_loader_aperture (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_loader_axi_awaddr),
        .s_axi_awvalid(s_loader_axi_awvalid),
        .s_axi_awready(s_loader_axi_awready),
        .s_axi_wdata(s_loader_axi_wdata),
        .s_axi_wstrb(s_loader_axi_wstrb),
        .s_axi_wvalid(s_loader_axi_wvalid),
        .s_axi_wready(s_loader_axi_wready),
        .s_axi_bresp(s_loader_axi_bresp),
        .s_axi_bvalid(s_loader_axi_bvalid),
        .s_axi_bready(s_loader_axi_bready),
        .s_axi_araddr(s_loader_axi_araddr),
        .s_axi_arvalid(s_loader_axi_arvalid),
        .s_axi_arready(s_loader_axi_arready),
        .s_axi_rdata(s_loader_axi_rdata),
        .s_axi_rresp(s_loader_axi_rresp),
        .s_axi_rvalid(s_loader_axi_rvalid),
        .s_axi_rready(s_loader_axi_rready),
        .engine_busy(engine_busy),
        .loader_busy(loader_busy),
        .img_finalize_valid(img_finalize_valid),
        .img_finalize_ready(img_finalize_ready),
        .img_finalize_bank(img_finalize_bank),
        .img_finalize_resp_valid(img_finalize_resp_valid),
        .img_finalize_resp_ready(img_finalize_resp_ready),
        .img_finalize_resp_error(img_finalize_resp_error),
        .img_finalize_resp_code(img_finalize_resp_code),
        .img_finalize_resp_detail(img_finalize_resp_detail),
        .img_wr_valid(img_wr_valid), .img_wr_ready(img_wr_ready),
        .img_wr_bank(img_wr_bank), .img_wr_plane(img_wr_plane),
        .img_wr_addr(img_wr_addr), .img_wr_data(img_wr_data),
        .img_wr_resp_valid(img_wr_resp_valid),
        .img_wr_resp_ready(img_wr_resp_ready),
        .img_wr_resp_error(img_wr_resp_error),
        .img_wr_resp_code(img_wr_resp_code),
        .img_wr_resp_detail(img_wr_resp_detail),
        .mem_cfg_wr_valid(mem_cfg_wr_valid),
        .mem_cfg_wr_ready(mem_cfg_wr_ready),
        .mem_cfg_wr_bank(mem_cfg_wr_bank), .mem_cfg_wr_id(mem_cfg_wr_id),
        .mem_cfg_wr_data(mem_cfg_wr_data),
        .mem_cfg_wr_resp_valid(mem_cfg_wr_resp_valid),
        .mem_cfg_wr_resp_ready(mem_cfg_wr_resp_ready),
        .mem_cfg_wr_resp_error(mem_cfg_wr_resp_error),
        .mem_cfg_wr_resp_code(mem_cfg_wr_resp_code),
        .mem_cfg_wr_resp_detail(mem_cfg_wr_resp_detail),
        .scalar_state_clear(scalar_state_clear),
        .scalar_preload_valid(scalar_preload_valid),
        .scalar_preload_ready(scalar_preload_ready),
        .scalar_preload_address(scalar_preload_address),
        .scalar_preload_data(scalar_preload_data),
        .scratch_init_valid(scratch_init_valid),
        .scratch_init_ready(scratch_init_ready),
        .scratch_init_bank(scratch_init_bank),
        .scratch_init_addr(scratch_init_addr),
        .scratch_init_data(scratch_init_data),
        .preload_valid(preload_valid), .preload_ready(preload_ready),
        .preload_src_addr(preload_src_addr),
        .preload_cfg_id(preload_cfg_id), .preload_cfg(preload_cfg),
        .preload_done_valid(preload_done_valid),
        .preload_done_ready(preload_done_ready),
        .preload_done_cfg_id(preload_done_cfg_id),
        .preload_done_error(preload_done_error),
        .preload_done_code(preload_done_code)
    );

    context_image_store u_context_image_store (
        .clk(clk), .rst_n(rst_n), .execution_active(image_locked),
        .active_image_bank(1'b0), .active_image_ok(active_image_ok),
        .active_ctx_count(active_context_count),
        .finalize_valid(img_finalize_valid),
        .finalize_ready(img_finalize_ready),
        .finalize_req_bank(img_finalize_bank),
        .finalize_resp_valid(img_finalize_resp_valid),
        .finalize_resp_ready(img_finalize_resp_ready),
        .finalize_resp_error(img_finalize_resp_error),
        .finalize_resp_code(img_finalize_resp_code),
        .finalize_resp_detail(img_finalize_resp_detail),
        .img_wr_valid(img_wr_valid), .img_wr_ready(img_wr_ready),
        .img_wr_bank(img_wr_bank), .img_wr_plane(img_wr_plane),
        .img_wr_addr(img_wr_addr), .img_wr_data(img_wr_data),
        .img_wr_resp_valid(img_wr_resp_valid),
        .img_wr_resp_ready(img_wr_resp_ready),
        .img_wr_resp_error(img_wr_resp_error),
        .img_wr_resp_code(img_wr_resp_code),
        .img_wr_resp_detail(img_wr_resp_detail),
        .array_rd_en(array_ctx_rd_en), .array_rd_addr(array_ctx_rd_addr),
        .array_rd_resp_valid(array_ctx_rd_resp_valid),
        .array_rd_valid(array_ctx_rd_valid), .array_rd_pc(array_ctx_rd_pc),
        .tile_ctx(stored_tile_ctx), .array_ctx(stored_array_ctx),
        .stream_ctx(stored_stream_ctx), .resource_ctx(stored_resource_ctx),
        .phase_rd_en(phase_rd_en), .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word)
    );

    memory_configuration_store u_memory_configuration_store (
        .clk(clk), .rst_n(rst_n), .execution_active(image_locked),
        .active_image_bank(1'b0), .cfg_wr_valid(mem_cfg_wr_valid),
        .cfg_wr_ready(mem_cfg_wr_ready), .cfg_wr_bank(mem_cfg_wr_bank),
        .cfg_wr_id(mem_cfg_wr_id), .cfg_wr_data(mem_cfg_wr_data),
        .cfg_wr_resp_valid(mem_cfg_wr_resp_valid),
        .cfg_wr_resp_ready(mem_cfg_wr_resp_ready),
        .cfg_wr_resp_error(mem_cfg_wr_resp_error),
        .cfg_wr_resp_code(mem_cfg_wr_resp_code),
        .cfg_wr_resp_detail(mem_cfg_wr_resp_detail),
        .cfg_a_id(cfg_a_id), .cfg_a_valid(cfg_a_valid),
        .cfg_a_data(cfg_a_data), .cfg_b_id(cfg_b_id),
        .cfg_b_valid(cfg_b_valid), .cfg_b_data(cfg_b_data),
        .cfg_stream_id(cfg_w_id), .cfg_stream_valid(cfg_w_valid),
        .cfg_stream_data(cfg_w_data), .phi_cfg_id(phi_cfg_id),
        .phi_cfg_valid(phi_cfg_valid), .phi_cfg_data(phi_cfg_data)
    );

    array_context_sequencer u_array_context_sequencer (
        .clk(clk), .rst_n(rst_n),
        .launch_valid(array_launch_valid && !preload_active),
        .launch_ready(sequencer_launch_ready), .entry_pc(array_entry_pc),
        .event_id(array_event_id), .abort_pending(compute_abort_pending),
        .predicate_values(predicate_values), .image_ok(active_image_ok),
        .image_count(active_context_count),
        .measurement_count(active_measurement_count),
        .signal_length(active_signal_length), .sparsity(active_sparsity),
        .outer_limit(active_outer_limit), .refine_limit(active_refine_limit),
        .run_param0({11'd0, active_measurement_row_blocks}),
        .run_param1({9'd0, resident_work_count}),
        .stream_in_ready(stream_input_ready),
        .stream_out_ready(stream_output_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid),
        .ctx_rd_en(array_ctx_rd_en), .ctx_rd_addr(array_ctx_rd_addr),
        .ctx_rd_resp_valid(array_ctx_rd_resp_valid),
        .ctx_rd_valid(array_ctx_rd_valid), .ctx_rd_pc(array_ctx_rd_pc),
        .ctx_tiles(stored_tile_ctx), .ctx_array(stored_array_ctx),
        .ctx_stream(stored_stream_ctx), .ctx_resource(stored_resource_ctx),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled), .array_pc(array_pc),
        .cluster_mask(cluster_mask), .tile_ctx(tile_ctx),
        .array_ctx(array_ctx), .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx), .execution_active(execution_active),
        .done_valid(array_done_valid), .done_ready(array_done_ready),
        .done_event_id(array_done_event_id),
        .done_aborted(array_done_aborted), .fault_valid(array_fault_valid),
        .fault_ready(array_fault_ready), .fault_code(array_fault_code),
        .fault_pc(array_fault_pc), .fault_detail(array_fault_detail),
        .commit_count(), .guaranteed_count(), .elastic_count(), .stall_count()
    );

    execution_profile_monitor u_execution_profile (
        .clk(clk), .rst_n(rst_n), .run_start(run_start_pulse),
        .engine_busy(engine_busy), .phase_active(phase_active),
        .execution_active(execution_active), .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .cycle_stalled(cycle_stalled),
        .cluster_mask(cluster_mask), .tile_ctx(tile_ctx),
        .array_ctx(array_ctx), .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx), .predicate_values(predicate_values),
        .stream_input_ready(stream_input_ready),
        .stream_output_ready(stream_output_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid),
        .total_cycles(profile_total_cycles),
        .phase_cycles(profile_phase_cycles),
        .execution_cycles(profile_execution_cycles),
        .array_commit_cycles(profile_array_commit_cycles),
        .array_stall_cycles(profile_array_stall_cycles),
        .useful_pe_cycles(profile_useful_pe_cycles),
        .useful_pe_slots(profile_useful_pe_slots),
        .resource_stall_cycles(profile_resource_stall_cycles)
    );

    execution_event_profile_monitor u_execution_event_profile (
        .clk(clk), .rst_n(rst_n), .run_start(run_start_pulse),
        .engine_busy(engine_busy),
        .phi_generate_fire(profile_phi_generate_fire),
        .phi_replay_request_fire(profile_phi_replay_request_fire),
        .phi_replay_response_fire(profile_phi_replay_response_fire),
        .phi_cache_fill_fire(profile_phi_cache_fill_fire),
        .phi_output_fire(profile_phi_output_fire),
        .selection_fire(profile_selection_fire),
        .dma_read_address_valid(m_axi_arvalid),
        .dma_read_address_ready(m_axi_arready),
        .dma_read_data_valid(m_axi_rvalid),
        .dma_read_data_ready(m_axi_rready),
        .dma_write_address_valid(m_axi_awvalid),
        .dma_write_address_ready(m_axi_awready),
        .dma_write_data_valid(m_axi_wvalid),
        .dma_write_data_ready(m_axi_wready),
        .dma_write_response_valid(m_axi_bvalid),
        .dma_write_response_ready(m_axi_bready),
        .writeback_active(writeback_active),
        .phi_generate_requests(profile_phi_generate_requests),
        .phi_replay_requests(profile_phi_replay_requests),
        .phi_replay_responses(profile_phi_replay_responses),
        .phi_cache_fills(profile_phi_cache_fills),
        .phi_output_symbols(profile_phi_output_symbols),
        .selection_accepts(profile_selection_accepts),
        .dma_read_requests(profile_dma_read_requests),
        .dma_read_beats(profile_dma_read_beats),
        .dma_write_requests(profile_dma_write_requests),
        .dma_write_beats(profile_dma_write_beats),
        .dma_write_responses(profile_dma_write_responses),
        .result_drain_cycles(profile_result_drain_cycles),
        .result_drain_beats(profile_result_drain_beats)
    );

    scratchpad_preload_engine #(.TAG_W(TAG_W)) u_preload_engine (
        .clk(clk), .rst_n(rst_n),
        .preload_valid(preload_valid && !engine_busy),
        .preload_ready(preload_engine_ready),
        .preload_src_addr(preload_src_addr), .preload_cfg_id(preload_cfg_id),
        .preload_cfg(preload_cfg), .preload_done_valid(preload_done_valid),
        .preload_done_ready(preload_done_ready),
        .preload_done_cfg_id(preload_done_cfg_id),
        .preload_done_error(preload_done_error),
        .preload_done_code(preload_done_code), .preload_active(preload_active),
        .load_begin(preload_load_begin),
        .load_begin_id(preload_load_begin_id),
        .load_commit(preload_load_commit),
        .load_commit_id(preload_load_commit_id),
        .dma_req_valid(preload_dma_req_valid),
        .dma_req_ready(preload_dma_req_ready),
        .dma_req_write(preload_dma_req_write),
        .dma_req_addr(preload_dma_req_addr),
        .dma_req_bytes(preload_dma_req_bytes),
        .dma_req_tag(preload_dma_req_tag),
        .dma_rd_valid(preload_dma_rd_valid),
        .dma_rd_ready(preload_dma_rd_ready),
        .dma_rd_data(preload_dma_rd_data),
        .dma_rd_last(preload_dma_rd_last),
        .dma_rd_resp(preload_dma_rd_resp),
        .dma_rd_tag(preload_dma_rd_tag),
        .dma_done_valid(preload_dma_done_valid),
        .dma_done_ready(preload_dma_done_ready),
        .dma_done_tag(preload_dma_done_tag),
        .dma_done_error(preload_dma_done_error),
        .dma_done_resp(preload_dma_done_resp),
        .sp0_valid(preload_sp0_valid), .sp0_ready(preload_sp0_ready),
        .sp0_write(preload_sp0_write), .sp0_bank_mask(preload_sp0_mask),
        .sp0_addr(preload_sp0_addr), .sp0_wr_data(preload_sp0_data),
        .sp1_valid(preload_sp1_valid), .sp1_ready(preload_sp1_ready),
        .sp1_write(preload_sp1_write), .sp1_bank_mask(preload_sp1_mask),
        .sp1_addr(preload_sp1_addr), .sp1_wr_data(preload_sp1_data),
        .sp_conflict(preload_sp_conflict)
    );

    m8_operator_harness #(
        .USE_INTERNAL_PHI_CACHE(1),
        .CGRA_FULL_PE_MASK(16'h000f)
    ) u_operator (
        .clk(clk), .rst_n(rst_n), .run_abort(compute_abort_pending),
        .run_start(launch_fire), .scalar_clear(scalar_state_clear),
        .scalar_load_valid(scalar_preload_valid),
        .scalar_load_ready(scalar_preload_ready),
        .scalar_load_select(scalar_preload_address),
        .scalar_load_data(scalar_preload_data),
        .phi_cache_clear(1'b0), .execution_active(execution_active),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .ctx_tile(tile_ctx), .ctx_array(array_ctx), .ctx_stream(stream_ctx),
        .ctx_resource(resource_ctx), .ctx_predicates(predicate_values),
        .cfg_seed(active_phi_seed),
        .cfg_measurement_count(active_measurement_count),
        .cfg_signal_length(active_signal_length),
        .cfg_work_count(active_sparsity),
        .cfg_selection_k(active_sparsity[5:0]),
        .cfg_normal_residual_shift(active_normal_residual_shift),
        .cfg_refinement_profile(active_refinement_profile),
        .cfg_refine_limit(active_refine_limit),
        .cfg_residual_limit(active_residual_limit),
        .cfg_phi_scale_mantissa_uq17(active_phi_scale_mantissa_uq17),
        .cfg_phi_scale_exponent(active_phi_scale_exponent),
        .cfg_a_valid(cfg_a_valid), .cfg_a_data(cfg_a_data),
        .cfg_b_valid(cfg_b_valid), .cfg_b_data(cfg_b_data),
        .cfg_w_valid(cfg_w_valid), .cfg_w_data(cfg_w_data),
        .phi_cfg_valid(phi_cfg_valid), .phi_cfg_data(phi_cfg_data),
        .phi_support_valid(1'b0), .phi_support_ready(),
        .phi_support_col(10'd0), .phi_cache_req_valid(),
        .phi_cache_req_ready(1'b0), .phi_cache_req_slot(),
        .phi_cache_req_row(), .phi_cache_req_tag(),
        .phi_cache_rsp_valid(1'b0), .phi_cache_rsp_ready(),
        .phi_cache_rsp_mask(32'd0), .phi_cache_rsp_sign(32'd0),
        .phi_cache_rsp_col(10'd0), .phi_cache_rsp_row(3'd0),
        .phi_cache_rsp_tag(8'd0), .phi_cache_ext_valid(1'b0),
        .scratch_init_valid(scratch_init_valid),
        .scratch_init_ready(scratch_init_ready),
        .scratch_init_bank(scratch_init_bank),
        .scratch_init_addr(scratch_init_addr),
        .scratch_init_wr_data(scratch_init_data),
        .scratch_load_active(preload_active),
        .scratch_load_p0_valid(preload_sp0_valid),
        .scratch_load_p0_ready(preload_sp0_ready),
        .scratch_load_p0_write(preload_sp0_write),
        .scratch_load_p0_bank_mask(preload_sp0_mask),
        .scratch_load_p0_addr(preload_sp0_addr),
        .scratch_load_p0_wr_data(preload_sp0_data),
        .scratch_load_p1_valid(preload_sp1_valid),
        .scratch_load_p1_ready(preload_sp1_ready),
        .scratch_load_p1_write(preload_sp1_write),
        .scratch_load_p1_bank_mask(preload_sp1_mask),
        .scratch_load_p1_addr(preload_sp1_addr),
        .scratch_load_p1_wr_data(preload_sp1_data),
        .scratch_load_conflict(preload_sp_conflict),
        .stream_input_ready(stream_input_ready),
        .stream_output_ready(stream_output_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid), .operator_fault(operator_fault),
        .operator_fault_detail(operator_fault_detail),
        .profile_phi_generate_fire(profile_phi_generate_fire),
        .profile_phi_replay_request_fire(profile_phi_replay_request_fire),
        .profile_phi_replay_response_fire(profile_phi_replay_response_fire),
        .profile_phi_cache_fill_fire(profile_phi_cache_fill_fire),
        .profile_phi_output_fire(profile_phi_output_fire),
        .profile_selection_fire(profile_selection_fire),
        .support_remap_event_valid(support_remap_event_valid),
        .support_remap_event_fault(support_remap_event_fault),
        .support_remap_dropped_count(), .support_remap_dropped_indices(),
        .support_remap_dropped_coefficients(),
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
        .resident_count(resident_work_count),
        .final_support_count(final_support_count),
        .final_support_indices(operator_support_indices),
        .final_support_coefficients(operator_support_coefficients),
        .selection_count(), .result_scores(), .result_indices(),
        .observed_phi_column(), .observed_phi_row_block()
    );

    m13_termination_monitor u_termination_monitor (
        .clk(clk), .rst_n(rst_n), .run_active(engine_busy),
        .outer_limit(active_outer_limit), .refine_limit(active_refine_limit),
        .termination_mode(active_termination_mode),
        .termination_event_valid(termination_event_valid),
        .termination_residual_limit_reached(
            termination_residual_limit_reached),
        .termination_residual_sq(termination_residual_sq),
        .refinement_event_valid(refinement_event_valid),
        .refinement_iteration_advance(refinement_iteration_advance),
        .refinement_certificate_pass(refinement_certificate_pass),
        .support_count(final_support_count),
        .support_indices(final_support_indices),
        .residual_limit_reached(residual_limit_reached),
        .iteration_limit_reached(iteration_limit_reached),
        .support_stable(support_stable),
        .residual_decreased(residual_decreased),
        .solver_converged(solver_converged),
        .outer_iter(outer_iter), .solver_iter(solver_iter)
    );

    m12_lifecycle_top #(
        .AXIL_AW(AXIL_AW), .TAG_W(TAG_W), .TRACE_ENABLE(TRACE_ENABLE)
    ) u_lifecycle (
        .solver_recompute_required(refinement_recompute_required),
        .solver_replacement_required(refinement_replacement_required),
        .aux_req_valid(lifecycle_aux_req_valid),
        .aux_req_ready(lifecycle_aux_req_ready),
        .aux_req_write(lifecycle_aux_req_write),
        .aux_req_addr(lifecycle_aux_req_addr),
        .aux_req_bytes(lifecycle_aux_req_bytes),
        .aux_req_tag(lifecycle_aux_req_tag),
        .aux_wr_valid(lifecycle_aux_wr_valid),
        .aux_wr_ready(lifecycle_aux_wr_ready),
        .aux_wr_data(lifecycle_aux_wr_data),
        .aux_wr_keep(lifecycle_aux_wr_keep),
        .aux_wr_last(lifecycle_aux_wr_last),
        .aux_rd_valid(lifecycle_aux_rd_valid),
        .aux_rd_ready(lifecycle_aux_rd_ready),
        .aux_rd_data(lifecycle_aux_rd_data),
        .aux_rd_last(lifecycle_aux_rd_last),
        .aux_rd_resp(lifecycle_aux_rd_resp),
        .aux_rd_tag(lifecycle_aux_rd_tag),
        .aux_done_valid(lifecycle_aux_done_valid),
        .aux_done_ready(lifecycle_aux_done_ready),
        .aux_done_tag(lifecycle_aux_done_tag),
        .aux_done_error(lifecycle_aux_done_error),
        .aux_done_resp(lifecycle_aux_done_resp),
        .aux_done_beat(lifecycle_aux_done_beat),
        .*
    );

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            if (execution_active)
                assert(active_image_ok);
            if (cycle_commit)
                assert(stream_input_ready && stream_output_ready &&
                       resource_req_ready && resource_rsp_valid);
        end
    end
`endif
endmodule

`default_nettype wire
