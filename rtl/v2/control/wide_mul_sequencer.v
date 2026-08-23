// 64x64 limb multiplier sequencer extracted from sparse_loop_controller.
//
// Sequences the four-row wide product: sign-magnitude split at issue, the
// two-limb 16x16 issue stream, the vertical (PE0->PE3) or horizontal drain,
// and the 128-bit reduction commit.  The operand SELECTION (which source
// feeds A/B per state) and the batch4 Gram/RHS capture gating stay in the
// controller; this module only sequences and reduces.  Register names are
// unchanged from the pre-extraction controller so hierarchical probes keep
// their meaning one level down.
module wide_mul_sequencer #(
    parameter integer COLS = 8
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    wide_mul_start_q,
    input  wire                    wide_mul_vertical_request_q,
    input  wire [4*64-1:0]         wide_mul_operand_a,
    input  wire [4*64-1:0]         wide_mul_operand_b,
    input  wire [COLS*4*64-1:0]    product_bus,
    input  wire [3:0]              row_product_valid,
    input  wire [3:0]              row_product_part1,

    output wire [3:0]              wide_mul_state_q,
    output wire                    wide_mul_done_q,
    output wire                    wide_mul_vertical_done_q,
    output wire                    wide_mul_vertical_q,
    output wire                    wide_mul_active_token_q,
    output wire                    wide_mul_vertical_token_q,
    output wire                    wide_mul_issue_token_q,
    output wire                    wide_mul_issue_part1_token_q,
    output wire [4*64-1:0]         wide_mul_abs_a_bus,
    output wire [4*64-1:0]         wide_mul_abs_b_bus,
    output wire [4*128-1:0]        wide_mul_result_flat,
    output wire [4*COLS*64-1:0]    wide_mul_captured_flat
);

    localparam [3:0] WIDE_MUL_IDLE=4'd0, WIDE_MUL_ISSUE0=4'd1,
                     WIDE_MUL_ISSUE1=4'd2, WIDE_MUL_DRAIN=4'd3,
                     WIDE_MUL_VDRAIN1=4'd4, WIDE_MUL_VDRAIN2=4'd5,
                     WIDE_MUL_VDRAIN3=4'd6, WIDE_MUL_COMMIT=4'd7,
                     WIDE_MUL_FINAL=4'd8, WIDE_MUL_FINISH=4'd9;

    reg [3:0] wide_mul_state_iq;
    reg wide_mul_done_iq;
    reg wide_mul_vertical_done_iq;
    reg wide_mul_vertical_iq;
    (* dont_touch = "true" *) reg wide_mul_active_token_iq;
    (* dont_touch = "true" *) reg wide_mul_vertical_token_iq;
    (* dont_touch = "true" *) reg wide_mul_issue_token_iq;
    (* dont_touch = "true" *) reg wide_mul_issue_part1_token_iq;
    reg [63:0] wide_mul_abs_a_q [0:3];
    reg [63:0] wide_mul_abs_b_q [0:3];
    reg wide_mul_neg_q [0:3];
    reg [127:0] wide_mul_acc_q [0:3];
    reg [127:0] wide_mul_partial_q [0:3];
    reg signed [127:0] wide_mul_result_q [0:3];
    reg [COLS*64-1:0] wide_product_q [0:3];
    reg [3:0] wide_product_valid_q;
    reg [3:0] wide_product_part1_q;
    reg [127:0] wide_partial_sum [0:3];

    integer wide_row, wide_col, wide_part, wide_a_limb, wide_b_limb, wide_shift;
    integer red_row, red_col, red_part, red_a_limb, red_b_limb, red_shift;

    assign wide_mul_state_q = wide_mul_state_iq;
    assign wide_mul_done_q = wide_mul_done_iq;
    assign wide_mul_vertical_done_q = wide_mul_vertical_done_iq;
    assign wide_mul_vertical_q = wide_mul_vertical_iq;
    assign wide_mul_active_token_q = wide_mul_active_token_iq;
    assign wide_mul_vertical_token_q = wide_mul_vertical_token_iq;
    assign wide_mul_issue_token_q = wide_mul_issue_token_iq;
    assign wide_mul_issue_part1_token_q = wide_mul_issue_part1_token_iq;

    genvar abs_g;
    generate
        for (abs_g = 0; abs_g < 4; abs_g = abs_g + 1) begin : gen_abs_bus
            assign wide_mul_abs_a_bus[abs_g*64 +: 64] = wide_mul_abs_a_q[abs_g];
            assign wide_mul_abs_b_bus[abs_g*64 +: 64] = wide_mul_abs_b_q[abs_g];
            assign wide_mul_result_flat[abs_g*128 +: 128] = wide_mul_result_q[abs_g];
            assign wide_mul_captured_flat[abs_g*COLS*64 +: COLS*64] = wide_product_q[abs_g];
        end
    endgenerate

    // Limb-pair reduction of the captured per-row product bank.  The part-1
    // flag selects the upper limb window; each limb pair is shifted to its
    // Q32 position and accumulated into the row partial sum.
    always @(*) begin
        for (red_row = 0; red_row < 4; red_row = red_row + 1)
            wide_partial_sum[red_row] = 128'd0;
        for (red_row = 0; red_row < 4; red_row = red_row + 1) begin
            if (wide_product_valid_q[red_row]) begin
                for (red_col = 0; red_col < COLS; red_col = red_col + 1) begin
                    red_part = (wide_product_part1_q[red_row] ? COLS : 0) + red_col;
                    red_a_limb = red_part >> 2;
                    red_b_limb = red_part & 3;
                    red_shift = (red_a_limb + red_b_limb) * 16;
                    wide_partial_sum[red_row] = wide_partial_sum[red_row] +
                        ({64'd0, $unsigned(wide_product_q[red_row][red_col*64 +: 64])} << red_shift);
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wide_mul_state_iq <= WIDE_MUL_IDLE;
            wide_mul_done_iq <= 1'b0;
            wide_mul_vertical_done_iq <= 1'b0;
            wide_mul_vertical_iq <= 1'b0;
            wide_mul_active_token_iq <= 1'b0;
            wide_mul_vertical_token_iq <= 1'b0;
            wide_mul_issue_token_iq <= 1'b0;
            wide_mul_issue_part1_token_iq <= 1'b0;
            for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                wide_mul_abs_a_q[wide_row] <= 64'd0;
                wide_mul_abs_b_q[wide_row] <= 64'd0;
                wide_mul_neg_q[wide_row] <= 1'b0;
                wide_mul_acc_q[wide_row] <= 128'd0;
                wide_mul_partial_q[wide_row] <= 128'd0;
                wide_mul_result_q[wide_row] <= 128'sd0;
                wide_product_q[wide_row] <= {(COLS*64){1'b0}};
            end
            wide_product_valid_q <= 4'b0000;
            wide_product_part1_q <= 4'b0000;
        end else begin
            wide_mul_done_iq <= 1'b0;
            wide_mul_vertical_done_iq <= 1'b0;
            wide_product_valid_q <= row_product_valid;
            wide_product_part1_q <= row_product_part1;
            for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                if (row_product_valid[wide_row]) begin
                    wide_product_q[wide_row] <=
                        product_bus[wide_row*COLS*64 +: COLS*64];
                end
            end
            case (wide_mul_state_iq)
            WIDE_MUL_IDLE: begin
                wide_mul_issue_token_iq <= 1'b0;
                wide_mul_issue_part1_token_iq <= 1'b0;
                if (wide_mul_start_q) begin
                    wide_mul_active_token_iq <= 1'b1;
                    wide_mul_vertical_token_iq <= wide_mul_vertical_request_q;
                    wide_mul_issue_token_iq <= 1'b1;
                    wide_mul_issue_part1_token_iq <= 1'b0;
                    wide_mul_vertical_iq <= wide_mul_vertical_request_q;
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                        wide_mul_abs_a_q[wide_row] <= wide_mul_operand_a[wide_row*64+63] ?
                            -$signed(wide_mul_operand_a[wide_row*64 +: 64]) : $signed(wide_mul_operand_a[wide_row*64 +: 64]);
                        wide_mul_abs_b_q[wide_row] <= wide_mul_operand_b[wide_row*64+63] ?
                            -$signed(wide_mul_operand_b[wide_row*64 +: 64]) : $signed(wide_mul_operand_b[wide_row*64 +: 64]);
                        wide_mul_neg_q[wide_row] <= wide_mul_operand_a[wide_row*64+63] ^ wide_mul_operand_b[wide_row*64+63];
                    end
                    wide_mul_state_iq <= WIDE_MUL_ISSUE0;
                end
            end
            WIDE_MUL_ISSUE0: begin
                wide_mul_issue_token_iq <= 1'b1;
                wide_mul_issue_part1_token_iq <= 1'b1;
                wide_mul_state_iq <= WIDE_MUL_ISSUE1;
            end
            WIDE_MUL_ISSUE1: begin
                wide_mul_issue_token_iq <= 1'b0;
                wide_mul_issue_part1_token_iq <= 1'b0;
                wide_mul_state_iq <= WIDE_MUL_DRAIN;
            end
            WIDE_MUL_DRAIN: begin
                if (wide_mul_vertical_iq)
                    wide_mul_state_iq <= WIDE_MUL_VDRAIN1;
                else
                    wide_mul_state_iq <= WIDE_MUL_COMMIT;
            end
            WIDE_MUL_VDRAIN1: begin
                wide_mul_acc_q[0] <= wide_partial_sum[0];
                wide_mul_state_iq <= WIDE_MUL_VDRAIN2;
            end
            WIDE_MUL_VDRAIN2: begin
                wide_mul_partial_q[0] <= wide_partial_sum[0];
                wide_mul_acc_q[1] <= wide_partial_sum[1];
                wide_mul_state_iq <= WIDE_MUL_VDRAIN3;
            end
            WIDE_MUL_VDRAIN3: begin
                if (wide_mul_neg_q[0])
                    wide_mul_result_q[0] <= -$signed(wide_mul_acc_q[0] + wide_mul_partial_q[0]);
                else
                    wide_mul_result_q[0] <= $signed(wide_mul_acc_q[0] + wide_mul_partial_q[0]);
                wide_mul_partial_q[1] <= wide_partial_sum[1];
                wide_mul_acc_q[2] <= wide_partial_sum[2];
                wide_mul_state_iq <= WIDE_MUL_COMMIT;
            end
            WIDE_MUL_COMMIT: begin
                if (wide_mul_vertical_iq) begin
                    if (wide_mul_neg_q[1])
                        wide_mul_result_q[1] <= -$signed(wide_mul_acc_q[1] + wide_mul_partial_q[1]);
                    else
                        wide_mul_result_q[1] <= $signed(wide_mul_acc_q[1] + wide_mul_partial_q[1]);
                    wide_mul_partial_q[2] <= wide_partial_sum[2];
                    wide_mul_acc_q[3] <= wide_partial_sum[3];
                end else begin
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1)
                        wide_mul_acc_q[wide_row] <= wide_partial_sum[wide_row];
                end
                wide_mul_state_iq <= WIDE_MUL_FINAL;
            end
            WIDE_MUL_FINAL: begin
                if (wide_mul_vertical_iq) begin
                    if (wide_mul_neg_q[2])
                        wide_mul_result_q[2] <= -$signed(wide_mul_acc_q[2] + wide_mul_partial_q[2]);
                    else
                        wide_mul_result_q[2] <= $signed(wide_mul_acc_q[2] + wide_mul_partial_q[2]);
                    // Isolate PE3's registered product from the final
                    // 128-bit add and completion edge.
                    wide_mul_partial_q[3] <= wide_partial_sum[3];
                end else begin
                    // All four rows capture the reduced part-1 limb here.
                    // FINISH only sees locally registered acc/partial data.
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1)
                        wide_mul_partial_q[wide_row] <= wide_partial_sum[wide_row];
                end
                wide_mul_state_iq <= WIDE_MUL_FINISH;
            end
            WIDE_MUL_FINISH: begin
                if (wide_mul_vertical_iq) begin
                    if (wide_mul_neg_q[3])
                        wide_mul_result_q[3] <= -$signed(wide_mul_acc_q[3] + wide_mul_partial_q[3]);
                    else
                        wide_mul_result_q[3] <= $signed(wide_mul_acc_q[3] + wide_mul_partial_q[3]);
                    wide_mul_vertical_done_iq <= 1'b1;
                end else begin
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                        if (wide_mul_neg_q[wide_row])
                            wide_mul_result_q[wide_row] <= -$signed(wide_mul_acc_q[wide_row] + wide_mul_partial_q[wide_row]);
                        else
                            wide_mul_result_q[wide_row] <= $signed(wide_mul_acc_q[wide_row] + wide_mul_partial_q[wide_row]);
                    end
                end
                wide_mul_done_iq <= 1'b1;
                wide_mul_state_iq <= WIDE_MUL_IDLE;
                wide_mul_vertical_iq <= 1'b0;
                wide_mul_active_token_iq <= 1'b0;
                wide_mul_vertical_token_iq <= 1'b0;
                wide_mul_issue_token_iq <= 1'b0;
                wide_mul_issue_part1_token_iq <= 1'b0;
            end
            default: begin
                // Recover from an illegal/X state instead of retaining a
                // dead FSM state with stale issue tokens asserted.
                wide_mul_state_iq <= WIDE_MUL_IDLE;
                wide_mul_vertical_iq <= 1'b0;
                wide_mul_active_token_iq <= 1'b0;
                wide_mul_vertical_token_iq <= 1'b0;
                wide_mul_issue_token_iq <= 1'b0;
                wide_mul_issue_part1_token_iq <= 1'b0;
            end
            endcase
        end
    end

endmodule
