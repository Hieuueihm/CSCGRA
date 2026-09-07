`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "m7_golden.vh"

module tb_m7_phi_cache_normalizer;
    reg clk = 1'b0;
    always #3.333 clk = ~clk;
    reg rst_n = 1'b0;

    reg normalizer_input_valid = 1'b0;
    wire normalizer_input_ready;
    reg signed [`RECON_ACC_W-1:0] normalizer_input_data = 0;
    reg normalizer_input_placement = 0;
    reg [`RECON_PHI_TAG_W-1:0] normalizer_input_tag = 0;
    reg normalizer_input_is_data18 = 0;
    reg [`RECON_PHI_SCALE_MANTISSA_W-1:0] normalizer_mantissa = 0;
    reg [`RECON_PHI_SCALE_EXPONENT_W-1:0] normalizer_exponent = 0;
    wire normalizer_output_valid;
    reg normalizer_output_ready = 1'b0;
    wire signed [`RECON_SOLVER_W-1:0] normalizer_output_data;
    wire normalizer_output_placement;
    wire [`RECON_PHI_TAG_W-1:0] normalizer_output_tag;
    wire normalizer_output_saturated;

    reg signed [`RECON_ACC_W-1:0] norm_input [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg [`RECON_PHI_SCALE_MANTISSA_W-1:0] norm_mantissa [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg [`RECON_PHI_SCALE_EXPONENT_W-1:0] norm_exponent [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg norm_placement [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg [`RECON_PHI_TAG_W-1:0] norm_tag [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg signed [`RECON_SOLVER_W-1:0] norm_result [0:`M7_NORMALIZER_CASE_COUNT-1];
    reg norm_saturated [0:`M7_NORMALIZER_CASE_COUNT-1];

    phi_operator_normalizer u_normalizer (
        .clk(clk), .rst_n(rst_n),
        .input_valid(normalizer_input_valid),
        .input_ready(normalizer_input_ready),
        .input_data(normalizer_input_data),
        .input_placement(normalizer_input_placement),
        .input_tag(normalizer_input_tag),
        .scale_mantissa_uq17(normalizer_mantissa),
        .scale_exponent(normalizer_exponent),
        .input_is_data18(normalizer_input_is_data18),
        .output_valid(normalizer_output_valid),
        .output_ready(normalizer_output_ready),
        .output_data(normalizer_output_data),
        .output_placement(normalizer_output_placement),
        .output_tag(normalizer_output_tag),
        .output_saturated(normalizer_output_saturated)
    );

    reg cache_invalidate = 1'b0;
    reg [8:0] cache_measurement_count = 9'd70;
    reg prepare_valid = 1'b0;
    wire prepare_ready;
    reg prepare_from_candidates = 1'b0;
    reg [6:0] prepare_support_count = 0;
    reg [6:0] prepare_preserve_count = 0;
    reg [2:0] prepare_row_block_count = 0;
    reg fill_valid = 1'b0;
    wire fill_ready;
    reg [6:0] fill_slot = 0;
    reg [2:0] fill_row_block = 0;
    reg [`RECON_PHI_COLUMN_W-1:0] fill_column = 0;
    reg [31:0] fill_nonzero = 0;
    reg [31:0] fill_sign = 0;
    reg capture_valid = 1'b0;
    wire capture_ready;
    reg [`RECON_PHI_COLUMN_W-1:0] capture_column = 0;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] capture_row_block = 0;
    reg [31:0] capture_nonzero = 0;
    reg [31:0] capture_sign = 0;
    reg candidate_store_valid = 1'b0;
    wire candidate_store_ready;
    reg [5:0] candidate_store_slot = 0;
    reg [`RECON_PHI_COLUMN_W-1:0] candidate_store_column = 0;
    reg promote_valid = 1'b0;
    wire promote_ready;
    reg [5:0] promote_candidate_slot = 0;
    reg [6:0] promote_support_slot = 0;
    reg replay_valid = 1'b0;
    wire replay_ready;
    reg [6:0] replay_slot = 0;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] replay_row_block = 0;
    reg [`RECON_PHI_TAG_W-1:0] replay_tag = 0;
    wire replay_response_valid;
    reg replay_response_ready = 1'b0;
    wire [31:0] replay_nonzero;
    wire [31:0] replay_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] replay_column;
    wire [6:0] replay_response_slot;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] replay_response_row_block;
    wire [`RECON_PHI_TAG_W-1:0] replay_response_tag;
    wire cache_valid;
    wire cache_busy;
    wire cache_fault;

    support_phi_symbol_cache u_cache (
        .clk(clk), .rst_n(rst_n), .invalidate(cache_invalidate),
        .measurement_count(cache_measurement_count),
        .prepare_valid(prepare_valid), .prepare_ready(prepare_ready),
        .prepare_from_candidates(prepare_from_candidates),
        .prepare_support_count(prepare_support_count),
        .prepare_preserve_count(prepare_preserve_count),
        .prepare_row_block_count(prepare_row_block_count),
        .fill_valid(fill_valid), .fill_ready(fill_ready),
        .fill_slot(fill_slot), .fill_row_block(fill_row_block),
        .fill_column(fill_column), .fill_nonzero(fill_nonzero),
        .fill_sign(fill_sign), .capture_valid(capture_valid),
        .capture_ready(capture_ready), .capture_column(capture_column),
        .capture_row_block(capture_row_block),
        .capture_nonzero(capture_nonzero), .capture_sign(capture_sign),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .candidate_release_valid(1'b0),
        .candidate_release_column({`RECON_PHI_COLUMN_W{1'b0}}),
        .promote_valid(promote_valid), .promote_ready(promote_ready),
        .promote_candidate_slot(promote_candidate_slot),
        .promote_support_slot(promote_support_slot),
        .replay_valid(replay_valid), .replay_ready(replay_ready),
        .replay_slot(replay_slot), .replay_row_block(replay_row_block),
        .replay_tag(replay_tag),
        .replay_response_valid(replay_response_valid),
        .replay_response_ready(replay_response_ready),
        .replay_nonzero(replay_nonzero), .replay_sign(replay_sign),
        .replay_column(replay_column),
        .replay_response_slot(replay_response_slot),
        .replay_response_row_block(replay_response_row_block),
        .replay_response_tag(replay_response_tag),
        .cache_valid(cache_valid), .cache_busy(cache_busy),
        .cache_fault(cache_fault)
    );

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task issue_prepare;
        input candidate_mode;
        input [6:0] support_count;
        input [2:0] row_count;
        begin
            @(negedge clk);
            prepare_from_candidates = candidate_mode;
            prepare_support_count = support_count;
            prepare_row_block_count = row_count;
            prepare_valid = 1'b1;
            #1;
            while (!prepare_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            prepare_valid = 1'b0;
        end
    endtask

    task issue_fill;
        input [6:0] slot;
        input [2:0] row_block;
        input [`RECON_PHI_COLUMN_W-1:0] column;
        input [31:0] nonzero;
        input [31:0] sign;
        begin
            @(negedge clk);
            fill_slot = slot;
            fill_row_block = row_block;
            fill_column = column;
            fill_nonzero = nonzero;
            fill_sign = sign;
            fill_valid = 1'b1;
            #1;
            while (!fill_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            fill_valid = 1'b0;
        end
    endtask

    task issue_capture;
        input [`RECON_PHI_COLUMN_W-1:0] column;
        input [2:0] row_block;
        input [31:0] nonzero;
        input [31:0] sign;
        begin
            @(negedge clk);
            capture_column = column;
            capture_row_block = row_block;
            capture_nonzero = nonzero;
            capture_sign = sign;
            capture_valid = 1'b1;
            #1;
            while (!capture_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            capture_valid = 1'b0;
        end
    endtask

    task issue_replay_and_check;
        input [6:0] slot;
        input [2:0] row_block;
        input [`RECON_PHI_COLUMN_W-1:0] column;
        input [31:0] expected_nonzero;
        input [31:0] expected_sign;
        input [7:0] tag;
        input integer stall_cycles;
        integer wait_count;
        reg [31:0] held_sign;
        begin
            @(negedge clk);
            replay_slot = slot;
            replay_row_block = row_block;
            replay_tag = tag;
            replay_valid = 1'b1;
            #1;
            while (!replay_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            replay_valid = 1'b0;
            replay_response_ready = 1'b0;
            while (!replay_response_valid) @(negedge clk);
            held_sign = replay_sign;
            for (wait_count = 0; wait_count < stall_cycles; wait_count = wait_count + 1) begin
                @(posedge clk);
                #1;
                if (!replay_response_valid || replay_sign !== held_sign)
                    fail("cache replay changed while stalled");
            end
            if (replay_nonzero !== expected_nonzero ||
                replay_sign !== expected_sign || replay_column !== column ||
                replay_response_slot !== slot ||
                replay_response_row_block !== row_block ||
                replay_response_tag !== tag)
                fail("cache replay payload mismatch");
            @(negedge clk);
            replay_response_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            replay_response_ready = 1'b0;
        end
    endtask

    task issue_replay_burst_check;
        integer burst_issue;
        integer burst_response;
        reg [6:0] expected_slot [0:3];
        reg [2:0] expected_row [0:3];
        reg [9:0] expected_column [0:3];
        reg [31:0] expected_nonzero [0:3];
        reg [31:0] expected_sign [0:3];
        reg [7:0] expected_tag [0:3];
        begin
            expected_slot[0] = 0; expected_row[0] = 0;
            expected_column[0] = 10'd3; expected_nonzero[0] = 32'hffff_ffff;
            expected_sign[0] = 32'h1111_0000; expected_tag[0] = 8'h61;
            expected_slot[1] = 0; expected_row[1] = 1;
            expected_column[1] = 10'd3; expected_nonzero[1] = 32'hffff_ffff;
            expected_sign[1] = 32'h2222_0001; expected_tag[1] = 8'h62;
            expected_slot[2] = 1; expected_row[2] = 0;
            expected_column[2] = 10'd17; expected_nonzero[2] = 32'hffff_ffff;
            expected_sign[2] = 32'haaaa_1000; expected_tag[2] = 8'h63;
            expected_slot[3] = 1; expected_row[3] = 2;
            expected_column[3] = 10'd17; expected_nonzero[3] = 32'h0000_003f;
            expected_sign[3] = 32'hcccc_1002; expected_tag[3] = 8'h64;
            replay_response_ready = 1'b1;
            fork
                begin
                    for (burst_issue = 0; burst_issue < 4;
                         burst_issue = burst_issue + 1) begin
                        @(negedge clk);
                        replay_slot = expected_slot[burst_issue];
                        replay_row_block = expected_row[burst_issue];
                        replay_tag = expected_tag[burst_issue];
                        replay_valid = 1'b1;
                        #1;
                        if (!replay_ready)
                            fail("cache replay II is not one");
                        @(posedge clk);
                    end
                    @(negedge clk);
                    replay_valid = 1'b0;
                end
                begin
                    burst_response = 0;
                    while (burst_response < 4) begin
                        @(negedge clk);
                        if (replay_response_valid) begin
                            if (replay_response_slot !== expected_slot[burst_response] ||
                                replay_response_row_block !== expected_row[burst_response] ||
                                replay_column !== expected_column[burst_response] ||
                                replay_nonzero !== expected_nonzero[burst_response] ||
                                replay_sign !== expected_sign[burst_response] ||
                                replay_response_tag !== expected_tag[burst_response])
                                fail("pipelined cache replay payload mismatch");
                            burst_response = burst_response + 1;
                        end
                    end
                end
            join
            @(negedge clk);
            replay_response_ready = 1'b0;
        end
    endtask

    integer issue_index;
    integer response_index;
    integer first_accept_cycle;
    integer first_output_cycle;
    integer cycle_count = 0;
    always @(posedge clk)
        cycle_count = cycle_count + 1;

    initial begin
        norm_input[0] = `M7_NORMALIZER_INPUT_0;
        norm_mantissa[0] = `M7_NORMALIZER_MANTISSA_0;
        norm_exponent[0] = `M7_NORMALIZER_EXPONENT_0;
        norm_placement[0] = `M7_NORMALIZER_PLACEMENT_0;
        norm_tag[0] = `M7_NORMALIZER_TAG_0;
        norm_result[0] = `M7_NORMALIZER_RESULT_0;
        norm_saturated[0] = `M7_NORMALIZER_SATURATED_0;
        norm_input[1] = `M7_NORMALIZER_INPUT_1;
        norm_mantissa[1] = `M7_NORMALIZER_MANTISSA_1;
        norm_exponent[1] = `M7_NORMALIZER_EXPONENT_1;
        norm_placement[1] = `M7_NORMALIZER_PLACEMENT_1;
        norm_tag[1] = `M7_NORMALIZER_TAG_1;
        norm_result[1] = `M7_NORMALIZER_RESULT_1;
        norm_saturated[1] = `M7_NORMALIZER_SATURATED_1;
        norm_input[2] = `M7_NORMALIZER_INPUT_2;
        norm_mantissa[2] = `M7_NORMALIZER_MANTISSA_2;
        norm_exponent[2] = `M7_NORMALIZER_EXPONENT_2;
        norm_placement[2] = `M7_NORMALIZER_PLACEMENT_2;
        norm_tag[2] = `M7_NORMALIZER_TAG_2;
        norm_result[2] = `M7_NORMALIZER_RESULT_2;
        norm_saturated[2] = `M7_NORMALIZER_SATURATED_2;
        norm_input[3] = `M7_NORMALIZER_INPUT_3;
        norm_mantissa[3] = `M7_NORMALIZER_MANTISSA_3;
        norm_exponent[3] = `M7_NORMALIZER_EXPONENT_3;
        norm_placement[3] = `M7_NORMALIZER_PLACEMENT_3;
        norm_tag[3] = `M7_NORMALIZER_TAG_3;
        norm_result[3] = `M7_NORMALIZER_RESULT_3;
        norm_saturated[3] = `M7_NORMALIZER_SATURATED_3;
        norm_input[4] = `M7_NORMALIZER_INPUT_4;
        norm_mantissa[4] = `M7_NORMALIZER_MANTISSA_4;
        norm_exponent[4] = `M7_NORMALIZER_EXPONENT_4;
        norm_placement[4] = `M7_NORMALIZER_PLACEMENT_4;
        norm_tag[4] = `M7_NORMALIZER_TAG_4;
        norm_result[4] = `M7_NORMALIZER_RESULT_4;
        norm_saturated[4] = `M7_NORMALIZER_SATURATED_4;
        norm_input[5] = `M7_NORMALIZER_INPUT_5;
        norm_mantissa[5] = `M7_NORMALIZER_MANTISSA_5;
        norm_exponent[5] = `M7_NORMALIZER_EXPONENT_5;
        norm_placement[5] = `M7_NORMALIZER_PLACEMENT_5;
        norm_tag[5] = `M7_NORMALIZER_TAG_5;
        norm_result[5] = `M7_NORMALIZER_RESULT_5;
        norm_saturated[5] = `M7_NORMALIZER_SATURATED_5;
        norm_input[6] = `M7_NORMALIZER_INPUT_6;
        norm_mantissa[6] = `M7_NORMALIZER_MANTISSA_6;
        norm_exponent[6] = `M7_NORMALIZER_EXPONENT_6;
        norm_placement[6] = `M7_NORMALIZER_PLACEMENT_6;
        norm_tag[6] = `M7_NORMALIZER_TAG_6;
        norm_result[6] = `M7_NORMALIZER_RESULT_6;
        norm_saturated[6] = `M7_NORMALIZER_SATURATED_6;
        norm_input[7] = `M7_NORMALIZER_INPUT_7;
        norm_mantissa[7] = `M7_NORMALIZER_MANTISSA_7;
        norm_exponent[7] = `M7_NORMALIZER_EXPONENT_7;
        norm_placement[7] = `M7_NORMALIZER_PLACEMENT_7;
        norm_tag[7] = `M7_NORMALIZER_TAG_7;
        norm_result[7] = `M7_NORMALIZER_RESULT_7;
        norm_saturated[7] = `M7_NORMALIZER_SATURATED_7;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        normalizer_output_ready = 1'b1;
        fork
            begin
                for (issue_index = 0; issue_index < `M7_NORMALIZER_CASE_COUNT;
                     issue_index = issue_index + 1) begin
                    @(negedge clk);
                    normalizer_input_data = norm_input[issue_index];
                    normalizer_mantissa = norm_mantissa[issue_index];
                    normalizer_exponent = norm_exponent[issue_index];
                    normalizer_input_placement = norm_placement[issue_index];
                    normalizer_input_tag = norm_tag[issue_index];
                    normalizer_input_valid = 1'b1;
                    if (!normalizer_input_ready)
                        fail("normalizer II is not one");
                    @(posedge clk);
                    if (issue_index == 0)
                        first_accept_cycle = cycle_count;
                end
                @(negedge clk);
                normalizer_input_valid = 1'b0;
            end
            begin
                response_index = 0;
                while (response_index < `M7_NORMALIZER_CASE_COUNT) begin
                    @(posedge clk);
                    if (normalizer_output_valid) begin
                        if (response_index == 0)
                            first_output_cycle = cycle_count;
                        if (normalizer_output_data !== norm_result[response_index] ||
                            normalizer_output_placement !== norm_placement[response_index] ||
                            normalizer_output_tag !== norm_tag[response_index] ||
                            normalizer_output_saturated !== norm_saturated[response_index])
                            fail("normalizer bit-exact result mismatch");
                        response_index = response_index + 1;
                    end
                end
            end
        join
        if (first_output_cycle - first_accept_cycle - 1 !=
            `RECON_PHI_NORMALIZER_LATENCY) begin
            $display("Measured normalizer latency: %0d",
                     first_output_cycle - first_accept_cycle - 1);
            fail("normalizer latency is not four cycles");
        end
        @(negedge clk);
        normalizer_input_data = 62'sd12345;
        normalizer_mantissa = 18'd131072;
        normalizer_exponent = 5'd12;
        normalizer_input_is_data18 = 1'b1;
        normalizer_input_tag = 8'h7e;
        normalizer_input_valid = 1'b1;
        if (!normalizer_input_ready)
            fail("invalid-shift guard did not accept request");
        @(posedge clk);
        @(negedge clk);
        normalizer_input_valid = 1'b0;
        while (!normalizer_output_valid) @(posedge clk);
        if (normalizer_output_data !== 0 || !normalizer_output_saturated ||
            normalizer_output_tag !== 8'h7e)
            fail("invalid-shift guard did not fail closed");
        normalizer_input_is_data18 = 1'b0;
        $display("M7 NORMALIZER PASS");

        $display("M7 CACHE DIRECT PREPARE");
        issue_prepare(1'b0, 7'd2, 3'd3);
        $display("M7 CACHE DIRECT FILL");
        issue_fill(0, 0, 10'd3, 32'hffff_ffff, 32'h1111_0000);
        issue_fill(0, 1, 10'd3, 32'hffff_ffff, 32'h2222_0001);
        issue_fill(0, 2, 10'd3, 32'h0000_003f, 32'h3333_0002);
        issue_fill(1, 0, 10'd17, 32'hffff_ffff, 32'haaaa_1000);
        issue_fill(1, 1, 10'd17, 32'hffff_ffff, 32'hbbbb_1001);
        issue_fill(1, 2, 10'd17, 32'h0000_003f, 32'hcccc_1002);
        $display("M7 CACHE DIRECT FILLED valid=%0d fault=%0d", cache_valid, cache_fault);
        if (!cache_valid || cache_fault)
            fail("direct cache fill did not commit");
        issue_replay_burst_check();
        $display("M7 CACHE PIPELINED REPLAY PASS");
        issue_replay_and_check(0, 0, 10'd3, 32'hffff_ffff,
                               32'h1111_0000, 8'h31, 3);
        issue_replay_and_check(1, 2, 10'd17, 32'h0000_003f,
                               32'hcccc_1002, 8'h42, 0);
        $display("M7 CACHE FILL/REPLAY PASS");

        @(negedge clk);
        cache_invalidate = 1'b1;
        @(posedge clk);
        @(negedge clk);
        cache_invalidate = 1'b0;
        if (cache_valid || replay_ready)
            fail("cache invalidate failed");

        issue_capture(10'd11, 0, 32'hffff_ffff, 32'hd111_0000);
        $display("M7 CACHE CAPTURE 0");
        issue_capture(10'd11, 1, 32'hffff_ffff, 32'hd222_0001);
        $display("M7 CACHE CAPTURE 1");
        issue_capture(10'd11, 2, 32'h0000_003f, 32'hd333_0002);
        $display("M7 CACHE CAPTURE 2");
        @(negedge clk);
        candidate_store_slot = 6'd5;
        candidate_store_column = 10'd11;
        candidate_store_valid = 1'b1;
        #1;
        while (!candidate_store_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        candidate_store_valid = 1'b0;
        while (cache_busy) @(negedge clk);

        issue_prepare(1'b1, 7'd1, 3'd3);
        @(negedge clk);
        promote_candidate_slot = 6'd5;
        promote_support_slot = 7'd0;
        promote_valid = 1'b1;
        #1;
        while (!promote_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        promote_valid = 1'b0;
        while (!cache_valid && !cache_fault) @(negedge clk);
        if (cache_fault)
            fail("candidate promotion faulted");
        issue_replay_and_check(0, 0, 10'd11, 32'hffff_ffff,
                               32'hd111_0000, 8'h53, 0);
        issue_replay_and_check(0, 2, 10'd11, 32'h0000_003f,
                               32'hd333_0002, 8'h54, 0);
        $display("M7 CANDIDATE CAPTURE/PROMOTE PASS");

        @(negedge clk);
        cache_invalidate = 1'b1;
        @(posedge clk);
        @(negedge clk);
        cache_invalidate = 1'b0;
        issue_prepare(1'b0, 7'd1, 3'd3);
        issue_fill(0, 1, 10'd1, 32'hffff_ffff, 32'hdead_beef);
        if (!cache_fault || cache_valid)
            fail("out-of-order fill did not fault/invalidate");
        $display("M7 CACHE INVALIDATE/FAULT PASS");
        $finish;
    end

    initial begin
        repeat (3000) @(posedge clk);
        fail("cache/normalizer timeout");
    end
endmodule

`default_nettype wire
