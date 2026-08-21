`timescale 1ns/1ps

// One-request LS issue boundary.
//
// The controller still owns the phase schedule, but the matrix service is no
// longer its direct endpoint.  This wrapper provides the architectural place
// for a future packet/issue queue while preserving the existing command
// timing: a request accepted in the current cycle is forwarded to the
// row-banked service in that same cycle.  Only one request can be active.
// No arithmetic, memory port, or PE-to-PE direction is changed here.
module ls_issue_engine #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 56,
    parameter integer FACTOR_W = 64,
    parameter integer RHS_W = 64,
    parameter integer FRAC_W = 16,
    parameter integer LANES = 8,
    parameter integer ENABLE_ROW_UPDATE_BLOCK = 0,
    parameter integer ROW_UPDATE_LANES = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [3:0]                   op,
    input  wire [4:0]                   row_a,
    input  wire [4:0]                   col_a,
    input  wire [4:0]                   row_b,
    input  wire [4:0]                   col_b,
    input  wire [4:0]                   row_base,
    input  wire [LANES-1:0]             lane_valid,
    input  wire                         row_update_block,
    input  wire signed [LANES*64-1:0]   lane_add,
    input  wire signed [4*LANES*64-1:0] lane_add4,
    input  wire [4*LANES-1:0]           acc4_lane_valid,
    input  wire [3:0]                   acc4_col_valid,
    input  wire signed [GE_W-1:0]       wdata,
    input  wire signed [4*GE_W-1:0]     write4_wdata,
    input  wire [3:0]                   write4_valid,
    input  wire signed [FACTOR_W-1:0]   factor,
    input  wire signed [RHS_W-1:0]      rhs_wdata,
    output wire                         busy,
    output wire                         done,
    output wire                         acc4_credit,
    output wire signed [GE_W-1:0]       rdata_a,
    output wire signed [GE_W-1:0]       rdata_b,
    output wire signed [4*GE_W-1:0]     read4_rdata,
    output wire signed [GE_W-1:0]       update_value,
    output wire signed [RHS_W-1:0]      rhs_rdata
);
    wire service_busy;
    wire service_done;
    reg active_q;

    // The controller has historically issued only after the previous LS
    // request completed.  Keep that invariant explicit at this boundary; an
    // accidental overlapping pulse is rejected instead of corrupting a row
    // bank.  The accepted pulse itself remains zero-latency to the service.
    wire issue_accept = start && !active_q && !service_busy;

    ls_matrix_service #(
        .MAX_K(MAX_K),
        .GE_W(GE_W),
        .FACTOR_W(FACTOR_W),
        .RHS_W(RHS_W),
        .FRAC_W(FRAC_W),
        .LANES(LANES),
        .ENABLE_ROW_UPDATE_BLOCK(ENABLE_ROW_UPDATE_BLOCK),
        .ROW_UPDATE_LANES(ROW_UPDATE_LANES)
    ) u_ls_matrix_service (
        .clk(clk),
        .rst_n(rst_n),
        .start(issue_accept),
        .op(op),
        .row_a(row_a),
        .col_a(col_a),
        .row_b(row_b),
        .col_b(col_b),
        .row_base(row_base),
        .lane_valid(lane_valid),
        .row_update_block(row_update_block),
        .lane_add(lane_add),
        .lane_add4(lane_add4),
        .acc4_lane_valid(acc4_lane_valid),
        .acc4_col_valid(acc4_col_valid),
        .wdata(wdata),
        .write4_wdata(write4_wdata),
        .write4_valid(write4_valid),
        .factor(factor),
        .rhs_wdata(rhs_wdata),
        .busy(service_busy),
        .done(service_done),
        .acc4_credit(acc4_credit),
        .rdata_a(rdata_a),
        .rdata_b(rdata_b),
        .read4_rdata(read4_rdata),
        .update_value(update_value),
        .rhs_rdata(rhs_rdata)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            active_q <= 1'b0;
        else if (service_done)
            active_q <= 1'b0;
        else if (issue_accept)
            active_q <= 1'b1;
    end

    assign busy = active_q | service_busy;
    assign done = service_done;
endmodule
