`include "memory_defs.vh"
`include "feeder_interface.vh"

module operand_plan (
    input wire [1:0] mode,
    input wire trans,
    input wire [7:0] rows,
    input wire [10:0] cols, out_idx, red_idx,
    input wire [2:0] step,
    input wire [11:0] vec_base,
    output reg [31:0] mat_mask, vec_mask,
    output reg [287:0] mat_addr,
    output reg [223:0] vec_addr,
    output reg [19:0] vec_banks,
    output reg [3:0] vec_lanes,
    output reg [3:0] fault
);
    wire dense = mode == `CSR_FEED_MODE_B_R1 || mode == `CSR_FEED_MODE_B_R4;
    wire rfour = mode == `CSR_FEED_MODE_PHI_R4 || mode == `CSR_FEED_MODE_B_R4;
    wire transpose = dense ? trans : rfour;
    integer outputs, reductions, output_idx, reduction, row_idx, col_idx, bank, addr, vector_idx;
    integer tile, lane;
    always @* begin
        mat_mask = '0; vec_mask = '0; mat_addr = '0; vec_addr = '0; vec_banks = '0; vec_lanes = '0; fault = '0;
        outputs = transpose ? int'(cols) : int'(rows);
        reductions = transpose ? int'(rows) : int'(cols);
        output_idx = 0; reduction = 0; row_idx = 0; col_idx = 0; bank = 0; addr = 0; vector_idx = 0; lane = 0;
        if (rows == 0 || int'(rows) > `CSR_MEM_B_ROWS || cols == 0 ||
            int'(cols) > (dense ? `CSR_MEM_B_COLS : `CSR_FEED_MAX_COLS)) fault = `CSR_MEM_FAULT_SHAPE;
        else if (int'(out_idx) >= outputs || int'(red_idx) >= reductions ||
                 (rfour && (out_idx[2:0] != 0 || red_idx[4:0] != 0)) ||
                 (!rfour && (out_idx[4:0] != 0 || step != 0)) || (!dense && trans != rfour)) fault = `CSR_MEM_FAULT_RANGE;
        if (fault == 0) begin
            for (tile = 0; tile < 32; tile = tile + 1) begin
                lane = rfour ? tile%4 : 0;
                output_idx = int'(out_idx)+(rfour ? tile/4 : tile);
                reduction = int'(red_idx)+(rfour ? 8*lane+int'(step) : 0);
                row_idx = transpose ? reduction : output_idx;
                col_idx = transpose ? output_idx : reduction;
                if (output_idx < outputs && reduction < reductions) begin
                    bank = dense ? (row_idx+col_idx)%32 : col_idx%8;
                    addr = dense ? row_idx*((int'(cols)+31)/32)+col_idx/32 : (col_idx/8)*((int'(rows)+31)/32)+row_idx/32;
                    if (addr >= 512 || (mat_mask[bank] && mat_addr[bank*9 +: 9] != 9'(addr))) fault = `CSR_MEM_FAULT_RANGE;
                    mat_mask[bank] = 1'b1; mat_addr[bank*9 +: 9] = 9'(addr);
                    vector_idx = int'(vec_base)+reduction;
                    if (vector_idx >= `CSR_MEM_V_LEN) fault = `CSR_MEM_FAULT_RANGE;
                    else begin
                        bank = vector_idx%32; addr = vector_idx/32;
                        vec_mask[bank] = 1'b1; vec_addr[bank*7 +: 7] = 7'(addr);
                        vec_banks[lane*5 +: 5] = 5'(bank); vec_lanes[lane] = 1'b1;
                    end
                end
            end
        end
        if (fault != 0) begin mat_mask = '0; vec_mask = '0; mat_addr = '0; vec_addr = '0; vec_lanes = '0; vec_banks = '0; end
    end
endmodule
