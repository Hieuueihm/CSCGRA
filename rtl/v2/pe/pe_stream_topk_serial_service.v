module pe_stream_topk_serial_service #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer IDX_W = 10,
    parameter integer MAX_SEL = 16,
    parameter integer MAX_SUPPORT = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [5:0]                   max_count,
    input  wire [2:0]                   append_path_in,
    input  wire                         sort_append_by_idx,
    input  wire                         exclude_support,
    input  wire                         allow_tiny,
    input  wire                         stream_valid,
    input  wire                         stream_done,
    input  wire [IDX_W-1:0]             stream_base_idx,
    input  wire [COLS-1:0]              stream_lane_valid,
    input  wire [COLS*DATA_W-1:0]       stream_data,
    input  wire [5:0]                   support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,

    // Score tokens are serialized only at the row0 ingress.  Ranking state
    // lives in the PE0->PE3 wavefront and returns a PE3-committed list.
    output reg                          pe_clear,
    output reg                          pe_token_valid,
    output reg  [IDX_W-1:0]             pe_token_idx,
    output reg  [DATA_W-1:0]            pe_token_score,
    output reg                          pe_token_eligible,
    output reg                          pe_stream_done,
    output reg  [5:0]                   pe_max_count,
    input  wire                         pe_result_valid,
    input  wire [5:0]                   pe_result_count,
    input  wire [MAX_SEL*IDX_W-1:0]     pe_result_idx_bus,

    input  wire                         append_done,
    output reg                          append_valid,
    output reg  [IDX_W-1:0]             append_idx,
    output reg  [2:0]                   append_path,
    output reg                          stream_ready,
    output reg                          busy,
    output reg                          done
);
    function [DATA_W-1:0] abs_data;
        input [DATA_W-1:0] value;
        begin
            if (value == {1'b1, {(DATA_W-1){1'b0}}})
                abs_data = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1])
                abs_data = ~value + 1'b1;
            else
                abs_data = value;
        end
    endfunction

    function support_has_idx;
        input [IDX_W-1:0] idx;
        integer support_rank;
        begin
            support_has_idx = 1'b0;
            for (support_rank = 0; support_rank < MAX_SUPPORT; support_rank = support_rank + 1)
                if ((support_rank < support_depth) &&
                    (support_bus[support_rank*IDX_W +: IDX_W] == idx))
                    support_has_idx = 1'b1;
        end
    endfunction

    localparam [2:0] S_IDLE=3'd0, S_CAPTURE=3'd1, S_ISSUE=3'd2,
                     S_WAIT_RESULT=3'd3, S_APPEND=3'd4, S_DONE=3'd5,
                     S_SORT_SCAN=3'd6, S_SORT_WAIT=3'd7;
    reg [2:0] state_q;
    reg [COLS-1:0] block_valid_q;
    reg [COLS*DATA_W-1:0] block_data_q;
    reg [IDX_W-1:0] block_base_q;
    reg block_done_q;
    reg [2:0] lane_q;
    reg [5:0] result_count_q;
    reg [MAX_SEL*IDX_W-1:0] result_idx_bus_q;
    reg [5:0] append_pos_q;
    reg append_wait_q;
    reg sort_append_q;
    reg [MAX_SEL-1:0] sort_used_q;
    reg [5:0] sort_scan_pos_q;
    reg [5:0] sort_best_pos_q;
    reg [IDX_W-1:0] sort_best_idx_q;
    wire [IDX_W-1:0] issue_idx_w = block_base_q + lane_q;
    wire [DATA_W-1:0] issue_abs_w =
        abs_data(block_data_q[lane_q*DATA_W +: DATA_W]);
    wire issue_eligible_w = block_valid_q[lane_q] &&
        (allow_tiny || (issue_abs_w > {{(DATA_W-1){1'b0}}, 1'b1})) &&
        (!exclude_support || !support_has_idx(issue_idx_w));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            pe_clear <= 1'b0;
            pe_token_valid <= 1'b0;
            pe_token_idx <= {IDX_W{1'b0}};
            pe_token_score <= {DATA_W{1'b0}};
            pe_token_eligible <= 1'b0;
            pe_stream_done <= 1'b0;
            pe_max_count <= 6'd0;
            append_valid <= 1'b0;
            append_idx <= {IDX_W{1'b0}};
            append_path <= 3'd0;
            stream_ready <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            block_valid_q <= {COLS{1'b0}};
            block_data_q <= {COLS*DATA_W{1'b0}};
            block_base_q <= {IDX_W{1'b0}};
            block_done_q <= 1'b0;
            lane_q <= 3'd0;
            result_count_q <= 6'd0;
            result_idx_bus_q <= {MAX_SEL*IDX_W{1'b0}};
            append_pos_q <= 6'd0;
            append_wait_q <= 1'b0;
            sort_append_q <= 1'b0;
            sort_used_q <= {MAX_SEL{1'b0}};
            sort_scan_pos_q <= 6'd0;
            sort_best_pos_q <= 6'd0;
            sort_best_idx_q <= {IDX_W{1'b1}};
        end else begin
            pe_clear <= 1'b0;
            pe_token_valid <= 1'b0;
            pe_stream_done <= 1'b0;
            append_valid <= 1'b0;
            done <= 1'b0;
            case (state_q)
                S_IDLE: begin
                    busy <= 1'b0;
                    stream_ready <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        stream_ready <= 1'b1;
                        pe_clear <= 1'b1;
                        pe_max_count <= (max_count == 6'd0) ? MAX_SEL[5:0] : max_count;
                        append_path <= append_path_in;
                        append_pos_q <= 6'd0;
                        append_wait_q <= 1'b0;
                        sort_append_q <= sort_append_by_idx;
                        sort_used_q <= {MAX_SEL{1'b0}};
                        sort_scan_pos_q <= 6'd0;
                        sort_best_pos_q <= 6'd0;
                        sort_best_idx_q <= {IDX_W{1'b1}};
                        state_q <= S_CAPTURE;
                    end
                end
                S_CAPTURE: begin
                    busy <= 1'b1;
                    stream_ready <= 1'b1;
                    if (stream_valid) begin
                        block_valid_q <= stream_lane_valid;
                        block_data_q <= stream_data;
                        block_base_q <= stream_base_idx;
                        block_done_q <= stream_done;
                        lane_q <= 3'd0;
                        stream_ready <= 1'b0;
                        state_q <= S_ISSUE;
                    end else if (stream_done) begin
                        stream_ready <= 1'b0;
                        pe_stream_done <= 1'b1;
                        state_q <= S_WAIT_RESULT;
                    end
                end
                S_ISSUE: begin
                    busy <= 1'b1;
                    pe_token_valid <= 1'b1;
                    pe_token_idx <= issue_idx_w;
                    pe_token_score <= issue_abs_w;
                    pe_token_eligible <= issue_eligible_w;
                    if (lane_q == COLS-1) begin
                        if (block_done_q) begin
                            pe_stream_done <= 1'b1;
                            state_q <= S_WAIT_RESULT;
                        end else begin
                            stream_ready <= 1'b1;
                            state_q <= S_CAPTURE;
                        end
                    end else begin
                        lane_q <= lane_q + 1'b1;
                    end
                end
                S_WAIT_RESULT: begin
                    busy <= 1'b1;
                    stream_ready <= 1'b0;
                    if (pe_result_valid) begin
                        result_count_q <= pe_result_count;
                        result_idx_bus_q <= pe_result_idx_bus;
                        append_pos_q <= 6'd0;
                        state_q <= (pe_result_count == 0) ? S_DONE :
                                   (sort_append_q ? S_SORT_SCAN : S_APPEND);
                    end
                end
                S_APPEND: begin
                    busy <= 1'b1;
                    if (append_pos_q >= result_count_q) begin
                        state_q <= S_DONE;
                    end else if (append_wait_q) begin
                        if (append_done) begin
                            append_pos_q <= append_pos_q + 1'b1;
                            if (append_pos_q + 1'b1 >= result_count_q) begin
                                append_wait_q <= 1'b0;
                                state_q <= S_DONE;
                            end else begin
                                // support_set_service acknowledges from a
                                // register and is back in IDLE on this edge.
                                // Present the next already-registered index
                                // immediately, avoiding the otherwise empty
                                // re-issue clock between narrow appends.
                                append_valid <= 1'b1;
                                append_idx <= result_idx_bus_q[
                                    (append_pos_q + 1'b1)*IDX_W +: IDX_W];
                                append_wait_q <= 1'b1;
                            end
                        end
                    end else begin
                        append_valid <= 1'b1;
                        append_idx <= result_idx_bus_q[append_pos_q*IDX_W +: IDX_W];
                        append_wait_q <= 1'b1;
                    end
                end
                S_SORT_SCAN: begin
                    busy <= 1'b1;
                    if (append_pos_q >= result_count_q) begin
                        state_q <= S_DONE;
                    end else if (sort_scan_pos_q < result_count_q) begin
                        if (!sort_used_q[sort_scan_pos_q] &&
                            (result_idx_bus_q[sort_scan_pos_q*IDX_W +: IDX_W] < sort_best_idx_q)) begin
                            sort_best_idx_q <=
                                result_idx_bus_q[sort_scan_pos_q*IDX_W +: IDX_W];
                            sort_best_pos_q <= sort_scan_pos_q;
                        end
                        sort_scan_pos_q <= sort_scan_pos_q + 1'b1;
                    end else begin
                        // Reproduce candidate_append_path_ctx's ascending-index
                        // order without a wide combinational sorting network.
                        append_valid <= 1'b1;
                        append_idx <= sort_best_idx_q;
                        state_q <= S_SORT_WAIT;
                    end
                end
                S_SORT_WAIT: begin
                    busy <= 1'b1;
                    if (append_done) begin
                        sort_used_q[sort_best_pos_q] <= 1'b1;
                        append_pos_q <= append_pos_q + 1'b1;
                        sort_scan_pos_q <= 6'd0;
                        sort_best_pos_q <= 6'd0;
                        sort_best_idx_q <= {IDX_W{1'b1}};
                        state_q <= S_SORT_SCAN;
                    end
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state_q <= S_IDLE;
                end
                default: begin
                    state_q <= S_IDLE;
                    busy <= 1'b0;
                    stream_ready <= 1'b0;
                end
            endcase
        end
    end
endmodule
