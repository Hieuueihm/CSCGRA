`include "tile_interface.vh"

module pe_operand #(
    parameter integer TILE_ID = 0
) (
    input wire enable,
    input wire [`CSR_TILE_SRC_W-1:0] kind,
    input wire [`CSR_TILE_REG_W-1:0] idx,
    input wire [`CSR_TILE_IMM_W-1:0] imm,
    input wire [`CSR_TILE_RF_WORDS*`CSR_PE_S_W-1:0] rf_data,
    input wire [`CSR_TILE_RF_WORDS-1:0] rf_valid,
    input wire [`CSR_TILE_PRED_BITS-1:0] preds,
    input wire [`CSR_PE_ACC_W-1:0] acc,
    input wire mode,
    input wire [`CSR_PE_S_W-1:0] mat, vec,
    input wire mat_valid, vec_valid,
    input wire [4*`CSR_PE_S_W-1:0] links,
    input wire [3:0] link_valid,
    output reg [`CSR_PE_S_W-1:0] data,
    output reg [`CSR_PE_FAULT_W-1:0] fault
);
    localparam integer SW = `CSR_PE_S_W;
    localparam integer AW = `CSR_PE_ACC_W;
    localparam integer IW = `CSR_TILE_IMM_W;
    localparam integer ROW = (TILE_ID % 16) / `CSR_PE_COLS;
    localparam integer COL = TILE_ID % `CSR_PE_COLS;
    localparam [3:0] EDGES = {COL > 0, ROW < `CSR_PE_ROWS-1, COL < `CSR_PE_COLS-1, ROW > 0};
    localparam signed [AW:0] S_MAX = (65'sd1 << (SW-1)) - 1;
    localparam signed [AW:0] S_MIN = -(65'sd1 << (SW-1));
    reg signed [AW:0] rounded;
    reg [AW:0] mag;
    integer shift;

    always @* begin
        data = '0;
        fault = '0;
        rounded = $signed({acc[AW-1], acc});
        mag = '0;
        shift = mode ? `CSR_PE_S_F : `CSR_PE_C_F;
        if (enable) begin
            case (kind)
                `CSR_TILE_SRC_NONE: data = '0;
                `CSR_TILE_SRC_ACC: begin
                    mag = rounded < 0 ? $unsigned(-rounded) : $unsigned(rounded);
                    mag = (mag + (65'd1 << (shift-1))) >> shift;
                    rounded = rounded < 0 ? -$signed(mag) : $signed(mag);
                    if (rounded > S_MAX || rounded < S_MIN) fault = `CSR_TILE_FAULT_ACC_RANGE;
                    else data = rounded[SW-1:0];
                end
                `CSR_TILE_SRC_RF: begin
                    if (!rf_valid[idx]) fault = `CSR_TILE_FAULT_UNINIT;
                    else data = rf_data[int'(idx)*SW +: SW];
                end
                `CSR_TILE_SRC_MATRIX: begin
                    if (!mat_valid) fault = `CSR_TILE_FAULT_SOURCE;
                    else data = mat;
                end
                `CSR_TILE_SRC_VECTOR: begin
                    if (!vec_valid) fault = `CSR_TILE_FAULT_SOURCE;
                    else data = vec;
                end
                `CSR_TILE_SRC_IMMEDIATE: data = {{(SW-IW){imm[IW-1]}}, imm};
                `CSR_TILE_SRC_LINK: begin
                    if (int'(idx) >= 4) fault = `CSR_TILE_FAULT_LINK;
                    else if (!EDGES[idx[1:0]] || !link_valid[idx[1:0]] || TILE_ID < 0 || TILE_ID >= `CSR_PE_TILES)
                        fault = `CSR_TILE_FAULT_LINK;
                    else data = links[int'(idx)*SW +: SW];
                end
                `CSR_TILE_SRC_PREDICATE: begin
                    if (int'(idx) >= `CSR_TILE_PRED_BITS) fault = `CSR_TILE_FAULT_PRED;
                    else data = {{(SW-1){1'b0}}, preds[idx[1:0]]};
                end
                default: fault = `CSR_TILE_FAULT_SOURCE;
            endcase
        end
    end
endmodule
