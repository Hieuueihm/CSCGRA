`timescale 1ns/1ps
`default_nettype none

module m10_refinement_integration #(
    parameter integer ENERGY_W = 62,
    parameter integer TAG_W = 3
)(
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire abort_transaction,
    input  wire begin_valid,
    output wire begin_ready,
    input  wire [TAG_W-1:0] begin_tag,
    input  wire [1:0] profile,
    input  wire [6:0] support_count,
    input  wire [8:0] measurement_count,
    input  wire [7:0] iteration_limit,
    input  wire [7:0] max_iterations,
    input  wire [4:0] normal_residual_shift,
    input  wire [ENERGY_W-1:0] gamma_reference,
    input  wire step_valid,
    output wire step_ready,
    input  wire signed [ENERGY_W-1:0] gamma,
    input  wire [ENERGY_W-1:0] gamma_new,
    input  wire signed [ENERGY_W-1:0] delta,
    input  wire step_saturation,
    output wire recompute_request_valid,
    input  wire recompute_request_ready,
    output wire [TAG_W-1:0] recompute_request_tag,
    output wire [6:0] recompute_support_count,
    output wire [7:0] recompute_iterations_used,
    output wire trigger_cheap,
    output wire trigger_reliable,
    output wire trigger_profile_boundary,
    output wire trigger_final,
    input  wire recompute_result_valid,
    output wire recompute_result_ready,
    input  wire [TAG_W-1:0] recompute_result_tag,
    input  wire [ENERGY_W-1:0] normal_residual_sq,
    input  wire recompute_breakdown,
    input  wire recompute_saturation,
    output wire result_valid,
    input  wire result_ready,
    output wire [TAG_W-1:0] result_tag,
    output wire commit_valid,
    output wire rollback_valid,
    output wire restart_required,
    output wire result_fault,
    output wire [7:0] iterations_used,
    output wire certificate_fail_pulse,
    output wire transaction_active,
    output wire [31:0] full_checks_requested,
    output wire [31:0] full_checks_completed,
    output wire [31:0] full_checks_skipped,
    output wire [31:0] reliable_replacements,
    output wire [31:0] certificate_failures,
    output wire [31:0] committed_transactions,
    output wire [31:0] rolled_back_transactions
);
    wire [4:0] certificate_shift;
    wire [ENERGY_W-1:0] certificate_gamma_reference;
    wire checker_response_valid;
    wire checker_response_ready;
    wire [TAG_W-1:0] checker_response_tag;
    wire checker_pass;
    wire checker_breakdown;
    wire checker_saturation;

    restricted_refinement_state #(.ENERGY_W(ENERGY_W), .TAG_W(TAG_W))
    u_state (
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
        .certificate_request_valid(recompute_request_valid),
        .certificate_request_ready(recompute_request_ready),
        .certificate_request_tag(recompute_request_tag),
        .certificate_support_count(recompute_support_count),
        .certificate_shift(certificate_shift),
        .certificate_iterations_used(recompute_iterations_used),
        .certificate_gamma_reference(certificate_gamma_reference),
        .trigger_cheap(trigger_cheap), .trigger_reliable(trigger_reliable),
        .trigger_profile_boundary(trigger_profile_boundary),
        .trigger_final(trigger_final),
        .certificate_result_valid(checker_response_valid),
        .certificate_result_ready(checker_response_ready),
        .certificate_result_tag(checker_response_tag),
        .certificate_result_pass(checker_pass),
        .certificate_result_breakdown(checker_breakdown),
        .certificate_result_saturation(checker_saturation),
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

    normal_residual_checker #(.ENERGY_W(ENERGY_W), .TAG_W(TAG_W))
    u_checker (
        .clk(clk), .rst_n(rst_n), .request_valid(recompute_result_valid),
        .request_ready(recompute_result_ready), .request_tag(recompute_result_tag),
        .support_count(recompute_support_count),
        .measurement_count(measurement_count),
        .normal_residual_shift(certificate_shift),
        .iterations_used(recompute_iterations_used),
        .gamma_reference(certificate_gamma_reference),
        .normal_residual_sq(normal_residual_sq),
        .absolute_limit_enable(1'b0),
        .absolute_limit({ENERGY_W{1'b0}}),
        .breakdown(recompute_breakdown), .saturation(recompute_saturation),
        .response_valid(checker_response_valid),
        .response_ready(checker_response_ready),
        .response_tag(checker_response_tag), .certificate_pass(checker_pass),
        .need_more_refinement(), .restart_required(),
        .response_breakdown(checker_breakdown),
        .response_saturation(checker_saturation),
        .response_iterations_used(), .stop_reason(),
        .relative_limit(), .quantization_floor(), .certificate_limit()
    );
endmodule

`default_nettype wire
