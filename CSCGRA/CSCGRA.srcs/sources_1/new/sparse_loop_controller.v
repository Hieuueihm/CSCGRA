module sparse_loop_controller #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W = 10,
    parameter integer MAX_M = 128,
    parameter integer MAX_N = 128,
    parameter integer MAX_K = 16,
    parameter integer REFINE_ITERS = 128,
    parameter integer MU_SHIFT = 2
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
    input wire [DATA_W-1:0] scale_q,
    input wire [1:0] phi_kind,
    input wire [COLS*DATA_W-1:0] phi_bus,
    input wire [COLS*64-1:0] pe_rhs_product_bus,
    input wire [SCALAR_W-1:0] last_result_value,
    input wire [IDX_W-1:0] last_result_idx,
    output reg [COLS*DATA_W-1:0] pe_rhs_phi_bus,
    output reg [COLS*DATA_W-1:0] pe_rhs_y_bus,
    output reg pe_rhs_active,
    output reg pe_sparse_clear,
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
    output reg busy,
    output reg done,
    output reg [SCALAR_W-1:0] result
);
localparam [6:0] S_IDLE=0, S_PRIME=1, S_ACC=3, S_WX=5, S_WR=7, S_DONE=8, S_SCAN=10, S_SOLVE_INIT=11, S_ELIM_START=12, S_ELIM_ROW=13, S_ELIM_UPDATE=14, S_BACK_INIT=15, S_BACK_ACC=16, S_BACK_DIV=17, S_SOLVE_DONE=18, S_ACC_RHS=19, S_ACC_GRAM=20, S_WR_ACC_INIT=21, S_WR_ACC=22, S_BACK_PREP=23, S_ELIM_PREP=24, S_ELIM_MUL=25, S_BACK_MUL=26, S_BACK_UPDATE=27, S_DIV_INIT=28, S_DIV_STEP=29, S_ELIM_DIV_DONE=30, S_BACK_DIV_DONE=31, S_CORR_INIT=34, S_CORR_SCAN=35, S_CORR_ACC=36, S_CORR_WRITE=37, S_IHT_X_WAIT=38, S_IHT_SCORE_WAIT=39, S_LOAD_COEFF_WAIT=40, S_PRUNE_X_WAIT=41, S_IHT_SCORE_READ=42, S_IHT_X_READ=43, S_PRUNE_X_READ=44, S_LOAD_COEFF_READ=45, S_LOAD_COEFF_CAP=46, S_ACC_PE_WAIT=47, S_GRAM_PE_WAIT=48, S_GRAM_PE_WAIT2=49, S_RESID_PE_WAIT=50, S_RESID_PE_WAIT2=51, S_ACC_PE_WAIT2=53, S_CORR_PE_WAIT=54, S_CORR_LATCH=57,
S_CACHE_BUILD=56, S_SCAN_DIRECT=55,
S_MP_X_READ=70, S_MP_X_WAIT=71, S_MP_DIV_PREP=72, S_MP_X_WRITE=73, S_MP_DIV_DONE=74, S_MP_SCORE_CAP=75, S_MP_X_CAP=76, S_SCAN_DIRECT_STEP=77, S_CACHE_BUILD_STEP=78;
localparam [3:0] OP_REFINE=4'd0, OP_CORR=4'd1, OP_IHT_UPDATE=4'd2, OP_RESID=4'd3, OP_PRUNE_X=4'd4, OP_MP_UPDATE=4'd5, OP_REFINE_SPARSE=4'd6;
localparam [4:0] RHS_BLOCK_STRIDE = COLS;

localparam [31:0] LFSR_TAPS = 32'h80200003;
localparam [31:0] DEFAULT_SEED = 32'hDEADBEEF;

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
            15: support_at = support15;
            16: support_at = support16;
            17: support_at = support17;
            18: support_at = support18;
            19: support_at = support19;
            20: support_at = support20;
            21: support_at = support21;
            22: support_at = support22;
            23: support_at = support23;
            24: support_at = support24;
            25: support_at = support25;
            26: support_at = support26;
            27: support_at = support27;
            28: support_at = support28;
            29: support_at = support29;
            30: support_at = support30;
            default: support_at = support31;
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
reg [31:0] accum_dbg;
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
reg signed [63:0] rhs_build_cache [0:MAX_K-1];
reg signed [DATA_W-1:0] coeff_mem [0:MAX_K-1];
localparam integer GE_MAT_W = 56;
reg signed [GE_MAT_W-1:0] ge_mat [0:MAX_K-1][0:MAX_K-1];
reg signed [GE_MAT_W-1:0] ge_mat_build_cache [0:MAX_K-1][0:MAX_K-1];
reg signed [63:0] ge_rhs [0:MAX_K-1];
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
reg [4:0] solve_i;
reg [4:0] solve_j;
reg [4:0] solve_k;
reg [4:0] acc_i;
reg [4:0] acc_j;
reg [4:0] resid_i;
reg [4:0] back_i;
reg [4:0] back_j;
reg signed [127:0] residual_acc;
reg signed [127:0] residual_block_sum;
reg signed [DATA_W-1:0] phi_cache [0:MAX_K-1];
reg [IDX_W-1:0] support_cache [0:MAX_K-1];
reg [IDX_W-1:0] support_build_cache [0:MAX_K-1];
reg refine_build_cache_valid;
reg [7:0] refine_build_cache_k;
reg [IDX_W-1:0] refine_cache_m_size;
reg [IDX_W-1:0] refine_cache_n_size;
reg [31:0] refine_cache_seed;
reg [DATA_W-1:0] refine_cache_scale_q;
reg [1:0] refine_cache_phi_kind;
reg refine_same_support_comb;
reg refine_extend_support_comb;
reg [4:0] refine_new_pos_comb;
reg refine_incremental_active;
reg refine_skip_build_active;
reg [4:0] refine_new_pos;
reg [7:0] refine_prime_k_eff;
reg refine_pos_match;
reg refine_any_insert_match;
reg [31:0] phi_state_q;
reg [31:0] phi_state_next;
reg [IDX_W-1:0] scan_col;
reg [4:0] phi_load_i;
reg [4:0] cache_i;
reg [4:0] cache_j;
reg [IDX_W-1:0] padded_n_q;
reg signed [DATA_W-1:0] scan_base_phi;
reg signed [DATA_W-1:0] scan_hit_phi;
reg scan_is_last_col;
reg [IDX_W-1:0] corr_col;
reg [IDX_W-1:0] corr_row;
reg [IDX_W-1:0] corr_scan_col;
reg signed [DATA_W-1:0] corr_phi;
reg signed [63:0] corr_acc;
reg [COLS*DATA_W-1:0] corr_phi_lane;
reg [COLS*64-1:0] corr_acc_lane;
reg corr_stream_valid_q;
reg corr_stream_done_q;
reg [IDX_W-1:0] corr_stream_base_idx_q;
reg [COLS-1:0] corr_stream_lane_valid_q;
reg [COLS*DATA_W-1:0] corr_stream_data_q;
reg [31:0] corr_block_seq;
reg [31:0] corr_block_state;
reg [31:0] corr_row_state;
reg [31:0] corr_row_next_state;
reg signed [DATA_W-1:0] iht_x_value;
reg [4:0] load_i;
reg [4:0] rhs_block_base;
reg [IDX_W-1:0] load_support_q;
reg [IDX_W-1:0] load_support_next_q;
integer gi, gj, gk;
integer comb_k;
integer keep_k;
integer rhs_lane;
integer corr_lane;
integer block_lane;
integer cache_pos;
integer cache_cmp;
reg keep_x;
reg [IDX_W-1:0] sparse_target_idx;
wire [IDX_W-1:0] support_xor = support0 ^ support1 ^ support2 ^ support3 ^ support4 ^ support5 ^ support6 ^ support7 ^ support8 ^ support9 ^ support10 ^ support11 ^ support12 ^ support13 ^ support14 ^ support15 ^ support16 ^ support17 ^ support18 ^ support19 ^ support20 ^ support21 ^ support22 ^ support23 ^ support24 ^ support25 ^ support26 ^ support27 ^ support28 ^ support29 ^ support30 ^ support31;
wire [DATA_W-1:0] phi_fold = phi_bus[DATA_W-1:0] ^ rd_data[DATA_W-1:0] ^ scale_q;
wire [31:0] misc_fold = seed ^ {24'd0, k_active} ^ {22'd0, op_sel, 2'b00} ^ { {(32-IDX_W){1'b0}}, support_xor };


function [IDX_W-1:0] support_cached_at;
    input [4:0] rank;
    begin
        support_cached_at = support_cache[rank];
    end
endfunction


assign corr_stream_valid = corr_stream_valid_q;
assign corr_stream_done = corr_stream_done_q;
assign corr_stream_base_idx = corr_stream_base_idx_q;
assign corr_stream_lane_valid = corr_stream_lane_valid_q;
assign corr_stream_data = corr_stream_data_q;

always @(*) begin
    refine_prime_k_eff = (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
    refine_same_support_comb = 1'b0;
    refine_extend_support_comb = 1'b0;
    refine_new_pos_comb = 5'd0;
    refine_any_insert_match = 1'b0;

    if (refine_build_cache_valid &&
        (refine_cache_m_size == m_size) &&
        (refine_cache_n_size == n_size) &&
        (refine_cache_seed == seed) &&
        (refine_cache_scale_q == scale_q) &&
        (refine_cache_phi_kind == phi_kind)) begin

        if (refine_build_cache_k == refine_prime_k_eff) begin
            refine_same_support_comb = 1'b1;
            for (cache_cmp = 0; cache_cmp < MAX_K; cache_cmp = cache_cmp + 1) begin
                if ((cache_cmp < refine_prime_k_eff) && (support_cache[cache_cmp] != support_build_cache[cache_cmp]))
                    refine_same_support_comb = 1'b0;
            end
        end

        if ((refine_prime_k_eff != 0) && (refine_build_cache_k + 8'd1 == refine_prime_k_eff)) begin
            for (cache_pos = 0; cache_pos < MAX_K; cache_pos = cache_pos + 1) begin
                refine_pos_match = 1'b1;
                for (cache_cmp = 0; cache_cmp < MAX_K; cache_cmp = cache_cmp + 1) begin
                    if (cache_cmp < refine_build_cache_k) begin
                        if (cache_cmp < cache_pos) begin
                            if (support_cache[cache_cmp] != support_build_cache[cache_cmp])
                                refine_pos_match = 1'b0;
                        end else begin
                            if (support_cache[cache_cmp + 1] != support_build_cache[cache_cmp])
                                refine_pos_match = 1'b0;
                        end
                    end
                end
                if ((cache_pos < refine_prime_k_eff) && refine_pos_match && !refine_any_insert_match) begin
                    refine_extend_support_comb = 1'b1;
                    refine_any_insert_match = 1'b1;
                    refine_new_pos_comb = cache_pos[4:0];
                end
            end
        end
    end
end

always @(*) begin
    residual_block_sum = 128'sd0;
    for (block_lane = 0; block_lane < RHS_BLOCK_STRIDE; block_lane = block_lane + 1) begin
        if ((rhs_block_base + block_lane) < active_k[4:0])
            residual_block_sum = residual_block_sum + $signed(pe_rhs_product_bus[block_lane*64 +: 64]);
    end
end

always @(*) begin
    pe_sparse_clear = busy && (active_op == OP_CORR) && (state == S_CORR_INIT);
    pe_sparse_op = busy ? active_op : op_sel;
    pe_rhs_active = ((((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && ((state == S_ACC) || (state == S_ACC_PE_WAIT) || (state == S_ACC_PE_WAIT2) || (state == S_ACC_RHS) || (state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM) || (state == S_RESID_PE_WAIT) || (state == S_RESID_PE_WAIT2) || (state == S_WR_ACC))) || ((active_op == OP_CORR) && (state == S_CORR_ACC)));
    pe_rhs_phi_bus = {COLS*DATA_W{1'b0}};
    pe_rhs_y_bus = {COLS*DATA_W{1'b0}};
    for (rhs_lane = 0; rhs_lane < COLS; rhs_lane = rhs_lane + 1) begin
        pe_rhs_phi_bus[rhs_lane*DATA_W +: DATA_W] = (active_op == OP_CORR) ? corr_phi_lane[rhs_lane*DATA_W +: DATA_W] : ((((state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM)) && refine_incremental_active) ? phi_cache[refine_new_pos] : (((rhs_block_base + rhs_lane) < active_k) ? phi_cache[rhs_block_base + rhs_lane] : {DATA_W{1'b0}}));
        pe_rhs_y_bus[rhs_lane*DATA_W +: DATA_W] = (((state == S_GRAM_PE_WAIT) || (state == S_GRAM_PE_WAIT2) || (state == S_ACC_GRAM)) ? (refine_incremental_active ? (((rhs_block_base + rhs_lane) < active_k) ? phi_cache[rhs_block_base + rhs_lane] : {DATA_W{1'b0}}) : phi_cache[acc_j]) : (((state == S_RESID_PE_WAIT) || (state == S_RESID_PE_WAIT2) || (state == S_WR_ACC)) ? (((rhs_block_base + rhs_lane) < active_k) ? coeff_mem[rhs_block_base + rhs_lane] : {DATA_W{1'b0}}) : ((active_op == OP_CORR) ? rd_data[corr_row[2:0]*DATA_W +: DATA_W] : rd_data[write_idx[2:0]*DATA_W +: DATA_W])));
    end
end

always @(*) begin
    sparse_target_idx = support_cached_at(write_idx[4:0]);
    if (phase_residual)
        base_addr = 10'h080 + write_idx[IDX_W-1:3];
    else if (active_op == OP_CORR)
        base_addr = 10'h180 + write_idx[IDX_W-1:3];
    else if ((active_op == OP_REFINE_SPARSE) && (state == S_WX))
        base_addr = 10'h000 + sparse_target_idx[IDX_W-1:3];
    else if (active_op == OP_IHT_UPDATE)
        base_addr = 10'h000 + write_idx[IDX_W-1:3];
    else
        base_addr = 10'h000 + write_idx[IDX_W-1:3];

    keep_x = 1'b0;
    for (keep_k = 0; keep_k < MAX_K; keep_k = keep_k + 1) begin
        if ((keep_k < active_k) && (write_idx == support_cached_at(keep_k[4:0])))
            keep_x = 1'b1;
    end

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

    if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE)) && (k_active <= MAX_K) && (state == S_WX)) begin
        write_value_now = {DATA_W{1'b0}};
        if (active_op == OP_REFINE_SPARSE) begin
            if (write_idx < active_k)
                write_value_now = coeff_mem[write_idx[4:0]];
        end else begin
            for (comb_k = 0; comb_k < MAX_K; comb_k = comb_k + 1) begin
                if ((comb_k < active_k) && (write_idx == support_cached_at(comb_k[4:0])))
                    write_value_now = coeff_mem[comb_k];
            end
        end
    end else if ((active_op == OP_CORR) && (state == S_CORR_WRITE)) begin
        write_value_now = write_value;
    end else if ((active_op == OP_IHT_UPDATE) && (state == S_IHT_SCORE_READ)) begin
        write_value_now = sat_s24($signed(iht_x_value) + ($signed(rd_data[write_idx[2:0]*DATA_W +: DATA_W]) >>> MU_SHIFT));
    end else if ((active_op == OP_PRUNE_X) && (state == S_PRUNE_X_WAIT)) begin
        write_value_now = keep_x ? rd_data[write_idx[2:0]*DATA_W +: DATA_W] : {DATA_W{1'b0}};
    end else if ((active_op == OP_MP_UPDATE) && (state == S_MP_X_WRITE)) begin
        write_value_now = mp_x_new_q;
    end else if (((active_op == OP_REFINE) || (active_op == OP_REFINE_SPARSE) || (active_op == OP_RESID)) && (k_active <= MAX_K) && (state == S_WR)) begin
        write_value_now = sat_s24($signed(rd_data[write_idx[2:0]*DATA_W +: DATA_W]) - $signed(residual_acc >>> 16));
    end else
        write_value_now = write_value;

    wr_addr = {COLS*MEM_AW{1'b0}};
    wr_data = {COLS*DATA_W{1'b0}};
    wr_en = {COLS{1'b0}};
    for (lane = 0; lane < COLS; lane = lane + 1) begin
        wr_addr[lane*MEM_AW +: MEM_AW] = base_addr;
        if ((active_op == OP_CORR) && (state == S_CORR_WRITE)) begin
            wr_data[lane*DATA_W +: DATA_W] = sat_s24($signed(corr_acc_lane[lane*64 +: 64]) >>> 16);
            wr_en[lane] = busy && ((write_idx + lane[IDX_W-1:0]) < write_limit);
        end else if ((((active_op == OP_REFINE_SPARSE) && (state == S_WX)) ? sparse_target_idx[2:0] : write_idx[2:0]) == lane[2:0]) begin
            wr_data[lane*DATA_W +: DATA_W] = write_value_now;
            wr_en[lane] = busy && ((state == S_WX) || (state == S_WR) || (state == S_IHT_SCORE_READ) || (state == S_PRUNE_X_WAIT) || (state == S_MP_X_WRITE));
        end
    end
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
        accum_dbg <= 32'd0;
        active_k <= 8'd0;
        phi_state_q <= DEFAULT_SEED;
        phi_state_next <= DEFAULT_SEED;
        scan_col <= {IDX_W{1'b0}};
        phi_load_i <= 5'd0;
        cache_i <= 5'd0;
        cache_j <= 5'd0;
        padded_n_q <= {IDX_W{1'b0}};
        scan_base_phi <= {DATA_W{1'b0}};
        scan_hit_phi <= {DATA_W{1'b0}};
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
        iht_x_value <= {DATA_W{1'b0}};
        load_i <= 5'd0;
        ge_mul_a <= 64'sd0;
        ge_mul_b <= 64'sd0;
        ge_mul_c <= 64'sd0;
        ge_mul_p <= 128'sd0;
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
        refine_build_cache_valid <= 1'b0;
        refine_build_cache_k <= 8'd0;
        refine_cache_m_size <= {IDX_W{1'b0}};
        refine_cache_n_size <= {IDX_W{1'b0}};
        refine_cache_seed <= 32'd0;
        refine_cache_scale_q <= {DATA_W{1'b0}};
        refine_cache_phi_kind <= 2'b00;
        refine_incremental_active <= 1'b0;
        refine_skip_build_active <= 1'b0;
        refine_new_pos <= 5'd0;
        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
            rhs[gi] <= 64'sd0;
            rhs_build_cache[gi] <= 64'sd0;
            coeff_mem[gi] <= {DATA_W{1'b0}};
            phi_cache[gi] <= {DATA_W{1'b0}};
            ge_rhs[gi] <= 64'sd0;
            ge_x[gi] <= 64'sd0;
            support_build_cache[gi] <= {IDX_W{1'b0}};
            for (gj = 0; gj < MAX_K; gj = gj + 1) begin
                ge_mat[gi][gj] <= 64'sd0;
                ge_mat_build_cache[gi][gj] <= 64'sd0;
            end
        end
    end else begin
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
                    accum_dbg <= misc_fold ^ {8'd0, phi_fold};
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
                    refine_incremental_active <= 1'b0;
                    refine_skip_build_active <= 1'b0;
                    refine_new_pos <= refine_new_pos_comb;
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    rd_addr <= 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    scan_col <= {IDX_W{1'b0}};
                    padded_n_q <= ((n_size + 7) >> 3) << 3;
                                acc_num <= 64'sd0;
                    acc_den <= 64'sd0;
                    acc_num1 <= 64'sd0;
                    acc_den01 <= 64'sd0;
                    acc_den11 <= 64'sd0;
                    if (refine_same_support_comb) begin
                        refine_skip_build_active <= 1'b1;
                        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                            rhs[gi] <= rhs_build_cache[gi];
                            coeff_mem[gi] <= {DATA_W{1'b0}};
                            ge_rhs[gi] <= 64'sd0;
                            ge_x[gi] <= 64'sd0;
                            for (gj = 0; gj < MAX_K; gj = gj + 1) begin
                                ge_mat[gi][gj] <= ge_mat_build_cache[gi][gj];
                            end
                        end
                    end else if (refine_extend_support_comb && (refine_new_pos_comb == refine_build_cache_k[4:0])) begin
                        refine_incremental_active <= 1'b1;
                        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                            coeff_mem[gi] <= {DATA_W{1'b0}};
                            ge_rhs[gi] <= 64'sd0;
                            ge_x[gi] <= 64'sd0;
                            if (gi < refine_build_cache_k[4:0])
                                rhs[gi] <= rhs_build_cache[gi];
                            else
                                rhs[gi] <= 64'sd0;
                            for (gj = 0; gj < MAX_K; gj = gj + 1) begin
                                if ((gi < refine_build_cache_k[4:0]) && (gj < refine_build_cache_k[4:0]))
                                    ge_mat[gi][gj] <= ge_mat_build_cache[gi][gj];
                                else
                                    ge_mat[gi][gj] <= {GE_MAT_W{1'b0}};
                            end
                        end
                    end else begin
                        for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                            rhs[gi] <= 64'sd0;
                            coeff_mem[gi] <= {DATA_W{1'b0}};
                            ge_rhs[gi] <= 64'sd0;
                            ge_x[gi] <= 64'sd0;
                            for (gj = 0; gj < MAX_K; gj = gj + 1) begin
                                ge_mat[gi][gj] <= 64'sd0;
                            end
                        end
                    end
                    phase_residual <= 1'b0;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    state <= refine_same_support_comb ? S_SOLVE_INIT : ((phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN);
                end else if ((active_op == OP_CORR) && (n_size != 0) && (m_size != 0)) begin
                    corr_col <= {IDX_W{1'b0}};
                    corr_row <= {IDX_W{1'b0}};
                    corr_scan_col <= {IDX_W{1'b0}};
                    corr_acc <= 64'sd0;
                    corr_phi_lane <= {COLS*DATA_W{1'b0}};
                    corr_acc_lane <= {COLS*64{1'b0}};
                    rd_addr <= 10'h080;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    corr_block_state <= (|seed) ? seed : DEFAULT_SEED;
                    corr_row_state <= (|seed) ? seed : DEFAULT_SEED;
                    corr_row_next_state <= lfsr_advance((|seed) ? seed : DEFAULT_SEED, ((n_size + 7) >> 3) << 3);
                    padded_n_q <= ((n_size + 7) >> 3) << 3;
                    state <= S_CORR_SCAN;
                end else if ((active_op == OP_IHT_UPDATE) && (n_size != 0)) begin
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
                    active_k <= (support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active;
                    mp_idx_q <= support_cached_at((((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) == 0) ? 5'd0 : (((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) - 1'b1));
                    write_idx <= support_cached_at((((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) == 0) ? 5'd0 : (((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) - 1'b1));
                    mp_den_q <= (($signed(mul_s24_s24(scale_q, scale_q)) + 64'sd32768) >>> 16) * $signed({1'b0, m_size});
                    rd_addr <= 10'h180 + (support_cached_at((((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) == 0) ? 5'd0 : (((support_depth0 < k_active[5:0]) ? {2'b00, support_depth0} : k_active) - 1'b1)) >> 3);
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
            S_ACC: begin
                acc_i <= 5'd0;
                rhs_block_base <= refine_incremental_active ? ((refine_new_pos / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE) : 5'd0;
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
                    if ((rhs_block_base + gi) < active_k[4:0] && (!refine_incremental_active || ((rhs_block_base + gi) == refine_new_pos)))
                        rhs[rhs_block_base + gi] <= rhs[rhs_block_base + gi] + $signed(pe_rhs_product_bus[gi*64 +: 64]);
                end
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k[4:0]) begin
                    if (refine_incremental_active) begin
                        acc_i <= 5'd0;
                        acc_j <= 5'd0;
                        rhs_block_base <= (refine_new_pos / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE;
                        state <= S_GRAM_PE_WAIT;
                    end else begin
                        rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                        acc_i <= 5'd0;
                        state <= S_ACC_PE_WAIT;
                    end
                end else begin
                    acc_i <= 5'd0;
                    acc_j <= refine_incremental_active ? refine_new_pos : 5'd0;
                    rhs_block_base <= 5'd0;
                    state <= S_GRAM_PE_WAIT;
                end
            end
            S_GRAM_PE_WAIT: begin
                state <= S_GRAM_PE_WAIT2;
            end
            S_GRAM_PE_WAIT2: begin
                state <= S_ACC_GRAM;
            end
            S_ACC_GRAM: begin
                for (gi = 0; gi < RHS_BLOCK_STRIDE; gi = gi + 1) begin
                    if (refine_incremental_active) begin
                        if ((rhs_block_base + gi) < active_k[4:0] && ((rhs_block_base + gi) <= refine_new_pos))
                            ge_mat[refine_new_pos][rhs_block_base + gi] <= ge_mat[refine_new_pos][rhs_block_base + gi] + $signed(pe_rhs_product_bus[gi*64 +: 64]);
                    end else if (((rhs_block_base + gi) < active_k[4:0]) && ((rhs_block_base + gi) >= acc_j)) begin
                        ge_mat[rhs_block_base + gi][acc_j] <= ge_mat[rhs_block_base + gi][acc_j] + $signed(pe_rhs_product_bus[gi*64 +: 64]);
                    end
                end
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k[4:0]) begin
                    if (refine_incremental_active) begin
                        rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                        acc_i <= 5'd0;
                        state <= S_GRAM_PE_WAIT;
                    end else begin
                        rhs_block_base <= rhs_block_base + RHS_BLOCK_STRIDE;
                        acc_i <= 5'd0;
                        state <= S_GRAM_PE_WAIT;
                    end
                end else if (acc_j + 5'd1 < active_k[4:0]) begin
                    if (refine_incremental_active) begin
                        acc_i <= 5'd0;
                        acc_j <= 5'd0;
                        rhs_block_base <= 5'd0;
                        if (write_idx + 1 >= write_limit) begin
                            state <= S_CACHE_BUILD;
                        end else begin
                            write_idx <= write_idx + 1'b1;
                            if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                                rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                            scan_col <= {IDX_W{1'b0}};
                            for (gi = 0; gi < MAX_K; gi = gi + 1)
                                phi_cache[gi] <= {DATA_W{1'b0}};
                            state <= (phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN;
                        end
                    end else begin
                    acc_j <= acc_j + 5'd1;
                    acc_i <= 5'd0;
                    rhs_block_base <= ((acc_j + 5'd1) / RHS_BLOCK_STRIDE) * RHS_BLOCK_STRIDE;
                    state <= S_GRAM_PE_WAIT;
                    end
                end else begin
                    acc_i <= 5'd0;
                    acc_j <= 5'd0;
                    rhs_block_base <= 5'd0;
                    if (write_idx + 1 >= write_limit) begin
                        state <= S_CACHE_BUILD;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                        if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                            rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                        scan_col <= {IDX_W{1'b0}};
                        for (gi = 0; gi < MAX_K; gi = gi + 1)
                            phi_cache[gi] <= {DATA_W{1'b0}};
                        state <= (phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN;
                    end
                end
            end
            S_CACHE_BUILD: begin
                refine_build_cache_valid <= 1'b1;
                refine_build_cache_k <= active_k;
                refine_cache_m_size <= m_size;
                refine_cache_n_size <= n_size;
                refine_cache_seed <= seed;
                refine_cache_scale_q <= scale_q;
                refine_cache_phi_kind <= phi_kind;
                cache_i <= 5'd0;
                cache_j <= 5'd0;
                state <= S_CACHE_BUILD_STEP;
            end
            S_CACHE_BUILD_STEP: begin
                ge_mat_build_cache[cache_i][cache_j] <= ge_mat[cache_i][cache_j];
                if (cache_j == 5'd0) begin
                    rhs_build_cache[cache_i] <= rhs[cache_i];
                    support_build_cache[cache_i] <= support_cache[cache_i];
                end
                if ((cache_i + 1'b1 >= MAX_K[4:0]) && (cache_j + 1'b1 >= MAX_K[4:0])) begin
                    cache_i <= 5'd0;
                    cache_j <= 5'd0;
                    state <= S_SOLVE_INIT;
                end else if (cache_j + 1'b1 >= MAX_K[4:0]) begin
                    cache_j <= 5'd0;
                    cache_i <= cache_i + 1'b1;
                end else begin
                    cache_j <= cache_j + 1'b1;
                end
            end
            S_WX: begin
                write_value <= write_value_now;
                if (write_idx + 1 >= write_limit) begin
                    write_idx <= {IDX_W{1'b0}};
                    phase_residual <= 1'b1;
                    write_limit <= m_size;
                    rd_addr <= 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    scan_col <= {IDX_W{1'b0}};
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    state <= (m_size == 0) ? S_DONE : ((phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN);
                end else begin
                    write_idx <= write_idx + 1'b1;
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
                if (rhs_block_base + RHS_BLOCK_STRIDE < active_k[4:0]) begin
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
                write_value <= write_value_now;
                if (write_idx + 1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    if ((write_idx[2:0] == 3'd7) && ((write_idx + 1'b1) < write_limit))
                        rd_addr <= 10'h100 + ((write_idx + 1'b1) >> 3);
                    scan_col <= {IDX_W{1'b0}};
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    state <= (phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN;
                end
            end
            S_SOLVE_INIT: begin
                for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                    ge_rhs[gi] <= rhs[gi];
                    ge_x[gi] <= 64'sd0;
                    coeff_mem[gi] <= {DATA_W{1'b0}};
                    for (gj = 0; gj < MAX_K; gj = gj + 1) begin
                        ge_mat[gi][gj] <= ((gi >= gj) ? ge_mat[gi][gj] : ge_mat[gj][gi]) + ((gi == gj) ? 64'sd1 : 64'sd0);
                    end
                end
                solve_i <= 5'd0;
                solve_j <= 5'd1;
                solve_k <= 5'd0;
                back_i <= (active_k == 0) ? 5'd0 : (active_k[4:0] - 5'd1);
                back_j <= 5'd0;
                ge_acc <= 64'sd0;
                state <= S_ELIM_START;
            end
            S_ELIM_START: begin
                if (solve_i >= active_k[4:0]) begin
                    back_i <= (active_k == 0) ? 5'd0 : (active_k[4:0] - 5'd1);
                    state <= S_BACK_INIT;
                end else begin
                    solve_j <= solve_i + 5'd1;
                    state <= S_ELIM_ROW;
                end
            end
            S_ELIM_ROW: begin
                if (solve_j >= active_k[4:0]) begin
                    solve_i <= solve_i + 5'd1;
                    state <= S_ELIM_START;
                end else begin
                    ge_div_num <= ge_mat[solve_j][solve_i] <<< 16;
                    ge_div_den <= (ge_mat[solve_i][solve_i] != 0) ? ge_mat[solve_i][solve_i] : 64'sd1;
                    solve_k <= solve_i;
                    state <= S_ELIM_PREP;
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
                ge_mat[solve_j][solve_k] <= ge_mul_a - $signed(ge_mul_p >>> 16);
                if (solve_k + 5'd1 >= active_k[4:0]) begin
                    ge_rhs[solve_j] <= ge_rhs[solve_j] - ((ge_factor * ge_mul_c) >>> 16);
                    solve_j <= solve_j + 5'd1;
                    state <= S_ELIM_ROW;
                end else begin
                    solve_k <= solve_k + 5'd1;
                    ge_mul_a <= ge_mat[solve_j][solve_k + 5'd1];
                    ge_mul_b <= ge_mat[solve_i][solve_k + 5'd1];
                    state <= S_ELIM_MUL;
                end
            end
            S_BACK_INIT: begin
                if (active_k == 0) begin
                    state <= S_SOLVE_DONE;
                end else begin
                    ge_acc <= 64'sd0;
                    back_j <= back_i + 5'd1;
                    state <= S_BACK_ACC;
                end
            end
            S_BACK_ACC: begin
                if (back_j >= active_k[4:0]) begin
                    state <= S_BACK_PREP;
                end else begin
                    ge_mul_a <= ge_mat[back_i][back_j];
                    ge_mul_b <= ge_x[back_j];
                    state <= S_BACK_MUL;
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
                ge_div_num <= (ge_rhs[back_i] - ge_acc) <<< 16;
                ge_div_den <= (ge_mat[back_i][back_i] != 0) ? ge_mat[back_i][back_i] : 64'sd1;
                state <= S_BACK_DIV;
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
                div_iter <= 7'd65;
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
                    if (div_iter <= 2) begin
                        if ({div_trial_rem[63:0], 1'b0} >= {1'b0, div_abs_den})
                            div_trial_quot = div_trial_quot + 1'b1;
                        div_result <= div_neg ? -$signed(div_trial_quot[63:0]) : $signed(div_trial_quot[63:0]);
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        state <= div_return_back ? S_BACK_DIV_DONE : (div_return_mp ? S_MP_DIV_DONE : S_ELIM_DIV_DONE);
                    end else begin
                        div_rem <= div_trial_rem;
                        div_quot <= div_trial_quot;
                        div_iter <= div_iter - 7'd2;
                    end
                end
            end
            S_ELIM_DIV_DONE: begin
                ge_factor <= div_result;
                ge_mul_a <= ge_mat[solve_j][solve_k];
                ge_mul_b <= ge_mat[solve_i][solve_k];
                ge_mul_c <= ge_rhs[solve_i];
                state <= S_ELIM_MUL;
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
                state <= S_MP_X_WAIT;
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
                mp_x_new_q <= sat_s24($signed(mp_x_old_q) + $signed(div_result));
                write_idx <= mp_idx_q;
                state <= S_MP_X_WRITE;
            end
            S_MP_X_WRITE: begin
                state <= S_DONE;
            end
            S_SOLVE_DONE: begin
                refine_incremental_active <= 1'b0;
                refine_skip_build_active <= 1'b0;
                write_idx <= {IDX_W{1'b0}};
                write_limit <= (active_op == OP_REFINE_SPARSE) ? active_k : n_size;
                phase_residual <= 1'b0;
                state <= S_WX;
            end
            S_CORR_INIT: begin
                corr_row <= {IDX_W{1'b0}};
                corr_scan_col <= {IDX_W{1'b0}};
                corr_acc <= 64'sd0;
                corr_phi_lane <= {COLS*DATA_W{1'b0}};
                corr_acc_lane <= {COLS*64{1'b0}};
                rd_addr <= 10'h080;
                phi_state_q <= corr_block_state;
                corr_row_state <= corr_block_state;
                corr_row_next_state <= lfsr_advance(corr_block_state, padded_n_q);
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
                state <= S_CORR_LATCH;
            end
            S_CORR_LATCH: begin
                for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1)
                    corr_acc_lane[corr_lane*64 +: 64] <= $signed(corr_acc_lane[corr_lane*64 +: 64]) + $signed(pe_rhs_product_bus[corr_lane*64 +: 64]);
                if (corr_row + 1 >= m_size) begin
                    write_idx <= corr_col;
                    state <= S_CORR_WRITE;
                end else begin
                    corr_row <= corr_row + 1'b1;
                    corr_row_state <= corr_row_next_state;
                    corr_row_next_state <= lfsr_advance(corr_row_next_state, padded_n_q);
                    rd_addr <= 10'h080 + ((corr_row + 1'b1) >> 3);
                    state <= S_CORR_SCAN;
                end
            end
            S_CORR_WRITE: begin
                corr_stream_valid_q <= busy;
                corr_stream_done_q <= (corr_col + COLS[IDX_W-1:0] >= n_size);
                corr_stream_base_idx_q <= corr_col;
                for (corr_lane = 0; corr_lane < COLS; corr_lane = corr_lane + 1) begin
                    corr_stream_lane_valid_q[corr_lane] <= ((corr_col + corr_lane[IDX_W-1:0]) < n_size);
                    corr_stream_data_q[corr_lane*DATA_W +: DATA_W] <= sat_s24($signed(corr_acc_lane[corr_lane*64 +: 64]) >>> 16);
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
                if (write_idx + 1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    rd_addr <= 10'h000 + ((write_idx + 1'b1) >> 3);
                    state <= S_IHT_X_READ;
                end
            end
            S_LOAD_COEFF_READ: begin
                state <= S_LOAD_COEFF_WAIT;
            end
            S_LOAD_COEFF_WAIT: begin
                state <= S_LOAD_COEFF_CAP;
            end
            S_LOAD_COEFF_CAP: begin
                coeff_mem[load_i] <= rd_data[load_support_q[2:0]*DATA_W +: DATA_W];
                if (load_i + 5'd1 >= active_k[4:0]) begin
                    write_idx <= {IDX_W{1'b0}};
                    write_limit <= m_size;
                    phase_residual <= 1'b1;
                    rd_addr <= 10'h100;
                    phi_state_q <= (|seed) ? seed : DEFAULT_SEED;
                    scan_col <= {IDX_W{1'b0}};
                    padded_n_q <= ((n_size + 7) >> 3) << 3;
                    for (gi = 0; gi < MAX_K; gi = gi + 1)
                        phi_cache[gi] <= {DATA_W{1'b0}};
                    state <= (phi_kind == 2'd0) ? S_SCAN_DIRECT : S_SCAN;
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
                if (write_idx + 1 >= write_limit) begin
                    state <= S_DONE;
                end else begin
                    write_idx <= write_idx + 1'b1;
                    rd_addr <= 10'h000 + ((write_idx + 1'b1) >> 3);
                    state <= S_PRUNE_X_READ;
                end
            end
            S_SCAN_DIRECT: begin
                phi_load_i <= 5'd0;
                state <= S_SCAN_DIRECT_STEP;
            end
            S_SCAN_DIRECT_STEP: begin
                if (phi_load_i < MAX_K[4:0]) begin
                    if (phi_load_i < active_k[4:0])
                        phi_cache[phi_load_i] <= phi_from_lfsr_state(lfsr_advance(phi_state_q, {1'b0, support_cache[phi_load_i]} + 1'b1));
                    else
                        phi_cache[phi_load_i] <= {DATA_W{1'b0}};
                end
                if (phi_load_i + 1'b1 >= MAX_K[4:0]) begin
                    phi_state_q <= lfsr_advance(phi_state_q, padded_n_q);
                    scan_col <= {IDX_W{1'b0}};
                    state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                end else begin
                    phi_load_i <= phi_load_i + 1'b1;
                end
            end
            S_SCAN: begin
                phi_state_next = galois_step(phi_state_q);
                scan_base_phi = phi_state_next[0] ? scale_q : ((~scale_q) + 1'b1);
                scan_hit_phi = scan_base_phi;
                for (gi = 0; gi < MAX_K; gi = gi + 1) begin
                    if ((gi < active_k) && (scan_col == support_cache[gi]))
                        phi_cache[gi] <= scan_hit_phi;
                end
                phi_state_q <= phi_state_next;
                if (scan_col + 1 >= padded_n_q) begin
                    state <= phase_residual ? S_WR_ACC_INIT : S_ACC;
                end else begin
                    scan_col <= scan_col + 1'b1;
                    state <= S_SCAN;
                end
            end
            S_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
                result <= {{(SCALAR_W-32){1'b0}}, accum_dbg};
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end
endmodule







