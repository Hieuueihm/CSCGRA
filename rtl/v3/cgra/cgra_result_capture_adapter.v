`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module cgra_result_capture_adapter #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W
)(
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire                         vec_w_en,
    input  wire [2:0]                   write_format,
    input  wire                         capture_start,
    input  wire                         normalizer_output_fire,
    input  wire [`RECON_PHI_TAG_W-1:0]  normalizer_output_tag,
    input  wire signed [DATA_W-1:0]     normalizer_output_data,
    input  wire                         residual_mode,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] row_block,
    input  wire [8:0]                   measurement_count,
    input  wire [32*DATA_W-1:0]         measurement_buffer,
    input  wire                         result_low_valid,
    input  wire                         result_high_valid,
    input  wire                         result_s27_high_select,
    output wire                         write_is_d18,
    output wire                         write_is_s27,
    output wire                         result_available,
    output wire                         capture_start_event,
    output wire                         capture_valid,
    output wire [4:0]                   capture_index,
    output wire [DATA_W-1:0]            capture_data,
    output wire                         capture_low_complete,
    output wire                         capture_high_complete,
    output wire                         consume_d18,
    output wire                         consume_s27
);
    function [DATA_W-1:0] residual_from_normalized_solver;
        input signed [DATA_W-1:0] measurement;
        input signed [DATA_W-1:0] fitted_solver;
        reg [DATA_W-1:0] solver_magnitude;
        reg [DATA_W-1:0] rounded_magnitude;
        reg signed [DATA_W:0] fitted_rounded;
        reg signed [17:0] fitted_data;
        reg signed [18:0] residual_wide;
        begin
            solver_magnitude = fitted_solver[DATA_W-1] ?
                (~fitted_solver + {{DATA_W-1{1'b0}}, 1'b1}) : fitted_solver;
            rounded_magnitude =
                (solver_magnitude + {{(DATA_W-5){1'b0}}, 5'd16}) >> 5;
            fitted_rounded = fitted_solver[DATA_W-1] ?
                -$signed({1'b0, rounded_magnitude}) :
                 $signed({1'b0, rounded_magnitude});
            if (fitted_rounded > 28'sd131071)
                fitted_data = 18'sd131071;
            else if (fitted_rounded < -28'sd131072)
                fitted_data = -18'sd131072;
            else
                fitted_data = fitted_rounded[17:0];
            residual_wide = $signed(measurement[17:0]) - fitted_data;
            if (residual_wide > 19'sd131071)
                residual_from_normalized_solver =
                    {{(DATA_W-18){1'b0}}, 18'sd131071};
            else if (residual_wide < -19'sd131072)
                residual_from_normalized_solver =
                    {{(DATA_W-18){1'b1}}, -18'sd131072};
            else
                residual_from_normalized_solver =
                    {{(DATA_W-18){residual_wide[17]}}, residual_wide[17:0]};
        end
    endfunction

    wire [4:0] output_index = normalizer_output_tag[4:0];
    wire [8:0] measurement_index =
        {1'b0, row_block, 5'd0} + output_index;
    wire signed [DATA_W-1:0] measurement_value =
        measurement_buffer[output_index*DATA_W +: DATA_W];

    assign write_is_d18 = write_format == `RECON_ELEMENT_FORMAT_DATA18;
    assign write_is_s27 = write_format == `RECON_ELEMENT_FORMAT_SOLVER27;
    assign capture_start_event = capture_start;
    assign capture_valid = normalizer_output_fire;
    assign capture_index = output_index;
    assign result_available = write_is_d18 ? result_high_valid :
        result_s27_high_select ? result_high_valid : result_low_valid;
    assign capture_data = residual_mode ?
        ((measurement_index >= measurement_count) ?
         {DATA_W{1'b0}} :
         residual_from_normalized_solver(measurement_value,
                                          normalizer_output_data)) :
        normalizer_output_data;
    assign capture_low_complete = !residual_mode && (output_index == 5'd15);
    assign capture_high_complete = output_index == 5'd31;
    assign consume_d18 = cycle_valid && cycle_commit && vec_w_en && write_is_d18;
    assign consume_s27 = cycle_valid && cycle_commit && vec_w_en &&
                         write_is_s27 && result_available;
endmodule

`default_nettype wire
