`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// One homogeneous context-programmed PE. Architectural state changes only on
// a shared committed cycle; there is no local PC, issue FSM or capability bit.
module pe_tile #(
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
    input  wire signed [DATA_W-1:0]     north_input,
    input  wire signed [DATA_W-1:0]     east_input,
    input  wire signed [DATA_W-1:0]     south_input,
    input  wire signed [DATA_W-1:0]     west_input,
    input  wire signed [DATA_W-1:0]     external_input_a,
    input  wire signed [DATA_W-1:0]     external_input_b,
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
    wire [`RECON_TILE_FIELD_OPERATION_W-1:0] operation =
        tile_ctx[`RECON_TILE_FIELD_OPERATION_LSB +:
                 `RECON_TILE_FIELD_OPERATION_W];
    wire [`RECON_TILE_FIELD_SOURCE_A_W-1:0] source_a =
        tile_ctx[`RECON_TILE_FIELD_SOURCE_A_LSB +:
                 `RECON_TILE_FIELD_SOURCE_A_W];
    wire [`RECON_TILE_FIELD_SOURCE_B_W-1:0] source_b =
        tile_ctx[`RECON_TILE_FIELD_SOURCE_B_LSB +:
                 `RECON_TILE_FIELD_SOURCE_B_W];
    wire [`RECON_TILE_FIELD_RF_READ_A_W-1:0] rf_read_a =
        tile_ctx[`RECON_TILE_FIELD_RF_READ_A_LSB +:
                 `RECON_TILE_FIELD_RF_READ_A_W];
    wire [`RECON_TILE_FIELD_RF_READ_B_W-1:0] rf_read_b =
        tile_ctx[`RECON_TILE_FIELD_RF_READ_B_LSB +:
                 `RECON_TILE_FIELD_RF_READ_B_W];
    wire [`RECON_TILE_FIELD_RF_WRITE_ADDRESS_W-1:0] rf_write_address =
        tile_ctx[`RECON_TILE_FIELD_RF_WRITE_ADDRESS_LSB +:
                 `RECON_TILE_FIELD_RF_WRITE_ADDRESS_W];
    wire rf_write_enable =
        tile_ctx[`RECON_TILE_FIELD_RF_WRITE_ENABLE_LSB];
    wire [`RECON_TILE_FIELD_PREDICATE_SELECT_W-1:0] predicate_select =
        tile_ctx[`RECON_TILE_FIELD_PREDICATE_SELECT_LSB +:
                 `RECON_TILE_FIELD_PREDICATE_SELECT_W];
    wire predicate_invert =
        tile_ctx[`RECON_TILE_FIELD_PREDICATE_INVERT_LSB];
    wire [`RECON_TILE_FIELD_ROUTE_NORTH_SELECT_W-1:0] route_north_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_NORTH_SELECT_LSB +:
                 `RECON_TILE_FIELD_ROUTE_NORTH_SELECT_W];
    wire [`RECON_TILE_FIELD_ROUTE_EAST_SELECT_W-1:0] route_east_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_EAST_SELECT_LSB +:
                 `RECON_TILE_FIELD_ROUTE_EAST_SELECT_W];
    wire [`RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_W-1:0] route_south_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_LSB +:
                 `RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_W];
    wire [`RECON_TILE_FIELD_ROUTE_WEST_SELECT_W-1:0] route_west_select =
        tile_ctx[`RECON_TILE_FIELD_ROUTE_WEST_SELECT_LSB +:
                 `RECON_TILE_FIELD_ROUTE_WEST_SELECT_W];

    wire selected_predicate =
        predicate_values[predicate_select] ^ predicate_invert;
    wire signed [DATA_W-1:0] rf_data_a;
    wire signed [DATA_W-1:0] rf_data_b;
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
    wire route_has_express =
        route_north_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS ||
        route_east_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS ||
        route_south_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS ||
        route_west_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
    wire context_legal = !alu_illegal && !route_has_express;
    wire tile_fire = cycle_valid && cycle_commit && tile_enable && context_legal;
    wire state_write_enable = tile_fire && selected_predicate;
    wire switchbox_error;

    assign result = result_reg;
    assign accumulator = accumulator_reg;

    function signed [DATA_W-1:0] select_data_operand;
        input [2:0] source;
        input signed [DATA_W-1:0] rf_value;
        input signed [DATA_W-1:0] north_value;
        input signed [DATA_W-1:0] east_value;
        input signed [DATA_W-1:0] south_value;
        input signed [DATA_W-1:0] west_value;
        input signed [DATA_W-1:0] accumulator_value;
        input signed [DATA_W-1:0] external_value;
        begin
            case (source)
                `RECON_OPERAND_SOURCE_ZERO:
                    select_data_operand = {DATA_W{1'b0}};
                `RECON_OPERAND_SOURCE_LOCAL_RF:
                    select_data_operand = rf_value;
                `RECON_OPERAND_SOURCE_NORTH:
                    select_data_operand = north_value;
                `RECON_OPERAND_SOURCE_EAST:
                    select_data_operand = east_value;
                `RECON_OPERAND_SOURCE_SOUTH:
                    select_data_operand = south_value;
                `RECON_OPERAND_SOURCE_WEST:
                    select_data_operand = west_value;
                `RECON_OPERAND_SOURCE_ACCUMULATOR:
                    select_data_operand = accumulator_value;
                default:
                    select_data_operand = external_value;
            endcase
        end
    endfunction

    wire signed [DATA_W-1:0] data_operand_a =
        select_data_operand(source_a, rf_data_a, north_input, east_input,
                            south_input, west_input,
                            accumulator_reg[DATA_W-1:0], external_input_a);
    wire signed [DATA_W-1:0] data_operand_b =
        select_data_operand(source_b, rf_data_b, north_input, east_input,
                            south_input, west_input,
                            accumulator_reg[DATA_W-1:0], external_input_b);
    wire signed [ACC_W-1:0] operand_a =
        (source_a == `RECON_OPERAND_SOURCE_ACCUMULATOR) ? accumulator_reg :
        {{(ACC_W-DATA_W){data_operand_a[DATA_W-1]}}, data_operand_a};
    wire signed [ACC_W-1:0] operand_b =
        (source_b == `RECON_OPERAND_SOURCE_ACCUMULATOR) ? accumulator_reg :
        {{(ACC_W-DATA_W){data_operand_b[DATA_W-1]}}, data_operand_b};

    pe_local_register_file #(.DATA_W(DATA_W)) local_state (
        .clk(clk), .rst_n(rst_n), .clear_all(1'b0),
        .read_address_a(rf_read_a), .read_address_b(rf_read_b),
        .read_data_a(rf_data_a), .read_data_b(rf_data_b),
        .read_valid_a(), .read_valid_b(),
        .write_enable(state_write_enable && rf_write_enable),
        .write_address(rf_write_address), .write_data(alu_result)
    );

    pe_alu #(.DATA_W(DATA_W), .ACC_W(ACC_W)) arithmetic (
        .operation(operation), .operand_a(operand_a), .operand_b(operand_b),
        .accumulator(accumulator_reg),
        .selected_predicate(selected_predicate),
        .phi_nonzero(phi_nonzero), .phi_sign(phi_sign),
        .result(alu_result), .accumulator_next(alu_accumulator_next),
        .accumulator_write(alu_accumulator_write),
        .comparison_result(),
        .saturated(alu_saturated), .illegal_operation(alu_illegal)
    );

    // PE_RESULT is the previous cycle's registered ALU value. Consequently a
    // tile operation costs one cycle and every switchbox hop costs one more.
    registered_switchbox #(.DATA_W(DATA_W)) switchbox (
        .clk(clk), .rst_n(rst_n), .update_enable(state_write_enable),
        .north_select(route_north_select), .east_select(route_east_select),
        .south_select(route_south_select), .west_select(route_west_select),
        .pe_result(result_reg), .north_input(north_input),
        .east_input(east_input), .south_input(south_input),
        .west_input(west_input), .external_input(external_input_a),
        .north_output(north_output), .east_output(east_output),
        .south_output(south_output), .west_output(west_output),
        .selection_error(switchbox_error)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            result_reg <= {DATA_W{1'b0}};
            acc_bank0 <= {ACC_W{1'b0}};
            acc_bank1 <= {ACC_W{1'b0}};
            acc_write_sel <= 1'b0;
            result_valid <= 1'b0;
            saturation_event <= 1'b0;
            contract_error <= 1'b0;
        end else begin
            result_valid <= state_write_enable;
            saturation_event <= state_write_enable && alu_saturated;
            contract_error <= cycle_valid && cycle_commit && tile_enable &&
                              (!context_legal || switchbox_error);
            if (state_write_enable) begin
                result_reg <= alu_result;
                if (alu_accumulator_write) begin
                    if (operation == `RECON_TILE_OP_ACCUMULATOR_CLEAR) begin
                        acc_write_sel <= ~acc_write_sel;
                        if (acc_write_sel)
                            acc_bank0 <= {ACC_W{1'b0}};
                        else
                            acc_bank1 <= {ACC_W{1'b0}};
                    end else if (acc_write_sel)
                        acc_bank1 <= alu_accumulator_next;
                    else
                        acc_bank0 <= alu_accumulator_next;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_prev_no_state_write;
    reg signed [DATA_W-1:0] f_result;
    reg signed [ACC_W-1:0] f_accumulator;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_prev_no_state_write) begin
            assert(result_reg == f_result);
            assert(accumulator_reg == f_accumulator);
        end
        if (rst_n && cycle_valid && !cycle_commit)
            assert(!state_write_enable);
        if (rst_n && !tile_enable)
            assert(!state_write_enable);
        f_prev_no_state_write <= !state_write_enable;
        f_result <= result_reg;
        f_accumulator <= accumulator_reg;
    end
`endif
endmodule

`default_nettype wire
