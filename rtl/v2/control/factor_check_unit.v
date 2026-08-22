// Factor-check scanner extracted from sparse_loop_controller.
//
// Streams the request support tuple by tuple into the PE0->PE3 factor pipe,
// accumulates the commutative reject fingerprint, the seen-mask, and the
// ordered/prefix bookkeeping, and maintains the normalized support view
// (config-match preload followed by unmatched appends in request order).
// The controller stays the owner of the DONE-time decisions: hit
// predicates, support_relation resolution, and the commit into
// support_cache[] at S_FACTOR_CHECK_DONE.
//
// Cycle contract: `start` is asserted combinationally while the controller
// is in S_FACTOR_CHECK_INIT; the unit runs its scan in lockstep while the
// controller sits in S_FACTOR_CHECK_SCAN, and `scan_done` is combinational
// on the last absorbed response so the controller's SCAN->DONE edge is the
// same cycle as before the extraction.
module factor_check_unit #(
    parameter integer IDX_W = 10,
    parameter integer MAX_K = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire                    config_match,
    input  wire [5:0]              request_k,
    input  wire [MAX_K*IDX_W-1:0]  request_support,
    input  wire [5:0]              cached_k,
    input  wire [MAX_K*IDX_W-1:0]  cached_support,
    input  wire                    resp_valid,
    input  wire [4:0]              resp_tag,
    input  wire [IDX_W-1:0]        resp_value,
    input  wire [MAX_K-1:0]        resp_match_mask,

    output wire                    scan_done,
    output wire [MAX_K*IDX_W-1:0]  norm_support_bus,
    output wire [31:0]             fingerprint_q,
    output wire [MAX_K-1:0]        seen_mask_q,
    output wire                    ordered_match_q,
    output wire                    prefix_ordered_q,
    output wire [1:0]              unmatched_count_q,
    output wire [4:0]              unmatched_tag_q,
    output wire [IDX_W-1:0]        unmatched_value_q,
    output reg                     pipe_valid,
    output reg  [4:0]              pipe_tag,
    output reg  [IDX_W-1:0]        pipe_value
);

    reg [5:0] factor_check_req_idx_q;
    reg [IDX_W-1:0] factor_check_request_value_q;
    reg [MAX_K*IDX_W-1:0] factor_check_request_shift_q;
    reg [MAX_K*IDX_W-1:0] norm_support_q;
    reg factor_check_ordered_match_q;
    reg factor_check_prefix_ordered_q;
    reg [5:0] factor_check_append_rank_q;
    reg [MAX_K-1:0] factor_check_seen_mask_q;
    reg [31:0] factor_check_fingerprint_q;
    reg [1:0] factor_check_unmatched_count_q;
    reg [4:0] factor_check_unmatched_tag_q;
    reg [IDX_W-1:0] factor_check_unmatched_value_q;
    reg scan_active_q;

    wire [31:0] factor_check_word_w = {{(32-IDX_W){1'b0}},
        factor_check_request_value_q};
    wire [31:0] factor_check_fingerprint_next_w =
        factor_check_fingerprint_q ^ factor_check_word_w ^
        (factor_check_word_w << 10) ^ (factor_check_word_w << 20) ^
        32'h9e3779b9;
    wire factor_pipe_resp_any_match_w = |resp_match_mask;
    wire factor_pipe_resp_ordered_match_w =
        ({1'b0, resp_tag} >= cached_k) || resp_match_mask[resp_tag];

    assign scan_done = scan_active_q && resp_valid &&
                       ({1'b0, resp_tag} + 1'b1 >= request_k);
    assign norm_support_bus = norm_support_q;
    assign fingerprint_q = factor_check_fingerprint_q;
    assign seen_mask_q = factor_check_seen_mask_q;
    assign ordered_match_q = factor_check_ordered_match_q;
    assign prefix_ordered_q = factor_check_prefix_ordered_q;
    assign unmatched_count_q = factor_check_unmatched_count_q;
    assign unmatched_tag_q = factor_check_unmatched_tag_q;
    assign unmatched_value_q = factor_check_unmatched_value_q;

    integer gi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            factor_check_req_idx_q <= 6'd0;
            factor_check_request_value_q <= {IDX_W{1'b0}};
            factor_check_request_shift_q <= {(MAX_K*IDX_W){1'b0}};
            norm_support_q <= {(MAX_K*IDX_W){1'b0}};
            factor_check_ordered_match_q <= 1'b0;
            factor_check_prefix_ordered_q <= 1'b0;
            factor_check_append_rank_q <= 6'd0;
            factor_check_seen_mask_q <= {MAX_K{1'b0}};
            factor_check_fingerprint_q <= 32'd0;
            factor_check_unmatched_count_q <= 2'd0;
            factor_check_unmatched_tag_q <= 5'd0;
            factor_check_unmatched_value_q <= {IDX_W{1'b0}};
            scan_active_q <= 1'b0;
            pipe_valid <= 1'b0;
            pipe_tag <= 5'd0;
            pipe_value <= {IDX_W{1'b0}};
        end else begin
            pipe_valid <= 1'b0;
            if (start) begin
                factor_check_req_idx_q <= 6'd0;
                factor_check_request_value_q <= request_support[0 +: IDX_W];
                factor_check_request_shift_q <= request_support >> IDX_W;
                factor_check_ordered_match_q <= config_match;
                factor_check_prefix_ordered_q <= config_match;
                factor_check_seen_mask_q <= {MAX_K{1'b0}};
                factor_check_fingerprint_q <=
                    32'h6d2b79f5 ^ {26'd0, request_k};
                factor_check_append_rank_q <= config_match ? cached_k : 6'd0;
                factor_check_unmatched_count_q <= 2'd0;
                factor_check_unmatched_tag_q <= 5'd0;
                factor_check_unmatched_value_q <= {IDX_W{1'b0}};
                norm_support_q <= config_match ? cached_support :
                                                request_support;
                scan_active_q <= config_match && (request_k != 0);
            end else if (scan_active_q) begin
                // One request token enters PE row0 per cycle.  The four rows
                // compare rank groups (rank mod 4) and PE3 returns a complete
                // match mask after the vertical pipe drain.
                if (factor_check_req_idx_q < request_k) begin
                    pipe_valid <= 1'b1;
                    pipe_tag <= factor_check_req_idx_q[4:0];
                    pipe_value <= factor_check_request_value_q;
                    factor_check_fingerprint_q <=
                        factor_check_fingerprint_next_w;
                    if (factor_check_req_idx_q + 1'b1 < request_k) begin
                        factor_check_req_idx_q <= factor_check_req_idx_q + 1'b1;
                        factor_check_request_value_q <=
                            factor_check_request_shift_q[0 +: IDX_W];
                        factor_check_request_shift_q <=
                            factor_check_request_shift_q >> IDX_W;
                    end else begin
                        // Mark all requests issued; responses continue to drain.
                        factor_check_req_idx_q <= request_k;
                    end
                end

                if (resp_valid) begin
                    factor_check_seen_mask_q <= factor_check_seen_mask_q |
                                                resp_match_mask;
                    factor_check_ordered_match_q <=
                        factor_check_ordered_match_q &&
                        factor_pipe_resp_ordered_match_w;
                    if ({1'b0, resp_tag} + 1'b1 < request_k)
                        factor_check_prefix_ordered_q <=
                            factor_check_prefix_ordered_q &&
                            factor_pipe_resp_ordered_match_w;
                    if (!factor_pipe_resp_any_match_w &&
                        (factor_check_append_rank_q < MAX_K)) begin
                        norm_support_q[factor_check_append_rank_q*IDX_W +: IDX_W] <=
                            resp_value;
                        factor_check_append_rank_q <=
                            factor_check_append_rank_q + 1'b1;
                    end
                    if (!factor_pipe_resp_any_match_w) begin
                        if (factor_check_unmatched_count_q != 2'b11)
                            factor_check_unmatched_count_q <=
                                factor_check_unmatched_count_q + 1'b1;
                        factor_check_unmatched_tag_q <= resp_tag;
                        factor_check_unmatched_value_q <= resp_value;
                    end
                    if (scan_done)
                        scan_active_q <= 1'b0;
                end
            end
        end
    end

endmodule
