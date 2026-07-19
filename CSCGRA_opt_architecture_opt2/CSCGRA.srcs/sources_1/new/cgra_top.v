module cgra_top #(
    parameter integer ROWS       = 4,
    parameter integer COLS       = 8,
    parameter integer DATA_W     = 24,
    parameter integer ACC_W      = 64,
    parameter integer SCALAR_W   = 56,
    parameter integer MEM_AW     = 10,
    parameter integer IDX_W      = 10,
    parameter integer CTX_W      = 64,
    parameter integer NCTX       = 2048,
    parameter integer AXIL_AW    = 14,
    parameter integer AXIL_DW    = 32,
    parameter integer AXI_AW     = 32,
    parameter integer AXI_DW     = 32,
    parameter integer SPARSE_MAX_M = 128,
    parameter integer SPARSE_MAX_N = 256,
    parameter integer SPARSE_MAX_K = 16,
    parameter integer SPARSE_REFINE_ITERS = 128
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [AXIL_AW-1:0]    s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [AXIL_DW-1:0]    s_axi_wdata,
    input  wire [AXIL_DW/8-1:0]  s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [AXIL_AW-1:0]    s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [AXIL_DW-1:0]    s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,
    output wire [AXI_AW-1:0]     m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [AXI_DW-1:0]     m_axi_rdata,
    input  wire                  m_axi_rvalid,
    input  wire                  m_axi_rlast,
    output wire                  m_axi_rready,
    output wire [AXI_AW-1:0]     m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,
    output wire [AXI_DW-1:0]     m_axi_wdata,
    output wire [AXI_DW/8-1:0]   m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,
    output wire                  irq_done,
    output wire                  irq_error
);
    localparam integer CTX_AW = 11;
    localparam integer Q_FRAC_W = DATA_W - 8;

    wire rst_core_n;
    wire soft_reset_pulse;
    assign rst_core_n = rst_n & !soft_reset_pulse;

    wire start_pulse, clear_error_pulse;
    wire [IDX_W-1:0] m_size, n_size;
    wire [7:0] k_param;
    wire [15:0] max_iter;
    wire [31:0] tol_sq_q16_16, y_ddr_addr, x_ddr_addr, seed;
    wire [DATA_W-1:0] phi_scale_q8_8;
    wire [31:0] flags, dense_step_q16_16;
    wire [3:0] mu_shift_cfg;
    wire [DATA_W-1:0] dense_lambda_q8_8, dense_rho_q8_8, dense_theta_q8_8, dense_damp_q8_8;
    wire [CTX_AW-1:0] prog_base;
    wire [CTX_AW:0] prog_len;
    wire cfg_wr_en;
    wire [CTX_AW-1:0] cfg_wr_addr;
    wire cfg_wr_word;
    wire [AXIL_DW-1:0] cfg_wr_data;
    wire cfg_dbg_rd_en;
    wire [CTX_AW-1:0] cfg_dbg_rd_addr;
    wire [CTX_W-1:0] cfg_dbg_rd_data;

    wire seq_busy, seq_done, seq_irq, seq_converged, seq_error;
    wire [3:0] seq_error_code;
    wire [CTX_AW-1:0] pc_dbg;
    reg [31:0] cycle_cnt;
    reg [31:0] result0_q;

    csr_regs #(.AXIL_AW(AXIL_AW), .AXIL_DW(AXIL_DW), .CTX_W(CTX_W), .CTX_AW(CTX_AW),
        .IDX_W(IDX_W), .DATA_W(DATA_W), .Q_FRAC_W(Q_FRAC_W)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .start_pulse(start_pulse), .soft_reset_pulse(soft_reset_pulse), .clear_error_pulse(clear_error_pulse),
        .m_size(m_size), .n_size(n_size), .k_param(k_param), .max_iter(max_iter), .tol_sq_q16_16(tol_sq_q16_16),
        .y_ddr_addr(y_ddr_addr), .x_ddr_addr(x_ddr_addr), .seed(seed), .phi_scale_q8_8(phi_scale_q8_8),
        .flags(flags), .mu_shift_cfg(mu_shift_cfg), .dense_step_q16_16(dense_step_q16_16), .dense_lambda_q8_8(dense_lambda_q8_8),
        .dense_rho_q8_8(dense_rho_q8_8), .dense_theta_q8_8(dense_theta_q8_8), .dense_damp_q8_8(dense_damp_q8_8),
        .prog_base(prog_base), .prog_len(prog_len), .busy(seq_busy), .done(seq_done), .converged(seq_converged),
        .error(seq_error), .error_code(seq_error_code), .result0(result0_q), .cycle_cnt(cycle_cnt), .pc_dbg(pc_dbg),
        .cfg_wr_en(cfg_wr_en), .cfg_wr_addr(cfg_wr_addr), .cfg_wr_word(cfg_wr_word), .cfg_wr_data(cfg_wr_data),
        .cfg_dbg_rd_en(cfg_dbg_rd_en), .cfg_dbg_rd_addr(cfg_dbg_rd_addr), .cfg_dbg_rd_data(cfg_dbg_rd_data)
    );

    wire [CTX_AW-1:0] seq_ctx_addr;
    wire [CTX_W-1:0] cfg_seq_ctx;
    wire [CTX_W-1:0] seq_ctx;
    assign seq_ctx = cfg_seq_ctx;

    configmem #(.NCTX(NCTX), .CTX_W(CTX_W), .CTX_AW(CTX_AW)) u_configmem (
        .clk(clk), .rst_n(rst_core_n), .wr_en(cfg_wr_en), .wr_addr(cfg_wr_addr), .wr_data(cfg_wr_data),
        .wr_word(cfg_wr_word), .seq_addr(seq_ctx_addr), .seq_ctx(cfg_seq_ctx),
        .dbg_rd_en(cfg_dbg_rd_en), .dbg_rd_addr(cfg_dbg_rd_addr), .dbg_rd_data(cfg_dbg_rd_data)
    );

    wire [3:0] pe_op;
    wire [2:0] src_a_sel, src_b_sel;
    wire [1:0] rf_rd_addr, rf_wr_addr;
    wire rf_wr_en, acc_clear, acc_en;
    wire [3:0] out_sel;
    wire spm_wr_en_dec;
    wire [2:0] spm_wr_data_sel, sb_sel;
    wire sb_sel_en;
    wire [3:0] row_en;
    wire [15:0] imm16;
    wire [7:0] lane_mask_lit;
    wire [3:0] lane_mask_mode, ext_ctrl, ctx_ver, uop_class, repeat_sel, addr_dim;
    wire [2:0] spm_a_vec, spm_b_vec, spm_w_vec, spm_addr_mode;
    wire [9:0] abs_addr;
    wire [3:0] lfsr_ctrl;
    wire [2:0] reduce_src_vec, reduce_dst;
    wire [7:0] scalar_op;
    wire [3:0] next_ctrl;
    wire ctx_decode_error;

    ctx_decoder #(.CTX_W(CTX_W)) u_decode (
        .ctx(seq_ctx), .pe_op(pe_op), .src_a_sel(src_a_sel), .src_b_sel(src_b_sel),
        .rf_rd_addr(rf_rd_addr), .rf_wr_addr(rf_wr_addr), .rf_wr_en(rf_wr_en),
        .acc_clear(acc_clear), .acc_en(acc_en), .out_sel(out_sel),
        .spm_wr_en(spm_wr_en_dec), .spm_wr_data_sel(spm_wr_data_sel), .sb_sel(sb_sel), .sb_sel_en(sb_sel_en),
        .row_en(row_en), .imm16(imm16), .lane_mask_lit(lane_mask_lit), .lane_mask_mode(lane_mask_mode),
        .ext_ctrl(ext_ctrl), .ctx_ver(ctx_ver), .uop_class(uop_class), .repeat_sel(repeat_sel),
        .addr_dim(addr_dim), .spm_a_vec(spm_a_vec), .spm_b_vec(spm_b_vec), .spm_w_vec(spm_w_vec),
        .spm_addr_mode(spm_addr_mode), .abs_addr(abs_addr), .lfsr_ctrl(lfsr_ctrl),
        .reduce_src_vec(reduce_src_vec), .reduce_dst(reduce_dst), .scalar_op(scalar_op), .next_ctrl(next_ctrl),
        .ctx_version_ok(), .ctx_decode_error(ctx_decode_error)
    );

    wire ctx_valid;
    wire [CTX_W-1:0] ctx_word;
    wire phase_start, support_clear_selected, ctx_done;
    wire dma_done, dma_error;
    wire [3:0] dma_error_code;
    wire compute_done;

    // v3/v5: vector math comes from pearray; class-4 reductions scan SPM data in top.
    wire [SCALAR_W-1:0] result_value;
    wire [IDX_W-1:0]    result_idx;
    wire                result_flag;
    wire                result_valid;
    reg  [SCALAR_W-1:0] last_result_value;
    reg  [IDX_W-1:0]    last_result_idx;

    wire reduce_valid;
    wire [SCALAR_W-1:0] reduce_result;
    wire [IDX_W-1:0] reduce_idx;
    wire reduce_converged;
    wire scalar_uop = (uop_class == 4'd8);
    wire ls_start = ctx_valid && scalar_uop && (scalar_op[7:4] == 4'h8);
    
    wire skse_support_done, skse_select_done;
    wire [IDX_W-1:0] skse_support_result_idx;
    wire skse_support_result_valid;
    wire ls_busy;
    wire ls_done;
    wire [SCALAR_W-1:0] ls_result;
    wire [MEM_AW-1:0] ls_rd_addr;
    wire [COLS*MEM_AW-1:0] ls_wr_addr;
    wire [COLS*DATA_W-1:0] ls_wr_data;
    wire [COLS-1:0] ls_wr_en;
    wire [5:0] support_depth0;
    wire [IDX_W-1:0] support0_w, support1_w, support2_w, support3_w, support4_w, support5_w, support6_w, support7_w;
    wire [IDX_W-1:0] support8_w, support9_w, support10_w, support11_w, support12_w, support13_w, support14_w, support15_w;
    wire [IDX_W-1:0] support16_w, support17_w, support18_w, support19_w, support20_w, support21_w, support22_w, support23_w;
    wire [IDX_W-1:0] support24_w, support25_w, support26_w, support27_w, support28_w, support29_w, support30_w, support31_w;
    wire [7:0] sparse_k_active = (support_depth0 != 0) ? ((support_depth0 > SPARSE_MAX_K[5:0]) ? SPARSE_MAX_K[7:0] : {2'b00, support_depth0}) : k_param;
    wire scalar_valid     = (scalar_uop && (scalar_op[7:4] == 4'h8)) ? ls_done : (result_valid && scalar_uop);
    wire [SCALAR_W-1:0] scalar_result = (scalar_uop && (scalar_op[7:4] == 4'h8)) ? ls_result : result_value;
    wire [DATA_W-1:0] scalar_q8_8 = scalar_result[DATA_W-1:0];
    wire scalar_cmp_true  = result_flag;
    wire scalar_error     = 1'b0;

    sequencer #(.CTX_W(CTX_W), .CTX_AW(CTX_AW), .IDX_W(IDX_W)) u_seq (
        .clk(clk), .rst_n(rst_core_n), .start(start_pulse), .prog_base(prog_base), .prog_len(prog_len),
        .m_size(m_size), .n_size(n_size), .k_param(k_param), .max_iter(max_iter), .tol_sq_q16_16(tol_sq_q16_16),
        .ctx_addr(seq_ctx_addr), .ctx_rdata(seq_ctx), .ctx_valid(ctx_valid), .ctx_word(ctx_word),
        .phase_start(phase_start), .support_clear_selected(support_clear_selected), .ctx_done(ctx_done),
        .ctx_decode_error(ctx_decode_error), .dma_done(dma_done), .compute_done(compute_done),
        .reduce_done(reduce_valid), .argmax_done(reduce_valid), .scalar_done(scalar_valid),
        .reduce_converged(reduce_converged), .scalar_cmp_true(scalar_cmp_true), .dma_error(dma_error), .dma_error_code(dma_error_code), .scalar_error(scalar_error),
        .busy(seq_busy), .done(seq_done), .irq(seq_irq), .converged(seq_converged),
        .error(seq_error), .error_code(seq_error_code), .pc_dbg(pc_dbg)
    );

    wire [IDX_W-1:0] addr_support_query_base;
    wire [COLS-1:0] selected_lane_mask, support_lane_mask;
    wire [COLS*MEM_AW-1:0] spm_a_addr, spm_b_addr, spm_w_addr;
    reg  [COLS*MEM_AW-1:0] pe_spm_w_addr_q;
    wire [COLS-1:0] lane_valid;
    reg  [COLS-1:0] pe_lane_valid_q;
    reg  [IDX_W-1:0] pe_base_idx_q;
    reg              pe_first_in_phase_q;
    reg  [IDX_W-1:0] pe_m_index_q;
    wire [IDX_W-1:0] base_idx;
    wire [IDX_W-1:0] m_index;
    wire last_reduce;
    wire first_reduce;
    wire addr_valid, addr_done, lfsr_en, lfsr_reseed, lfsr_advance_masked, final_m_block;
    wire first_in_phase;
    wire [COLS-1:0] spm_mask_byte;
    wire pe_addr_uop = (uop_class <= 4'd3) || (uop_class == 4'd5);
    reg pe_exec_valid_q;
    reg pe_active_q;
    reg [3:0] pe_op_q;
    reg [2:0] pe_src_a_sel_q;
    reg [2:0] pe_src_b_sel_q;
    reg [1:0] pe_rf_rd_addr_q;
    reg [1:0] pe_rf_wr_addr_q;
    reg pe_rf_wr_en_q;
    reg pe_acc_clear_q;
    reg pe_acc_en_q;
    reg [3:0] pe_out_sel_q;
    reg pe_spm_wr_en_q;
    reg [2:0] pe_spm_wr_data_sel_q;
    reg [2:0] pe_sb_sel_q;
    reg pe_sb_sel_en_q;
    reg [3:0] pe_row_en_q;
    reg [15:0] pe_imm16_q;
    reg [3:0] pe_ext_ctrl_q;
    reg [7:0] pe_lane_mask_lit_q;
    reg [3:0] pe_lane_mask_mode_q;
    reg [3:0] pe_addr_dim_q;
    reg [2:0] pe_spm_a_vec_q;
    reg [2:0] pe_spm_b_vec_q;
    reg [2:0] pe_spm_w_vec_q;
    reg [2:0] pe_spm_addr_mode_q;
    reg [9:0] pe_abs_addr_q;
    reg [3:0] pe_lfsr_ctrl_q;
    wire [3:0] pe_active_ext_ctrl = pe_active_q ? pe_ext_ctrl_q : ext_ctrl;
    wire [7:0] pe_active_lane_mask_lit = pe_active_q ? pe_lane_mask_lit_q : lane_mask_lit;
    wire [3:0] pe_active_lane_mask_mode = pe_active_q ? pe_lane_mask_mode_q : lane_mask_mode;
    wire [3:0] pe_active_addr_dim = pe_active_q ? pe_addr_dim_q : addr_dim;
    wire [2:0] pe_active_spm_a_vec = pe_active_q ? pe_spm_a_vec_q : spm_a_vec;
    wire [2:0] pe_active_spm_b_vec = pe_active_q ? pe_spm_b_vec_q : spm_b_vec;
    wire [2:0] pe_active_spm_w_vec = pe_active_q ? pe_spm_w_vec_q : spm_w_vec;
    wire [2:0] pe_active_spm_addr_mode = pe_active_q ? pe_spm_addr_mode_q : spm_addr_mode;
    wire [9:0] pe_active_abs_addr = pe_active_q ? pe_abs_addr_q : abs_addr;
    wire [3:0] pe_active_lfsr_ctrl = pe_active_q ? pe_lfsr_ctrl_q : lfsr_ctrl;
    reg [5:0] pe_done_pipe;
    reg [COLS*MEM_AW-1:0] pe_spm_w_addr_write_q;
    reg pe_issue_valid_q;
    reg [COLS-1:0] pe_issue_lane_valid_q;
    reg [IDX_W-1:0] pe_issue_base_idx_q;
    reg pe_issue_first_q;
    reg [IDX_W-1:0] pe_issue_m_index_q;
    reg [COLS*MEM_AW-1:0] pe_issue_spm_a_addr_q;
    reg [COLS*MEM_AW-1:0] pe_issue_spm_b_addr_q;
    reg [COLS*MEM_AW-1:0] pe_issue_spm_w_addr_q;
    reg [COLS*MEM_AW-1:0] pe_waddr_pipe0_q;
    reg [COLS*MEM_AW-1:0] pe_waddr_pipe1_q;
    reg [COLS*MEM_AW-1:0] pe_waddr_pipe2_q;
    reg [COLS*MEM_AW-1:0] pe_waddr_pipe3_q;
    reg pe_issue_final_m_q;
    reg pe_issue_done_q;

    addrgen #(.COLS(COLS), .MEM_AW(MEM_AW), .IDX_W(IDX_W)) u_addrgen (
        .clk(clk), .rst_n(rst_core_n), .start(ctx_valid),
        .m_size(m_size), .n_size(n_size), .k_param(k_param),
        .lane_mask_lit(pe_active_lane_mask_lit), .lane_mask_mode(pe_active_lane_mask_mode),
        .addr_dim(pe_active_addr_dim), .spm_a_vec(pe_active_spm_a_vec), .spm_b_vec(pe_active_spm_b_vec),
        .spm_w_vec(pe_active_spm_w_vec), .spm_addr_mode(pe_active_spm_addr_mode),
        .abs_addr(pe_active_abs_addr), .lfsr_ctrl(pe_active_lfsr_ctrl), .ext_ctrl(pe_active_ext_ctrl),
        .support_query_base(addr_support_query_base), .support_lane_mask(support_lane_mask),
        .selected_lane_mask(selected_lane_mask), .spm_mask_byte(spm_mask_byte),
        .spm_a_addr(spm_a_addr), .spm_b_addr(spm_b_addr), .spm_w_addr(spm_w_addr), .lane_valid(lane_valid),
        .m_index(m_index), .n_base(), .base_idx(base_idx), .first_in_phase(first_in_phase), .last_in_phase(),
        .first_reduce(first_reduce), .last_reduce(last_reduce), .final_m_block(final_m_block), .lfsr_en(lfsr_en), .lfsr_reseed(lfsr_reseed),
        .lfsr_advance_masked(lfsr_advance_masked), .valid(addr_valid), .ready(1'b1), .done(addr_done)
    );

    wire [COLS*DATA_W-1:0] phi_lfsr_bus;
    wire [COLS*DATA_W-1:0] phi_bus;
    lfsr_phi #(.COLS(COLS), .DATA_W(DATA_W), .Q_FRAC_W(Q_FRAC_W)) u_lfsr_phi (
        .clk(clk), .rst_n(rst_core_n), .seed(seed), .phi_scale_q8_8(phi_scale_q8_8),
        .gen_en(lfsr_en), .reseed(lfsr_reseed), .advance_masked_lanes(lfsr_advance_masked),
        .lane_valid(lane_valid), .phi_bus(phi_lfsr_bus), .phi_valid()
    );

    wire [COLS*DATA_W-1:0] spm_pa_rdata, spm_pb_rdata, pe_spm_wdata;
    wire [COLS*64-1:0] ls_pe_rhs_product_bus;
    wire [COLS*64-1:0] pe_corr_acc_bus;
    wire [ROWS*COLS*ACC_W-1:0] ls_wide_product_bus;
    wire [ROWS*COLS*DATA_W-1:0] ls_wide_a_bus;
    wire [ROWS*COLS*DATA_W-1:0] ls_wide_b_bus;
    wire ls_wide_mul_active;
    wire [3:0] ls_pe_sparse_op;
    wire ls_pe_sparse_clear, ls_pe_corr_acc_clear, ls_pe_corr_acc_en;
    wire [COLS*DATA_W-1:0] ls_pe_rhs_phi_bus, ls_pe_rhs_y_bus;
    wire ls_pe_rhs_active;
    wire [CTX_W-1:0] mesh_ctx_word;
    wire [DATA_W-1:0] mesh_ctx_threshold;
    reg  [COLS*DATA_W-1:0] pe_spm_pa_rdata_q, pe_spm_pb_rdata_q;
    wire [COLS*DATA_W-1:0] pe_spm_pa_rdata = pe_active_q ? pe_spm_pa_rdata_q : spm_pa_rdata;
    wire [COLS*DATA_W-1:0] pe_spm_pb_rdata = pe_active_q ? pe_spm_pb_rdata_q : spm_pb_rdata;
    wire [COLS-1:0] pe_spm_wen_raw;
    reg  [COLS-1:0] pe_spm_wen_q;
    reg  [COLS-1:0] pe_wen_pipe0_q;
    reg  [COLS-1:0] pe_wen_pipe1_q;
    wire [COLS*DATA_W-1:0] reduce_data;
    wire [COLS*DATA_W-1:0] mesh_ctx_commit_data;
    wire mesh_ctx_valid;
    wire [1:0] mesh_ctx_mode;
    wire [IDX_W-1:0] mesh_ctx_base_idx;
    wire [IDX_W-1:0] mesh_ctx_limit;
    wire [3:0] mesh_ctx_shift;
    wire [COLS*DATA_W-1:0] mesh_ctx_x_bus;
    wire [COLS*DATA_W-1:0] mesh_ctx_delta_bus;
    wire [COLS-1:0] mesh_ctx_keep_bus;
    wire [COLS*ACC_W-1:0] acc_data;
    wire [COLS*DATA_W-1:0] scalar_bus;
    reg [DATA_W-1:0] spm_b_broadcast;
    wire [COLS*DATA_W-1:0] spm_b_broadcast_bus;
    wire [COLS*MEM_AW-1:0] dma_spm_addr;
    wire [COLS*DATA_W-1:0] dma_spm_wdata;
    wire [COLS-1:0] dma_spm_wen;
    wire dma_phase = (uop_class == 4'd7);

    spm_cluster #(.COLS(COLS), .WORD_W(DATA_W), .MEM_AW(MEM_AW), .BANK_DEPTH(1 << MEM_AW)) u_spm (
        .clk(clk),
        .pa_addr(dma_phase ? dma_spm_addr : (ls_busy ? {COLS{ls_rd_addr}} : (pe_active_q ? pe_issue_spm_a_addr_q : spm_a_addr))),
        .pa_wdata(dma_phase ? dma_spm_wdata : {COLS*DATA_W{1'b0}}),
        .pa_wen(dma_phase ? dma_spm_wen : {COLS{1'b0}}),
        .pa_rdata(spm_pa_rdata),
        .pb_addr(dma_phase ? {COLS*MEM_AW{1'b0}} : (pe_active_q ? pe_issue_spm_b_addr_q : spm_b_addr)),
        .pb_wdata({COLS*DATA_W{1'b0}}),
        .pb_wen({COLS{1'b0}}),
        .pb_rdata(spm_pb_rdata),
        .pc_addr(dma_phase ? {COLS*MEM_AW{1'b0}} : (ls_busy ? ls_wr_addr : pe_waddr_pipe3_q)),
        .pc_wdata(dma_phase ? {COLS*DATA_W{1'b0}} : (ls_busy ? ls_wr_data : pe_spm_wdata)),
        .pc_wen(dma_phase ? {COLS{1'b0}} : (ls_busy ? ls_wr_en : pe_wen_pipe1_q))
    );

    assign phi_bus = phi_lfsr_bus;

    sparse_kernel_service_engine #(
        .COLS(COLS), .DATA_W(DATA_W), .SCALAR_W(SCALAR_W), .MEM_AW(MEM_AW), .IDX_W(IDX_W), .CTX_W(CTX_W),
        .MAX_M(SPARSE_MAX_M), .MAX_N(SPARSE_MAX_N), .MAX_K(SPARSE_MAX_K), .REFINE_ITERS(SPARSE_REFINE_ITERS)
    ) u_sparse_kernel_service_engine (
        .clk(clk), .rst_n(rst_core_n),
        .clear_error_pulse(clear_error_pulse), .start_pulse(start_pulse), .support_clear_selected(support_clear_selected),
        .ctx_valid(ctx_valid), .ctx_word(ctx_word), .uop_class(uop_class), .ext_ctrl(ext_ctrl), .lane_valid(lane_valid),
        .ls_start(ls_start), .scalar_op_low(scalar_op[3:0]), .m_size(m_size), .n_size(n_size),
        .sparse_k_active(sparse_k_active), .seed(seed), .mu_shift_cfg(mu_shift_cfg), .phi_scale_q8_8(phi_scale_q8_8), .phi_kind(flags[3:2]), .phi_bus(phi_bus),
        .addr_support_query_base(addr_support_query_base), .base_idx(base_idx), .select_base_idx(base_idx), .addr_valid(addr_valid), .addr_done(addr_done), .select_addr_valid(addr_valid), .select_addr_done(addr_done),
        .spm_pa_rdata(spm_pa_rdata), .select_spm_pa_rdata(spm_pa_rdata), .select_lane_valid(lane_valid), .pe_rhs_product_bus(ls_pe_rhs_product_bus), .pe_corr_acc_bus(pe_corr_acc_bus), .ls_wide_product_bus(ls_wide_product_bus),
        .last_result_value(last_result_value), .last_result_idx(last_result_idx),
        .support_lane_mask(support_lane_mask), .selected_lane_mask(selected_lane_mask), .support_depth0(support_depth0),
        .support0_w(support0_w), .support1_w(support1_w), .support2_w(support2_w), .support3_w(support3_w),
        .support4_w(support4_w), .support5_w(support5_w), .support6_w(support6_w), .support7_w(support7_w),
        .support8_w(support8_w), .support9_w(support9_w), .support10_w(support10_w), .support11_w(support11_w),
        .support12_w(support12_w), .support13_w(support13_w), .support14_w(support14_w), .support15_w(support15_w),
        .support16_w(support16_w), .support17_w(support17_w), .support18_w(support18_w), .support19_w(support19_w),
        .support20_w(support20_w), .support21_w(support21_w), .support22_w(support22_w), .support23_w(support23_w),
        .support24_w(support24_w), .support25_w(support25_w), .support26_w(support26_w), .support27_w(support27_w),
        .support28_w(support28_w), .support29_w(support29_w), .support30_w(support30_w), .support31_w(support31_w),
        .reduce_valid(reduce_valid), .reduce_result(reduce_result), .reduce_idx(reduce_idx), .reduce_converged(reduce_converged),
        .ls_busy(ls_busy), .ls_done(ls_done), .ls_result(ls_result),
        .ls_rd_addr(ls_rd_addr), .ls_wr_addr(ls_wr_addr), .ls_wr_data(ls_wr_data), .ls_wr_en(ls_wr_en),
        .ls_pe_rhs_phi_bus(ls_pe_rhs_phi_bus), .ls_pe_rhs_y_bus(ls_pe_rhs_y_bus), .ls_pe_rhs_active(ls_pe_rhs_active), .pe_sparse_clear(ls_pe_sparse_clear), .pe_corr_acc_clear(ls_pe_corr_acc_clear), .pe_corr_acc_en(ls_pe_corr_acc_en), .pe_sparse_op(ls_pe_sparse_op),
        .ls_wide_mul_active(ls_wide_mul_active), .ls_wide_a_bus(ls_wide_a_bus), .ls_wide_b_bus(ls_wide_b_bus),
        .mesh_ctx_valid(mesh_ctx_valid), .mesh_ctx_word(mesh_ctx_word), .mesh_ctx_mode(mesh_ctx_mode), .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift), .mesh_ctx_x_bus(mesh_ctx_x_bus), .mesh_ctx_delta_bus(mesh_ctx_delta_bus), .mesh_ctx_keep_bus(mesh_ctx_keep_bus), .mesh_ctx_commit_data(mesh_ctx_commit_data),
        .support_done(skse_support_done), .support_result_idx(skse_support_result_idx), .support_result_valid(skse_support_result_valid), .select_done(skse_select_done)
    );


    wire [3:0] mesh_ctx_dec_pe_op;
    wire [2:0] mesh_ctx_dec_src_a_sel, mesh_ctx_dec_src_b_sel;
    wire [1:0] mesh_ctx_dec_rf_rd_addr, mesh_ctx_dec_rf_wr_addr;
    wire mesh_ctx_dec_rf_wr_en, mesh_ctx_dec_acc_clear, mesh_ctx_dec_acc_en;
    wire [3:0] mesh_ctx_dec_out_sel;
    wire mesh_ctx_dec_spm_wr_en;
    wire [2:0] mesh_ctx_dec_spm_wr_data_sel, mesh_ctx_dec_sb_sel;
    wire mesh_ctx_dec_sb_sel_en;
    wire [3:0] mesh_ctx_dec_row_en;
    wire [15:0] mesh_ctx_dec_imm16;
    wire [7:0] mesh_ctx_dec_lane_mask_lit;
    wire [3:0] mesh_ctx_dec_lane_mask_mode, mesh_ctx_dec_ext_ctrl, mesh_ctx_dec_ctx_ver, mesh_ctx_dec_uop_class, mesh_ctx_dec_repeat_sel, mesh_ctx_dec_addr_dim;
    wire [2:0] mesh_ctx_dec_spm_a_vec, mesh_ctx_dec_spm_b_vec, mesh_ctx_dec_spm_w_vec, mesh_ctx_dec_spm_addr_mode;
    wire [9:0] mesh_ctx_dec_abs_addr;
    wire [3:0] mesh_ctx_dec_lfsr_ctrl;
    wire [2:0] mesh_ctx_dec_reduce_src_vec, mesh_ctx_dec_reduce_dst;
    wire [7:0] mesh_ctx_dec_scalar_op;
    wire [3:0] mesh_ctx_dec_next_ctrl;

    ctx_decoder #(.CTX_W(CTX_W)) u_mesh_ctx_decode (
        .ctx(mesh_ctx_word), .pe_op(mesh_ctx_dec_pe_op), .src_a_sel(mesh_ctx_dec_src_a_sel), .src_b_sel(mesh_ctx_dec_src_b_sel),
        .rf_rd_addr(mesh_ctx_dec_rf_rd_addr), .rf_wr_addr(mesh_ctx_dec_rf_wr_addr), .rf_wr_en(mesh_ctx_dec_rf_wr_en),
        .acc_clear(mesh_ctx_dec_acc_clear), .acc_en(mesh_ctx_dec_acc_en), .out_sel(mesh_ctx_dec_out_sel),
        .spm_wr_en(mesh_ctx_dec_spm_wr_en), .spm_wr_data_sel(mesh_ctx_dec_spm_wr_data_sel), .sb_sel(mesh_ctx_dec_sb_sel), .sb_sel_en(mesh_ctx_dec_sb_sel_en),
        .row_en(mesh_ctx_dec_row_en), .imm16(mesh_ctx_dec_imm16), .lane_mask_lit(mesh_ctx_dec_lane_mask_lit), .lane_mask_mode(mesh_ctx_dec_lane_mask_mode),
        .ext_ctrl(mesh_ctx_dec_ext_ctrl), .ctx_ver(mesh_ctx_dec_ctx_ver), .uop_class(mesh_ctx_dec_uop_class), .repeat_sel(mesh_ctx_dec_repeat_sel),
        .addr_dim(mesh_ctx_dec_addr_dim), .spm_a_vec(mesh_ctx_dec_spm_a_vec), .spm_b_vec(mesh_ctx_dec_spm_b_vec), .spm_w_vec(mesh_ctx_dec_spm_w_vec),
        .spm_addr_mode(mesh_ctx_dec_spm_addr_mode), .abs_addr(mesh_ctx_dec_abs_addr), .lfsr_ctrl(mesh_ctx_dec_lfsr_ctrl),
        .reduce_src_vec(mesh_ctx_dec_reduce_src_vec), .reduce_dst(mesh_ctx_dec_reduce_dst), .scalar_op(mesh_ctx_dec_scalar_op), .next_ctrl(mesh_ctx_dec_next_ctrl),
        .ctx_version_ok(), .ctx_decode_error()
    );

    wire pe_array_ctx_valid = mesh_ctx_valid ? 1'b1 : pe_exec_valid_q;
    wire [3:0] pe_array_op = mesh_ctx_valid ? mesh_ctx_dec_pe_op : pe_op_q;
    wire [2:0] pe_array_src_a_sel = mesh_ctx_valid ? mesh_ctx_dec_src_a_sel : pe_src_a_sel_q;
    wire [2:0] pe_array_src_b_sel = mesh_ctx_valid ? mesh_ctx_dec_src_b_sel : pe_src_b_sel_q;
    wire [1:0] pe_array_rf_rd_addr = mesh_ctx_valid ? mesh_ctx_dec_rf_rd_addr : pe_rf_rd_addr_q;
    wire [1:0] pe_array_rf_wr_addr = mesh_ctx_valid ? mesh_ctx_dec_rf_wr_addr : pe_rf_wr_addr_q;
    wire pe_array_rf_wr_en = mesh_ctx_valid ? mesh_ctx_dec_rf_wr_en : pe_rf_wr_en_q;
    wire pe_array_acc_clear = mesh_ctx_valid ? mesh_ctx_dec_acc_clear : pe_acc_clear_q;
    wire pe_array_acc_en = mesh_ctx_valid ? mesh_ctx_dec_acc_en : pe_acc_en_q;
    wire [3:0] pe_array_out_sel = mesh_ctx_valid ? mesh_ctx_dec_out_sel : pe_out_sel_q;
    wire pe_array_spm_wr_en = mesh_ctx_valid ? mesh_ctx_dec_spm_wr_en : pe_spm_wr_en_q;
    wire [2:0] pe_array_spm_wr_data_sel = mesh_ctx_valid ? mesh_ctx_dec_spm_wr_data_sel : pe_spm_wr_data_sel_q;
    wire [2:0] pe_array_sb_sel = mesh_ctx_valid ? mesh_ctx_dec_sb_sel : pe_sb_sel_q;
    wire pe_array_sb_sel_en = mesh_ctx_valid ? mesh_ctx_dec_sb_sel_en : pe_sb_sel_en_q;
    wire [3:0] pe_array_row_en = mesh_ctx_valid ? mesh_ctx_dec_row_en : pe_row_en_q;
    wire [15:0] pe_array_imm16 = mesh_ctx_valid ? mesh_ctx_dec_imm16 : pe_imm16_q;
    wire [3:0] pe_array_ext_ctrl = mesh_ctx_valid ? mesh_ctx_dec_ext_ctrl : pe_ext_ctrl_q;
    wire [1:0] pe_array_mesh_ctx_mode = mesh_ctx_valid ? mesh_ctx_mode : 2'd0;
    wire [COLS-1:0] pe_array_lane_valid = mesh_ctx_valid ? {COLS{1'b1}} : pe_lane_valid_q;
    wire [IDX_W-1:0] pe_array_base_idx = mesh_ctx_valid ? mesh_ctx_base_idx : pe_base_idx_q;
    wire pe_array_first_in_phase = mesh_ctx_valid ? 1'b1 : pe_first_in_phase_q;
    pearray #(.ROWS(ROWS), .COLS(COLS), .DATA_W(DATA_W), .ACC_W(ACC_W), .CTX_W(CTX_W),
        .SCALAR_W(SCALAR_W), .MEM_AW(MEM_AW), .IDX_W(IDX_W), .Q_FRAC_W(Q_FRAC_W), .ENABLE_MESH_CTX(1)) u_pearray (
        .clk(clk), .rst_n(rst_core_n), .ctx_valid(pe_array_ctx_valid),
        .pe_op(pe_array_op), .src_a_sel(pe_array_src_a_sel), .src_b_sel(pe_array_src_b_sel),
        .rf_rd_addr(pe_array_rf_rd_addr), .rf_wr_addr(pe_array_rf_wr_addr), .rf_wr_en(pe_array_rf_wr_en),
        .acc_clear(pe_array_acc_clear), .acc_en(pe_array_acc_en), .out_sel(pe_array_out_sel),
        .spm_wr_en(pe_array_spm_wr_en), .spm_wr_data_sel(pe_array_spm_wr_data_sel),
        .sb_sel(pe_array_sb_sel), .sb_sel_en(pe_array_sb_sel_en), .row_en(pe_array_row_en),
        .imm16(pe_array_imm16), .ext_ctrl(pe_array_ext_ctrl), .mesh_ctx_mode(pe_array_mesh_ctx_mode),
        .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift), .mesh_ctx_x_bus(mesh_ctx_x_bus), .mesh_ctx_delta_bus(mesh_ctx_delta_bus), .mesh_ctx_keep_bus(mesh_ctx_keep_bus),
        .lane_valid(pe_array_lane_valid), .base_idx(pe_array_base_idx), .first_in_phase(pe_array_first_in_phase),
        .spm_a_rdata(pe_spm_pa_rdata), .spm_b_rdata(pe_spm_pb_rdata), .phi_bus(ls_busy ? ls_pe_rhs_phi_bus : phi_bus), .scalar_bus(ls_busy ? ls_pe_rhs_y_bus : scalar_bus),
        .sparse_active(ls_start || ls_busy), .sparse_step_active(ls_pe_rhs_active), .sparse_clear(ls_pe_sparse_clear), .corr_acc_clear(ls_pe_corr_acc_clear), .corr_acc_en(ls_pe_corr_acc_en), .sparse_op((ls_busy || ls_start) ? ((ls_pe_sparse_op == 4'd1) ? 4'd1 : 4'd0) : scalar_op[3:0]), .sparse_k_active(sparse_k_active),
        .ls_wide_mul_active(ls_wide_mul_active), .ls_wide_a_bus(ls_wide_a_bus), .ls_wide_b_bus(ls_wide_b_bus), .ls_wide_product_bus(ls_wide_product_bus),
        .spm_wdata(pe_spm_wdata), .spm_wen(pe_spm_wen_raw), .reduce_data(reduce_data), .acc_data(acc_data), .sparse_rhs_product_bus(ls_pe_rhs_product_bus), .corr_acc_bus(pe_corr_acc_bus), .mesh_ctx_commit_data(mesh_ctx_commit_data),
        .result_value(result_value), .result_idx(result_idx), .result_flag(result_flag),
        .result_valid(result_valid), .compute_done(compute_done)
    );

    always @(posedge clk or negedge rst_core_n) begin
        if (!rst_core_n) begin
            pe_exec_valid_q <= 1'b0; pe_active_q <= 1'b0; pe_op_q <= 4'd0; pe_src_a_sel_q <= 3'd0; pe_src_b_sel_q <= 3'd0; pe_rf_rd_addr_q <= 2'd0; pe_rf_wr_addr_q <= 2'd0; pe_rf_wr_en_q <= 1'b0; pe_acc_clear_q <= 1'b0; pe_acc_en_q <= 1'b0; pe_out_sel_q <= 4'd0; pe_spm_wr_en_q <= 1'b0; pe_spm_wr_data_sel_q <= 3'd0; pe_sb_sel_q <= 3'd0; pe_sb_sel_en_q <= 1'b0; pe_row_en_q <= 4'd0; pe_imm16_q <= 16'd0; pe_ext_ctrl_q <= 4'd0; pe_lane_mask_lit_q <= 8'd0; pe_lane_mask_mode_q <= 4'd0; pe_addr_dim_q <= 4'd0; pe_spm_a_vec_q <= 3'd0; pe_spm_b_vec_q <= 3'd0; pe_spm_w_vec_q <= 3'd0; pe_spm_addr_mode_q <= 3'd0; pe_abs_addr_q <= 10'd0; pe_lfsr_ctrl_q <= 4'd0; pe_lane_valid_q <= {COLS{1'b0}}; pe_base_idx_q <= {IDX_W{1'b0}}; pe_first_in_phase_q <= 1'b0; pe_m_index_q <= {IDX_W{1'b0}};
            pe_spm_w_addr_q <= {COLS*MEM_AW{1'b0}}; pe_spm_w_addr_write_q <= {COLS*MEM_AW{1'b0}};
            pe_spm_pa_rdata_q <= {COLS*DATA_W{1'b0}}; pe_spm_pb_rdata_q <= {COLS*DATA_W{1'b0}};
            pe_spm_wen_q <= {COLS{1'b0}}; pe_wen_pipe0_q <= {COLS{1'b0}}; pe_wen_pipe1_q <= {COLS{1'b0}}; pe_done_pipe <= 6'b000000;
            pe_issue_valid_q <= 1'b0; pe_issue_lane_valid_q <= {COLS{1'b0}}; pe_issue_base_idx_q <= {IDX_W{1'b0}}; pe_issue_first_q <= 1'b0; pe_issue_m_index_q <= {IDX_W{1'b0}}; pe_issue_spm_a_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_b_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_w_addr_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe0_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe1_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe2_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe3_q <= {COLS*MEM_AW{1'b0}}; pe_issue_final_m_q <= 1'b0; pe_issue_done_q <= 1'b0;
        end else begin
            if (ctx_valid && pe_addr_uop) begin
                pe_exec_valid_q <= 1'b0; pe_active_q <= 1'b1; pe_op_q <= pe_op; pe_src_a_sel_q <= src_a_sel; pe_src_b_sel_q <= src_b_sel; pe_rf_rd_addr_q <= rf_rd_addr; pe_rf_wr_addr_q <= rf_wr_addr; pe_rf_wr_en_q <= rf_wr_en; pe_acc_clear_q <= acc_clear; pe_acc_en_q <= acc_en; pe_out_sel_q <= out_sel; pe_spm_wr_en_q <= spm_wr_en_dec; pe_spm_wr_data_sel_q <= spm_wr_data_sel; pe_sb_sel_q <= sb_sel; pe_sb_sel_en_q <= sb_sel_en; pe_row_en_q <= row_en; pe_imm16_q <= imm16; pe_ext_ctrl_q <= ext_ctrl; pe_lane_mask_lit_q <= lane_mask_lit; pe_lane_mask_mode_q <= lane_mask_mode; pe_addr_dim_q <= addr_dim; pe_spm_a_vec_q <= spm_a_vec; pe_spm_b_vec_q <= spm_b_vec; pe_spm_w_vec_q <= spm_w_vec; pe_spm_addr_mode_q <= spm_addr_mode; pe_abs_addr_q <= abs_addr; pe_lfsr_ctrl_q <= lfsr_ctrl; pe_lane_valid_q <= {COLS{1'b0}}; pe_base_idx_q <= {IDX_W{1'b0}}; pe_first_in_phase_q <= 1'b0; pe_m_index_q <= {IDX_W{1'b0}};
                pe_spm_w_addr_q <= {COLS*MEM_AW{1'b0}}; pe_spm_w_addr_write_q <= {COLS*MEM_AW{1'b0}};
                pe_spm_wen_q <= {COLS{1'b0}}; pe_wen_pipe0_q <= {COLS{1'b0}}; pe_wen_pipe1_q <= {COLS{1'b0}}; pe_done_pipe <= 6'b000000;
                pe_issue_valid_q <= 1'b0; pe_issue_lane_valid_q <= {COLS{1'b0}}; pe_issue_base_idx_q <= {IDX_W{1'b0}}; pe_issue_first_q <= 1'b0; pe_issue_m_index_q <= {IDX_W{1'b0}}; pe_issue_spm_a_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_b_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_w_addr_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe0_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe1_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe2_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe3_q <= {COLS*MEM_AW{1'b0}}; pe_issue_final_m_q <= 1'b0; pe_issue_done_q <= 1'b0;
            end else if (pe_active_q) begin
                pe_exec_valid_q <= pe_issue_valid_q;
                pe_lane_valid_q <= pe_issue_lane_valid_q;
                pe_base_idx_q <= pe_issue_base_idx_q;
                pe_first_in_phase_q <= pe_issue_first_q;
                pe_m_index_q <= pe_issue_m_index_q;
                pe_spm_w_addr_write_q <= pe_spm_w_addr_q;
                pe_spm_w_addr_q <= pe_issue_spm_w_addr_q;
                pe_spm_wen_q <= pe_spm_wen_raw & ({COLS{(!pe_active_ext_ctrl[0] && (pe_active_spm_addr_mode != 3'd6)) || pe_issue_final_m_q}});
                pe_wen_pipe0_q <= pe_spm_wen_q;
                pe_wen_pipe1_q <= pe_wen_pipe0_q;
                pe_done_pipe <= {pe_done_pipe[4:0], pe_issue_done_q};

                pe_issue_valid_q <= addr_valid;
                pe_issue_lane_valid_q <= lane_valid;
                pe_issue_base_idx_q <= base_idx;
                pe_issue_first_q <= first_in_phase || (m_index == {IDX_W{1'b0}});
                pe_issue_m_index_q <= m_index;
                pe_issue_spm_a_addr_q <= spm_a_addr;
                pe_issue_spm_b_addr_q <= spm_b_addr;
                pe_issue_spm_w_addr_q <= spm_w_addr;
                pe_waddr_pipe0_q <= pe_issue_spm_w_addr_q;
                pe_waddr_pipe1_q <= pe_waddr_pipe0_q;
                pe_waddr_pipe2_q <= pe_waddr_pipe1_q;
                pe_waddr_pipe3_q <= pe_waddr_pipe2_q;
                pe_spm_pa_rdata_q <= spm_pa_rdata;
                pe_spm_pb_rdata_q <= spm_pb_rdata;
                pe_issue_final_m_q <= final_m_block;
                pe_issue_done_q <= addr_done;
                if (pe_done_pipe[5]) pe_active_q <= 1'b0;
            end else begin
                pe_exec_valid_q <= 1'b0;
                pe_lane_valid_q <= {COLS{1'b0}};
                pe_first_in_phase_q <= 1'b0;
                pe_m_index_q <= {IDX_W{1'b0}};
                pe_spm_wen_q <= {COLS{1'b0}};
                pe_wen_pipe0_q <= {COLS{1'b0}};
                pe_wen_pipe1_q <= {COLS{1'b0}};
                pe_done_pipe <= {pe_done_pipe[4:0], 1'b0};
                pe_issue_valid_q <= 1'b0; pe_issue_lane_valid_q <= {COLS{1'b0}}; pe_issue_base_idx_q <= {IDX_W{1'b0}}; pe_issue_first_q <= 1'b0; pe_issue_m_index_q <= {IDX_W{1'b0}}; pe_issue_spm_a_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_b_addr_q <= {COLS*MEM_AW{1'b0}}; pe_issue_spm_w_addr_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe0_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe1_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe2_q <= {COLS*MEM_AW{1'b0}}; pe_waddr_pipe3_q <= {COLS*MEM_AW{1'b0}}; pe_issue_final_m_q <= 1'b0; pe_issue_done_q <= 1'b0;
            end
        end
    end

    genvar bm_i;
    generate
        for (bm_i = 0; bm_i < COLS; bm_i = bm_i + 1) begin : gen_lane_masks
            assign spm_mask_byte[bm_i] = spm_pb_rdata[bm_i*DATA_W];
        end
    endgenerate

    wire [SCALAR_W-1:0] global_scalar_a, global_scalar_b, global_scalar_broadcast;
    global_scalar_rf #(.SCALAR_W(SCALAR_W), .N_REGS(16), .ADDR_W(4)) u_global_scalar_rf (
        .clk(clk), .rst_n(rst_core_n), .clear(clear_error_pulse || start_pulse),
        .wr_en(scalar_valid), .wr_addr({1'b0, reduce_dst}), .wr_data(scalar_result),
        .rd_a_addr({1'b0, reduce_src_vec}), .rd_b_addr({1'b0, spm_a_vec}), .broadcast_addr({1'b0, reduce_dst}),
        .rd_a_data(global_scalar_a), .rd_b_data(global_scalar_b), .broadcast_data(global_scalar_broadcast)
    );

    always @(*) begin
        case (pe_m_index_q[2:0])
            3'd0: spm_b_broadcast = spm_pb_rdata[0*DATA_W +: DATA_W];
            3'd1: spm_b_broadcast = spm_pb_rdata[1*DATA_W +: DATA_W];
            3'd2: spm_b_broadcast = spm_pb_rdata[2*DATA_W +: DATA_W];
            3'd3: spm_b_broadcast = spm_pb_rdata[3*DATA_W +: DATA_W];
            3'd4: spm_b_broadcast = spm_pb_rdata[4*DATA_W +: DATA_W];
            3'd5: spm_b_broadcast = spm_pb_rdata[5*DATA_W +: DATA_W];
            3'd6: spm_b_broadcast = spm_pb_rdata[6*DATA_W +: DATA_W];
            default: spm_b_broadcast = spm_pb_rdata[7*DATA_W +: DATA_W];
        endcase
    end
    genvar sb_i;
    generate
        for (sb_i = 0; sb_i < COLS; sb_i = sb_i + 1) begin : gen_scalar_bus
            assign spm_b_broadcast_bus[sb_i*DATA_W +: DATA_W] = spm_b_broadcast;
            assign scalar_bus[sb_i*DATA_W +: DATA_W] = (pe_addr_uop && (pe_active_ext_ctrl[0] || (pe_active_spm_addr_mode == 3'd6))) ? spm_b_broadcast_bus[sb_i*DATA_W +: DATA_W] : scalar_q8_8;
        end
    endgenerate

    dma_ctrl #(.AXI_AW(AXI_AW), .AXI_DW(AXI_DW), .COLS(COLS), .MEM_AW(MEM_AW), .DATA_W(DATA_W), .IDX_W(IDX_W)) u_dma (
        .clk(clk), .rst_n(rst_core_n), .start(ctx_valid && (uop_class == 4'd7)), .dir(ctx_word[0]),
        .vec_id(spm_a_vec), .length((addr_dim == 4'd1) ? m_size : n_size),
        .ddr_addr((ctx_word[0] || (spm_a_vec == 3'd0)) ? x_ddr_addr : y_ddr_addr), .done(dma_done), .error(dma_error), .error_code(dma_error_code),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready), .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rlast(m_axi_rlast), .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .spm_addr(dma_spm_addr), .spm_wdata(dma_spm_wdata), .spm_wen(dma_spm_wen), .spm_rdata(spm_pa_rdata)
    );

    assign ctx_done =
        (uop_class == 4'd7) ? dma_done :
        (uop_class == 4'd4) ? reduce_valid :
        (uop_class == 4'd5) ? (ctx_word[31] ? 1'b1 : skse_select_done) :
        (uop_class == 4'd6) ? skse_support_done :
        (uop_class == 4'd8) ? scalar_valid :
        (uop_class == 4'd9) ? 1'b1 :
        (pe_addr_uop || pe_active_q) ? pe_done_pipe[5] :
                              (addr_done | compute_done);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt <= 32'd0; result0_q <= 32'd0;
            last_result_value <= {SCALAR_W{1'b0}};
            last_result_idx <= {IDX_W{1'b0}};
        end else begin
            if (start_pulse) cycle_cnt <= 32'd0;
            else if (seq_busy) cycle_cnt <= cycle_cnt + 1'b1;
            if (reduce_valid) begin
                result0_q <= reduce_result[31:0];
                last_result_value <= reduce_result;
                last_result_idx <= reduce_idx;
            end else if (scalar_valid) begin
                result0_q <= scalar_result[31:0];
                last_result_value <= scalar_result;
                last_result_idx <= result_idx;
            end
        end
    end

    assign irq_done  = seq_irq && seq_done;
    assign irq_error = seq_irq && seq_error;

endmodule
































