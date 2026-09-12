`timescale 1ns/1ps
module tb_pe_context #(parameter integer TILE_ID = 5);
    reg clk = 0;
    reg [542:0] stim;
    wire [0:0] rst;
    wire [0:0] cancel;
    wire [0:0] req_valid;
    wire [63:0] req_word;
    wire [7:0] req_rev;
    wire [0:0] req_mode;
    wire [26:0] req_mat;
    wire [26:0] req_vec;
    wire [107:0] req_links;
    wire [255:0] req_wlinks;
    wire [0:0] req_mat_valid;
    wire [0:0] req_vec_valid;
    wire [3:0] req_link_valid;
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
    wire [0:0] rsp_store;
    wire [0:0] rsp_halt;
    wire [63:0] state_acc;
    wire [0:0] state_mode;
    wire [215:0] state_rf;
    wire [7:0] state_valid;
    wire [2:0] state_preds;
    wire [3:0] state_decode_fault;
    wire [11:0] state_routes;

    assign {
        rst,
        cancel,
        req_valid,
        req_word,
        req_rev,
        req_mode,
        req_mat,
        req_vec,
        req_links,
        req_wlinks,
        req_mat_valid,
        req_vec_valid,
        req_link_valid,
        req_lane,
        req_job,
        req_tag,
        req_fmt,
        req_last,
        rsp_ready
    } = stim;
    assign state_acc = dut.tile.acc_view;
    assign state_mode = dut.tile.mode_view;
    assign state_rf = dut.tile.rf_flat;
    assign state_valid = dut.tile.rf_valid;
    assign state_preds = dut.tile.preds;
    assign state_decode_fault = dut.dec_fault;
    assign state_routes = dut.routes;

    pe_context #(.TILE_ID(TILE_ID)) dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .req_valid(req_valid),
        .req_word(req_word),
        .req_rev(req_rev),
        .req_mode(req_mode),
        .req_mat(req_mat),
        .req_vec(req_vec),
        .req_links(req_links),
        .req_wlinks(req_wlinks),
        .req_mat_valid(req_mat_valid),
        .req_vec_valid(req_vec_valid),
        .req_link_valid(req_link_valid),
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
        .rsp_exec(rsp_exec),
        .rsp_store(rsp_store),
        .rsp_halt(rsp_halt)
    );
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
                $fdisplay(dst, "%0d 0 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, rsp_store, rsp_halt, state_acc, state_mode, state_rf, state_valid, state_preds, state_decode_fault, state_routes);
                clk = 1; #1;
                $fdisplay(dst, "%0d 1 %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    cycle, req_ready, rsp_valid, rsp_data, rsp_acc, rsp_cmp, rsp_fault, rsp_job, rsp_tag, rsp_fmt, rsp_last, rsp_lane, rsp_exec, rsp_store, rsp_halt, state_acc, state_mode, state_rf, state_valid, state_preds, state_decode_fault, state_routes);
                #4; clk = 0; cycle = cycle + 1;
            end else if (!$feof(src)) $fatal(1, "bad vector row");
        end
        $fclose(src); $fclose(dst);
        $display("PASS cycles=%0d", cycle); $finish;
    end
    initial begin #10000000; $fatal(1, "timeout"); end
endmodule
