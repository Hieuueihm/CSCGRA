`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module phi_stream_subsystem #(
    parameter integer USE_INTERNAL_CACHE = 1
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clear,
    input  wire         abort,

    input  wire [63:0]  seed,
    input  wire [8:0]   measurement_count,
    input  wire [10:0]  signal_length,
    input  wire [6:0]   work_count,
    input  wire [6:0]   support_count,

    input  wire         cmd_valid,
    output wire         cmd_ready,
    input  wire [1:0]   cmd_op,
    input  wire [5:0]   cmd_cfg_id,
    input  wire         cfg_valid,
    input  wire [`RECON_MEMORY_CONFIGURATION_W-1:0] cfg_data,

    input  wire         support_valid,
    output wire         support_ready,
    input  wire [`RECON_PHI_COLUMN_W-1:0] support_col,
    input  wire         refill_pending,
    input  wire         refill_start,
    input  wire [6:0]   refill_support_count,
    input  wire         refill_support_valid,
    output wire         refill_support_ready,
    input  wire [`RECON_PHI_COLUMN_W-1:0] refill_support_col,

    output wire         cache_req_valid,
    input  wire         cache_req_ready,
    output wire [6:0]   cache_req_slot,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_req_row,
    output wire [`RECON_PHI_TAG_W-1:0] cache_req_tag,
    input  wire         cache_rsp_valid,
    output wire         cache_rsp_ready,
    input  wire [31:0]  cache_rsp_mask,
    input  wire [31:0]  cache_rsp_sign,
    input  wire [`RECON_PHI_COLUMN_W-1:0] cache_rsp_col,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_rsp_row,
    input  wire [`RECON_PHI_TAG_W-1:0] cache_rsp_tag,
    input  wire         cache_ext_valid,

    input  wire         cache_invalidate,
    input  wire         cache_prepare_valid,
    output wire         cache_prepare_ready,
    input  wire         cache_prepare_from_candidates,
    input  wire [6:0]   cache_prepare_support_count,
    input  wire [6:0]   cache_prepare_preserve_count,
    input  wire         cache_candidate_valid,
    output wire         cache_candidate_ready,
    input  wire [5:0]   cache_candidate_slot,
    input  wire [`RECON_PHI_COLUMN_W-1:0] cache_candidate_col,
    input  wire         cache_release_event,
    input  wire [`RECON_PHI_COLUMN_W-1:0] cache_release_event_col,
    input  wire         cache_promote_valid,
    output wire         cache_promote_ready,
    input  wire [5:0]   cache_promote_candidate_slot,
    input  wire [6:0]   cache_promote_support_slot,
    output wire         cache_capture_ready,
    output wire         cache_fill_fire,
    output wire         event_generate_request_fire,
    output wire         event_replay_request_fire,
    output wire         event_replay_response_fire,

    output wire         out_valid,
    input  wire         out_ready,
    output wire [31:0]  out_mask,
    output wire [31:0]  out_sign,
    output wire [`RECON_PHI_COLUMN_W-1:0] out_col,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] out_row,
    output wire [`RECON_PHI_TAG_W-1:0] out_tag,
    output wire         out_fire,

    output wire         status_busy,
    output wire         status_done,
    output wire         status_cfg_error,
    output wire [2:0]   status_mode,
    output wire         status_refill_active,
    output wire         status_capture_enable,
    output wire         status_cache_valid,
    output wire         status_cache_busy,
    output wire         status_cache_fault
);
    wire internal_req_ready;
    wire internal_rsp_valid;
    wire [31:0] internal_rsp_mask;
    wire [31:0] internal_rsp_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] internal_rsp_col;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] internal_rsp_row;
    wire [`RECON_PHI_TAG_W-1:0] internal_rsp_tag;
    wire internal_cache_valid;
    wire internal_cache_busy;
    wire internal_cache_fault;
    wire internal_prepare_ready;
    wire internal_fill_ready;
    wire internal_capture_ready;
    wire internal_candidate_ready;
    wire internal_promote_ready;
    wire provider_support_ready;

    localparam [5:0] DENSE_NO_CAPTURE_CFG_ID = 6'd44;

    reg [2:0] mode_q;
    reg capture_suppress_q;
    reg [6:0] fill_slot_q;
    reg release_pending_q;
    reg [`RECON_PHI_COLUMN_W-1:0] release_col_q;

    wire cmd_start_fire = cmd_valid && cmd_ready &&
        (cmd_op == `RECON_PHI_COMMAND_START);
    wire refill_active = USE_INTERNAL_CACHE && refill_pending &&
        (mode_q == 3'd1);
    wire capture_enable = USE_INTERNAL_CACHE && !refill_active &&
        !capture_suppress_q && (mode_q != 3'd3) && (mode_q != 3'd5);
    wire [6:0] provider_support_count = (refill_pending || refill_start) ?
        refill_support_count : support_count;
    wire provider_support_valid = refill_pending ?
        refill_support_valid : support_valid;
    wire [`RECON_PHI_COLUMN_W-1:0] provider_support_col = refill_pending ?
        refill_support_col : support_col;
    wire release_valid = release_pending_q &&
        !(cache_candidate_valid && cache_candidate_ready);
    wire [3:0] row_count =
        ({1'b0, measurement_count} + 10'd31) >> 5;
    wire final_row = ({1'b0, out_row} + 4'd1) == row_count;

    wire provider_req_ready = USE_INTERNAL_CACHE ?
        internal_req_ready : cache_req_ready;
    wire provider_rsp_valid = USE_INTERNAL_CACHE ?
        internal_rsp_valid : cache_rsp_valid;
    wire [31:0] provider_rsp_mask = USE_INTERNAL_CACHE ?
        internal_rsp_mask : cache_rsp_mask;
    wire [31:0] provider_rsp_sign = USE_INTERNAL_CACHE ?
        internal_rsp_sign : cache_rsp_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] provider_rsp_col =
        USE_INTERNAL_CACHE ? internal_rsp_col : cache_rsp_col;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] provider_rsp_row =
        USE_INTERNAL_CACHE ? internal_rsp_row : cache_rsp_row;
    wire [`RECON_PHI_TAG_W-1:0] provider_rsp_tag =
        USE_INTERNAL_CACHE ? internal_rsp_tag : cache_rsp_tag;
    wire provider_cache_valid = USE_INTERNAL_CACHE ?
        internal_cache_valid : cache_ext_valid;

    wire cache_fill_valid = refill_active && out_valid;
    wire cache_capture_valid = capture_enable && out_valid && out_ready;
    wire provider_out_ready = refill_active ?
        internal_fill_ready :
        (out_ready && (!capture_enable || internal_capture_ready));

    assign support_ready = !refill_pending && provider_support_ready;
    assign refill_support_ready = provider_support_ready;
    assign cache_prepare_ready = USE_INTERNAL_CACHE ?
        internal_prepare_ready : 1'b1;
    assign cache_candidate_ready = USE_INTERNAL_CACHE ?
        internal_candidate_ready : 1'b1;
    assign cache_promote_ready = USE_INTERNAL_CACHE ?
        internal_promote_ready : 1'b1;
    assign cache_capture_ready = internal_capture_ready;
    assign cache_fill_fire = cache_fill_valid && internal_fill_ready;
    assign out_fire = out_valid && provider_out_ready;
    assign status_mode = mode_q;
    assign status_refill_active = refill_active;
    assign status_capture_enable = capture_enable;
    assign status_cache_valid = USE_INTERNAL_CACHE ? internal_cache_valid : 1'b1;
    assign status_cache_busy = USE_INTERNAL_CACHE ? internal_cache_busy : 1'b0;
    assign status_cache_fault = USE_INTERNAL_CACHE ? internal_cache_fault : 1'b0;

    phi_stream_provider u_provider (
        .clk(clk),
        .rst_n(rst_n),
        .abort_flush(abort),
        .active_seed(seed),
        .active_measurement_count(measurement_count),
        .active_signal_length(signal_length),
        .active_work_count(work_count),
        .support_list_count(provider_support_count),
        .command_valid(cmd_valid),
        .command_ready(cmd_ready),
        .command(cmd_op),
        .configuration_id(cmd_cfg_id),
        .configuration_valid(cfg_valid),
        .configuration_data(cfg_data),
        .support_column_valid(provider_support_valid),
        .support_column_ready(provider_support_ready),
        .support_column(provider_support_col),
        .cache_replay_valid(cache_req_valid),
        .cache_replay_ready(provider_req_ready),
        .cache_replay_slot(cache_req_slot),
        .cache_replay_row_block(cache_req_row),
        .cache_replay_tag(cache_req_tag),
        .cache_symbol_valid(provider_rsp_valid),
        .cache_symbol_ready(cache_rsp_ready),
        .cache_nonzero(provider_rsp_mask),
        .cache_sign(provider_rsp_sign),
        .cache_column(provider_rsp_col),
        .cache_row_block(provider_rsp_row),
        .cache_tag(provider_rsp_tag),
        .cache_valid(provider_cache_valid),
        .phi_symbol_valid(out_valid),
        .phi_symbol_ready(provider_out_ready),
        .phi_nonzero(out_mask),
        .phi_sign(out_sign),
        .phi_column(out_col),
        .phi_row_block(out_row),
        .phi_tag(out_tag),
        .provider_busy(status_busy),
        .stream_done(status_done),
        .configuration_error(status_cfg_error),
        .event_generate_request_fire(event_generate_request_fire),
        .event_replay_request_fire(event_replay_request_fire),
        .event_replay_response_fire(event_replay_response_fire)
    );

    support_phi_symbol_cache u_cache (
        .clk(clk),
        .rst_n(rst_n),
        .invalidate(cache_invalidate),
        .measurement_count(measurement_count),
        .prepare_valid(USE_INTERNAL_CACHE && cache_prepare_valid),
        .prepare_ready(internal_prepare_ready),
        .prepare_from_candidates(cache_prepare_from_candidates),
        .prepare_support_count(cache_prepare_support_count),
        .prepare_preserve_count(cache_prepare_preserve_count),
        .prepare_row_block_count(row_count[2:0]),
        .fill_valid(cache_fill_valid),
        .fill_ready(internal_fill_ready),
        .fill_slot(fill_slot_q),
        .fill_row_block(out_row),
        .fill_column(out_col),
        .fill_nonzero(out_mask),
        .fill_sign(out_sign),
        .capture_valid(cache_capture_valid),
        .capture_ready(internal_capture_ready),
        .capture_column(out_col),
        .capture_row_block(out_row),
        .capture_nonzero(out_mask),
        .capture_sign(out_sign),
        .candidate_store_valid(USE_INTERNAL_CACHE && cache_candidate_valid),
        .candidate_store_ready(internal_candidate_ready),
        .candidate_store_slot(cache_candidate_slot),
        .candidate_store_column(cache_candidate_col),
        .candidate_release_valid(USE_INTERNAL_CACHE && release_valid),
        .candidate_release_column(release_col_q),
        .promote_valid(USE_INTERNAL_CACHE && cache_promote_valid),
        .promote_ready(internal_promote_ready),
        .promote_candidate_slot(cache_promote_candidate_slot),
        .promote_support_slot(cache_promote_support_slot),
        .replay_valid(USE_INTERNAL_CACHE && cache_req_valid),
        .replay_ready(internal_req_ready),
        .replay_slot(cache_req_slot),
        .replay_row_block(cache_req_row),
        .replay_tag(cache_req_tag),
        .replay_response_valid(internal_rsp_valid),
        .replay_response_ready(cache_rsp_ready),
        .replay_nonzero(internal_rsp_mask),
        .replay_sign(internal_rsp_sign),
        .replay_column(internal_rsp_col),
        .replay_response_slot(),
        .replay_response_row_block(internal_rsp_row),
        .replay_response_tag(internal_rsp_tag),
        .cache_valid(internal_cache_valid),
        .cache_busy(internal_cache_busy),
        .cache_fault(internal_cache_fault)
    );

    always @(posedge clk) begin
        if (!rst_n || clear || abort) begin
            mode_q <= 3'd0;
            capture_suppress_q <= 1'b0;
            fill_slot_q <= 7'd0;
            release_pending_q <= 1'b0;
            release_col_q <= {`RECON_PHI_COLUMN_W{1'b0}};
        end else begin
            if (cmd_start_fire) begin
                mode_q <= cfg_data[51:49];
                capture_suppress_q <= cmd_cfg_id == DENSE_NO_CAPTURE_CFG_ID;
            end

            if (!refill_pending)
                fill_slot_q <= 7'd0;
            else if (cache_fill_fire && final_row)
                fill_slot_q <= fill_slot_q + 1'b1;

            if (cache_release_event) begin
                release_pending_q <= 1'b1;
                release_col_q <= cache_release_event_col;
            end else begin
                release_pending_q <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
