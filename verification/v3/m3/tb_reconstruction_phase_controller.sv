`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_reconstruction_phase_controller;
    localparam [2:0] PHASE_MODE_COMPLETE = 3'd0;
    localparam [2:0] PHASE_MODE_SAFE_ABORT = 3'd1;
    localparam [2:0] PHASE_MODE_MISSING = 3'd2;
    localparam [2:0] PHASE_MODE_RAISE_ERROR = 3'd3;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;

    reg start_request = 1'b0;
    reg [63:0] start_address = 64'd0;
    reg abort_request = 1'b0;

    wire cfg_start_valid;
    reg cfg_start_ready = 1'b0;
    wire [63:0] cfg_start_addr;
    reg cfg_fetch_active = 1'b0;
    reg cfg_fetch_error_valid = 1'b0;
    wire cfg_fetch_error_ready;
    reg [3:0] cfg_fetch_error_class = `RECON_ERROR_CLASS_NONE;
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
    reg [2:0] phase_mode = PHASE_MODE_COMPLETE;

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
    reg [3:0] exec_error_class = `RECON_ERROR_CLASS_NONE;
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

    function automatic [35:0] make_phase_instruction;
        input [2:0] operation;
        input [3:0] terminal_code;
        input safe_abort_point;
        reg [35:0] word;
        begin
            word = 36'd0;
            word[2:0] = operation;
            word[14:11] = `RECON_PHASE_CONDITION_ALWAYS;
            word[31:28] = terminal_code;
            word[32] = safe_abort_point;
            word[33] = 1'b1;
            make_phase_instruction = word;
        end
    endfunction

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

    task automatic issue_start;
        input [63:0] address;
        begin
            @(negedge clk);
            start_address = address;
            start_request = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start_request = 1'b0;
        end
    endtask

    task automatic accept_configuration_request;
        begin
            timeout = 0;
            while (!cfg_start_valid && timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(cfg_start_valid,
                  "sequencer issues one configuration request");
            repeat (2) begin
                @(posedge clk);
                check(cfg_start_valid,
                      "configuration request holds under backpressure");
            end
            @(negedge clk);
            cfg_start_ready = 1'b1;
            cfg_fetch_active = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cfg_start_ready = 1'b0;
            cfg_fetch_active = 1'b0;
            active_cfg_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic clear_active_configuration;
        begin
            // Model active_configuration_store: release is sampled on the next
            // rising edge, then active_valid may drop.
            @(posedge clk);
            @(negedge clk);
            active_cfg_valid = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic pulse_abort;
        begin
            @(negedge clk);
            abort_request = 1'b1;
            @(posedge clk);
            @(negedge clk);
            abort_request = 1'b0;
        end
    endtask

    task automatic wait_terminal_pulse;
        begin
            timeout = 0;
            while (!done_pulse && !error_pulse && timeout < 80) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(done_pulse || error_pulse,
                  "run reaches exactly one terminal pulse");
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_rd_resp_valid <= 1'b0;
            phase_rd_valid <= 1'b0;
            phase_rd_pc <= 8'd0;
            phase_word <= 36'd0;
        end else begin
            phase_rd_resp_valid <= phase_rd_en;
            if (phase_rd_en) begin
                phase_rd_pc <= phase_rd_addr;
                phase_rd_valid <= phase_mode != PHASE_MODE_MISSING;
                case (phase_mode)
                    PHASE_MODE_SAFE_ABORT:
                        phase_word <= make_phase_instruction(
                            `RECON_PHASE_OP_NOP, 4'd0, 1'b1);
                    PHASE_MODE_RAISE_ERROR:
                        phase_word <= make_phase_instruction(
                            `RECON_PHASE_OP_RAISE_ERROR, 4'h6, 1'b0);
                    default:
                        phase_word <= make_phase_instruction(
                            `RECON_PHASE_OP_COMPLETE,
                            `RECON_STOP_ITERATION_LIMIT, 1'b0);
                endcase
            end
        end
    end

    reconstruction_phase_controller dut (
        .clk(clk), .rst_n(rst_n),
        .start_request(start_request), .start_address(start_address),
        .abort_request(abort_request),
        .cfg_start_valid(cfg_start_valid),
        .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(cfg_start_addr),
        .cfg_fetch_active(cfg_fetch_active),
        .cfg_fetch_error_valid(cfg_fetch_error_valid),
        .cfg_fetch_error_ready(cfg_fetch_error_ready),
        .cfg_fetch_error_class(cfg_fetch_error_class),
        .cfg_fetch_error_code(cfg_fetch_error_code),
        .cfg_fetch_error_word(cfg_fetch_error_word),
        .cfg_fetch_error_detail(cfg_fetch_error_detail),
        .active_cfg_valid(active_cfg_valid),
        .active_context_image_ok(active_context_image_ok),
        .active_cfg_release(active_cfg_release),
        .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid), .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word),
        .array_launch_valid(array_launch_valid),
        .array_launch_ready(array_launch_ready),
        .array_entry_pc(array_entry_pc),
        .array_event_id(array_event_id),
        .array_done_valid(array_done_valid),
        .array_done_ready(array_done_ready),
        .array_done_event_id(array_done_event_id),
        .array_done_aborted(array_done_aborted),
        .array_fault_valid(array_fault_valid),
        .array_fault_ready(array_fault_ready),
        .array_fault_code(array_fault_code), .array_fault_pc(array_fault_pc),
        .array_fault_detail(array_fault_detail),
        .resource_valid(1'b0),
        .resource_ready(resource_ready),
        .resource_event(4'd0), .dma_done(1'b0),
        .residual_limit_reached(1'b0),
        .iteration_limit_reached(1'b0), .support_stable(1'b0),
        .residual_decreased(1'b0), .solver_converged(1'b0),
        .solver_fault(1'b0),
        .exec_error_pending(exec_error_pending),
        .exec_error_class(exec_error_class),
        .exec_error_code(exec_error_code),
        .exec_error_detail(exec_error_detail),
        .active_support(7'd9),
        .outer_iter(16'd2),
        .solver_iter(8'd3),
        .engine_busy(engine_busy),
        .phase_active(phase_active),
        .csr_cfg_fetch_active(
            csr_cfg_fetch_active),
        .writeback_active(writeback_active),
        .abort_pending(abort_pending),
        .done_pulse(done_pulse),
        .stop_reason(stop_reason),
        .support_count(support_count),
        .error_pulse(error_pulse), .error_class(error_class),
        .error_code(error_code), .error_phase(error_phase),
        .cfg_error_word(cfg_error_word),
        .error_detail(error_detail),
        .phase_progress(phase_progress),
        .outer_progress(outer_progress),
        .solver_progress(solver_progress),
        .total_cycles(total_cycles),
        .control_state(control_state), .active_image_bank(active_image_bank),
        .trace_valid(trace_valid), .trace_phase_pc(trace_phase_pc),
        .trace_operation(trace_operation),
        .trace_condition(trace_condition)
    );

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // Successful run: one compiler phase instruction retires directly.
        phase_mode = PHASE_MODE_COMPLETE;
        issue_start(64'h0000_0000_0000_2000);
        check(engine_busy, "START makes the global sequencer busy");
        check(cfg_start_addr == 64'h0000_0000_0000_2000,
              "captured configuration address is exact");
        @(negedge clk); start_address = 64'hdead_beef_dead_beef;
        accept_configuration_request();
        wait_terminal_pulse();
        check(done_pulse && !error_pulse,
              "phase COMPLETE produces a completion pulse");
        check(stop_reason == `RECON_STOP_ITERATION_LIMIT &&
              support_count == 7'd9,
              "completion metadata comes from phase context and progress");
        check(active_cfg_release && !engine_busy,
              "successful retirement releases configuration and returns idle");
        check(total_cycles != 64'd0 && trace_valid,
              "cycle and phase trace telemetry are active");
        clear_active_configuration();

        // An unfinalized active context image is rejected before phase fetch.
        active_context_image_ok = 1'b0;
        issue_start(64'h0000_0000_0000_2800);
        accept_configuration_request();
        wait_terminal_pulse();
        check(error_pulse &&
              error_class == `RECON_ERROR_CLASS_CONTEXT &&
              error_code == `RECON_CONTEXT_ERROR_IMAGE_UNAVAILABLE,
              "unavailable context image is rejected before phase fetch");
        check(active_cfg_release && !phase_rd_en,
              "unavailable image releases configuration without execution");
        clear_active_configuration();
        active_context_image_ok = 1'b1;

        // M2 fetch/validation error metadata is preserved exactly.
        issue_start(64'h0000_0000_0000_3000);
        timeout = 0;
        while (!cfg_start_valid && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        @(negedge clk); cfg_start_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); cfg_start_ready = 1'b0;
        cfg_fetch_error_class = `RECON_ERROR_CLASS_DMA_READ;
        cfg_fetch_error_code = 8'h55;
        cfg_fetch_error_word = 5'd7;
        cfg_fetch_error_detail = 32'hfeed_0007;
        cfg_fetch_error_valid = 1'b1;
        check(cfg_fetch_error_ready,
              "configuration error channel is accepted in wait state");
        @(posedge clk); #1;
        check(error_pulse && error_class == `RECON_ERROR_CLASS_DMA_READ &&
              error_code == 8'h55 && cfg_error_word == 5'd7 &&
              error_detail == 32'hfeed_0007,
              "configuration error attribution is unchanged");
        @(negedge clk); cfg_fetch_error_valid = 1'b0;
        repeat (2) @(posedge clk);

        // Abort before configuration ownership completes has no release pulse.
        issue_start(64'h0000_0000_0000_3800);
        timeout = 0;
        while (!cfg_start_valid && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        pulse_abort();
        wait_terminal_pulse();
        check(done_pulse &&
              stop_reason == `RECON_STOP_ABORTED &&
              !active_cfg_release,
              "pre-configuration abort retires without false release");
        repeat (2) @(posedge clk);

        // Runtime abort waits for a compiler-declared safe phase instruction.
        phase_mode = PHASE_MODE_SAFE_ABORT;
        issue_start(64'h0000_0000_0000_4000);
        accept_configuration_request();
        wait (phase_active);
        pulse_abort();
        wait_terminal_pulse();
        check(done_pulse &&
              stop_reason == `RECON_STOP_ABORTED &&
              active_cfg_release,
              "safe phase context consumes pending abort");
        clear_active_configuration();

        // Missing resident phase context is deterministic, never an idle hang.
        phase_mode = PHASE_MODE_MISSING;
        issue_start(64'h0000_0000_0000_4800);
        accept_configuration_request();
        wait_terminal_pulse();
        check(error_pulse &&
              error_class == `RECON_ERROR_CLASS_CONTEXT &&
              error_code == `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION &&
              error_phase == 8'd0,
              "missing phase PC produces an address-specific context error");
        clear_active_configuration();

        // Phase RAISE_ERROR retires directly through the global sequencer.
        phase_mode = PHASE_MODE_RAISE_ERROR;
        issue_start(64'h0000_0000_0000_5000);
        accept_configuration_request();
        wait_terminal_pulse();
        check(error_pulse &&
              error_class == `RECON_ERROR_CLASS_NUMERIC &&
              error_code == 8'h06 && error_phase == 8'd0,
              "phase error opcode reaches CSR-facing metadata directly");
        clear_active_configuration();

        check(!engine_busy && !csr_cfg_fetch_active &&
              !writeback_active && !active_image_bank,
              "global sequencer returns to clean bank-zero idle state");

        if (failures == 0)
            $display("M3 CONTROL SEQUENCER PASS");
        else
            $display("M3 CONTROL SEQUENCER FAIL count=%0d", failures);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: M3 control sequencer timeout");
        $finish;
    end
endmodule

`default_nettype wire
