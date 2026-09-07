`timescale 1ns/1ps
`default_nettype none

module tb_support_coefficient_stripe_store;
    localparam integer DATA_W = 27;
    reg clk = 0;
    reg rst_n = 0;
    reg write_enable = 0;
    reg write_bank = 0;
    reg [6:0] write_slot = 0;
    reg [DATA_W-1:0] write_coefficient = 0;
    reg scalar_read_enable = 0;
    reg scalar_read_bank = 0;
    reg [6:0] scalar_read_slot = 0;
    wire scalar_read_valid;
    wire [DATA_W-1:0] scalar_read_coefficient;
    reg stripe_read_enable = 0;
    reg stripe_read_bank = 0;
    reg [2:0] stripe_read_index = 0;
    wire stripe_read_valid;
    wire [16*DATA_W-1:0] stripe_read_coefficients;

    always #5 clk = ~clk;

    support_coefficient_stripe_store #(.DATA_W(DATA_W)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .write_enable(write_enable), .write_bank(write_bank),
        .write_slot(write_slot), .write_coefficient(write_coefficient),
        .scalar_read_enable(scalar_read_enable),
        .scalar_read_bank(scalar_read_bank),
        .scalar_read_slot(scalar_read_slot),
        .scalar_read_valid(scalar_read_valid),
        .scalar_read_coefficient(scalar_read_coefficient),
        .stripe_read_enable(stripe_read_enable),
        .stripe_read_bank(stripe_read_bank),
        .stripe_read_index(stripe_read_index),
        .stripe_read_valid(stripe_read_valid),
        .stripe_read_coefficients(stripe_read_coefficients)
    );

    task write_value;
        input bank;
        input [6:0] slot;
        input signed [DATA_W-1:0] coefficient;
        begin
            @(negedge clk);
            write_enable = 1;
            write_bank = bank;
            write_slot = slot;
            write_coefficient = coefficient;
            @(negedge clk);
            write_enable = 0;
        end
    endtask

    task fail;
        input [8*80-1:0] message;
        begin
            $display("SUPPORT COEFFICIENT STRIPE STORE FAIL: %0s", message);
            $fatal(1);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        write_value(0, 7'd0, 27'sd101);
        write_value(0, 7'd15, -27'sd202);
        write_value(0, 7'd16, 27'sd303);
        write_value(1, 7'd16, -27'sd404);

        @(negedge clk);
        scalar_read_enable = 1;
        scalar_read_bank = 1;
        scalar_read_slot = 7'd16;
        @(posedge clk);
        #1;
        if (!scalar_read_valid ||
            $signed(scalar_read_coefficient) != -27'sd404)
            fail("scalar read mismatch");

        @(negedge clk);
        scalar_read_enable = 0;
        stripe_read_enable = 1;
        stripe_read_bank = 0;
        stripe_read_index = 3'd0;
        @(posedge clk);
        #1;
        if (!stripe_read_valid ||
            $signed(stripe_read_coefficients[0 +: DATA_W]) != 27'sd101 ||
            $signed(stripe_read_coefficients[15*DATA_W +: DATA_W]) !=
                -27'sd202)
            fail("stripe read mismatch");

        @(negedge clk);
        stripe_read_bank = 0;
        stripe_read_index = 3'd1;
        write_enable = 1;
        write_bank = 0;
        write_slot = 7'd16;
        write_coefficient = 27'sd505;
        @(posedge clk);
        #1;
        if (!stripe_read_valid ||
            $signed(stripe_read_coefficients[0 +: DATA_W]) != 27'sd505)
            fail("same-cycle forwarding mismatch");

        $display("SUPPORT COEFFICIENT STRIPE STORE PASS");
        $finish;
    end
endmodule

`default_nettype wire
