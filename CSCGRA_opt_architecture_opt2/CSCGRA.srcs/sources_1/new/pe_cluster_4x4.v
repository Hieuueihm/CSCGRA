// 4-row PE pipeline mapping used by the optimized architecture:
//   row0: MAC stage for Phi*x, Phi^T*r, Gram/RHS products.
//   row1: accumulation stage for row0 partial products.
//   row2: reduction/normalization/update-prep stage using SAT_ADD_SHIFT on real mesh operands.
//   row3: writeback/result stage that drives reduce/SPM/result buses.
// Context mesh mode uses all four rows: prepare, math, mask, final commit.
module pe_cluster_4x4 #(
    parameter integer ROWS = 4,
    parameter integer CLUSTER_COLS = 4,
    parameter integer TOTAL_COLS = 8,
    parameter integer COL_OFFSET = 0,
    parameter integer DATA_W = 24,
    parameter integer ACC_W = 48,
    parameter integer IDX_W = 10,
    parameter integer MAX_K = 16,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer ENABLE_MESH_CTX = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ctx_valid,
    input  wire [3:0] pe_op,
    input  wire [2:0] src_a_sel,
    input  wire [2:0] src_b_sel,
    input  wire [1:0] rf_rd_addr,
    input  wire [1:0] rf_wr_addr,
    input  wire rf_wr_en,
    input  wire acc_clear,
    input  wire acc_en,
    input  wire [3:0] out_sel,
    input  wire [2:0] sb_sel,
    input  wire sb_sel_en,
    input  wire [3:0] row_en,
    input  wire [15:0] imm16,
    input  wire [3:0] ext_ctrl,
    input  wire [1:0] mesh_ctx_mode,
    input  wire [IDX_W-1:0] mesh_ctx_base_idx,
    input  wire [IDX_W-1:0] mesh_ctx_limit,
    input  wire [DATA_W-1:0] mesh_ctx_threshold,
    input  wire [3:0] mesh_ctx_shift,
    input  wire [CLUSTER_COLS*DATA_W-1:0] mesh_ctx_x_bus,
    input  wire [CLUSTER_COLS*DATA_W-1:0] mesh_ctx_delta_bus,
    input  wire [CLUSTER_COLS-1:0] mesh_ctx_keep_bus,
    input  wire [CLUSTER_COLS-1:0] lane_valid,
    input  wire [IDX_W-1:0] base_idx,
    input  wire first_in_phase,
    input  wire [CLUSTER_COLS*DATA_W-1:0] spm_a_rdata,
    input  wire [CLUSTER_COLS*DATA_W-1:0] spm_b_rdata,
    input  wire [CLUSTER_COLS*DATA_W-1:0] phi_bus,
    input  wire [CLUSTER_COLS*DATA_W-1:0] scalar_bus,
    input  wire sparse_active,
    input  wire sparse_step_active,
    input  wire [3:0] sparse_op,
    input  wire [7:0] sparse_k_active,
    input  wire corr_acc_clear,
    input  wire corr_acc_en,
    input  wire [1:0] corr_slot,
    input  wire ls_wide_mul_active,
    input  wire ls_wide_vertical_active,
    input  wire [4:0] ls_wide_vertical_tag,
    input  wire [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_a_bus,
    input  wire [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_b_bus,
    input  wire [3:0] mesh_keepalive,
    // Factor-cache requests have one ingress at PE row0.  Each row compares
    // the cache ranks owned by rank mod 4 and forwards the accumulated mask.
    input  wire factor_pipe_valid,
    input  wire [4:0] factor_pipe_tag,
    input  wire [IDX_W-1:0] factor_pipe_value,
    input  wire [5:0] factor_pipe_cache_k,
    input  wire [MAX_K*IDX_W-1:0] factor_pipe_cache_bus,
    // Streaming top-K also has a single row0 ingress.  The owner row is
    // selected by candidate index mod 4; candidates and end tags move south.
    input  wire topk_pipe_clear,
    input  wire topk_pipe_token_valid,
    input  wire [IDX_W-1:0] topk_pipe_token_idx,
    input  wire [DATA_W-1:0] topk_pipe_token_score,
    input  wire topk_pipe_token_eligible,
    input  wire topk_pipe_stream_done,
    input  wire [5:0] topk_pipe_max_count,
    input  wire [ROWS*DATA_W-1:0] west_boundary_data_i,
    input  wire [ROWS*IDX_W-1:0]  west_boundary_idx_i,
    input  wire [ROWS*DATA_W-1:0] east_boundary_data_i,
    input  wire [ROWS*IDX_W-1:0]  east_boundary_idx_i,
    output wire [ROWS*DATA_W-1:0] west_boundary_data_o,
    output wire [ROWS*IDX_W-1:0]  west_boundary_idx_o,
    output wire [ROWS*DATA_W-1:0] east_boundary_data_o,
    output wire [ROWS*IDX_W-1:0]  east_boundary_idx_o,
    output wire [ROWS*CLUSTER_COLS*DATA_W-1:0] tile_out_bus,
    output wire [ROWS*CLUSTER_COLS*DATA_W-1:0] mesh_ctx_data_bus,
    output wire [ROWS*CLUSTER_COLS*ACC_W-1:0] tile_acc_bus,
    output wire [ROWS*CLUSTER_COLS*ACC_W-1:0] all_mul_product_bus,
    output wire [ROWS*CLUSTER_COLS*IDX_W-1:0] idx_out_bus,
    output wire [CLUSTER_COLS*DATA_W-1:0] colbus_r0_bus,
    output wire [CLUSTER_COLS*ACC_W-1:0] sparse_product_comb_bus,
    output wire factor_pipe_resp_valid,
    output wire [4:0] factor_pipe_resp_tag,
    output wire [IDX_W-1:0] factor_pipe_resp_value,
    output wire [MAX_K-1:0] factor_pipe_resp_match_mask,
    output wire topk_pipe_result_valid,
    output wire [5:0] topk_pipe_result_count,
    output wire [MAX_K*IDX_W-1:0] topk_pipe_result_idx_bus
);
    localparam integer CELLS = ROWS * CLUSTER_COLS;
    localparam [1:0] MESH_CTX_NONE   = 2'd0;
    localparam [1:0] MESH_CTX_UPDATE = 2'd1;
    localparam [1:0] MESH_CTX_PRUNE  = 2'd2;
    localparam [1:0] MESH_CTX_RESID  = 2'd3;
    localparam [3:0] OP_ADD  = 4'd1;
    localparam [3:0] OP_SUB  = 4'd2;
    localparam [3:0] OP_ABS  = 4'd3;
    localparam [3:0] OP_PASS = 4'd7;

    wire [DATA_W-1:0] inN  [0:CELLS-1];
    wire [DATA_W-1:0] inS  [0:CELLS-1];
    wire [DATA_W-1:0] inE  [0:CELLS-1];
    wire [DATA_W-1:0] inW  [0:CELLS-1];
    wire [DATA_W-1:0] outN [0:CELLS-1];
    wire [DATA_W-1:0] outS [0:CELLS-1];
    wire [DATA_W-1:0] outE [0:CELLS-1];
    wire [DATA_W-1:0] outW [0:CELLS-1];
    wire [IDX_W-1:0]  idxE_out [0:CELLS-1];
    wire [IDX_W-1:0]  idxW_out [0:CELLS-1];
    wire [IDX_W-1:0]  idx_out  [0:CELLS-1];
    wire [DATA_W-1:0] tile_out [0:CELLS-1];
    wire [DATA_W-1:0] tile_mesh_ctx [0:CELLS-1];
    wire [ACC_W-1:0]  tile_acc [0:CELLS-1];
    wire [ACC_W-1:0]  tile_mul_product [0:CELLS-1];
    wire [DATA_W-1:0] colbus_r0 [0:CLUSTER_COLS-1];

    // Mesh-context payloads have a single physical ingress at PE row 0.
    // Each register below is one vertical PE hop; rows 1..3 never consume the
    // controller buses directly.  The payload/tag pipeline is deliberately
    // kept beside the normal outS->inN data link so both advance one row per
    // clock in mesh-context mode.
    reg [1:0] mesh_mode_r1_q, mesh_mode_r2_q, mesh_mode_r3_q;
    reg [IDX_W-1:0] mesh_base_r1_q, mesh_base_r2_q, mesh_base_r3_q;
    reg [IDX_W-1:0] mesh_limit_r1_q, mesh_limit_r2_q, mesh_limit_r3_q;
    reg [DATA_W-1:0] mesh_threshold_r1_q, mesh_threshold_r2_q, mesh_threshold_r3_q;
    reg [3:0] mesh_shift_r1_q, mesh_shift_r2_q, mesh_shift_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] mesh_x_r1_q, mesh_x_r2_q, mesh_x_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] mesh_delta_r1_q, mesh_delta_r2_q, mesh_delta_r3_q;
    reg [CLUSTER_COLS-1:0] mesh_keep_r1_q, mesh_keep_r2_q, mesh_keep_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] sparse_phi_r1_q, sparse_phi_r2_q, sparse_phi_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] sparse_scalar_r1_q, sparse_scalar_r2_q, sparse_scalar_r3_q;
    reg sparse_valid_r1_q, sparse_valid_r2_q, sparse_valid_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] corr_phi_r1_q, corr_phi_r2_q, corr_phi_r3_q;
    reg [CLUSTER_COLS*DATA_W-1:0] corr_scalar_r1_q, corr_scalar_r2_q, corr_scalar_r3_q;
    reg [1:0] corr_slot_r1_q, corr_slot_r2_q, corr_slot_r3_q;
    reg corr_valid_r1_q, corr_valid_r2_q, corr_valid_r3_q;
    reg ls_wide_vertical_r1_q, ls_wide_vertical_r2_q, ls_wide_vertical_r3_q;
    reg [4:0] ls_wide_tag_r1_q, ls_wide_tag_r2_q, ls_wide_tag_r3_q;
    reg [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_a_r1_q, ls_wide_a_r2_q, ls_wide_a_r3_q;
    reg [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_b_r1_q, ls_wide_b_r2_q, ls_wide_b_r3_q;
    wire ls_wide_any_vertical_active = ls_wide_vertical_active |
        ls_wide_vertical_r1_q | ls_wide_vertical_r2_q | ls_wide_vertical_r3_q;

    // Cache data is part of the token and advances through the same vertical
    // row pipeline.  A lower row never observes the controller cache bus.
    reg factor_valid_r1_q, factor_valid_r2_q, factor_valid_r3_q;
    reg [4:0] factor_tag_r1_q, factor_tag_r2_q, factor_tag_r3_q;
    reg [IDX_W-1:0] factor_value_r1_q, factor_value_r2_q, factor_value_r3_q;
    reg [5:0] factor_cache_k_r1_q, factor_cache_k_r2_q, factor_cache_k_r3_q;
    reg [MAX_K*IDX_W-1:0] factor_cache_r1_q, factor_cache_r2_q, factor_cache_r3_q;
    reg [MAX_K-1:0] factor_match_r1_q, factor_match_r2_q, factor_match_r3_q;

    function [MAX_K-1:0] factor_row_match;
        input [IDX_W-1:0] request_value;
        input [MAX_K*IDX_W-1:0] cache_bus;
        input [5:0] cache_k;
        input [1:0] owner_row;
        integer factor_rank;
        begin
            factor_row_match = {MAX_K{1'b0}};
            for (factor_rank = 0; factor_rank < MAX_K; factor_rank = factor_rank + 1) begin
                if ((factor_rank < cache_k) &&
                    (factor_rank[1:0] == owner_row) &&
                    (request_value == cache_bus[factor_rank*IDX_W +: IDX_W]))
                    factor_row_match[factor_rank] = 1'b1;
            end
        end
    endfunction

    assign factor_pipe_resp_valid = factor_valid_r3_q;
    assign factor_pipe_resp_tag = factor_tag_r3_q;
    assign factor_pipe_resp_value = factor_value_r3_q;
    assign factor_pipe_resp_match_mask = factor_match_r3_q |
        factor_row_match(factor_value_r3_q, factor_cache_r3_q,
                         factor_cache_k_r3_q, 2'd3);

    // Top-K token pipeline.  Each row keeps an exact local top-K for its
    // modulo-4 ownership class.  A candidate that cannot enter its owner's
    // local top-K cannot enter the global top-K either, so filtering is exact.
    reg topk_clear_r1_q, topk_clear_r2_q, topk_clear_r3_q;
    reg topk_valid_r1_q, topk_valid_r2_q, topk_valid_r3_q;
    reg topk_done_r1_q, topk_done_r2_q, topk_done_r3_q;
    reg [IDX_W-1:0] topk_idx_r1_q, topk_idx_r2_q, topk_idx_r3_q;
    reg [DATA_W-1:0] topk_score_r1_q, topk_score_r2_q, topk_score_r3_q;
    reg topk_keep_r1_q, topk_keep_r2_q, topk_keep_r3_q;
    reg [5:0] topk_max_r1_q, topk_max_r2_q, topk_max_r3_q;
    reg [IDX_W-1:0] topk_local_idx_q [0:4*MAX_K-1];
    reg [DATA_W-1:0] topk_local_score_q [0:4*MAX_K-1];
    reg [5:0] topk_local_count_q [0:3];
    reg [IDX_W-1:0] topk_global_idx_q [0:MAX_K-1];
    reg [DATA_W-1:0] topk_global_score_q [0:MAX_K-1];
    reg [5:0] topk_global_count_q;
    reg topk_result_valid_q;
    reg [4:0] topk_local_insert_pos [0:3];
    reg topk_local_accept [0:3];
    reg [4:0] topk_global_insert_pos;
    reg topk_global_accept;
    integer topk_row;
    integer topk_rank;
    integer topk_reset_rank;
    integer topk_seq_row;
    integer topk_seq_rank;

    function topk_better;
        input [DATA_W-1:0] score_a;
        input [IDX_W-1:0] idx_a;
        input [DATA_W-1:0] score_b;
        input [IDX_W-1:0] idx_b;
        begin
            topk_better = (score_a > score_b) ||
                          ((score_a == score_b) && (idx_a < idx_b));
        end
    endfunction

    wire [IDX_W-1:0] topk_row_idx [0:3];
    wire [DATA_W-1:0] topk_row_score [0:3];
    wire [5:0] topk_row_max [0:3];
    wire topk_row_valid [0:3];
    wire topk_row_keep [0:3];
    assign topk_row_idx[0] = topk_pipe_token_idx;
    assign topk_row_idx[1] = topk_idx_r1_q;
    assign topk_row_idx[2] = topk_idx_r2_q;
    assign topk_row_idx[3] = topk_idx_r3_q;
    assign topk_row_score[0] = topk_pipe_token_score;
    assign topk_row_score[1] = topk_score_r1_q;
    assign topk_row_score[2] = topk_score_r2_q;
    assign topk_row_score[3] = topk_score_r3_q;
    assign topk_row_max[0] = topk_pipe_max_count;
    assign topk_row_max[1] = topk_max_r1_q;
    assign topk_row_max[2] = topk_max_r2_q;
    assign topk_row_max[3] = topk_max_r3_q;
    assign topk_row_valid[0] = topk_pipe_token_valid;
    assign topk_row_valid[1] = topk_valid_r1_q;
    assign topk_row_valid[2] = topk_valid_r2_q;
    assign topk_row_valid[3] = topk_valid_r3_q;
    assign topk_row_keep[0] = topk_pipe_token_eligible;
    assign topk_row_keep[1] = topk_keep_r1_q;
    assign topk_row_keep[2] = topk_keep_r2_q;
    assign topk_row_keep[3] = topk_keep_r3_q;

    always @(*) begin
        for (topk_row = 0; topk_row < 4; topk_row = topk_row + 1) begin
            topk_local_insert_pos[topk_row] = MAX_K[4:0];
            topk_local_accept[topk_row] = 1'b0;
            if (topk_row_valid[topk_row] && topk_row_keep[topk_row] &&
                (topk_row_idx[topk_row][1:0] == topk_row[1:0])) begin
                for (topk_rank = 0; topk_rank < MAX_K; topk_rank = topk_rank + 1) begin
                    if ((topk_rank < topk_row_max[topk_row]) &&
                        (topk_rank <= topk_local_count_q[topk_row]) &&
                        (topk_local_insert_pos[topk_row] == MAX_K[4:0]) &&
                        ((topk_rank == topk_local_count_q[topk_row]) ||
                         topk_better(topk_row_score[topk_row], topk_row_idx[topk_row],
                                     topk_local_score_q[topk_row*MAX_K+topk_rank],
                                     topk_local_idx_q[topk_row*MAX_K+topk_rank])))
                        topk_local_insert_pos[topk_row] = topk_rank[4:0];
                end
                topk_local_accept[topk_row] =
                    (topk_local_insert_pos[topk_row] < topk_row_max[topk_row]) &&
                    (topk_local_insert_pos[topk_row] < MAX_K);
            end
        end

        topk_global_insert_pos = MAX_K[4:0];
        topk_global_accept = 1'b0;
        if (topk_valid_r3_q && topk_keep_r3_q &&
            ((topk_idx_r3_q[1:0] != 2'd3) || topk_local_accept[3])) begin
            for (topk_rank = 0; topk_rank < MAX_K; topk_rank = topk_rank + 1) begin
                if ((topk_rank < topk_max_r3_q) &&
                    (topk_rank <= topk_global_count_q) &&
                    (topk_global_insert_pos == MAX_K[4:0]) &&
                    ((topk_rank == topk_global_count_q) ||
                     topk_better(topk_score_r3_q, topk_idx_r3_q,
                                 topk_global_score_q[topk_rank],
                                 topk_global_idx_q[topk_rank])))
                    topk_global_insert_pos = topk_rank[4:0];
            end
            topk_global_accept =
                (topk_global_insert_pos < topk_max_r3_q) &&
                (topk_global_insert_pos < MAX_K);
        end
    end

    assign topk_pipe_result_valid = topk_result_valid_q;
    assign topk_pipe_result_count = topk_global_count_q;
    genvar topk_pack_rank;
    generate
        for (topk_pack_rank = 0; topk_pack_rank < MAX_K; topk_pack_rank = topk_pack_rank + 1) begin : gen_topk_result_pack
            assign topk_pipe_result_idx_bus[topk_pack_rank*IDX_W +: IDX_W] =
                topk_global_idx_q[topk_pack_rank];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            topk_clear_r1_q <= 1'b0;
            topk_clear_r2_q <= 1'b0;
            topk_clear_r3_q <= 1'b0;
            topk_valid_r1_q <= 1'b0;
            topk_valid_r2_q <= 1'b0;
            topk_valid_r3_q <= 1'b0;
            topk_done_r1_q <= 1'b0;
            topk_done_r2_q <= 1'b0;
            topk_done_r3_q <= 1'b0;
            topk_idx_r1_q <= {IDX_W{1'b0}};
            topk_idx_r2_q <= {IDX_W{1'b0}};
            topk_idx_r3_q <= {IDX_W{1'b0}};
            topk_score_r1_q <= {DATA_W{1'b0}};
            topk_score_r2_q <= {DATA_W{1'b0}};
            topk_score_r3_q <= {DATA_W{1'b0}};
            topk_keep_r1_q <= 1'b0;
            topk_keep_r2_q <= 1'b0;
            topk_keep_r3_q <= 1'b0;
            topk_max_r1_q <= 6'd0;
            topk_max_r2_q <= 6'd0;
            topk_max_r3_q <= 6'd0;
            topk_global_count_q <= 6'd0;
            topk_result_valid_q <= 1'b0;
            for (topk_reset_rank = 0; topk_reset_rank < 4*MAX_K; topk_reset_rank = topk_reset_rank + 1) begin
                topk_local_idx_q[topk_reset_rank] <= {IDX_W{1'b1}};
                topk_local_score_q[topk_reset_rank] <= {DATA_W{1'b0}};
            end
            for (topk_reset_rank = 0; topk_reset_rank < MAX_K; topk_reset_rank = topk_reset_rank + 1) begin
                topk_global_idx_q[topk_reset_rank] <= {IDX_W{1'b1}};
                topk_global_score_q[topk_reset_rank] <= {DATA_W{1'b0}};
            end
            for (topk_reset_rank = 0; topk_reset_rank < 4; topk_reset_rank = topk_reset_rank + 1)
                topk_local_count_q[topk_reset_rank] <= 6'd0;
        end else begin
            topk_result_valid_q <= 1'b0;
            topk_clear_r1_q <= topk_pipe_clear;
            topk_clear_r2_q <= topk_clear_r1_q;
            topk_clear_r3_q <= topk_clear_r2_q;
            topk_valid_r1_q <= topk_pipe_token_valid;
            topk_valid_r2_q <= topk_valid_r1_q;
            topk_valid_r3_q <= topk_valid_r2_q;
            topk_done_r1_q <= topk_pipe_stream_done;
            topk_done_r2_q <= topk_done_r1_q;
            topk_done_r3_q <= topk_done_r2_q;
            topk_idx_r1_q <= topk_pipe_token_idx;
            topk_idx_r2_q <= topk_idx_r1_q;
            topk_idx_r3_q <= topk_idx_r2_q;
            topk_score_r1_q <= topk_pipe_token_score;
            topk_score_r2_q <= topk_score_r1_q;
            topk_score_r3_q <= topk_score_r2_q;
            topk_max_r1_q <= topk_pipe_max_count;
            topk_max_r2_q <= topk_max_r1_q;
            topk_max_r3_q <= topk_max_r2_q;
            topk_keep_r1_q <= topk_pipe_token_eligible &&
                ((topk_pipe_token_idx[1:0] != 2'd0) || topk_local_accept[0]);
            topk_keep_r2_q <= topk_keep_r1_q &&
                ((topk_idx_r1_q[1:0] != 2'd1) || topk_local_accept[1]);
            topk_keep_r3_q <= topk_keep_r2_q &&
                ((topk_idx_r2_q[1:0] != 2'd2) || topk_local_accept[2]);

            for (topk_seq_row = 0; topk_seq_row < 4; topk_seq_row = topk_seq_row + 1) begin
                if ((topk_seq_row == 0 && topk_pipe_clear) ||
                    (topk_seq_row == 1 && topk_clear_r1_q) ||
                    (topk_seq_row == 2 && topk_clear_r2_q) ||
                    (topk_seq_row == 3 && topk_clear_r3_q)) begin
                    topk_local_count_q[topk_seq_row] <= 6'd0;
                    for (topk_seq_rank = 0; topk_seq_rank < MAX_K; topk_seq_rank = topk_seq_rank + 1) begin
                        topk_local_idx_q[topk_seq_row*MAX_K+topk_seq_rank] <= {IDX_W{1'b1}};
                        topk_local_score_q[topk_seq_row*MAX_K+topk_seq_rank] <= {DATA_W{1'b0}};
                    end
                end else if (topk_local_accept[topk_seq_row]) begin
                    for (topk_seq_rank = 0; topk_seq_rank < MAX_K; topk_seq_rank = topk_seq_rank + 1) begin
                        if ((topk_seq_rank > topk_local_insert_pos[topk_seq_row]) &&
                            (topk_seq_rank < topk_row_max[topk_seq_row])) begin
                            topk_local_idx_q[topk_seq_row*MAX_K+topk_seq_rank] <=
                                topk_local_idx_q[topk_seq_row*MAX_K+topk_seq_rank-1];
                            topk_local_score_q[topk_seq_row*MAX_K+topk_seq_rank] <=
                                topk_local_score_q[topk_seq_row*MAX_K+topk_seq_rank-1];
                        end
                    end
                    topk_local_idx_q[topk_seq_row*MAX_K+topk_local_insert_pos[topk_seq_row]] <= topk_row_idx[topk_seq_row];
                    topk_local_score_q[topk_seq_row*MAX_K+topk_local_insert_pos[topk_seq_row]] <= topk_row_score[topk_seq_row];
                    if ((topk_local_count_q[topk_seq_row] < topk_row_max[topk_seq_row]) &&
                        (topk_local_count_q[topk_seq_row] < MAX_K))
                        topk_local_count_q[topk_seq_row] <= topk_local_count_q[topk_seq_row] + 1'b1;
                end
            end

            if (topk_clear_r3_q) begin
                topk_global_count_q <= 6'd0;
                for (topk_seq_rank = 0; topk_seq_rank < MAX_K; topk_seq_rank = topk_seq_rank + 1) begin
                    topk_global_idx_q[topk_seq_rank] <= {IDX_W{1'b1}};
                    topk_global_score_q[topk_seq_rank] <= {DATA_W{1'b0}};
                end
            end else if (topk_global_accept) begin
                for (topk_seq_rank = 0; topk_seq_rank < MAX_K; topk_seq_rank = topk_seq_rank + 1) begin
                    if ((topk_seq_rank > topk_global_insert_pos) &&
                        (topk_seq_rank < topk_max_r3_q)) begin
                        topk_global_idx_q[topk_seq_rank] <= topk_global_idx_q[topk_seq_rank-1];
                        topk_global_score_q[topk_seq_rank] <= topk_global_score_q[topk_seq_rank-1];
                    end
                end
                topk_global_idx_q[topk_global_insert_pos] <= topk_idx_r3_q;
                topk_global_score_q[topk_global_insert_pos] <= topk_score_r3_q;
                if ((topk_global_count_q < topk_max_r3_q) &&
                    (topk_global_count_q < MAX_K))
                    topk_global_count_q <= topk_global_count_q + 1'b1;
            end

            if (topk_done_r3_q)
                topk_result_valid_q <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mesh_mode_r1_q <= MESH_CTX_NONE;
            mesh_mode_r2_q <= MESH_CTX_NONE;
            mesh_mode_r3_q <= MESH_CTX_NONE;
            mesh_base_r1_q <= {IDX_W{1'b0}};
            mesh_base_r2_q <= {IDX_W{1'b0}};
            mesh_base_r3_q <= {IDX_W{1'b0}};
            mesh_limit_r1_q <= {IDX_W{1'b0}};
            mesh_limit_r2_q <= {IDX_W{1'b0}};
            mesh_limit_r3_q <= {IDX_W{1'b0}};
            mesh_threshold_r1_q <= {DATA_W{1'b0}};
            mesh_threshold_r2_q <= {DATA_W{1'b0}};
            mesh_threshold_r3_q <= {DATA_W{1'b0}};
            mesh_shift_r1_q <= 4'd0;
            mesh_shift_r2_q <= 4'd0;
            mesh_shift_r3_q <= 4'd0;
            mesh_x_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_x_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_x_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_delta_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_delta_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_delta_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            mesh_keep_r1_q <= {CLUSTER_COLS{1'b0}};
            mesh_keep_r2_q <= {CLUSTER_COLS{1'b0}};
            mesh_keep_r3_q <= {CLUSTER_COLS{1'b0}};
            sparse_phi_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_phi_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_phi_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_scalar_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_scalar_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_scalar_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_valid_r1_q <= 1'b0;
            sparse_valid_r2_q <= 1'b0;
            sparse_valid_r3_q <= 1'b0;
            corr_phi_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_phi_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_phi_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_scalar_r1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_scalar_r2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_scalar_r3_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_slot_r1_q <= 2'd0;
            corr_slot_r2_q <= 2'd0;
            corr_slot_r3_q <= 2'd0;
            corr_valid_r1_q <= 1'b0;
            corr_valid_r2_q <= 1'b0;
            corr_valid_r3_q <= 1'b0;
            ls_wide_vertical_r1_q <= 1'b0;
            ls_wide_vertical_r2_q <= 1'b0;
            ls_wide_vertical_r3_q <= 1'b0;
            ls_wide_tag_r1_q <= 5'd0;
            ls_wide_tag_r2_q <= 5'd0;
            ls_wide_tag_r3_q <= 5'd0;
            ls_wide_a_r1_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_a_r2_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_a_r3_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_b_r1_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_b_r2_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_b_r3_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            factor_valid_r1_q <= 1'b0;
            factor_valid_r2_q <= 1'b0;
            factor_valid_r3_q <= 1'b0;
            factor_tag_r1_q <= 5'd0;
            factor_tag_r2_q <= 5'd0;
            factor_tag_r3_q <= 5'd0;
            factor_value_r1_q <= {IDX_W{1'b0}};
            factor_value_r2_q <= {IDX_W{1'b0}};
            factor_value_r3_q <= {IDX_W{1'b0}};
            factor_cache_k_r1_q <= 6'd0;
            factor_cache_k_r2_q <= 6'd0;
            factor_cache_k_r3_q <= 6'd0;
            factor_cache_r1_q <= {MAX_K*IDX_W{1'b0}};
            factor_cache_r2_q <= {MAX_K*IDX_W{1'b0}};
            factor_cache_r3_q <= {MAX_K*IDX_W{1'b0}};
            factor_match_r1_q <= {MAX_K{1'b0}};
            factor_match_r2_q <= {MAX_K{1'b0}};
            factor_match_r3_q <= {MAX_K{1'b0}};
        end else begin
            mesh_mode_r1_q <= (ctx_valid ? mesh_ctx_mode : MESH_CTX_NONE);
            mesh_mode_r2_q <= mesh_mode_r1_q;
            mesh_mode_r3_q <= mesh_mode_r2_q;
            mesh_base_r1_q <= mesh_ctx_base_idx;
            mesh_base_r2_q <= mesh_base_r1_q;
            mesh_base_r3_q <= mesh_base_r2_q;
            mesh_limit_r1_q <= mesh_ctx_limit;
            mesh_limit_r2_q <= mesh_limit_r1_q;
            mesh_limit_r3_q <= mesh_limit_r2_q;
            mesh_threshold_r1_q <= mesh_ctx_threshold;
            mesh_threshold_r2_q <= mesh_threshold_r1_q;
            mesh_threshold_r3_q <= mesh_threshold_r2_q;
            mesh_shift_r1_q <= mesh_ctx_shift;
            mesh_shift_r2_q <= mesh_shift_r1_q;
            mesh_shift_r3_q <= mesh_shift_r2_q;
            mesh_x_r1_q <= mesh_ctx_x_bus;
            mesh_x_r2_q <= mesh_x_r1_q;
            mesh_x_r3_q <= mesh_x_r2_q;
            mesh_delta_r1_q <= mesh_ctx_delta_bus;
            mesh_delta_r2_q <= mesh_delta_r1_q;
            mesh_delta_r3_q <= mesh_delta_r2_q;
            mesh_keep_r1_q <= mesh_ctx_keep_bus;
            mesh_keep_r2_q <= mesh_keep_r1_q;
            mesh_keep_r3_q <= mesh_keep_r2_q;
            // Phi/coefficient operands also have one ingress.  A stable LS
            // issue is striped by support rank p mod 4 as it moves downward.
            sparse_phi_r1_q <= phi_bus;
            sparse_phi_r2_q <= sparse_phi_r1_q;
            sparse_phi_r3_q <= sparse_phi_r2_q;
            sparse_scalar_r1_q <= scalar_bus;
            sparse_scalar_r2_q <= sparse_scalar_r1_q;
            sparse_scalar_r3_q <= sparse_scalar_r2_q;
            sparse_valid_r1_q <= sparse_active && sparse_step_active && (sparse_op == 4'd3);
            sparse_valid_r2_q <= sparse_valid_r1_q;
            sparse_valid_r3_q <= sparse_valid_r2_q;
            corr_phi_r1_q <= phi_bus;
            corr_phi_r2_q <= corr_phi_r1_q;
            corr_phi_r3_q <= corr_phi_r2_q;
            corr_scalar_r1_q <= scalar_bus;
            corr_scalar_r2_q <= corr_scalar_r1_q;
            corr_scalar_r3_q <= corr_scalar_r2_q;
            corr_slot_r1_q <= corr_slot;
            corr_slot_r2_q <= corr_slot_r1_q;
            corr_slot_r3_q <= corr_slot_r2_q;
            corr_valid_r1_q <= corr_acc_en;
            corr_valid_r2_q <= corr_valid_r1_q;
            corr_valid_r3_q <= corr_valid_r2_q;
            ls_wide_vertical_r1_q <= ls_wide_vertical_active;
            ls_wide_vertical_r2_q <= ls_wide_vertical_r1_q;
            ls_wide_vertical_r3_q <= ls_wide_vertical_r2_q;
            ls_wide_tag_r1_q <= ls_wide_vertical_tag;
            ls_wide_tag_r2_q <= ls_wide_tag_r1_q;
            ls_wide_tag_r3_q <= ls_wide_tag_r2_q;
            ls_wide_a_r1_q <= ls_wide_a_bus;
            ls_wide_a_r2_q <= ls_wide_a_r1_q;
            ls_wide_a_r3_q <= ls_wide_a_r2_q;
            ls_wide_b_r1_q <= ls_wide_b_bus;
            ls_wide_b_r2_q <= ls_wide_b_r1_q;
            ls_wide_b_r3_q <= ls_wide_b_r2_q;
            factor_valid_r1_q <= factor_pipe_valid;
            factor_valid_r2_q <= factor_valid_r1_q;
            factor_valid_r3_q <= factor_valid_r2_q;
            factor_tag_r1_q <= factor_pipe_tag;
            factor_tag_r2_q <= factor_tag_r1_q;
            factor_tag_r3_q <= factor_tag_r2_q;
            factor_value_r1_q <= factor_pipe_value;
            factor_value_r2_q <= factor_value_r1_q;
            factor_value_r3_q <= factor_value_r2_q;
            factor_cache_k_r1_q <= factor_pipe_cache_k;
            factor_cache_k_r2_q <= factor_cache_k_r1_q;
            factor_cache_k_r3_q <= factor_cache_k_r2_q;
            factor_cache_r1_q <= factor_pipe_cache_bus;
            factor_cache_r2_q <= factor_cache_r1_q;
            factor_cache_r3_q <= factor_cache_r2_q;
            factor_match_r1_q <= factor_row_match(
                factor_pipe_value, factor_pipe_cache_bus,
                factor_pipe_cache_k, 2'd0);
            factor_match_r2_q <= factor_match_r1_q | factor_row_match(
                factor_value_r1_q, factor_cache_r1_q,
                factor_cache_k_r1_q, 2'd1);
            factor_match_r3_q <= factor_match_r2_q | factor_row_match(
                factor_value_r2_q, factor_cache_r2_q,
                factor_cache_k_r2_q, 2'd2);
        end
    end

`ifndef SYNTHESIS
    // Simulation-only contract checks for the single-ingress vertical mesh.
    // A lower row may become valid only from the immediately preceding row,
    // with the same operation tag and block bounds one clock later.
    reg [1:0] mesh_assert_prev_mode0_q, mesh_assert_prev_mode1_q, mesh_assert_prev_mode2_q;
    reg [IDX_W-1:0] mesh_assert_prev_base0_q, mesh_assert_prev_base1_q, mesh_assert_prev_base2_q;
    reg [IDX_W-1:0] mesh_assert_prev_limit0_q, mesh_assert_prev_limit1_q, mesh_assert_prev_limit2_q;
    reg sparse_assert_prev_valid0_q, sparse_assert_prev_valid1_q, sparse_assert_prev_valid2_q;
    reg [CLUSTER_COLS*DATA_W-1:0] sparse_assert_prev_phi0_q, sparse_assert_prev_phi1_q, sparse_assert_prev_phi2_q;
    reg [CLUSTER_COLS*DATA_W-1:0] sparse_assert_prev_scalar0_q, sparse_assert_prev_scalar1_q, sparse_assert_prev_scalar2_q;
    reg corr_assert_prev_valid0_q, corr_assert_prev_valid1_q, corr_assert_prev_valid2_q;
    reg [1:0] corr_assert_prev_slot0_q, corr_assert_prev_slot1_q, corr_assert_prev_slot2_q;
    reg [CLUSTER_COLS*DATA_W-1:0] corr_assert_prev_phi0_q, corr_assert_prev_phi1_q, corr_assert_prev_phi2_q;
    reg [CLUSTER_COLS*DATA_W-1:0] corr_assert_prev_scalar0_q, corr_assert_prev_scalar1_q, corr_assert_prev_scalar2_q;
    reg factor_assert_prev_valid0_q, factor_assert_prev_valid1_q, factor_assert_prev_valid2_q;
    reg [4:0] factor_assert_prev_tag0_q, factor_assert_prev_tag1_q, factor_assert_prev_tag2_q;
    reg [IDX_W-1:0] factor_assert_prev_value0_q, factor_assert_prev_value1_q, factor_assert_prev_value2_q;
    reg topk_assert_prev_valid0_q, topk_assert_prev_valid1_q, topk_assert_prev_valid2_q;
    reg topk_assert_prev_done0_q, topk_assert_prev_done1_q, topk_assert_prev_done2_q;
    reg topk_assert_prev_done3_q;
    reg [IDX_W-1:0] topk_assert_prev_idx0_q, topk_assert_prev_idx1_q, topk_assert_prev_idx2_q;
    reg [DATA_W-1:0] topk_assert_prev_score0_q, topk_assert_prev_score1_q, topk_assert_prev_score2_q;
    reg ls_wide_assert_prev_valid0_q, ls_wide_assert_prev_valid1_q, ls_wide_assert_prev_valid2_q;
    reg [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_assert_prev_a0_q, ls_wide_assert_prev_a1_q, ls_wide_assert_prev_a2_q;
    reg [ROWS*CLUSTER_COLS*DATA_W-1:0] ls_wide_assert_prev_b0_q, ls_wide_assert_prev_b1_q, ls_wide_assert_prev_b2_q;
    reg [4:0] ls_wide_assert_prev_tag0_q, ls_wide_assert_prev_tag1_q, ls_wide_assert_prev_tag2_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mesh_assert_prev_mode0_q <= MESH_CTX_NONE;
            mesh_assert_prev_mode1_q <= MESH_CTX_NONE;
            mesh_assert_prev_mode2_q <= MESH_CTX_NONE;
            mesh_assert_prev_base0_q <= {IDX_W{1'b0}};
            mesh_assert_prev_base1_q <= {IDX_W{1'b0}};
            mesh_assert_prev_base2_q <= {IDX_W{1'b0}};
            mesh_assert_prev_limit0_q <= {IDX_W{1'b0}};
            mesh_assert_prev_limit1_q <= {IDX_W{1'b0}};
            mesh_assert_prev_limit2_q <= {IDX_W{1'b0}};
            sparse_assert_prev_valid0_q <= 1'b0;
            sparse_assert_prev_valid1_q <= 1'b0;
            sparse_assert_prev_valid2_q <= 1'b0;
            sparse_assert_prev_phi0_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_assert_prev_phi1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_assert_prev_phi2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_assert_prev_scalar0_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_assert_prev_scalar1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            sparse_assert_prev_scalar2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_valid0_q <= 1'b0;
            corr_assert_prev_valid1_q <= 1'b0;
            corr_assert_prev_valid2_q <= 1'b0;
            corr_assert_prev_slot0_q <= 2'd0;
            corr_assert_prev_slot1_q <= 2'd0;
            corr_assert_prev_slot2_q <= 2'd0;
            corr_assert_prev_phi0_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_phi1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_phi2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_scalar0_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_scalar1_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            corr_assert_prev_scalar2_q <= {(CLUSTER_COLS*DATA_W){1'b0}};
            factor_assert_prev_valid0_q <= 1'b0;
            factor_assert_prev_valid1_q <= 1'b0;
            factor_assert_prev_valid2_q <= 1'b0;
            factor_assert_prev_tag0_q <= 5'd0;
            factor_assert_prev_tag1_q <= 5'd0;
            factor_assert_prev_tag2_q <= 5'd0;
            factor_assert_prev_value0_q <= {IDX_W{1'b0}};
            factor_assert_prev_value1_q <= {IDX_W{1'b0}};
            factor_assert_prev_value2_q <= {IDX_W{1'b0}};
            topk_assert_prev_valid0_q <= 1'b0;
            topk_assert_prev_valid1_q <= 1'b0;
            topk_assert_prev_valid2_q <= 1'b0;
            topk_assert_prev_done0_q <= 1'b0;
            topk_assert_prev_done1_q <= 1'b0;
            topk_assert_prev_done2_q <= 1'b0;
            topk_assert_prev_done3_q <= 1'b0;
            topk_assert_prev_idx0_q <= {IDX_W{1'b0}};
            topk_assert_prev_idx1_q <= {IDX_W{1'b0}};
            topk_assert_prev_idx2_q <= {IDX_W{1'b0}};
            topk_assert_prev_score0_q <= {DATA_W{1'b0}};
            topk_assert_prev_score1_q <= {DATA_W{1'b0}};
            topk_assert_prev_score2_q <= {DATA_W{1'b0}};
            ls_wide_assert_prev_valid0_q <= 1'b0;
            ls_wide_assert_prev_valid1_q <= 1'b0;
            ls_wide_assert_prev_valid2_q <= 1'b0;
            ls_wide_assert_prev_a0_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_a1_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_a2_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_b0_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_b1_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_b2_q <= {ROWS*CLUSTER_COLS*DATA_W{1'b0}};
            ls_wide_assert_prev_tag0_q <= 5'd0;
            ls_wide_assert_prev_tag1_q <= 5'd0;
            ls_wide_assert_prev_tag2_q <= 5'd0;
        end else begin
            if ((mesh_mode_r1_q != MESH_CTX_NONE) &&
                ((mesh_assert_prev_mode0_q == MESH_CTX_NONE) ||
                 (mesh_mode_r1_q != mesh_assert_prev_mode0_q) ||
                 (mesh_base_r1_q != mesh_assert_prev_base0_q) ||
                 (mesh_limit_r1_q != mesh_assert_prev_limit0_q)))
                $error("PE_VERTICAL_ASSERT row1 payload/tag did not originate at row0 one cycle earlier");
            if ((mesh_mode_r2_q != MESH_CTX_NONE) &&
                ((mesh_assert_prev_mode1_q == MESH_CTX_NONE) ||
                 (mesh_mode_r2_q != mesh_assert_prev_mode1_q) ||
                 (mesh_base_r2_q != mesh_assert_prev_base1_q) ||
                 (mesh_limit_r2_q != mesh_assert_prev_limit1_q)))
                $error("PE_VERTICAL_ASSERT row2 payload/tag did not originate at row1 one cycle earlier");
            if ((mesh_mode_r3_q != MESH_CTX_NONE) &&
                ((mesh_assert_prev_mode2_q == MESH_CTX_NONE) ||
                 (mesh_mode_r3_q != mesh_assert_prev_mode2_q) ||
                 (mesh_base_r3_q != mesh_assert_prev_base2_q) ||
                 (mesh_limit_r3_q != mesh_assert_prev_limit2_q)))
                $error("PE_VERTICAL_ASSERT row3 payload/tag did not originate at row2 one cycle earlier");
            if (sparse_valid_r1_q &&
                (!sparse_assert_prev_valid0_q ||
                 (sparse_phi_r1_q != sparse_assert_prev_phi0_q) ||
                 (sparse_scalar_r1_q != sparse_assert_prev_scalar0_q)))
                $error("PE_VERTICAL_ASSERT residual row1 operands did not originate at row0 one cycle earlier");
            if (sparse_valid_r2_q &&
                (!sparse_assert_prev_valid1_q ||
                 (sparse_phi_r2_q != sparse_assert_prev_phi1_q) ||
                 (sparse_scalar_r2_q != sparse_assert_prev_scalar1_q)))
                $error("PE_VERTICAL_ASSERT residual row2 operands did not originate at row1 one cycle earlier");
            if (sparse_valid_r3_q &&
                (!sparse_assert_prev_valid2_q ||
                 (sparse_phi_r3_q != sparse_assert_prev_phi2_q) ||
                 (sparse_scalar_r3_q != sparse_assert_prev_scalar2_q)))
                $error("PE_VERTICAL_ASSERT residual row3 operands did not originate at row2 one cycle earlier");
            if (corr_valid_r1_q &&
                (!corr_assert_prev_valid0_q || (corr_slot_r1_q != corr_assert_prev_slot0_q) ||
                 (corr_phi_r1_q != corr_assert_prev_phi0_q) ||
                 (corr_scalar_r1_q != corr_assert_prev_scalar0_q)))
                $error("PE_VERTICAL_ASSERT correlation row1 token did not originate at row0 one cycle earlier");
            if (corr_valid_r2_q &&
                (!corr_assert_prev_valid1_q || (corr_slot_r2_q != corr_assert_prev_slot1_q) ||
                 (corr_phi_r2_q != corr_assert_prev_phi1_q) ||
                 (corr_scalar_r2_q != corr_assert_prev_scalar1_q)))
                $error("PE_VERTICAL_ASSERT correlation row2 token did not originate at row1 one cycle earlier");
            if (corr_valid_r3_q &&
                (!corr_assert_prev_valid2_q || (corr_slot_r3_q != corr_assert_prev_slot2_q) ||
                 (corr_phi_r3_q != corr_assert_prev_phi2_q) ||
                 (corr_scalar_r3_q != corr_assert_prev_scalar2_q)))
                $error("PE_VERTICAL_ASSERT correlation row3 token did not originate at row2 one cycle earlier");
            if (factor_valid_r1_q &&
                (!factor_assert_prev_valid0_q ||
                 (factor_tag_r1_q != factor_assert_prev_tag0_q) ||
                 (factor_value_r1_q != factor_assert_prev_value0_q)))
                $error("PE_VERTICAL_ASSERT factor row1 request did not originate at row0 one cycle earlier");
            if (factor_valid_r2_q &&
                (!factor_assert_prev_valid1_q ||
                 (factor_tag_r2_q != factor_assert_prev_tag1_q) ||
                 (factor_value_r2_q != factor_assert_prev_value1_q)))
                $error("PE_VERTICAL_ASSERT factor row2 request did not originate at row1 one cycle earlier");
            if (factor_valid_r3_q &&
                (!factor_assert_prev_valid2_q ||
                 (factor_tag_r3_q != factor_assert_prev_tag2_q) ||
                 (factor_value_r3_q != factor_assert_prev_value2_q)))
                $error("PE_VERTICAL_ASSERT factor row3 request did not originate at row2 one cycle earlier");
            if (topk_valid_r1_q &&
                (!topk_assert_prev_valid0_q ||
                 (topk_idx_r1_q != topk_assert_prev_idx0_q) ||
                 (topk_score_r1_q != topk_assert_prev_score0_q)))
                $error("PE_VERTICAL_ASSERT topk row1 token did not originate at row0 one cycle earlier");
            if (topk_valid_r2_q &&
                (!topk_assert_prev_valid1_q ||
                 (topk_idx_r2_q != topk_assert_prev_idx1_q) ||
                 (topk_score_r2_q != topk_assert_prev_score1_q)))
                $error("PE_VERTICAL_ASSERT topk row2 token did not originate at row1 one cycle earlier");
            if (topk_valid_r3_q &&
                (!topk_assert_prev_valid2_q ||
                 (topk_idx_r3_q != topk_assert_prev_idx2_q) ||
                 (topk_score_r3_q != topk_assert_prev_score2_q)))
                $error("PE_VERTICAL_ASSERT topk row3 token did not originate at row2 one cycle earlier");
            if (topk_done_r1_q && !topk_assert_prev_done0_q)
                $error("PE_VERTICAL_ASSERT topk row1 end tag lacked row0 provenance");
            if (topk_done_r2_q && !topk_assert_prev_done1_q)
                $error("PE_VERTICAL_ASSERT topk row2 end tag lacked row1 provenance");
            if (topk_done_r3_q && !topk_assert_prev_done2_q)
                $error("PE_VERTICAL_ASSERT topk row3 end tag lacked row2 provenance");
            if (topk_pipe_result_valid && !topk_assert_prev_done3_q)
                $error("PE_VERTICAL_ASSERT topk result committed without prior PE3 end tag");
            if (ls_wide_vertical_r1_q &&
                (!ls_wide_assert_prev_valid0_q ||
                 (ls_wide_tag_r1_q != ls_wide_assert_prev_tag0_q) ||
                 (ls_wide_a_r1_q != ls_wide_assert_prev_a0_q) ||
                 (ls_wide_b_r1_q != ls_wide_assert_prev_b0_q)))
                $error("PE_VERTICAL_ASSERT LDLT row1 operands did not originate at row0 one cycle earlier");
            if (ls_wide_vertical_r2_q &&
                (!ls_wide_assert_prev_valid1_q ||
                 (ls_wide_tag_r2_q != ls_wide_assert_prev_tag1_q) ||
                 (ls_wide_a_r2_q != ls_wide_assert_prev_a1_q) ||
                 (ls_wide_b_r2_q != ls_wide_assert_prev_b1_q)))
                $error("PE_VERTICAL_ASSERT LDLT row2 operands did not originate at row1 one cycle earlier");
            if (ls_wide_vertical_r3_q &&
                (!ls_wide_assert_prev_valid2_q ||
                 (ls_wide_tag_r3_q != ls_wide_assert_prev_tag2_q) ||
                 (ls_wide_a_r3_q != ls_wide_assert_prev_a2_q) ||
                 (ls_wide_b_r3_q != ls_wide_assert_prev_b2_q)))
                $error("PE_VERTICAL_ASSERT LDLT row3 operands did not originate at row2 one cycle earlier");

            mesh_assert_prev_mode0_q <= ctx_valid ? mesh_ctx_mode : MESH_CTX_NONE;
            mesh_assert_prev_mode1_q <= mesh_mode_r1_q;
            mesh_assert_prev_mode2_q <= mesh_mode_r2_q;
            mesh_assert_prev_base0_q <= mesh_ctx_base_idx;
            mesh_assert_prev_base1_q <= mesh_base_r1_q;
            mesh_assert_prev_base2_q <= mesh_base_r2_q;
            mesh_assert_prev_limit0_q <= mesh_ctx_limit;
            mesh_assert_prev_limit1_q <= mesh_limit_r1_q;
            mesh_assert_prev_limit2_q <= mesh_limit_r2_q;
            sparse_assert_prev_valid0_q <= sparse_active && sparse_step_active && (sparse_op == 4'd3);
            sparse_assert_prev_valid1_q <= sparse_valid_r1_q;
            sparse_assert_prev_valid2_q <= sparse_valid_r2_q;
            sparse_assert_prev_phi0_q <= phi_bus;
            sparse_assert_prev_phi1_q <= sparse_phi_r1_q;
            sparse_assert_prev_phi2_q <= sparse_phi_r2_q;
            sparse_assert_prev_scalar0_q <= scalar_bus;
            sparse_assert_prev_scalar1_q <= sparse_scalar_r1_q;
            sparse_assert_prev_scalar2_q <= sparse_scalar_r2_q;
            corr_assert_prev_valid0_q <= corr_acc_en;
            corr_assert_prev_valid1_q <= corr_valid_r1_q;
            corr_assert_prev_valid2_q <= corr_valid_r2_q;
            corr_assert_prev_slot0_q <= corr_slot;
            corr_assert_prev_slot1_q <= corr_slot_r1_q;
            corr_assert_prev_slot2_q <= corr_slot_r2_q;
            corr_assert_prev_phi0_q <= phi_bus;
            corr_assert_prev_phi1_q <= corr_phi_r1_q;
            corr_assert_prev_phi2_q <= corr_phi_r2_q;
            corr_assert_prev_scalar0_q <= scalar_bus;
            corr_assert_prev_scalar1_q <= corr_scalar_r1_q;
            corr_assert_prev_scalar2_q <= corr_scalar_r2_q;
            factor_assert_prev_valid0_q <= factor_pipe_valid;
            factor_assert_prev_valid1_q <= factor_valid_r1_q;
            factor_assert_prev_valid2_q <= factor_valid_r2_q;
            factor_assert_prev_tag0_q <= factor_pipe_tag;
            factor_assert_prev_tag1_q <= factor_tag_r1_q;
            factor_assert_prev_tag2_q <= factor_tag_r2_q;
            factor_assert_prev_value0_q <= factor_pipe_value;
            factor_assert_prev_value1_q <= factor_value_r1_q;
            factor_assert_prev_value2_q <= factor_value_r2_q;
            topk_assert_prev_valid0_q <= topk_pipe_token_valid;
            topk_assert_prev_valid1_q <= topk_valid_r1_q;
            topk_assert_prev_valid2_q <= topk_valid_r2_q;
            topk_assert_prev_done0_q <= topk_pipe_stream_done;
            topk_assert_prev_done1_q <= topk_done_r1_q;
            topk_assert_prev_done2_q <= topk_done_r2_q;
            topk_assert_prev_done3_q <= topk_done_r3_q;
            topk_assert_prev_idx0_q <= topk_pipe_token_idx;
            topk_assert_prev_idx1_q <= topk_idx_r1_q;
            topk_assert_prev_idx2_q <= topk_idx_r2_q;
            topk_assert_prev_score0_q <= topk_pipe_token_score;
            topk_assert_prev_score1_q <= topk_score_r1_q;
            topk_assert_prev_score2_q <= topk_score_r2_q;
            ls_wide_assert_prev_valid0_q <= ls_wide_vertical_active;
            ls_wide_assert_prev_valid1_q <= ls_wide_vertical_r1_q;
            ls_wide_assert_prev_valid2_q <= ls_wide_vertical_r2_q;
            ls_wide_assert_prev_a0_q <= ls_wide_a_bus;
            ls_wide_assert_prev_a1_q <= ls_wide_a_r1_q;
            ls_wide_assert_prev_a2_q <= ls_wide_a_r2_q;
            ls_wide_assert_prev_b0_q <= ls_wide_b_bus;
            ls_wide_assert_prev_b1_q <= ls_wide_b_r1_q;
            ls_wide_assert_prev_b2_q <= ls_wide_b_r2_q;
            ls_wide_assert_prev_tag0_q <= ls_wide_vertical_tag;
            ls_wide_assert_prev_tag1_q <= ls_wide_tag_r1_q;
            ls_wide_assert_prev_tag2_q <= ls_wide_tag_r2_q;
        end
    end
`endif

    genvar r;
    genvar lc;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_r
            for (lc = 0; lc < CLUSTER_COLS; lc = lc + 1) begin : gen_c
                localparam integer CELL = r*CLUSTER_COLS + lc;
                localparam integer GLOBAL_C = COL_OFFSET + lc;
                localparam [1:0] ROW_SLOT = r;
                wire [1:0] mesh_ctx_mode_row = (r == 0) ? mesh_ctx_mode :
                                               (r == 1) ? mesh_mode_r1_q :
                                               (r == 2) ? mesh_mode_r2_q : mesh_mode_r3_q;
                wire [IDX_W-1:0] mesh_ctx_base_row = (r == 0) ? mesh_ctx_base_idx :
                                                       (r == 1) ? mesh_base_r1_q :
                                                       (r == 2) ? mesh_base_r2_q : mesh_base_r3_q;
                wire [IDX_W-1:0] mesh_ctx_limit_row = (r == 0) ? mesh_ctx_limit :
                                                        (r == 1) ? mesh_limit_r1_q :
                                                        (r == 2) ? mesh_limit_r2_q : mesh_limit_r3_q;
                wire [DATA_W-1:0] mesh_ctx_threshold_row = (r == 0) ? mesh_ctx_threshold :
                                                             (r == 1) ? mesh_threshold_r1_q :
                                                             (r == 2) ? mesh_threshold_r2_q : mesh_threshold_r3_q;
                wire [3:0] mesh_ctx_shift_row = (r == 0) ? mesh_ctx_shift :
                                                  (r == 1) ? mesh_shift_r1_q :
                                                  (r == 2) ? mesh_shift_r2_q : mesh_shift_r3_q;
                wire [CLUSTER_COLS*DATA_W-1:0] mesh_ctx_x_row = (r == 0) ? mesh_ctx_x_bus :
                                                                  (r == 1) ? mesh_x_r1_q :
                                                                  (r == 2) ? mesh_x_r2_q : mesh_x_r3_q;
                wire [CLUSTER_COLS*DATA_W-1:0] mesh_ctx_delta_row = (r == 0) ? mesh_ctx_delta_bus :
                                                                      (r == 1) ? mesh_delta_r1_q :
                                                                      (r == 2) ? mesh_delta_r2_q : mesh_delta_r3_q;
                wire [CLUSTER_COLS-1:0] mesh_ctx_keep_row = (r == 0) ? mesh_ctx_keep_bus :
                                                               (r == 1) ? mesh_keep_r1_q :
                                                               (r == 2) ? mesh_keep_r2_q : mesh_keep_r3_q;
                wire [IDX_W-1:0] idx_self = base_idx + GLOBAL_C[IDX_W-1:0];
                assign inN[CELL] = (r == 0) ? {DATA_W{1'b0}} : outS[(r-1)*CLUSTER_COLS+lc];
                assign inS[CELL] = (r == ROWS-1) ? {DATA_W{1'b0}} : outN[(r+1)*CLUSTER_COLS+lc];
                assign inE[CELL] = (lc == CLUSTER_COLS-1) ? east_boundary_data_i[r*DATA_W +: DATA_W] : outW[r*CLUSTER_COLS+(lc+1)];
                assign inW[CELL] = (lc == 0) ? west_boundary_data_i[r*DATA_W +: DATA_W] : outE[r*CLUSTER_COLS+(lc-1)];
                wire [IDX_W-1:0] idxE_in = (lc == CLUSTER_COLS-1) ? east_boundary_idx_i[r*IDX_W +: IDX_W] : idxW_out[r*CLUSTER_COLS+(lc+1)];
                wire [IDX_W-1:0] idxW_in = (lc == 0) ? west_boundary_idx_i[r*IDX_W +: IDX_W] : idxE_out[r*CLUSTER_COLS+(lc-1)];
                // Correlation is striped across all four physical rows.  Each
                // row owns one sample slot modulo four and keeps an independent
                // full-precision partial sum, so the stream accepts one sample
                // every clock while all rows perform useful MAC work.
                wire phys_corr_pe_active = sparse_active && (sparse_op == 4'd1);
                wire phys_refine_pe_active = sparse_active && (sparse_op == 4'd0) &&
                                             (r < ROWS-1) && (sparse_k_active > GLOBAL_C);
                wire phys_resid_wave_active = sparse_active && sparse_step_active &&
                                              (sparse_op == 4'd3) && (sparse_k_active > GLOBAL_C);
                wire row0_mac_stage = phys_refine_pe_active && (r == 0);
                wire row1_accum_stage = phys_refine_pe_active && (r == 1);
                wire row2_update_stage = phys_refine_pe_active && (r == 2);
                wire corr_token_active = (r == 0) ? corr_acc_en :
                                         (r == 1) ? corr_valid_r1_q :
                                         (r == 2) ? corr_valid_r2_q : corr_valid_r3_q;
                wire [1:0] corr_token_slot = (r == 0) ? corr_slot :
                                             (r == 1) ? corr_slot_r1_q :
                                             (r == 2) ? corr_slot_r2_q : corr_slot_r3_q;
                wire corr_row_owner = phys_corr_pe_active && corr_token_active &&
                                      (corr_token_slot == ROW_SLOT);
                wire ls_wide_vertical_row_active = (r == 0) ? ls_wide_vertical_active :
                                                   (r == 1) ? ls_wide_vertical_r1_q :
                                                   (r == 2) ? ls_wide_vertical_r2_q :
                                                              ls_wide_vertical_r3_q;
                wire ls_wide_active_row = ls_wide_any_vertical_active ?
                                          ls_wide_vertical_row_active :
                                          ls_wide_mul_active;
                wire phys_ls_pe_active = !ls_wide_active_row &&
                                         (phys_corr_pe_active || phys_refine_pe_active || phys_resid_wave_active);
                wire mesh_ctx_active = (mesh_ctx_mode_row != MESH_CTX_NONE);
                wire [3:0] mesh_ctx_row_op =
                    (mesh_ctx_mode_row == MESH_CTX_UPDATE) ? (r == 1 ? OP_ADD : OP_PASS) :
                    (mesh_ctx_mode_row == MESH_CTX_PRUNE)  ? (r == 0 ? OP_ABS : OP_PASS) :
                    (mesh_ctx_mode_row == MESH_CTX_RESID)  ? (r == 1 ? OP_SUB : OP_PASS) : OP_PASS;
                wire [3:0] tile_pe_op = ls_wide_active_row ? 4'd0 : (mesh_ctx_active ? mesh_ctx_row_op :
                                          (phys_corr_pe_active ? 4'd0 :
                                          (phys_resid_wave_active ? 4'd0 :
                                          (phys_refine_pe_active ? (row0_mac_stage ? 4'd0 : (row1_accum_stage ? 4'd1 : 4'd8)) : pe_op))));
                wire [2:0] tile_src_a_sel = mesh_ctx_active ? 3'd0 : (ls_wide_active_row ? 3'd7 : (phys_corr_pe_active ? 3'd7 :
                                             (phys_resid_wave_active ? 3'd7 :
                                             (phys_refine_pe_active ? (row0_mac_stage ? 3'd7 : 3'd0) : src_a_sel))));
                wire [2:0] tile_src_b_sel = mesh_ctx_active ? 3'd0 : (ls_wide_active_row ? 3'd7 : (phys_corr_pe_active ? 3'd7 :
                                             (phys_resid_wave_active ? 3'd7 :
                                             (phys_refine_pe_active ? (row0_mac_stage ? 3'd7 : (row2_update_stage ? 3'd3 : 3'd5)) : src_b_sel))));
                wire [15:0] tile_imm16 = phys_corr_pe_active ? 16'h4000 :
                                             (phys_refine_pe_active ? (row0_mac_stage ? 16'h4000 : 16'h0001) : imm16);
                wire tile_acc_clear = ls_wide_active_row ? 1'b0 : (phys_corr_pe_active ? corr_acc_clear :
                                          (phys_resid_wave_active ? 1'b0 :
                                          (phys_refine_pe_active ? (r == 0) : (ctx_valid && row_en[r] && acc_clear && first_in_phase))));
                wire tile_acc_en = ls_wide_active_row ? 1'b0 : (phys_corr_pe_active ? corr_row_owner :
                                       (phys_resid_wave_active ? 1'b0 :
                                       (phys_refine_pe_active ? (r == 0) : (ctx_valid && row_en[r] && lane_valid[lc] && acc_en))));
                wire tile_sb_sel_en = mesh_ctx_active ? 1'b1 : (phys_ls_pe_active ? 1'b1 : (sb_sel_en && row_en[r]));
                wire [2:0] tile_sb_sel = mesh_ctx_active ? 3'd4 : (phys_ls_pe_active ? 3'd4 : sb_sel);
                wire [3:0] tile_out_sel = phys_ls_pe_active ? 4'd0 : out_sel;
                wire tile_ext_b_is_scalar = ls_wide_active_row ? 1'b1 :
                                                ((phys_corr_pe_active || phys_resid_wave_active) ? 1'b1 :
                                                (phys_refine_pe_active ? (r == 0) : ext_ctrl[0]));
                wire tile_en = ls_wide_active_row || (ctx_valid && row_en[r] && lane_valid[lc]) || phys_ls_pe_active || mesh_ctx_active || (|mesh_keepalive);
                wire [DATA_W-1:0] ls_wide_vertical_a_row = (r == 0) ?
                    ls_wide_a_bus[(0*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                    (r == 1) ? ls_wide_a_r1_q[(1*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                    (r == 2) ? ls_wide_a_r2_q[(2*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                               ls_wide_a_r3_q[(3*CLUSTER_COLS+lc)*DATA_W +: DATA_W];
                wire [DATA_W-1:0] ls_wide_vertical_b_row = (r == 0) ?
                    ls_wide_b_bus[(0*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                    (r == 1) ? ls_wide_b_r1_q[(1*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                    (r == 2) ? ls_wide_b_r2_q[(2*CLUSTER_COLS+lc)*DATA_W +: DATA_W] :
                               ls_wide_b_r3_q[(3*CLUSTER_COLS+lc)*DATA_W +: DATA_W];
                wire [DATA_W-1:0] tile_phi_data = ls_wide_active_row ?
                    (ls_wide_any_vertical_active ? ls_wide_vertical_a_row :
                     ls_wide_a_bus[CELL*DATA_W +: DATA_W]) :
                    ((phys_corr_pe_active && corr_token_active) ?
                                             ((r == 0) ? phi_bus[lc*DATA_W +: DATA_W] :
                                               (r == 1) ? corr_phi_r1_q[lc*DATA_W +: DATA_W] :
                                               (r == 2) ? corr_phi_r2_q[lc*DATA_W +: DATA_W] :
                                                          corr_phi_r3_q[lc*DATA_W +: DATA_W]) :
                    (phys_resid_wave_active ? ((r == 0) ? phi_bus[lc*DATA_W +: DATA_W] :
                                               (r == 1) ? sparse_phi_r1_q[lc*DATA_W +: DATA_W] :
                                               (r == 2) ? sparse_phi_r2_q[lc*DATA_W +: DATA_W] :
                                                          sparse_phi_r3_q[lc*DATA_W +: DATA_W]) :
                                             phi_bus[lc*DATA_W +: DATA_W]));
                wire [DATA_W-1:0] tile_scalar_data = ls_wide_active_row ?
                    (ls_wide_any_vertical_active ? ls_wide_vertical_b_row :
                     ls_wide_b_bus[CELL*DATA_W +: DATA_W]) :
                    ((phys_corr_pe_active && corr_token_active) ?
                                             ((r == 0) ? scalar_bus[lc*DATA_W +: DATA_W] :
                                               (r == 1) ? corr_scalar_r1_q[lc*DATA_W +: DATA_W] :
                                               (r == 2) ? corr_scalar_r2_q[lc*DATA_W +: DATA_W] :
                                                          corr_scalar_r3_q[lc*DATA_W +: DATA_W]) :
                    (phys_resid_wave_active ? ((r == 0) ? scalar_bus[lc*DATA_W +: DATA_W] :
                                               (r == 1) ? sparse_scalar_r1_q[lc*DATA_W +: DATA_W] :
                                               (r == 2) ? sparse_scalar_r2_q[lc*DATA_W +: DATA_W] :
                                                          sparse_scalar_r3_q[lc*DATA_W +: DATA_W]) :
                                             scalar_bus[lc*DATA_W +: DATA_W]));

                pe_tile #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W),
                    .Q_FRAC_W(Q_FRAC_W),
                    .IDX_W(IDX_W),
                    .ROW_ID(r),
                    .GLOBAL_COL(GLOBAL_C),
                    .PIPE_MESH(1), .PIPE_CORE_IN(1), .FULL_OUT_MUX((r == ROWS-1) ? 1 : 0), .ENABLE_MESH_CTX(ENABLE_MESH_CTX)
                ) u_tile (
                    .clk(clk), .rst_n(rst_n), .tile_en(tile_en),
                    .sparse_wavefront_active(phys_resid_wave_active),
                    .corr_wavefront_active(phys_corr_pe_active && corr_token_active),
                    .corr_pipeline_active(phys_corr_pe_active),
                    .inN(inN[CELL]), .inS(inS[CELL]), .inE(inE[CELL]), .inW(inW[CELL]),
                    .idxE_in(idxE_in), .idxW_in(idxW_in), .idx_self(idx_self),
                    .spm_a_data(spm_a_rdata[lc*DATA_W +: DATA_W]),
                    .spm_b_data(spm_b_rdata[lc*DATA_W +: DATA_W]),
                    .phi_data(tile_phi_data),
                    .colbus_data((r == ROWS-1) ? colbus_r0[lc] : {DATA_W{1'b0}}),
                    .scalar_data(tile_scalar_data),
                    .imm16(tile_imm16), .mesh_ctx_mode(mesh_ctx_mode_row), .pe_op(tile_pe_op),
                    .mesh_ctx_base_idx(mesh_ctx_base_row), .mesh_ctx_limit(mesh_ctx_limit_row), .mesh_ctx_threshold(mesh_ctx_threshold_row), .mesh_ctx_shift(mesh_ctx_shift_row),
                    .mesh_ctx_x(mesh_ctx_x_row[lc*DATA_W +: DATA_W]), .mesh_ctx_delta(mesh_ctx_delta_row[lc*DATA_W +: DATA_W]), .mesh_ctx_keep(mesh_ctx_keep_row[lc]),
                    .src_a_sel(tile_src_a_sel), .src_b_sel(tile_src_b_sel),
                    .rf_rd_addr(rf_rd_addr), .rf_wr_addr(rf_wr_addr),
                    .rf_wr_en(ctx_valid && row_en[r] && lane_valid[lc] && rf_wr_en),
                    .acc_clear(tile_acc_clear), .acc_en(tile_acc_en),
                    .sb_sel(tile_sb_sel), .sb_sel_en(tile_sb_sel_en),
                    .out_sel(tile_out_sel), .ext_b_is_scalar(tile_ext_b_is_scalar),
                    .outN(outN[CELL]), .outS(outS[CELL]), .outE(outE[CELL]), .outW(outW[CELL]),
                    .idxE_out(idxE_out[CELL]), .idxW_out(idxW_out[CELL]),
                    .pe_data_out(tile_out[CELL]), .mesh_ctx_data_out(tile_mesh_ctx[CELL]), .idx_out(idx_out[CELL]), .acc_out(tile_acc[CELL]), .mul_product_out(tile_mul_product[CELL])
                );

`ifdef TB_CORR_WAVE_TRACE
                if (GLOBAL_C == 0) begin : gen_corr_wave_trace
                    always @(posedge clk) begin
                        if (corr_row_owner)
                            $display("CORR_WAVE row=%0d slot=%0d phi=%06x scalar=%06x product=%016x acc_before=%016x",
                                     r, corr_token_slot, tile_phi_data, tile_scalar_data,
                                     tile_mul_product[CELL], tile_acc[CELL]);
                        if (corr_acc_clear && !corr_acc_en && (tile_acc[CELL] != 0))
                            $display("CORR_FINAL row=%0d acc=%016x", r, tile_acc[CELL]);
                    end
                end
`endif

                assign tile_out_bus[CELL*DATA_W +: DATA_W] = tile_out[CELL];
                assign mesh_ctx_data_bus[CELL*DATA_W +: DATA_W] = ENABLE_MESH_CTX ? tile_mesh_ctx[CELL] : {DATA_W{1'b0}};
                assign tile_acc_bus[CELL*ACC_W +: ACC_W] = tile_acc[CELL];
                assign all_mul_product_bus[CELL*ACC_W +: ACC_W] = tile_mul_product[CELL];
                assign idx_out_bus[CELL*IDX_W +: IDX_W] = idx_out[CELL];
                if (r == 0) begin : gen_colbus
                    assign colbus_r0[lc] = tile_out[CELL];
                end
            end
        end
        for (lc = 0; lc < CLUSTER_COLS; lc = lc + 1) begin : gen_sparse_product_owner
            localparam integer OWNER_ROW = (COL_OFFSET + lc) % ROWS;
            // Logical support p enters row 0 and is consumed only by p mod 4.
            assign sparse_product_comb_bus[lc*ACC_W +: ACC_W] =
                (sparse_op == 4'd3) ? tile_mul_product[OWNER_ROW*CLUSTER_COLS + lc] :
                                      tile_mul_product[lc];
        end
        for (lc = 0; lc < CLUSTER_COLS; lc = lc + 1) begin : gen_colbus_out
            assign colbus_r0_bus[lc*DATA_W +: DATA_W] = colbus_r0[lc];
        end
        for (r = 0; r < ROWS; r = r + 1) begin : gen_boundary
            assign west_boundary_data_o[r*DATA_W +: DATA_W] = outW[r*CLUSTER_COLS];
            assign west_boundary_idx_o[r*IDX_W +: IDX_W] = idxW_out[r*CLUSTER_COLS];
            assign east_boundary_data_o[r*DATA_W +: DATA_W] = outE[r*CLUSTER_COLS+(CLUSTER_COLS-1)];
            assign east_boundary_idx_o[r*IDX_W +: IDX_W] = idxE_out[r*CLUSTER_COLS+(CLUSTER_COLS-1)];
        end
    endgenerate
endmodule




