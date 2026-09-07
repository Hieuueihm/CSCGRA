`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Homogeneous PE arithmetic leaf. General multiplication is deliberately not
// present here; it is owned by the scheduled shared vector arithmetic unit.
module pe_alu #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W
)(
    input  wire [4:0]                    operation,
    input  wire signed [ACC_W-1:0]       operand_a,
    input  wire signed [ACC_W-1:0]       operand_b,
    input  wire signed [ACC_W-1:0]       accumulator,
    input  wire                          selected_predicate,
    input  wire                          phi_nonzero,
    input  wire                          phi_sign,
    output reg  signed [DATA_W-1:0]      result,
    output reg  signed [ACC_W-1:0]       accumulator_next,
    output reg                           accumulator_write,
    output reg                           comparison_result,
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
    localparam signed [ACC_W-1:0] DATA_MAX_EXT =
        {{(ACC_W-DATA_W){1'b0}}, DATA_MAX};
    localparam signed [ACC_W-1:0] DATA_MIN_EXT =
        {{(ACC_W-DATA_W){1'b1}}, DATA_MIN};
    localparam signed [DATA_W:0] DATA_MAX_WIDE = {1'b0, DATA_MAX};
    localparam signed [DATA_W:0] DATA_MIN_WIDE = {1'b1, DATA_MIN};
    localparam integer PHI_DATA_SHIFT = `RECON_SOLVER_F - `RECON_DATA_F;
    localparam signed [`RECON_DATA_W-1:0] PHI_DATA_MAX =
        {1'b0, {`RECON_DATA_W-1{1'b1}}};
    localparam signed [`RECON_DATA_W-1:0] PHI_DATA_MIN =
        {1'b1, {`RECON_DATA_W-1{1'b0}}};

    wire signed [DATA_W-1:0] data_a = operand_a[DATA_W-1:0];
    wire signed [DATA_W-1:0] data_b = operand_b[DATA_W-1:0];
    wire [DATA_W-1:0] data_b_magnitude = data_b[DATA_W-1] ?
        (~data_b + {{DATA_W-1{1'b0}},1'b1}) : data_b;
    wire signed [DATA_W:0] data_add =
        {data_a[DATA_W-1], data_a} + {data_b[DATA_W-1], data_b};
    wire signed [DATA_W:0] data_sub =
        {data_a[DATA_W-1], data_a} - {data_b[DATA_W-1], data_b};
    wire signed [ACC_W-1:0] accumulator_add = operand_a + operand_b;
    wire signed [ACC_W-1:0] accumulator_sub = operand_a - operand_b;
    wire accumulator_add_overflow =
        (operand_a[ACC_W-1] == operand_b[ACC_W-1]) &&
        (accumulator_add[ACC_W-1] != operand_a[ACC_W-1]);
    wire accumulator_sub_overflow =
        (operand_a[ACC_W-1] != operand_b[ACC_W-1]) &&
        (accumulator_sub[ACC_W-1] != operand_a[ACC_W-1]);
    reg signed [ACC_W-1:0] clipped_accumulator;
    reg signed [ACC_W-1:0] phi_accumulate_term;
    reg signed [ACC_W-1:0] phi_accumulator_sum;
    reg phi_accumulator_overflow;
    reg [DATA_W:0] phi_data_magnitude;
    reg [DATA_W:0] phi_data_rounded_magnitude;
    reg signed [`RECON_DATA_W-1:0] phi_data_narrowed;
    reg signed [DATA_W-1:0] phi_data_rescaled;
    reg phi_data_saturated;
    reg wide_saturated;
    reg narrow_saturated;
    reg [4:0] shift_amount;

    task narrow_data_wide;
        input signed [DATA_W:0] value;
        begin
            if (value > DATA_MAX_WIDE) begin
                result = DATA_MAX;
                saturated = 1'b1;
            end else if (value < DATA_MIN_WIDE) begin
                result = DATA_MIN;
                saturated = 1'b1;
            end else begin
                result = value[DATA_W-1:0];
            end
        end
    endtask

    task narrow_accumulator;
        input signed [ACC_W-1:0] value;
        begin
            narrow_saturated = 1'b0;
            if (value[ACC_W-1:DATA_W-1] ==
                    {(ACC_W-DATA_W+1){value[DATA_W-1]}}) begin
                result = value[DATA_W-1:0];
            end else begin
                result = value[ACC_W-1] ? DATA_MIN : DATA_MAX;
                narrow_saturated = 1'b1;
            end
        end
    endtask

    always @* begin
        result = {DATA_W{1'b0}};
        accumulator_next = accumulator;
        accumulator_write = 1'b0;
        comparison_result = 1'b0;
        saturated = 1'b0;
        illegal_operation = 1'b0;
        clipped_accumulator = {ACC_W{1'b0}};
        phi_accumulate_term = {ACC_W{1'b0}};
        phi_accumulator_sum = {ACC_W{1'b0}};
        phi_accumulator_overflow = 1'b0;
        phi_data_magnitude = {(DATA_W+1){1'b0}};
        phi_data_rounded_magnitude = {(DATA_W+1){1'b0}};
        phi_data_narrowed = {`RECON_DATA_W{1'b0}};
        phi_data_rescaled = {DATA_W{1'b0}};
        phi_data_saturated = 1'b0;
        wide_saturated = 1'b0;
        narrow_saturated = 1'b0;
        shift_amount = 5'd0;

        case (operation)
            `RECON_TILE_OP_NOP: result = {DATA_W{1'b0}};
            `RECON_TILE_OP_PASS: result = data_a;
            `RECON_TILE_OP_ADD: narrow_data_wide(data_add);
            `RECON_TILE_OP_SUB: narrow_data_wide(data_sub);
            `RECON_TILE_OP_ABS: begin
                if (data_a == DATA_MIN) begin
                    result = DATA_MAX;
                    saturated = 1'b1;
                end else begin
                    result = data_a[DATA_W-1] ? -data_a : data_a;
                end
            end
            `RECON_TILE_OP_MIN: result = (data_a <= data_b) ? data_a : data_b;
            `RECON_TILE_OP_MAX: result = (data_a >= data_b) ? data_a : data_b;
            `RECON_TILE_OP_COMPARE_EQ: begin
                comparison_result = (data_a == data_b);
                result = {{DATA_W-1{1'b0}}, comparison_result};
            end
            `RECON_TILE_OP_COMPARE_LT: begin
                comparison_result = (data_a < data_b);
                result = {{DATA_W-1{1'b0}}, comparison_result};
            end
            `RECON_TILE_OP_COMPARE_LE: begin
                comparison_result = (data_a <= data_b);
                result = {{DATA_W-1{1'b0}}, comparison_result};
            end
            `RECON_TILE_OP_SELECT:
                result = selected_predicate ? data_a : data_b;
            `RECON_TILE_OP_SHIFT: begin
                if (data_b[DATA_W-1]) begin
                    shift_amount = data_b_magnitude[4:0];
                    result = data_a >>> shift_amount;
                end else begin
                    shift_amount = data_b[4:0];
                    result = data_a << shift_amount;
                    if (shift_amount != 0 &&
                        ($signed(result) >>> shift_amount) != data_a) begin
                        result = data_a[DATA_W-1] ? DATA_MIN : DATA_MAX;
                        saturated = 1'b1;
                    end
                end
            end
            `RECON_TILE_OP_BIT_AND: result = data_a & data_b;
            `RECON_TILE_OP_BIT_OR: result = data_a | data_b;
            `RECON_TILE_OP_BIT_XOR: result = data_a ^ data_b;
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
                // Accumulator-only operation: no intermediate S27 narrowing.
                result = {DATA_W{1'b0}};
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
                result = {DATA_W{1'b0}};
                accumulator_write = 1'b1;
            end
            `RECON_TILE_OP_ACCUMULATOR_READ: begin
                narrow_accumulator(accumulator);
                saturated = narrow_saturated;
            end
            `RECON_TILE_OP_SATURATING_ADD,
            `RECON_TILE_OP_SATURATING_SUB: begin
                if (operation == `RECON_TILE_OP_SATURATING_ADD) begin
                    clipped_accumulator = accumulator_add;
                    wide_saturated = accumulator_add_overflow;
                end else begin
                    clipped_accumulator = accumulator_sub;
                    wide_saturated = accumulator_sub_overflow;
                end
                if (wide_saturated) begin
                    clipped_accumulator = operand_a[ACC_W-1] ? ACC_MIN : ACC_MAX;
                    wide_saturated = 1'b1;
                end
                accumulator_next = clipped_accumulator;
                accumulator_write = 1'b1;
                narrow_accumulator(clipped_accumulator);
                saturated = wide_saturated || narrow_saturated;
            end
            `RECON_TILE_OP_PHI_SIGN_SCALE: begin
                if (!phi_nonzero) begin
                    result = {DATA_W{1'b0}};
                end else if (!phi_sign) begin
                    if (data_a == DATA_MIN) begin
                        result = DATA_MAX;
                        saturated = 1'b1;
                    end else begin
                        result = -data_a;
                    end
                end else begin
                    result = data_a;
                end
            end
            `RECON_TILE_OP_ACCUMULATOR_CLEAR: begin
                result = {DATA_W{1'b0}};
                accumulator_next = {ACC_W{1'b0}};
                accumulator_write = 1'b1;
            end
            `RECON_TILE_OP_PHI_ACCUMULATOR_CAPTURE,
            `RECON_TILE_OP_PHI_RESIDUAL_CAPTURE: begin
                result = {DATA_W{1'b0}};
            end
            default: illegal_operation = 1'b1;
        endcase
    end

`ifdef FORMAL
    always @* begin
        if (operation == `RECON_TILE_OP_PHI_SIGN_SCALE && !phi_nonzero)
            assert(result == 0);
        if (operation == `RECON_TILE_OP_PHI_ACCUMULATE) begin
            assert(accumulator_write);
            assert(result == 0);
        end
        if (operation == `RECON_TILE_OP_PHI_DATA_ACCUMULATE) begin
            assert(accumulator_write);
            assert(result == 0);
        end
        if (operation == `RECON_TILE_OP_ACCUMULATOR_CLEAR) begin
            assert(accumulator_write);
            assert(accumulator_next == 0);
        end
        if (operation == `RECON_TILE_OP_ABS && data_a == DATA_MIN) begin
            assert(result == DATA_MAX);
            assert(saturated);
        end
    end
`endif
endmodule

`default_nettype wire
