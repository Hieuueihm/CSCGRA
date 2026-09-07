`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "reconstruction_control_defs.vh"

module m12_lifecycle_top #(
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

    input  wire active_context_image_ok,
    output wire phase_rd_en,
    output wire [7:0] phase_rd_addr,
    input  wire phase_rd_resp_valid,
    input  wire phase_rd_valid,
    input  wire [7:0] phase_rd_pc,
    input  wire [35:0] phase_word,
    output wire array_launch_valid,
    input  wire array_launch_ready,
    output wire [7:0] array_entry_pc,
    output wire [3:0] array_event_id,
    input  wire array_done_valid,
    output wire array_done_ready,
    input  wire [3:0] array_done_event_id,
    input  wire array_done_aborted,
    input  wire array_fault_valid,
    output wire array_fault_ready,
    input  wire [7:0] array_fault_code,
    input  wire [7:0] array_fault_pc,
    input  wire [31:0] array_fault_detail,
    input  wire resource_valid,
    output wire resource_ready,
    input  wire [3:0] resource_event,
    input  wire compute_dma_done,
    input  wire residual_limit_reached,
    input  wire iteration_limit_reached,
    input  wire support_stable,
    input  wire residual_decreased,
    input  wire solver_converged,
    input  wire solver_recompute_required,
    input  wire solver_replacement_required,
    input  wire solver_fault,
    input  wire exec_error_pending,
    input  wire [3:0] exec_error_class,
    input  wire [7:0] exec_error_code,
    input  wire [31:0] exec_error_detail,
    input  wire [15:0] outer_iter,
    input  wire [7:0] solver_iter,
    input  wire [6:0] final_support_count,
    input  wire [`RECON_K_MAX*10-1:0] final_support_indices,
    input  wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0]
        final_support_coefficients,

    output wire active_cfg_valid,
    output wire [1:0] active_result_mode,
    output wire [1:0] active_matrix_kind,
    output wire [8:0] active_measurement_count,
    output wire [4:0] active_measurement_row_blocks,
    output wire [10:0] active_signal_length,
    output wire [6:0] active_sparsity,
    output wire [15:0] active_outer_limit,
    output wire [7:0] active_refine_limit,
    output wire [4:0] active_normal_residual_shift,
    output wire active_termination_mode,
    output wire [1:0] active_refinement_profile,
    output wire [61:0] active_residual_limit,
    output wire [63:0] active_phi_seed,
    output wire [63:0] active_measurement_address,
    output wire [63:0] active_dense_result_address,
    output wire [63:0] active_sparse_result_address,
    output wire [31:0] active_user_tag,
    output wire [17:0] active_phi_scale_mantissa_uq17,
    output wire [4:0] active_phi_scale_exponent,
    output wire [7:0] active_phi_column_weight,
    output wire active_require_unit_norm,

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
    output wire compute_abort_pending,
    output wire writeback_active,
    output wire [2:0] lifecycle_state,
    output wire run_start_pulse
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_COMPUTE = 3'd1;
    localparam [2:0] STATE_START_WRITEBACK = 3'd2;
    localparam [2:0] STATE_WRITEBACK = 3'd3;

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

    wire cfg_start_valid;
    wire cfg_start_ready;
    wire [63:0] cfg_start_addr;
    wire cfg_fetch_active;
    wire cfg_validation_active;
    wire cfg_control_busy;
    wire cfg_error_valid;
    wire cfg_error_ready;
    wire [3:0] cfg_error_class;
    wire [7:0] cfg_error_code;
    wire [4:0] cfg_error_word;
    wire [31:0] cfg_error_detail;
    reg cfg_terminal_release;

    wire cfg_dma_req_valid;
    wire cfg_dma_req_ready;
    wire cfg_dma_req_write;
    wire [63:0] cfg_dma_req_addr;
    wire [15:0] cfg_dma_req_bytes;
    wire [TAG_W-1:0] cfg_dma_req_tag;
    wire cfg_dma_rd_valid;
    wire cfg_dma_rd_ready;
    wire [127:0] cfg_dma_rd_data;
    wire cfg_dma_rd_last;
    wire [1:0] cfg_dma_rd_resp;
    wire [TAG_W-1:0] cfg_dma_rd_tag;
    wire cfg_dma_done_valid;
    wire cfg_dma_done_ready;
    wire [TAG_W-1:0] cfg_dma_done_tag;
    wire cfg_dma_done_error;
    wire [1:0] cfg_dma_done_resp;
    wire [8:0] cfg_dma_done_beat;

    wire phase_engine_busy;
    wire phase_cfg_release;
    wire phase_abort_pending;
    wire phase_done_pulse;
    wire [3:0] phase_stop_reason;
    wire [6:0] phase_support_count;
    wire phase_error_pulse;
    wire [3:0] phase_error_class;
    wire [7:0] phase_error_code;
    wire [7:0] phase_error_phase;
    wire [4:0] phase_cfg_error_word;
    wire [31:0] phase_error_detail;
    wire [7:0] phase_progress;
    wire [15:0] outer_progress;
    wire [7:0] solver_progress;
    wire [63:0] phase_total_cycles;

    reg [2:0] state;
    reg [3:0] terminal_stop_reason;
    reg [6:0] terminal_support_count;
    reg [`RECON_K_MAX*10-1:0] terminal_support_indices;
    reg [`RECON_K_MAX*`RECON_SOLVER_W-1:0]
        terminal_support_coefficients;
    reg csr_done_pulse;
    reg [3:0] csr_stop_reason;
    reg [6:0] csr_support_count;
    reg csr_error_pulse;
    reg [3:0] csr_error_class;
    reg [7:0] csr_error_code;
    reg [7:0] csr_error_phase;
    reg [4:0] csr_cfg_error_word;
    reg [31:0] csr_error_detail;
    reg writeback_abort_pending;
    reg [63:0] lifecycle_cycles;

    wire result_start_valid =
        (state == STATE_START_WRITEBACK) && !abort_request;
    wire result_start_ready;
    wire result_completion_valid;
    wire [3:0] result_completion_stop_reason;
    wire result_error_valid;
    wire [3:0] result_error_class;
    wire [7:0] result_error_code;
    wire [1:0] result_error_response;
    wire [8:0] result_error_beat;
    wire [TAG_W-1:0] result_error_tag;
    wire dma_active;

    assign compute_abort_pending = phase_abort_pending;

    wire [2:0] dma_aux_req_valid = {aux_req_valid, cfg_dma_req_valid};
    wire [2:0] dma_aux_req_ready;
    wire [2:0] dma_aux_req_write = {aux_req_write, cfg_dma_req_write};
    wire [3*64-1:0] dma_aux_req_addr = {aux_req_addr, cfg_dma_req_addr};
    wire [3*16-1:0] dma_aux_req_bytes = {aux_req_bytes, cfg_dma_req_bytes};
    wire [3*TAG_W-1:0] dma_aux_req_tag = {aux_req_tag, cfg_dma_req_tag};
    wire [2:0] dma_aux_wr_valid = {aux_wr_valid, 1'b0};
    wire [2:0] dma_aux_wr_ready;
    wire [3*128-1:0] dma_aux_wr_data = {aux_wr_data, 128'd0};
    wire [3*16-1:0] dma_aux_wr_keep = {aux_wr_keep, 16'd0};
    wire [2:0] dma_aux_wr_last = {aux_wr_last, 1'b0};
    wire [2:0] dma_aux_rd_valid;
    wire [2:0] dma_aux_rd_ready = {aux_rd_ready, cfg_dma_rd_ready};
    wire [3*128-1:0] dma_aux_rd_data;
    wire [2:0] dma_aux_rd_last;
    wire [3*2-1:0] dma_aux_rd_resp;
    wire [3*TAG_W-1:0] dma_aux_rd_tag;
    wire [2:0] dma_aux_done_valid;
    wire [2:0] dma_aux_done_ready = {aux_done_ready, cfg_dma_done_ready};
    wire [3*TAG_W-1:0] dma_aux_done_tag;
    wire [2:0] dma_aux_done_error;
    wire [3*2-1:0] dma_aux_done_resp;
    wire [3*9-1:0] dma_aux_done_beat;

    assign lifecycle_state = state;
    assign run_start_pulse = run_start;
    assign engine_busy = (state != STATE_IDLE) || phase_engine_busy ||
        cfg_control_busy || dma_active;
    assign aux_req_ready = dma_aux_req_ready[2:1];
    assign aux_wr_ready = dma_aux_wr_ready[2:1];
    assign aux_rd_valid = dma_aux_rd_valid[2:1];
    assign aux_rd_data = dma_aux_rd_data[3*128-1:128];
    assign aux_rd_last = dma_aux_rd_last[2:1];
    assign aux_rd_resp = dma_aux_rd_resp[3*2-1:2];
    assign aux_rd_tag = dma_aux_rd_tag[3*TAG_W-1:TAG_W];
    assign aux_done_valid = dma_aux_done_valid[2:1];
    assign aux_done_tag = dma_aux_done_tag[3*TAG_W-1:TAG_W];
    assign aux_done_error = dma_aux_done_error[2:1];
    assign aux_done_resp = dma_aux_done_resp[3*2-1:2];
    assign aux_done_beat = dma_aux_done_beat[3*9-1:9];
    assign cfg_dma_req_ready = dma_aux_req_ready[0];
    assign cfg_dma_rd_valid = dma_aux_rd_valid[0];
    assign cfg_dma_rd_data = dma_aux_rd_data[127:0];
    assign cfg_dma_rd_last = dma_aux_rd_last[0];
    assign cfg_dma_rd_resp = dma_aux_rd_resp[1:0];
    assign cfg_dma_rd_tag = dma_aux_rd_tag[TAG_W-1:0];
    assign cfg_dma_done_valid = dma_aux_done_valid[0];
    assign cfg_dma_done_tag = dma_aux_done_tag[TAG_W-1:0];
    assign cfg_dma_done_error = dma_aux_done_error[0];
    assign cfg_dma_done_resp = dma_aux_done_resp[1:0];
    assign cfg_dma_done_beat = dma_aux_done_beat[8:0];

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

    reconstruction_csr #(
        .AXIL_AW(AXIL_AW), .TRACE_ENABLE(TRACE_ENABLE)
    ) u_csr (
        .clk(clk), .rst_n(rst_n), .csr_wr_valid(csr_wr_valid),
        .csr_wr_addr(csr_wr_addr), .csr_wr_data(csr_wr_data),
        .csr_wr_strb(csr_wr_strb), .csr_wr_resp(csr_wr_resp),
        .csr_rd_valid(csr_rd_valid), .csr_rd_addr(csr_rd_addr),
        .csr_rd_data(csr_rd_data), .csr_rd_resp(csr_rd_resp),
        .run_start(run_start), .abort_request(abort_request), .irq(irq),
        .run_cfg_addr(run_cfg_addr), .engine_busy(engine_busy),
        .cfg_fetch_active(cfg_fetch_active), .array_active(phase_active),
        .writeback_active(writeback_active),
        .abort_pending(phase_abort_pending || writeback_abort_pending),
        .done_pulse(csr_done_pulse), .stop_reason(csr_stop_reason),
        .support_count(csr_support_count), .error_pulse(csr_error_pulse),
        .error_class(csr_error_class), .error_code(csr_error_code),
        .error_phase(csr_error_phase),
        .cfg_error_word(csr_cfg_error_word),
        .error_detail(csr_error_detail), .phase_progress(phase_progress),
        .outer_progress(outer_progress), .solver_progress(solver_progress),
        .total_cycles(lifecycle_cycles)
    );

    reconstruction_configuration_unit #(.TAG_W(TAG_W)) u_configuration (
        .clk(clk), .rst_n(rst_n), .start_valid(cfg_start_valid),
        .start_ready(cfg_start_ready), .start_address(cfg_start_addr),
        .abort_request(abort_request && (state == STATE_COMPUTE)),
        .terminal_release(cfg_terminal_release),
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
        .active_valid(active_cfg_valid), .result_mode(active_result_mode),
        .matrix_kind(active_matrix_kind),
        .measurement_count(active_measurement_count),
        .measurement_row_blocks(active_measurement_row_blocks),
        .signal_length(active_signal_length), .sparsity(active_sparsity),
        .outer_limit(active_outer_limit), .refine_limit(active_refine_limit),
        .normal_residual_shift(active_normal_residual_shift),
        .termination_mode(active_termination_mode),
        .refinement_profile(active_refinement_profile),
        .residual_limit(active_residual_limit), .phi_seed(active_phi_seed),
        .measurement_address(active_measurement_address),
        .dense_result_address(active_dense_result_address),
        .sparse_result_address(active_sparse_result_address),
        .user_tag(active_user_tag),
        .phi_scale_mantissa_uq17(active_phi_scale_mantissa_uq17),
        .phi_scale_exponent(active_phi_scale_exponent),
        .phi_column_weight(active_phi_column_weight),
        .require_unit_norm(active_require_unit_norm)
    );

    reconstruction_phase_controller u_phase_controller (
        .clk(clk), .rst_n(rst_n), .start_request(run_start),
        .start_address(run_cfg_addr),
        .abort_request(abort_request && (state == STATE_COMPUTE)),
        .cfg_start_valid(cfg_start_valid), .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(cfg_start_addr), .cfg_fetch_active(cfg_fetch_active),
        .cfg_fetch_error_valid(cfg_error_valid),
        .cfg_fetch_error_ready(cfg_error_ready),
        .cfg_fetch_error_class(cfg_error_class),
        .cfg_fetch_error_code(cfg_error_code),
        .cfg_fetch_error_word(cfg_error_word),
        .cfg_fetch_error_detail(cfg_error_detail),
        .active_cfg_valid(active_cfg_valid),
        .active_context_image_ok(active_context_image_ok),
        .active_cfg_release(phase_cfg_release), .phase_rd_en(phase_rd_en),
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
        .resource_valid(resource_valid), .resource_ready(resource_ready),
        .resource_event(resource_event), .dma_done(compute_dma_done),
        .residual_limit_reached(residual_limit_reached),
        .iteration_limit_reached(iteration_limit_reached),
        .support_stable(support_stable),
        .residual_decreased(residual_decreased),
        .solver_converged(solver_converged),
        .solver_recompute_required(solver_recompute_required),
        .solver_replacement_required(solver_replacement_required),
        .solver_fault(solver_fault),
        .exec_error_pending(exec_error_pending),
        .exec_error_class(exec_error_class),
        .exec_error_code(exec_error_code),
        .exec_error_detail(exec_error_detail),
        .active_support(final_support_count), .outer_iter(outer_iter),
        .solver_iter(solver_iter), .engine_busy(phase_engine_busy),
        .phase_active(phase_active), .csr_cfg_fetch_active(),
        .writeback_active(), .abort_pending(phase_abort_pending),
        .done_pulse(phase_done_pulse), .stop_reason(phase_stop_reason),
        .support_count(phase_support_count),
        .error_pulse(phase_error_pulse),
        .error_class(phase_error_class), .error_code(phase_error_code),
        .error_phase(phase_error_phase),
        .cfg_error_word(phase_cfg_error_word),
        .error_detail(phase_error_detail), .phase_progress(phase_progress),
        .outer_progress(outer_progress), .solver_progress(solver_progress),
        .total_cycles(phase_total_cycles), .control_state(),
        .active_image_bank(), .trace_valid(), .trace_phase_pc(),
        .trace_operation(), .trace_condition()
    );

    m12_result_dma_integration #(.TAG_W(TAG_W)) u_result_dma (
        .clk(clk), .rst_n(rst_n), .result_start_valid(result_start_valid),
        .result_start_ready(result_start_ready),
        .result_abort_request(abort_request &&
            (state == STATE_WRITEBACK)),
        .result_mode(active_result_mode),
        .signal_length(active_signal_length),
        .support_count(terminal_support_count),
        .support_indices(terminal_support_indices),
        .support_coefficients(terminal_support_coefficients),
        .dense_result_address(active_dense_result_address),
        .sparse_result_address(active_sparse_result_address),
        .user_tag(active_user_tag), .stop_reason(terminal_stop_reason),
        .writeback_active(writeback_active),
        .completion_valid(result_completion_valid),
        .completion_ready(1'b1),
        .completion_stop_reason(result_completion_stop_reason),
        .error_valid(result_error_valid), .error_ready(1'b1),
        .error_class(result_error_class), .error_code(result_error_code),
        .error_response(result_error_response),
        .error_beat(result_error_beat), .error_tag(result_error_tag),
        .aux_req_valid(dma_aux_req_valid),
        .aux_req_ready(dma_aux_req_ready),
        .aux_req_write(dma_aux_req_write), .aux_req_addr(dma_aux_req_addr),
        .aux_req_bytes(dma_aux_req_bytes), .aux_req_tag(dma_aux_req_tag),
        .aux_wr_valid(dma_aux_wr_valid), .aux_wr_ready(dma_aux_wr_ready),
        .aux_wr_data(dma_aux_wr_data), .aux_wr_keep(dma_aux_wr_keep),
        .aux_wr_last(dma_aux_wr_last), .aux_rd_valid(dma_aux_rd_valid),
        .aux_rd_ready(dma_aux_rd_ready), .aux_rd_data(dma_aux_rd_data),
        .aux_rd_last(dma_aux_rd_last), .aux_rd_resp(dma_aux_rd_resp),
        .aux_rd_tag(dma_aux_rd_tag), .aux_done_valid(dma_aux_done_valid),
        .aux_done_ready(dma_aux_done_ready),
        .aux_done_tag(dma_aux_done_tag),
        .aux_done_error(dma_aux_done_error),
        .aux_done_resp(dma_aux_done_resp),
        .aux_done_beat(dma_aux_done_beat), .dma_active(dma_active),
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

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            terminal_stop_reason <= `RECON_STOP_NONE;
            terminal_support_count <= 7'd0;
            terminal_support_indices <=
                {`RECON_K_MAX*10{1'b0}};
            terminal_support_coefficients <=
                {`RECON_K_MAX*`RECON_SOLVER_W{1'b0}};
            csr_done_pulse <= 1'b0;
            csr_stop_reason <= `RECON_STOP_NONE;
            csr_support_count <= 7'd0;
            csr_error_pulse <= 1'b0;
            csr_error_class <= `RECON_ERROR_CLASS_NONE;
            csr_error_code <= 8'd0;
            csr_error_phase <= 8'd0;
            csr_cfg_error_word <= 5'd0;
            csr_error_detail <= 32'd0;
            cfg_terminal_release <= 1'b0;
            writeback_abort_pending <= 1'b0;
            lifecycle_cycles <= 64'd0;
        end else begin
            csr_done_pulse <= 1'b0;
            csr_error_pulse <= 1'b0;
            cfg_terminal_release <= 1'b0;
            if (state != STATE_IDLE)
                lifecycle_cycles <= lifecycle_cycles + 64'd1;

            case (state)
                STATE_IDLE: begin
                    writeback_abort_pending <= 1'b0;
                    if (run_start) begin
                        state <= STATE_COMPUTE;
                        lifecycle_cycles <= 64'd0;
                    end
                end
                STATE_COMPUTE: begin
                    if (phase_error_pulse) begin
                        csr_error_pulse <= 1'b1;
                        csr_error_class <= phase_error_class;
                        csr_error_code <= phase_error_code;
                        csr_error_phase <= phase_error_phase;
                        csr_cfg_error_word <= phase_cfg_error_word;
                        csr_error_detail <= phase_error_detail;
                        cfg_terminal_release <= active_cfg_valid;
                        state <= STATE_IDLE;
                    end else if (phase_done_pulse) begin
                        if ((phase_stop_reason == `RECON_STOP_ABORTED) ||
                            abort_request) begin
                            csr_done_pulse <= 1'b1;
                            csr_stop_reason <= `RECON_STOP_ABORTED;
                            csr_support_count <= phase_support_count;
                            cfg_terminal_release <= active_cfg_valid;
                            state <= STATE_IDLE;
                        end else begin
                            terminal_stop_reason <= phase_stop_reason;
                            terminal_support_count <= phase_support_count;
                            terminal_support_indices <=
                                final_support_indices;
                            terminal_support_coefficients <=
                                final_support_coefficients;
                            state <= STATE_START_WRITEBACK;
                        end
                    end
                end
                STATE_START_WRITEBACK: begin
                    if (abort_request) begin
                        csr_done_pulse <= 1'b1;
                        csr_stop_reason <= `RECON_STOP_ABORTED;
                        csr_support_count <= terminal_support_count;
                        cfg_terminal_release <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (result_start_valid && result_start_ready) begin
                        state <= STATE_WRITEBACK;
                    end
                end
                STATE_WRITEBACK: begin
                    if (abort_request)
                        writeback_abort_pending <= 1'b1;
                    if (result_error_valid) begin
                        csr_error_pulse <= 1'b1;
                        csr_error_class <= result_error_class;
                        csr_error_code <= result_error_code;
                        csr_error_phase <= phase_progress;
                        csr_cfg_error_word <= 5'd0;
                        csr_error_detail <= {result_error_tag, 5'd0,
                            result_error_beat, 8'd0, result_error_response};
                        cfg_terminal_release <= 1'b1;
                        writeback_abort_pending <= 1'b0;
                        state <= STATE_IDLE;
                    end else if (result_completion_valid) begin
                        csr_done_pulse <= 1'b1;
                        csr_stop_reason <= result_completion_stop_reason;
                        csr_support_count <= terminal_support_count;
                        cfg_terminal_release <= 1'b1;
                        writeback_abort_pending <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_run_outstanding;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_run_outstanding <= 1'b0;
        end else begin
            assert(!(csr_done_pulse && csr_error_pulse));
            assert(!cfg_terminal_release || active_cfg_valid);
            assert(!result_start_valid || (state == STATE_START_WRITEBACK));
            if (run_start) begin
                assert(!f_run_outstanding);
                f_run_outstanding <= 1'b1;
            end
            if (csr_done_pulse || csr_error_pulse) begin
                assert(f_run_outstanding);
                f_run_outstanding <= 1'b0;
            end
            if (state == STATE_WRITEBACK)
                assert(active_cfg_valid);
        end
    end
`endif
endmodule

`default_nettype wire
