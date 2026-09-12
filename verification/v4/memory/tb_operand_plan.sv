module tb_operand_plan;
reg clk = 0;
reg [58:0] stim;
wire [1:0] mode;
wire [0:0] trans;
wire [7:0] rows;
wire [10:0] cols;
wire [10:0] out_idx;
wire [10:0] red_idx;
wire [2:0] step;
wire [11:0] vec_base;
wire [31:0] mat_mask;
wire [31:0] vec_mask;
wire [287:0] mat_addr;
wire [223:0] vec_addr;
wire [19:0] vec_banks;
wire [3:0] vec_lanes;
wire [3:0] fault;
assign {mode, trans, rows, cols, out_idx, red_idx, step, vec_base} = stim;
operand_plan dut (.mode(mode), .trans(trans), .rows(rows), .cols(cols), .out_idx(out_idx), .red_idx(red_idx), .step(step), .vec_base(vec_base), .mat_mask(mat_mask), .vec_mask(vec_mask), .mat_addr(mat_addr), .vec_addr(vec_addr), .vec_banks(vec_banks), .vec_lanes(vec_lanes), .fault(fault));
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h", cycle, mat_mask, vec_mask, mat_addr, vec_addr, vec_banks, vec_lanes, fault);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h", cycle, mat_mask, vec_mask, mat_addr, vec_addr, vec_banks, vec_lanes, fault);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #100000000; $fatal(1, "timeout"); end
endmodule
