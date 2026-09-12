`timescale 1ns/1ps
module tb_pe_tile #(parameter integer TILE_ID = 0);
    reg clk = 0;
    reg [330:0] stim;
    wire [0:0] rst;
    wire [0:0] cancel;
    wire [0:0] req_valid;
    wire [4:0] req_op;
    wire [0:0] req_mode;
    wire [3:0] req_a_kind;
    wire [3:0] req_b_kind;
    wire [2:0] req_a_idx;
    wire [2:0] req_b_idx;
    wire [15:0] req_imm;
    wire [26:0] req_mat;
    wire [26:0] req_vec;
    wire [107:0] req_links;
    wire [0:0] req_mat_valid;
    wire [0:0] req_vec_valid;
    wire [3:0] req_link_valid;
    wire [63:0] req_wide;
    wire [0:0] req_wide_valid;
    wire [2:0] req_guard;
    wire [2:0] req_sel;
    wire [0:0] req_rf_we;
    wire [2:0] req_dst;
    wire [0:0] req_pred_we;
    wire [1:0] req_pred_dst;
    wire [2:0] req_pred_src;
    wire [0:0] req_lane;
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
    wire [215:0] state_rf;
    wire [7:0] state_valid;
    wire [2:0] state_preds;

    assign {
        rst,
        cancel,
        req_valid,
        req_op,
        req_mode,
        req_a_kind,
        req_b_kind,
        req_a_idx,
        req_b_idx,
        req_imm,
        req_mat,
        req_vec,
        req_links,
        req_mat_valid,
        req_vec_valid,
        req_link_valid,
        req_wide,
        req_wide_valid,
        req_guard,
        req_sel,
        req_rf_we,
        req_dst,
        req_pred_we,
        req_pred_dst,
        req_pred_src,
        req_lane,
        req_job,
        req_tag,
        req_fmt,
        req_last,
        rsp_ready
    } = stim;
    assign state_acc = dut.acc_view;
    assign state_mode = dut.mode_view;
    assign state_rf = dut.rf_flat;
    assign state_valid = dut.rf_valid;
    assign state_preds = dut.preds;

    pe_tile #(.TILE_ID(TILE_ID)) dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .req_valid(req_valid),
        .req_op(req_op),
        .req_mode(req_mode),
        .req_a_kind(req_a_kind),
        .req_b_kind(req_b_kind),
        .req_a_idx(req_a_idx),
        .req_b_idx(req_b_idx),
        .req_imm(req_imm),
        .req_mat(req_mat),
        .req_vec(req_vec),
        .req_links(req_links),
        .req_mat_valid(req_mat_valid),
        .req_vec_valid(req_vec_valid),
        .req_link_valid(req_link_valid),
        .req_wide(req_wide),
        .req_wide_valid(req_wide_valid),
        .req_guard(req_guard),
        .req_sel(req_sel),
        .req_rf_we(req_rf_we),
        .req_dst(req_dst),
        .req_pred_we(req_pred_we),
        .req_pred_dst(req_pred_dst),
        .req_pred_src(req_pred_src),
        .req_lane(req_lane),
        .req_job(req_job),
        .req_tag(req_tag),
        .req_fmt(req_fmt),
        .req_last(req_last),
        .rsp_ready(rsp_ready), .rsp_drop(1'b0),
        .req_ready(req_ready),
        .rsp_valid(rsp_valid),
        .rsp_data(rsp_data),
        .rsp_acc(rsp_acc),
        .rsp_cmp(rsp_cmp),
        .rsp_fault(rsp_fault),
        .rsp_job(rsp_job),
        .rsp_tag(rsp_tag),
        .rsp_fmt(rsp_fmt),
        .rsp_last(rsp_last),
        .rsp_lane(rsp_lane),
        .rsp_exec(rsp_exec)
    );

    integer src, dst, count, cycle;
    reg [4095:0] src_path, dst_path;
    initial begin
        if (!$value$plusargs("src=%s", src_path)) $fatal(1, "missing vectors");
        if (!$value$plusargs("dst=%s", dst_path)) $fatal(1, "missing trace");
        src = $fopen(src_path, "r");
        dst = $fopen(dst_path, "w");
        if (!src || !dst) $fatal(1, "cannot open files");
        cycle = 0;
        while (!$feof(src)) begin
            count = $fscanf(src, "%h", stim);
            if (count == 1) begin
                #4;
                $fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, state_acc, state_mode, state_rf, state_valid, state_preds);
                clk = 1; #1;
                $fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, state_acc, state_mode, state_rf, state_valid, state_preds);
                #4; clk = 0; cycle = cycle + 1;
            end else if (!$feof(src)) $fatal(1, "bad vector row");
        end
        $fclose(src); $fclose(dst);
        $display("PASS cycles=%0d", cycle); $finish;
    end
    initial begin #10000000; $fatal(1, "timeout"); end
endmodule
