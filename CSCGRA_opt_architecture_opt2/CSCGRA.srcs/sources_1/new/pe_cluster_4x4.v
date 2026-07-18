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
    input  wire [3:0] sparse_op,
    input  wire [7:0] sparse_k_active,
    input  wire [3:0] mesh_keepalive,
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
    output wire [ROWS*CLUSTER_COLS*IDX_W-1:0] idx_out_bus,
    output wire [CLUSTER_COLS*DATA_W-1:0] colbus_r0_bus,
    output wire [CLUSTER_COLS*ACC_W-1:0] sparse_product_comb_bus
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

    genvar r;
    genvar lc;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_r
            for (lc = 0; lc < CLUSTER_COLS; lc = lc + 1) begin : gen_c
                localparam integer CELL = r*CLUSTER_COLS + lc;
                localparam integer GLOBAL_C = COL_OFFSET + lc;
                wire [IDX_W-1:0] idx_self = base_idx + GLOBAL_C[IDX_W-1:0];
                assign inN[CELL] = (r == 0) ? {DATA_W{1'b0}} : outS[(r-1)*CLUSTER_COLS+lc];
                assign inS[CELL] = (r == ROWS-1) ? {DATA_W{1'b0}} : outN[(r+1)*CLUSTER_COLS+lc];
                assign inE[CELL] = (lc == CLUSTER_COLS-1) ? east_boundary_data_i[r*DATA_W +: DATA_W] : outW[r*CLUSTER_COLS+(lc+1)];
                assign inW[CELL] = (lc == 0) ? west_boundary_data_i[r*DATA_W +: DATA_W] : outE[r*CLUSTER_COLS+(lc-1)];
                wire [IDX_W-1:0] idxE_in = (lc == CLUSTER_COLS-1) ? east_boundary_idx_i[r*IDX_W +: IDX_W] : idxW_out[r*CLUSTER_COLS+(lc+1)];
                wire [IDX_W-1:0] idxW_in = (lc == 0) ? west_boundary_idx_i[r*IDX_W +: IDX_W] : idxE_out[r*CLUSTER_COLS+(lc-1)];
                wire phys_ls_pe_active = sparse_active && (r < ROWS-1) && ((sparse_op == 4'd1) || (sparse_k_active > GLOBAL_C)) && ((sparse_op == 4'd0) || (sparse_op == 4'd1));
                wire row0_mac_stage = phys_ls_pe_active && (r == 0);
                wire row1_accum_stage = phys_ls_pe_active && (r == 1);
                wire row2_update_stage = phys_ls_pe_active && (r == 2);
                wire mesh_ctx_active = ctx_valid && (mesh_ctx_mode != MESH_CTX_NONE);
                wire [3:0] mesh_ctx_row_op =
                    (mesh_ctx_mode == MESH_CTX_UPDATE) ? (r == 1 ? OP_ADD : OP_PASS) :
                    (mesh_ctx_mode == MESH_CTX_PRUNE)  ? (r == 0 ? OP_ABS : OP_PASS) :
                    (mesh_ctx_mode == MESH_CTX_RESID)  ? (r == 1 ? OP_SUB : OP_PASS) : OP_PASS;
                wire [3:0] tile_pe_op = mesh_ctx_active ? mesh_ctx_row_op : (phys_ls_pe_active ? (row0_mac_stage ? 4'd0 : (row1_accum_stage ? 4'd1 : 4'd8)) : pe_op);
                wire [2:0] tile_src_a_sel = phys_ls_pe_active ? (row0_mac_stage ? 3'd7 : 3'd0) : src_a_sel;
                wire [2:0] tile_src_b_sel = phys_ls_pe_active ? (row0_mac_stage ? 3'd7 : (row2_update_stage ? 3'd3 : 3'd5)) : src_b_sel;
                wire [15:0] tile_imm16 = phys_ls_pe_active ? (row0_mac_stage ? 16'h4000 : 16'h0001) : imm16;
                wire tile_acc_clear = phys_ls_pe_active ? (r == 0) : (ctx_valid && row_en[r] && acc_clear && first_in_phase);
                wire tile_acc_en = phys_ls_pe_active ? (r == 0) : (ctx_valid && row_en[r] && lane_valid[lc] && acc_en);
                wire tile_sb_sel_en = phys_ls_pe_active ? 1'b1 : (sb_sel_en && row_en[r]);
                wire [2:0] tile_sb_sel = phys_ls_pe_active ? 3'd4 : sb_sel;
                wire [3:0] tile_out_sel = phys_ls_pe_active ? 4'd0 : out_sel;
                wire tile_ext_b_is_scalar = phys_ls_pe_active ? (r == 0) : ext_ctrl[0];
                wire tile_en = (ctx_valid && row_en[r] && lane_valid[lc]) || phys_ls_pe_active || (mesh_ctx_active && row_en[r]) || (|mesh_keepalive);

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
                    .inN(inN[CELL]), .inS(inS[CELL]), .inE(inE[CELL]), .inW(inW[CELL]),
                    .idxE_in(idxE_in), .idxW_in(idxW_in), .idx_self(idx_self),
                    .spm_a_data(spm_a_rdata[lc*DATA_W +: DATA_W]),
                    .spm_b_data(spm_b_rdata[lc*DATA_W +: DATA_W]),
                    .phi_data(phi_bus[lc*DATA_W +: DATA_W]),
                    .colbus_data((r == ROWS-1) ? colbus_r0[lc] : {DATA_W{1'b0}}),
                    .scalar_data(scalar_bus[lc*DATA_W +: DATA_W]),
                    .imm16(tile_imm16), .mesh_ctx_mode(mesh_ctx_mode), .pe_op(tile_pe_op),
                    .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift),
                    .mesh_ctx_x(mesh_ctx_x_bus[lc*DATA_W +: DATA_W]), .mesh_ctx_delta(mesh_ctx_delta_bus[lc*DATA_W +: DATA_W]), .mesh_ctx_keep(mesh_ctx_keep_bus[lc]),
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

                assign tile_out_bus[CELL*DATA_W +: DATA_W] = tile_out[CELL];
                assign mesh_ctx_data_bus[CELL*DATA_W +: DATA_W] = ENABLE_MESH_CTX ? tile_mesh_ctx[CELL] : {DATA_W{1'b0}};
                assign tile_acc_bus[CELL*ACC_W +: ACC_W] = tile_acc[CELL];
                assign idx_out_bus[CELL*IDX_W +: IDX_W] = idx_out[CELL];
                if (r == 0) begin : gen_colbus
                    assign colbus_r0[lc] = tile_out[CELL];
                    assign sparse_product_comb_bus[lc*ACC_W +: ACC_W] = tile_mul_product[CELL];
                end
            end
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




