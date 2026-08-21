`ifndef CSCGRA_SUPPORT_SET_SERVICE_VH
`define CSCGRA_SUPPORT_SET_SERVICE_VH

// Support-set storage and update service used by the sparse kernel.
module support_set_service #(
    parameter integer COLS     = 8,
    parameter integer IDX_W    = 10,
    parameter integer CTX_W    = 64,
    parameter integer SCALAR_W = 56,
    parameter integer MAX_SUPPORT = 16,
    parameter integer MAX_CANDIDATE = 32
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
    localparam integer STORE_STRIDE = MAX_CANDIDATE;
    localparam integer K_AW = $clog2(MAX_CANDIDATE);
    localparam integer COUNT_W = K_AW + 1;

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_COPY       = 4'd1;
    localparam [3:0] S_APPEND_SCAN= 4'd2;
    localparam [3:0] S_APPEND_SHIFT=4'd3;
    localparam [3:0] S_APPEND_WR  = 4'd4;
    localparam [3:0] S_MERGE_INIT = 4'd5;
    localparam [3:0] S_MERGE_SCAN = 4'd6;
    localparam [3:0] S_MERGE_NEXT = 4'd7;
    localparam [3:0] S_DONE       = 4'd8;

    reg [COUNT_W-1:0] depth_mem [0:PATHS-1];
    reg [IDX_W-1:0] support_mem [0:(PATHS*STORE_STRIDE)-1];
    // Tuple metadata is kept alongside the legacy index store.  The index
    // remains the bit-exact source for the existing controller; valid/version
    // make writeback and invalidate explicit so dense scans can be removed in
    // a later checkpoint without changing support semantics.
    reg [PATHS*STORE_STRIDE-1:0] tuple_valid_mem;
    reg [7:0] tuple_version_mem [0:(PATHS*STORE_STRIDE)-1];
    reg [7:0] path_version_mem [0:PATHS-1];

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
    wire [COUNT_W-1:0] candidate_path_capacity = candidate_path ?
        MAX_CANDIDATE[COUNT_W-1:0] : MAX_SUPPORT[COUNT_W-1:0];
    wire [COUNT_W-1:0] candidate_depth_ext =
        // A five-bit legacy field cannot encode 32/64. For META only, bit10
        // means "full capacity"; zero without bit10 remains a true clear.
        (candidate_meta && ctx_word[10]) ? candidate_path_capacity :
        {{(COUNT_W-5){1'b0}}, candidate_depth};
    wire [COUNT_W-1:0] candidate_depth_clamped =
        (candidate_depth_ext >= candidate_path_capacity) ?
        candidate_path_capacity : candidate_depth_ext;
    wire [COUNT_W-1:0] candidate_depth_now =
        (depth_mem[candidate_path] >= candidate_path_capacity) ?
        candidate_path_capacity : depth_mem[candidate_path];
    wire [COUNT_W-1:0] candidate_copy_depth =
        (depth_mem[candidate_path] >= MAX_SUPPORT) ?
        MAX_SUPPORT[COUNT_W-1:0] : depth_mem[candidate_path];

    reg [PATH_AW-1:0] selected_path_q;
    reg [3:0] state_q;
    reg [PATH_AW-1:0] op_path_q;
    reg [PATH_AW-1:0] op_src_path_q;
    reg [IDX_W-1:0] op_idx_q;
    reg [COUNT_W-1:0] scan_q;
    reg [COUNT_W-1:0] insert_pos_q;
    reg dup_q;
    reg found_q;
    reg [COUNT_W-1:0] merge_src_q;
    reg [COUNT_W-1:0] merge_depth_q;
    reg op_done_q;

    assign op_done = op_done_q;

    integer state_p;
    integer state_k;
    integer mask_i;
    integer mask_k;
    integer tuple_addr;

    task tuple_write;
        input [PATH_AW-1:0] tw_path;
        input [K_AW-1:0] tw_slot;
        input [IDX_W-1:0] tw_value;
        begin
            tuple_addr = (tw_path * STORE_STRIDE) + tw_slot;
            support_mem[tuple_addr] <= tw_value;
            tuple_valid_mem[tuple_addr] <= 1'b1;
            tuple_version_mem[tuple_addr] <= path_version_mem[tw_path] + 1'b1;
            path_version_mem[tw_path] <= path_version_mem[tw_path] + 1'b1;
        end
    endtask
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
    assign support16 = (MAX_SUPPORT > 16) ? support_mem[16] : {IDX_W{1'b0}};
    assign support17 = (MAX_SUPPORT > 17) ? support_mem[17] : {IDX_W{1'b0}};
    assign support18 = (MAX_SUPPORT > 18) ? support_mem[18] : {IDX_W{1'b0}};
    assign support19 = (MAX_SUPPORT > 19) ? support_mem[19] : {IDX_W{1'b0}};
    assign support20 = (MAX_SUPPORT > 20) ? support_mem[20] : {IDX_W{1'b0}};
    assign support21 = (MAX_SUPPORT > 21) ? support_mem[21] : {IDX_W{1'b0}};
    assign support22 = (MAX_SUPPORT > 22) ? support_mem[22] : {IDX_W{1'b0}};
    assign support23 = (MAX_SUPPORT > 23) ? support_mem[23] : {IDX_W{1'b0}};
    assign support24 = (MAX_SUPPORT > 24) ? support_mem[24] : {IDX_W{1'b0}};
    assign support25 = (MAX_SUPPORT > 25) ? support_mem[25] : {IDX_W{1'b0}};
    assign support26 = (MAX_SUPPORT > 26) ? support_mem[26] : {IDX_W{1'b0}};
    assign support27 = (MAX_SUPPORT > 27) ? support_mem[27] : {IDX_W{1'b0}};
    assign support28 = (MAX_SUPPORT > 28) ? support_mem[28] : {IDX_W{1'b0}};
    assign support29 = (MAX_SUPPORT > 29) ? support_mem[29] : {IDX_W{1'b0}};
    assign support30 = (MAX_SUPPORT > 30) ? support_mem[30] : {IDX_W{1'b0}};
    assign support31 = (MAX_SUPPORT > 31) ? support_mem[31] : {IDX_W{1'b0}};

    always @(*) begin
        support_lane_mask = {COLS{1'b0}};
        selected_lane_mask = {COLS{1'b0}};
        for (mask_i = 0; mask_i < COLS; mask_i = mask_i + 1) begin
            for (mask_k = 0; mask_k < MAX_CANDIDATE; mask_k = mask_k + 1) begin
                if ((mask_k < MAX_SUPPORT) && (mask_k < depth_mem[0]) && tuple_valid_mem[mask_k] && (support_mem[mask_k] == (addr_support_query_base + mask_i[IDX_W-1:0]))) begin
                    support_lane_mask[mask_i] = 1'b1;
                end
                if ((mask_k < depth_mem[selected_path_q]) && tuple_valid_mem[(selected_path_q * STORE_STRIDE) + mask_k] && (support_mem[(selected_path_q * STORE_STRIDE) + mask_k] == (addr_support_query_base + mask_i[IDX_W-1:0]))) begin
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
            scan_q <= {COUNT_W{1'b0}};
            insert_pos_q <= {COUNT_W{1'b0}};
            dup_q <= 1'b0;
            found_q <= 1'b0;
            merge_src_q <= {COUNT_W{1'b0}};
            merge_depth_q <= {COUNT_W{1'b0}};
            for (state_p = 0; state_p < PATHS; state_p = state_p + 1)
                begin
                    depth_mem[state_p] <= {(K_AW+1){1'b0}};
                    path_version_mem[state_p] <= 8'd0;
                end
            for (state_k = 0; state_k < PATHS*STORE_STRIDE; state_k = state_k + 1)
                begin
                    support_mem[state_k] <= {IDX_W{1'b0}};
                    tuple_valid_mem[state_k] <= 1'b0;
                    tuple_version_mem[state_k] <= 8'd0;
                end
        end else begin
            op_done_q <= 1'b0;
            result_valid <= 1'b0;
            if (clear_error_pulse) begin
                selected_path_q <= 3'd0;
                state_q <= S_IDLE;
                op_done_q <= 1'b0;
                for (state_p = 0; state_p < PATHS; state_p = state_p + 1) begin
                    depth_mem[state_p] <= {(K_AW+1){1'b0}};
                    tuple_valid_mem[state_p*STORE_STRIDE +: STORE_STRIDE] <= {STORE_STRIDE{1'b0}};
                    path_version_mem[state_p] <= path_version_mem[state_p] + 1'b1;
                end
            end else begin
                case (state_q)
                    S_IDLE: begin
                        if (select_append_valid) begin
                            op_path_q <= select_append_path;
                            op_idx_q <= select_append_idx;
                            if (depth_mem[select_append_path] >=
                                (select_append_path == 0 ? MAX_SUPPORT : MAX_CANDIDATE)) op_done_q <= 1'b1;
                            else begin
                                tuple_write(select_append_path[PATH_AW-1:0], depth_mem[select_append_path][K_AW-1:0], select_append_idx);
                                depth_mem[select_append_path] <= depth_mem[select_append_path] + 1'b1;
                                op_done_q <= 1'b1;
                            end
                        end else if (candidate_selpath) begin
                            selected_path_q <= candidate_path;
                            op_done_q <= 1'b1;
                        end else if (candidate_copy_to_path0) begin
                            selected_path_q <= 3'd0;
                            op_path_q <= candidate_path;
                            scan_q <= {COUNT_W{1'b0}};
                            depth_mem[0] <= candidate_copy_depth;
                            tuple_valid_mem[0 +: STORE_STRIDE] <= {STORE_STRIDE{1'b0}};
                            path_version_mem[0] <= path_version_mem[0] + 1'b1;
                            state_q <= (candidate_copy_depth == 0) ? S_DONE : S_COPY;
                        end else if (candidate_merge_sel_to_path) begin
                            op_path_q <= candidate_path;
                            op_src_path_q <= selected_path_q;
                            scan_q <= {COUNT_W{1'b0}};
                            merge_src_q <= {COUNT_W{1'b0}};
                            merge_depth_q <= depth_mem[candidate_path];
                            state_q <= S_MERGE_INIT;
                        end else if (candidate_meta) begin
                            depth_mem[candidate_path] <= candidate_depth_clamped;
                            path_version_mem[candidate_path] <= path_version_mem[candidate_path] + 1'b1;
                            for (state_k = 0; state_k < STORE_STRIDE; state_k = state_k + 1)
                                tuple_valid_mem[(candidate_path * STORE_STRIDE) + state_k] <=
                                    (state_k < candidate_depth_clamped);
                            op_done_q <= 1'b1;
                        end else if (candidate_commit) begin
                            op_path_q <= candidate_path;
                            op_idx_q <= candidate_append_idx;
                            scan_q <= {COUNT_W{1'b0}};
                            insert_pos_q <= candidate_depth_now;
                            dup_q <= 1'b0;
                            found_q <= 1'b0;
                            if (candidate_depth_now >= candidate_path_capacity) begin
                                op_done_q <= 1'b1;
                            end else if (!candidate_sorted) begin
                                tuple_write(candidate_path[PATH_AW-1:0], candidate_depth_now[K_AW-1:0], candidate_append_idx);
                                depth_mem[candidate_path] <= candidate_depth_now + 1'b1;
                                op_done_q <= 1'b1;
                            end else begin
                                state_q <= S_APPEND_SCAN;
                            end
                        end
                    end

                    S_COPY: begin
                        tuple_write(1'b0, scan_q[K_AW-1:0], support_mem[(op_path_q * STORE_STRIDE) + scan_q[K_AW-1:0]]);
                        if ((scan_q + 1'b1) >= depth_mem[op_path_q]) state_q <= S_DONE;
                        else scan_q <= scan_q + 1'b1;
                    end

                    S_APPEND_SCAN: begin
                        if (scan_q < depth_mem[op_path_q]) begin
                            if (support_mem[(op_path_q * STORE_STRIDE) + scan_q[K_AW-1:0]] == op_idx_q)
                                dup_q <= 1'b1;
                            if (!found_q && (op_idx_q < support_mem[(op_path_q * STORE_STRIDE) + scan_q[K_AW-1:0]])) begin
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
                            tuple_write(op_path_q, scan_q[K_AW-1:0], support_mem[(op_path_q * STORE_STRIDE) + (scan_q[K_AW-1:0] - 1'b1)]);
                            scan_q <= scan_q - 1'b1;
                        end else begin
                            state_q <= S_APPEND_WR;
                        end
                    end

                    S_APPEND_WR: begin
                        tuple_write(op_path_q, insert_pos_q[K_AW-1:0], op_idx_q);
                        depth_mem[op_path_q] <= depth_mem[op_path_q] + 1'b1;
                        state_q <= S_DONE;
                    end

                    S_MERGE_INIT: begin
                        if (merge_src_q < depth_mem[op_src_path_q]) begin
                            op_idx_q <= support_mem[(op_src_path_q * STORE_STRIDE) + merge_src_q[K_AW-1:0]];
                            scan_q <= {COUNT_W{1'b0}};
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
                            if (support_mem[(op_path_q * STORE_STRIDE) + scan_q[K_AW-1:0]] == op_idx_q)
                                dup_q <= 1'b1;
                            if (!found_q && (op_idx_q < support_mem[(op_path_q * STORE_STRIDE) + scan_q[K_AW-1:0]])) begin
                                insert_pos_q <= scan_q;
                                found_q <= 1'b1;
                            end
                            scan_q <= scan_q + 1'b1;
                        end else begin
                            if (dup_q) begin
                                merge_src_q <= merge_src_q + 1'b1;
                                state_q <= S_MERGE_INIT;
                            end else if (merge_depth_q >=
                                         (op_path_q == 0 ? MAX_SUPPORT : MAX_CANDIDATE)) begin
                                if (found_q) begin
                                    scan_q <= (op_path_q == 0 ? MAX_SUPPORT : MAX_CANDIDATE) - 1'b1;
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
                            tuple_write(op_path_q, scan_q[K_AW-1:0], support_mem[(op_path_q * STORE_STRIDE) + (scan_q[K_AW-1:0] - 1'b1)]);
                            scan_q <= scan_q - 1'b1;
                        end else begin
                            tuple_write(op_path_q, insert_pos_q[K_AW-1:0], op_idx_q);
                            if (merge_depth_q < (op_path_q == 0 ? MAX_SUPPORT : MAX_CANDIDATE))
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

`endif
