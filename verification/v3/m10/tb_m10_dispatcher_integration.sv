`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m10_dispatcher_integration;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg scalar_state_clear = 0;
    reg algorithm_preload_seen = 0;
    reg [5:0] selection_k = 6'd2;
    reg [6:0] active_work_count = 7'd32;
    reg [8:0] active_measurement_count = 9'd32;
    reg [1:0] active_refinement_profile = 2'd0;
    reg [7:0] active_refine_limit = 8'd8;
    reg [4:0] active_normal_residual_shift = 5'd14;
    reg [`RECON_ACC_W-1:0] active_residual_limit = {`RECON_ACC_W{1'b1}};
    reg cycle_valid = 0;
    reg cycle_commit = 0;
    reg [35:0] resource_ctx = 0;
    wire m5_cycle_valid;
    wire m5_cycle_commit;
    reg m5_resource_in_ready = 1;
    reg m5_resource_out_ready = 1;
    reg m5_resource_contract_error = 0;
    reg m5_scalar0_valid = 1;
    reg signed [`RECON_ACC_W-1:0] m5_scalar0_data = 1;
    reg m5_scalar1_valid = 1;
    reg signed [`RECON_ACC_W-1:0] m5_scalar1_data = 0;
    reg m5_refinement_breakdown = 0;
    reg m5_refinement_saturation = 0;
    reg transport_restart_ready = 1;
    wire transport_restart_valid;
    wire [2:0] transport_restart_mask;
    reg candidate_valid = 0;
    wire candidate_ready;
    reg signed [`RECON_SOLVER_W-1:0] candidate_score = 0;
    reg [9:0] candidate_index = 0;
    reg candidate_saturated = 0;
    wire candidate_store_valid;
    reg candidate_store_ready = 1;
    wire [5:0] candidate_store_slot;
    wire [9:0] candidate_store_column;
    wire phi_cache_prepare_valid;
    reg phi_cache_prepare_ready = 1;
    wire phi_cache_prepare_from_candidates;
    wire [6:0] phi_cache_prepare_support_count;
    wire [6:0] phi_cache_prepare_preserve_count;
    wire phi_cache_promote_valid;
    reg phi_cache_promote_ready = 1;
    wire [5:0] phi_cache_promote_candidate_slot;
    wire [6:0] phi_cache_promote_support_slot;
    reg phi_cache_valid = 1;
    reg phi_cache_fault = 0;
    wire phi_cache_invalidate;
    wire phi_cache_refill_pending;
    wire [6:0] phi_cache_refill_support_count;
    wire phi_cache_refill_column_valid;
    reg phi_cache_refill_column_ready = 0;
    wire [6:0] phi_cache_refill_column_slot;
    wire [9:0] phi_cache_refill_column;
    wire resource_in_ready;
    wire resource_out_ready;
    wire resource_contract_error;
    wire selection_fault_valid;
    wire support_remap_event_valid;
    wire support_remap_event_fault;
    wire [6:0] support_remap_dropped_count;
    wire [96*10-1:0] support_remap_dropped_indices;
    wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients;
    wire [1023:0] active_support_bitmap;
    wire [96*10-1:0] active_support_indices;
    wire [96*`RECON_SOLVER_W-1:0] active_support_coefficients;
    reg support_coefficient_stripe_read_enable = 0;
    reg [2:0] support_coefficient_stripe_read_index = 0;
    wire support_coefficient_stripe_read_valid;
    wire [16*`RECON_SOLVER_W-1:0]
        support_coefficient_stripe_read_coefficients;
    wire [96*`RECON_SOLVER_W-1:0] active_support_gradients;
    wire [95:0] active_support_gradient_valid;
    wire [6:0] active_support_count;
    wire refinement_event_valid;
    wire refinement_certificate_pass;
    wire refinement_restart_required;
    wire refinement_recompute_required;
    wire refinement_replacement_required;
    wire refinement_iteration_advance;
    wire [2:0] refinement_stop_reason;
    wire termination_event_valid;
    wire termination_residual_limit_reached;
    wire [`RECON_ACC_W-1:0] termination_residual_sq;
    wire [5:0] selection_count;
    wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores;
    wire [`RECON_K_MAX*10-1:0] result_indices;

    m8_resource_dispatcher dut (.*);

    function [35:0] make_resource;
        input [4:0] operation;
        input [5:0] configuration;
        input wait_ready;
        input wait_result;
        input [3:0] tag;
        input refinement_format;
        reg [35:0] word;
        begin
            word = 0;
            word[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                 `RECON_RESOURCE_FIELD_OPERATION_W] = operation;
            word[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +:
                 `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W] = configuration;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB] = wait_ready;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB] = wait_result;
            word[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +:
                 `RECON_RESOURCE_FIELD_EVENT_ID_W] = tag;
            if (refinement_format) begin
                word[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_INPUT_SELECT_W] =
                    configuration[5] ? `RECON_RESOURCE_INPUT_SCALAR_1 :
                    `RECON_RESOURCE_INPUT_SCALAR_0;
                word[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W] =
                    `RECON_RESOURCE_OUTPUT_EVENT;
                word[`RECON_RESOURCE_FIELD_COUNT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_COUNT_SELECT_W] =
                    configuration[5] ?
                    `RECON_RESOURCE_COUNT_MEASUREMENT_COUNT :
                    `RECON_RESOURCE_COUNT_ACTIVE_SUPPORT_COUNT;
            end
            make_resource = word;
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s time=%0t ctx=%h pending=%0d owner=%0d err=%0d",
                message, $time, resource_ctx, dut.pending_valid,
                dut.pending_owner, resource_contract_error);
            $display("CERT pass=%0d restart=%0d stop=%0d event=%0d ref=%0d rel=%0d floor=%0d limit=%0d residual=%0d work=%0d shift=%0d full_pending=%0d",
                refinement_certificate_pass, refinement_restart_required,
                refinement_stop_reason, refinement_event_valid,
                dut.refinement_reference_comb, dut.refinement_relative_limit,
                dut.refinement_quantization_floor,
                dut.refinement_certificate_limit, m5_scalar1_data,
                dut.resident_work_count, dut.refinement_certificate_shift,
                dut.refinement_full_check_pending);
            $finish;
        end
    endtask

    task issue;
        input [4:0] operation;
        input [5:0] configuration;
        input [3:0] tag;
        input refinement_format;
        begin
            @(negedge clk);
            resource_ctx = make_resource(operation, configuration, 1, 0,
                                         tag, refinement_format);
            cycle_valid = 1;
            cycle_commit = 0;
            #1;
            if (!resource_in_ready || resource_contract_error)
                fail("issue rejected");
            cycle_commit = 1;
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 0;
        end
    endtask

    task wait_response;
        input [4:0] operation;
        input [5:0] configuration;
        input [3:0] tag;
        input refinement_format;
        integer guard;
        begin
            resource_ctx = make_resource(operation, configuration, 0, 1,
                                         tag, refinement_format);
            cycle_commit = 0;
            guard = 0;
            while (!resource_out_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (resource_contract_error) fail("legal wait flagged error");
                if (guard > 100) fail("response timeout");
            end
            repeat (3) begin
                @(negedge clk);
                if (!resource_out_ready || resource_contract_error)
                    fail("response changed while stalled");
            end
            cycle_commit = 1;
            #1;
            if (operation == `RECON_RESOURCE_OP_REFINEMENT_CHECK) begin
                if (configuration[5] && !termination_event_valid)
                    fail("termination event missing");
                if (!configuration[5] && !refinement_event_valid)
                    fail("refinement event missing");
            end
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 0;
            cycle_valid = 0;
            resource_ctx = 0;
        end
    endtask

    reg [31:0] rollback_base;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        issue(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 1, 0);
        wait_response(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 1, 0);
        if (!dut.support_transaction_open) fail("support proposal not open");
        rollback_base = dut.support_rollback_count;

        m5_scalar0_data = 1;
        m5_scalar1_data = 62'sd65536;
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 3, 2, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 3, 2, 1);
        if (refinement_certificate_pass || !refinement_restart_required ||
            !refinement_recompute_required || refinement_stop_reason != 2)
            fail("certificate recompute trigger mismatch");
        if (!dut.support_transaction_open)
            fail("recompute trigger rolled back support");

        m5_scalar1_data = 62'sd65537;
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 3, 2, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 3, 2, 1);
        if (refinement_certificate_pass || !refinement_restart_required ||
            refinement_stop_reason != 2)
            fail("certificate failure event mismatch");
        if (!refinement_replacement_required ||
            !dut.support_transaction_open ||
            dut.support_rollback_count != rollback_base ||
            phi_cache_invalidate)
            fail("certificate replacement did not preserve proposal");

        issue(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 3, 0);
        wait_response(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 3, 0);
        m5_scalar1_data = 62'sd65536;
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 4, 4, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 4, 4, 1);
        if (refinement_certificate_pass || !refinement_restart_required ||
            !refinement_recompute_required || refinement_stop_reason != 2)
            fail("passing certificate recompute trigger mismatch");
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 4, 4, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 4, 4, 1);
        if (!refinement_certificate_pass || refinement_restart_required ||
            refinement_stop_reason != 1)
            fail("certificate pass event mismatch");
        if (!dut.support_transaction_open)
            fail("passing certificate rolled back support");

        issue(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 5, 0);
        wait_response(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 5, 0);
        issue(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 6, 0);
        wait_response(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 6, 0);
        m5_scalar0_data = -62'sd1;
        m5_scalar1_data = 0;
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 1, 7, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 1, 7, 1);
        if (refinement_certificate_pass || refinement_stop_reason != 3)
            fail("breakdown fail-closed mismatch");
        if (dut.support_transaction_open)
            fail("breakdown did not rollback support");

        active_residual_limit = 62'd100;
        m5_scalar0_data = 1;
        m5_scalar1_data = 62'sd99 <<
            (2 * (`RECON_SOLVER_F-`RECON_DATA_F));
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 6'd32, 8, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 6'd32, 8, 1);
        if (!termination_residual_limit_reached ||
            termination_residual_sq != 62'd99 || refinement_event_valid)
            fail("termination residual pass mismatch");
        m5_scalar1_data = 62'sd101 <<
            (2 * (`RECON_SOLVER_F-`RECON_DATA_F));
        issue(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 6'd32, 9, 1);
        wait_response(`RECON_RESOURCE_OP_REFINEMENT_CHECK, 6'd32, 9, 1);
        if (termination_residual_limit_reached ||
            termination_residual_sq != 62'd101 || refinement_event_valid)
            fail("termination residual fail mismatch");

        @(negedge clk);
        m5_scalar0_data = 1;
        m5_scalar1_data = 0;
        resource_ctx = make_resource(`RECON_RESOURCE_OP_REFINEMENT_CHECK,
                                     0, 1, 0, 10, 0);
        cycle_valid = 1;
        #1;
        if (!resource_contract_error || resource_in_ready)
            fail("malformed refinement context accepted");
        cycle_valid = 0;
        resource_ctx = 0;

        if (m5_cycle_valid || m5_cycle_commit || selection_fault_valid)
            fail("refinement leaked into M5/selection owner");

        $display("M10 DISPATCHER REFINEMENT/ROLLBACK PASS");
        $finish;
    end

    initial begin
        #2000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
