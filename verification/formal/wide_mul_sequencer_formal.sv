`default_nettype none

module wide_mul_sequencer_formal;
    localparam integer COLS = 8;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    (* anyseq *) reg wide_mul_start_q;
    (* anyseq *) reg wide_mul_vertical_request_q;
    (* anyseq *) reg [4*64-1:0] wide_mul_operand_a;
    (* anyseq *) reg [4*64-1:0] wide_mul_operand_b;
    (* anyseq *) reg [COLS*4*64-1:0] product_bus;
    (* anyseq *) reg [3:0] row_product_valid;
    (* anyseq *) reg [3:0] row_product_part1;

    wire [3:0] wide_mul_state_q;
    wire wide_mul_done_q, wide_mul_vertical_done_q, wide_mul_vertical_q;
    wire wide_mul_active_token_q, wide_mul_vertical_token_q;
    wire wide_mul_issue_token_q, wide_mul_issue_part1_token_q;
    wire [4*64-1:0] wide_mul_abs_a_bus, wide_mul_abs_b_bus;
    wire [4*128-1:0] wide_mul_result_flat;
    wire [4*COLS*64-1:0] wide_mul_captured_flat;

    reg f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!f_past_valid)
            assume(!rst_n);
        else
            assume(rst_n);
    end

    wide_mul_sequencer #(.COLS(COLS)) dut (
        .clk(clk), .rst_n(rst_n), .wide_mul_start_q(wide_mul_start_q),
        .wide_mul_vertical_request_q(wide_mul_vertical_request_q),
        .wide_mul_operand_a(wide_mul_operand_a),
        .wide_mul_operand_b(wide_mul_operand_b), .product_bus(product_bus),
        .row_product_valid(row_product_valid),
        .row_product_part1(row_product_part1),
        .wide_mul_state_q(wide_mul_state_q), .wide_mul_done_q(wide_mul_done_q),
        .wide_mul_vertical_done_q(wide_mul_vertical_done_q),
        .wide_mul_vertical_q(wide_mul_vertical_q),
        .wide_mul_active_token_q(wide_mul_active_token_q),
        .wide_mul_vertical_token_q(wide_mul_vertical_token_q),
        .wide_mul_issue_token_q(wide_mul_issue_token_q),
        .wide_mul_issue_part1_token_q(wide_mul_issue_part1_token_q),
        .wide_mul_abs_a_bus(wide_mul_abs_a_bus),
        .wide_mul_abs_b_bus(wide_mul_abs_b_bus),
        .wide_mul_result_flat(wide_mul_result_flat),
        .wide_mul_captured_flat(wide_mul_captured_flat)
    );
endmodule

`default_nettype wire
