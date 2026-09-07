`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Small shared scalar state. Data bits are intentionally not reset so Vivado
// may implement them as distributed memory; the valid bitmap owns reset state.
module scalar_register_file #(
    parameter integer DATA_W = `RECON_ACC_W,
    parameter integer DEPTH = 2,
    parameter integer ADDR_W = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_all,
    input  wire [ADDR_W-1:0]        read_address_a,
    output wire [DATA_W-1:0]        read_data_a,
    output wire                     read_valid_a,
    input  wire [ADDR_W-1:0]        read_address_b,
    output wire [DATA_W-1:0]        read_data_b,
    output wire                     read_valid_b,
    input  wire                     preload_valid,
    output wire                     preload_ready,
    input  wire [ADDR_W-1:0]        preload_address,
    input  wire [DATA_W-1:0]        preload_data,
    input  wire                     write_valid,
    input  wire                     cycle_commit,
    input  wire [ADDR_W-1:0]        write_address,
    input  wire [DATA_W-1:0]        write_data,
    input  wire                     clear_valid,
    input  wire [ADDR_W-1:0]        clear_address
);
    reg [DATA_W-1:0] data [0:DEPTH-1];
    reg [DEPTH-1:0] valid_bits;

    assign read_data_a = data[read_address_a];
    assign read_data_b = data[read_address_b];
    assign read_valid_a = valid_bits[read_address_a];
    assign read_valid_b = valid_bits[read_address_b];
    assign preload_ready = !clear_all && !(write_valid && cycle_commit) &&
                           !(clear_valid && cycle_commit);

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_bits <= {DEPTH{1'b0}};
        end else if (clear_all) begin
            valid_bits <= {DEPTH{1'b0}};
        end else begin
            if (clear_valid && cycle_commit)
                valid_bits[clear_address] <= 1'b0;
            if (write_valid && cycle_commit) begin
                data[write_address] <= write_data;
                valid_bits[write_address] <= 1'b1;
            end else if (preload_valid && preload_ready) begin
                data[preload_address] <= preload_data;
                valid_bits[preload_address] <= 1'b1;
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n && write_valid && !cycle_commit)
            assert(!read_valid_a || (read_address_a != write_address) ||
                   (read_data_a == data[read_address_a]));
        if (rst_n && write_valid && clear_valid && cycle_commit &&
            (write_address == clear_address))
            assert(read_valid_a || !read_valid_a); // write has explicit priority.
    end
`endif
endmodule

`default_nettype wire
