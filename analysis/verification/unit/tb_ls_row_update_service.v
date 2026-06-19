`timescale 1ns/1ps
module tb_ls_row_update_service;
    localparam DATA_W = 56;
    localparam FACTOR_W = 64;
    localparam FRAC_W = 16;
    reg clk=0, rst_n=0, start=0;
    reg signed [FACTOR_W-1:0] factor_q=0;
    reg signed [DATA_W-1:0] pivot_value=0, row_value=0;
    wire valid, busy, done;
    wire signed [DATA_W-1:0] row_next;
    integer passes=0, fails=0;

    ls_row_update_service #(.DATA_W(DATA_W), .FACTOR_W(FACTOR_W), .FRAC_W(FRAC_W)) dut(
        .clk(clk), .rst_n(rst_n), .start(start), .factor_q(factor_q), .pivot_value(pivot_value),
        .row_value(row_value), .valid(valid), .row_next(row_next), .busy(busy), .done(done)
    );
    always #5 clk=~clk;

    task run_case;
        input signed [FACTOR_W-1:0] factor;
        input signed [DATA_W-1:0] pivot;
        input signed [DATA_W-1:0] row_in;
        input signed [DATA_W-1:0] exp_row;
        begin
            @(negedge clk);
            factor_q = factor; pivot_value = pivot; row_value = row_in; start = 1'b1;
            @(negedge clk); start = 1'b0;
            wait(done);
            if (valid && row_next === exp_row) passes = passes + 1;
            else begin
                fails = fails + 1;
                $display("FAIL factor=%0d pivot=%0d row=%0d got=%0d exp=%0d", factor, pivot, row_in, row_next, exp_row);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        run_case(64'sd65536, 56'sd131072, 56'sd262144, 56'sd131072);
        run_case(-64'sd65536, 56'sd131072, 56'sd262144, 56'sd393216);
        run_case(64'sd32768, -56'sd65536, 56'sd131072, 56'sd163840);
        $display("tb_ls_row_update_service: %0d PASS, %0d FAIL", passes, fails);
        if (fails) $fatal(1);
        $finish;
    end
endmodule
