`timescale 1ns/1ps

module ls_matrix_service #(
    parameter integer MAX_K = 16,
    parameter integer GE_W = 56,
    parameter integer FACTOR_W = 64,
    parameter integer FRAC_W = 16,
    parameter integer LANES = 8
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
    input  wire signed [LANES*64-1:0]   lane_add,
    input  wire signed [GE_W-1:0]       wdata,
    input  wire signed [FACTOR_W-1:0]   factor,
    output reg                          busy,
    output reg                          done,
    output reg signed [GE_W-1:0]        rdata_a,
    output reg signed [GE_W-1:0]        rdata_b,
    output reg signed [GE_W-1:0]        update_value
);
    localparam [2:0] OP_CLEAR      = 3'd0;
    localparam [2:0] OP_WRITE      = 3'd1;
    localparam [2:0] OP_READ2      = 3'd2;
    localparam [2:0] OP_ACC_BLOCK  = 3'd3;
    localparam [2:0] OP_ROW_UPDATE = 3'd4;

    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_CLEAR       = 4'd1;
    localparam [3:0] S_READ_WAIT   = 4'd2;
    localparam [3:0] S_READ_CAP    = 4'd3;
    localparam [3:0] S_UPDATE_WAIT = 4'd4;
    localparam [3:0] S_UPDATE_MUL  = 4'd5;
    localparam [3:0] S_UPDATE_WR   = 4'd6;
    localparam [3:0] S_DONE        = 4'd7;

    localparam integer BANKS = 8;
    localparam integer BANK_DEPTH = (MAX_K / BANKS) * MAX_K;

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

    reg clear_en;
    reg write_en;
    reg acc_en;
    reg update_write_en;
    reg signed [GE_W-1:0] update_write_data;

    wire signed [BANKS*GE_W-1:0] bank_rdata_a;
    wire signed [BANKS*GE_W-1:0] bank_rdata_b;

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

    genvar bank;
    generate
        for (bank = 0; bank < BANKS; bank = bank + 1) begin : gen_bank
            (* ram_style = "block" *) reg signed [GE_W-1:0] mem_a [0:BANK_DEPTH-1];
            (* ram_style = "block" *) reg signed [GE_W-1:0] mem_b [0:BANK_DEPTH-1];
            reg signed [GE_W-1:0] rd_a_q;
            reg signed [GE_W-1:0] rd_b_q;
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
                end
                rd_a_q <= mem_a[rd_addr_a];
                rd_b_q <= mem_b[rd_addr_b];
            end
            assign bank_rdata_a[bank*GE_W +: GE_W] = rd_a_q;
            assign bank_rdata_b[bank*GE_W +: GE_W] = rd_b_q;
        end
    endgenerate

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
            update_value <= {GE_W{1'b0}};
            rdata_a <= {GE_W{1'b0}};
            rdata_b <= {GE_W{1'b0}};
            clear_en <= 1'b0;
            write_en <= 1'b0;
            acc_en <= 1'b0;
            update_write_en <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            clear_en <= 1'b0;
            write_en <= 1'b0;
            acc_en <= 1'b0;
            update_write_en <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        if (op == OP_CLEAR) begin
                            clear_addr <= 6'd0;
                            clear_en <= 1'b1;
                            state <= S_CLEAR;
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
                    if (clear_addr == BANK_DEPTH[5:0] - 6'd1)
                        state <= S_DONE;
                    else begin
                        clear_addr <= clear_addr + 6'd1;
                        clear_en <= 1'b1;
                    end
                end
                S_READ_WAIT: begin
                    state <= S_READ_CAP;
                end
                S_READ_CAP: begin
                    rdata_a <= bank_rdata_a[rd_bank_a*GE_W +: GE_W];
                    rdata_b <= bank_rdata_b[rd_bank_b*GE_W +: GE_W];
                    state <= S_DONE;
                end
                S_UPDATE_WAIT: begin
                    state <= S_UPDATE_MUL;
                end
                S_UPDATE_MUL: begin
                    row_value_q <= bank_rdata_a[rd_bank_a*GE_W +: GE_W];
                    product_q <= $signed(factor) * $signed(bank_rdata_b[rd_bank_b*GE_W +: GE_W]);
                    state <= S_UPDATE_WR;
                end
                S_UPDATE_WR: begin
                    update_write_data <= row_value_q - $signed(product_q >>> FRAC_W);
                    update_value <= row_value_q - $signed(product_q >>> FRAC_W);
                    rdata_a <= row_value_q - $signed(product_q >>> FRAC_W);
                    update_write_en <= 1'b1;
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
