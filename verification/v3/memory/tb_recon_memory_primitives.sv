`timescale 1ns/1ps
`default_nettype none

module tb_recon_memory_primitives;
    reg clk;
    reg rst_n;
    reg clear_valid;
    reg write_valid;
    reg [3:0] write_index;
    reg [2:0] write_slot;
    reg query0_valid;
    reg [3:0] query0_index;
    wire query0_response_valid;
    wire query0_member;
    wire [2:0] query0_slot;
    reg query1_valid;
    reg [3:0] query1_index;
    wire query1_response_valid;
    wire query1_member;
    wire [2:0] query1_slot;
    wire epoch_wrap_fault;

    recon_epoch_slot_map #(
        .INDEX_W(4), .SLOT_W(3), .EPOCH_W(4), .DEPTH(16)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear_valid(clear_valid),
        .write_valid(write_valid), .write_index(write_index),
        .write_slot(write_slot), .query0_valid(query0_valid),
        .query0_index(query0_index),
        .query0_response_valid(query0_response_valid),
        .query0_member(query0_member), .query0_slot(query0_slot),
        .query1_valid(query1_valid), .query1_index(query1_index),
        .query1_response_valid(query1_response_valid),
        .query1_member(query1_member), .query1_slot(query1_slot),
        .epoch_wrap_fault(epoch_wrap_fault)
    );

    always #5 clk = ~clk;

    task automatic idle_inputs;
        begin
            clear_valid = 0;
            write_valid = 0;
            query0_valid = 0;
            query1_valid = 0;
        end
    endtask

    task automatic query_pair;
        input request0_valid;
        input [3:0] request0_index;
        input expected0_member;
        input [2:0] expected0_slot;
        input request1_valid;
        input [3:0] request1_index;
        input expected1_member;
        input [2:0] expected1_slot;
        begin
            @(negedge clk);
            query0_valid = request0_valid;
            query0_index = request0_index;
            query1_valid = request1_valid;
            query1_index = request1_index;
            @(posedge clk);
            #1;
            query0_valid = 0;
            query1_valid = 0;
            if (request0_valid &&
                (!query0_response_valid ||
                 (query0_member !== expected0_member) ||
                 (expected0_member && (query0_slot !== expected0_slot)))) begin
                $display("FAIL query0 valid=%0d member=%0d slot=%0d",
                         query0_response_valid, query0_member, query0_slot);
                $fatal(1);
            end
            if (request1_valid &&
                (!query1_response_valid ||
                 (query1_member !== expected1_member) ||
                 (expected1_member && (query1_slot !== expected1_slot)))) begin
                $display("FAIL query1 valid=%0d member=%0d slot=%0d",
                         query1_response_valid, query1_member, query1_slot);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        write_index = 0;
        write_slot = 0;
        query0_index = 0;
        query1_index = 0;
        idle_inputs();
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        query_pair(1, 4'd5, 0, 0, 0, 0, 0, 0);

        @(negedge clk);
        write_valid = 1;
        write_index = 4'd5;
        write_slot = 3'd3;
        query0_valid = 1;
        query0_index = 4'd5;
        @(posedge clk);
        #1;
        write_valid = 0;
        query0_valid = 0;
        if (!query0_response_valid || !query0_member || (query0_slot !== 3'd3)) begin
            $display("FAIL write-through query");
            $fatal(1);
        end

        @(negedge clk);
        write_valid = 1;
        write_index = 4'd9;
        write_slot = 3'd6;
        @(posedge clk);
        #1;
        write_valid = 0;
        query_pair(1, 4'd5, 1, 3, 1, 4'd9, 1, 6);

        @(negedge clk);
        clear_valid = 1;
        @(posedge clk);
        #1;
        clear_valid = 0;
        query_pair(1, 4'd5, 0, 0, 1, 4'd9, 0, 0);

        if (epoch_wrap_fault) begin
            $display("FAIL unexpected epoch wrap fault");
            $fatal(1);
        end
        $display("PASS reusable synchronous memory primitives");
        $finish;
    end
endmodule

`default_nettype wire
