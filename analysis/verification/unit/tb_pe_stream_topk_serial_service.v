`timescale 1ns/1ps
module tb_pe_stream_topk_serial_service;
    localparam COLS=8, DATA_W=24, IDX_W=10, MAX_SEL=16, MAX_SUPPORT=32;
    reg clk=0,rst_n=0,start=0,exclude_support=0,allow_tiny=1,stream_valid=0,stream_done=0,append_done=0;
    reg [4:0] max_count=0; reg [2:0] append_path_in=0; reg [IDX_W-1:0] stream_base_idx=0;
    reg [COLS-1:0] stream_lane_valid=0; reg [COLS*DATA_W-1:0] stream_data=0;
    reg [5:0] support_depth=0; reg [MAX_SUPPORT*IDX_W-1:0] support_bus=0;
    wire append_valid,stream_ready,busy,done; wire [IDX_W-1:0] append_idx; wire [2:0] append_path;
    integer passes=0,fails=0,out_count=0; reg [IDX_W-1:0] got[0:15];
    pe_stream_topk_serial_service #(.COLS(COLS),.DATA_W(DATA_W),.IDX_W(IDX_W),.MAX_SEL(MAX_SEL),.MAX_SUPPORT(MAX_SUPPORT)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.max_count(max_count),.append_path_in(append_path_in),.exclude_support(exclude_support),.allow_tiny(allow_tiny),
        .stream_valid(stream_valid),.stream_done(stream_done),.stream_base_idx(stream_base_idx),.stream_lane_valid(stream_lane_valid),.stream_data(stream_data),
        .support_depth(support_depth),.support_bus(support_bus),.append_done(append_done),.append_valid(append_valid),.append_idx(append_idx),.append_path(append_path),.stream_ready(stream_ready),.busy(busy),.done(done));
    always #5 clk=~clk;
    always @(posedge clk) begin append_done<=0; if(append_valid) begin got[out_count]<=append_idx; out_count<=out_count+1; append_done<=1; end end
    task set_lane; input integer lane; input signed [DATA_W-1:0] value; begin stream_data[lane*DATA_W +: DATA_W]=value[DATA_W-1:0]; end endtask
    task pulse_start; begin out_count=0; @(posedge clk); start<=1; @(posedge clk); start<=0; end endtask
    task send_block; input [IDX_W-1:0] base; input [COLS-1:0] valid; input last; begin wait(stream_ready); @(negedge clk); stream_base_idx=base; stream_lane_valid=valid; stream_valid=1; stream_done=last; @(negedge clk); stream_valid=0; stream_done=0; stream_lane_valid=0; end endtask
    task expect_count; input integer exp; begin if(out_count==exp) passes=passes+1; else begin fails=fails+1; $display("FAIL count exp=%0d got=%0d",exp,out_count); end end endtask
    task expect_idx; input integer pos; input [IDX_W-1:0] exp; begin if(got[pos]==exp) passes=passes+1; else begin fails=fails+1; $display("FAIL pos=%0d exp=%0d got=%0d",pos,exp,got[pos]); end end endtask
    initial begin
        repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        max_count=3; append_path_in=2; stream_data=0; pulse_start();
        set_lane(0,3); set_lane(1,-9); set_lane(2,8); set_lane(3,1); set_lane(4,-2); set_lane(5,7); set_lane(6,0); set_lane(7,-4); send_block(0,8'hff,0);
        stream_data=0; set_lane(0,9); set_lane(1,-6); set_lane(2,10); set_lane(3,5); send_block(8,8'h0f,1);
        wait(done); @(posedge clk); expect_count(3); expect_idx(0,10); expect_idx(1,1); expect_idx(2,8);
        support_bus=0; support_depth=1; support_bus[0 +: IDX_W]=31; exclude_support=1; max_count=2; stream_data=0; pulse_start();
        set_lane(0,1); set_lane(1,-20); set_lane(2,19); set_lane(3,4); send_block(30,8'h0f,1);
        wait(done); @(posedge clk); expect_count(2); expect_idx(0,32); expect_idx(1,33);
        allow_tiny=0; exclude_support=0; support_depth=0; max_count=2; stream_data=0; pulse_start();
        set_lane(0,1); set_lane(1,-1); set_lane(2,2); set_lane(3,-3); send_block(40,8'h0f,1);
        wait(done); @(posedge clk); expect_count(2); expect_idx(0,43); expect_idx(1,42);
        $display("tb_pe_stream_topk_serial_service: %0d PASS, %0d FAIL",passes,fails); if(fails) $fatal(1); $finish;
    end
endmodule
