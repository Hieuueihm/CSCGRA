module tb_operand_feeder;
reg clk = 0;
reg [1350:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] req_valid;
wire [1:0] req_mode;
wire [0:0] req_trans;
wire [7:0] req_rows;
wire [10:0] req_cols;
wire [10:0] req_out;
wire [10:0] req_red;
wire [2:0] req_step;
wire [17:0] req_scale;
wire [255:0] req_signs;
wire [255:0] req_masks;
wire [7:0] req_sign_valid;
wire [575:0] req_dense;
wire [31:0] req_dense_valid;
wire [107:0] req_vec;
wire [3:0] req_vec_valid;
wire [0:0] req_src_fault;
wire [15:0] req_job;
wire [15:0] req_tag;
wire [7:0] req_fmt;
wire [0:0] req_last;
wire [0:0] rsp_ready;
wire [0:0] req_ready;
wire [0:0] rsp_valid;
wire [863:0] rsp_mat;
wire [863:0] rsp_vec;
wire [31:0] rsp_mask;
wire [3:0] rsp_fault;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
wire [0:0] rsp_last;
assign {rst, cancel, req_valid, req_mode, req_trans, req_rows, req_cols, req_out, req_red, req_step, req_scale, req_signs, req_masks, req_sign_valid, req_dense, req_dense_valid, req_vec, req_vec_valid, req_src_fault, req_job, req_tag, req_fmt, req_last, rsp_ready} = stim;
operand_feeder dut (.clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_mode(req_mode), .req_trans(req_trans), .req_rows(req_rows), .req_cols(req_cols), .req_out(req_out), .req_red(req_red), .req_step(req_step), .req_scale(req_scale), .req_signs(req_signs), .req_masks(req_masks), .req_sign_valid(req_sign_valid), .req_dense(req_dense), .req_dense_valid(req_dense_valid), .req_vec(req_vec), .req_vec_valid(req_vec_valid), .req_src_fault(req_src_fault), .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last), .rsp_ready(rsp_ready), .req_ready(req_ready), .rsp_valid(rsp_valid), .rsp_mat(rsp_mat), .rsp_vec(rsp_vec), .rsp_mask(rsp_mask), .rsp_fault(rsp_fault), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_last(rsp_last));
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, rsp_valid, rsp_mat, rsp_vec, rsp_mask, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h", cycle, req_ready, rsp_valid, rsp_mat, rsp_vec, rsp_mask, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #10000000; $fatal(1, "timeout"); end
endmodule
