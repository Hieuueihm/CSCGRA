`timescale 1ns/1ps
`default_nettype none

// Synthesis-only timing harness.  It closes the real registered path from the
// context BRAM output through the reservation guard into sequencer state.
module m3_context_execution_ooc (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         img_wr_valid,
    output wire         img_wr_ready,
    input  wire         img_wr_bank,
    input  wire [3:0]   img_wr_plane,
    input  wire [7:0]   img_wr_addr,
    input  wire [71:0]  img_wr_data,
    output wire         img_wr_resp_valid,
    input  wire         img_wr_resp_ready,
    output wire         img_wr_resp_error,
    output wire [7:0]   img_wr_resp_code,
    output wire [31:0]  img_wr_resp_detail,
    input  wire         finalize_valid,
    output wire         finalize_ready,
    input  wire         finalize_req_bank,
    output wire         finalize_resp_valid,
    input  wire         finalize_resp_ready,
    output wire         finalize_resp_error,
    output wire [7:0]   finalize_resp_code,
    output wire [31:0]  finalize_resp_detail,
    input  wire         launch_valid,
    output wire         launch_ready,
    input  wire [7:0]   entry_pc,
    input  wire [3:0]   event_id,
    input  wire         abort_pending,
    input  wire [7:0]   predicate_values,
    input  wire         stream_in_ready,
    input  wire         stream_out_ready,
    input  wire         resource_req_ready,
    input  wire         resource_rsp_valid,
    output wire         cycle_valid,
    output wire         cycle_commit,
    output wire         cycle_stalled,
    output wire [7:0]   array_pc,
    output wire [1:0]   cluster_mask,
    output wire [575:0] tile_ctx,
    output wire [35:0]  array_ctx,
    output wire [35:0]  stream_ctx,
    output wire [35:0]  resource_ctx,
    output wire         execution_active,
    output wire         done_valid,
    input  wire         done_ready,
    output wire [3:0]   done_event_id,
    output wire         done_aborted,
    output wire         fault_valid,
    input  wire         fault_ready,
    output wire [7:0]   fault_code,
    output wire [7:0]   fault_pc,
    output wire [31:0]  fault_detail,
    output wire [31:0]  commit_count,
    output wire [31:0]  guaranteed_count,
    output wire [31:0]  elastic_count,
    output wire [31:0]  stall_count
);
    wire ctx_rd_en;
    wire [7:0] ctx_rd_addr;
    wire ctx_rd_resp_valid;
    wire ctx_rd_valid;
    wire active_image_ok;
    wire [8:0] active_ctx_count;
    wire [7:0] ctx_rd_pc;
    wire [575:0] ctx_tiles;
    wire [35:0] ctx_array;
    wire [35:0] ctx_stream;
    wire [35:0] ctx_resource;

    context_image_store u_context_image_store (
        .clk(clk), .rst_n(rst_n), .execution_active(execution_active),
        .active_image_bank(1'b0),
        .active_image_ok(active_image_ok),
        .active_ctx_count(active_ctx_count),
        .finalize_valid(finalize_valid),
        .finalize_ready(finalize_ready),
        .finalize_req_bank(finalize_req_bank),
        .finalize_resp_valid(
            finalize_resp_valid),
        .finalize_resp_ready(
            finalize_resp_ready),
        .finalize_resp_error(
            finalize_resp_error),
        .finalize_resp_code(
            finalize_resp_code),
        .finalize_resp_detail(
            finalize_resp_detail),
        .img_wr_valid(img_wr_valid),
        .img_wr_ready(img_wr_ready),
        .img_wr_bank(img_wr_bank),
        .img_wr_plane(img_wr_plane),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),
        .img_wr_resp_valid(img_wr_resp_valid),
        .img_wr_resp_ready(img_wr_resp_ready),
        .img_wr_resp_error(img_wr_resp_error),
        .img_wr_resp_code(img_wr_resp_code),
        .img_wr_resp_detail(img_wr_resp_detail),
        .array_rd_en(ctx_rd_en),
        .array_rd_addr(ctx_rd_addr),
        .array_rd_resp_valid(ctx_rd_resp_valid),
        .array_rd_valid(ctx_rd_valid),
        .array_rd_pc(ctx_rd_pc),
        .tile_ctx(ctx_tiles),
        .array_ctx(ctx_array),
        .stream_ctx(ctx_stream),
        .resource_ctx(ctx_resource),
        .phase_rd_en(1'b0),
        .phase_rd_addr(8'd0),
        .phase_rd_resp_valid(),
        .phase_rd_valid(),
        .phase_rd_pc(), .phase_word()
    );

    array_context_sequencer u_array_context_sequencer (
        .clk(clk), .rst_n(rst_n),
        .launch_valid(launch_valid), .launch_ready(launch_ready),
        .entry_pc(entry_pc),
        .event_id(event_id),
        .abort_pending(abort_pending),
        .predicate_values(predicate_values),
        .image_ok(active_image_ok),
        .image_count(active_ctx_count),
        .measurement_count(9'd128), .signal_length(11'd1024),
        .sparsity(7'd32), .outer_limit(16'hffff),
        .refine_limit(8'hff),
        .run_param0(16'hffff), .run_param1(16'hffff),
        .stream_in_ready(stream_in_ready),
        .stream_out_ready(stream_out_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid),
        .ctx_rd_en(ctx_rd_en),
        .ctx_rd_addr(ctx_rd_addr),
        .ctx_rd_resp_valid(ctx_rd_resp_valid),
        .ctx_rd_valid(ctx_rd_valid),
        .ctx_rd_pc(ctx_rd_pc),
        .ctx_tiles(ctx_tiles),
        .ctx_array(ctx_array),
        .ctx_stream(ctx_stream),
        .ctx_resource(ctx_resource),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled),
        .array_pc(array_pc),
        .cluster_mask(cluster_mask),
        .tile_ctx(tile_ctx),
        .array_ctx(array_ctx),
        .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx),
        .execution_active(execution_active),
        .done_valid(done_valid), .done_ready(done_ready),
        .done_event_id(done_event_id), .done_aborted(done_aborted),
        .fault_valid(fault_valid), .fault_ready(fault_ready),
        .fault_code(fault_code), .fault_pc(fault_pc),
        .fault_detail(fault_detail),
        .commit_count(commit_count),
        .guaranteed_count(guaranteed_count),
        .elastic_count(elastic_count),
        .stall_count(stall_count)
    );
endmodule

`default_nettype wire
