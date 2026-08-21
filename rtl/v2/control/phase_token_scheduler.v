// Phase-token scheduler for the unified sparse-algorithm dataflow.
//
// Context words remain the externally visible pseudo-instructions.  This
// block turns them into a narrow, versioned token stream and owns the three
// producer/consumer fusions that cross service boundaries.  Keeping this
// state out of sparse_kernel_service_engine prevents algorithm-specific
// handshake bits from growing into another controller-wide decode cone.
module phase_token_scheduler #(
    parameter integer VERSION_W = 8
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 flush,
    input  wire                 ctx_valid,
    input  wire [63:0]          ctx_word,
    input  wire [3:0]           uop_class,
    input  wire [3:0]           ext_ctrl,
    input  wire                 ls_done_raw,
    input  wire                 select_busy,
    input  wire                 select_done,

    output reg                  corr_stream_pending,
    output reg                  corr_stream_post_update_x,
    output reg                  corr_stream_post_refine_support,
    output wire                 ls_done,
    output reg  [VERSION_W-1:0] support_version,
    output reg  [VERSION_W-1:0] vector_version,
    output reg  [VERSION_W-1:0] matrix_version,
    output reg  [3:0]           phase_opcode,
    output reg                  phase_token_valid
);
    localparam [3:0] UOP_SELECT    = 4'd5;
    localparam [3:0] UOP_CANDIDATE = 4'd6;
    localparam [3:0] UOP_SPARSE    = 4'd8;

    localparam [3:0] PH_NOP          = 4'd0;
    localparam [3:0] PH_CORRELATE    = 4'd1;
    localparam [3:0] PH_SELECT_TOPK  = 4'd2;
    localparam [3:0] PH_SUPPORT_EDIT = 4'd3;
    localparam [3:0] PH_SOLVE        = 4'd4;
    localparam [3:0] PH_RESIDUAL     = 4'd5;
    localparam [3:0] PH_VECTOR       = 4'd6;

    wire stream_select_ctx = ctx_valid && (uop_class == UOP_SELECT) &&
                             ctx_word[31];
    wire support_mutation_ctx = ctx_valid && (uop_class == UOP_CANDIDATE) &&
        // select-path is metadata only; append, copy, merge and depth updates
        // create a new logical support version.
        !((ext_ctrl == 4'b0110) && !ext_ctrl[3]);
    wire sparse_ctx = ctx_valid && (uop_class == UOP_SPARSE);
    wire [3:0] sparse_op = ctx_word[23:20];
    wire sparse_writes_vector = sparse_ctx &&
        ((sparse_op == 4'd0) || (sparse_op == 4'd2) ||
         (sparse_op == 4'd4) || (sparse_op == 4'd5) ||
         (sparse_op == 4'd6) || (sparse_op == 4'd7) ||
         (sparse_op == 4'd8) || (sparse_op == 4'd10));

    reg ls_done_deferred_q;
    wire ls_done_deferred_fire = ls_done_deferred_q &&
                                 !corr_stream_pending && !select_busy;
    assign ls_done = (ls_done_raw && !(corr_stream_pending && select_busy)) ||
                     ls_done_deferred_fire;

    always @(*) begin
        phase_opcode = PH_NOP;
        if (ctx_valid) begin
            case (uop_class)
                UOP_SELECT:    phase_opcode = PH_SELECT_TOPK;
                UOP_CANDIDATE: phase_opcode = PH_SUPPORT_EDIT;
                UOP_SPARSE: begin
                    case (sparse_op)
                        4'd0, 4'd6: phase_opcode = PH_SOLVE;
                        4'd1, 4'd8: phase_opcode = PH_CORRELATE;
                        4'd3:       phase_opcode = PH_RESIDUAL;
                        default:    phase_opcode = PH_VECTOR;
                    endcase
                end
                default: phase_opcode = PH_NOP;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            corr_stream_pending <= 1'b0;
            corr_stream_post_update_x <= 1'b0;
            corr_stream_post_refine_support <= 1'b0;
            ls_done_deferred_q <= 1'b0;
            support_version <= {VERSION_W{1'b0}};
            vector_version <= {VERSION_W{1'b0}};
            matrix_version <= {VERSION_W{1'b0}};
            phase_token_valid <= 1'b0;
        end else if (flush) begin
            corr_stream_pending <= 1'b0;
            corr_stream_post_update_x <= 1'b0;
            corr_stream_post_refine_support <= 1'b0;
            ls_done_deferred_q <= 1'b0;
            // A new job/configuration is a new matrix epoch.  Support and
            // vector epochs restart locally, avoiding wide global clears.
            support_version <= {VERSION_W{1'b0}};
            vector_version <= {VERSION_W{1'b0}};
            matrix_version <= matrix_version + 1'b1;
            phase_token_valid <= 1'b0;
        end else begin
            phase_token_valid <= ctx_valid;
            if (support_mutation_ctx)
                support_version <= support_version + 1'b1;
            if (sparse_writes_vector)
                vector_version <= vector_version + 1'b1;

            if (stream_select_ctx) begin
                corr_stream_pending <= 1'b1;
                // Existing context encoding is retained: bit29 selects the
                // post-update x producer, bit28 the post-REFINE sparse stream.
                corr_stream_post_update_x <= ctx_word[29];
                corr_stream_post_refine_support <= ctx_word[28];
            end
            if (ls_done_raw && corr_stream_pending && select_busy)
                ls_done_deferred_q <= 1'b1;
            if (select_done) begin
                corr_stream_pending <= 1'b0;
                corr_stream_post_update_x <= 1'b0;
                corr_stream_post_refine_support <= 1'b0;
            end
            if (ls_done_deferred_fire)
                ls_done_deferred_q <= 1'b0;
        end
    end
endmodule
