`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_execution_profile_monitor;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg run_start = 1'b0;
    reg engine_busy = 1'b0;
    reg phase_active = 1'b0;
    reg execution_active = 1'b0;
    reg cycle_valid = 1'b0;
    reg cycle_commit = 1'b0;
    reg cycle_stalled = 1'b0;
    reg [`RECON_CLUSTER_COUNT-1:0] cluster_mask = 0;
    reg [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx = 0;
    reg [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx = 0;
    reg [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx = 0;
    reg [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx = 0;
    reg [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0]
        predicate_values = 0;
    reg stream_input_ready = 1'b1;
    reg stream_output_ready = 1'b1;
    reg resource_req_ready = 1'b1;
    reg resource_rsp_valid = 1'b1;
    wire [63:0] total_cycles;
    wire [63:0] phase_cycles;
    wire [63:0] execution_cycles;
    wire [63:0] array_commit_cycles;
    wire [63:0] array_stall_cycles;
    wire [63:0] useful_pe_cycles;
    wire [63:0] useful_pe_slots;
    wire [63:0] resource_stall_cycles;

    integer failures = 0;
    task automatic check;
        input condition;
        input [255:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic clock_once;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    execution_profile_monitor dut (.*);

    initial begin
        repeat (3) clock_once();
        rst_n = 1'b1;
        run_start = 1'b1;
        clock_once();
        run_start = 1'b0;

        engine_busy = 1'b1;
        phase_active = 1'b1;
        repeat (2) clock_once();

        execution_active = 1'b1;
        cycle_valid = 1'b1;
        cycle_commit = 1'b1;
        cluster_mask = 2'b11;
        tile_ctx[0*`RECON_TILE_CONTEXT_W +
                 `RECON_TILE_FIELD_OPERATION_LSB +:
                 `RECON_TILE_FIELD_OPERATION_W] = `RECON_TILE_OP_ADD;
        tile_ctx[3*`RECON_TILE_CONTEXT_W +
                 `RECON_TILE_FIELD_OPERATION_LSB +:
                 `RECON_TILE_FIELD_OPERATION_W] = `RECON_TILE_OP_SUB;
        clock_once();

        cycle_commit = 1'b0;
        cycle_stalled = 1'b1;
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB] = 1'b1;
        resource_req_ready = 1'b0;
        clock_once();

        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB] = 1'b1;
        stream_input_ready = 1'b0;
        clock_once();

        check(total_cycles == 5, "first run total cycles");
        check(phase_cycles == 5, "first run phase cycles");
        check(execution_cycles == 3, "first run execution cycles");
        check(array_commit_cycles == 1, "first run commit cycles");
        check(array_stall_cycles == 2, "first run stall cycles");
        check(useful_pe_cycles == 1, "first run useful PE cycles");
        check(useful_pe_slots == 4, "first run useful PE slots");
        check(resource_stall_cycles == 1,
            "resource stall excludes higher-priority stream stall");

        array_ctx[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W] =
            `RECON_NEXT_PC_MODE_WAIT_EVENT;
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_OUTPUT_LSB] = 1'b1;
        stream_output_ready = 1'b0;
        clock_once();
        check(resource_stall_cycles == 1,
            "resource stall excludes wait-event and stream blockers");

        array_ctx = 0;
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB] = 1'b0;
        stream_input_ready = 1'b1;
        clock_once();
        check(resource_stall_cycles == 1,
            "resource stall excludes stream-output blocker");

        stream_ctx = 0;
        stream_output_ready = 1'b1;
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB] = 1'b0;
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB] = 1'b1;
        resource_req_ready = 1'b1;
        resource_rsp_valid = 1'b0;
        clock_once();
        check(resource_stall_cycles == 2,
            "resource response stall counted without higher-priority blocker");

        cycle_stalled = 1'b0;
        clock_once();
        check(resource_stall_cycles == 2,
            "resource unavailability ignored without sequencer stall");
        check(total_cycles == 9, "extended first run total cycles");
        check(array_stall_cycles == 5, "exclusive stall scenarios counted once");

        run_start = 1'b1;
        clock_once();
        check(total_cycles == 0, "run start resets total cycles");
        check(useful_pe_slots == 0, "run start resets PE slots");
        check(resource_stall_cycles == 0,
            "run start resets resource stalls");

        run_start = 1'b0;
        stream_ctx = 0;
        resource_ctx = 0;
        stream_input_ready = 1'b1;
        resource_req_ready = 1'b1;
        cycle_stalled = 1'b0;
        cycle_commit = 1'b1;
        cluster_mask = 2'b01;
        tile_ctx = 0;
        tile_ctx[7*`RECON_TILE_CONTEXT_W +
                 `RECON_TILE_FIELD_OPERATION_LSB +:
                 `RECON_TILE_FIELD_OPERATION_W] = `RECON_TILE_OP_ADD;
        clock_once();

        check(total_cycles == 1, "second run total cycles");
        check(array_commit_cycles == 1, "second run commit cycles");
        check(useful_pe_cycles == 1, "second run useful cycles");
        check(useful_pe_slots == 1, "second run useful slots");

        if (failures == 0)
            $display("EXECUTION PROFILE MONITOR PASS");
        else
            $display("FAIL: execution profile monitor failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
