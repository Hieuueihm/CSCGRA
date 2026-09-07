`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"

// One-entry AXI element normalizer. External 32-bit D18/S27/index elements are
// checked before narrowing; raw and 64-bit formats pass through unchanged.
module dma_element_normalizer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         input_valid,
    output wire         input_ready,
    input  wire [127:0] input_data,
    input  wire [15:0]  input_keep,
    input  wire         input_last,
    input  wire [2:0]   element_format,
    output reg          output_valid,
    input  wire         output_ready,
    output reg  [127:0] output_data,
    output reg  [3:0]   output_element_valid,
    output reg          output_last,
    output reg          output_error,
    output reg  [1:0]   output_error_lane
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
        normalized_valid = 4'b0000;
        normalized_error = 1'b0;
        normalized_error_lane = 2'd0;
        lane_error = 1'b0;

        if ((element_format == `RECON_ELEMENT_FORMAT_ACC62) ||
            (element_format == `RECON_ELEMENT_FORMAT_RAW64)) begin
            if (input_keep[7:0] == 8'hff)
                normalized_valid[1:0] = 2'b11;
            else if (input_keep[7:0] != 8'h00) begin
                normalized_error = 1'b1;
                normalized_error_lane = 2'd0;
            end
            if (input_keep[15:8] == 8'hff)
                normalized_valid[3:2] = 2'b11;
            else if (input_keep[15:8] != 8'h00) begin
                if (!normalized_error)
                    normalized_error_lane = 2'd2;
                normalized_error = 1'b1;
            end
        end else begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                lane_error = 1'b0;
                if (input_keep[lane*4 +: 4] == 4'hf) begin
                    normalized_valid[lane] = 1'b1;
                    case (element_format)
                        `RECON_ELEMENT_FORMAT_DATA18: begin
                            if (input_data[lane*32+31 -: 14] !=
                                {14{input_data[lane*32+17]}})
                                lane_error = 1'b1;
                            normalized_data[lane*32 +: 32] =
                                {{14{input_data[lane*32+17]}},
                                  input_data[lane*32 +: 18]};
                        end
                        `RECON_ELEMENT_FORMAT_SOLVER27: begin
                            if (input_data[lane*32+31 -: 5] !=
                                {5{input_data[lane*32+26]}})
                                lane_error = 1'b1;
                            normalized_data[lane*32 +: 32] =
                                {{5{input_data[lane*32+26]}},
                                  input_data[lane*32 +: 27]};
                        end
                        `RECON_ELEMENT_FORMAT_INDEX10: begin
                            if (|input_data[lane*32+31 -: 22])
                                lane_error = 1'b1;
                            normalized_data[lane*32 +: 32] =
                                {22'd0, input_data[lane*32 +: 10]};
                        end
                        `RECON_ELEMENT_FORMAT_RAW32,
                        `RECON_ELEMENT_FORMAT_BITMAP1:
                            normalized_data[lane*32 +: 32] =
                                input_data[lane*32 +: 32];
                        default: lane_error = 1'b1;
                    endcase
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

`ifdef FORMAL
    reg f_past_valid;
    reg f_output_valid;
    reg f_output_ready;
    reg [127:0] f_output_data;
    reg [3:0] f_output_element_valid;
    reg f_output_last;
    reg f_output_error;
    reg [1:0] f_output_error_lane;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_output_valid <= output_valid;
        f_output_ready <= output_ready;
        f_output_data <= output_data;
        f_output_element_valid <= output_element_valid;
        f_output_last <= output_last;
        f_output_error <= output_error;
        f_output_error_lane <= output_error_lane;
        if (rst_n && f_past_valid && f_output_valid && !f_output_ready) begin
            assert(output_valid);
            assert(output_data == f_output_data);
            assert(output_element_valid == f_output_element_valid);
            assert(output_last == f_output_last);
            assert(output_error == f_output_error);
            assert(output_error_lane == f_output_error_lane);
        end
    end
`endif
endmodule

`default_nettype wire
