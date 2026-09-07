`timescale 1ns/1ps
`default_nettype none

// Candidate-only 32-bit external lane checker for D22 or S31.
module candidate_dma_element_normalizer #(
    parameter integer ELEMENT_W = 22
) (
    input wire clk,
    input wire rst_n,
    input wire input_valid,
    output wire input_ready,
    input wire [127:0] input_data,
    input wire [15:0] input_keep,
    input wire input_last,
    output reg output_valid,
    input wire output_ready,
    output reg [127:0] output_data,
    output reg [3:0] output_element_valid,
    output reg output_last,
    output reg output_error,
    output reg [1:0] output_error_lane
);
    integer lane;
    reg [127:0] normalized_data;
    reg [3:0] normalized_valid;
    reg normalized_error;
    reg [1:0] normalized_error_lane;
    reg lane_error;

    assign input_ready = !output_valid;

    always @* begin
        normalized_data = input_data;
        normalized_valid = 4'd0;
        normalized_error = 1'b0;
        normalized_error_lane = 2'd0;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            lane_error = 1'b0;
            if (input_keep[lane*4 +: 4] == 4'hf) begin
                normalized_valid[lane] = 1'b1;
                if (ELEMENT_W < 32 &&
                    input_data[lane*32+31 -: 32-ELEMENT_W] !=
                    {(32-ELEMENT_W){input_data[lane*32+ELEMENT_W-1]}})
                    lane_error = 1'b1;
            end else if (input_keep[lane*4 +: 4] != 4'h0) begin
                lane_error = 1'b1;
            end
            if (lane_error) begin
                if (!normalized_error)
                    normalized_error_lane = lane[1:0];
                normalized_error = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            output_valid <= 1'b0;
            output_data <= 128'd0;
            output_element_valid <= 4'd0;
            output_last <= 1'b0;
            output_error <= 1'b0;
            output_error_lane <= 2'd0;
        end else if (output_valid) begin
            if (output_ready)
                output_valid <= 1'b0;
        end else if (input_valid) begin
            output_valid <= 1'b1;
            output_data <= normalized_data;
            output_element_valid <= normalized_valid;
            output_last <= input_last;
            output_error <= normalized_error;
            output_error_lane <= normalized_error_lane;
        end
    end
endmodule

`default_nettype wire
