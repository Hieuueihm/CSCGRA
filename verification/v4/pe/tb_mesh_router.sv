`timescale 1ns/1ps
module tb_mesh_router #(parameter integer TILE_ID = 0);
reg clk = 0;
reg [257:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] req_valid;
wire [11:0] req_routes;
wire [63:0] req_val;
wire [63:0] req_acc;
wire [63:0] req_res;
wire [2:0] req_src;
wire [0:0] req_lane;
wire [0:0] req_exec;
wire [15:0] req_job;
wire [15:0] req_tag;
wire [7:0] req_fmt;
wire [0:0] req_last;
wire [3:0] out_ready;
wire [0:0] rsp_ready;
wire [0:0] req_ready;
wire [3:0] out_valid;
wire [255:0] out_data;
wire [11:0] out_sel;
wire [15:0] out_job;
wire [15:0] out_tag;
wire [7:0] out_fmt;
wire [0:0] out_last;
wire [0:0] rsp_valid;
wire [3:0] rsp_fault;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
wire [0:0] rsp_last;
wire [0:0] rsp_lane;
wire [0:0] rsp_exec;
assign {rst, cancel, req_valid, req_routes, req_val, req_acc, req_res, req_src, req_lane, req_exec, req_job, req_tag, req_fmt, req_last, out_ready, rsp_ready} = stim;
mesh_router #(.TILE_ID(TILE_ID)) dut (.clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_routes(req_routes), .req_val(req_val), .req_acc(req_acc), .req_res(req_res), .req_src(req_src), .req_lane(req_lane), .req_exec(req_exec), .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last), .out_ready(out_ready), .rsp_ready(rsp_ready), .req_ready(req_ready), .out_valid(out_valid), .out_data(out_data), .out_sel(out_sel), .out_job(out_job), .out_tag(out_tag), .out_fmt(out_fmt), .out_last(out_last), .rsp_valid(rsp_valid), .rsp_fault(rsp_fault), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_last(rsp_last), .rsp_lane(rsp_lane), .rsp_exec(rsp_exec));
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, out_valid, out_data, out_sel, out_job, out_tag, out_fmt, out_last, rsp_valid, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, out_valid, out_data, out_sel, out_job, out_tag, out_fmt, out_last, rsp_valid, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #10000000; $fatal(1, "timeout"); end
endmodule

