module pe_array_top1_tree_4x8 #(
    parameter integer ROWS = 4,
    parameter integer COLS = 8,
    parameter integer DATA_W = 24,
    parameter integer IDX_W = 10
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         in_valid,
    input  wire [ROWS*COLS-1:0]         lane_valid,
    input  wire [ROWS*COLS*DATA_W-1:0]  lane_score,
    input  wire [ROWS*COLS*IDX_W-1:0]   lane_idx,
    output reg                          out_valid,
    output reg  [DATA_W-1:0]            out_score,
    output reg  [IDX_W-1:0]             out_idx
);
    localparam integer LANES = ROWS * COLS;

    function [DATA_W-1:0] abs_score;
        input [DATA_W-1:0] value;
        begin
            if (value == {1'b1, {(DATA_W-1){1'b0}}})
                abs_score = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1])
                abs_score = ~value + 1'b1;
            else
                abs_score = value;
        end
    endfunction

    function choose_left;
        input lhs_valid;
        input [DATA_W-1:0] lhs_score;
        input [IDX_W-1:0] lhs_idx;
        input rhs_valid;
        input [DATA_W-1:0] rhs_score;
        input [IDX_W-1:0] rhs_idx;
        reg [DATA_W-1:0] lhs_abs;
        reg [DATA_W-1:0] rhs_abs;
        begin
            lhs_abs = abs_score(lhs_score);
            rhs_abs = abs_score(rhs_score);
            if (!lhs_valid)
                choose_left = 1'b0;
            else if (!rhs_valid)
                choose_left = 1'b1;
            else if (lhs_abs > rhs_abs)
                choose_left = 1'b1;
            else if (lhs_abs < rhs_abs)
                choose_left = 1'b0;
            else
                choose_left = (lhs_idx < rhs_idx);
        end
    endfunction

    reg s1_valid [0:15];
    reg [DATA_W-1:0] s1_score [0:15];
    reg [IDX_W-1:0] s1_idx [0:15];
    reg s2_valid [0:7];
    reg [DATA_W-1:0] s2_score [0:7];
    reg [IDX_W-1:0] s2_idx [0:7];
    reg s3_valid [0:3];
    reg [DATA_W-1:0] s3_score [0:3];
    reg [IDX_W-1:0] s3_idx [0:3];
    reg s4_valid [0:1];
    reg [DATA_W-1:0] s4_score [0:1];
    reg [IDX_W-1:0] s4_idx [0:1];
    reg v1, v2, v3, v4;
    integer i;

    task pick_pair32;
        input integer out_pos;
        input integer lhs_pos;
        input integer rhs_pos;
        begin
            if (choose_left(lane_valid[lhs_pos], lane_score[lhs_pos*DATA_W +: DATA_W], lane_idx[lhs_pos*IDX_W +: IDX_W],
                            lane_valid[rhs_pos], lane_score[rhs_pos*DATA_W +: DATA_W], lane_idx[rhs_pos*IDX_W +: IDX_W])) begin
                s1_valid[out_pos] <= lane_valid[lhs_pos];
                s1_score[out_pos] <= lane_score[lhs_pos*DATA_W +: DATA_W];
                s1_idx[out_pos] <= lane_idx[lhs_pos*IDX_W +: IDX_W];
            end else begin
                s1_valid[out_pos] <= lane_valid[rhs_pos];
                s1_score[out_pos] <= lane_score[rhs_pos*DATA_W +: DATA_W];
                s1_idx[out_pos] <= lane_idx[rhs_pos*IDX_W +: IDX_W];
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_score <= {DATA_W{1'b0}};
            out_idx <= {IDX_W{1'b0}};
            v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                s1_valid[i] <= 1'b0;
                s1_score[i] <= {DATA_W{1'b0}};
                s1_idx[i] <= {IDX_W{1'b0}};
            end
            for (i = 0; i < 8; i = i + 1) begin
                s2_valid[i] <= 1'b0;
                s2_score[i] <= {DATA_W{1'b0}};
                s2_idx[i] <= {IDX_W{1'b0}};
            end
            for (i = 0; i < 4; i = i + 1) begin
                s3_valid[i] <= 1'b0;
                s3_score[i] <= {DATA_W{1'b0}};
                s3_idx[i] <= {IDX_W{1'b0}};
            end
            for (i = 0; i < 2; i = i + 1) begin
                s4_valid[i] <= 1'b0;
                s4_score[i] <= {DATA_W{1'b0}};
                s4_idx[i] <= {IDX_W{1'b0}};
            end
        end else begin
            for (i = 0; i < 16; i = i + 1)
                pick_pair32(i, i*2, i*2 + 1);

            for (i = 0; i < 8; i = i + 1) begin
                if (choose_left(s1_valid[i*2], s1_score[i*2], s1_idx[i*2], s1_valid[i*2+1], s1_score[i*2+1], s1_idx[i*2+1])) begin
                    s2_valid[i] <= s1_valid[i*2]; s2_score[i] <= s1_score[i*2]; s2_idx[i] <= s1_idx[i*2];
                end else begin
                    s2_valid[i] <= s1_valid[i*2+1]; s2_score[i] <= s1_score[i*2+1]; s2_idx[i] <= s1_idx[i*2+1];
                end
            end

            for (i = 0; i < 4; i = i + 1) begin
                if (choose_left(s2_valid[i*2], s2_score[i*2], s2_idx[i*2], s2_valid[i*2+1], s2_score[i*2+1], s2_idx[i*2+1])) begin
                    s3_valid[i] <= s2_valid[i*2]; s3_score[i] <= s2_score[i*2]; s3_idx[i] <= s2_idx[i*2];
                end else begin
                    s3_valid[i] <= s2_valid[i*2+1]; s3_score[i] <= s2_score[i*2+1]; s3_idx[i] <= s2_idx[i*2+1];
                end
            end

            for (i = 0; i < 2; i = i + 1) begin
                if (choose_left(s3_valid[i*2], s3_score[i*2], s3_idx[i*2], s3_valid[i*2+1], s3_score[i*2+1], s3_idx[i*2+1])) begin
                    s4_valid[i] <= s3_valid[i*2]; s4_score[i] <= s3_score[i*2]; s4_idx[i] <= s3_idx[i*2];
                end else begin
                    s4_valid[i] <= s3_valid[i*2+1]; s4_score[i] <= s3_score[i*2+1]; s4_idx[i] <= s3_idx[i*2+1];
                end
            end

            if (choose_left(s4_valid[0], s4_score[0], s4_idx[0], s4_valid[1], s4_score[1], s4_idx[1])) begin
                out_valid <= v4 && s4_valid[0];
                out_score <= s4_score[0];
                out_idx <= s4_idx[0];
            end else begin
                out_valid <= v4 && s4_valid[1];
                out_score <= s4_score[1];
                out_idx <= s4_idx[1];
            end
            v1 <= in_valid;
            v2 <= v1;
            v3 <= v2;
            v4 <= v3;
        end
    end
endmodule
