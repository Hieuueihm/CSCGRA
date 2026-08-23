module csr_regs #(
    parameter integer AXIL_AW = 12,
    parameter integer AXIL_DW = 32,
    parameter integer CTX_W   = 64,
    parameter integer CTX_AW  = 6,
    parameter integer NCTX    = 64,
    parameter integer IDX_W   = 10,
    parameter integer DATA_W  = 24,
    parameter integer Q_FRAC_W = DATA_W - 8
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire [AXIL_AW-1:0]   s_axi_awaddr,
    input  wire                 s_axi_awvalid,
    output wire                 s_axi_awready,
    input  wire [AXIL_DW-1:0]   s_axi_wdata,
    input  wire [AXIL_DW/8-1:0] s_axi_wstrb,
    input  wire                 s_axi_wvalid,
    output wire                 s_axi_wready,
    output wire [1:0]           s_axi_bresp,
    output reg                  s_axi_bvalid,
    input  wire                 s_axi_bready,
    input  wire [AXIL_AW-1:0]   s_axi_araddr,
    input  wire                 s_axi_arvalid,
    output wire                 s_axi_arready,
    output reg  [AXIL_DW-1:0]   s_axi_rdata,
    output wire [1:0]           s_axi_rresp,
    output reg                  s_axi_rvalid,
    input  wire                 s_axi_rready,

    output reg                  start_pulse,
    output reg                  soft_reset_pulse,
    output reg                  clear_error_pulse,
    output reg  [IDX_W-1:0]     m_size,
    output reg  [IDX_W-1:0]     n_size,
    output reg  [7:0]           k_param,
    output reg  [15:0]          max_iter,
    output reg  [31:0]          tol_sq_q16_16,
    output reg  [31:0]          y_ddr_addr,
    output reg  [31:0]          x_ddr_addr,
    output reg  [31:0]          seed,
    output reg  [DATA_W-1:0]    phi_scale_q8_8,
    output reg  [31:0]          flags,
    output reg  [3:0]           mu_shift_cfg,
    output reg  [31:0]          dense_step_q16_16,
    output reg  [DATA_W-1:0]    dense_lambda_q8_8,
    output reg  [DATA_W-1:0]    dense_rho_q8_8,
    output reg  [DATA_W-1:0]    dense_theta_q8_8,
    output reg  [DATA_W-1:0]    dense_damp_q8_8,
    output reg  [CTX_AW-1:0]    prog_base,
    output reg  [CTX_AW:0]      prog_len,

    input  wire                 busy,
    input  wire                 done,
    input  wire                 converged,
    input  wire                 error,
    input  wire [3:0]           error_code,
    input  wire [31:0]          result0,
    input  wire [31:0]          cycle_cnt,
    input  wire [CTX_AW-1:0]    pc_dbg,
    input  wire [31:0]          phase_cycle_corr,
    input  wire [31:0]          phase_cycle_topk,
    input  wire [31:0]          phase_cycle_support,
    input  wire [31:0]          phase_cycle_solve,
    input  wire [31:0]          phase_cycle_residual,
    input  wire [31:0]          phase_cycle_vector,

    output reg                  cfg_wr_en,
    output reg  [CTX_AW-1:0]    cfg_wr_addr,
    output reg                  cfg_wr_word,
    output reg  [AXIL_DW-1:0]   cfg_wr_data,
    output reg  [AXIL_DW/8-1:0] cfg_wr_strb,

    output reg                  cfg_dbg_rd_en,
    output reg  [CTX_AW-1:0]    cfg_dbg_rd_addr,
    input  wire [CTX_W-1:0]     cfg_dbg_rd_data
);

    localparam [AXIL_AW-1:0] A_CTRL       = 12'h000;
    localparam [AXIL_AW-1:0] A_STATUS     = 12'h004;
    localparam [AXIL_AW-1:0] A_RESERVED_008 = 12'h008;
    localparam [AXIL_AW-1:0] A_M_SIZE     = 12'h00C;
    localparam [AXIL_AW-1:0] A_N_SIZE     = 12'h010;
    localparam [AXIL_AW-1:0] A_K_PARAM    = 12'h014;
    localparam [AXIL_AW-1:0] A_Y_DDR      = 12'h018;
    localparam [AXIL_AW-1:0] A_X_DDR      = 12'h01C;
    localparam [AXIL_AW-1:0] A_SEED       = 12'h020;
    localparam [AXIL_AW-1:0] A_PHI_SCALE  = 12'h024;
    localparam [AXIL_AW-1:0] A_MAX_ITER   = 12'h028;
    localparam [AXIL_AW-1:0] A_TOL        = 12'h02C;
    localparam [AXIL_AW-1:0] A_FLAGS      = 12'h030;
    localparam [AXIL_AW-1:0] A_CG_MAXITER = 12'h034;
    localparam [AXIL_AW-1:0] A_CG_TOL     = 12'h038;
    localparam [AXIL_AW-1:0] A_CG_PRIM    = 12'h03C;
    localparam [AXIL_AW-1:0] A_PROG_BASE  = 12'h040;
    localparam [AXIL_AW-1:0] A_PROG_LEN   = 12'h044;
    localparam [AXIL_AW-1:0] A_RESULT0    = 12'h050;
    localparam [AXIL_AW-1:0] A_CYCLE_CNT  = 12'h054;
    localparam [AXIL_AW-1:0] A_PC_DBG     = 12'h058;
    localparam [AXIL_AW-1:0] A_PHASE_CORR = 12'h074;
    localparam [AXIL_AW-1:0] A_PHASE_TOPK = 12'h078;
    localparam [AXIL_AW-1:0] A_PHASE_SUPPORT = 12'h07C;
    localparam [AXIL_AW-1:0] A_PHASE_SOLVE = 12'h080;
    localparam [AXIL_AW-1:0] A_PHASE_RESIDUAL = 12'h084;
    localparam [AXIL_AW-1:0] A_PHASE_VECTOR = 12'h088;
    localparam [AXIL_AW-1:0] A_DENSE_STEP = 12'h05C;
    localparam [AXIL_AW-1:0] A_DENSE_LAMBDA = 12'h060;
    localparam [AXIL_AW-1:0] A_DENSE_RHO  = 12'h064;
    localparam [AXIL_AW-1:0] A_DENSE_THETA = 12'h068;
    localparam [AXIL_AW-1:0] A_DENSE_DAMP = 12'h06C;
    localparam [AXIL_AW-1:0] A_MU_SHIFT   = 12'h070;
    localparam [AXIL_AW-1:0] A_CTX_BASE   = 12'h100;
    localparam integer CTX_WINDOW_BYTES = NCTX * 8;
    localparam [DATA_W-1:0] Q_ONE  = {{(DATA_W-Q_FRAC_W-1){1'b0}}, 1'b1, {Q_FRAC_W{1'b0}}};
    localparam [DATA_W-1:0] Q_HALF = {{(DATA_W-Q_FRAC_W){1'b0}}, 1'b1, {(Q_FRAC_W-1){1'b0}}};

    // AXI-Lite address and write-data channels are independent.  Keep one
    // pending item per channel so a master may present AW and W in different
    // cycles without losing either half of the transaction.
    reg                  aw_pending_q;
    reg [AXIL_AW-1:0]    awaddr_q;
    reg                  w_pending_q;
    reg [AXIL_DW-1:0]    wdata_q;
    reg [AXIL_DW/8-1:0]  wstrb_q;
    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire wr_have_aw = aw_pending_q || aw_fire;
    wire wr_have_w  = w_pending_q  || w_fire;
    wire wr_commit  = !s_axi_bvalid && wr_have_aw && wr_have_w;
    wire [AXIL_AW-1:0] wr_addr_eff = aw_pending_q ? awaddr_q : s_axi_awaddr;
    wire [AXIL_DW-1:0] wr_data_eff = w_pending_q ? wdata_q : s_axi_wdata;
    wire [AXIL_DW/8-1:0] wr_strb_eff = w_pending_q ? wstrb_q : s_axi_wstrb;

    reg                  ctx_rd_pending_q;
    reg [1:0]            ctx_rd_wait_q;
    reg                  ctx_rd_word_q;

    assign s_axi_awready = !s_axi_bvalid && !aw_pending_q;
    assign s_axi_wready  = !s_axi_bvalid && !w_pending_q;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = !s_axi_rvalid && !ctx_rd_pending_q;
    assign s_axi_rresp   = 2'b00;

    wire rd_fire = s_axi_arvalid && s_axi_arready;
    // Context entries are two 32-bit words and must be naturally aligned.
    wire ctx_addr_hit_wr = (wr_addr_eff >= A_CTX_BASE) &&
                           (wr_addr_eff < (A_CTX_BASE + CTX_WINDOW_BYTES)) &&
                           (wr_addr_eff[1:0] == 2'b00);
    wire ctx_addr_hit_rd = (s_axi_araddr >= A_CTX_BASE) &&
                           (s_axi_araddr < (A_CTX_BASE + CTX_WINDOW_BYTES)) &&
                           (s_axi_araddr[1:0] == 2'b00);
    wire [CTX_AW-1:0] ctx_wr_index = (wr_addr_eff - A_CTX_BASE) >> 3;
    wire ctx_wr_word = wr_addr_eff[2];
    wire [CTX_AW-1:0] ctx_rd_index = (s_axi_araddr - A_CTX_BASE) >> 3;
    wire ctx_rd_word = s_axi_araddr[2];

    reg done_latched;
    reg error_latched;
    reg [3:0] error_code_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;
            clear_error_pulse <= 1'b0;
            m_size <= {IDX_W{1'b0}};
            n_size <= {IDX_W{1'b0}};
            k_param <= 8'd0;
            max_iter <= 16'd0;
            tol_sq_q16_16 <= 32'd0;
            y_ddr_addr <= 32'd0;
            x_ddr_addr <= 32'd0;
            seed <= 32'h1;
            phi_scale_q8_8 <= Q_ONE;
            flags <= 32'd0;
            mu_shift_cfg <= 4'd2;
            dense_step_q16_16 <= 32'd0;
            dense_lambda_q8_8 <= {DATA_W{1'b0}};
            dense_rho_q8_8 <= {DATA_W{1'b0}};
            dense_theta_q8_8 <= {DATA_W{1'b0}};
            dense_damp_q8_8 <= Q_HALF;
            prog_base <= {CTX_AW{1'b0}};
            prog_len <= {(CTX_AW+1){1'b0}};
            cfg_wr_en <= 1'b0;
            cfg_wr_addr <= {CTX_AW{1'b0}};
            cfg_wr_word <= 1'b0;
            cfg_wr_data <= {AXIL_DW{1'b0}};
            cfg_wr_strb <= {(AXIL_DW/8){1'b0}};
            cfg_dbg_rd_en <= 1'b0;
            cfg_dbg_rd_addr <= {CTX_AW{1'b0}};
            aw_pending_q <= 1'b0;
            awaddr_q <= {AXIL_AW{1'b0}};
            w_pending_q <= 1'b0;
            wdata_q <= {AXIL_DW{1'b0}};
            wstrb_q <= {(AXIL_DW/8){1'b0}};
            ctx_rd_pending_q <= 1'b0;
            ctx_rd_wait_q <= 2'd0;
            ctx_rd_word_q <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= {AXIL_DW{1'b0}};
            done_latched <= 1'b0;
            error_latched <= 1'b0;
            error_code_latched <= 4'd0;
        end else begin
            start_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;
            clear_error_pulse <= 1'b0;
            cfg_wr_en <= 1'b0;
            cfg_dbg_rd_en <= 1'b0;

            if (done) done_latched <= 1'b1;
            if (error) begin
                error_latched <= 1'b1;
                error_code_latched <= error_code;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (wr_commit) begin
                s_axi_bvalid <= 1'b1;
                aw_pending_q <= 1'b0;
                w_pending_q <= 1'b0;
                if (ctx_addr_hit_wr) begin
                    cfg_wr_en <= 1'b1;
                    cfg_wr_addr <= ctx_wr_index;
                    cfg_wr_word <= ctx_wr_word;
                    cfg_wr_data <= wr_data_eff;
                    cfg_wr_strb <= wr_strb_eff;
                end else begin
                    case (wr_addr_eff)
                        A_CTRL: begin
                            start_pulse <= wr_data_eff[0];
                            soft_reset_pulse <= wr_data_eff[1];
                            clear_error_pulse <= wr_data_eff[2];
                            if (wr_data_eff[0] || wr_data_eff[2]) begin
                                done_latched <= 1'b0;
                                error_latched <= 1'b0;
                                error_code_latched <= 4'd0;
                            end
                        end
                        A_M_SIZE:     m_size <= wr_data_eff[IDX_W-1:0];
                        A_N_SIZE:     n_size <= wr_data_eff[IDX_W-1:0];
                        A_K_PARAM:    k_param <= wr_data_eff[7:0];
                        A_Y_DDR:      y_ddr_addr <= wr_data_eff;
                        A_X_DDR:      x_ddr_addr <= wr_data_eff;
                        A_SEED:       seed <= wr_data_eff;
                        A_PHI_SCALE:  phi_scale_q8_8 <= wr_data_eff[DATA_W-1:0];
                        A_MAX_ITER:   max_iter <= wr_data_eff[15:0];
                        A_TOL:        tol_sq_q16_16 <= wr_data_eff;
                        A_FLAGS:      flags <= wr_data_eff;
                        A_DENSE_STEP: dense_step_q16_16 <= wr_data_eff;
                        A_DENSE_LAMBDA: dense_lambda_q8_8 <= wr_data_eff[DATA_W-1:0];
                        A_DENSE_RHO:  dense_rho_q8_8 <= wr_data_eff[DATA_W-1:0];
                        A_DENSE_THETA: dense_theta_q8_8 <= wr_data_eff[DATA_W-1:0];
                        A_DENSE_DAMP: dense_damp_q8_8 <= wr_data_eff[DATA_W-1:0];
                        A_MU_SHIFT:   mu_shift_cfg <= wr_data_eff[3:0];
                        A_PROG_BASE:  prog_base <= wr_data_eff[CTX_AW-1:0];
                        A_PROG_LEN:   prog_len <= wr_data_eff[CTX_AW:0];
                        default: begin
                        end
                    endcase
                end
            end else begin
                if (aw_fire) begin
                    aw_pending_q <= 1'b1;
                    awaddr_q <= s_axi_awaddr;
                end
                if (w_fire) begin
                    w_pending_q <= 1'b1;
                    wdata_q <= s_axi_wdata;
                    wstrb_q <= s_axi_wstrb;
                end
            end

            if (rd_fire) begin
                if (ctx_addr_hit_rd) begin
                    cfg_dbg_rd_en <= 1'b1;
                    cfg_dbg_rd_addr <= ctx_rd_index;
                    ctx_rd_word_q <= ctx_rd_word;
                    ctx_rd_pending_q <= 1'b1;
                    ctx_rd_wait_q <= 2'd2;
                end else begin
                    s_axi_rvalid <= 1'b1;
                    case (s_axi_araddr)
                        A_STATUS: s_axi_rdata <= {24'd0, error_code_latched, error_latched, converged, busy, done_latched};
                        A_RESERVED_008: s_axi_rdata <= 32'd0;
                        A_M_SIZE: s_axi_rdata <= {{(32-IDX_W){1'b0}}, m_size};
                        A_N_SIZE: s_axi_rdata <= {{(32-IDX_W){1'b0}}, n_size};
                        A_K_PARAM: s_axi_rdata <= {24'd0, k_param};
                        A_Y_DDR: s_axi_rdata <= y_ddr_addr;
                        A_X_DDR: s_axi_rdata <= x_ddr_addr;
                        A_SEED: s_axi_rdata <= seed;
                        A_PHI_SCALE: s_axi_rdata <= {{(32-DATA_W){1'b0}}, phi_scale_q8_8};
                        A_MAX_ITER: s_axi_rdata <= {16'd0, max_iter};
                        A_TOL: s_axi_rdata <= tol_sq_q16_16;
                        A_FLAGS: s_axi_rdata <= flags;
                        A_DENSE_STEP: s_axi_rdata <= dense_step_q16_16;
                        A_DENSE_LAMBDA: s_axi_rdata <= {{(32-DATA_W){1'b0}}, dense_lambda_q8_8};
                        A_DENSE_RHO: s_axi_rdata <= {{(32-DATA_W){1'b0}}, dense_rho_q8_8};
                        A_DENSE_THETA: s_axi_rdata <= {{(32-DATA_W){1'b0}}, dense_theta_q8_8};
                        A_DENSE_DAMP: s_axi_rdata <= {{(32-DATA_W){1'b0}}, dense_damp_q8_8};
                        A_MU_SHIFT: s_axi_rdata <= {28'd0, mu_shift_cfg};
                        A_CG_MAXITER: s_axi_rdata <= 32'd0;
                        A_CG_TOL: s_axi_rdata <= 32'd0;
                        A_CG_PRIM: s_axi_rdata <= 32'd0;
                        A_PROG_BASE: s_axi_rdata <= {{(32-CTX_AW){1'b0}}, prog_base};
                        A_PROG_LEN: s_axi_rdata <= {{(31-CTX_AW){1'b0}}, prog_len};
                        A_RESULT0: s_axi_rdata <= result0;
                        A_CYCLE_CNT: s_axi_rdata <= cycle_cnt;
                        A_PC_DBG: s_axi_rdata <= {{(32-CTX_AW){1'b0}}, pc_dbg};
                        A_PHASE_CORR: s_axi_rdata <= phase_cycle_corr;
                        A_PHASE_TOPK: s_axi_rdata <= phase_cycle_topk;
                        A_PHASE_SUPPORT: s_axi_rdata <= phase_cycle_support;
                        A_PHASE_SOLVE: s_axi_rdata <= phase_cycle_solve;
                        A_PHASE_RESIDUAL: s_axi_rdata <= phase_cycle_residual;
                        A_PHASE_VECTOR: s_axi_rdata <= phase_cycle_vector;
                        default: s_axi_rdata <= 32'd0;
                    endcase
                end
            end

            // configmem has a registered synchronous debug read.  The read
            // request is observed by configmem one cycle after cfg_dbg_rd_en
            // is asserted, so wait one additional cycle before forming the
            // AXI-Lite response from cfg_dbg_rd_data.
            if (ctx_rd_pending_q) begin
                if (ctx_rd_wait_q != 0)
                    ctx_rd_wait_q <= ctx_rd_wait_q - 1'b1;
                if (ctx_rd_wait_q == 1) begin
                    s_axi_rvalid <= 1'b1;
                    case (ctx_rd_word_q)
                        1'b0: s_axi_rdata <= cfg_dbg_rd_data[31:0];
                        1'b1: s_axi_rdata <= cfg_dbg_rd_data[63:32];
                        default: s_axi_rdata <= 32'd0;
                    endcase
                    ctx_rd_pending_q <= 1'b0;
                    ctx_rd_wait_q <= 2'd0;
                end
            end
        end
    end

endmodule
