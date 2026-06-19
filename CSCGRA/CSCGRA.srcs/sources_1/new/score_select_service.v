module score_select_service #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer IDX_W = 10,
    parameter integer CTX_W = 64,
    parameter integer MAX_SEL = 16,
    parameter integer MAX_SUPPORT = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   ctx_valid,
    input  wire [CTX_W-1:0]       ctx_word,
    input  wire [3:0]             uop_class,
    input  wire [COLS-1:0]        lane_valid,
    input  wire [IDX_W-1:0]       base_idx,
    input  wire                   addr_valid,
    input  wire                   addr_done,
    input  wire [COLS*DATA_W-1:0] spm_pa_rdata,
    input  wire [SCALAR_W-1:0]    threshold_value,
    input  wire [5:0]             support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,
    input  wire                   stream_valid,
    input  wire                   stream_done,
    input  wire [IDX_W-1:0]       stream_base_idx,
    input  wire [COLS-1:0]        stream_lane_valid,
    input  wire [COLS*DATA_W-1:0] stream_data,
    input  wire                   append_done,
    output wire                   append_valid,
    output wire [IDX_W-1:0]       append_idx,
    output wire [2:0]             append_path,
    output reg                    busy,
    output reg                    done
);
    wire stream_mode = ctx_word[31];
    wire select_start = ctx_valid && (uop_class == 4'd5) && ((ctx_word[27:24] == 4'd1) || (ctx_word[27:24] == 4'd2) || (ctx_word[27:24] == 4'd3));
    wire stream_select_start = select_start && stream_mode;
    wire nonstream_select_start = select_start && !stream_mode;
    wire [4:0] max_count_w = (ctx_word[15:11] == 5'd0) ? MAX_SEL[4:0] : ctx_word[15:11];
    wire [2:0] append_path_w = ctx_word[22:20];
    wire exclude_support_w = (ctx_word[27:24] == 4'd2);
    wire allow_tiny_w = ctx_word[30] || (ctx_word[27:24] == 4'd3);
    wire topk_busy;
    wire topk_done;

    pe_stream_topk_serial_service #(
        .COLS(COLS),
        .DATA_W(DATA_W),
        .IDX_W(IDX_W),
        .MAX_SEL(MAX_SEL),
        .MAX_SUPPORT(MAX_SUPPORT)
    ) u_stream_topk (
        .clk(clk),
        .rst_n(rst_n),
        .start(stream_select_start),
        .max_count(max_count_w),
        .append_path_in(append_path_w),
        .exclude_support(exclude_support_w),
        .allow_tiny(allow_tiny_w),
        .stream_valid(stream_valid),
        .stream_done(stream_done),
        .stream_base_idx(stream_base_idx),
        .stream_lane_valid(stream_lane_valid),
        .stream_data(stream_data),
        .support_depth(support_depth),
        .support_bus(support_bus),
        .append_done(append_done),
        .append_valid(append_valid),
        .append_idx(append_idx),
        .append_path(append_path),
        .stream_ready(),
        .busy(topk_busy),
        .done(topk_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (stream_select_start) begin
                busy <= 1'b1;
            end else if (nonstream_select_start) begin
                busy <= 1'b1;
                done <= 1'b1;
            end else if (topk_done) begin
                busy <= 1'b0;
                done <= 1'b1;
            end else if (!topk_busy && !stream_select_start) begin
                busy <= 1'b0;
            end
        end
    end
endmodule
