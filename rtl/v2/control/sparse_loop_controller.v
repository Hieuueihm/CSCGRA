module sparse_loop_controller #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W = 10,
    parameter integer MAX_M = 128,
    parameter integer MAX_N = 128,
    parameter integer MAX_K = 16,
    parameter integer REFINE_ITERS = 128
)(
    input wire clk,
    input wire rst_n,
    input wire ctx_valid,
    input wire [63:0] ctx_word,
    input wire start,
    input wire [3:0] op,
    input wire [IDX_W-1:0] m_size,
    input wire [IDX_W-1:0] n_size,
    input wire [7:0] k_active,
    input wire [5:0] support_depth0,
    input wire [31:0] seed,
    input wire [3:0] mu_shift_cfg,
    input wire [DATA_W-1:0] scale_q,
    input wire [1:0] phi_kind,
    input wire [COLS*DATA_W-1:0] phi_bus,
    input wire [COLS*64-1:0] pe_rhs_product_bus,
    input wire [COLS*64-1:0] pe_corr_acc_bus,
    input wire [SCALAR_W-1:0] last_result_value,
    input wire [IDX_W-1:0] last_result_idx,
    output reg [COLS*DATA_W-1:0] pe_rhs_phi_bus,
    output reg [COLS*DATA_W-1:0] pe_rhs_y_bus,
    output reg pe_rhs_active,
    output wire pe_sparse_clear,
    output reg pe_corr_acc_clear,
    output reg pe_corr_acc_en,
    output reg [3:0] pe_sparse_op,
    output reg ls_wide_mul_active,
    output wire ls_wide_vertical_active,
    output wire [4:0] ls_wide_vertical_tag,
    output reg [4*COLS*DATA_W-1:0] ls_wide_a_bus,
    output reg [4*COLS*DATA_W-1:0] ls_wide_b_bus,
    input wire [4*COLS*64-1:0] ls_wide_product_bus,
    output reg factor_pipe_valid,
    output reg [4:0] factor_pipe_tag,
    output reg [IDX_W-1:0] factor_pipe_value,
    output wire [5:0] factor_pipe_cache_k,
    output wire [MAX_K*IDX_W-1:0] factor_pipe_cache_bus,
    input wire factor_pipe_resp_valid,
    input wire [4:0] factor_pipe_resp_tag,
    input wire [IDX_W-1:0] factor_pipe_resp_value,
    input wire [MAX_K-1:0] factor_pipe_resp_match_mask,
    output wire corr_stream_valid,
    output wire corr_stream_done,
    output wire [IDX_W-1:0] corr_stream_base_idx,
    output wire [COLS-1:0] corr_stream_lane_valid,
    output wire [COLS*DATA_W-1:0] corr_stream_data,
    input wire corr_stream_active,
    input wire corr_stream_post_update_x,
    input wire corr_stream_post_refine_support,
    input wire corr_stream_ready,
    input wire [IDX_W-1:0] support0,
    input wire [IDX_W-1:0] support1,
    input wire [IDX_W-1:0] support2,
    input wire [IDX_W-1:0] support3,
    input wire [IDX_W-1:0] support4,
    input wire [IDX_W-1:0] support5,
    input wire [IDX_W-1:0] support6,
    input wire [IDX_W-1:0] support7,
    input wire [IDX_W-1:0] support8,
    input wire [IDX_W-1:0] support9,
    input wire [IDX_W-1:0] support10,
    input wire [IDX_W-1:0] support11,
    input wire [IDX_W-1:0] support12,
    input wire [IDX_W-1:0] support13,
    input wire [IDX_W-1:0] support14,
    input wire [IDX_W-1:0] support15,
    input wire [IDX_W-1:0] support16,
    input wire [IDX_W-1:0] support17,
    input wire [IDX_W-1:0] support18,
    input wire [IDX_W-1:0] support19,
    input wire [IDX_W-1:0] support20,
    input wire [IDX_W-1:0] support21,
    input wire [IDX_W-1:0] support22,
    input wire [IDX_W-1:0] support23,
    input wire [IDX_W-1:0] support24,
    input wire [IDX_W-1:0] support25,
    input wire [IDX_W-1:0] support26,
    input wire [IDX_W-1:0] support27,
    input wire [IDX_W-1:0] support28,
    input wire [IDX_W-1:0] support29,
    input wire [IDX_W-1:0] support30,
    input wire [IDX_W-1:0] support31,
    output reg [MEM_AW-1:0] rd_addr,
    input wire [COLS*DATA_W-1:0] rd_data,
    output reg [COLS*MEM_AW-1:0] wr_addr,
    output reg [COLS*DATA_W-1:0] wr_data,
    output reg [COLS-1:0] wr_en,
    output wire mesh_ctx_valid,
    output wire [63:0] mesh_ctx_word,
    output wire [1:0] mesh_ctx_mode,
    output wire [IDX_W-1:0] mesh_ctx_base_idx,
    output wire [IDX_W-1:0] mesh_ctx_limit,
    output wire [DATA_W-1:0] mesh_ctx_threshold,
    output wire [3:0] mesh_ctx_shift,
    output wire [COLS*DATA_W-1:0] mesh_ctx_x_bus,
    output wire [COLS*DATA_W-1:0] mesh_ctx_delta_bus,
    output wire [COLS-1:0] mesh_ctx_keep_bus,
    input  wire [COLS*DATA_W-1:0] mesh_ctx_commit_data,
    output reg busy,
    output reg done,
    output reg [SCALAR_W-1:0] result
);

localparam [6:0] S_IDLE=0, S_PRIME=1, S_ACC=3, S_WX=5, S_WR=7, S_DONE=8, S_SCAN=10, S_SOLVE_INIT=11, S_ELIM_START=12, S_ELIM_ROW=13, S_ELIM_UPDATE=14, S_BACK_INIT=15, S_BACK_ACC=16, S_BACK_DIV=17, S_SOLVE_DONE=18, S_ACC_RHS=19, S_ACC_GRAM=20, S_WR_ACC_INIT=21, S_ACC_PE_WAIT3=22, S_BACK_PREP=23, S_ELIM_PREP=24, S_ELIM_MUL=25, S_BACK_MUL=26, S_BACK_UPDATE=27, S_DIV_INIT=28, S_DIV_STEP=29, S_ELIM_DIV_DONE=30, S_BACK_DIV_DONE=31, S_CORR_INIT=34, S_CORR_SCAN=35, S_CORR_ACC=36, S_CORR_WRITE=37, S_IHT_X_WAIT=38, S_IHT_SCORE_WAIT=39, S_LOAD_COEFF_WAIT=40, S_PRUNE_X_WAIT=41, S_IHT_SCORE_READ=42, S_IHT_X_READ=43, S_PRUNE_X_READ=44, S_LOAD_COEFF_READ=45, S_LOAD_COEFF_CAP=46, S_ACC_PE_WAIT=47, S_GRAM_PE_WAIT=48, S_GRAM_PE_WAIT2=49, S_RESID_PE_WAIT=50, S_ACC_PE_WAIT2=53, S_CORR_PE_WAIT=54, S_CORR_LATCH=57,
S_CACHE_BUILD=56, S_SCAN_DIRECT=55,
S_MP_X_READ=70, S_MP_X_WAIT=71, S_MP_DIV_PREP=72, S_MP_X_WRITE=73, S_MP_DIV_DONE=74, S_MP_SCORE_CAP=75, S_MP_X_CAP=76, S_SCAN_DIRECT_STEP=77, S_CACHE_BUILD_STEP=78,
S_LS_CLEAR_START=86, S_LS_CLEAR_WAIT=87, S_SOLVE_SYM_READ=88, S_SOLVE_SYM_WAIT=89, S_SOLVE_SYM_WRITE=90, S_SOLVE_SYM_WRITE_WAIT=91,
S_ELIM_ROW_READ=92, S_ELIM_ROW_WAIT=93, S_ELIM_UPDATE_START=94, S_ELIM_UPDATE_WAIT=95, S_BACK_ACC_READ=96, S_BACK_ACC_WAIT=97, S_BACK_PREP_READ=98, S_BACK_PREP_WAIT=99, S_GRAM_ACC_WAIT=100, S_SCAN_DIRECT_LATCH=101, S_RHS_INIT_WAIT=103, S_ELIM_RHS_READ_WAIT=104, S_ELIM_RHS_UPDATE_WAIT=105, S_BACK_RHS_READ=106, S_BACK_RHS_READ_WAIT=107;
localparam [6:0] S_IHT_MESH_WAIT=108, S_IHT_MESH_WRITE=110, S_PRUNE_MESH_WAIT=111, S_PRUNE_MESH_WRITE=113, S_WR_MESH_WAIT=114, S_WR_MESH_COMMIT=116, S_WX_COMMIT=117, S_WX_CLEAR=4, S_DELTA_CLEAR_START=6, S_DELTA_CLEAR_WAIT=9;
localparam [6:0] S_LDL_INIT=58, S_LDL_DIAG_READ=59, S_LDL_DIAG_WAIT=60,
S_LDL_DIAG_GATHER=61, S_LDL_DIAG_GATHER_WAIT=62, S_LDL_DIAG_MUL1=63,
S_LDL_DIAG_MUL1_WAIT=64, S_LDL_DIAG_MUL2=65, S_LDL_DIAG_MUL2_WAIT=66,
S_LDL_DIAG_WRITE=67, S_LDL_DIAG_WRITE_WAIT=68, S_LDL_INV_DIV=69,
S_LDL_INV_DONE=79, S_LDL_ROW_INIT=80,
S_LDL_ROW_A_WAIT=82, S_LDL_ROW_P_WAIT=84,
S_LDL_ROW_MUL1=85, S_LDL_ROW_MUL2=119, S_LDL_ROW_FINAL_MUL=121,
S_LDL_ROW_FINAL_WAIT=122,
S_LDL_ROW_WRITE_WAIT=124;
localparam [6:0] S_FACTOR_CHECK_INIT=125, S_FACTOR_CHECK_SCAN=126,
                 S_FACTOR_CHECK_DONE=127;
localparam [6:0] S_FUSED_UPDATE_CAPTURE=7'd2;
localparam [6:0] S_GP_DIV_DONE=7'd118;
// Registered commit boundary for the GP x update.  GP is the only score
// update which multiplies an SPM value by the line-search alpha; committing
// it directly in S_IHT_SCORE_READ formed an SPM -> DSP -> saturation -> SPM
// path in one clock.
localparam [6:0] S_GP_UPDATE_COMMIT=7'd51,
                 S_GP_UPDATE_OPERANDS=7'd52,
                 S_GP_UPDATE_MUL=7'd81,
                 S_GP_UPDATE_SAT=7'd83;
localparam [3:0] OP_REFINE=4'd0, OP_CORR=4'd1, OP_IHT_UPDATE=4'd2, OP_RESID=4'd3, OP_PRUNE_X=4'd4, OP_MP_UPDATE=4'd5, OP_REFINE_SPARSE=4'd6, OP_GRAD_STEP=4'd7, OP_CORR_UPDATE=4'd8, OP_GP_PROJECT=4'd9, OP_GP_UPDATE=4'd10; // 9/10: isolated canonical GP project/update
localparam [1:0] MESH_CTX_NONE=2'd0, MESH_CTX_UPDATE=2'd1, MESH_CTX_PRUNE=2'd2, MESH_CTX_RESID=2'd3;
// Mesh tokens bypass the generic core-input register and advance through the
// registered PE0->PE1->PE2->PE3 south links in three clocks.
localparam [3:0] MESH_CTX_WAIT_CYCLES = 4'd3;
localparam [4:0] RHS_BLOCK_STRIDE = COLS;
localparam [4:0] LS_ROW_UPDATE_STRIDE = COLS;
localparam [3:0] LS_OP_CLEAR=4'd0, LS_OP_WRITE=4'd1, LS_OP_READ2=4'd2, LS_OP_ACC_BLOCK=4'd3, LS_OP_ROW_UPDATE=4'd4, LS_OP_RHS_WRITE=4'd5, LS_OP_RHS_READ=4'd6, LS_OP_RHS_UPDATE=4'd7, LS_OP_READ4=4'd8, LS_OP_WRITE4=4'd9, LS_OP_ACC4=4'd10, LS_OP_CLEAR_ROW=4'd11;
localparam [1:0] FACTOR_REUSE_NONE=2'd0, FACTOR_REUSE_EXACT=2'd1,
                 FACTOR_REUSE_PREFIX=2'd2;

localparam [31:0] LFSR_TAPS = 32'h80200003;
localparam [31:0] DEFAULT_SEED = 32'hDEADBEEF;
localparam signed [DATA_W-1:0] DATA_MIN = {1'b1, {(DATA_W-1){1'b0}}};

wire [3:0] mu_shift_eff = (mu_shift_cfg > 4'd15) ? 4'd15 : mu_shift_cfg;

function [31:0] galois_step;
    input [31:0] state;
    reg [31:0] shifted;
    begin
        shifted = {1'b0, state[31:1]};
        if (state[0])
            galois_step = shifted ^ LFSR_TAPS;
        else
            galois_step = shifted;
    end
endfunction

function [31:0] lfsr_advance;
    input [31:0] state;
    input [IDX_W:0] steps;
    integer adv_i;
    begin
        lfsr_advance = state;
        for (adv_i = 0; adv_i < MAX_N; adv_i = adv_i + 1) begin
            if (adv_i < steps)
                lfsr_advance = galois_step(lfsr_advance);
        end
    end
endfunction

function [31:0] lfsr_advance16;
    input [31:0] state;
    input [4:0] steps;
    integer adv16_i;
    begin
        lfsr_advance16 = state;
        for (adv16_i = 0; adv16_i < 16; adv16_i = adv16_i + 1) begin
            if (adv16_i < steps)
                lfsr_advance16 = galois_step(lfsr_advance16);
        end
    end
endfunction
function [31:0] lfsr_advance32;
    input [31:0] state;
    input [5:0] steps;
    integer adv32_i;
    begin
        lfsr_advance32 = state;
        for (adv32_i = 0; adv32_i < 32; adv32_i = adv32_i + 1) begin
            if (adv32_i < steps)
                lfsr_advance32 = galois_step(lfsr_advance32);
        end
    end
endfunction
`include "sparse_loop_lfsr_jump.vh"

function signed [DATA_W-1:0] phi_from_lfsr_state;
    input [31:0] state;
    begin
        phi_from_lfsr_state = state[0] ? scale_q : ((~scale_q) + 1'b1);
    end
endfunction


function signed [63:0] mul_s24_s24;
    input signed [DATA_W-1:0] a;
    input signed [DATA_W-1:0] b;
    reg signed [63:0] a_ext;
    reg signed [63:0] b_ext;
    begin
        a_ext = {{(64-DATA_W){a[DATA_W-1]}}, a};
        b_ext = {{(64-DATA_W){b[DATA_W-1]}}, b};
        mul_s24_s24 = a_ext * b_ext;
    end
endfunction

function signed [DATA_W-1:0] sat_s24;
    input signed [63:0] value;
    begin
        if (value > 64'sd8388607)
            sat_s24 = 24'sh7fffff;
        else if (value < -64'sd8388608)
            sat_s24 = 24'sh800000;
        else
            sat_s24 = value[DATA_W-1:0];
    end
endfunction

function [IDX_W-1:0] support_at;
    input [4:0] rank;
    begin
        case (rank)
            0: support_at = support0;
            1: support_at = support1;
            2: support_at = support2;
            3: support_at = support3;
            4: support_at = support4;
            5: support_at = support5;
            6: support_at = support6;
            7: support_at = support7;
            8: support_at = support8;
            9: support_at = support9;
            10: support_at = support10;
            11: support_at = support11;
            12: support_at = support12;
            13: support_at = support13;
            14: support_at = support14;
            default: support_at = support15;
        endcase
    end
endfunction



wire ctx_sparse_uop = ctx_valid && (ctx_word[63:60] == 4'h1) && (ctx_word[59:56] == 4'd8) && (ctx_word[27:24] == 4'h8);
wire [3:0] ctx_sparse_op = ctx_word[23:20];
wire [3:0] op_sel = ctx_sparse_uop ? ctx_sparse_op : op;

reg [6:0] state;
reg [3:0] active_op;
reg [IDX_W-1:0] write_idx;
reg [IDX_W-1:0] write_limit;
reg [DATA_W-1:0] write_value;
reg phase_residual;
integer lane;
reg [MEM_AW-1:0] base_addr;
reg signed [63:0] acc_num;
reg signed [63:0] acc_den;
reg signed [63:0] acc_num1;
reg signed [63:0] acc_den01;
reg signed [63:0] acc_den11;
reg signed [63:0] gp_num_acc_q;
reg signed [63:0] gp_den_acc_q;
reg signed [63:0] gp_alpha_q;
reg signed [DATA_W-1:0] gp_update_x_q;
reg signed [DATA_W-1:0] gp_update_grad_q;
reg signed [DATA_W-1:0] gp_update_alpha_q;
reg gp_update_support_q;
reg signed [63:0] gp_update_product_q;
reg signed [63:0] gp_update_sum_q;
reg signed [DATA_W-1:0] gp_update_value_q;
reg signed [DATA_W-1:0] y_cur;
reg signed [DATA_W-1:0] phi_cur;
reg signed [DATA_W-1:0] phi1_cur;
reg signed [DATA_W-1:0] write_value_now;
reg signed [127:0] k2_a00;
reg signed [127:0] k2_a01;
reg signed [127:0] k2_a11;
reg signed [127:0] k2_b0;
reg signed [127:0] k2_b1;
reg signed [127:0] k2_det;
reg [7:0] active_k;
// Stable, local fan-out source for the LS/residual datapaths.  KEEP prevents
// Vivado from merging this timing-isolation register back into the support-set
// depth register; MAX_FANOUT allows local replicas near the four PE rows.
(* keep = "true", max_fanout = 16 *) reg [5:0] active_k_count_q;
reg signed [63:0] rhs [0:MAX_K-1];
// One measurement sample is reused across every four-row RHS block.  Capture
// it in S_ACC, the existing setup cycle, so the following PE issue states do
// not carry a direct BRAM-output path into the MAC/accumulator cone.
reg signed [DATA_W-1:0] rhs_y_sample_q;
// Timing boundary between the four-row PE multiplier wavefront and the RHS
// accumulator.  The existing PE wait schedule makes the products valid while
// leaving S_ACC_PE_WAIT2, so this register does not add a controller cycle.
reg [COLS*64-1:0] rhs4_product_q;
reg signed [DATA_W-1:0] coeff_mem [0:MAX_K-1];
localparam integer GE_MAT_W = 56;
reg signed [63:0] ge_x [0:MAX_K-1];
reg signed [63:0] ge_factor;
reg signed [63:0] ge_acc;
reg signed [63:0] ge_diag;
reg signed [63:0] ge_value;
reg signed [63:0] ge_div_num;
reg signed [63:0] ge_div_den;
reg signed [63:0] ge_mul_a;
reg signed [63:0] ge_mul_b;
reg signed [63:0] ge_mul_c;
reg signed [127:0] ge_mul_p;
wire signed [63:0] back_mul_a_w = {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w};
wire signed [63:0] back_mul_b_w = ge_x[back_j];
(* use_dsp = "no" *) wire signed [127:0] back_mul_p_w = $signed(back_mul_a_w) * $signed(back_mul_b_w);
reg ls_start_q;
reg [3:0] ls_op_q;
reg [4:0] ls_row_a_q;
reg [4:0] ls_col_a_q;
reg [4:0] ls_row_b_q;
reg [4:0] ls_col_b_q;
reg [4:0] ls_row_base_q;
reg [COLS-1:0] ls_lane_valid_q;
reg [4*COLS-1:0] ls_acc4_lane_valid_q;
reg [3:0] ls_acc4_col_valid_q;
reg ls_acc4_payload_valid_q;
reg ls_row_update_block_q;
reg signed [GE_MAT_W-1:0] ls_wdata_q;
reg signed [4*GE_MAT_W-1:0] ls_write4_wdata_q;
reg [3:0] ls_write4_valid_q;
reg signed [63:0] ls_factor_q;
reg signed [63:0] ls_rhs_wdata_q;
wire ls_busy_w;
wire ls_done_w;
wire ls_acc4_credit_w;
wire [4*COLS*64-1:0] ls_acc4_product_q_bus;
// Back-solve READ4 uses only controller registers for its address.  Decode the
// dedicated command state directly at the service boundary so the request is
// accepted on the READ -> WAIT edge instead of one clock after ls_start_q.
// Other LS operations retain the registered command path unchanged.
wire back_read4_fast_start_w = (state == S_BACK_RHS_READ);
wire ls_start_w = (ls_start_q &&
    ((ls_op_q != LS_OP_ACC4) || ls_acc4_payload_valid_q)) |
    back_read4_fast_start_w;
wire [3:0] ls_op_w = back_read4_fast_start_w ? LS_OP_READ4 : ls_op_q;
wire [4:0] ls_row_a_w = back_read4_fast_start_w ? ldlt_p_base_q : ls_row_a_q;
wire [4:0] ls_col_a_w = back_read4_fast_start_w ? back_i : ls_col_a_q;
wire [4:0] ls_row_b_w = back_read4_fast_start_w ? ldlt_p_base_q : ls_row_b_q;
wire [4:0] ls_col_b_w = back_read4_fast_start_w ? back_i : ls_col_b_q;
wire signed [GE_MAT_W-1:0] ls_rdata_a_w;
wire signed [GE_MAT_W-1:0] ls_rdata_b_w;
wire signed [4*GE_MAT_W-1:0] ls_read4_rdata_w;
wire signed [GE_MAT_W-1:0] ls_update_value_w;
wire signed [63:0] ls_rhs_rdata_w;
ls_matrix_service #(
    .MAX_K(MAX_K),
    .GE_W(GE_MAT_W),
    .LANES(COLS),
    .ENABLE_ROW_UPDATE_BLOCK(1),
    .ROW_UPDATE_LANES(LS_ROW_UPDATE_STRIDE)
) u_ls_matrix_service (
    .clk(clk),
    .rst_n(rst_n),
    .start(ls_start_w),
    .op(ls_op_w),
    .row_a(ls_row_a_w),
    .col_a(ls_col_a_w),
    .row_b(ls_row_b_w),
    .col_b(ls_col_b_w),
    .row_base(ls_row_base_q),
    .lane_valid(ls_lane_valid_q),
    .row_update_block(ls_row_update_block_q),
    .lane_add(pe_rhs_product_bus),
    .lane_add4(ls_acc4_product_q_bus),
    .acc4_lane_valid(ls_acc4_lane_valid_q),
    .acc4_col_valid(ls_acc4_col_valid_q),
    .wdata(ls_wdata_q),
    .write4_wdata(ls_write4_wdata_q),
    .write4_valid(ls_write4_valid_q),
    .factor(ls_factor_q),
    .rhs_wdata(ls_rhs_wdata_q),
    .busy(ls_busy_w),
    .done(ls_done_w),
    .acc4_credit(ls_acc4_credit_w),
    .rdata_a(ls_rdata_a_w),
    .rdata_b(ls_rdata_b_w),
    .read4_rdata(ls_read4_rdata_w),
    .update_value(ls_update_value_w),
    .rhs_rdata(ls_rhs_rdata_w)
);

// Four-row wide multiplier built from the existing 24x24 PE multipliers.
// Each physical row evaluates one signed 64x64 product.  Sixteen unsigned
// 16x16 limb products are issued over the eight PE columns in two clocks;
// no extra wide multiplier or DSP array is instantiated in the LS controller.
localparam [3:0] WIDE_MUL_IDLE=4'd0, WIDE_MUL_ISSUE0=4'd1,
                 WIDE_MUL_ISSUE1=4'd2, WIDE_MUL_DRAIN=4'd3,
                 WIDE_MUL_VDRAIN1=4'd4, WIDE_MUL_VDRAIN2=4'd5,
                 WIDE_MUL_VDRAIN3=4'd6, WIDE_MUL_COMMIT=4'd7,
                 WIDE_MUL_FINAL=4'd8, WIDE_MUL_FINISH=4'd9;
reg [3:0] wide_mul_state_q;
reg wide_mul_start_q;
reg wide_mul_done_q;
reg wide_mul_vertical_done_q;
reg wide_mul_vertical_request_q;
reg wide_mul_vertical_q;
reg signed [4*64-1:0] wide_mul_a_q;
reg signed [4*64-1:0] wide_mul_b_q;
reg [63:0] wide_mul_abs_a_q [0:3];
reg [63:0] wide_mul_abs_b_q [0:3];
reg wide_mul_neg_q [0:3];
reg [127:0] wide_mul_acc_q [0:3];
reg [127:0] wide_mul_partial_q [0:3];
reg signed [127:0] wide_mul_result_q [0:3];
reg [COLS*64-1:0] wide_product_q [0:3];
reg wide_product_valid_q [0:3];
reg wide_product_part1_q [0:3];
reg [127:0] wide_partial_sum [0:3];
reg wide_row_product_valid [0:3];
reg wide_row_product_part1 [0:3];
reg [4:0] ldlt_k_q;
reg [4:0] ldlt_i_base_q;
reg [4:0] ldlt_p_base_q;
reg [2:0] ldlt_lane_q;
reg [3:0] ldlt_lane_valid_q;
reg signed [63:0] ldlt_diag_a_q;
reg signed [127:0] ldlt_diag_acc_q;
reg signed [63:0] ldlt_d_cur_q;
reg signed [63:0] ldlt_l_lane_q [0:3];
reg signed [63:0] ldlt_lkp_lane_q [0:3];
reg signed [63:0] ldlt_a_lane_q [0:3];
reg signed [63:0] ldlt_acc_lane_q [0:3];
reg signed [63:0] ldlt_d_mem [0:MAX_K-1];
// Border factorization is split into two tagged streams.  Preloading removes
// the matrix-read bubbles between transactions; every transaction still
// enters at PE0 as two 16x16-limb tokens and advances one physical row per
// clock before retirement at PE3.
(* ram_style = "distributed" *) reg signed [4*GE_MAT_W-1:0] ldlt_border_lip_cache_q [0:MAX_K-1];
(* ram_style = "distributed" *) reg signed [GE_MAT_W-1:0] ldlt_border_lkp_cache_q [0:MAX_K-1];
(* ram_style = "distributed" *) reg signed [4*64-1:0] ldlt_border_mul1_cache_q [0:MAX_K-1];
reg [4:0] ldlt_border_issue_p_q;
reg ldlt_border_issue_part_q;
reg ldlt_border_issue_phase_q;
reg [4:0] ldlt_border_mul1_complete_q;
reg [4:0] ldlt_border_mul2_complete_q;
reg [3:0] ldlt_border_mul1_slot_ready_q;
reg border_token_valid_q [0:3];
reg [4:0] border_token_tag_q [0:3];
reg border_token_part_q [0:3];
reg border_token_phase_q [0:3];
reg [3:0] border_token_neg_q [0:3];
// Narrow metadata stage aligned with the registered product egress of each PE.
reg border_product_valid_q [0:3];
reg [4:0] border_product_tag_q [0:3];
reg border_product_part_q [0:3];
reg border_product_phase_q [0:3];
reg [3:0] border_product_neg_q [0:3];
reg border_capture_valid_q [0:3];
reg [4:0] border_capture_tag_q [0:3];
reg border_capture_part_q [0:3];
reg border_capture_phase_q [0:3];
reg [3:0] border_capture_neg_q [0:3];
reg [COLS*64-1:0] border_product_q [0:3];
// One single-write scoreboard bank belongs to each physical PE row.  Data is
// never read without the associated capture/done valid, so the payload banks
// need no reset and can map to distributed RAM instead of resettable FFs.
(* ram_style = "distributed" *) reg signed [127:0] border_acc_bank0_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_acc_bank1_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_acc_bank2_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_acc_bank3_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_result_bank0_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_result_bank1_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_result_bank2_q [0:3];
(* ram_style = "distributed" *) reg signed [127:0] border_result_bank3_q [0:3];
reg border_done_pending_q;
reg [4:0] border_done_pending_tag_q;
reg border_done_pending_phase_q;
reg border_done_q;
reg [4:0] border_done_tag_q;
reg border_done_phase_q;
reg signed [63:0] border_operand_a [0:3];
reg signed [63:0] border_operand_b [0:3];
reg [63:0] border_operand_abs_a [0:3];
reg [63:0] border_operand_abs_b [0:3];
reg [3:0] border_ingress_neg;
// Narrow registered boundary for border operands.  The cache read and sign
// decode terminate here; the PE0 limb fanout starts from these local values.
reg [63:0] border_operand_abs_a_q [0:3];
reg [63:0] border_operand_abs_b_q [0:3];
reg border_operand_boundary_active_q;
reg [4:0] border_operand_boundary_tag_q;
reg border_operand_boundary_part_q;
reg border_operand_boundary_phase_q;
reg [3:0] border_operand_boundary_neg_q;
reg [127:0] border_partial_sum [0:3];
integer wide_row;
integer wide_col;
integer wide_part;
integer wide_a_limb;
integer wide_b_limb;
integer wide_shift;
integer acc4_valid_col;
integer border_row;
integer border_col;
integer border_part;
integer border_a_limb;
integer border_b_limb;
integer border_shift;
wire ldlt_border_stream_state_w = (state == S_LDL_ROW_MUL1) ||
                                  (state == S_LDL_ROW_MUL2);
wire ldlt_border_issue_active_w = ldlt_border_stream_state_w &&
                                  (ldlt_border_issue_p_q < ldlt_k_q) &&
                                  (!ldlt_border_issue_phase_q ||
                                   ldlt_border_mul1_slot_ready_q[ldlt_border_issue_p_q[1:0]]);
wire legacy_wide_vertical_active_w =
    (wide_mul_state_q != WIDE_MUL_IDLE) && wide_mul_vertical_q;
assign ls_wide_vertical_active = legacy_wide_vertical_active_w ||
                                 border_operand_boundary_active_q;
assign ls_wide_vertical_tag = border_operand_boundary_active_q ?
                              border_operand_boundary_tag_q : ldlt_i_base_q;
wire signed [127:0] ldlt_wide_q32_sum =
    ($signed(wide_mul_result_q[0]) >>> 32) +
    ($signed(wide_mul_result_q[1]) >>> 32) +
    ($signed(wide_mul_result_q[2]) >>> 32) +
    ($signed(wide_mul_result_q[3]) >>> 32);
wire signed [127:0] ldlt_wide_q16_sum =
    ($signed(wide_mul_result_q[0]) >>> 16) +
    ($signed(wide_mul_result_q[1]) >>> 16) +
    ($signed(wide_mul_result_q[2]) >>> 16) +
    ($signed(wide_mul_result_q[3]) >>> 16);

wire ls_rhs4_active = (state == S_ACC_PE_WAIT) ||
                       (state == S_ACC_PE_WAIT2) ||
                       (state == S_ACC_PE_WAIT3) ||
                       (state == S_ACC_RHS);
wire ls_gram4_active = (state == S_GRAM_PE_WAIT) ||
                       (state == S_GRAM_PE_WAIT2) ||
                       (state == S_ACC_GRAM);
wire ls_batch4_active = busy &&
                        ((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) &&
                        (ls_rhs4_active || ls_gram4_active);

wire [COLS*64-1:0] rhs4_product_bus;
assign ls_acc4_product_q_bus =
    {wide_product_q[3], wide_product_q[2], wide_product_q[1], wide_product_q[0]};
genvar rhs4_lane_g;
generate
    for (rhs4_lane_g = 0; rhs4_lane_g < COLS; rhs4_lane_g = rhs4_lane_g + 1) begin : gen_rhs4_product
        localparam integer RHS4_ROW = rhs4_lane_g % 4;
        assign rhs4_product_bus[rhs4_lane_g*64 +: 64] =
            ls_wide_product_bus[(RHS4_ROW*COLS+rhs4_lane_g)*64 +: 64];
    end
endgenerate

always @(*) begin
    ls_wide_mul_active = (wide_mul_state_q != WIDE_MUL_IDLE) ||
                         ls_batch4_active || ldlt_border_issue_active_w;
    ls_wide_a_bus = {4*COLS*DATA_W{1'b0}};
    ls_wide_b_bus = {4*COLS*DATA_W{1'b0}};
    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1)
        wide_partial_sum[wide_row] = 128'd0;
    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
        wide_row_product_valid[wide_row] = 1'b0;
        wide_row_product_part1[wide_row] = 1'b0;
    end

    // Capture four Gram columns into the existing row-local product banks.
    // ACC4 transfers this registered payload once and drains it locally over
    // four clocks, leaving the controller free to prepare the next batch.
    if (ls_gram4_active && (state == S_ACC_GRAM) &&
        (wide_mul_state_q == WIDE_MUL_IDLE)) begin
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            wide_row_product_valid[wide_row] = 1'b1;
            wide_row_product_part1[wide_row] = 1'b0;
        end
    end

    if (border_operand_boundary_active_q) begin
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            for (wide_col = 0; wide_col < COLS; wide_col = wide_col + 1) begin
                wide_part = (border_operand_boundary_part_q ? COLS : 0) + wide_col;
                wide_a_limb = wide_part >> 2;
                wide_b_limb = wide_part & 3;
                ls_wide_a_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                    {{(DATA_W-16){1'b0}}, border_operand_abs_a_q[wide_row][wide_a_limb*16 +: 16]};
                ls_wide_b_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                    {{(DATA_W-16){1'b0}}, border_operand_abs_b_q[wide_row][wide_b_limb*16 +: 16]};
            end
        end
    end else if (ls_batch4_active && (wide_mul_state_q == WIDE_MUL_IDLE)) begin
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            for (wide_col = 0; wide_col < COLS; wide_col = wide_col + 1) begin
                if ((rhs_block_base + wide_col) < active_k_count) begin
                    if (ls_rhs4_active && ((wide_col % 4) == wide_row)) begin
                        ls_wide_a_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                            phi_cache[rhs_block_base + wide_col];
                        ls_wide_b_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                            rhs_y_sample_q;
                    end else if (ls_gram4_active && ((acc_j + wide_row) < active_k_count)) begin
                        // Physical row r owns Gram column acc_j+r.
                        ls_wide_a_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                            phi_cache[rhs_block_base + wide_col];
                        ls_wide_b_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                            phi_cache[acc_j + wide_row];
                    end
                end
            end
        end
    end else if ((wide_mul_state_q == WIDE_MUL_ISSUE0) ||
        (wide_mul_state_q == WIDE_MUL_ISSUE1)) begin
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            for (wide_col = 0; wide_col < COLS; wide_col = wide_col + 1) begin
                wide_part = ((wide_mul_state_q == WIDE_MUL_ISSUE1) ? COLS : 0) + wide_col;
                wide_a_limb = wide_part >> 2;
                wide_b_limb = wide_part & 3;
                ls_wide_a_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                    {{(DATA_W-16){1'b0}}, wide_mul_abs_a_q[wide_row][wide_a_limb*16 +: 16]};
                ls_wide_b_bus[(wide_row*COLS+wide_col)*DATA_W +: DATA_W] =
                    {{(DATA_W-16){1'b0}}, wide_mul_abs_b_q[wide_row][wide_b_limb*16 +: 16]};
            end
        end
    end

    if (wide_mul_vertical_q) begin
        case (wide_mul_state_q)
            WIDE_MUL_DRAIN: begin
                wide_row_product_valid[0] = 1'b1;
                wide_row_product_part1[0] = 1'b0;
            end
            WIDE_MUL_VDRAIN1: begin
                wide_row_product_valid[0] = 1'b1;
                wide_row_product_part1[0] = 1'b1;
                wide_row_product_valid[1] = 1'b1;
                wide_row_product_part1[1] = 1'b0;
            end
            WIDE_MUL_VDRAIN2: begin
                wide_row_product_valid[1] = 1'b1;
                wide_row_product_part1[1] = 1'b1;
                wide_row_product_valid[2] = 1'b1;
                wide_row_product_part1[2] = 1'b0;
            end
            WIDE_MUL_VDRAIN3: begin
                wide_row_product_valid[2] = 1'b1;
                wide_row_product_part1[2] = 1'b1;
                wide_row_product_valid[3] = 1'b1;
                wide_row_product_part1[3] = 1'b0;
            end
            WIDE_MUL_COMMIT: begin
                wide_row_product_valid[3] = 1'b1;
                wide_row_product_part1[3] = 1'b1;
            end
            default: begin end
        endcase
    end else if ((wide_mul_state_q == WIDE_MUL_DRAIN) ||
                 (wide_mul_state_q == WIDE_MUL_COMMIT)) begin
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            wide_row_product_valid[wide_row] = 1'b1;
            wide_row_product_part1[wide_row] =
                (wide_mul_state_q == WIDE_MUL_COMMIT);
        end
    end

    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
        if (wide_product_valid_q[wide_row]) begin
            for (wide_col = 0; wide_col < COLS; wide_col = wide_col + 1) begin
                wide_part = (wide_product_part1_q[wide_row] ? COLS : 0) + wide_col;
                wide_a_limb = wide_part >> 2;
                wide_b_limb = wide_part & 3;
                wide_shift = (wide_a_limb + wide_b_limb) * 16;
                wide_partial_sum[wide_row] = wide_partial_sum[wide_row] +
                    ({64'd0, $unsigned(wide_product_q[wide_row][wide_col*64 +: 64])} << wide_shift);
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wide_mul_state_q <= WIDE_MUL_IDLE;
        wide_mul_done_q <= 1'b0;
        wide_mul_vertical_done_q <= 1'b0;
        wide_mul_vertical_q <= 1'b0;
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            wide_mul_abs_a_q[wide_row] <= 64'd0;
            wide_mul_abs_b_q[wide_row] <= 64'd0;
            wide_mul_neg_q[wide_row] <= 1'b0;
            wide_mul_acc_q[wide_row] <= 128'd0;
            wide_mul_partial_q[wide_row] <= 128'd0;
            wide_mul_result_q[wide_row] <= 128'sd0;
            wide_product_q[wide_row] <= {(COLS*64){1'b0}};
            wide_product_valid_q[wide_row] <= 1'b0;
            wide_product_part1_q[wide_row] <= 1'b0;
        end
    end else begin
        wide_mul_done_q <= 1'b0;
        wide_mul_vertical_done_q <= 1'b0;
        for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
            wide_product_valid_q[wide_row] <= wide_row_product_valid[wide_row];
            if (wide_row_product_valid[wide_row]) begin
                wide_product_q[wide_row] <=
                    ls_wide_product_bus[wide_row*COLS*64 +: COLS*64];
                wide_product_part1_q[wide_row] <= wide_row_product_part1[wide_row];
            end
        end
        case (wide_mul_state_q)
            WIDE_MUL_IDLE: begin
                if (wide_mul_start_q) begin
                    wide_mul_vertical_q <= wide_mul_vertical_request_q;
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                        wide_mul_abs_a_q[wide_row] <= wide_mul_a_q[wide_row*64+63] ?
                            -$signed(wide_mul_a_q[wide_row*64 +: 64]) : $signed(wide_mul_a_q[wide_row*64 +: 64]);
                        wide_mul_abs_b_q[wide_row] <= wide_mul_b_q[wide_row*64+63] ?
                            -$signed(wide_mul_b_q[wide_row*64 +: 64]) : $signed(wide_mul_b_q[wide_row*64 +: 64]);
                        wide_mul_neg_q[wide_row] <= wide_mul_a_q[wide_row*64+63] ^ wide_mul_b_q[wide_row*64+63];
                    end
                    wide_mul_state_q <= WIDE_MUL_ISSUE0;
                end
            end
            WIDE_MUL_ISSUE0: wide_mul_state_q <= WIDE_MUL_ISSUE1;
            WIDE_MUL_ISSUE1: wide_mul_state_q <= WIDE_MUL_DRAIN;
            WIDE_MUL_DRAIN: begin
                if (wide_mul_vertical_q)
                    wide_mul_state_q <= WIDE_MUL_VDRAIN1;
                else
                    wide_mul_state_q <= WIDE_MUL_COMMIT;
            end
            WIDE_MUL_VDRAIN1: begin
                wide_mul_acc_q[0] <= wide_partial_sum[0];
                wide_mul_state_q <= WIDE_MUL_VDRAIN2;
            end
            WIDE_MUL_VDRAIN2: begin
                wide_mul_partial_q[0] <= wide_partial_sum[0];
                wide_mul_acc_q[1] <= wide_partial_sum[1];
                wide_mul_state_q <= WIDE_MUL_VDRAIN3;
            end
            WIDE_MUL_VDRAIN3: begin
                if (wide_mul_neg_q[0])
                    wide_mul_result_q[0] <= -$signed(wide_mul_acc_q[0] + wide_mul_partial_q[0]);
                else
                    wide_mul_result_q[0] <= $signed(wide_mul_acc_q[0] + wide_mul_partial_q[0]);
                wide_mul_partial_q[1] <= wide_partial_sum[1];
                wide_mul_acc_q[2] <= wide_partial_sum[2];
                wide_mul_state_q <= WIDE_MUL_COMMIT;
            end
            WIDE_MUL_COMMIT: begin
                if (wide_mul_vertical_q) begin
                    if (wide_mul_neg_q[1])
                        wide_mul_result_q[1] <= -$signed(wide_mul_acc_q[1] + wide_mul_partial_q[1]);
                    else
                        wide_mul_result_q[1] <= $signed(wide_mul_acc_q[1] + wide_mul_partial_q[1]);
                    wide_mul_partial_q[2] <= wide_partial_sum[2];
                    wide_mul_acc_q[3] <= wide_partial_sum[3];
                end else begin
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1)
                        wide_mul_acc_q[wide_row] <= wide_partial_sum[wide_row];
                end
                wide_mul_state_q <= WIDE_MUL_FINAL;
            end
            WIDE_MUL_FINAL: begin
                if (wide_mul_vertical_q) begin
                    if (wide_mul_neg_q[2])
                        wide_mul_result_q[2] <= -$signed(wide_mul_acc_q[2] + wide_mul_partial_q[2]);
                    else
                        wide_mul_result_q[2] <= $signed(wide_mul_acc_q[2] + wide_mul_partial_q[2]);
                    // Isolate PE3's registered product from the final
                    // 128-bit add and completion edge.
                    wide_mul_partial_q[3] <= wide_partial_sum[3];
                end else begin
                    // All four rows capture the reduced part-1 limb here.
                    // FINISH only sees locally registered acc/partial data.
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1)
                        wide_mul_partial_q[wide_row] <= wide_partial_sum[wide_row];
                end
                wide_mul_state_q <= WIDE_MUL_FINISH;
            end
            WIDE_MUL_FINISH: begin
                if (wide_mul_vertical_q) begin
                    if (wide_mul_neg_q[3])
                        wide_mul_result_q[3] <= -$signed(wide_mul_acc_q[3] + wide_mul_partial_q[3]);
                    else
                        wide_mul_result_q[3] <= $signed(wide_mul_acc_q[3] + wide_mul_partial_q[3]);
                    wide_mul_vertical_done_q <= 1'b1;
                end else begin
                    for (wide_row = 0; wide_row < 4; wide_row = wide_row + 1) begin
                        if (wide_mul_neg_q[wide_row])
                            wide_mul_result_q[wide_row] <= -$signed(wide_mul_acc_q[wide_row] + wide_mul_partial_q[wide_row]);
                        else
                            wide_mul_result_q[wide_row] <= $signed(wide_mul_acc_q[wide_row] + wide_mul_partial_q[wide_row]);
                    end
                end
                wide_mul_done_q <= 1'b1;
                wide_mul_state_q <= WIDE_MUL_IDLE;
                wide_mul_vertical_q <= 1'b0;
            end
        endcase
    end
end

always @(*) begin
    border_ingress_neg = 4'd0;
    for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
        if (!ldlt_border_issue_phase_q) begin
            border_operand_a[border_row] =
                {{(64-GE_MAT_W){ldlt_border_lip_cache_q[ldlt_border_issue_p_q]
                    [border_row*GE_MAT_W+GE_MAT_W-1]}},
                 ldlt_border_lip_cache_q[ldlt_border_issue_p_q]
                    [border_row*GE_MAT_W +: GE_MAT_W]};
            border_operand_b[border_row] =
                {{(64-GE_MAT_W){ldlt_border_lkp_cache_q[ldlt_border_issue_p_q]
                    [GE_MAT_W-1]}}, ldlt_border_lkp_cache_q[ldlt_border_issue_p_q]};
        end else begin
            border_operand_a[border_row] =
                ldlt_border_mul1_cache_q[ldlt_border_issue_p_q][border_row*64 +: 64];
            border_operand_b[border_row] =
                ldlt_d_mem[ldlt_border_issue_p_q];
        end
        border_ingress_neg[border_row] =
            border_operand_a[border_row][63] ^ border_operand_b[border_row][63];
        border_operand_abs_a[border_row] = border_operand_a[border_row][63] ?
            -$signed(border_operand_a[border_row]) : $signed(border_operand_a[border_row]);
        border_operand_abs_b[border_row] = border_operand_b[border_row][63] ?
            -$signed(border_operand_b[border_row]) : $signed(border_operand_b[border_row]);
    end

    for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
        border_partial_sum[border_row] = 128'd0;
        if (border_capture_valid_q[border_row]) begin
            for (border_col = 0; border_col < COLS; border_col = border_col + 1) begin
                border_part = (border_capture_part_q[border_row] ? COLS : 0) + border_col;
                border_a_limb = border_part >> 2;
                border_b_limb = border_part & 3;
                border_shift = (border_a_limb + border_b_limb) * 16;
                border_partial_sum[border_row] = border_partial_sum[border_row] +
                    ({64'd0, $unsigned(border_product_q[border_row][border_col*64 +: 64])} << border_shift);
            end
        end
    end
end

// Metadata follows the same registered south links as the operand bundle.
// Products are captured before the shifted limb reduction so the PE
// multiplier is never on the same timing path as the 128-bit adder tree.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        border_operand_boundary_active_q <= 1'b0;
        border_operand_boundary_tag_q <= 5'd0;
        border_operand_boundary_part_q <= 1'b0;
        border_operand_boundary_phase_q <= 1'b0;
        border_operand_boundary_neg_q <= 4'd0;
        for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
            border_operand_abs_a_q[border_row] <= 64'd0;
            border_operand_abs_b_q[border_row] <= 64'd0;
        end
        border_done_pending_q <= 1'b0;
        border_done_pending_tag_q <= 5'd0;
        border_done_pending_phase_q <= 1'b0;
        border_done_q <= 1'b0;
        border_done_tag_q <= 5'd0;
        border_done_phase_q <= 1'b0;
        for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
            border_token_valid_q[border_row] <= 1'b0;
            border_token_tag_q[border_row] <= 5'd0;
            border_token_part_q[border_row] <= 1'b0;
            border_token_phase_q[border_row] <= 1'b0;
            border_token_neg_q[border_row] <= 4'd0;
            border_product_valid_q[border_row] <= 1'b0;
            border_product_tag_q[border_row] <= 5'd0;
            border_product_part_q[border_row] <= 1'b0;
            border_product_phase_q[border_row] <= 1'b0;
            border_product_neg_q[border_row] <= 4'd0;
            border_capture_valid_q[border_row] <= 1'b0;
            border_capture_tag_q[border_row] <= 5'd0;
            border_capture_part_q[border_row] <= 1'b0;
            border_capture_phase_q[border_row] <= 1'b0;
            border_capture_neg_q[border_row] <= 4'd0;
            border_product_q[border_row] <= {(COLS*64){1'b0}};
        end
    end else begin
        border_operand_boundary_active_q <= ldlt_border_issue_active_w;
        border_operand_boundary_tag_q <= ldlt_border_issue_p_q;
        border_operand_boundary_part_q <= ldlt_border_issue_part_q;
        border_operand_boundary_phase_q <= ldlt_border_issue_phase_q;
        border_operand_boundary_neg_q <= border_ingress_neg;
        for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
            border_operand_abs_a_q[border_row] <= border_operand_abs_a[border_row];
            border_operand_abs_b_q[border_row] <= border_operand_abs_b[border_row];
        end
        border_done_q <= border_done_pending_q;
        if (border_done_pending_q) begin
            border_done_tag_q <= border_done_pending_tag_q;
            border_done_phase_q <= border_done_pending_phase_q;
        end
        border_done_pending_q <= 1'b0;

        border_token_valid_q[0] <= border_operand_boundary_active_q;
        border_token_tag_q[0] <= border_operand_boundary_tag_q;
        border_token_part_q[0] <= border_operand_boundary_part_q;
        border_token_phase_q[0] <= border_operand_boundary_phase_q;
        border_token_neg_q[0] <= border_operand_boundary_neg_q;
        for (border_row = 1; border_row < 4; border_row = border_row + 1) begin
            border_token_valid_q[border_row] <= border_token_valid_q[border_row-1];
            border_token_tag_q[border_row] <= border_token_tag_q[border_row-1];
            border_token_part_q[border_row] <= border_token_part_q[border_row-1];
            border_token_phase_q[border_row] <= border_token_phase_q[border_row-1];
            border_token_neg_q[border_row] <= border_token_neg_q[border_row-1];
        end

        for (border_row = 0; border_row < 4; border_row = border_row + 1) begin
            border_product_valid_q[border_row] <= border_token_valid_q[border_row];
            if (border_token_valid_q[border_row]) begin
                border_product_tag_q[border_row] <= border_token_tag_q[border_row];
                border_product_part_q[border_row] <= border_token_part_q[border_row];
                border_product_phase_q[border_row] <= border_token_phase_q[border_row];
                border_product_neg_q[border_row] <= border_token_neg_q[border_row];
            end
            border_capture_valid_q[border_row] <= border_product_valid_q[border_row];
            if (border_product_valid_q[border_row]) begin
                border_capture_tag_q[border_row] <= border_product_tag_q[border_row];
                border_capture_part_q[border_row] <= border_product_part_q[border_row];
                border_capture_phase_q[border_row] <= border_product_phase_q[border_row];
                border_capture_neg_q[border_row] <= border_product_neg_q[border_row];
                border_product_q[border_row] <=
                    ls_wide_product_bus[border_row*COLS*64 +: COLS*64];
            end

        end

        if (border_capture_valid_q[3] && border_capture_part_q[3]) begin
            border_done_pending_q <= 1'b1;
            border_done_pending_tag_q <= border_capture_tag_q[3];
            border_done_pending_phase_q <= border_capture_phase_q[3];
        end
    end
end

// Keep payload storage out of the asynchronously-reset metadata process.  The
// valid pipeline guarantees that uninitialized entries are never observed.
always @(posedge clk) begin
    if (border_capture_valid_q[0]) begin
        if (!border_capture_part_q[0])
            border_acc_bank0_q[border_capture_tag_q[0][1:0]] <= border_partial_sum[0];
        else if (border_capture_neg_q[0][0])
            border_result_bank0_q[border_capture_tag_q[0][1:0]] <=
                -$signed(border_acc_bank0_q[border_capture_tag_q[0][1:0]] + border_partial_sum[0]);
        else
            border_result_bank0_q[border_capture_tag_q[0][1:0]] <=
                $signed(border_acc_bank0_q[border_capture_tag_q[0][1:0]] + border_partial_sum[0]);
    end
    if (border_capture_valid_q[1]) begin
        if (!border_capture_part_q[1])
            border_acc_bank1_q[border_capture_tag_q[1][1:0]] <= border_partial_sum[1];
        else if (border_capture_neg_q[1][1])
            border_result_bank1_q[border_capture_tag_q[1][1:0]] <=
                -$signed(border_acc_bank1_q[border_capture_tag_q[1][1:0]] + border_partial_sum[1]);
        else
            border_result_bank1_q[border_capture_tag_q[1][1:0]] <=
                $signed(border_acc_bank1_q[border_capture_tag_q[1][1:0]] + border_partial_sum[1]);
    end
    if (border_capture_valid_q[2]) begin
        if (!border_capture_part_q[2])
            border_acc_bank2_q[border_capture_tag_q[2][1:0]] <= border_partial_sum[2];
        else if (border_capture_neg_q[2][2])
            border_result_bank2_q[border_capture_tag_q[2][1:0]] <=
                -$signed(border_acc_bank2_q[border_capture_tag_q[2][1:0]] + border_partial_sum[2]);
        else
            border_result_bank2_q[border_capture_tag_q[2][1:0]] <=
                $signed(border_acc_bank2_q[border_capture_tag_q[2][1:0]] + border_partial_sum[2]);
    end
    if (border_capture_valid_q[3]) begin
        if (!border_capture_part_q[3])
            border_acc_bank3_q[border_capture_tag_q[3][1:0]] <= border_partial_sum[3];
        else if (border_capture_neg_q[3][3])
            border_result_bank3_q[border_capture_tag_q[3][1:0]] <=
                -$signed(border_acc_bank3_q[border_capture_tag_q[3][1:0]] + border_partial_sum[3]);
        else
            border_result_bank3_q[border_capture_tag_q[3][1:0]] <=
                $signed(border_acc_bank3_q[border_capture_tag_q[3][1:0]] + border_partial_sum[3]);
    end
end

`ifndef SYNTHESIS
// The phase overlap reuses four modulo-tag scoreboard slots.  Check a
// representative physical row against an independent product and verify that
// completions remain ordered; this caught unsafe cross-phase slot reuse during
// development without adding any synthesizable logic.
function signed [127:0] border_reference_mul;
    input signed [63:0] lhs;
    input signed [63:0] rhs;
    begin
        border_reference_mul = lhs * rhs;
    end
endfunction

reg signed [63:0] border_reference_lip;
reg signed [63:0] border_reference_lkp;
always @(posedge clk) begin
    if (border_done_q) begin
        if (!border_done_phase_q) begin
            border_reference_lip = {{(64-GE_MAT_W){ldlt_border_lip_cache_q[border_done_tag_q]
                [GE_MAT_W-1]}}, ldlt_border_lip_cache_q[border_done_tag_q][0 +: GE_MAT_W]};
            border_reference_lkp = {{(64-GE_MAT_W){ldlt_border_lkp_cache_q[border_done_tag_q]
                [GE_MAT_W-1]}}, ldlt_border_lkp_cache_q[border_done_tag_q]};
            if ($signed(border_result_bank0_q[border_done_tag_q[1:0]]) !==
                border_reference_mul(border_reference_lip, border_reference_lkp))
                $error("LDLT_BORDER_ASSERT MUL1 row0 mismatch tag=%0d", border_done_tag_q);
            if (border_done_tag_q != ldlt_border_mul1_complete_q)
                $error("LDLT_BORDER_ASSERT MUL1 completion order tag=%0d expected=%0d",
                       border_done_tag_q, ldlt_border_mul1_complete_q);
        end else begin
            if ($signed(border_result_bank0_q[border_done_tag_q[1:0]]) !==
                border_reference_mul(ldlt_border_mul1_cache_q[border_done_tag_q][0 +: 64],
                                     ldlt_d_mem[border_done_tag_q]))
                $error("LDLT_BORDER_ASSERT MUL2 row0 mismatch tag=%0d", border_done_tag_q);
            if (border_done_tag_q != ldlt_border_mul2_complete_q)
                $error("LDLT_BORDER_ASSERT MUL2 completion order tag=%0d expected=%0d",
                       border_done_tag_q, ldlt_border_mul2_complete_q);
        end
    end
end

reg wide_vertical_pe3_done_prev_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wide_vertical_pe3_done_prev_q <= 1'b0;
    end else begin
        if (wide_mul_vertical_done_q && !wide_vertical_pe3_done_prev_q)
            $error("PE_VERTICAL_ASSERT LDLT wide result committed before PE3 drain");
        wide_vertical_pe3_done_prev_q <=
            wide_mul_vertical_q && (wide_mul_state_q == WIDE_MUL_FINISH);
    end
end
`endif

reg [64:0] div_abs_num;
reg [63:0] div_abs_den;
reg [64:0] div_rem;
reg [64:0] div_quot;
reg [64:0] div_trial_rem;
reg [64:0] div_trial_quot;
reg [6:0] div_iter;
reg div_neg;
reg div_return_back;
reg div_return_mp;
reg div_return_ldlt;
reg div_return_gp;
reg [IDX_W-1:0] mp_idx_q;
reg signed [DATA_W-1:0] mp_score_q;
reg signed [DATA_W-1:0] mp_x_old_q;
reg signed [DATA_W-1:0] mp_x_new_q;
reg signed [63:0] mp_den_q;
reg signed [63:0] div_result;
reg [5:0] solve_i;
reg [5:0] solve_j;
reg [5:0] solve_k;
wire ldlt_shared_tail_state_w = (state == S_LDL_DIAG_GATHER_WAIT) ||
                                (state == S_ELIM_ROW_READ);
wire [5:0] ldlt_shared_tail_limit_w = (state == S_ELIM_ROW_READ) ?
                                      solve_i : {1'b0, ldlt_k_q};
wire ldlt_shared_tail_last_w = (ldlt_lane_q == 3) ||
                               ({1'b0, ldlt_p_base_q} +
                                {3'b000, ldlt_lane_q} + 1'b1 >=
                                ldlt_shared_tail_limit_w);
reg [4:0] acc_i;
reg [5:0] acc_j;
reg [5:0] back_i;
reg [5:0] back_j;
reg signed [127:0] residual_acc;
// A residual block contains at most eight signed 24x24 products. The exact
// block sum needs at most 51 signed bits, so keep the PE-row reduction at
// 64 bits and sign-extend only at the long-lived accumulator boundary.
reg signed [63:0] residual_row_partial [0:3];
reg signed [63:0] residual_pipe_sum_r1_q;
reg signed [63:0] residual_pipe_sum_r2_q;
reg signed [63:0] residual_pipe_sum_r3_q;
reg signed [63:0] residual_pipe_sum_r1_delay_q;
reg signed [63:0] residual_pipe_row1_product_q;
reg signed [63:0] residual_pipe_row2_product_q;
reg signed [63:0] residual_pipe_row3_product_q;
reg signed [63:0] residual_pipe_sum_r4_q;
reg residual_product_valid_q;
reg residual_product_egress_valid_q;
reg residual_pipe_valid_r1_q;
reg residual_pipe_valid_r2_q;
reg residual_pipe_valid_r3_q;
reg residual_pipe_valid_r4_q;
reg residual_pipe_valid_r5_q;
reg [1:0] residual_blocks_total_q;
reg [1:0] residual_blocks_issued_q;
reg [1:0] residual_blocks_retired_q;
reg residual_stream_issue_q;
// Residual operands are prepared one clock before they enter PE0.  This keeps
// active_k/range selection out of the PE multiply-and-reduce timing path while
// preserving the registered PE0 -> PE1 -> PE2 -> PE3 wavefront.
reg residual_ingress_valid_q;
reg signed [COLS*DATA_W-1:0] residual_ingress_phi_q;
reg signed [COLS*DATA_W-1:0] residual_ingress_coeff_q;
reg signed [DATA_W-1:0] phi_cache [0:MAX_K-1];
reg [IDX_W-1:0] support_cache [0:MAX_K-1];
// Coherent sparse view of the dense x bank. LS coefficients remain resident
// as (index,value) tuples; writeback touches only dropped and new support
// entries instead of sweeping all N elements after every solve.
reg [IDX_W-1:0] x_support_cache [0:MAX_K-1];
reg [5:0] x_support_k_q;
reg [MAX_K*IDX_W-1:0] factor_support_cache_q;
// Four inverse-D banks match the four physical PE rows.  The solve reads one
// aligned entry from each bank, avoiding four 16:1 x 64-bit register muxes.
(* ram_style = "distributed" *) reg signed [63:0] ldlt_inv_d_bank0 [0:(MAX_K/4)-1];
(* ram_style = "distributed" *) reg signed [63:0] ldlt_inv_d_bank1 [0:(MAX_K/4)-1];
(* ram_style = "distributed" *) reg signed [63:0] ldlt_inv_d_bank2 [0:(MAX_K/4)-1];
(* ram_style = "distributed" *) reg signed [63:0] ldlt_inv_d_bank3 [0:(MAX_K/4)-1];
reg factor_valid_q;
reg [5:0] factor_k_q;
reg [IDX_W-1:0] factor_m_q;
reg [IDX_W-1:0] factor_n_q;
reg [31:0] factor_seed_q;
reg [DATA_W-1:0] factor_scale_q;
reg [1:0] factor_phi_kind_q;
reg [31:0] factor_support_fingerprint_q;
reg [31:0] request_support_fingerprint_q;
reg [1:0] factor_reuse_mode_q;
reg [MAX_K*IDX_W-1:0] request_support_cache_q;
reg [MAX_K*IDX_W-1:0] factor_check_request_shift_q;
reg [5:0] factor_check_req_idx_q;
reg [IDX_W-1:0] factor_check_request_value_q;
reg factor_check_ordered_match_q;
reg factor_check_prefix_ordered_q;
reg [5:0] factor_check_append_rank_q;
reg [MAX_K-1:0] factor_check_seen_mask_q;
reg [31:0] factor_check_fingerprint_q;
reg [1:0] factor_check_unmatched_count_q;
reg [4:0] factor_check_unmatched_tag_q;
reg [IDX_W-1:0] factor_check_unmatched_value_q;
reg factor_border_clear_q;
reg [7:0] refine_prime_k_eff;
reg [31:0] phi_state_q;
reg [5:0] phi_load_i;
reg [IDX_W-1:0] phi_support_q;
reg phi_support_valid_q;
reg [IDX_W-1:0] padded_n_q;
reg [IDX_W-1:0] phi_scan_col_q;
reg [31:0] phi_scan_state_q;
// Fixed jump matrices form 64- and 128-column direct-Phi scan windows without
// creating a serial LFSR chain.  The 128-column path is used only at N=256;
// smaller configurations retain their signed-off SPM-settle schedule.
wire [31:0] phi_scan_state32_w = lfsr_jump_padded(phi_scan_state_q, 10'd32);
wire [31:0] phi_scan_state64_w = lfsr_jump_padded(phi_scan_state_q, 10'd64);
wire [31:0] phi_scan_state96_w = lfsr_jump_padded(phi_scan_state_q, 10'd96);
wire [31:0] phi_scan_state128_w = lfsr_jump_padded(phi_scan_state_q, 10'd128);
reg scan_is_last_col;
reg [IDX_W-1:0] corr_col;
reg [IDX_W-1:0] corr_row;
reg [IDX_W-1:0] corr_scan_col;
reg signed [DATA_W-1:0] corr_phi;
reg signed [63:0] corr_acc;
reg [COLS*DATA_W-1:0] corr_phi_lane;
reg [COLS*DATA_W-1:0] corr_y_block;
reg [COLS*DATA_W-1:0] corr_y_next_block;
reg corr_stream_valid_q;
reg corr_stream_done_q;
reg [IDX_W-1:0] corr_stream_base_idx_q;
reg [COLS-1:0] corr_stream_lane_valid_q;
reg [COLS*DATA_W-1:0] corr_stream_data_q;
reg [5:0] refine_stream_count_q;
reg [31:0] corr_block_seq;
reg [31:0] corr_block_state;
reg [31:0] corr_row_state;
reg [31:0] corr_row_next_state;
reg [COLS*DATA_W-1:0] iht_x_block;
reg signed [DATA_W-1:0] iht_x_value;
reg keep_x;
reg [COLS*DATA_W-1:0] mesh_ctx_x_block;
reg [COLS*DATA_W-1:0] mesh_ctx_delta_block;
reg [COLS-1:0] mesh_ctx_keep_block;
reg [IDX_W-1:0] mesh_ctx_base_idx_block;
reg [IDX_W-1:0] mesh_ctx_limit_block;
reg [3:0] mesh_ctx_shift_block;
reg [3:0] mesh_ctx_wait_count;
wire [COLS*DATA_W-1:0] pe_update_block_w = mesh_ctx_commit_data;
reg [5:0] load_i;
reg [5:0] rhs_block_base;
reg [1:0] corr_drain_wait_q;
reg [IDX_W-1:0] load_support_q;
reg [IDX_W-1:0] load_support_next_q;
integer gi, gj, gk;
integer row2_prune_lane;
integer row2_prune_rank;
integer row3_lane;
integer factor_cmp;
reg row2_prune_support_hit;
reg [IDX_W-1:0] row2_prune_support_idx;
reg [IDX_W-1:0] row2_prune_lane_index;
reg signed [63:0] row3_residual_delta;
reg [COLS*DATA_W-1:0] mesh_ctx_residual_delta_bus;
reg [COLS*DATA_W-1:0] residual_delta_block_q;

integer comb_k;
integer rhs_lane;
integer corr_lane;
integer residual_lane;
integer residual_row;
integer cache_pos;
integer cache_cmp;
reg [COLS-1:0] row2_prune_keep_mask;
wire [MAX_K*IDX_W-1:0] row2_support_flat_w;
wire corr_active_op_w = (active_op == OP_CORR) ||
                        (active_op == OP_CORR_UPDATE);
wire corr_request_op_w = (op_sel == OP_CORR) ||
                         (op_sel == OP_CORR_UPDATE);
wire corr_pe_state_w = (state == S_PRIME) ||
                       (state == S_CORR_INIT) ||
                       (state == S_CORR_SCAN) ||
                       (state == S_CORR_LATCH) ||
                       (state == S_CORR_ACC) ||
                       (state == S_CORR_PE_WAIT) ||
                       (state == S_CORR_WRITE);
reg [IDX_W-1:0] sparse_target_idx;
reg [IDX_W-1:0] wx_target_idx_q;
reg [DATA_W-1:0] wx_value_q;
reg [DATA_W-1:0] row3_selected_value;
reg [COLS*MEM_AW-1:0] row3_wr_addr;
reg [COLS*DATA_W-1:0] row3_wr_data;
reg [COLS-1:0] row3_wr_en;
wire row3_corr_mode_w = corr_active_op_w && (state == S_CORR_WRITE);
wire row3_scalar_write_en_w = ((state == S_WX) || (state == S_WX_COMMIT) ||
                                   (state == S_WX_CLEAR) ||
                                   (state == S_WR_MESH_COMMIT) ||
                                   (state == S_IHT_MESH_WRITE) ||
                                   (state == S_PRUNE_MESH_WRITE) ||
                                   ((state == S_IHT_SCORE_READ) &&
                                    (active_op != OP_GP_UPDATE)) ||
                                   (state == S_GP_UPDATE_COMMIT) ||
                                   (state == S_MP_X_WRITE));
wire row3_prune_block_mode_w = ((active_op == OP_PRUNE_X) && (state == S_PRUNE_MESH_WRITE));
wire row3_update_block_mode_w = (((active_op == OP_IHT_UPDATE) ||
                                  (active_op == OP_GRAD_STEP) ||
                                  (active_op == OP_CORR_UPDATE)) &&
                                 (state == S_IHT_MESH_WRITE));
wire row3_project_write_op_w = ((active_op == OP_GP_PROJECT) && (state == S_WR));
wire row3_resid_write_op_w = (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_RESID) || (active_op == OP_MP_UPDATE)) && (k_active <= MAX_K));
wire row3_resid_mode_w = (row3_resid_write_op_w && (state == S_WR_MESH_COMMIT));
wire residual_block_last_w = (write_idx[2:0] == (COLS-1)) || (write_idx + 1'b1 >= write_limit);
wire row3_commit_value_mode_w = row3_update_block_mode_w || row3_prune_block_mode_w || row3_resid_mode_w;
wire [DATA_W-1:0] row3_commit_value_w = row3_commit_value_mode_w ? row3_selected_value : write_value_now;
wire [COLS*DATA_W-1:0] row3_block_value_w = (row3_update_block_mode_w || row3_prune_block_mode_w || row3_resid_mode_w) ? pe_update_block_w : rd_data;
wire wx_commit_mode_w = (((active_op == OP_REFINE) ||
                          (active_op == OP_REFINE_SPARSE)) &&
                         ((state == S_WX_COMMIT) || (state == S_WX_CLEAR)));
wire [2:0] row3_target_lane_w = wx_commit_mode_w ? wx_target_idx_q[2:0] : write_idx[2:0];
wire mesh_ctx_update_issue_w = 1'b0;
// Present a prune token to PE0 for exactly one cycle.  The cluster registers
// carry the token, keep mask, and metadata through PE1..PE3 after PE0 ingress;
// keeping mesh_ctx_valid asserted throughout WAIT/WRITE needlessly couples the
// controller state/address cones into the PE arithmetic timing paths.
wire mesh_ctx_prune_issue_w = ((state == S_PRUNE_MESH_WAIT) &&
                               (mesh_ctx_wait_count == MESH_CTX_WAIT_CYCLES));
// The residual payload is captured in S_WR.  Issue it on the following clock,
// after the block registers are stable, and inject exactly one PE0 token.  The
// registered south links then carry that token through PE1..PE3.
wire mesh_ctx_resid_issue_w = (row3_resid_write_op_w &&
                               (state == S_WR_MESH_WAIT) &&
                               (mesh_ctx_wait_count == MESH_CTX_WAIT_CYCLES));
wire mesh_ctx_update_active_w = mesh_ctx_update_issue_w || (state == S_IHT_MESH_WAIT) || (state == S_IHT_MESH_WRITE);
wire mesh_ctx_prune_active_w = mesh_ctx_prune_issue_w;
wire mesh_ctx_resid_active_w = mesh_ctx_resid_issue_w;
assign mesh_ctx_valid = mesh_ctx_update_active_w || mesh_ctx_prune_active_w || mesh_ctx_resid_active_w;
assign mesh_ctx_word = ctx_word;
assign mesh_ctx_mode = mesh_ctx_update_active_w ? MESH_CTX_UPDATE : (mesh_ctx_prune_active_w ? MESH_CTX_PRUNE : (mesh_ctx_resid_active_w ? MESH_CTX_RESID : MESH_CTX_NONE));
assign mesh_ctx_base_idx = mesh_ctx_base_idx_block;
assign mesh_ctx_limit = mesh_ctx_limit_block;
assign mesh_ctx_threshold = {DATA_W{1'b0}};
assign mesh_ctx_shift = mesh_ctx_shift_block;
assign mesh_ctx_x_bus = mesh_ctx_x_block;
assign mesh_ctx_delta_bus = mesh_ctx_delta_block;
assign mesh_ctx_keep_bus = mesh_ctx_keep_block;
assign pe_sparse_clear = 1'b0;
genvar row2_support_pack_g;
generate
    for (row2_support_pack_g = 0; row2_support_pack_g < MAX_K; row2_support_pack_g = row2_support_pack_g + 1) begin : gen_row2_support_pack
        assign row2_support_flat_w[row2_support_pack_g*IDX_W +: IDX_W] = support_cache[row2_support_pack_g];
    end
endgenerate
always @(*) begin
    keep_x = 1'b0;
    for (cache_cmp = 0; cache_cmp < MAX_K; cache_cmp = cache_cmp + 1) begin
        if ((cache_cmp < active_k) && (write_idx == support_cache[cache_cmp]))
            keep_x = 1'b1;
    end
end

always @(*) begin
    row2_prune_keep_mask = {COLS{1'b0}};
    for (row2_prune_lane = 0; row2_prune_lane < COLS; row2_prune_lane = row2_prune_lane + 1) begin
        row2_prune_support_hit = 1'b0;
        row2_prune_lane_index = write_idx + row2_prune_lane[IDX_W-1:0];
        for (row2_prune_rank = 0; row2_prune_rank < MAX_K; row2_prune_rank = row2_prune_rank + 1) begin
            row2_prune_support_idx = row2_support_flat_w[row2_prune_rank*IDX_W +: IDX_W];
            if ((row2_prune_rank < active_k) && (row2_prune_lane_index == row2_prune_support_idx))
                row2_prune_support_hit = 1'b1;
        end
        row2_prune_keep_mask[row2_prune_lane] = (row2_prune_lane_index < write_limit) && row2_prune_support_hit;
    end
end

always @(*) begin
    row3_residual_delta = $signed(residual_acc >>> 16);
    // Seven lanes come from the block accumulator; the lane currently being
    // evaluated bypasses its register so the final lane can launch the block
    // wavefront without an extra staging clock.
    mesh_ctx_residual_delta_bus = residual_delta_block_q;
    mesh_ctx_residual_delta_bus[write_idx[2:0]*DATA_W +: DATA_W] = row3_residual_delta[DATA_W-1:0];
    // Keep the GP multiplier/saturation cone structurally off the SPM DIN
    // bus while S_IHT_SCORE_READ captures it.  Write enable is low in that
    // state, but timing analysis still sees a BRAM -> DSP -> BRAM path unless
    // DIN is sourced only from the registered GP commit value.
    if (active_op == OP_GP_UPDATE)
        row3_selected_value = gp_update_value_q;
    else
        row3_selected_value = row3_commit_value_mode_w ?
                              row3_block_value_w[row3_target_lane_w*DATA_W +: DATA_W] :
                              write_value_now;
    row3_wr_addr = {COLS*MEM_AW{1'b0}};
    row3_wr_data = {COLS*DATA_W{1'b0}};
    row3_wr_en = {COLS{1'b0}};
    for (row3_lane = 0; row3_lane < COLS; row3_lane = row3_lane + 1) begin
        row3_wr_addr[row3_lane*MEM_AW +: MEM_AW] = base_addr;
        if (row3_corr_mode_w) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = sat_s24($signed(pe_corr_acc_bus[row3_lane*64 +: 64]) >>> 16);
            row3_wr_en[row3_lane] = busy && ((write_idx + row3_lane[IDX_W-1:0]) < write_limit);
        end else if (row3_update_block_mode_w) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = row3_block_value_w[row3_lane*DATA_W +: DATA_W];
            row3_wr_en[row3_lane] = busy && row3_scalar_write_en_w && ((write_idx + row3_lane[IDX_W-1:0]) < write_limit);
        end else if (row3_prune_block_mode_w) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = row3_block_value_w[row3_lane*DATA_W +: DATA_W];
            row3_wr_en[row3_lane] = busy && row3_scalar_write_en_w && ((write_idx + row3_lane[IDX_W-1:0]) < write_limit);
        end else if (row3_resid_mode_w) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = row3_block_value_w[row3_lane*DATA_W +: DATA_W];
            row3_wr_en[row3_lane] = busy && row3_scalar_write_en_w &&
                                   (({write_idx[IDX_W-1:3], 3'b000} + row3_lane[IDX_W-1:0]) < write_limit);
        end else if ((row3_target_lane_w == row3_lane[2:0]) && !row3_project_write_op_w) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = row3_selected_value;
            row3_wr_en[row3_lane] = busy && row3_scalar_write_en_w &&
                ((state != S_WX_CLEAR) ||
                 !support_cached_has_idx(wx_target_idx_q));
        end
    end
end
wire [5:0] active_k_count = active_k_count_q;
wire [5:0] active_k_last = (active_k_count == 6'd0) ? 6'd0 : (active_k_count - 6'd1);
wire residual_stream_prepare_w = (state == S_RESID_PE_WAIT) && residual_stream_issue_q;
// residual_ingress_valid_q is the registered transaction token.  Use it as
// the datapath select as well as the issue qualifier, so the controller state
// decode does not sit in front of the four PE-row multipliers.
wire residual_stream_issue_w = residual_ingress_valid_q;
wire residual_stream_retire_w = (state == S_RESID_PE_WAIT) && residual_pipe_valid_r5_q;
wire signed [63:0] residual_stream_retire_sum_w = residual_pipe_sum_r4_q;
wire signed [127:0] residual_stream_retire_sum_ext_w =
    {{64{residual_stream_retire_sum_w[63]}}, residual_stream_retire_sum_w};

wire [5:0] request_k_eff_w = (support_depth0 < k_active[5:0]) ?
                             support_depth0 : k_active[5:0];
wire [31:0] request_seed_eff_w = (|seed) ? seed : DEFAULT_SEED;
wire [32*IDX_W-1:0] request_support_flat_w = {
    support31, support30, support29, support28, support27, support26,
    support25, support24, support23, support22, support21, support20,
    support19, support18, support17, support16, support15, support14,
    support13, support12, support11, support10, support9, support8,
    support7, support6, support5, support4, support3, support2,
    support1, support0};
wire factor_config_match_w = factor_valid_q &&
    (factor_m_q == m_size) && (factor_n_q == n_size) &&
    (factor_seed_q == request_seed_eff_w) &&
    (factor_scale_q == scale_q) && (factor_phi_kind_q == phi_kind);
assign factor_pipe_cache_k = factor_k_q;
assign factor_pipe_cache_bus = factor_support_cache_q;
wire [31:0] factor_check_word_w = {{(32-IDX_W){1'b0}},
    factor_check_request_value_q};
wire [31:0] factor_check_fingerprint_next_w =
    factor_check_fingerprint_q ^ factor_check_word_w ^
    (factor_check_word_w << 10) ^ (factor_check_word_w << 20) ^
    32'h9e3779b9;
wire factor_pipe_resp_any_match_w = |factor_pipe_resp_match_mask;
wire factor_pipe_resp_ordered_match_w =
    ({1'b0, factor_pipe_resp_tag} >= factor_k_q) ||
    factor_pipe_resp_match_mask[factor_pipe_resp_tag];
reg factor_check_all_seen_w;
always @(*) begin
    factor_check_all_seen_w = 1'b1;
    for (factor_cmp = 0; factor_cmp < MAX_K; factor_cmp = factor_cmp + 1) begin
        if ((factor_cmp < factor_k_q) && !factor_check_seen_mask_q[factor_cmp])
            factor_check_all_seen_w = 1'b0;
    end
end

// The fingerprint is only a reject filter.  Exact/prefix acceptance also
// requires every cached support entry to have been observed by the sequential
// set scanner, so a fingerprint collision cannot authorize factor reuse.
wire factor_exact_hit_w = factor_config_match_w &&
    (k_active != 0) && (k_active <= MAX_K) &&
    (request_k_eff_w == factor_k_q) &&
    (factor_check_fingerprint_q == factor_support_fingerprint_q) &&
    factor_check_all_seen_w;
wire factor_prefix_hit_w = factor_config_match_w &&
    (k_active != 0) && (k_active <= MAX_K) &&
    (factor_k_q != 0) && (request_k_eff_w > factor_k_q) &&
    factor_check_all_seen_w;
// Safe downdate case: the request is an ordered prefix of the cached factor.
// The leading principal LDLT block is already exact, so only RHS/solve run.
wire factor_truncate_hit_w = factor_config_match_w &&
    (request_k_eff_w != 0) && (request_k_eff_w < factor_k_q) &&
    factor_check_ordered_match_q &&
    (factor_check_unmatched_count_q == 0);
// A last-rank replacement preserves the leading (K-1)x(K-1) factor. Clear
// that one Gram border, refill it through ACC4, then use the existing four-row
// LDLT border pipeline. Arbitrary interior DROP/SWAP still falls back safely.
wire factor_swap_last_hit_w = factor_config_match_w &&
    (request_k_eff_w == factor_k_q) && (factor_k_q != 0) &&
    factor_check_prefix_ordered_q &&
    (factor_check_unmatched_count_q == 1) &&
    ({1'b0, factor_check_unmatched_tag_q} + 1'b1 == request_k_eff_w);

wire [2:0] support_relation_opcode_w;
wire [1:0] support_relation_reuse_mode_w;
wire support_relation_border_clear_w;
wire support_relation_reuse_enable_w;
support_relation_unit u_support_relation_unit (
    .exact_hit(factor_exact_hit_w),
    .prefix_hit(factor_prefix_hit_w),
    .truncate_hit(factor_truncate_hit_w),
    .swap_last_hit(factor_swap_last_hit_w),
    .relation_opcode(support_relation_opcode_w),
    .reuse_mode(support_relation_reuse_mode_w),
    .border_clear(support_relation_border_clear_w),
    .reuse_enable(support_relation_reuse_enable_w)
);


function [IDX_W-1:0] support_cached_at;
    input [4:0] rank;
    begin
        support_cached_at = support_cache[rank];
    end
endfunction

function [DATA_W-1:0] coeff_for_dense_idx;
    input [IDX_W-1:0] dense_idx;
    integer coeff_rank;
    begin
        coeff_for_dense_idx = {DATA_W{1'b0}};
        for (coeff_rank = 0; coeff_rank < MAX_K; coeff_rank = coeff_rank + 1) begin
            if ((coeff_rank < active_k) && (dense_idx == support_cache[coeff_rank]))
                coeff_for_dense_idx = coeff_mem[coeff_rank];
        end
    end
endfunction
function support_cached_has_idx;
    input [IDX_W-1:0] dense_idx;
    integer support_rank;
    begin
        support_cached_has_idx = 1'b0;
        for (support_rank = 0; support_rank < MAX_K; support_rank = support_rank + 1) begin
            if ((support_rank < active_k) &&
                (dense_idx == support_cache[support_rank]))
                support_cached_has_idx = 1'b1;
        end
    end
endfunction

reg x_support_has_drop_w;
integer x_drop_rank;
integer x_drop_new_rank;
reg x_drop_found;
always @(*) begin
    x_support_has_drop_w = 1'b0;
    for (x_drop_rank = 0; x_drop_rank < MAX_K; x_drop_rank = x_drop_rank + 1) begin
        x_drop_found = 1'b0;
        for (x_drop_new_rank = 0; x_drop_new_rank < MAX_K;
             x_drop_new_rank = x_drop_new_rank + 1) begin
            if ((x_drop_rank < x_support_k_q) &&
                (x_drop_new_rank < active_k_count) &&
                (x_support_cache[x_drop_rank] == support_cache[x_drop_new_rank]))
                x_drop_found = 1'b1;
        end
        if ((x_drop_rank < x_support_k_q) && !x_drop_found)
            x_support_has_drop_w = 1'b1;
    end
end
function [7:0] ge_lower_idx;
    input [4:0] row;
    input [4:0] col;
    reg [7:0] base;
    begin
        case (row[3:0])
            4'd0:  base = 8'd0;
            4'd1:  base = 8'd1;
            4'd2:  base = 8'd3;
            4'd3:  base = 8'd6;
            4'd4:  base = 8'd10;
            4'd5:  base = 8'd15;
            4'd6:  base = 8'd21;
            4'd7:  base = 8'd28;
            4'd8:  base = 8'd36;
            4'd9:  base = 8'd45;
            4'd10: base = 8'd55;
            4'd11: base = 8'd66;
            4'd12: base = 8'd78;
            4'd13: base = 8'd91;
            4'd14: base = 8'd105;
            default: base = 8'd120;
        endcase
        ge_lower_idx = base + {4'd0, col[3:0]};
    end
endfunction


assign corr_stream_valid = corr_stream_valid_q;
assign corr_stream_done = corr_stream_done_q;
assign corr_stream_base_idx = corr_stream_base_idx_q;
assign corr_stream_lane_valid = corr_stream_lane_valid_q;
assign corr_stream_data = corr_stream_data_q;

always @(*) begin
    refine_prime_k_eff = (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
end


always @(*) begin
    // Clear on the request edge as well as in the internal clear states.  The
    // PE tiles register their control inputs, so waiting for busy/S_CORR_INIT
    // leaves one stale accumulator cycle at the first column block of every
    // correlation service after reset.  This is a startup-only clear; it does
    // not insert a bubble in the one-row-per-clock stream.
    pe_corr_acc_clear = (start && corr_request_op_w) ||
                        (busy && corr_active_op_w &&
                         ((state == S_CORR_INIT) || (state == S_CORR_WRITE)));
    // Correlation accepts one row per clock in S_CORR_ACC.  Four PE rows own
    // round-robin partial sums; S_CORR_PE_WAIT is only the final pipe drain.
    pe_corr_acc_en = busy && corr_active_op_w && (state == S_CORR_ACC);
    // The PE array already has the four-row striped OP_CORR datapath.  The
    // fused opcode reuses that datapath, then enters the mesh update pipeline.
    pe_sparse_op = busy ? ((corr_active_op_w && corr_pe_state_w) ? OP_CORR :
                           (phase_residual ? OP_RESID : active_op)) :
                          (corr_request_op_w ? OP_CORR : op_sel);
    pe_rhs_active = ((((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_MP_UPDATE) || (active_op == OP_RESID) || (active_op == OP_GP_PROJECT)) &&
                      ((state == S_ACC) || (state == S_ACC_PE_WAIT) || (state == S_ACC_PE_WAIT2) ||
                       (state == S_ACC_PE_WAIT3) ||
                       (state == S_ACC_RHS) || (state == S_GRAM_PE_WAIT) ||
                       (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM))) ||
                     residual_stream_issue_w ||
                     (corr_active_op_w && (state == S_CORR_ACC)));
    pe_rhs_phi_bus = {COLS*DATA_W{1'b0}};
    pe_rhs_y_bus = {COLS*DATA_W{1'b0}};
    for (rhs_lane = 0; rhs_lane < COLS; rhs_lane = rhs_lane + 1) begin
        pe_rhs_phi_bus[rhs_lane*DATA_W +: DATA_W] =
            residual_ingress_valid_q ?
                residual_ingress_phi_q[rhs_lane*DATA_W +: DATA_W] :
            (corr_active_op_w ? corr_phi_lane[rhs_lane*DATA_W +: DATA_W] :
                (((rhs_block_base + rhs_lane) < active_k_count) ?
                    phi_cache[rhs_block_base + rhs_lane] : {DATA_W{1'b0}}));
        pe_rhs_y_bus[rhs_lane*DATA_W +: DATA_W] =
            (residual_ingress_valid_q ?
                residual_ingress_coeff_q[rhs_lane*DATA_W +: DATA_W] :
             (((state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) ||
               (state == S_ACC_GRAM)) ? phi_cache[acc_j] :
              (corr_active_op_w ?
                corr_y_block[corr_row[2:0]*DATA_W +: DATA_W] :
                rhs_y_sample_q)));
    end
end

// Tagged residual block-8 wavefront.  Row r owns lanes whose index modulo
// four equals r.  The partial sum follows its transaction from PE0 to PE3.
always @(*) begin
    for (residual_row = 0; residual_row < 4; residual_row = residual_row + 1)
        residual_row_partial[residual_row] = 64'sd0;
    for (residual_lane = 0; residual_lane < COLS; residual_lane = residual_lane + 1) begin
        residual_row_partial[residual_lane % 4] =
            residual_row_partial[residual_lane % 4] +
            $signed(ls_wide_product_bus[((residual_lane % 4)*COLS+residual_lane)*64 +: 64]);
    end
end

always @(*) begin
    sparse_target_idx = support_cached_at(write_idx[4:0]);
    if (phase_residual)
        base_addr = 10'h080 + write_idx[IDX_W-1:3];
    else if (row3_corr_mode_w)
        base_addr = 10'h180 + write_idx[IDX_W-1:3];
    else if (wx_commit_mode_w)
        base_addr = 10'h000 + wx_target_idx_q[IDX_W-1:3];
    else if ((active_op == OP_IHT_UPDATE) || (active_op == OP_GRAD_STEP) || (active_op == OP_GP_UPDATE))
        base_addr = 10'h000 + write_idx[IDX_W-1:3];
    else
        base_addr = 10'h000 + write_idx[IDX_W-1:3];


    case (load_i)
        5'd0:  load_support_next_q = support1;
        5'd1:  load_support_next_q = support2;
        5'd2:  load_support_next_q = support3;
        5'd3:  load_support_next_q = support4;
        5'd4:  load_support_next_q = support5;
        5'd5:  load_support_next_q = support6;
        5'd6:  load_support_next_q = support7;
        5'd7:  load_support_next_q = support8;
        5'd8:  load_support_next_q = support9;
        5'd9:  load_support_next_q = support10;
        5'd10: load_support_next_q = support11;
        5'd11: load_support_next_q = support12;
        5'd12: load_support_next_q = support13;
        5'd13: load_support_next_q = support14;
        5'd14: load_support_next_q = support15;
        5'd15: load_support_next_q = support16;
        5'd16: load_support_next_q = support17;
        5'd17: load_support_next_q = support18;
        5'd18: load_support_next_q = support19;
        5'd19: load_support_next_q = support20;
        5'd20: load_support_next_q = support21;
        5'd21: load_support_next_q = support22;
        5'd22: load_support_next_q = support23;
        5'd23: load_support_next_q = support24;
        5'd24: load_support_next_q = support25;
        5'd25: load_support_next_q = support26;
        5'd26: load_support_next_q = support27;
        5'd27: load_support_next_q = support28;
        5'd28: load_support_next_q = support29;
        5'd29: load_support_next_q = support30;
        default: load_support_next_q = support31;
    endcase

    if (wx_commit_mode_w) begin
        write_value_now = wx_value_q;
    end else if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active <= MAX_K) && (state == S_WX)) begin
        write_value_now = {DATA_W{1'b0}};
        if (active_op == OP_REFINE_SPARSE) begin
            if (write_idx < active_k)
                write_value_now = wx_value_q;
        end else begin
            for (comb_k = 0; comb_k < MAX_K; comb_k = comb_k + 1) begin
                if ((comb_k < active_k) && (write_idx == support_cached_at(comb_k[4:0])))
                    write_value_now = coeff_mem[comb_k];
            end
        end
    end else if ((active_op == OP_CORR) && (state == S_CORR_WRITE)) begin
        write_value_now = write_value;
    end else if ((active_op == OP_IHT_UPDATE) && (state == S_IHT_SCORE_READ)) begin
        write_value_now = sat_s24($signed(iht_x_value) + ($signed(rd_data[write_idx[2:0]*DATA_W +: DATA_W]) >>> mu_shift_eff));
    end else if ((active_op == OP_GRAD_STEP) && (state == S_IHT_SCORE_READ)) begin
        write_value_now = sat_s24($signed(iht_x_value) + ($signed(rd_data[write_idx[2:0]*DATA_W +: DATA_W]) >>> mu_shift_eff));
    end else if ((active_op == OP_PRUNE_X) && (state == S_PRUNE_X_WAIT)) begin
        write_value_now = keep_x ? rd_data[write_idx[2:0]*DATA_W +: DATA_W] : {DATA_W{1'b0}};
    end else if ((active_op == OP_MP_UPDATE) && (state == S_MP_X_WRITE)) begin
        write_value_now = mp_x_new_q;
    end else if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_RESID) || (active_op == OP_MP_UPDATE)) && (k_active <= MAX_K) && (state == S_WR)) begin
        write_value_now = write_value;
    end else
        write_value_now = write_value;
    wr_addr = row3_wr_addr;
    wr_data = row3_wr_data;
    wr_en = row3_wr_en;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
rd_addr <= {MEM_AW{1'b0}};
        busy <= 1'b0;
        done <= 1'b0;
        result <= {SCALAR_W{1'b0}};
        state <= S_IDLE;
active_op <= OP_REFINE;
        write_idx <= {IDX_W{1'b0}};
        write_limit <= {IDX_W{1'b0}};
        write_value <= {DATA_W{1'b0}};
        phase_residual <= 1'b0;
        active_k <= 8'd0;
        active_k_count_q <= 6'd0;
        rhs_y_sample_q <= {DATA_W{1'b0}};
        phi_state_q <= DEFAULT_SEED;
        phi_load_i <= 5'd0;
        back_j <= 6'd0;
        back_i <= 6'd0;
        solve_k <= 6'd0;
        solve_j <= 6'd0;
        solve_i <= 6'd0;
        acc_j <= 6'd0;
        acc_i <= 5'd0;
        residual_acc <= 128'sd0;
        residual_pipe_sum_r1_q <= 64'sd0;
        residual_pipe_sum_r2_q <= 64'sd0;
        residual_pipe_sum_r3_q <= 64'sd0;
        residual_pipe_sum_r1_delay_q <= 64'sd0;
        residual_pipe_row1_product_q <= 64'sd0;
        residual_pipe_row2_product_q <= 64'sd0;
        residual_pipe_row3_product_q <= 64'sd0;
        residual_pipe_sum_r4_q <= 64'sd0;
        residual_product_valid_q <= 1'b0;
        residual_product_egress_valid_q <= 1'b0;
        residual_pipe_valid_r1_q <= 1'b0;
        residual_pipe_valid_r2_q <= 1'b0;
        residual_pipe_valid_r3_q <= 1'b0;
        residual_pipe_valid_r4_q <= 1'b0;
        residual_pipe_valid_r5_q <= 1'b0;
        residual_blocks_total_q <= 2'd0;
        residual_blocks_issued_q <= 2'd0;
        residual_blocks_retired_q <= 2'd0;
        residual_stream_issue_q <= 1'b0;
        residual_ingress_valid_q <= 1'b0;
        residual_ingress_phi_q <= {COLS*DATA_W{1'b0}};
        residual_ingress_coeff_q <= {COLS*DATA_W{1'b0}};
        rhs_block_base <= 6'd0;
        rhs4_product_q <= {COLS*64{1'b0}};
        corr_drain_wait_q <= 2'd0;
        wx_target_idx_q <= {IDX_W{1'b0}};
        wx_value_q <= {DATA_W{1'b0}};
        phi_support_q <= {IDX_W{1'b0}};
        phi_support_valid_q <= 1'b0;
        phi_scan_col_q <= {IDX_W{1'b0}};
        phi_scan_state_q <= DEFAULT_SEED;
        padded_n_q <= {IDX_W{1'b0}};
        scan_is_last_col <= 1'b0;
        corr_col <= {IDX_W{1'b0}};
        corr_row <= {IDX_W{1'b0}};
        corr_scan_col <= {IDX_W{1'b0}};
        corr_phi <= {DATA_W{1'b0}};
        corr_acc <= 64'sd0;
        corr_y_block <= {COLS*DATA_W{1'b0}};
        corr_y_next_block <= {COLS*DATA_W{1'b0}};
        corr_stream_valid_q <= 1'b0;
        corr_stream_done_q <= 1'b0;
        corr_stream_base_idx_q <= {IDX_W{1'b0}};
        corr_stream_lane_valid_q <= {COLS{1'b0}};
        corr_stream_data_q <= {COLS*DATA_W{1'b0}};
        refine_stream_count_q <= 6'd0;
        iht_x_block <= {COLS*DATA_W{1'b0}};
        load_i <= 5'd0;
        ge_mul_a <= 64'sd0;
        ge_mul_b <= 64'sd0;
        ge_mul_c <= 64'sd0;
        ge_mul_p <= 128'sd0;
        ls_start_q <= 1'b0;
        ls_op_q <= LS_OP_CLEAR;
        ls_row_a_q <= 5'd0;
        ls_col_a_q <= 5'd0;
        ls_row_b_q <= 5'd0;
        ls_col_b_q <= 5'd0;
        ls_row_base_q <= 5'd0;
        ls_lane_valid_q <= {COLS{1'b0}};
        ls_acc4_lane_valid_q <= {4*COLS{1'b0}};
        ls_acc4_col_valid_q <= 4'b0000;
        ls_acc4_payload_valid_q <= 1'b0;
        ls_wdata_q <= {GE_MAT_W{1'b0}};
        ls_write4_wdata_q <= {4*GE_MAT_W{1'b0}};
        ls_write4_valid_q <= 4'b0000;
        ls_factor_q <= 64'sd0;
        ls_rhs_wdata_q <= 64'sd0;
        ls_row_update_block_q <= 1'b0;
        wide_mul_start_q <= 1'b0;
        wide_mul_vertical_request_q <= 1'b0;
        div_abs_num <= 65'd0;
        div_abs_den <= 64'd1;
        div_rem <= 65'd0;
        div_quot <= 65'd0;
        div_trial_rem <= 65'd0;
        div_trial_quot <= 65'd0;
        div_iter <= 7'd0;
        div_neg <= 1'b0;
        div_return_back <= 1'b0;
        div_return_mp <= 1'b0;
        div_return_ldlt <= 1'b0;
        div_return_gp <= 1'b0;
        div_result <= 64'sd0;
        mp_idx_q <= {IDX_W{1'b0}};
        mp_score_q <= {DATA_W{1'b0}};
        mp_x_old_q <= {DATA_W{1'b0}};
        mp_x_new_q <= {DATA_W{1'b0}};
        mp_den_q <= 64'sd0;
        gp_num_acc_q <= 64'sd0;
        gp_den_acc_q <= 64'sd0;
        gp_alpha_q <= 64'sd0;
        gp_update_x_q <= {DATA_W{1'b0}};
        gp_update_grad_q <= {DATA_W{1'b0}};
        gp_update_alpha_q <= {DATA_W{1'b0}};
        gp_update_support_q <= 1'b0;
        gp_update_product_q <= 64'sd0;
        gp_update_sum_q <= 64'sd0;
        gp_update_value_q <= {DATA_W{1'b0}};
        mesh_ctx_x_block <= {COLS*DATA_W{1'b0}};
        mesh_ctx_delta_block <= {COLS*DATA_W{1'b0}};
        mesh_ctx_keep_block <= {COLS{1'b0}};
        mesh_ctx_base_idx_block <= {IDX_W{1'b0}};
        mesh_ctx_limit_block <= {IDX_W{1'b0}};
        mesh_ctx_shift_block <= 4'd0;
        mesh_ctx_wait_count <= 4'd0;
        residual_delta_block_q <= {COLS*DATA_W{1'b0}};
        ldlt_k_q <= 5'd0;
        ldlt_i_base_q <= 5'd0;
        ldlt_p_base_q <= 5'd0;
        ldlt_lane_q <= 3'd0;
        ldlt_lane_valid_q <= 4'd0;
        ldlt_border_issue_p_q <= 5'd0;
        ldlt_border_issue_part_q <= 1'b0;
        ldlt_border_issue_phase_q <= 1'b0;
        ldlt_border_mul1_complete_q <= 5'd0;
        ldlt_border_mul2_complete_q <= 5'd0;
        ldlt_border_mul1_slot_ready_q <= 4'd0;
        ldlt_diag_a_q <= 64'sd0;
        ldlt_diag_acc_q <= 128'sd0;
        ldlt_d_cur_q <= 64'sd0;
        factor_valid_q <= 1'b0;
        factor_k_q <= 6'd0;
        factor_m_q <= {IDX_W{1'b0}};
        factor_n_q <= {IDX_W{1'b0}};
        factor_seed_q <= DEFAULT_SEED;
        factor_scale_q <= {DATA_W{1'b0}};
        factor_phi_kind_q <= 2'd0;
        factor_support_fingerprint_q <= 32'd0;
        request_support_fingerprint_q <= 32'd0;
        factor_reuse_mode_q <= FACTOR_REUSE_NONE;
        factor_check_req_idx_q <= 6'd0;
        factor_check_request_value_q <= {IDX_W{1'b0}};
        factor_check_ordered_match_q <= 1'b0;
        factor_check_prefix_ordered_q <= 1'b0;
        factor_check_append_rank_q <= 6'd0;
        factor_check_seen_mask_q <= {MAX_K{1'b0}};
        factor_check_fingerprint_q <= 32'd0;
        factor_check_unmatched_count_q <= 2'd0;
        factor_check_unmatched_tag_q <= 5'd0;
        factor_check_unmatched_value_q <= {IDX_W{1'b0}};
        factor_border_clear_q <= 1'b0;
        factor_support_cache_q <= {MAX_K*IDX_W{1'b0}};
        request_support_cache_q <= {MAX_K*IDX_W{1'b0}};
        factor_check_request_shift_q <= {MAX_K*IDX_W{1'b0}};
        factor_pipe_valid <= 1'b0;
        factor_pipe_tag <= 5'd0;
        factor_pipe_value <= {IDX_W{1'b0}};
        x_support_k_q <= 6'd0;
        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
            rhs[gi] <= 64'sd0;
            coeff_mem[gi] <= {DATA_W{1'b0}};
            phi_cache[gi] <= {DATA_W{1'b0}};
            ge_x[gi] <= 64'sd0;
            ldlt_d_mem[gi] <= 64'sd0;
            x_support_cache[gi] <= {IDX_W{1'b0}};
        end
    end else begin
                ls_start_q <= 1'b0;
                ls_acc4_payload_valid_q <= 1'b0;
                wide_mul_start_q <= 1'b0;
                wide_mul_vertical_request_q <= 1'b0;
                residual_ingress_valid_q <= residual_stream_prepare_w;
                if (residual_stream_prepare_w) begin
                    for (gi = 0; gi < COLS; gi = gi + 1) begin
                        if ((rhs_block_base + gi) < active_k_count) begin
                            residual_ingress_phi_q[gi*DATA_W +: DATA_W] <=
                                phi_cache[rhs_block_base + gi];
                            residual_ingress_coeff_q[gi*DATA_W +: DATA_W] <=
                                coeff_mem[rhs_block_base + gi];
                        end else begin
                            residual_ingress_phi_q[gi*DATA_W +: DATA_W] <=
                                {DATA_W{1'b0}};
                            residual_ingress_coeff_q[gi*DATA_W +: DATA_W] <=
                                {DATA_W{1'b0}};
                        end
                    end
                end
                if (state == S_RESID_PE_WAIT) begin
                    // Match the controller token to the registered PE input
                    // and then the registered PE product egress.  No PE
                    // multiplier remains on a residual accumulator edge.
                    residual_product_valid_q <= residual_stream_issue_w;
                    residual_product_egress_valid_q <= residual_product_valid_q;
                    residual_pipe_valid_r1_q <= residual_product_egress_valid_q;
                    residual_pipe_valid_r2_q <= residual_pipe_valid_r1_q;
                    residual_pipe_valid_r3_q <= residual_pipe_valid_r2_q;
                    residual_pipe_valid_r4_q <= residual_pipe_valid_r3_q;
                    residual_pipe_valid_r5_q <= residual_pipe_valid_r4_q;
                    if (residual_product_egress_valid_q)
                        residual_pipe_sum_r1_q <= residual_row_partial[0];
                    // Register each arriving PE-row product before its
                    // accumulator stage. This removes the row-1 and row-2
                    // DSP -> carry-chain paths without changing II=1.
                    if (residual_pipe_valid_r1_q) begin
                        residual_pipe_sum_r1_delay_q <= residual_pipe_sum_r1_q;
                        residual_pipe_row1_product_q <= residual_row_partial[1];
                    end
                    if (residual_pipe_valid_r2_q) begin
                        residual_pipe_sum_r2_q <= residual_pipe_sum_r1_delay_q +
                                                  residual_pipe_row1_product_q;
                        residual_pipe_row2_product_q <= residual_row_partial[2];
                    end
                    if (residual_pipe_valid_r3_q) begin
                        residual_pipe_sum_r3_q <= residual_pipe_sum_r2_q +
                                                  residual_pipe_row2_product_q;
                        residual_pipe_row3_product_q <= residual_row_partial[3];
                    end
                    if (residual_pipe_valid_r4_q)
                        residual_pipe_sum_r4_q <= residual_pipe_sum_r3_q +
                                                  residual_pipe_row3_product_q;
                end else begin
                    residual_product_valid_q <= 1'b0;
                    residual_product_egress_valid_q <= 1'b0;
                    residual_pipe_valid_r1_q <= 1'b0;
                    residual_pipe_valid_r2_q <= 1'b0;
                    residual_pipe_valid_r3_q <= 1'b0;
                    residual_pipe_valid_r4_q <= 1'b0;
                    residual_pipe_valid_r5_q <= 1'b0;
                end
                if (ls_done_w)
                    ls_row_update_block_q <= 1'b0;
        if (corr_stream_valid_q && corr_stream_ready) begin
            corr_stream_valid_q <= 1'b0;
            corr_stream_done_q <= 1'b0;
        end
        factor_pipe_valid <= 1'b0;
case (state)
            S_IDLE: begin
                busy <= 1'b0;
                done <= 1'b0;
                rd_addr <= {MEM_AW{1'b0}};
                if (start) begin
                    done <= 1'b0;
                    busy <= 1'b1;
                    active_op <= op_sel;
                    request_support_cache_q <=
                        request_support_flat_w[MAX_K*IDX_W-1:0];
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        if (!(((op_sel == OP_REFINE) ||
                               (op_sel == OP_REFINE_SPARSE)) &&
                              (k_active != 0) && (k_active <= MAX_K)))
                            support_cache[gi] <=
                                request_support_flat_w[gi*IDX_W +: IDX_W];
                    end
                    factor_reuse_mode_q <= FACTOR_REUSE_NONE;
                    factor_border_clear_q <= 1'b0;
                    write_idx <= {IDX_W{1'b0}};
                    phase_residual <= 1'b0;
                    write_limit <= n_size;
                    write_value <= {DATA_W{1'b0}};
                    refine_stream_count_q <= 6'd0;
                    state <= (((op_sel == OP_REFINE) ||
                               (op_sel == OP_REFINE_SPARSE)) &&
                              (k_active != 0) && (k_active <= MAX_K)) ?
                             S_FACTOR_CHECK_INIT : S_PRIME;
                end
            end
            S_FACTOR_CHECK_INIT: begin
                factor_check_req_idx_q <= 6'd0;
                factor_check_request_value_q <=
                    request_support_cache_q[0 +: IDX_W];
                factor_check_request_shift_q <=
                    request_support_cache_q >> IDX_W;
                factor_check_ordered_match_q <= factor_config_match_w;
                factor_check_prefix_ordered_q <= factor_config_match_w;
                factor_check_seen_mask_q <= {MAX_K{1'b0}};
                factor_check_fingerprint_q <=
                    32'h6d2b79f5 ^ {26'd0, request_k_eff_w};
                factor_check_append_rank_q <= factor_config_match_w ?
                                              factor_k_q : 6'd0;
                factor_check_unmatched_count_q <= 2'd0;
                factor_check_unmatched_tag_q <= 5'd0;
                factor_check_unmatched_value_q <= {IDX_W{1'b0}};
                if (factor_config_match_w) begin
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        support_cache[gi] <=
                            factor_support_cache_q[gi*IDX_W +: IDX_W];
                end
                // A smaller request can reuse a leading principal LDLT block,
                // so it must be scanned as well. Only configuration mismatch
                // and the empty request bypass the PE0 factor-token wavefront.
                state <= (!factor_config_match_w ||
                          (request_k_eff_w == 0)) ?
                         S_FACTOR_CHECK_DONE : S_FACTOR_CHECK_SCAN;
            end
            S_FACTOR_CHECK_SCAN: begin
                // One request token enters PE row0 per cycle.  The four rows
                // compare rank groups (rank mod 4) and PE3 returns a complete
                // match mask after the vertical pipe drain.
                if (factor_check_req_idx_q < request_k_eff_w) begin
                    factor_pipe_valid <= 1'b1;
                    factor_pipe_tag <= factor_check_req_idx_q[4:0];
                    factor_pipe_value <= factor_check_request_value_q;
                    factor_check_fingerprint_q <=
                        factor_check_fingerprint_next_w;
                    if (factor_check_req_idx_q + 1'b1 < request_k_eff_w) begin
                        factor_check_req_idx_q <= factor_check_req_idx_q + 1'b1;
                        factor_check_request_value_q <=
                            factor_check_request_shift_q[0 +: IDX_W];
                        factor_check_request_shift_q <=
                            factor_check_request_shift_q >> IDX_W;
                    end else begin
                        // Mark all requests issued; responses continue to drain.
                        factor_check_req_idx_q <= request_k_eff_w;
                    end
                end

                if (factor_pipe_resp_valid) begin
                    factor_check_seen_mask_q <= factor_check_seen_mask_q |
                                                factor_pipe_resp_match_mask;
                    factor_check_ordered_match_q <=
                        factor_check_ordered_match_q &&
                        factor_pipe_resp_ordered_match_w;
                    if ({1'b0, factor_pipe_resp_tag} + 1'b1 < request_k_eff_w)
                        factor_check_prefix_ordered_q <=
                            factor_check_prefix_ordered_q &&
                            factor_pipe_resp_ordered_match_w;
                    if (!factor_pipe_resp_any_match_w &&
                        (factor_check_append_rank_q < MAX_K)) begin
                        support_cache[factor_check_append_rank_q] <=
                            factor_pipe_resp_value;
                        factor_check_append_rank_q <=
                            factor_check_append_rank_q + 1'b1;
                    end
                    if (!factor_pipe_resp_any_match_w) begin
                        if (factor_check_unmatched_count_q != 2'b11)
                            factor_check_unmatched_count_q <=
                                factor_check_unmatched_count_q + 1'b1;
                        factor_check_unmatched_tag_q <= factor_pipe_resp_tag;
                        factor_check_unmatched_value_q <= factor_pipe_resp_value;
                    end
                    if ({1'b0, factor_pipe_resp_tag} + 1'b1 >= request_k_eff_w)
                        state <= S_FACTOR_CHECK_DONE;
                end
            end
            S_FACTOR_CHECK_DONE: begin
                request_support_fingerprint_q <= factor_check_fingerprint_q;
                if (support_relation_reuse_enable_w) begin
                    factor_reuse_mode_q <= support_relation_reuse_mode_w;
                end
                if (support_relation_border_clear_w) begin
                    factor_k_q <= factor_k_q - 1'b1;
                    support_cache[factor_k_q - 1'b1] <=
                        factor_check_unmatched_value_q;
                    factor_border_clear_q <= 1'b1;
                end else if (!support_relation_reuse_enable_w) begin
                    factor_reuse_mode_q <= FACTOR_REUSE_NONE;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        support_cache[gi] <=
                            request_support_cache_q[gi*IDX_W +: IDX_W];
                end
`ifdef TB_FACTOR_REUSE_TRACE
                $display("FACTOR_REUSE_REQ time=%0t op=%0d k=%0d cached_k=%0d valid=%0d exact=%0d prefix=%0d fp=%08x cached_fp=%08x s0=%0d s1=%0d s2=%0d s3=%0d s4=%0d s5=%0d s6=%0d s7=%0d",
                    $time, active_op, request_k_eff_w, factor_k_q,
                    factor_valid_q, factor_exact_hit_w, factor_prefix_hit_w,
                    factor_check_fingerprint_q,
                    factor_support_fingerprint_q,
                    request_support_cache_q[0*IDX_W +: IDX_W],
                    request_support_cache_q[1*IDX_W +: IDX_W],
                    request_support_cache_q[2*IDX_W +: IDX_W],
                    request_support_cache_q[3*IDX_W +: IDX_W],
                    request_support_cache_q[4*IDX_W +: IDX_W],
                    request_support_cache_q[5*IDX_W +: IDX_W],
                    request_support_cache_q[6*IDX_W +: IDX_W],
                    request_support_cache_q[7*IDX_W +: IDX_W]);
`endif
                state <= S_PRIME;
            end
            S_PRIME: begin
                if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active == 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= 8'd0;
                    active_k_count_q <= 6'd0;
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= 10'h100;
                    residual_acc <= 128'sd0;
                    state <= S_WR;
                end else if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active <= MAX_K) && (k_active != 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
                    active_k_count_q <= (support_depth0 < k_active[5:0]) ?
                                        support_depth0 : k_active[5:0];
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    rd_addr <= 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                                padded_n_q <= ((n_size + 7) >> 3) << 3;
                                acc_num <= 64'sd0;
                    acc_den <= 64'sd0;
                    acc_num1 <= 64'sd0;
                    acc_den01 <= 64'sd0;
                    acc_den11 <= 64'sd0;
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        rhs[gi] <= 64'sd0;
                        coeff_mem[gi] <= {DATA_W{1'b0}};
                                    ge_x[gi] <= 64'sd0;
                    end
                    phase_residual <= 1'b0;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    if (factor_reuse_mode_q != FACTOR_REUSE_NONE) begin
                        // Preserve the cached L/D banks.  The scan still
                        // rebuilds RHS; exact hits skip Gram, while prefix
                        // hits accumulate only the newly appended columns.
                        phi_scan_col_q <= {IDX_W{1'b0}};
                        phi_scan_state_q <= (|seed) ? seed : DEFAULT_SEED;
                        state <= factor_border_clear_q ?
                                 S_DELTA_CLEAR_START : S_SCAN_DIRECT_STEP;
                    end else begin
                        factor_valid_q <= 1'b0;
                        state <= S_LS_CLEAR_START;
                    end
                end else if (corr_active_op_w && (n_size != 0) && (m_size != 0)) begin
                    corr_col <= {IDX_W{1'b0}};
                    corr_row <= {IDX_W{1'b0}};
                    corr_scan_col <= {IDX_W{1'b0}};
                    corr_acc <= 64'sd0;
                    corr_phi_lane <= {COLS*DATA_W{1'b0}};
                    rd_addr <= 10'h080;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    corr_block_state <= (|seed) ? seed : DEFAULT_SEED;
                    corr_row_state <= (|seed) ? seed : DEFAULT_SEED;
                    corr_row_next_state <= lfsr_jump_padded((|seed) ? seed : DEFAULT_SEED, ((n_size + 7) >> 3) << 3);
                    padded_n_q <= ((n_size + 7) >> 3) << 3;
                    state <= S_CORR_SCAN;
                end else if (((active_op == OP_IHT_UPDATE) || (active_op == OP_GRAD_STEP)) && (n_size != 0)) begin
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= n_size;
                    rd_addr <= 10'h000;
                    state <= S_IHT_X_READ;
                end else if ((active_op == OP_RESID) && (k_active != 0) && (k_active <= MAX_K) && (m_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
                    active_k_count_q <= (support_depth0 < k_active[5:0]) ?
                                        support_depth0 : k_active[5:0];
                    load_i <= 5'd0;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        coeff_mem[gi] <= {DATA_W{1'b0}};
                    load_support_q <= support0;
                    rd_addr <= 10'h000 + (support0 >> 3);
                    state <= S_LOAD_COEFF_READ;
                end else if ((active_op == OP_RESID) && (k_active == 0) && (m_size != 0)) begin
                    active_k <= 8'd0;
                    active_k_count_q <= 6'd0;
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= 10'h100;
                    residual_acc <= 128'sd0;
                    state <= S_WR;
                end else if ((active_op == OP_GP_PROJECT) && (support_depth0 != 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
                    active_k_count_q <= (support_depth0 < k_active[5:0]) ?
                                        support_depth0 : k_active[5:0];
                    load_i <= 5'd0;
                    load_support_q <= support0;
                    // The restricted gradient is read from the correlation
                    // vector produced by the preceding OP_CORR command.
                    rd_addr <= 10'h180 + (support0 >> 3);
                    gp_num_acc_q <= 64'sd0;
                    gp_den_acc_q <= 64'sd0;
                    state <= S_LOAD_COEFF_READ;
                end else if ((active_op == OP_GP_UPDATE) && (n_size != 0)) begin
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= n_size;
                    rd_addr <= 10'h000;
                    state <= S_IHT_X_READ;
                end else if ((active_op == OP_MP_UPDATE) && (support_depth0 != 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= 8'd1;
                    active_k_count_q <= 6'd1;
                    mp_idx_q <= last_result_idx;
                    write_idx <= last_result_idx;
                    mp_den_q <= (($signed(mul_s24_s24(scale_q, scale_q)) + 64'sd32768) >>> 16) * $signed({1'b0, m_size});
                    rd_addr <= 10'h180 + (last_result_idx >> 3);
                    state <= S_MP_X_READ;
                end else if ((active_op == OP_PRUNE_X) && (n_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
                    active_k_count_q <= (support_depth0 < k_active[5:0]) ?
                                        support_depth0 : k_active[5:0];
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= n_size;
                    phase_residual <= 1'b0;
                    rd_addr <= 10'h000;
                    state <= S_PRUNE_X_READ;
                end else begin
                    rd_addr <= {MEM_AW{1'b0}};
                    state <= (write_limit == 0) ? ((active_op == OP_CORR) ? S_DONE : S_WR) : S_WX;
                end
            end
            S_DELTA_CLEAR_START: begin
                // SWAP_LAST reuses the leading principal factor. The replaced
                // rank is the first new border (factor_k_q after decrement).
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_CLEAR_ROW;
                ls_row_a_q <= factor_k_q[4:0];
                state <= S_DELTA_CLEAR_WAIT;
            end
            S_DELTA_CLEAR_WAIT: begin
                if (ls_done_w) begin
                    factor_border_clear_q <= 1'b0;
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    state <= S_SCAN_DIRECT_STEP;
                end
            end
            S_LS_CLEAR_START: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_CLEAR;
                state <= S_LS_CLEAR_WAIT;
            end
            S_LS_CLEAR_WAIT: begin
                if (ls_done_w) begin
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= phi_state_q;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    state <= S_SCAN_DIRECT_STEP;
                end
            end
            S_ACC: begin
                acc_i <= 5'd0;
                rhs_block_base <= 5'd0;
                rhs_y_sample_q <= rd_data[write_idx[2:0]*DATA_W +: DATA_W];
                state <= S_ACC_PE_WAIT;
            end
            S_ACC_PE_WAIT: begin
                state <= S_ACC_PE_WAIT2;
            end
            S_ACC_PE_WAIT2: begin
                state <= S_ACC_PE_WAIT3;
            end
            S_ACC_PE_WAIT3: begin
                rhs4_product_q <= rhs4_product_bus;
                state <= S_ACC_RHS;
            end
            S_ACC_RHS: begin
                for (gi = 0; gi < RHS_BLOCK_STRIDE; gi = gi + 1) begin
                    if ((rhs_block_base + gi) < active_k_count)
                        rhs[rhs_block_base + gi] <= rhs[rhs_block_base + gi] +
                            $signed(rhs4_product_q[gi*64 +: 64]);
                end
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) begin
                    rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                    acc_i <= 5'd0;
                    state <= S_ACC_PE_WAIT;
                end else begin
                    acc_i <= 5'd0;
                    if (factor_reuse_mode_q == FACTOR_REUSE_EXACT) begin
                        rhs_block_base <= 5'd0;
                        if (write_idx + 1 >= write_limit) begin
                            state <= S_SOLVE_INIT;
                        end else begin
                            write_idx <= write_idx + 1'b1;
                            if ((write_idx[2:0] == 3'd7) &&
                                ((write_idx + 1'b1) < write_limit))
                                rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                            for (gi = 0; gi < MAX_K; gi = gi + 1)
                                phi_cache[gi] <= {DATA_W{1'b0}};
                            phi_scan_col_q <= {IDX_W{1'b0}};
                            phi_scan_state_q <= phi_state_q;
                            state <= S_SCAN_DIRECT_STEP;
                        end
                    end else begin
                        // A border extension must rebuild every cross term
                        // A(new_row, old_col), not only the new/new corner.
                        // Scan all Gram columns while the lane mask below keeps
                        // the already-factorized old/old triangle untouched.
                        acc_j <= 6'd0;
                        rhs_block_base <= (factor_reuse_mode_q == FACTOR_REUSE_PREFIX) ?
                            ((factor_k_q / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE) : 6'd0;
                        state <= S_GRAM_PE_WAIT;
                    end
                end
            end
            S_GRAM_PE_WAIT: begin
                // Hold the four-row batch through the registered core input
                // and registered product egress boundaries.
                state <= S_GRAM_PE_WAIT2;
            end
            S_GRAM_PE_WAIT2: begin
                state <= S_ACC_GRAM;
            end
            S_ACC_GRAM: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_ACC4;
                ls_acc4_payload_valid_q <= 1'b1;
                ls_row_base_q <= rhs_block_base;
                ls_col_a_q <= acc_j;
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    ls_acc4_col_valid_q[gi] <= ((acc_j + gi) < active_k_count);
                    ls_acc4_lane_valid_q[gi*COLS +: COLS] <= {COLS{1'b0}};
                    for (acc4_valid_col = 0; acc4_valid_col < COLS; acc4_valid_col = acc4_valid_col + 1) begin
                        ls_acc4_lane_valid_q[gi*COLS+acc4_valid_col] <=
                            (((rhs_block_base + acc4_valid_col) < active_k_count) &&
                             ((rhs_block_base + acc4_valid_col) >= (acc_j + gi)) &&
                             ((acc_j + gi) < active_k_count) &&
                             ((factor_reuse_mode_q != FACTOR_REUSE_PREFIX) ||
                              ((rhs_block_base + acc4_valid_col) >= factor_k_q)));
                    end
                end
                state <= S_GRAM_ACC_WAIT;
            end
            S_GRAM_ACC_WAIT: begin
                if (((rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) ||
                     (acc_j + 5'd4 < active_k_count)) ?
                    ls_acc4_credit_w : ls_done_w) begin
                    if (rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) begin
                        rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                        acc_i <= 5'd0;
                        state <= S_GRAM_PE_WAIT;
                    end else if (acc_j + 5'd4 < active_k_count) begin
                        acc_j <= acc_j + 5'd4;
                        acc_i <= 5'd0;
                        if ((factor_reuse_mode_q == FACTOR_REUSE_PREFIX) &&
                            ((((acc_j + 5'd4) / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE) <
                             ((factor_k_q / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE)))
                            rhs_block_base <= (factor_k_q / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE;
                        else
                            rhs_block_base <= ((acc_j + 5'd4) / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE;
                        state <= S_GRAM_PE_WAIT;
                    end else begin
                        acc_i <= 5'd0;
                        acc_j <= 5'd0;
                        rhs_block_base <= 5'd0;
                        if (write_idx + 1 >= write_limit) begin
                            state <= S_SOLVE_INIT;
                        end else begin
                            write_idx <= write_idx + 1'b1;
                            if ((write_idx[2:0] == 3'd7) &&
                                ((write_idx + 1'b1) < write_limit)) begin
                                rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                            end
                            for (gi = 0; gi < MAX_K; gi = gi + 1)
                                phi_cache[gi] <= {DATA_W{1'b0}};
                            phi_scan_col_q <= {IDX_W{1'b0}};
                            phi_scan_state_q <= phi_state_q;
                            state <= S_SCAN_DIRECT_STEP;
                        end
                    end
                end
            end
            S_CACHE_BUILD: begin
                state <= S_SOLVE_INIT;
            end
            S_CACHE_BUILD_STEP: begin
                state <= S_SOLVE_INIT;
            end
            S_WX_COMMIT: begin
                write_value <= row3_commit_value_w;
                if (corr_stream_active && corr_stream_post_refine_support &&
                    (active_op == OP_REFINE) &&
                    support_cached_has_idx(wx_target_idx_q) &&
                    corr_stream_valid_q && !corr_stream_ready) begin
                    // Keep the current dense commit stable until the previous
                    // support-only token has been accepted at the PE0 ingress.
                    state <= S_WX_COMMIT;
                end else begin
                    if (corr_stream_active && corr_stream_post_refine_support &&
                        (active_op == OP_REFINE) &&
                        support_cached_has_idx(wx_target_idx_q)) begin
                        corr_stream_valid_q <= busy;
                        corr_stream_done_q <=
                            (refine_stream_count_q + 1'b1 >= active_k_count);
                        corr_stream_base_idx_q <=
                            {wx_target_idx_q[IDX_W-1:3], 3'b000};
                        corr_stream_lane_valid_q <=
                            ({{(COLS-1){1'b0}}, 1'b1} << wx_target_idx_q[2:0]);
                        corr_stream_data_q <= {COLS*DATA_W{1'b0}};
                        corr_stream_data_q[wx_target_idx_q[2:0]*DATA_W +: DATA_W] <=
                            row3_commit_value_w;
                        refine_stream_count_q <= refine_stream_count_q + 1'b1;
                    end
                if (write_idx + 1 >= write_limit) begin
                    x_support_k_q <= active_k_count;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        if (gi < active_k_count)
                            x_support_cache[gi] <= support_cache[gi];
                    write_idx <= {IDX_W{1'b0}};
                    phase_residual <= 1'b1;
                    write_limit <= m_size;
                    rd_addr <= 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    state <= (m_size == 0) ? S_DONE : S_SCAN_DIRECT_STEP;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    wx_target_idx_q <= support_cached_at(write_idx[4:0] + 5'd1);
                    wx_value_q <= coeff_mem[write_idx[4:0] + 5'd1];
                end
                end
            end
            S_WX_CLEAR: begin
                // Inspect one old tuple per clock. The row-3 write-enable
                // suppresses retained indices and clears only true DROPs.
                if (write_idx + 1 >= write_limit) begin
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= active_k_count;
                    wx_target_idx_q <= support_cached_at(5'd0);
                    wx_value_q <= coeff_mem[0];
                    state <= S_WX_COMMIT;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    wx_target_idx_q <= x_support_cache[write_idx[4:0] + 5'd1];
                    wx_value_q <= {DATA_W{1'b0}};
                end
            end
            S_WR_ACC_INIT: begin
                residual_acc <= 128'sd0;
                residual_blocks_total_q <= (active_k_count + (RHS_BLOCK_STRIDE-1)) / RHS_BLOCK_STRIDE;
                residual_blocks_retired_q <= 2'd0;
                if (active_k_count >= RHS_BLOCK_STRIDE) begin
                    // Full block supports have stable cached operands here,
                    // so preload block zero while clearing the accumulator.
                    // PE0 consumes it on the first WAIT clock and later
                    // blocks retain the existing chained preload.
                    rhs_block_base <= RHS_BLOCK_STRIDE;
                    residual_blocks_issued_q <= 2'd1;
                    residual_stream_issue_q <=
                        (active_k_count > RHS_BLOCK_STRIDE);
                    residual_ingress_valid_q <= 1'b1;
                    for (gi = 0; gi < COLS; gi = gi + 1) begin
                        residual_ingress_phi_q[gi*DATA_W +: DATA_W] <=
                            phi_cache[gi];
                        residual_ingress_coeff_q[gi*DATA_W +: DATA_W] <=
                            coeff_mem[gi];
                    end
                end else begin
                    // Sub-block K2/K4 update callers require the original
                    // extra settle clock before the masked residual payload
                    // is captured.  Preserve that signed-off schedule.
                    rhs_block_base <= 5'd0;
                    residual_blocks_issued_q <= 2'd0;
                    residual_stream_issue_q <= (active_k_count != 0);
                    residual_ingress_valid_q <= 1'b0;
                end
                state <= S_RESID_PE_WAIT;
            end
            S_RESID_PE_WAIT: begin
                if (residual_stream_prepare_w) begin
                    residual_blocks_issued_q <= residual_blocks_issued_q + 1'b1;
                    rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                    residual_stream_issue_q <=
                        (residual_blocks_issued_q + 1'b1 < residual_blocks_total_q);
                end
                if (residual_stream_retire_w) begin
                    residual_acc <= residual_acc + residual_stream_retire_sum_ext_w;
                    residual_blocks_retired_q <= residual_blocks_retired_q + 1'b1;
                    if (residual_blocks_retired_q + 1'b1 >= residual_blocks_total_q) begin
                        residual_stream_issue_q <= 1'b0;
                        rhs_block_base <= 5'd0;
                        state <= S_WR;
                    end
                end
            end
            S_WR: begin
                y_cur <= rd_data[write_idx[2:0]*DATA_W +: DATA_W];
                phi_cur <= phi_cache[0];
                phi1_cur <= phi_cache[1];
                write_value <= row3_commit_value_w;
                if (active_op == OP_GP_PROJECT) begin
                    // The four-row residual wavefront has reduced c=A*d for
                    // this measurement row.  Accumulate both line-search
                    // products at the registered controller boundary; no
                    // completion feedback is placed on the PE datapath.
                    gp_num_acc_q <= gp_num_acc_q +
                                    mul_s24_s24(rd_data[write_idx[2:0]*DATA_W +: DATA_W],
                                                row3_residual_delta[DATA_W-1:0]);
                    gp_den_acc_q <= gp_den_acc_q +
                                    mul_s24_s24(row3_residual_delta[DATA_W-1:0],
                                                row3_residual_delta[DATA_W-1:0]);
                    if (write_idx + 1 >= write_limit) begin
                        ge_div_num <= (gp_num_acc_q +
                                       mul_s24_s24(rd_data[write_idx[2:0]*DATA_W +: DATA_W],
                                                   row3_residual_delta[DATA_W-1:0])) <<< 16;
                        ge_div_den <= gp_den_acc_q +
                                      mul_s24_s24(row3_residual_delta[DATA_W-1:0],
                                                  row3_residual_delta[DATA_W-1:0]);
                        div_return_gp <= 1'b1;
                        state <= S_DIV_INIT;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                        if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                            rd_addr <= 10'h080 + ((write_idx + 1'b1) >> 3);
                        for (gi = 0; gi < MAX_K; gi = gi + 1)
                            phi_cache[gi] <= {DATA_W{1'b0}};
                        phi_scan_col_q <= {IDX_W{1'b0}};
                        phi_scan_state_q <= phi_state_q;
                        state <= S_SCAN_DIRECT_STEP;
                    end
                end else if (row3_resid_write_op_w) begin
                    residual_delta_block_q[write_idx[2:0]*DATA_W +: DATA_W] <= row3_residual_delta[DATA_W-1:0];
                    if (residual_block_last_w) begin
                        // One complete eight-lane residual word enters row 0;
                        // subtract/mask/range-check then flow through rows 1..3.
                        mesh_ctx_x_block <= rd_data;
                        mesh_ctx_delta_block <= mesh_ctx_residual_delta_bus;
                        mesh_ctx_keep_block <= {COLS{1'b1}};
                        mesh_ctx_base_idx_block <= {write_idx[IDX_W-1:3], 3'b000};
                        mesh_ctx_limit_block <= write_limit;
                        mesh_ctx_shift_block <= mu_shift_eff;
                        mesh_ctx_wait_count <= MESH_CTX_WAIT_CYCLES;
                        state <= S_WR_MESH_WAIT;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                        for (gi = 0; gi < MAX_K; gi = gi + 1)
                            phi_cache[gi] <= {DATA_W{1'b0}};
                        phi_scan_col_q <= {IDX_W{1'b0}};
                        phi_scan_state_q <= phi_state_q;
                        state <= S_SCAN_DIRECT_STEP;
                    end
                end else if (write_idx + 1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                        rd_addr <= ((active_op == OP_MP_UPDATE) ? 10'h080 : 10'h100) + ((write_idx + 1'b1) >> 3);
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= phi_state_q;
                    state <= S_SCAN_DIRECT_STEP;
                end
            end
            S_WR_MESH_WAIT: begin
                if (mesh_ctx_wait_count == 4'd0) begin
                    state <= S_WR_MESH_COMMIT;
                end else begin
                    mesh_ctx_wait_count <= mesh_ctx_wait_count - 1'b1;
                end
            end
            S_WR_MESH_COMMIT: begin
                write_value <= row3_commit_value_w;
                if (write_idx + 1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    residual_delta_block_q <= {COLS*DATA_W{1'b0}};
                    if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                        rd_addr <= ((active_op == OP_MP_UPDATE) ? 10'h080 : 10'h100) + ((write_idx + 1'b1) >> 3);
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= phi_state_q;
                    state <= S_SCAN_DIRECT_STEP;
                end
            end            S_SOLVE_INIT: begin
                for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                    ge_x[gi] <= 64'sd0;
                    coeff_mem[gi] <= {DATA_W{1'b0}};
                end
                solve_i <= 5'd0;
                solve_j <= 5'd0;
                solve_k <= 5'd0;
                back_i <= active_k_last;
                back_j <= 5'd0;
                ge_acc <= 64'sd0;
                if (active_k_count == 0) begin
                    state <= (factor_reuse_mode_q == FACTOR_REUSE_EXACT) ?
                             S_ELIM_START : S_LDL_INIT;
                end else begin
                    // Start the first RHS transfer while solve state is being
                    // initialized.  Subsequent entries are chained from the
                    // preceding completion pulse below.
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_RHS_WRITE;
                    ls_row_a_q <= 5'd0;
                    ls_rhs_wdata_q <= rhs[0];
                    state <= S_RHS_INIT_WAIT;
                end
            end
            S_RHS_INIT_WAIT: begin
                if (ls_done_w) begin
                    if (solve_i + 5'd1 >= active_k_count) begin
                        solve_i <= 5'd0;
                        state <= (factor_reuse_mode_q == FACTOR_REUSE_EXACT) ?
                                 S_ELIM_START : S_LDL_INIT;
                    end else begin
                        solve_i <= solve_i + 5'd1;
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_RHS_WRITE;
                        ls_row_a_q <= solve_i + 5'd1;
                        ls_rhs_wdata_q <= rhs[solve_i + 5'd1];
                    end
                end
            end
            S_LDL_INIT: begin
                if (factor_reuse_mode_q == FACTOR_REUSE_PREFIX) begin
                    // Border LDLT extension has two parts.  First replay each
                    // cached pivot only across the newly appended rows to turn
                    // A(new,old) into L(new,old).  The cached old/old L and D
                    // triangle is never rewritten.  Once all old pivots have
                    // participated, factor the first new diagonal normally.
                    ldlt_k_q <= 5'd0;
                    ldlt_i_base_q <= factor_k_q[4:0];
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        if (gi < factor_k_q) begin
                            case (gi % 4)
                                0: ge_x[gi] <= ldlt_inv_d_bank0[gi/4];
                                1: ge_x[gi] <= ldlt_inv_d_bank1[gi/4];
                                2: ge_x[gi] <= ldlt_inv_d_bank2[gi/4];
                                default: ge_x[gi] <= ldlt_inv_d_bank3[gi/4];
                            endcase
                        end
                    end
                    state <= S_LDL_ROW_INIT;
                end else begin
                    ldlt_k_q <= 5'd0;
                    state <= S_LDL_DIAG_READ;
                end
            end
            S_LDL_DIAG_READ: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_READ2;
                ls_row_a_q <= ldlt_k_q;
                ls_col_a_q <= ldlt_k_q;
                ls_row_b_q <= ldlt_k_q;
                ls_col_b_q <= ldlt_k_q;
                state <= S_LDL_DIAG_WAIT;
            end
            S_LDL_DIAG_WAIT: begin
                if (ls_done_w) begin
                    ldlt_diag_a_q <= {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w} + 64'sd1;
                    ldlt_diag_acc_q <= 128'sd0;
                    ldlt_p_base_q <= 5'd0;
                    ldlt_lane_q <= 3'd0;
                    if (ldlt_k_q == 0) begin
                        ldlt_d_cur_q <= {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w} + 64'sd1;
                        state <= S_LDL_DIAG_WRITE;
                    end else begin
                        // The diagonal read completion returns the matrix
                        // service to IDLE.  Launch p=0 immediately so the
                        // gather does not spend a command-only controller
                        // clock.  Only this request is active.
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ2;
                        ls_row_a_q <= ldlt_k_q;
                        ls_col_a_q <= 5'd0;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= 5'd0;
                        state <= S_LDL_DIAG_GATHER_WAIT;
                    end
                end
            end
            S_LDL_DIAG_GATHER: begin
                if ((ldlt_p_base_q + ldlt_lane_q) < ldlt_k_q) begin
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_READ2;
                    ls_row_a_q <= ldlt_k_q;
                    ls_col_a_q <= ldlt_p_base_q + ldlt_lane_q;
                    ls_row_b_q <= ldlt_k_q;
                    ls_col_b_q <= ldlt_p_base_q + ldlt_lane_q;
                    state <= S_LDL_DIAG_GATHER_WAIT;
                end else begin
                    ldlt_l_lane_q[ldlt_lane_q] <= 64'sd0;
                    if (ldlt_lane_q == 3) begin
                        state <= S_LDL_DIAG_MUL1;
                    end else begin
                        ldlt_lane_q <= ldlt_lane_q + 1'b1;
                    end
                end
            end
            S_LDL_DIAG_GATHER_WAIT: begin
                if (ls_done_w) begin
                    ldlt_l_lane_q[ldlt_lane_q] <= {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w};
                    if (ldlt_shared_tail_last_w) begin
                        // Inactive lanes are cleared by the shared tail mask
                        // below; diagonal gather and forward solve use the
                        // same physical lane-register write path.
                        state <= S_LDL_DIAG_MUL1;
                    end else begin
                        ldlt_lane_q <= ldlt_lane_q + 1'b1;
                        // Chain the next same-row READ2 from the completion
                        // pulse.  The service has completed the previous read,
                        // so at most one LS request remains in flight.
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ2;
                        ls_row_a_q <= ldlt_k_q;
                        ls_col_a_q <= ldlt_p_base_q + ldlt_lane_q + 1'b1;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= ldlt_p_base_q + ldlt_lane_q + 1'b1;
                    end
                end
            end
            S_LDL_DIAG_MUL1: begin
                wide_mul_a_q <= {ldlt_l_lane_q[3],ldlt_l_lane_q[2],ldlt_l_lane_q[1],ldlt_l_lane_q[0]};
                wide_mul_b_q <= {ldlt_l_lane_q[3],ldlt_l_lane_q[2],ldlt_l_lane_q[1],ldlt_l_lane_q[0]};
                wide_mul_start_q <= 1'b1;
                state <= S_LDL_DIAG_MUL1_WAIT;
            end
            S_LDL_DIAG_MUL1_WAIT: begin
                if (wide_mul_done_q)
                    state <= S_LDL_DIAG_MUL2;
            end
            S_LDL_DIAG_MUL2: begin
                wide_mul_a_q <= {wide_mul_result_q[3][63:0],wide_mul_result_q[2][63:0],wide_mul_result_q[1][63:0],wide_mul_result_q[0][63:0]};
                wide_mul_b_q <= {
                    ((ldlt_p_base_q+3 < ldlt_k_q) ? ldlt_d_mem[ldlt_p_base_q+3] : 64'sd0),
                    ((ldlt_p_base_q+2 < ldlt_k_q) ? ldlt_d_mem[ldlt_p_base_q+2] : 64'sd0),
                    ((ldlt_p_base_q+1 < ldlt_k_q) ? ldlt_d_mem[ldlt_p_base_q+1] : 64'sd0),
                    ldlt_d_mem[ldlt_p_base_q]};
                wide_mul_start_q <= 1'b1;
                state <= S_LDL_DIAG_MUL2_WAIT;
            end
            S_LDL_DIAG_MUL2_WAIT: begin
                if (wide_mul_done_q) begin
                    if (ldlt_p_base_q + 5'd4 < ldlt_k_q) begin
                        ldlt_diag_acc_q <= ldlt_diag_acc_q + ldlt_wide_q32_sum;
                        ldlt_p_base_q <= ldlt_p_base_q + 5'd4;
                        ldlt_lane_q <= 3'd0;
                        // The matrix service is idle throughout the PE multiply
                        // phase.  Start lane zero of the next four-value gather
                        // here instead of entering a command-only state.
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ2;
                        ls_row_a_q <= ldlt_k_q;
                        ls_col_a_q <= ldlt_p_base_q + 5'd4;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= ldlt_p_base_q + 5'd4;
                        state <= S_LDL_DIAG_GATHER_WAIT;
                    end else begin
                        ldlt_d_cur_q <= ldlt_diag_a_q - ldlt_diag_acc_q - ldlt_wide_q32_sum;
                        state <= S_LDL_DIAG_WRITE;
                    end
                end
            end
            S_LDL_DIAG_WRITE: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_WRITE;
                ls_row_a_q <= ldlt_k_q;
                ls_col_a_q <= ldlt_k_q;
                ls_wdata_q <= ldlt_d_cur_q[GE_MAT_W-1:0];
                state <= S_LDL_DIAG_WRITE_WAIT;
            end
            S_LDL_DIAG_WRITE_WAIT: begin
                if (ls_done_w) begin
                    ldlt_d_mem[ldlt_k_q] <= ldlt_d_cur_q;
                    ge_div_num <= 64'sh0001_0000_0000_0000;
                    ge_div_den <= (ldlt_d_cur_q != 0) ? ldlt_d_cur_q : 64'sd1;
                    state <= S_LDL_INV_DIV;
                end
            end
            S_LDL_INV_DIV: begin
                div_return_back <= 1'b0;
                div_return_mp <= 1'b0;
                div_return_ldlt <= 1'b1;
                div_neg <= ge_div_num[63] ^ ge_div_den[63];
                div_abs_den <= ge_div_den[63] ? -ge_div_den : ge_div_den;
                div_abs_num <= {1'b0, (ge_div_num[63] ? -ge_div_num : ge_div_num)};
                div_rem <= 65'd0;
                div_quot <= 65'd0;
                div_iter <= 7'd64;
                state <= S_DIV_STEP;
            end
            S_LDL_INV_DONE: begin
                div_return_ldlt <= 1'b0;
                // Keep inv(D) in the factor cache so an exact support hit can
                // enter the solve without rerunning the divider/factor states.
                ge_x[ldlt_k_q] <= div_result;
                case (ldlt_k_q[1:0])
                    2'd0: ldlt_inv_d_bank0[ldlt_k_q[4:2]] <= div_result;
                    2'd1: ldlt_inv_d_bank1[ldlt_k_q[4:2]] <= div_result;
                    2'd2: ldlt_inv_d_bank2[ldlt_k_q[4:2]] <= div_result;
                    default: ldlt_inv_d_bank3[ldlt_k_q[4:2]] <= div_result;
                endcase
                if (ldlt_k_q + 1'b1 < active_k_count) begin
                    ldlt_i_base_q <= ldlt_k_q + 1'b1;
                    state <= S_LDL_ROW_INIT;
                end else begin
                    factor_valid_q <= 1'b1;
                    factor_k_q <= active_k_count;
                    factor_m_q <= m_size;
                    factor_n_q <= n_size;
                    factor_seed_q <= (|seed) ? seed : DEFAULT_SEED;
                    factor_scale_q <= scale_q;
                    factor_phi_kind_q <= phi_kind;
                    factor_support_fingerprint_q <= request_support_fingerprint_q;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        factor_support_cache_q[gi*IDX_W +: IDX_W] <=
                            support_cache[gi];
                    solve_i <= 5'd0;
                    state <= S_ELIM_START;
                end
            end
            S_LDL_ROW_INIT: begin
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    ldlt_lane_valid_q[gi] <= ((ldlt_i_base_q + gi) < active_k_count);
                    ldlt_a_lane_q[gi] <= 64'sd0;
                    ldlt_acc_lane_q[gi] <= 128'sd0;
                end
                // Four consecutive target rows occupy four independent row
                // banks, so all A(i,k) operands are fetched in one request.
                // Launch that request during initialization to remove the
                // command-only state before every four-row block.
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_READ4;
                ls_row_a_q <= ldlt_i_base_q;
                ls_col_a_q <= ldlt_k_q;
                ls_row_b_q <= ldlt_k_q;
                ls_col_b_q <= ldlt_k_q;
                state <= S_LDL_ROW_A_WAIT;
            end
            S_LDL_ROW_A_WAIT: begin
                if (ls_done_w) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        if ((ldlt_i_base_q + gi) < active_k_count)
                            ldlt_a_lane_q[gi] <= {{(64-GE_MAT_W){ls_read4_rdata_w[gi*GE_MAT_W+GE_MAT_W-1]}}, ls_read4_rdata_w[gi*GE_MAT_W +: GE_MAT_W]};
                        else
                            ldlt_a_lane_q[gi] <= 64'sd0;
                    end
                    ldlt_p_base_q <= 5'd0;
                    if (ldlt_k_q == 0) begin
                        state <= S_LDL_ROW_FINAL_MUL;
                    end else begin
                        // The completion pulse means that the matrix service
                        // has returned to IDLE.  Chain p=0 immediately without
                        // adding a second request or a memory-port conflict.
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ4;
                        ls_row_a_q <= ldlt_i_base_q;
                        ls_col_a_q <= 5'd0;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= 5'd0;
                        state <= S_LDL_ROW_P_WAIT;
                    end
                end
            end
            S_LDL_ROW_P_WAIT: begin
                if (ls_done_w) begin
                    // Whole-word writes let Vivado map the preload cache to
                    // distributed RAM instead of four independent FF banks.
                    ldlt_border_lip_cache_q[ldlt_p_base_q] <= {
                        ((ldlt_i_base_q + 3 < active_k_count) ?
                            ls_read4_rdata_w[3*GE_MAT_W +: GE_MAT_W] : {GE_MAT_W{1'b0}}),
                        ((ldlt_i_base_q + 2 < active_k_count) ?
                            ls_read4_rdata_w[2*GE_MAT_W +: GE_MAT_W] : {GE_MAT_W{1'b0}}),
                        ((ldlt_i_base_q + 1 < active_k_count) ?
                            ls_read4_rdata_w[1*GE_MAT_W +: GE_MAT_W] : {GE_MAT_W{1'b0}}),
                        ((ldlt_i_base_q < active_k_count) ?
                            ls_read4_rdata_w[0*GE_MAT_W +: GE_MAT_W] : {GE_MAT_W{1'b0}})};
                    ldlt_border_lkp_cache_q[ldlt_p_base_q] <=
                        ls_rdata_b_w;
                    if (ldlt_p_base_q + 1'b1 < ldlt_k_q) begin
                        ldlt_p_base_q <= ldlt_p_base_q + 1'b1;
                        // Chain p+1 from p's completion pulse.  Only one LS
                        // request remains in flight, but the controller no
                        // longer inserts a command-only bubble per preload.
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ4;
                        ls_row_a_q <= ldlt_i_base_q;
                        ls_col_a_q <= ldlt_p_base_q + 1'b1;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= ldlt_p_base_q + 1'b1;
                    end else begin
                        ldlt_border_issue_p_q <= 5'd0;
                        ldlt_border_issue_part_q <= 1'b0;
                        ldlt_border_issue_phase_q <= 1'b0;
                        ldlt_border_mul1_complete_q <= 5'd0;
                        ldlt_border_mul2_complete_q <= 5'd0;
                        ldlt_border_mul1_slot_ready_q <= 4'd0;
                        state <= S_LDL_ROW_MUL1;
                    end
                end
            end
            S_LDL_ROW_MUL1: begin
                if (ldlt_border_issue_active_w) begin
                    if (ldlt_border_issue_part_q) begin
                        ldlt_border_issue_part_q <= 1'b0;
                        if (ldlt_border_issue_p_q + 1'b1 >= ldlt_k_q) begin
                            // MUL1 tokens already in the PE0->PE3 pipe keep
                            // draining with phase=0.  Start the in-order MUL2
                            // stream as each modulo-4 scoreboard slot retires
                            // its final MUL1 owner.
                            ldlt_border_issue_p_q <= 5'd0;
                            ldlt_border_issue_phase_q <= 1'b1;
                            state <= S_LDL_ROW_MUL2;
                        end else begin
                            ldlt_border_issue_p_q <= ldlt_border_issue_p_q + 1'b1;
                        end
                    end else begin
                        ldlt_border_issue_part_q <= 1'b1;
                    end
                end
                if (border_done_q && !border_done_phase_q) begin
                    ldlt_border_mul1_cache_q[border_done_tag_q] <= {
                        border_result_bank3_q[border_done_tag_q[1:0]][0 +: 64],
                        border_result_bank2_q[border_done_tag_q[1:0]][0 +: 64],
                        border_result_bank1_q[border_done_tag_q[1:0]][0 +: 64],
                        border_result_bank0_q[border_done_tag_q[1:0]][0 +: 64]};
                    ldlt_border_mul1_complete_q <= ldlt_border_mul1_complete_q + 1'b1;
                    if (border_done_tag_q + 5'd4 >= ldlt_k_q)
                        ldlt_border_mul1_slot_ready_q[border_done_tag_q[1:0]] <= 1'b1;
                end
            end
            S_LDL_ROW_MUL2: begin
                if (ldlt_border_issue_active_w) begin
                    if (ldlt_border_issue_part_q) begin
                        ldlt_border_issue_part_q <= 1'b0;
                        ldlt_border_issue_p_q <= ldlt_border_issue_p_q + 1'b1;
                    end else begin
                        ldlt_border_issue_part_q <= 1'b1;
                    end
                end
                if (border_done_q) begin
                    if (!border_done_phase_q) begin
                        // Late MUL1 completions are classified by their
                        // registered phase tag even after MUL2 issue begins.
                        ldlt_border_mul1_cache_q[border_done_tag_q] <= {
                            border_result_bank3_q[border_done_tag_q[1:0]][0 +: 64],
                            border_result_bank2_q[border_done_tag_q[1:0]][0 +: 64],
                            border_result_bank1_q[border_done_tag_q[1:0]][0 +: 64],
                            border_result_bank0_q[border_done_tag_q[1:0]][0 +: 64]};
                        ldlt_border_mul1_complete_q <= ldlt_border_mul1_complete_q + 1'b1;
                        if (border_done_tag_q + 5'd4 >= ldlt_k_q)
                            ldlt_border_mul1_slot_ready_q[border_done_tag_q[1:0]] <= 1'b1;
                    end else begin
                        ldlt_acc_lane_q[0] <= ldlt_acc_lane_q[0] +
                            ($signed(border_result_bank0_q[border_done_tag_q[1:0]]) >>> 32);
                        ldlt_acc_lane_q[1] <= ldlt_acc_lane_q[1] +
                            ($signed(border_result_bank1_q[border_done_tag_q[1:0]]) >>> 32);
                        ldlt_acc_lane_q[2] <= ldlt_acc_lane_q[2] +
                            ($signed(border_result_bank2_q[border_done_tag_q[1:0]]) >>> 32);
                        ldlt_acc_lane_q[3] <= ldlt_acc_lane_q[3] +
                            ($signed(border_result_bank3_q[border_done_tag_q[1:0]]) >>> 32);
                        ldlt_border_mul2_complete_q <= ldlt_border_mul2_complete_q + 1'b1;
                        if (ldlt_border_mul2_complete_q + 1'b1 >= ldlt_k_q)
                            state <= S_LDL_ROW_FINAL_MUL;
                    end
                end
            end
            S_LDL_ROW_FINAL_MUL: begin
                wide_mul_a_q <= {
                    (ldlt_a_lane_q[3] - ldlt_acc_lane_q[3]),
                    (ldlt_a_lane_q[2] - ldlt_acc_lane_q[2]),
                    (ldlt_a_lane_q[1] - ldlt_acc_lane_q[1]),
                    (ldlt_a_lane_q[0] - ldlt_acc_lane_q[0])};
                wide_mul_b_q <= {4{ge_x[ldlt_k_q]}};
                wide_mul_start_q <= 1'b1;
                wide_mul_vertical_request_q <= 1'b1;
                state <= S_LDL_ROW_FINAL_WAIT;
            end
            S_LDL_ROW_FINAL_WAIT: begin
                if (wide_mul_done_q) begin
                    // The four PE-row results are already registered by the
                    // wide multiplier.  Forward them into the WRITE4 command
                    // registers here instead of staging through a command-only
                    // controller state.
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_WRITE4;
                    ls_row_a_q <= ldlt_i_base_q;
                    ls_col_a_q <= ldlt_k_q;
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        ls_write4_wdata_q[gi*GE_MAT_W +: GE_MAT_W] <=
                            $signed(wide_mul_result_q[gi]) >>> 32;
                        ls_write4_valid_q[gi] <=
                            ((ldlt_i_base_q + gi) < active_k_count);
                    end
                    state <= S_LDL_ROW_WRITE_WAIT;
                end
            end
            S_LDL_ROW_WRITE_WAIT: begin
                if (ls_done_w) begin
                    if (ldlt_i_base_q + 5'd4 < active_k_count) begin
                        ldlt_i_base_q <= ldlt_i_base_q + 5'd4;
                        // WRITE4 has completed and the matrix service is back
                        // in IDLE.  Prepare the following four-row block and
                        // launch its A(i,k) READ4 on this completion pulse.
                        // This preserves a single active LS request while
                        // removing the intervening ROW_INIT clock.
                        for (gi = 0; gi < 4; gi = gi + 1) begin
                            ldlt_lane_valid_q[gi] <=
                                ((ldlt_i_base_q + 5'd4 + gi) < active_k_count);
                            ldlt_a_lane_q[gi] <= 64'sd0;
                            ldlt_acc_lane_q[gi] <= 128'sd0;
                        end
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ4;
                        ls_row_a_q <= ldlt_i_base_q + 5'd4;
                        ls_col_a_q <= ldlt_k_q;
                        ls_row_b_q <= ldlt_k_q;
                        ls_col_b_q <= ldlt_k_q;
                        state <= S_LDL_ROW_A_WAIT;
                    end else if ((factor_reuse_mode_q == FACTOR_REUSE_PREFIX) &&
                                 (ldlt_k_q + 1'b1 < factor_k_q)) begin
                        // Reuse the next cached pivot, again updating only the
                        // appended border rows.  Prepare and launch its first
                        // READ4 directly from the preceding WRITE4 completion.
                        ldlt_k_q <= ldlt_k_q + 1'b1;
                        ldlt_i_base_q <= factor_k_q[4:0];
                        for (gi = 0; gi < 4; gi = gi + 1) begin
                            ldlt_lane_valid_q[gi] <=
                                ((factor_k_q + gi) < active_k_count);
                            ldlt_a_lane_q[gi] <= 64'sd0;
                            ldlt_acc_lane_q[gi] <= 128'sd0;
                        end
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ4;
                        ls_row_a_q <= factor_k_q[4:0];
                        ls_col_a_q <= ldlt_k_q + 1'b1;
                        ls_row_b_q <= ldlt_k_q + 1'b1;
                        ls_col_b_q <= ldlt_k_q + 1'b1;
                        state <= S_LDL_ROW_A_WAIT;
                    end else begin
                        // The final row block for this pivot has committed.
                        // Chain the next diagonal READ2 immediately; the
                        // completed WRITE4 is no longer active in the service.
                        ldlt_k_q <= ldlt_k_q + 1'b1;
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ2;
                        ls_row_a_q <= ldlt_k_q + 1'b1;
                        ls_col_a_q <= ldlt_k_q + 1'b1;
                        ls_row_b_q <= ldlt_k_q + 1'b1;
                        ls_col_b_q <= ldlt_k_q + 1'b1;
                        state <= S_LDL_DIAG_WAIT;
                    end
                end
            end
            S_SOLVE_SYM_READ: begin
                if (solve_i >= active_k_count) begin
                    solve_i <= 5'd0;
                    solve_j <= 5'd1;
                    solve_k <= 5'd0;
                    state <= S_ELIM_START;
                end else if (solve_i > solve_j) begin
                    if (solve_j + 5'd1 >= active_k_count) begin
                        solve_j <= 5'd0;
                        solve_i <= solve_i + 5'd1;
                    end else begin
                        solve_j <= solve_j + 5'd1;
                    end
                end else begin
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_READ2;
                    if (solve_i == solve_j) begin
                        ls_row_a_q <= solve_i;
                        ls_col_a_q <= solve_i;
                    end else begin
                        ls_row_a_q <= solve_j;
                        ls_col_a_q <= solve_i;
                    end
                    ls_row_b_q <= 5'd0;
                    ls_col_b_q <= 5'd0;
                    state <= S_SOLVE_SYM_WAIT;
                end
            end
            S_SOLVE_SYM_WAIT: begin
                if (ls_done_w)
                    state <= S_SOLVE_SYM_WRITE;
            end
            S_SOLVE_SYM_WRITE: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_WRITE;
                ls_row_a_q <= solve_i;
                ls_col_a_q <= solve_j;
                ls_wdata_q <= ls_rdata_a_w + ((solve_i == solve_j) ? {{(GE_MAT_W-1){1'b0}}, 1'b1} : {GE_MAT_W{1'b0}});
                state <= S_SOLVE_SYM_WRITE_WAIT;
            end
            S_SOLVE_SYM_WRITE_WAIT: begin
                if (ls_done_w) begin
                    if (solve_j + 5'd1 >= active_k_count) begin
                        solve_j <= 5'd0;
                        solve_i <= solve_i + 5'd1;
                    end else begin
                        solve_j <= solve_j + 5'd1;
                    end
                    state <= S_SOLVE_SYM_READ;
                end
            end
            S_ELIM_START: begin
                if (solve_i >= active_k_count) begin
                    ldlt_i_base_q <= 5'd0;
                    state <= S_BACK_INIT;
                end else if (solve_i == 0) begin
                    // Unit-lower forward solve: z[0] = b[0].
                    solve_i <= 5'd1;
                end else begin
                    ldlt_p_base_q <= 5'd0;
                    ldlt_lane_q <= 3'd0;
                    ge_acc <= 64'sd0;
                    state <= S_ELIM_ROW;
                end
            end
            S_ELIM_ROW: begin
                // Entry is guarded by ELIM_START, the preceding read
                // completion, or a four-lane block advance, so lane_q always
                // names a valid j.  Keep the service command registered to
                // isolate the matrix-memory address path from solve control.
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_READ2;
                ls_row_a_q <= solve_i;
                ls_col_a_q <= ldlt_p_base_q + ldlt_lane_q;
                ls_row_b_q <= solve_i;
                ls_col_b_q <= ldlt_p_base_q + ldlt_lane_q;
                state <= S_ELIM_ROW_READ;
            end
            S_ELIM_ROW_READ: begin
                if (ls_done_w) begin
                    ldlt_l_lane_q[ldlt_lane_q] <= {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w};
                    ldlt_lkp_lane_q[ldlt_lane_q] <= rhs[ldlt_p_base_q + ldlt_lane_q];
                    if (ldlt_shared_tail_last_w) begin
                        // Complete a partial final block in the same edge as
                        // its last valid read instead of spending one state
                        // transition per zero-filled tail lane.
                        state <= S_ELIM_PREP;
                    end else begin
                        ldlt_lane_q <= ldlt_lane_q + 1'b1;
                        state <= S_ELIM_ROW;
                    end
                end
            end
            S_ELIM_PREP: begin
                // Four j terms are evaluated together; PE row r owns j=base+r.
                wide_mul_a_q <= {ldlt_l_lane_q[3],ldlt_l_lane_q[2],ldlt_l_lane_q[1],ldlt_l_lane_q[0]};
                wide_mul_b_q <= {ldlt_lkp_lane_q[3],ldlt_lkp_lane_q[2],ldlt_lkp_lane_q[1],ldlt_lkp_lane_q[0]};
                wide_mul_start_q <= 1'b1;
                state <= S_ELIM_MUL;
            end
            S_ELIM_MUL: begin
                if (wide_mul_done_q)
                    state <= S_ELIM_UPDATE;
            end
            S_ELIM_UPDATE: begin
                if (ldlt_p_base_q + 5'd4 < solve_i) begin
                    ge_acc <= ge_acc + ldlt_wide_q16_sum;
                    ldlt_p_base_q <= ldlt_p_base_q + 5'd4;
                    ldlt_lane_q <= 3'd0;
                    state <= S_ELIM_ROW;
                end else begin
                    rhs[solve_i] <= rhs[solve_i] - ge_acc - ldlt_wide_q16_sum;
                    solve_i <= solve_i + 1'b1;
                    state <= S_ELIM_START;
                end
            end
            S_ELIM_UPDATE_WAIT: begin
                if (ls_done_w) begin
                    if (solve_k + LS_ROW_UPDATE_STRIDE >= active_k_count) begin
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_RHS_UPDATE;
                        ls_row_a_q <= solve_j;
                        ls_row_b_q <= solve_i;
                        ls_factor_q <= ge_factor;
                        ls_row_update_block_q <= 1'b0;
                        state <= S_ELIM_RHS_UPDATE_WAIT;
                    end else begin
                        solve_k <= solve_k + LS_ROW_UPDATE_STRIDE;
                        state <= S_ELIM_UPDATE;
                    end
                end
            end
            S_ELIM_ROW_WAIT: begin
                state <= S_ELIM_UPDATE;
            end
            S_ELIM_RHS_UPDATE_WAIT: begin
                if (ls_done_w) begin
                    solve_j <= solve_j + 5'd1;
                    state <= S_ELIM_ROW;
                end
            end
            S_BACK_INIT: begin
                // Diagonal solve w = D^-1 z in batches of four PE rows.
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    if ((ldlt_i_base_q + gi) < active_k_count) begin
                        ldlt_l_lane_q[gi] <= rhs[ldlt_i_base_q + gi];
                    end else begin
                        ldlt_l_lane_q[gi] <= 64'sd0;
                    end
                end
                ldlt_lkp_lane_q[0] <= (ldlt_i_base_q < active_k_count) ?
                    ldlt_inv_d_bank0[ldlt_i_base_q[4:2]] : 64'sd0;
                ldlt_lkp_lane_q[1] <= (ldlt_i_base_q + 1 < active_k_count) ?
                    ldlt_inv_d_bank1[ldlt_i_base_q[4:2]] : 64'sd0;
                ldlt_lkp_lane_q[2] <= (ldlt_i_base_q + 2 < active_k_count) ?
                    ldlt_inv_d_bank2[ldlt_i_base_q[4:2]] : 64'sd0;
                ldlt_lkp_lane_q[3] <= (ldlt_i_base_q + 3 < active_k_count) ?
                    ldlt_inv_d_bank3[ldlt_i_base_q[4:2]] : 64'sd0;
                state <= S_BACK_ACC;
            end
            S_BACK_ACC: begin
                wide_mul_a_q <= {ldlt_l_lane_q[3],ldlt_l_lane_q[2],ldlt_l_lane_q[1],ldlt_l_lane_q[0]};
                wide_mul_b_q <= {ldlt_lkp_lane_q[3],ldlt_lkp_lane_q[2],ldlt_lkp_lane_q[1],ldlt_lkp_lane_q[0]};
                wide_mul_start_q <= 1'b1;
                state <= S_BACK_ACC_READ;
            end
            S_BACK_ACC_READ: begin
                if (wide_mul_done_q) begin
                    for (gi = 0; gi < 4; gi = gi + 1)
                        if ((ldlt_i_base_q + gi) < active_k_count)
                            ge_x[ldlt_i_base_q + gi] <= $signed(wide_mul_result_q[gi]) >>> 32;
                    if (ldlt_i_base_q + 5'd4 < active_k_count) begin
                        ldlt_i_base_q <= ldlt_i_base_q + 5'd4;
                        state <= S_BACK_INIT;
                    end else begin
                        back_i <= active_k_last;
                        state <= S_BACK_PREP;
                    end
                end
            end
            S_BACK_MUL: begin
                // Back substitution: PE row r owns j=base+r.
                wide_mul_a_q <= {ldlt_l_lane_q[3],ldlt_l_lane_q[2],ldlt_l_lane_q[1],ldlt_l_lane_q[0]};
                wide_mul_b_q <= {ldlt_lkp_lane_q[3],ldlt_lkp_lane_q[2],ldlt_lkp_lane_q[1],ldlt_lkp_lane_q[0]};
                wide_mul_start_q <= 1'b1;
                state <= S_BACK_UPDATE;
            end
            S_BACK_UPDATE: begin
                if (wide_mul_done_q) begin
                    if (ldlt_p_base_q + 5'd4 < active_k_count) begin
                        ge_acc <= ge_acc + ldlt_wide_q16_sum;
                        ldlt_p_base_q <= ldlt_p_base_q + 5'd4;
                        ldlt_lane_q <= 3'd0;
                        state <= S_BACK_RHS_READ;
                    end else begin
                        ge_x[back_i] <= ge_x[back_i] - ge_acc - ldlt_wide_q16_sum;
                        coeff_mem[back_i] <= sat_s24(ge_x[back_i] - ge_acc - ldlt_wide_q16_sum);
                        if (back_i == 0)
                            state <= S_SOLVE_DONE;
                        else begin
                            back_i <= back_i - 1'b1;
                            state <= S_BACK_PREP;
                        end
                    end
                end
            end
            S_BACK_PREP: begin
                ge_acc <= 64'sd0;
                ldlt_p_base_q <= back_i + 1'b1;
                ldlt_lane_q <= 3'd0;
                if (back_i + 1'b1 >= active_k_count) begin
                    coeff_mem[back_i] <= sat_s24(ge_x[back_i]);
                    if (back_i == 0)
                        state <= S_SOLVE_DONE;
                    else begin
                        back_i <= back_i - 1'b1;
                        state <= S_BACK_PREP;
                    end
                end else begin
                    state <= S_BACK_RHS_READ;
                end
            end
            S_BACK_PREP_READ: begin
                if (ls_done_w) begin
                    ge_div_den <= (ls_rdata_a_w != 0) ? {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w} : 64'sd1;
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_RHS_READ;
                    ls_row_a_q <= back_i;
                    state <= S_BACK_RHS_READ_WAIT;
                end
            end
            S_BACK_RHS_READ: begin
                // L(j+r,i) is a four-row banked column read; each returned
                // coefficient feeds the matching physical PE row.  The
                // service accepts the decoded command on this transition.
                state <= S_BACK_RHS_READ_WAIT;
            end
            S_BACK_RHS_READ_WAIT: begin
                if (ls_done_w) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        if ((ldlt_p_base_q + gi) < active_k_count) begin
                            ldlt_l_lane_q[gi] <= {{(64-GE_MAT_W){ls_read4_rdata_w[gi*GE_MAT_W+GE_MAT_W-1]}}, ls_read4_rdata_w[gi*GE_MAT_W +: GE_MAT_W]};
                            ldlt_lkp_lane_q[gi] <= ge_x[ldlt_p_base_q + gi];
                        end else begin
                            ldlt_l_lane_q[gi] <= 64'sd0;
                            ldlt_lkp_lane_q[gi] <= 64'sd0;
                        end
                    end
                    state <= S_BACK_MUL;
                end
            end
            S_BACK_DIV: begin
                state <= S_BACK_MUL;
            end
            S_DIV_INIT: begin
                div_neg <= ge_div_num[63] ^ ge_div_den[63];
                div_abs_den <= ge_div_den[63] ? -ge_div_den : ge_div_den;
                div_abs_num <= {1'b0, (ge_div_num[63] ? -ge_div_num : ge_div_num)};
                div_rem <= 65'd0;
                div_quot <= 65'd0;
                div_iter <= 7'd64;
                state <= S_DIV_STEP;
            end
            S_DIV_STEP: begin
                if (div_abs_den == 0) begin
                                div_result <= 64'sd0;
                    state <= div_return_ldlt ? S_LDL_INV_DONE :
                             (div_return_back ? S_BACK_DIV_DONE :
                              (div_return_mp ? S_MP_DIV_DONE :
                               (div_return_gp ? S_GP_DIV_DONE : S_ELIM_DIV_DONE)));
                end else begin
                    div_trial_rem = div_rem;
                    div_trial_quot = div_quot;
                    if (div_iter != 0) begin
                        div_trial_rem = {div_trial_rem[63:0], div_abs_num[div_iter - 1'b1]};
                        if (div_trial_rem >= {1'b0, div_abs_den}) begin
                            div_trial_rem = div_trial_rem - {1'b0, div_abs_den};
                            div_trial_quot[div_iter - 1'b1] = 1'b1;
                        end
                    end
                    if (div_iter > 1) begin
                        div_trial_rem = {div_trial_rem[63:0], div_abs_num[div_iter - 2'd2]};
                        if (div_trial_rem >= {1'b0, div_abs_den}) begin
                            div_trial_rem = div_trial_rem - {1'b0, div_abs_den};
                            div_trial_quot[div_iter - 2'd2] = 1'b1;
                        end
                    end
                    // Limit the shared divider to two restoring bits per
                    // clock.  Four chained compare/subtract steps were the
                    // next routed critical path after the GP SPM boundary.
                    // This trades divider cycles for a much shorter 65-bit
                    // carry path without changing quotient or rounding.
                    if (div_iter <= 2) begin
                        // Canonical fixed-point GP defines alpha with signed
                        // division truncated toward zero.  The shared LS/MP
                        // divider retains its historical round-to-nearest
                        // behavior; suppress only that final increment for
                        // the isolated GP line-search transaction.
                        if (!div_return_gp &&
                            ({div_trial_rem[63:0], 1'b0} >= {1'b0, div_abs_den}))
                            div_trial_quot = div_trial_quot + 1'b1;
                        div_result <= div_neg ? -$signed(div_trial_quot[63:0]) : $signed(div_trial_quot[63:0]);
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        state <= div_return_ldlt ? S_LDL_INV_DONE :
                                 (div_return_back ? S_BACK_DIV_DONE :
                                  (div_return_mp ? S_MP_DIV_DONE :
                                   (div_return_gp ? S_GP_DIV_DONE : S_ELIM_DIV_DONE)));
                    end else begin
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        div_iter <= div_iter - 7'd2;
                    end
                end
            end
            S_ELIM_DIV_DONE: begin
                ge_factor <= div_result;
                state <= S_ELIM_UPDATE;
            end
            S_ELIM_RHS_READ_WAIT: begin
                if (ls_done_w) begin
                    ge_mul_c <= ls_rhs_rdata_w;
                    state <= S_ELIM_UPDATE;
                end
            end
            S_BACK_DIV_DONE: begin
                ge_x[back_i] <= div_result;
                coeff_mem[back_i] <= sat_s24(div_result);
                if (back_i == 0) begin
                    state <= S_SOLVE_DONE;
                end else begin
                    back_i <= back_i - 5'd1;
                    state <= S_BACK_INIT;
                end
            end
            S_MP_X_READ: begin
                state <= S_MP_SCORE_CAP;
            end
            S_MP_X_WAIT: begin
                state <= S_MP_SCORE_CAP;
            end
            S_MP_SCORE_CAP: begin
                mp_score_q <= rd_data[mp_idx_q[2:0]*DATA_W +: DATA_W];
                rd_addr <= 10'h000 + (mp_idx_q >> 3);
                state <= S_MP_DIV_PREP;
            end
            S_MP_DIV_PREP: begin
                state <= S_MP_X_CAP;
            end
            S_MP_X_CAP: begin
                mp_x_old_q <= rd_data[mp_idx_q[2:0]*DATA_W +: DATA_W];
                ge_div_num <= {{(64-DATA_W){mp_score_q[DATA_W-1]}}, mp_score_q} <<< 16;
                ge_div_den <= (mp_den_q != 0) ? mp_den_q : 64'sd1;
                div_return_back <= 1'b0;
                div_return_mp <= 1'b1;
                state <= S_DIV_INIT;
            end
            S_MP_DIV_DONE: begin
                div_return_mp <= 1'b0;
                coeff_mem[0] <= sat_s24(div_result);
                mp_x_new_q <= sat_s24($signed(mp_x_old_q) + $signed(div_result));
                write_idx <= mp_idx_q;
                state <= S_MP_X_WRITE;
            end
            S_GP_DIV_DONE: begin
                div_return_gp <= 1'b0;
                // ge_div_num is numerator<<16, so the divider result is a
                // Q16 line-search alpha consumed by OP_GP_UPDATE.
                gp_alpha_q <= div_result;
                state <= S_DONE;
            end
            S_MP_X_WRITE: begin
                active_k <= 8'd1;
                active_k_count_q <= 6'd1;
                support_cache[0] <= mp_idx_q;
                write_idx <= {IDX_W{1'b0}};
                write_limit <= m_size;
                phase_residual <= 1'b1;
                rd_addr <= 10'h080;
                phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                padded_n_q <= ((n_size + 7) >> 3) << 3;
                for (gi = 0; gi < MAX_K; gi = gi + 1)
                    phi_cache[gi] <= {DATA_W{1'b0}};
                phi_scan_col_q <= {IDX_W{1'b0}};
                phi_scan_state_q <= (|seed) ? seed : DEFAULT_SEED;
                state <= S_SCAN_DIRECT_STEP;
            end
            S_SOLVE_DONE: begin
`ifdef TB_PHASE_TRACE
                $display("PHASE_LS_DONE op=%0d k=%0d s0=%0d s1=%0d s2=%0d s3=%0d s4=%0d s5=%0d s6=%0d s7=%0d s8=%0d s9=%0d s10=%0d s11=%0d s12=%0d s13=%0d s14=%0d s15=%0d c0=%0d c1=%0d c2=%0d c3=%0d c4=%0d c5=%0d c6=%0d c7=%0d c8=%0d c9=%0d c10=%0d c11=%0d c12=%0d c13=%0d c14=%0d c15=%0d",
                    active_op, active_k_count,
                    support_cache[0], support_cache[1], support_cache[2], support_cache[3],
                    support_cache[4], support_cache[5], support_cache[6], support_cache[7],
                    support_cache[8], support_cache[9], support_cache[10], support_cache[11],
                    support_cache[12], support_cache[13], support_cache[14], support_cache[15],
                    coeff_mem[0], coeff_mem[1], coeff_mem[2], coeff_mem[3],
                    coeff_mem[4], coeff_mem[5], coeff_mem[6], coeff_mem[7],
                    coeff_mem[8], coeff_mem[9], coeff_mem[10], coeff_mem[11],
                    coeff_mem[12], coeff_mem[13], coeff_mem[14], coeff_mem[15]);
`endif
                write_idx <= {IDX_W{1'b0}};
                phase_residual <= 1'b0;
                refine_stream_count_q <= 6'd0;
                if (x_support_has_drop_w && (x_support_k_q != 0)) begin
                    write_limit <= x_support_k_q;
                    wx_target_idx_q <= x_support_cache[0];
                    wx_value_q <= {DATA_W{1'b0}};
                    state <= S_WX_CLEAR;
                end else begin
                    write_limit <= active_k_count;
                    wx_target_idx_q <= support_cached_at(5'd0);
                    wx_value_q <= coeff_mem[0];
                    state <= S_WX_COMMIT;
                end
            end
            S_CORR_INIT: begin
                corr_row <= {IDX_W{1'b0}};
                corr_scan_col <= {IDX_W{1'b0}};
                corr_acc <= 64'sd0;
                corr_phi_lane <= {COLS*DATA_W{1'b0}};
                corr_y_block <= {COLS*DATA_W{1'b0}};
                corr_y_next_block <= {COLS*DATA_W{1'b0}};
                rd_addr <= 10'h080;
                phi_state_q <= corr_block_state;
                corr_row_state <= corr_block_state;
                corr_row_next_state <= lfsr_jump_padded(corr_block_state, padded_n_q);
                state <= S_CORR_SCAN;
            end
            S_CORR_SCAN: begin
                for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                    if ((corr_col + corr_lane[IDX_W-1:0]) < n_size)
                        corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= phi_from_lfsr_state(lfsr_advance(corr_row_state, corr_lane[IDX_W-1:0] + 1'b1));
                    else
                        corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
                end
                phi_state_q <= corr_row_next_state;
                corr_scan_col <= {IDX_W{1'b0}};
                // One startup wait lets the synchronous SPM port publish the
                // complete 8-sample residual word.  Subsequent words are
                // prefetched while the current word streams at II=1.
                state <= S_CORR_LATCH;
            end
            S_CORR_LATCH: begin
                corr_y_block <= rd_data;
                state <= S_CORR_ACC;
            end
            S_CORR_ACC: begin
                // Start the next synchronous SPM read early enough that it is
                // cached before the current eight-row word is exhausted.
                if ((corr_row[2:0] == 3'd0) &&
                    (((corr_row >> 3) + 1'b1) << 3 < m_size))
                    rd_addr <= 10'h080 + (corr_row >> 3) + 1'b1;

                // rd_data for the prefetched word is stable by stream slot 2.
                if ((corr_row[2:0] == 3'd2) &&
                    (((corr_row >> 3) + 1'b1) << 3 < m_size))
                    corr_y_next_block <= rd_data;

                if (corr_row + 1 < m_size) begin
                    for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                        if ((corr_col + corr_lane[IDX_W-1:0]) < n_size)
                            corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= phi_from_lfsr_state(lfsr_advance(corr_row_next_state, corr_lane[IDX_W-1:0] + 1'b1));
                        else
                            corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
                    end
                    phi_state_q <= lfsr_jump_padded(corr_row_next_state, padded_n_q);
                    corr_scan_col <= {IDX_W{1'b0}};
                end
                if (corr_row + 1 >= m_size) begin
                    // The PE input register still holds the final sample; one
                    // drain clock commits it to its row accumulator.
                    // Row 3 consumes the final m mod 4 token, then its PE
                    // accumulator commits on the following edge.  Keep one
                    // explicit capture clock before exposing corr_acc_bus.
                    // The registered multiplier result needs one additional
                    // drain clock before the final PE accumulator is visible.
                    corr_drain_wait_q <= 2'd3;
                    state <= S_CORR_PE_WAIT;
                end else begin
                    if (corr_row[2:0] == 3'd7)
                        corr_y_block <= corr_y_next_block;
                    corr_row <= corr_row + 1'b1;
                    corr_row_state <= corr_row_next_state;
                    corr_row_next_state <= lfsr_jump_padded(corr_row_next_state, padded_n_q);
                    state <= S_CORR_ACC;
                end
            end
            S_CORR_PE_WAIT: begin
                if (corr_drain_wait_q != 0) begin
                    corr_drain_wait_q <= corr_drain_wait_q - 1'b1;
                end else if (corr_stream_active && corr_stream_valid_q && !corr_stream_ready) begin
                    // Keep the completed correlation block in the registered
                    // producer slot until the PE0 serial consumer accepts it.
                    // Correlation may prepare the next block in parallel, but
                    // it cannot overwrite an unconsumed stream transaction.
                    state <= S_CORR_PE_WAIT;
                end else begin
                    write_idx <= corr_col;
                    if (active_op == OP_CORR_UPDATE)
                        rd_addr <= 10'h000 + (corr_col >> 3);
                    state <= S_CORR_WRITE;
                end
            end
            S_CORR_WRITE: begin
                if (!corr_stream_post_update_x) begin
                    corr_stream_valid_q <= busy && corr_stream_active;
                    corr_stream_done_q <= corr_stream_active &&
                                          (corr_col + COLS[IDX_W-1:0] >= n_size);
                    corr_stream_base_idx_q <= corr_col;
                    for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                        corr_stream_lane_valid_q[corr_lane] <= ((corr_col + corr_lane[IDX_W-1:0]) < n_size);
                        corr_stream_data_q[corr_lane*DATA_W +: DATA_W] <= row3_wr_data[corr_lane*DATA_W +: DATA_W];
                    end
                end
                corr_block_seq <= corr_block_seq + 1'b1;
                if (active_op == OP_CORR_UPDATE) begin
                    // Score writeback occurs on this clock.  In parallel,
                    // capture its full block as the update delta; the x block
                    // requested in S_CORR_PE_WAIT is available next clock.
                    mesh_ctx_delta_block <= row3_wr_data;
                    mesh_ctx_keep_block <= {COLS{1'b1}};
                    mesh_ctx_base_idx_block <= corr_col;
                    mesh_ctx_limit_block <= n_size;
                    mesh_ctx_shift_block <= mu_shift_eff;
                    mesh_ctx_wait_count <= MESH_CTX_WAIT_CYCLES;
                    state <= S_FUSED_UPDATE_CAPTURE;
                end else if (corr_col + COLS[IDX_W-1:0] >= n_size) begin
                    state <= S_DONE;
                end else begin
                    corr_col <= corr_col + COLS[IDX_W-1:0];
                    corr_block_state <= lfsr_advance(corr_block_state, COLS);
                    state <= S_CORR_INIT;
                end
            end
            S_FUSED_UPDATE_CAPTURE: begin
                mesh_ctx_x_block <= rd_data;
                state <= S_IHT_MESH_WAIT;
            end
            S_IHT_MESH_WAIT: begin
                if (mesh_ctx_wait_count == 0)
                    state <= S_IHT_MESH_WRITE;
                else
                    mesh_ctx_wait_count <= mesh_ctx_wait_count - 1'b1;
            end
            S_IHT_MESH_WRITE: begin
                if (corr_stream_active && corr_stream_post_update_x) begin
                    // The updated x block has entered only at PE0 and reached
                    // PE3 through the registered mesh wavefront.  Publish the
                    // exact block committed to SPM, not the pre-update score.
                    corr_stream_valid_q <= busy;
                    corr_stream_done_q <=
                        (corr_col + COLS[IDX_W-1:0] >= n_size);
                    corr_stream_base_idx_q <= corr_col;
                    for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                        corr_stream_lane_valid_q[corr_lane] <=
                            ((corr_col + corr_lane[IDX_W-1:0]) < n_size);
                        corr_stream_data_q[corr_lane*DATA_W +: DATA_W] <=
                            row3_wr_data[corr_lane*DATA_W +: DATA_W];
                    end
                end
                if (corr_col + COLS[IDX_W-1:0] >= n_size) begin
                    state <= S_DONE;
                end else begin
                    corr_col <= corr_col + COLS[IDX_W-1:0];
                    corr_block_state <= lfsr_advance(corr_block_state, COLS);
                    state <= S_CORR_INIT;
                end
            end
            S_IHT_X_READ: begin
                state <= S_IHT_X_WAIT;
            end
            S_IHT_X_WAIT: begin
                iht_x_value <= rd_data[write_idx[2:0]*DATA_W +: DATA_W];
                rd_addr <= 10'h180 + write_idx[IDX_W-1:3];
                state <= S_IHT_SCORE_WAIT;
            end
            S_IHT_SCORE_WAIT: begin
                state <= S_IHT_SCORE_READ;
            end
            S_IHT_SCORE_READ: begin
                if (active_op == OP_GP_UPDATE) begin
                    // Conservative GP retime: BRAM output, multiplier, add,
                    // saturation and SPM commit each terminate at a register.
                    // The extra clocks are intentional timing margin; the
                    // fixed-point operation order and truncation stay exact.
                    gp_update_x_q <= iht_x_value;
                    gp_update_grad_q <=
                        rd_data[write_idx[2:0]*DATA_W +: DATA_W];
                    gp_update_alpha_q <= gp_alpha_q[DATA_W-1:0];
                    gp_update_support_q <= support_cached_has_idx(write_idx);
                    state <= S_GP_UPDATE_OPERANDS;
                end else begin
                    write_value <= write_value_now;
                    if (write_idx + 1'b1 >= write_limit) begin
                        state <= S_DONE;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                        rd_addr <= 10'h000 + ((write_idx + 1'b1) >> 3);
                        state <= S_IHT_X_READ;
                    end
                end
            end
            S_GP_UPDATE_OPERANDS: begin
                gp_update_product_q <= gp_update_support_q ?
                    mul_s24_s24(gp_update_grad_q, gp_update_alpha_q) :
                    64'sd0;
                state <= S_GP_UPDATE_MUL;
            end
            S_GP_UPDATE_MUL: begin
                gp_update_sum_q <= $signed(gp_update_x_q) +
                                   ($signed(gp_update_product_q) >>> 16);
                state <= S_GP_UPDATE_SAT;
            end
            S_GP_UPDATE_SAT: begin
                gp_update_value_q <= sat_s24(gp_update_sum_q);
                state <= S_GP_UPDATE_COMMIT;
            end
            S_GP_UPDATE_COMMIT: begin
                write_value <= gp_update_value_q;
                if (write_idx + 1'b1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    rd_addr <= 10'h000 + ((write_idx + 1'b1) >> 3);
                    state <= S_IHT_X_READ;
                end
            end
            S_LOAD_COEFF_READ: begin
                state <= S_LOAD_COEFF_CAP;
            end
            S_LOAD_COEFF_WAIT: begin
                state <= S_LOAD_COEFF_CAP;
            end
            S_LOAD_COEFF_CAP: begin
                coeff_mem[load_i] <= rd_data[load_support_q[2:0]*DATA_W +: DATA_W];
                if (load_i + 5'd1 >= active_k_count) begin
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= (active_op == OP_GP_PROJECT) ? 10'h080 : 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                                padded_n_q <= ((n_size + 7) >> 3) << 3;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    phi_scan_col_q <= {IDX_W{1'b0}};
                    phi_scan_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    state <= S_SCAN_DIRECT_STEP;
                end else begin
                    load_i <= load_i + 5'd1;
                    load_support_q <= load_support_next_q;
                    rd_addr <= ((active_op == OP_GP_PROJECT) ? 10'h180 : 10'h000) + (load_support_next_q >> 3);
                    state <= S_LOAD_COEFF_READ;
                end
            end
            S_PRUNE_X_READ: begin
                state <= S_PRUNE_X_WAIT;
            end
            S_PRUNE_X_WAIT: begin
                // One complete x word enters PE0.  The support keep mask and
                // address metadata follow the same registered southward token
                // through PE1, PE2, and PE3; no lower row receives controller
                // data directly.
                mesh_ctx_delta_block <= rd_data;
                mesh_ctx_keep_block <= row2_prune_keep_mask;
                mesh_ctx_base_idx_block <= write_idx;
                mesh_ctx_limit_block <= write_limit;
                mesh_ctx_shift_block <= 4'd0;
                mesh_ctx_wait_count <= MESH_CTX_WAIT_CYCLES;
                state <= S_PRUNE_MESH_WAIT;
            end
            S_PRUNE_MESH_WAIT: begin
                if (mesh_ctx_wait_count == 0)
                    state <= S_PRUNE_MESH_WRITE;
                else
                    mesh_ctx_wait_count <= mesh_ctx_wait_count - 1'b1;
            end
            S_PRUNE_MESH_WRITE: begin
                if (write_idx + COLS[IDX_W-1:0] >= write_limit) begin
                    x_support_k_q <= active_k_count;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        if (gi < active_k_count)
                            x_support_cache[gi] <= support_cache[gi];
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + COLS[IDX_W-1:0];
                    rd_addr <= 10'h000 + ((write_idx + COLS[IDX_W-1:0]) >> 3);
                    state <= S_PRUNE_X_READ;
                end
            end
            S_SCAN_DIRECT: begin
                phi_scan_col_q <= {IDX_W{1'b0}};
                phi_scan_state_q <= phi_state_q;
                for (gi = 0; gi < MAX_K; gi = gi + 1)
                    phi_cache[gi] <= {DATA_W{1'b0}};
                state <= S_SCAN_DIRECT_STEP;
            end
            S_SCAN_DIRECT_STEP: begin
                if (padded_n_q <= 10'd64) begin
                    // Preserve the original two-cycle N=64 schedule.  Several
                    // callers enter this scan on the same edge that changes a
                    // synchronous SPM address, so collapsing N=64 to one scan
                    // clock removes a required memory-settle interval.
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        if ((gi < active_k_count) &&
                            (support_cache[gi] >= phi_scan_col_q) &&
                            (support_cache[gi] < (phi_scan_col_q + 10'd32)))
                            phi_cache[gi] <= phi_from_lfsr_state(
                                lfsr_advance32(phi_scan_state_q,
                                    (support_cache[gi] - phi_scan_col_q) + 6'd1));
                    end
                    if (phi_scan_col_q + 10'd32 >= padded_n_q) begin
                        phi_state_q <= phi_scan_state32_w;
                        state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                    end else begin
                        phi_scan_col_q <= phi_scan_col_q + 10'd32;
                        phi_scan_state_q <= phi_scan_state32_w;
                    end
                end else if (padded_n_q <= 10'd128) begin
                    // Keep N=128 at two scan clocks.  As with N=64, callers
                    // rely on this interval after changing an SPM address.
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        if ((gi < active_k_count) &&
                            (support_cache[gi] >= phi_scan_col_q) &&
                            (support_cache[gi] < (phi_scan_col_q + 10'd64))) begin
                            if (support_cache[gi] < (phi_scan_col_q + 10'd32))
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state_q,
                                        (support_cache[gi] - phi_scan_col_q) + 6'd1));
                            else
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state32_w,
                                        (support_cache[gi] - phi_scan_col_q - 10'd32) + 6'd1));
                        end
                    end
                    if (phi_scan_col_q + 10'd64 >= padded_n_q) begin
                        phi_state_q <= phi_scan_state64_w;
                        state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                    end else begin
                        phi_scan_col_q <= phi_scan_col_q + 10'd64;
                        phi_scan_state_q <= phi_scan_state64_w;
                    end
                end else begin
                    // N=256 has enough remaining scan latency to cover the
                    // synchronous SPM settle interval.  Four independent
                    // 32-column windows therefore complete 128 columns per
                    // controller clock without a long serial feedback path.
                    for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                        if ((gi < active_k_count) &&
                            (support_cache[gi] >= phi_scan_col_q) &&
                            (support_cache[gi] < (phi_scan_col_q + 10'd128))) begin
                            if (support_cache[gi] < (phi_scan_col_q + 10'd32))
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state_q,
                                        (support_cache[gi] - phi_scan_col_q) + 6'd1));
                            else if (support_cache[gi] < (phi_scan_col_q + 10'd64))
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state32_w,
                                        (support_cache[gi] - phi_scan_col_q - 10'd32) + 6'd1));
                            else if (support_cache[gi] < (phi_scan_col_q + 10'd96))
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state64_w,
                                        (support_cache[gi] - phi_scan_col_q - 10'd64) + 6'd1));
                            else
                                phi_cache[gi] <= phi_from_lfsr_state(
                                    lfsr_advance32(phi_scan_state96_w,
                                        (support_cache[gi] - phi_scan_col_q - 10'd96) + 6'd1));
                        end
                    end
                    if (phi_scan_col_q + 10'd128 >= padded_n_q) begin
                        phi_state_q <= phi_scan_state128_w;
                        state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                    end else begin
                        phi_scan_col_q <= phi_scan_col_q + 10'd128;
                        phi_scan_state_q <= phi_scan_state128_w;
                    end
                end
            end
            S_DONE: begin                busy <= 1'b0;
                done <= 1'b1;
                result <= {SCALAR_W{1'b0}};
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
        // Both LDLT diagonal gather and the unit-lower forward solve consume
        // the same four coefficient-lane registers.  Share one tail-clear
        // write decode so adding forward-solve completion does not duplicate
        // a 4x64-bit zero-fill mux.  Only the coefficient side must be zero:
        // the paired stale RHS value is harmless because 0*x remains zero.
        if (ls_done_w && ldlt_shared_tail_state_w &&
            ldlt_shared_tail_last_w) begin
            for (gi = 0; gi < 4; gi = gi + 1) begin
                if (gi > ldlt_lane_q)
                    ldlt_l_lane_q[gi] <= 64'sd0;
            end
        end
    end
end
endmodule































