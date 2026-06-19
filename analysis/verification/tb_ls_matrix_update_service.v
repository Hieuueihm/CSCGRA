`timescale 1ns/1ps

module tb_ls_matrix_update_service;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n;
    reg start;
    reg [1:0] op;
    reg bank;
    reg [4:0] row_i;
    reg [4:0] row_k;
    reg [4:0] col;
    reg signed [63:0] wdata;
    reg signed [63:0] factor;
    wire busy;
    wire done;
    wire signed [63:0] rdata;
    wire signed [63:0] update_value;

    integer pass_count = 0;
    integer fail_count = 0;

    ls_matrix_update_service dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op(op), .bank(bank),
        .row_i(row_i), .row_k(row_k), .col(col), .wdata(wdata), .factor(factor),
        .busy(busy), .done(done), .rdata(rdata), .update_value(update_value)
    );

    task launch;
        input [1:0] op_i;
        input bank_i;
        input [4:0] row_i_i;
        input [4:0] row_k_i;
        input [4:0] col_i;
        input signed [63:0] wdata_i;
        input signed [63:0] factor_i;
        begin
            @(negedge clk);
            op = op_i;
            bank = bank_i;
            row_i = row_i_i;
            row_k = row_k_i;
            col = col_i;
            wdata = wdata_i;
            factor = factor_i;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done === 1'b1);
            @(negedge clk);
        end
    endtask

    task check64;
        input [255:0] name;
        input signed [63:0] got;
        input signed [63:0] exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("PASS %0s got=%0d", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s got=%0d exp=%0d", name, got, exp);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        op = 2'd0;
        bank = 1'b0;
        row_i = 5'd0;
        row_k = 5'd0;
        col = 5'd0;
        wdata = 64'sd0;
        factor = 64'sd0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        launch(2'd1, 1'b0, 5'd1, 5'd0, 5'd3, 64'sd1000, 64'sd0);
        launch(2'd1, 1'b0, 5'd2, 5'd0, 5'd3, 64'sd256, 64'sd0);
        launch(2'd0, 1'b0, 5'd1, 5'd0, 5'd3, 64'sd0, 64'sd0);
        check64("read_before_update", rdata, 64'sd1000);

        launch(2'd2, 1'b0, 5'd1, 5'd2, 5'd3, 64'sd0, 64'sd131072);
        check64("update_value", update_value, 64'sd488);
        launch(2'd0, 1'b0, 5'd1, 5'd0, 5'd3, 64'sd0, 64'sd0);
        check64("read_after_update", rdata, 64'sd488);

        launch(2'd1, 1'b1, 5'd1, 5'd0, 5'd3, -64'sd77, 64'sd0);
        launch(2'd0, 1'b1, 5'd1, 5'd0, 5'd3, 64'sd0, 64'sd0);
        check64("bank1_isolated", rdata, -64'sd77);
        launch(2'd0, 1'b0, 5'd1, 5'd0, 5'd3, 64'sd0, 64'sd0);
        check64("bank0_preserved", rdata, 64'sd488);

        $display("tb_ls_matrix_update_service: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count != 0) $fatal(1);
        $finish;
    end
endmodule
