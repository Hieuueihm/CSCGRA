`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_topk_selection_unit;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer INDEX_W = 10;
    localparam integer K_MAX = `RECON_K_MAX;
    localparam integer TAG_W = 3;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg selection_epoch_start = 0;
    reg [5:0] selection_k = 0;
    reg [6:0] candidate_limit = 0;
    reg cycle_valid = 0;
    wire cycle_ready;
    reg cycle_commit = 0;
    reg [4:0] operation = 0;
    reg [TAG_W-1:0] request_tag = 0;
    reg signed [DATA_W-1:0] candidate_score = 0;
    reg [INDEX_W-1:0] candidate_index = 0;
    wire response_valid;
    reg response_ready = 1;
    wire [4:0] response_operation;
    wire [TAG_W-1:0] response_tag;
    wire response_fault;
    wire [5:0] response_count;
    wire [K_MAX*DATA_W-1:0] result_scores;
    wire [K_MAX*INDEX_W-1:0] result_indices;
    reg candidate_symbol_valid = 0;
    reg [127:0] candidate_symbol_payload = 0;
    wire candidate_symbol_ready;

    integer cycle_count = 0;
    integer golden_candidate_count;
    integer golden_expected_count;
    reg signed [DATA_W-1:0] golden_candidate_score [0:63];
    reg [INDEX_W-1:0] golden_candidate_index [0:63];
    reg signed [DATA_W-1:0] golden_expected_score [0:K_MAX-1];
    reg [INDEX_W-1:0] golden_expected_index [0:K_MAX-1];
    integer accepted_cycle [0:63];
    integer accepted_count = 0;
    integer response_seen = 0;
    integer test_index;
    integer send_index;
    integer random_seed = 32'h4d39_a026;
    reg monitor_push_responses = 0;
    reg stall_active = 0;
    reg [4:0] stalled_operation;
    reg [TAG_W-1:0] stalled_tag;
    reg stalled_fault;
    reg [5:0] stalled_count;
    reg [K_MAX*DATA_W-1:0] stalled_scores;
    reg [K_MAX*INDEX_W-1:0] stalled_indices;

    `include "m9a_golden.vh"

    topk_selection_unit dut (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .selection_epoch_start(selection_epoch_start),
        .selection_k(selection_k), .candidate_limit(candidate_limit),
        .candidate_store_enable(1'b0), .cycle_valid(cycle_valid),
        .cycle_ready(cycle_ready), .cycle_commit(cycle_commit),
        .operation(operation), .request_tag(request_tag),
        .candidate_score(candidate_score), .candidate_index(candidate_index),
        .candidate_exclude(1'b0),
        .response_valid(response_valid), .response_ready(response_ready),
        .response_operation(response_operation), .response_tag(response_tag),
        .response_fault(response_fault), .response_count(response_count),
        .result_scores(result_scores), .result_indices(result_indices),
        .retained_candidate_count(), .retained_candidate_values(),
        .retained_candidate_indices(), .retained_candidate_symbol_slots(),
        .retained_candidate_read_slot(7'd0),
        .retained_candidate_read_valid(), .retained_candidate_read_value(),
        .retained_candidate_read_index(),
        .retained_candidate_read_symbol_slot(),
        .retained_candidate_read_sorted_slot(),
        .candidate_store_valid(), .candidate_store_ready(1'b1),
        .candidate_store_slot(), .candidate_store_column(),
        .candidate_symbol_valid(candidate_symbol_valid),
        .candidate_symbol_payload(candidate_symbol_payload),
        .candidate_symbol_ready(candidate_symbol_ready)
    );

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (monitor_push_responses && response_valid && response_ready) begin
            if (response_fault) fail("push response fault");
            if (response_operation != `RECON_RESOURCE_OP_TOPK_PUSH)
                fail("push response opcode mismatch");
            if (response_tag != response_seen[TAG_W-1:0])
                fail("push response tag order mismatch");
            response_seen = response_seen + 1;
        end
    end

    always @(negedge clk) begin
        if (response_valid && !response_ready) begin
            if (!stall_active) begin
                stall_active = 1;
                stalled_operation = response_operation;
                stalled_tag = response_tag;
                stalled_fault = response_fault;
                stalled_count = response_count;
                stalled_scores = result_scores;
                stalled_indices = result_indices;
            end else if (response_operation != stalled_operation ||
                         response_tag != stalled_tag ||
                         response_fault != stalled_fault ||
                         response_count != stalled_count ||
                         result_scores != stalled_scores ||
                         result_indices != stalled_indices)
                fail("response payload changed under backpressure");
        end else begin
            stall_active = 0;
        end
    end

    task fail;
        input [8*96-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task start_selection;
        input [5:0] k_value;
        begin
            @(negedge clk);
            response_ready = 1;
            cycle_valid = 0;
            cycle_commit = 0;
            selection_k = k_value;
            candidate_limit = {1'b0, k_value};
            routine_start = 1;
            @(posedge clk);
            @(negedge clk);
            routine_start = 0;
        end
    endtask

    task push_and_wait;
        input signed [DATA_W-1:0] score;
        input [INDEX_W-1:0] index;
        input [TAG_W-1:0] tag;
        input expected_fault;
        integer accept_at;
        begin
            @(negedge clk);
            operation = `RECON_RESOURCE_OP_TOPK_PUSH;
            candidate_score = score;
            candidate_index = index;
            request_tag = tag;
            cycle_valid = 1;
            cycle_commit = 1;
            if (!cycle_ready) fail("single push unexpectedly stalled");
            @(posedge clk); #1;
            accept_at = cycle_count;
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            @(posedge clk); #1;
            if (response_valid) fail("TOPK_PUSH response arrived before two cycles");
            @(posedge clk); #1;
            if (!response_valid || cycle_count - accept_at != 2)
                fail("TOPK_PUSH latency is not two cycles");
            if ((response_fault != expected_fault) || response_tag != tag)
                fail("single push response mismatch");
            @(posedge clk);
        end
    endtask

    task check_final_golden;
        begin
            if (response_count != golden_expected_count)
                fail("selected count mismatch");
            for (test_index = 0; test_index < golden_expected_count; test_index = test_index + 1) begin
                if (result_indices[test_index*INDEX_W +: INDEX_W] !=
                    golden_expected_index[test_index]) begin
                    $display("INDEX MISMATCH slot=%0d actual=%0d expected=%0d score=%0d expected_score=%0d",
                        test_index, result_indices[test_index*INDEX_W +: INDEX_W],
                        golden_expected_index[test_index],
                        $signed(result_scores[test_index*DATA_W +: DATA_W]),
                        golden_expected_score[test_index]);
                    fail("golden index mismatch");
                end
                if ($signed(result_scores[test_index*DATA_W +: DATA_W]) !=
                    golden_expected_score[test_index]) begin
                    $display("SCORE MISMATCH slot=%0d index=%0d actual=%0d expected=%0d",
                        test_index, result_indices[test_index*INDEX_W +: INDEX_W],
                        $signed(result_scores[test_index*DATA_W +: DATA_W]),
                        golden_expected_score[test_index]);
                    fail("golden score mismatch");
                end
            end
        end
    endtask

    task stream_no_stall;
        begin
            accepted_count = 0;
            response_seen = 0;
            monitor_push_responses = 1;
            response_ready = 1;
            operation = `RECON_RESOURCE_OP_TOPK_PUSH;
            @(negedge clk);
            cycle_valid = 1;
            cycle_commit = 1;
            for (send_index = 0; send_index < golden_candidate_count; send_index = send_index + 1) begin
                candidate_score = golden_candidate_score[send_index];
                candidate_index = golden_candidate_index[send_index];
                request_tag = send_index[TAG_W-1:0];
                if (!cycle_ready) fail("TOPK_PUSH II exceeded one without backpressure");
                @(posedge clk); #1;
                accepted_cycle[send_index] = cycle_count;
                accepted_count = accepted_count + 1;
            end
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            while (response_seen != golden_candidate_count) @(negedge clk);
            monitor_push_responses = 0;
            for (test_index = 1; test_index < golden_candidate_count; test_index = test_index + 1)
                if (accepted_cycle[test_index] - accepted_cycle[test_index-1] != 1)
                    fail("accepted push cadence is not II=1");
            check_final_golden();
        end
    endtask

    task stream_random_stall;
        reg accept_now;
        begin
            accepted_count = 0;
            response_seen = 0;
            monitor_push_responses = 1;
            operation = `RECON_RESOURCE_OP_TOPK_PUSH;
            @(negedge clk);
            cycle_valid = 1;
            cycle_commit = 1;
            send_index = 0;
            while (send_index < golden_candidate_count) begin
                response_ready = (($random(random_seed) & 3) != 0);
                candidate_score = golden_candidate_score[send_index];
                candidate_index = golden_candidate_index[send_index];
                request_tag = send_index[TAG_W-1:0];
                #1;
                accept_now = cycle_ready;
                @(posedge clk); #1;
                if (accept_now) begin
                    accepted_count = accepted_count + 1;
                    send_index = send_index + 1;
                end
            end
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            while (response_seen != golden_candidate_count) begin
                response_ready = (($random(random_seed) & 3) != 0);
                @(negedge clk);
            end
            response_ready = 1;
            monitor_push_responses = 0;
            if (accepted_count != golden_candidate_count)
                fail("random stall lost accepted pushes");
            check_final_golden();
        end
    endtask

    task commit_with_stall;
        integer accept_at;
        integer hold_index;
        begin
            while (response_valid) @(negedge clk);
            @(negedge clk);
            response_ready = 0;
            operation = `RECON_RESOURCE_OP_TOPK_COMMIT;
            request_tag = 3'd6;
            cycle_valid = 1;
            cycle_commit = 1;
            if (!cycle_ready) fail("TOPK_COMMIT unexpectedly stalled at issue");
            @(posedge clk); #1;
            accept_at = cycle_count;
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            @(posedge clk); #1;
            if (!response_valid || cycle_count - accept_at != 1)
                fail("TOPK_COMMIT latency is not one cycle");
            if (response_fault || response_operation != `RECON_RESOURCE_OP_TOPK_COMMIT ||
                response_tag != 3'd6 || response_count != golden_expected_count)
                fail("TOPK_COMMIT response mismatch");
            for (hold_index = 0; hold_index < 4; hold_index = hold_index + 1)
                @(posedge clk);
            response_ready = 1;
            @(posedge clk);
        end
    endtask

    initial begin
        load_m9a_golden();
        repeat (4) @(posedge clk);
        rst_n = 1;

        if (candidate_symbol_ready) fail("N3 candidate-symbol seam falsely implemented");
        candidate_symbol_valid = 1;
        candidate_symbol_payload = 128'h1;
        #1;
        if (candidate_symbol_ready) fail("N3 candidate-symbol payload accepted");
        candidate_symbol_valid = 0;
        candidate_symbol_payload = 0;

        start_selection(6'd4);
        push_and_wait(-27'sd10, 10'd5, 3'd0, 0);
        push_and_wait(27'sd10, 10'd3, 3'd1, 0);
        push_and_wait(27'sd7, 10'd1, 3'd2, 0);
        push_and_wait(-27'sd12, 10'd9, 3'd3, 0);
        push_and_wait(27'sd12, 10'd2, 3'd4, 0);
        push_and_wait(27'sd13, 10'd3, 3'd5, 0);
        if (response_count != 4 ||
            result_indices[0*INDEX_W +: INDEX_W] != 10'd2 ||
            result_indices[1*INDEX_W +: INDEX_W] != 10'd9 ||
            result_indices[2*INDEX_W +: INDEX_W] != 10'd3 ||
            $signed(result_scores[2*DATA_W +: DATA_W]) != 27'sd10 ||
            result_indices[3*INDEX_W +: INDEX_W] != 10'd5)
            fail("tie or duplicate replacement order mismatch");

        @(negedge clk);
        selection_k = 6'd4;
        operation = `RECON_RESOURCE_OP_TOPK_PUSH;
        candidate_score = -27'sd99;
        candidate_index = 10'd17;
        request_tag = 3'd7;
        cycle_valid = 1;
        cycle_commit = 1;
        selection_epoch_start = 1;
        if (!cycle_ready) fail("epoch-start first push stalled");
        @(posedge clk);
        @(negedge clk);
        selection_epoch_start = 0;
        cycle_valid = 0;
        cycle_commit = 0;
        repeat (2) @(posedge clk);
        #1;
        if (!response_valid || response_fault || response_count != 1 ||
            result_indices[0 +: INDEX_W] != 10'd17 ||
            $signed(result_scores[0 +: DATA_W]) != -27'sd99)
            fail("epoch-start first candidate was not retained");
        @(posedge clk);

        start_selection(6'd32);
        stream_no_stall();
        commit_with_stall();

        start_selection(6'd32);
        stream_random_stall();

        @(negedge clk);
        operation = `RECON_RESOURCE_OP_TOPK_PUSH;
        candidate_score = 27'sd12345;
        candidate_index = 10'd1000;
        cycle_valid = 1;
        cycle_commit = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        cycle_valid = 0;
        if (response_valid) fail("non-committed request produced response");
        check_final_golden();

        start_selection(6'd0);
        push_and_wait(27'sd1, 10'd1, 3'd1, 1);
        if (!response_fault) fail("invalid K did not fault");

        $display("M9A TOPK SELECTION PASS");
        $finish;
    end

    initial begin
        #500000;
        fail("timeout");
    end
endmodule

`default_nettype wire
