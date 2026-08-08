module sparse_kernel_service_engine #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer MEM_AW = 10,
    parameter integer IDX_W = 10,
    parameter integer CTX_W = 64,
    parameter integer MAX_M = 256,
    parameter integer MAX_N = 256,
    parameter integer MAX_K = 16,
    parameter integer REFINE_ITERS = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_error_pulse,
    input  wire                     start_pulse,
    input  wire                     support_clear_selected,
    input  wire                     ctx_valid,
    input  wire [CTX_W-1:0]         ctx_word,
    input  wire [3:0]               uop_class,
    input  wire [3:0]               ext_ctrl,
    input  wire [COLS-1:0]          lane_valid,
    input  wire [COLS-1:0]          select_lane_valid,
    input  wire                     ls_start,
    input  wire [3:0]               scalar_op_low,
    input  wire [IDX_W-1:0]         m_size,
    input  wire [IDX_W-1:0]         n_size,
    input  wire [7:0]               sparse_k_active,
    input  wire [31:0]              seed,
    input  wire [3:0]               mu_shift_cfg,
    input  wire signed [DATA_W-1:0] phi_scale_q8_8,
    input  wire [1:0]               phi_kind,
    input  wire [COLS*DATA_W-1:0]   phi_bus,
    input  wire [IDX_W-1:0]         addr_support_query_base,
    input  wire [IDX_W-1:0]         base_idx,
    input  wire [IDX_W-1:0]         select_base_idx,
    input  wire                     addr_valid,
    input  wire                     addr_done,
    input  wire                     select_addr_valid,
    input  wire                     select_addr_done,
    input  wire [COLS*DATA_W-1:0]   spm_pa_rdata,
    input  wire [COLS*DATA_W-1:0]   select_spm_pa_rdata,
    input  wire [COLS*64-1:0]       pe_rhs_product_bus,
    input  wire [COLS*64-1:0]       pe_corr_acc_bus,
    input  wire [4*COLS*64-1:0]     ls_wide_product_bus,
    input  wire [SCALAR_W-1:0]      last_result_value,
    input  wire [IDX_W-1:0]         last_result_idx,

    output wire [COLS-1:0]          support_lane_mask,
    output wire [COLS-1:0]          selected_lane_mask,
    output wire [5:0]               support_depth0,
    output wire [IDX_W-1:0]         support0_w,
    output wire [IDX_W-1:0]         support1_w,
    output wire [IDX_W-1:0]         support2_w,
    output wire [IDX_W-1:0]         support3_w,
    output wire [IDX_W-1:0]         support4_w,
    output wire [IDX_W-1:0]         support5_w,
    output wire [IDX_W-1:0]         support6_w,
    output wire [IDX_W-1:0]         support7_w,
    output wire [IDX_W-1:0]         support8_w,
    output wire [IDX_W-1:0]         support9_w,
    output wire [IDX_W-1:0]         support10_w,
    output wire [IDX_W-1:0]         support11_w,
    output wire [IDX_W-1:0]         support12_w,
    output wire [IDX_W-1:0]         support13_w,
    output wire [IDX_W-1:0]         support14_w,
    output wire [IDX_W-1:0]         support15_w,
    output wire [IDX_W-1:0]         support16_w,
    output wire [IDX_W-1:0]         support17_w,
    output wire [IDX_W-1:0]         support18_w,
    output wire [IDX_W-1:0]         support19_w,
    output wire [IDX_W-1:0]         support20_w,
    output wire [IDX_W-1:0]         support21_w,
    output wire [IDX_W-1:0]         support22_w,
    output wire [IDX_W-1:0]         support23_w,
    output wire [IDX_W-1:0]         support24_w,
    output wire [IDX_W-1:0]         support25_w,
    output wire [IDX_W-1:0]         support26_w,
    output wire [IDX_W-1:0]         support27_w,
    output wire [IDX_W-1:0]         support28_w,
    output wire [IDX_W-1:0]         support29_w,
    output wire [IDX_W-1:0]         support30_w,
    output wire [IDX_W-1:0]         support31_w,

    output wire                     reduce_valid,
    output wire [SCALAR_W-1:0]      reduce_result,
    output wire [IDX_W-1:0]         reduce_idx,
    output wire                     reduce_converged,

    output wire                     ls_busy,
    output wire                     ls_done,
    output wire [SCALAR_W-1:0]      ls_result,
    output wire [MEM_AW-1:0]        ls_rd_addr,
    output wire [COLS*MEM_AW-1:0]   ls_wr_addr,
    output wire [COLS*DATA_W-1:0]   ls_wr_data,
    output wire [COLS-1:0]          ls_wr_en,
    output wire [COLS*DATA_W-1:0]   ls_pe_rhs_phi_bus,
    output wire [COLS*DATA_W-1:0]   ls_pe_rhs_y_bus,
    output wire                     ls_pe_rhs_active,
    output wire                     pe_sparse_clear,
    output wire                     pe_corr_acc_clear,
    output wire                     pe_corr_acc_en,
    output wire [3:0]               pe_sparse_op,
    output wire                     ls_wide_mul_active,
    output wire                     ls_wide_vertical_active,
    output wire [4:0]               ls_wide_vertical_tag,
    output wire [4*COLS*DATA_W-1:0] ls_wide_a_bus,
    output wire [4*COLS*DATA_W-1:0] ls_wide_b_bus,
    output wire                     factor_pipe_valid,
    output wire [4:0]               factor_pipe_tag,
    output wire [IDX_W-1:0]         factor_pipe_value,
    output wire [5:0]               factor_pipe_cache_k,
    output wire [MAX_K*IDX_W-1:0]   factor_pipe_cache_bus,
    input  wire                     factor_pipe_resp_valid,
    input  wire [4:0]               factor_pipe_resp_tag,
    input  wire [IDX_W-1:0]         factor_pipe_resp_value,
    input  wire [MAX_K-1:0]         factor_pipe_resp_match_mask,
    output wire                     topk_pipe_clear,
    output wire                     topk_pipe_token_valid,
    output wire [IDX_W-1:0]         topk_pipe_token_idx,
    output wire [DATA_W-1:0]        topk_pipe_token_score,
    output wire                     topk_pipe_token_eligible,
    output wire                     topk_pipe_stream_done,
    output wire [5:0]               topk_pipe_max_count,
    input  wire                     topk_pipe_result_valid,
    input  wire [5:0]               topk_pipe_result_count,
    input  wire [MAX_K*IDX_W-1:0]   topk_pipe_result_idx_bus,
    output wire                     mesh_ctx_valid,
    output wire [CTX_W-1:0]         mesh_ctx_word,
    output wire [1:0]               mesh_ctx_mode,
    output wire [IDX_W-1:0]         mesh_ctx_base_idx,
    output wire [IDX_W-1:0]         mesh_ctx_limit,
    output wire [DATA_W-1:0]        mesh_ctx_threshold,
    output wire [3:0]               mesh_ctx_shift,
    output wire [COLS*DATA_W-1:0]   mesh_ctx_x_bus,
    output wire [COLS*DATA_W-1:0]   mesh_ctx_delta_bus,
    output wire [COLS-1:0]          mesh_ctx_keep_bus,
    input  wire [COLS*DATA_W-1:0]   mesh_ctx_commit_data,
    output wire                     support_done,
    output wire [IDX_W-1:0]         support_result_idx,
    output wire                     support_result_valid,
    output wire                     select_done
);
    wire select_append_valid;
    wire [IDX_W-1:0] select_append_idx;
    wire [2:0] select_append_path;
    wire select_busy;
    wire ls_done_raw;
    wire select_start = ctx_valid && (uop_class == 4'd5) && ((ctx_word[27:24] == 4'd1) || (ctx_word[27:24] == 4'd2) || (ctx_word[27:24] == 4'd3));
    wire stream_select_start = select_start && ctx_word[31];
    wire nonstream_select_start = select_start && !ctx_word[31];
    wire [5:0] select_max_count = (ctx_word[15:11] == 5'd0) ? MAX_K[5:0] : {1'b0, ctx_word[15:11]};
    wire [2:0] select_append_path_cfg = ctx_word[22:20];
    wire select_exclude_support = (ctx_word[27:24] == 4'd2);
    wire select_allow_tiny = ctx_word[30] || (ctx_word[27:24] == 4'd3);
    wire topk_busy;
    wire topk_done;
    reg select_busy_q;
    reg select_done_q;
    assign select_busy = select_busy_q;
    assign select_done = select_done_q;
    reg stream_select_pending_q;
    reg ls_done_deferred_q;
    // Timing-isolated sample used only by the loop controller.  It is aligned
    // with cgra_top's registered sparse_k_active value, so both operands seen
    // by the controller describe the same support-depth cycle.
    reg [5:0] support_depth_ctrl_q;

    wire ls_corr_stream_valid;
    wire ls_corr_stream_done;
    wire [IDX_W-1:0] ls_corr_stream_base_idx;
    wire [COLS-1:0] ls_corr_stream_lane_valid;
    wire [COLS*DATA_W-1:0] ls_corr_stream_data;
    wire topk_stream_ready;
    wire [32*IDX_W-1:0] support_bus_w;
    assign support_bus_w = {support31_w, support30_w, support29_w, support28_w, support27_w, support26_w, support25_w, support24_w, support23_w, support22_w, support21_w, support20_w, support19_w, support18_w, support17_w, support16_w, support15_w, support14_w, support13_w, support12_w, support11_w, support10_w, support9_w, support8_w, support7_w, support6_w, support5_w, support4_w, support3_w, support2_w, support1_w, support0_w};

    reduce_scan #(.COLS(COLS), .DATA_W(DATA_W), .SCALAR_W(SCALAR_W), .IDX_W(IDX_W)) u_reduce_scan (
        .clk(clk), .rst_n(rst_n), .ctx_valid(ctx_valid), .uop_class(uop_class),
        .lane_valid(select_lane_valid), .base_idx(select_base_idx), .addr_valid(select_addr_valid), .addr_done(select_addr_done),
        .spm_pa_rdata(select_spm_pa_rdata),
        .reduce_valid(reduce_valid), .reduce_result(reduce_result),
        .reduce_idx(reduce_idx), .reduce_converged(reduce_converged)
    );

    support_set_service #(.COLS(COLS), .IDX_W(IDX_W), .CTX_W(CTX_W), .SCALAR_W(SCALAR_W)) u_support_service (
        .clk(clk), .rst_n(rst_n),
        .clear_error_pulse(clear_error_pulse), .start_pulse(start_pulse), .support_clear_selected(support_clear_selected),
        .ctx_valid(ctx_valid), .ctx_word(ctx_word), .uop_class(uop_class), .ext_ctrl(ext_ctrl),
        .reduce_valid(reduce_valid), .reduce_idx(reduce_idx),
        .addr_support_query_base(addr_support_query_base), .base_idx(base_idx),
        .last_result_value(last_result_value), .last_result_idx(last_result_idx),
        .select_append_valid(select_append_valid), .select_append_idx(select_append_idx), .select_append_path(select_append_path),
        .support_lane_mask(support_lane_mask), .selected_lane_mask(selected_lane_mask),
        .depth0(support_depth0),
        .support0(support0_w), .support1(support1_w), .support2(support2_w), .support3(support3_w),
        .support4(support4_w), .support5(support5_w), .support6(support6_w), .support7(support7_w),
        .support8(support8_w), .support9(support9_w), .support10(support10_w), .support11(support11_w),
        .support12(support12_w), .support13(support13_w), .support14(support14_w), .support15(support15_w),
        .support16(support16_w), .support17(support17_w), .support18(support18_w), .support19(support19_w), .support20(support20_w), .support21(support21_w), .support22(support22_w), .support23(support23_w),
        .support24(support24_w), .support25(support25_w), .support26(support26_w), .support27(support27_w), .support28(support28_w), .support29(support29_w), .support30(support30_w), .support31(support31_w), .op_done(support_done), .result_idx(support_result_idx), .result_valid(support_result_valid)
    );


    pe_stream_topk_serial_service #(.COLS(COLS), .DATA_W(DATA_W), .IDX_W(IDX_W), .MAX_SEL(MAX_K), .MAX_SUPPORT(MAX_K)) u_stream_topk (
        .clk(clk), .rst_n(rst_n), .start(stream_select_start), .max_count(select_max_count), .append_path_in(select_append_path_cfg),
        .exclude_support(select_exclude_support), .allow_tiny(select_allow_tiny),
        .stream_valid(ls_corr_stream_valid), .stream_done(ls_corr_stream_done), .stream_base_idx(ls_corr_stream_base_idx), .stream_lane_valid(ls_corr_stream_lane_valid), .stream_data(ls_corr_stream_data),
        .support_depth(support_depth0), .support_bus(support_bus_w[MAX_K*IDX_W-1:0]), .append_done(support_done),
        .pe_clear(topk_pipe_clear), .pe_token_valid(topk_pipe_token_valid),
        .pe_token_idx(topk_pipe_token_idx), .pe_token_score(topk_pipe_token_score),
        .pe_token_eligible(topk_pipe_token_eligible), .pe_stream_done(topk_pipe_stream_done),
        .pe_max_count(topk_pipe_max_count), .pe_result_valid(topk_pipe_result_valid),
        .pe_result_count(topk_pipe_result_count), .pe_result_idx_bus(topk_pipe_result_idx_bus),
        .append_valid(select_append_valid), .append_idx(select_append_idx), .append_path(select_append_path),
        .stream_ready(topk_stream_ready), .busy(topk_busy), .done(topk_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            select_busy_q <= 1'b0;
            select_done_q <= 1'b0;
            support_depth_ctrl_q <= 6'd0;
        end else begin
            support_depth_ctrl_q <= support_depth0;
            select_done_q <= 1'b0;
            if (stream_select_start) begin
                select_busy_q <= 1'b1;
            end else if (nonstream_select_start) begin
                select_busy_q <= 1'b1;
                select_done_q <= 1'b1;
            end else if (topk_done) begin
                select_busy_q <= 1'b0;
                select_done_q <= 1'b1;
            end else if (!topk_busy && !stream_select_start) begin
                select_busy_q <= 1'b0;
            end
        end
    end

    sparse_loop_controller #(.COLS(COLS), .DATA_W(DATA_W), .SCALAR_W(SCALAR_W), .MEM_AW(MEM_AW), .IDX_W(IDX_W), .MAX_M(MAX_M), .MAX_N(MAX_N), .MAX_K(MAX_K), .REFINE_ITERS(REFINE_ITERS)) u_sparse_loop_controller (
        .clk(clk), .rst_n(rst_n), .ctx_valid(ctx_valid), .ctx_word(ctx_word),
        .start(ls_start), .op(scalar_op_low), .m_size(m_size), .n_size(n_size),
        .k_active(sparse_k_active), .support_depth0(support_depth_ctrl_q), .seed(seed), .mu_shift_cfg(mu_shift_cfg), .scale_q(phi_scale_q8_8), .phi_kind(phi_kind), .phi_bus(phi_bus),
        .pe_rhs_product_bus(pe_rhs_product_bus), .pe_corr_acc_bus(pe_corr_acc_bus), .last_result_value(last_result_value), .last_result_idx(last_result_idx), .pe_rhs_phi_bus(ls_pe_rhs_phi_bus), .pe_rhs_y_bus(ls_pe_rhs_y_bus), .pe_rhs_active(ls_pe_rhs_active), .pe_sparse_clear(pe_sparse_clear), .pe_corr_acc_clear(pe_corr_acc_clear), .pe_corr_acc_en(pe_corr_acc_en), .pe_sparse_op(pe_sparse_op),
        .factor_pipe_valid(factor_pipe_valid), .factor_pipe_tag(factor_pipe_tag), .factor_pipe_value(factor_pipe_value), .factor_pipe_cache_k(factor_pipe_cache_k), .factor_pipe_cache_bus(factor_pipe_cache_bus),
        .factor_pipe_resp_valid(factor_pipe_resp_valid), .factor_pipe_resp_tag(factor_pipe_resp_tag), .factor_pipe_resp_value(factor_pipe_resp_value), .factor_pipe_resp_match_mask(factor_pipe_resp_match_mask),
        .ls_wide_mul_active(ls_wide_mul_active), .ls_wide_vertical_active(ls_wide_vertical_active), .ls_wide_vertical_tag(ls_wide_vertical_tag), .ls_wide_a_bus(ls_wide_a_bus), .ls_wide_b_bus(ls_wide_b_bus), .ls_wide_product_bus(ls_wide_product_bus),
        .corr_stream_valid(ls_corr_stream_valid), .corr_stream_done(ls_corr_stream_done), .corr_stream_base_idx(ls_corr_stream_base_idx), .corr_stream_lane_valid(ls_corr_stream_lane_valid), .corr_stream_data(ls_corr_stream_data),
        .corr_stream_active(stream_select_pending_q), .corr_stream_ready(topk_stream_ready),
        .support0(support0_w), .support1(support1_w), .support2(support2_w), .support3(support3_w), .support4(support4_w), .support5(support5_w), .support6(support6_w), .support7(support7_w),
        .support8(support8_w), .support9(support9_w), .support10(support10_w), .support11(support11_w), .support12(support12_w), .support13(support13_w), .support14(support14_w), .support15(support15_w),
        .support16(support16_w), .support17(support17_w), .support18(support18_w), .support19(support19_w), .support20(support20_w), .support21(support21_w), .support22(support22_w), .support23(support23_w),
        .support24(support24_w), .support25(support25_w), .support26(support26_w), .support27(support27_w), .support28(support28_w), .support29(support29_w), .support30(support30_w), .support31(support31_w),
        .rd_addr(ls_rd_addr), .rd_data(spm_pa_rdata),
        .wr_addr(ls_wr_addr), .wr_data(ls_wr_data), .wr_en(ls_wr_en),
        .mesh_ctx_valid(mesh_ctx_valid), .mesh_ctx_word(mesh_ctx_word), .mesh_ctx_mode(mesh_ctx_mode), .mesh_ctx_base_idx(mesh_ctx_base_idx), .mesh_ctx_limit(mesh_ctx_limit), .mesh_ctx_threshold(mesh_ctx_threshold), .mesh_ctx_shift(mesh_ctx_shift), .mesh_ctx_x_bus(mesh_ctx_x_bus), .mesh_ctx_delta_bus(mesh_ctx_delta_bus), .mesh_ctx_keep_bus(mesh_ctx_keep_bus), .mesh_ctx_commit_data(mesh_ctx_commit_data),
        .busy(ls_busy), .done(ls_done_raw), .result(ls_result)
    );

wire stream_select_ctx = ctx_valid && (uop_class == 4'd5) && ctx_word[31];
wire ls_done_deferred_fire = ls_done_deferred_q && !stream_select_pending_q && !select_busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stream_select_pending_q <= 1'b0;
        ls_done_deferred_q <= 1'b0;
    end else if (clear_error_pulse || (start_pulse && !stream_select_ctx)) begin
        stream_select_pending_q <= 1'b0;
        ls_done_deferred_q <= 1'b0;
    end else begin
        if (stream_select_ctx)
            stream_select_pending_q <= 1'b1;
        if (ls_done_raw && stream_select_pending_q && select_busy)
            ls_done_deferred_q <= 1'b1;
        if (select_done)
            stream_select_pending_q <= 1'b0;
        if (ls_done_deferred_fire)
            ls_done_deferred_q <= 1'b0;
    end
end

assign ls_done = (ls_done_raw && !(stream_select_pending_q && select_busy)) || ls_done_deferred_fire;

endmodule

`include "support_set_service.vh"
