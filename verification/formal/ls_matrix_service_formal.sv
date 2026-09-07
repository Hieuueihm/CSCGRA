`default_nettype none

module ls_matrix_service_formal;
    localparam integer MAX_K = 16;
    localparam integer GE_W = 56;
    localparam integer FACTOR_W = 64;
    localparam integer RHS_W = 64;
    localparam integer LANES = 8;

    localparam [3:0] OP_WRITE = 4'd1;
    localparam [3:0] OP_READ2 = 4'd2;
    localparam [3:0] OP_ACC_BLOCK = 4'd3;
    localparam [3:0] OP_RHS_WRITE = 4'd5;
    localparam [3:0] OP_RHS_READ = 4'd6;
    localparam [3:0] OP_READ4 = 4'd8;
    localparam [3:0] OP_WRITE4 = 4'd9;
    localparam [3:0] OP_ACC4 = 4'd10;
    localparam [3:0] OP_CLEAR_ROW = 4'd11;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    (* anyseq *) reg start;
    (* anyseq *) reg [3:0] op;
    (* anyseq *) reg [4:0] row_a, col_a, row_b, col_b, row_base;
    (* anyseq *) reg [LANES-1:0] lane_valid;
    (* anyseq *) reg row_update_block;
    (* anyseq *) reg signed [LANES*64-1:0] lane_add;
    (* anyseq *) reg signed [4*LANES*64-1:0] lane_add4;
    (* anyseq *) reg [4*LANES-1:0] acc4_lane_valid;
    (* anyseq *) reg [3:0] acc4_col_valid;
    (* anyseq *) reg signed [GE_W-1:0] wdata;
    (* anyseq *) reg signed [4*GE_W-1:0] write4_wdata;
    (* anyseq *) reg [3:0] write4_valid;
    (* anyseq *) reg signed [FACTOR_W-1:0] factor;
    (* anyseq *) reg signed [RHS_W-1:0] rhs_wdata;

    wire busy, done, acc4_credit;
    wire signed [GE_W-1:0] rdata_a, rdata_b, update_value;
    wire signed [4*GE_W-1:0] read4_rdata;
    wire signed [RHS_W-1:0] rhs_rdata;

    reg f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!f_past_valid)
            assume(!rst_n);
        else
            assume(rst_n);

        if (start) begin
            case (op)
                OP_WRITE, OP_ACC_BLOCK: begin
                    assume(row_a < MAX_K);
                    assume(col_a < MAX_K);
                end
                OP_READ2: begin
                    assume(row_a < MAX_K);
                    assume(col_a < MAX_K);
                    assume(row_b < MAX_K);
                    assume(col_b < MAX_K);
                end
                OP_READ4: begin
                    assume(({1'b0, row_a} + 6'd3) < MAX_K);
                    assume(col_a < MAX_K);
                    assume(row_b < MAX_K);
                    assume(col_b < MAX_K);
                end
                OP_WRITE4: begin
                    assume(({1'b0, row_a} + 6'd3) < MAX_K);
                    assume(col_a < MAX_K);
                end
                OP_RHS_WRITE, OP_RHS_READ: assume(row_a < MAX_K);
                OP_ACC4: begin
                    assume(({1'b0, row_base} + 6'd3) < MAX_K);
                    assume(({1'b0, col_a} + 6'd3) < MAX_K);
                end
                OP_CLEAR_ROW: assume(row_a < MAX_K);
                default: begin end
            endcase
        end
    end

    ls_matrix_service #(
        .MAX_K(MAX_K), .GE_W(GE_W), .FACTOR_W(FACTOR_W),
        .RHS_W(RHS_W), .LANES(LANES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op(op),
        .row_a(row_a), .col_a(col_a), .row_b(row_b), .col_b(col_b),
        .row_base(row_base), .lane_valid(lane_valid),
        .row_update_block(row_update_block), .lane_add(lane_add),
        .lane_add4(lane_add4), .acc4_lane_valid(acc4_lane_valid),
        .acc4_col_valid(acc4_col_valid), .wdata(wdata),
        .write4_wdata(write4_wdata), .write4_valid(write4_valid),
        .factor(factor), .rhs_wdata(rhs_wdata), .busy(busy), .done(done),
        .acc4_credit(acc4_credit), .rdata_a(rdata_a), .rdata_b(rdata_b),
        .read4_rdata(read4_rdata), .update_value(update_value),
        .rhs_rdata(rhs_rdata)
    );
endmodule

`default_nettype wire
