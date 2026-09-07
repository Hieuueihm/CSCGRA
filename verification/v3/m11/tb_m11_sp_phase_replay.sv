`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_m11_sp_phase_replay;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer launch_count = 0;
    integer trace_count = 0;
    integer certificate_count = 0;
    integer residual_count = 0;
    integer expected_count = 0;

    reg [35:0] phase_memory [0:255];
    reg [7:0] expected_entry [0:86];

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
    wire residual_decreased = residual_count == 2;

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
            phase_rd_valid <= phase_rd_addr < 8'd161;
            phase_rd_pc <= phase_rd_addr;
            phase_word <= phase_memory[phase_rd_addr];
        end

        if (array_launch_valid && array_launch_ready) begin
            check(launch_count < 87, "SP phase emitted no extra array launch");
            if ((launch_count < 87) &&
                    (array_entry_pc != expected_entry[launch_count]))
                $display("SP LAUNCH MISMATCH slot=%0d actual=%0d expected=%0d",
                         launch_count, array_entry_pc,
                         expected_entry[launch_count]);
            if (launch_count < 87)
                check(array_entry_pc == expected_entry[launch_count],
                      "SP phase launch order matches resident context ABI");
            launch_count <= launch_count + 1;
            if (array_entry_pc == 8'd68)
                certificate_count <= certificate_count + 1;
            if (array_entry_pc == 8'd10)
                residual_count <= residual_count + 1;
            array_done_valid <= 1'b1;
            array_done_event_id <= array_event_id;
        end else if (array_done_valid && array_done_ready) begin
            array_done_valid <= 1'b0;
        end

        if (trace_valid) begin
            $display("SP TRACE pc=%0d op=%0d cond=%b", trace_phase_pc,
                     trace_operation, trace_condition);
            trace_count <= trace_count + 1;
        end
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
        .iteration_limit_reached(1'b0), .support_stable(1'b0),
        .residual_decreased(residual_decreased), .solver_converged(solver_converged),
        .solver_fault(1'b0), .solver_recompute_required(1'b0),
        .solver_replacement_required(1'b0),
        .exec_error_pending(exec_error_pending),
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

    task automatic append_expected;
        input [7:0] entry_pc;
        begin
            expected_entry[expected_count] = entry_pc;
            expected_count = expected_count + 1;
        end
    endtask

    task automatic append_refinement;
        input [7:0] scatter_pc;
        begin
            append_expected(8'd37);
            append_expected(8'd16);
            append_expected(8'd53);
            append_expected(8'd30);
            append_expected(8'd68);
            append_expected(8'd77);
            append_expected(8'd16);
            append_expected(8'd53);
            append_expected(8'd30);
            append_expected(8'd68);
            append_expected(scatter_pc);
        end
    endtask

    task automatic append_iteration;
        begin
            append_expected(8'd0);
            append_expected(8'd169);
            append_expected(8'd136);
            append_refinement(8'd184);
            append_expected(8'd153);
            append_expected(8'd174);
            append_expected(8'd136);
            append_expected(8'd144);
            append_expected(8'd10);
            append_refinement(8'd184);
            append_expected(8'd144);
            append_expected(8'd10);
        end
    endtask

    initial begin
        $readmemh("program_04_phase.mem", phase_memory);
        append_expected(8'd255);
        append_expected(8'd0);
        append_expected(8'd122);
        append_expected(8'd136);
        append_expected(8'd89);
        append_expected(8'd30);
        append_expected(8'd92);
        append_expected(8'd16);
        append_expected(8'd53);
        append_expected(8'd30);
        append_expected(8'd68);
        append_expected(8'd77);
        append_expected(8'd16);
        append_expected(8'd53);
        append_expected(8'd30);
        append_expected(8'd68);
        append_expected(8'd140);
        append_expected(8'd144);
        append_expected(8'd10);
        append_iteration();
        append_expected(8'd188);
        append_iteration();
        append_expected(8'd191);
        append_expected(8'd144);
        append_expected(8'd10);
        check(expected_count == 87, "SP expected launch count is complete");

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
        check(cfg_start_valid, "SP phase requests configuration");
        @(negedge clk); cfg_start_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); cfg_start_ready = 1'b0; active_cfg_valid = 1'b1;

        timeout = 0;
        while (!done_pulse && !error_pulse && timeout < 2400) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        $display("SP FINAL done=%b error=%b class=%0d code=%0d phase=%0d detail=%08x launches=%0d cert=%0d residual=%0d traces=%0d timeout=%0d",
                 done_pulse, error_pulse, error_class, error_code, error_phase,
                 error_detail,
                 launch_count, certificate_count, residual_count, trace_count,
                 timeout);
        check(!error_pulse, "SP phase replay has no controller error");
        check(done_pulse, "SP phase replay terminates");
        check(stop_reason == `RECON_STOP_NON_DECREASE,
              "SP phase stops on non-decrease after rollback");
        check(launch_count == 87, "SP phase covers accept then rollback paths");
        check(certificate_count == 10,
              "SP phase completes two refinement iterations per LS solve");
        check(residual_count == 6,
              "SP phase recomputes accepted residual after rollback");
        check(trace_count >= 150, "SP phase emits instruction trace");
        check(active_cfg_release, "SP phase releases active configuration");
        if (failures == 0)
            $display("M11 SP PHASE IMAGE REPLAY PASS launches=%0d traces=%0d certificates=%0d",
                     launch_count, trace_count, certificate_count);
        else
            $display("FAIL: M11 SP phase replay failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
