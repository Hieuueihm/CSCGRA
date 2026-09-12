module tb_control_decode;
reg clk = 0;
reg [263:0] stim;
wire [255:0] word;
wire [7:0] rev;
wire [3:0] kind;
wire [15:0] count;
wire [7:0] loop_target;
wire [7:0] branch_target;
wire [2:0] predicate;
wire [2:0] address_mode;
wire [23:0] address;
wire [15:0] stride;
wire [3:0] fault;
assign {word, rev} = stim;
control_decode dut (.word(word), .rev(rev), .kind(kind), .count(count), .loop_target(loop_target), .branch_target(branch_target), .predicate(predicate), .address_mode(address_mode), .address(address), .stride(stride), .fault(fault));
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h", cycle, kind, count, loop_target, branch_target, predicate, address_mode, address, stride, fault);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h", cycle, kind, count, loop_target, branch_target, predicate, address_mode, address, stride, fault);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #100000000; $fatal(1, "timeout"); end
endmodule
