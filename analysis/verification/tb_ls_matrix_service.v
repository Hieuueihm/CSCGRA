`timescale 1ns/1ps

module tb_ls_matrix_service;
    localparam integer GE_W = 56;
    localparam integer LANES = 8;
    localparam [2:0] OP_CLEAR      = 3'd0;
    localparam [2:0] OP_WRITE      = 3'd1;
    localparam [2:0] OP_READ2      = 3'd2;
    localparam [2:0] OP_ACC_BLOCK  = 3'd3;
    localparam [2:0] OP_ROW_UPDATE = 3'd4;

    reg clk;
    reg rst_n;
    reg start;
    reg [2:0] op;
    reg [4:0] row_a;
    reg [4:0] col_a;
    reg [4:0] row_b;
    reg [4:0] col_b;
    reg [4:0] row_base;
    reg [LANES-1:0] lane_valid;
    reg signed [LANES*64-1:0] lane_add;
    reg signed [GE_W-1:0] wdata;
    reg signed [63:0] factor;
    wire busy;
    wire done;
    wire signed [GE_W-1:0] rdata_a;
    wire signed [GE_W-1:0] rdata_b;
    wire signed [GE_W-1:0] update_value;

    integer pass_count;
    integer fail_count;

    ls_matrix_service #(.MAX_K(16), .GE_W(GE_W), .LANES(LANES)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op(op),
        .row_a(row_a), .col_a(col_a), .row_b(row_b), .col_b(col_b),
        .row_base(row_base), .lane_valid(lane_valid), .lane_add(lane_add),
        .wdata(wdata), .factor(factor), .busy(busy), .done(done),
        .rdata_a(rdata_a), .rdata_b(rdata_b), .update_value(update_value)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task issue;
        input [2:0] op_i;
        begin
            @(negedge clk);
            op = op_i;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done == 1'b1);
            @(negedge clk);
        end
    endtask

    task check_eq;
        input signed [GE_W-1:0] got;
        input signed [GE_W-1:0] exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("PASS got=%0d", got);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL got=%0d exp=%0d", got, exp);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start = 1'b0;
        op = OP_CLEAR;
        row_a = 5'd0;
        col_a = 5'd0;
        row_b = 5'd0;
        col_b = 5'd0;
        row_base = 5'd0;
        lane_valid = {LANES{1'b0}};
        lane_add = {LANES*64{1'b0}};
        wdata = {GE_W{1'b0}};
        factor = 64'sd0;
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        issue(OP_CLEAR);

        row_a = 5'd3;
        col_a = 5'd4;
        wdata = 56'sd12345;
        issue(OP_WRITE);

        row_a = 5'd3;
        col_a = 5'd4;
        row_b = 5'd0;
        col_b = 5'd0;
        issue(OP_READ2);
        check_eq(rdata_a, 56'sd12345);

        row_base = 5'd0;
        col_a = 5'd2;
        lane_valid = 8'b00001111;
        lane_add = {64'sd0, 64'sd0, 64'sd0, 64'sd0, 64'sd40, 64'sd30, 64'sd20, 64'sd10};
        issue(OP_ACC_BLOCK);

        row_a = 5'd2;
        col_a = 5'd2;
        row_b = 5'd3;
        col_b = 5'd2;
        issue(OP_READ2);
        check_eq(rdata_a, 56'sd30);
        check_eq(rdata_b, 56'sd40);

        row_a = 5'd5;
        col_a = 5'd6;
        wdata = 56'sd1000;
        issue(OP_WRITE);
        row_a = 5'd4;
        col_a = 5'd6;
        wdata = 56'sd256;
        issue(OP_WRITE);
        row_a = 5'd5;
        col_a = 5'd6;
        row_b = 5'd4;
        col_b = 5'd6;
        factor = 64'sd131072;
        issue(OP_ROW_UPDATE);
        check_eq(update_value, 56'sd488);
        row_a = 5'd5;
        col_a = 5'd6;
        issue(OP_READ2);
        check_eq(rdata_a, 56'sd488);

        $display("tb_ls_matrix_service: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count != 0)
            $fatal(1, "ls_matrix_service unit failed");
        $finish;
    end
endmodule
