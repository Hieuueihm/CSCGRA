`timescale 1ns/1ps
`default_nettype none

`include "reconstruction_control_defs.vh"

// Owns the fetch -> validate -> atomic active-configuration transaction.
module reconstruction_configuration_unit #(
    parameter integer ADDRESS_W = 64,
    parameter integer TAG_W = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start_valid,
    output wire                   start_ready,
    input  wire [ADDRESS_W-1:0]   start_address,
    input  wire                   abort_request,
    input  wire                   terminal_release,
    output wire                   fetch_active,
    output wire                   validation_active,
    output wire                   control_busy,
    output wire                   dma_req_valid,
    input  wire                   dma_req_ready,
    output wire                   dma_req_write,
    output wire [ADDRESS_W-1:0]   dma_req_addr,
    output wire [15:0]            dma_req_bytes,
    output wire [TAG_W-1:0]       dma_req_tag,
    input  wire                   dma_rd_valid,
    output wire                   dma_rd_ready,
    input  wire [`RECON_DMA_DATA_W-1:0] dma_rd_data,
    input  wire                   dma_rd_last,
    input  wire [1:0]             dma_rd_resp,
    input  wire [TAG_W-1:0]       dma_rd_tag,
    input  wire                   dma_done_valid,
    output wire                   dma_done_ready,
    input  wire [TAG_W-1:0]       dma_done_tag,
    input  wire                   dma_done_error,
    input  wire [1:0]             dma_done_resp,
    input  wire [8:0]             dma_completion_beat,
    output wire                   error_valid,
    input  wire                   error_ready,
    output wire [3:0]             error_class,
    output wire [7:0]             error_code,
    output wire [4:0]             cfg_error_word,
    output wire [31:0]            error_detail,
    output wire                   active_valid,
    output wire [1:0]             result_mode,
    output wire [1:0]             matrix_kind,
    output wire [8:0]             measurement_count,
    output wire [4:0]             measurement_row_blocks,
    output wire [10:0]            signal_length,
    output wire [6:0]             sparsity,
    output wire [15:0]            outer_limit,
    output wire [7:0]             refine_limit,
    output wire [4:0]             normal_residual_shift,
    output wire                   termination_mode,
    output wire [1:0]             refinement_profile,
    output wire [61:0]            residual_limit,
    output wire [63:0]            phi_seed,
    output wire [63:0]            measurement_address,
    output wire [63:0]            dense_result_address,
    output wire [63:0]            sparse_result_address,
    output wire [31:0]            user_tag,
    output wire [17:0]            phi_scale_mantissa_uq17,
    output wire [4:0]             phi_scale_exponent,
    output wire [7:0]             phi_column_weight,
    output wire                   require_unit_norm
);
    wire fetch_start_ready;
    wire fetched_cfg_valid;
    wire fetched_cfg_ready;
    wire [`RECON_RUN_CONFIGURATION_BITS-1:0]
        fetched_cfg_data;
    wire fetch_error_valid;
    wire fetch_error_ready;
    wire [7:0] fetch_error_code;
    wire [4:0] fetch_error_word;
    wire [31:0] fetch_error_detail;
    wire commit_valid;
    wire commit_ready;
    wire [`RECON_RUN_CONFIGURATION_BITS-1:0] commit_data;
    wire validation_error_valid;
    wire validation_error_ready;
    wire [7:0] validation_error_code;
    wire [4:0] validation_error_word;
    wire [31:0] validation_error_detail;

    assign start_ready = fetch_start_ready && !active_valid && !validation_active;
    assign control_busy = fetch_active || validation_active || commit_valid || active_valid;
    assign error_valid = fetch_error_valid || validation_error_valid;
    assign error_class = fetch_error_valid ?
        `RECON_ERROR_CLASS_DMA_READ : `RECON_ERROR_CLASS_RUN_CONFIGURATION;
    assign error_code = fetch_error_valid ? fetch_error_code : validation_error_code;
    assign cfg_error_word = fetch_error_valid ?
        fetch_error_word : validation_error_word;
    assign error_detail = fetch_error_valid ? fetch_error_detail : validation_error_detail;
    assign fetch_error_ready = error_ready;
    assign validation_error_ready = error_ready && !fetch_error_valid;

    configuration_fetch_unit #(
        .ADDRESS_W(ADDRESS_W), .TAG_W(TAG_W)
    ) u_cfg_fetch (
        .clk(clk), .rst_n(rst_n),
        .start_valid(start_valid && start_ready),
        .start_ready(fetch_start_ready), .start_address(start_address),
        .abort_request(abort_request),
        .fetch_active(fetch_active),
        .dma_req_valid(dma_req_valid),
        .dma_req_ready(dma_req_ready),
        .dma_req_write(dma_req_write),
        .dma_req_addr(dma_req_addr),
        .dma_req_bytes(dma_req_bytes), .dma_req_tag(dma_req_tag),
        .dma_rd_valid(dma_rd_valid), .dma_rd_ready(dma_rd_ready),
        .dma_rd_data(dma_rd_data), .dma_rd_last(dma_rd_last),
        .dma_rd_resp(dma_rd_resp), .dma_rd_tag(dma_rd_tag),
        .dma_done_valid(dma_done_valid),
        .dma_done_ready(dma_done_ready),
        .dma_done_tag(dma_done_tag),
        .dma_done_error(dma_done_error),
        .dma_done_resp(dma_done_resp),
        .dma_completion_beat(dma_completion_beat),
        .run_configuration_valid(fetched_cfg_valid),
        .run_configuration_ready(fetched_cfg_ready),
        .run_configuration_data(fetched_cfg_data),
        .error_valid(fetch_error_valid), .error_ready(fetch_error_ready),
        .error_code(fetch_error_code),
        .cfg_error_word(fetch_error_word),
        .error_detail(fetch_error_detail)
    );

    configuration_check_unit u_cfg_check (
        .clk(clk), .rst_n(rst_n),
        .run_configuration_valid(fetched_cfg_valid),
        .run_configuration_ready(fetched_cfg_ready),
        .run_configuration_data(fetched_cfg_data),
        .abort_request(abort_request),
        .validation_active(validation_active),
        .commit_valid(commit_valid), .commit_ready(commit_ready),
        .commit_data(commit_data),
        .error_valid(validation_error_valid),
        .error_ready(validation_error_ready),
        .error_code(validation_error_code),
        .cfg_error_word(validation_error_word),
        .error_detail(validation_error_detail)
    );

    active_configuration_store u_cfg_regs (
        .clk(clk), .rst_n(rst_n),
        .commit_valid(commit_valid), .commit_ready(commit_ready),
        .commit_data(commit_data), .terminal_release(terminal_release),
        .active_valid(active_valid),
        .result_mode(result_mode), .matrix_kind(matrix_kind),
        .measurement_count(measurement_count),
        .measurement_row_blocks(measurement_row_blocks),
        .signal_length(signal_length),
        .sparsity(sparsity), .outer_limit(outer_limit),
        .refine_limit(refine_limit),
        .normal_residual_shift(normal_residual_shift),
        .termination_mode(termination_mode),
        .refinement_profile(refinement_profile),
        .residual_limit(residual_limit),
        .phi_seed(phi_seed), .measurement_address(measurement_address),
        .dense_result_address(dense_result_address),
        .sparse_result_address(sparse_result_address), .user_tag(user_tag),
        .phi_scale_mantissa_uq17(phi_scale_mantissa_uq17),
        .phi_scale_exponent(phi_scale_exponent),
        .phi_column_weight(phi_column_weight),
        .require_unit_norm(require_unit_norm)
    );

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert(!(fetch_error_valid && validation_error_valid));
            assert(!active_valid || !start_ready);
            if (commit_valid)
                assert(!error_valid);
        end
    end
`endif
endmodule

`default_nettype wire
