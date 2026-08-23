module sequencer #(
    parameter integer CTX_W  = 64,
    parameter integer CTX_AW = 6,
    parameter integer IDX_W  = 10,
    parameter integer NCTX   = 64
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 start,
    input  wire [CTX_AW-1:0]    prog_base,
    input  wire [CTX_AW:0]      prog_len,
    input  wire [IDX_W-1:0]     m_size,
    input  wire [IDX_W-1:0]     n_size,
    input  wire [7:0]           k_param,
    input  wire [15:0]          max_iter,
    input  wire [31:0]          tol_sq_q16_16,

    output reg  [CTX_AW-1:0]    ctx_addr,
    input  wire [CTX_W-1:0]     ctx_rdata,

    output reg                  ctx_valid,
    output reg  [CTX_W-1:0]     ctx_word,
    output reg                  phase_start,
    output reg                  support_clear_selected,
    input  wire                 ctx_done,
    input  wire                 ctx_decode_error,


    input  wire                 dma_done,
    input  wire                 compute_done,
    input  wire                 reduce_done,
    input  wire                 argmax_done,
    input  wire                 scalar_done,
    input  wire                 reduce_converged,
    input  wire                 scalar_cmp_true,
    input  wire                 dma_error,
    input  wire [3:0]           dma_error_code,
    input  wire                 scalar_error,

    output reg                  busy,
    output reg                  done,
    output reg                  irq,
    output reg                  converged,
    output reg                  error,
    output reg  [3:0]           error_code,
    output reg  [CTX_AW-1:0]    pc_dbg
);

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_FETCH  = 3'd1;
    localparam [2:0] S_FETCH_WAIT = 3'd2;
    localparam [2:0] S_DECODE = 3'd3;
    localparam [2:0] S_CLEAR  = 3'd4;
    localparam [2:0] S_ISSUE  = 3'd5;
    localparam [2:0] S_WAIT   = 3'd6;
    localparam [2:0] S_RETIRE = 3'd7;
    localparam [3:0] S_ERROR  = 4'd8;

    localparam [3:0] ERR_NONE     = 4'd0;
    localparam [3:0] ERR_CTX_VER  = 4'd1;
    localparam [3:0] ERR_PC_RANGE = 4'd2;
    localparam [3:0] ERR_DMA      = 4'd3;
    localparam [3:0] ERR_SCALAR   = 4'd4;
    localparam [3:0] ERR_TIMEOUT  = 4'd5;
    // S_WAIT watchdog bound.  The longest legitimate single context op is an
    // LDLT factorization at K16 (~5e4 clocks); 2**26 clocks at 100 MHz is
    // >0.6 s, far beyond any legal wait, so firing can only mean a lost
    // completion pulse or a wedged engine.
    localparam [26:0] WAIT_TIMEOUT_LIMIT = 27'h400_0000;

    localparam [3:0] UOP_ARGMAX    = 4'd5;
    localparam [3:0] UOP_CTRL      = 4'd9;
    localparam [3:0] NEXT_END_PROG = 4'd6;

    localparam [3:0] CF_NOP            = 4'd0;
    localparam [3:0] CF_JUMP_ABS       = 4'd1;
    localparam [3:0] CF_JUMP_REL       = 4'd2;
    localparam [3:0] CF_LOOP           = 4'd3;
    localparam [3:0] CF_COND_END       = 4'd4;
    localparam [3:0] CF_COND_JUMP_ABS  = 4'd5;
    localparam [3:0] CF_COND_JUMP_REL  = 4'd6;

    reg [3:0] state;
    // Counts consecutive S_WAIT clocks; see WAIT_TIMEOUT_LIMIT.
    reg [26:0] wait_timeout_cnt;
    reg [CTX_AW-1:0] pc;
    reg [CTX_AW:0] prog_len_q;
    reg [7:0] loop_counter [0:3];
    // Two views of the fetched word.  fetched_uop reads the configmem output
    // register (ctx_rdata) and is only valid in S_DECODE, the cycle ctx_word
    // captures it; issued_uop reads the registered ctx_word from S_ISSUE
    // onward.  They are identical because ctx_addr is held until S_RETIRE and
    // configmem has a single-cycle read latency.  The S_ISSUE assertion below
    // verifies the invariant; changing the fetch pipeline depth requires
    // revisiting both views.
    wire [3:0] fetched_uop = ctx_rdata[59:56];
    wire [3:0] issued_uop = ctx_word[59:56];
    wire [3:0] current_next_ctrl = ctx_word[47:44];
    wire [CTX_AW:0] pc_offset = {1'b0, (pc - prog_base)};
    wire normal_pc_ok = (pc >= prog_base) && (pc_offset < prog_len_q) && (prog_len_q != 0);
    wire normal_pc_last = ((pc_offset + 1'b1) >= prog_len_q);
    wire [CTX_AW:0] prog_end = {1'b0, prog_base} + prog_len;
    wire prog_range_ok = (prog_len != 0) && (prog_end <= NCTX);

    wire [3:0] ctrl_op = ctx_word[43:40];
    wire [CTX_AW-1:0] ctrl_abs_pc = ctx_word[39:34];
    wire [5:0] ctrl_rel_off = ctx_word[33:28];
    wire [CTX_AW-1:0] ctrl_rel_mag = {{(CTX_AW-6){1'b0}}, ((~ctrl_rel_off) + 1'b1)};
    wire [CTX_AW-1:0] ctrl_rel_pos = {{(CTX_AW-6){1'b0}}, ctrl_rel_off};
    wire [CTX_AW-1:0] ctrl_rel_pc =
        ctrl_rel_off[5] ? (pc - ctrl_rel_mag) : (pc + ctrl_rel_pos);
    wire [7:0] ctrl_loop_count_imm = ctx_word[27:20];
    wire [7:0] ctrl_loop_load_count =
        (ctrl_loop_count_imm != 8'd0) ? ctrl_loop_count_imm : max_iter[7:0];
    wire [1:0] ctrl_loop_id = ctx_word[19:18];
    wire [7:0] ctrl_loop_active_count = loop_counter[ctrl_loop_id];
    wire [7:0] ctrl_loop_work_count =
        (ctrl_loop_active_count == 8'd0) ? ctrl_loop_load_count : ctrl_loop_active_count;
    wire [1:0] ctrl_cond_sel = ctx_word[17:16];
    wire ctrl_cond_invert = ctx_word[15];
    wire ctrl_cond_raw =
        (ctrl_cond_sel == 2'd0) ? reduce_converged :
        (ctrl_cond_sel == 2'd1) ? scalar_cmp_true :
        (ctrl_cond_sel == 2'd2) ? (reduce_converged | scalar_cmp_true | converged) :
                                  1'b1;
    wire ctrl_cond_true = ctrl_cond_invert ? !ctrl_cond_raw : ctrl_cond_raw;
    wire ctrl_loop_take = (ctrl_op == CF_LOOP) && (ctrl_loop_work_count > 8'd1);
    wire ctrl_op_uses_rel = (ctrl_op == CF_JUMP_REL) ||
                            ((ctrl_op == CF_LOOP) && ctrl_loop_take) ||
                            ((ctrl_op == CF_COND_JUMP_REL) && ctrl_cond_true);
    wire [CTX_AW-1:0] ctrl_target_pc = ctrl_op_uses_rel ? ctrl_rel_pc : ctrl_abs_pc;
    wire [CTX_AW:0] ctrl_target_offset = {1'b0, (ctrl_target_pc - prog_base)};
    wire ctrl_target_ok = (ctrl_target_pc >= prog_base) &&
                          (ctrl_target_offset < prog_len_q) &&
                          (prog_len_q != 0);
    wire ctrl_take_branch =
        (ctrl_op == CF_JUMP_ABS) ||
        (ctrl_op == CF_JUMP_REL) ||
        ctrl_loop_take ||
        ((ctrl_op == CF_COND_JUMP_ABS) && ctrl_cond_true) ||
        ((ctrl_op == CF_COND_JUMP_REL) && ctrl_cond_true);
    wire ctrl_need_target = ctrl_take_branch;
    wire ctrl_cond_end = (ctrl_op == CF_COND_END) && ctrl_cond_true;

    integer loop_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            pc <= {CTX_AW{1'b0}};
            prog_len_q <= {(CTX_AW+1){1'b0}};
            ctx_addr <= {CTX_AW{1'b0}};
            ctx_valid <= 1'b0;
            ctx_word <= {CTX_W{1'b0}};
            phase_start <= 1'b0;
            support_clear_selected <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            irq <= 1'b0;
            converged <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
            wait_timeout_cnt <= 27'd0;
            pc_dbg <= {CTX_AW{1'b0}};
            for (loop_i = 0; loop_i < 4; loop_i = loop_i + 1)
                loop_counter[loop_i] <= 8'd0;
        end else begin
            ctx_valid <= 1'b0;
            phase_start <= 1'b0;
            support_clear_selected <= 1'b0;
            done <= 1'b0;
            irq <= 1'b0;
            if (dma_error) begin
                error <= 1'b1;
                error_code <= (dma_error_code == ERR_NONE) ? ERR_DMA : dma_error_code;
                state <= S_ERROR;
            end else if (scalar_error) begin
                error <= 1'b1;
                error_code <= ERR_SCALAR;
                state <= S_ERROR;
            end else begin
                case (state)
                    S_IDLE: begin
                        busy <= 1'b0;
                        wait_timeout_cnt <= 27'd0;
                        if (start) begin
                            if (!prog_range_ok) begin
                                error <= 1'b1;
                                error_code <= ERR_PC_RANGE;
                                busy <= 1'b0;
                                irq <= 1'b1;
                                state <= S_ERROR;
                            end else begin
                                pc <= prog_base;
                                prog_len_q <= prog_len;
                                pc_dbg <= prog_base;
                                error <= 1'b0;
                                error_code <= ERR_NONE;
                                converged <= 1'b0;
                                busy <= 1'b1;
                                for (loop_i = 0; loop_i < 4; loop_i = loop_i + 1)
                                    loop_counter[loop_i] <= 8'd0;
                                ctx_addr <= prog_base;
                                state <= S_FETCH_WAIT;
                            end
                        end
                    end
                    S_FETCH: begin
                        if (!normal_pc_ok) begin
                            error <= 1'b1;
                            error_code <= ERR_PC_RANGE;
                            state <= S_ERROR;
                        end else begin
                            ctx_addr <= pc;
                            pc_dbg <= pc;
                            state <= S_FETCH_WAIT;
                        end
                    end
                    S_FETCH_WAIT: begin
                        state <= S_DECODE;
                    end
                    S_DECODE: begin
                        ctx_word <= ctx_rdata;
                        if (ctx_decode_error) begin
                            error <= 1'b1;
                            error_code <= ERR_CTX_VER;
                            state <= S_ERROR;
                        end else if (fetched_uop == UOP_ARGMAX) begin
                            state <= S_CLEAR;
                        end else begin
                            state <= S_ISSUE;
                        end
                    end
                    S_CLEAR: begin
                        support_clear_selected <= 1'b1;
                        state <= S_ISSUE;
                    end
                    S_ISSUE: begin
                        if (issued_uop == UOP_CTRL) begin
                            state <= S_RETIRE;
                        end else begin
                            ctx_valid <= 1'b1;
                            phase_start <= 1'b1;
                            state <= S_WAIT;
                        end
                    end
                    S_WAIT: begin
                        // Watchdog: a lost completion pulse or a wedged
                        // engine would otherwise hang the program forever.
                        // Any legal op finishes orders of magnitude below
                        // WAIT_TIMEOUT_LIMIT, so this never fires in a
                        // healthy run and the cycle schedule is unchanged.
                        wait_timeout_cnt <= wait_timeout_cnt + 1'b1;
                        if (wait_timeout_cnt >= WAIT_TIMEOUT_LIMIT) begin
                            error <= 1'b1;
                            error_code <= ERR_TIMEOUT;
                            state <= S_ERROR;
                        end else if (ctx_done) begin
                            wait_timeout_cnt <= 27'd0;
                            state <= S_RETIRE;
                        end
                    end
                    S_RETIRE: begin
                        if (issued_uop == UOP_CTRL) begin
                            if (ctrl_op == CF_LOOP) begin
                                if (ctrl_loop_take)
                                    loop_counter[ctrl_loop_id] <= ctrl_loop_work_count - 1'b1;
                                else
                                    loop_counter[ctrl_loop_id] <= 8'd0;
                            end

                            if (ctrl_cond_end) begin
                                converged <= 1'b1;
                                busy <= 1'b0;
                                done <= 1'b1;
                                irq <= 1'b1;
                                state <= S_IDLE;
                            end else if (ctrl_need_target && !ctrl_target_ok) begin
                                error <= 1'b1;
                                error_code <= ERR_PC_RANGE;
                                state <= S_ERROR;
                            end else if (ctrl_take_branch) begin
                                pc <= ctrl_target_pc;
                                ctx_addr <= ctrl_target_pc;
                                pc_dbg <= ctrl_target_pc;
                                state <= S_FETCH_WAIT;
                            end else if (current_next_ctrl == NEXT_END_PROG ||
                                         normal_pc_last) begin
                                busy <= 1'b0;
                                done <= 1'b1;
                                irq <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                pc <= pc + 1'b1;
                                ctx_addr <= pc + 1'b1;
                                pc_dbg <= pc + 1'b1;
                                state <= S_FETCH_WAIT;
                            end
                        end else if (current_next_ctrl == NEXT_END_PROG ||
                                     normal_pc_last) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            irq <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            pc <= pc + 1'b1;
                                ctx_addr <= pc + 1'b1;
                                pc_dbg <= pc + 1'b1;
                                state <= S_FETCH_WAIT;
                        end
                    end
                    S_ERROR: begin
                        busy <= 1'b0;
                        irq <= 1'b1;
                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    // S_DECODE decides on the configmem output view while S_ISSUE/S_RETIRE
    // decide on the registered view.  Fail loudly if a fetch-pipeline change
    // ever breaks their equality instead of silently mis-stepping.
    always @(posedge clk) begin
        if (rst_n && (state == S_ISSUE) && (fetched_uop != issued_uop))
            $error("sequencer fetch views diverged at S_ISSUE: ctx_rdata uop=%h ctx_word uop=%h",
                   fetched_uop, issued_uop);
    end
`endif

endmodule



