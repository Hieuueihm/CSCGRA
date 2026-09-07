`timescale 1ns/1ps
`default_nettype none

module tb_restricted_refinement_state;
    localparam integer ENERGY_W = 62;
    localparam integer TAG_W = 3;
    localparam [1:0] PROFILE_STRICT = 2'd0;
    localparam [1:0] PROFILE_BALANCED = 2'd1;
    localparam [1:0] PROFILE_FAST = 2'd2;

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
    reg [4:0] normal_residual_shift = 0;
    reg [ENERGY_W-1:0] gamma_reference = 0;
    reg step_valid = 0;
    wire step_ready;
    reg signed [ENERGY_W-1:0] gamma = 1;
    reg [ENERGY_W-1:0] gamma_new = 0;
    reg signed [ENERGY_W-1:0] delta = 1;
    reg step_saturation = 0;
    wire certificate_request_valid;
    reg certificate_request_ready = 1;
    wire [TAG_W-1:0] certificate_request_tag;
    wire [6:0] certificate_support_count;
    wire [4:0] certificate_shift;
    wire [7:0] certificate_iterations_used;
    wire [ENERGY_W-1:0] certificate_gamma_reference;
    wire trigger_cheap;
    wire trigger_reliable;
    wire trigger_profile_boundary;
    wire trigger_final;
    reg certificate_result_valid = 0;
    wire certificate_result_ready;
    reg [TAG_W-1:0] certificate_result_tag = 0;
    reg certificate_result_pass = 0;
    reg certificate_result_breakdown = 0;
    reg certificate_result_saturation = 0;
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

    restricted_refinement_state #(.ENERGY_W(ENERGY_W), .TAG_W(TAG_W)) dut (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .abort_transaction(abort_transaction), .begin_valid(begin_valid),
        .begin_ready(begin_ready), .begin_tag(begin_tag), .profile(profile),
        .support_count(support_count), .measurement_count(measurement_count),
        .iteration_limit(iteration_limit),
        .max_iterations(max_iterations),
        .normal_residual_shift(normal_residual_shift),
        .gamma_reference(gamma_reference), .step_valid(step_valid),
        .step_ready(step_ready), .gamma(gamma), .gamma_new(gamma_new),
        .delta(delta), .step_saturation(step_saturation),
        .certificate_request_valid(certificate_request_valid),
        .certificate_request_ready(certificate_request_ready),
        .certificate_request_tag(certificate_request_tag),
        .certificate_support_count(certificate_support_count),
        .certificate_shift(certificate_shift),
        .certificate_iterations_used(certificate_iterations_used),
        .certificate_gamma_reference(certificate_gamma_reference),
        .trigger_cheap(trigger_cheap), .trigger_reliable(trigger_reliable),
        .trigger_profile_boundary(trigger_profile_boundary),
        .trigger_final(trigger_final),
        .certificate_result_valid(certificate_result_valid),
        .certificate_result_ready(certificate_result_ready),
        .certificate_result_tag(certificate_result_tag),
        .certificate_result_pass(certificate_result_pass),
        .certificate_result_breakdown(certificate_result_breakdown),
        .certificate_result_saturation(certificate_result_saturation),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_tag(result_tag), .commit_valid(commit_valid),
        .rollback_valid(rollback_valid), .restart_required(restart_required),
        .result_fault(result_fault), .iterations_used(iterations_used),
        .certificate_fail_pulse(certificate_fail_pulse),
        .transaction_active(transaction_active),
        .full_checks_requested(full_checks_requested),
        .full_checks_completed(full_checks_completed),
        .full_checks_skipped(full_checks_skipped),
        .reliable_replacements(reliable_replacements),
        .certificate_failures(certificate_failures),
        .committed_transactions(committed_transactions),
        .rolled_back_transactions(rolled_back_transactions)
    );

    task fail;
        input [8*100-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task start_transaction;
        input [1:0] start_profile;
        input [6:0] start_support;
        input [7:0] start_limit;
        input [7:0] start_max;
        begin
            @(negedge clk);
            begin_tag = begin_tag + 1'b1;
            profile = start_profile;
            support_count = start_support;
            iteration_limit = start_limit;
            max_iterations = start_max;
            normal_residual_shift = 14;
            gamma_reference = 62'd1;
            begin_valid = 1;
            while (!begin_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            begin_valid = 0;
        end
    endtask

    task send_step;
        input [ENERGY_W-1:0] next_gamma;
        input signed [ENERGY_W-1:0] current_gamma;
        input signed [ENERGY_W-1:0] current_delta;
        input saturated;
        begin
            @(negedge clk);
            gamma_new = next_gamma;
            gamma = current_gamma;
            delta = current_delta;
            step_saturation = saturated;
            step_valid = 1;
            while (!step_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            step_valid = 0;
            step_saturation = 0;
        end
    endtask

    task await_request;
        input expected_cheap;
        input expected_reliable;
        input expected_profile;
        input expected_final;
        begin
            while (!certificate_request_valid) @(negedge clk);
            if (certificate_request_tag != begin_tag) fail("request tag mismatch");
            if (certificate_support_count != support_count) fail("request support mismatch");
            if (certificate_gamma_reference != gamma_reference) fail("request reference mismatch");
            if (trigger_cheap != expected_cheap ||
                trigger_reliable != expected_reliable ||
                trigger_profile_boundary != expected_profile ||
                trigger_final != expected_final)
                fail("certificate trigger mismatch");
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task send_certificate;
        input [TAG_W-1:0] response_tag_value;
        input passed;
        input broken;
        input saturated;
        begin
            certificate_result_tag = response_tag_value;
            certificate_result_pass = passed;
            certificate_result_breakdown = broken;
            certificate_result_saturation = saturated;
            certificate_result_valid = 1;
            while (!certificate_result_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            certificate_result_valid = 0;
            certificate_result_breakdown = 0;
            certificate_result_saturation = 0;
        end
    endtask

    task expect_terminal;
        input expected_commit;
        input expected_rollback;
        input expected_fault;
        begin
            if (!result_valid) fail("terminal result missing");
            if (result_tag != begin_tag) fail("terminal tag mismatch");
            if (commit_valid != expected_commit ||
                rollback_valid != expected_rollback ||
                result_fault != expected_fault)
                fail("terminal payload mismatch");
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    integer step_index;
    reg [TAG_W-1:0] held_request_tag;
    reg [31:0] requested_base;
    reg [31:0] skipped_base;
    reg [31:0] failure_base;
    reg [31:0] rollback_base;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        start_transaction(PROFILE_STRICT, 1, 4, 4);
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag, 1, 0, 0);
        expect_terminal(1, 0, 0);

        requested_base = full_checks_requested;
        skipped_base = full_checks_skipped;
        failure_base = certificate_failures;
        start_transaction(PROFILE_STRICT, 32, 4, 4);
        send_step(100000, 100, 100, 0);
        if (full_checks_skipped != skipped_base + 1) fail("skip counter mismatch");
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag, 0, 0, 0);
        if (!restart_required || !certificate_fail_pulse)
            fail("certificate restart pulse missing");
        if (certificate_failures != failure_base + 1)
            fail("certificate failure counter mismatch");
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag, 1, 0, 0);
        expect_terminal(1, 0, 0);
        if (full_checks_requested != requested_base + 2)
            fail("requested counter mismatch");

        start_transaction(PROFILE_STRICT, 64, 10, 10);
        for (step_index = 0; step_index < 8; step_index = step_index + 1)
            send_step(1000000, 100, 100, 0);
        await_request(0, 1, 0, 0);
        send_certificate(begin_tag, 0, 0, 0);
        if (!restart_required || reliable_replacements != 1)
            fail("reliable replacement mismatch");
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag, 1, 0, 0);
        expect_terminal(1, 0, 0);

        start_transaction(PROFILE_BALANCED, 96, 2, 4);
        send_step(1000000, 100, 100, 0);
        send_step(1000000, 100, 100, 0);
        await_request(0, 0, 1, 0);
        send_certificate(begin_tag, 0, 0, 0);
        if (!restart_required || certificate_shift != 14)
            fail("balanced fallback mismatch");
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag, 1, 0, 0);
        expect_terminal(1, 0, 0);

        start_transaction(PROFILE_FAST, 32, 1, 4);
        send_step(1000000, 100, 100, 0);
        await_request(0, 0, 1, 0);
        send_certificate(begin_tag, 0, 0, 0);
        expect_terminal(1, 0, 0);

        rollback_base = rolled_back_transactions;
        start_transaction(PROFILE_STRICT, 32, 2, 2);
        send_step(1000000, 100, 100, 0);
        send_step(1000000, 100, 100, 0);
        await_request(0, 0, 0, 1);
        send_certificate(begin_tag, 0, 0, 0);
        expect_terminal(0, 1, 0);

        start_transaction(PROFILE_STRICT, 32, 2, 2);
        send_step(100000, 0, 100, 0);
        expect_terminal(0, 1, 1);

        start_transaction(PROFILE_STRICT, 32, 2, 2);
        send_step(100000, 100, 100, 1);
        expect_terminal(0, 1, 1);

        start_transaction(PROFILE_STRICT, 32, 2, 2);
        @(negedge clk);
        abort_transaction = 1;
        @(posedge clk);
        @(negedge clk);
        abort_transaction = 0;
        expect_terminal(0, 1, 0);

        start_transaction(PROFILE_STRICT, 32, 2, 2);
        send_step(16384, 100, 100, 0);
        await_request(1, 0, 0, 0);
        send_certificate(begin_tag + 1'b1, 1, 0, 0);
        expect_terminal(0, 1, 1);

        start_transaction(PROFILE_STRICT, 32, 2, 2);
        certificate_request_ready = 0;
        send_step(16384, 100, 100, 0);
        while (!certificate_request_valid) @(negedge clk);
        held_request_tag = certificate_request_tag;
        repeat (3) begin
            @(posedge clk);
            @(negedge clk);
            if (!certificate_request_valid ||
                certificate_request_tag != held_request_tag)
                fail("stalled request changed");
        end
        certificate_request_ready = 1;
        @(posedge clk);
        @(negedge clk);
        send_certificate(begin_tag, 1, 0, 0);
        result_ready = 0;
        if (!result_valid) fail("stalled terminal missing");
        repeat (3) begin
            @(posedge clk);
            @(negedge clk);
            if (!result_valid || !commit_valid || result_tag != begin_tag)
                fail("stalled result changed");
        end
        result_ready = 1;
        @(posedge clk);

        if (rolled_back_transactions != rollback_base + 5)
            fail("rollback total mismatch");
        if (full_checks_completed > full_checks_requested)
            fail("telemetry conservation mismatch");
        $display("M10 RESTRICTED REFINEMENT STATE PASS");
        $finish;
    end

    initial begin
        #3000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
