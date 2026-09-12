`timescale 1ns/1ps
module tb_pe_alu;
reg clk = 0;
reg [171:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] req_valid;
wire [4:0] req_op;
wire [0:0] req_mode;
wire [26:0] req_a;
wire [26:0] req_b;
wire [63:0] req_acc;
wire [0:0] req_sel;
wire [0:0] req_lane;
wire [0:0] req_exec;
wire [15:0] req_job;
wire [15:0] req_tag;
wire [7:0] req_fmt;
wire [0:0] req_last;
wire [0:0] rsp_ready;
wire [0:0] req_ready;
wire [0:0] rsp_valid;
wire [26:0] rsp_data;
wire [63:0] rsp_acc;
wire [2:0] rsp_cmp;
wire [3:0] rsp_fault;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
wire [0:0] rsp_last;
wire [0:0] rsp_lane;
wire [0:0] rsp_exec;
wire [63:0] state_acc;
wire [0:0] state_mode;
assign {rst, cancel, req_valid, req_op, req_mode, req_a, req_b, req_acc, req_sel, req_lane, req_exec, req_job, req_tag, req_fmt, req_last, rsp_ready} = stim;
pe_alu dut (.clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_op(req_op), .req_mode(req_mode), .req_a(req_a), .req_b(req_b), .req_acc(req_acc), .req_sel(req_sel), .req_lane(req_lane), .req_exec(req_exec), .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last), .rsp_ready(rsp_ready), .rsp_drop(1'b0), .req_ready(req_ready), .rsp_valid(rsp_valid), .rsp_data(rsp_data), .rsp_acc(rsp_acc), .rsp_cmp(rsp_cmp), .rsp_fault(rsp_fault), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_last(rsp_last), .rsp_lane(rsp_lane), .rsp_exec(rsp_exec), .state_acc(state_acc), .state_mode(state_mode));
integer src, dst, count, cycle;
reg [4095:0] src_path, dst_path;
initial begin
if (!$value$plusargs("src=%s", src_path)) $fatal(1, "missing vectors");
if (!$value$plusargs("dst=%s", dst_path)) $fatal(1, "missing trace");
src = $fopen(src_path, "r"); dst = $fopen(dst_path, "w");
if (!src || !dst) $fatal(1, "cannot open files");
cycle = 0;
while (!$feof(src)) begin
count = $fscanf(src, "%h", stim);
if (count == 1) begin
#4;
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, state_acc, state_mode);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, state_acc, state_mode);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #10000000; $fatal(1, "timeout"); end
endmodule
