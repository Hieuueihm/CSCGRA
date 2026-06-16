module score_select_service #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer IDX_W = 10,
    parameter integer CTX_W = 64,
    parameter integer MAX_SEL = 16,
    parameter integer MAX_SUPPORT = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   ctx_valid,
    input  wire [CTX_W-1:0]       ctx_word,
    input  wire [3:0]             uop_class,
    input  wire [COLS-1:0]        lane_valid,
    input  wire [IDX_W-1:0]       base_idx,
    input  wire                   addr_valid,
    input  wire                   addr_done,
    input  wire [COLS*DATA_W-1:0] spm_pa_rdata,
    input  wire [SCALAR_W-1:0]    threshold_value,
    input  wire [5:0]             support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,
    input  wire                   stream_valid,
    input  wire                   stream_done,
    input  wire [IDX_W-1:0]       stream_base_idx,
    input  wire [COLS-1:0]        stream_lane_valid,
    input  wire [COLS*DATA_W-1:0] stream_data,
    input  wire                   append_done,
    output reg                    append_valid,
    output reg  [IDX_W-1:0]       append_idx,
    output reg  [2:0]             append_path,
    output reg                    busy,
    output reg                    done
);
    function [DATA_W-1:0] abs_data;
        input [DATA_W-1:0] value;
        begin
            if (value == {1'b1, {(DATA_W-1){1'b0}}}) abs_data = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1]) abs_data = ~value + 1'b1;
            else abs_data = value;
        end
    endfunction

    function support_has_idx;
        input [IDX_W-1:0] idx;
        integer si;
        begin
            support_has_idx = 1'b0;
            for (si = 0; si < MAX_SUPPORT; si = si + 1) begin
                if ((si < support_depth) && (support_bus[si*IDX_W +: IDX_W] == idx))
                    support_has_idx = 1'b1;
            end
        end
    endfunction

    localparam [1:0] S_IDLE=2'd0, S_SCAN=2'd1, S_APPEND=2'd2, S_DONE=2'd3;
    reg [1:0] state_q;
    reg [DATA_W-1:0] threshold_q;
    reg [IDX_W-1:0] sel_mem [0:MAX_SEL-1];
    reg [DATA_W-1:0] sel_score [0:MAX_SEL-1];
    reg [4:0] sel_count_q;
    reg [4:0] append_pos_q;
    reg [4:0] max_count_q;
    reg append_wait_q;
    reg scan_valid_q;
    reg scan_done_q;
    reg [COLS-1:0] scan_lane_valid_q;
    reg [IDX_W-1:0] scan_base_idx_q;
    reg [COLS*DATA_W-1:0] scan_data_q;
    reg scan2_valid_q;
    reg scan2_done_q;
    reg [COLS-1:0] scan2_lane_valid_q;
    reg [IDX_W-1:0] scan2_base_idx_q;
    reg [COLS*DATA_W-1:0] scan2_data_q;
    reg topk_mode_q;
    reg topk_exclude_support_q;
    reg [DATA_W-1:0] lane_abs_q;
    reg [IDX_W-1:0] topk_idx_eff;
    reg [1:0] topk_drain_q;
    reg [IDX_W-1:0] topk_base_eff;
    reg topk_lane_valid_eff;
    reg topk_dup_eff;
    reg block_best_valid_q;
    reg [DATA_W-1:0] block_best_score_q;
    reg [IDX_W-1:0] block_best_idx_q;
    reg block_best_valid_next;
    reg [DATA_W-1:0] block_best_score_next;
    reg [IDX_W-1:0] block_best_idx_next;
    reg stream_arm_q;
    reg stream_exclude_support_q;
    reg [2:0] stream_path_q;
    reg stream_best_valid_q;
    reg [DATA_W-1:0] stream_best_score_q;
    reg [IDX_W-1:0] stream_best_idx_q;
    reg stream_append_wait_q;
    reg stream_done_seen_q;
    reg [COLS-1:0] lane_keep_q;
    reg [COLS*DATA_W-1:0] lane_score_q;
    reg [COLS*IDX_W-1:0] lane_idx_q;
    integer insert_pos;
    integer shift_pos;
    integer lane;
    integer r;
    integer d;
    integer valid_count;
    integer add_count;
    wire [IDX_W-1:0] lane0_idx_ext = {{(IDX_W-1){1'b0}}, 1'b0};

    wire stream_mode = ctx_word[31];
    wire select_start = ctx_valid && (uop_class == 4'd5) && ((ctx_word[27:24] == 4'd1) || (ctx_word[27:24] == 4'd2) || (ctx_word[27:24] == 4'd3));
    wire [3:0] shift_sel = ctx_word[19:16];
    wire [DATA_W-1:0] threshold_next = threshold_value[DATA_W-1:0] >> shift_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            append_valid <= 1'b0;
            append_idx <= {IDX_W{1'b0}};
            append_path <= 3'd0;
            busy <= 1'b0;
            done <= 1'b0;
            threshold_q <= {DATA_W{1'b0}};
            sel_count_q <= 5'd0;
            append_pos_q <= 5'd0;
            append_wait_q <= 1'b0;
            max_count_q <= 5'd0;
            scan_valid_q <= 1'b0;
            scan_done_q <= 1'b0;
            scan_lane_valid_q <= {COLS{1'b0}};
            scan_base_idx_q <= {IDX_W{1'b0}};
            scan_data_q <= {(COLS*DATA_W){1'b0}};
            scan2_valid_q <= 1'b0; scan2_done_q <= 1'b0; scan2_lane_valid_q <= {COLS{1'b0}}; scan2_base_idx_q <= {IDX_W{1'b0}}; scan2_data_q <= {(COLS*DATA_W){1'b0}};
            topk_mode_q <= 1'b0;
            topk_drain_q <= 2'd0;
            topk_base_eff <= {IDX_W{1'b0}};
            topk_idx_eff <= {IDX_W{1'b0}};
            topk_exclude_support_q <= 1'b1;
            lane_abs_q <= {DATA_W{1'b0}};
            block_best_valid_q <= 1'b0;
            block_best_score_q <= {DATA_W{1'b0}};
            block_best_idx_q <= {IDX_W{1'b0}};
            stream_arm_q <= 1'b0;
            stream_exclude_support_q <= 1'b1;
            stream_path_q <= 3'd0;
            stream_best_valid_q <= 1'b0;
            stream_best_score_q <= {DATA_W{1'b0}};
            stream_best_idx_q <= {IDX_W{1'b0}};
            stream_append_wait_q <= 1'b0;
            stream_done_seen_q <= 1'b0;
            lane_keep_q <= {COLS{1'b0}};
            lane_score_q <= {(COLS*DATA_W){1'b0}};
            lane_idx_q <= {(COLS*IDX_W){1'b0}};
            for (r = 0; r < MAX_SEL; r = r + 1) begin
                sel_mem[r] <= {IDX_W{1'b1}};
                sel_score[r] <= {DATA_W{1'b0}};
            end
        end else begin
            append_valid <= 1'b0;
            done <= 1'b0;
            if (stream_arm_q) begin
                busy <= 1'b1;
                if (stream_append_wait_q) begin
                    if (append_done) begin
                        stream_arm_q <= 1'b0;
                        stream_append_wait_q <= 1'b0;
                        stream_done_seen_q <= 1'b0;
                        done <= 1'b1;
                    end
                end else begin
                    if (stream_valid) begin
                        block_best_valid_next = 1'b0;
                        block_best_score_next = {DATA_W{1'b0}};
                        block_best_idx_next = {IDX_W{1'b0}};
                        for (lane = 0; lane < COLS; lane = lane + 1) begin
                            if (stream_lane_valid[lane]) begin
                                topk_idx_eff = stream_base_idx + lane[IDX_W-1:0];
                                lane_abs_q = abs_data(stream_data[lane*DATA_W +: DATA_W]);
                                if ((lane_abs_q > {{(DATA_W-1){1'b0}},1'b1}) && (!stream_exclude_support_q || !support_has_idx(topk_idx_eff))) begin
                                    if (!block_best_valid_next || (lane_abs_q > block_best_score_next) || ((lane_abs_q == block_best_score_next) && (topk_idx_eff < block_best_idx_next))) begin
                                        block_best_valid_next = 1'b1;
                                        block_best_score_next = lane_abs_q;
                                        block_best_idx_next = topk_idx_eff;
                                    end
                                end
                            end
                        end
                        if (block_best_valid_next && (!stream_best_valid_q || (block_best_score_next > stream_best_score_q) || ((block_best_score_next == stream_best_score_q) && (block_best_idx_next < stream_best_idx_q)))) begin
                            stream_best_valid_q <= 1'b1;
                            stream_best_score_q <= block_best_score_next;
                            stream_best_idx_q <= block_best_idx_next;
                        end
                    end
                    if (stream_done)
                        stream_done_seen_q <= 1'b1;
                    if (stream_done_seen_q || stream_done) begin
                        if (stream_best_valid_q) begin
                            append_valid <= 1'b1;
                            append_idx <= stream_best_idx_q;
                            append_path <= stream_path_q;
                            stream_append_wait_q <= 1'b1;
                        end else begin
                            stream_arm_q <= 1'b0;
                            stream_done_seen_q <= 1'b0;
                            done <= 1'b1;
                        end
                    end
                end
            end
            case (state_q)
                S_IDLE: begin
                    if (!stream_arm_q) busy <= 1'b0;
                    if (select_start && stream_mode) begin
                        busy <= 1'b1;
                        stream_arm_q <= 1'b1;
                        stream_exclude_support_q <= (ctx_word[27:24] == 4'd2);
                        stream_path_q <= ctx_word[22:20];
                        stream_best_valid_q <= 1'b0;
                        stream_best_score_q <= {DATA_W{1'b0}};
                        stream_best_idx_q <= {IDX_W{1'b0}};
                        stream_append_wait_q <= 1'b0;
                        stream_done_seen_q <= 1'b0;
                    end else if (select_start) begin
                        busy <= 1'b1;
                        append_path <= ctx_word[22:20];
                        threshold_q <= threshold_next;
                        sel_count_q <= 5'd0;
                        append_pos_q <= 5'd0;
                        append_wait_q <= 1'b0;
                        max_count_q <= (ctx_word[15:11] == 5'd0) ? MAX_SEL[4:0] : ctx_word[15:11];
                        scan_valid_q <= 1'b0;
                        scan_done_q <= 1'b0;
                        scan_lane_valid_q <= {COLS{1'b0}};
                        scan_base_idx_q <= {IDX_W{1'b0}};
                        topk_mode_q <= (ctx_word[27:24] == 4'd2) || (ctx_word[27:24] == 4'd3);
                        topk_exclude_support_q <= (ctx_word[27:24] == 4'd2);
                        block_best_valid_q <= 1'b0;
                        block_best_score_q <= {DATA_W{1'b0}};
                        block_best_idx_q <= {IDX_W{1'b0}};
                        lane_keep_q <= {COLS{1'b0}};
                        lane_score_q <= {(COLS*DATA_W){1'b0}};
                        lane_idx_q <= {(COLS*IDX_W){1'b0}};
                        for (r = 0; r < MAX_SEL; r = r + 1) begin
                            sel_mem[r] <= {IDX_W{1'b1}};
                            sel_score[r] <= {DATA_W{1'b0}};
                        end
            topk_drain_q <= 2'd0;
                        state_q <= S_SCAN;
                    end
                end
                S_SCAN: begin
                    busy <= 1'b1;
                    if (topk_mode_q) begin
                        if (block_best_valid_q && ((block_best_score_q > sel_score[0]) || ((block_best_score_q == sel_score[0]) && (block_best_idx_q < sel_mem[0])))) begin
                            sel_score[0] <= block_best_score_q;
                            sel_mem[0] <= block_best_idx_q;
                        end
                        block_best_valid_next = 1'b0;
                        block_best_score_next = {DATA_W{1'b0}};
                        block_best_idx_next = {IDX_W{1'b1}};
                        for (lane = 0; lane < COLS; lane = lane + 1) begin
                            lane_abs_q = lane_score_q[lane*DATA_W +: DATA_W];
                            topk_idx_eff = lane_idx_q[lane*IDX_W +: IDX_W];
                            if (lane_keep_q[lane] && ((lane_abs_q > block_best_score_next) || ((lane_abs_q == block_best_score_next) && (topk_idx_eff < block_best_idx_next)))) begin
                                block_best_valid_next = 1'b1;
                                block_best_score_next = lane_abs_q;
                                block_best_idx_next = topk_idx_eff;
                            end
                        end
                        block_best_valid_q <= block_best_valid_next;
                        block_best_score_q <= block_best_score_next;
                        block_best_idx_q <= block_best_idx_next;
                        lane_keep_q <= {COLS{1'b0}};
                        lane_score_q <= {(COLS*DATA_W){1'b0}};
                        lane_idx_q <= {(COLS*IDX_W){1'b0}};
                        if (scan2_valid_q) begin
                            topk_base_eff = (scan2_base_idx_q >= (COLS*2)) ? (scan2_base_idx_q - (COLS*2)) : scan2_base_idx_q;
                            for (lane = 0; lane < COLS; lane = lane + 1) begin
                                topk_lane_valid_eff = scan2_lane_valid_q[lane] || ((scan2_lane_valid_q == {COLS{1'b0}}) && (scan2_base_idx_q >= (COLS*2)));
                                topk_idx_eff = topk_base_eff + lane[IDX_W-1:0];
                                lane_score_q[lane*DATA_W +: DATA_W] <= (abs_data(scan2_data_q[lane*DATA_W +: DATA_W]) <= {{(DATA_W-1){1'b0}},1'b1}) ? {DATA_W{1'b0}} : abs_data(scan2_data_q[lane*DATA_W +: DATA_W]);
                                lane_idx_q[lane*IDX_W +: IDX_W] <= topk_idx_eff;
                                lane_keep_q[lane] <= topk_lane_valid_eff && (!topk_exclude_support_q || !support_has_idx(topk_idx_eff));
                            end
                        end
                        if (addr_done)
                            topk_drain_q <= 2'd3;
                        else if (topk_drain_q != 2'd0)
                            topk_drain_q <= topk_drain_q - 1'b1;
                        if (topk_drain_q == 2'd1) begin
                            sel_count_q <= max_count_q;
                            append_pos_q <= 5'd0;
                            state_q <= S_APPEND;
                        end
                    end else begin
                        if (scan_valid_q) begin
                            add_count = 0;
                            for (lane = 0; lane < COLS; lane = lane + 1) begin
                                if (scan_lane_valid_q[lane] && ((sel_count_q + add_count) < max_count_q) &&
                                    (abs_data(scan_data_q[lane*DATA_W +: DATA_W]) >= threshold_q)) begin
                                    sel_mem[sel_count_q + add_count] <= scan_base_idx_q + lane[IDX_W-1:0];
                                    add_count = add_count + 1;
                                end
                            end
                            sel_count_q <= sel_count_q + add_count[4:0];
                            if (scan_done_q || (scan_valid_q && !addr_valid)) begin
                                append_pos_q <= 5'd0;
                                state_q <= S_APPEND;
                            end
                        end
                    end
                    scan2_valid_q <= scan_valid_q;
                    scan2_done_q <= scan_done_q;
                    scan2_lane_valid_q <= scan_lane_valid_q;
                    scan2_base_idx_q <= scan_base_idx_q;
                    scan2_data_q <= scan_data_q;
                    scan_valid_q <= stream_mode ? stream_valid : addr_valid;
                    scan_done_q <= stream_mode ? stream_done : addr_done;
                    scan_lane_valid_q <= stream_mode ? stream_lane_valid : lane_valid;
                    scan_base_idx_q <= stream_mode ? stream_base_idx : base_idx;
                    scan_data_q <= stream_mode ? stream_data : spm_pa_rdata;
                end

                S_APPEND: begin
                    busy <= 1'b1;
                    if (append_pos_q >= sel_count_q) begin
                        state_q <= S_DONE;
                    end else if (append_wait_q) begin
                        if (append_done) begin
                            append_wait_q <= 1'b0;
                            append_pos_q <= append_pos_q + 1'b1;
                        end
                    end else begin
                        append_valid <= 1'b1;
                        append_idx <= sel_mem[append_pos_q];
                        append_wait_q <= 1'b1;
                    end
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state_q <= S_IDLE;
                end
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule
