`include "context_defs.vh"

module context_decode #(
    parameter integer TILE_ID = 0,
    parameter integer ROUTING = 0
) (
    input wire [63:0] word,
    input wire [7:0] rev,
    input wire mode,
    output reg [`CSR_PE_OP_W-1:0] op,
    output reg [3:0] a_kind, b_kind,
    output reg [2:0] a_idx, b_idx,
    output wire [15:0] imm,
    output reg [2:0] guard, sel,
    output reg rf_we,
    output wire [2:0] dst,
    output reg pred_we,
    output reg [1:0] pred_dst,
    output reg [2:0] pred_src,
    output reg wide,
    output wire [1:0] wide_idx,
    output wire [11:0] routes,
    output wire store, halt,
    output reg [3:0] fault
);
    localparam integer ROW = (TILE_ID % 16) / `CSR_PE_COLS;
    localparam integer COL = TILE_ID % `CSR_PE_COLS;
    localparam [3:0] EDGES = {COL > 0, ROW < `CSR_PE_ROWS-1, COL < `CSR_PE_COLS-1, ROW > 0};
    wire [5:0] code = word[`CSR_CTX_OPCODE_LSB +: `CSR_CTX_OPCODE_W];
    wire [3:0] src_a = word[`CSR_CTX_SRCA_KIND_LSB +: `CSR_CTX_SRCA_KIND_W];
    wire [3:0] src_b = word[`CSR_CTX_SRCB_KIND_LSB +: `CSR_CTX_SRCB_KIND_W];
    wire [2:0] reg_a = word[`CSR_CTX_SRCA_REG_LSB +: `CSR_CTX_SRCA_REG_W];
    wire [2:0] reg_b = word[`CSR_CTX_SRCB_REG_LSB +: `CSR_CTX_SRCB_REG_W];
    wire acc_write = word[`CSR_CTX_ACC_WRITE_LSB];
    wire [2:0] predicate = word[`CSR_CTX_PREDICATE_LSB +: `CSR_CTX_PREDICATE_W];
    wire [2:0] fmt = word[`CSR_CTX_FORMAT_LSB +: `CSR_CTX_FORMAT_W];
    wire any_route = routes != 0;
    reg bad_word, bad_edge, unsupported;
    integer dir;
    reg [2:0] route_sel;

    assign imm = word[`CSR_CTX_IMMEDIATE_LSB +: `CSR_CTX_IMMEDIATE_W];
    assign dst = word[`CSR_CTX_DST_REG_LSB +: `CSR_CTX_DST_REG_W];
    assign routes = word[`CSR_CTX_ROUTEN_LSB +: 12];
    assign wide_idx = reg_b[1:0];
    assign store = code == `CSR_CTX_OP_STORE;
    assign halt = code == `CSR_CTX_OP_HALT;

    always @* begin
        op = `CSR_PE_OP_HOLD;
        a_kind = src_a; b_kind = src_b; a_idx = reg_a; b_idx = reg_b;
        guard = predicate; sel = 0;
        rf_we = word[`CSR_CTX_RF_WRITE_LSB];
        pred_we = 1'b0; pred_dst = 0; pred_src = 0; wide = 1'b0;
        bad_word = code > `CSR_CTX_OP_HALT || src_a > `CSR_CTX_SRC_PREDICATE ||
                   src_b > `CSR_CTX_SRC_PREDICATE || fmt > `CSR_CTX_FMT_ADDRESS ||
                   word[`CSR_CTX_RESERVED_LSB +: `CSR_CTX_RESERVED_W] != 0;
        bad_edge = TILE_ID < 0 || TILE_ID >= `CSR_PE_TILES;
        unsupported = any_route && ROUTING == 0;
        route_sel = 0;
        if (src_a == `CSR_CTX_SRC_LINK) begin
            if (reg_a > 3) bad_word = 1'b1;
            else if (!EDGES[reg_a[1:0]]) bad_edge = 1'b1;
        end
        if (src_b == `CSR_CTX_SRC_LINK) begin
            if (reg_b > 3) bad_word = 1'b1;
            else if (!EDGES[reg_b[1:0]]) bad_edge = 1'b1;
        end
        for (dir = 0; dir < 4; dir = dir + 1) begin
            route_sel = routes[dir*3 +: 3];
            if (route_sel > `CSR_CTX_ROUTE_RESULT) bad_word = 1'b1;
            if (route_sel == `CSR_CTX_ROUTE_VALUE && code != `CSR_CTX_OP_ROUTE) unsupported = 1'b1;
            if (route_sel != 0 && !EDGES[dir]) bad_edge = 1'b1;
        end
        if (code == `CSR_CTX_OP_NOP && word[63:6] != 0) bad_word = 1'b1;
        if (code == `CSR_CTX_OP_HALT && any_route) bad_word = 1'b1;
        if (code == `CSR_CTX_OP_ROUTE && (!any_route ||
            (src_a != `CSR_CTX_SRC_ACC && src_a != `CSR_CTX_SRC_LINK && src_a != `CSR_CTX_SRC_NONE)))
            bad_word = 1'b1;
        case (code)
            `CSR_CTX_OP_NOP: begin guard = 0; rf_we = 1'b0; end
            `CSR_CTX_OP_CLEAR: begin
                op = `CSR_PE_OP_ACC_CLEAR;
                if (!acc_write || rf_we || (fmt != `CSR_CTX_FMT_FIXED && fmt != `CSR_CTX_FMT_NONE)) unsupported = 1'b1;
            end
            `CSR_CTX_OP_READ, `CSR_CTX_OP_MOV, `CSR_CTX_OP_STORE: begin
                op = `CSR_PE_OP_MOV;
                if (acc_write) unsupported = 1'b1;
            end
            `CSR_CTX_OP_MAC, `CSR_CTX_OP_MUL: begin
                op = code == `CSR_CTX_OP_MAC ? `CSR_PE_OP_MAC : `CSR_PE_OP_MUL;
                if (fmt != `CSR_CTX_FMT_FIXED || acc_write != (code == `CSR_CTX_OP_MAC)) unsupported = 1'b1;
                if (!mode) begin a_kind = src_b; b_kind = src_a; a_idx = reg_b; b_idx = reg_a; end
            end
            `CSR_CTX_OP_ADD, `CSR_CTX_OP_SUB: begin
                op = code == `CSR_CTX_OP_ADD ? `CSR_PE_OP_ADD : `CSR_PE_OP_SUB;
                if (fmt != `CSR_CTX_FMT_FIXED && fmt != `CSR_CTX_FMT_SIGNED) unsupported = 1'b1;
                if (acc_write) begin
                    if (code == `CSR_CTX_OP_ADD && src_a == `CSR_CTX_SRC_ACC && src_b == `CSR_CTX_SRC_LINK && fmt == `CSR_CTX_FMT_FIXED) begin
                        op = `CSR_PE_OP_ACC_ADD; wide = 1'b1; a_kind = 0; b_kind = 0;
                    end else unsupported = 1'b1;
                end
            end
            `CSR_CTX_OP_CMP: begin
                if (fmt == `CSR_CTX_FMT_UNSIGNED || fmt == `CSR_CTX_FMT_ADDRESS) op = `CSR_PE_OP_CMP_U;
                else if (fmt == `CSR_CTX_FMT_SIGNED || fmt == `CSR_CTX_FMT_FIXED) op = `CSR_PE_OP_CMP_S;
                else unsupported = 1'b1;
                if (acc_write || predicate > 2) unsupported = 1'b1;
                guard = 0; pred_we = 1'b1; pred_dst = predicate[1:0]; pred_src = `CSR_TILE_PSEL_LT;
            end
            `CSR_CTX_OP_SELECT: begin
                op = `CSR_PE_OP_SELECT; guard = 0; sel = predicate;
                if (acc_write) unsupported = 1'b1;
            end
            `CSR_CTX_OP_ROUTE: begin
                if (ROUTING == 0 || acc_write || rf_we) unsupported = 1'b1;
            end
            `CSR_CTX_OP_HALT: begin
                guard = 0; rf_we = 1'b0;
                if (word[63:6] != 0) unsupported = 1'b1;
            end
            default: unsupported = 1'b1;
        endcase
        fault = 0;
        if (rev != `CSR_CTX_REVISION) fault = `CSR_CTX_FAULT_REV;
        else if (bad_word) fault = `CSR_CTX_FAULT_WORD;
        else if (bad_edge) fault = `CSR_CTX_FAULT_EDGE;
        else if (unsupported) fault = `CSR_CTX_FAULT_EXEC;
    end
endmodule
