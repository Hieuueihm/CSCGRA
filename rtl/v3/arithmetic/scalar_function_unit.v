`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"

// Shared exact fixed-point divider. A divide request runs ceil(OUT_W/2)
// radix-4 quotient steps plus one finalize cycle. Reciprocal and square-root
// encodings remain
// decodable but return a deterministic one-cycle contract fault.
module scalar_function_unit #(
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer OUT_W = `RECON_SOLVER_W,
    parameter integer FRACTION_W = `RECON_SOLVER_F,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [4:0]                   req_operation,
    input  wire [TAG_W-1:0]             req_tag,
    input  wire signed [ACC_W-1:0]      req_numerator,
    input  wire signed [ACC_W-1:0]      req_denominator,

    output reg                          rsp_valid,
    input  wire                         rsp_ready,
    output reg  [TAG_W-1:0]             rsp_tag,
    output reg  signed [OUT_W-1:0]      rsp_result,
    output reg                          rsp_fault,
    output reg  [7:0]                   rsp_fault_code,
    output reg  [15:0]                  rsp_fault_detail,
    output reg                          rsp_divide_by_zero,
    output reg                          rsp_saturated
);
    localparam integer QUOTIENT_W = OUT_W;
    localparam integer WORK_W = ACC_W + OUT_W;
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_ITERATE = 2'd1;
    localparam [1:0] STATE_FINALIZE = 2'd2;
    localparam [1:0] STATE_RESERVED = 2'd3;

    reg [1:0] state;
    reg [4:0] iteration_bit;
    reg [WORK_W-1:0] remainder_work;
    reg [WORK_W-1:0] shifted_denominator;
    reg [WORK_W-1:0] shifted_denominator_three_halves;
    reg [ACC_W-1:0] denominator_magnitude;
    reg [QUOTIENT_W-1:0] quotient_work;
    reg [QUOTIENT_W-1:0] quotient_final;
    reg [WORK_W-1:0] remainder_final;
    reg result_negative;
    reg quotient_overflow;
    reg divide_by_zero_pending;
    reg [TAG_W-1:0] active_tag;
    reg [TAG_W-1:0] reserved_tag;
    reg [4:0] reserved_operation;

    wire [ACC_W-1:0] numerator_magnitude = req_numerator[ACC_W-1] ?
        (~req_numerator + {{ACC_W-1{1'b0}}, 1'b1}) : req_numerator;
    wire [ACC_W-1:0] request_denominator_magnitude = req_denominator[ACC_W-1] ?
        (~req_denominator + {{ACC_W-1{1'b0}}, 1'b1}) : req_denominator;
    wire [WORK_W-1:0] scaled_numerator =
        {{OUT_W{1'b0}}, numerator_magnitude} << FRACTION_W;
    wire [WORK_W-1:0] denominator_overflow_threshold =
        {{OUT_W{1'b0}}, request_denominator_magnitude} << OUT_W;

    wire step_take = remainder_work >= shifted_denominator;
    wire [WORK_W-1:0] step_remainder = step_take ?
        remainder_work - shifted_denominator : remainder_work;
    wire [QUOTIENT_W-1:0] step_quotient = step_take ?
        quotient_work | ({{QUOTIENT_W-1{1'b0}},1'b1} << iteration_bit) :
        quotient_work;
    wire [WORK_W-1:0] radix4_half_denominator = shifted_denominator >> 1;
    wire [1:0] radix4_digit =
        (remainder_work >= shifted_denominator_three_halves) ? 2'b11 :
        (remainder_work >= shifted_denominator) ? 2'b10 :
        (remainder_work >= radix4_half_denominator) ? 2'b01 : 2'b00;
    wire [WORK_W-1:0] radix4_subtrahend =
        (radix4_digit == 2'b11) ? shifted_denominator_three_halves :
        (radix4_digit == 2'b10) ? shifted_denominator :
        (radix4_digit == 2'b01) ? radix4_half_denominator :
                                  {WORK_W{1'b0}};
    wire [WORK_W-1:0] radix4_remainder =
        remainder_work - radix4_subtrahend;
    wire [4:0] radix4_low_bit = (iteration_bit == 0) ?
        5'd0 : iteration_bit - 1'b1;
    wire [QUOTIENT_W-1:0] radix4_quotient = quotient_work |
        (radix4_digit[1] ?
         ({{QUOTIENT_W-1{1'b0}},1'b1} << iteration_bit) :
         {QUOTIENT_W{1'b0}}) |
        (radix4_digit[0] ?
         ({{QUOTIENT_W-1{1'b0}},1'b1} << radix4_low_bit) :
         {QUOTIENT_W{1'b0}});

    wire response_slot_ready = !rsp_valid;
    assign req_ready =
        ((state == STATE_IDLE) && response_slot_ready) ||
        ((state == STATE_FINALIZE) && response_slot_ready &&
         (req_operation == `RECON_RESOURCE_OP_SCALAR_DIVIDE)) ||
        ((state == STATE_RESERVED) && response_slot_ready);

    task start_divide;
        begin
            iteration_bit <= OUT_W-1;
            remainder_work <= scaled_numerator;
            shifted_denominator <=
                {{OUT_W{1'b0}}, request_denominator_magnitude} << (OUT_W-1);
            shifted_denominator_three_halves <=
                ({{OUT_W{1'b0}}, request_denominator_magnitude} << (OUT_W-1)) +
                ({{OUT_W{1'b0}}, request_denominator_magnitude} << (OUT_W-2));
            denominator_magnitude <= request_denominator_magnitude;
            quotient_work <= {QUOTIENT_W{1'b0}};
            result_negative <= req_numerator[ACC_W-1] ^ req_denominator[ACC_W-1];
            quotient_overflow <= (request_denominator_magnitude != 0) &&
                                  (scaled_numerator >= denominator_overflow_threshold);
            divide_by_zero_pending <= (request_denominator_magnitude == 0);
            active_tag <= req_tag;
            state <= STATE_ITERATE;
        end
    endtask

    reg [QUOTIENT_W:0] rounded_magnitude;
    reg round_up;
    always @* begin
        round_up = ({remainder_final, 1'b0} >=
                    {{(WORK_W+1-ACC_W){1'b0}}, denominator_magnitude});
        rounded_magnitude = {1'b0, quotient_final} + round_up;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            rsp_valid <= 1'b0;
            rsp_fault <= 1'b0;
            rsp_divide_by_zero <= 1'b0;
            rsp_saturated <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (req_valid && req_ready) begin
                        if (req_operation == `RECON_RESOURCE_OP_SCALAR_DIVIDE) begin
                            start_divide();
                        end else begin
                            reserved_tag <= req_tag;
                            reserved_operation <= req_operation;
                            state <= STATE_RESERVED;
                        end
                    end
                end

                STATE_ITERATE: begin
                    if (iteration_bit == 0) begin
                        remainder_work <= step_remainder;
                        quotient_work <= step_quotient;
                        shifted_denominator <= shifted_denominator >> 1;
                        shifted_denominator_three_halves <=
                            shifted_denominator_three_halves >> 1;
                        quotient_final <= step_quotient;
                        remainder_final <= step_remainder;
                        state <= STATE_FINALIZE;
                    end else if (iteration_bit == 1) begin
                        remainder_work <= radix4_remainder;
                        quotient_work <= radix4_quotient;
                        shifted_denominator <= shifted_denominator >> 2;
                        shifted_denominator_three_halves <=
                            shifted_denominator_three_halves >> 2;
                        quotient_final <= radix4_quotient;
                        remainder_final <= radix4_remainder;
                        state <= STATE_FINALIZE;
                    end else begin
                        remainder_work <= radix4_remainder;
                        quotient_work <= radix4_quotient;
                        shifted_denominator <= shifted_denominator >> 2;
                        shifted_denominator_three_halves <=
                            shifted_denominator_three_halves >> 2;
                        iteration_bit <= iteration_bit - 2'd2;
                    end
                end

                STATE_FINALIZE: begin
                    rsp_valid <= 1'b1;
                    rsp_tag <= active_tag;
                    rsp_fault <= 1'b0;
                    rsp_fault_code <= 8'd0;
                    rsp_fault_detail <= 16'd0;
                    rsp_divide_by_zero <= divide_by_zero_pending;
                    rsp_saturated <= 1'b0;
                    if (divide_by_zero_pending) begin
                        rsp_result <= {OUT_W{1'b0}};
                    end else if (quotient_overflow ||
                                 (!result_negative &&
                                  (rounded_magnitude > {1'b0, {OUT_W-1{1'b1}}})) ||
                                 (result_negative &&
                                  (rounded_magnitude > ({{OUT_W{1'b0}},1'b1} <<
                                                        (OUT_W-1))))) begin
                        rsp_saturated <= 1'b1;
                        rsp_result <= result_negative ?
                            {1'b1, {OUT_W-1{1'b0}}} :
                            {1'b0, {OUT_W-1{1'b1}}};
                    end else if (result_negative) begin
                        rsp_result <= -$signed(rounded_magnitude[OUT_W-1:0]);
                    end else begin
                        rsp_result <= rounded_magnitude[OUT_W-1:0];
                    end

                    if (req_valid && req_ready)
                        start_divide();
                    else
                        state <= STATE_IDLE;
                end

                STATE_RESERVED: begin
                    if (response_slot_ready) begin
                        rsp_valid <= 1'b1;
                        rsp_tag <= reserved_tag;
                        rsp_result <= {OUT_W{1'b0}};
                        rsp_fault <= 1'b1;
                        rsp_fault_code <= `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT;
                        rsp_fault_detail <= {3'd1, reserved_operation, 8'd0};
                        rsp_divide_by_zero <= 1'b0;
                        rsp_saturated <= 1'b0;

                        if (req_valid && req_ready) begin
                            if (req_operation == `RECON_RESOURCE_OP_SCALAR_DIVIDE) begin
                                start_divide();
                            end else begin
                                reserved_tag <= req_tag;
                                reserved_operation <= req_operation;
                                state <= STATE_RESERVED;
                            end
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [TAG_W-1:0] f_tag;
    reg signed [OUT_W-1:0] f_result;
    reg f_fault;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled) begin
            assert(rsp_valid);
            assert(rsp_tag == f_tag);
            assert(rsp_result == f_result);
            assert(rsp_fault == f_fault);
        end
        if (rsp_valid && rsp_divide_by_zero) begin
            assert(!rsp_fault);
            assert(rsp_result == 0);
        end
        if (rsp_valid && rsp_fault)
            assert(rsp_fault_code == `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT);
        f_stalled <= rsp_valid && !rsp_ready;
        f_tag <= rsp_tag;
        f_result <= rsp_result;
        f_fault <= rsp_fault;
    end
`endif
endmodule

`default_nettype wire
