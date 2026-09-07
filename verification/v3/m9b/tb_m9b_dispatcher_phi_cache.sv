`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m9b_dispatcher_phi_cache;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg routine_start = 1'b0;
    reg [8:0] measurement_count = 9'd128;
    reg [5:0] selection_k = 6'd2;
    reg cycle_valid = 1'b0;
    reg cycle_commit = 1'b0;
    reg [35:0] resource_ctx = 36'd0;
    wire m5_cycle_valid;
    wire m5_cycle_commit;
    reg m5_resource_in_ready = 1'b1;
    reg m5_resource_out_ready = 1'b1;
    reg m5_resource_contract_error = 1'b0;
    reg transport_restart_ready = 1'b1;
    wire transport_restart_valid;
    wire [2:0] transport_restart_mask;
    reg candidate_valid = 1'b0;
    wire candidate_ready;
    reg signed [`RECON_SOLVER_W-1:0] candidate_score = 0;
    reg [9:0] candidate_index = 0;
    reg candidate_saturated = 1'b0;
    reg capture_valid = 1'b0;
    wire capture_ready;
    reg [9:0] capture_column = 0;
    reg [2:0] capture_row_block = 0;
    reg [31:0] capture_nonzero = 32'hffff_ffff;
    reg [31:0] capture_sign = 0;
    reg replay_valid = 1'b0;
    wire replay_ready;
    reg [6:0] replay_slot = 0;
    reg [2:0] replay_row_block = 0;
    reg [7:0] replay_tag = 0;
    wire replay_response_valid;
    reg replay_response_ready = 1'b0;
    wire [31:0] replay_nonzero;
    wire [31:0] replay_sign;
    wire [9:0] replay_column;
    wire [6:0] replay_response_slot;
    wire [2:0] replay_response_row_block;
    wire [7:0] replay_response_tag;
    wire cache_valid;
    wire cache_busy;
    wire cache_fault;
    wire resource_in_ready;
    wire resource_out_ready;
    wire resource_contract_error;
    wire selection_fault_valid;
    wire support_remap_event_valid;
    wire support_remap_event_fault;
    wire [6:0] support_remap_dropped_count;
    wire [96*10-1:0] support_remap_dropped_indices;
    wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients;
    wire [96*10-1:0] active_support_indices;
    wire [96*`RECON_SOLVER_W-1:0] active_support_coefficients;
    wire [6:0] active_support_count;
    wire [5:0] selection_count;
    wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] result_scores;
    wire [`RECON_K_MAX*10-1:0] result_indices;
    reg [7:0] support_seen = 8'd0;
    integer response_stall = 0;
    integer guard;

    m9b_n3_integration dut (.*);

    function [35:0] make_resource;
        input [4:0] op;
        input [5:0] config_id;
        input wait_ready;
        input wait_result;
        input [3:0] tag;
        reg [35:0] word;
        begin
            word = 36'd0;
            word[`RECON_RESOURCE_FIELD_OPERATION_LSB +: `RECON_RESOURCE_FIELD_OPERATION_W] = op;
            word[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +: `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W] = config_id;
            word[`RECON_RESOURCE_FIELD_STREAM_BOUNDARY_LSB +: `RECON_RESOURCE_FIELD_STREAM_BOUNDARY_W] = `RECON_STREAM_BOUNDARY_BODY;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB] = wait_ready;
            word[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB] = wait_result;
            word[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +: `RECON_RESOURCE_FIELD_EVENT_ID_W] = tag;
            make_resource = word;
        end
    endfunction

    function signed [`RECON_SOLVER_W-1:0] canonical_data_coefficient;
        input signed [`RECON_SOLVER_W-1:0] value;
        reg [`RECON_SOLVER_W:0] magnitude;
        reg [`RECON_SOLVER_W:0] rounded_magnitude;
        reg signed [`RECON_DATA_W-1:0] data_value;
        begin
            magnitude = value[`RECON_SOLVER_W-1] ?
                {1'b0, (~value + 1'b1)} : {1'b0, value};
            rounded_magnitude =
                (magnitude + (1'b1 <<
                 (`RECON_SOLVER_F-`RECON_DATA_F-1))) >>
                (`RECON_SOLVER_F-`RECON_DATA_F);
            data_value = value[`RECON_SOLVER_W-1] ?
                -$signed(rounded_magnitude[`RECON_DATA_W-1:0]) :
                $signed(rounded_magnitude[`RECON_DATA_W-1:0]);
            canonical_data_coefficient =
                $signed({{(`RECON_SOLVER_W-`RECON_DATA_W){
                    data_value[`RECON_DATA_W-1]}}, data_value}) <<<
                (`RECON_SOLVER_F-`RECON_DATA_F);
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s time=%0t ctx=%h pending=%0d op=%0d tag=%0d support=%0d out=%0d err=%0d topv=%0d supv=%0d",
                message, $time, resource_ctx, dut.u_dispatcher.pending_valid,
                dut.u_dispatcher.pending_operation, dut.u_dispatcher.pending_tag,
                dut.u_dispatcher.pending_support, resource_out_ready,
                resource_contract_error, dut.u_dispatcher.topk_response_valid,
                dut.u_dispatcher.support_response_valid);
            $finish;
        end
    endtask

    task capture_column_words;
        input [9:0] column;
        input [31:0] base_sign;
        integer row;
        begin
            for (row = 0; row < 4; row = row + 1) begin
                @(negedge clk);
                capture_column = column;
                capture_row_block = row[2:0];
                capture_nonzero = 32'hffff_ffff;
                capture_sign = base_sign + row;
                capture_valid = 1'b1;
                guard = 0;
                while (!capture_ready) begin
                    @(negedge clk);
                    guard = guard + 1;
                    if (guard > 200) fail("capture ready timeout");
                end
                @(posedge clk);
                @(negedge clk);
                capture_valid = 1'b0;
            end
        end
    endtask

    task begin_issue;
        input [4:0] op;
        input [5:0] config_id;
        input [3:0] tag;
        input with_candidate;
        input signed [`RECON_SOLVER_W-1:0] score;
        input [9:0] index;
        begin
            @(negedge clk);
            resource_ctx = make_resource(op, config_id, 1'b1, 1'b0, tag);
            cycle_valid = 1'b1;
            cycle_commit = 1'b0;
            candidate_valid = with_candidate;
            candidate_score = score;
            candidate_index = index;
            #1;
            guard = 0;
            while (!resource_in_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 500) fail("issue ready timeout");
            end
            cycle_commit = 1'b1;
            #1;
            if (with_candidate && !candidate_ready)
                fail("candidate not accepted with issue");
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b0;
            candidate_valid = 1'b0;
            if ((op >= `RECON_RESOURCE_OP_SUPPORT_CLEAR) &&
                (op <= `RECON_RESOURCE_OP_SUPPORT_ROLLBACK))
                support_seen[op-`RECON_RESOURCE_OP_SUPPORT_CLEAR] = 1'b1;
        end
    endtask

    task finish_response;
        input [4:0] op;
        input [5:0] config_id;
        input [3:0] tag;
        begin
            resource_ctx = make_resource(op, config_id, 1'b0, 1'b1, tag);
            cycle_valid = 1'b1;
            cycle_commit = 1'b0;
            #1;
            guard = 0;
            while (!resource_out_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (resource_contract_error)
                    fail("legal response flagged contract error");
                if (guard > 1200) fail("response ready timeout");
            end
            response_stall = $urandom_range(0, 4);
            repeat (response_stall) begin
                @(negedge clk);
                if (!resource_out_ready || resource_contract_error)
                    fail("response changed during backpressure");
            end
            cycle_commit = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b0;
            cycle_valid = 1'b0;
            resource_ctx = 36'd0;
            if (selection_fault_valid)
                fail("unexpected selection fault");
        end
    endtask

    task issue_context;
        input [4:0] op;
        input [5:0] config_id;
        input [3:0] tag;
        input with_candidate;
        input signed [`RECON_SOLVER_W-1:0] score;
        input [9:0] index;
        begin
            begin_issue(op, config_id, tag, with_candidate, score, index);
            finish_response(op, config_id, tag);
        end
    endtask

    task issue_active_scatter;
        input [6:0] slot;
        input signed [`RECON_SOLVER_W-1:0] coefficient;
        input [3:0] tag;
        input integer stall_cycles;
        reg [35:0] stream_resource;
        reg [96*10-1:0] indices_before;
        reg cache_before;
        begin
            indices_before = active_support_indices;
            cache_before = cache_valid;
            @(negedge clk);
            stream_resource = make_resource(
                `RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, 1'b1, 1'b0, tag);
            stream_resource[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                            `RECON_RESOURCE_FIELD_INPUT_SELECT_W] =
                `RECON_RESOURCE_INPUT_MEMORY_STREAM;
            resource_ctx = stream_resource;
            cycle_valid = 1'b1;
            cycle_commit = 1'b0;
            candidate_valid = 1'b1;
            candidate_score = coefficient;
            candidate_index = {3'd0, slot};
            repeat (stall_cycles) begin
                @(negedge clk);
                if (!resource_in_ready || candidate_ready)
                    fail("active scatter pre-commit handshake mismatch");
                if (active_support_indices != indices_before ||
                    cache_valid != cache_before ||
                    dut.u_dispatcher.support_transaction_open ||
                    dut.u_dispatcher.phi_cache_refill_pending)
                    fail("active scatter changed state before commit");
            end
            cycle_commit = 1'b1;
            #1;
            if (!resource_in_ready || !candidate_ready ||
                resource_contract_error)
                fail("active scatter issue rejected");
            if (dut.u_dispatcher.phi_cache_prepare_valid ||
                dut.u_dispatcher.phi_cache_promote_valid ||
                dut.u_dispatcher.phi_cache_invalidate)
                fail("active scatter touched Phi cache transaction");
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b0;
            candidate_valid = 1'b0;
            finish_response(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, tag);
            if (active_support_indices != indices_before ||
                $signed(active_support_coefficients[slot*`RECON_SOLVER_W +:
                        `RECON_SOLVER_W]) !=
                canonical_data_coefficient(coefficient))
                fail("active scatter coefficient writeback mismatch");
            if (cache_valid != cache_before ||
                dut.u_dispatcher.support_transaction_open ||
                dut.u_dispatcher.phi_cache_refill_pending)
                fail("active scatter opened proposal or cache refill");
        end
    endtask

    task replay_check;
        input [6:0] slot;
        input [2:0] row_block;
        input [9:0] column;
        input [31:0] sign_word;
        input [7:0] tag;
        begin
            @(negedge clk);
            replay_slot = slot;
            replay_row_block = row_block;
            replay_tag = tag;
            replay_valid = 1'b1;
            guard = 0;
            while (!replay_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 300) fail("replay request timeout");
            end
            @(posedge clk);
            @(negedge clk);
            replay_valid = 1'b0;
            repeat ($urandom_range(0, 3)) @(negedge clk);
            replay_response_ready = 1'b1;
            guard = 0;
            while (!replay_response_valid) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 300) fail("replay response timeout");
            end
            if (replay_column != column || replay_sign != sign_word ||
                replay_nonzero != 32'hffff_ffff ||
                replay_response_slot != slot ||
                replay_response_row_block != row_block ||
                replay_response_tag != tag)
                fail("Phi cache replay mismatch");
            @(posedge clk);
            @(negedge clk);
            replay_response_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        routine_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        routine_start = 1'b0;

        resource_ctx = make_resource(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 1, 4'h1);
        cycle_valid = 1'b1;
        #1;
        if (!resource_contract_error || resource_out_ready)
            fail("response without pending not fail-closed");
        cycle_valid = 1'b0;
        resource_ctx = 0;

        capture_column_words(10'd11, 32'ha110_0000);
        issue_context(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 4'h1, 1'b1, 27'sd100, 10'd11);
        while (!capture_ready) @(negedge clk);
        capture_column_words(10'd22, 32'hb220_0000);
        issue_context(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 4'h2, 1'b1, 27'sd90, 10'd22);

        issue_context(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 4'h3, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 4'h4, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_UNION, 0, 4'h5, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, 4'h6, 0, -27'sd17, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 4'h7, 0, 0, 0);
        if (!cache_valid || cache_fault) fail("commit did not validate Phi cache");

        capture_column_words(10'd33, 32'hc330_0000);
        issue_context(`RECON_RESOURCE_OP_TOPK_PUSH, 0, 4'h0, 1'b1, 27'sd80, 10'd33);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_APPEND, 2, 4'h1, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 4'h2, 0, 0, 0);
        if (!cache_valid || cache_fault) fail("prefix-preserving commit failed");

        if (active_support_count != 3)
            fail("active support count mismatch before coefficient writeback");
        issue_active_scatter(7'd0, 27'sd31415, 4'h8, 3);
        issue_active_scatter(7'd1, -27'sd27182, 4'h9, 1);

        issue_context(`RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP, 0, 4'h0, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 4'h1, 0, 0, 0);

        begin_issue(`RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP, 0, 4'h2, 0, 0, 0);
        resource_ctx = make_resource(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 0, 1, 4'h2);
        cycle_valid = 1'b1;
        #1;
        if (!resource_contract_error || resource_out_ready)
            fail("wrong pending opcode not fail-closed");
        resource_ctx = make_resource(`RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP, 0, 0, 1, 4'h3);
        #1;
        if (!resource_contract_error || resource_out_ready)
            fail("wrong pending tag not fail-closed");
        finish_response(`RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP, 0, 4'h2);

        issue_context(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 4'h3, 0, 0, 0);
        issue_context(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 4'h4, 0, 0, 0);
        if (support_seen != 8'hff) fail("not all eight SUPPORT opcodes replayed");

        replay_check(0, 0, 10'd11, 32'ha110_0000, 8'h51);
        replay_check(0, 3, 10'd11, 32'ha110_0003, 8'h52);
        replay_check(1, 1, 10'd22, 32'hb220_0001, 8'h61);
        replay_check(2, 2, 10'd33, 32'hc330_0002, 8'h71);

        @(negedge clk);
        resource_ctx = make_resource(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0, 4'h5);
        cycle_valid = 1'b1;
        #1;
        if (!resource_contract_error || resource_in_ready || resource_out_ready)
            fail("support context without wait not fail-closed");
        resource_ctx = make_resource(5'd31, 0, 0, 0, 4'h6);
        #1;
        if (!resource_contract_error || resource_in_ready || resource_out_ready)
            fail("unowned opcode not fail-closed");
        cycle_valid = 1'b0;
        resource_ctx = 0;

        $display("M9B DISPATCHER CONTEXT REPLAY/N3 PHI CACHE PASS");
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk);
        fail("integration timeout");
    end
endmodule

`default_nettype wire
