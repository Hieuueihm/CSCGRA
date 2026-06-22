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
    input  wire [4:0]                   max_count,
    input  wire [2:0]                   append_path_in,
    input  wire                         exclude_support,
    input  wire                         allow_tiny,
    input  wire                         stream_valid,
    input  wire                         stream_done,
    input  wire [IDX_W-1:0]             stream_base_idx,
    input  wire [COLS-1:0]              stream_lane_valid,
    input  wire [COLS*DATA_W-1:0]       stream_data,
    input  wire [5:0]                   support_depth,
    input  wire [MAX_SUPPORT*IDX_W-1:0] support_bus,
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
            if (value == {1'b1, {(DATA_W-1){1'b0}}}) abs_data = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1]) abs_data = ~value + 1'b1;
            else abs_data = value;
        end
    endfunction

    function support_has_idx;
        input [IDX_W-1:0] idx;
        integer si;
        begin
            support_has_idx = 1'b0;
            for (si = 0; si < MAX_SUPPORT; si = si + 1)
                if ((si < support_depth) && (support_bus[si*IDX_W +: IDX_W] == idx))
                    support_has_idx = 1'b1;
        end
    endfunction

    localparam [2:0] S_IDLE=3'd0, S_CAPTURE=3'd1, S_LANE=3'd2, S_INSERT=3'd3, S_SHIFT=3'd4, S_APPEND=3'd5, S_DONE=3'd6;
    reg [2:0] state_q;
    reg [IDX_W-1:0] sel_mem [0:MAX_SEL-1];
    reg [DATA_W-1:0] sel_score [0:MAX_SEL-1];
    reg [COLS-1:0] block_valid_q;
    reg [COLS*DATA_W-1:0] block_data_q;
    reg [IDX_W-1:0] block_base_q;
    reg block_done_q;
    reg [2:0] lane_q;
    reg [4:0] sel_count_q;
    reg [4:0] max_count_q;
    reg [4:0] append_pos_q;
    reg append_wait_q;
    reg [IDX_W-1:0] cand_idx_q;
    reg [DATA_W-1:0] cand_abs_q;
    reg cand_valid_q;
    reg [4:0] insert_pos_q;
    reg [4:0] shift_pos_q;
    integer r;

    always @(*) begin
        insert_pos_q = MAX_SEL[4:0];
        for (r = 0; r < MAX_SEL; r = r + 1) begin
            if ((r < max_count_q) && (r <= sel_count_q) && (insert_pos_q == MAX_SEL[4:0]) &&
                ((r == sel_count_q) || (cand_abs_q > sel_score[r]) || ((cand_abs_q == sel_score[r]) && (cand_idx_q < sel_mem[r]))))
                insert_pos_q = r[4:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            append_valid <= 1'b0;
            append_idx <= {IDX_W{1'b0}};
            append_path <= 3'd0;
            stream_ready <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            block_valid_q <= {COLS{1'b0}};
            block_data_q <= {(COLS*DATA_W){1'b0}};
            block_base_q <= {IDX_W{1'b0}};
            block_done_q <= 1'b0;
            lane_q <= 3'd0;
            sel_count_q <= 5'd0;
            max_count_q <= 5'd0;
            append_pos_q <= 5'd0;
            append_wait_q <= 1'b0;
            cand_idx_q <= {IDX_W{1'b0}};
            cand_abs_q <= {DATA_W{1'b0}};
            cand_valid_q <= 1'b0;
            shift_pos_q <= 5'd0;
            for (r = 0; r < MAX_SEL; r = r + 1) begin
                sel_mem[r] <= {IDX_W{1'b1}};
                sel_score[r] <= {DATA_W{1'b0}};
            end
        end else begin
            append_valid <= 1'b0;
            done <= 1'b0;
            case (state_q)
                S_IDLE: begin
                    busy <= 1'b0;
                    stream_ready <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        stream_ready <= 1'b1;
                        state_q <= S_CAPTURE;
                        max_count_q <= (max_count == 5'd0) ? MAX_SEL[4:0] : max_count;
                        sel_count_q <= 5'd0;
                        append_pos_q <= 5'd0;
                        append_wait_q <= 1'b0;
                        append_path <= append_path_in;
                        block_done_q <= 1'b0;
                        for (r = 0; r < MAX_SEL; r = r + 1) begin
                            sel_mem[r] <= {IDX_W{1'b1}};
                            sel_score[r] <= {DATA_W{1'b0}};
                        end
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
                        state_q <= S_LANE;
                    end else if (stream_done) begin
                        stream_ready <= 1'b0;
                        append_pos_q <= 5'd0;
                        state_q <= (sel_count_q == 5'd0) ? S_DONE : S_APPEND;
                    end
                end
                S_LANE: begin
                    cand_idx_q <= block_base_q + lane_q;
                    cand_abs_q <= abs_data(block_data_q[lane_q*DATA_W +: DATA_W]);
                    cand_valid_q <= block_valid_q[lane_q] &&
                                    (allow_tiny || (abs_data(block_data_q[lane_q*DATA_W +: DATA_W]) > {{(DATA_W-1){1'b0}}, 1'b1})) &&
                                    (!exclude_support || !support_has_idx(block_base_q + lane_q));
                    state_q <= S_INSERT;
                end
                S_INSERT: begin
                    if (cand_valid_q && (insert_pos_q < max_count_q)) begin
                        shift_pos_q <= max_count_q - 1'b1;
                        state_q <= S_SHIFT;
                    end else if (lane_q == COLS-1) begin
                        state_q <= block_done_q ? ((sel_count_q == 5'd0) ? S_DONE : S_APPEND) : S_CAPTURE;
                    end else begin
                        lane_q <= lane_q + 1'b1;
                        state_q <= S_LANE;
                    end
                end
                S_SHIFT: begin
                    if ((shift_pos_q > insert_pos_q) && (shift_pos_q < max_count_q)) begin
                        sel_mem[shift_pos_q] <= sel_mem[shift_pos_q-1];
                        sel_score[shift_pos_q] <= sel_score[shift_pos_q-1];
                        shift_pos_q <= shift_pos_q - 1'b1;
                    end else begin
                        sel_mem[insert_pos_q] <= cand_idx_q;
                        sel_score[insert_pos_q] <= cand_abs_q;
                        if (sel_count_q < max_count_q)
                            sel_count_q <= sel_count_q + 1'b1;
                        if (lane_q == COLS-1)
                            state_q <= block_done_q ? S_APPEND : S_CAPTURE;
                        else begin
                            lane_q <= lane_q + 1'b1;
                            state_q <= S_LANE;
                        end
                    end
                end
                S_APPEND: begin
                    busy <= 1'b1;
                    if (append_pos_q >= sel_count_q) begin
                        state_q <= S_DONE;
                    end else if (append_wait_q) begin
                        if (append_done) begin
                            append_wait_q <= 1'b0;
                            append_pos_q <= append_pos_q + 1'b1;
                        end
                    end else begin
                        append_valid <= 1'b1;
                        append_idx <= sel_mem[append_pos_q];
                        append_path <= append_path;
                        append_wait_q <= 1'b1;
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


