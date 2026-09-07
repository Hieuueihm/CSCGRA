`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module tb_m11_iht_state_rebuild;
    localparam integer DATA_W = `RECON_SOLVER_W;
    reg [2:0] rebuild_mode = 3'd0;
    reg [10:0] stripe_base = 11'd0;
    reg [10:0] signal_length = 11'd20;
    reg [6:0] support_count = 7'd2;
    reg [5:0] selected_count = 6'd2;
    reg [`RECON_K_MAX*10-1:0] selected_indices = 0;
    reg [96*10-1:0] support_indices = 0;
    reg [96*DATA_W-1:0] support_coefficients = 0;
    reg support_coefficient_stripe_valid = 1;
    reg [16*DATA_W-1:0] support_coefficient_stripe = 0;
    reg [96*DATA_W-1:0] support_gradients = 0;
    reg [95:0] support_gradient_valid = 0;
    reg [16*DATA_W-1:0] dense_input = 0;
    wire [16*DATA_W-1:0] rebuilt_output;

    support_vector_rebuilder u_dut (
        .rebuild_mode(rebuild_mode),
        .stripe_base(stripe_base),
        .signal_length(signal_length),
        .support_count(support_count),
        .selected_count(selected_count),
        .selected_indices(selected_indices),
        .support_indices(support_indices),
        .support_coefficients(support_coefficients),
        .support_coefficient_stripe_valid(support_coefficient_stripe_valid),
        .support_coefficient_stripe(support_coefficient_stripe),
        .support_gradients(support_gradients),
        .support_gradient_valid(support_gradient_valid),
        .dense_input(dense_input),
        .rebuilt_output(rebuilt_output)
    );

    task fail;
        input [8*80-1:0] message;
        begin
            $display("M11 IHT STATE REBUILD FAIL: %0s", message);
            $fatal(1);
        end
    endtask

    integer lane;
    initial begin
        selected_indices[0 +: 10] = 10'd1;
        selected_indices[10 +: 10] = 10'd17;
        for (lane = 0; lane < 16; lane = lane + 1)
            dense_input[lane*DATA_W +: DATA_W] = lane + 1;
        #1;
        for (lane = 0; lane < 16; lane = lane + 1)
            if ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) !=
                ((lane == 1) ? 27'sd2 : 27'sd0))
                fail("dense first stripe mismatch");

        stripe_base = 11'd16;
        for (lane = 0; lane < 16; lane = lane + 1)
            dense_input[lane*DATA_W +: DATA_W] = 27'sd101 + lane;
        #1;
        for (lane = 0; lane < 16; lane = lane + 1)
            if ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) !=
                ((lane == 1) ? 27'sd102 : 27'sd0))
                fail("dense final partial stripe mismatch");

        rebuild_mode = 3'd1;
        stripe_base = 11'd0;
        support_coefficient_stripe[0 +: DATA_W] = 27'sd12345;
        support_coefficient_stripe[DATA_W +: DATA_W] = -27'sd6789;
        #1;
        for (lane = 0; lane < 16; lane = lane + 1) begin
            if ((lane == 0) &&
                ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) != 27'sd12345))
                fail("support coefficient slot zero mismatch");
            if ((lane == 1) &&
                ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) != -27'sd6789))
                fail("support coefficient slot one mismatch");
            if ((lane > 1) &&
                ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) != 27'sd0))
                fail("support pack tail not zero");
        end

        stripe_base = 11'd16;
        #1;
        if (rebuilt_output != 0)
            fail("support pack inactive stripe not zero");

        rebuild_mode = 3'd2;
        stripe_base = 11'd0;
        support_indices[0 +: 10] = 10'd1;
        support_indices[10 +: 10] = 10'd17;
        support_coefficients[0 +: DATA_W] = -27'sd31415;
        support_coefficients[DATA_W +: DATA_W] = 27'sd27182;
        #1;
        for (lane = 0; lane < 16; lane = lane + 1)
            if ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) !=
                ((lane == 1) ? -27'sd31415 : 27'sd0))
                fail("support dense scatter first stripe mismatch");

        stripe_base = 11'd16;
        #1;
        for (lane = 0; lane < 16; lane = lane + 1)
            if ($signed(rebuilt_output[lane*DATA_W +: DATA_W]) !=
                ((lane == 1) ? 27'sd27182 : 27'sd0))
                fail("support dense scatter partial stripe mismatch");

        stripe_base = 11'd32;
        #1;
        if (rebuilt_output != 0)
            fail("support dense scatter inactive stripe not zero");

        rebuild_mode = 3'd4;
        stripe_base = 11'd0;
        selected_count = 6'd1;
        selected_indices[0 +: 10] = 10'd17;
        support_gradients[0 +: DATA_W] = 27'sd111;
        support_gradients[DATA_W +: DATA_W] = -27'sd222;
        support_gradient_valid[1:0] = 2'b11;
        #1;
        if ($signed(rebuilt_output[0 +: DATA_W]) != 27'sd0 ||
            $signed(rebuilt_output[DATA_W +: DATA_W]) != -27'sd222)
            fail("MP rank-one gradient pack mismatch");
        $display("M11 IHT DENSE/SUPPORT STATE REBUILD PASS");
        $finish;
    end
endmodule

`default_nettype wire
