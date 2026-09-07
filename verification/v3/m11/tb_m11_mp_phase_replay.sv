`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_m11_mp_phase_replay;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer launch_count = 0;
    integer trace_count = 0;
    reg [35:0] phase_memory [0:255];
    reg [7:0] expected_entry [0:21];

    reg start_request = 1'b0;
    wire cfg_start_valid;
    reg cfg_start_ready = 1'b0;
    reg active_cfg_valid = 1'b0;
    wire active_cfg_release;
    wire phase_rd_en;
    wire [7:0] phase_rd_addr;
    reg phase_rd_resp_valid = 1'b0;
    reg phase_rd_valid = 1'b0;
    reg [7:0] phase_rd_pc = 8'd0;
    reg [35:0] phase_word = 36'd0;
    wire array_launch_valid;
    wire [7:0] array_entry_pc;
    wire [3:0] array_event_id;
    reg array_done_valid = 1'b0;
    wire array_done_ready;
    reg [3:0] array_done_event_id = 4'd0;
    wire done_pulse;
    wire [3:0] stop_reason;
    wire error_pulse;
    wire trace_valid;

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        phase_rd_resp_valid <= 1'b0;
        if (phase_rd_en) begin
            phase_rd_resp_valid <= 1'b1;
            phase_rd_valid <= phase_rd_addr < 8'd27;
            phase_rd_pc <= phase_rd_addr;
            phase_word <= phase_memory[phase_rd_addr];
        end
        if (array_launch_valid) begin
            check(launch_count < 22, "MP phase emitted no extra array launch");
            if (launch_count < 22)
                check(array_entry_pc == expected_entry[launch_count],
                      "MP phase launch order matches resident context ABI");
            launch_count <= launch_count + 1;
            array_done_valid <= 1'b1;
            array_done_event_id <= array_event_id;
        end else if (array_done_valid && array_done_ready) begin
            array_done_valid <= 1'b0;
        end
        if (trace_valid)
            trace_count <= trace_count + 1;
    end

    reconstruction_phase_controller dut (
        .clk(clk), .rst_n(rst_n), .start_request(start_request),
        .start_address(64'h7000), .abort_request(1'b0),
        .cfg_start_valid(cfg_start_valid), .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(), .cfg_fetch_active(1'b0),
        .cfg_fetch_error_valid(1'b0), .cfg_fetch_error_ready(),
        .cfg_fetch_error_class(4'd0), .cfg_fetch_error_code(8'd0),
        .cfg_fetch_error_word(5'd0), .cfg_fetch_error_detail(32'd0),
        .active_cfg_valid(active_cfg_valid), .active_context_image_ok(1'b1),
        .active_cfg_release(active_cfg_release), .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr), .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word), .array_launch_valid(array_launch_valid),
        .array_launch_ready(1'b1), .array_entry_pc(array_entry_pc),
        .array_event_id(array_event_id), .array_done_valid(array_done_valid),
        .array_done_ready(array_done_ready),
        .array_done_event_id(array_done_event_id), .array_done_aborted(1'b0),
        .array_fault_valid(1'b0), .array_fault_ready(),
        .array_fault_code(8'd0), .array_fault_pc(8'd0),
        .array_fault_detail(32'd0), .resource_valid(1'b0), .resource_ready(),
        .resource_event(4'd0), .dma_done(1'b0),
        .residual_limit_reached(1'b0),
        .iteration_limit_reached(launch_count >= 22), .support_stable(1'b1),
        .residual_decreased(1'b0), .solver_converged(1'b0),
        .solver_fault(1'b0), .exec_error_pending(1'b0),
        .exec_error_class(4'd0), .exec_error_code(8'd0),
        .exec_error_detail(32'd0), .active_support(7'd1),
        .outer_iter(16'd2), .solver_iter(8'd0), .engine_busy(),
        .phase_active(), .csr_cfg_fetch_active(), .writeback_active(),
        .abort_pending(), .done_pulse(done_pulse), .stop_reason(stop_reason),
        .support_count(), .error_pulse(error_pulse), .error_class(),
        .error_code(), .error_phase(), .cfg_error_word(), .error_detail(),
        .phase_progress(), .outer_progress(), .solver_progress(),
        .total_cycles(), .control_state(), .active_image_bank(),
        .trace_valid(trace_valid), .trace_phase_pc(), .trace_operation(),
        .trace_condition()
    );

    task automatic append_iteration;
        input integer base;
        begin
            expected_entry[base+0] = 8'd85;
            expected_entry[base+1] = 8'd174;
            expected_entry[base+2] = 8'd180;
            expected_entry[base+3] = 8'd116;
            expected_entry[base+4] = 8'd222;
            expected_entry[base+5] = 8'd16;
            expected_entry[base+6] = 8'd189;
            expected_entry[base+7] = 8'd204;
            expected_entry[base+8] = 8'd120;
            expected_entry[base+9] = 8'd124;
            expected_entry[base+10] = 8'd10;
        end
    endtask

    initial begin
        $readmemh("program_07_phase.mem", phase_memory);
        append_iteration(0);
        append_iteration(11);
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(negedge clk); start_request = 1'b1;
        @(posedge clk);
        @(negedge clk); start_request = 1'b0;
        timeout = 0;
        while (!cfg_start_valid && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(cfg_start_valid, "MP phase requests configuration");
        @(negedge clk); cfg_start_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); cfg_start_ready = 1'b0; active_cfg_valid = 1'b1;
        timeout = 0;
        while (!done_pulse && !error_pulse && timeout < 800) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(!error_pulse, "MP phase replay has no controller error");
        check(done_pulse, "MP phase replay terminates");
        check(stop_reason == `RECON_STOP_ITERATION_LIMIT,
              "MP phase stops on iteration limit");
        check(launch_count == 22, "MP phase completes exactly two iterations");
        check(trace_count >= 48, "MP phase emits instruction trace");
        check(active_cfg_release, "MP phase releases active configuration");
        if (failures == 0)
            $display("M11 MP PHASE IMAGE REPLAY PASS launches=%0d traces=%0d",
                     launch_count, trace_count);
        else
            $display("FAIL: M11 MP phase replay failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
