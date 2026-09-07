`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Eight-entry two-read/one-write local state. Data bits are not reset so the
// FPGA can infer distributed RAM; reset clears only architectural valid bits.
module pe_local_register_file #(
    parameter integer DATA_W = `RECON_SOLVER_W
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_all,
    input  wire [2:0]              read_address_a,
    input  wire [2:0]              read_address_b,
    output wire signed [DATA_W-1:0] read_data_a,
    output wire signed [DATA_W-1:0] read_data_b,
    output wire                    read_valid_a,
    output wire                    read_valid_b,
    input  wire                    write_enable,
    input  wire [2:0]              write_address,
    input  wire signed [DATA_W-1:0] write_data
);
    (* ram_style = "distributed" *) reg signed [DATA_W-1:0] data [0:7];
    reg [7:0] valid_bits;

    assign read_valid_a = valid_bits[read_address_a];
    assign read_valid_b = valid_bits[read_address_b];
    assign read_data_a = read_valid_a ? data[read_address_a] : {DATA_W{1'b0}};
    assign read_data_b = read_valid_b ? data[read_address_b] : {DATA_W{1'b0}};

    always @(posedge clk) begin
        if (!rst_n || clear_all) begin
            valid_bits <= 8'd0;
        end else if (write_enable) begin
            data[write_address] <= write_data;
            valid_bits[write_address] <= 1'b1;
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n && write_enable) begin
            assert(write_address < 8);
        end
    end
`endif
endmodule

`default_nettype wire
