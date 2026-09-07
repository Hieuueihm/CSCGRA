`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_symbol_builder (
    input  wire         input_valid,
    output wire         input_ready,
    input  wire [31:0]  input_word0,
    input  wire [31:0]  input_word1,
    input  wire [`RECON_PHI_COLUMN_W-1:0] input_column,
    input  wire [`RECON_PHI_ROW_PAIR_W-1:0] input_row_pair,
    input  wire [`RECON_PHI_TAG_W-1:0] input_tag,
    input  wire [8:0]   input_measurement_count,
    output wire         output_valid,
    input  wire         output_ready,
    output wire [31:0]  output_nonzero0,
    output wire [31:0]  output_sign0,
    output wire [31:0]  output_nonzero1,
    output wire [31:0]  output_sign1,
    output wire [`RECON_PHI_COLUMN_W-1:0] output_column,
    output wire [`RECON_PHI_ROW_PAIR_W-1:0] output_row_pair,
    output wire [`RECON_PHI_TAG_W-1:0] output_tag
);
    function [31:0] lane_mask;
        input [8:0] measurement_count;
        input [3:0] row_block;
        reg [9:0] row_base;
        reg [9:0] remaining;
        begin
            row_base = {row_block, 5'b00000};
            if ({1'b0, measurement_count} <= row_base)
                lane_mask = 32'd0;
            else begin
                remaining = {1'b0, measurement_count} - row_base;
                if (remaining >= 10'd32)
                    lane_mask = 32'hffff_ffff;
                else
                    lane_mask = (32'h0000_0001 << remaining[4:0]) - 1'b1;
            end
        end
    endfunction

    wire [3:0] row_block0 = {input_row_pair, 1'b0};
    wire [3:0] row_block1 = {input_row_pair, 1'b1};
    assign input_ready = output_ready;
    assign output_valid = input_valid;
    assign output_nonzero0 = lane_mask(input_measurement_count, row_block0);
    assign output_nonzero1 = lane_mask(input_measurement_count, row_block1);
    assign output_sign0 = input_word0;
    assign output_sign1 = input_word1;
    assign output_column = input_column;
    assign output_row_pair = input_row_pair;
    assign output_tag = input_tag;
endmodule

`default_nettype wire
