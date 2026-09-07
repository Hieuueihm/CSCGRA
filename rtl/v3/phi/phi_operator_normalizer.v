`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_operator_normalizer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         input_valid,
    output wire         input_ready,
    input  wire signed [`RECON_ACC_W-1:0] input_data,
    input  wire         input_placement,
    input  wire [`RECON_PHI_TAG_W-1:0] input_tag,
    input  wire [`RECON_PHI_SCALE_MANTISSA_W-1:0] scale_mantissa_uq17,
    input  wire [`RECON_PHI_SCALE_EXPONENT_W-1:0] scale_exponent,
    input  wire         input_is_data18,
    output wire         output_valid,
    input  wire         output_ready,
    output wire signed [`RECON_SOLVER_W-1:0] output_data,
    output wire         output_placement,
    output wire [`RECON_PHI_TAG_W-1:0] output_tag,
    output wire         output_saturated
);
    localparam integer MANTISSA_SIGNED_W = `RECON_PHI_SCALE_MANTISSA_W + 1;
    localparam integer PRODUCT_W = `RECON_ACC_W + MANTISSA_SIGNED_W;
    localparam [`RECON_SOLVER_W-1:0] POSITIVE_MAX =
        {1'b0, {(`RECON_SOLVER_W-1){1'b1}}};
    localparam [`RECON_SOLVER_W-1:0] NEGATIVE_MIN =
        {1'b1, {(`RECON_SOLVER_W-1){1'b0}}};

    reg valid0;
    reg valid1;
    reg valid2;
    reg valid3;
    reg valid4;
    reg signed [PRODUCT_W-1:0] product0;
    reg [5:0] shift0;
    reg invalid_shift0;
    reg placement0;
    reg [`RECON_PHI_TAG_W-1:0] tag0;
    reg [PRODUCT_W-1:0] magnitude1;
    reg negative1;
    reg invalid_shift1;
    reg placement1;
    reg [`RECON_PHI_TAG_W-1:0] tag1;
    reg signed [`RECON_SOLVER_W-1:0] result2;
    reg saturated2;
    reg placement2;
    reg [`RECON_PHI_TAG_W-1:0] tag2;
    reg signed [`RECON_SOLVER_W-1:0] result3;
    reg saturated3;
    reg placement3;
    reg [`RECON_PHI_TAG_W-1:0] tag3;
    reg signed [`RECON_SOLVER_W-1:0] result4;
    reg saturated4;
    reg placement4;
    reg [`RECON_PHI_TAG_W-1:0] tag4;
    assign output_valid = valid4;
    assign output_data = result4;
    assign output_placement = placement4;
    assign output_tag = tag4;
    assign output_saturated = saturated4;
    wire advance = !valid4 || output_ready;
    assign input_ready = advance;

    wire signed [MANTISSA_SIGNED_W-1:0] input_signed_mantissa =
        $signed({1'b0, scale_mantissa_uq17});
    wire signed [5:0] input_signed_exponent =
        {{(6-`RECON_PHI_SCALE_EXPONENT_W){scale_exponent[
            `RECON_PHI_SCALE_EXPONENT_W-1]}}, scale_exponent};
    wire signed [PRODUCT_W-1:0] input_product =
        input_data * input_signed_mantissa;
    wire signed [6:0] input_shift = 7'sd17 - input_signed_exponent -
        (input_is_data18 ? (`RECON_SOLVER_F-`RECON_DATA_F) : 0);
    wire [PRODUCT_W-1:0] absolute_product = product0[PRODUCT_W-1] ?
        (~product0 + {{PRODUCT_W-1{1'b0}}, 1'b1}) : product0;
    wire [PRODUCT_W-1:0] rounding_increment =
        {{PRODUCT_W-1{1'b0}}, 1'b1} << (shift0 - 1'b1);
    wire [PRODUCT_W-1:0] rounded_magnitude =
        (absolute_product + rounding_increment) >> shift0;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid0 <= 1'b0;
            valid1 <= 1'b0;
            valid2 <= 1'b0;
            valid3 <= 1'b0;
            valid4 <= 1'b0;
            invalid_shift0 <= 1'b0;
            invalid_shift1 <= 1'b0;
        end else if (advance) begin
            valid4 <= valid3;
            result4 <= result3;
            saturated4 <= saturated3;
            placement4 <= placement3;
            tag4 <= tag3;

            valid3 <= valid2;
            result3 <= result2;
            saturated3 <= saturated2;
            placement3 <= placement2;
            tag3 <= tag2;

            valid2 <= valid1;
            placement2 <= placement1;
            tag2 <= tag1;
            saturated2 <= 1'b0;
            if (invalid_shift1) begin
                result2 <= {`RECON_SOLVER_W{1'b0}};
                saturated2 <= 1'b1;
            end else if (!negative1 &&
                (magnitude1 > {{(PRODUCT_W-`RECON_SOLVER_W){1'b0}},
                               POSITIVE_MAX})) begin
                result2 <= $signed(POSITIVE_MAX);
                saturated2 <= 1'b1;
            end else if (negative1 &&
                         (magnitude1 >
                          ({{(PRODUCT_W-1){1'b0}}, 1'b1} <<
                           (`RECON_SOLVER_W-1)))) begin
                result2 <= $signed(NEGATIVE_MIN);
                saturated2 <= 1'b1;
            end else if (negative1) begin
                result2 <= -$signed(magnitude1[`RECON_SOLVER_W-1:0]);
            end else begin
                result2 <= $signed(magnitude1[`RECON_SOLVER_W-1:0]);
            end

            valid1 <= valid0;
            negative1 <= product0[PRODUCT_W-1];
            invalid_shift1 <= invalid_shift0;
            placement1 <= placement0;
            tag1 <= tag0;
            magnitude1 <= rounded_magnitude;

            valid0 <= input_valid;
            if (input_valid) begin
                product0 <= input_product;
                shift0 <= input_shift > 0 ? input_shift[5:0] : 6'd1;
                invalid_shift0 <= input_shift <= 0;
                placement0 <= input_placement;
                tag0 <= input_tag;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg signed [`RECON_SOLVER_W-1:0] f_data;
    reg f_placement;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    reg f_saturated;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled) begin
            assert(output_valid);
            assert(output_data == f_data);
            assert(output_placement == f_placement);
            assert(output_tag == f_tag);
            assert(output_saturated == f_saturated);
        end
        if (rst_n && valid0)
            assert(shift0 > 0);
        f_stalled <= output_valid && !output_ready;
        f_data <= output_data;
        f_placement <= output_placement;
        f_tag <= output_tag;
        f_saturated <= output_saturated;
    end
`endif
endmodule

`default_nettype wire
