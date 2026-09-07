`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module phi_pe_alu #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W
)(
    input  wire [4:0]                    operation,
    input  wire signed [DATA_W-1:0]     data_a,
    input  wire signed [ACC_W-1:0]      accumulator,
    input  wire                          phi_nonzero,
    input  wire                          phi_sign,
    output reg  signed [DATA_W-1:0]      result,
    output reg  signed [ACC_W-1:0]       accumulator_next,
    output reg                           accumulator_write,
    output reg                           saturated,
    output reg                           illegal_operation
);
    localparam signed [DATA_W-1:0] DATA_MAX =
        {1'b0, {DATA_W-1{1'b1}}};
    localparam signed [DATA_W-1:0] DATA_MIN =
        {1'b1, {DATA_W-1{1'b0}}};
    localparam signed [ACC_W-1:0] ACC_MAX =
        {1'b0, {ACC_W-1{1'b1}}};
    localparam signed [ACC_W-1:0] ACC_MIN =
        {1'b1, {ACC_W-1{1'b0}}};
    localparam integer PHI_DATA_SHIFT = `RECON_SOLVER_F - `RECON_DATA_F;
    localparam signed [`RECON_DATA_W-1:0] PHI_DATA_MAX =
        {1'b0, {`RECON_DATA_W-1{1'b1}}};
    localparam signed [`RECON_DATA_W-1:0] PHI_DATA_MIN =
        {1'b1, {`RECON_DATA_W-1{1'b0}}};

    reg signed [ACC_W-1:0] phi_accumulate_term;
    reg signed [ACC_W-1:0] phi_accumulator_sum;
    reg phi_accumulator_overflow;
    reg [DATA_W:0] phi_data_magnitude;
    reg [DATA_W:0] phi_data_rounded_magnitude;
    reg signed [`RECON_DATA_W-1:0] phi_data_narrowed;
    reg signed [DATA_W-1:0] phi_data_rescaled;
    reg phi_data_saturated;

    task narrow_accumulator;
        input signed [ACC_W-1:0] value;
        begin
            if (value[ACC_W-1:DATA_W-1] ==
                    {(ACC_W-DATA_W+1){value[DATA_W-1]}})
                result = value[DATA_W-1:0];
            else begin
                result = value[ACC_W-1] ? DATA_MIN : DATA_MAX;
                saturated = 1'b1;
            end
        end
    endtask

    always @* begin
        result = {DATA_W{1'b0}};
        accumulator_next = accumulator;
        accumulator_write = 1'b0;
        saturated = 1'b0;
        illegal_operation = 1'b0;
        phi_accumulate_term = {ACC_W{1'b0}};
        phi_accumulator_sum = accumulator;
        phi_accumulator_overflow = 1'b0;
        phi_data_magnitude = {(DATA_W+1){1'b0}};
        phi_data_rounded_magnitude = {(DATA_W+1){1'b0}};
        phi_data_narrowed = {`RECON_DATA_W{1'b0}};
        phi_data_rescaled = {DATA_W{1'b0}};
        phi_data_saturated = 1'b0;
        case (operation)
            `RECON_TILE_OP_NOP,
            `RECON_TILE_OP_PHI_ACCUMULATOR_CAPTURE,
            `RECON_TILE_OP_PHI_RESIDUAL_CAPTURE: begin
                result = {DATA_W{1'b0}};
            end
            `RECON_TILE_OP_ACCUMULATOR_CLEAR: begin
                accumulator_next = {ACC_W{1'b0}};
                accumulator_write = 1'b1;
            end
            `RECON_TILE_OP_ACCUMULATOR_READ: narrow_accumulator(accumulator);
            `RECON_TILE_OP_PHI_ACCUMULATE: begin
                if (phi_nonzero) begin
                    phi_accumulate_term =
                        {{(ACC_W-DATA_W){data_a[DATA_W-1]}}, data_a};
                    if (!phi_sign)
                        phi_accumulate_term = -phi_accumulate_term;
                end
                phi_accumulator_sum = accumulator + phi_accumulate_term;
                phi_accumulator_overflow =
                    (accumulator[ACC_W-1] == phi_accumulate_term[ACC_W-1]) &&
                    (phi_accumulator_sum[ACC_W-1] != accumulator[ACC_W-1]);
                if (phi_accumulator_overflow) begin
                    accumulator_next = accumulator[ACC_W-1] ? ACC_MIN : ACC_MAX;
                    saturated = 1'b1;
                end else begin
                    accumulator_next = phi_accumulator_sum;
                end
                accumulator_write = 1'b1;
            end
            `RECON_TILE_OP_PHI_DATA_ACCUMULATE: begin
                phi_data_magnitude = data_a[DATA_W-1] ?
                    {1'b0, (~data_a + {{DATA_W-1{1'b0}}, 1'b1})} :
                    {1'b0, data_a};
                phi_data_rounded_magnitude =
                    (phi_data_magnitude +
                     ({{DATA_W{1'b0}}, 1'b1} << (PHI_DATA_SHIFT-1))) >>
                    PHI_DATA_SHIFT;
                if (data_a[DATA_W-1]) begin
                    if (phi_data_rounded_magnitude >
                            ({{DATA_W{1'b0}}, 1'b1} << (`RECON_DATA_W-1))) begin
                        phi_data_narrowed = PHI_DATA_MIN;
                        phi_data_saturated = 1'b1;
                    end else if (phi_data_rounded_magnitude ==
                            ({{DATA_W{1'b0}}, 1'b1} << (`RECON_DATA_W-1))) begin
                        phi_data_narrowed = PHI_DATA_MIN;
                    end else begin
                        phi_data_narrowed = -$signed(
                            phi_data_rounded_magnitude[`RECON_DATA_W-1:0]);
                    end
                end else if (phi_data_rounded_magnitude > PHI_DATA_MAX) begin
                    phi_data_narrowed = PHI_DATA_MAX;
                    phi_data_saturated = 1'b1;
                end else begin
                    phi_data_narrowed =
                        phi_data_rounded_magnitude[`RECON_DATA_W-1:0];
                end
                phi_data_rescaled =
                    $signed({{(DATA_W-`RECON_DATA_W){
                                  phi_data_narrowed[`RECON_DATA_W-1]}},
                             phi_data_narrowed}) <<< PHI_DATA_SHIFT;
                if (phi_nonzero) begin
                    phi_accumulate_term =
                        {{(ACC_W-DATA_W){phi_data_rescaled[DATA_W-1]}},
                         phi_data_rescaled};
                    if (!phi_sign)
                        phi_accumulate_term = -phi_accumulate_term;
                end
                phi_accumulator_sum = accumulator + phi_accumulate_term;
                phi_accumulator_overflow =
                    (accumulator[ACC_W-1] == phi_accumulate_term[ACC_W-1]) &&
                    (phi_accumulator_sum[ACC_W-1] != accumulator[ACC_W-1]);
                if (phi_accumulator_overflow) begin
                    accumulator_next = accumulator[ACC_W-1] ? ACC_MIN : ACC_MAX;
                    saturated = 1'b1;
                end else begin
                    accumulator_next = phi_accumulator_sum;
                    saturated = phi_data_saturated;
                end
                accumulator_write = 1'b1;
            end
            default: illegal_operation = 1'b1;
        endcase
    end
endmodule

`default_nettype wire
