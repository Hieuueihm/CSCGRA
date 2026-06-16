(* keep_hierarchy = "yes" *)
module pe_cluster_4x4 #(
    parameter integer COL_OFFSET = 0,
    parameter integer ROWS   = 4,
    parameter integer DATA_W = 24,
    parameter integer ACC_W  = 64,
    parameter integer IDX_W  = 10,
    parameter integer Q_FRAC_W = DATA_W - 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     ctx_valid,
    input  wire [3:0]               lane_valid,
    input  wire [IDX_W-1:0]         base_idx,
    input  wire                     first_in_phase,
    input  wire [4:0]               pe_op,
    input  wire [2:0]               src_a_sel,
    input  wire [2:0]               src_b_sel,
    input  wire [1:0]               rf_rd_addr,
    input  wire [1:0]               rf_wr_addr,
    input  wire                     rf_wr_en,
    input  wire                     acc_clear,
    input  wire                     acc_en,
    input  wire [3:0]               out_sel,
    input  wire [2:0]               sb_sel,
    input  wire                     sb_sel_en,
    input  wire [3:0]               row_en,
    input  wire [15:0]              imm16,
    input  wire [3:0]               ext_ctrl,
    input  wire [3:0]               mesh_keepalive_q,
    input  wire [4*DATA_W-1:0]      spm_a_rdata,
    input  wire [4*DATA_W-1:0]      spm_b_rdata,
    input  wire [4*DATA_W-1:0]      phi_bus,
    input  wire [4*DATA_W-1:0]      scalar_bus,
    input  wire                     sparse_active,
    input  wire [3:0]               sparse_op,
    input  wire [7:0]               sparse_k_active,
    input  wire [ROWS*DATA_W-1:0]   west_data_in,
    input  wire [ROWS*DATA_W-1:0]   east_data_in,
    input  wire [ROWS*IDX_W-1:0]    west_idx_in,
    input  wire [ROWS*IDX_W-1:0]    east_idx_in,
    output wire [ROWS*DATA_W-1:0]   west_data_out,
    output wire [ROWS*DATA_W-1:0]   east_data_out,
    output wire [ROWS*IDX_W-1:0]    west_idx_out,
    output wire [ROWS*IDX_W-1:0]    east_idx_out,
    output wire [ROWS*4*DATA_W-1:0] tile_out_bus,
    output wire [ROWS*4*ACC_W-1:0]  tile_acc_bus,
    output wire [ROWS*4*IDX_W-1:0]  idx_out_bus
);
    localparam integer COLS = 4;
    localparam integer CELLS = ROWS * COLS;

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

    genvar r;
    genvar c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_r
            for (c = 0; c < COLS; c = c + 1) begin : gen_c
                localparam integer GC = COL_OFFSET + c;
                assign inN[r*COLS+c] = (r == 0)      ? {DATA_W{1'b0}} : outS[(r-1)*COLS+c];
                assign inS[r*COLS+c] = (r == ROWS-1) ? {DATA_W{1'b0}} : outN[(r+1)*COLS+c];
                assign inE[r*COLS+c] = (c == COLS-1) ? east_data_in[r*DATA_W +: DATA_W] : outW[r*COLS+(c+1)];
                assign inW[r*COLS+c] = (c == 0)      ? west_data_in[r*DATA_W +: DATA_W] : outE[r*COLS+(c-1)];

                wire [IDX_W-1:0] idx_self = base_idx + GC[IDX_W-1:0];
                wire [IDX_W-1:0] idxE_in  = (c == COLS-1) ? east_idx_in[r*IDX_W +: IDX_W] : idxW_out[r*COLS+(c+1)];
                wire [IDX_W-1:0] idxW_in  = (c == 0)      ? west_idx_in[r*IDX_W +: IDX_W] : idxE_out[r*COLS+(c-1)];
                wire phys_ls_pe_active = sparse_active && (r < ROWS-1) && (sparse_k_active > GC) && ((sparse_op == 4'd0) || (sparse_op == 4'd1));
                wire [4:0] tile_pe_op = phys_ls_pe_active ? ((r == 0) ? 5'd0 : ((r == 1) ? 5'd1 : 5'd7)) : pe_op;
                wire [2:0] tile_src_a_sel = phys_ls_pe_active ? ((r == 0) ? 3'd7 : 3'd0) : src_a_sel;
                wire [2:0] tile_src_b_sel = phys_ls_pe_active ? ((r == 0) ? 3'd7 : ((r == 1) ? 3'd5 : 3'd5)) : src_b_sel;
                wire [15:0] tile_imm16 = phys_ls_pe_active ? ((r == 0) ? 16'h4000 : 16'h0001) : imm16;
                wire tile_acc_clear = phys_ls_pe_active ? (r == 0) : (ctx_valid && row_en[r] && acc_clear && first_in_phase);
                wire tile_acc_en = phys_ls_pe_active ? (r == 0) : (ctx_valid && row_en[r] && lane_valid[c] && acc_en);
                wire tile_sb_sel_en = phys_ls_pe_active ? 1'b1 : (sb_sel_en && row_en[r]);
                wire [2:0] tile_sb_sel = phys_ls_pe_active ? 3'd4 : sb_sel;
                wire [3:0] tile_out_sel = phys_ls_pe_active ? ((r == 0) ? 4'd0 : 4'd0) : out_sel;
                wire tile_ext_b_is_scalar = phys_ls_pe_active ? (r == 0) : ext_ctrl[0];
                wire tile_en = (ctx_valid && row_en[r] && lane_valid[c]) || phys_ls_pe_active || (|mesh_keepalive_q);

                (* dont_touch = "yes" *) pe_tile #(
                    .DATA_W(DATA_W), .ACC_W(ACC_W), .Q_FRAC_W(Q_FRAC_W), .IDX_W(IDX_W),
                    .SCALAR_FN((GC == 0) ? 1 : 0), .PIPE_MESH(1), .PIPE_CORE_IN(1), .FULL_OUT_MUX((r == ROWS-1) ? 1 : 0)
                ) u_tile (
                    .clk(clk), .rst_n(rst_n), .tile_en(tile_en),
                    .inN(inN[r*COLS+c]), .inS(inS[r*COLS+c]), .inE(inE[r*COLS+c]), .inW(inW[r*COLS+c]),
                    .idxE_in(idxE_in), .idxW_in(idxW_in), .idx_self(idx_self),
                    .spm_a_data(spm_a_rdata[c*DATA_W +: DATA_W]), .spm_b_data(spm_b_rdata[c*DATA_W +: DATA_W]),
                    .phi_data(phi_bus[c*DATA_W +: DATA_W]), .colbus_data((r == ROWS-1) ? colbus_r0[c] : {DATA_W{1'b0}}),
                    .scalar_data(scalar_bus[c*DATA_W +: DATA_W]), .imm16(tile_imm16),
                    .pe_op(tile_pe_op), .src_a_sel(tile_src_a_sel), .src_b_sel(tile_src_b_sel),
                    .rf_rd_addr(rf_rd_addr), .rf_wr_addr(rf_wr_addr), .rf_wr_en(ctx_valid && row_en[r] && lane_valid[c] && rf_wr_en),
                    .acc_clear(tile_acc_clear), .acc_en(tile_acc_en), .sb_sel(tile_sb_sel), .sb_sel_en(tile_sb_sel_en),
                    .out_sel(tile_out_sel), .ext_b_is_scalar(tile_ext_b_is_scalar),
                    .outN(outN[r*COLS+c]), .outS(outS[r*COLS+c]), .outE(outE[r*COLS+c]), .outW(outW[r*COLS+c]),
                    .idxE_out(idxE_out[r*COLS+c]), .idxW_out(idxW_out[r*COLS+c]),
                    .pe_data_out(tile_out[r*COLS+c]), .idx_out(idx_out[r*COLS+c]), .acc_out(tile_acc[r*COLS+c])
                );

                assign tile_out_bus[(r*COLS+c)*DATA_W +: DATA_W] = tile_out[r*COLS+c];
                assign tile_acc_bus[(r*COLS+c)*ACC_W +: ACC_W] = tile_acc[r*COLS+c];
                assign idx_out_bus[(r*COLS+c)*IDX_W +: IDX_W] = idx_out[r*COLS+c];
            end
            assign west_data_out[r*DATA_W +: DATA_W] = outE[r*COLS+0];
            assign east_data_out[r*DATA_W +: DATA_W] = outW[r*COLS+(COLS-1)];
            assign west_idx_out[r*IDX_W +: IDX_W] = idxE_out[r*COLS+0];
            assign east_idx_out[r*IDX_W +: IDX_W] = idxW_out[r*COLS+(COLS-1)];
        end
        for (c = 0; c < COLS; c = c + 1) begin : gen_colbus
            assign colbus_r0[c] = tile_out[c];
        end
    endgenerate
endmodule
