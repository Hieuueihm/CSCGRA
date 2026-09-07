`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

// Verification/synthesis harness for the implemented M1--M4 architecture.
// This is deliberately not the production top.  It leaves the future PE
// array, Phi generator and shared-resource units as explicit boundaries while
// using the real control, DMA, context and vector-memory RTL internally.
module m1_m4_integration_harness #(
    parameter integer AXIL_AW = 12
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [AXIL_AW-1:0]     s_axi_awaddr,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [31:0]            s_axi_wdata,
    input  wire [3:0]             s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [AXIL_AW-1:0]     s_axi_araddr,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [31:0]            s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    output wire [63:0]            m_axi_araddr,
    output wire [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    output wire                   m_axi_arvalid,
    input  wire                   m_axi_arready,
    input  wire [127:0]           m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,
    output wire [63:0]            m_axi_awaddr,
    output wire [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,
    output wire                   m_axi_awvalid,
    input  wire                   m_axi_awready,
    output wire [127:0]           m_axi_wdata,
    output wire [15:0]            m_axi_wstrb,
    output wire                   m_axi_wlast,
    output wire                   m_axi_wvalid,
    input  wire                   m_axi_wready,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready,

    input  wire                   img_wr_valid,
    output wire                   img_wr_ready,
    input  wire                   img_wr_bank,
    input  wire [3:0]             img_wr_plane,
    input  wire [7:0]             img_wr_addr,
    input  wire [71:0]            img_wr_data,
    output wire                   img_wr_resp_valid,
    input  wire                   img_wr_resp_ready,
    output wire                   img_wr_resp_error,
    output wire [7:0]             img_wr_resp_code,
    output wire [31:0]            img_wr_resp_detail,
    input  wire                   img_finalize_valid,
    output wire                   img_finalize_ready,
    input  wire                   img_finalize_bank,
    output wire                   img_finalize_resp_valid,
    input  wire                   img_finalize_resp_ready,
    output wire                   img_finalize_resp_error,
    output wire [7:0]             img_finalize_resp_code,
    output wire [31:0]            img_finalize_resp_detail,

    input  wire                   mem_cfg_wr_valid,
    output wire                   mem_cfg_wr_ready,
    input  wire                   mem_cfg_wr_bank,
    input  wire [5:0]             mem_cfg_wr_id,
    input  wire [63:0]            mem_cfg_wr_data,
    output wire                   mem_cfg_wr_resp_valid,
    input  wire                   mem_cfg_wr_resp_ready,
    output wire                   mem_cfg_wr_resp_error,
    output wire [7:0]             mem_cfg_wr_resp_code,
    output wire [31:0]            mem_cfg_wr_resp_detail,

    input  wire                   preload_valid,
    output wire                   preload_ready,
    input  wire [63:0]            preload_src_addr,
    input  wire [5:0]             preload_cfg_id,
    input  wire [63:0]            preload_cfg,
    output wire                   preload_done_valid,
    input  wire                   preload_done_ready,
    output wire [5:0]             preload_done_cfg_id,
    output wire                   preload_done_error,
    output wire [7:0]             preload_done_code,
    output wire                   preload_active,
    input  wire                   residency_clear,
    input  wire                   residency_invalidate,
    input  wire [5:0]             residency_invalidate_id,

    input  wire [7:0]             predicate_values,
    input  wire                   resource_req_ready,
    input  wire                   resource_rsp_valid,
    input  wire                   resource_event_valid,
    input  wire [3:0]             resource_event_id,
    input  wire                   residual_limit_reached,
    input  wire                   iteration_limit_reached,
    input  wire                   support_stable,
    input  wire                   residual_decreased,
    input  wire                   solver_converged,
    input  wire                   solver_fault,
    input  wire [6:0]             active_support,
    input  wire [15:0]            outer_iteration,
    input  wire [7:0]             solver_iteration,

    input  wire                   array_sink_ready,
    input  wire [575:0]           vector_write_data,
    input  wire                   scalar_valid,
    input  wire [26:0]            scalar_data,
    output wire                   phi_command_valid,
    input  wire                   phi_command_ready,
    output wire [1:0]             phi_command,
    output wire [5:0]             phi_cfg_id,
    output wire [63:0]            phi_cfg_data,
    input  wire                   phi_symbol_valid,
    output wire                   phi_symbol_ready,
    input  wire [31:0]            phi_nonzero,
    input  wire [31:0]            phi_sign,

    output wire                   irq,
    output wire                   engine_busy,
    output wire                   cfg_fetch_active,
    output wire                   array_active,
    output wire                   cycle_valid,
    output wire                   cycle_commit,
    output wire                   cycle_stalled,
    output wire [7:0]             array_pc,
    output wire [1:0]             cluster_mask,
    output wire [575:0]           tile_ctx,
    output wire [35:0]            array_ctx,
    output wire [35:0]            stream_ctx,
    output wire [35:0]            resource_ctx,
    output wire [863:0]           vector_a_data,
    output wire                   vector_a_valid,
    output wire [863:0]           vector_b_data,
    output wire                   vector_b_valid,
    output wire [26:0]            routed_scalar,
    output wire [31:0]            array_commit_count,
    output wire [31:0]            array_stall_count,
    output wire [63:0]            resident_bitmap,
    output wire                   integration_error
);
    wire csr_wr_valid;
    wire [AXIL_AW-1:0] csr_wr_addr;
    wire [31:0] csr_wr_data;
    wire [3:0] csr_wr_strb;
    wire [1:0] csr_wr_resp;
    wire csr_rd_valid;
    wire [AXIL_AW-1:0] csr_rd_addr;
    wire [31:0] csr_rd_data;
    wire [1:0] csr_rd_resp;

    wire run_start;
    wire abort_request;
    wire [63:0] run_cfg_addr;
    wire abort_pending;
    wire phase_engine_busy;
    wire done_pulse;
    wire [3:0] stop_reason;
    wire [6:0] support_count;
    wire control_error_pulse;
    wire [3:0] control_error_class;
    wire [7:0] control_error_code;
    wire [7:0] control_error_phase;
    wire [4:0] control_cfg_error_word;
    wire [31:0] control_error_detail;
    wire [7:0] phase_progress;
    wire [15:0] outer_progress;
    wire [7:0] solver_progress;
    wire [63:0] total_cycles;

    axilite_slave #(.AXIL_AW(AXIL_AW), .AXIL_DW(32)) u_axilite_slave (
        .aclk(clk), .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .csr_wr_valid(csr_wr_valid),
        .csr_wr_addr(csr_wr_addr), .csr_wr_data(csr_wr_data),
        .csr_wr_strb(csr_wr_strb), .csr_wr_resp(csr_wr_resp),
        .csr_rd_valid(csr_rd_valid), .csr_rd_addr(csr_rd_addr),
        .csr_rd_data(csr_rd_data), .csr_rd_resp(csr_rd_resp)
    );

    reconstruction_csr #(.AXIL_AW(AXIL_AW)) u_reconstruction_csr (
        .clk(clk), .rst_n(rst_n), .csr_wr_valid(csr_wr_valid),
        .csr_wr_addr(csr_wr_addr), .csr_wr_data(csr_wr_data),
        .csr_wr_strb(csr_wr_strb), .csr_wr_resp(csr_wr_resp),
        .csr_rd_valid(csr_rd_valid), .csr_rd_addr(csr_rd_addr),
        .csr_rd_data(csr_rd_data), .csr_rd_resp(csr_rd_resp),
        .run_start(run_start), .abort_request(abort_request), .irq(irq),
        .run_cfg_addr(run_cfg_addr), .engine_busy(engine_busy),
        .cfg_fetch_active(cfg_fetch_active), .array_active(array_active),
        .writeback_active(1'b0), .abort_pending(abort_pending),
        .done_pulse(done_pulse), .stop_reason(stop_reason),
        .support_count(support_count), .error_pulse(control_error_pulse),
        .error_class(control_error_class), .error_code(control_error_code),
        .error_phase(control_error_phase),
        .cfg_error_word(control_cfg_error_word),
        .error_detail(control_error_detail), .phase_progress(phase_progress),
        .outer_progress(outer_progress), .solver_progress(solver_progress),
        .total_cycles(total_cycles)
    );

    wire cfg_start_valid;
    wire cfg_start_ready;
    wire [63:0] cfg_start_addr;
    wire cfg_validation_active;
    wire cfg_control_busy;
    wire cfg_error_valid;
    wire cfg_error_ready;
    wire [3:0] cfg_error_class;
    wire [7:0] cfg_error_code;
    wire [4:0] cfg_error_word;
    wire [31:0] cfg_error_detail;
    wire active_cfg_valid;
    wire active_cfg_release;
    wire [1:0] active_result_mode;
    wire [1:0] active_matrix_kind;
    wire [8:0] active_measurement_count;
    wire [10:0] active_signal_length;
    wire [6:0] active_sparsity;
    wire [15:0] active_outer_limit;
    wire [7:0] active_refine_limit;
    wire [4:0] active_normal_residual_shift;
    wire [1:0] active_refinement_profile;
    wire [61:0] active_residual_limit;
    wire [63:0] active_phi_seed;
    wire [63:0] active_measurement_address;
    wire [63:0] active_dense_result_address;
    wire [63:0] active_sparse_result_address;
    wire [31:0] active_user_tag;
    wire [17:0] active_phi_scale_mantissa;
    wire [4:0] active_phi_scale_exponent;
    wire [7:0] active_phi_column_weight;
    wire active_require_unit_norm;

    wire cfg_dma_req_valid, cfg_dma_req_ready, cfg_dma_req_write;
    wire [63:0] cfg_dma_req_addr;
    wire [15:0] cfg_dma_req_bytes;
    wire [7:0] cfg_dma_req_tag;
    wire cfg_dma_rd_valid, cfg_dma_rd_ready, cfg_dma_rd_last;
    wire [127:0] cfg_dma_rd_data;
    wire [1:0] cfg_dma_rd_resp;
    wire [7:0] cfg_dma_rd_tag;
    wire cfg_dma_done_valid, cfg_dma_done_ready, cfg_dma_done_error;
    wire [7:0] cfg_dma_done_tag;
    wire [1:0] cfg_dma_done_resp;
    wire [8:0] cfg_dma_done_beat;

    reconstruction_configuration_unit u_configuration_unit (
        .clk(clk), .rst_n(rst_n), .start_valid(cfg_start_valid),
        .start_ready(cfg_start_ready), .start_address(cfg_start_addr),
        .abort_request(abort_request),
        .terminal_release(active_cfg_release),
        .fetch_active(cfg_fetch_active),
        .validation_active(cfg_validation_active),
        .control_busy(cfg_control_busy), .dma_req_valid(cfg_dma_req_valid),
        .dma_req_ready(cfg_dma_req_ready), .dma_req_write(cfg_dma_req_write),
        .dma_req_addr(cfg_dma_req_addr), .dma_req_bytes(cfg_dma_req_bytes),
        .dma_req_tag(cfg_dma_req_tag), .dma_rd_valid(cfg_dma_rd_valid),
        .dma_rd_ready(cfg_dma_rd_ready), .dma_rd_data(cfg_dma_rd_data),
        .dma_rd_last(cfg_dma_rd_last), .dma_rd_resp(cfg_dma_rd_resp),
        .dma_rd_tag(cfg_dma_rd_tag), .dma_done_valid(cfg_dma_done_valid),
        .dma_done_ready(cfg_dma_done_ready),
        .dma_done_tag(cfg_dma_done_tag),
        .dma_done_error(cfg_dma_done_error),
        .dma_done_resp(cfg_dma_done_resp),
        .dma_completion_beat(cfg_dma_done_beat),
        .error_valid(cfg_error_valid), .error_ready(cfg_error_ready),
        .error_class(cfg_error_class), .error_code(cfg_error_code),
        .cfg_error_word(cfg_error_word), .error_detail(cfg_error_detail),
        .active_valid(active_cfg_valid),
        .result_mode(active_result_mode), .matrix_kind(active_matrix_kind),
        .measurement_count(active_measurement_count),
        .signal_length(active_signal_length), .sparsity(active_sparsity),
        .outer_limit(active_outer_limit), .refine_limit(active_refine_limit),
        .normal_residual_shift(active_normal_residual_shift),
        .refinement_profile(active_refinement_profile),
        .residual_limit(active_residual_limit), .phi_seed(active_phi_seed),
        .measurement_address(active_measurement_address),
        .dense_result_address(active_dense_result_address),
        .sparse_result_address(active_sparse_result_address),
        .user_tag(active_user_tag),
        .phi_scale_mantissa_uq17(active_phi_scale_mantissa),
        .phi_scale_exponent(active_phi_scale_exponent),
        .phi_column_weight(active_phi_column_weight),
        .require_unit_norm(active_require_unit_norm)
    );

    wire phase_rd_en, phase_rd_resp_valid, phase_rd_valid;
    wire [7:0] phase_rd_addr, phase_rd_pc;
    wire [35:0] phase_word;
    wire array_launch_valid, array_launch_ready;
    wire [7:0] array_entry_pc;
    wire [3:0] array_event_id;
    wire array_done_valid, array_done_ready, array_done_aborted;
    wire [3:0] array_done_event_id;
    wire array_fault_valid, array_fault_ready;
    wire [7:0] array_fault_code, array_fault_pc;
    wire [31:0] array_fault_detail;
    wire phase_active;
    wire [2:0] control_state;
    wire active_image_bank;
    wire phase_trace_valid;
    wire [7:0] phase_trace_pc;
    wire [2:0] phase_trace_operation;
    wire phase_trace_condition;
    wire stream_contract_error;
    wire residency_violation;
    wire execution_error = stream_contract_error || residency_violation;

    reconstruction_phase_controller u_phase_controller (
        .clk(clk), .rst_n(rst_n), .start_request(run_start),
        .start_address(run_cfg_addr), .abort_request(abort_request),
        .cfg_start_valid(cfg_start_valid), .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(cfg_start_addr), .cfg_fetch_active(cfg_fetch_active),
        .cfg_fetch_error_valid(cfg_error_valid),
        .cfg_fetch_error_ready(cfg_error_ready),
        .cfg_fetch_error_class(cfg_error_class),
        .cfg_fetch_error_code(cfg_error_code),
        .cfg_fetch_error_word(cfg_error_word),
        .cfg_fetch_error_detail(cfg_error_detail),
        .active_cfg_valid(active_cfg_valid),
        .active_context_image_ok(image_ok),
        .active_cfg_release(active_cfg_release), .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word), .array_launch_valid(array_launch_valid),
        .array_launch_ready(array_launch_ready),
        .array_entry_pc(array_entry_pc), .array_event_id(array_event_id),
        .array_done_valid(array_done_valid),
        .array_done_ready(array_done_ready),
        .array_done_event_id(array_done_event_id),
        .array_done_aborted(array_done_aborted),
        .array_fault_valid(array_fault_valid),
        .array_fault_ready(array_fault_ready),
        .array_fault_code(array_fault_code), .array_fault_pc(array_fault_pc),
        .array_fault_detail(array_fault_detail),
        .resource_valid(resource_event_valid), .resource_ready(),
        .resource_event(resource_event_id),
        .dma_done(preload_done_valid && !preload_done_error),
        .residual_limit_reached(residual_limit_reached),
        .iteration_limit_reached(iteration_limit_reached),
        .support_stable(support_stable),
        .residual_decreased(residual_decreased),
        .solver_converged(solver_converged), .solver_fault(solver_fault),
        .exec_error_pending(execution_error),
        .exec_error_class(`RECON_ERROR_CLASS_CONTEXT),
        .exec_error_code(residency_violation ?
            `RECON_CONTEXT_ERROR_MEMORY_CONFIGURATION :
            `RECON_CONTEXT_ERROR_STREAM_CONTRACT),
        .exec_error_detail({array_pc, 22'd0, residency_violation,
                            stream_contract_error}),
        .active_support(active_support), .outer_iter(outer_iteration),
        .solver_iter(solver_iteration), .engine_busy(phase_engine_busy),
        .phase_active(phase_active), .csr_cfg_fetch_active(),
        .writeback_active(), .abort_pending(abort_pending),
        .done_pulse(done_pulse), .stop_reason(stop_reason),
        .support_count(support_count), .error_pulse(control_error_pulse),
        .error_class(control_error_class), .error_code(control_error_code),
        .error_phase(control_error_phase),
        .cfg_error_word(control_cfg_error_word),
        .error_detail(control_error_detail), .phase_progress(phase_progress),
        .outer_progress(outer_progress), .solver_progress(solver_progress),
        .total_cycles(total_cycles), .control_state(control_state),
        .active_image_bank(active_image_bank), .trace_valid(phase_trace_valid),
        .trace_phase_pc(phase_trace_pc),
        .trace_operation(phase_trace_operation),
        .trace_condition(phase_trace_condition)
    );

    wire image_ok;
    wire [8:0] image_count;
    wire ctx_rd_en, ctx_rd_resp_valid, ctx_rd_valid;
    wire [7:0] ctx_rd_addr, ctx_rd_pc;
    wire [575:0] stored_tile_ctx;
    wire [35:0] stored_array_ctx, stored_stream_ctx, stored_resource_ctx;
    wire image_locked = engine_busy || preload_active;
    assign engine_busy = phase_engine_busy || preload_active;

    context_image_store u_context_image_store (
        .clk(clk), .rst_n(rst_n), .execution_active(image_locked),
        .active_image_bank(active_image_bank), .active_image_ok(image_ok),
        .active_ctx_count(image_count),
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
        .img_wr_resp_detail(img_wr_resp_detail), .array_rd_en(ctx_rd_en),
        .array_rd_addr(ctx_rd_addr), .array_rd_resp_valid(ctx_rd_resp_valid),
        .array_rd_valid(ctx_rd_valid), .array_rd_pc(ctx_rd_pc),
        .tile_ctx(stored_tile_ctx), .array_ctx(stored_array_ctx),
        .stream_ctx(stored_stream_ctx), .resource_ctx(stored_resource_ctx),
        .phase_rd_en(phase_rd_en), .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word)
    );

    wire [5:0] vec_cfg_a, vec_cfg_b, vec_cfg_w;
    wire cfg_a_valid, cfg_b_valid, cfg_w_valid, phi_cfg_valid;
    wire [63:0] cfg_a_data, cfg_b_data, cfg_w_data;

    memory_configuration_store u_memory_configuration_store (
        .clk(clk), .rst_n(rst_n), .execution_active(image_locked),
        .active_image_bank(active_image_bank),
        .cfg_wr_valid(mem_cfg_wr_valid), .cfg_wr_ready(mem_cfg_wr_ready),
        .cfg_wr_bank(mem_cfg_wr_bank), .cfg_wr_id(mem_cfg_wr_id),
        .cfg_wr_data(mem_cfg_wr_data),
        .cfg_wr_resp_valid(mem_cfg_wr_resp_valid),
        .cfg_wr_resp_ready(mem_cfg_wr_resp_ready),
        .cfg_wr_resp_error(mem_cfg_wr_resp_error),
        .cfg_wr_resp_code(mem_cfg_wr_resp_code),
        .cfg_wr_resp_detail(mem_cfg_wr_resp_detail),
        .cfg_a_id(vec_cfg_a), .cfg_a_valid(cfg_a_valid),
        .cfg_a_data(cfg_a_data), .cfg_b_id(vec_cfg_b),
        .cfg_b_valid(cfg_b_valid), .cfg_b_data(cfg_b_data),
        .cfg_stream_id(vec_cfg_w), .cfg_stream_valid(cfg_w_valid),
        .cfg_stream_data(cfg_w_data), .phi_cfg_id(phi_cfg_id),
        .phi_cfg_valid(phi_cfg_valid), .phi_cfg_data(phi_cfg_data)
    );

    wire router_stream_in_ready, router_stream_out_ready;
    wire configs_resident;
    wire missing_cfg_valid;
    wire [5:0] missing_cfg_id;
    wire vec_req_valid, vec_cycle_commit;
    wire vec_a_en, vec_b_en, vec_w_en;
    wire vec_in_ready, vec_out_ready, vec_cfg_error, vec_access_conflict;
    wire physical_vec_a_valid, physical_vec_b_valid;
    wire [575:0] physical_vec_a, physical_vec_b;
    wire [863:0] expanded_vec_a, expanded_vec_b;
    wire [1:0] ext_a_sel, ext_b_sel;
    wire [31:0] routed_phi_nonzero, routed_phi_sign;

    scratchpad_residency_tracker u_residency_tracker (
        .clk(clk), .rst_n(rst_n), .clear_all(residency_clear),
        .load_begin(preload_load_begin),
        .load_begin_id(preload_load_begin_id),
        .load_commit(preload_load_commit),
        .load_commit_id(preload_load_commit_id),
        .invalidate(residency_invalidate),
        .invalidate_id(residency_invalidate_id), .ctx_valid(cycle_valid),
        .stream_ctx(stream_ctx), .configs_resident(configs_resident),
        .reservation_violation(residency_violation),
        .missing_valid(missing_cfg_valid), .missing_id(missing_cfg_id),
        .resident_bitmap_out(resident_bitmap)
    );

    wire sequencer_stream_in_ready = router_stream_in_ready &&
                                     configs_resident && array_sink_ready;

    array_context_sequencer u_array_sequencer (
        .clk(clk), .rst_n(rst_n), .launch_valid(array_launch_valid),
        .launch_ready(array_launch_ready), .entry_pc(array_entry_pc),
        .event_id(array_event_id), .abort_pending(abort_pending),
        .predicate_values(predicate_values), .image_ok(image_ok),
        .image_count(image_count),
        .measurement_count(active_measurement_count),
        .signal_length(active_signal_length), .sparsity(active_sparsity),
        .outer_limit(active_outer_limit), .refine_limit(active_refine_limit),
        .run_param0(16'd0), .run_param1(16'd0),
        .stream_in_ready(sequencer_stream_in_ready),
        .stream_out_ready(router_stream_out_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid), .ctx_rd_en(ctx_rd_en),
        .ctx_rd_addr(ctx_rd_addr), .ctx_rd_resp_valid(ctx_rd_resp_valid),
        .ctx_rd_valid(ctx_rd_valid), .ctx_rd_pc(ctx_rd_pc),
        .ctx_tiles(stored_tile_ctx), .ctx_array(stored_array_ctx),
        .ctx_stream(stored_stream_ctx), .ctx_resource(stored_resource_ctx),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled), .array_pc(array_pc),
        .cluster_mask(cluster_mask), .tile_ctx(tile_ctx),
        .array_ctx(array_ctx), .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx), .execution_active(array_active),
        .done_valid(array_done_valid), .done_ready(array_done_ready),
        .done_event_id(array_done_event_id),
        .done_aborted(array_done_aborted), .fault_valid(array_fault_valid),
        .fault_ready(array_fault_ready), .fault_code(array_fault_code),
        .fault_pc(array_fault_pc), .fault_detail(array_fault_detail),
        .commit_count(array_commit_count), .guaranteed_count(),
        .elastic_count(), .stall_count(array_stall_count)
    );

    stream_context_router u_stream_router (
        .clk(clk), .rst_n(rst_n), .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit), .stream_ctx(stream_ctx),
        .vec_req_valid(vec_req_valid), .vec_cycle_commit(vec_cycle_commit),
        .vec_a_en(vec_a_en), .vec_b_en(vec_b_en), .vec_w_en(vec_w_en),
        .vec_cfg_a(vec_cfg_a), .vec_cfg_b(vec_cfg_b), .vec_cfg_w(vec_cfg_w),
        .vec_in_ready(vec_in_ready), .vec_out_ready(vec_out_ready),
        .vec_cfg_error(vec_cfg_error),
        .vec_access_conflict(vec_access_conflict),
        .vector_a_valid(physical_vec_a_valid),
        .vector_a_data(expanded_vec_a),
        .vector_b_valid(physical_vec_b_valid),
        .vector_b_data(expanded_vec_b), .scalar_a_valid(scalar_valid),
        .scalar_a_data(scalar_data), .scalar_b_valid(scalar_valid),
        .scalar_b_data(scalar_data), .ext_a_sel(ext_a_sel),
        .ext_b_sel(ext_b_sel), .out_vec_a(vector_a_data),
        .out_vec_b(vector_b_data), .out_scalar(routed_scalar),
        .phi_command_valid(phi_command_valid),
        .phi_command_ready(phi_command_ready), .phi_command(phi_command),
        .phi_cfg_id(phi_cfg_id), .phi_cfg_valid(phi_cfg_valid),
        .phi_symbol_valid(phi_symbol_valid),
        .phi_symbol_ready(phi_symbol_ready), .phi_nonzero(phi_nonzero),
        .phi_sign(phi_sign), .out_phi_nonzero(routed_phi_nonzero),
        .out_phi_sign(routed_phi_sign),
        .stream_in_ready(router_stream_in_ready),
        .stream_out_ready(router_stream_out_ready),
        .stream_contract_error(stream_contract_error)
    );

    assign vector_a_valid = physical_vec_a_valid;
    assign vector_b_valid = physical_vec_b_valid;
    assign integration_error = execution_error;

    genvar codec_bank;
    generate
        for (codec_bank = 0; codec_bank < 8; codec_bank = codec_bank + 1) begin : g_read_codecs
            scratchpad_word_codec u_a_codec (
                .unpack_valid(physical_vec_a_valid),
                .unpack_word(physical_vec_a[codec_bank*72 +: 72]),
                .unpack_element_format(cfg_a_data[54:52]),
                .unpack_packing_mode(cfg_a_data[57:55]),
                .unpack_format_valid(),
                .pe_lane_data(expanded_vec_a[codec_bank*108 +: 108]),
                .pe_lane_valid(), .sidecar_lane_data(),
                .sidecar_lane_valid(), .index_data(), .index_valid(),
                .raw_word_data(), .raw_word_valid(), .pack_valid(1'b0),
                .pack_element_format(3'd0), .pack_packing_mode(3'd0),
                .pack_pe_lane_data(108'd0), .pack_sidecar_lane_data(54'd0),
                .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
                .packed_word_valid(), .packed_word(), .pack_range_error()
            );
            scratchpad_word_codec u_b_codec (
                .unpack_valid(physical_vec_b_valid),
                .unpack_word(physical_vec_b[codec_bank*72 +: 72]),
                .unpack_element_format(cfg_b_data[54:52]),
                .unpack_packing_mode(cfg_b_data[57:55]),
                .unpack_format_valid(),
                .pe_lane_data(expanded_vec_b[codec_bank*108 +: 108]),
                .pe_lane_valid(), .sidecar_lane_data(),
                .sidecar_lane_valid(), .index_data(), .index_valid(),
                .raw_word_data(), .raw_word_valid(), .pack_valid(1'b0),
                .pack_element_format(3'd0), .pack_packing_mode(3'd0),
                .pack_pe_lane_data(108'd0), .pack_sidecar_lane_data(54'd0),
                .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
                .packed_word_valid(), .packed_word(), .pack_range_error()
            );
        end
    endgenerate

    wire stream_p0_valid, stream_p0_ready, stream_p0_write;
    wire [7:0] stream_p0_mask;
    wire [71:0] stream_p0_addr;
    wire [575:0] stream_p0_wr_data;
    wire stream_p0_rd_valid;
    wire [7:0] stream_p0_rd_mask;
    wire [575:0] stream_p0_rd_data;
    wire stream_p1_valid, stream_p1_ready, stream_p1_write;
    wire [7:0] stream_p1_mask;
    wire [71:0] stream_p1_addr;
    wire [575:0] stream_p1_wr_data;
    wire stream_p1_rd_valid;
    wire [7:0] stream_p1_rd_mask;
    wire [575:0] stream_p1_rd_data;
    wire scratchpad_conflict;

    vector_stream_engine u_vector_stream_engine (
        .clk(clk), .rst_n(rst_n),
        .cursor_restart_valid(1'b0), .cursor_restart_mask(3'b000),
        .cursor_restart_ready(), .routine_start(array_launch_valid && array_launch_ready),
        .req_valid(vec_req_valid), .cycle_commit(vec_cycle_commit),
        .vec_a_en(vec_a_en), .vec_b_en(vec_b_en), .vec_w_en(vec_w_en),
        .vec_a_restart(1'b0), .vec_b_restart(1'b0),
        .vec_cfg_a(vec_cfg_a), .vec_cfg_b(vec_cfg_b), .vec_cfg_w(vec_cfg_w),
        .cfg_a_valid(cfg_a_valid), .cfg_a(cfg_a_data),
        .cfg_b_valid(cfg_b_valid), .cfg_b(cfg_b_data),
        .cfg_w_valid(cfg_w_valid), .cfg_w(cfg_w_data),
        .vec_w_data(vector_write_data), .stream_in_ready(vec_in_ready),
        .stream_out_ready(vec_out_ready), .cfg_error(vec_cfg_error),
        .access_conflict(vec_access_conflict),
        .vec_a_valid(physical_vec_a_valid), .vec_a_data(physical_vec_a),
        .vec_b_valid(physical_vec_b_valid), .vec_b_data(physical_vec_b),
        .sp0_valid(stream_p0_valid), .sp0_ready(stream_p0_ready),
        .sp0_write(stream_p0_write), .sp0_bank_mask(stream_p0_mask),
        .sp0_addr(stream_p0_addr), .sp0_wr_data(stream_p0_wr_data),
        .sp0_rd_valid(stream_p0_rd_valid),
        .sp0_rd_bank_mask(stream_p0_rd_mask),
        .sp0_rd_data(stream_p0_rd_data), .sp1_valid(stream_p1_valid),
        .sp1_ready(stream_p1_ready), .sp1_write(stream_p1_write),
        .sp1_bank_mask(stream_p1_mask), .sp1_addr(stream_p1_addr),
        .sp1_wr_data(stream_p1_wr_data),
        .sp1_rd_valid(stream_p1_rd_valid),
        .sp1_rd_bank_mask(stream_p1_rd_mask),
        .sp1_rd_data(stream_p1_rd_data), .sp_conflict(scratchpad_conflict)
    );

    wire preload_cmd_ready;
    wire preload_load_begin, preload_load_commit;
    wire [5:0] preload_load_begin_id, preload_load_commit_id;
    wire preload_dma_req_valid, preload_dma_req_ready, preload_dma_req_write;
    wire [63:0] preload_dma_req_addr;
    wire [15:0] preload_dma_req_bytes;
    wire [7:0] preload_dma_req_tag;
    wire preload_dma_rd_valid, preload_dma_rd_ready, preload_dma_rd_last;
    wire [127:0] preload_dma_rd_data;
    wire [1:0] preload_dma_rd_resp;
    wire [7:0] preload_dma_rd_tag;
    wire preload_dma_done_valid, preload_dma_done_ready;
    wire [7:0] preload_dma_done_tag;
    wire preload_dma_done_error;
    wire [1:0] preload_dma_done_resp;
    wire preload_p0_valid, preload_p0_ready, preload_p0_write;
    wire [7:0] preload_p0_mask;
    wire [71:0] preload_p0_addr;
    wire [575:0] preload_p0_wr_data;
    wire preload_p1_valid, preload_p1_ready, preload_p1_write;
    wire [7:0] preload_p1_mask;
    wire [71:0] preload_p1_addr;
    wire [575:0] preload_p1_wr_data;

    assign preload_ready = preload_cmd_ready && !engine_busy;
    scratchpad_preload_engine u_preload_engine (
        .clk(clk), .rst_n(rst_n),
        .preload_valid(preload_valid && !engine_busy),
        .preload_ready(preload_cmd_ready), .preload_src_addr(preload_src_addr),
        .preload_cfg_id(preload_cfg_id), .preload_cfg(preload_cfg),
        .preload_done_valid(preload_done_valid),
        .preload_done_ready(preload_done_ready),
        .preload_done_cfg_id(preload_done_cfg_id),
        .preload_done_error(preload_done_error),
        .preload_done_code(preload_done_code),
        .preload_active(preload_active), .load_begin(preload_load_begin),
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
        .dma_rd_resp(preload_dma_rd_resp), .dma_rd_tag(preload_dma_rd_tag),
        .dma_done_valid(preload_dma_done_valid),
        .dma_done_ready(preload_dma_done_ready),
        .dma_done_tag(preload_dma_done_tag),
        .dma_done_error(preload_dma_done_error),
        .dma_done_resp(preload_dma_done_resp),
        .sp0_valid(preload_p0_valid), .sp0_ready(preload_p0_ready),
        .sp0_write(preload_p0_write), .sp0_bank_mask(preload_p0_mask),
        .sp0_addr(preload_p0_addr), .sp0_wr_data(preload_p0_wr_data),
        .sp1_valid(preload_p1_valid), .sp1_ready(preload_p1_ready),
        .sp1_write(preload_p1_write), .sp1_bank_mask(preload_p1_mask),
        .sp1_addr(preload_p1_addr), .sp1_wr_data(preload_p1_wr_data),
        .sp_conflict(scratchpad_conflict)
    );

    wire scratchpad_p0_valid = preload_active ? preload_p0_valid : stream_p0_valid;
    wire scratchpad_p0_ready;
    wire scratchpad_p0_write = preload_active ? preload_p0_write : stream_p0_write;
    wire [7:0] scratchpad_p0_mask = preload_active ? preload_p0_mask : stream_p0_mask;
    wire [71:0] scratchpad_p0_addr = preload_active ? preload_p0_addr : stream_p0_addr;
    wire [575:0] scratchpad_p0_wr_data = preload_active ?
        preload_p0_wr_data : stream_p0_wr_data;
    wire scratchpad_p1_valid = preload_active ? preload_p1_valid : stream_p1_valid;
    wire scratchpad_p1_ready;
    wire scratchpad_p1_write = preload_active ? preload_p1_write : stream_p1_write;
    wire [7:0] scratchpad_p1_mask = preload_active ? preload_p1_mask : stream_p1_mask;
    wire [71:0] scratchpad_p1_addr = preload_active ? preload_p1_addr : stream_p1_addr;
    wire [575:0] scratchpad_p1_wr_data = preload_active ?
        preload_p1_wr_data : stream_p1_wr_data;
    wire scratchpad_p0_rd_valid, scratchpad_p1_rd_valid;
    wire [7:0] scratchpad_p0_rd_mask, scratchpad_p1_rd_mask;
    wire [575:0] scratchpad_p0_rd_data, scratchpad_p1_rd_data;

    assign preload_p0_ready = preload_active && scratchpad_p0_ready;
    assign preload_p1_ready = preload_active && scratchpad_p1_ready;
    assign stream_p0_ready = !preload_active && scratchpad_p0_ready;
    assign stream_p1_ready = !preload_active && scratchpad_p1_ready;
    assign stream_p0_rd_valid = !preload_active && scratchpad_p0_rd_valid;
    assign stream_p0_rd_mask = scratchpad_p0_rd_mask;
    assign stream_p0_rd_data = scratchpad_p0_rd_data;
    assign stream_p1_rd_valid = !preload_active && scratchpad_p1_rd_valid;
    assign stream_p1_rd_mask = scratchpad_p1_rd_mask;
    assign stream_p1_rd_data = scratchpad_p1_rd_data;

    vector_scratchpad u_vector_scratchpad (
        .clk(clk), .rst_n(rst_n), .p0_valid(scratchpad_p0_valid),
        .p0_ready(scratchpad_p0_ready), .p0_write(scratchpad_p0_write),
        .p0_bank_mask(scratchpad_p0_mask), .p0_addr(scratchpad_p0_addr),
        .p0_wr_data(scratchpad_p0_wr_data),
        .p0_rd_valid(scratchpad_p0_rd_valid),
        .p0_rd_bank_mask(scratchpad_p0_rd_mask),
        .p0_rd_data(scratchpad_p0_rd_data), .p1_valid(scratchpad_p1_valid),
        .p1_ready(scratchpad_p1_ready), .p1_write(scratchpad_p1_write),
        .p1_bank_mask(scratchpad_p1_mask), .p1_addr(scratchpad_p1_addr),
        .p1_wr_data(scratchpad_p1_wr_data),
        .p1_rd_valid(scratchpad_p1_rd_valid),
        .p1_rd_bank_mask(scratchpad_p1_rd_mask),
        .p1_rd_data(scratchpad_p1_rd_data),
        .external_conflict(1'b0),
        .access_conflict(scratchpad_conflict)
    );

    wire [3:0] dma_client_req_valid =
        {1'b0, preload_dma_req_valid, 1'b0, cfg_dma_req_valid};
    wire [3:0] dma_client_req_ready;
    wire [3:0] dma_client_req_write =
        {1'b0, preload_dma_req_write, 1'b0, cfg_dma_req_write};
    wire [255:0] dma_client_req_addr =
        {64'd0, preload_dma_req_addr, 64'd0, cfg_dma_req_addr};
    wire [63:0] dma_client_req_bytes =
        {16'd0, preload_dma_req_bytes, 16'd0, cfg_dma_req_bytes};
    wire [31:0] dma_client_req_tag =
        {8'd0, preload_dma_req_tag, 8'd0, cfg_dma_req_tag};
    wire [3:0] dma_client_wr_ready;
    wire [3:0] dma_client_rd_valid;
    wire [511:0] dma_client_rd_data;
    wire [3:0] dma_client_rd_last;
    wire [7:0] dma_client_rd_resp;
    wire [31:0] dma_client_rd_tag;
    wire [3:0] dma_client_done_valid;
    wire [31:0] dma_client_done_tag;
    wire [3:0] dma_client_done_error;
    wire [7:0] dma_client_done_resp;
    wire [35:0] dma_client_done_beat;
    wire dma_active;

    assign cfg_dma_req_ready = dma_client_req_ready[0];
    assign cfg_dma_rd_valid = dma_client_rd_valid[0];
    assign cfg_dma_rd_data = dma_client_rd_data[127:0];
    assign cfg_dma_rd_last = dma_client_rd_last[0];
    assign cfg_dma_rd_resp = dma_client_rd_resp[1:0];
    assign cfg_dma_rd_tag = dma_client_rd_tag[7:0];
    assign cfg_dma_done_valid = dma_client_done_valid[0];
    assign cfg_dma_done_tag = dma_client_done_tag[7:0];
    assign cfg_dma_done_error = dma_client_done_error[0];
    assign cfg_dma_done_resp = dma_client_done_resp[1:0];
    assign cfg_dma_done_beat = dma_client_done_beat[8:0];
    assign preload_dma_req_ready = dma_client_req_ready[2];
    assign preload_dma_rd_valid = dma_client_rd_valid[2];
    assign preload_dma_rd_data = dma_client_rd_data[383:256];
    assign preload_dma_rd_last = dma_client_rd_last[2];
    assign preload_dma_rd_resp = dma_client_rd_resp[5:4];
    assign preload_dma_rd_tag = dma_client_rd_tag[23:16];
    assign preload_dma_done_valid = dma_client_done_valid[2];
    assign preload_dma_done_tag = dma_client_done_tag[23:16];
    assign preload_dma_done_error = dma_client_done_error[2];
    assign preload_dma_done_resp = dma_client_done_resp[5:4];

    memory_dma_engine u_memory_dma_engine (
        .clk(clk), .rst_n(rst_n), .client_req_valid(dma_client_req_valid),
        .client_req_ready(dma_client_req_ready),
        .client_req_write(dma_client_req_write),
        .client_req_addr(dma_client_req_addr),
        .client_req_bytes(dma_client_req_bytes),
        .client_req_tag(dma_client_req_tag), .client_wr_valid(4'd0),
        .client_wr_ready(dma_client_wr_ready), .client_wr_data(512'd0),
        .client_wr_keep(64'd0), .client_wr_last(4'd0),
        .client_rd_valid(dma_client_rd_valid),
        .client_rd_ready({1'b0, preload_dma_rd_ready, 1'b0,
                          cfg_dma_rd_ready}),
        .client_rd_data(dma_client_rd_data),
        .client_rd_last(dma_client_rd_last),
        .client_rd_resp(dma_client_rd_resp),
        .client_rd_tag(dma_client_rd_tag),
        .client_done_valid(dma_client_done_valid),
        .client_done_ready({1'b0, preload_dma_done_ready, 1'b0,
                            cfg_dma_done_ready}),
        .client_done_tag(dma_client_done_tag),
        .client_done_error(dma_client_done_error),
        .client_done_resp(dma_client_done_resp),
        .client_done_beat(dma_client_done_beat), .dma_active(dma_active),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert(!(preload_active && phase_engine_busy));
            if (cycle_commit) begin
                assert(configs_resident);
                assert(router_stream_in_ready);
                assert(router_stream_out_ready);
                assert(!integration_error);
            end
            if (preload_valid && engine_busy)
                assert(!preload_ready);
        end
    end
`endif
endmodule

`default_nettype wire
