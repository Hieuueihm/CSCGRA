`timescale 1ns/1ps
`default_nettype none

module tb_m10_refinement_integration;
    localparam integer ENERGY_W = 62;
    localparam integer TAG_W = 3;
    reg clk = 0;
    always #3.333 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg abort_transaction = 0;
    reg begin_valid = 0;
    wire begin_ready;
    reg [TAG_W-1:0] begin_tag = 0;
    reg [1:0] profile = 0;
    reg [6:0] support_count = 0;
    reg [8:0] measurement_count = 9'd32;
    reg [7:0] iteration_limit = 0;
    reg [7:0] max_iterations = 0;
    reg [4:0] normal_residual_shift = 14;
    reg [ENERGY_W-1:0] gamma_reference = 1;
    reg step_valid = 0;
    wire step_ready;
    reg signed [ENERGY_W-1:0] gamma = 100;
    reg [ENERGY_W-1:0] gamma_new = 0;
    reg signed [ENERGY_W-1:0] delta = 100;
    reg step_saturation = 0;
    wire recompute_request_valid;
    reg recompute_request_ready = 1;
    wire [TAG_W-1:0] recompute_request_tag;
    wire [6:0] recompute_support_count;
    wire [7:0] recompute_iterations_used;
    wire trigger_cheap;
    wire trigger_reliable;
    wire trigger_profile_boundary;
    wire trigger_final;
    reg recompute_result_valid = 0;
    wire recompute_result_ready;
    reg [TAG_W-1:0] recompute_result_tag = 0;
    reg [ENERGY_W-1:0] normal_residual_sq = 0;
    reg recompute_breakdown = 0;
    reg recompute_saturation = 0;
    wire result_valid;
    reg result_ready = 1;
    wire [TAG_W-1:0] result_tag;
    wire commit_valid;
    wire rollback_valid;
    wire restart_required;
    wire result_fault;
    wire [7:0] iterations_used;
    wire certificate_fail_pulse;
    wire transaction_active;
    wire [31:0] full_checks_requested;
    wire [31:0] full_checks_completed;
    wire [31:0] full_checks_skipped;
    wire [31:0] reliable_replacements;
    wire [31:0] certificate_failures;
    wire [31:0] committed_transactions;
    wire [31:0] rolled_back_transactions;

    m10_refinement_integration dut (.*);

    task fail;
        input [8*100-1:0] message;
        begin
            $display("FAIL: %0s time=%0t tag=%0d support=%0d",
                     message, $time, begin_tag, support_count);
            $finish;
        end
    endtask

    task start_case;
        input [6:0] count;
        input [7:0] limit;
        input [7:0] maximum;
        begin
            @(negedge clk);
            begin_tag = begin_tag + 1'b1;
            support_count = count;
            iteration_limit = limit;
            max_iterations = maximum;
            begin_valid = 1;
            while (!begin_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            begin_valid = 0;
        end
    endtask

    task step_case;
        input [ENERGY_W-1:0] next_gamma;
        begin
            gamma_new = next_gamma;
            step_valid = 1;
            while (!step_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            step_valid = 0;
        end
    endtask

    task recompute_case;
        input [ENERGY_W-1:0] residual_sq;
        begin
            while (!recompute_request_valid) @(negedge clk);
            if (recompute_request_tag != begin_tag ||
                recompute_support_count != support_count)
                fail("recompute request metadata mismatch");
            @(posedge clk);
            @(negedge clk);
            recompute_result_tag = recompute_request_tag;
            normal_residual_sq = residual_sq;
            recompute_result_valid = 1;
            while (!recompute_result_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            recompute_result_valid = 0;
        end
    endtask

    task expect_result;
        input expect_commit;
        input expect_rollback;
        begin
            while (!result_valid) @(negedge clk);
            if (result_tag != begin_tag || commit_valid != expect_commit ||
                rollback_valid != expect_rollback || result_fault)
                fail("integrated terminal mismatch");
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    integer case_index;
    integer step_index;
    reg [ENERGY_W-1:0] expected_floor;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        for (case_index = 1; case_index <= 32; case_index = case_index + 1) begin
            expected_floor = case_index * 2048;
            if (expected_floor < 16384)
                expected_floor = 16384;
            start_case(case_index[6:0], 1, 1);
            step_case(expected_floor);
            if (!trigger_cheap || !trigger_final)
                fail("S corner trigger mismatch");
            recompute_case(expected_floor);
            expect_result(1, 0);
        end
        start_case(64, 1, 1);
        step_case(131072);
        recompute_case(131072);
        expect_result(1, 0);
        start_case(96, 1, 1);
        step_case(196608);
        recompute_case(196608);
        expect_result(1, 0);

        start_case(32, 1, 1);
        step_case(65536);
        recompute_case(65537);
        expect_result(0, 1);
        if (!certificate_fail_pulse && certificate_failures != 1)
            fail("certificate failure telemetry mismatch");

        start_case(32, 10, 10);
        for (step_index = 0; step_index < 8; step_index = step_index + 1)
            step_case(1000000);
        if (!recompute_request_valid || !trigger_reliable || trigger_cheap)
            fail("interval-8 trigger mismatch");
        recompute_case(65536);
        expect_result(1, 0);

        if (full_checks_requested != 36 || full_checks_completed != 36 ||
            full_checks_skipped != 7 || committed_transactions != 35 ||
            rolled_back_transactions != 1)
            fail("integrated telemetry conservation mismatch");
        $display("M10 REFINEMENT INTEGRATION PASS");
        $finish;
    end

    initial begin
        #2000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
