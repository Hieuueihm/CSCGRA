module tb_vector_store;
reg clk = 0;
reg [1642:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] begin_valid;
wire [1:0] begin_plane;
wire [12:0] begin_length;
wire [31:0] begin_generation;
wire [15:0] begin_job;
wire [7:0] begin_fmt;
wire [0:0] fill_valid;
wire [6:0] fill_block;
wire [31:0] fill_mask;
wire [863:0] fill_data;
wire [0:0] fill_last;
wire [1:0] rd_valid;
wire [3:0] rd_plane;
wire [63:0] rd_mask;
wire [447:0] rd_addr;
wire [63:0] rd_generation;
wire [31:0] rd_job;
wire [31:0] rd_tag;
wire [15:0] rd_fmt;
wire [1:0] rsp_ready;
wire [0:0] begin_ready;
wire [0:0] fill_ready;
wire [0:0] loading;
wire [2:0] plane_valid;
wire [3:0] load_fault;
wire [1:0] rd_ready;
wire [1:0] rsp_valid;
wire [1727:0] rsp_data;
wire [63:0] rsp_mask;
wire [63:0] rsp_generation;
wire [31:0] rsp_job;
wire [31:0] rsp_tag;
wire [15:0] rsp_fmt;
wire [7:0] rsp_fault;
assign {rst, cancel, begin_valid, begin_plane, begin_length, begin_generation, begin_job, begin_fmt, fill_valid, fill_block, fill_mask, fill_data, fill_last, rd_valid, rd_plane, rd_mask, rd_addr, rd_generation, rd_job, rd_tag, rd_fmt, rsp_ready} = stim;
vector_store dut (.clk(clk), .rst(rst), .cancel(cancel), .begin_valid(begin_valid), .begin_plane(begin_plane), .begin_length(begin_length), .begin_generation(begin_generation), .begin_job(begin_job), .begin_fmt(begin_fmt), .fill_valid(fill_valid), .fill_block(fill_block), .fill_mask(fill_mask), .fill_data(fill_data), .fill_last(fill_last), .rd_valid(rd_valid), .rd_plane(rd_plane), .rd_mask(rd_mask), .rd_addr(rd_addr), .rd_generation(rd_generation), .rd_job(rd_job), .rd_tag(rd_tag), .rd_fmt(rd_fmt), .rsp_ready(rsp_ready), .begin_ready(begin_ready), .fill_ready(fill_ready), .loading(loading), .plane_valid(plane_valid), .load_fault(load_fault), .rd_ready(rd_ready), .rsp_valid(rsp_valid), .rsp_data(rsp_data), .rsp_mask(rsp_mask), .rsp_generation(rsp_generation), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_fault(rsp_fault));
integer src, dst, scanned, cycle;
reg [4095:0] src_path, dst_path;
initial begin
if (!$value$plusargs("src=%s", src_path)) $fatal(1, "missing vectors");
if (!$value$plusargs("dst=%s", dst_path)) $fatal(1, "missing trace");
src = $fopen(src_path, "r"); dst = $fopen(dst_path, "w");
if (!src || !dst) $fatal(1, "cannot open files");
cycle = 0;
while (!$feof(src)) begin
scanned = $fscanf(src, "%h", stim);
if (scanned == 1) begin
#4;
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, begin_ready, fill_ready, loading, plane_valid, load_fault, rd_ready, rsp_valid, rsp_data, rsp_mask, rsp_generation, rsp_job, rsp_tag, rsp_fmt, rsp_fault);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, begin_ready, fill_ready, loading, plane_valid, load_fault, rd_ready, rsp_valid, rsp_data, rsp_mask, rsp_generation, rsp_job, rsp_tag, rsp_fmt, rsp_fault);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #100000000; $fatal(1, "timeout"); end
endmodule
