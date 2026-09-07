`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

// Single global control sequencer for one reconstruction run.  The fixed FSM
// owns only launch, configuration lifetime, phase-context fetch and terminal
// retirement. Execution order is encoded in the compiler-generated phase
// context image; this module never identifies an algorithm or decodes a PE operation.
module reconstruction_phase_controller #(
    parameter integer ADDRESS_W = 64
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   start_request,
    input  wire [ADDRESS_W-1:0]   start_address,
    input  wire                   abort_request,

    output wire                   cfg_start_valid,
    input  wire                   cfg_start_ready,
    output wire [ADDRESS_W-1:0]   cfg_start_addr,
    input  wire                   cfg_fetch_active,
    input  wire                   cfg_fetch_error_valid,
    output wire                   cfg_fetch_error_ready,
    input  wire [3:0]             cfg_fetch_error_class,
    input  wire [7:0]             cfg_fetch_error_code,
    input  wire [4:0]             cfg_fetch_error_word,
    input  wire [31:0]            cfg_fetch_error_detail,
    input  wire                   active_cfg_valid,
    input  wire                   active_context_image_ok,
    output reg                    active_cfg_release,

    output wire                   phase_rd_en,
    output wire [7:0]             phase_rd_addr,
    input  wire                   phase_rd_resp_valid,
    input  wire                   phase_rd_valid,
    input  wire [7:0]             phase_rd_pc,
    input  wire [35:0]            phase_word,

    output wire                   array_launch_valid,
    input  wire                   array_launch_ready,
    output wire [7:0]             array_entry_pc,
    output wire [3:0]             array_event_id,
    input  wire                   array_done_valid,
    output wire                   array_done_ready,
    input  wire [3:0]             array_done_event_id,
    input  wire                   array_done_aborted,
    input  wire                   array_fault_valid,
    output wire                   array_fault_ready,
    input  wire [7:0]             array_fault_code,
    input  wire [7:0]             array_fault_pc,
    input  wire [31:0]            array_fault_detail,

    input  wire                   resource_valid,
    output wire                   resource_ready,
    input  wire [3:0]             resource_event,
    input  wire                   dma_done,
    input  wire                   residual_limit_reached,
    input  wire                   iteration_limit_reached,
    input  wire                   support_stable,
    input  wire                   residual_decreased,
    input  wire                   solver_converged,
    input  wire                   solver_recompute_required,
    input  wire                   solver_replacement_required,
    input  wire                   solver_fault,
    input  wire                   exec_error_pending,
    input  wire [3:0]             exec_error_class,
    input  wire [7:0]             exec_error_code,
    input  wire [31:0]            exec_error_detail,

    input  wire [6:0]             active_support,
    input  wire [15:0]            outer_iter,
    input  wire [7:0]             solver_iter,

    output wire                   engine_busy,
    output wire                   phase_active,
    output wire                   csr_cfg_fetch_active,
    output wire                   writeback_active,
    output reg                    abort_pending,
    output reg                    done_pulse,
    output reg  [3:0]             stop_reason,
    output reg  [6:0]             support_count,
    output reg                    error_pulse,
    output reg  [3:0]             error_class,
    output reg  [7:0]             error_code,
    output reg  [7:0]             error_phase,
    output reg  [4:0]             cfg_error_word,
    output reg  [31:0]            error_detail,
    output wire [7:0]             phase_progress,
    output wire [15:0]            outer_progress,
    output wire [7:0]             solver_progress,
    output reg  [63:0]            total_cycles,
    output reg  [2:0]             control_state,
    output wire                   active_image_bank,

    output reg                    trace_valid,
    output reg  [7:0]             trace_phase_pc,
    output reg  [2:0]             trace_operation,
    output reg                    trace_condition
);
    localparam [2:0] STATE_IDLE                  = 3'd0;
    localparam [2:0] STATE_REQ_CFG  = 3'd1;
    localparam [2:0] STATE_WAIT_CFG = 3'd2;
    localparam [2:0] STATE_PHASE_FETCH           = 3'd3;
    localparam [2:0] STATE_PHASE_EXECUTE         = 3'd4;

    localparam [31:0] DETAIL_MISSING_PHASE = 32'h0100_0000;
    localparam [31:0] DETAIL_PC_MISMATCH = 32'h0200_0000;
    localparam [31:0] DETAIL_RESERVED = 32'h0300_0000;
    localparam [31:0] DETAIL_OPERATION = 32'h0400_0000;
    localparam [31:0] DETAIL_CONDITION = 32'h0500_0000;

    localparam [7:0] PHASE_OP_LEGAL =
        `RECON_PHASE_OPERATION_LEGAL_MASK;
    localparam [15:0] PHASE_COND_LEGAL =
        `RECON_PHASE_CONDITION_LEGAL_MASK;

    reg [ADDRESS_W-1:0] start_addr_reg;
    reg [7:0] phase_pc;
    reg [35:0] instruction;
    reg selected_condition;

    wire cfg_start_fire = cfg_start_valid &&
                                      cfg_start_ready;
    wire phase_exec_state = control_state == STATE_PHASE_EXECUTE;
    wire abort_seen = abort_pending ||
        (abort_request && (control_state != STATE_IDLE));

    wire [2:0] operation = instruction[2:0];
    wire [7:0] instr_array_pc = instruction[10:3];
    wire [3:0] cond_sel = instruction[14:11];
    wire cond_inv = instruction[15];
    wire [7:0] target_pc = instruction[23:16];
    wire [3:0] instr_event = instruction[27:24];
    wire [3:0] instr_terminal = instruction[31:28];
    wire instr_safe_abort = instruction[32];
    wire instr_trace = instruction[33];
    wire [1:0] instr_reserved = instruction[35:34];

    wire array_match = array_done_valid &&
                             (array_done_event_id == instr_event);
    wire resource_match = resource_valid &&
        (resource_event == instr_event);
    wire cond_true = selected_condition ^ cond_inv;
    wire op_legal = PHASE_OP_LEGAL[operation];
    wire cond_legal = PHASE_COND_LEGAL[cond_sel];
    wire instr_legal = op_legal && cond_legal &&
                             (instr_reserved == 2'b00);
    wire abort_now = phase_exec_state && instr_legal &&
        abort_seen && instr_safe_abort;
    wire wait_done = phase_exec_state && instr_legal &&
        (operation == `RECON_PHASE_OP_WAIT_CONDITION) &&
        cond_true;
    wire array_aborted = phase_active && array_done_valid &&
                             array_done_aborted;

    assign engine_busy = control_state != STATE_IDLE;
    assign phase_active =
        (control_state == STATE_PHASE_FETCH) || phase_exec_state;
    assign cfg_start_valid =
        control_state == STATE_REQ_CFG;
    assign cfg_start_addr = start_addr_reg;
    assign cfg_fetch_error_ready =
        control_state == STATE_WAIT_CFG;
    assign csr_cfg_fetch_active = cfg_fetch_active;
    assign writeback_active = 1'b0;
    assign active_image_bank = 1'b0;

    // Speculative prefetch: during a WAIT_CONDITION that has not yet fired,
    // issue a read for the next instruction (phase_pc + 1) so that when the
    // wait completes the instruction is already in the pipeline.  This
    // eliminates the 1-cycle PHASE_FETCH gap between consecutive routines.
    wire wait_speculative_prefetch =
        phase_exec_state && instr_legal &&
        (operation == `RECON_PHASE_OP_WAIT_CONDITION) &&
        !cond_true && !abort_now && !exec_error_pending && !array_fault_valid;
    reg  prefetch_valid;
    reg  [35:0] prefetch_word;
    reg  [7:0]  prefetch_pc;
    wire use_prefetch = phase_exec_state && instr_legal &&
        (operation == `RECON_PHASE_OP_WAIT_CONDITION) && cond_true &&
        prefetch_valid && (prefetch_pc == phase_pc + 8'd1);

    assign phase_rd_en = (control_state == STATE_PHASE_FETCH && !use_prefetch) ||
                         wait_speculative_prefetch;
    assign phase_rd_addr = wait_speculative_prefetch ? (phase_pc + 8'd1) : phase_pc;
    assign array_launch_valid = phase_exec_state && instr_legal &&
        (operation == `RECON_PHASE_OP_LAUNCH_ARRAY) &&
        !abort_now && !exec_error_pending && !array_fault_valid;
    assign array_entry_pc = instr_array_pc;
    assign array_event_id = instr_event;
    assign array_done_ready = phase_active &&
        (array_done_aborted ||
         (wait_done && !cond_inv &&
          (cond_sel ==
           `RECON_PHASE_CONDITION_ARRAY_ROUTINE_DONE) && array_match));
    assign resource_ready = phase_active &&
        wait_done && !cond_inv &&
        (cond_sel == `RECON_PHASE_CONDITION_RESOURCE_EVENT) &&
        resource_match;
    assign array_fault_ready = phase_active;

    assign phase_progress = phase_pc;
    assign outer_progress = outer_iter;
    assign solver_progress = solver_iter;

    always @* begin
        case (cond_sel)
            `RECON_PHASE_CONDITION_ALWAYS:
                selected_condition = 1'b1;
            `RECON_PHASE_CONDITION_ARRAY_ROUTINE_DONE:
                selected_condition = array_match;
            `RECON_PHASE_CONDITION_RESOURCE_EVENT:
                selected_condition = resource_match;
            `RECON_PHASE_CONDITION_DMA_DONE:
                selected_condition = dma_done;
            `RECON_PHASE_CONDITION_RESIDUAL_LIMIT:
                selected_condition = residual_limit_reached;
            `RECON_PHASE_CONDITION_ITERATION_LIMIT:
                selected_condition = iteration_limit_reached;
            `RECON_PHASE_CONDITION_SUPPORT_STABLE:
                selected_condition = support_stable;
            `RECON_PHASE_CONDITION_RESIDUAL_DECREASED:
                selected_condition = residual_decreased;
            `RECON_PHASE_CONDITION_SOLVER_CONVERGED:
                selected_condition = solver_converged;
            `RECON_PHASE_CONDITION_SOLVER_FAULT:
                selected_condition = solver_fault;
            `RECON_PHASE_CONDITION_SOLVER_RECOMPUTE_REQUIRED:
                selected_condition = solver_recompute_required;
            `RECON_PHASE_CONDITION_SOLVER_REPLACEMENT_REQUIRED:
                selected_condition = solver_replacement_required;
            `RECON_PHASE_CONDITION_ABORT_PENDING:
                selected_condition = abort_seen;
            `RECON_PHASE_CONDITION_ERROR_PENDING:
                selected_condition = exec_error_pending;
            default:
                selected_condition = 1'b0;
        endcase
    end

    task emit_completion;
        input [3:0] reason;
        begin
            done_pulse <= 1'b1;
            stop_reason <= reason;
            support_count <= active_support;
            if (active_cfg_valid)
                active_cfg_release <= 1'b1;
            control_state <= STATE_IDLE;
            abort_pending <= 1'b0;
        end
    endtask

    task emit_error;
        input [3:0] captured_class;
        input [7:0] captured_code;
        input [7:0] captured_phase;
        input [4:0] cfg_word;
        input [31:0] captured_detail;
        begin
            error_pulse <= 1'b1;
            error_class <= captured_class;
            error_code <= captured_code;
            error_phase <= captured_phase;
            cfg_error_word <= cfg_word;
            error_detail <= captured_detail;
            if (active_cfg_valid)
                active_cfg_release <= 1'b1;
            control_state <= STATE_IDLE;
            abort_pending <= 1'b0;
        end
    endtask

    task emit_trace;
        input [2:0] captured_operation;
        input captured_condition;
        begin
            if (instr_trace) begin
                trace_valid <= 1'b1;
                trace_phase_pc <= phase_pc;
                trace_operation <= captured_operation;
                trace_condition <= captured_condition;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            start_addr_reg <= {ADDRESS_W{1'b0}};
            phase_pc <= 8'd0;
            instruction <= 36'd0;
            active_cfg_release <= 1'b0;
            abort_pending <= 1'b0;
            done_pulse <= 1'b0;
            stop_reason <= `RECON_STOP_NONE;
            support_count <= 7'd0;
            error_pulse <= 1'b0;
            error_class <= `RECON_ERROR_CLASS_NONE;
            error_code <= 8'd0;
            error_phase <= 8'd0;
            cfg_error_word <= 5'd0;
            error_detail <= 32'd0;
            total_cycles <= 64'd0;
            control_state <= STATE_IDLE;
            trace_valid <= 1'b0;
            trace_phase_pc <= 8'd0;
            trace_operation <= 3'd0;
            trace_condition <= 1'b0;
            prefetch_valid <= 1'b0;
            prefetch_word <= 36'd0;
            prefetch_pc <= 8'd0;
        end else begin
            active_cfg_release <= 1'b0;
            done_pulse <= 1'b0;
            error_pulse <= 1'b0;
            trace_valid <= 1'b0;
            // Capture speculative prefetch response
            if (wait_speculative_prefetch && phase_rd_resp_valid &&
                    phase_rd_valid && (phase_rd_pc == phase_pc + 8'd1)) begin
                prefetch_valid <= 1'b1;
                prefetch_word <= phase_word;
                prefetch_pc <= phase_pc + 8'd1;
            end

            if (engine_busy)
                total_cycles <= total_cycles + 64'd1;
            if (abort_request && engine_busy)
                abort_pending <= 1'b1;

            case (control_state)
                STATE_IDLE: begin
                    abort_pending <= 1'b0;
                    if (start_request) begin
                        start_addr_reg <= start_address;
                        total_cycles <= 64'd0;
                        prefetch_valid <= 1'b0;
                        control_state <= STATE_REQ_CFG;
                    end
                end

                STATE_REQ_CFG: begin
                    if (abort_seen) begin
                        emit_completion(`RECON_STOP_ABORTED);
                    end else if (cfg_start_fire) begin
                        control_state <= STATE_WAIT_CFG;
                    end
                end

                STATE_WAIT_CFG: begin
                    if (abort_seen) begin
                        emit_completion(`RECON_STOP_ABORTED);
                    end else if (cfg_fetch_error_valid) begin
                        emit_error(cfg_fetch_error_class,
                                   cfg_fetch_error_code, 8'd0,
                                   cfg_fetch_error_word,
                                   cfg_fetch_error_detail);
                    end else if (active_cfg_valid) begin
                        if (abort_seen) begin
                            emit_completion(`RECON_STOP_ABORTED);
                        end else if (!active_context_image_ok) begin
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_IMAGE_UNAVAILABLE,
                                8'd0, 5'd0, 32'd0);
                        end else begin
                            phase_pc <= `RECON_PHASE_ENTRY_PC;
                            control_state <= STATE_PHASE_FETCH;
                        end
                    end
                end

                STATE_PHASE_FETCH: begin
                    if (array_fault_valid) begin
                        emit_error(`RECON_ERROR_CLASS_CONTEXT,
                            array_fault_code, phase_pc, 5'd0,
                            {array_fault_pc, array_fault_detail[23:0]});
                    end else if (exec_error_pending) begin
                        emit_error(exec_error_class, exec_error_code,
                            phase_pc, 5'd0, exec_error_detail);
                    end else if (array_aborted) begin
                        emit_completion(`RECON_STOP_ABORTED);
                    end else if (phase_rd_resp_valid) begin
                        if (!phase_rd_valid) begin
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                phase_pc, 5'd0,
                                DETAIL_MISSING_PHASE | {24'd0, phase_pc});
                        end else if (phase_rd_pc != phase_pc) begin
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                phase_pc, 5'd0,
                                DETAIL_PC_MISMATCH |
                                {16'd0, phase_rd_pc, phase_pc});
                        end else begin
                            instruction <= phase_word;
                            control_state <= STATE_PHASE_EXECUTE;
                        end
                    end
                end

                STATE_PHASE_EXECUTE: begin
                    if (array_fault_valid) begin
                        emit_error(`RECON_ERROR_CLASS_CONTEXT,
                            array_fault_code, phase_pc, 5'd0,
                            {array_fault_pc, array_fault_detail[23:0]});
                    end else if (exec_error_pending) begin
                        emit_error(exec_error_class, exec_error_code,
                            phase_pc, 5'd0, exec_error_detail);
                    end else if (array_aborted) begin
                        emit_completion(`RECON_STOP_ABORTED);
                    end else if (!instr_legal) begin
                        if (instr_reserved != 2'b00)
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                phase_pc, 5'd0, DETAIL_RESERVED |
                                {30'd0, instr_reserved});
                        else if (!op_legal)
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                phase_pc, 5'd0, DETAIL_OPERATION |
                                {29'd0, operation});
                        else
                            emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                phase_pc, 5'd0, DETAIL_CONDITION |
                                {28'd0, cond_sel});
                    end else if (abort_now) begin
                        emit_trace(operation, cond_true);
                        emit_completion(`RECON_STOP_ABORTED);
                    end else begin
                        case (operation)
                            `RECON_PHASE_OP_NOP: begin
                                emit_trace(operation, cond_true);
                                phase_pc <= phase_pc + 8'd1;
                                prefetch_valid <= 1'b0;
                                control_state <= STATE_PHASE_FETCH;
                            end
                            `RECON_PHASE_OP_LAUNCH_ARRAY: begin
                                if (array_launch_valid &&
                                        array_launch_ready) begin
                                    emit_trace(operation,
                                               cond_true);
                                    phase_pc <= phase_pc + 8'd1;
                                    prefetch_valid <= 1'b0;
                                    control_state <= STATE_PHASE_FETCH;
                                end
                            end
                            `RECON_PHASE_OP_WAIT_CONDITION: begin
                                if (cond_true) begin
                                    emit_trace(operation, 1'b1);
                                    phase_pc <= phase_pc + 8'd1;
                                    if (use_prefetch) begin
                                        // Fast-chain: skip FETCH, load
                                        // prefetched instruction directly
                                        instruction <= prefetch_word;
                                        prefetch_valid <= 1'b0;
                                        control_state <= STATE_PHASE_EXECUTE;
                                    end else begin
                                        prefetch_valid <= 1'b0;
                                        control_state <= STATE_PHASE_FETCH;
                                    end
                                end
                            end
                            `RECON_PHASE_OP_BRANCH: begin
                                emit_trace(operation, cond_true);
                                phase_pc <= cond_true ?
                                    target_pc : phase_pc + 8'd1;
                                prefetch_valid <= 1'b0;
                                control_state <= STATE_PHASE_FETCH;
                            end
                            `RECON_PHASE_OP_COMPLETE: begin
                                emit_trace(operation, cond_true);
                                emit_completion(instr_terminal);
                            end
                            `RECON_PHASE_OP_RAISE_ERROR: begin
                                emit_trace(operation, cond_true);
                                emit_error(`RECON_ERROR_CLASS_NUMERIC,
                                    {4'd0, instr_terminal},
                                    phase_pc, 5'd0,
                                    {24'd0, phase_pc});
                            end
                            default: begin
                                emit_error(`RECON_ERROR_CLASS_CONTEXT,
                                    `RECON_CONTEXT_ERROR_PHASE_INSTRUCTION,
                                    phase_pc, 5'd0, DETAIL_OPERATION |
                                    {29'd0, operation});
                            end
                        endcase
                    end
                end

                default: begin
                    emit_error(`RECON_ERROR_CLASS_CONTEXT,
                               `RECON_CONTEXT_ERROR_ARRAY_CONTROL,
                               phase_pc, 5'd0,
                               {29'd0, control_state});
                end
            endcase
        end
    end

`ifdef FORMAL
    reg formal_past_valid;
    reg formal_outstanding_run;
    reg f_prev_wait_hold;
    reg [7:0] f_prev_phase_pc;

    always @(posedge clk) begin
        if (!rst_n) begin
            formal_past_valid <= 1'b0;
            formal_outstanding_run <= 1'b0;
            f_prev_wait_hold <= 1'b0;
            f_prev_phase_pc <= 8'd0;
        end else begin
            formal_past_valid <= 1'b1;
            assert(!(done_pulse && error_pulse));
            assert(!abort_pending || engine_busy);
            assert(!active_cfg_release ||
                   active_cfg_valid);
            assert(!array_launch_valid || phase_exec_state);
            if (phase_active)
                assert(active_cfg_valid);
            if (formal_past_valid && f_prev_wait_hold)
                assert(phase_pc == f_prev_phase_pc);
            if (formal_past_valid && (done_pulse || error_pulse))
                assert(formal_outstanding_run);
            if (start_request && control_state == STATE_IDLE)
                formal_outstanding_run <= 1'b1;
            if (done_pulse || error_pulse)
                formal_outstanding_run <= 1'b0;
            if (!engine_busy)
                assert(!cfg_start_valid &&
                       !phase_rd_en && !array_launch_valid);

            f_prev_wait_hold <= phase_exec_state &&
                (((operation == `RECON_PHASE_OP_WAIT_CONDITION) &&
                  !cond_true) ||
                 ((operation == `RECON_PHASE_OP_LAUNCH_ARRAY) &&
                  !array_launch_ready));
            f_prev_phase_pc <= phase_pc;
        end
    end
`endif
endmodule

`default_nettype wire
