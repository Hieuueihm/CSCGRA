// Normalizes support/factor-cache outcomes into a small ISA relation opcode.
// The existing factor scanner remains the producer of the predicates; this
// unit is the architectural boundary that will later own relation-specific
// LS issue sequences.
module support_relation_unit (
    input  wire       exact_hit,
    input  wire       prefix_hit,
    input  wire       truncate_hit,
    input  wire       swap_last_hit,
    output reg  [2:0] relation_opcode,
    output reg  [1:0] reuse_mode,
    output reg        border_clear,
    output wire       reuse_enable
);
    localparam [2:0] REL_NONE = 3'd0;
    localparam [2:0] REL_EXACT = 3'd1;
    localparam [2:0] REL_PREFIX = 3'd2;
    localparam [2:0] REL_TRUNCATE = 3'd3;
    localparam [2:0] REL_SWAP_LAST = 3'd4;
    localparam [1:0] REUSE_NONE = 2'd0;
    localparam [1:0] REUSE_EXACT = 2'd1;
    localparam [1:0] REUSE_PREFIX = 2'd2;

    always @(*) begin
        relation_opcode = REL_NONE;
        reuse_mode = REUSE_NONE;
        border_clear = 1'b0;
        // Preserve the controller's existing priority: exact/truncate,
        // prefix, then the safe last-rank swap.
        if (exact_hit) begin
            relation_opcode = REL_EXACT;
            reuse_mode = REUSE_EXACT;
        end else if (truncate_hit) begin
            relation_opcode = REL_TRUNCATE;
            reuse_mode = REUSE_EXACT;
        end else if (prefix_hit) begin
            relation_opcode = REL_PREFIX;
            reuse_mode = REUSE_PREFIX;
        end else if (swap_last_hit) begin
            relation_opcode = REL_SWAP_LAST;
            reuse_mode = REUSE_PREFIX;
            border_clear = 1'b1;
        end
    end

    assign reuse_enable = (relation_opcode != REL_NONE);
endmodule
