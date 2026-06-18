`timescale 1ns/1ps

module ls_scratchpad #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 56,
    parameter integer RHS_W = 64,
    parameter integer GE_ADDR_W = 8,
    parameter integer RHS_ADDR_W = 4
)(
    input  wire clk,

    input  wire ge_we,
    input  wire ge_bank_w,
    input  wire [GE_ADDR_W-1:0] ge_waddr,
    input  wire signed [GE_W-1:0] ge_wdata,

    input  wire ge_bank_a,
    input  wire [GE_ADDR_W-1:0] ge_raddr_a,
    output reg  signed [GE_W-1:0] ge_rdata_a,

    input  wire ge_bank_b,
    input  wire [GE_ADDR_W-1:0] ge_raddr_b,
    output reg  signed [GE_W-1:0] ge_rdata_b,

    input  wire rhs_we,
    input  wire rhs_bank_w,
    input  wire [RHS_ADDR_W-1:0] rhs_waddr,
    input  wire signed [RHS_W-1:0] rhs_wdata,

    input  wire rhs_bank_r,
    input  wire [RHS_ADDR_W-1:0] rhs_raddr,
    output reg  signed [RHS_W-1:0] rhs_rdata
);
    localparam integer GE_DEPTH = MAX_K * MAX_K;

    (* ram_style = "block" *) reg signed [GE_W-1:0] ge0_a [0:GE_DEPTH-1];
    (* ram_style = "block" *) reg signed [GE_W-1:0] ge1_a [0:GE_DEPTH-1];
    (* ram_style = "block" *) reg signed [GE_W-1:0] ge0_b [0:GE_DEPTH-1];
    (* ram_style = "block" *) reg signed [GE_W-1:0] ge1_b [0:GE_DEPTH-1];

    (* ram_style = "distributed" *) reg signed [RHS_W-1:0] rhs0 [0:MAX_K-1];
    (* ram_style = "distributed" *) reg signed [RHS_W-1:0] rhs1 [0:MAX_K-1];

    always @(posedge clk) begin
        if (ge_we) begin
            if (ge_bank_w) begin
                ge1_a[ge_waddr] <= ge_wdata;
                ge1_b[ge_waddr] <= ge_wdata;
            end else begin
                ge0_a[ge_waddr] <= ge_wdata;
                ge0_b[ge_waddr] <= ge_wdata;
            end
        end

        ge_rdata_a <= ge_bank_a ? ge1_a[ge_raddr_a] : ge0_a[ge_raddr_a];
        ge_rdata_b <= ge_bank_b ? ge1_b[ge_raddr_b] : ge0_b[ge_raddr_b];

        if (rhs_we) begin
            if (rhs_bank_w)
                rhs1[rhs_waddr] <= rhs_wdata;
            else
                rhs0[rhs_waddr] <= rhs_wdata;
        end
        rhs_rdata <= rhs_bank_r ? rhs1[rhs_raddr] : rhs0[rhs_raddr];
    end
endmodule
