`timescale 1ns/1ps
`default_nettype none

module tb_support_workspace_coefficient_mirror;
    localparam integer DATA_W = 27;
    localparam integer INDEX_W = 10;
    localparam integer WORK_MAX = 96;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg clear_valid = 0;
    reg clear_bank = 0;
    reg write_valid = 0;
    reg write_bank = 0;
    reg [6:0] write_slot = 0;
    reg [INDEX_W-1:0] write_atom = 0;
    reg signed [DATA_W-1:0] write_coefficient = 0;
    reg write_atom_enable = 0;
    reg write_coefficient_enable = 0;
    reg read_bank = 0;
    reg [6:0] read_slot = 0;
    wire read_valid;
    wire [INDEX_W-1:0] read_atom;
    wire signed [DATA_W-1:0] read_coefficient;
    reg coefficient_scalar_read_enable = 0;
    reg coefficient_scalar_read_bank = 0;
    reg [6:0] coefficient_scalar_read_slot = 0;
    wire coefficient_scalar_read_valid;
    wire signed [DATA_W-1:0] coefficient_scalar_read_coefficient;
    reg coefficient_stripe_read_enable = 0;
    reg coefficient_stripe_read_bank = 0;
    reg [2:0] coefficient_stripe_read_index = 0;
    wire coefficient_stripe_read_valid;
    wire [16*DATA_W-1:0] coefficient_stripe_read_coefficients;

    support_workspace #(
        .DATA_W(DATA_W), .INDEX_W(INDEX_W), .WORK_MAX(WORK_MAX)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .clear_valid(clear_valid),
        .clear_bank(clear_bank), .write_valid(write_valid),
        .write_bank(write_bank), .write_slot(write_slot),
        .write_atom(write_atom), .write_coefficient(write_coefficient),
        .write_atom_enable(write_atom_enable),
        .write_coefficient_enable(write_coefficient_enable),
        .read_bank(read_bank), .read_slot(read_slot),
        .read_valid(read_valid), .read_atom(read_atom),
        .read_coefficient(read_coefficient),
        .coefficient_scalar_read_enable(coefficient_scalar_read_enable),
        .coefficient_scalar_read_bank(coefficient_scalar_read_bank),
        .coefficient_scalar_read_slot(coefficient_scalar_read_slot),
        .coefficient_scalar_read_valid(coefficient_scalar_read_valid),
        .coefficient_scalar_read_coefficient(coefficient_scalar_read_coefficient),
        .coefficient_stripe_read_enable(coefficient_stripe_read_enable),
        .coefficient_stripe_read_bank(coefficient_stripe_read_bank),
        .coefficient_stripe_read_index(coefficient_stripe_read_index),
        .coefficient_stripe_read_valid(coefficient_stripe_read_valid),
        .coefficient_stripe_read_coefficients(coefficient_stripe_read_coefficients),
        .query_bank(1'b0), .query_atom({INDEX_W{1'b0}}),
        .query_member(), .query_slot(), .membership_query_bank(1'b0),
        .membership_query_atom({INDEX_W{1'b0}}),
        .membership_query_member(), .membership_query_slot(),
        .bank0_entries(), .bank1_entries(), .bank0_slot_valid(),
        .bank1_slot_valid(), .debug_bitmaps()
    );

    task write_entry;
        input bank;
        input [6:0] slot;
        input [INDEX_W-1:0] atom;
        input signed [DATA_W-1:0] coefficient;
        input atom_enable;
        input coefficient_enable;
        begin
            @(negedge clk);
            write_valid = 1;
            write_bank = bank;
            write_slot = slot;
            write_atom = atom;
            write_coefficient = coefficient;
            write_atom_enable = atom_enable;
            write_coefficient_enable = coefficient_enable;
            @(negedge clk);
            write_valid = 0;
            write_atom_enable = 0;
            write_coefficient_enable = 0;
        end
    endtask

    task check_scalar;
        input bank;
        input [6:0] slot;
        input signed [DATA_W-1:0] expected;
        begin
            @(negedge clk);
            coefficient_scalar_read_enable = 1;
            coefficient_scalar_read_bank = bank;
            coefficient_scalar_read_slot = slot;
            @(posedge clk);
            #1;
            if (!coefficient_scalar_read_valid ||
                coefficient_scalar_read_coefficient !== expected) begin
                $display("FAIL scalar bank=%0d slot=%0d got=%0d expected=%0d",
                    bank, slot, $signed(coefficient_scalar_read_coefficient),
                    $signed(expected));
                $fatal(1);
            end
            @(negedge clk);
            coefficient_scalar_read_enable = 0;
        end
    endtask

    task check_stripe_lane;
        input bank;
        input [2:0] stripe;
        input [3:0] lane;
        input signed [DATA_W-1:0] expected;
        reg signed [DATA_W-1:0] observed;
        begin
            @(negedge clk);
            coefficient_stripe_read_enable = 1;
            coefficient_stripe_read_bank = bank;
            coefficient_stripe_read_index = stripe;
            @(posedge clk);
            #1;
            observed = coefficient_stripe_read_coefficients[lane*DATA_W +: DATA_W];
            if (!coefficient_stripe_read_valid || observed !== expected) begin
                $display("FAIL stripe bank=%0d stripe=%0d lane=%0d got=%0d expected=%0d",
                    bank, stripe, lane, $signed(observed), $signed(expected));
                $fatal(1);
            end
            @(negedge clk);
            coefficient_stripe_read_enable = 0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        write_entry(0, 7'd0, 10'd12, 27'sd111, 1, 1);
        write_entry(0, 7'd17, 10'd23, -27'sd222, 1, 1);
        write_entry(1, 7'd2, 10'd34, 27'sd333, 1, 1);
        write_entry(0, 7'd0, 10'd45, 27'sd999, 1, 0);

        read_bank = 0;
        read_slot = 0;
        #1;
        if (!read_valid || read_atom !== 10'd45 || read_coefficient !== 27'sd111) begin
            $display("FAIL legacy workspace path atom=%0d coefficient=%0d",
                read_atom, $signed(read_coefficient));
            $fatal(1);
        end

        check_scalar(0, 7'd0, 27'sd111);
        check_scalar(0, 7'd17, -27'sd222);
        check_scalar(1, 7'd2, 27'sd333);
        check_stripe_lane(0, 3'd0, 4'd0, 27'sd111);
        check_stripe_lane(0, 3'd1, 4'd1, -27'sd222);
        check_stripe_lane(1, 3'd0, 4'd2, 27'sd333);
        $display("SUPPORT WORKSPACE COEFFICIENT MIRROR PASS");
        $finish;
    end
endmodule

`default_nettype wire
