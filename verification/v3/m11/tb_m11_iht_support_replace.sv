`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m11_iht_support_replace;
    localparam integer DATA_W = `RECON_SOLVER_W;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg cycle_valid = 0;
    reg cycle_commit = 0;
    reg [4:0] operation = 0;
    reg [2:0] request_tag = 0;
    reg [6:0] request_slot = 0;
    reg request_cache_from_candidates = 1;
    reg request_candidate_coefficients = 0;
    wire cycle_ready;
    wire response_valid;
    reg response_ready = 0;
    wire response_fault;
    wire [6:0] current_count;
    wire current_bank;
    reg [6:0] candidate_count = 2;
    reg [64*DATA_W-1:0] candidate_values = 0;
    reg [64*10-1:0] candidate_indices = 0;
    reg [64*6-1:0] candidate_symbol_slots = 0;
    wire [96*37-1:0] bank0_entries;
    wire [96*37-1:0] bank1_entries;
    wire cache_prepare_valid;
    wire cache_prepare_ready;
    wire cache_prepare_from_candidates;
    wire [6:0] cache_prepare_support_count;
    wire [6:0] cache_prepare_preserve_count;
    wire cache_valid;
    wire cache_fault;
    wire cache_refill_pending;
    wire [6:0] cache_refill_support_count;
    wire cache_refill_column_valid;
    reg cache_refill_column_ready = 0;
    wire [6:0] cache_refill_column_slot;
    wire [9:0] cache_refill_column;
    reg fill_valid = 0;
    wire fill_ready;
    reg [6:0] fill_slot = 0;
    reg [2:0] fill_row_block = 0;
    reg [9:0] fill_column = 0;
    reg [31:0] fill_sign = 0;
    wire replay_ready;
    reg replay_valid = 0;
    reg [6:0] replay_slot = 0;
    reg [2:0] replay_row_block = 0;
    wire replay_response_valid;
    reg replay_response_ready = 0;
    wire [31:0] replay_sign;
    wire [9:0] replay_column;

    support_state_manager dut (
        .clk(clk), .rst_n(rst_n), .routine_start(1'b0),
        .abort_transaction(1'b0), .certificate_fail(1'b0),
        .cycle_valid(cycle_valid), .cycle_ready(cycle_ready),
        .cycle_commit(cycle_commit), .operation(operation),
        .request_tag(request_tag), .request_slot(request_slot),
        .request_cache_from_candidates(request_cache_from_candidates),
        .request_candidate_coefficients(request_candidate_coefficients),
        .request_zero_candidate_coefficient(1'b0),
        .request_defer_activation(1'b0),
        .request_sort_by_index(1'b0),
        .request_scatter_active(1'b0),
        .scatter_coefficient(27'sd0), .candidate_count(candidate_count),
        .candidate_values(candidate_values), .candidate_indices(candidate_indices),
        .candidate_symbol_slots(candidate_symbol_slots),
        .membership_query_atom(10'd0), .membership_query_member(),
        .membership_query_slot(),
        .append_gradient_valid(), .append_gradient_slot(),
        .append_gradient_value(),
        .response_valid(response_valid), .response_ready(response_ready),
        .response_operation(), .response_tag(), .response_fault(response_fault),
        .response_count(), .response_member(), .response_slot(),
        .response_atom(), .response_coefficient(), .transaction_open(),
        .current_bank(current_bank), .current_count(current_count),
        .proposed_count(), .view_count(), .proposal_view_active(),
        .rollback_count(), .rollback_cycle_count(),
        .bank0_entries(bank0_entries), .bank1_entries(bank1_entries),
        .bank0_slot_valid(), .bank1_slot_valid(), .remap_event_valid(),
        .active_support_bitmap(),
        .active_support_indices(),
        .active_support_coefficients(),
        .remap_event_fault(), .remap_dropped_count(),
        .remap_dropped_indices(), .remap_dropped_coefficients(),
        .cache_prepare_valid(cache_prepare_valid),
        .cache_prepare_ready(cache_prepare_ready),
        .cache_prepare_from_candidates(cache_prepare_from_candidates),
        .cache_prepare_support_count(cache_prepare_support_count),
        .cache_prepare_preserve_count(cache_prepare_preserve_count),
        .cache_promote_valid(), .cache_promote_ready(1'b0),
        .cache_promote_candidate_slot(), .cache_promote_support_slot(),
        .cache_valid(cache_valid), .cache_fault(cache_fault),
        .cache_invalidate(), .cache_refill_pending(cache_refill_pending),
        .cache_refill_support_count(cache_refill_support_count),
        .cache_refill_column_valid(cache_refill_column_valid),
        .cache_refill_column_ready(cache_refill_column_ready),
        .cache_refill_column_slot(cache_refill_column_slot),
        .cache_refill_column(cache_refill_column)
    );

    support_phi_symbol_cache cache (
        .clk(clk), .rst_n(rst_n), .invalidate(1'b0),
        .measurement_count(9'd64), .prepare_valid(cache_prepare_valid),
        .prepare_ready(cache_prepare_ready),
        .prepare_from_candidates(cache_prepare_from_candidates),
        .prepare_support_count(cache_prepare_support_count),
        .prepare_preserve_count(cache_prepare_preserve_count),
        .prepare_row_block_count(3'd2), .fill_valid(fill_valid),
        .fill_ready(fill_ready), .fill_slot(fill_slot),
        .fill_row_block(fill_row_block), .fill_column(fill_column),
        .fill_nonzero(32'hffff_ffff), .fill_sign(fill_sign),
        .capture_valid(1'b0), .capture_ready(), .capture_column(10'd0),
        .capture_row_block(3'd0), .capture_nonzero(32'd0), .capture_sign(32'd0),
        .candidate_store_valid(1'b0), .candidate_store_ready(),
        .candidate_store_slot(6'd0), .candidate_store_column(10'd0),
        .candidate_release_valid(1'b0), .candidate_release_column(10'd0),
        .promote_valid(1'b0), .promote_ready(),
        .promote_candidate_slot(6'd0), .promote_support_slot(7'd0),
        .replay_valid(replay_valid), .replay_ready(replay_ready),
        .replay_slot(replay_slot), .replay_row_block(replay_row_block),
        .replay_tag(8'h55), .replay_response_valid(replay_response_valid),
        .replay_response_ready(replay_response_ready), .replay_nonzero(),
        .replay_sign(replay_sign), .replay_column(replay_column),
        .replay_response_slot(), .replay_response_row_block(),
        .replay_response_tag(), .cache_valid(cache_valid),
        .cache_busy(), .cache_fault(cache_fault)
    );

    task fail;
        input [8*120-1:0] message;
        begin $display("FAIL: %0s", message); $finish; end
    endtask

    task issue;
        input [4:0] selected_operation;
        input from_candidates;
        input candidate_coefficients;
        begin
            @(negedge clk);
            operation = selected_operation;
            request_cache_from_candidates = from_candidates;
            request_candidate_coefficients = candidate_coefficients;
            cycle_valid = 1;
            while (!cycle_ready) @(negedge clk);
            cycle_commit = 1;
            @(posedge clk);
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            while (!response_valid) @(negedge clk);
            if (response_fault) fail("resource response fault");
            response_ready = 1;
            @(posedge clk);
            @(negedge clk);
            response_ready = 0;
        end
    endtask

    integer slot;
    integer row;
    reg [96*37-1:0] active_entries;
    initial begin
        candidate_values[0 +: DATA_W] = 27'sd111;
        candidate_values[DATA_W +: DATA_W] = -27'sd222;
        candidate_indices[0 +: 10] = 10'd5;
        candidate_indices[10 +: 10] = 10'd7;
        repeat (4) @(posedge clk);
        rst_n = 1;

        issue(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 1'b1, 1'b0);
        issue(`RECON_RESOURCE_OP_SUPPORT_UNION, 1'b1, 1'b1);
        issue(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 1'b0, 1'b0);
        if (!cache_refill_pending || cache_refill_support_count != 2)
            fail("refill transaction did not open");

        for (slot = 0; slot < 2; slot = slot + 1) begin
            while (!cache_refill_column_valid) @(negedge clk);
            if (cache_refill_column_slot != slot ||
                cache_refill_column != (slot == 0 ? 10'd5 : 10'd7))
                fail("proposal column order mismatch");
            cache_refill_column_ready = 1;
            @(posedge clk);
            @(negedge clk);
            cache_refill_column_ready = 0;
            for (row = 0; row < 2; row = row + 1) begin
                while (!fill_ready) @(negedge clk);
                fill_slot = slot;
                fill_row_block = row;
                fill_column = slot == 0 ? 10'd5 : 10'd7;
                fill_sign = 32'h1000_0000 + slot*16 + row;
                fill_valid = 1;
                @(posedge clk);
                @(negedge clk);
                fill_valid = 0;
            end
        end
        while (!cache_valid) @(negedge clk);
        issue(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 1'b1, 1'b0);
        if (cache_refill_pending || current_count != 2)
            fail("atomic finalize failed");
        active_entries = current_bank ? bank1_entries : bank0_entries;
        if (active_entries[DATA_W +: 10] != 10'd5 ||
            $signed(active_entries[0 +: DATA_W]) != 27'sd96 ||
            active_entries[37+DATA_W +: 10] != 10'd7 ||
            $signed(active_entries[37 +: DATA_W]) != -27'sd224)
            fail("support coefficient payload mismatch");

        replay_slot = 1;
        replay_row_block = 1;
        replay_valid = 1;
        while (!replay_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        replay_valid = 0;
        while (!replay_response_valid) @(negedge clk);
        if (replay_column != 10'd7 || replay_sign != 32'h1000_0011)
            fail("refilled Phi cache replay mismatch");
        replay_response_ready = 1;
        @(posedge clk);
        $display("M11 IHT SUPPORT REPLACE/PHI REFILL PASS");
        $finish;
    end
endmodule

`default_nettype wire
