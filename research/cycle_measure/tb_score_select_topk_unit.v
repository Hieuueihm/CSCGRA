`timescale 1ns/1ps
module tb_score_select_topk_unit;
localparam COLS=8; localparam DATA_W=24; localparam SCALAR_W=56; localparam IDX_W=10; localparam CTX_W=64;
reg clk=0,rst_n=0,ctx_valid=0,addr_valid=0,addr_done=0,append_done=0;
reg [CTX_W-1:0] ctx_word=0; reg [3:0] uop_class=0; reg [COLS-1:0] lane_valid=0; reg [IDX_W-1:0] base_idx=0; reg [COLS*DATA_W-1:0] spm_pa_rdata=0; reg [SCALAR_W-1:0] threshold_value=0;
wire append_valid; wire [IDX_W-1:0] append_idx; wire [2:0] append_path; wire busy,done;
integer pass_cnt=0, fail_cnt=0, cycle=0, ap=0; reg [IDX_W-1:0] got[0:3];
score_select_service dut(.clk(clk),.rst_n(rst_n),.ctx_valid(ctx_valid),.ctx_word(ctx_word),.uop_class(uop_class),.lane_valid(lane_valid),.base_idx(base_idx),.addr_valid(addr_valid),.addr_done(addr_done),.spm_pa_rdata(spm_pa_rdata),.threshold_value(threshold_value),.support_depth(6'd0),.support_bus({(32*IDX_W){1'b0}}),.append_done(append_done),.append_valid(append_valid),.append_idx(append_idx),.append_path(append_path),.busy(busy),.done(done));
always #5 clk=~clk; task tick; begin @(posedge clk); #1; cycle=cycle+1; append_done=0; if(append_valid) begin got[ap]=append_idx; ap=ap+1; append_done=1; $display("APPEND idx=%0d", append_idx); end end endtask
task check; input [255:0] name; input cond; begin if(cond) begin pass_cnt=pass_cnt+1; $display("PASS %0s",name); end else begin fail_cnt=fail_cnt+1; $display("FAIL %0s",name); end end endtask
function [63:0] select_topk_ctx; input [4:0] count; begin select_topk_ctx=0; select_topk_ctx[63:60]=4'h1; select_topk_ctx[59:56]=4'd5; select_topk_ctx[55:52]=4'd1; select_topk_ctx[51:48]=4'd2; select_topk_ctx[27:24]=4'd2; select_topk_ctx[22:20]=3'd0; select_topk_ctx[15:11]=count; end endfunction
task set_lane; input integer lane; input [23:0] v; begin spm_pa_rdata[lane*DATA_W +: DATA_W]=v; end endtask
initial begin
 repeat(3) tick(); rst_n=1; repeat(2) tick();
 ctx_word=select_topk_ctx(5'd2); uop_class=4'd5; ctx_valid=1; tick(); ctx_valid=0; uop_class=0;
 lane_valid=8'hff; base_idx=0; spm_pa_rdata=0; set_lane(0,24'h000000); set_lane(1,24'h011000); set_lane(2,24'hfec000); set_lane(3,24'hffc000); set_lane(4,24'h009000); set_lane(5,24'h00b000); set_lane(6,24'hff7000); set_lane(7,24'h005000); addr_valid=1; addr_done=0; tick();
 base_idx=8; spm_pa_rdata=0; set_lane(0,24'hfe4000); set_lane(1,24'h003000); set_lane(2,24'h004000); set_lane(3,24'h002000); set_lane(4,24'hfef000); set_lane(5,24'h001000); set_lane(6,24'hfed000); set_lane(7,24'h002000); addr_valid=1; addr_done=0; tick();
 base_idx=16; spm_pa_rdata=0; set_lane(0,24'h00e000); set_lane(1,24'hffd000); set_lane(2,24'h000000); set_lane(3,24'h005000); set_lane(4,24'h001000); set_lane(5,24'hfff000); set_lane(6,24'hffb000); set_lane(7,24'h013000); addr_valid=1; addr_done=0; tick();
 base_idx=24; spm_pa_rdata=0; set_lane(0,24'h004000); set_lane(1,24'h007000); set_lane(2,24'hff6000); set_lane(3,24'hfff000); set_lane(4,24'h000000); set_lane(5,24'hff7000); set_lane(6,24'hffb000); set_lane(7,24'h005000); addr_valid=1; addr_done=1; tick();
 addr_valid=0; addr_done=0;
 repeat(30) tick();
 check("top0", got[0]==10'd8); check("top1", got[1]==10'd2); check("done", done || !busy); check("count", ap==2);
 $display("tb_score_select_topk_unit: %0d PASS, %0d FAIL", pass_cnt, fail_cnt); $finish;
end
endmodule
