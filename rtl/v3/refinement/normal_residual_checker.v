`timescale 1ns/1ps
`default_nettype none

module normal_residual_checker #(
    parameter integer ENERGY_W = 62,
    parameter integer TAG_W = 3
)(
    input  wire clk,
    input  wire rst_n,
    input  wire request_valid,
    output wire request_ready,
    input  wire [TAG_W-1:0] request_tag,
    input  wire [6:0] support_count,
    input  wire [8:0] measurement_count,
    input  wire [4:0] normal_residual_shift,
    input  wire [7:0] iterations_used,
    input  wire [ENERGY_W-1:0] gamma_reference,
    input  wire [ENERGY_W-1:0] normal_residual_sq,
    input  wire absolute_limit_enable,
    input  wire [ENERGY_W-1:0] absolute_limit,
    input  wire breakdown,
    input  wire saturation,
    output reg  response_valid,
    input  wire response_ready,
    output reg  [TAG_W-1:0] response_tag,
    output reg  certificate_pass,
    output reg  need_more_refinement,
    output reg  restart_required,
    output reg  response_breakdown,
    output reg  response_saturation,
    output reg  [7:0] response_iterations_used,
    output reg  [2:0] stop_reason,
    output reg  [ENERGY_W-1:0] relative_limit,
    output reg  [ENERGY_W-1:0] quantization_floor,
    output reg  [ENERGY_W-1:0] certificate_limit
);
    localparam [2:0] STOP_CERTIFICATE_PASS = 3'd1;
    localparam [2:0] STOP_CERTIFICATE_FAIL = 3'd2;
    localparam [2:0] STOP_BREAKDOWN = 3'd3;
    localparam [2:0] STOP_SATURATION = 3'd4;
    wire response_advance = !response_valid || response_ready;
    assign request_ready = !response_valid;
    wire request_accept = request_valid && request_ready;

    wire [ENERGY_W-1:0] computed_relative_limit;
    wire [ENERGY_W-1:0] computed_quantization_floor;
    wire [ENERGY_W-1:0] computed_certificate_limit;
    wire selected_pass = !breakdown && !saturation &&
        (normal_residual_sq <= computed_certificate_limit);

    certificate_limit_unit #(.ENERGY_W(ENERGY_W)) u_limit (
        .support_count(support_count),
        .measurement_count(measurement_count),
        .normal_residual_shift(normal_residual_shift),
        .gamma_reference(gamma_reference),
        .absolute_limit_enable(absolute_limit_enable),
        .absolute_limit(absolute_limit),
        .relative_limit(computed_relative_limit),
        .quantization_floor(computed_quantization_floor),
        .certificate_limit(computed_certificate_limit)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            response_valid <= 0;
            response_tag <= 0;
            certificate_pass <= 0;
            need_more_refinement <= 0;
            restart_required <= 0;
            response_breakdown <= 0;
            response_saturation <= 0;
            response_iterations_used <= 0;
            stop_reason <= 0;
            relative_limit <= 0;
            quantization_floor <= 0;
            certificate_limit <= 0;
        end else begin
            if (response_valid && response_ready)
                response_valid <= 0;
            if (request_accept) begin
                response_valid <= 1;
                response_tag <= request_tag;
                certificate_pass <= selected_pass;
                need_more_refinement <= !selected_pass && !breakdown && !saturation;
                restart_required <= !selected_pass;
                response_breakdown <= breakdown;
                response_saturation <= saturation;
                response_iterations_used <= iterations_used;
                relative_limit <= computed_relative_limit;
                quantization_floor <= computed_quantization_floor;
                certificate_limit <= computed_certificate_limit;
                if (breakdown)
                    stop_reason <= STOP_BREAKDOWN;
                else if (saturation)
                    stop_reason <= STOP_SATURATION;
                else if (selected_pass)
                    stop_reason <= STOP_CERTIFICATE_PASS;
                else
                    stop_reason <= STOP_CERTIFICATE_FAIL;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_response_stalled;
    reg [TAG_W-1:0] f_response_tag;
    reg f_certificate_pass;
    reg [ENERGY_W-1:0] f_certificate_limit;
    reg f_absolute_limit_enable;
    reg [ENERGY_W-1:0] f_absolute_limit;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;
        f_response_stalled <= response_valid && !response_ready;
        f_response_tag <= response_tag;
        f_certificate_pass <= certificate_pass;
        f_certificate_limit <= certificate_limit;
        if (request_accept) begin
            f_absolute_limit_enable <= absolute_limit_enable;
            f_absolute_limit <= absolute_limit;
        end
        if (rst_n && f_past_valid && f_response_stalled) begin
            assert(response_valid);
            assert(response_tag == f_response_tag);
            assert(certificate_pass == f_certificate_pass);
            assert(certificate_limit == f_certificate_limit);
        end
        if (rst_n && response_valid) begin
            assert(!(certificate_pass && restart_required));
            if (f_absolute_limit_enable)
                assert(certificate_limit == f_absolute_limit);
            else begin
                assert(certificate_limit >= quantization_floor);
                assert(certificate_limit >= relative_limit);
            end
        end
    end
`endif
endmodule

`default_nettype wire
