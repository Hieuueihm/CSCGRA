`timescale 1ns/1ps
`default_nettype none

module restricted_refinement_state #(
    parameter integer ENERGY_W = 62,
    parameter integer TAG_W = 3,
    parameter integer WORK_MAX = 96,
    parameter integer RELIABLE_INTERVAL = 8,
    parameter integer STRICT_SHIFT = 14
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
    output reg  certificate_request_valid,
    input  wire certificate_request_ready,
    output reg  [TAG_W-1:0] certificate_request_tag,
    output reg  [6:0] certificate_support_count,
    output reg  [4:0] certificate_shift,
    output reg  [7:0] certificate_iterations_used,
    output reg  [ENERGY_W-1:0] certificate_gamma_reference,
    output reg  trigger_cheap,
    output reg  trigger_reliable,
    output reg  trigger_profile_boundary,
    output reg  trigger_final,
    input  wire certificate_result_valid,
    output wire certificate_result_ready,
    input  wire [TAG_W-1:0] certificate_result_tag,
    input  wire certificate_result_pass,
    input  wire certificate_result_breakdown,
    input  wire certificate_result_saturation,
    output reg  result_valid,
    input  wire result_ready,
    output reg  [TAG_W-1:0] result_tag,
    output reg  commit_valid,
    output reg  rollback_valid,
    output reg  restart_required,
    output reg  result_fault,
    output reg  [7:0] iterations_used,
    output reg  certificate_fail_pulse,
    output wire transaction_active,
    output reg  [31:0] full_checks_requested,
    output reg  [31:0] full_checks_completed,
    output reg  [31:0] full_checks_skipped,
    output reg  [31:0] reliable_replacements,
    output reg  [31:0] certificate_failures,
    output reg  [31:0] committed_transactions,
    output reg  [31:0] rolled_back_transactions
);
    localparam [1:0] PROFILE_STRICT = 2'd0;
    localparam [1:0] PROFILE_BALANCED = 2'd1;
    localparam [1:0] PROFILE_FAST = 2'd2;
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_RUN = 2'd1;
    localparam [1:0] STATE_REQUEST = 2'd2;
    localparam [1:0] STATE_WAIT = 2'd3;

    reg [1:0] state;
    reg [TAG_W-1:0] active_tag;
    reg [1:0] active_profile;
    reg [6:0] active_support_count;
    reg [8:0] active_measurement_count;
    reg [7:0] active_iteration_limit;
    reg [7:0] active_max_iterations;
    reg [4:0] active_shift;
    reg [ENERGY_W-1:0] active_gamma_reference;
    reg [7:0] active_iterations;
    reg balanced_fallback;
    reg pending_reliable;
    reg pending_profile_boundary;
    reg pending_final;

    wire result_advance = !result_valid || result_ready;
    assign begin_ready = (state == STATE_IDLE) && result_advance;
    assign step_ready = (state == STATE_RUN) && !result_valid;
    assign certificate_result_ready = state == STATE_WAIT;
    assign transaction_active = state != STATE_IDLE;

    wire begin_accept = begin_valid && begin_ready;
    wire step_accept = step_valid && step_ready;
    wire request_accept = certificate_request_valid && certificate_request_ready;
    wire certificate_accept = certificate_result_valid && certificate_result_ready;
    wire [7:0] next_iteration = active_iterations + 1'b1;
    wire profile_boundary =
        ((active_profile == PROFILE_BALANCED) && !balanced_fallback &&
         (next_iteration >= active_iteration_limit)) ||
        ((active_profile == PROFILE_FAST) &&
         (next_iteration >= active_iteration_limit));
    wire final_boundary = next_iteration >= active_max_iterations;
    wire reliable_boundary = (RELIABLE_INTERVAL > 0) &&
                             ((next_iteration % RELIABLE_INTERVAL) == 0);

    reg [6:0] double_shift;
    reg [ENERGY_W-1:0] relative_limit_comb;
    reg [ENERGY_W-1:0] remainder_mask;
    reg [ENERGY_W-1:0] support_floor_comb;
    reg [ENERGY_W-1:0] measurement_floor_comb;
    reg [ENERGY_W-1:0] quant_floor_comb;
    reg [ENERGY_W-1:0] certificate_limit_comb;
    reg effective_cheap;
    always @* begin
        double_shift = {active_shift, 1'b0};
        if (double_shift == 0) begin
            relative_limit_comb = active_gamma_reference;
            remainder_mask = 0;
        end else if (double_shift >= ENERGY_W) begin
            relative_limit_comb = active_gamma_reference != 0;
            remainder_mask = {ENERGY_W{1'b1}};
        end else begin
            remainder_mask = ~({ENERGY_W{1'b1}} << double_shift);
            relative_limit_comb = (active_gamma_reference >> double_shift) +
                                  ((active_gamma_reference & remainder_mask) != 0);
        end
        support_floor_comb = active_measurement_count <= 32 ?
            {{(ENERGY_W-18){1'b0}}, active_support_count, 11'b0} :
            {{(ENERGY_W-19){1'b0}}, active_support_count, 12'b0};
        measurement_floor_comb = active_measurement_count > 32 ?
            {{(ENERGY_W-19){1'b0}}, active_measurement_count, 10'b0} :
            {ENERGY_W{1'b0}};
        quant_floor_comb = support_floor_comb > 16384 ?
                           support_floor_comb : 16384;
        if (measurement_floor_comb > quant_floor_comb)
            quant_floor_comb = measurement_floor_comb;
        certificate_limit_comb = relative_limit_comb > quant_floor_comb ?
                                 relative_limit_comb : quant_floor_comb;
        effective_cheap = gamma_new <= certificate_limit_comb;
    end

    function [31:0] increment_saturated;
        input [31:0] value;
        begin
            increment_saturated = value == 32'hffffffff ? value : value + 1'b1;
        end
    endfunction

    task set_terminal;
        input do_commit;
        input do_rollback;
        input do_restart;
        input fault;
        begin
            result_valid <= 1;
            result_tag <= active_tag;
            commit_valid <= do_commit;
            rollback_valid <= do_rollback;
            restart_required <= do_restart;
            result_fault <= fault;
            iterations_used <= active_iterations;
            if (do_commit)
                committed_transactions <= increment_saturated(committed_transactions);
            if (do_rollback)
                rolled_back_transactions <= increment_saturated(rolled_back_transactions);
            state <= STATE_IDLE;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            active_tag <= 0;
            active_profile <= 0;
            active_support_count <= 0;
            active_measurement_count <= 0;
            active_iteration_limit <= 0;
            active_max_iterations <= 0;
            active_shift <= 0;
            active_gamma_reference <= 0;
            active_iterations <= 0;
            balanced_fallback <= 0;
            pending_reliable <= 0;
            pending_profile_boundary <= 0;
            pending_final <= 0;
            certificate_request_valid <= 0;
            certificate_request_tag <= 0;
            certificate_support_count <= 0;
            certificate_shift <= 0;
            certificate_iterations_used <= 0;
            certificate_gamma_reference <= 0;
            trigger_cheap <= 0;
            trigger_reliable <= 0;
            trigger_profile_boundary <= 0;
            trigger_final <= 0;
            result_valid <= 0;
            result_tag <= 0;
            commit_valid <= 0;
            rollback_valid <= 0;
            restart_required <= 0;
            result_fault <= 0;
            iterations_used <= 0;
            certificate_fail_pulse <= 0;
            if (!result_valid)
                restart_required <= 0;
            full_checks_requested <= 0;
            full_checks_completed <= 0;
            full_checks_skipped <= 0;
            reliable_replacements <= 0;
            certificate_failures <= 0;
            committed_transactions <= 0;
            rolled_back_transactions <= 0;
        end else begin
            certificate_fail_pulse <= 0;
            if (result_valid && result_ready) begin
                result_valid <= 0;
                commit_valid <= 0;
                rollback_valid <= 0;
                restart_required <= 0;
                result_fault <= 0;
            end
            if (request_accept) begin
                certificate_request_valid <= 0;
                state <= STATE_WAIT;
            end

            if (routine_start && (state != STATE_IDLE)) begin
                certificate_request_valid <= 0;
                certificate_fail_pulse <= 1;
                set_terminal(0, 1, 0, 1);
            end else if (abort_transaction && (state != STATE_IDLE)) begin
                certificate_request_valid <= 0;
                certificate_fail_pulse <= 1;
                set_terminal(0, 1, 0, 0);
            end else begin
                if (begin_accept) begin
                    active_tag <= begin_tag;
                    active_profile <= profile;
                active_support_count <= support_count;
                active_measurement_count <= measurement_count;
                    active_iteration_limit <= iteration_limit;
                    active_max_iterations <= max_iterations;
                    active_shift <= normal_residual_shift;
                    active_gamma_reference <= gamma_reference;
                    active_iterations <= 0;
                    balanced_fallback <= 0;
                    if ((profile > PROFILE_FAST) || (support_count == 0) ||
                        (support_count > WORK_MAX) || (iteration_limit == 0) ||
                        (max_iterations == 0) ||
                        (iteration_limit > max_iterations)) begin
                        result_valid <= 1;
                        result_tag <= begin_tag;
                        commit_valid <= 0;
                        rollback_valid <= 1;
                        restart_required <= 0;
                        result_fault <= 1;
                        iterations_used <= 0;
                        rolled_back_transactions <=
                            increment_saturated(rolled_back_transactions);
                        state <= STATE_IDLE;
                    end else begin
                        state <= STATE_RUN;
                    end
                end

                if (step_accept) begin
                    active_iterations <= next_iteration;
                    if ((gamma <= 0) || (delta <= 0) || step_saturation) begin
                        result_valid <= 1;
                        result_tag <= active_tag;
                        commit_valid <= 0;
                        rollback_valid <= 1;
                        restart_required <= 0;
                        result_fault <= 1;
                        iterations_used <= next_iteration;
                        certificate_fail_pulse <= 1;
                        rolled_back_transactions <=
                            increment_saturated(rolled_back_transactions);
                        state <= STATE_IDLE;
                    end else if (effective_cheap || reliable_boundary ||
                                 profile_boundary || final_boundary) begin
                        certificate_request_valid <= 1;
                        certificate_request_tag <= active_tag;
                        certificate_support_count <= active_support_count;
                        certificate_shift <= balanced_fallback ?
                                             STRICT_SHIFT : active_shift;
                        certificate_iterations_used <= next_iteration;
                        certificate_gamma_reference <= active_gamma_reference;
                        trigger_cheap <= effective_cheap;
                        trigger_reliable <= reliable_boundary;
                        trigger_profile_boundary <= profile_boundary;
                        trigger_final <= final_boundary;
                        pending_reliable <= reliable_boundary;
                        pending_profile_boundary <= profile_boundary;
                        pending_final <= final_boundary;
                        full_checks_requested <=
                            increment_saturated(full_checks_requested);
                        state <= STATE_REQUEST;
                    end else begin
                        full_checks_skipped <=
                            increment_saturated(full_checks_skipped);
                    end
                end

                if (certificate_accept) begin
                    full_checks_completed <=
                        increment_saturated(full_checks_completed);
                    if ((certificate_result_tag != active_tag) ||
                        certificate_result_breakdown ||
                        certificate_result_saturation) begin
                        certificate_fail_pulse <= 1;
                        certificate_failures <=
                            increment_saturated(certificate_failures);
                        set_terminal(0, 1, 0, 1);
                    end else if ((active_profile == PROFILE_FAST) &&
                                 pending_profile_boundary) begin
                        set_terminal(1, 0, 0, 0);
                    end else if (certificate_result_pass) begin
                        set_terminal(1, 0, 0, 0);
                    end else begin
                        certificate_fail_pulse <= 1;
                        certificate_failures <=
                            increment_saturated(certificate_failures);
                        if (pending_reliable)
                            reliable_replacements <=
                                increment_saturated(reliable_replacements);
                        if ((active_profile == PROFILE_BALANCED) &&
                            pending_profile_boundary && !balanced_fallback) begin
                            balanced_fallback <= 1;
                            active_shift <= STRICT_SHIFT;
                            restart_required <= 1;
                            state <= STATE_RUN;
                        end else if (!pending_final) begin
                            restart_required <= 1;
                            state <= STATE_RUN;
                        end else begin
                            set_terminal(0, 1, 0, 0);
                        end
                    end
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_request_stalled;
    reg [TAG_W-1:0] f_request_tag;
    reg [ENERGY_W-1:0] f_request_reference;
    reg f_result_stalled;
    reg [TAG_W-1:0] f_result_tag;
    reg f_commit_valid;
    reg f_rollback_valid;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;
        f_request_stalled <= certificate_request_valid &&
                             !certificate_request_ready;
        f_request_tag <= certificate_request_tag;
        f_request_reference <= certificate_gamma_reference;
        f_result_stalled <= result_valid && !result_ready;
        f_result_tag <= result_tag;
        f_commit_valid <= commit_valid;
        f_rollback_valid <= rollback_valid;
        if (rst_n && f_past_valid && f_request_stalled) begin
            assert(certificate_request_valid);
            assert(certificate_request_tag == f_request_tag);
            assert(certificate_gamma_reference == f_request_reference);
        end
        if (rst_n && f_past_valid && f_result_stalled) begin
            assert(result_valid);
            assert(result_tag == f_result_tag);
            assert(commit_valid == f_commit_valid);
            assert(rollback_valid == f_rollback_valid);
        end
        if (rst_n && result_valid)
            assert(!(commit_valid && rollback_valid));
    end
`endif
endmodule

`default_nettype wire
