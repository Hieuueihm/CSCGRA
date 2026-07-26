`timescale 1ns/1ps

module tb_ls_matrix_scratchpad;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg ge_we;
    reg ge_bank_w;
    reg [4:0] ge_wrow;
    reg [4:0] ge_wcol;
    reg signed [63:0] ge_wdata;
    reg ge_bank_a;
    reg [4:0] ge_rrow_a;
    reg [4:0] ge_rcol_a;
    wire signed [63:0] ge_rdata_a;
    reg ge_bank_b;
    reg [4:0] ge_rrow_b;
    reg [4:0] ge_rcol_b;
    wire signed [63:0] ge_rdata_b;
    reg rhs_we;
    reg rhs_bank_w;
    reg [4:0] rhs_waddr;
    reg signed [63:0] rhs_wdata;
    reg rhs_bank_r;
    reg [4:0] rhs_raddr;
    wire signed [63:0] rhs_rdata;

    integer pass_count = 0;
    integer fail_count = 0;

    ls_matrix_scratchpad dut (
        .clk(clk),
        .ge_we(ge_we), .ge_bank_w(ge_bank_w), .ge_wrow(ge_wrow), .ge_wcol(ge_wcol), .ge_wdata(ge_wdata),
        .ge_bank_a(ge_bank_a), .ge_rrow_a(ge_rrow_a), .ge_rcol_a(ge_rcol_a), .ge_rdata_a(ge_rdata_a),
        .ge_bank_b(ge_bank_b), .ge_rrow_b(ge_rrow_b), .ge_rcol_b(ge_rcol_b), .ge_rdata_b(ge_rdata_b),
        .rhs_we(rhs_we), .rhs_bank_w(rhs_bank_w), .rhs_waddr(rhs_waddr), .rhs_wdata(rhs_wdata),
        .rhs_bank_r(rhs_bank_r), .rhs_raddr(rhs_raddr), .rhs_rdata(rhs_rdata)
    );

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
        ge_we = 0; ge_bank_w = 0; ge_wrow = 0; ge_wcol = 0; ge_wdata = 0;
        ge_bank_a = 0; ge_rrow_a = 0; ge_rcol_a = 0;
        ge_bank_b = 0; ge_rrow_b = 0; ge_rcol_b = 0;
        rhs_we = 0; rhs_bank_w = 0; rhs_waddr = 0; rhs_wdata = 0;
        rhs_bank_r = 0; rhs_raddr = 0;

        repeat (2) @(posedge clk);

        @(negedge clk);
        ge_we = 1; ge_bank_w = 0; ge_wrow = 5'd3; ge_wcol = 5'd5; ge_wdata = 64'sd12345;
        @(negedge clk);
        ge_bank_w = 1; ge_wrow = 5'd7; ge_wcol = 5'd2; ge_wdata = -64'sd9876;
        @(negedge clk);
        ge_we = 0;

        ge_bank_a = 0; ge_rrow_a = 5'd3; ge_rcol_a = 5'd5;
        ge_bank_b = 1; ge_rrow_b = 5'd7; ge_rcol_b = 5'd2;
        @(posedge clk);
        @(negedge clk);
        check64("ge_a_bank0", ge_rdata_a, 64'sd12345);
        check64("ge_b_bank1", ge_rdata_b, -64'sd9876);

        rhs_we = 1; rhs_bank_w = 0; rhs_waddr = 5'd4; rhs_wdata = 64'sd111;
        @(negedge clk);
        rhs_bank_w = 1; rhs_waddr = 5'd4; rhs_wdata = -64'sd222;
        @(negedge clk);
        rhs_we = 0;

        rhs_bank_r = 0; rhs_raddr = 5'd4;
        @(posedge clk);
        @(negedge clk);
        check64("rhs_bank0", rhs_rdata, 64'sd111);
        rhs_bank_r = 1; rhs_raddr = 5'd4;
        @(posedge clk);
        @(negedge clk);
        check64("rhs_bank1", rhs_rdata, -64'sd222);

        $display("tb_ls_matrix_scratchpad: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count != 0) $fatal(1);
        $finish;
    end
endmodule
