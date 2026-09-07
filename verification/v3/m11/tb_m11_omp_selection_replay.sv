`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m11_omp_selection_replay;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg cycle_valid = 0;
    reg cycle_commit = 0;
    reg [35:0] resource_ctx = 0;
    reg candidate_valid = 0;
    reg signed [`RECON_SOLVER_W-1:0] candidate_score = 0;
    reg [9:0] candidate_index = 0;
    wire candidate_ready;
    wire candidate_store_valid;
    wire [5:0] candidate_store_slot;
    wire [9:0] candidate_store_column;
    wire resource_in_ready;
    wire resource_out_ready;
    wire resource_contract_error;
    wire selection_fault_valid;
    wire [5:0] selection_count;
    wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores;
    wire [`RECON_K_MAX*10-1:0] result_indices;
    wire phi_cache_prepare_valid;
    wire [6:0] phi_cache_prepare_support_count;
    wire phi_cache_promote_valid;
    integer guard;
    reg second_epoch = 0;
    reg second_epoch_stored_member = 0;
    reg second_epoch_stored_next = 0;
    reg saw_support_count_two = 0;

    wire m5_cycle_valid;
    wire m5_cycle_commit;
    wire transport_restart_valid;
    wire [2:0] transport_restart_mask;
    wire [5:0] phi_cache_promote_candidate_slot;
    wire [6:0] phi_cache_promote_support_slot;
    wire phi_cache_invalidate;
    wire support_remap_event_valid;
    wire support_remap_event_fault;
    wire [6:0] support_remap_dropped_count;
    wire [96*10-1:0] support_remap_dropped_indices;
    wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients;
    wire refinement_event_valid;
    wire refinement_certificate_pass;
    wire refinement_restart_required;
    wire [2:0] refinement_stop_reason;

    m8_resource_dispatcher dut (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .selection_k(6'd1), .active_work_count(7'd1),
        .active_measurement_count(9'd32),
        .active_normal_residual_shift(5'd0),
        .active_residual_limit({`RECON_ACC_W{1'b1}}),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .resource_ctx(resource_ctx),
        .m5_cycle_valid(m5_cycle_valid), .m5_cycle_commit(m5_cycle_commit),
        .m5_resource_in_ready(1'b1), .m5_resource_out_ready(1'b1),
        .m5_resource_contract_error(1'b0),
        .m5_scalar0_valid(1'b1), .m5_scalar0_data({`RECON_ACC_W{1'b0}}),
        .m5_scalar1_valid(1'b1), .m5_scalar1_data({`RECON_ACC_W{1'b0}}),
        .m5_refinement_breakdown(1'b0), .m5_refinement_saturation(1'b0),
        .transport_restart_ready(1'b1),
        .transport_restart_valid(transport_restart_valid),
        .transport_restart_mask(transport_restart_mask),
        .candidate_valid(candidate_valid), .candidate_ready(candidate_ready),
        .candidate_score(candidate_score), .candidate_index(candidate_index),
        .candidate_saturated(1'b0),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(1'b1),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .phi_cache_prepare_valid(phi_cache_prepare_valid),
        .phi_cache_prepare_ready(1'b1),
        .phi_cache_prepare_support_count(phi_cache_prepare_support_count),
        .phi_cache_prepare_preserve_count(),
        .phi_cache_promote_valid(phi_cache_promote_valid),
        .phi_cache_promote_ready(1'b1),
        .phi_cache_promote_candidate_slot(phi_cache_promote_candidate_slot),
        .phi_cache_promote_support_slot(phi_cache_promote_support_slot),
        .phi_cache_valid(1'b1), .phi_cache_fault(1'b0),
        .phi_cache_invalidate(phi_cache_invalidate),
        .resource_in_ready(resource_in_ready),
        .resource_out_ready(resource_out_ready),
        .resource_contract_error(resource_contract_error),
        .selection_fault_valid(selection_fault_valid),
        .support_remap_event_valid(support_remap_event_valid),
        .support_remap_event_fault(support_remap_event_fault),
        .support_remap_dropped_count(support_remap_dropped_count),
        .support_remap_dropped_indices(support_remap_dropped_indices),
        .support_remap_dropped_coefficients(support_remap_dropped_coefficients),
        .active_support_bitmap(), .active_support_indices(),
        .active_support_coefficients(), .active_support_gradients(),
        .active_support_gradient_valid(), .active_support_count(),
        .refinement_event_valid(refinement_event_valid),
        .refinement_certificate_pass(refinement_certificate_pass),
        .refinement_restart_required(refinement_restart_required),
        .refinement_stop_reason(refinement_stop_reason),
        .termination_event_valid(),
        .termination_residual_limit_reached(), .termination_residual_sq(),
        .selection_count(selection_count), .result_scores(result_scores),
        .result_indices(result_indices)
    );

    function [35:0] make_resource;
        input [4:0] operation;
        input [5:0] configuration_id;
        input wait_for_ready;
        input wait_for_result;
        input [3:0] event_id;
        reg [35:0] word;
        begin
            word = 0;
            word[`RECON_RESOURCE_FIELD_OPERATION_LSB +: `RECON_RESOURCE_FIELD_OPERATION_W] = operation;
            if (operation == `RECON_RESOURCE_OP_TOPK_PUSH)
                word[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_INPUT_SELECT_W] =
                    `RECON_RESOURCE_INPUT_GLOBAL_REDUCTION;
            word[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +: `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W] = configuration_id;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB] = wait_for_ready;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB] = wait_for_result;
            word[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +: `RECON_RESOURCE_FIELD_EVENT_ID_W] = event_id;
            make_resource = word;
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s time=%0t op=%0d pending=%b epoch=%b topk_ready=%b support_ready=%b support_state=%0d",
                message, $time,
                resource_ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +: `RECON_RESOURCE_FIELD_OPERATION_W],
                dut.pending_valid, dut.selection_epoch_pending,
                dut.topk_cycle_ready, dut.support_cycle_ready,
                dut.u_support.state);
            $finish;
        end
    endtask

    task issue;
        input [4:0] operation;
        input [5:0] configuration_id;
        input [3:0] event_id;
        input has_candidate;
        input signed [`RECON_SOLVER_W-1:0] score;
        input [9:0] index;
        begin
            @(negedge clk);
            resource_ctx = make_resource(operation, configuration_id, 1'b1, 1'b0, event_id);
            cycle_valid = 1;
            candidate_valid = has_candidate;
            candidate_score = score;
            candidate_index = index;
            #1;
            guard = 0;
            while (!resource_in_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 400) fail("issue timeout");
            end
            cycle_commit = 1;
            #1;
            if (has_candidate && !candidate_ready)
                fail("candidate handshake missing");
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 0;
            candidate_valid = 0;

            resource_ctx = make_resource(operation, configuration_id, 1'b0, 1'b1, event_id);
            #1;
            guard = 0;
            while (!resource_out_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (resource_contract_error) fail("legal response contract error");
                if (guard > 1200) fail("response timeout");
            end
            cycle_commit = 1;
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 0;
            cycle_valid = 0;
            resource_ctx = 0;
            if (selection_fault_valid) fail("selection fault");
        end
    endtask

    always @(posedge clk) begin
        if (second_epoch && candidate_store_valid) begin
            if (candidate_store_column == 10'd5)
                second_epoch_stored_member <= 1;
            if (candidate_store_column == 10'd7)
                second_epoch_stored_next <= 1;
        end
        if (phi_cache_prepare_valid && (phi_cache_prepare_support_count == 2))
            saw_support_count_two <= 1;
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(negedge clk); routine_start = 1;
        @(posedge clk); @(negedge clk); routine_start = 0;

        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 6'h22, 1, 1, 27'sd100, 10'd5);
        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 6'h22, 2, 1, 27'sd80, 10'd7);
        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 6'h22, 3, 1, 27'sd90, 10'd9);
        issue(`RECON_RESOURCE_OP_TOPK_COMMIT, 0, 4, 0, 0, 0);
        if (selection_count != 2 || result_indices[0 +: 10] != 10'd5 ||
            result_indices[10 +: 10] != 10'd9)
            fail("context literal TOP2 override mismatch");
        @(negedge clk); routine_start = 1;
        @(posedge clk); @(negedge clk); routine_start = 0;

        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 1, 1, 27'sd100, 10'd5);
        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 2, 1, 27'sd80, 10'd7);
        issue(`RECON_RESOURCE_OP_TOPK_COMMIT, 0, 3, 0, 0, 0);
        if (selection_count != 1 || result_indices[0 +: 10] != 10'd5)
            fail("epoch one top candidate mismatch");
        issue(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 4, 0, 0, 0);
        issue(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 5, 0, 0, 0);

        second_epoch = 1;
        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 6, 1, 27'sd120, 10'd5);
        issue(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 7, 1, 27'sd90, 10'd7);
        issue(`RECON_RESOURCE_OP_TOPK_COMMIT, 0, 8, 0, 0, 0);
        if (selection_count != 1 || result_indices[0 +: 10] != 10'd7)
            fail("support exclusion did not choose next atom");
        if (second_epoch_stored_member || !second_epoch_stored_next)
            fail("collector accepted excluded support atom");
        issue(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 9, 0, 0, 0);
        issue(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 10, 0, 0, 0);
        if (!saw_support_count_two)
            fail("second support commit did not reach count two");

        $display("M11 OMP SELECTION EPOCH/EXCLUSION REPLAY PASS");
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk);
        fail("timeout");
    end
endmodule

`default_nettype wire
