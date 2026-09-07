`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module cgra_result_buffer #(
    parameter integer LANE_COUNT = `RECON_PE_COUNT,
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 5
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_event,
    input  wire                         capture_start_event,
    input  wire                         capture_valid,
    input  wire [INDEX_W-1:0]           capture_index,
    input  wire [DATA_W-1:0]            capture_data,
    input  wire                         capture_low_complete,
    input  wire                         capture_high_complete,
    input  wire                         consume_d18_event,
    input  wire                         consume_s27_event,
    output reg  [LANE_COUNT*DATA_W-1:0] result_data,
    output reg                          low_valid,
    output reg                          high_valid,
    output reg                          s27_high_select,
    output wire                         busy
);
    assign busy = low_valid || high_valid;

    always @(posedge clk) begin
        if (!rst_n || clear_event) begin
            result_data <= {LANE_COUNT*DATA_W{1'b0}};
            low_valid <= 1'b0;
            high_valid <= 1'b0;
            s27_high_select <= 1'b0;
        end else begin
            if (capture_start_event) begin
                low_valid <= 1'b0;
                high_valid <= 1'b0;
                s27_high_select <= 1'b0;
            end else if (capture_valid) begin
                result_data[capture_index*DATA_W +: DATA_W] <= capture_data;
                if (capture_low_complete)
                    low_valid <= 1'b1;
                if (capture_high_complete)
                    high_valid <= 1'b1;
            end

            if (consume_d18_event) begin
                low_valid <= 1'b0;
                high_valid <= 1'b0;
            end

            if (consume_s27_event) begin
                if (s27_high_select) begin
                    s27_high_select <= 1'b0;
                    high_valid <= 1'b0;
                end else begin
                    s27_high_select <= 1'b1;
                    low_valid <= 1'b0;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_prev_consume_d18;
    reg f_prev_consume_low_s27;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_past_valid <= 1'b0;
            f_prev_consume_d18 <= 1'b0;
            f_prev_consume_low_s27 <= 1'b0;
        end else begin
            if (f_past_valid) begin
                if (f_prev_consume_d18) begin
                    assert(!low_valid);
                    assert(!high_valid);
                end
                if (f_prev_consume_low_s27)
                    assert(s27_high_select);
            end
            f_past_valid <= 1'b1;
            f_prev_consume_d18 <= !clear_event && consume_d18_event;
            f_prev_consume_low_s27 <= !clear_event && consume_s27_event &&
                                      !s27_high_select;
        end
    end
`endif
endmodule

`default_nettype wire
