`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module reduction_pipeline #(
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer INDEX_W = 10,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [4:0]                   req_operation,
    input  wire [TAG_W-1:0]             req_tag,
    input  wire [3:0]                   req_lane_mask,
    input  wire [31:0]                  req_lane_valid,
    input  wire [16*ACC_W-1:0]          req_cluster0_data,
    input  wire [16*ACC_W-1:0]          req_cluster1_data,
    input  wire [16*INDEX_W-1:0]        req_cluster0_index,
    input  wire [16*INDEX_W-1:0]        req_cluster1_index,
    input  wire                         req_clear_before,
    input  wire                         req_accumulate,
    input  wire                         req_emit_result,
    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire [4:0]                   rsp_operation,
    output wire [TAG_W-1:0]             rsp_tag,
    output wire signed [ACC_W-1:0]      rsp_data,
    output wire [INDEX_W-1:0]           rsp_index,
    output wire                         rsp_fault
);
    wire cluster0_req_ready;
    wire cluster1_req_ready;
    assign req_ready = cluster0_req_ready && cluster1_req_ready;

    wire cluster0_valid;
    wire cluster0_ready;
    wire [4:0] cluster0_operation;
    wire [TAG_W-1:0] cluster0_tag;
    wire signed [ACC_W-1:0] cluster0_data;
    wire [INDEX_W-1:0] cluster0_index;
    wire cluster0_any;
    wire cluster0_clear_before;
    wire cluster0_accumulate;
    wire cluster0_emit_result;
    wire cluster0_fault;
    wire cluster1_valid;
    wire cluster1_ready;
    wire [4:0] cluster1_operation;
    wire [TAG_W-1:0] cluster1_tag;
    wire signed [ACC_W-1:0] cluster1_data;
    wire [INDEX_W-1:0] cluster1_index;
    wire cluster1_any;
    wire cluster1_clear_before;
    wire cluster1_accumulate;
    wire cluster1_emit_result;
    wire cluster1_fault;

    cluster_reduction_unit #(
        .ACC_W(ACC_W), .INDEX_W(INDEX_W), .TAG_W(TAG_W)
    ) cluster0 (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid),
        .req_ready(cluster0_req_ready), .req_operation(req_operation),
        .req_tag(req_tag), .req_lane_mask(req_lane_mask),
        .req_lane_valid(req_lane_valid[15:0]),
        .req_lane_data(req_cluster0_data),
        .req_lane_index(req_cluster0_index),
        .req_clear_before(req_clear_before),
        .req_accumulate(req_accumulate), .req_emit_result(req_emit_result),
        .rsp_valid(cluster0_valid), .rsp_ready(cluster0_ready),
        .rsp_operation(cluster0_operation), .rsp_tag(cluster0_tag),
        .rsp_data(cluster0_data), .rsp_index(cluster0_index),
        .rsp_any(cluster0_any), .rsp_clear_before(cluster0_clear_before),
        .rsp_accumulate(cluster0_accumulate),
        .rsp_emit_result(cluster0_emit_result), .rsp_fault(cluster0_fault)
    );

    cluster_reduction_unit #(
        .ACC_W(ACC_W), .INDEX_W(INDEX_W), .TAG_W(TAG_W)
    ) cluster1 (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid),
        .req_ready(cluster1_req_ready), .req_operation(req_operation),
        .req_tag(req_tag), .req_lane_mask(req_lane_mask),
        .req_lane_valid(req_lane_valid[31:16]),
        .req_lane_data(req_cluster1_data),
        .req_lane_index(req_cluster1_index),
        .req_clear_before(req_clear_before),
        .req_accumulate(req_accumulate), .req_emit_result(req_emit_result),
        .rsp_valid(cluster1_valid), .rsp_ready(cluster1_ready),
        .rsp_operation(cluster1_operation), .rsp_tag(cluster1_tag),
        .rsp_data(cluster1_data), .rsp_index(cluster1_index),
        .rsp_any(cluster1_any), .rsp_clear_before(cluster1_clear_before),
        .rsp_accumulate(cluster1_accumulate),
        .rsp_emit_result(cluster1_emit_result), .rsp_fault(cluster1_fault)
    );

    global_reduction_merge #(
        .ACC_W(ACC_W), .INDEX_W(INDEX_W), .TAG_W(TAG_W)
    ) merge (
        .clk(clk), .rst_n(rst_n),
        .cluster0_valid(cluster0_valid), .cluster0_ready(cluster0_ready),
        .cluster0_operation(cluster0_operation), .cluster0_tag(cluster0_tag),
        .cluster0_data(cluster0_data), .cluster0_index(cluster0_index),
        .cluster0_any(cluster0_any),
        .cluster0_clear_before(cluster0_clear_before),
        .cluster0_accumulate(cluster0_accumulate),
        .cluster0_emit_result(cluster0_emit_result),
        .cluster0_fault(cluster0_fault),
        .cluster1_valid(cluster1_valid), .cluster1_ready(cluster1_ready),
        .cluster1_operation(cluster1_operation), .cluster1_tag(cluster1_tag),
        .cluster1_data(cluster1_data), .cluster1_index(cluster1_index),
        .cluster1_any(cluster1_any),
        .cluster1_clear_before(cluster1_clear_before),
        .cluster1_accumulate(cluster1_accumulate),
        .cluster1_emit_result(cluster1_emit_result),
        .cluster1_fault(cluster1_fault),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_operation(rsp_operation), .rsp_tag(rsp_tag),
        .rsp_data(rsp_data), .rsp_index(rsp_index), .rsp_fault(rsp_fault)
    );
endmodule

`default_nettype wire
