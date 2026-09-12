`include "control_defs.vh"

module control_decode (
    input wire [255:0] word,
    input wire [7:0] rev,
    output wire [3:0] kind,
    output wire [15:0] count,
    output wire [7:0] loop_target, branch_target,
    output wire [2:0] predicate, address_mode,
    output wire [23:0] address,
    output wire [15:0] stride,
    output reg [3:0] fault
);
    wire [3:0] flags = word[`CSR_CTL_FLAGS_LSB +: 4];
    wire [7:0] repeat_count = word[`CSR_CTL_REPEAT_LSB +: 8];
    wire [31:0] immediate = word[`CSR_CTL_IMMEDIATE_LSB +: 32];
    wire reserved_set = |word[`CSR_CTL_RESERVED_LSB +: `CSR_CTL_RESERVED_W];
    assign kind = word[`CSR_CTL_KIND_LSB +: 4];
    assign count = word[`CSR_CTL_COUNT_LSB +: 16];
    assign loop_target = word[`CSR_CTL_LOOP_TARGET_LSB +: 8];
    assign branch_target = word[`CSR_CTL_BRANCH_TARGET_LSB +: 8];
    assign predicate = word[`CSR_CTL_PREDICATE_LSB +: 3];
    assign address_mode = word[`CSR_CTL_ADDRESS_MODE_LSB +: 3];
    assign address = word[`CSR_CTL_IMMEDIATE_ADDRESS_LSB +: 24];
    assign stride = word[`CSR_CTL_STRIDE_LSB +: 16];
    always @* begin
        fault = `CSR_CTL_FAULT_NONE;
        if (rev != `CSR_CTL_REV) fault = `CSR_CTL_FAULT_REV;
        else if (kind > `CSR_CTL_KIND_HALT || address_mode > `CSR_CTL_ADDR_SCRATCH || reserved_set ||
                 (kind == `CSR_CTL_KIND_LOOP_BEGIN && count == 0)) fault = `CSR_CTL_FAULT_WORD;
        else if (flags != 0 || repeat_count != 0 || immediate != 0 ||
                 (kind != `CSR_CTL_KIND_LOOP_BEGIN && count != 0) ||
                 (kind != `CSR_CTL_KIND_LOOP_BEGIN && kind != `CSR_CTL_KIND_LOOP_END && loop_target != 0) ||
                 (kind != `CSR_CTL_KIND_BRANCH && branch_target != 0) ||
                 (kind != `CSR_CTL_KIND_BRANCH && kind != `CSR_CTL_KIND_WAIT && predicate != 0) ||
                 (kind != `CSR_CTL_KIND_ADDRESS && (address_mode != 0 || address != 0 || stride != 0)) ||
                 (kind == `CSR_CTL_KIND_ADDRESS && address_mode == 0)) fault = `CSR_CTL_FAULT_EXEC;
    end
endmodule
