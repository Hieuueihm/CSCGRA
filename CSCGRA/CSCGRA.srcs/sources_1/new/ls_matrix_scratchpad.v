`timescale 1ns/1ps

module ls_matrix_scratchpad #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 64,
    parameter integer RHS_W = 64
)(
    input  wire clk,

    input  wire ge_we,
    input  wire ge_bank_w,
    input  wire [4:0] ge_wrow,
    input  wire [4:0] ge_wcol,
    input  wire signed [GE_W-1:0] ge_wdata,

    input  wire ge_bank_a,
    input  wire [4:0] ge_rrow_a,
    input  wire [4:0] ge_rcol_a,
    output reg  signed [GE_W-1:0] ge_rdata_a,

    input  wire ge_bank_b,
    input  wire [4:0] ge_rrow_b,
    input  wire [4:0] ge_rcol_b,
    output reg  signed [GE_W-1:0] ge_rdata_b,

    input  wire rhs_we,
    input  wire rhs_bank_w,
    input  wire [4:0] rhs_waddr,
    input  wire signed [RHS_W-1:0] rhs_wdata,

    input  wire rhs_bank_r,
    input  wire [4:0] rhs_raddr,
    output reg  signed [RHS_W-1:0] rhs_rdata
);
    localparam integer GE_DEPTH = 512;

    wire [8:0] ge_waddr = {ge_bank_w, ge_wrow[3:0], ge_wcol[3:0]};
    wire [8:0] ge_addr_a = {ge_bank_a, ge_rrow_a[3:0], ge_rcol_a[3:0]};
    wire [8:0] ge_addr_b = {ge_bank_b, ge_rrow_b[3:0], ge_rcol_b[3:0]};

    (* ram_style = "block" *) reg signed [GE_W-1:0] ge_mem_a [0:GE_DEPTH-1];
    (* ram_style = "block" *) reg signed [GE_W-1:0] ge_mem_b [0:GE_DEPTH-1];
    (* ram_style = "distributed" *) reg signed [RHS_W-1:0] rhs_mem [0:31];

    wire [4:0] rhs_waddr_i = {rhs_bank_w, rhs_waddr[3:0]};
    wire [4:0] rhs_raddr_i = {rhs_bank_r, rhs_raddr[3:0]};

    always @(posedge clk) begin
        if (ge_we) begin
            ge_mem_a[ge_waddr] <= ge_wdata;
            ge_mem_b[ge_waddr] <= ge_wdata;
        end
        ge_rdata_a <= ge_mem_a[ge_addr_a];
        ge_rdata_b <= ge_mem_b[ge_addr_b];

        if (rhs_we)
            rhs_mem[rhs_waddr_i] <= rhs_wdata;
        rhs_rdata <= rhs_mem[rhs_raddr_i];
    end
endmodule
