`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "m5_golden.vh"

module tb_m5_resource_router;
    localparam integer ACC_W = `RECON_ACC_W;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer LANES = `RECON_SHARED_VECTOR_LANES;
    localparam signed [DATA_W-1:0] EXPECTED_BROADCAST = `M5_VECTOR_DOT;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg cycle_valid = 0;
    reg cycle_commit = 0;
    reg [35:0] resource_ctx = 0;
    reg [15:0] reduction_lane_valid = 16'hffff;
    reg [16*ACC_W-1:0] cluster0_lane_data = 0;
    reg [16*ACC_W-1:0] cluster1_lane_data = 0;
    reg [159:0] cluster0_lane_index = 0;
    reg [159:0] cluster1_lane_index = 0;
    reg [LANES-1:0] vector_lane_valid = {LANES{1'b1}};
    reg [LANES*DATA_W-1:0] vector_a = `M5_VECTOR_A;
    reg [LANES*DATA_W-1:0] vector_b = `M5_VECTOR_B;
    reg vector_result_ready = 1;

    wire vector_result_valid;
    wire [LANES-1:0] vector_result_lane_valid;
    wire [LANES*DATA_W-1:0] vector_result_data;
    wire scalar0_valid;
    wire signed [ACC_W-1:0] scalar0_data;
    wire scalar1_valid;
    wire signed [ACC_W-1:0] scalar1_data;
    wire scalar_broadcast_valid;
    wire signed [DATA_W-1:0] scalar_broadcast_data;
    wire event_valid;
    wire [3:0] event_id;
    wire [9:0] result_index;
    wire divide_by_zero_event;
    wire saturation_event;
    wire fault_valid;
    wire [7:0] fault_code;
    wire [15:0] fault_detail;
    wire resource_in_ready;
    wire resource_out_ready;
    wire resource_contract_error;

    m5_arithmetic_ooc dut (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .resource_ctx(resource_ctx), .reduction_lane_valid(reduction_lane_valid),
        .cluster0_lane_data(cluster0_lane_data),
        .cluster1_lane_data(cluster1_lane_data),
        .cluster0_lane_index(cluster0_lane_index),
        .cluster1_lane_index(cluster1_lane_index),
        .vector_lane_valid(vector_lane_valid), .vector_a(vector_a),
        .vector_b(vector_b), .vector_result_ready(vector_result_ready),
        .vector_result_valid(vector_result_valid),
        .vector_result_lane_valid(vector_result_lane_valid),
        .vector_result_data(vector_result_data), .scalar0_valid(scalar0_valid),
        .scalar0_data(scalar0_data), .scalar1_valid(scalar1_valid),
        .scalar1_data(scalar1_data),
        .scalar_broadcast_valid(scalar_broadcast_valid),
        .scalar_broadcast_data(scalar_broadcast_data),
        .event_valid(event_valid), .event_id(event_id), .result_index(result_index),
        .divide_by_zero_event(divide_by_zero_event),
        .saturation_event(saturation_event), .fault_valid(fault_valid),
        .fault_code(fault_code), .fault_detail(fault_detail),
        .resource_in_ready(resource_in_ready),
        .resource_out_ready(resource_out_ready),
        .resource_contract_error(resource_contract_error)
    );

    function [35:0] make_context;
        input [4:0] operation;
        input [2:0] input_select;
        input [2:0] output_select;
        input [3:0] lane_mask;
        input clear_before;
        input accumulate;
        input commit_after;
        input wait_ready;
        input wait_result;
        input [3:0] event_number;
        reg [35:0] word;
        begin
            word = 36'd0;
            word[4:0] = operation;
            word[7:5] = input_select;
            word[10:8] = output_select;
            word[24:21] = lane_mask;
            word[27] = clear_before;
            word[28] = accumulate;
            word[29] = commit_after;
            word[30] = wait_ready;
            word[31] = wait_result;
            word[35:32] = event_number;
            make_context = word;
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task issue_operation;
        input [4:0] operation;
        input [2:0] input_select;
        input [2:0] output_select;
        input clear_before;
        input accumulate;
        input commit_after;
        input [3:0] event_number;
        begin
            @(negedge clk);
            resource_ctx = make_context(operation, input_select, output_select,
                4'hf, clear_before, accumulate, commit_after, 1'b1, 1'b0,
                event_number);
            cycle_valid = 1'b1;
            @(posedge clk);
            while (!resource_in_ready) @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b0;
            cycle_valid = 1'b0;
        end
    endtask

    task consume_operation;
        input [4:0] operation;
        begin
            @(negedge clk);
            resource_ctx = make_context(operation, `RECON_RESOURCE_INPUT_NONE,
                `RECON_RESOURCE_OUTPUT_DISCARD, 4'hf, 0, 0, 0, 0, 1, 0);
            cycle_valid = 1'b1;
            @(posedge clk);
            while (!resource_out_ready) @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            cycle_commit = 1'b0;
            cycle_valid = 1'b0;
        end
    endtask

    integer lane;
    integer wait_cycles;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(negedge clk);
        routine_start = 1;
        @(posedge clk);
        @(negedge clk);
        routine_start = 0;

        // PE scalar broadcast is registered before the wait context may commit.
        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_PE_SCALAR_BROADCAST, 1, 1, 1, 4'd0);
        @(negedge clk);
        resource_ctx = make_context(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
            4'hf, 0, 0, 0, 0, 1, 0);
        cycle_valid = 1;
        #1;
        if (resource_out_ready || scalar_broadcast_valid)
            fail("broadcast response bypassed register stage");
        wait_cycles = 0;
        while (!resource_out_ready) begin
            @(posedge clk);
            #1;
            wait_cycles = wait_cycles + 1;
            if (wait_cycles > 100)
                fail("registered broadcast response timeout");
        end
        if (wait_cycles < 1 || !scalar_broadcast_valid)
            fail("broadcast wait context did not stall for register capture");
        if (scalar_broadcast_data !== EXPECTED_BROADCAST)
            fail("registered broadcast payload mismatch");
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!resource_out_ready || !scalar_broadcast_valid ||
                scalar_broadcast_data !== EXPECTED_BROADCAST)
                fail("registered broadcast changed under backpressure");
        end
        @(negedge clk);
        cycle_commit = 1;
        #1;
        if (!resource_out_ready || !scalar_broadcast_valid)
            fail("registered broadcast missing on commit");
        @(posedge clk);
        #1;
        if (resource_out_ready || scalar_broadcast_valid)
            fail("registered broadcast response consumed more than once");
        @(negedge clk);
        cycle_commit = 0;
        cycle_valid = 0;

        // DOT and NORM results are committed through the router into A62 state.
        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 0, 0, 1, 4'd1);
        consume_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT);
        if (!scalar0_valid || scalar0_data !== `M5_VECTOR_DOT)
            fail("router DOT to scalar0 mismatch");

        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_SCALAR_1, 0, 0, 1, 4'd2);
        consume_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ);
        if (!scalar1_valid || scalar1_data !== `M5_VECTOR_NORM)
            fail("router NORM to scalar1 mismatch");

        issue_operation(`RECON_RESOURCE_OP_SCALAR_DIVIDE,
            `RECON_RESOURCE_INPUT_SCALAR_0,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 0, 0, 1, 4'd3);
        consume_operation(`RECON_RESOURCE_OP_SCALAR_DIVIDE);
        if (scalar0_data[DATA_W-1:0] !== `M5_DOT_OVER_NORM ||
            saturation_event !== `M5_DOT_OVER_NORM_SAT)
            fail("router divide/scalar writeback mismatch");

        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_DISCARD, 1, 1, 0, 4'd4);
        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 0, 1, 1, 4'd5);
        consume_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT);
        if (scalar0_data !== (`M5_VECTOR_DOT <<< 1))
            fail("router multi-stripe DOT accumulation mismatch");

        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_SCALAR_1, 1, 1, 1, 4'd6);
        consume_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ);
        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 1, 1, 1, 4'd7);
        consume_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT);
        issue_operation(`RECON_RESOURCE_OP_SCALAR_DIVIDE,
            `RECON_RESOURCE_INPUT_SCALAR_1,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 0, 0, 1, 4'd8);
        consume_operation(`RECON_RESOURCE_OP_SCALAR_DIVIDE);
        if (scalar0_data[DATA_W-1:0] !== `M5_NORM_OVER_DOT ||
            saturation_event !== `M5_NORM_OVER_DOT_SAT)
            fail("router reverse divide input selection mismatch");

        // COPY response must not escape while the memory sink is blocked.
        vector_result_ready = 0;
        issue_operation(`RECON_RESOURCE_OP_SHARED_VECTOR_COPY,
            `RECON_RESOURCE_INPUT_MEMORY_STREAM,
            `RECON_RESOURCE_OUTPUT_MEMORY_STREAM, 0, 0, 1, 4'd9);
        @(negedge clk);
        resource_ctx = make_context(`RECON_RESOURCE_OP_SHARED_VECTOR_COPY,
            `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
            4'hf, 0, 0, 0, 0, 1, 0);
        cycle_valid = 1;
        repeat (5) begin
            @(posedge clk);
            if (resource_out_ready || vector_result_valid)
                fail("router released vector response under sink backpressure");
        end
        vector_result_ready = 1;
        while (!resource_out_ready) @(posedge clk);
        @(negedge clk);
        cycle_commit = 1;
        #1;
        if (!vector_result_valid || vector_result_data !== `M5_VECTOR_A)
            fail("router COPY memory result mismatch");
        @(posedge clk);
        @(negedge clk);
        cycle_commit = 0;
        cycle_valid = 0;

        // Reserved opcode remains legal to decode but faults at response commit.
        issue_operation(`RECON_RESOURCE_OP_SCALAR_RECIPROCAL,
            `RECON_RESOURCE_INPUT_SCALAR_0,
            `RECON_RESOURCE_OUTPUT_EVENT, 0, 0, 1, 4'd9);
        @(negedge clk);
        resource_ctx = make_context(`RECON_RESOURCE_OP_SCALAR_RECIPROCAL,
            `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
            4'hf, 0, 0, 0, 0, 1, 0);
        cycle_valid = 1;
        while (!resource_out_ready) @(posedge clk);
        @(negedge clk);
        cycle_commit = 1;
        #1;
        if (!fault_valid || fault_code != `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT)
            fail("reserved opcode fault was not routed");
        if (event_valid) fail("faulting operation emitted normal event");
        @(posedge clk);
        @(negedge clk);
        cycle_commit = 0;
        cycle_valid = 0;

        // Planned/unowned opcodes fail closed instead of committing as silent no-ops.
        @(negedge clk);
        resource_ctx = make_context(`RECON_RESOURCE_OP_TOPK_PUSH,
            `RECON_RESOURCE_INPUT_GLOBAL_REDUCTION,
            `RECON_RESOURCE_OUTPUT_TOPK_STATE, 4'hf, 0, 0, 0, 1, 0, 0);
        cycle_valid = 1;
        #1;
        if (!resource_contract_error)
            fail("unowned TOPK opcode did not fail closed");
        @(negedge clk);
        cycle_valid = 0;
        resource_ctx = 0;

        // Full five-level reduction path writes scalar0 through the same router.
        for (lane = 0; lane < 16; lane = lane + 1) begin
            cluster0_lane_data[lane*ACC_W +: ACC_W] = lane;
            cluster1_lane_data[lane*ACC_W +: ACC_W] = lane + 16;
            cluster0_lane_index[lane*10 +: 10] = lane;
            cluster1_lane_index[lane*10 +: 10] = lane + 16;
        end
        issue_operation(`RECON_RESOURCE_OP_REDUCE_SUM,
            `RECON_RESOURCE_INPUT_CLUSTER_REDUCTION,
            `RECON_RESOURCE_OUTPUT_SCALAR_0, 1, 1, 1, 4'd5);
        consume_operation(`RECON_RESOURCE_OP_REDUCE_SUM);
        if (scalar0_data != 62'sd496)
            fail("router reduction writeback mismatch");

        if (resource_contract_error)
            fail("resource router reported unexpected contract error");
        $display("M5 RESOURCE ROUTER PASS");
        $finish;
    end

    initial begin
        #250000;
        fail("timeout");
    end
endmodule

`default_nettype wire
