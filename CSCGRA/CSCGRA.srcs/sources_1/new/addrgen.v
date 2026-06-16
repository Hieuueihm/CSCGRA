module addrgen #(
    parameter integer COLS   = 8,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W  = 10,
    parameter integer CTX_W  = 64
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     start,
    input  wire [CTX_W-1:0]         ctx,
    input  wire [IDX_W-1:0]         m_size,
    input  wire [IDX_W-1:0]         n_size,
    input  wire [7:0]               k_param,

    output wire [IDX_W-1:0]         support_query_base,
    input  wire [COLS-1:0]          support_lane_mask,
    input  wire [COLS-1:0]          selected_lane_mask,
    input  wire [COLS-1:0]          spm_mask_byte,    // mode 7: SPM-driven lane mask

    output reg  [COLS*MEM_AW-1:0]   spm_a_addr,
    output reg  [COLS*MEM_AW-1:0]   spm_b_addr,
    output reg  [COLS*MEM_AW-1:0]   spm_w_addr,
    output reg  [COLS-1:0]          lane_valid,

    output reg  [IDX_W-1:0]         m_index,
    output reg  [IDX_W-1:0]         n_base,
    output reg  [IDX_W-1:0]         base_idx,
    output reg                      first_in_phase,
    output reg                      last_in_phase,
    output reg                      first_reduce,
    output reg                      last_reduce,
    output wire                     final_m_block,

    output reg                      lfsr_en,
    output reg                      lfsr_reseed,
    output reg                      lfsr_advance_masked,

    output reg                      valid,
    input  wire                     ready,
    output reg                      done
);

    localparam [3:0] ADDR_NONE = 4'd0;
    localparam [3:0] ADDR_M    = 4'd1;
    localparam [3:0] ADDR_N    = 4'd2;
    localparam [3:0] ADDR_MN   = 4'd3;
    localparam [IDX_W-1:0] COLS_STEP = COLS;

    wire [7:0]  lane_mask_lit;
    wire [3:0]  lane_mask_mode;
    wire [3:0]  addr_dim;
    wire [2:0]  spm_a_vec;
    wire [2:0]  spm_b_vec;
    wire [2:0]  spm_w_vec;
    wire [2:0]  spm_addr_mode;
    wire [9:0]  abs_addr;
    wire [3:0]  lfsr_ctrl;
    wire [3:0]  ext_ctrl;

    ctx_decoder #(.CTX_W(CTX_W)) u_decode (
        .ctx(ctx),
        .pe_op(),
        .src_a_sel(),
        .src_b_sel(),
        .rf_rd_addr(),
        .rf_wr_addr(),
        .rf_wr_en(),
        .acc_clear(),
        .acc_en(),
        .out_sel(),
        .spm_wr_en(),
        .spm_wr_data_sel(),
        .sb_sel(),
        .sb_sel_en(),
        .row_en(),
        .imm16(),
        .lane_mask_lit(lane_mask_lit),
        .lane_mask_mode(lane_mask_mode),
        .ext_ctrl(ext_ctrl),
        .ctx_ver(),
        .uop_class(),
        .repeat_sel(),
        .addr_dim(addr_dim),
        .spm_a_vec(spm_a_vec),
        .spm_b_vec(spm_b_vec),
        .spm_w_vec(spm_w_vec),
        .spm_addr_mode(spm_addr_mode),
        .abs_addr(abs_addr),
        .lfsr_ctrl(lfsr_ctrl),
        .reduce_op(),
        .reduce_src_vec(),
        .reduce_dst(),
        .scalar_op(),
        .next_ctrl(),
        .ctx_version_ok(),
        .ctx_decode_error()
    );

    function [MEM_AW-1:0] vec_base;
        input [2:0] vec_id;
        begin
            case (vec_id)
                3'd0: vec_base = 10'h000;
                3'd1: vec_base = 10'h080;
                3'd2: vec_base = 10'h100;
                3'd3: vec_base = 10'h180;
                3'd4: vec_base = 10'h200;
                3'd5: vec_base = 10'h280;
                3'd6: vec_base = 10'h300;
                3'd7: vec_base = 10'h380;
                default: vec_base = {MEM_AW{1'b0}};
            endcase
        end
    endfunction

    function [MEM_AW-1:0] bank_addr;
        input [2:0] vec_id;
        input [IDX_W-1:0] index;
        begin
            if (spm_addr_mode == 3'd5)
                bank_addr = abs_addr[MEM_AW-1:0];
            else
                bank_addr = vec_base(vec_id) + index[IDX_W-1:3];
        end
    endfunction

    function [MEM_AW-1:0] bank_addr_m;
        input [2:0] vec_id;
        begin
            bank_addr_m = vec_base(vec_id) + m_index[IDX_W-1:3];
        end
    endfunction

    function [MEM_AW-1:0] bank_addr_mn;
        input [2:0] vec_id;
        input [IDX_W-1:0] index;
        reg [IDX_W-1:0] n_blocks;
        begin
            n_blocks = (n_size[IDX_W-1:3]) + ((|n_size[2:0]) ? {{(IDX_W-1){1'b0}}, 1'b1} : {IDX_W{1'b0}});
            if (n_blocks == {IDX_W{1'b0}})
                n_blocks = {{(IDX_W-1){1'b0}}, 1'b1};
            bank_addr_mn = vec_base(vec_id) + ((m_index * n_blocks) & {IDX_W{1'b1}}) + index[IDX_W-1:3];
        end
    endfunction

    integer i;
    reg [IDX_W-1:0] lane_idx_mask;
    reg [IDX_W-1:0] lane_idx_addr;
    reg [IDX_W-1:0] mask_base;
    reg [COLS-1:0] mask_next;
    reg functional_lane;
    reg bound_lane;
    reg [IDX_W-1:0] n_blocks_comb;
    reg [IDX_W-1:0] matrix_row_base;

    assign support_query_base = mask_base;

    wire [IDX_W-1:0] active_limit =
        (addr_dim == ADDR_M)  ? m_size :
        (addr_dim == ADDR_N)  ? n_size :
        (addr_dim == ADDR_MN) ? n_size :
                                {{(IDX_W-1){1'b0}}, 1'b1};

    wire [IDX_W-1:0] next_n_base = n_base + COLS_STEP;
    wire last_n_block = (next_n_base >= active_limit);
    wire last_m_block = (m_index + {{(IDX_W-1){1'b0}}, 1'b1} >= m_size);
    assign final_m_block = (addr_dim == ADDR_MN) ? (m_index + {{(IDX_W-1){1'b0}}, 1'b1} == m_size) : last_reduce;

    always @(*) begin
        mask_base = start ? {IDX_W{1'b0}} :
                    (addr_dim == ADDR_MN) ? base_idx :
                    (valid && ready && !last_in_phase && addr_dim != ADDR_NONE) ? next_n_base :
                    base_idx;
        mask_next = {COLS{1'b1}};
        for (i = 0; i < COLS; i = i + 1) begin
            lane_idx_mask = mask_base + i;
            case (lane_mask_mode)
                4'd0: functional_lane = 1'b1;
                4'd1: functional_lane = support_lane_mask[i];
                4'd2: functional_lane = selected_lane_mask[i];
                4'd3: functional_lane = !selected_lane_mask[i];
                4'd4: functional_lane = support_lane_mask[i] && !selected_lane_mask[i];
                4'd5: functional_lane = 1'b0;
                4'd6: functional_lane = (i == 0);
                4'd7: functional_lane = spm_mask_byte[i];  // SPM-byte mask
                default: functional_lane = 1'b0;
            endcase
            bound_lane = (addr_dim == ADDR_NONE) ? 1'b1 : (lane_idx_mask < active_limit);
            mask_next[i] = functional_lane && bound_lane;
        end
    end

    always @(*) begin
        n_blocks_comb = n_size[IDX_W-1:3] + ((|n_size[2:0]) ? {{(IDX_W-1){1'b0}}, 1'b1} : {IDX_W{1'b0}});
        if (n_blocks_comb == {IDX_W{1'b0}})
            n_blocks_comb = {{(IDX_W-1){1'b0}}, 1'b1};
        matrix_row_base = vec_base(spm_a_vec) + (m_index * n_blocks_comb);
        for (i = 0; i < COLS; i = i + 1) begin
            lane_idx_addr = base_idx + i;
            if (ext_ctrl[0] && (addr_dim == ADDR_MN) && (spm_a_vec == 3'd7))
                spm_a_addr[i*MEM_AW +: MEM_AW] = matrix_row_base[MEM_AW-1:0] + lane_idx_addr[IDX_W-1:3];
            else
                spm_a_addr[i*MEM_AW +: MEM_AW] = bank_addr(spm_a_vec, lane_idx_addr);
            spm_b_addr[i*MEM_AW +: MEM_AW] = (ext_ctrl[0] || (spm_addr_mode == 3'd6)) ? bank_addr_m(spm_b_vec) : bank_addr(spm_b_vec, lane_idx_addr);
            spm_w_addr[i*MEM_AW +: MEM_AW] = bank_addr(spm_w_vec, lane_idx_addr);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_index             <= {IDX_W{1'b0}};
            n_base              <= {IDX_W{1'b0}};
            base_idx            <= {IDX_W{1'b0}};
            lane_valid          <= {COLS{1'b0}};
            first_in_phase      <= 1'b0;
            last_in_phase       <= 1'b0;
            first_reduce        <= 1'b0;
            last_reduce         <= 1'b0;
            lfsr_en             <= 1'b0;
            lfsr_reseed         <= 1'b0;
            lfsr_advance_masked <= 1'b0;
            valid               <= 1'b0;
            done                <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start) begin
                m_index        <= {IDX_W{1'b0}};
                n_base         <= {IDX_W{1'b0}};
                base_idx       <= {IDX_W{1'b0}};
                lane_valid     <= mask_next;
                first_in_phase <= 1'b1;
                first_reduce   <= 1'b1;
                last_in_phase  <= (addr_dim == ADDR_NONE) ? 1'b1 : ((active_limit <= COLS_STEP) && (addr_dim != ADDR_MN));
                last_reduce    <= (addr_dim != ADDR_MN) ? 1'b1 : ((m_size <= 1) && (n_size <= COLS_STEP));
                lfsr_en        <= lfsr_ctrl[0] && !lfsr_ctrl[3];
                lfsr_reseed    <= lfsr_ctrl[1];
                lfsr_advance_masked <= lfsr_ctrl[2];
                valid          <= 1'b1;
            end else if (valid && ready) begin
                first_in_phase <= 1'b0;
                first_reduce   <= 1'b0;
                lfsr_reseed    <= 1'b0;

                if (last_in_phase || addr_dim == ADDR_NONE) begin
                    valid <= 1'b0;
                    done  <= 1'b1;
                    lfsr_en <= 1'b0;
                end else begin
                    if (addr_dim == ADDR_MN) begin
                        first_reduce <= (m_index == {IDX_W{1'b0}});
                        if (last_n_block) begin
                            n_base  <= {IDX_W{1'b0}};
                            base_idx <= {IDX_W{1'b0}};
                            m_index <= m_index + 1'b1;
                            last_in_phase <= last_m_block;
                            last_reduce <= last_m_block;
                        end else begin
                            n_base  <= next_n_base;
                            base_idx <= next_n_base;
                            last_in_phase <= 1'b0;
                            last_reduce <= 1'b0;
                        end
                    end else begin
                        n_base  <= next_n_base;
                        base_idx <= next_n_base;
                        last_in_phase <= (next_n_base >= active_limit);
                        last_reduce <= 1'b1;
                    end
                    lane_valid <= mask_next;
                    lfsr_en <= lfsr_ctrl[0] && !lfsr_ctrl[3];
                end
            end else if (!valid) begin
                lane_valid <= {COLS{1'b0}};
                lfsr_en <= 1'b0;
                lfsr_reseed <= 1'b0;
            end
        end
    end

endmodule




