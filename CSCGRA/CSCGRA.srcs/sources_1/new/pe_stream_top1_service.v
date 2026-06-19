module pe_stream_top1_service #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer IDX_W = 10,
    parameter integer MAX_SUPPORT = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire                         stream_valid,
    input  wire                         stream_done,
    input  wire [IDX_W-1:0]             stream_base_idx,
    input  wire [COLS-1:0]              stream_lane_valid,
    input  wire [COLS*DATA_W-1:0]       stream_data,
    input  wire                         exclude_support,
    input  wire [5:0]                   support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,
    output reg                          candidate_valid,
    output reg  [IDX_W-1:0]             candidate_idx,
    output reg  [DATA_W-1:0]            candidate_value,
    output reg                          busy,
    output reg                          done
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

    function better_candidate;
        input lhs_valid;
        input [DATA_W-1:0] lhs_abs;
        input [IDX_W-1:0] lhs_idx;
        input rhs_valid;
        input [DATA_W-1:0] rhs_abs;
        input [IDX_W-1:0] rhs_idx;
        begin
            if (!lhs_valid) better_candidate = 1'b0;
            else if (!rhs_valid) better_candidate = 1'b1;
            else if (lhs_abs > rhs_abs) better_candidate = 1'b1;
            else if (lhs_abs < rhs_abs) better_candidate = 1'b0;
            else better_candidate = (lhs_idx < rhs_idx);
        end
    endfunction

    reg stage0_valid [0:COLS-1];
    reg [DATA_W-1:0] stage0_abs [0:COLS-1];
    reg [DATA_W-1:0] stage0_value [0:COLS-1];
    reg [IDX_W-1:0] stage0_idx [0:COLS-1];
    reg stage1_valid [0:3];
    reg [DATA_W-1:0] stage1_abs [0:3];
    reg [DATA_W-1:0] stage1_value [0:3];
    reg [IDX_W-1:0] stage1_idx [0:3];
    reg stage2_valid [0:1];
    reg [DATA_W-1:0] stage2_abs [0:1];
    reg [DATA_W-1:0] stage2_value [0:1];
    reg [IDX_W-1:0] stage2_idx [0:1];
    reg stage3_valid;
    reg [DATA_W-1:0] stage3_abs;
    reg [DATA_W-1:0] stage3_value;
    reg [IDX_W-1:0] stage3_idx;
    reg best_valid_q;
    reg [DATA_W-1:0] best_abs_q;
    reg [DATA_W-1:0] best_value_q;
    reg [IDX_W-1:0] best_idx_q;
    reg done_pipe_q;
    reg done_pipe2_q;
    reg done_pipe3_q;
    integer lane;
    integer pair;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            candidate_valid <= 1'b0;
            candidate_idx <= {IDX_W{1'b0}};
            candidate_value <= {DATA_W{1'b0}};
            best_valid_q <= 1'b0;
            best_abs_q <= {DATA_W{1'b0}};
            best_value_q <= {DATA_W{1'b0}};
            best_idx_q <= {IDX_W{1'b0}};
            stage3_valid <= 1'b0;
            done_pipe_q <= 1'b0;
            done_pipe2_q <= 1'b0;
            done_pipe3_q <= 1'b0;
            for (lane = 0; lane < COLS; lane = lane + 1) begin
                stage0_valid[lane] <= 1'b0;
                stage0_abs[lane] <= {DATA_W{1'b0}};
                stage0_value[lane] <= {DATA_W{1'b0}};
                stage0_idx[lane] <= {IDX_W{1'b0}};
            end
            for (pair = 0; pair < 4; pair = pair + 1) begin
                stage1_valid[pair] <= 1'b0;
                stage1_abs[pair] <= {DATA_W{1'b0}};
                stage1_value[pair] <= {DATA_W{1'b0}};
                stage1_idx[pair] <= {IDX_W{1'b0}};
            end
            for (pair = 0; pair < 2; pair = pair + 1) begin
                stage2_valid[pair] <= 1'b0;
                stage2_abs[pair] <= {DATA_W{1'b0}};
                stage2_value[pair] <= {DATA_W{1'b0}};
                stage2_idx[pair] <= {IDX_W{1'b0}};
            end
        end else begin
            done <= 1'b0;
            if (start) begin
                busy <= 1'b1;
                candidate_valid <= 1'b0;
                best_valid_q <= 1'b0;
                done_pipe_q <= 1'b0;
                done_pipe2_q <= 1'b0;
                done_pipe3_q <= 1'b0;
            end

            for (lane = 0; lane < COLS; lane = lane + 1) begin
                stage0_idx[lane] <= stream_base_idx + lane;
                stage0_value[lane] <= stream_data[lane*DATA_W +: DATA_W];
                stage0_abs[lane] <= abs_data(stream_data[lane*DATA_W +: DATA_W]);
                stage0_valid[lane] <= busy && stream_valid && stream_lane_valid[lane] &&
                                      (!exclude_support || !support_has_idx(stream_base_idx + lane));
            end

            for (pair = 0; pair < 4; pair = pair + 1) begin
                if (better_candidate(stage0_valid[pair*2], stage0_abs[pair*2], stage0_idx[pair*2],
                                     stage0_valid[pair*2+1], stage0_abs[pair*2+1], stage0_idx[pair*2+1])) begin
                    stage1_valid[pair] <= stage0_valid[pair*2];
                    stage1_abs[pair] <= stage0_abs[pair*2];
                    stage1_value[pair] <= stage0_value[pair*2];
                    stage1_idx[pair] <= stage0_idx[pair*2];
                end else begin
                    stage1_valid[pair] <= stage0_valid[pair*2+1];
                    stage1_abs[pair] <= stage0_abs[pair*2+1];
                    stage1_value[pair] <= stage0_value[pair*2+1];
                    stage1_idx[pair] <= stage0_idx[pair*2+1];
                end
            end

            for (pair = 0; pair < 2; pair = pair + 1) begin
                if (better_candidate(stage1_valid[pair*2], stage1_abs[pair*2], stage1_idx[pair*2],
                                     stage1_valid[pair*2+1], stage1_abs[pair*2+1], stage1_idx[pair*2+1])) begin
                    stage2_valid[pair] <= stage1_valid[pair*2];
                    stage2_abs[pair] <= stage1_abs[pair*2];
                    stage2_value[pair] <= stage1_value[pair*2];
                    stage2_idx[pair] <= stage1_idx[pair*2];
                end else begin
                    stage2_valid[pair] <= stage1_valid[pair*2+1];
                    stage2_abs[pair] <= stage1_abs[pair*2+1];
                    stage2_value[pair] <= stage1_value[pair*2+1];
                    stage2_idx[pair] <= stage1_idx[pair*2+1];
                end
            end

            if (better_candidate(stage2_valid[0], stage2_abs[0], stage2_idx[0],
                                 stage2_valid[1], stage2_abs[1], stage2_idx[1])) begin
                stage3_valid <= stage2_valid[0];
                stage3_abs <= stage2_abs[0];
                stage3_value <= stage2_value[0];
                stage3_idx <= stage2_idx[0];
            end else begin
                stage3_valid <= stage2_valid[1];
                stage3_abs <= stage2_abs[1];
                stage3_value <= stage2_value[1];
                stage3_idx <= stage2_idx[1];
            end

            if (better_candidate(stage3_valid, stage3_abs, stage3_idx,
                                 best_valid_q, best_abs_q, best_idx_q)) begin
                best_valid_q <= stage3_valid;
                best_abs_q <= stage3_abs;
                best_value_q <= stage3_value;
                best_idx_q <= stage3_idx;
            end

            done_pipe_q <= busy && stream_done;
            done_pipe2_q <= done_pipe_q;
            done_pipe3_q <= done_pipe2_q;
            if (done_pipe3_q) begin
                busy <= 1'b0;
                done <= 1'b1;
                candidate_valid <= best_valid_q;
                candidate_idx <= best_idx_q;
                candidate_value <= best_value_q;
            end
        end
    end
endmodule
