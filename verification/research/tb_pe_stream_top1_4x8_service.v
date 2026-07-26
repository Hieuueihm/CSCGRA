`timescale 1ns/1ps
module tb_pe_stream_top1_4x8_service;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,stream_valid=0,stream_done=0,exclude_support=0,allow_tiny=1;
    reg [9:0] stream_base_idx=0;
    reg [7:0] stream_lane_valid=0;
    reg [8*24-1:0] stream_data=0;
    reg [5:0] support_depth=0;
    reg [32*10-1:0] support_bus=0;
    wire candidate_valid,busy,done;
    wire [9:0] candidate_idx;
    wire [23:0] candidate_value;
    integer pass_count=0, fail_count=0;
    integer lane;

    pe_stream_top1_4x8_service dut(
        .clk(clk),.rst_n(rst_n),.start(start),.stream_valid(stream_valid),.stream_done(stream_done),
        .stream_base_idx(stream_base_idx),.stream_lane_valid(stream_lane_valid),.stream_data(stream_data),
        .exclude_support(exclude_support),.allow_tiny(allow_tiny),.support_depth(support_depth),.support_bus(support_bus),
        .candidate_valid(candidate_valid),.candidate_idx(candidate_idx),.candidate_value(candidate_value),.busy(busy),.done(done));

    task set_lane; input integer l; input signed [23:0] v; begin stream_data[l*24 +:24]=v; end endtask
    task send_block; input [9:0] base; input done_i; begin
        @(negedge clk); stream_base_idx=base; stream_lane_valid=8'hff; stream_valid=1; stream_done=done_i;
        @(negedge clk); stream_valid=0; stream_done=0; stream_data=0;
    end endtask
    task check; input [255:0] name; input cond; begin
        if(cond) begin pass_count=pass_count+1; $display("PASS %0s",name); end
        else begin fail_count=fail_count+1; $display("FAIL %0s idx=%0d val=%0d valid=%0b",name,candidate_idx,$signed(candidate_value),candidate_valid); end
    end endtask

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); start=1; @(negedge clk); start=0;
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, lane+1); send_block(10'd0,0);
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, lane+9); send_block(10'd8,0);
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, lane+17); set_lane(3,-24'sd99); send_block(10'd16,0);
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, lane+25); send_block(10'd24,1);
        wait(done===1'b1); @(negedge clk);
        check("four_block_max", candidate_valid && candidate_idx==10'd19 && $signed(candidate_value)==-24'sd99);

        @(negedge clk); start=1; @(negedge clk); start=0;
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, 24'sd1); set_lane(1,24'sd50); send_block(10'd0,0);
        for(lane=0; lane<8; lane=lane+1) set_lane(lane, 24'sd2); set_lane(0,-24'sd50); send_block(10'd8,1);
        wait(done===1'b1); @(negedge clk);
        check("partial_tie", candidate_valid && candidate_idx==10'd1 && $signed(candidate_value)==24'sd50);

        $display("tb_pe_stream_top1_4x8_service: %0d PASS, %0d FAIL", pass_count, fail_count);
        if(fail_count!=0) $fatal(1);
        $finish;
    end
endmodule
