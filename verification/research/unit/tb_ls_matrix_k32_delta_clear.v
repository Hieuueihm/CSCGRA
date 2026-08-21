`timescale 1ns/1ps
module tb_ls_matrix_k32_delta_clear;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [3:0] op = 0;
    reg [4:0] row_a = 0, col_a = 0, row_b = 0, col_b = 0, row_base = 0;
    reg signed [55:0] wdata = 0;
    wire busy, done;
    wire signed [55:0] rdata_a;
    always #5 clk = ~clk;

    ls_matrix_service #(.MAX_K(32)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op(op),
        .row_a(row_a), .col_a(col_a), .row_b(row_b), .col_b(col_b),
        .row_base(row_base), .lane_valid(8'd0), .row_update_block(1'b0),
        .lane_add(512'd0), .lane_add4(2048'd0),
        .acc4_lane_valid(32'd0), .acc4_col_valid(4'd0),
        .wdata(wdata), .write4_wdata(224'd0), .write4_valid(4'd0),
        .factor(64'd0), .rhs_wdata(64'd0), .busy(busy), .done(done),
        .rdata_a(rdata_a)
    );

    task command;
        input [3:0] cmd;
        input [4:0] row;
        input [4:0] col;
        input signed [55:0] value;
        begin
            @(negedge clk); op=cmd; row_a=row; col_a=col; wdata=value; start=1;
            @(negedge clk); start=0;
            while (!done) @(negedge clk);
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk); rst_n=1;
        command(4'd1, 5'd30, 5'd0, 56'sd77);
        for (i=0; i<32; i=i+1)
            command(4'd1, 5'd31, i[4:0], 56'sd1000+i);
        command(4'd11, 5'd31, 5'd0, 56'sd0);
        command(4'd2, 5'd31, 5'd17, 56'sd0);
        if (rdata_a !== 56'sd0) $fatal(1,"row31 not cleared: %0d",rdata_a);
        command(4'd2, 5'd30, 5'd0, 56'sd0);
        if (rdata_a !== 56'sd77) $fatal(1,"row30 alias/corruption: %0d",rdata_a);
        $display("LS_MATRIX_K32_DELTA_CLEAR PASS");
        $finish;
    end
endmodule
