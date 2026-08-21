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
    output reg                  phase_token_valid,
    output reg  [31:0]          phase_cycle_corr,
    output reg  [31:0]          phase_cycle_topk,
    output reg  [31:0]          phase_cycle_support,
    output reg  [31:0]          phase_cycle_solve,
    output reg  [31:0]          phase_cycle_residual,
    output reg  [31:0]          phase_cycle_vector
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

    // Narrow metadata packet for the PE0 -> PE1 -> PE2 -> PE3 control path.
    // Wide arithmetic data stays on its existing registered buses.
    wire [3:0] isa_phase_w;
    wire [3:0] isa_engine_w;
    wire [3:0] isa_owner_w;
    wire [7:0] isa_dependency_w;
    wire [3:0] isa_opcode_w;
    wire isa_control_w;
    wire isa_last_w;
    phase_isa_decoder u_phase_isa_decoder (
        .ctx_word(ctx_word), .ctx_valid(ctx_valid), .phase(isa_phase_w),
        .engine(isa_engine_w), .owner(isa_owner_w),
        .dependency_mask(isa_dependency_w), .opcode(isa_opcode_w),
        .is_control(isa_control_w), .is_last(isa_last_w)
    );
    wire [3:0] packet_mode_now = isa_engine_w;
    wire [3:0] packet_owner_now = isa_owner_w;
    wire [7:0] packet_version_now = sparse_writes_vector ? vector_version : support_version;
    wire [9:0] packet_idx_now = ctx_word[39:30];
    wire [23:0] packet_data_now = ctx_word[23:0];
    wire packet_valid_w;
    wire [3:0] packet_phase_w, packet_mode_w, packet_owner_w;
    wire [7:0] packet_dependency_w;
    wire [7:0] packet_version_w;
    wire [9:0] packet_idx_w;
    wire [23:0] packet_data_w;

    reg ls_done_deferred_q;
    wire ls_done_deferred_fire = ls_done_deferred_q &&
                                 !corr_stream_pending && !select_busy;
    assign ls_done = (ls_done_raw && !(corr_stream_pending && select_busy)) ||
                     ls_done_deferred_fire;

    always @(*) begin
        // Report the phase at the packet issue point.  During the four-cycle
        // PE0->PE3 flight the decoded context phase is still useful for
        // observability, but CSR counters must count only an issued token.
        phase_opcode = packet_valid_w ? packet_phase_w : isa_phase_w;
    end

    phase_packet_pipe #(.VERSION_W(VERSION_W), .IDX_W(10), .DATA_W(24), .STAGES(4))
    u_phase_packet_pipe (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(ctx_valid), .in_phase(phase_opcode),
        .in_mode(packet_mode_now), .in_owner(packet_owner_now),
        .in_dependency_mask(isa_dependency_w),
        .in_version(packet_version_now), .in_idx(packet_idx_now),
        .in_data(packet_data_now), .out_valid(packet_valid_w),
        .out_phase(packet_phase_w), .out_mode(packet_mode_w),
        .out_owner(packet_owner_w), .out_dependency_mask(packet_dependency_w),
        .out_version(packet_version_w),
        .out_idx(packet_idx_w), .out_data(packet_data_w)
    );

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
            phase_cycle_corr <= 32'd0;
            phase_cycle_topk <= 32'd0;
            phase_cycle_support <= 32'd0;
            phase_cycle_solve <= 32'd0;
            phase_cycle_residual <= 32'd0;
            phase_cycle_vector <= 32'd0;
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
            phase_cycle_corr <= 32'd0;
            phase_cycle_topk <= 32'd0;
            phase_cycle_support <= 32'd0;
            phase_cycle_solve <= 32'd0;
            phase_cycle_residual <= 32'd0;
            phase_cycle_vector <= 32'd0;
        end else begin
            phase_token_valid <= packet_valid_w;
            if (packet_valid_w) begin
                case (packet_phase_w)
                    PH_CORRELATE: phase_cycle_corr <= phase_cycle_corr + 1'b1;
                    PH_SELECT_TOPK: phase_cycle_topk <= phase_cycle_topk + 1'b1;
                    PH_SUPPORT_EDIT: phase_cycle_support <= phase_cycle_support + 1'b1;
                    PH_SOLVE: phase_cycle_solve <= phase_cycle_solve + 1'b1;
                    PH_RESIDUAL: phase_cycle_residual <= phase_cycle_residual + 1'b1;
                    PH_VECTOR: phase_cycle_vector <= phase_cycle_vector + 1'b1;
                    default: begin end
                endcase
            end
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
