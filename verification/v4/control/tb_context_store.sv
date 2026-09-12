module tb_context_store;
reg clk = 0;
reg [348:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] invalidate;
wire [0:0] image_ready;
wire [31:0] generation;
wire [0:0] wr_en;
wire [7:0] wr_pc;
wire [5:0] wr_bank;
wire [255:0] wr_data;
wire [0:0] rd_valid;
wire [7:0] rd_pc;
wire [31:0] rd_generation;
wire [0:0] rsp_ready;
wire [0:0] rd_ready;
wire [0:0] rsp_valid;
wire [2047:0] rsp_words;
wire [255:0] rsp_control;
wire [7:0] rsp_pc;
wire [31:0] rsp_generation;
wire [3:0] rsp_fault;
assign {rst, cancel, invalidate, image_ready, generation, wr_en, wr_pc, wr_bank, wr_data, rd_valid, rd_pc, rd_generation, rsp_ready} = stim;
context_store dut (.clk(clk), .rst(rst), .cancel(cancel), .invalidate(invalidate), .image_ready(image_ready), .generation(generation), .wr_en(wr_en), .wr_pc(wr_pc), .wr_bank(wr_bank), .wr_data(wr_data), .rd_valid(rd_valid), .rd_pc(rd_pc), .rd_generation(rd_generation), .rsp_ready(rsp_ready), .rd_ready(rd_ready), .rsp_valid(rsp_valid), .rsp_words(rsp_words), .rsp_control(rsp_control), .rsp_pc(rsp_pc), .rsp_generation(rsp_generation), .rsp_fault(rsp_fault));
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h", cycle, rd_ready, rsp_valid, rsp_words, rsp_control, rsp_pc, rsp_generation, rsp_fault);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h", cycle, rd_ready, rsp_valid, rsp_words, rsp_control, rsp_pc, rsp_generation, rsp_fault);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #100000000; $fatal(1, "timeout"); end
endmodule
