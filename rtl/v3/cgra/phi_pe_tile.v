`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module phi_pe_tile #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire                         tile_enable,
    input  wire [`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_PREDICATE_COUNT-1:0] predicate_values,
    input  wire signed [DATA_W-1:0]     external_input_a,
    input  wire                         phi_nonzero,
    input  wire                         phi_sign,
    output wire signed [DATA_W-1:0]     north_output,
    output wire signed [DATA_W-1:0]     east_output,
    output wire signed [DATA_W-1:0]     south_output,
    output wire signed [DATA_W-1:0]     west_output,
    output wire signed [DATA_W-1:0]     result,
    output wire signed [ACC_W-1:0]      accumulator,
    output reg                          result_valid,
    output reg                          saturation_event,
    output reg                          contract_error
);
    wire [4:0] operation = tile_ctx[`RECON_TILE_FIELD_OPERATION_LSB +: 5];
    wire [2:0] predicate_select =
        tile_ctx[`RECON_TILE_FIELD_PREDICATE_SELECT_LSB +: 3];
    wire predicate_invert = tile_ctx[`RECON_TILE_FIELD_PREDICATE_INVERT_LSB];
    wire selected_predicate =
        predicate_values[predicate_select] ^ predicate_invert;
    wire rf_write_enable = tile_ctx[`RECON_TILE_FIELD_RF_WRITE_ENABLE_LSB];
    wire [2:0] route_north_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_NORTH_SELECT_LSB +: 3];
    wire [2:0] route_east_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_EAST_SELECT_LSB +: 3];
    wire [2:0] route_south_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_LSB +: 3];
    wire [2:0] route_west_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_WEST_SELECT_LSB +: 3];
    wire routes_hold =
        (route_north_select == `RECON_ROUTE_SOURCE_HOLD) &&
        (route_east_select == `RECON_ROUTE_SOURCE_HOLD) &&
        (route_south_select == `RECON_ROUTE_SOURCE_HOLD) &&
        (route_west_select == `RECON_ROUTE_SOURCE_HOLD);

    reg signed [DATA_W-1:0] result_reg;
    reg signed [ACC_W-1:0] acc_bank0;
    reg signed [ACC_W-1:0] acc_bank1;
    reg acc_write_sel;
    wire signed [ACC_W-1:0] accumulator_reg =
        acc_write_sel ? acc_bank1 : acc_bank0;
    wire signed [DATA_W-1:0] alu_result;
    wire signed [ACC_W-1:0] alu_accumulator_next;
    wire alu_accumulator_write;
    wire alu_saturated;
    wire alu_illegal;
    wire context_legal = !alu_illegal && routes_hold && !rf_write_enable;
    wire state_write_enable = cycle_valid && cycle_commit && tile_enable &&
        context_legal && selected_predicate;

    phi_pe_alu #(.DATA_W(DATA_W), .ACC_W(ACC_W)) arithmetic (
        .operation(operation), .data_a(external_input_a),
        .accumulator(accumulator_reg), .phi_nonzero(phi_nonzero),
        .phi_sign(phi_sign), .result(alu_result),
        .accumulator_next(alu_accumulator_next),
        .accumulator_write(alu_accumulator_write),
        .saturated(alu_saturated), .illegal_operation(alu_illegal)
    );

    assign north_output = {DATA_W{1'b0}};
    assign east_output = {DATA_W{1'b0}};
    assign south_output = {DATA_W{1'b0}};
    assign west_output = {DATA_W{1'b0}};
    assign result = result_reg;
    assign accumulator = accumulator_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            result_reg <= 0;
            acc_bank0 <= 0;
            acc_bank1 <= 0;
            acc_write_sel <= 0;
            result_valid <= 0;
            saturation_event <= 0;
            contract_error <= 0;
        end else begin
            result_valid <= state_write_enable;
            saturation_event <= state_write_enable && alu_saturated;
            contract_error <= cycle_valid && cycle_commit && tile_enable &&
                !context_legal;
            if (state_write_enable) begin
                result_reg <= alu_result;
                if (alu_accumulator_write) begin
                    if (operation == `RECON_TILE_OP_ACCUMULATOR_CLEAR) begin
                        acc_write_sel <= ~acc_write_sel;
                        if (acc_write_sel)
                            acc_bank0 <= 0;
                        else
                            acc_bank1 <= 0;
                    end else if (acc_write_sel)
                        acc_bank1 <= alu_accumulator_next;
                    else
                        acc_bank0 <= alu_accumulator_next;
                end
            end
        end
    end
endmodule

`default_nettype wire
