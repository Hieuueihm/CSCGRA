module tb_context_fabric;
reg clk = 0;
reg [590:0] stim;
wire [0:0] rst;
wire [0:0] cancel;
wire [0:0] begin_valid;
wire [7:0] begin_rev;
wire [8:0] begin_depth;
wire [0:0] begin_verified;
wire [31:0] begin_generation;
wire [0:0] wr_valid;
wire [7:0] wr_pc;
wire [5:0] wr_bank;
wire [255:0] wr_data;
wire [0:0] wr_last;
wire [0:0] start_valid;
wire [7:0] start_pc;
wire [31:0] start_limit;
wire [15:0] start_job;
wire [7:0] start_fmt;
wire [2:0] predicates;
wire [0:0] addr_ready;
wire [0:0] addr_rsp_valid;
wire [0:0] addr_rsp_fault;
wire [15:0] addr_rsp_job;
wire [15:0] addr_rsp_tag;
wire [0:0] done_ready;
wire [0:0] issue_allow;
wire [0:0] response_allow;
wire [31:0] backend_mask;
wire [127:0] link_ready;
wire [0:0] begin_ready;
wire [0:0] wr_ready;
wire [0:0] image_ready;
wire [0:0] loading;
wire [3:0] load_fault;
wire [0:0] start_ready;
wire [0:0] addr_valid;
wire [2:0] addr_mode;
wire [23:0] addr_value;
wire [15:0] addr_stride;
wire [0:0] addr_rsp_ready;
wire [0:0] exec_valid;
wire [2047:0] exec_words;
wire [15:0] exec_job;
wire [15:0] exec_tag;
wire [7:0] exec_fmt;
wire [0:0] exec_last;
wire [0:0] exec_cancel;
wire [0:0] exec_rsp_ready;
wire [0:0] done_valid;
wire [3:0] done_fault;
wire [7:0] pc;
wire [31:0] retired;
wire [2:0] state_depth;
wire [63:0] state_remaining;
wire [0:0] state_fetch_valid;
wire [0:0] state_mem_valid;
wire [2047:0] state_acc;
wire [6911:0] state_rf;
wire [255:0] state_valid;
wire [95:0] state_preds;
wire [0:0] result_valid;
wire [863:0] result_data;
wire [0:0] result_fault;
wire [31:0] result_store;
assign {rst, cancel, begin_valid, begin_rev, begin_depth, begin_verified, begin_generation, wr_valid, wr_pc, wr_bank, wr_data, wr_last, start_valid, start_pc, start_limit, start_job, start_fmt, predicates, addr_ready, addr_rsp_valid, addr_rsp_fault, addr_rsp_job, addr_rsp_tag, done_ready, issue_allow, response_allow, backend_mask, link_ready} = stim;
wire exec_ready, exec_rsp_valid, exec_rsp_fault;
wire [15:0] exec_rsp_job, exec_rsp_tag;
wire [7:0] exec_rsp_fmt;
wire fab_ready, fab_valid, fab_fault;
wire [2047:0] unused_acc;
wire [127:0] unused_faults;
wire [31:0] unused_exec, unused_halt;
wire [3:0] unused_feed_fault;
wire unused_last;
context_engine dut (.clk(clk), .rst(rst), .cancel(cancel), .begin_valid(begin_valid), .begin_rev(begin_rev), .begin_depth(begin_depth), .begin_verified(begin_verified), .begin_generation(begin_generation), .wr_valid(wr_valid), .wr_pc(wr_pc), .wr_bank(wr_bank), .wr_data(wr_data), .wr_last(wr_last), .start_valid(start_valid), .start_pc(start_pc), .start_limit(start_limit), .start_job(start_job), .start_fmt(start_fmt), .predicates(predicates), .addr_ready(addr_ready), .addr_rsp_valid(addr_rsp_valid), .addr_rsp_fault(addr_rsp_fault), .addr_rsp_job(addr_rsp_job), .addr_rsp_tag(addr_rsp_tag), .exec_ready(exec_ready), .exec_rsp_valid(exec_rsp_valid), .exec_rsp_fault(exec_rsp_fault), .exec_rsp_job(exec_rsp_job), .exec_rsp_tag(exec_rsp_tag), .exec_rsp_fmt(exec_rsp_fmt), .done_ready(done_ready), .begin_ready(begin_ready), .wr_ready(wr_ready), .image_ready(image_ready), .loading(loading), .load_fault(load_fault), .start_ready(start_ready), .addr_valid(addr_valid), .addr_mode(addr_mode), .addr_value(addr_value), .addr_stride(addr_stride), .addr_rsp_ready(addr_rsp_ready), .exec_valid(exec_valid), .exec_words(exec_words), .exec_job(exec_job), .exec_tag(exec_tag), .exec_fmt(exec_fmt), .exec_last(exec_last), .exec_cancel(exec_cancel), .exec_rsp_ready(exec_rsp_ready), .done_valid(done_valid), .done_fault(done_fault), .pc(pc), .retired(retired));
assign state_depth = dut.sequencer.depth;
assign state_fetch_valid = dut.fetch_valid;
assign state_mem_valid = dut.mem_valid;
assign state_remaining[0 +: 16] = state_depth > 0 ? dut.sequencer.remaining[0] : 16'b0;
assign state_remaining[16 +: 16] = state_depth > 1 ? dut.sequencer.remaining[1] : 16'b0;
assign state_remaining[32 +: 16] = state_depth > 2 ? dut.sequencer.remaining[2] : 16'b0;
assign state_remaining[48 +: 16] = state_depth > 3 ? dut.sequencer.remaining[3] : 16'b0;
assign exec_ready = fab_ready && issue_allow;
assign exec_rsp_valid = fab_valid && response_allow;
assign exec_rsp_fault = fab_fault;
assign result_valid = fab_valid;
assign result_fault = fab_fault;
cgra_fabric fabric (
    .clk(clk),
    .rst(rst),
    .cancel(exec_cancel),
    .req_valid(exec_valid && issue_allow),
    .req_ready(fab_ready),
    .req_mode(2'b0),
    .req_trans(1'b0),
    .req_rows(8'b0),
    .req_cols(11'b0),
    .req_out(11'b0),
    .req_red(11'b0),
    .req_step(3'b0),
    .req_scale(18'b0),
    .req_signs(256'b0),
    .req_masks(256'b0),
    .req_sign_valid(8'b0),
    .req_dense(576'b0),
    .req_dense_valid(32'b0),
    .req_vec(108'b0),
    .req_vec_valid(4'b0),
    .req_src_fault(1'b0),
    .req_job(exec_job),
    .req_tag(exec_tag),
    .req_fmt(exec_fmt),
    .req_last(exec_last),
    .req_words(exec_words),
    .req_rev(8'd1),
    .req_alu_mode(1'b0),
    .req_operands(1'b0),
    .req_enable(backend_mask),
    .link_ready(link_ready),
    .rsp_valid(fab_valid),
    .rsp_ready(exec_rsp_ready && response_allow),
    .rsp_data(result_data),
    .rsp_acc(unused_acc),
    .rsp_faults(unused_faults),
    .rsp_store(result_store),
    .rsp_exec(unused_exec),
    .rsp_halt(unused_halt),
    .rsp_fault(fab_fault),
    .rsp_feed_fault(unused_feed_fault),
    .rsp_job(exec_rsp_job),
    .rsp_tag(exec_rsp_tag),
    .rsp_fmt(exec_rsp_fmt),
    .rsp_last(unused_last)
);
assign state_acc[0 +: 64] = fabric.array_pair[0].array_core.pe[0].ctx.tile.acc_view;
assign state_rf[0 +: 216] = fabric.array_pair[0].array_core.pe[0].ctx.tile.rf_flat;
assign state_valid[0 +: 8] = fabric.array_pair[0].array_core.pe[0].ctx.tile.rf_valid;
assign state_preds[0 +: 3] = fabric.array_pair[0].array_core.pe[0].ctx.tile.preds;
assign state_acc[64 +: 64] = fabric.array_pair[0].array_core.pe[1].ctx.tile.acc_view;
assign state_rf[216 +: 216] = fabric.array_pair[0].array_core.pe[1].ctx.tile.rf_flat;
assign state_valid[8 +: 8] = fabric.array_pair[0].array_core.pe[1].ctx.tile.rf_valid;
assign state_preds[3 +: 3] = fabric.array_pair[0].array_core.pe[1].ctx.tile.preds;
assign state_acc[128 +: 64] = fabric.array_pair[0].array_core.pe[2].ctx.tile.acc_view;
assign state_rf[432 +: 216] = fabric.array_pair[0].array_core.pe[2].ctx.tile.rf_flat;
assign state_valid[16 +: 8] = fabric.array_pair[0].array_core.pe[2].ctx.tile.rf_valid;
assign state_preds[6 +: 3] = fabric.array_pair[0].array_core.pe[2].ctx.tile.preds;
assign state_acc[192 +: 64] = fabric.array_pair[0].array_core.pe[3].ctx.tile.acc_view;
assign state_rf[648 +: 216] = fabric.array_pair[0].array_core.pe[3].ctx.tile.rf_flat;
assign state_valid[24 +: 8] = fabric.array_pair[0].array_core.pe[3].ctx.tile.rf_valid;
assign state_preds[9 +: 3] = fabric.array_pair[0].array_core.pe[3].ctx.tile.preds;
assign state_acc[256 +: 64] = fabric.array_pair[0].array_core.pe[4].ctx.tile.acc_view;
assign state_rf[864 +: 216] = fabric.array_pair[0].array_core.pe[4].ctx.tile.rf_flat;
assign state_valid[32 +: 8] = fabric.array_pair[0].array_core.pe[4].ctx.tile.rf_valid;
assign state_preds[12 +: 3] = fabric.array_pair[0].array_core.pe[4].ctx.tile.preds;
assign state_acc[320 +: 64] = fabric.array_pair[0].array_core.pe[5].ctx.tile.acc_view;
assign state_rf[1080 +: 216] = fabric.array_pair[0].array_core.pe[5].ctx.tile.rf_flat;
assign state_valid[40 +: 8] = fabric.array_pair[0].array_core.pe[5].ctx.tile.rf_valid;
assign state_preds[15 +: 3] = fabric.array_pair[0].array_core.pe[5].ctx.tile.preds;
assign state_acc[384 +: 64] = fabric.array_pair[0].array_core.pe[6].ctx.tile.acc_view;
assign state_rf[1296 +: 216] = fabric.array_pair[0].array_core.pe[6].ctx.tile.rf_flat;
assign state_valid[48 +: 8] = fabric.array_pair[0].array_core.pe[6].ctx.tile.rf_valid;
assign state_preds[18 +: 3] = fabric.array_pair[0].array_core.pe[6].ctx.tile.preds;
assign state_acc[448 +: 64] = fabric.array_pair[0].array_core.pe[7].ctx.tile.acc_view;
assign state_rf[1512 +: 216] = fabric.array_pair[0].array_core.pe[7].ctx.tile.rf_flat;
assign state_valid[56 +: 8] = fabric.array_pair[0].array_core.pe[7].ctx.tile.rf_valid;
assign state_preds[21 +: 3] = fabric.array_pair[0].array_core.pe[7].ctx.tile.preds;
assign state_acc[512 +: 64] = fabric.array_pair[0].array_core.pe[8].ctx.tile.acc_view;
assign state_rf[1728 +: 216] = fabric.array_pair[0].array_core.pe[8].ctx.tile.rf_flat;
assign state_valid[64 +: 8] = fabric.array_pair[0].array_core.pe[8].ctx.tile.rf_valid;
assign state_preds[24 +: 3] = fabric.array_pair[0].array_core.pe[8].ctx.tile.preds;
assign state_acc[576 +: 64] = fabric.array_pair[0].array_core.pe[9].ctx.tile.acc_view;
assign state_rf[1944 +: 216] = fabric.array_pair[0].array_core.pe[9].ctx.tile.rf_flat;
assign state_valid[72 +: 8] = fabric.array_pair[0].array_core.pe[9].ctx.tile.rf_valid;
assign state_preds[27 +: 3] = fabric.array_pair[0].array_core.pe[9].ctx.tile.preds;
assign state_acc[640 +: 64] = fabric.array_pair[0].array_core.pe[10].ctx.tile.acc_view;
assign state_rf[2160 +: 216] = fabric.array_pair[0].array_core.pe[10].ctx.tile.rf_flat;
assign state_valid[80 +: 8] = fabric.array_pair[0].array_core.pe[10].ctx.tile.rf_valid;
assign state_preds[30 +: 3] = fabric.array_pair[0].array_core.pe[10].ctx.tile.preds;
assign state_acc[704 +: 64] = fabric.array_pair[0].array_core.pe[11].ctx.tile.acc_view;
assign state_rf[2376 +: 216] = fabric.array_pair[0].array_core.pe[11].ctx.tile.rf_flat;
assign state_valid[88 +: 8] = fabric.array_pair[0].array_core.pe[11].ctx.tile.rf_valid;
assign state_preds[33 +: 3] = fabric.array_pair[0].array_core.pe[11].ctx.tile.preds;
assign state_acc[768 +: 64] = fabric.array_pair[0].array_core.pe[12].ctx.tile.acc_view;
assign state_rf[2592 +: 216] = fabric.array_pair[0].array_core.pe[12].ctx.tile.rf_flat;
assign state_valid[96 +: 8] = fabric.array_pair[0].array_core.pe[12].ctx.tile.rf_valid;
assign state_preds[36 +: 3] = fabric.array_pair[0].array_core.pe[12].ctx.tile.preds;
assign state_acc[832 +: 64] = fabric.array_pair[0].array_core.pe[13].ctx.tile.acc_view;
assign state_rf[2808 +: 216] = fabric.array_pair[0].array_core.pe[13].ctx.tile.rf_flat;
assign state_valid[104 +: 8] = fabric.array_pair[0].array_core.pe[13].ctx.tile.rf_valid;
assign state_preds[39 +: 3] = fabric.array_pair[0].array_core.pe[13].ctx.tile.preds;
assign state_acc[896 +: 64] = fabric.array_pair[0].array_core.pe[14].ctx.tile.acc_view;
assign state_rf[3024 +: 216] = fabric.array_pair[0].array_core.pe[14].ctx.tile.rf_flat;
assign state_valid[112 +: 8] = fabric.array_pair[0].array_core.pe[14].ctx.tile.rf_valid;
assign state_preds[42 +: 3] = fabric.array_pair[0].array_core.pe[14].ctx.tile.preds;
assign state_acc[960 +: 64] = fabric.array_pair[0].array_core.pe[15].ctx.tile.acc_view;
assign state_rf[3240 +: 216] = fabric.array_pair[0].array_core.pe[15].ctx.tile.rf_flat;
assign state_valid[120 +: 8] = fabric.array_pair[0].array_core.pe[15].ctx.tile.rf_valid;
assign state_preds[45 +: 3] = fabric.array_pair[0].array_core.pe[15].ctx.tile.preds;
assign state_acc[1024 +: 64] = fabric.array_pair[1].array_core.pe[0].ctx.tile.acc_view;
assign state_rf[3456 +: 216] = fabric.array_pair[1].array_core.pe[0].ctx.tile.rf_flat;
assign state_valid[128 +: 8] = fabric.array_pair[1].array_core.pe[0].ctx.tile.rf_valid;
assign state_preds[48 +: 3] = fabric.array_pair[1].array_core.pe[0].ctx.tile.preds;
assign state_acc[1088 +: 64] = fabric.array_pair[1].array_core.pe[1].ctx.tile.acc_view;
assign state_rf[3672 +: 216] = fabric.array_pair[1].array_core.pe[1].ctx.tile.rf_flat;
assign state_valid[136 +: 8] = fabric.array_pair[1].array_core.pe[1].ctx.tile.rf_valid;
assign state_preds[51 +: 3] = fabric.array_pair[1].array_core.pe[1].ctx.tile.preds;
assign state_acc[1152 +: 64] = fabric.array_pair[1].array_core.pe[2].ctx.tile.acc_view;
assign state_rf[3888 +: 216] = fabric.array_pair[1].array_core.pe[2].ctx.tile.rf_flat;
assign state_valid[144 +: 8] = fabric.array_pair[1].array_core.pe[2].ctx.tile.rf_valid;
assign state_preds[54 +: 3] = fabric.array_pair[1].array_core.pe[2].ctx.tile.preds;
assign state_acc[1216 +: 64] = fabric.array_pair[1].array_core.pe[3].ctx.tile.acc_view;
assign state_rf[4104 +: 216] = fabric.array_pair[1].array_core.pe[3].ctx.tile.rf_flat;
assign state_valid[152 +: 8] = fabric.array_pair[1].array_core.pe[3].ctx.tile.rf_valid;
assign state_preds[57 +: 3] = fabric.array_pair[1].array_core.pe[3].ctx.tile.preds;
assign state_acc[1280 +: 64] = fabric.array_pair[1].array_core.pe[4].ctx.tile.acc_view;
assign state_rf[4320 +: 216] = fabric.array_pair[1].array_core.pe[4].ctx.tile.rf_flat;
assign state_valid[160 +: 8] = fabric.array_pair[1].array_core.pe[4].ctx.tile.rf_valid;
assign state_preds[60 +: 3] = fabric.array_pair[1].array_core.pe[4].ctx.tile.preds;
assign state_acc[1344 +: 64] = fabric.array_pair[1].array_core.pe[5].ctx.tile.acc_view;
assign state_rf[4536 +: 216] = fabric.array_pair[1].array_core.pe[5].ctx.tile.rf_flat;
assign state_valid[168 +: 8] = fabric.array_pair[1].array_core.pe[5].ctx.tile.rf_valid;
assign state_preds[63 +: 3] = fabric.array_pair[1].array_core.pe[5].ctx.tile.preds;
assign state_acc[1408 +: 64] = fabric.array_pair[1].array_core.pe[6].ctx.tile.acc_view;
assign state_rf[4752 +: 216] = fabric.array_pair[1].array_core.pe[6].ctx.tile.rf_flat;
assign state_valid[176 +: 8] = fabric.array_pair[1].array_core.pe[6].ctx.tile.rf_valid;
assign state_preds[66 +: 3] = fabric.array_pair[1].array_core.pe[6].ctx.tile.preds;
assign state_acc[1472 +: 64] = fabric.array_pair[1].array_core.pe[7].ctx.tile.acc_view;
assign state_rf[4968 +: 216] = fabric.array_pair[1].array_core.pe[7].ctx.tile.rf_flat;
assign state_valid[184 +: 8] = fabric.array_pair[1].array_core.pe[7].ctx.tile.rf_valid;
assign state_preds[69 +: 3] = fabric.array_pair[1].array_core.pe[7].ctx.tile.preds;
assign state_acc[1536 +: 64] = fabric.array_pair[1].array_core.pe[8].ctx.tile.acc_view;
assign state_rf[5184 +: 216] = fabric.array_pair[1].array_core.pe[8].ctx.tile.rf_flat;
assign state_valid[192 +: 8] = fabric.array_pair[1].array_core.pe[8].ctx.tile.rf_valid;
assign state_preds[72 +: 3] = fabric.array_pair[1].array_core.pe[8].ctx.tile.preds;
assign state_acc[1600 +: 64] = fabric.array_pair[1].array_core.pe[9].ctx.tile.acc_view;
assign state_rf[5400 +: 216] = fabric.array_pair[1].array_core.pe[9].ctx.tile.rf_flat;
assign state_valid[200 +: 8] = fabric.array_pair[1].array_core.pe[9].ctx.tile.rf_valid;
assign state_preds[75 +: 3] = fabric.array_pair[1].array_core.pe[9].ctx.tile.preds;
assign state_acc[1664 +: 64] = fabric.array_pair[1].array_core.pe[10].ctx.tile.acc_view;
assign state_rf[5616 +: 216] = fabric.array_pair[1].array_core.pe[10].ctx.tile.rf_flat;
assign state_valid[208 +: 8] = fabric.array_pair[1].array_core.pe[10].ctx.tile.rf_valid;
assign state_preds[78 +: 3] = fabric.array_pair[1].array_core.pe[10].ctx.tile.preds;
assign state_acc[1728 +: 64] = fabric.array_pair[1].array_core.pe[11].ctx.tile.acc_view;
assign state_rf[5832 +: 216] = fabric.array_pair[1].array_core.pe[11].ctx.tile.rf_flat;
assign state_valid[216 +: 8] = fabric.array_pair[1].array_core.pe[11].ctx.tile.rf_valid;
assign state_preds[81 +: 3] = fabric.array_pair[1].array_core.pe[11].ctx.tile.preds;
assign state_acc[1792 +: 64] = fabric.array_pair[1].array_core.pe[12].ctx.tile.acc_view;
assign state_rf[6048 +: 216] = fabric.array_pair[1].array_core.pe[12].ctx.tile.rf_flat;
assign state_valid[224 +: 8] = fabric.array_pair[1].array_core.pe[12].ctx.tile.rf_valid;
assign state_preds[84 +: 3] = fabric.array_pair[1].array_core.pe[12].ctx.tile.preds;
assign state_acc[1856 +: 64] = fabric.array_pair[1].array_core.pe[13].ctx.tile.acc_view;
assign state_rf[6264 +: 216] = fabric.array_pair[1].array_core.pe[13].ctx.tile.rf_flat;
assign state_valid[232 +: 8] = fabric.array_pair[1].array_core.pe[13].ctx.tile.rf_valid;
assign state_preds[87 +: 3] = fabric.array_pair[1].array_core.pe[13].ctx.tile.preds;
assign state_acc[1920 +: 64] = fabric.array_pair[1].array_core.pe[14].ctx.tile.acc_view;
assign state_rf[6480 +: 216] = fabric.array_pair[1].array_core.pe[14].ctx.tile.rf_flat;
assign state_valid[240 +: 8] = fabric.array_pair[1].array_core.pe[14].ctx.tile.rf_valid;
assign state_preds[90 +: 3] = fabric.array_pair[1].array_core.pe[14].ctx.tile.preds;
assign state_acc[1984 +: 64] = fabric.array_pair[1].array_core.pe[15].ctx.tile.acc_view;
assign state_rf[6696 +: 216] = fabric.array_pair[1].array_core.pe[15].ctx.tile.rf_flat;
assign state_valid[248 +: 8] = fabric.array_pair[1].array_core.pe[15].ctx.tile.rf_valid;
assign state_preds[93 +: 3] = fabric.array_pair[1].array_core.pe[15].ctx.tile.preds;
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
$fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, begin_ready, wr_ready, image_ready, loading, load_fault, start_ready, addr_valid, addr_mode, addr_value, addr_stride, addr_rsp_ready, exec_valid, exec_words, exec_job, exec_tag, exec_fmt, exec_last, exec_cancel, exec_rsp_ready, done_valid, done_fault, pc, retired, state_depth, state_remaining, state_fetch_valid, state_mem_valid, state_acc, state_rf, state_valid, state_preds, result_valid, result_data, result_fault, result_store);
clk = 1; #1;
$fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", cycle, begin_ready, wr_ready, image_ready, loading, load_fault, start_ready, addr_valid, addr_mode, addr_value, addr_stride, addr_rsp_ready, exec_valid, exec_words, exec_job, exec_tag, exec_fmt, exec_last, exec_cancel, exec_rsp_ready, done_valid, done_fault, pc, retired, state_depth, state_remaining, state_fetch_valid, state_mem_valid, state_acc, state_rf, state_valid, state_preds, result_valid, result_data, result_fault, result_store);
#4; clk = 0; cycle = cycle + 1;
end else if (!$feof(src)) $fatal(1, "bad vector row");
end
$fclose(src); $fclose(dst);
$display("PASS cycles=%0d", cycle); $finish;
end
initial begin #100000000; $fatal(1, "timeout"); end
endmodule
