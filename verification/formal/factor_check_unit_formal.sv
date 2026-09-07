`default_nettype none

module factor_check_unit_formal;
    localparam integer IDX_W = 10;
    localparam integer MAX_K = 16;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    (* anyseq *) reg start;
    (* anyconst *) reg config_match;
    (* anyconst *) reg [5:0] request_k;
    (* anyconst *) reg [MAX_K*IDX_W-1:0] request_support;
    (* anyconst *) reg [5:0] cached_k;
    (* anyconst *) reg [MAX_K*IDX_W-1:0] cached_support;
    (* anyseq *) reg resp_valid;
    (* anyseq *) reg [4:0] resp_tag;
    (* anyseq *) reg [IDX_W-1:0] resp_value;
    (* anyseq *) reg [MAX_K-1:0] resp_match_mask;

    wire scan_done;
    wire [MAX_K*IDX_W-1:0] norm_support_bus;
    wire [31:0] fingerprint_q;
    wire [MAX_K-1:0] seen_mask_q;
    wire ordered_match_q, prefix_ordered_q;
    wire [1:0] unmatched_count_q;
    wire [4:0] unmatched_tag_q;
    wire [IDX_W-1:0] unmatched_value_q;
    wire pipe_valid;
    wire [4:0] pipe_tag;
    wire [IDX_W-1:0] pipe_value;

    reg f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!f_past_valid)
            assume(!rst_n);
        else
            assume(rst_n);
        assume(request_k <= MAX_K);
        assume(cached_k <= MAX_K);
        if (resp_valid) begin
            assume({1'b0, resp_tag} < request_k);
            assume({1'b0, resp_tag} < MAX_K);
        end
    end

    factor_check_unit #(.IDX_W(IDX_W), .MAX_K(MAX_K)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .config_match(config_match), .request_k(request_k),
        .request_support(request_support), .cached_k(cached_k),
        .cached_support(cached_support), .resp_valid(resp_valid),
        .resp_tag(resp_tag), .resp_value(resp_value),
        .resp_match_mask(resp_match_mask), .scan_done(scan_done),
        .norm_support_bus(norm_support_bus), .fingerprint_q(fingerprint_q),
        .seen_mask_q(seen_mask_q), .ordered_match_q(ordered_match_q),
        .prefix_ordered_q(prefix_ordered_q),
        .unmatched_count_q(unmatched_count_q),
        .unmatched_tag_q(unmatched_tag_q),
        .unmatched_value_q(unmatched_value_q), .pipe_valid(pipe_valid),
        .pipe_tag(pipe_tag), .pipe_value(pipe_value)
    );
endmodule

`default_nettype wire
