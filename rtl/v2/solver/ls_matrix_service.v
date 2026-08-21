`timescale 1ns/1ps

// Eight row banks hold the regularized Cholesky LDLT matrix. READ4/WRITE4 use
// four distinct row banks. ACC4 captures the products from all four physical
// PE rows once, then drains the four Gram columns into the row banks while the
// controller prepares the next batch. ACC4 intentionally exposes only one
// active transaction: the producer advances on done before issuing another
// token. Keeping the wide payload row-stationary removes the former 2048-bit
// pending queue, its promotion mux and its 1.8k-load capture enables. The
// small drain latency is traded for lower congestion and deterministic timing.
module ls_matrix_service #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 56,
    parameter integer FACTOR_W = 64,
    parameter integer RHS_W = 64,
    parameter integer FRAC_W = 16,
    parameter integer LANES = 8,
    parameter integer ENABLE_ROW_UPDATE_BLOCK = 0,
    parameter integer ROW_UPDATE_LANES = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [3:0]                   op,
    input  wire [4:0]                   row_a,
    input  wire [4:0]                   col_a,
    input  wire [4:0]                   row_b,
    input  wire [4:0]                   col_b,
    input  wire [4:0]                   row_base,
    input  wire [LANES-1:0]             lane_valid,
    input  wire                         row_update_block,
    input  wire signed [LANES*64-1:0]   lane_add,
    input  wire signed [4*LANES*64-1:0] lane_add4,
    input  wire [4*LANES-1:0]           acc4_lane_valid,
    input  wire [3:0]                   acc4_col_valid,
    input  wire signed [GE_W-1:0]       wdata,
    input  wire signed [4*GE_W-1:0]     write4_wdata,
    input  wire [3:0]                   write4_valid,
    input  wire signed [FACTOR_W-1:0]   factor,
    input  wire signed [RHS_W-1:0]      rhs_wdata,
    output reg                          busy,
    output reg                          done,
    output reg                          acc4_credit,
    output reg signed [GE_W-1:0]        rdata_a,
    output reg signed [GE_W-1:0]        rdata_b,
    output reg signed [4*GE_W-1:0]      read4_rdata,
    output reg signed [GE_W-1:0]        update_value,
    output reg signed [RHS_W-1:0]       rhs_rdata
);
    localparam [3:0] OP_CLEAR      = 4'd0;
    localparam [3:0] OP_WRITE      = 4'd1;
    localparam [3:0] OP_READ2      = 4'd2;
    localparam [3:0] OP_ACC_BLOCK  = 4'd3;
    localparam [3:0] OP_ROW_UPDATE = 4'd4;
    localparam [3:0] OP_RHS_WRITE  = 4'd5;
    localparam [3:0] OP_RHS_READ   = 4'd6;
    localparam [3:0] OP_RHS_UPDATE = 4'd7;
    localparam [3:0] OP_READ4      = 4'd8;
    localparam [3:0] OP_WRITE4     = 4'd9;
    localparam [3:0] OP_ACC4       = 4'd10;
    localparam [3:0] OP_CLEAR_ROW  = 4'd11;

    localparam [2:0] S_IDLE=3'd0, S_CLEAR=3'd1, S_CLEAR_ROW=3'd2,
                     S_DONE=3'd4, S_ACC4=3'd5;
    localparam integer ROW_BANKS = 8;
    localparam integer COL_BANKS = 1;
    localparam integer BANK_DEPTH = (MAX_K/ROW_BANKS)*MAX_K;
    localparam integer MAT_AW = $clog2(BANK_DEPTH);

    reg [2:0] state;
    reg [MAT_AW-1:0] clear_addr_q;
    reg [4:0] clear_row_q;
    reg [4:0] clear_col_q;
    reg [1:0] acc4_drain_col_q;
    reg [4:0] acc4_col_base_q;
    reg [4:0] acc4_row_base_q;
    reg signed [LANES*64-1:0] acc4_column_add_q;
    reg [LANES-1:0] acc4_column_valid_q;
    reg signed [LANES*64-1:0] acc4_prefetch_add_w;
    reg [LANES-1:0] acc4_prefetch_valid_w;
    wire [4*LANES-1:0] acc4_effective_lane_valid_w =
        acc4_lane_valid & {{LANES{acc4_col_valid[3]}},
                           {LANES{acc4_col_valid[2]}},
                           {LANES{acc4_col_valid[1]}},
                           {LANES{acc4_col_valid[0]}}};

    always @* begin
        case (acc4_drain_col_q)
            2'd0: begin
                acc4_prefetch_add_w = lane_add4[LANES*64 +: LANES*64];
                acc4_prefetch_valid_w = acc4_effective_lane_valid_w[LANES +: LANES];
            end
            2'd1: begin
                acc4_prefetch_add_w = lane_add4[2*LANES*64 +: LANES*64];
                acc4_prefetch_valid_w = acc4_effective_lane_valid_w[2*LANES +: LANES];
            end
            default: begin
                acc4_prefetch_add_w = lane_add4[3*LANES*64 +: LANES*64];
                acc4_prefetch_valid_w = acc4_effective_lane_valid_w[3*LANES +: LANES];
            end
        endcase
    end

    wire [4:0] read4_row0 = row_a;
    wire [4:0] read4_row1 = row_a + 5'd1;
    wire [4:0] read4_row2 = row_a + 5'd2;
    wire [4:0] read4_row3 = row_a + 5'd3;

    wire signed [ROW_BANKS*COL_BANKS*GE_W-1:0] bank_read_a;
    wire signed [ROW_BANKS*COL_BANKS*GE_W-1:0] bank_read_b;

    function [MAT_AW-1:0] matrix_addr;
        input [4:0] row;
        input [4:0] col;
        begin
            matrix_addr = ((row >> 3) * MAX_K) + col;
        end
    endfunction

    function signed [GE_W-1:0] add_to_ge;
        input signed [GE_W-1:0] cur;
        input signed [63:0] addend;
        reg signed [63:0] cur_ext;
        begin
            cur_ext = {{(64-GE_W){cur[GE_W-1]}},cur};
            add_to_ge = cur_ext + addend;
        end
    endfunction

    (* ram_style = "distributed" *) reg signed [RHS_W-1:0] rhs_mem [0:MAX_K-1];

    genvar rb, cb;
    generate
        for (rb=0; rb<ROW_BANKS; rb=rb+1) begin : gen_row_bank
            for (cb=0; cb<COL_BANKS; cb=cb+1) begin : gen_col_bank
                localparam integer FLAT_BANK = rb*COL_BANKS+cb;
                (* ram_style = "distributed" *) reg signed [GE_W-1:0] mem_a [0:BANK_DEPTH-1];
                (* ram_style = "distributed" *) reg signed [GE_W-1:0] mem_b [0:BANK_DEPTH-1];

                wire read4_hit0 = (read4_row0[2:0] == rb[2:0]);
                wire read4_hit1 = (read4_row1[2:0] == rb[2:0]);
                wire read4_hit2 = (read4_row2[2:0] == rb[2:0]);
                wire [4:0] read4_row_sel = read4_hit0 ? read4_row0 :
                                           read4_hit1 ? read4_row1 :
                                           read4_hit2 ? read4_row2 : read4_row3;
                wire [MAT_AW-1:0] read_addr_a = (op == OP_READ4) ?
                    matrix_addr(read4_row_sel,col_a) : matrix_addr(row_a,col_a);
                wire [MAT_AW-1:0] read_addr_b = matrix_addr(row_b,col_b);

                wire write4_hit0 = write4_valid[0] && (read4_row0[2:0] == rb[2:0]);
                wire write4_hit1 = write4_valid[1] && (read4_row1[2:0] == rb[2:0]);
                wire write4_hit2 = write4_valid[2] && (read4_row2[2:0] == rb[2:0]);
                wire write4_hit3 = write4_valid[3] && (read4_row3[2:0] == rb[2:0]);
                wire [1:0] write4_lane = write4_hit0 ? 2'd0 : write4_hit1 ? 2'd1 :
                                         write4_hit2 ? 2'd2 : 2'd3;
                wire [4:0] write4_row = write4_lane==0 ? read4_row0 :
                                        write4_lane==1 ? read4_row1 :
                                        write4_lane==2 ? read4_row2 : read4_row3;
                wire [4:0] acc4_col = acc4_col_base_q + {3'd0,acc4_drain_col_q};
                wire [4:0] acc4_row = acc4_row_base_q + rb[4:0];

                always @(posedge clk) begin
                    if (state == S_CLEAR) begin
                        mem_a[clear_addr_q] <= {GE_W{1'b0}};
                        mem_b[clear_addr_q] <= {GE_W{1'b0}};
                    end else if ((state == S_CLEAR_ROW) &&
                                 (clear_row_q[2:0] == rb[2:0])) begin
                        // Delta-SWAP invalidates exactly one lower-triangle
                        // border. Clearing it serially keeps the bank write
                        // ports unchanged and costs at most MAX_K clocks.
                        mem_a[matrix_addr(clear_row_q,clear_col_q)] <= {GE_W{1'b0}};
                        mem_b[matrix_addr(clear_row_q,clear_col_q)] <= {GE_W{1'b0}};
                    end else if ((state == S_ACC4) && acc4_column_valid_q[rb]) begin
                        mem_a[matrix_addr(acc4_row,acc4_col)] <= add_to_ge(
                            mem_a[matrix_addr(acc4_row,acc4_col)],
                            $signed(acc4_column_add_q[rb*64 +: 64]));
                        mem_b[matrix_addr(acc4_row,acc4_col)] <= add_to_ge(
                            mem_a[matrix_addr(acc4_row,acc4_col)],
                            $signed(acc4_column_add_q[rb*64 +: 64]));
                    end else if ((state == S_IDLE) && start && (op == OP_ACC_BLOCK) &&
                                 lane_valid[rb]) begin
                        mem_a[matrix_addr(row_base+rb[4:0],col_a)] <= add_to_ge(
                            mem_a[matrix_addr(row_base+rb[4:0],col_a)],
                            $signed(lane_add[rb*64 +: 64]));
                        mem_b[matrix_addr(row_base+rb[4:0],col_a)] <= add_to_ge(
                            mem_a[matrix_addr(row_base+rb[4:0],col_a)],
                            $signed(lane_add[rb*64 +: 64]));
                    end else if ((state == S_IDLE) && start && (op == OP_WRITE) &&
                                 (row_a[2:0] == rb[2:0])) begin
                        mem_a[matrix_addr(row_a,col_a)] <= wdata;
                        mem_b[matrix_addr(row_a,col_a)] <= wdata;
                    end else if ((state == S_IDLE) && start && (op == OP_WRITE4) &&
                                 (write4_hit0 || write4_hit1 || write4_hit2 || write4_hit3)) begin
                        mem_a[matrix_addr(write4_row,col_a)] <= write4_wdata[write4_lane*GE_W +: GE_W];
                        mem_b[matrix_addr(write4_row,col_a)] <= write4_wdata[write4_lane*GE_W +: GE_W];
                    end
                end

                assign bank_read_a[FLAT_BANK*GE_W +: GE_W] = mem_a[read_addr_a];
                assign bank_read_b[FLAT_BANK*GE_W +: GE_W] = mem_b[read_addr_b];
            end
        end
    endgenerate

    integer clear_i;
    integer read_lane_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            clear_addr_q <= {MAT_AW{1'b0}};
            clear_row_q <= 5'd0;
            clear_col_q <= 5'd0;
            acc4_drain_col_q <= 2'd0;
            acc4_col_base_q <= 5'd0;
            acc4_row_base_q <= 5'd0;
            acc4_column_add_q <= {LANES*64{1'b0}};
            acc4_column_valid_q <= {LANES{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            acc4_credit <= 1'b0;
            rdata_a <= {GE_W{1'b0}};
            rdata_b <= {GE_W{1'b0}};
            read4_rdata <= {4*GE_W{1'b0}};
            update_value <= {GE_W{1'b0}};
            rhs_rdata <= {RHS_W{1'b0}};
            for (clear_i=0; clear_i<MAX_K; clear_i=clear_i+1)
                rhs_mem[clear_i] <= {RHS_W{1'b0}};
        end else begin
            done <= 1'b0;
            acc4_credit <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        case (op)
                            OP_CLEAR: begin
                                clear_addr_q <= {MAT_AW{1'b0}};
                                for (clear_i=0; clear_i<MAX_K; clear_i=clear_i+1)
                                    rhs_mem[clear_i] <= {RHS_W{1'b0}};
                                state <= S_CLEAR;
                            end
                            OP_CLEAR_ROW: begin
                                clear_row_q <= row_a;
                                clear_col_q <= 5'd0;
                                state <= S_CLEAR_ROW;
                            end
                            OP_READ2: begin
                                rdata_a <= bank_read_a[row_a[2:0]*GE_W +: GE_W];
                                rdata_b <= bank_read_b[row_b[2:0]*GE_W +: GE_W];
                                state <= S_DONE;
                            end
                            OP_READ4: begin
                                for (read_lane_i=0; read_lane_i<4; read_lane_i=read_lane_i+1)
                                    read4_rdata[read_lane_i*GE_W +: GE_W] <=
                                        bank_read_a[((row_a+read_lane_i)&5'h7)*GE_W +: GE_W];
                                rdata_b <= bank_read_b[row_b[2:0]*GE_W +: GE_W];
                                state <= S_DONE;
                            end
                            // Gaussian row/RHS update hardware is intentionally
                            // absent.  The retained solver is Cholesky LDLT.
                            OP_ROW_UPDATE: begin update_value <= {GE_W{1'b0}}; state <= S_DONE; end
                            OP_RHS_WRITE: begin rhs_mem[row_a] <= rhs_wdata; state <= S_DONE; end
                            OP_RHS_READ: begin rhs_rdata <= rhs_mem[row_a]; state <= S_DONE; end
                            OP_RHS_UPDATE: state <= S_DONE;
                            OP_ACC4: begin
                                acc4_drain_col_q <= 2'd0;
                                acc4_col_base_q <= col_a;
                                acc4_row_base_q <= row_base;
                                acc4_column_add_q <= lane_add4[0 +: LANES*64];
                                acc4_column_valid_q <= acc4_effective_lane_valid_w[0 +: LANES];
                                state <= S_ACC4;
                            end
                            default: state <= S_DONE; // WRITE/WRITE4/ACC/ACC4 occur in banks above.
                        endcase
                    end
                end
                S_CLEAR: begin
                    if (clear_addr_q == BANK_DEPTH-1)
                        state <= S_DONE;
                    else
                        clear_addr_q <= clear_addr_q + 1'b1;
                end
                S_CLEAR_ROW: begin
                    if (clear_col_q >= clear_row_q)
                        state <= S_DONE;
                    else
                        clear_col_q <= clear_col_q + 1'b1;
                end
                S_ACC4: begin
                    if (acc4_drain_col_q == 2'd3) begin
                        done <= 1'b1;
                        busy <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        acc4_column_add_q <= acc4_prefetch_add_w;
                        acc4_column_valid_q <= acc4_prefetch_valid_w;
                        if (acc4_drain_col_q == 2'd0)
                            acc4_credit <= 1'b1;
                        acc4_drain_col_q <= acc4_drain_col_q + 1'b1;
                    end
                end
                S_DONE: begin busy <= 1'b0; done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
