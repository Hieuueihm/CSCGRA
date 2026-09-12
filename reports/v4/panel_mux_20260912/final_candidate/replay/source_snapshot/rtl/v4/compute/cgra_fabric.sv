`include "context_defs.vh"

module cgra_fabric (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [1:0] req_mode,
    input wire req_trans,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols, req_out, req_red,
    input wire [2:0] req_step,
    input wire [`CSR_PE_C_W-1:0] req_scale,
    input wire [255:0] req_signs, req_masks,
    input wire [7:0] req_sign_valid,
    input wire [32*`CSR_PE_C_W-1:0] req_dense,
    input wire [31:0] req_dense_valid,
    input wire [4*`CSR_PE_S_W-1:0] req_vec,
    input wire [3:0] req_vec_valid,
    input wire req_src_fault,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    input wire [32*64-1:0] req_words,
    input wire [7:0] req_rev,
    input wire req_alu_mode,
    input wire req_operands,
    input wire [31:0] req_enable,
    input wire [127:0] link_ready,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [32*`CSR_PE_S_W-1:0] rsp_data,
    output wire [32*`CSR_PE_ACC_W-1:0] rsp_acc,
    output wire [127:0] rsp_faults,
    output wire [31:0] rsp_store, rsp_exec, rsp_halt,
    output wire rsp_fault,
    output reg [3:0] rsp_feed_fault,
    output reg [`CSR_PE_JOB_W-1:0] rsp_job,
    output reg [`CSR_PE_TAG_W-1:0] rsp_tag,
    output reg [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output reg rsp_last
);
    localparam integer SW = `CSR_PE_S_W;
    localparam integer AW = `CSR_PE_ACC_W;
    localparam [1:0] IDLE = 0, FEED = 1, EXEC = 2, ERROR = 3;
    reg [1:0] state;
    reg [2047:0] words;
    reg [7:0] rev;
    reg alu_mode, use_feed;
    reg [31:0] enable_q;
    wire active = !rst && !cancel;
    wire feed_ready, feed_valid, feeder_valid;
    wire [32*SW-1:0] feed_mat, feed_vec;
    wire [31:0] feed_mask;
    wire [3:0] feeder_fault;
    wire [15:0] unused_rsp_job_0;
    wire [15:0] unused_rsp_tag_1;
    wire [7:0] unused_rsp_fmt_2;
    wire [0:0] unused_rsp_last_3;
    wire [3:0] feed_fault;
    wire [32*SW-1:0] mat, vec;
    wire [31:0] mask;
    wire [1:0] array_ready, array_valid, array_fault;
    wire [32*SW-1:0] data;
    wire [32*AW-1:0] acc;
    wire [127:0] faults;
    wire [31:0] stores, execs, halts;
    wire feed_retire = state == FEED && (feed_fault != 0 || (&array_ready));
    wire array_issue = active && state == FEED && feed_valid && feed_fault == 0 && (&array_ready);
    wire retire = rsp_valid && rsp_ready;
    assign req_ready = active && state == IDLE && (!req_operands || feed_ready);
    assign feed_valid = use_feed ? feeder_valid : 1'b1;
    assign feed_fault = use_feed ? feeder_fault : 4'b0;
    assign mat = use_feed ? feed_mat : '0;
    assign vec = use_feed ? feed_vec : '0;
    assign mask = enable_q & (use_feed ? feed_mask : 32'hffffffff);
    assign rsp_valid = active && (state == ERROR || (state == EXEC && (&array_valid)));
    assign rsp_fault = rsp_feed_fault != 0 || (state == EXEC && (|array_fault));
    assign rsp_faults = state == EXEC ? faults : 128'b0;
    assign rsp_data = state == EXEC ? data : '0;
    assign rsp_acc = state == EXEC ? acc : '0;
    assign rsp_exec = state == EXEC && !rsp_fault ? execs : '0;
    assign rsp_store = state == EXEC && !rsp_fault ? stores : '0;
    assign rsp_halt = state == EXEC && !rsp_fault ? halts : '0;
    operand_feeder feeder (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid && state == IDLE && req_operands), .req_ready(feed_ready),
        .req_mode(req_mode),
        .req_trans(req_trans),
        .req_rows(req_rows),
        .req_cols(req_cols),
        .req_out(req_out),
        .req_red(req_red),
        .req_step(req_step),
        .req_scale(req_scale),
        .req_signs(req_signs),
        .req_masks(req_masks),
        .req_sign_valid(req_sign_valid),
        .req_dense(req_dense),
        .req_dense_valid(req_dense_valid),
        .req_vec(req_vec),
        .req_vec_valid(req_vec_valid),
        .req_src_fault(req_src_fault),
        .req_job(req_job),
        .req_tag(req_tag),
        .req_fmt(req_fmt),
        .req_last(req_last),
        .rsp_valid(feeder_valid), .rsp_ready(feed_retire), .rsp_mat(feed_mat), .rsp_vec(feed_vec), .rsp_mask(feed_mask),
        .rsp_fault(feeder_fault), .rsp_job(unused_rsp_job_0), .rsp_tag(unused_rsp_tag_1), .rsp_fmt(unused_rsp_fmt_2), .rsp_last(unused_rsp_last_3)
    );
    genvar cluster;
    generate
        for (cluster = 0; cluster < 2; cluster = cluster + 1) begin : array_pair
            pe_array #(.ARRAY_ID(cluster)) array_core (
                .clk(clk), .rst(rst), .cancel(cancel), .req_valid(array_issue), .req_ready(array_ready[cluster]),
                .req_words(words[cluster*1024 +: 1024]), .req_rev(rev), .req_mode(alu_mode),
                .req_mat(mat[cluster*16*SW +: 16*SW]), .req_vec(vec[cluster*16*SW +: 16*SW]),
                .req_mask(mask[cluster*16 +: 16]), .req_operand_valid(use_feed ? mask[cluster*16 +: 16] : 16'b0), .req_job(rsp_job), .req_tag(rsp_tag), .req_fmt(rsp_fmt), .req_last(rsp_last),
                .link_ready(link_ready[cluster*64 +: 64]), .rsp_valid(array_valid[cluster]),
                .rsp_ready(retire), .rsp_drop(|array_fault), .rsp_data(data[cluster*16*SW +: 16*SW]),
                .rsp_acc(acc[cluster*16*AW +: 16*AW]), .rsp_faults(faults[cluster*64 +: 64]),
                .rsp_store(stores[cluster*16 +: 16]), .rsp_exec(execs[cluster*16 +: 16]), .rsp_halt(halts[cluster*16 +: 16]), .rsp_fault(array_fault[cluster])
            );
        end
    endgenerate
    always @(posedge clk) begin
        if (rst || cancel) begin
            state <= IDLE; words <= '0; rev <= '0; alu_mode <= 1'b0; use_feed <= 1'b0; enable_q <= '0;
            rsp_feed_fault <= '0; rsp_job <= '0; rsp_tag <= '0; rsp_fmt <= '0; rsp_last <= 1'b0;
        end else begin
            if (req_valid && req_ready) begin
                state <= FEED; words <= req_words; rev <= req_rev; alu_mode <= req_alu_mode;
                use_feed <= req_operands; enable_q <= req_enable;
                rsp_feed_fault <= '0; rsp_job <= req_job; rsp_tag <= req_tag; rsp_fmt <= req_fmt; rsp_last <= req_last;
            end
            if (state == FEED && feed_valid && feed_retire) begin
                rsp_feed_fault <= feed_fault;
                state <= feed_fault != 0 ? ERROR : EXEC;
            end
            if (retire) state <= IDLE;
        end
    end
endmodule
