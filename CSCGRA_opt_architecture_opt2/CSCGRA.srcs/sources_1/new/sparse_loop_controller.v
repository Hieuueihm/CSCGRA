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
    output wire corr_stream_valid,
    output wire corr_stream_done,
    output wire [IDX_W-1:0] corr_stream_base_idx,
    output wire [COLS-1:0] corr_stream_lane_valid,
    output wire [COLS*DATA_W-1:0] corr_stream_data,
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
localparam [6:0] S_IDLE=0, S_PRIME=1, S_ACC=3, S_WX=5, S_WR=7, S_DONE=8, S_SCAN=10, S_SOLVE_INIT=11, S_ELIM_START=12, S_ELIM_ROW=13, S_ELIM_UPDATE=14, S_BACK_INIT=15, S_BACK_ACC=16, S_BACK_DIV=17, S_SOLVE_DONE=18, S_ACC_RHS=19, S_ACC_GRAM=20, S_WR_ACC_INIT=21, S_WR_ACC=22, S_BACK_PREP=23, S_ELIM_PREP=24, S_ELIM_MUL=25, S_BACK_MUL=26, S_BACK_UPDATE=27, S_DIV_INIT=28, S_DIV_STEP=29, S_ELIM_DIV_DONE=30, S_BACK_DIV_DONE=31, S_CORR_INIT=34, S_CORR_SCAN=35, S_CORR_ACC=36, S_CORR_WRITE=37, S_IHT_X_WAIT=38, S_IHT_SCORE_WAIT=39, S_LOAD_COEFF_WAIT=40, S_PRUNE_X_WAIT=41, S_IHT_SCORE_READ=42, S_IHT_X_READ=43, S_PRUNE_X_READ=44, S_LOAD_COEFF_READ=45, S_LOAD_COEFF_CAP=46, S_ACC_PE_WAIT=47, S_GRAM_PE_WAIT=48, S_GRAM_PE_WAIT2=49, S_RESID_PE_WAIT=50, S_RESID_PE_WAIT2=51, S_ACC_PE_WAIT2=53, S_CORR_PE_WAIT=54, S_CORR_LATCH=57,
S_CACHE_BUILD=56, S_SCAN_DIRECT=55,
S_MP_X_READ=70, S_MP_X_WAIT=71, S_MP_DIV_PREP=72, S_MP_X_WRITE=73, S_MP_DIV_DONE=74, S_MP_SCORE_CAP=75, S_MP_X_CAP=76, S_SCAN_DIRECT_STEP=77, S_CACHE_BUILD_STEP=78,
S_LS_CLEAR_START=86, S_LS_CLEAR_WAIT=87, S_SOLVE_SYM_READ=88, S_SOLVE_SYM_WAIT=89, S_SOLVE_SYM_WRITE=90, S_SOLVE_SYM_WRITE_WAIT=91,
S_ELIM_ROW_READ=92, S_ELIM_ROW_WAIT=93, S_ELIM_UPDATE_START=94, S_ELIM_UPDATE_WAIT=95, S_BACK_ACC_READ=96, S_BACK_ACC_WAIT=97, S_BACK_PREP_READ=98, S_BACK_PREP_WAIT=99, S_GRAM_ACC_WAIT=100, S_SCAN_DIRECT_LATCH=101, S_RHS_INIT_WRITE=102, S_RHS_INIT_WAIT=103, S_ELIM_RHS_READ_WAIT=104, S_ELIM_RHS_UPDATE_WAIT=105, S_BACK_RHS_READ=106, S_BACK_RHS_READ_WAIT=107;
localparam [6:0] S_IHT_MESH_WAIT=108, S_IHT_MESH_WRITE=110, S_PRUNE_MESH_WAIT=111, S_PRUNE_MESH_WRITE=113, S_WR_MESH_WAIT=114, S_WR_MESH_COMMIT=116, S_WX_COMMIT=117;
localparam [3:0] OP_REFINE=4'd0, OP_CORR=4'd1, OP_IHT_UPDATE=4'd2, OP_RESID=4'd3, OP_PRUNE_X=4'd4, OP_MP_UPDATE=4'd5, OP_REFINE_SPARSE=4'd6, OP_GRAD_STEP=4'd7; // OP_GRAD_STEP: scaled projected-gradient x += (Phi^T r >>> mu_shift), followed by prune/residual in context
localparam [1:0] MESH_CTX_NONE=2'd0, MESH_CTX_UPDATE=2'd1, MESH_CTX_PRUNE=2'd2, MESH_CTX_RESID=2'd3;
localparam [3:0] MESH_CTX_WAIT_CYCLES = 4'd6;
localparam [4:0] RHS_BLOCK_STRIDE = COLS;
localparam [4:0] LS_ROW_UPDATE_STRIDE = COLS;
localparam [2:0] LS_OP_CLEAR=3'd0, LS_OP_WRITE=3'd1, LS_OP_READ2=3'd2, LS_OP_ACC_BLOCK=3'd3, LS_OP_ROW_UPDATE=3'd4, LS_OP_RHS_WRITE=3'd5, LS_OP_RHS_READ=3'd6, LS_OP_RHS_UPDATE=3'd7;

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
function [31:0] lfsr_jump_padded;
    input [31:0] state;
    input [IDX_W-1:0] steps;
    begin
        lfsr_jump_padded = state;
        case (steps)
            10'd8: begin
                lfsr_jump_padded[0] = ^(state & 32'h000001b6);
                lfsr_jump_padded[1] = ^(state & 32'h000002db);
                lfsr_jump_padded[2] = ^(state & 32'h00000400);
                lfsr_jump_padded[3] = ^(state & 32'h00000800);
                lfsr_jump_padded[4] = ^(state & 32'h00001000);
                lfsr_jump_padded[5] = ^(state & 32'h00002000);
                lfsr_jump_padded[6] = ^(state & 32'h00004000);
                lfsr_jump_padded[7] = ^(state & 32'h00008000);
                lfsr_jump_padded[8] = ^(state & 32'h00010000);
                lfsr_jump_padded[9] = ^(state & 32'h00020000);
                lfsr_jump_padded[10] = ^(state & 32'h00040000);
                lfsr_jump_padded[11] = ^(state & 32'h00080000);
                lfsr_jump_padded[12] = ^(state & 32'h00100000);
                lfsr_jump_padded[13] = ^(state & 32'h00200000);
                lfsr_jump_padded[14] = ^(state & 32'h00400001);
                lfsr_jump_padded[15] = ^(state & 32'h00800003);
                lfsr_jump_padded[16] = ^(state & 32'h01000006);
                lfsr_jump_padded[17] = ^(state & 32'h0200000d);
                lfsr_jump_padded[18] = ^(state & 32'h0400001b);
                lfsr_jump_padded[19] = ^(state & 32'h08000036);
                lfsr_jump_padded[20] = ^(state & 32'h1000006d);
                lfsr_jump_padded[21] = ^(state & 32'h200000db);
                lfsr_jump_padded[22] = ^(state & 32'h40000000);
                lfsr_jump_padded[23] = ^(state & 32'h80000000);
                lfsr_jump_padded[24] = ^(state & 32'h00000001);
                lfsr_jump_padded[25] = ^(state & 32'h00000003);
                lfsr_jump_padded[26] = ^(state & 32'h00000006);
                lfsr_jump_padded[27] = ^(state & 32'h0000000d);
                lfsr_jump_padded[28] = ^(state & 32'h0000001b);
                lfsr_jump_padded[29] = ^(state & 32'h00000036);
                lfsr_jump_padded[30] = ^(state & 32'h0000006d);
                lfsr_jump_padded[31] = ^(state & 32'h000000db);
            end
            10'd16: begin
                lfsr_jump_padded[0] = ^(state & 32'h0001b6db);
                lfsr_jump_padded[1] = ^(state & 32'h0002db6d);
                lfsr_jump_padded[2] = ^(state & 32'h00040000);
                lfsr_jump_padded[3] = ^(state & 32'h00080000);
                lfsr_jump_padded[4] = ^(state & 32'h00100000);
                lfsr_jump_padded[5] = ^(state & 32'h00200000);
                lfsr_jump_padded[6] = ^(state & 32'h00400001);
                lfsr_jump_padded[7] = ^(state & 32'h00800003);
                lfsr_jump_padded[8] = ^(state & 32'h01000006);
                lfsr_jump_padded[9] = ^(state & 32'h0200000d);
                lfsr_jump_padded[10] = ^(state & 32'h0400001b);
                lfsr_jump_padded[11] = ^(state & 32'h08000036);
                lfsr_jump_padded[12] = ^(state & 32'h1000006d);
                lfsr_jump_padded[13] = ^(state & 32'h200000db);
                lfsr_jump_padded[14] = ^(state & 32'h400001b6);
                lfsr_jump_padded[15] = ^(state & 32'h8000036d);
                lfsr_jump_padded[16] = ^(state & 32'h000006da);
                lfsr_jump_padded[17] = ^(state & 32'h00000db5);
                lfsr_jump_padded[18] = ^(state & 32'h00001b6b);
                lfsr_jump_padded[19] = ^(state & 32'h000036d6);
                lfsr_jump_padded[20] = ^(state & 32'h00006dad);
                lfsr_jump_padded[21] = ^(state & 32'h0000db5b);
                lfsr_jump_padded[22] = ^(state & 32'h0000006d);
                lfsr_jump_padded[23] = ^(state & 32'h000000db);
                lfsr_jump_padded[24] = ^(state & 32'h000001b6);
                lfsr_jump_padded[25] = ^(state & 32'h0000036d);
                lfsr_jump_padded[26] = ^(state & 32'h000006db);
                lfsr_jump_padded[27] = ^(state & 32'h00000db6);
                lfsr_jump_padded[28] = ^(state & 32'h00001b6d);
                lfsr_jump_padded[29] = ^(state & 32'h000036db);
                lfsr_jump_padded[30] = ^(state & 32'h00006db6);
                lfsr_jump_padded[31] = ^(state & 32'h0000db6d);
            end
            10'd24: begin
                lfsr_jump_padded[0] = ^(state & 32'h01b6db68);
                lfsr_jump_padded[1] = ^(state & 32'h02db6db9);
                lfsr_jump_padded[2] = ^(state & 32'h0400001b);
                lfsr_jump_padded[3] = ^(state & 32'h08000036);
                lfsr_jump_padded[4] = ^(state & 32'h1000006d);
                lfsr_jump_padded[5] = ^(state & 32'h200000db);
                lfsr_jump_padded[6] = ^(state & 32'h400001b6);
                lfsr_jump_padded[7] = ^(state & 32'h8000036d);
                lfsr_jump_padded[8] = ^(state & 32'h000006da);
                lfsr_jump_padded[9] = ^(state & 32'h00000db5);
                lfsr_jump_padded[10] = ^(state & 32'h00001b6b);
                lfsr_jump_padded[11] = ^(state & 32'h000036d6);
                lfsr_jump_padded[12] = ^(state & 32'h00006dad);
                lfsr_jump_padded[13] = ^(state & 32'h0000db5b);
                lfsr_jump_padded[14] = ^(state & 32'h0001b6b6);
                lfsr_jump_padded[15] = ^(state & 32'h00036d6d);
                lfsr_jump_padded[16] = ^(state & 32'h0006dadb);
                lfsr_jump_padded[17] = ^(state & 32'h000db5b6);
                lfsr_jump_padded[18] = ^(state & 32'h001b6b6d);
                lfsr_jump_padded[19] = ^(state & 32'h0036d6db);
                lfsr_jump_padded[20] = ^(state & 32'h006dadb7);
                lfsr_jump_padded[21] = ^(state & 32'h00db5b6f);
                lfsr_jump_padded[22] = ^(state & 32'h00006db6);
                lfsr_jump_padded[23] = ^(state & 32'h0000db6d);
                lfsr_jump_padded[24] = ^(state & 32'h0001b6db);
                lfsr_jump_padded[25] = ^(state & 32'h00036db6);
                lfsr_jump_padded[26] = ^(state & 32'h0006db6d);
                lfsr_jump_padded[27] = ^(state & 32'h000db6db);
                lfsr_jump_padded[28] = ^(state & 32'h001b6db6);
                lfsr_jump_padded[29] = ^(state & 32'h0036db6d);
                lfsr_jump_padded[30] = ^(state & 32'h006db6da);
                lfsr_jump_padded[31] = ^(state & 32'h00db6db4);
            end
            10'd32: begin
                lfsr_jump_padded[0] = ^(state & 32'hb6db68a3);
                lfsr_jump_padded[1] = ^(state & 32'hdb6db9e4);
                lfsr_jump_padded[2] = ^(state & 32'h00001b6b);
                lfsr_jump_padded[3] = ^(state & 32'h000036d6);
                lfsr_jump_padded[4] = ^(state & 32'h00006dad);
                lfsr_jump_padded[5] = ^(state & 32'h0000db5b);
                lfsr_jump_padded[6] = ^(state & 32'h0001b6b6);
                lfsr_jump_padded[7] = ^(state & 32'h00036d6d);
                lfsr_jump_padded[8] = ^(state & 32'h0006dadb);
                lfsr_jump_padded[9] = ^(state & 32'h000db5b6);
                lfsr_jump_padded[10] = ^(state & 32'h001b6b6d);
                lfsr_jump_padded[11] = ^(state & 32'h0036d6db);
                lfsr_jump_padded[12] = ^(state & 32'h006dadb7);
                lfsr_jump_padded[13] = ^(state & 32'h00db5b6f);
                lfsr_jump_padded[14] = ^(state & 32'h01b6b6de);
                lfsr_jump_padded[15] = ^(state & 32'h036d6dbc);
                lfsr_jump_padded[16] = ^(state & 32'h06dadb79);
                lfsr_jump_padded[17] = ^(state & 32'h0db5b6f3);
                lfsr_jump_padded[18] = ^(state & 32'h1b6b6de7);
                lfsr_jump_padded[19] = ^(state & 32'h36d6dbcf);
                lfsr_jump_padded[20] = ^(state & 32'h6dadb79e);
                lfsr_jump_padded[21] = ^(state & 32'hdb5b6f3c);
                lfsr_jump_padded[22] = ^(state & 32'h006db6da);
                lfsr_jump_padded[23] = ^(state & 32'h00db6db4);
                lfsr_jump_padded[24] = ^(state & 32'h01b6db68);
                lfsr_jump_padded[25] = ^(state & 32'h036db6d1);
                lfsr_jump_padded[26] = ^(state & 32'h06db6da2);
                lfsr_jump_padded[27] = ^(state & 32'h0db6db45);
                lfsr_jump_padded[28] = ^(state & 32'h1b6db68a);
                lfsr_jump_padded[29] = ^(state & 32'h36db6d14);
                lfsr_jump_padded[30] = ^(state & 32'h6db6da28);
                lfsr_jump_padded[31] = ^(state & 32'hdb6db451);
            end
            10'd40: begin
                lfsr_jump_padded[0] = ^(state & 32'hdb68a3cf);
                lfsr_jump_padded[1] = ^(state & 32'h6db9e451);
                lfsr_jump_padded[2] = ^(state & 32'h001b6b6d);
                lfsr_jump_padded[3] = ^(state & 32'h0036d6db);
                lfsr_jump_padded[4] = ^(state & 32'h006dadb7);
                lfsr_jump_padded[5] = ^(state & 32'h00db5b6f);
                lfsr_jump_padded[6] = ^(state & 32'h01b6b6de);
                lfsr_jump_padded[7] = ^(state & 32'h036d6dbc);
                lfsr_jump_padded[8] = ^(state & 32'h06dadb79);
                lfsr_jump_padded[9] = ^(state & 32'h0db5b6f3);
                lfsr_jump_padded[10] = ^(state & 32'h1b6b6de7);
                lfsr_jump_padded[11] = ^(state & 32'h36d6dbcf);
                lfsr_jump_padded[12] = ^(state & 32'h6dadb79e);
                lfsr_jump_padded[13] = ^(state & 32'hdb5b6f3c);
                lfsr_jump_padded[14] = ^(state & 32'hb6b6de79);
                lfsr_jump_padded[15] = ^(state & 32'h6d6dbcf3);
                lfsr_jump_padded[16] = ^(state & 32'hdadb79e7);
                lfsr_jump_padded[17] = ^(state & 32'hb5b6f3cf);
                lfsr_jump_padded[18] = ^(state & 32'h6b6de79e);
                lfsr_jump_padded[19] = ^(state & 32'hd6dbcf3c);
                lfsr_jump_padded[20] = ^(state & 32'hadb79e79);
                lfsr_jump_padded[21] = ^(state & 32'h5b6f3cf3);
                lfsr_jump_padded[22] = ^(state & 32'h6db6da28);
                lfsr_jump_padded[23] = ^(state & 32'hdb6db451);
                lfsr_jump_padded[24] = ^(state & 32'hb6db68a3);
                lfsr_jump_padded[25] = ^(state & 32'h6db6d147);
                lfsr_jump_padded[26] = ^(state & 32'hdb6da28f);
                lfsr_jump_padded[27] = ^(state & 32'hb6db451e);
                lfsr_jump_padded[28] = ^(state & 32'h6db68a3c);
                lfsr_jump_padded[29] = ^(state & 32'hdb6d1479);
                lfsr_jump_padded[30] = ^(state & 32'hb6da28f3);
                lfsr_jump_padded[31] = ^(state & 32'h6db451e7);
            end
            10'd48: begin
                lfsr_jump_padded[0] = ^(state & 32'h68a3cf21);
                lfsr_jump_padded[1] = ^(state & 32'hb9e45163);
                lfsr_jump_padded[2] = ^(state & 32'h1b6b6de7);
                lfsr_jump_padded[3] = ^(state & 32'h36d6dbcf);
                lfsr_jump_padded[4] = ^(state & 32'h6dadb79e);
                lfsr_jump_padded[5] = ^(state & 32'hdb5b6f3c);
                lfsr_jump_padded[6] = ^(state & 32'hb6b6de79);
                lfsr_jump_padded[7] = ^(state & 32'h6d6dbcf3);
                lfsr_jump_padded[8] = ^(state & 32'hdadb79e7);
                lfsr_jump_padded[9] = ^(state & 32'hb5b6f3cf);
                lfsr_jump_padded[10] = ^(state & 32'h6b6de79e);
                lfsr_jump_padded[11] = ^(state & 32'hd6dbcf3c);
                lfsr_jump_padded[12] = ^(state & 32'hadb79e79);
                lfsr_jump_padded[13] = ^(state & 32'h5b6f3cf3);
                lfsr_jump_padded[14] = ^(state & 32'hb6de79e7);
                lfsr_jump_padded[15] = ^(state & 32'h6dbcf3cf);
                lfsr_jump_padded[16] = ^(state & 32'hdb79e79f);
                lfsr_jump_padded[17] = ^(state & 32'hb6f3cf3e);
                lfsr_jump_padded[18] = ^(state & 32'h6de79e7d);
                lfsr_jump_padded[19] = ^(state & 32'hdbcf3cfa);
                lfsr_jump_padded[20] = ^(state & 32'hb79e79f4);
                lfsr_jump_padded[21] = ^(state & 32'h6f3cf3e9);
                lfsr_jump_padded[22] = ^(state & 32'hb6da28f3);
                lfsr_jump_padded[23] = ^(state & 32'h6db451e7);
                lfsr_jump_padded[24] = ^(state & 32'hdb68a3cf);
                lfsr_jump_padded[25] = ^(state & 32'hb6d1479e);
                lfsr_jump_padded[26] = ^(state & 32'h6da28f3c);
                lfsr_jump_padded[27] = ^(state & 32'hdb451e79);
                lfsr_jump_padded[28] = ^(state & 32'hb68a3cf2);
                lfsr_jump_padded[29] = ^(state & 32'h6d1479e4);
                lfsr_jump_padded[30] = ^(state & 32'hda28f3c8);
                lfsr_jump_padded[31] = ^(state & 32'hb451e790);
            end
            10'd56: begin
                lfsr_jump_padded[0] = ^(state & 32'ha3cf2132);
                lfsr_jump_padded[1] = ^(state & 32'he4516356);
                lfsr_jump_padded[2] = ^(state & 32'h6b6de79e);
                lfsr_jump_padded[3] = ^(state & 32'hd6dbcf3c);
                lfsr_jump_padded[4] = ^(state & 32'hadb79e79);
                lfsr_jump_padded[5] = ^(state & 32'h5b6f3cf3);
                lfsr_jump_padded[6] = ^(state & 32'hb6de79e7);
                lfsr_jump_padded[7] = ^(state & 32'h6dbcf3cf);
                lfsr_jump_padded[8] = ^(state & 32'hdb79e79f);
                lfsr_jump_padded[9] = ^(state & 32'hb6f3cf3e);
                lfsr_jump_padded[10] = ^(state & 32'h6de79e7d);
                lfsr_jump_padded[11] = ^(state & 32'hdbcf3cfa);
                lfsr_jump_padded[12] = ^(state & 32'hb79e79f4);
                lfsr_jump_padded[13] = ^(state & 32'h6f3cf3e9);
                lfsr_jump_padded[14] = ^(state & 32'hde79e7d2);
                lfsr_jump_padded[15] = ^(state & 32'hbcf3cfa5);
                lfsr_jump_padded[16] = ^(state & 32'h79e79f4b);
                lfsr_jump_padded[17] = ^(state & 32'hf3cf3e97);
                lfsr_jump_padded[18] = ^(state & 32'he79e7d2f);
                lfsr_jump_padded[19] = ^(state & 32'hcf3cfa5f);
                lfsr_jump_padded[20] = ^(state & 32'h9e79f4be);
                lfsr_jump_padded[21] = ^(state & 32'h3cf3e97d);
                lfsr_jump_padded[22] = ^(state & 32'hda28f3c8);
                lfsr_jump_padded[23] = ^(state & 32'hb451e790);
                lfsr_jump_padded[24] = ^(state & 32'h68a3cf21);
                lfsr_jump_padded[25] = ^(state & 32'hd1479e42);
                lfsr_jump_padded[26] = ^(state & 32'ha28f3c84);
                lfsr_jump_padded[27] = ^(state & 32'h451e7909);
                lfsr_jump_padded[28] = ^(state & 32'h8a3cf213);
                lfsr_jump_padded[29] = ^(state & 32'h1479e426);
                lfsr_jump_padded[30] = ^(state & 32'h28f3c84c);
                lfsr_jump_padded[31] = ^(state & 32'h51e79099);
            end
            10'd64: begin
                lfsr_jump_padded[0] = ^(state & 32'hcf213212);
                lfsr_jump_padded[1] = ^(state & 32'h51635637);
                lfsr_jump_padded[2] = ^(state & 32'h6de79e7d);
                lfsr_jump_padded[3] = ^(state & 32'hdbcf3cfa);
                lfsr_jump_padded[4] = ^(state & 32'hb79e79f4);
                lfsr_jump_padded[5] = ^(state & 32'h6f3cf3e9);
                lfsr_jump_padded[6] = ^(state & 32'hde79e7d2);
                lfsr_jump_padded[7] = ^(state & 32'hbcf3cfa5);
                lfsr_jump_padded[8] = ^(state & 32'h79e79f4b);
                lfsr_jump_padded[9] = ^(state & 32'hf3cf3e97);
                lfsr_jump_padded[10] = ^(state & 32'he79e7d2f);
                lfsr_jump_padded[11] = ^(state & 32'hcf3cfa5f);
                lfsr_jump_padded[12] = ^(state & 32'h9e79f4be);
                lfsr_jump_padded[13] = ^(state & 32'h3cf3e97d);
                lfsr_jump_padded[14] = ^(state & 32'h79e7d2fa);
                lfsr_jump_padded[15] = ^(state & 32'hf3cfa5f4);
                lfsr_jump_padded[16] = ^(state & 32'he79f4be9);
                lfsr_jump_padded[17] = ^(state & 32'hcf3e97d2);
                lfsr_jump_padded[18] = ^(state & 32'h9e7d2fa5);
                lfsr_jump_padded[19] = ^(state & 32'h3cfa5f4b);
                lfsr_jump_padded[20] = ^(state & 32'h79f4be97);
                lfsr_jump_padded[21] = ^(state & 32'hf3e97d2f);
                lfsr_jump_padded[22] = ^(state & 32'h28f3c84c);
                lfsr_jump_padded[23] = ^(state & 32'h51e79099);
                lfsr_jump_padded[24] = ^(state & 32'ha3cf2132);
                lfsr_jump_padded[25] = ^(state & 32'h479e4264);
                lfsr_jump_padded[26] = ^(state & 32'h8f3c84c8);
                lfsr_jump_padded[27] = ^(state & 32'h1e790990);
                lfsr_jump_padded[28] = ^(state & 32'h3cf21321);
                lfsr_jump_padded[29] = ^(state & 32'h79e42642);
                lfsr_jump_padded[30] = ^(state & 32'hf3c84c84);
                lfsr_jump_padded[31] = ^(state & 32'he7909909);
            end
            10'd72: begin
                lfsr_jump_padded[0] = ^(state & 32'h213212b9);
                lfsr_jump_padded[1] = ^(state & 32'h635637cb);
                lfsr_jump_padded[2] = ^(state & 32'he79e7d2f);
                lfsr_jump_padded[3] = ^(state & 32'hcf3cfa5f);
                lfsr_jump_padded[4] = ^(state & 32'h9e79f4be);
                lfsr_jump_padded[5] = ^(state & 32'h3cf3e97d);
                lfsr_jump_padded[6] = ^(state & 32'h79e7d2fa);
                lfsr_jump_padded[7] = ^(state & 32'hf3cfa5f4);
                lfsr_jump_padded[8] = ^(state & 32'he79f4be9);
                lfsr_jump_padded[9] = ^(state & 32'hcf3e97d2);
                lfsr_jump_padded[10] = ^(state & 32'h9e7d2fa5);
                lfsr_jump_padded[11] = ^(state & 32'h3cfa5f4b);
                lfsr_jump_padded[12] = ^(state & 32'h79f4be97);
                lfsr_jump_padded[13] = ^(state & 32'hf3e97d2f);
                lfsr_jump_padded[14] = ^(state & 32'he7d2fa5e);
                lfsr_jump_padded[15] = ^(state & 32'hcfa5f4bc);
                lfsr_jump_padded[16] = ^(state & 32'h9f4be978);
                lfsr_jump_padded[17] = ^(state & 32'h3e97d2f1);
                lfsr_jump_padded[18] = ^(state & 32'h7d2fa5e3);
                lfsr_jump_padded[19] = ^(state & 32'hfa5f4bc7);
                lfsr_jump_padded[20] = ^(state & 32'hf4be978f);
                lfsr_jump_padded[21] = ^(state & 32'he97d2f1e);
                lfsr_jump_padded[22] = ^(state & 32'hf3c84c84);
                lfsr_jump_padded[23] = ^(state & 32'he7909909);
                lfsr_jump_padded[24] = ^(state & 32'hcf213212);
                lfsr_jump_padded[25] = ^(state & 32'h9e426425);
                lfsr_jump_padded[26] = ^(state & 32'h3c84c84a);
                lfsr_jump_padded[27] = ^(state & 32'h79099095);
                lfsr_jump_padded[28] = ^(state & 32'hf213212b);
                lfsr_jump_padded[29] = ^(state & 32'he4264257);
                lfsr_jump_padded[30] = ^(state & 32'hc84c84ae);
                lfsr_jump_padded[31] = ^(state & 32'h9099095c);
            end
            10'd80: begin
                lfsr_jump_padded[0] = ^(state & 32'h3212b93a);
                lfsr_jump_padded[1] = ^(state & 32'h5637cb4f);
                lfsr_jump_padded[2] = ^(state & 32'h9e7d2fa5);
                lfsr_jump_padded[3] = ^(state & 32'h3cfa5f4b);
                lfsr_jump_padded[4] = ^(state & 32'h79f4be97);
                lfsr_jump_padded[5] = ^(state & 32'hf3e97d2f);
                lfsr_jump_padded[6] = ^(state & 32'he7d2fa5e);
                lfsr_jump_padded[7] = ^(state & 32'hcfa5f4bc);
                lfsr_jump_padded[8] = ^(state & 32'h9f4be978);
                lfsr_jump_padded[9] = ^(state & 32'h3e97d2f1);
                lfsr_jump_padded[10] = ^(state & 32'h7d2fa5e3);
                lfsr_jump_padded[11] = ^(state & 32'hfa5f4bc7);
                lfsr_jump_padded[12] = ^(state & 32'hf4be978f);
                lfsr_jump_padded[13] = ^(state & 32'he97d2f1e);
                lfsr_jump_padded[14] = ^(state & 32'hd2fa5e3d);
                lfsr_jump_padded[15] = ^(state & 32'ha5f4bc7b);
                lfsr_jump_padded[16] = ^(state & 32'h4be978f6);
                lfsr_jump_padded[17] = ^(state & 32'h97d2f1ec);
                lfsr_jump_padded[18] = ^(state & 32'h2fa5e3d9);
                lfsr_jump_padded[19] = ^(state & 32'h5f4bc7b2);
                lfsr_jump_padded[20] = ^(state & 32'hbe978f65);
                lfsr_jump_padded[21] = ^(state & 32'h7d2f1eca);
                lfsr_jump_padded[22] = ^(state & 32'hc84c84ae);
                lfsr_jump_padded[23] = ^(state & 32'h9099095c);
                lfsr_jump_padded[24] = ^(state & 32'h213212b9);
                lfsr_jump_padded[25] = ^(state & 32'h42642572);
                lfsr_jump_padded[26] = ^(state & 32'h84c84ae4);
                lfsr_jump_padded[27] = ^(state & 32'h099095c9);
                lfsr_jump_padded[28] = ^(state & 32'h13212b93);
                lfsr_jump_padded[29] = ^(state & 32'h26425727);
                lfsr_jump_padded[30] = ^(state & 32'h4c84ae4e);
                lfsr_jump_padded[31] = ^(state & 32'h99095c9d);
            end
            10'd88: begin
                lfsr_jump_padded[0] = ^(state & 32'h12b93a96);
                lfsr_jump_padded[1] = ^(state & 32'h37cb4fba);
                lfsr_jump_padded[2] = ^(state & 32'h7d2fa5e3);
                lfsr_jump_padded[3] = ^(state & 32'hfa5f4bc7);
                lfsr_jump_padded[4] = ^(state & 32'hf4be978f);
                lfsr_jump_padded[5] = ^(state & 32'he97d2f1e);
                lfsr_jump_padded[6] = ^(state & 32'hd2fa5e3d);
                lfsr_jump_padded[7] = ^(state & 32'ha5f4bc7b);
                lfsr_jump_padded[8] = ^(state & 32'h4be978f6);
                lfsr_jump_padded[9] = ^(state & 32'h97d2f1ec);
                lfsr_jump_padded[10] = ^(state & 32'h2fa5e3d9);
                lfsr_jump_padded[11] = ^(state & 32'h5f4bc7b2);
                lfsr_jump_padded[12] = ^(state & 32'hbe978f65);
                lfsr_jump_padded[13] = ^(state & 32'h7d2f1eca);
                lfsr_jump_padded[14] = ^(state & 32'hfa5e3d94);
                lfsr_jump_padded[15] = ^(state & 32'hf4bc7b29);
                lfsr_jump_padded[16] = ^(state & 32'he978f653);
                lfsr_jump_padded[17] = ^(state & 32'hd2f1eca6);
                lfsr_jump_padded[18] = ^(state & 32'ha5e3d94d);
                lfsr_jump_padded[19] = ^(state & 32'h4bc7b29b);
                lfsr_jump_padded[20] = ^(state & 32'h978f6536);
                lfsr_jump_padded[21] = ^(state & 32'h2f1eca6c);
                lfsr_jump_padded[22] = ^(state & 32'h4c84ae4e);
                lfsr_jump_padded[23] = ^(state & 32'h99095c9d);
                lfsr_jump_padded[24] = ^(state & 32'h3212b93a);
                lfsr_jump_padded[25] = ^(state & 32'h64257275);
                lfsr_jump_padded[26] = ^(state & 32'hc84ae4ea);
                lfsr_jump_padded[27] = ^(state & 32'h9095c9d4);
                lfsr_jump_padded[28] = ^(state & 32'h212b93a9);
                lfsr_jump_padded[29] = ^(state & 32'h42572752);
                lfsr_jump_padded[30] = ^(state & 32'h84ae4ea5);
                lfsr_jump_padded[31] = ^(state & 32'h095c9d4b);
            end
            10'd96: begin
                lfsr_jump_padded[0] = ^(state & 32'hb93a9645);
                lfsr_jump_padded[1] = ^(state & 32'hcb4fbace);
                lfsr_jump_padded[2] = ^(state & 32'h2fa5e3d9);
                lfsr_jump_padded[3] = ^(state & 32'h5f4bc7b2);
                lfsr_jump_padded[4] = ^(state & 32'hbe978f65);
                lfsr_jump_padded[5] = ^(state & 32'h7d2f1eca);
                lfsr_jump_padded[6] = ^(state & 32'hfa5e3d94);
                lfsr_jump_padded[7] = ^(state & 32'hf4bc7b29);
                lfsr_jump_padded[8] = ^(state & 32'he978f653);
                lfsr_jump_padded[9] = ^(state & 32'hd2f1eca6);
                lfsr_jump_padded[10] = ^(state & 32'ha5e3d94d);
                lfsr_jump_padded[11] = ^(state & 32'h4bc7b29b);
                lfsr_jump_padded[12] = ^(state & 32'h978f6536);
                lfsr_jump_padded[13] = ^(state & 32'h2f1eca6c);
                lfsr_jump_padded[14] = ^(state & 32'h5e3d94d8);
                lfsr_jump_padded[15] = ^(state & 32'hbc7b29b1);
                lfsr_jump_padded[16] = ^(state & 32'h78f65363);
                lfsr_jump_padded[17] = ^(state & 32'hf1eca6c7);
                lfsr_jump_padded[18] = ^(state & 32'he3d94d8e);
                lfsr_jump_padded[19] = ^(state & 32'hc7b29b1c);
                lfsr_jump_padded[20] = ^(state & 32'h8f653638);
                lfsr_jump_padded[21] = ^(state & 32'h1eca6c70);
                lfsr_jump_padded[22] = ^(state & 32'h84ae4ea5);
                lfsr_jump_padded[23] = ^(state & 32'h095c9d4b);
                lfsr_jump_padded[24] = ^(state & 32'h12b93a96);
                lfsr_jump_padded[25] = ^(state & 32'h2572752c);
                lfsr_jump_padded[26] = ^(state & 32'h4ae4ea59);
                lfsr_jump_padded[27] = ^(state & 32'h95c9d4b2);
                lfsr_jump_padded[28] = ^(state & 32'h2b93a964);
                lfsr_jump_padded[29] = ^(state & 32'h572752c8);
                lfsr_jump_padded[30] = ^(state & 32'hae4ea591);
                lfsr_jump_padded[31] = ^(state & 32'h5c9d4b22);
            end
            10'd104: begin
                lfsr_jump_padded[0] = ^(state & 32'h3a9645c2);
                lfsr_jump_padded[1] = ^(state & 32'h4fbace47);
                lfsr_jump_padded[2] = ^(state & 32'ha5e3d94d);
                lfsr_jump_padded[3] = ^(state & 32'h4bc7b29b);
                lfsr_jump_padded[4] = ^(state & 32'h978f6536);
                lfsr_jump_padded[5] = ^(state & 32'h2f1eca6c);
                lfsr_jump_padded[6] = ^(state & 32'h5e3d94d8);
                lfsr_jump_padded[7] = ^(state & 32'hbc7b29b1);
                lfsr_jump_padded[8] = ^(state & 32'h78f65363);
                lfsr_jump_padded[9] = ^(state & 32'hf1eca6c7);
                lfsr_jump_padded[10] = ^(state & 32'he3d94d8e);
                lfsr_jump_padded[11] = ^(state & 32'hc7b29b1c);
                lfsr_jump_padded[12] = ^(state & 32'h8f653638);
                lfsr_jump_padded[13] = ^(state & 32'h1eca6c70);
                lfsr_jump_padded[14] = ^(state & 32'h3d94d8e0);
                lfsr_jump_padded[15] = ^(state & 32'h7b29b1c0);
                lfsr_jump_padded[16] = ^(state & 32'hf6536381);
                lfsr_jump_padded[17] = ^(state & 32'heca6c702);
                lfsr_jump_padded[18] = ^(state & 32'hd94d8e05);
                lfsr_jump_padded[19] = ^(state & 32'hb29b1c0a);
                lfsr_jump_padded[20] = ^(state & 32'h65363814);
                lfsr_jump_padded[21] = ^(state & 32'hca6c7029);
                lfsr_jump_padded[22] = ^(state & 32'hae4ea591);
                lfsr_jump_padded[23] = ^(state & 32'h5c9d4b22);
                lfsr_jump_padded[24] = ^(state & 32'hb93a9645);
                lfsr_jump_padded[25] = ^(state & 32'h72752c8b);
                lfsr_jump_padded[26] = ^(state & 32'he4ea5917);
                lfsr_jump_padded[27] = ^(state & 32'hc9d4b22e);
                lfsr_jump_padded[28] = ^(state & 32'h93a9645c);
                lfsr_jump_padded[29] = ^(state & 32'h2752c8b8);
                lfsr_jump_padded[30] = ^(state & 32'h4ea59170);
                lfsr_jump_padded[31] = ^(state & 32'h9d4b22e1);
            end
            10'd112: begin
                lfsr_jump_padded[0] = ^(state & 32'h9645c282);
                lfsr_jump_padded[1] = ^(state & 32'hbace4786);
                lfsr_jump_padded[2] = ^(state & 32'he3d94d8e);
                lfsr_jump_padded[3] = ^(state & 32'hc7b29b1c);
                lfsr_jump_padded[4] = ^(state & 32'h8f653638);
                lfsr_jump_padded[5] = ^(state & 32'h1eca6c70);
                lfsr_jump_padded[6] = ^(state & 32'h3d94d8e0);
                lfsr_jump_padded[7] = ^(state & 32'h7b29b1c0);
                lfsr_jump_padded[8] = ^(state & 32'hf6536381);
                lfsr_jump_padded[9] = ^(state & 32'heca6c702);
                lfsr_jump_padded[10] = ^(state & 32'hd94d8e05);
                lfsr_jump_padded[11] = ^(state & 32'hb29b1c0a);
                lfsr_jump_padded[12] = ^(state & 32'h65363814);
                lfsr_jump_padded[13] = ^(state & 32'hca6c7029);
                lfsr_jump_padded[14] = ^(state & 32'h94d8e053);
                lfsr_jump_padded[15] = ^(state & 32'h29b1c0a7);
                lfsr_jump_padded[16] = ^(state & 32'h5363814f);
                lfsr_jump_padded[17] = ^(state & 32'ha6c7029f);
                lfsr_jump_padded[18] = ^(state & 32'h4d8e053f);
                lfsr_jump_padded[19] = ^(state & 32'h9b1c0a7e);
                lfsr_jump_padded[20] = ^(state & 32'h363814fc);
                lfsr_jump_padded[21] = ^(state & 32'h6c7029f9);
                lfsr_jump_padded[22] = ^(state & 32'h4ea59170);
                lfsr_jump_padded[23] = ^(state & 32'h9d4b22e1);
                lfsr_jump_padded[24] = ^(state & 32'h3a9645c2);
                lfsr_jump_padded[25] = ^(state & 32'h752c8b85);
                lfsr_jump_padded[26] = ^(state & 32'hea59170a);
                lfsr_jump_padded[27] = ^(state & 32'hd4b22e14);
                lfsr_jump_padded[28] = ^(state & 32'ha9645c28);
                lfsr_jump_padded[29] = ^(state & 32'h52c8b850);
                lfsr_jump_padded[30] = ^(state & 32'ha59170a0);
                lfsr_jump_padded[31] = ^(state & 32'h4b22e141);
            end
            10'd120: begin
                lfsr_jump_padded[0] = ^(state & 32'h45c28201);
                lfsr_jump_padded[1] = ^(state & 32'hce478602);
                lfsr_jump_padded[2] = ^(state & 32'hd94d8e05);
                lfsr_jump_padded[3] = ^(state & 32'hb29b1c0a);
                lfsr_jump_padded[4] = ^(state & 32'h65363814);
                lfsr_jump_padded[5] = ^(state & 32'hca6c7029);
                lfsr_jump_padded[6] = ^(state & 32'h94d8e053);
                lfsr_jump_padded[7] = ^(state & 32'h29b1c0a7);
                lfsr_jump_padded[8] = ^(state & 32'h5363814f);
                lfsr_jump_padded[9] = ^(state & 32'ha6c7029f);
                lfsr_jump_padded[10] = ^(state & 32'h4d8e053f);
                lfsr_jump_padded[11] = ^(state & 32'h9b1c0a7e);
                lfsr_jump_padded[12] = ^(state & 32'h363814fc);
                lfsr_jump_padded[13] = ^(state & 32'h6c7029f9);
                lfsr_jump_padded[14] = ^(state & 32'hd8e053f2);
                lfsr_jump_padded[15] = ^(state & 32'hb1c0a7e5);
                lfsr_jump_padded[16] = ^(state & 32'h63814fca);
                lfsr_jump_padded[17] = ^(state & 32'hc7029f95);
                lfsr_jump_padded[18] = ^(state & 32'h8e053f2a);
                lfsr_jump_padded[19] = ^(state & 32'h1c0a7e54);
                lfsr_jump_padded[20] = ^(state & 32'h3814fca8);
                lfsr_jump_padded[21] = ^(state & 32'h7029f950);
                lfsr_jump_padded[22] = ^(state & 32'ha59170a0);
                lfsr_jump_padded[23] = ^(state & 32'h4b22e141);
                lfsr_jump_padded[24] = ^(state & 32'h9645c282);
                lfsr_jump_padded[25] = ^(state & 32'h2c8b8504);
                lfsr_jump_padded[26] = ^(state & 32'h59170a08);
                lfsr_jump_padded[27] = ^(state & 32'hb22e1410);
                lfsr_jump_padded[28] = ^(state & 32'h645c2820);
                lfsr_jump_padded[29] = ^(state & 32'hc8b85040);
                lfsr_jump_padded[30] = ^(state & 32'h9170a080);
                lfsr_jump_padded[31] = ^(state & 32'h22e14100);
            end
            10'd128: begin
                lfsr_jump_padded[0] = ^(state & 32'hc28201d2);
                lfsr_jump_padded[1] = ^(state & 32'h47860276);
                lfsr_jump_padded[2] = ^(state & 32'h4d8e053f);
                lfsr_jump_padded[3] = ^(state & 32'h9b1c0a7e);
                lfsr_jump_padded[4] = ^(state & 32'h363814fc);
                lfsr_jump_padded[5] = ^(state & 32'h6c7029f9);
                lfsr_jump_padded[6] = ^(state & 32'hd8e053f2);
                lfsr_jump_padded[7] = ^(state & 32'hb1c0a7e5);
                lfsr_jump_padded[8] = ^(state & 32'h63814fca);
                lfsr_jump_padded[9] = ^(state & 32'hc7029f95);
                lfsr_jump_padded[10] = ^(state & 32'h8e053f2a);
                lfsr_jump_padded[11] = ^(state & 32'h1c0a7e54);
                lfsr_jump_padded[12] = ^(state & 32'h3814fca8);
                lfsr_jump_padded[13] = ^(state & 32'h7029f950);
                lfsr_jump_padded[14] = ^(state & 32'he053f2a1);
                lfsr_jump_padded[15] = ^(state & 32'hc0a7e542);
                lfsr_jump_padded[16] = ^(state & 32'h814fca85);
                lfsr_jump_padded[17] = ^(state & 32'h029f950a);
                lfsr_jump_padded[18] = ^(state & 32'h053f2a15);
                lfsr_jump_padded[19] = ^(state & 32'h0a7e542a);
                lfsr_jump_padded[20] = ^(state & 32'h14fca854);
                lfsr_jump_padded[21] = ^(state & 32'h29f950a9);
                lfsr_jump_padded[22] = ^(state & 32'h9170a080);
                lfsr_jump_padded[23] = ^(state & 32'h22e14100);
                lfsr_jump_padded[24] = ^(state & 32'h45c28201);
                lfsr_jump_padded[25] = ^(state & 32'h8b850403);
                lfsr_jump_padded[26] = ^(state & 32'h170a0807);
                lfsr_jump_padded[27] = ^(state & 32'h2e14100e);
                lfsr_jump_padded[28] = ^(state & 32'h5c28201d);
                lfsr_jump_padded[29] = ^(state & 32'hb850403a);
                lfsr_jump_padded[30] = ^(state & 32'h70a08074);
                lfsr_jump_padded[31] = ^(state & 32'he14100e9);
            end
            10'd136: begin
                lfsr_jump_padded[0] = ^(state & 32'h8201d263);
                lfsr_jump_padded[1] = ^(state & 32'h860276a4);
                lfsr_jump_padded[2] = ^(state & 32'h8e053f2a);
                lfsr_jump_padded[3] = ^(state & 32'h1c0a7e54);
                lfsr_jump_padded[4] = ^(state & 32'h3814fca8);
                lfsr_jump_padded[5] = ^(state & 32'h7029f950);
                lfsr_jump_padded[6] = ^(state & 32'he053f2a1);
                lfsr_jump_padded[7] = ^(state & 32'hc0a7e542);
                lfsr_jump_padded[8] = ^(state & 32'h814fca85);
                lfsr_jump_padded[9] = ^(state & 32'h029f950a);
                lfsr_jump_padded[10] = ^(state & 32'h053f2a15);
                lfsr_jump_padded[11] = ^(state & 32'h0a7e542a);
                lfsr_jump_padded[12] = ^(state & 32'h14fca854);
                lfsr_jump_padded[13] = ^(state & 32'h29f950a9);
                lfsr_jump_padded[14] = ^(state & 32'h53f2a152);
                lfsr_jump_padded[15] = ^(state & 32'ha7e542a4);
                lfsr_jump_padded[16] = ^(state & 32'h4fca8548);
                lfsr_jump_padded[17] = ^(state & 32'h9f950a90);
                lfsr_jump_padded[18] = ^(state & 32'h3f2a1521);
                lfsr_jump_padded[19] = ^(state & 32'h7e542a42);
                lfsr_jump_padded[20] = ^(state & 32'hfca85485);
                lfsr_jump_padded[21] = ^(state & 32'hf950a90b);
                lfsr_jump_padded[22] = ^(state & 32'h70a08074);
                lfsr_jump_padded[23] = ^(state & 32'he14100e9);
                lfsr_jump_padded[24] = ^(state & 32'hc28201d2);
                lfsr_jump_padded[25] = ^(state & 32'h850403a4);
                lfsr_jump_padded[26] = ^(state & 32'h0a080749);
                lfsr_jump_padded[27] = ^(state & 32'h14100e93);
                lfsr_jump_padded[28] = ^(state & 32'h28201d26);
                lfsr_jump_padded[29] = ^(state & 32'h50403a4c);
                lfsr_jump_padded[30] = ^(state & 32'ha0807498);
                lfsr_jump_padded[31] = ^(state & 32'h4100e931);
            end
            10'd144: begin
                lfsr_jump_padded[0] = ^(state & 32'h01d263b1);
                lfsr_jump_padded[1] = ^(state & 32'h0276a4d2);
                lfsr_jump_padded[2] = ^(state & 32'h053f2a15);
                lfsr_jump_padded[3] = ^(state & 32'h0a7e542a);
                lfsr_jump_padded[4] = ^(state & 32'h14fca854);
                lfsr_jump_padded[5] = ^(state & 32'h29f950a9);
                lfsr_jump_padded[6] = ^(state & 32'h53f2a152);
                lfsr_jump_padded[7] = ^(state & 32'ha7e542a4);
                lfsr_jump_padded[8] = ^(state & 32'h4fca8548);
                lfsr_jump_padded[9] = ^(state & 32'h9f950a90);
                lfsr_jump_padded[10] = ^(state & 32'h3f2a1521);
                lfsr_jump_padded[11] = ^(state & 32'h7e542a42);
                lfsr_jump_padded[12] = ^(state & 32'hfca85485);
                lfsr_jump_padded[13] = ^(state & 32'hf950a90b);
                lfsr_jump_padded[14] = ^(state & 32'hf2a15217);
                lfsr_jump_padded[15] = ^(state & 32'he542a42e);
                lfsr_jump_padded[16] = ^(state & 32'hca85485c);
                lfsr_jump_padded[17] = ^(state & 32'h950a90b9);
                lfsr_jump_padded[18] = ^(state & 32'h2a152172);
                lfsr_jump_padded[19] = ^(state & 32'h542a42e5);
                lfsr_jump_padded[20] = ^(state & 32'ha85485ca);
                lfsr_jump_padded[21] = ^(state & 32'h50a90b94);
                lfsr_jump_padded[22] = ^(state & 32'ha0807498);
                lfsr_jump_padded[23] = ^(state & 32'h4100e931);
                lfsr_jump_padded[24] = ^(state & 32'h8201d263);
                lfsr_jump_padded[25] = ^(state & 32'h0403a4c7);
                lfsr_jump_padded[26] = ^(state & 32'h0807498e);
                lfsr_jump_padded[27] = ^(state & 32'h100e931d);
                lfsr_jump_padded[28] = ^(state & 32'h201d263b);
                lfsr_jump_padded[29] = ^(state & 32'h403a4c76);
                lfsr_jump_padded[30] = ^(state & 32'h807498ec);
                lfsr_jump_padded[31] = ^(state & 32'h00e931d8);
            end
            10'd152: begin
                lfsr_jump_padded[0] = ^(state & 32'hd263b1d6);
                lfsr_jump_padded[1] = ^(state & 32'h76a4d27b);
                lfsr_jump_padded[2] = ^(state & 32'h3f2a1521);
                lfsr_jump_padded[3] = ^(state & 32'h7e542a42);
                lfsr_jump_padded[4] = ^(state & 32'hfca85485);
                lfsr_jump_padded[5] = ^(state & 32'hf950a90b);
                lfsr_jump_padded[6] = ^(state & 32'hf2a15217);
                lfsr_jump_padded[7] = ^(state & 32'he542a42e);
                lfsr_jump_padded[8] = ^(state & 32'hca85485c);
                lfsr_jump_padded[9] = ^(state & 32'h950a90b9);
                lfsr_jump_padded[10] = ^(state & 32'h2a152172);
                lfsr_jump_padded[11] = ^(state & 32'h542a42e5);
                lfsr_jump_padded[12] = ^(state & 32'ha85485ca);
                lfsr_jump_padded[13] = ^(state & 32'h50a90b94);
                lfsr_jump_padded[14] = ^(state & 32'ha1521729);
                lfsr_jump_padded[15] = ^(state & 32'h42a42e52);
                lfsr_jump_padded[16] = ^(state & 32'h85485ca4);
                lfsr_jump_padded[17] = ^(state & 32'h0a90b949);
                lfsr_jump_padded[18] = ^(state & 32'h15217293);
                lfsr_jump_padded[19] = ^(state & 32'h2a42e527);
                lfsr_jump_padded[20] = ^(state & 32'h5485ca4e);
                lfsr_jump_padded[21] = ^(state & 32'ha90b949d);
                lfsr_jump_padded[22] = ^(state & 32'h807498ec);
                lfsr_jump_padded[23] = ^(state & 32'h00e931d8);
                lfsr_jump_padded[24] = ^(state & 32'h01d263b1);
                lfsr_jump_padded[25] = ^(state & 32'h03a4c763);
                lfsr_jump_padded[26] = ^(state & 32'h07498ec7);
                lfsr_jump_padded[27] = ^(state & 32'h0e931d8e);
                lfsr_jump_padded[28] = ^(state & 32'h1d263b1d);
                lfsr_jump_padded[29] = ^(state & 32'h3a4c763a);
                lfsr_jump_padded[30] = ^(state & 32'h7498ec75);
                lfsr_jump_padded[31] = ^(state & 32'he931d8eb);
            end
            10'd160: begin
                lfsr_jump_padded[0] = ^(state & 32'h63b1d6a6);
                lfsr_jump_padded[1] = ^(state & 32'ha4d27bea);
                lfsr_jump_padded[2] = ^(state & 32'h2a152172);
                lfsr_jump_padded[3] = ^(state & 32'h542a42e5);
                lfsr_jump_padded[4] = ^(state & 32'ha85485ca);
                lfsr_jump_padded[5] = ^(state & 32'h50a90b94);
                lfsr_jump_padded[6] = ^(state & 32'ha1521729);
                lfsr_jump_padded[7] = ^(state & 32'h42a42e52);
                lfsr_jump_padded[8] = ^(state & 32'h85485ca4);
                lfsr_jump_padded[9] = ^(state & 32'h0a90b949);
                lfsr_jump_padded[10] = ^(state & 32'h15217293);
                lfsr_jump_padded[11] = ^(state & 32'h2a42e527);
                lfsr_jump_padded[12] = ^(state & 32'h5485ca4e);
                lfsr_jump_padded[13] = ^(state & 32'ha90b949d);
                lfsr_jump_padded[14] = ^(state & 32'h5217293a);
                lfsr_jump_padded[15] = ^(state & 32'ha42e5275);
                lfsr_jump_padded[16] = ^(state & 32'h485ca4eb);
                lfsr_jump_padded[17] = ^(state & 32'h90b949d6);
                lfsr_jump_padded[18] = ^(state & 32'h217293ad);
                lfsr_jump_padded[19] = ^(state & 32'h42e5275a);
                lfsr_jump_padded[20] = ^(state & 32'h85ca4eb4);
                lfsr_jump_padded[21] = ^(state & 32'h0b949d69);
                lfsr_jump_padded[22] = ^(state & 32'h7498ec75);
                lfsr_jump_padded[23] = ^(state & 32'he931d8eb);
                lfsr_jump_padded[24] = ^(state & 32'hd263b1d6);
                lfsr_jump_padded[25] = ^(state & 32'ha4c763ad);
                lfsr_jump_padded[26] = ^(state & 32'h498ec75a);
                lfsr_jump_padded[27] = ^(state & 32'h931d8eb5);
                lfsr_jump_padded[28] = ^(state & 32'h263b1d6a);
                lfsr_jump_padded[29] = ^(state & 32'h4c763ad4);
                lfsr_jump_padded[30] = ^(state & 32'h98ec75a9);
                lfsr_jump_padded[31] = ^(state & 32'h31d8eb53);
            end
            10'd168: begin
                lfsr_jump_padded[0] = ^(state & 32'hb1d6a630);
                lfsr_jump_padded[1] = ^(state & 32'hd27bea51);
                lfsr_jump_padded[2] = ^(state & 32'h15217293);
                lfsr_jump_padded[3] = ^(state & 32'h2a42e527);
                lfsr_jump_padded[4] = ^(state & 32'h5485ca4e);
                lfsr_jump_padded[5] = ^(state & 32'ha90b949d);
                lfsr_jump_padded[6] = ^(state & 32'h5217293a);
                lfsr_jump_padded[7] = ^(state & 32'ha42e5275);
                lfsr_jump_padded[8] = ^(state & 32'h485ca4eb);
                lfsr_jump_padded[9] = ^(state & 32'h90b949d6);
                lfsr_jump_padded[10] = ^(state & 32'h217293ad);
                lfsr_jump_padded[11] = ^(state & 32'h42e5275a);
                lfsr_jump_padded[12] = ^(state & 32'h85ca4eb4);
                lfsr_jump_padded[13] = ^(state & 32'h0b949d69);
                lfsr_jump_padded[14] = ^(state & 32'h17293ad3);
                lfsr_jump_padded[15] = ^(state & 32'h2e5275a7);
                lfsr_jump_padded[16] = ^(state & 32'h5ca4eb4e);
                lfsr_jump_padded[17] = ^(state & 32'hb949d69c);
                lfsr_jump_padded[18] = ^(state & 32'h7293ad39);
                lfsr_jump_padded[19] = ^(state & 32'he5275a73);
                lfsr_jump_padded[20] = ^(state & 32'hca4eb4e6);
                lfsr_jump_padded[21] = ^(state & 32'h949d69cc);
                lfsr_jump_padded[22] = ^(state & 32'h98ec75a9);
                lfsr_jump_padded[23] = ^(state & 32'h31d8eb53);
                lfsr_jump_padded[24] = ^(state & 32'h63b1d6a6);
                lfsr_jump_padded[25] = ^(state & 32'hc763ad4c);
                lfsr_jump_padded[26] = ^(state & 32'h8ec75a98);
                lfsr_jump_padded[27] = ^(state & 32'h1d8eb531);
                lfsr_jump_padded[28] = ^(state & 32'h3b1d6a63);
                lfsr_jump_padded[29] = ^(state & 32'h763ad4c6);
                lfsr_jump_padded[30] = ^(state & 32'hec75a98c);
                lfsr_jump_padded[31] = ^(state & 32'hd8eb5318);
            end
            10'd176: begin
                lfsr_jump_padded[0] = ^(state & 32'hd6a6308f);
                lfsr_jump_padded[1] = ^(state & 32'h7bea5191);
                lfsr_jump_padded[2] = ^(state & 32'h217293ad);
                lfsr_jump_padded[3] = ^(state & 32'h42e5275a);
                lfsr_jump_padded[4] = ^(state & 32'h85ca4eb4);
                lfsr_jump_padded[5] = ^(state & 32'h0b949d69);
                lfsr_jump_padded[6] = ^(state & 32'h17293ad3);
                lfsr_jump_padded[7] = ^(state & 32'h2e5275a7);
                lfsr_jump_padded[8] = ^(state & 32'h5ca4eb4e);
                lfsr_jump_padded[9] = ^(state & 32'hb949d69c);
                lfsr_jump_padded[10] = ^(state & 32'h7293ad39);
                lfsr_jump_padded[11] = ^(state & 32'he5275a73);
                lfsr_jump_padded[12] = ^(state & 32'hca4eb4e6);
                lfsr_jump_padded[13] = ^(state & 32'h949d69cc);
                lfsr_jump_padded[14] = ^(state & 32'h293ad399);
                lfsr_jump_padded[15] = ^(state & 32'h5275a732);
                lfsr_jump_padded[16] = ^(state & 32'ha4eb4e64);
                lfsr_jump_padded[17] = ^(state & 32'h49d69cc8);
                lfsr_jump_padded[18] = ^(state & 32'h93ad3990);
                lfsr_jump_padded[19] = ^(state & 32'h275a7320);
                lfsr_jump_padded[20] = ^(state & 32'h4eb4e640);
                lfsr_jump_padded[21] = ^(state & 32'h9d69cc81);
                lfsr_jump_padded[22] = ^(state & 32'hec75a98c);
                lfsr_jump_padded[23] = ^(state & 32'hd8eb5318);
                lfsr_jump_padded[24] = ^(state & 32'hb1d6a630);
                lfsr_jump_padded[25] = ^(state & 32'h63ad4c61);
                lfsr_jump_padded[26] = ^(state & 32'hc75a98c2);
                lfsr_jump_padded[27] = ^(state & 32'h8eb53184);
                lfsr_jump_padded[28] = ^(state & 32'h1d6a6308);
                lfsr_jump_padded[29] = ^(state & 32'h3ad4c611);
                lfsr_jump_padded[30] = ^(state & 32'h75a98c23);
                lfsr_jump_padded[31] = ^(state & 32'heb531847);
            end
            10'd184: begin
                lfsr_jump_padded[0] = ^(state & 32'ha6308f08);
                lfsr_jump_padded[1] = ^(state & 32'hea519118);
                lfsr_jump_padded[2] = ^(state & 32'h7293ad39);
                lfsr_jump_padded[3] = ^(state & 32'he5275a73);
                lfsr_jump_padded[4] = ^(state & 32'hca4eb4e6);
                lfsr_jump_padded[5] = ^(state & 32'h949d69cc);
                lfsr_jump_padded[6] = ^(state & 32'h293ad399);
                lfsr_jump_padded[7] = ^(state & 32'h5275a732);
                lfsr_jump_padded[8] = ^(state & 32'ha4eb4e64);
                lfsr_jump_padded[9] = ^(state & 32'h49d69cc8);
                lfsr_jump_padded[10] = ^(state & 32'h93ad3990);
                lfsr_jump_padded[11] = ^(state & 32'h275a7320);
                lfsr_jump_padded[12] = ^(state & 32'h4eb4e640);
                lfsr_jump_padded[13] = ^(state & 32'h9d69cc81);
                lfsr_jump_padded[14] = ^(state & 32'h3ad39903);
                lfsr_jump_padded[15] = ^(state & 32'h75a73206);
                lfsr_jump_padded[16] = ^(state & 32'heb4e640c);
                lfsr_jump_padded[17] = ^(state & 32'hd69cc819);
                lfsr_jump_padded[18] = ^(state & 32'had399032);
                lfsr_jump_padded[19] = ^(state & 32'h5a732065);
                lfsr_jump_padded[20] = ^(state & 32'hb4e640ca);
                lfsr_jump_padded[21] = ^(state & 32'h69cc8195);
                lfsr_jump_padded[22] = ^(state & 32'h75a98c23);
                lfsr_jump_padded[23] = ^(state & 32'heb531847);
                lfsr_jump_padded[24] = ^(state & 32'hd6a6308f);
                lfsr_jump_padded[25] = ^(state & 32'had4c611e);
                lfsr_jump_padded[26] = ^(state & 32'h5a98c23c);
                lfsr_jump_padded[27] = ^(state & 32'hb5318478);
                lfsr_jump_padded[28] = ^(state & 32'h6a6308f0);
                lfsr_jump_padded[29] = ^(state & 32'hd4c611e1);
                lfsr_jump_padded[30] = ^(state & 32'ha98c23c2);
                lfsr_jump_padded[31] = ^(state & 32'h53184784);
            end
            10'd192: begin
                lfsr_jump_padded[0] = ^(state & 32'h308f085d);
                lfsr_jump_padded[1] = ^(state & 32'h519118e6);
                lfsr_jump_padded[2] = ^(state & 32'h93ad3990);
                lfsr_jump_padded[3] = ^(state & 32'h275a7320);
                lfsr_jump_padded[4] = ^(state & 32'h4eb4e640);
                lfsr_jump_padded[5] = ^(state & 32'h9d69cc81);
                lfsr_jump_padded[6] = ^(state & 32'h3ad39903);
                lfsr_jump_padded[7] = ^(state & 32'h75a73206);
                lfsr_jump_padded[8] = ^(state & 32'heb4e640c);
                lfsr_jump_padded[9] = ^(state & 32'hd69cc819);
                lfsr_jump_padded[10] = ^(state & 32'had399032);
                lfsr_jump_padded[11] = ^(state & 32'h5a732065);
                lfsr_jump_padded[12] = ^(state & 32'hb4e640ca);
                lfsr_jump_padded[13] = ^(state & 32'h69cc8195);
                lfsr_jump_padded[14] = ^(state & 32'hd399032b);
                lfsr_jump_padded[15] = ^(state & 32'ha7320657);
                lfsr_jump_padded[16] = ^(state & 32'h4e640cae);
                lfsr_jump_padded[17] = ^(state & 32'h9cc8195c);
                lfsr_jump_padded[18] = ^(state & 32'h399032b9);
                lfsr_jump_padded[19] = ^(state & 32'h73206573);
                lfsr_jump_padded[20] = ^(state & 32'he640cae7);
                lfsr_jump_padded[21] = ^(state & 32'hcc8195cf);
                lfsr_jump_padded[22] = ^(state & 32'ha98c23c2);
                lfsr_jump_padded[23] = ^(state & 32'h53184784);
                lfsr_jump_padded[24] = ^(state & 32'ha6308f08);
                lfsr_jump_padded[25] = ^(state & 32'h4c611e10);
                lfsr_jump_padded[26] = ^(state & 32'h98c23c21);
                lfsr_jump_padded[27] = ^(state & 32'h31847842);
                lfsr_jump_padded[28] = ^(state & 32'h6308f085);
                lfsr_jump_padded[29] = ^(state & 32'hc611e10b);
                lfsr_jump_padded[30] = ^(state & 32'h8c23c217);
                lfsr_jump_padded[31] = ^(state & 32'h1847842e);
            end
            10'd200: begin
                lfsr_jump_padded[0] = ^(state & 32'h8f085dbd);
                lfsr_jump_padded[1] = ^(state & 32'h9118e6c7);
                lfsr_jump_padded[2] = ^(state & 32'had399032);
                lfsr_jump_padded[3] = ^(state & 32'h5a732065);
                lfsr_jump_padded[4] = ^(state & 32'hb4e640ca);
                lfsr_jump_padded[5] = ^(state & 32'h69cc8195);
                lfsr_jump_padded[6] = ^(state & 32'hd399032b);
                lfsr_jump_padded[7] = ^(state & 32'ha7320657);
                lfsr_jump_padded[8] = ^(state & 32'h4e640cae);
                lfsr_jump_padded[9] = ^(state & 32'h9cc8195c);
                lfsr_jump_padded[10] = ^(state & 32'h399032b9);
                lfsr_jump_padded[11] = ^(state & 32'h73206573);
                lfsr_jump_padded[12] = ^(state & 32'he640cae7);
                lfsr_jump_padded[13] = ^(state & 32'hcc8195cf);
                lfsr_jump_padded[14] = ^(state & 32'h99032b9f);
                lfsr_jump_padded[15] = ^(state & 32'h3206573f);
                lfsr_jump_padded[16] = ^(state & 32'h640cae7e);
                lfsr_jump_padded[17] = ^(state & 32'hc8195cfd);
                lfsr_jump_padded[18] = ^(state & 32'h9032b9fa);
                lfsr_jump_padded[19] = ^(state & 32'h206573f5);
                lfsr_jump_padded[20] = ^(state & 32'h40cae7ea);
                lfsr_jump_padded[21] = ^(state & 32'h8195cfd5);
                lfsr_jump_padded[22] = ^(state & 32'h8c23c217);
                lfsr_jump_padded[23] = ^(state & 32'h1847842e);
                lfsr_jump_padded[24] = ^(state & 32'h308f085d);
                lfsr_jump_padded[25] = ^(state & 32'h611e10bb);
                lfsr_jump_padded[26] = ^(state & 32'hc23c2176);
                lfsr_jump_padded[27] = ^(state & 32'h847842ed);
                lfsr_jump_padded[28] = ^(state & 32'h08f085db);
                lfsr_jump_padded[29] = ^(state & 32'h11e10bb7);
                lfsr_jump_padded[30] = ^(state & 32'h23c2176f);
                lfsr_jump_padded[31] = ^(state & 32'h47842ede);
            end
            10'd208: begin
                lfsr_jump_padded[0] = ^(state & 32'h085dbd53);
                lfsr_jump_padded[1] = ^(state & 32'h18e6c7f5);
                lfsr_jump_padded[2] = ^(state & 32'h399032b9);
                lfsr_jump_padded[3] = ^(state & 32'h73206573);
                lfsr_jump_padded[4] = ^(state & 32'he640cae7);
                lfsr_jump_padded[5] = ^(state & 32'hcc8195cf);
                lfsr_jump_padded[6] = ^(state & 32'h99032b9f);
                lfsr_jump_padded[7] = ^(state & 32'h3206573f);
                lfsr_jump_padded[8] = ^(state & 32'h640cae7e);
                lfsr_jump_padded[9] = ^(state & 32'hc8195cfd);
                lfsr_jump_padded[10] = ^(state & 32'h9032b9fa);
                lfsr_jump_padded[11] = ^(state & 32'h206573f5);
                lfsr_jump_padded[12] = ^(state & 32'h40cae7ea);
                lfsr_jump_padded[13] = ^(state & 32'h8195cfd5);
                lfsr_jump_padded[14] = ^(state & 32'h032b9faa);
                lfsr_jump_padded[15] = ^(state & 32'h06573f54);
                lfsr_jump_padded[16] = ^(state & 32'h0cae7ea8);
                lfsr_jump_padded[17] = ^(state & 32'h195cfd51);
                lfsr_jump_padded[18] = ^(state & 32'h32b9faa3);
                lfsr_jump_padded[19] = ^(state & 32'h6573f547);
                lfsr_jump_padded[20] = ^(state & 32'hcae7ea8f);
                lfsr_jump_padded[21] = ^(state & 32'h95cfd51e);
                lfsr_jump_padded[22] = ^(state & 32'h23c2176f);
                lfsr_jump_padded[23] = ^(state & 32'h47842ede);
                lfsr_jump_padded[24] = ^(state & 32'h8f085dbd);
                lfsr_jump_padded[25] = ^(state & 32'h1e10bb7a);
                lfsr_jump_padded[26] = ^(state & 32'h3c2176f5);
                lfsr_jump_padded[27] = ^(state & 32'h7842edea);
                lfsr_jump_padded[28] = ^(state & 32'hf085dbd5);
                lfsr_jump_padded[29] = ^(state & 32'he10bb7aa);
                lfsr_jump_padded[30] = ^(state & 32'hc2176f54);
                lfsr_jump_padded[31] = ^(state & 32'h842edea9);
            end
            10'd216: begin
                lfsr_jump_padded[0] = ^(state & 32'h5dbd5325);
                lfsr_jump_padded[1] = ^(state & 32'he6c7f56f);
                lfsr_jump_padded[2] = ^(state & 32'h9032b9fa);
                lfsr_jump_padded[3] = ^(state & 32'h206573f5);
                lfsr_jump_padded[4] = ^(state & 32'h40cae7ea);
                lfsr_jump_padded[5] = ^(state & 32'h8195cfd5);
                lfsr_jump_padded[6] = ^(state & 32'h032b9faa);
                lfsr_jump_padded[7] = ^(state & 32'h06573f54);
                lfsr_jump_padded[8] = ^(state & 32'h0cae7ea8);
                lfsr_jump_padded[9] = ^(state & 32'h195cfd51);
                lfsr_jump_padded[10] = ^(state & 32'h32b9faa3);
                lfsr_jump_padded[11] = ^(state & 32'h6573f547);
                lfsr_jump_padded[12] = ^(state & 32'hcae7ea8f);
                lfsr_jump_padded[13] = ^(state & 32'h95cfd51e);
                lfsr_jump_padded[14] = ^(state & 32'h2b9faa3c);
                lfsr_jump_padded[15] = ^(state & 32'h573f5478);
                lfsr_jump_padded[16] = ^(state & 32'hae7ea8f1);
                lfsr_jump_padded[17] = ^(state & 32'h5cfd51e3);
                lfsr_jump_padded[18] = ^(state & 32'hb9faa3c7);
                lfsr_jump_padded[19] = ^(state & 32'h73f5478e);
                lfsr_jump_padded[20] = ^(state & 32'he7ea8f1c);
                lfsr_jump_padded[21] = ^(state & 32'hcfd51e38);
                lfsr_jump_padded[22] = ^(state & 32'hc2176f54);
                lfsr_jump_padded[23] = ^(state & 32'h842edea9);
                lfsr_jump_padded[24] = ^(state & 32'h085dbd53);
                lfsr_jump_padded[25] = ^(state & 32'h10bb7aa6);
                lfsr_jump_padded[26] = ^(state & 32'h2176f54c);
                lfsr_jump_padded[27] = ^(state & 32'h42edea99);
                lfsr_jump_padded[28] = ^(state & 32'h85dbd532);
                lfsr_jump_padded[29] = ^(state & 32'h0bb7aa64);
                lfsr_jump_padded[30] = ^(state & 32'h176f54c9);
                lfsr_jump_padded[31] = ^(state & 32'h2edea992);
            end
            10'd224: begin
                lfsr_jump_padded[0] = ^(state & 32'hbd532556);
                lfsr_jump_padded[1] = ^(state & 32'hc7f56ffa);
                lfsr_jump_padded[2] = ^(state & 32'h32b9faa3);
                lfsr_jump_padded[3] = ^(state & 32'h6573f547);
                lfsr_jump_padded[4] = ^(state & 32'hcae7ea8f);
                lfsr_jump_padded[5] = ^(state & 32'h95cfd51e);
                lfsr_jump_padded[6] = ^(state & 32'h2b9faa3c);
                lfsr_jump_padded[7] = ^(state & 32'h573f5478);
                lfsr_jump_padded[8] = ^(state & 32'hae7ea8f1);
                lfsr_jump_padded[9] = ^(state & 32'h5cfd51e3);
                lfsr_jump_padded[10] = ^(state & 32'hb9faa3c7);
                lfsr_jump_padded[11] = ^(state & 32'h73f5478e);
                lfsr_jump_padded[12] = ^(state & 32'he7ea8f1c);
                lfsr_jump_padded[13] = ^(state & 32'hcfd51e38);
                lfsr_jump_padded[14] = ^(state & 32'h9faa3c71);
                lfsr_jump_padded[15] = ^(state & 32'h3f5478e3);
                lfsr_jump_padded[16] = ^(state & 32'h7ea8f1c6);
                lfsr_jump_padded[17] = ^(state & 32'hfd51e38c);
                lfsr_jump_padded[18] = ^(state & 32'hfaa3c719);
                lfsr_jump_padded[19] = ^(state & 32'hf5478e33);
                lfsr_jump_padded[20] = ^(state & 32'hea8f1c67);
                lfsr_jump_padded[21] = ^(state & 32'hd51e38cf);
                lfsr_jump_padded[22] = ^(state & 32'h176f54c9);
                lfsr_jump_padded[23] = ^(state & 32'h2edea992);
                lfsr_jump_padded[24] = ^(state & 32'h5dbd5325);
                lfsr_jump_padded[25] = ^(state & 32'hbb7aa64a);
                lfsr_jump_padded[26] = ^(state & 32'h76f54c95);
                lfsr_jump_padded[27] = ^(state & 32'hedea992a);
                lfsr_jump_padded[28] = ^(state & 32'hdbd53255);
                lfsr_jump_padded[29] = ^(state & 32'hb7aa64aa);
                lfsr_jump_padded[30] = ^(state & 32'h6f54c955);
                lfsr_jump_padded[31] = ^(state & 32'hdea992ab);
            end
            10'd232: begin
                lfsr_jump_padded[0] = ^(state & 32'h53255641);
                lfsr_jump_padded[1] = ^(state & 32'hf56ffac3);
                lfsr_jump_padded[2] = ^(state & 32'hb9faa3c7);
                lfsr_jump_padded[3] = ^(state & 32'h73f5478e);
                lfsr_jump_padded[4] = ^(state & 32'he7ea8f1c);
                lfsr_jump_padded[5] = ^(state & 32'hcfd51e38);
                lfsr_jump_padded[6] = ^(state & 32'h9faa3c71);
                lfsr_jump_padded[7] = ^(state & 32'h3f5478e3);
                lfsr_jump_padded[8] = ^(state & 32'h7ea8f1c6);
                lfsr_jump_padded[9] = ^(state & 32'hfd51e38c);
                lfsr_jump_padded[10] = ^(state & 32'hfaa3c719);
                lfsr_jump_padded[11] = ^(state & 32'hf5478e33);
                lfsr_jump_padded[12] = ^(state & 32'hea8f1c67);
                lfsr_jump_padded[13] = ^(state & 32'hd51e38cf);
                lfsr_jump_padded[14] = ^(state & 32'haa3c719f);
                lfsr_jump_padded[15] = ^(state & 32'h5478e33e);
                lfsr_jump_padded[16] = ^(state & 32'ha8f1c67c);
                lfsr_jump_padded[17] = ^(state & 32'h51e38cf8);
                lfsr_jump_padded[18] = ^(state & 32'ha3c719f1);
                lfsr_jump_padded[19] = ^(state & 32'h478e33e2);
                lfsr_jump_padded[20] = ^(state & 32'h8f1c67c5);
                lfsr_jump_padded[21] = ^(state & 32'h1e38cf8a);
                lfsr_jump_padded[22] = ^(state & 32'h6f54c955);
                lfsr_jump_padded[23] = ^(state & 32'hdea992ab);
                lfsr_jump_padded[24] = ^(state & 32'hbd532556);
                lfsr_jump_padded[25] = ^(state & 32'h7aa64aac);
                lfsr_jump_padded[26] = ^(state & 32'hf54c9559);
                lfsr_jump_padded[27] = ^(state & 32'hea992ab2);
                lfsr_jump_padded[28] = ^(state & 32'hd5325564);
                lfsr_jump_padded[29] = ^(state & 32'haa64aac8);
                lfsr_jump_padded[30] = ^(state & 32'h54c95590);
                lfsr_jump_padded[31] = ^(state & 32'ha992ab20);
            end
            10'd240: begin
                lfsr_jump_padded[0] = ^(state & 32'h25564105);
                lfsr_jump_padded[1] = ^(state & 32'h6ffac30e);
                lfsr_jump_padded[2] = ^(state & 32'hfaa3c719);
                lfsr_jump_padded[3] = ^(state & 32'hf5478e33);
                lfsr_jump_padded[4] = ^(state & 32'hea8f1c67);
                lfsr_jump_padded[5] = ^(state & 32'hd51e38cf);
                lfsr_jump_padded[6] = ^(state & 32'haa3c719f);
                lfsr_jump_padded[7] = ^(state & 32'h5478e33e);
                lfsr_jump_padded[8] = ^(state & 32'ha8f1c67c);
                lfsr_jump_padded[9] = ^(state & 32'h51e38cf8);
                lfsr_jump_padded[10] = ^(state & 32'ha3c719f1);
                lfsr_jump_padded[11] = ^(state & 32'h478e33e2);
                lfsr_jump_padded[12] = ^(state & 32'h8f1c67c5);
                lfsr_jump_padded[13] = ^(state & 32'h1e38cf8a);
                lfsr_jump_padded[14] = ^(state & 32'h3c719f14);
                lfsr_jump_padded[15] = ^(state & 32'h78e33e29);
                lfsr_jump_padded[16] = ^(state & 32'hf1c67c52);
                lfsr_jump_padded[17] = ^(state & 32'he38cf8a4);
                lfsr_jump_padded[18] = ^(state & 32'hc719f149);
                lfsr_jump_padded[19] = ^(state & 32'h8e33e292);
                lfsr_jump_padded[20] = ^(state & 32'h1c67c525);
                lfsr_jump_padded[21] = ^(state & 32'h38cf8a4a);
                lfsr_jump_padded[22] = ^(state & 32'h54c95590);
                lfsr_jump_padded[23] = ^(state & 32'ha992ab20);
                lfsr_jump_padded[24] = ^(state & 32'h53255641);
                lfsr_jump_padded[25] = ^(state & 32'ha64aac82);
                lfsr_jump_padded[26] = ^(state & 32'h4c955904);
                lfsr_jump_padded[27] = ^(state & 32'h992ab208);
                lfsr_jump_padded[28] = ^(state & 32'h32556410);
                lfsr_jump_padded[29] = ^(state & 32'h64aac820);
                lfsr_jump_padded[30] = ^(state & 32'hc9559041);
                lfsr_jump_padded[31] = ^(state & 32'h92ab2082);
            end
            10'd248: begin
                lfsr_jump_padded[0] = ^(state & 32'h564105fd);
                lfsr_jump_padded[1] = ^(state & 32'hfac30e06);
                lfsr_jump_padded[2] = ^(state & 32'ha3c719f1);
                lfsr_jump_padded[3] = ^(state & 32'h478e33e2);
                lfsr_jump_padded[4] = ^(state & 32'h8f1c67c5);
                lfsr_jump_padded[5] = ^(state & 32'h1e38cf8a);
                lfsr_jump_padded[6] = ^(state & 32'h3c719f14);
                lfsr_jump_padded[7] = ^(state & 32'h78e33e29);
                lfsr_jump_padded[8] = ^(state & 32'hf1c67c52);
                lfsr_jump_padded[9] = ^(state & 32'he38cf8a4);
                lfsr_jump_padded[10] = ^(state & 32'hc719f149);
                lfsr_jump_padded[11] = ^(state & 32'h8e33e292);
                lfsr_jump_padded[12] = ^(state & 32'h1c67c525);
                lfsr_jump_padded[13] = ^(state & 32'h38cf8a4a);
                lfsr_jump_padded[14] = ^(state & 32'h719f1495);
                lfsr_jump_padded[15] = ^(state & 32'he33e292b);
                lfsr_jump_padded[16] = ^(state & 32'hc67c5256);
                lfsr_jump_padded[17] = ^(state & 32'h8cf8a4ad);
                lfsr_jump_padded[18] = ^(state & 32'h19f1495b);
                lfsr_jump_padded[19] = ^(state & 32'h33e292b7);
                lfsr_jump_padded[20] = ^(state & 32'h67c5256f);
                lfsr_jump_padded[21] = ^(state & 32'hcf8a4ade);
                lfsr_jump_padded[22] = ^(state & 32'hc9559041);
                lfsr_jump_padded[23] = ^(state & 32'h92ab2082);
                lfsr_jump_padded[24] = ^(state & 32'h25564105);
                lfsr_jump_padded[25] = ^(state & 32'h4aac820b);
                lfsr_jump_padded[26] = ^(state & 32'h95590417);
                lfsr_jump_padded[27] = ^(state & 32'h2ab2082f);
                lfsr_jump_padded[28] = ^(state & 32'h5564105f);
                lfsr_jump_padded[29] = ^(state & 32'haac820bf);
                lfsr_jump_padded[30] = ^(state & 32'h5590417f);
                lfsr_jump_padded[31] = ^(state & 32'hab2082fe);
            end
            10'd256: begin
                lfsr_jump_padded[0] = ^(state & 32'h4105fdc3);
                lfsr_jump_padded[1] = ^(state & 32'hc30e0645);
                lfsr_jump_padded[2] = ^(state & 32'hc719f149);
                lfsr_jump_padded[3] = ^(state & 32'h8e33e292);
                lfsr_jump_padded[4] = ^(state & 32'h1c67c525);
                lfsr_jump_padded[5] = ^(state & 32'h38cf8a4a);
                lfsr_jump_padded[6] = ^(state & 32'h719f1495);
                lfsr_jump_padded[7] = ^(state & 32'he33e292b);
                lfsr_jump_padded[8] = ^(state & 32'hc67c5256);
                lfsr_jump_padded[9] = ^(state & 32'h8cf8a4ad);
                lfsr_jump_padded[10] = ^(state & 32'h19f1495b);
                lfsr_jump_padded[11] = ^(state & 32'h33e292b7);
                lfsr_jump_padded[12] = ^(state & 32'h67c5256f);
                lfsr_jump_padded[13] = ^(state & 32'hcf8a4ade);
                lfsr_jump_padded[14] = ^(state & 32'h9f1495bc);
                lfsr_jump_padded[15] = ^(state & 32'h3e292b79);
                lfsr_jump_padded[16] = ^(state & 32'h7c5256f2);
                lfsr_jump_padded[17] = ^(state & 32'hf8a4ade5);
                lfsr_jump_padded[18] = ^(state & 32'hf1495bcb);
                lfsr_jump_padded[19] = ^(state & 32'he292b797);
                lfsr_jump_padded[20] = ^(state & 32'hc5256f2f);
                lfsr_jump_padded[21] = ^(state & 32'h8a4ade5e);
                lfsr_jump_padded[22] = ^(state & 32'h5590417f);
                lfsr_jump_padded[23] = ^(state & 32'hab2082fe);
                lfsr_jump_padded[24] = ^(state & 32'h564105fd);
                lfsr_jump_padded[25] = ^(state & 32'hac820bfb);
                lfsr_jump_padded[26] = ^(state & 32'h590417f7);
                lfsr_jump_padded[27] = ^(state & 32'hb2082fee);
                lfsr_jump_padded[28] = ^(state & 32'h64105fdc);
                lfsr_jump_padded[29] = ^(state & 32'hc820bfb8);
                lfsr_jump_padded[30] = ^(state & 32'h90417f70);
                lfsr_jump_padded[31] = ^(state & 32'h2082fee1);
            end
            default: lfsr_jump_padded = state;
        endcase
    end
endfunction

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
reg signed [63:0] rhs [0:MAX_K-1];
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
reg [2:0] ls_op_q;
reg [4:0] ls_row_a_q;
reg [4:0] ls_col_a_q;
reg [4:0] ls_row_b_q;
reg [4:0] ls_col_b_q;
reg [4:0] ls_row_base_q;
reg [COLS-1:0] ls_lane_valid_q;
reg ls_row_update_block_q;
reg signed [GE_MAT_W-1:0] ls_wdata_q;
reg signed [63:0] ls_factor_q;
reg signed [63:0] ls_rhs_wdata_q;
wire ls_busy_w;
wire ls_done_w;
wire signed [GE_MAT_W-1:0] ls_rdata_a_w;
wire signed [GE_MAT_W-1:0] ls_rdata_b_w;
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
    .start(ls_start_q),
    .op(ls_op_q),
    .row_a(ls_row_a_q),
    .col_a(ls_col_a_q),
    .row_b(ls_row_b_q),
    .col_b(ls_col_b_q),
    .row_base(ls_row_base_q),
    .lane_valid(ls_lane_valid_q),
    .row_update_block(ls_row_update_block_q),
    .lane_add(pe_rhs_product_bus),
    .wdata(ls_wdata_q),
    .factor(ls_factor_q),
    .rhs_wdata(ls_rhs_wdata_q),
    .busy(ls_busy_w),
    .done(ls_done_w),
    .rdata_a(ls_rdata_a_w),
    .rdata_b(ls_rdata_b_w),
    .update_value(ls_update_value_w),
    .rhs_rdata(ls_rhs_rdata_w)
);

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
reg [IDX_W-1:0] mp_idx_q;
reg signed [DATA_W-1:0] mp_score_q;
reg signed [DATA_W-1:0] mp_x_old_q;
reg signed [DATA_W-1:0] mp_x_new_q;
reg signed [63:0] mp_den_q;
reg signed [63:0] div_result;
reg [5:0] solve_i;
reg [5:0] solve_j;
reg [5:0] solve_k;
reg [4:0] acc_i;
reg [5:0] acc_j;
reg [4:0] resid_i;
reg [5:0] back_i;
reg [5:0] back_j;
reg signed [127:0] residual_acc;
reg signed [127:0] residual_block_sum;
reg signed [DATA_W-1:0] phi_cache [0:MAX_K-1];
reg [IDX_W-1:0] support_cache [0:MAX_K-1];
reg [7:0] refine_prime_k_eff;
reg [31:0] phi_state_q;
reg [5:0] phi_load_i;
reg [IDX_W-1:0] phi_support_q;
reg phi_support_valid_q;
reg [IDX_W-1:0] padded_n_q;
reg [IDX_W-1:0] phi_scan_col_q;
reg [31:0] phi_scan_state_q;
reg scan_is_last_col;
reg [IDX_W-1:0] corr_col;
reg [IDX_W-1:0] corr_row;
reg [IDX_W-1:0] corr_scan_col;
reg signed [DATA_W-1:0] corr_phi;
reg signed [63:0] corr_acc;
reg [COLS*DATA_W-1:0] corr_phi_lane;
reg corr_stream_valid_q;
reg corr_stream_done_q;
reg [IDX_W-1:0] corr_stream_base_idx_q;
reg [COLS-1:0] corr_stream_lane_valid_q;
reg [COLS*DATA_W-1:0] corr_stream_data_q;
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
reg [IDX_W-1:0] load_support_q;
reg [IDX_W-1:0] load_support_next_q;
integer gi, gj, gk;
integer row2_prune_lane;
integer row2_prune_rank;
integer row3_lane;
reg row2_prune_support_hit;
reg [IDX_W-1:0] row2_prune_support_idx;
reg [IDX_W-1:0] row2_prune_lane_index;
reg signed [63:0] row3_residual_delta;
reg [COLS*DATA_W-1:0] mesh_ctx_residual_delta_bus;

integer comb_k;
integer rhs_lane;
integer corr_lane;
integer block_lane;
integer cache_pos;
integer cache_cmp;
reg [COLS-1:0] row2_prune_keep_mask;
wire [MAX_K*IDX_W-1:0] row2_support_flat_w;
reg [IDX_W-1:0] sparse_target_idx;
reg [IDX_W-1:0] wx_target_idx_q;
reg [DATA_W-1:0] wx_value_q;
reg [DATA_W-1:0] row3_selected_value;
reg [COLS*MEM_AW-1:0] row3_wr_addr;
reg [COLS*DATA_W-1:0] row3_wr_data;
reg [COLS-1:0] row3_wr_en;
wire row3_corr_mode_w = ((active_op == OP_CORR) && (state == S_CORR_WRITE));
wire row3_scalar_write_en_w = ((state == S_WX) || (state == S_WX_COMMIT) || (state == S_WR_MESH_COMMIT) || (state == S_IHT_MESH_WRITE) || (state == S_PRUNE_MESH_WRITE) || (state == S_IHT_SCORE_READ) || (state == S_PRUNE_X_WAIT) || (state == S_MP_X_WRITE));
wire row3_prune_block_mode_w = ((active_op == OP_PRUNE_X) && (state == S_PRUNE_MESH_WRITE));
wire row3_update_block_mode_w = (((active_op == OP_IHT_UPDATE) || (active_op == OP_GRAD_STEP)) && (state == S_IHT_MESH_WRITE));
wire row3_resid_write_op_w = (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_RESID) || (active_op == OP_MP_UPDATE)) && (k_active <= MAX_K));
wire row3_resid_mode_w = (row3_resid_write_op_w && (state == S_WR_MESH_COMMIT));
wire row3_commit_value_mode_w = row3_update_block_mode_w || row3_prune_block_mode_w || row3_resid_mode_w;
wire [DATA_W-1:0] row3_commit_value_w = row3_commit_value_mode_w ? row3_selected_value : write_value_now;
wire [COLS*DATA_W-1:0] row3_block_value_w = (row3_update_block_mode_w || row3_prune_block_mode_w || row3_resid_mode_w) ? pe_update_block_w : rd_data;
wire wx_commit_mode_w = (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (state == S_WX_COMMIT));
wire [2:0] row3_target_lane_w = wx_commit_mode_w ? wx_target_idx_q[2:0] : write_idx[2:0];
wire mesh_ctx_update_issue_w = 1'b0;
wire mesh_ctx_prune_issue_w = 1'b0;
wire mesh_ctx_resid_issue_w = (row3_resid_write_op_w && (state == S_WR));
wire mesh_ctx_update_active_w = mesh_ctx_update_issue_w || (state == S_IHT_MESH_WAIT) || (state == S_IHT_MESH_WRITE);
wire mesh_ctx_prune_active_w = mesh_ctx_prune_issue_w || (state == S_PRUNE_MESH_WAIT) || (state == S_PRUNE_MESH_WRITE);
wire mesh_ctx_resid_active_w = mesh_ctx_resid_issue_w || (state == S_WR_MESH_WAIT) || (state == S_WR_MESH_COMMIT);
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
    mesh_ctx_residual_delta_bus = {COLS*DATA_W{1'b0}};
    for (row3_lane = 0; row3_lane < COLS; row3_lane = row3_lane + 1)
        mesh_ctx_residual_delta_bus[row3_lane*DATA_W +: DATA_W] = row3_residual_delta[DATA_W-1:0];
    row3_selected_value = row3_commit_value_mode_w ? row3_block_value_w[row3_target_lane_w*DATA_W +: DATA_W] : write_value_now;
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
        end else if (row3_target_lane_w == row3_lane[2:0]) begin
            row3_wr_data[row3_lane*DATA_W +: DATA_W] = row3_selected_value;
            row3_wr_en[row3_lane] = busy && row3_scalar_write_en_w;
        end
    end
end
wire [5:0] active_k_count = (active_k > MAX_K[7:0]) ? MAX_K[5:0] : active_k[5:0];
wire [5:0] active_k_last = (active_k_count == 6'd0) ? 6'd0 : (active_k_count - 6'd1);


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
    residual_block_sum = 128'sd0;
    for (block_lane = 0; block_lane < RHS_BLOCK_STRIDE; block_lane = block_lane + 1) begin
        if ((rhs_block_base + block_lane) < active_k_count)
            residual_block_sum = residual_block_sum + $signed(pe_rhs_product_bus[block_lane*64 +: 64]);
    end
end

always @(*) begin
    pe_corr_acc_clear = busy && (active_op == OP_CORR) && ((state == S_CORR_INIT) || (state == S_CORR_WRITE));
    // The PE product is usable in PE_WAIT except on the first row after an
    // 8-row SPM bank transition, where the memory address needs one more cycle.
    pe_corr_acc_en = busy && (active_op == OP_CORR) &&
                     (((state == S_CORR_PE_WAIT) && !((corr_row != 0) && (corr_row[2:0] == 3'd0))) ||
                      (state == S_CORR_LATCH));
    pe_sparse_op = busy ? active_op : op_sel;
    pe_rhs_active = ((((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_MP_UPDATE)) && ((state == S_ACC) || (state == S_ACC_PE_WAIT) || (state == S_ACC_PE_WAIT2) || (state == S_ACC_RHS) || (state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM) || (state == S_RESID_PE_WAIT) || (state == S_RESID_PE_WAIT2) || (state == S_WR_ACC))) || ((active_op == OP_CORR) && (state == S_CORR_ACC)));
    pe_rhs_phi_bus = {COLS*DATA_W{1'b0}};
    pe_rhs_y_bus = {COLS*DATA_W{1'b0}};
    for (rhs_lane = 0; rhs_lane < COLS; rhs_lane = rhs_lane + 1) begin
        pe_rhs_phi_bus[rhs_lane*DATA_W +: DATA_W] = (active_op == OP_CORR) ? corr_phi_lane[rhs_lane*DATA_W +: DATA_W] : (((rhs_block_base + rhs_lane) < active_k) ? phi_cache[rhs_block_base + rhs_lane] : {DATA_W{1'b0}});
        pe_rhs_y_bus[rhs_lane*DATA_W +: DATA_W] = (((state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM)) ? phi_cache[acc_j] : (((state == S_RESID_PE_WAIT) || (state == S_RESID_PE_WAIT2) || (state == S_WR_ACC)) ? (((rhs_block_base + rhs_lane) < active_k) ? coeff_mem[rhs_block_base + rhs_lane] : {DATA_W{1'b0}}) : ((active_op == OP_CORR) ? rd_data[corr_row[2:0]*DATA_W +: DATA_W] : rd_data[write_idx[2:0]*DATA_W +: DATA_W])));
    end
end

always @(*) begin
    sparse_target_idx = support_cached_at(write_idx[4:0]);
    if (phase_residual)
        base_addr = 10'h080 + write_idx[IDX_W-1:3];
    else if (active_op == OP_CORR)
        base_addr = 10'h180 + write_idx[IDX_W-1:3];
    else if (wx_commit_mode_w)
        base_addr = 10'h000 + wx_target_idx_q[IDX_W-1:3];
    else if ((active_op == OP_IHT_UPDATE) || (active_op == OP_GRAD_STEP))
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
        phi_state_q <= DEFAULT_SEED;
        phi_load_i <= 5'd0;
        back_j <= 6'd0;
        back_i <= 6'd0;
        solve_k <= 6'd0;
        solve_j <= 6'd0;
        solve_i <= 6'd0;
        acc_j <= 6'd0;
        acc_i <= 5'd0;
        resid_i <= 5'd0;
        residual_acc <= 128'sd0;
        rhs_block_base <= 6'd0;
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
        corr_stream_valid_q <= 1'b0;
        corr_stream_done_q <= 1'b0;
        corr_stream_base_idx_q <= {IDX_W{1'b0}};
        corr_stream_lane_valid_q <= {COLS{1'b0}};
        corr_stream_data_q <= {COLS*DATA_W{1'b0}};
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
        ls_wdata_q <= {GE_MAT_W{1'b0}};
        ls_factor_q <= 64'sd0;
        ls_rhs_wdata_q <= 64'sd0;
        ls_row_update_block_q <= 1'b0;
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
        div_result <= 64'sd0;
        mp_idx_q <= {IDX_W{1'b0}};
        mp_score_q <= {DATA_W{1'b0}};
        mp_x_old_q <= {DATA_W{1'b0}};
        mp_x_new_q <= {DATA_W{1'b0}};
        mp_den_q <= 64'sd0;
        mesh_ctx_x_block <= {COLS*DATA_W{1'b0}};
        mesh_ctx_delta_block <= {COLS*DATA_W{1'b0}};
        mesh_ctx_keep_block <= {COLS{1'b0}};
        mesh_ctx_base_idx_block <= {IDX_W{1'b0}};
        mesh_ctx_limit_block <= {IDX_W{1'b0}};
        mesh_ctx_shift_block <= 4'd0;
        mesh_ctx_wait_count <= 4'd0;
        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
            rhs[gi] <= 64'sd0;
            coeff_mem[gi] <= {DATA_W{1'b0}};
            phi_cache[gi] <= {DATA_W{1'b0}};
            ge_x[gi] <= 64'sd0;
        end
    end else begin
                ls_start_q <= 1'b0;
                if (ls_done_w)
                    ls_row_update_block_q <= 1'b0;
        corr_stream_valid_q <= 1'b0;
        corr_stream_done_q <= 1'b0;
case (state)
            S_IDLE: begin
                busy <= 1'b0;
                done <= 1'b0;
                rd_addr <= {MEM_AW{1'b0}};
                if (start) begin
                    done <= 1'b0;
                    busy <= 1'b1;
                    active_op <= op_sel;
                    support_cache[0] <= support0;
                    support_cache[1] <= support1;
                    support_cache[2] <= support2;
                    support_cache[3] <= support3;
                    support_cache[4] <= support4;
                    support_cache[5] <= support5;
                    support_cache[6] <= support6;
                    support_cache[7] <= support7;
                    support_cache[8] <= support8;
                    support_cache[9] <= support9;
                    support_cache[10] <= support10;
                    support_cache[11] <= support11;
                    support_cache[12] <= support12;
                    support_cache[13] <= support13;
                    support_cache[14] <= support14;
                    support_cache[15] <= support15;
                    write_idx <= {IDX_W{1'b0}};
                    phase_residual <= 1'b0;
                    write_limit <= (op_sel == OP_CORR) ? n_size : n_size;
                    write_value <= {DATA_W{1'b0}};
                    state <= S_PRIME;
                end
            end
            S_PRIME: begin
                if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active == 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= 8'd0;
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= 10'h100;
                    residual_acc <= 128'sd0;
                    state <= S_WR;
                end else if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active <= MAX_K) && (k_active != 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
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
                    state <= S_LS_CLEAR_START;
                end else if ((active_op == OP_CORR) && (n_size != 0) && (m_size != 0)) begin
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
                    load_i <= 5'd0;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        coeff_mem[gi] <= {DATA_W{1'b0}};
                    load_support_q <= support0;
                    rd_addr <= 10'h000 + (support0 >> 3);
                    state <= S_LOAD_COEFF_READ;
                end else if ((active_op == OP_RESID) && (k_active == 0) && (m_size != 0)) begin
                    active_k <= 8'd0;
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= 10'h100;
                    residual_acc <= 128'sd0;
                    state <= S_WR;
                end else if ((active_op == OP_MP_UPDATE) && (support_depth0 != 0) && (n_size != 0) && (m_size != 0)) begin
                    active_k <= 8'd1;
                    mp_idx_q <= last_result_idx;
                    write_idx <= last_result_idx;
                    mp_den_q <= (($signed(mul_s24_s24(scale_q, scale_q)) + 64'sd32768) >>> 16) * $signed({1'b0, m_size});
                    rd_addr <= 10'h180 + (last_result_idx >> 3);
                    state <= S_MP_X_READ;
                end else if ((active_op == OP_PRUNE_X) && (n_size != 0)) begin
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
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
                state <= S_ACC_PE_WAIT;
            end
            S_ACC_PE_WAIT: begin
                state <= S_ACC_PE_WAIT2;
            end
            S_ACC_PE_WAIT2: begin
                state <= S_ACC_RHS;
            end
            S_ACC_RHS: begin
                for (gi = 0; gi < RHS_BLOCK_STRIDE; gi = gi + 1) begin
                    if ((rhs_block_base + gi) < active_k_count)
                        rhs[rhs_block_base + gi] <= rhs[rhs_block_base + gi] + $signed(pe_rhs_product_bus[gi*64 +: 64]);
                end
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) begin
                    rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                    acc_i <= 5'd0;
                    state <= S_ACC_PE_WAIT;
                end else begin
                    acc_i <= 5'd0;
                    acc_j <= 5'd0;
                    rhs_block_base <= 5'd0;
                    state <= S_GRAM_PE_WAIT;
                end
            end
            S_GRAM_PE_WAIT: begin
                state <= S_ACC_GRAM;
            end
            S_GRAM_PE_WAIT2: begin
                state <= S_ACC_GRAM;
            end
            S_ACC_GRAM: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_ACC_BLOCK;
                ls_row_base_q <= rhs_block_base;
                ls_col_a_q <= acc_j;
                for (gi = 0; gi < RHS_BLOCK_STRIDE; gi = gi + 1) begin
                    ls_lane_valid_q[gi] <= (((rhs_block_base + gi) < active_k_count) && ((rhs_block_base + gi) >= acc_j));
                end
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) begin
                    rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                    acc_i <= 5'd0;
                    state <= S_GRAM_PE_WAIT;
                end else if (acc_j + 5'd1 < active_k_count) begin
                    acc_j <= acc_j + 5'd1;
                    acc_i <= 5'd0;
                    rhs_block_base <= ((acc_j + 5'd1) / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE;
                    state <= S_GRAM_PE_WAIT;
                end else begin
                    acc_i <= 5'd0;
                    acc_j <= 5'd0;
                    rhs_block_base <= 5'd0;
                    if (write_idx + 1 >= write_limit) begin
                        state <= S_SOLVE_INIT;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                        if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                            rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                                        for (gi = 0; gi < MAX_K; gi = gi + 1)
                            phi_cache[gi] <= {DATA_W{1'b0}};
                        phi_scan_col_q <= {IDX_W{1'b0}};
                        phi_scan_state_q <= phi_state_q;
                        state <= S_SCAN_DIRECT_STEP;
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
                if (write_idx + 1 >= write_limit) begin
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
                    if (active_op == OP_REFINE_SPARSE) begin
                        wx_target_idx_q <= support_cached_at(write_idx[4:0] + 5'd1);
                        wx_value_q <= coeff_mem[write_idx[4:0] + 5'd1];
                    end else if (active_op == OP_REFINE) begin
                        wx_target_idx_q <= write_idx + 1'b1;
                        wx_value_q <= coeff_for_dense_idx(write_idx + 1'b1);
                    end
                end
            end
            S_WR_ACC_INIT: begin
                residual_acc <= 128'sd0;
                resid_i <= 5'd0;
                rhs_block_base <= 5'd0;
                state <= S_RESID_PE_WAIT;
            end
            S_RESID_PE_WAIT: begin
                state <= S_RESID_PE_WAIT2;
            end
            S_RESID_PE_WAIT2: begin
                state <= S_WR_ACC;
            end
            S_WR_ACC: begin
                residual_acc <= residual_acc + residual_block_sum;
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k_count) begin
                    rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                    resid_i <= 5'd0;
                    state <= S_RESID_PE_WAIT;
                end else begin
                    rhs_block_base <= 5'd0;
                    resid_i <= 5'd0;
                    state <= S_WR;
                end
            end
            S_WR: begin
                y_cur <= rd_data[write_idx[2:0]*DATA_W +: DATA_W];
                phi_cur <= phi_cache[0];
                phi1_cur <= phi_cache[1];
                write_value <= row3_commit_value_w;
                if (row3_resid_write_op_w) begin
                    mesh_ctx_x_block <= rd_data;
                    mesh_ctx_delta_block <= mesh_ctx_residual_delta_bus;
                    mesh_ctx_keep_block <= {COLS{1'b1}};
                    mesh_ctx_base_idx_block <= {write_idx[IDX_W-1:3], 3'b000};
                    mesh_ctx_limit_block <= write_limit;
                    mesh_ctx_shift_block <= mu_shift_eff;
                    mesh_ctx_wait_count <= MESH_CTX_WAIT_CYCLES;
                    state <= S_WR_MESH_WAIT;
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
                state <= S_RHS_INIT_WRITE;
            end
            S_RHS_INIT_WRITE: begin
                if (solve_i >= active_k_count) begin
                    solve_i <= 5'd0;
                    state <= S_SOLVE_SYM_READ;
                end else begin
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_RHS_WRITE;
                    ls_row_a_q <= solve_i;
                    ls_rhs_wdata_q <= rhs[solve_i];
                    state <= S_RHS_INIT_WAIT;
                end
            end
            S_RHS_INIT_WAIT: begin
                if (ls_done_w) begin
                    solve_i <= solve_i + 5'd1;
                    state <= S_RHS_INIT_WRITE;
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
                    back_i <= active_k_last;
                    state <= S_BACK_INIT;
                end else begin
                    solve_j <= solve_i + 5'd1;
                    state <= S_ELIM_ROW;
                end
            end
            S_ELIM_ROW: begin
                if (solve_j >= active_k_count) begin
                    solve_i <= solve_i + 5'd1;
                    state <= S_ELIM_START;
                end else begin
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_READ2;
                    ls_row_a_q <= solve_j;
                    ls_col_a_q <= solve_i;
                    ls_row_b_q <= solve_i;
                    ls_col_b_q <= solve_i;
                    solve_k <= solve_i;
                    state <= S_ELIM_ROW_READ;
                end
            end
            S_ELIM_ROW_READ: begin
                if (ls_done_w) begin
                    ge_div_num <= {{(64-GE_MAT_W){ls_rdata_a_w[GE_MAT_W-1]}}, ls_rdata_a_w} <<< 16;
                    ge_div_den <= (ls_rdata_b_w != 0) ? {{(64-GE_MAT_W){ls_rdata_b_w[GE_MAT_W-1]}}, ls_rdata_b_w} : 64'sd1;
                    div_return_back <= 1'b0;
                    state <= S_DIV_INIT;
                end
            end
            S_ELIM_PREP: begin
                div_return_back <= 1'b0;
                state <= S_DIV_INIT;
            end
            S_ELIM_MUL: begin
                ge_mul_p <= $signed(ge_factor) * $signed(ge_mul_b);
                state <= S_ELIM_UPDATE;
            end
            S_ELIM_UPDATE: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_ROW_UPDATE;
                ls_row_a_q <= solve_j;
                ls_col_a_q <= solve_k;
                ls_row_b_q <= solve_i;
                ls_col_b_q <= solve_k;
                ls_factor_q <= ge_factor;
                ls_row_update_block_q <= 1'b1;
                for (gi = 0; gi < COLS; gi = gi + 1) begin
                    ls_lane_valid_q[gi] <= ((solve_k + gi[4:0]) < active_k_count);
                end
                state <= S_ELIM_UPDATE_WAIT;
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
                if (active_k == 0) begin
                    state <= S_SOLVE_DONE;
                end else begin
                    ge_acc <= 64'sd0;
                    back_j <= back_i + 5'd1;
                    // Keep the small back-solve controller here.  Issuing the
                    // first upper read in this state saves only one cycle per
                    // row, but causes a large mux replication after synthesis.
                    // S_BACK_ACC_READ still prefetches the diagonal on the last
                    // upper term, which retains the inexpensive fast path.
                    state <= S_BACK_ACC;
                end
            end
            S_BACK_ACC: begin
                if (back_j >= active_k_count) begin
                    state <= S_BACK_PREP;
                end else begin
                    ls_start_q <= 1'b1;
                    ls_op_q <= LS_OP_READ2;
                    ls_row_a_q <= back_i;
                    ls_col_a_q <= back_j;
                    ls_row_b_q <= 5'd0;
                    ls_col_b_q <= 5'd0;
                    state <= S_BACK_ACC_READ;
                end
            end
            S_BACK_ACC_READ: begin
                if (ls_done_w) begin
                    ge_acc <= ge_acc + $signed(back_mul_p_w >>> 16);
                    back_j <= back_j + 5'd1;
                    if ((back_j + 5'd1) >= active_k_count) begin
                        ls_start_q <= 1'b1;
                        ls_op_q <= LS_OP_READ2;
                        ls_row_a_q <= back_i;
                        ls_col_a_q <= back_i;
                        ls_row_b_q <= 5'd0;
                        ls_col_b_q <= 5'd0;
                        state <= S_BACK_PREP_READ;
                    end else begin
                        state <= S_BACK_ACC;
                    end
                end
            end
            S_BACK_MUL: begin
                ge_mul_p <= $signed(ge_mul_a) * $signed(ge_mul_b);
                state <= S_BACK_UPDATE;
            end
            S_BACK_UPDATE: begin
                ge_acc <= ge_acc + $signed(ge_mul_p >>> 16);
                back_j <= back_j + 5'd1;
                state <= S_BACK_ACC;
            end
            S_BACK_PREP: begin
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_READ2;
                ls_row_a_q <= back_i;
                ls_col_a_q <= back_i;
                ls_row_b_q <= 5'd0;
                ls_col_b_q <= 5'd0;
                state <= S_BACK_PREP_READ;
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
                ls_start_q <= 1'b1;
                ls_op_q <= LS_OP_RHS_READ;
                ls_row_a_q <= back_i;
                state <= S_BACK_RHS_READ_WAIT;
            end
            S_BACK_RHS_READ_WAIT: begin
                if (ls_done_w) begin
                    ge_div_num <= (ls_rhs_rdata_w - ge_acc) <<< 16;
                    div_return_back <= 1'b1;
                    state <= S_DIV_INIT;
                end
            end
            S_BACK_DIV: begin
                div_return_back <= 1'b1;
                state <= S_DIV_INIT;
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
                    state <= div_return_back ? S_BACK_DIV_DONE : (div_return_mp ? S_MP_DIV_DONE : S_ELIM_DIV_DONE);
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
                    // Two more restoring steps halve the LS divider latency
                    // from 32 to 16 clocks without adding another divider or
                    // changing the fixed-point quotient/rounding behavior.
                    if (div_iter > 2) begin
                        div_trial_rem = {div_trial_rem[63:0], div_abs_num[div_iter - 3'd3]};
                        if (div_trial_rem >= {1'b0, div_abs_den}) begin
                            div_trial_rem = div_trial_rem - {1'b0, div_abs_den};
                            div_trial_quot[div_iter - 3'd3] = 1'b1;
                        end
                    end
                    if (div_iter > 3) begin
                        div_trial_rem = {div_trial_rem[63:0], div_abs_num[div_iter - 3'd4]};
                        if (div_trial_rem >= {1'b0, div_abs_den}) begin
                            div_trial_rem = div_trial_rem - {1'b0, div_abs_den};
                            div_trial_quot[div_iter - 3'd4] = 1'b1;
                        end
                    end
                    if (div_iter <= 4) begin
                        if ({div_trial_rem[63:0], 1'b0} >= {1'b0, div_abs_den})
                            div_trial_quot = div_trial_quot + 1'b1;
                        div_result <= div_neg ? -$signed(div_trial_quot[63:0]) : $signed(div_trial_quot[63:0]);
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        state <= div_return_back ? S_BACK_DIV_DONE : (div_return_mp ? S_MP_DIV_DONE : S_ELIM_DIV_DONE);
                    end else begin
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        div_iter <= div_iter - 7'd4;
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
            S_MP_X_WRITE: begin
                active_k <= 8'd1;
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
                write_idx <= {IDX_W{1'b0}};
                write_limit <= (active_op == OP_REFINE_SPARSE) ? active_k : n_size;
                phase_residual <= 1'b0;
                wx_target_idx_q <= (active_op == OP_REFINE_SPARSE) ? support_cached_at(5'd0) : {IDX_W{1'b0}};
                wx_value_q <= (active_op == OP_REFINE_SPARSE) ? coeff_mem[0] : coeff_for_dense_idx({IDX_W{1'b0}});
                state <= S_WX_COMMIT;
            end
            S_CORR_INIT: begin
                corr_row <= {IDX_W{1'b0}};
                corr_scan_col <= {IDX_W{1'b0}};
                corr_acc <= 64'sd0;
                corr_phi_lane <= {COLS*DATA_W{1'b0}};
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
                state <= S_CORR_ACC;
            end
            S_CORR_ACC: begin
                state <= S_CORR_PE_WAIT;
            end
            S_CORR_PE_WAIT: begin
                if (corr_row + 1 < m_size) begin
                    rd_addr <= 10'h080 + ((corr_row + 1'b1) >> 3);
                    for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                        if ((corr_col + corr_lane[IDX_W-1:0]) < n_size)
                            corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= phi_from_lfsr_state(lfsr_advance(corr_row_next_state, corr_lane[IDX_W-1:0] + 1'b1));
                        else
                            corr_phi_lane[corr_lane*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
                    end
                    phi_state_q <= lfsr_jump_padded(corr_row_next_state, padded_n_q);
                    corr_scan_col <= {IDX_W{1'b0}};
                end
                // Retain the latch bubble only at SPM bank boundaries.
                if ((corr_row != 0) && (corr_row[2:0] == 3'd0)) begin
                    state <= S_CORR_LATCH;
                end else if (corr_row + 1 >= m_size) begin
                    write_idx <= corr_col;
                    state <= S_CORR_WRITE;
                end else begin
                    corr_row <= corr_row + 1'b1;
                    corr_row_state <= corr_row_next_state;
                    corr_row_next_state <= lfsr_jump_padded(corr_row_next_state, padded_n_q);
                    state <= S_CORR_ACC;
                end
            end
            S_CORR_LATCH: begin
                if (corr_row + 1 >= m_size) begin
                    write_idx <= corr_col;
                    state <= S_CORR_WRITE;
                end else begin
                    corr_row <= corr_row + 1'b1;
                    corr_row_state <= corr_row_next_state;
                    corr_row_next_state <= lfsr_jump_padded(corr_row_next_state, padded_n_q);
                    state <= S_CORR_ACC;
                end
            end
            S_CORR_WRITE: begin
                corr_stream_valid_q <= busy;
                corr_stream_done_q <= (corr_col + COLS[IDX_W-1:0] >= n_size);
                corr_stream_base_idx_q <= corr_col;
                for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                    corr_stream_lane_valid_q[corr_lane] <= ((corr_col + corr_lane[IDX_W-1:0]) < n_size);
                    corr_stream_data_q[corr_lane*DATA_W +: DATA_W] <= row3_wr_data[corr_lane*DATA_W +: DATA_W];
                end
                corr_block_seq <= corr_block_seq + 1'b1;
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
                write_value <= write_value_now;
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
                    rd_addr <= 10'h100;
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
                    rd_addr <= 10'h000 + (load_support_next_q >> 3);
                    state <= S_LOAD_COEFF_READ;
                end
            end
            S_PRUNE_X_READ: begin
                state <= S_PRUNE_X_WAIT;
            end
            S_PRUNE_X_WAIT: begin
                write_value <= write_value_now;
                if (write_idx + 1'b1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    rd_addr <= 10'h000 + ((write_idx + 1'b1) >> 3);
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
                for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                    if ((gi < active_k_count) && (support_cache[gi] >= phi_scan_col_q) && (support_cache[gi] < (phi_scan_col_q + 10'd32))) begin
                        phi_cache[gi] <= phi_from_lfsr_state(lfsr_advance32(phi_scan_state_q, {1'b0, (support_cache[gi] - phi_scan_col_q[IDX_W-1:0])} + 6'd1));
                    end
                end
                if (phi_scan_col_q + 10'd32 >= padded_n_q) begin
                    phi_state_q <= lfsr_advance32(phi_scan_state_q, 6'd32);
                    state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                end else begin
                    phi_scan_col_q <= phi_scan_col_q + 10'd32;
                    phi_scan_state_q <= lfsr_advance32(phi_scan_state_q, 6'd32);
                end
            end
            S_DONE: begin                busy <= 1'b0;
                done <= 1'b1;
                result <= {SCALAR_W{1'b0}};
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end
endmodule
































