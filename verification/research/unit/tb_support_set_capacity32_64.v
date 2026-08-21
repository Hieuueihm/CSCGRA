`timescale 1ns/1ps
module tb_support_set_capacity32_64;
    reg clk = 0;
    reg rst_n = 0;
    reg clear_error_pulse = 0;
    reg start_pulse = 0;
    reg support_clear_selected = 0;
    reg ctx_valid = 0;
    reg [63:0] ctx_word = 0;
    reg [3:0] uop_class = 0;
    reg [3:0] ext_ctrl = 0;
    reg reduce_valid = 0;
    reg [10:0] reduce_idx = 0;
    reg [10:0] addr_support_query_base = 0;
    reg [10:0] base_idx = 0;
    reg [55:0] last_result_value = 0;
    reg [10:0] last_result_idx = 0;
    reg select_append_valid = 0;
    reg [10:0] select_append_idx = 0;
    reg [2:0] select_append_path = 0;
    wire [7:0] support_lane_mask, selected_lane_mask;
    wire [5:0] depth0;
    wire [10:0] support0, support31;
    wire op_done;
    wire [10:0] result_idx;
    wire result_valid;

    always #5 clk = ~clk;

    support_set_service #(
        .IDX_W(11), .MAX_SUPPORT(32), .MAX_CANDIDATE(64)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear_error_pulse(clear_error_pulse),
        .start_pulse(start_pulse),
        .support_clear_selected(support_clear_selected), .ctx_valid(ctx_valid),
        .ctx_word(ctx_word), .uop_class(uop_class), .ext_ctrl(ext_ctrl),
        .reduce_valid(reduce_valid), .reduce_idx(reduce_idx),
        .addr_support_query_base(addr_support_query_base), .base_idx(base_idx),
        .last_result_value(last_result_value), .last_result_idx(last_result_idx),
        .select_append_valid(select_append_valid),
        .select_append_idx(select_append_idx),
        .select_append_path(select_append_path),
        .support_lane_mask(support_lane_mask),
        .selected_lane_mask(selected_lane_mask), .depth0(depth0),
        .support0(support0), .support31(support31), .op_done(op_done),
        .result_idx(result_idx), .result_valid(result_valid)
    );

    integer i;
    task append;
        input [2:0] path;
        input [10:0] idx;
        begin
            @(negedge clk);
            select_append_path = path;
            select_append_idx = idx;
            select_append_valid = 1'b1;
            @(negedge clk);
            select_append_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        // Candidate path accepts all 64 entries without consuming solution
        // storage. Path0 independently retains the exact 32-entry solution.
        for (i = 0; i < 64; i = i + 1)
            append(3'd1, 11'd1000 - i);
        for (i = 0; i < 32; i = i + 1)
            append(3'd0, i[10:0]);
        @(negedge clk);
        if (depth0 !== 6'd32 || support0 !== 11'd0 || support31 !== 11'd31)
            $fatal(1, "capacity mismatch depth=%0d s0=%0d s31=%0d",
                   depth0, support0, support31);
        $display("SUPPORT_CAPACITY32_64 PASS");
        $finish;
    end
endmodule
