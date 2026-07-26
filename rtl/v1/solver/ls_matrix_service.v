`timescale 1ns/1ps

// LS matrix service row-stage mapping for the 4-row PE pipeline:
//   Row0/Row1: OP_ACC_BLOCK accumulates Gram/RHS products across BANKS=8 lanes.
//   Row2: OP_ROW_UPDATE and OP_RHS_UPDATE perform Gaussian elimination update/normalization work.
//   Row3: OP_WRITE/OP_RHS_WRITE publish refined coefficients back to the controller writeback path.
// The numerical Gaussian/LS flow is unchanged; this module only makes the existing stages explicit.
module ls_matrix_service #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 56,
    parameter integer FACTOR_W = 64,
    parameter integer RHS_W = 64,
    parameter integer FRAC_W = 16,
    parameter integer LANES = 8,
    parameter integer ENABLE_ROW_UPDATE_BLOCK = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [2:0]                   op,
    input  wire [4:0]                   row_a,
    input  wire [4:0]                   col_a,
    input  wire [4:0]                   row_b,
    input  wire [4:0]                   col_b,
    input  wire [4:0]                   row_base,
    input  wire [LANES-1:0]             lane_valid,
    input  wire                         row_update_block,
    input  wire signed [LANES*64-1:0]   lane_add,
    input  wire signed [GE_W-1:0]       wdata,
    input  wire signed [FACTOR_W-1:0]   factor,
    input  wire signed [RHS_W-1:0]       rhs_wdata,
    output reg                          busy,
    output reg                          done,
    output reg signed [GE_W-1:0]        rdata_a,
    output reg signed [GE_W-1:0]        rdata_b,
    output reg signed [GE_W-1:0]        update_value,
    output reg signed [RHS_W-1:0]        rhs_rdata
);
    localparam [2:0] OP_CLEAR      = 3'd0;
    localparam [2:0] OP_WRITE      = 3'd1;
    localparam [2:0] OP_READ2      = 3'd2;
    localparam [2:0] OP_ACC_BLOCK  = 3'd3;
    localparam [2:0] OP_ROW_UPDATE = 3'd4;
    localparam [2:0] OP_RHS_WRITE  = 3'd5;
    localparam [2:0] OP_RHS_READ   = 3'd6;
    localparam [2:0] OP_RHS_UPDATE = 3'd7;

    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_CLEAR       = 4'd1;
    localparam [3:0] S_READ_WAIT   = 4'd2;
    localparam [3:0] S_READ_CAP    = 4'd3;
    localparam [3:0] S_UPDATE_WAIT = 4'd4;
    localparam [3:0] S_UPDATE_MUL  = 4'd5;
    localparam [3:0] S_UPDATE_WR   = 4'd6;
    localparam [3:0] S_DONE        = 4'd7;
    localparam [3:0] S_BLOCK_WR    = 4'd8;
    localparam [3:0] S_RHS_WR      = 4'd9;

    localparam integer BANKS = 8;
    localparam integer BANK_DEPTH = (MAX_K / BANKS) * MAX_K;
    localparam [2:0] LAST_LANE = LANES - 1;

    reg [3:0] state;
    reg [5:0] clear_addr;
    reg [4:0] rd_addr_a;
    reg [4:0] rd_addr_b;
    reg [2:0] rd_bank_a;
    reg [2:0] rd_bank_b;
    reg [4:0] wr_addr_q;
    reg [2:0] wr_bank_q;
    reg signed [GE_W-1:0] row_value_q;
    reg signed [(FACTOR_W+GE_W)-1:0] product_q;
    reg [4:0] block_col_base_q;
    reg [2:0] block_wr_bank_q;
    reg [LANES-1:0] block_lane_valid_q;
    reg [2:0] block_wr_lane_q;
    reg signed [LANES*GE_W-1:0] block_row_value_q;
    reg signed [LANES*GE_W-1:0] block_pivot_value_q;
    reg signed [LANES*GE_W-1:0] block_update_value_q;
    reg [4:0] rhs_wr_addr_q;
    reg signed [RHS_W-1:0] rhs_value_q;
    reg signed [RHS_W-1:0] rhs_pivot_q;
    reg clear_en;
    reg write_en;
    reg acc_en;
    reg update_write_en;
    reg block_update_write_en;
    reg signed [GE_W-1:0] update_write_data;

    wire signed [BANKS*GE_W-1:0] bank_rdata_a;
    wire signed [BANKS*GE_W-1:0] bank_rdata_b;
    wire signed [BANKS*GE_W-1:0] direct_rdata_a;
    wire signed [BANKS*GE_W-1:0] direct_rdata_b;
    reg signed [LANES*GE_W-1:0] block_target_read_w;
    reg signed [LANES*GE_W-1:0] block_pivot_read_w;
    integer rd_lane;
    integer upd_lane;

    function [4:0] bank_addr;
        input [4:0] row;
        input [4:0] col;
        begin
            bank_addr = {row[3], col[3:0]};
        end
    endfunction

    function signed [GE_W-1:0] add_to_ge;
        input signed [GE_W-1:0] cur;
        input signed [63:0] addend;
        reg signed [63:0] cur_ext;
        reg signed [63:0] sum_ext;
        begin
            cur_ext = {{(64-GE_W){cur[GE_W-1]}}, cur};
            sum_ext = cur_ext + addend;
            add_to_ge = sum_ext[GE_W-1:0];
        end
    endfunction

    function signed [GE_W-1:0] row_update_result;
        input signed [GE_W-1:0] cur;
        input signed [(FACTOR_W+GE_W)-1:0] product;
        begin
            row_update_result = cur - $signed(product >>> FRAC_W);
        end
    endfunction

    function signed [GE_W-1:0] row_update_factor;
        input signed [GE_W-1:0] cur;
        input signed [GE_W-1:0] pivot;
        input signed [FACTOR_W-1:0] factor_i;
        reg signed [(FACTOR_W+GE_W)-1:0] product;
        begin
            product = $signed(factor_i) * $signed(pivot);
            row_update_factor = cur - $signed(product >>> FRAC_W);
        end
    endfunction


    (* ram_style = "distributed" *) reg signed [RHS_W-1:0] rhs_mem [0:MAX_K-1];

    genvar bank;
    generate
        for (bank = 0; bank < BANKS; bank = bank + 1) begin : gen_bank
            (* ram_style = "distributed" *) reg signed [GE_W-1:0] mem_a [0:BANK_DEPTH-1];
            (* ram_style = "distributed" *) reg signed [GE_W-1:0] mem_b [0:BANK_DEPTH-1];
            wire [4:0] acc_addr = {row_base[3], col_a[3:0]};
            always @(posedge clk) begin
                if (clear_en) begin
                    mem_a[clear_addr[4:0]] <= {GE_W{1'b0}};
                    mem_b[clear_addr[4:0]] <= {GE_W{1'b0}};
                end else if (acc_en && lane_valid[bank]) begin
                    mem_a[acc_addr] <= add_to_ge(mem_a[acc_addr], $signed(lane_add[bank*64 +: 64]));
                    mem_b[acc_addr] <= add_to_ge(mem_a[acc_addr], $signed(lane_add[bank*64 +: 64]));
                end else if (write_en && (wr_bank_q == bank[2:0])) begin
                    mem_a[wr_addr_q] <= wdata;
                    mem_b[wr_addr_q] <= wdata;
                end else if (update_write_en && (wr_bank_q == bank[2:0])) begin
                    mem_a[wr_addr_q] <= update_write_data;
                    mem_b[wr_addr_q] <= update_write_data;
                end else if (block_update_write_en && (block_wr_bank_q == bank[2:0]) && block_lane_valid_q[block_wr_lane_q]) begin
                    mem_a[bank_addr(row_a, block_col_base_q + {2'b00, block_wr_lane_q})] <= block_update_value_q[block_wr_lane_q*GE_W +: GE_W];
                    mem_b[bank_addr(row_a, block_col_base_q + {2'b00, block_wr_lane_q})] <= block_update_value_q[block_wr_lane_q*GE_W +: GE_W];
                end
            end
            assign bank_rdata_a[bank*GE_W +: GE_W] = mem_a[rd_addr_a];
            assign bank_rdata_b[bank*GE_W +: GE_W] = mem_b[rd_addr_b];
            assign direct_rdata_a[bank*GE_W +: GE_W] = mem_a[bank_addr(row_a, col_a)];
            assign direct_rdata_b[bank*GE_W +: GE_W] = mem_b[bank_addr(row_b, col_b)];
        end
    endgenerate

    always @(*) begin
        block_target_read_w = {LANES*GE_W{1'b0}};
        block_pivot_read_w = {LANES*GE_W{1'b0}};
        for (rd_lane = 0; rd_lane < LANES; rd_lane = rd_lane + 1) begin
            case (row_a[2:0])
                3'd0: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[0].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd1: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[1].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd2: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[2].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd3: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[3].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd4: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[4].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd5: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[5].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                3'd6: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[6].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
                default: block_target_read_w[rd_lane*GE_W +: GE_W] = gen_bank[7].mem_a[bank_addr(row_a, block_col_base_q + rd_lane[4:0])];
            endcase
            case (row_b[2:0])
                3'd0: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[0].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd1: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[1].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd2: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[2].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd3: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[3].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd4: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[4].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd5: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[5].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                3'd6: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[6].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
                default: block_pivot_read_w[rd_lane*GE_W +: GE_W] = gen_bank[7].mem_b[bank_addr(row_b, block_col_base_q + rd_lane[4:0])];
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            clear_addr <= 6'd0;
            rd_addr_a <= 5'd0;
            rd_addr_b <= 5'd0;
            rd_bank_a <= 3'd0;
            rd_bank_b <= 3'd0;
            wr_addr_q <= 5'd0;
            wr_bank_q <= 3'd0;
            row_value_q <= {GE_W{1'b0}};
            product_q <= {(FACTOR_W+GE_W){1'b0}};
            update_write_data <= {GE_W{1'b0}};
            block_col_base_q <= 5'd0;
            block_wr_bank_q <= 3'd0;
            block_wr_lane_q <= 3'd0;
            block_lane_valid_q <= {LANES{1'b0}};
            block_row_value_q <= {LANES*GE_W{1'b0}};
            block_pivot_value_q <= {LANES*GE_W{1'b0}};
            block_update_value_q <= {LANES*GE_W{1'b0}};
            rhs_wr_addr_q <= 5'd0;
            rhs_value_q <= {RHS_W{1'b0}};
            rhs_pivot_q <= {RHS_W{1'b0}};
            update_value <= {GE_W{1'b0}};
            rhs_rdata <= {RHS_W{1'b0}};
            rdata_a <= {GE_W{1'b0}};
            rdata_b <= {GE_W{1'b0}};
            clear_en <= 1'b0;
            write_en <= 1'b0;
            acc_en <= 1'b0;
            update_write_en <= 1'b0;
            block_update_write_en <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            clear_en <= 1'b0;
            write_en <= 1'b0;
            acc_en <= 1'b0;
            update_write_en <= 1'b0;
            block_update_write_en <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        if (op == OP_CLEAR) begin
                            clear_addr <= 6'd0;
                            clear_en <= 1'b1;
                            state <= S_CLEAR;
                        end else if (op == OP_RHS_WRITE) begin
                            rhs_mem[row_a] <= rhs_wdata;
                            state <= S_DONE;
                        end else if (op == OP_RHS_READ) begin
                            rhs_rdata <= rhs_mem[row_a];
                            state <= S_DONE;
                        end else if (op == OP_RHS_UPDATE) begin
                            rhs_wr_addr_q <= row_a;
                            rhs_value_q <= rhs_mem[row_a];
                            rhs_pivot_q <= rhs_mem[row_b];
                            state <= S_RHS_WR;
                        end else if (op == OP_READ2) begin
                            rdata_a <= direct_rdata_a[row_a[2:0]*GE_W +: GE_W];
                            rdata_b <= direct_rdata_b[row_b[2:0]*GE_W +: GE_W];
                            state <= S_DONE;
                        end else if ((op == OP_ROW_UPDATE) && row_update_block) begin
                            block_col_base_q <= col_a;
                            block_wr_bank_q <= row_a[2:0];
                            block_lane_valid_q <= lane_valid;
                            state <= S_UPDATE_WAIT;
                        end else if (op == OP_ROW_UPDATE) begin
                            row_value_q <= direct_rdata_a[row_a[2:0]*GE_W +: GE_W];
                            product_q <= $signed(factor) * $signed(direct_rdata_b[row_b[2:0]*GE_W +: GE_W]);
                            wr_bank_q <= row_a[2:0];
                            wr_addr_q <= bank_addr(row_a, col_a);
                            state <= S_UPDATE_WR;
                        end else if (op == OP_WRITE) begin
                            wr_bank_q <= row_a[2:0];
                            wr_addr_q <= bank_addr(row_a, col_a);
                            write_en <= 1'b1;
                            state <= S_DONE;
                        end else if (op == OP_ACC_BLOCK) begin
                            acc_en <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            rd_bank_a <= row_a[2:0];
                            rd_bank_b <= row_b[2:0];
                            rd_addr_a <= bank_addr(row_a, col_a);
                            rd_addr_b <= bank_addr(row_b, col_b);
                            wr_bank_q <= row_a[2:0];
                            wr_addr_q <= bank_addr(row_a, col_a);
                            state <= (op == OP_ROW_UPDATE) ? S_UPDATE_WAIT : S_READ_WAIT;
                        end
                    end
                end
                S_CLEAR: begin
                    if (clear_addr < MAX_K[5:0])
                        rhs_mem[clear_addr[4:0]] <= {RHS_W{1'b0}};
                    if (clear_addr == BANK_DEPTH[5:0] - 6'd1) begin
                        state <= S_DONE;
                    end else begin
                        clear_addr <= clear_addr + 6'd1;
                        clear_en <= 1'b1;
                    end
                end
                S_READ_WAIT: begin
                    rdata_a <= bank_rdata_a[rd_bank_a*GE_W +: GE_W];
                    rdata_b <= bank_rdata_b[rd_bank_b*GE_W +: GE_W];
                    state <= S_DONE;
                end
                S_READ_CAP: begin
                    state <= S_DONE;
                end
                S_UPDATE_WAIT: begin
                    if (ENABLE_ROW_UPDATE_BLOCK && row_update_block) begin
                        block_row_value_q <= block_target_read_w;
                        block_pivot_value_q <= block_pivot_read_w;
                        state <= S_UPDATE_MUL;
                    end else begin
                        row_value_q <= bank_rdata_a[rd_bank_a*GE_W +: GE_W];
                        product_q <= $signed(factor) * $signed(bank_rdata_b[rd_bank_b*GE_W +: GE_W]);
                        state <= S_UPDATE_WR;
                    end
                end
                S_UPDATE_MUL: begin
                    if (ENABLE_ROW_UPDATE_BLOCK && row_update_block) begin
                        for (upd_lane = 0; upd_lane < LANES; upd_lane = upd_lane + 1) begin
                            block_update_value_q[upd_lane*GE_W +: GE_W] <= row_update_factor(
                                block_row_value_q[upd_lane*GE_W +: GE_W],
                                block_pivot_value_q[upd_lane*GE_W +: GE_W],
                                factor
                            );
                        end
                    end
                    state <= S_UPDATE_WR;
                end
                S_UPDATE_WR: begin
                    if (ENABLE_ROW_UPDATE_BLOCK && row_update_block) begin
                        block_wr_lane_q <= 3'd0;
                        block_update_write_en <= 1'b1;
                        state <= S_BLOCK_WR;
                    end else begin
                        update_write_data <= row_update_result(row_value_q, product_q);
                        update_value <= row_update_result(row_value_q, product_q);
                        rdata_a <= row_update_result(row_value_q, product_q);
                        update_write_en <= 1'b1;
                        state <= S_DONE;
                    end
                end
                S_BLOCK_WR: begin
                    if (block_wr_lane_q == LAST_LANE) begin
                        state <= S_DONE;
                    end else begin
                        block_wr_lane_q <= block_wr_lane_q + 3'd1;
                        block_update_write_en <= 1'b1;
                    end
                end
                S_RHS_WR: begin
                    rhs_mem[rhs_wr_addr_q] <= rhs_value_q - (($signed(factor) * $signed(rhs_pivot_q)) >>> FRAC_W);
                    state <= S_DONE;
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule







