// Canonical decode for the unified sparse execution ISA.
//
// A context word is still backward-compatible with the existing sequencer,
// but every issued operation now has an explicit phase, engine owner and
// dependency mask before it enters the packet pipe.
module phase_isa_decoder (
    input  wire [63:0] ctx_word,
    input  wire         ctx_valid,
    output reg  [3:0]   phase,
    output reg  [3:0]   engine,
    output wire [3:0]   owner,
    output reg  [7:0]   dependency_mask,
    output wire [3:0]   opcode,
    output wire         is_control,
    output wire         is_last
);
    localparam [3:0] UOP_REDUCE = 4'd4;
    localparam [3:0] UOP_SELECT = 4'd5;
    localparam [3:0] UOP_CANDIDATE = 4'd6;
    localparam [3:0] UOP_DMA = 4'd7;
    localparam [3:0] UOP_SPARSE = 4'd8;
    localparam [3:0] UOP_BITMAP = 4'd9;

    localparam [3:0] PH_NOP = 4'd0;
    localparam [3:0] PH_CORRELATE = 4'd1;
    localparam [3:0] PH_TOPK = 4'd2;
    localparam [3:0] PH_SUPPORT = 4'd3;
    localparam [3:0] PH_SOLVE = 4'd4;
    localparam [3:0] PH_RESIDUAL = 4'd5;
    localparam [3:0] PH_VECTOR = 4'd6;
    localparam [3:0] PH_CONTROL = 4'd7;

    localparam [3:0] ENG_NONE = 4'd0;
    localparam [3:0] ENG_CORRELATE = 4'd1;
    localparam [3:0] ENG_TOPK = 4'd2;
    localparam [3:0] ENG_SUPPORT = 4'd3;
    localparam [3:0] ENG_LS = 4'd4;
    localparam [3:0] ENG_RESIDUAL = 4'd5;
    localparam [3:0] ENG_VECTOR = 4'd6;
    localparam [3:0] ENG_CONTROL = 4'd7;

    assign owner = ctx_word[59:56];
    assign opcode = ctx_word[23:20];
    assign is_control = ctx_word[59:56] == 4'd9;
    assign is_last = ctx_word[47:44] == 4'd6;

    always @(*) begin
        phase = PH_NOP;
        engine = ENG_NONE;
        dependency_mask = 8'h00;
        if (ctx_valid) begin
            case (ctx_word[59:56])
                UOP_SELECT: begin
                    phase = PH_TOPK;
                    engine = ENG_TOPK;
                    // Correlation data must be valid before streamed top-K.
                    dependency_mask = 8'h01;
                end
                UOP_CANDIDATE: begin
                    phase = PH_SUPPORT;
                    engine = ENG_SUPPORT;
                    // Candidate edits consume the preceding top-K result.
                    dependency_mask = 8'h02;
                end
                UOP_SPARSE: begin
                    case (ctx_word[23:20])
                        4'd0, 4'd6: begin
                            phase = PH_SOLVE;
                            engine = ENG_LS;
                            dependency_mask = 8'h04;
                        end
                        4'd1, 4'd8: begin
                            phase = PH_CORRELATE;
                            engine = ENG_CORRELATE;
                            dependency_mask = 8'h08;
                        end
                        4'd3: begin
                            phase = PH_RESIDUAL;
                            engine = ENG_RESIDUAL;
                            dependency_mask = 8'h10;
                        end
                        default: begin
                            phase = PH_VECTOR;
                            engine = ENG_VECTOR;
                            dependency_mask = 8'h20;
                        end
                    endcase
                end
                UOP_REDUCE: begin
                    phase = PH_TOPK;
                    engine = ENG_TOPK;
                    dependency_mask = 8'h01;
                end
                UOP_DMA: begin
                    phase = PH_CONTROL;
                    engine = ENG_CONTROL;
                    dependency_mask = 8'h40;
                end
                UOP_BITMAP: begin
                    phase = PH_CONTROL;
                    engine = ENG_CONTROL;
                    dependency_mask = 8'h80;
                end
                default: begin
                    phase = PH_NOP;
                    engine = ENG_NONE;
                    dependency_mask = 8'h00;
                end
            endcase
        end
    end
endmodule
