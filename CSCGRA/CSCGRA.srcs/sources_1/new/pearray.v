(* keep_hierarchy = "yes" *)
module pearray #(
    parameter integer ROWS   = 4,
    parameter integer COLS   = 8,
    parameter integer DATA_W = 24,
    parameter integer ACC_W  = 48,
    parameter integer CTX_W  = 64,
    parameter integer SCALAR_W = 56,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W  = 10,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer ENABLE_DEBUG_COUNTERS = 0
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       ctx_valid,
    input  wire [CTX_W-1:0]           ctx_word,
    input  wire [COLS-1:0]            lane_valid,
    input  wire [IDX_W-1:0]           base_idx,
    input  wire                       first_in_phase,

    input  wire [COLS*DATA_W-1:0]     spm_a_rdata,
    input  wire [COLS*DATA_W-1:0]     spm_b_rdata,
    input  wire [COLS*DATA_W-1:0]     phi_bus,
    input  wire [COLS*DATA_W-1:0]     scalar_bus,

    input  wire                       sparse_active,
    input  wire                       sparse_step_active,
    input  wire                       sparse_clear,
    input  wire [3:0]                 sparse_op,
    input  wire [7:0]                 sparse_k_active,

    output wire [COLS*DATA_W-1:0]     spm_wdata,
    output wire [COLS-1:0]            spm_wen,

    output wire [COLS*DATA_W-1:0]     reduce_data,
    output wire [COLS*ACC_W-1:0]      acc_data,
    output wire [COLS*64-1:0]         sparse_rhs_product_bus,
    output wire [COLS*64-1:0]         corr_acc_bus,
    // v3 result interface (replaces external reduction_unit / scalar_unit latch)
    output wire [SCALAR_W-1:0]        result_value,
    output wire [IDX_W-1:0]           result_idx,
    output wire                       result_flag,
    output wire                       result_valid,
    output wire                       compute_done
);

    wire [4:0]  pe_op;
    wire [2:0]  src_a_sel;
    wire [2:0]  src_b_sel;
    wire [1:0]  rf_rd_addr;
    wire [1:0]  rf_wr_addr;
    wire        rf_wr_en;
    wire        acc_clear;
    wire        acc_en;
    wire [3:0]  out_sel;
    wire        spm_wr_en;
    wire [2:0]  spm_wr_data_sel;
    wire [2:0]  sb_sel;
    wire        sb_sel_en;
    wire [3:0]  row_en;
    wire [15:0] imm16;
    wire [3:0]  ext_ctrl;

    ctx_decoder #(.CTX_W(CTX_W)) u_decode (
        .ctx(ctx_word),
        .pe_op(pe_op),
        .src_a_sel(src_a_sel),
        .src_b_sel(src_b_sel),
        .rf_rd_addr(rf_rd_addr),
        .rf_wr_addr(rf_wr_addr),
        .rf_wr_en(rf_wr_en),
        .acc_clear(acc_clear),
        .acc_en(acc_en),
        .out_sel(out_sel),
        .spm_wr_en(spm_wr_en),
        .spm_wr_data_sel(spm_wr_data_sel),
        .sb_sel(sb_sel),
        .sb_sel_en(sb_sel_en),
        .row_en(row_en),
        .imm16(imm16),
        .lane_mask_lit(),
        .lane_mask_mode(),
        .ext_ctrl(ext_ctrl),
        .ctx_ver(),
        .uop_class(),
        .repeat_sel(),
        .addr_dim(),
        .spm_a_vec(),
        .spm_b_vec(),
        .spm_w_vec(),
        .spm_addr_mode(),
        .abs_addr(),
        .lfsr_ctrl(),
        .reduce_op(),
        .reduce_src_vec(),
        .reduce_dst(),
        .scalar_op(),
        .next_ctrl(),
        .ctx_version_ok(),
        .ctx_decode_error()
    );


    // Sparse loop control lives above pearray; pearray remains compute fabric.
    localparam CELLS = ROWS * COLS;

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
    reg [3:0] mesh_keepalive_q;
    reg [3:0] sparse_step_pipe_q;
    wire mesh_active_req = ctx_valid | sparse_active;
    reg [31:0] row_exec_count [0:ROWS-1];
    reg [31:0] col_exec_count [0:COLS-1];
    reg [31:0] phys_row0_pe_mac_count;
    reg [31:0] phys_row1_pe_accum_count;
    reg [31:0] phys_row2_pe_forward_count;
    reg [31:0] phys_row0_nonzero_count;
    reg [31:0] phys_row1_nonzero_count;
    reg [31:0] phys_row2_nonzero_count;
    reg [31:0] phys_corr_row0_mac_count;
    reg [31:0] phys_corr_row1_accum_count;
    reg [31:0] phys_corr_row2_forward_count;
    reg [31:0] phys_refine_row0_mac_count;
    reg [31:0] phys_refine_row1_accum_count;
    reg [31:0] phys_refine_row2_forward_count;

    genvar r;
    genvar c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_mesh_r
            for (c = 0; c < COLS; c = c + 1) begin : gen_mesh_c
                assign inN[r*COLS+c] = (r == 0)      ? {DATA_W{1'b0}} : outS[(r-1)*COLS+c];
                assign inS[r*COLS+c] = (r == ROWS-1) ? {DATA_W{1'b0}} : outN[(r+1)*COLS+c];
                assign inE[r*COLS+c] = (c == COLS-1) ? {DATA_W{1'b0}} : outW[r*COLS+(c+1)];
                assign inW[r*COLS+c] = (c == 0)      ? {DATA_W{1'b0}} : outE[r*COLS+(c-1)];

                wire [IDX_W-1:0] idx_self = base_idx + c[IDX_W-1:0];
                wire [IDX_W-1:0] idxE_in  = (c == COLS-1) ? idx_self : idxW_out[r*COLS+(c+1)];
                wire [IDX_W-1:0] idxW_in  = (c == 0)      ? idx_self : idxE_out[r*COLS+(c-1)];
                wire phys_ls_pe_active = sparse_active && (r < ROWS-1) && ((sparse_op == 4'd1) || (sparse_k_active > c)) && ((sparse_op == 4'd0) || (sparse_op == 4'd1));
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
                begin : gen_regular_tiles
                    (* dont_touch = "yes" *) pe_tile #(
                        .DATA_W(DATA_W),
                        .ACC_W(ACC_W),
                        .Q_FRAC_W(Q_FRAC_W),
                        .IDX_W(IDX_W),
                        .SCALAR_FN((c == 0) ? 1 : 0),
                        .PIPE_MESH(1), .PIPE_CORE_IN(1), .FULL_OUT_MUX((r == ROWS-1) ? 1 : 0)
                    ) u_tile (
                        .clk(clk),
                        .rst_n(rst_n),
                        .tile_en(tile_en),
                        .inN(inN[r*COLS+c]),
                        .inS(inS[r*COLS+c]),
                        .inE(inE[r*COLS+c]),
                        .inW(inW[r*COLS+c]),
                        .idxE_in(idxE_in),
                        .idxW_in(idxW_in),
                        .idx_self(idx_self),
                        .spm_a_data(spm_a_rdata[c*DATA_W +: DATA_W]),
                        .spm_b_data(spm_b_rdata[c*DATA_W +: DATA_W]),
                        .phi_data(phi_bus[c*DATA_W +: DATA_W]),
                        .colbus_data((r == ROWS-1) ? colbus_r0[c] : {DATA_W{1'b0}}),
                        .scalar_data(scalar_bus[c*DATA_W +: DATA_W]),
                        .imm16(tile_imm16),
                        .pe_op(tile_pe_op),
                        .src_a_sel(tile_src_a_sel),
                        .src_b_sel(tile_src_b_sel),
                        .rf_rd_addr(rf_rd_addr),
                        .rf_wr_addr(rf_wr_addr),
                        .rf_wr_en(ctx_valid && row_en[r] && lane_valid[c] && rf_wr_en),
                        .acc_clear(tile_acc_clear),
                        .acc_en(tile_acc_en),
                        .sb_sel(tile_sb_sel),
                        .sb_sel_en(tile_sb_sel_en),
                        .out_sel(tile_out_sel),
                        .ext_b_is_scalar(tile_ext_b_is_scalar),
                        .outN(outN[r*COLS+c]),
                        .outS(outS[r*COLS+c]),
                        .outE(outE[r*COLS+c]),
                        .outW(outW[r*COLS+c]),
                        .idxE_out(idxE_out[r*COLS+c]),
                        .idxW_out(idxW_out[r*COLS+c]),
                        .pe_data_out(tile_out[r*COLS+c]),
                        .idx_out(idx_out[r*COLS+c]),
                        .acc_out(tile_acc[r*COLS+c])
                    );
                end

                if (r == 0) begin : gen_colbus
                    assign colbus_r0[c] = tile_out[r*COLS+c];
                end
            end
        end
    endgenerate
    generate
        for (c = 0; c < COLS; c = c + 1) begin : gen_outputs
            assign reduce_data[c*DATA_W +: DATA_W] = tile_out[(ROWS-1)*COLS+c];
            assign acc_data[c*ACC_W +: ACC_W]      = tile_acc[(ROWS-1)*COLS+c];
            assign sparse_rhs_product_bus[c*64 +: 64] = tile_acc[c][63:0];
            assign corr_acc_bus[c*64 +: 64] = tile_acc[c][63:0];
            assign spm_wdata[c*DATA_W +: DATA_W]   = tile_out[(ROWS-1)*COLS+c];
            assign spm_wen[c] = ctx_valid && spm_wr_en && lane_valid[c];
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
            sparse_step_pipe_q <= 4'b0000;
            if (ENABLE_DEBUG_COUNTERS) begin
                for (util_i = 0; util_i < ROWS; util_i = util_i + 1) row_exec_count[util_i] <= 32'd0;
                for (util_i = 0; util_i < COLS; util_i = util_i + 1) col_exec_count[util_i] <= 32'd0;
                phys_row0_pe_mac_count <= 32'd0;
                phys_row1_pe_accum_count <= 32'd0;
                phys_row2_pe_forward_count <= 32'd0;
                phys_row0_nonzero_count <= 32'd0;
                phys_row1_nonzero_count <= 32'd0;
                phys_row2_nonzero_count <= 32'd0;
                phys_corr_row0_mac_count <= 32'd0;
                phys_corr_row1_accum_count <= 32'd0;
                phys_corr_row2_forward_count <= 32'd0;
                phys_refine_row0_mac_count <= 32'd0;
                phys_refine_row1_accum_count <= 32'd0;
                phys_refine_row2_forward_count <= 32'd0;
            end
        end else begin
            if (sparse_clear)
                sparse_step_pipe_q <= 4'b0000;
            else
                sparse_step_pipe_q <= {sparse_step_pipe_q[2:0], sparse_step_active && (sparse_op == 4'd1)};
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
                phys_row0_pe_mac_count <= phys_row0_pe_mac_count + 1'b1;
                phys_row1_pe_accum_count <= phys_row1_pe_accum_count + 1'b1;
                phys_row2_pe_forward_count <= phys_row2_pe_forward_count + 1'b1;
                if (sparse_op == 4'd1) begin
                    phys_corr_row0_mac_count <= phys_corr_row0_mac_count + 1'b1;
                    phys_corr_row1_accum_count <= phys_corr_row1_accum_count + 1'b1;
                    phys_corr_row2_forward_count <= phys_corr_row2_forward_count + 1'b1;
                end else if (sparse_op == 4'd0) begin
                    phys_refine_row0_mac_count <= phys_refine_row0_mac_count + 1'b1;
                    phys_refine_row1_accum_count <= phys_refine_row1_accum_count + 1'b1;
                    phys_refine_row2_forward_count <= phys_refine_row2_forward_count + 1'b1;
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








