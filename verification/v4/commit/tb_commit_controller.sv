`timescale 1ns/1ps
module tb_commit_controller;
reg clk=0;
reg [0:0] rst;
reg [0:0] cancel;
reg [0:0] begin_valid;
reg [7:0] begin_rows;
reg [6:0] begin_count;
reg [959:0] begin_support;
reg [15:0] begin_job;
reg [15:0] begin_tag;
reg [7:0] begin_fmt;
reg [6:0] begin_exponent;
reg [0:0] fill_valid;
reg [1:0] fill_block;
reg [31:0] fill_mask;
reg [863:0] fill_data;
reg [0:0] fill_last;
reg [15:0] fill_job;
reg [15:0] fill_tag;
reg [7:0] fill_fmt;
reg [0:0] decision_valid;
reg [0:0] decision_approve;
reg [15:0] decision_job;
reg [15:0] decision_tag;
reg [7:0] decision_fmt;
reg [0:0] status_ready;
reg [0:0] read_valid;
reg [6:0] read_slot;
reg [0:0] rsp_ready;
wire [0:0] begin_ready;
wire [0:0] fill_ready;
wire [0:0] decision_ready;
wire [0:0] status_valid;
wire [3:0] status_fault;
wire [0:0] status_committed;
wire [15:0] status_job;
wire [15:0] status_tag;
wire [7:0] status_fmt;
wire [0:0] committed_valid;
wire [6:0] committed_count;
wire [7:0] committed_rows;
wire [0:0] read_ready;
wire [0:0] rsp_valid;
wire [23:0] rsp_x;
wire [9:0] rsp_index;
wire [6:0] rsp_exponent;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
wire [3:0] rsp_fault;
commit_controller dut(.*);
integer src,dst,rc,cycle;
reg [4095:0] src_path,dst_path;
task snapshot(input integer phase);
$fdisplay(dst,"%0d %0d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",cycle,phase,begin_ready,fill_ready,decision_ready,status_valid,status_fault,status_committed,status_job,status_tag,status_fmt,committed_valid,committed_count,committed_rows,read_ready,rsp_valid,rsp_x,rsp_index,rsp_exponent,rsp_job,rsp_tag,rsp_fmt,rsp_fault);
endtask
initial begin
if (!$value$plusargs("src=%s",src_path) || !$value$plusargs("dst=%s",dst_path)) $fatal(1,"paths");
src=$fopen(src_path,"r"); dst=$fopen(dst_path,"w"); if (!src || !dst) $fatal(1,"files");
cycle=0;
while (!$feof(src)) begin
rc=$fscanf(src,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rst,cancel,begin_valid,begin_rows,begin_count,begin_support,begin_job,begin_tag,begin_fmt,begin_exponent,fill_valid,fill_block,fill_mask,fill_data,fill_last,fill_job,fill_tag,fill_fmt,decision_valid,decision_approve,decision_job,decision_tag,decision_fmt,status_ready,read_valid,read_slot,rsp_ready);
if (rc!=27) $fatal(1,"bad vector");
#5; snapshot(0); clk=1; #5; snapshot(1); clk=0; cycle=cycle+1;
end
$fclose(src); $fclose(dst); $display("PASS cycles=%0d",cycle); $finish;
end
endmodule
