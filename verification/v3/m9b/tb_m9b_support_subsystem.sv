`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m9b_support_subsystem;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer INDEX_W = 10;
    localparam integer CANDIDATE_MAX = 64;
    localparam integer WORK_MAX = 96;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg collector_reset = 0;
    reg collector_epoch_start = 0;
    reg [6:0] candidate_limit = 64;
    reg candidate_store_enable = 1;
    reg candidate_valid = 0;
    wire candidate_ready;
    reg signed [DATA_W-1:0] candidate_value = 0;
    reg [INDEX_W-1:0] candidate_index = 0;
    wire candidate_store_valid;
    reg candidate_store_ready = 1;
    wire [5:0] candidate_store_slot;
    wire [INDEX_W-1:0] candidate_store_column;
    reg gradient_valid = 0;
    reg [6:0] gradient_slot = 0;
    reg signed [DATA_W-1:0] gradient_value = 0;
    wire [6:0] candidate_count;
    wire [CANDIDATE_MAX*DATA_W-1:0] candidate_values;
    wire [CANDIDATE_MAX*INDEX_W-1:0] candidate_indices;
    wire [CANDIDATE_MAX*6-1:0] candidate_symbol_slots;
    wire [WORK_MAX*DATA_W-1:0] support_gradients;
    wire [WORK_MAX-1:0] support_gradient_valid;

    proxy_candidate_collector u_collector (
        .clk(clk), .rst_n(rst_n), .routine_start(collector_reset),
        .selection_epoch_start(collector_epoch_start),
        .candidate_limit(candidate_limit),
        .candidate_store_enable(candidate_store_enable),
        .candidate_valid(candidate_valid),
        .candidate_ready(candidate_ready), .candidate_value(candidate_value),
        .candidate_index(candidate_index),
        .candidate_store_valid(candidate_store_valid),
        .candidate_store_ready(candidate_store_ready),
        .candidate_store_slot(candidate_store_slot),
        .candidate_store_column(candidate_store_column),
        .gradient_valid(gradient_valid), .gradient_slot(gradient_slot),
        .gradient_value(gradient_value), .candidate_count(candidate_count),
        .candidate_values(candidate_values), .candidate_indices(candidate_indices),
        .candidate_symbol_slots(candidate_symbol_slots),
        .support_gradients(support_gradients),
        .support_gradient_valid(support_gradient_valid)
    );

    reg manager_start = 0;
    reg abort_transaction = 0;
    reg certificate_fail = 0;
    reg cycle_valid = 0;
    wire cycle_ready;
    reg cycle_commit = 0;
    reg [4:0] operation = 0;
    reg [2:0] request_tag = 0;
    reg [6:0] request_slot = 0;
    reg request_defer_activation = 0;
    reg request_scatter_active = 0;
    reg signed [DATA_W-1:0] scatter_coefficient = 0;
    wire response_valid;
    reg response_ready = 1;
    wire [4:0] response_operation;
    wire [2:0] response_tag;
    wire response_fault;
    wire [6:0] response_count;
    wire response_member;
    wire [6:0] response_slot;
    wire [INDEX_W-1:0] response_atom;
    wire signed [DATA_W-1:0] response_coefficient;
    wire transaction_open;
    wire current_bank;
    wire [6:0] current_count;
    wire [6:0] proposed_count;
    wire [6:0] view_count;
    wire proposal_view_active;
    wire [31:0] rollback_count;
    wire [31:0] rollback_cycle_count;
    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank0_entries;
    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank1_entries;
    wire [WORK_MAX-1:0] bank0_slot_valid;
    wire [WORK_MAX-1:0] bank1_slot_valid;
    wire [WORK_MAX*INDEX_W-1:0] active_support_indices;
    wire [WORK_MAX*DATA_W-1:0] active_support_coefficients;
    wire manager_remap_event_valid;
    wire manager_remap_event_fault;
    wire [6:0] manager_remap_dropped_count;
    wire [WORK_MAX*INDEX_W-1:0] manager_remap_dropped_indices;
    wire [WORK_MAX*DATA_W-1:0] manager_remap_dropped_coefficients;

    support_state_manager u_manager (
        .clk(clk), .rst_n(rst_n), .routine_start(manager_start),
        .abort_transaction(abort_transaction), .certificate_fail(certificate_fail),
        .cycle_valid(cycle_valid), .cycle_ready(cycle_ready), .cycle_commit(cycle_commit),
        .operation(operation), .request_tag(request_tag), .request_slot(request_slot),
        .request_cache_from_candidates(1'b1),
        .request_candidate_coefficients(1'b0),
        .request_zero_candidate_coefficient(1'b0),
        .request_defer_activation(request_defer_activation),
        .request_sort_by_index(1'b0),
        .request_scatter_active(request_scatter_active),
        .scatter_coefficient(scatter_coefficient), .candidate_count(candidate_count),
        .candidate_values(candidate_values), .candidate_indices(candidate_indices),
        .candidate_symbol_slots(candidate_symbol_slots),
        .membership_query_atom(10'd0), .membership_query_member(),
        .membership_query_slot(),
        .append_gradient_valid(), .append_gradient_slot(),
        .append_gradient_value(),
        .response_valid(response_valid), .response_ready(response_ready),
        .response_operation(response_operation), .response_tag(response_tag),
        .response_fault(response_fault), .response_count(response_count),
        .response_member(response_member), .response_slot(response_slot),
        .response_atom(response_atom), .response_coefficient(response_coefficient),
        .transaction_open(transaction_open), .current_bank(current_bank),
        .current_count(current_count), .proposed_count(proposed_count),
        .view_count(view_count), .proposal_view_active(proposal_view_active),
        .rollback_count(rollback_count), .rollback_cycle_count(rollback_cycle_count),
        .bank0_entries(bank0_entries), .bank1_entries(bank1_entries),
        .bank0_slot_valid(bank0_slot_valid), .bank1_slot_valid(bank1_slot_valid),
        .active_support_bitmap(),
        .active_support_indices(active_support_indices),
        .active_support_coefficients(active_support_coefficients),
        .remap_event_valid(manager_remap_event_valid),
        .remap_event_fault(manager_remap_event_fault),
        .remap_dropped_count(manager_remap_dropped_count),
        .remap_dropped_indices(manager_remap_dropped_indices),
        .remap_dropped_coefficients(manager_remap_dropped_coefficients),
        .cache_prepare_valid(), .cache_prepare_ready(1'b1),
        .cache_prepare_from_candidates(),
        .cache_prepare_support_count(), .cache_prepare_preserve_count(),
        .cache_promote_valid(), .cache_promote_ready(1'b1),
        .cache_promote_candidate_slot(), .cache_promote_support_slot(),
        .cache_valid(1'b1), .cache_fault(1'b0), .cache_invalidate(),
        .cache_refill_pending(), .cache_refill_support_count(),
        .cache_refill_column_valid(), .cache_refill_column_ready(1'b0),
        .cache_refill_column_slot(), .cache_refill_column()
    );

    reg remap_start_valid = 0;
    wire remap_start_ready;
    reg [6:0] remap_current_count = 0;
    reg [WORK_MAX*INDEX_W-1:0] remap_current_indices = 0;
    reg [WORK_MAX*DATA_W-1:0] remap_current_coefficients = 0;
    reg [6:0] remap_proposed_count = 0;
    reg [WORK_MAX*INDEX_W-1:0] remap_proposed_indices = 0;
    wire remap_done_valid;
    reg remap_done_ready = 1;
    wire remap_fault;
    wire remap_coefficient_valid;
    wire [6:0] remap_coefficient_slot;
    wire signed [DATA_W-1:0] remap_coefficient;
    reg [WORK_MAX*DATA_W-1:0] remapped_coefficients = 0;
    wire [6:0] dropped_count;
    wire [WORK_MAX*INDEX_W-1:0] dropped_indices;
    wire [WORK_MAX*DATA_W-1:0] dropped_coefficients;
    wire remap_query_valid;
    wire remap_query_current_bank;
    wire [INDEX_W-1:0] remap_query_atom;
    reg remap_query_member;
    reg [6:0] remap_query_slot;
    wire remap_read_current_bank;
    wire [6:0] remap_read_slot;
    wire [INDEX_W-1:0] remap_read_atom = remap_read_current_bank ?
        remap_current_indices[remap_read_slot*INDEX_W +: INDEX_W] :
        remap_proposed_indices[remap_read_slot*INDEX_W +: INDEX_W];
    wire remap_coefficient_read_enable;
    wire remap_coefficient_read_current_bank;
    wire [6:0] remap_coefficient_read_slot;
    reg remap_coefficient_read_valid = 0;
    reg signed [DATA_W-1:0] remap_coefficient_read_data = 0;

    always @(posedge clk) begin
        remap_coefficient_read_valid <= remap_coefficient_read_enable;
        if (remap_coefficient_read_enable)
            remap_coefficient_read_data <= remap_current_coefficients[
                remap_coefficient_read_slot*DATA_W +: DATA_W];
    end

    integer remap_query_index;
    always @* begin
        remap_query_member = 0;
        remap_query_slot = 0;
        for (remap_query_index = 0; remap_query_index < WORK_MAX;
             remap_query_index = remap_query_index + 1) begin
            if (remap_query_current_bank &&
                (remap_query_index < remap_current_count) &&
                (remap_current_indices[remap_query_index*INDEX_W +: INDEX_W] ==
                 remap_query_atom)) begin
                remap_query_member = 1;
                remap_query_slot = remap_query_index[6:0];
            end
            if (!remap_query_current_bank &&
                (remap_query_index < remap_proposed_count) &&
                (remap_proposed_indices[remap_query_index*INDEX_W +: INDEX_W] ==
                 remap_query_atom)) begin
                remap_query_member = 1;
                remap_query_slot = remap_query_index[6:0];
            end
        end
    end

    support_coefficient_remapper u_remapper (
        .clk(clk), .rst_n(rst_n), .cancel(1'b0),
        .start_valid(remap_start_valid),
        .start_ready(remap_start_ready), .current_count(remap_current_count),
        .proposed_count(remap_proposed_count),
        .read_current_bank(remap_read_current_bank), .read_slot(remap_read_slot),
        .read_atom(remap_read_atom),
        .coefficient_read_enable(remap_coefficient_read_enable),
        .coefficient_read_current_bank(remap_coefficient_read_current_bank),
        .coefficient_read_slot(remap_coefficient_read_slot),
        .coefficient_read_valid(remap_coefficient_read_valid),
        .coefficient_read_data(remap_coefficient_read_data),
        .query_valid(remap_query_valid),
        .query_current_bank(remap_query_current_bank), .query_atom(remap_query_atom),
        .query_member(remap_query_member), .query_slot(remap_query_slot),
        .done_valid(remap_done_valid), .done_ready(remap_done_ready), .fault(remap_fault),
        .remap_coefficient_valid(remap_coefficient_valid),
        .remap_coefficient_slot(remap_coefficient_slot),
        .remap_coefficient(remap_coefficient), .dropped_count(dropped_count),
        .dropped_indices(dropped_indices), .dropped_coefficients(dropped_coefficients)
    );

    always @(posedge clk) begin
        if (remap_coefficient_valid)
            remapped_coefficients[remap_coefficient_slot*DATA_W +: DATA_W] <=
                remap_coefficient;
    end

    integer store_events = 0;
    always @(posedge clk)
        if (candidate_store_valid && candidate_store_ready)
            store_events <= store_events + 1;

    task fail;
        input [8*128-1:0] message;
        begin $display("FAIL: %0s", message); $finish; end
    endtask

    task reset_collector;
        begin
            @(negedge clk); collector_reset = 1;
            @(posedge clk); @(negedge clk); collector_reset = 0;
        end
    endtask

    task push_candidate;
        input [INDEX_W-1:0] atom;
        input signed [DATA_W-1:0] value;
        begin
            @(negedge clk);
            candidate_index = atom;
            candidate_value = value;
            candidate_valid = 1;
            while (!candidate_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            candidate_valid = 0;
        end
    endtask

    task issue_support;
        input [4:0] op;
        input [6:0] slot;
        input signed [DATA_W-1:0] coefficient;
        input expect_fault;
        integer guard;
        begin
            while (response_valid) @(negedge clk);
            @(negedge clk);
            operation = op;
            request_slot = slot;
            scatter_coefficient = coefficient;
            request_tag = request_tag + 1'b1;
            cycle_valid = 1;
            cycle_commit = 1;
            guard = 0;
            while (!cycle_ready) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 300) fail("support issue timeout");
            end
            @(posedge clk);
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            guard = 0;
            while (!response_valid) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 5000) fail("support response timeout");
            end
            if (response_operation != op || response_fault != expect_fault)
                fail("support response mismatch");
            @(posedge clk);
        end
    endtask

    task check_current_atom;
        input [6:0] slot;
        input [INDEX_W-1:0] expected_atom;
        begin
            issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, slot, 0, 0);
            if (response_atom != expected_atom) fail("gather atom mismatch");
        end
    endtask

    task issue_stalled_commit;
        reg old_bank;
        reg [4:0] held_operation;
        reg [2:0] held_tag;
        reg held_fault;
        integer guard;
        begin
            while (response_valid) @(negedge clk);
            old_bank = current_bank;
            response_ready = 0;
            @(negedge clk);
            operation = `RECON_RESOURCE_OP_SUPPORT_COMMIT;
            request_tag = request_tag + 1'b1;
            cycle_valid = 1;
            cycle_commit = 1;
            while (!cycle_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            guard = 0;
            while (!response_valid) begin
                if (current_bank != old_bank)
                    fail("committed bank changed before commit response");
                @(negedge clk);
                guard = guard + 1;
                if (guard > 300) fail("stalled commit response timeout");
            end
            if (!manager_remap_event_valid || manager_remap_event_fault)
                fail("production remap success event mismatch");
            if (current_bank == old_bank)
                fail("committed bank did not swap atomically");
            held_operation = response_operation;
            held_tag = response_tag;
            held_fault = response_fault;
            repeat (3) begin
                @(posedge clk);
                if (!response_valid || response_operation != held_operation ||
                    response_tag != held_tag || response_fault != held_fault)
                    fail("commit response changed under stall");
            end
            response_ready = 1;
            @(posedge clk);
        end
    endtask

    task abort_commit_during_remap;
        reg old_bank;
        reg [31:0] old_rollback_count;
        integer guard;
        begin
            while (response_valid) @(negedge clk);
            old_bank = current_bank;
            old_rollback_count = rollback_count;
            @(negedge clk);
            operation = `RECON_RESOURCE_OP_SUPPORT_COMMIT;
            request_tag = request_tag + 1'b1;
            cycle_valid = 1;
            cycle_commit = 1;
            while (!cycle_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            guard = 0;
            while (u_manager.state != 4'd8) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 20) fail("remap wait state timeout");
            end
            certificate_fail = 1;
            @(posedge clk);
            @(negedge clk);
            certificate_fail = 0;
            if (!response_valid || !response_fault ||
                response_operation != `RECON_RESOURCE_OP_SUPPORT_COMMIT)
                fail("remap abort response mismatch");
            if (current_bank != old_bank || transaction_open ||
                rollback_count != old_rollback_count + 1'b1)
                fail("remap abort rollback mismatch");
            @(posedge clk);
        end
    endtask

    integer test_index;
    integer rollback_base;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;

        candidate_store_ready = 0;
        candidate_store_enable = 0;
        @(negedge clk);
        candidate_limit = 7'd64;
        candidate_index = 10'd23;
        candidate_value = -27'sd321;
        candidate_valid = 1;
        collector_epoch_start = 1;
        if (!candidate_ready) fail("collector epoch-start candidate stalled");
        @(posedge clk);
        @(negedge clk);
        collector_epoch_start = 0;
        candidate_valid = 0;
        if (candidate_count != 1 ||
            candidate_indices[0 +: INDEX_W] != 10'd23 ||
            $signed(candidate_values[0 +: DATA_W]) != -27'sd321)
            fail("collector epoch-start candidate was not retained");
        reset_collector();
        push_candidate(10'd7, 27'sd123);
        if (candidate_store_valid || candidate_count != 1)
            fail("cacheless candidate collection mismatch");
        candidate_store_enable = 1;
        candidate_store_ready = 1;
        reset_collector();
        for (test_index = 0; test_index < 64; test_index = test_index + 1)
            push_candidate(test_index[9:0], 27'sd10000 - test_index);
        push_candidate(10'd7, 27'sd50000);
        if (candidate_count != 64) fail("collector 2K count mismatch");
        if (candidate_indices[0 +: INDEX_W] != 0 ||
            candidate_indices[63*INDEX_W +: INDEX_W] != 63)
            fail("collector rank order mismatch");
        if (store_events != 64) fail("collector duplicate emitted store token");

        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        for (test_index = 0; test_index < 32; test_index = test_index + 1)
            issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, test_index[6:0], 0, 0);
        if (proposed_count != 32) fail("K32 proposed count mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 7, 0, 0);
        if (proposed_count != 32) fail("duplicate atom changed count");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (current_count != 32) fail("K32 commit count mismatch");
        check_current_atom(0, 0);
        check_current_atom(31, 31);

        issue_support(`RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP, 7, 0, 0);
        if (!response_member || response_slot != 7) fail("membership mismatch");

        reset_collector();
        for (test_index = 0; test_index < 64; test_index = test_index + 1)
            push_candidate((100 + test_index), 27'sd20000 - test_index);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_UNION, 0, 0, 0);
        if (proposed_count != 96) fail("3K union count mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (current_count != 96) fail("3K commit count mismatch");
        check_current_atom(32, 100);
        check_current_atom(95, 163);

        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, -27'sd1248, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 0, 0);
        if ($signed(response_coefficient) != -27'sd1248)
            fail("scatter/gather coefficient mismatch");

        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        for (test_index = 0; test_index < 32; test_index = test_index + 1)
            issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, test_index[6:0], 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (current_count != 32) fail("prune K32 count mismatch");

        rollback_base = rollback_count;
        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 0, 0);
        if (current_count != 32 || rollback_count != rollback_base + 1 ||
            rollback_cycle_count != rollback_count)
            fail("explicit rollback mismatch");

        repeat (3) begin
            issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
            issue_support(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 0, 0);
        end
        if (rollback_count != rollback_base + 4)
            fail("rollback storm counter mismatch");

        issue_support(`RECON_RESOURCE_OP_SUPPORT_UNION, 0, 0, 0);
        @(negedge clk); abort_transaction = 1;
        @(posedge clk); @(negedge clk); abort_transaction = 0;
        repeat (3) @(posedge clk);
        if (transaction_open || current_count != 32 || rollback_count != rollback_base + 5)
            fail("mid-transaction abort mismatch");

        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        @(negedge clk); certificate_fail = 1;
        @(posedge clk); @(negedge clk); certificate_fail = 0;
        if (transaction_open || current_count != 32 || rollback_count != rollback_base + 6)
            fail("certificate rollback mismatch");

        remap_current_count = 2;
        remap_current_indices[0*INDEX_W +: INDEX_W] = 10'd4;
        remap_current_indices[1*INDEX_W +: INDEX_W] = 10'd9;
        remap_current_coefficients[0*DATA_W +: DATA_W] = 27'sd111;
        remap_current_coefficients[1*DATA_W +: DATA_W] = -27'sd222;
        remap_proposed_count = 2;
        remap_proposed_indices[0*INDEX_W +: INDEX_W] = 10'd9;
        remap_proposed_indices[1*INDEX_W +: INDEX_W] = 10'd12;
        remapped_coefficients = 0;
        @(negedge clk); remap_start_valid = 1;
        while (!remap_start_ready) @(negedge clk);
        @(posedge clk); @(negedge clk); remap_start_valid = 0;
        while (!remap_done_valid) @(negedge clk);
        if (remap_fault ||
            $signed(remapped_coefficients[0*DATA_W +: DATA_W]) != -27'sd222 ||
            $signed(remapped_coefficients[1*DATA_W +: DATA_W]) != 0 ||
            dropped_count != 1 || dropped_indices[0 +: INDEX_W] != 4 ||
            $signed(dropped_coefficients[0 +: DATA_W]) != 27'sd111)
            fail("coefficient remap mismatch");

        reset_collector();
        push_candidate(10'd4, 27'sd200);
        push_candidate(10'd9, 27'sd100);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 1, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, 27'sd128, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 1, -27'sd224, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);

        reset_collector();
        push_candidate(10'd9, 27'sd200);
        push_candidate(10'd12, 27'sd100);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 1, 0, 0);
        issue_stalled_commit();
        if (manager_remap_dropped_count != 1 ||
            manager_remap_dropped_indices[0 +: INDEX_W] != 10'd4 ||
            $signed(manager_remap_dropped_coefficients[0 +: DATA_W]) != 27'sd128)
            fail("production dropped-atom telemetry mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 0, 0);
        if (response_atom != 10'd9 ||
            $signed(response_coefficient) != -27'sd224)
            fail("production reordered coefficient mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 1, 0, 0);
        if (response_atom != 10'd12 || $signed(response_coefficient) != 0)
            fail("production new coefficient was not zero");

        reset_collector();
        push_candidate(10'd20, 27'sd200);
        push_candidate(10'd21, 27'sd100);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_UNION, 0, 0, 0);
        request_defer_activation = 1;
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (!proposal_view_active || current_count != 2 || view_count != 4 ||
            active_support_indices[0*INDEX_W +: INDEX_W] != 10'd9 ||
            active_support_indices[1*INDEX_W +: INDEX_W] != 10'd12 ||
            active_support_indices[2*INDEX_W +: INDEX_W] != 10'd20 ||
            active_support_indices[3*INDEX_W +: INDEX_W] != 10'd21)
            fail("deferred proposal view mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 2, 27'sd320, 0);
        if ($signed(active_support_coefficients[2*DATA_W +: DATA_W]) != 27'sd320)
            fail("proposal coefficient scatter mismatch");

        reset_collector();
        push_candidate(10'd12, 27'sd200);
        push_candidate(10'd20, 27'sd100);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 1, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 0, -27'sd448, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_SCATTER, 1, 27'sd544, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (!proposal_view_active || current_count != 2 || view_count != 2 ||
            active_support_indices[0*INDEX_W +: INDEX_W] != 10'd12 ||
            active_support_indices[1*INDEX_W +: INDEX_W] != 10'd20 ||
            $signed(active_support_coefficients[0*DATA_W +: DATA_W]) != -27'sd448 ||
            $signed(active_support_coefficients[1*DATA_W +: DATA_W]) != 27'sd544)
            fail("proposal prune view mismatch");
        request_defer_activation = 0;
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (proposal_view_active || transaction_open || current_count != 2)
            fail("deferred proposal accept mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 0, 0);
        if (response_atom != 10'd12 || $signed(response_coefficient) != -27'sd448)
            fail("accepted proposal slot zero mismatch");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 1, 0, 0);
        if (response_atom != 10'd20 || $signed(response_coefficient) != 27'sd544)
            fail("accepted proposal slot one mismatch");

        reset_collector();
        push_candidate(10'd30, 27'sd200);
        push_candidate(10'd31, 27'sd100);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 1, 0, 0);
        request_defer_activation = 1;
        issue_support(`RECON_RESOURCE_OP_SUPPORT_COMMIT, 0, 0, 0);
        if (!proposal_view_active || view_count != 2)
            fail("rollback proposal view missing");
        issue_support(`RECON_RESOURCE_OP_SUPPORT_ROLLBACK, 0, 0, 0);
        request_defer_activation = 0;
        if (proposal_view_active || transaction_open || current_count != 2 ||
            active_support_indices[0*INDEX_W +: INDEX_W] != 10'd12 ||
            active_support_indices[1*INDEX_W +: INDEX_W] != 10'd20)
            fail("proposal rollback changed accepted support");

        issue_support(`RECON_RESOURCE_OP_SUPPORT_CLEAR, 0, 0, 0);
        issue_support(`RECON_RESOURCE_OP_SUPPORT_APPEND, 0, 0, 0);
        abort_commit_during_remap();
        issue_support(`RECON_RESOURCE_OP_SUPPORT_GATHER, 0, 0, 0);
        if (response_atom != 10'd12 ||
            $signed(response_coefficient) != -27'sd448)
            fail("remap abort changed committed coefficient");

        gradient_slot = 95;
        gradient_value = -27'sd77;
        gradient_valid = 1;
        @(posedge clk); @(negedge clk); gradient_valid = 0;
        if (!support_gradient_valid[95] ||
            $signed(support_gradients[95*DATA_W +: DATA_W]) != -27'sd77)
            fail("active support gradient capture mismatch");

        $display("M9B SUPPORT SUBSYSTEM PASS");
        $finish;
    end

    initial begin
        #2000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
