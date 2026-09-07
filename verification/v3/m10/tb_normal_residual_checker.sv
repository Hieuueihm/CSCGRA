`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module tb_normal_residual_checker;
    localparam integer ENERGY_W = 62;
    localparam integer TAG_W = 3;

    reg clk = 0;
    always #3.333 clk = ~clk;
    reg rst_n = 0;
    reg request_valid = 0;
    wire request_ready;
    reg [TAG_W-1:0] request_tag = 0;
    reg [6:0] support_count = 0;
    reg [8:0] measurement_count = 9'd32;
    reg [4:0] normal_residual_shift = 0;
    reg [7:0] iterations_used = 0;
    reg [ENERGY_W-1:0] gamma_reference = 0;
    reg [ENERGY_W-1:0] normal_residual_sq = 0;
    reg breakdown = 0;
    reg saturation = 0;
    wire response_valid;
    reg response_ready = 1;
    wire [TAG_W-1:0] response_tag;
    wire certificate_pass;
    wire need_more_refinement;
    wire restart_required;
    wire response_breakdown;
    wire response_saturation;
    wire [7:0] response_iterations_used;
    wire [2:0] stop_reason;
    wire [ENERGY_W-1:0] relative_limit;
    wire [ENERGY_W-1:0] quantization_floor;
    wire [ENERGY_W-1:0] certificate_limit;
    wire [69:0] candidate_relative_limit;
    wire [69:0] candidate_quantization_floor;
    wire [69:0] candidate_certificate_limit;

    normal_residual_checker #(.ENERGY_W(ENERGY_W), .TAG_W(TAG_W)) dut (
        .clk(clk), .rst_n(rst_n), .request_valid(request_valid),
        .request_ready(request_ready), .request_tag(request_tag),
        .support_count(support_count), .measurement_count(measurement_count),
        .normal_residual_shift(normal_residual_shift),
        .iterations_used(iterations_used), .gamma_reference(gamma_reference),
        .normal_residual_sq(normal_residual_sq),
        .absolute_limit_enable(1'b0),
        .absolute_limit({ENERGY_W{1'b0}}), .breakdown(breakdown),
        .saturation(saturation), .response_valid(response_valid),
        .response_ready(response_ready), .response_tag(response_tag),
        .certificate_pass(certificate_pass),
        .need_more_refinement(need_more_refinement),
        .restart_required(restart_required),
        .response_breakdown(response_breakdown),
        .response_saturation(response_saturation),
        .response_iterations_used(response_iterations_used),
        .stop_reason(stop_reason), .relative_limit(relative_limit),
        .quantization_floor(quantization_floor),
        .certificate_limit(certificate_limit)
    );

    certificate_limit_unit #(
        .ENERGY_W(70),
        .ABSOLUTE_FLOOR(`RECON_CANDIDATE_CERT_ABSOLUTE_FLOOR),
        .SUPPORT_SMALL_SHIFT(`RECON_CANDIDATE_CERT_SUPPORT_SMALL_SHIFT),
        .SUPPORT_LARGE_SHIFT(`RECON_CANDIDATE_CERT_SUPPORT_LARGE_SHIFT),
        .MEASUREMENT_SHIFT(`RECON_CANDIDATE_CERT_MEASUREMENT_SHIFT)
    ) candidate_limit_unit (
        .support_count(support_count),
        .measurement_count(measurement_count),
        .normal_residual_shift(`RECON_CANDIDATE_STRICT_NORMAL_RESIDUAL_SHIFT),
        .gamma_reference({8'd0, gamma_reference}),
        .absolute_limit_enable(1'b0),
        .absolute_limit(70'd0),
        .relative_limit(candidate_relative_limit),
        .quantization_floor(candidate_quantization_floor),
        .certificate_limit(candidate_certificate_limit)
    );

    task fail;
        input [8*100-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task check_result;
        input [6:0] check_support;
        input [4:0] check_shift;
        input [ENERGY_W-1:0] check_reference;
        input [ENERGY_W-1:0] check_residual;
        input check_breakdown;
        input check_saturation;
        input [ENERGY_W-1:0] expected_relative;
        input [ENERGY_W-1:0] expected_floor;
        input [ENERGY_W-1:0] expected_limit;
        input expected_pass;
        begin
            @(negedge clk);
            request_tag = request_tag + 1'b1;
            support_count = check_support;
            normal_residual_shift = check_shift;
            iterations_used = 8'd9;
            gamma_reference = check_reference;
            normal_residual_sq = check_residual;
            breakdown = check_breakdown;
            saturation = check_saturation;
            request_valid = 1;
            while (!request_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            request_valid = 0;
            if (!response_valid) fail("checker response missing");
            if (response_tag != request_tag) fail("checker tag mismatch");
            if (relative_limit != expected_relative) fail("relative ceil mismatch");
            if (quantization_floor != expected_floor) fail("quant floor mismatch");
            if (certificate_limit != expected_limit) fail("certificate limit mismatch");
            if (certificate_pass != expected_pass) fail("certificate pass mismatch");
            if (need_more_refinement !=
                (!expected_pass && !check_breakdown && !check_saturation))
                fail("need-more mismatch");
            if (restart_required != !expected_pass) fail("restart mismatch");
            if (response_breakdown != check_breakdown) fail("breakdown mismatch");
            if (response_saturation != check_saturation) fail("saturation mismatch");
            if (response_iterations_used != 9) fail("iteration tag mismatch");
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    reg [TAG_W-1:0] held_tag;
    reg [ENERGY_W-1:0] held_limit;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        check_result(1, 14, (62'd5 << 28) + 1, 16384,
                     0, 0, 6, 16384, 16384, 1);
        check_result(32, 14, 1, 65536,
                     0, 0, 1, 65536, 65536, 1);
        check_result(32, 14, 1, 65537,
                     0, 0, 1, 65536, 65536, 0);
        check_result(64, 14, 1, 131072,
                     0, 0, 1, 131072, 131072, 1);
        check_result(96, 14, 1, 196609,
                     0, 0, 1, 196608, 196608, 0);
        check_result(32, 14, (62'd300000 << 28), 300000,
                     0, 0, 300000, 65536, 300000, 1);
        check_result(1, 31, 1, 1,
                     0, 0, 1, 16384, 16384, 1);
        check_result(1, 14, 1, 0,
                     1, 0, 1, 16384, 16384, 0);
        check_result(1, 14, 1, 0,
                     0, 1, 1, 16384, 16384, 0);

        support_count = 1;
        measurement_count = 32;
        gamma_reference = (62'd5 << 32) + 1;
        #1;
        if (candidate_relative_limit != 6 ||
            candidate_quantization_floor != 16384 ||
            candidate_certificate_limit != 16384)
            fail("D22 strict shift 16 certificate-unit mismatch");

        @(negedge clk);
        response_ready = 0;
        request_tag = 3'd6;
        support_count = 32;
        normal_residual_shift = 14;
        iterations_used = 7;
        gamma_reference = 1;
        normal_residual_sq = 10;
        breakdown = 0;
        saturation = 0;
        request_valid = 1;
        @(posedge clk);
        @(negedge clk);
        request_valid = 0;
        held_tag = response_tag;
        held_limit = certificate_limit;
        repeat (3) begin
            @(posedge clk);
            @(negedge clk);
            if (!response_valid || response_tag != held_tag ||
                certificate_limit != held_limit)
                fail("stalled checker payload changed");
        end
        response_ready = 1;
        @(posedge clk);

        $display("M10 NORMAL RESIDUAL CHECKER PASS");
        $finish;
    end

    initial begin
        #1000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
