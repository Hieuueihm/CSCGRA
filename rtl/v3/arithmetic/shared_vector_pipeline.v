`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module shared_vector_pipeline #(
    parameter integer LANES = `RECON_SHARED_VECTOR_LANES,
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [4:0]                   req_operation,
    input  wire [TAG_W-1:0]             req_tag,
    input  wire [LANES-1:0]             req_lane_valid,
    input  wire [LANES*DATA_W-1:0]      req_a,
    input  wire [LANES*DATA_W-1:0]      req_b,
    input  wire signed [DATA_W-1:0]     req_scalar,
    input  wire                         req_clear,
    input  wire                         req_accumulate,
    input  wire                         req_emit,
    input  wire                         req_subtract,
    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire [4:0]                   rsp_operation,
    output wire [TAG_W-1:0]             rsp_tag,
    output wire [LANES-1:0]             rsp_lane_valid,
    output wire [LANES*DATA_W-1:0]      rsp_data,
    output wire signed [ACC_W-1:0]      rsp_scalar,
    output wire [LANES-1:0]             rsp_saturated,
    output wire                         rsp_fault
);
    shared_vector_arithmetic_unit #(
        .LANES(LANES), .DATA_W(DATA_W), .ACC_W(ACC_W), .TAG_W(TAG_W)
    ) u_unit (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_operation(req_operation), .req_tag(req_tag),
        .req_lane_valid(req_lane_valid), .req_vector_a(req_a),
        .req_vector_b(req_b), .req_scalar(req_scalar),
        .req_clear_before(req_clear), .req_accumulate(req_accumulate),
        .req_emit_result(req_emit), .req_subtract(req_subtract),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_operation(rsp_operation), .rsp_tag(rsp_tag),
        .rsp_lane_valid(rsp_lane_valid), .rsp_vector(rsp_data),
        .rsp_scalar(rsp_scalar), .rsp_saturated(rsp_saturated),
        .rsp_fault(rsp_fault)
    );
endmodule

`default_nettype wire

