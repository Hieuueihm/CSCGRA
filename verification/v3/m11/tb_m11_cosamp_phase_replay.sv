`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_m11_cosamp_phase_replay;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer launch_count = 0;
    integer trace_count = 0;
    integer certificate_count = 0;

    reg [35:0] phase_memory [0:255];
    reg [7:0] expected_entry [0:35];

    reg start_request = 1'b0;
    reg [63:0] start_address = 64'h3000;
    reg abort_request = 1'b0;
    wire cfg_start_valid;
    reg cfg_start_ready = 1'b0;
    wire [63:0] cfg_start_addr;
    reg cfg_fetch_active = 1'b0;
    reg cfg_fetch_error_valid = 1'b0;
    wire cfg_fetch_error_ready;
    reg [3:0] cfg_fetch_error_class = 4'd0;
    reg [7:0] cfg_fetch_error_code = 8'd0;
    reg [4:0] cfg_fetch_error_word = 5'd0;
    reg [31:0] cfg_fetch_error_detail = 32'd0;
    reg active_cfg_valid = 1'b0;
    reg active_context_image_ok = 1'b1;
    wire active_cfg_release;

    wire phase_rd_en;
    wire [7:0] phase_rd_addr;
    reg phase_rd_resp_valid = 1'b0;
    reg phase_rd_valid = 1'b0;
    reg [7:0] phase_rd_pc = 8'd0;
    reg [35:0] phase_word = 36'd0;

    wire array_launch_valid;
    reg array_launch_ready = 1'b1;
    wire [7:0] array_entry_pc;
    wire [3:0] array_event_id;
    reg array_done_valid = 1'b0;
    wire array_done_ready;
    reg [3:0] array_done_event_id = 4'd0;
    reg array_done_aborted = 1'b0;
    reg array_fault_valid = 1'b0;
    wire array_fault_ready;
    reg [7:0] array_fault_code = 8'd0;
    reg [7:0] array_fault_pc = 8'd0;
    reg [31:0] array_fault_detail = 32'd0;

    wire resource_ready;
    reg exec_error_pending = 1'b0;
    reg [3:0] exec_error_class = 4'd0;
    reg [7:0] exec_error_code = 8'd0;
    reg [31:0] exec_error_detail = 32'd0;
    wire engine_busy;
    wire phase_active;
    wire csr_cfg_fetch_active;
    wire writeback_active;
    wire abort_pending;
    wire done_pulse;
    wire [3:0] stop_reason;
    wire [6:0] support_count;
    wire error_pulse;
    wire [3:0] error_class;
    wire [7:0] error_code;
    wire [7:0] error_phase;
    wire [4:0] cfg_error_word;
    wire [31:0] error_detail;
    wire [7:0] phase_progress;
    wire [15:0] outer_progress;
    wire [7:0] solver_progress;
    wire [63:0] total_cycles;
    wire [2:0] control_state;
    wire active_image_bank;
    wire trace_valid;
    wire [7:0] trace_phase_pc;
    wire [2:0] trace_operation;
    wire trace_condition;
    wire solver_converged = (certificate_count != 0) &&
                            ((certificate_count & 1) == 0);

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
            phase_rd_valid <= phase_rd_addr < 8'd39;
            phase_rd_pc <= phase_rd_addr;
            phase_word <= phase_memory[phase_rd_addr];
        end

        if (array_launch_valid && array_launch_ready) begin
            check(launch_count < 36, "COSAMP phase emitted no extra array launch");
            if (launch_count < 36)
                check(array_entry_pc == expected_entry[launch_count],
                      "COSAMP phase launch order matches resident context ABI");
            launch_count <= launch_count + 1;
            if (array_entry_pc == 8'd59)
                certificate_count <= certificate_count + 1;
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
        .start_address(start_address), .abort_request(abort_request),
        .cfg_start_valid(cfg_start_valid), .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(cfg_start_addr), .cfg_fetch_active(cfg_fetch_active),
        .cfg_fetch_error_valid(cfg_fetch_error_valid),
        .cfg_fetch_error_ready(cfg_fetch_error_ready),
        .cfg_fetch_error_class(cfg_fetch_error_class),
        .cfg_fetch_error_code(cfg_fetch_error_code),
        .cfg_fetch_error_word(cfg_fetch_error_word),
        .cfg_fetch_error_detail(cfg_fetch_error_detail),
        .active_cfg_valid(active_cfg_valid),
        .active_context_image_ok(active_context_image_ok),
        .active_cfg_release(active_cfg_release), .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr), .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word), .array_launch_valid(array_launch_valid),
        .array_launch_ready(array_launch_ready), .array_entry_pc(array_entry_pc),
        .array_event_id(array_event_id), .array_done_valid(array_done_valid),
        .array_done_ready(array_done_ready),
        .array_done_event_id(array_done_event_id),
        .array_done_aborted(array_done_aborted),
        .array_fault_valid(array_fault_valid),
        .array_fault_ready(array_fault_ready), .array_fault_code(array_fault_code),
        .array_fault_pc(array_fault_pc), .array_fault_detail(array_fault_detail),
        .resource_valid(1'b0), .resource_ready(resource_ready),
        .resource_event(4'd0), .dma_done(1'b0),
        .residual_limit_reached(1'b0),
        .iteration_limit_reached(launch_count >= 36), .support_stable(1'b0),
        .residual_decreased(1'b0), .solver_converged(solver_converged),
        .solver_fault(1'b0), .exec_error_pending(exec_error_pending),
        .exec_error_class(exec_error_class), .exec_error_code(exec_error_code),
        .exec_error_detail(exec_error_detail), .active_support(7'd2),
        .outer_iter(16'd2), .solver_iter(certificate_count[7:0]),
        .engine_busy(engine_busy), .phase_active(phase_active),
        .csr_cfg_fetch_active(csr_cfg_fetch_active),
        .writeback_active(writeback_active), .abort_pending(abort_pending),
        .done_pulse(done_pulse), .stop_reason(stop_reason),
        .support_count(support_count), .error_pulse(error_pulse),
        .error_class(error_class), .error_code(error_code),
        .error_phase(error_phase), .cfg_error_word(cfg_error_word),
        .error_detail(error_detail), .phase_progress(phase_progress),
        .outer_progress(outer_progress), .solver_progress(solver_progress),
        .total_cycles(total_cycles), .control_state(control_state),
        .active_image_bank(active_image_bank), .trace_valid(trace_valid),
        .trace_phase_pc(trace_phase_pc), .trace_operation(trace_operation),
        .trace_condition(trace_condition)
    );

    integer outer_index;
    integer launch_index;
    initial begin
        $readmemh("program_01_phase.mem", phase_memory);
        for (outer_index = 0; outer_index < 2; outer_index = outer_index + 1) begin
            launch_index = outer_index * 18;
            expected_entry[launch_index+0] = 8'd0;
            expected_entry[launch_index+1] = 8'd128;
            expected_entry[launch_index+2] = 8'd116;
            expected_entry[launch_index+3] = 8'd37;
            expected_entry[launch_index+4] = 8'd16;
            expected_entry[launch_index+5] = 8'd44;
            expected_entry[launch_index+6] = 8'd30;
            expected_entry[launch_index+7] = 8'd59;
            expected_entry[launch_index+8] = 8'd68;
            expected_entry[launch_index+9] = 8'd16;
            expected_entry[launch_index+10] = 8'd44;
            expected_entry[launch_index+11] = 8'd30;
            expected_entry[launch_index+12] = 8'd59;
            expected_entry[launch_index+13] = 8'd133;
            expected_entry[launch_index+14] = 8'd139;
            expected_entry[launch_index+15] = 8'd116;
            expected_entry[launch_index+16] = 8'd124;
            expected_entry[launch_index+17] = 8'd10;
        end

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
        check(cfg_start_valid, "COSAMP phase requests configuration");
        @(negedge clk); cfg_start_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); cfg_start_ready = 1'b0; active_cfg_valid = 1'b1;

        timeout = 0;
        while (!done_pulse && !error_pulse && timeout < 1200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(!error_pulse, "COSAMP phase replay has no controller error");
        check(done_pulse, "COSAMP phase replay terminates");
        check(stop_reason == `RECON_STOP_ITERATION_LIMIT,
              "COSAMP phase stops on iteration limit");
        check(launch_count == 36, "COSAMP phase completes two outer iterations");
        check(certificate_count == 4, "COSAMP phase completes two refinement iterations per outer loop");
        check(trace_count >= 70, "COSAMP phase emits instruction trace");
        check(active_cfg_release, "COSAMP phase releases active configuration");
        if (failures == 0)
            $display("M11 COSAMP PHASE IMAGE REPLAY PASS launches=%0d traces=%0d certificates=%0d",
                     launch_count, trace_count, certificate_count);
        else
            $display("FAIL: M11 COSAMP phase replay failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire

