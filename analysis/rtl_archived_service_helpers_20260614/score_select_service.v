module score_select_service #(
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer SCALAR_W = 56,
    parameter integer IDX_W = 10,
    parameter integer CTX_W = 64,
    parameter integer MAX_SEL = 16
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
    input  wire                   append_done,
    output reg                    append_valid,
    output reg  [IDX_W-1:0]       append_idx,
    output reg  [2:0]             append_path,
    output reg                    busy,
    output reg                    done
);
    function [DATA_W-1:0] abs_data;
        input [DATA_W-1:0] value;
        begin
            if (value == {1'b1, {(DATA_W-1){1'b0}}}) abs_data = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1]) abs_data = ~value + 1'b1;
            else abs_data = value;
        end
    endfunction

    localparam [1:0] S_IDLE=2'd0, S_SCAN=2'd1, S_APPEND=2'd2, S_DONE=2'd3;
    reg [1:0] state_q;
    reg [DATA_W-1:0] threshold_q;
    reg [IDX_W-1:0] sel_mem [0:MAX_SEL-1];
    reg [4:0] sel_count_q;
    reg [4:0] append_pos_q;
    reg [4:0] max_count_q;
    reg append_wait_q;
    reg scan_valid_q;
    reg scan_done_q;
    reg [COLS-1:0] scan_lane_valid_q;
    reg [IDX_W-1:0] scan_base_idx_q;
    integer lane;
    integer r;
    integer add_count;

    wire select_start = ctx_valid && (uop_class == 4'd5) && (ctx_word[27:24] == 4'd1);
    wire [3:0] shift_sel = ctx_word[19:16];
    wire [DATA_W-1:0] threshold_next = threshold_value[DATA_W-1:0] >> shift_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            append_valid <= 1'b0;
            append_idx <= {IDX_W{1'b0}};
            append_path <= 3'd0;
            busy <= 1'b0;
            done <= 1'b0;
            threshold_q <= {DATA_W{1'b0}};
            sel_count_q <= 5'd0;
            append_pos_q <= 5'd0;
            append_wait_q <= 1'b0;
            max_count_q <= 5'd0;
            scan_valid_q <= 1'b0;
            scan_done_q <= 1'b0;
            scan_lane_valid_q <= {COLS{1'b0}};
            scan_base_idx_q <= {IDX_W{1'b0}};
            for (r = 0; r < MAX_SEL; r = r + 1) sel_mem[r] <= {IDX_W{1'b0}};
        end else begin
            append_valid <= 1'b0;
            done <= 1'b0;
            case (state_q)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (select_start) begin
                        busy <= 1'b1;
                        append_path <= ctx_word[22:20];
                        threshold_q <= threshold_next;
                        sel_count_q <= 5'd0;
                        append_pos_q <= 5'd0;
                        append_wait_q <= 1'b0;
                        max_count_q <= (ctx_word[15:11] == 5'd0) ? MAX_SEL[4:0] : ctx_word[15:11];
                        scan_valid_q <= 1'b0;
                        scan_done_q <= 1'b0;
                        scan_lane_valid_q <= {COLS{1'b0}};
                        scan_base_idx_q <= {IDX_W{1'b0}};
                        state_q <= S_SCAN;
                    end
                end
                S_SCAN: begin
                    busy <= 1'b1;
                    if (scan_valid_q) begin
                        add_count = 0;
                        for (lane = 0; lane < COLS; lane = lane + 1) begin
                            if (scan_lane_valid_q[lane] && ((sel_count_q + add_count) < max_count_q) &&
                                (abs_data(spm_pa_rdata[lane*DATA_W +: DATA_W]) >= threshold_q)) begin
                                sel_mem[sel_count_q + add_count] <= scan_base_idx_q + lane[IDX_W-1:0];
                                add_count = add_count + 1;
                            end
                        end
                        sel_count_q <= sel_count_q + add_count[4:0];
                        if (scan_done_q || (scan_valid_q && !addr_valid)) begin
                            append_pos_q <= 5'd0;
                            state_q <= S_APPEND;
                        end
                    end
                    scan_valid_q <= addr_valid;
                    scan_done_q <= addr_done;
                    scan_lane_valid_q <= lane_valid;
                    scan_base_idx_q <= base_idx;
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
                        append_wait_q <= 1'b1;
                    end
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state_q <= S_IDLE;
                end
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule
