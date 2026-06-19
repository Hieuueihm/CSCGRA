module pe_stream_top1_4x8_service #(
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
    input  wire                         allow_tiny,
    input  wire [5:0]                   support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,
    output reg                          candidate_valid,
    output reg  [IDX_W-1:0]             candidate_idx,
    output reg  [DATA_W-1:0]            candidate_value,
    output reg                          busy,
    output reg                          done
);
    localparam integer LANES = 32;

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
            for (si = 0; si < MAX_SUPPORT; si = si + 1)
                if ((si < support_depth) && (support_bus[si*IDX_W +: IDX_W] == idx))
                    support_has_idx = 1'b1;
        end
    endfunction

    function better;
        input lhs_valid;
        input [DATA_W-1:0] lhs_value;
        input [IDX_W-1:0] lhs_idx;
        input rhs_valid;
        input [DATA_W-1:0] rhs_value;
        input [IDX_W-1:0] rhs_idx;
        reg [DATA_W-1:0] lhs_abs;
        reg [DATA_W-1:0] rhs_abs;
        begin
            lhs_abs = abs_data(lhs_value);
            rhs_abs = abs_data(rhs_value);
            if (!lhs_valid) better = 1'b0;
            else if (!rhs_valid) better = 1'b1;
            else if (lhs_abs > rhs_abs) better = 1'b1;
            else if (lhs_abs < rhs_abs) better = 1'b0;
            else better = (lhs_idx < rhs_idx);
        end
    endfunction

    reg [LANES-1:0] tree_lane_valid;
    reg [LANES*DATA_W-1:0] tree_lane_score;
    reg [LANES*IDX_W-1:0] tree_lane_idx;
    reg [1:0] block_count_q;
    reg tree_in_valid_q;
    wire tree_out_valid;
    wire [DATA_W-1:0] tree_out_score;
    wire [IDX_W-1:0] tree_out_idx;
    reg final_flush_q;
    reg [3:0] pending_trees_q;
    reg best_valid_q;
    reg [DATA_W-1:0] best_value_q;
    reg [IDX_W-1:0] best_idx_q;
    integer lane;
    integer slot;

    pe_array_top1_tree_4x8 #(
        .ROWS(4), .COLS(8), .DATA_W(DATA_W), .IDX_W(IDX_W)
    ) u_tree (
        .clk(clk), .rst_n(rst_n), .in_valid(tree_in_valid_q),
        .lane_valid(tree_lane_valid), .lane_score(tree_lane_score), .lane_idx(tree_lane_idx),
        .out_valid(tree_out_valid), .out_score(tree_out_score), .out_idx(tree_out_idx)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate_valid <= 1'b0;
            candidate_idx <= {IDX_W{1'b0}};
            candidate_value <= {DATA_W{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            tree_lane_valid <= {LANES{1'b0}};
            tree_lane_score <= {(LANES*DATA_W){1'b0}};
            tree_lane_idx <= {(LANES*IDX_W){1'b0}};
            block_count_q <= 2'd0;
            tree_in_valid_q <= 1'b0;
            final_flush_q <= 1'b0;
            pending_trees_q <= 4'd0;
            best_valid_q <= 1'b0;
            best_value_q <= {DATA_W{1'b0}};
            best_idx_q <= {IDX_W{1'b0}};
        end else begin
            done <= 1'b0;
            tree_in_valid_q <= 1'b0;
            if (start) begin
                candidate_valid <= 1'b0;
                busy <= 1'b1;
                tree_lane_valid <= {LANES{1'b0}};
                tree_lane_score <= {(LANES*DATA_W){1'b0}};
                tree_lane_idx <= {(LANES*IDX_W){1'b0}};
                block_count_q <= 2'd0;
                final_flush_q <= 1'b0;
                pending_trees_q <= 4'd0;
                best_valid_q <= 1'b0;
                best_value_q <= {DATA_W{1'b0}};
                best_idx_q <= {IDX_W{1'b0}};
            end else if (busy) begin
                if (stream_valid) begin
                    for (lane = 0; lane < COLS; lane = lane + 1) begin
                        slot = (block_count_q * COLS) + lane;
                        tree_lane_score[slot*DATA_W +: DATA_W] <= stream_data[lane*DATA_W +: DATA_W];
                        tree_lane_idx[slot*IDX_W +: IDX_W] <= stream_base_idx + lane[IDX_W-1:0];
                        tree_lane_valid[slot] <= stream_lane_valid[lane] &&
                                                 (allow_tiny || (abs_data(stream_data[lane*DATA_W +: DATA_W]) > {{(DATA_W-1){1'b0}}, 1'b1})) &&
                                                 (!exclude_support || !support_has_idx(stream_base_idx + lane[IDX_W-1:0]));
                    end
                    if ((block_count_q == 2'd3) || stream_done) begin
                        tree_in_valid_q <= 1'b1;
                        pending_trees_q <= pending_trees_q + 1'b1;
                        block_count_q <= 2'd0;
                        final_flush_q <= stream_done;
                        if (stream_done) begin
                            for (slot = 0; slot < LANES; slot = slot + 1) begin
                                if (slot >= ((block_count_q + 1'b1) * COLS)) begin
                                    tree_lane_valid[slot] <= 1'b0;
                                    tree_lane_score[slot*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
                                    tree_lane_idx[slot*IDX_W +: IDX_W] <= {IDX_W{1'b1}};
                                end
                            end
                        end
                    end else begin
                        block_count_q <= block_count_q + 1'b1;
                    end
                end
                if (tree_out_valid) begin
                    pending_trees_q <= pending_trees_q - 1'b1;
                    if (better(1'b1, tree_out_score, tree_out_idx, best_valid_q, best_value_q, best_idx_q)) begin
                        best_valid_q <= 1'b1;
                        best_value_q <= tree_out_score;
                        best_idx_q <= tree_out_idx;
                    end
                    if (final_flush_q && (pending_trees_q == 4'd1)) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        candidate_valid <= better(1'b1, tree_out_score, tree_out_idx, best_valid_q, best_value_q, best_idx_q) ? 1'b1 : best_valid_q;
                        candidate_value <= better(1'b1, tree_out_score, tree_out_idx, best_valid_q, best_value_q, best_idx_q) ? tree_out_score : best_value_q;
                        candidate_idx <= better(1'b1, tree_out_score, tree_out_idx, best_valid_q, best_value_q, best_idx_q) ? tree_out_idx : best_idx_q;
                    end
                end
            end
        end
    end
endmodule
