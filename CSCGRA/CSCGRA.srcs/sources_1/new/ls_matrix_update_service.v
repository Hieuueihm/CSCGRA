`timescale 1ns/1ps

module ls_matrix_update_service #(
    parameter integer MAX_K = 16,
    parameter integer STORE_W = 64,
    parameter integer MAT_W = 56,
    parameter integer FRAC_W = 16
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire [1:0] op,
    input  wire bank,
    input  wire [4:0] row_i,
    input  wire [4:0] row_k,
    input  wire [4:0] col,
    input  wire signed [STORE_W-1:0] wdata,
    input  wire signed [STORE_W-1:0] factor,

    output reg busy,
    output reg done,
    output reg signed [STORE_W-1:0] rdata,
    output reg signed [STORE_W-1:0] update_value
);
    localparam [1:0] OP_READ = 2'd0;
    localparam [1:0] OP_WRITE = 2'd1;
    localparam [1:0] OP_ROW_UPDATE = 2'd2;

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_READ_WAIT = 3'd1;
    localparam [2:0] S_READ_CAP = 3'd2;
    localparam [2:0] S_UPDATE_WAIT = 3'd3;
    localparam [2:0] S_UPDATE_MUL = 3'd4;
    localparam [2:0] S_UPDATE_WRITE = 3'd5;
    localparam [2:0] S_DONE = 3'd6;

    reg [2:0] state;
    reg [1:0] op_q;
    reg bank_q;
    reg [4:0] row_i_q;
    reg [4:0] row_k_q;
    reg [4:0] col_q;
    reg signed [STORE_W-1:0] wdata_q;
    reg signed [STORE_W-1:0] factor_q;
    reg signed [STORE_W-1:0] row_i_val;
    reg signed [STORE_W-1:0] row_k_val;
    reg signed [(STORE_W+MAT_W)-1:0] product;

    reg ge_we;
    reg [4:0] ge_wrow;
    reg [4:0] ge_wcol;
    reg signed [STORE_W-1:0] ge_wdata;
    reg [4:0] ge_rrow_a;
    reg [4:0] ge_rcol_a;
    wire signed [STORE_W-1:0] ge_rdata_a;
    reg [4:0] ge_rrow_b;
    reg [4:0] ge_rcol_b;
    wire signed [STORE_W-1:0] ge_rdata_b;

    ls_matrix_scratchpad #(
        .MAX_K(MAX_K),
        .GE_W(STORE_W),
        .RHS_W(STORE_W)
    ) u_matrix (
        .clk(clk),
        .ge_we(ge_we),
        .ge_bank_w(bank_q),
        .ge_wrow(ge_wrow),
        .ge_wcol(ge_wcol),
        .ge_wdata(ge_wdata),
        .ge_bank_a(bank_q),
        .ge_rrow_a(ge_rrow_a),
        .ge_rcol_a(ge_rcol_a),
        .ge_rdata_a(ge_rdata_a),
        .ge_bank_b(bank_q),
        .ge_rrow_b(ge_rrow_b),
        .ge_rcol_b(ge_rcol_b),
        .ge_rdata_b(ge_rdata_b),
        .rhs_we(1'b0),
        .rhs_bank_w(1'b0),
        .rhs_waddr(5'd0),
        .rhs_wdata({STORE_W{1'b0}}),
        .rhs_bank_r(1'b0),
        .rhs_raddr(5'd0),
        .rhs_rdata()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            rdata <= {STORE_W{1'b0}};
            update_value <= {STORE_W{1'b0}};
            op_q <= OP_READ;
            bank_q <= 1'b0;
            row_i_q <= 5'd0;
            row_k_q <= 5'd0;
            col_q <= 5'd0;
            wdata_q <= {STORE_W{1'b0}};
            factor_q <= {STORE_W{1'b0}};
            row_i_val <= {STORE_W{1'b0}};
            row_k_val <= {STORE_W{1'b0}};
            product <= {(STORE_W+MAT_W){1'b0}};
            ge_we <= 1'b0;
            ge_wrow <= 5'd0;
            ge_wcol <= 5'd0;
            ge_wdata <= {STORE_W{1'b0}};
            ge_rrow_a <= 5'd0;
            ge_rcol_a <= 5'd0;
            ge_rrow_b <= 5'd0;
            ge_rcol_b <= 5'd0;
        end else begin
            done <= 1'b0;
            ge_we <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        op_q <= op;
                        bank_q <= bank;
                        row_i_q <= row_i;
                        row_k_q <= row_k;
                        col_q <= col;
                        wdata_q <= wdata;
                        factor_q <= factor;
                        if (op == OP_WRITE) begin
                            ge_we <= 1'b1;
                            ge_wrow <= row_i;
                            ge_wcol <= col;
                            ge_wdata <= wdata;
                            state <= S_DONE;
                        end else if (op == OP_ROW_UPDATE) begin
                            ge_rrow_a <= row_i;
                            ge_rcol_a <= col;
                            ge_rrow_b <= row_k;
                            ge_rcol_b <= col;
                            state <= S_UPDATE_WAIT;
                        end else begin
                            ge_rrow_a <= row_i;
                            ge_rcol_a <= col;
                            state <= S_READ_WAIT;
                        end
                    end
                end
                S_READ_WAIT: begin
                    state <= S_READ_CAP;
                end
                S_READ_CAP: begin
                    rdata <= ge_rdata_a;
                    state <= S_DONE;
                end
                S_UPDATE_WAIT: begin
                    state <= S_UPDATE_MUL;
                end
                S_UPDATE_MUL: begin
                    row_i_val <= ge_rdata_a;
                    row_k_val <= ge_rdata_b;
                    product <= $signed(factor_q) * $signed(ge_rdata_b[MAT_W-1:0]);
                    state <= S_UPDATE_WRITE;
                end
                S_UPDATE_WRITE: begin
                    update_value <= row_i_val - $signed(product >>> FRAC_W);
                    rdata <= row_i_val - $signed(product >>> FRAC_W);
                    ge_we <= 1'b1;
                    ge_wrow <= row_i_q;
                    ge_wcol <= col_q;
                    ge_wdata <= row_i_val - $signed(product >>> FRAC_W);
                    state <= S_DONE;
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule


