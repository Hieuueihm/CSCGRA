module csr_regs #(
    parameter integer AXIL_AW = 12,
    parameter integer AXIL_DW = 32,
    parameter integer CTX_W   = 64,
    parameter integer CTX_AW  = 6,
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

    output reg                  cfg_wr_en,
    output reg  [CTX_AW-1:0]    cfg_wr_addr,
    output reg                  cfg_wr_word,
    output reg  [AXIL_DW-1:0]   cfg_wr_data,

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
    localparam [AXIL_AW-1:0] A_DENSE_STEP = 12'h05C;
    localparam [AXIL_AW-1:0] A_DENSE_LAMBDA = 12'h060;
    localparam [AXIL_AW-1:0] A_DENSE_RHO  = 12'h064;
    localparam [AXIL_AW-1:0] A_DENSE_THETA = 12'h068;
    localparam [AXIL_AW-1:0] A_DENSE_DAMP = 12'h06C;
    localparam [AXIL_AW-1:0] A_MU_SHIFT   = 12'h070;
    localparam [AXIL_AW-1:0] A_CTX_BASE   = 12'h100;
    localparam [DATA_W-1:0] Q_ONE  = {{(DATA_W-Q_FRAC_W-1){1'b0}}, 1'b1, {Q_FRAC_W{1'b0}}};
    localparam [DATA_W-1:0] Q_HALF = {{(DATA_W-Q_FRAC_W){1'b0}}, 1'b1, {(Q_FRAC_W-1){1'b0}}};

    assign s_axi_awready = !s_axi_bvalid;
    assign s_axi_wready  = !s_axi_bvalid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    wire wr_fire = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
    wire rd_fire = s_axi_arvalid && s_axi_arready;
    wire ctx_addr_hit_wr = (s_axi_awaddr >= A_CTX_BASE);
    wire ctx_addr_hit_rd = (s_axi_araddr >= A_CTX_BASE);
    wire [CTX_AW-1:0] ctx_wr_index = (s_axi_awaddr - A_CTX_BASE) >> 3;
    wire ctx_wr_word = s_axi_awaddr[2];
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
            cfg_dbg_rd_en <= 1'b0;
            cfg_dbg_rd_addr <= {CTX_AW{1'b0}};
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

            if (wr_fire) begin
                s_axi_bvalid <= 1'b1;
                if (ctx_addr_hit_wr) begin
                    cfg_wr_en <= 1'b1;
                    cfg_wr_addr <= ctx_wr_index;
                    cfg_wr_word <= ctx_wr_word;
                    cfg_wr_data <= s_axi_wdata;
                end else begin
                    case (s_axi_awaddr)
                        A_CTRL: begin
                            start_pulse <= s_axi_wdata[0];
                            soft_reset_pulse <= s_axi_wdata[1];
                            clear_error_pulse <= s_axi_wdata[2];
                            if (s_axi_wdata[0] || s_axi_wdata[2]) begin
                                done_latched <= 1'b0;
                                error_latched <= 1'b0;
                                error_code_latched <= 4'd0;
                            end
                        end
                        A_M_SIZE:     m_size <= s_axi_wdata[IDX_W-1:0];
                        A_N_SIZE:     n_size <= s_axi_wdata[IDX_W-1:0];
                        A_K_PARAM:    k_param <= s_axi_wdata[7:0];
                        A_Y_DDR:      y_ddr_addr <= s_axi_wdata;
                        A_X_DDR:      x_ddr_addr <= s_axi_wdata;
                        A_SEED:       seed <= s_axi_wdata;
                        A_PHI_SCALE:  phi_scale_q8_8 <= s_axi_wdata[DATA_W-1:0];
                        A_MAX_ITER:   max_iter <= s_axi_wdata[15:0];
                        A_TOL:        tol_sq_q16_16 <= s_axi_wdata;
                        A_FLAGS:      flags <= s_axi_wdata;
                        A_DENSE_STEP: dense_step_q16_16 <= s_axi_wdata;
                        A_DENSE_LAMBDA: dense_lambda_q8_8 <= s_axi_wdata[DATA_W-1:0];
                        A_DENSE_RHO:  dense_rho_q8_8 <= s_axi_wdata[DATA_W-1:0];
                        A_DENSE_THETA: dense_theta_q8_8 <= s_axi_wdata[DATA_W-1:0];
                        A_DENSE_DAMP: dense_damp_q8_8 <= s_axi_wdata[DATA_W-1:0];
                        A_MU_SHIFT:   mu_shift_cfg <= s_axi_wdata[3:0];
                        A_PROG_BASE:  prog_base <= s_axi_wdata[CTX_AW-1:0];
                        A_PROG_LEN:   prog_len <= s_axi_wdata[CTX_AW:0];
                        default: begin
                        end
                    endcase
                end
            end

            if (rd_fire) begin
                s_axi_rvalid <= 1'b1;
                if (ctx_addr_hit_rd) begin
                    cfg_dbg_rd_en <= 1'b1;
                    cfg_dbg_rd_addr <= ctx_rd_index;
                    case (ctx_rd_word)
                        1'b0: s_axi_rdata <= cfg_dbg_rd_data[31:0];
                        1'b1: s_axi_rdata <= cfg_dbg_rd_data[63:32];
                        default: s_axi_rdata <= 32'd0;
                    endcase
                end else begin
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
                        default: s_axi_rdata <= 32'd0;
                    endcase
                end
            end
        end
    end

endmodule
