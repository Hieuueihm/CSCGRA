`timescale 1ns/1ps
`default_nettype none

module recon_1w2r_ram #(
    parameter integer DATA_W = 32,
    parameter integer DEPTH = 1024,
    parameter integer ADDR_W = 10,
    parameter integer INITIALIZE_TO_ZERO = 0
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  write_enable,
    input  wire [ADDR_W-1:0]     write_address,
    input  wire [DATA_W-1:0]     write_data,
    input  wire                  read0_enable,
    input  wire [ADDR_W-1:0]     read0_address,
    output wire                  read0_valid,
    output wire [DATA_W-1:0]     read0_data,
    input  wire                  read1_enable,
    input  wire [ADDR_W-1:0]     read1_address,
    output wire                  read1_valid,
    output wire [DATA_W-1:0]     read1_data
);
    recon_sdp_ram #(
        .DATA_W(DATA_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W),
        .INITIALIZE_TO_ZERO(INITIALIZE_TO_ZERO)
    ) u_read0_copy (
        .clk(clk), .rst_n(rst_n),
        .write_enable(write_enable), .write_address(write_address),
        .write_data(write_data), .read_enable(read0_enable),
        .read_address(read0_address), .read_valid(read0_valid),
        .read_data(read0_data)
    );

    recon_sdp_ram #(
        .DATA_W(DATA_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W),
        .INITIALIZE_TO_ZERO(INITIALIZE_TO_ZERO)
    ) u_read1_copy (
        .clk(clk), .rst_n(rst_n),
        .write_enable(write_enable), .write_address(write_address),
        .write_data(write_data), .read_enable(read1_enable),
        .read_address(read1_address), .read_valid(read1_valid),
        .read_data(read1_data)
    );
endmodule

`default_nettype wire
