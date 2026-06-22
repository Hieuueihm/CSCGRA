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
    output wire                     support_done,
    output wire [IDX_W-1:0]         support_result_idx,
    output wire                     support_result_valid,
    output wire                     select_done
);

    wire [3:0] reduce_op_unused;
    wire select_append_valid;
    wire [IDX_W-1:0] select_append_idx;
    wire [2:0] select_append_path;
    wire select_busy;
    wire ls_done_raw;
    wire select_start = ctx_valid && (uop_class == 4'd5) && ((ctx_word[27:24] == 4'd1) || (ctx_word[27:24] == 4'd2) || (ctx_word[27:24] == 4'd3));
    wire stream_select_start = select_start && ctx_word[31];
    wire nonstream_select_start = select_start && !ctx_word[31];
    wire [4:0] select_max_count = (ctx_word[15:11] == 5'd0) ? MAX_K[4:0] : ctx_word[15:11];
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

    wire ls_corr_stream_valid;
    wire ls_corr_stream_done;
    wire [IDX_W-1:0] ls_corr_stream_base_idx;
    wire [COLS-1:0] ls_corr_stream_lane_valid;
    wire [COLS*DATA_W-1:0] ls_corr_stream_data;
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
        .reduce_valid(reduce_valid), .reduce_op(reduce_op_unused), .reduce_idx(reduce_idx),
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
        .append_valid(select_append_valid), .append_idx(select_append_idx), .append_path(select_append_path),
        .stream_ready(), .busy(topk_busy), .done(topk_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            select_busy_q <= 1'b0;
            select_done_q <= 1'b0;
        end else begin
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
        .k_active(sparse_k_active), .support_depth0(support_depth0), .seed(seed), .scale_q(phi_scale_q8_8), .phi_kind(phi_kind), .phi_bus(phi_bus),
        .pe_rhs_product_bus(pe_rhs_product_bus), .pe_corr_acc_bus(pe_corr_acc_bus), .last_result_value(last_result_value), .last_result_idx(last_result_idx), .pe_rhs_phi_bus(ls_pe_rhs_phi_bus), .pe_rhs_y_bus(ls_pe_rhs_y_bus), .pe_rhs_active(ls_pe_rhs_active), .pe_sparse_clear(pe_sparse_clear), .pe_corr_acc_clear(pe_corr_acc_clear), .pe_corr_acc_en(pe_corr_acc_en), .pe_sparse_op(pe_sparse_op),
        .corr_stream_valid(ls_corr_stream_valid), .corr_stream_done(ls_corr_stream_done), .corr_stream_base_idx(ls_corr_stream_base_idx), .corr_stream_lane_valid(ls_corr_stream_lane_valid), .corr_stream_data(ls_corr_stream_data),
        .support0(support0_w), .support1(support1_w), .support2(support2_w), .support3(support3_w), .support4(support4_w), .support5(support5_w), .support6(support6_w), .support7(support7_w),
        .support8(support8_w), .support9(support9_w), .support10(support10_w), .support11(support11_w), .support12(support12_w), .support13(support13_w), .support14(support14_w), .support15(support15_w),
        .support16(support16_w), .support17(support17_w), .support18(support18_w), .support19(support19_w), .support20(support20_w), .support21(support21_w), .support22(support22_w), .support23(support23_w),
        .support24(support24_w), .support25(support25_w), .support26(support26_w), .support27(support27_w), .support28(support28_w), .support29(support29_w), .support30(support30_w), .support31(support31_w),
        .rd_addr(ls_rd_addr), .rd_data(spm_pa_rdata),
        .wr_addr(ls_wr_addr), .wr_data(ls_wr_data), .wr_en(ls_wr_en),
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

module support_set_service #(
    parameter integer COLS     = 8,
    parameter integer IDX_W    = 10,
    parameter integer CTX_W    = 64,
    parameter integer SCALAR_W = 56
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
    input  wire                     reduce_valid,
    input  wire [3:0]               reduce_op,
    input  wire [IDX_W-1:0]         reduce_idx,
    input  wire [IDX_W-1:0]         addr_support_query_base,
    input  wire [IDX_W-1:0]         base_idx,
    input  wire [SCALAR_W-1:0]      last_result_value,
    input  wire [IDX_W-1:0]         last_result_idx,
    input  wire                     select_append_valid,
    input  wire [IDX_W-1:0]         select_append_idx,
    input  wire [2:0]               select_append_path,
    output reg  [COLS-1:0]          support_lane_mask,
    output reg  [COLS-1:0]          selected_lane_mask,
    output wire [5:0]               depth0,
    output wire [IDX_W-1:0]         support0,
    output wire [IDX_W-1:0]         support1,
    output wire [IDX_W-1:0]         support2,
    output wire [IDX_W-1:0]         support3,
    output wire [IDX_W-1:0]         support4,
    output wire [IDX_W-1:0]         support5,
    output wire [IDX_W-1:0]         support6,
    output wire [IDX_W-1:0]         support7,
    output wire [IDX_W-1:0]         support8,
    output wire [IDX_W-1:0]         support9,
    output wire [IDX_W-1:0]         support10,
    output wire [IDX_W-1:0]         support11,
    output wire [IDX_W-1:0]         support12,
    output wire [IDX_W-1:0]         support13,
    output wire [IDX_W-1:0]         support14,
    output wire [IDX_W-1:0]         support15,
    output wire [IDX_W-1:0]         support16,
    output wire [IDX_W-1:0]         support17,
    output wire [IDX_W-1:0]         support18,
    output wire [IDX_W-1:0]         support19,
    output wire [IDX_W-1:0]         support20,
    output wire [IDX_W-1:0]         support21,
    output wire [IDX_W-1:0]         support22,
    output wire [IDX_W-1:0]         support23,
    output wire [IDX_W-1:0]         support24,
    output wire [IDX_W-1:0]         support25,
    output wire [IDX_W-1:0]         support26,
    output wire [IDX_W-1:0]         support27,
    output wire [IDX_W-1:0]         support28,
    output wire [IDX_W-1:0]         support29,
    output wire [IDX_W-1:0]         support30,
    output wire [IDX_W-1:0]         support31,
    output wire                     op_done,
    output reg  [IDX_W-1:0]         result_idx,
    output reg                      result_valid
);
    localparam integer PATHS = 2;
    localparam integer PATH_AW = 1;
    localparam integer MAX_K = 32;
    localparam integer K_AW = 5;

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_COPY       = 4'd1;
    localparam [3:0] S_APPEND_SCAN= 4'd2;
    localparam [3:0] S_APPEND_SHIFT=4'd3;
    localparam [3:0] S_APPEND_WR  = 4'd4;
    localparam [3:0] S_MERGE_INIT = 4'd5;
    localparam [3:0] S_MERGE_SCAN = 4'd6;
    localparam [3:0] S_MERGE_NEXT = 4'd7;
    localparam [3:0] S_DONE       = 4'd8;

    reg [K_AW:0] depth_mem [0:PATHS-1];
    reg [IDX_W-1:0] support_mem [0:(PATHS*MAX_K)-1];

    wire candidate_uop = ctx_valid && (uop_class == 4'd6);
    wire candidate_commit = candidate_uop && ext_ctrl[0];
    wire candidate_meta = candidate_uop && ext_ctrl[2];
    wire candidate_sorted = candidate_uop && ext_ctrl[3];
    wire candidate_selpath = candidate_meta && ext_ctrl[1] && !ext_ctrl[3];
    wire candidate_copy_to_path0 = candidate_meta && ext_ctrl[1] && ext_ctrl[3];
    wire candidate_merge_sel_to_path = candidate_uop && (ext_ctrl == 4'b0010);
    wire [2:0] candidate_path_raw = ctx_word[22:20];
    wire [PATH_AW-1:0] candidate_path = candidate_path_raw[PATH_AW-1:0];
    wire [4:0] candidate_depth = ctx_word[15:11];
    wire [2:0] candidate_src_path_raw = ctx_word[25:23];
    wire [PATH_AW-1:0] candidate_src_path = candidate_src_path_raw[PATH_AW-1:0];
    wire [4:0] candidate_src_slot = ctx_word[30:26];
    wire [4:0] candidate_dst_slot = ctx_word[15:11];
    wire candidate_imm_idx_en = ctx_word[10];
    wire [IDX_W-1:0] candidate_append_idx = candidate_imm_idx_en ? ctx_word[IDX_W-1:0] : last_result_idx;
    localparam [K_AW:0] MAX_K_COUNT = 5'd16;
    wire [K_AW:0] candidate_depth_clamped = (candidate_depth >= MAX_K_COUNT) ? MAX_K_COUNT : {1'b0, candidate_depth[K_AW-1:0]};
    wire [K_AW:0] candidate_depth_now = (depth_mem[candidate_path] >= MAX_K_COUNT) ? MAX_K_COUNT : depth_mem[candidate_path];
    wire [K_AW:0] candidate_copy_depth = (depth_mem[candidate_path] >= MAX_K_COUNT) ? MAX_K_COUNT : depth_mem[candidate_path];

    reg [PATH_AW-1:0] selected_path_q;
    reg [3:0] state_q;
    reg [PATH_AW-1:0] op_path_q;
    reg [PATH_AW-1:0] op_src_path_q;
    reg [IDX_W-1:0] op_idx_q;
    reg op_sorted_q;
    reg [K_AW:0] scan_q;
    reg [K_AW:0] insert_pos_q;
    reg dup_q;
    reg found_q;
    reg [K_AW:0] merge_src_q;
    reg [K_AW:0] merge_depth_q;
    reg op_done_q;

    assign op_done = op_done_q;

    integer state_p;
    integer state_k;
    integer mask_i;
    integer mask_k;
    assign depth0 = depth_mem[0];
    assign support0 = support_mem[0];
    assign support1 = support_mem[1];
    assign support2 = support_mem[2];
    assign support3 = support_mem[3];
    assign support4 = support_mem[4];
    assign support5 = support_mem[5];
    assign support6 = support_mem[6];
    assign support7 = support_mem[7];
    assign support8 = support_mem[8];
    assign support9 = support_mem[9];
    assign support10 = support_mem[10];
    assign support11 = support_mem[11];
    assign support12 = support_mem[12];
    assign support13 = support_mem[13];
    assign support14 = support_mem[14];
    assign support15 = support_mem[15];
    assign support16 = {IDX_W{1'b0}};
    assign support17 = {IDX_W{1'b0}};
    assign support18 = {IDX_W{1'b0}};
    assign support19 = {IDX_W{1'b0}};
    assign support20 = {IDX_W{1'b0}};
    assign support21 = {IDX_W{1'b0}};
    assign support22 = {IDX_W{1'b0}};
    assign support23 = {IDX_W{1'b0}};
    assign support24 = {IDX_W{1'b0}};
    assign support25 = {IDX_W{1'b0}};
    assign support26 = {IDX_W{1'b0}};
    assign support27 = {IDX_W{1'b0}};
    assign support28 = {IDX_W{1'b0}};
    assign support29 = {IDX_W{1'b0}};
    assign support30 = {IDX_W{1'b0}};
    assign support31 = {IDX_W{1'b0}};

    always @(*) begin
        support_lane_mask = {COLS{1'b0}};
        selected_lane_mask = {COLS{1'b0}};
        for (mask_i = 0; mask_i < COLS; mask_i = mask_i + 1) begin
            for (mask_k = 0; mask_k < MAX_K; mask_k = mask_k + 1) begin
                if ((mask_k < depth_mem[0]) && (support_mem[mask_k] == (addr_support_query_base + mask_i[IDX_W-1:0]))) begin
                    support_lane_mask[mask_i] = 1'b1;
                end
                if ((mask_k < depth_mem[selected_path_q]) && (support_mem[(selected_path_q * MAX_K) + mask_k] == (addr_support_query_base + mask_i[IDX_W-1:0]))) begin
                    selected_lane_mask[mask_i] = 1'b1;
                end
            end
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selected_path_q <= 3'd0;
            state_q <= S_IDLE;
            op_done_q <= 1'b0;
            result_idx <= {IDX_W{1'b0}};
            result_valid <= 1'b0;
            op_path_q <= 3'd0;
            op_src_path_q <= 3'd0;
            op_idx_q <= {IDX_W{1'b0}};
            op_sorted_q <= 1'b0;
            scan_q <= {(K_AW+1){1'b0}};
            insert_pos_q <= {(K_AW+1){1'b0}};
            dup_q <= 1'b0;
            found_q <= 1'b0;
            merge_src_q <= {(K_AW+1){1'b0}};
            merge_depth_q <= {(K_AW+1){1'b0}};
            for (state_p = 0; state_p < PATHS; state_p = state_p + 1)
                depth_mem[state_p] <= {(K_AW+1){1'b0}};
            for (state_k = 0; state_k < PATHS*MAX_K; state_k = state_k + 1)
                support_mem[state_k] <= {IDX_W{1'b0}};
        end else begin
            op_done_q <= 1'b0;
            result_valid <= 1'b0;
            if (clear_error_pulse) begin
                selected_path_q <= 3'd0;
                state_q <= S_IDLE;
                op_done_q <= 1'b0;
                for (state_p = 0; state_p < PATHS; state_p = state_p + 1)
                    depth_mem[state_p] <= {(K_AW+1){1'b0}};
            end else begin
                case (state_q)
                    S_IDLE: begin
                        if (select_append_valid) begin
                            op_path_q <= select_append_path;
                            op_idx_q <= select_append_idx;
                            op_sorted_q <= 1'b0;
                            if (depth_mem[select_append_path] >= MAX_K) op_done_q <= 1'b1;
                            else begin
                                support_mem[(select_append_path * MAX_K) + depth_mem[select_append_path][K_AW-1:0]] <= select_append_idx;
                                depth_mem[select_append_path] <= depth_mem[select_append_path] + 1'b1;
                                op_done_q <= 1'b1;
                            end
                        end else if (candidate_selpath) begin
                            selected_path_q <= candidate_path;
                            op_done_q <= 1'b1;
                        end else if (candidate_copy_to_path0) begin
                            selected_path_q <= 3'd0;
                            op_path_q <= candidate_path;
                            scan_q <= {(K_AW+1){1'b0}};
                            depth_mem[0] <= candidate_copy_depth;
                            state_q <= (candidate_copy_depth == 0) ? S_DONE : S_COPY;
                        end else if (candidate_merge_sel_to_path) begin
                            op_path_q <= candidate_path;
                            op_src_path_q <= selected_path_q;
                            scan_q <= {(K_AW+1){1'b0}};
                            merge_src_q <= {(K_AW+1){1'b0}};
                            merge_depth_q <= depth_mem[candidate_path];
                            state_q <= S_MERGE_INIT;
                        end else if (candidate_meta) begin
                            depth_mem[candidate_path] <= candidate_depth_clamped;
                            op_done_q <= 1'b1;
                        end else if (candidate_commit) begin
                            op_path_q <= candidate_path;
                            op_idx_q <= candidate_append_idx;
                            op_sorted_q <= candidate_sorted;
                            scan_q <= {(K_AW+1){1'b0}};
                            insert_pos_q <= candidate_depth_now;
                            dup_q <= 1'b0;
                            found_q <= 1'b0;
                            if (candidate_depth_now >= MAX_K) begin
                                op_done_q <= 1'b1;
                            end else if (!candidate_sorted) begin
                                support_mem[(candidate_path * MAX_K) + candidate_depth_now[K_AW-1:0]] <= candidate_append_idx;
                                depth_mem[candidate_path] <= candidate_depth_now + 1'b1;
                                op_done_q <= 1'b1;
                            end else begin
                                state_q <= S_APPEND_SCAN;
                            end
                        end
                    end

                    S_COPY: begin
                        support_mem[scan_q[K_AW-1:0]] <= support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]];
                        if ((scan_q + 1'b1) >= depth_mem[op_path_q]) state_q <= S_DONE;
                        else scan_q <= scan_q + 1'b1;
                    end

                    S_APPEND_SCAN: begin
                        if (scan_q < depth_mem[op_path_q]) begin
                            if (support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]] == op_idx_q)
                                dup_q <= 1'b1;
                            if (!found_q && (op_idx_q < support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]])) begin
                                insert_pos_q <= scan_q;
                                found_q <= 1'b1;
                            end
                            scan_q <= scan_q + 1'b1;
                        end else begin
                            if (dup_q) state_q <= S_DONE;
                            else begin
                                scan_q <= depth_mem[op_path_q];
                                state_q <= S_APPEND_SHIFT;
                            end
                        end
                    end

                    S_APPEND_SHIFT: begin
                        if (scan_q > insert_pos_q) begin
                            support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]] <= support_mem[(op_path_q * MAX_K) + (scan_q[K_AW-1:0] - 1'b1)];
                            scan_q <= scan_q - 1'b1;
                        end else begin
                            state_q <= S_APPEND_WR;
                        end
                    end

                    S_APPEND_WR: begin
                        support_mem[(op_path_q * MAX_K) + insert_pos_q[K_AW-1:0]] <= op_idx_q;
                        depth_mem[op_path_q] <= depth_mem[op_path_q] + 1'b1;
                        state_q <= S_DONE;
                    end

                    S_MERGE_INIT: begin
                        if (merge_src_q < depth_mem[op_src_path_q]) begin
                            op_idx_q <= support_mem[(op_src_path_q * MAX_K) + merge_src_q[K_AW-1:0]];
                            scan_q <= {(K_AW+1){1'b0}};
                            insert_pos_q <= merge_depth_q;
                            dup_q <= 1'b0;
                            found_q <= 1'b0;
                            state_q <= S_MERGE_SCAN;
                        end else begin
                            depth_mem[op_path_q] <= merge_depth_q;
                            state_q <= S_DONE;
                        end
                    end

                    S_MERGE_SCAN: begin
                        if (scan_q < merge_depth_q) begin
                            if (support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]] == op_idx_q)
                                dup_q <= 1'b1;
                            if (!found_q && (op_idx_q < support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]])) begin
                                insert_pos_q <= scan_q;
                                found_q <= 1'b1;
                            end
                            scan_q <= scan_q + 1'b1;
                        end else begin
                            if (dup_q) begin
                                merge_src_q <= merge_src_q + 1'b1;
                                state_q <= S_MERGE_INIT;
                            end else if (merge_depth_q >= MAX_K) begin
                                if (found_q) begin
                                    scan_q <= MAX_K_COUNT - 1'b1;
                                    state_q <= S_MERGE_NEXT;
                                end else begin
                                    merge_src_q <= merge_src_q + 1'b1;
                                    state_q <= S_MERGE_INIT;
                                end
                            end else begin
                                scan_q <= merge_depth_q;
                                state_q <= S_MERGE_NEXT;
                            end
                        end
                    end

                    S_MERGE_NEXT: begin
                        if (scan_q > insert_pos_q) begin
                            support_mem[(op_path_q * MAX_K) + scan_q[K_AW-1:0]] <= support_mem[(op_path_q * MAX_K) + (scan_q[K_AW-1:0] - 1'b1)];
                            scan_q <= scan_q - 1'b1;
                        end else begin
                            support_mem[(op_path_q * MAX_K) + insert_pos_q[K_AW-1:0]] <= op_idx_q;
                            if (merge_depth_q < MAX_K)
                                merge_depth_q <= merge_depth_q + 1'b1;
                            merge_src_q <= merge_src_q + 1'b1;
                            state_q <= S_MERGE_INIT;
                        end
                    end

                    S_DONE: begin
                        op_done_q <= 1'b1;
                        state_q <= S_IDLE;
                    end

                    default: state_q <= S_IDLE;
                endcase
            end
        end
    end
endmodule

