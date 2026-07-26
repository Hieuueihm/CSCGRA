`timescale 1ns/1ps

module tb_pe_array_top1_tree_4x8;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n;
    reg in_valid;
    reg [31:0] lane_valid;
    reg [32*24-1:0] lane_score;
    reg [32*10-1:0] lane_idx;
    wire out_valid;
    wire [23:0] out_score;
    wire [9:0] out_idx;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    pe_array_top1_tree_4x8 dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .lane_valid(lane_valid), .lane_score(lane_score), .lane_idx(lane_idx),
        .out_valid(out_valid), .out_score(out_score), .out_idx(out_idx)
    );

    task set_lane;
        input integer lane;
        input valid;
        input signed [23:0] score;
        input [9:0] idx;
        begin
            lane_valid[lane] = valid;
            lane_score[lane*24 +: 24] = score;
            lane_idx[lane*10 +: 10] = idx;
        end
    endtask

    task check;
        input [255:0] name;
        input cond;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s out_valid=%0b out_idx=%0d out_score=%0d", name, out_valid, out_idx, $signed(out_score));
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        lane_valid = 32'd0;
        lane_score = {32*24{1'b0}};
        lane_idx = {32*10{1'b0}};
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 32; i = i + 1)
            set_lane(i, 1'b1, i[23:0], i[9:0]);
        set_lane(11, 1'b1, -24'sd120, 10'd11);
        set_lane(29, 1'b1, 24'sd119, 10'd29);
        @(negedge clk);
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;
        wait(out_valid === 1'b1);
        @(negedge clk);
        check("max_abs_negative", out_valid && (out_idx == 10'd11) && ($signed(out_score) == -24'sd120));

        for (i = 0; i < 32; i = i + 1)
            set_lane(i, 1'b1, 24'sd7, i[9:0]);
        set_lane(7, 1'b1, -24'sd55, 10'd7);
        set_lane(19, 1'b1, 24'sd55, 10'd19);
        set_lane(3, 1'b1, -24'sd55, 10'd3);
        @(negedge clk);
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;
        wait(out_valid === 1'b1);
        @(negedge clk);
        check("tie_index_small", out_valid && (out_idx == 10'd3) && ($signed(out_score) == -24'sd55));

        lane_valid = 32'd0;
        for (i = 0; i < 32; i = i + 1)
            set_lane(i, 1'b0, 24'sd100, i[9:0]);
        set_lane(25, 1'b1, 24'sd42, 10'd25);
        @(negedge clk);
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;
        wait(out_valid === 1'b1);
        @(negedge clk);
        check("mask_valid", out_valid && (out_idx == 10'd25) && ($signed(out_score) == 24'sd42));

        $display("tb_pe_array_top1_tree_4x8: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count != 0) $fatal(1);
        $finish;
    end
endmodule


