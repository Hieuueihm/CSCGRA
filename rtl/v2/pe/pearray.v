module pearray #(
    parameter integer ROWS   = 4,
    parameter integer COLS   = 8,
    parameter integer DATA_W = 24,
    // Architectural constant: the corr_acc_bus/sparse_rhs_product_bus
    // packing below slices [63:0] directly and the sparse kernel engine
    // consumes fixed 64-bit products.  See the guard after the localparams.
    parameter integer ACC_W  = 64,
    parameter integer CTX_W  = 64,
    parameter integer SCALAR_W = 56,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W  = 10,
    parameter integer MAX_K  = 16,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer ENABLE_DEBUG_COUNTERS = 0,
    parameter integer ENABLE_MESH_CTX = 1
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       ctx_valid,
    input  wire [3:0]                 pe_op,
    input  wire [2:0]                 src_a_sel,
    input  wire [2:0]                 src_b_sel,
    input  wire [1:0]                 rf_rd_addr,
    input  wire [1:0]                 rf_wr_addr,
    input  wire                       rf_wr_en,
    input  wire                       acc_clear,
    input  wire                       acc_en,
    input  wire [3:0]                 out_sel,
    input  wire                       spm_wr_en,
    input  wire [2:0]                 spm_wr_data_sel,
    input  wire [2:0]                 sb_sel,
    input  wire                       sb_sel_en,
    input  wire [3:0]                 row_en,
    input  wire [15:0]                imm16,
    input  wire [3:0]                 ext_ctrl,
    input  wire [1:0]                 mesh_ctx_mode,
    input  wire [IDX_W-1:0]           mesh_ctx_base_idx,
    input  wire [IDX_W-1:0]           mesh_ctx_limit,
    input  wire [DATA_W-1:0]          mesh_ctx_threshold,
    input  wire [3:0]                 mesh_ctx_shift,
    input  wire [COLS*DATA_W-1:0]     mesh_ctx_x_bus,
    input  wire [COLS*DATA_W-1:0]     mesh_ctx_delta_bus,
    input  wire [COLS-1:0]            mesh_ctx_keep_bus,
    input  wire [COLS-1:0]            lane_valid,
    input  wire [IDX_W-1:0]           base_idx,
    input  wire                       first_in_phase,

    input  wire [COLS*DATA_W-1:0]     spm_a_rdata,
    input  wire [COLS*DATA_W-1:0]     spm_b_rdata,
    input  wire [COLS*DATA_W-1:0]     phi_bus,
    // Pair-mode second-half correlation Phi lanes (16-column super-blocks);
    // registered down to PE rows 2/3 inside each cluster.
    input  wire [COLS*DATA_W-1:0]     phi2_bus,
    input  wire [COLS*DATA_W-1:0]     scalar_bus,

    input  wire                       sparse_active,
    input  wire                       sparse_step_active,
    input  wire                       sparse_clear,
    input  wire                       corr_acc_clear,
    input  wire                       corr_acc_en,
    // corr_pair_mode: rows {0,1} own super-block columns 0-7 and rows {2,3}
    // own columns 8-15, sample ownership by slot parity.  corr_half_sel
    // picks which half's sums corr_acc_bus exposes during the two-phase
    // super-block drain.  Both are stable while a correlation block runs.
    input  wire                       corr_pair_mode,
    input  wire                       corr_half_sel,
    input  wire [3:0]                 sparse_op,
    input  wire [7:0]                 sparse_k_active,
    input  wire                       ls_wide_mul_active,
    input  wire                       ls_wide_operand_valid,
    input  wire                       ls_wide_vertical_active,
    input  wire [4:0]                 ls_wide_vertical_tag,
    input  wire [COLS*DATA_W-1:0]      ls_wide_a_row0_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_a_row1_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_a_row2_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_a_row3_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_b_row0_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_b_row1_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_b_row2_bus,
    input  wire [COLS*DATA_W-1:0]      ls_wide_b_row3_bus,
    input  wire                       factor_pipe_valid,
    input  wire [4:0]                 factor_pipe_tag,
    input  wire [IDX_W-1:0]           factor_pipe_value,
    input  wire [5:0]                 factor_pipe_cache_k,
    input  wire [MAX_K*IDX_W-1:0]     factor_pipe_cache_bus,
    input  wire                       topk_pipe_clear,
    input  wire                       topk_pipe_token_valid,
    input  wire [IDX_W-1:0]           topk_pipe_token_idx,
    input  wire [DATA_W-1:0]          topk_pipe_token_score,
    input  wire                       topk_pipe_token_eligible,
    input  wire                       topk_pipe_stream_done,
    input  wire [5:0]                 topk_pipe_max_count,

    output wire [COLS*DATA_W-1:0]     spm_wdata,
    output wire [COLS-1:0]            spm_wen,

    output wire [COLS*DATA_W-1:0]     reduce_data,
    output wire [COLS*ACC_W-1:0]      acc_data,
    output wire [COLS*64-1:0]         sparse_rhs_product_bus,
    output wire [COLS*64-1:0]         corr_acc_bus,
    output wire [ROWS*COLS*ACC_W-1:0] ls_wide_product_bus,
    output wire                       factor_pipe_resp_valid,
    output wire [4:0]                 factor_pipe_resp_tag,
    output wire [IDX_W-1:0]           factor_pipe_resp_value,
    output wire [MAX_K-1:0]           factor_pipe_resp_match_mask,
    output wire                       topk_pipe_result_valid,
    output wire [5:0]                 topk_pipe_result_count,
    output wire [MAX_K*IDX_W-1:0]     topk_pipe_result_idx_bus,
    output wire [COLS*DATA_W-1:0]     mesh_ctx_commit_data,
    // v3 result interface (replaces external reduction_unit / scalar_unit latch)
    output wire [SCALAR_W-1:0]        result_value,
    output wire [IDX_W-1:0]           result_idx,
    output wire                       result_flag,
    output wire                       result_valid,
    output wire                       compute_done
);


    // Sparse loop control lives above pearray; pearray remains compute fabric.
    // Physical PE fabric is organized as two 4x4 clusters.  The boundary
    // between column 3 and column 4 is connected by a combinational column
    // connection (CC); CC is only a named wire-level connection, not a register.
    localparam CELLS = ROWS * COLS;
    localparam CLUSTER_COLS = 4;
    localparam CLUSTER_COUNT = 2;
    localparam CC_WEST_COL = CLUSTER_COLS - 1;
    localparam CC_EAST_COL = CLUSTER_COLS;

`ifndef SYNTHESIS
    // ACC_W is not a free knob: the 64-bit correlation/sparse product bus
    // contract is hard-coded in this module's output packing and in the
    // sparse kernel engine.  The stale 48-bit CGRA-era default never worked;
    // fail loudly on any future misconfiguration instead of slicing x's.
    initial begin
        if (ACC_W != 64)
            $error("pearray ACC_W must be 64 (64-bit corr/product bus contract), got %0d", ACC_W);
    end
`endif

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
    wire [ACC_W-1:0]  tile_acc [0:CELLS-1];
    wire [DATA_W-1:0] colbus_r0 [0:COLS-1];
    wire [DATA_W-1:0] cc_west_to_east_data [0:ROWS-1];
    wire [DATA_W-1:0] cc_east_to_west_data [0:ROWS-1];
    wire [IDX_W-1:0]  cc_west_to_east_idx  [0:ROWS-1];
    wire [IDX_W-1:0]  cc_east_to_west_idx  [0:ROWS-1];
    wire [ROWS*DATA_W-1:0] boundary_zero_data = {ROWS*DATA_W{1'b0}};
    wire [ROWS*IDX_W-1:0]  boundary_zero_idx  = {ROWS*IDX_W{1'b0}};
    wire [ROWS*DATA_W-1:0] cc_west_to_east_data_bus;
    wire [ROWS*DATA_W-1:0] cc_east_to_west_data_bus;
    wire [ROWS*IDX_W-1:0]  cc_west_to_east_idx_bus;
    wire [ROWS*IDX_W-1:0]  cc_east_to_west_idx_bus;
    wire [ROWS*DATA_W-1:0] cluster0_east_data_bus;
    wire [ROWS*DATA_W-1:0] cluster1_west_data_bus;
    wire [ROWS*IDX_W-1:0]  cluster0_east_idx_bus;
    wire [ROWS*IDX_W-1:0]  cluster1_west_idx_bus;
    wire [ROWS*DATA_W-1:0] cluster0_west_data_unused;
    wire [ROWS*DATA_W-1:0] cluster1_east_data_unused;
    wire [ROWS*IDX_W-1:0]  cluster0_west_idx_unused;
    wire [ROWS*IDX_W-1:0]  cluster1_east_idx_unused;
    wire [ROWS*CLUSTER_COLS*DATA_W-1:0] cluster0_tile_out_bus;
    wire [ROWS*CLUSTER_COLS*DATA_W-1:0] cluster0_mesh_ctx_data_bus;
    wire [ROWS*CLUSTER_COLS*DATA_W-1:0] cluster1_tile_out_bus;
    wire [ROWS*CLUSTER_COLS*DATA_W-1:0] cluster1_mesh_ctx_data_bus;
    wire [ROWS*CLUSTER_COLS*ACC_W-1:0]  cluster0_tile_acc_bus;
    wire [ROWS*CLUSTER_COLS*ACC_W-1:0]  cluster1_tile_acc_bus;
    wire [ROWS*CLUSTER_COLS*ACC_W-1:0]  cluster0_all_mul_product_bus;
    wire [ROWS*CLUSTER_COLS*ACC_W-1:0]  cluster1_all_mul_product_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_a_row0_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_a_row1_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_a_row2_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_a_row3_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_a_row0_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_a_row1_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_a_row2_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_a_row3_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_b_row0_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_b_row1_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_b_row2_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_ls_wide_b_row3_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_b_row0_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_b_row1_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_b_row2_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_ls_wide_b_row3_bus;
    wire [ROWS*CLUSTER_COLS*IDX_W-1:0]  cluster0_idx_out_bus;
    wire [ROWS*CLUSTER_COLS*IDX_W-1:0]  cluster1_idx_out_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster0_colbus_r0_bus;
    wire [CLUSTER_COLS*DATA_W-1:0] cluster1_colbus_r0_bus;
    wire [CLUSTER_COLS*ACC_W-1:0] cluster0_sparse_product_comb_bus;
    wire [CLUSTER_COLS*ACC_W-1:0] cluster1_sparse_product_comb_bus;
    wire cluster0_factor_pipe_resp_valid;
    wire [4:0] cluster0_factor_pipe_resp_tag;
    wire [IDX_W-1:0] cluster0_factor_pipe_resp_value;
    wire [MAX_K-1:0] cluster0_factor_pipe_resp_match_mask;
    wire cluster1_factor_pipe_resp_valid_unused;
    wire [4:0] cluster1_factor_pipe_resp_tag_unused;
    wire [IDX_W-1:0] cluster1_factor_pipe_resp_value_unused;
    wire [MAX_K-1:0] cluster1_factor_pipe_resp_match_mask_unused;
    wire cluster0_topk_pipe_result_valid;
    wire [5:0] cluster0_topk_pipe_result_count;
    wire [MAX_K*IDX_W-1:0] cluster0_topk_pipe_result_idx_bus;
    wire cluster1_topk_pipe_result_valid_unused;
    wire [5:0] cluster1_topk_pipe_result_count_unused;
    wire [MAX_K*IDX_W-1:0] cluster1_topk_pipe_result_idx_bus_unused;
    assign factor_pipe_resp_valid = cluster0_factor_pipe_resp_valid;
    assign factor_pipe_resp_tag = cluster0_factor_pipe_resp_tag;
    assign factor_pipe_resp_value = cluster0_factor_pipe_resp_value;
    assign factor_pipe_resp_match_mask = cluster0_factor_pipe_resp_match_mask;
    assign topk_pipe_result_valid = cluster0_topk_pipe_result_valid;
    assign topk_pipe_result_count = cluster0_topk_pipe_result_count;
    assign topk_pipe_result_idx_bus = cluster0_topk_pipe_result_idx_bus;
    wire [COLS*ACC_W-1:0] sparse_product_comb_bus = {cluster1_sparse_product_comb_bus, cluster0_sparse_product_comb_bus};
    reg [3:0] mesh_keepalive_q;
    reg [1:0] corr_slot_q;
    wire mesh_active_req = ctx_valid | sparse_active;
    reg [31:0] row_exec_count [0:ROWS-1];
    reg [31:0] col_exec_count [0:COLS-1];
    reg [31:0] phys_row0_pe_mac_count;
    reg [31:0] phys_row1_pe_accum_count;
    reg [31:0] phys_row2_pe_update_count;
    reg [31:0] phys_row0_nonzero_count;
    reg [31:0] phys_row1_nonzero_count;
    reg [31:0] phys_row2_nonzero_count;
    reg [31:0] phys_corr_row0_mac_count;
    reg [31:0] phys_corr_row1_accum_count;
    reg [31:0] phys_corr_row2_update_count;
    reg [31:0] phys_corr_row3_write_count;
    reg [31:0] phys_refine_row0_mac_count;
    reg [31:0] phys_refine_row1_accum_count;
    reg [31:0] phys_refine_row2_update_count;

    genvar r;
    genvar c;
    genvar lc;

    pe_cluster_4x4 #(
        .ROWS(ROWS), .CLUSTER_COLS(CLUSTER_COLS), .TOTAL_COLS(COLS), .COL_OFFSET(0),
        .DATA_W(DATA_W), .ACC_W(ACC_W), .IDX_W(IDX_W), .MAX_K(MAX_K), .Q_FRAC_W(Q_FRAC_W), .ENABLE_MESH_CTX(ENABLE_MESH_CTX)
    ) u_pe_cluster0_4x4 (
        .clk(clk), .rst_n(rst_n), .ctx_valid(ctx_valid), .pe_op(pe_op),
        .src_a_sel(src_a_sel), .src_b_sel(src_b_sel), .rf_rd_addr(rf_rd_addr),
        .rf_wr_addr(rf_wr_addr), .rf_wr_en(rf_wr_en), .acc_clear(acc_clear),
        .acc_en(acc_en), .out_sel(out_sel), .sb_sel(sb_sel), .sb_sel_en(sb_sel_en),
        .row_en(row_en), .imm16(imm16), .ext_ctrl(ext_ctrl), .mesh_ctx_mode(mesh_ctx_mode),
        .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift), .mesh_ctx_x_bus(mesh_ctx_x_bus[0 +: CLUSTER_COLS*DATA_W]), .mesh_ctx_delta_bus(mesh_ctx_delta_bus[0 +: CLUSTER_COLS*DATA_W]), .mesh_ctx_keep_bus(mesh_ctx_keep_bus[0 +: CLUSTER_COLS]),
        .lane_valid(lane_valid[CLUSTER_COLS-1:0]), .base_idx(base_idx),
        .first_in_phase(first_in_phase),
        .spm_a_rdata(spm_a_rdata[0 +: CLUSTER_COLS*DATA_W]),
        .spm_b_rdata(spm_b_rdata[0 +: CLUSTER_COLS*DATA_W]),
        .phi_bus(phi_bus[0 +: CLUSTER_COLS*DATA_W]),
        .phi2_bus(phi2_bus[0 +: CLUSTER_COLS*DATA_W]),
        .scalar_bus(scalar_bus[0 +: CLUSTER_COLS*DATA_W]),
        .sparse_active(sparse_active), .sparse_step_active(sparse_step_active), .sparse_op(sparse_op), .sparse_k_active(sparse_k_active),
        .corr_acc_clear(corr_acc_clear), .corr_acc_en(corr_acc_en), .corr_slot(corr_slot_q), .corr_pair_mode(corr_pair_mode),
        .ls_wide_mul_active(ls_wide_mul_active),
        .ls_wide_operand_valid(ls_wide_operand_valid),
        .ls_wide_vertical_active(ls_wide_vertical_active),
        .ls_wide_vertical_tag(ls_wide_vertical_tag),
        .ls_wide_a_row0_bus(cluster0_ls_wide_a_row0_bus),
        .ls_wide_a_row1_bus(cluster0_ls_wide_a_row1_bus),
        .ls_wide_a_row2_bus(cluster0_ls_wide_a_row2_bus),
        .ls_wide_a_row3_bus(cluster0_ls_wide_a_row3_bus),
        .ls_wide_b_row0_bus(cluster0_ls_wide_b_row0_bus),
        .ls_wide_b_row1_bus(cluster0_ls_wide_b_row1_bus),
        .ls_wide_b_row2_bus(cluster0_ls_wide_b_row2_bus),
        .ls_wide_b_row3_bus(cluster0_ls_wide_b_row3_bus),
        .mesh_keepalive(mesh_keepalive_q),
        .factor_pipe_valid(factor_pipe_valid), .factor_pipe_tag(factor_pipe_tag),
        .factor_pipe_value(factor_pipe_value), .factor_pipe_cache_k(factor_pipe_cache_k),
        .factor_pipe_cache_bus(factor_pipe_cache_bus),
        .topk_pipe_clear(topk_pipe_clear), .topk_pipe_token_valid(topk_pipe_token_valid),
        .topk_pipe_token_idx(topk_pipe_token_idx), .topk_pipe_token_score(topk_pipe_token_score),
        .topk_pipe_token_eligible(topk_pipe_token_eligible), .topk_pipe_stream_done(topk_pipe_stream_done),
        .topk_pipe_max_count(topk_pipe_max_count),
        .west_boundary_data_i(boundary_zero_data), .west_boundary_idx_i(boundary_zero_idx),
        .east_boundary_data_i(cc_east_to_west_data_bus), .east_boundary_idx_i(cc_east_to_west_idx_bus),
        .west_boundary_data_o(cluster0_west_data_unused), .west_boundary_idx_o(cluster0_west_idx_unused),
        .east_boundary_data_o(cluster0_east_data_bus), .east_boundary_idx_o(cluster0_east_idx_bus),
        .tile_out_bus(cluster0_tile_out_bus), .mesh_ctx_data_bus(cluster0_mesh_ctx_data_bus), .tile_acc_bus(cluster0_tile_acc_bus), .all_mul_product_bus(cluster0_all_mul_product_bus),
        .idx_out_bus(cluster0_idx_out_bus), .colbus_r0_bus(cluster0_colbus_r0_bus), .sparse_product_comb_bus(cluster0_sparse_product_comb_bus),
        .factor_pipe_resp_valid(cluster0_factor_pipe_resp_valid), .factor_pipe_resp_tag(cluster0_factor_pipe_resp_tag),
        .factor_pipe_resp_value(cluster0_factor_pipe_resp_value), .factor_pipe_resp_match_mask(cluster0_factor_pipe_resp_match_mask),
        .topk_pipe_result_valid(cluster0_topk_pipe_result_valid), .topk_pipe_result_count(cluster0_topk_pipe_result_count),
        .topk_pipe_result_idx_bus(cluster0_topk_pipe_result_idx_bus)
    );

    pe_cluster_4x4 #(
        .ROWS(ROWS), .CLUSTER_COLS(CLUSTER_COLS), .TOTAL_COLS(COLS), .COL_OFFSET(CLUSTER_COLS),
        .DATA_W(DATA_W), .ACC_W(ACC_W), .IDX_W(IDX_W), .MAX_K(MAX_K), .Q_FRAC_W(Q_FRAC_W), .ENABLE_MESH_CTX(ENABLE_MESH_CTX)
    ) u_pe_cluster1_4x4 (
        .clk(clk), .rst_n(rst_n), .ctx_valid(ctx_valid), .pe_op(pe_op),
        .src_a_sel(src_a_sel), .src_b_sel(src_b_sel), .rf_rd_addr(rf_rd_addr),
        .rf_wr_addr(rf_wr_addr), .rf_wr_en(rf_wr_en), .acc_clear(acc_clear),
        .acc_en(acc_en), .out_sel(out_sel), .sb_sel(sb_sel), .sb_sel_en(sb_sel_en),
        .row_en(row_en), .imm16(imm16), .ext_ctrl(ext_ctrl), .mesh_ctx_mode(mesh_ctx_mode),
        .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift), .mesh_ctx_x_bus(mesh_ctx_x_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]), .mesh_ctx_delta_bus(mesh_ctx_delta_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]), .mesh_ctx_keep_bus(mesh_ctx_keep_bus[CLUSTER_COLS +: CLUSTER_COLS]),
        .lane_valid(lane_valid[COLS-1:CLUSTER_COLS]), .base_idx(base_idx),
        .first_in_phase(first_in_phase),
        .spm_a_rdata(spm_a_rdata[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]),
        .spm_b_rdata(spm_b_rdata[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]),
        .phi_bus(phi_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]),
        .phi2_bus(phi2_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]),
        .scalar_bus(scalar_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W]),
        .sparse_active(sparse_active), .sparse_step_active(sparse_step_active), .sparse_op(sparse_op), .sparse_k_active(sparse_k_active),
        .corr_acc_clear(corr_acc_clear), .corr_acc_en(corr_acc_en), .corr_slot(corr_slot_q), .corr_pair_mode(corr_pair_mode),
        .ls_wide_mul_active(ls_wide_mul_active),
        .ls_wide_operand_valid(ls_wide_operand_valid),
        .ls_wide_vertical_active(ls_wide_vertical_active),
        .ls_wide_vertical_tag(ls_wide_vertical_tag),
        .ls_wide_a_row0_bus(cluster1_ls_wide_a_row0_bus),
        .ls_wide_a_row1_bus(cluster1_ls_wide_a_row1_bus),
        .ls_wide_a_row2_bus(cluster1_ls_wide_a_row2_bus),
        .ls_wide_a_row3_bus(cluster1_ls_wide_a_row3_bus),
        .ls_wide_b_row0_bus(cluster1_ls_wide_b_row0_bus),
        .ls_wide_b_row1_bus(cluster1_ls_wide_b_row1_bus),
        .ls_wide_b_row2_bus(cluster1_ls_wide_b_row2_bus),
        .ls_wide_b_row3_bus(cluster1_ls_wide_b_row3_bus),
        .mesh_keepalive(mesh_keepalive_q),
        .factor_pipe_valid(1'b0), .factor_pipe_tag(5'd0),
        .factor_pipe_value({IDX_W{1'b0}}), .factor_pipe_cache_k(6'd0),
        .factor_pipe_cache_bus({MAX_K*IDX_W{1'b0}}),
        .topk_pipe_clear(1'b0), .topk_pipe_token_valid(1'b0),
        .topk_pipe_token_idx({IDX_W{1'b0}}), .topk_pipe_token_score({DATA_W{1'b0}}),
        .topk_pipe_token_eligible(1'b0), .topk_pipe_stream_done(1'b0), .topk_pipe_max_count(6'd0),
        .west_boundary_data_i(cc_west_to_east_data_bus), .west_boundary_idx_i(cc_west_to_east_idx_bus),
        .east_boundary_data_i(boundary_zero_data), .east_boundary_idx_i(boundary_zero_idx),
        .west_boundary_data_o(cluster1_west_data_bus), .west_boundary_idx_o(cluster1_west_idx_bus),
        .east_boundary_data_o(cluster1_east_data_unused), .east_boundary_idx_o(cluster1_east_idx_unused),
        .tile_out_bus(cluster1_tile_out_bus), .mesh_ctx_data_bus(cluster1_mesh_ctx_data_bus), .tile_acc_bus(cluster1_tile_acc_bus), .all_mul_product_bus(cluster1_all_mul_product_bus),
        .idx_out_bus(cluster1_idx_out_bus), .colbus_r0_bus(cluster1_colbus_r0_bus), .sparse_product_comb_bus(cluster1_sparse_product_comb_bus),
        .factor_pipe_resp_valid(cluster1_factor_pipe_resp_valid_unused), .factor_pipe_resp_tag(cluster1_factor_pipe_resp_tag_unused),
        .factor_pipe_resp_value(cluster1_factor_pipe_resp_value_unused), .factor_pipe_resp_match_mask(cluster1_factor_pipe_resp_match_mask_unused),
        .topk_pipe_result_valid(cluster1_topk_pipe_result_valid_unused), .topk_pipe_result_count(cluster1_topk_pipe_result_count_unused),
        .topk_pipe_result_idx_bus(cluster1_topk_pipe_result_idx_bus_unused)
    );

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_cluster_map_r
            for (lc = 0; lc < CLUSTER_COLS; lc = lc + 1) begin : gen_cluster_map_c
                assign tile_out[r*COLS+lc] = cluster0_tile_out_bus[(r*CLUSTER_COLS+lc)*DATA_W +: DATA_W];
                assign tile_acc[r*COLS+lc] = cluster0_tile_acc_bus[(r*CLUSTER_COLS+lc)*ACC_W +: ACC_W];
                assign idx_out[r*COLS+lc] = cluster0_idx_out_bus[(r*CLUSTER_COLS+lc)*IDX_W +: IDX_W];
                assign colbus_r0[lc] = cluster0_colbus_r0_bus[lc*DATA_W +: DATA_W];
                assign ls_wide_product_bus[(r*COLS+lc)*ACC_W +: ACC_W] = cluster0_all_mul_product_bus[(r*CLUSTER_COLS+lc)*ACC_W +: ACC_W];
                assign tile_out[r*COLS+CLUSTER_COLS+lc] = cluster1_tile_out_bus[(r*CLUSTER_COLS+lc)*DATA_W +: DATA_W];
                assign tile_acc[r*COLS+CLUSTER_COLS+lc] = cluster1_tile_acc_bus[(r*CLUSTER_COLS+lc)*ACC_W +: ACC_W];
                assign idx_out[r*COLS+CLUSTER_COLS+lc] = cluster1_idx_out_bus[(r*CLUSTER_COLS+lc)*IDX_W +: IDX_W];
                assign colbus_r0[CLUSTER_COLS+lc] = cluster1_colbus_r0_bus[lc*DATA_W +: DATA_W];
                assign ls_wide_product_bus[(r*COLS+CLUSTER_COLS+lc)*ACC_W +: ACC_W] = cluster1_all_mul_product_bus[(r*CLUSTER_COLS+lc)*ACC_W +: ACC_W];
            end
        end
    endgenerate

    // The controller-facing operand bus is split into local column banks
    // before entering either PE cluster.  Each bank now has only one row and
    // one eight-column destination, instead of feeding a 4-row crossbar.
    assign cluster0_ls_wide_a_row0_bus = ls_wide_a_row0_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_a_row1_bus = ls_wide_a_row1_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_a_row2_bus = ls_wide_a_row2_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_a_row3_bus = ls_wide_a_row3_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_a_row0_bus = ls_wide_a_row0_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_a_row1_bus = ls_wide_a_row1_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_a_row2_bus = ls_wide_a_row2_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_a_row3_bus = ls_wide_a_row3_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_b_row0_bus = ls_wide_b_row0_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_b_row1_bus = ls_wide_b_row1_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_b_row2_bus = ls_wide_b_row2_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster0_ls_wide_b_row3_bus = ls_wide_b_row3_bus[0 +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_b_row0_bus = ls_wide_b_row0_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_b_row1_bus = ls_wide_b_row1_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_b_row2_bus = ls_wide_b_row2_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];
    assign cluster1_ls_wide_b_row3_bus = ls_wide_b_row3_bus[CLUSTER_COLS*DATA_W +: CLUSTER_COLS*DATA_W];

    genvar cc_r;
    generate
        for (cc_r = 0; cc_r < ROWS; cc_r = cc_r + 1) begin : gen_column_connection
            pe_column_connection #(.DATA_W(DATA_W), .IDX_W(IDX_W)) u_cc (
                .west_to_east_data_i(cluster0_east_data_bus[cc_r*DATA_W +: DATA_W]),
                .west_to_east_idx_i(cluster0_east_idx_bus[cc_r*IDX_W +: IDX_W]),
                .east_to_west_data_i(cluster1_west_data_bus[cc_r*DATA_W +: DATA_W]),
                .east_to_west_idx_i(cluster1_west_idx_bus[cc_r*IDX_W +: IDX_W]),
                .west_to_east_data_o(cc_west_to_east_data[cc_r]),
                .west_to_east_idx_o(cc_west_to_east_idx[cc_r]),
                .east_to_west_data_o(cc_east_to_west_data[cc_r]),
                .east_to_west_idx_o(cc_east_to_west_idx[cc_r])
            );
        end
    endgenerate

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_cc_bus_pack
            assign cc_west_to_east_data_bus[r*DATA_W +: DATA_W] = cc_west_to_east_data[r];
            assign cc_east_to_west_data_bus[r*DATA_W +: DATA_W] = cc_east_to_west_data[r];
            assign cc_west_to_east_idx_bus[r*IDX_W +: IDX_W] = cc_west_to_east_idx[r];
            assign cc_east_to_west_idx_bus[r*IDX_W +: IDX_W] = cc_east_to_west_idx[r];
        end
    endgenerate

    generate
        for (c = 0; c < COLS; c = c + 1) begin : gen_outputs
            wire signed [64:0] corr_sum01 =
                $signed({tile_acc[c][63], tile_acc[c][63:0]}) +
                $signed({tile_acc[COLS+c][63], tile_acc[COLS+c][63:0]});
            wire signed [64:0] corr_sum23 =
                $signed({tile_acc[(2*COLS)+c][63], tile_acc[(2*COLS)+c][63:0]}) +
                $signed({tile_acc[(3*COLS)+c][63], tile_acc[(3*COLS)+c][63:0]});
            wire signed [65:0] corr_sum_all =
                $signed({corr_sum01[64], corr_sum01}) +
                $signed({corr_sum23[64], corr_sum23});
            // Classic mode sums all four sample-mod-4 partials.  Pair mode
            // reads one half at a time: rows {0,1} hold the first eight
            // super-block columns (split by sample parity) and rows {2,3}
            // the second eight, so each half needs a single 64-bit add.
            wire signed [64:0] corr_half_sel_sum =
                corr_half_sel ? corr_sum23 : corr_sum01;
            // The four-row correlation sum needs 66 bits; the controller
            // consumes a 64-bit word.  The truncation is exact for every
            // supported configuration (Q16 products of 24-bit operands
            // accumulated over M <= 64 samples stay far inside 64 bits), and
            // saturating here would only lengthen this output cone.  The
            // simulation check below guards the assumption instead.
`ifndef SYNTHESIS
            always @(posedge clk) begin
                if (rst_n && ((corr_sum_all[65] != corr_sum_all[63]) ||
                              (corr_sum_all[64] != corr_sum_all[63])))
                    $error("pearray: corr_sum_all overflowed 64 bits for column %0d (sum=%h)",
                           c, corr_sum_all);
            end
`endif
            assign reduce_data[c*DATA_W +: DATA_W] = tile_out[(ROWS-1)*COLS+c];
            assign acc_data[c*ACC_W +: ACC_W]      = tile_acc[(ROWS-1)*COLS+c];
            assign sparse_rhs_product_bus[c*64 +: 64] = (sparse_op == 4'd3) ?
                sparse_product_comb_bus[c*ACC_W +: 64] : tile_acc[c][63:0];
            assign corr_acc_bus[c*64 +: 64] = corr_pair_mode ? corr_half_sel_sum[63:0] :
                                                               corr_sum_all[63:0];
            assign spm_wdata[c*DATA_W +: DATA_W]   = tile_out[(ROWS-1)*COLS+c];
            assign spm_wen[c] = ctx_valid && spm_wr_en && lane_valid[c];
        end
    endgenerate

    generate
        for (c = 0; c < COLS; c = c + 1) begin : gen_mesh_ctx_commit_data
            if (c < CLUSTER_COLS) begin : gen_mesh_commit_cluster0
                assign mesh_ctx_commit_data[c*DATA_W +: DATA_W] =
                    cluster0_mesh_ctx_data_bus[(3*CLUSTER_COLS+c)*DATA_W +: DATA_W];
            end else begin : gen_mesh_commit_cluster1
                assign mesh_ctx_commit_data[c*DATA_W +: DATA_W] =
                    cluster1_mesh_ctx_data_bus[(3*CLUSTER_COLS+(c-CLUSTER_COLS))*DATA_W +: DATA_W];
            end
        end
    endgenerate
    // v3 result latch: argmax tree lands at column 0 of last row
    localparam integer RES_CELL = (ROWS-1)*COLS + 0;
    wire signed [DATA_W-1:0] res_data = tile_out[RES_CELL];
    assign result_value = {{(SCALAR_W-DATA_W){res_data[DATA_W-1]}}, res_data};
    assign result_idx   = idx_out[RES_CELL];
    assign result_flag  = tile_acc[RES_CELL][0];

    integer util_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            corr_slot_q <= 2'd0;
            if (ENABLE_DEBUG_COUNTERS) begin
                for (util_i = 0; util_i < ROWS; util_i = util_i + 1) row_exec_count[util_i] <= 32'd0;
                for (util_i = 0; util_i < COLS; util_i = util_i + 1) col_exec_count[util_i] <= 32'd0;
                phys_row0_pe_mac_count <= 32'd0;
                phys_row1_pe_accum_count <= 32'd0;
                phys_row2_pe_update_count <= 32'd0;
                phys_row0_nonzero_count <= 32'd0;
                phys_row1_nonzero_count <= 32'd0;
                phys_row2_nonzero_count <= 32'd0;
                phys_corr_row0_mac_count <= 32'd0;
                phys_corr_row1_accum_count <= 32'd0;
                phys_corr_row2_update_count <= 32'd0;
                phys_corr_row3_write_count <= 32'd0;
                phys_refine_row0_mac_count <= 32'd0;
                phys_refine_row1_accum_count <= 32'd0;
                phys_refine_row2_update_count <= 32'd0;
            end
        end else begin
            if (corr_acc_clear)
                corr_slot_q <= 2'd0;
            else if (corr_acc_en)
                corr_slot_q <= corr_slot_q + 2'd1;
            if (ENABLE_DEBUG_COUNTERS && ctx_valid) begin
                for (util_i = 0; util_i < ROWS; util_i = util_i + 1)
                    if (row_en[util_i]) row_exec_count[util_i] <= row_exec_count[util_i] + 1'b1;
                for (util_i = 0; util_i < COLS; util_i = util_i + 1)
                    if (lane_valid[util_i]) col_exec_count[util_i] <= col_exec_count[util_i] + 1'b1;
            end
            if (ENABLE_DEBUG_COUNTERS && sparse_active) begin
                row_exec_count[0] <= row_exec_count[0] + 1'b1;
                row_exec_count[1] <= row_exec_count[1] + 1'b1;
                row_exec_count[2] <= row_exec_count[2] + 1'b1;
                row_exec_count[ROWS-1] <= row_exec_count[ROWS-1] + 1'b1;
                for (util_i = 0; util_i < COLS; util_i = util_i + 1) begin
                    if (sparse_k_active > util_i) begin
                        col_exec_count[util_i] <= col_exec_count[util_i] + 1'b1;
                    end
                end
            end
            if (ENABLE_DEBUG_COUNTERS && sparse_active) begin
                if ((sparse_op == 4'd1) && corr_acc_en) begin
                    case (corr_slot_q)
                        2'd0: phys_corr_row0_mac_count <= phys_corr_row0_mac_count + 1'b1;
                        2'd1: phys_corr_row1_accum_count <= phys_corr_row1_accum_count + 1'b1;
                        2'd2: phys_corr_row2_update_count <= phys_corr_row2_update_count + 1'b1;
                        default: phys_corr_row3_write_count <= phys_corr_row3_write_count + 1'b1;
                    endcase
                end else if (sparse_op == 4'd0) begin
                    phys_row0_pe_mac_count <= phys_row0_pe_mac_count + 1'b1;
                    phys_row1_pe_accum_count <= phys_row1_pe_accum_count + 1'b1;
                    phys_row2_pe_update_count <= phys_row2_pe_update_count + 1'b1;
                    phys_refine_row0_mac_count <= phys_refine_row0_mac_count + 1'b1;
                    phys_refine_row1_accum_count <= phys_refine_row1_accum_count + 1'b1;
                    phys_refine_row2_update_count <= phys_refine_row2_update_count + 1'b1;
                end
                for (util_i = 0; util_i < COLS; util_i = util_i + 1) begin
                    if ((sparse_k_active > util_i) && (tile_out[util_i] != {DATA_W{1'b0}}))
                        phys_row0_nonzero_count <= phys_row0_nonzero_count + 1'b1;
                    if ((sparse_k_active > util_i) && (tile_out[COLS + util_i] != {DATA_W{1'b0}}))
                        phys_row1_nonzero_count <= phys_row1_nonzero_count + 1'b1;
                    if ((sparse_k_active > util_i) && (tile_out[(2*COLS) + util_i] != {DATA_W{1'b0}}))
                        phys_row2_nonzero_count <= phys_row2_nonzero_count + 1'b1;
                end
            end
        end
    end
    reg compute_done_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mesh_keepalive_q <= 4'b0000;
        else
            mesh_keepalive_q <= {mesh_keepalive_q[2:0], mesh_active_req};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            compute_done_q <= 1'b0;
        else
            compute_done_q <= ctx_valid;
    end

    assign compute_done = compute_done_q;
    assign result_valid = compute_done_q;

endmodule
















