module ctx_decoder #(
    parameter integer CTX_W = 64
)(
    input  wire [CTX_W-1:0] ctx,

    output wire [3:0]       pe_op,
    output wire [2:0]       src_a_sel,
    output wire [2:0]       src_b_sel,
    output wire [1:0]       rf_rd_addr,
    output wire [1:0]       rf_wr_addr,
    output wire             rf_wr_en,
    output wire             acc_clear,
    output wire             acc_en,
    output wire [3:0]       out_sel,
    output wire             spm_wr_en,
    output wire [2:0]       spm_wr_data_sel,
    output wire [2:0]       sb_sel,
    output wire             sb_sel_en,
    output wire [3:0]       row_en,
    output wire [15:0]      imm16,
    output wire [7:0]       lane_mask_lit,
    output wire [3:0]       lane_mask_mode,
    output wire [3:0]       ext_ctrl,

    output wire [3:0]       ctx_ver,
    output wire [3:0]       uop_class,
    output wire [3:0]       repeat_sel,
    output wire [3:0]       addr_dim,
    output wire [2:0]       spm_a_vec,
    output wire [2:0]       spm_b_vec,
    output wire [2:0]       spm_w_vec,
    output wire [2:0]       spm_addr_mode,
    output wire [9:0]       abs_addr,
    output wire [3:0]       lfsr_ctrl,
    output wire [2:0]       reduce_src_vec,
    output wire [2:0]       reduce_dst,
    output wire [7:0]       scalar_op,
    output wire [3:0]       next_ctrl,

    output wire             ctx_version_ok,
    output wire             ctx_decode_error
);

    wire pe_addr_fmt;
    wire pe_imm_fmt;
    wire reduce_fmt;
    wire candidate_fmt;
    wire dma_fmt;
    wire scalar_fmt;
    wire bitmap_fmt;
    wire reserved_uop;
    wire reserved_repeat;
    wire reserved_addr_dim;
    wire reserved_addr_mode;
    wire support_mask_on_m_vec;

    assign ctx_ver    = ctx[63:60];
    assign uop_class  = ctx[59:56];
    assign repeat_sel = ctx[55:52];
    assign addr_dim   = ctx[51:48];
    assign next_ctrl  = ctx[47:44];

    assign pe_addr_fmt = (uop_class == 4'd1) ||
                         (uop_class == 4'd2) ||
                         (uop_class == 4'd3) ||
                         (uop_class == 4'd5);
    assign pe_imm_fmt  = (uop_class == 4'd0);
    assign reduce_fmt  = (uop_class == 4'd4);
    assign candidate_fmt = (uop_class == 4'd6);
    assign dma_fmt     = (uop_class == 4'd7);
    assign scalar_fmt  = (uop_class == 4'd8);
    assign bitmap_fmt  = (uop_class == 4'd9);

    assign imm16 = (pe_imm_fmt || scalar_fmt) ? ctx[43:28] : 16'd0;

    assign pe_op      = (pe_addr_fmt || pe_imm_fmt) ? {ctx[2], ctx[15:13]} : 4'd0;
    assign src_a_sel  = (pe_addr_fmt || pe_imm_fmt) ? ctx[12:10] : 3'd0;
    assign src_b_sel  = (pe_addr_fmt || pe_imm_fmt) ? ctx[9:7]   : 3'd0;
    assign out_sel    = (pe_addr_fmt || pe_imm_fmt) ? {1'b0, ctx[6:4]} : 4'd0;
    assign rf_wr_en   = (pe_addr_fmt || pe_imm_fmt) ? ctx[3]    : 1'b0;
    assign rf_rd_addr = (pe_addr_fmt || pe_imm_fmt) ? ctx[1:0]  : 2'd0;
    assign rf_wr_addr = rf_rd_addr;
    assign acc_clear  = (pe_addr_fmt || pe_imm_fmt) ? ctx[22]   : 1'b0;
    assign acc_en     = (pe_addr_fmt || pe_imm_fmt) ? ctx[21]   : 1'b0;
    assign spm_wr_en  = (pe_addr_fmt || pe_imm_fmt) ? ctx[23]   : 1'b0;
    assign spm_wr_data_sel = 3'd0;

    assign ext_ctrl = scalar_fmt ? ctx[19:16] :
                      (candidate_fmt ? ctx[19:16] :
                      (bitmap_fmt ? {1'b0, ctx[2:0]} :
                      ((pe_addr_fmt || pe_imm_fmt) ? {3'd0, ctx[20]} : 4'd0)));

    assign sb_sel_en = (pe_addr_fmt || pe_imm_fmt) ? ctx[19]    : 1'b0;
    assign sb_sel    = (pe_addr_fmt || pe_imm_fmt) ? ctx[18:16] : 3'd4;
    assign row_en    = (pe_addr_fmt || pe_imm_fmt) ? ctx[27:24] : 4'h0;

    assign spm_a_vec = (pe_addr_fmt || reduce_fmt || dma_fmt) ? ctx[43:41] :
                       (scalar_fmt ? ctx[9:7] : 3'd0);
    assign spm_b_vec = (pe_addr_fmt || reduce_fmt) ? ctx[40:38] : 3'd0;
    assign spm_w_vec = (pe_addr_fmt || reduce_fmt) ? ctx[37:35] : 3'd0;

    assign lane_mask_mode = (pe_addr_fmt || reduce_fmt) ? {1'b0, ctx[34:32]} : 4'd0;
    assign lfsr_ctrl      = (pe_addr_fmt || reduce_fmt) ? ctx[31:28] : 4'd0;
    assign lane_mask_lit = reduce_fmt ? ctx[23:16] : 8'd0;
    assign spm_addr_mode = reduce_fmt ? ctx[15:13] : 3'd0;
    assign abs_addr      = reduce_fmt ? ctx[12:3]  : 10'd0;

    assign reduce_src_vec = scalar_fmt ? ctx[12:10] : 3'd0;
    assign reduce_dst     = scalar_fmt ? ctx[15:13] : 3'd0;
    assign scalar_op      = scalar_fmt ? ctx[27:20] : 8'd0;

    assign ctx_version_ok = (ctx_ver == 4'h1);

    assign reserved_uop       = (uop_class > 4'd9);
    assign reserved_repeat    = (repeat_sel > 4'd7);
    assign reserved_addr_dim  = (addr_dim > 4'd4);
    assign reserved_addr_mode = 1'b0;
    assign support_mask_on_m_vec = ((lane_mask_mode == 4'd1) ||
                                    (lane_mask_mode == 4'd4)) &&
                                   (addr_dim == 4'd1);

    assign ctx_decode_error = !ctx_version_ok        ||
                              reserved_uop           ||
                              reserved_repeat        ||
                              reserved_addr_dim      ||
                              reserved_addr_mode     ||
                              support_mask_on_m_vec;

endmodule

