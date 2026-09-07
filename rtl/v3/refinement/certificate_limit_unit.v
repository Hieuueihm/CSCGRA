`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module certificate_limit_unit #(
    parameter integer ENERGY_W = `RECON_ACC_W,
    parameter integer ABSOLUTE_FLOOR = `RECON_CERT_ABSOLUTE_FLOOR,
    parameter integer SUPPORT_SMALL_SHIFT = `RECON_CERT_SUPPORT_SMALL_SHIFT,
    parameter integer SUPPORT_LARGE_SHIFT = `RECON_CERT_SUPPORT_LARGE_SHIFT,
    parameter integer MEASUREMENT_SHIFT = `RECON_CERT_MEASUREMENT_SHIFT
)(
    input  wire [6:0] support_count,
    input  wire [8:0] measurement_count,
    input  wire [4:0] normal_residual_shift,
    input  wire [ENERGY_W-1:0] gamma_reference,
    input  wire absolute_limit_enable,
    input  wire [ENERGY_W-1:0] absolute_limit,
    output reg  [ENERGY_W-1:0] relative_limit,
    output reg  [ENERGY_W-1:0] quantization_floor,
    output reg  [ENERGY_W-1:0] certificate_limit
);
    reg [5:0] double_shift;
    reg [ENERGY_W-1:0] remainder_mask;
    reg [ENERGY_W-1:0] support_floor;
    reg [ENERGY_W-1:0] measurement_floor;

    always @* begin
        double_shift = {normal_residual_shift, 1'b0};
        if (double_shift == 0) begin
            relative_limit = gamma_reference;
            remainder_mask = {ENERGY_W{1'b0}};
        end else if (double_shift >= ENERGY_W) begin
            relative_limit = gamma_reference != 0;
            remainder_mask = {ENERGY_W{1'b1}};
        end else begin
            remainder_mask = ~({ENERGY_W{1'b1}} << double_shift);
            relative_limit = (gamma_reference >> double_shift) +
                ((gamma_reference & remainder_mask) != 0);
        end
        if (measurement_count <= 32)
            support_floor = {{(ENERGY_W-7){1'b0}}, support_count} <<
                SUPPORT_SMALL_SHIFT;
        else
            support_floor = {{(ENERGY_W-7){1'b0}}, support_count} <<
                SUPPORT_LARGE_SHIFT;
        measurement_floor = measurement_count > 32 ?
            ({{(ENERGY_W-9){1'b0}}, measurement_count} <<
             MEASUREMENT_SHIFT) : {ENERGY_W{1'b0}};
        quantization_floor = support_floor > ABSOLUTE_FLOOR ?
            support_floor : ABSOLUTE_FLOOR;
        if (measurement_floor > quantization_floor)
            quantization_floor = measurement_floor;
        certificate_limit = absolute_limit_enable ? absolute_limit :
            (relative_limit > quantization_floor ? relative_limit :
             quantization_floor);
    end
endmodule

`default_nettype wire
