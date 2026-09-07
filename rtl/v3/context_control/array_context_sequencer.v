`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"

// Shared-PC array sequencer.  One 16-word spatial context is broadcast to the
// corresponding tiles in both 4x4 clusters.  A context is architecturally
// visible only on cycle_commit.
module array_context_sequencer (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         launch_valid,
    output wire         launch_ready,
    input  wire [7:0]   entry_pc,
    input  wire [3:0]   event_id,
    input  wire         abort_pending,
    input  wire [7:0]   predicate_values,
    input  wire         image_ok,
    input  wire [8:0]   image_count,

    input  wire [8:0]   measurement_count,
    input  wire [10:0]  signal_length,
    input  wire [6:0]   sparsity,
    input  wire [15:0]  outer_limit,
    input  wire [7:0]   refine_limit,
    input  wire [15:0]  run_param0,
    input  wire [15:0]  run_param1,

    input  wire         stream_in_ready,
    input  wire         stream_out_ready,
    input  wire         resource_req_ready,
    input  wire         resource_rsp_valid,

    output wire         ctx_rd_en,
    output wire [7:0]   ctx_rd_addr,
    input  wire         ctx_rd_resp_valid,
    input  wire         ctx_rd_valid,
    input  wire [7:0]   ctx_rd_pc,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] ctx_tiles,
    input  wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] ctx_array,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] ctx_stream,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] ctx_resource,

    output wire         cycle_valid,
    output wire         cycle_commit,
    output wire         cycle_stalled,
    output wire [7:0]   array_pc,
    output wire [1:0]   cluster_mask,
    output wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    output wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx,
    output wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,
    output wire [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx,
    output reg          execution_active,

    output reg          done_valid,
    input  wire         done_ready,
    output reg  [3:0]   done_event_id,
    output reg          done_aborted,

    output reg          fault_valid,
    input  wire         fault_ready,
    output reg  [7:0]   fault_code,
    output reg  [7:0]   fault_pc,
    output reg  [31:0]  fault_detail,

    output reg  [31:0]  commit_count,
    output reg  [31:0]  guaranteed_count,
    output reg  [31:0]  elastic_count,
    output reg  [31:0]  stall_count
);
    reg [7:0] pc;
    reg [3:0] active_event;
    reg [15:0] loop_count [0:3];
    integer loop_id;

    wire launch_fire = launch_valid && launch_ready;
    wire entry_in_range =
        ({1'b0, entry_pc} < image_count);
    wire launch_ok = image_ok &&
                                 entry_in_range;
    wire pc_match = ctx_rd_pc == pc;
    wire ctx_available = execution_active &&
        ctx_rd_resp_valid && ctx_rd_valid &&
        pc_match;
    wire fetch_fault = execution_active &&
        ctx_rd_resp_valid &&
        (!ctx_rd_valid || !pc_match);

    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W-1:0] next_mode =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_W-1:0] decoded_next_pc =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_LOOP_COUNTER_SELECT_W-1:0] loop_sel =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_LOOP_COUNTER_SELECT_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_LOOP_COUNTER_SELECT_W];
    wire loop_reset =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_LOOP_COUNTER_RESET_LSB];
    wire loop_inc =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_LOOP_COUNTER_INCREMENT_LSB];
    wire [`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W-1:0] limit_sel =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_IMMEDIATE_W-1:0] limit_imm =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_IMMEDIATE_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_IMMEDIATE_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_W-1:0] pred_sel =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_W];
    wire pred_inv =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_PREDICATE_INVERT_LSB];
    wire [`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_W-1:0] decoded_cluster_mask =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_W];
    wire routine_done =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_ROUTINE_DONE_LSB];
    wire safe_abort_point =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_SAFE_ABORT_POINT_LSB];
    wire guaranteed_commit =
        ctx_array[`RECON_ARRAY_CONTROL_FIELD_GUARANTEED_COMMIT_LSB];
    wire stream_vector_active =
        ctx_stream[`RECON_STREAM_FIELD_VECTOR_READ_A_ENABLE_LSB] ||
        ctx_stream[`RECON_STREAM_FIELD_VECTOR_READ_B_ENABLE_LSB] ||
        ctx_stream[`RECON_STREAM_FIELD_VECTOR_WRITE_ENABLE_LSB];
    wire [`RECON_STREAM_FIELD_PHI_COMMAND_W-1:0] phi_command =
        ctx_stream[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                   `RECON_STREAM_FIELD_PHI_COMMAND_W];
    wire stream_stall_on_input =
        ctx_stream[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB];
    wire stream_stall_on_output =
        ctx_stream[`RECON_STREAM_FIELD_STALL_ON_OUTPUT_LSB];
    wire resource_wait_for_ready =
        ctx_resource[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire resource_wait_for_result =
        ctx_resource[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];

    wire pred_value = predicate_values[pred_sel];
    wire pred_true = pred_value ^ pred_inv;
    wire wait_stall =
        (next_mode == `RECON_NEXT_PC_MODE_WAIT_EVENT) &&
        !pred_true;
    wire input_stall = stream_stall_on_input &&
                              !stream_in_ready;
    wire output_stall = stream_stall_on_output &&
                               !stream_out_ready;
    wire resource_req_stall = resource_wait_for_ready &&
                                !resource_req_ready;
    wire resource_rsp_stall = resource_wait_for_result &&
                                 !resource_rsp_valid;
    wire stall = wait_stall || input_stall ||
        output_stall || resource_req_stall || resource_rsp_stall;
    wire safe_abort = ctx_available && abort_pending &&
                               safe_abort_point;

    reg [15:0] loop_limit;
    reg [7:0] next_pc;
    wire [15:0] loop_value = loop_count[loop_sel];
    wire [15:0] loop_base = loop_reset ? 16'd0 : loop_value;
    wire [15:0] loop_next = loop_base + (loop_inc ? 16'd1 : 16'd0);
    wire return_to_phase = routine_done ||
        (next_mode == `RECON_NEXT_PC_MODE_RETURN_TO_PHASE);

    assign launch_ready = !execution_active && !done_valid && !fault_valid;
    assign array_pc = pc;
    assign cluster_mask = decoded_cluster_mask;
    assign tile_ctx = ctx_tiles;
    assign array_ctx = ctx_array;
    assign stream_ctx = ctx_stream;
    assign resource_ctx = ctx_resource;
    assign cycle_valid = ctx_available &&
                               !done_valid && !fault_valid;
    assign cycle_stalled = cycle_valid && !guaranteed_commit &&
                                 stall && !safe_abort;
    assign cycle_commit = cycle_valid && !safe_abort &&
        (guaranteed_commit || !stall);

    // Predictive synchronous-RAM address generation gives one committed
    // context per clock after the initial read latency.
    assign ctx_rd_en =
        (launch_fire && launch_ok) || execution_active;
    assign ctx_rd_addr = launch_fire ? entry_pc :
        (cycle_commit && !return_to_phase ?
         next_pc : pc);

    always @* begin
        case (limit_sel)
            `RECON_LOOP_LIMIT_IMMEDIATE:
                loop_limit = {8'd0, limit_imm};
            `RECON_LOOP_LIMIT_MEASUREMENT_COUNT:
                loop_limit = {7'd0, measurement_count};
            `RECON_LOOP_LIMIT_SIGNAL_LENGTH:
                loop_limit = {5'd0, signal_length};
            `RECON_LOOP_LIMIT_SPARSITY_LEVEL:
                loop_limit = {9'd0, sparsity};
            `RECON_LOOP_LIMIT_TWICE_SPARSITY:
                loop_limit = {8'd0, sparsity, 1'b0};
            `RECON_LOOP_LIMIT_THREE_TIMES_SPARSITY:
                loop_limit = {9'd0, sparsity} +
                                      {8'd0, sparsity, 1'b0};
            `RECON_LOOP_LIMIT_OUTER_ITERATION_LIMIT:
                loop_limit = outer_limit;
            `RECON_LOOP_LIMIT_REFINEMENT_ITERATION_LIMIT:
                loop_limit = {8'd0, refine_limit};
            `RECON_LOOP_LIMIT_RUN_PARAMETER_0:
                loop_limit = run_param0;
            `RECON_LOOP_LIMIT_RUN_PARAMETER_1:
                loop_limit = run_param1;
            `RECON_LOOP_LIMIT_MEASUREMENT_STRIPES_16:
                loop_limit = (({7'd0, measurement_count} + 16'd31) >> 5) << 1;
            `RECON_LOOP_LIMIT_ACTIVE_WORK_STRIPES_16:
                loop_limit = (run_param1 + 16'd15) >> 4;
            `RECON_LOOP_LIMIT_SIGNAL_LENGTH_STRIPES_16:
                loop_limit = ({5'd0, signal_length} + 16'd15) >> 4;
            `RECON_LOOP_LIMIT_SIGNAL_LENGTH_MINUS_IMMEDIATE:
                loop_limit = ({5'd0, signal_length} > {8'd0, limit_imm}) ?
                    ({5'd0, signal_length} - {8'd0, limit_imm}) : 16'd0;
            default: loop_limit = 16'd0;
        endcase

        next_pc = pc + 8'd1;
        case (next_mode)
            `RECON_NEXT_PC_MODE_SEQUENTIAL:
                next_pc = pc + 8'd1;
            `RECON_NEXT_PC_MODE_JUMP:
                next_pc = decoded_next_pc;
            `RECON_NEXT_PC_MODE_COUNTED_LOOP:
                next_pc = (loop_next <
                                    loop_limit) ?
                    decoded_next_pc : pc + 8'd1;
            `RECON_NEXT_PC_MODE_PREDICATE_SELECT:
                next_pc = pred_true ?
                    decoded_next_pc : pc + 8'd1;
            `RECON_NEXT_PC_MODE_WAIT_EVENT:
                next_pc = decoded_next_pc;
            `RECON_NEXT_PC_MODE_RETURN_TO_PHASE:
                next_pc = pc;
            default:
                next_pc = pc;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pc <= 8'd0;
            active_event <= 4'd0;
            for (loop_id = 0; loop_id < 4; loop_id = loop_id + 1)
                loop_count[loop_id] <= 16'd0;
            execution_active <= 1'b0;
            done_valid <= 1'b0;
            done_event_id <= 4'd0;
            done_aborted <= 1'b0;
            fault_valid <= 1'b0;
            fault_code <= 8'd0;
            fault_pc <= 8'd0;
            fault_detail <= 32'd0;
            commit_count <= 32'd0;
            guaranteed_count <= 32'd0;
            elastic_count <= 32'd0;
            stall_count <= 32'd0;
        end else begin
            if (done_valid && done_ready)
                done_valid <= 1'b0;
            if (fault_valid && fault_ready)
                fault_valid <= 1'b0;

            if (launch_fire) begin
                pc <= entry_pc;
                active_event <= event_id;
                for (loop_id = 0; loop_id < 4; loop_id = loop_id + 1)
                    loop_count[loop_id] <= 16'd0;
                execution_active <= launch_ok;
                commit_count <= 32'd0;
                guaranteed_count <= 32'd0;
                elastic_count <= 32'd0;
                stall_count <= 32'd0;
                if (!image_ok) begin
                    fault_valid <= 1'b1;
                    fault_code <= `RECON_CONTEXT_ERROR_IMAGE_WRITE;
                    fault_pc <= entry_pc;
                    fault_detail <= {8'hfe, entry_pc, 16'd0};
                end else if (!entry_in_range) begin
                    fault_valid <= 1'b1;
                    fault_code <= `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
                    fault_pc <= entry_pc;
                    fault_detail <= {8'hff, entry_pc,
                                     7'd0, 1'b0, entry_pc};
                end
            end

            if (execution_active && ctx_rd_resp_valid) begin
                if (fetch_fault) begin
                    execution_active <= 1'b0;
                    fault_valid <= 1'b1;
                    fault_code <= `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
                    fault_pc <= pc;
                    fault_detail <= {8'hff, ctx_rd_pc,
                                     7'd0, ctx_rd_valid, pc};
                end else if (safe_abort) begin
                    execution_active <= 1'b0;
                    done_valid <= 1'b1;
                    done_event_id <= active_event;
                    done_aborted <= 1'b1;
                end else if (cycle_commit) begin
                    commit_count <= commit_count + 32'd1;
                    if (guaranteed_commit)
                        guaranteed_count <=
                            guaranteed_count + 32'd1;
                    else
                        elastic_count <= elastic_count + 32'd1;

                    if (loop_reset || loop_inc)
                        loop_count[loop_sel] <= loop_next;

                    if (return_to_phase) begin
                        execution_active <= 1'b0;
                        done_valid <= 1'b1;
                        done_event_id <= active_event;
                        done_aborted <= 1'b0;
                    end else begin
                        pc <= next_pc;
                    end
                end else if (cycle_stalled) begin
                    stall_count <= stall_count + 32'd1;
                end
            end
        end
    end

`ifdef FORMAL
    wire formal_violation;
    wire [7:0] formal_violation_code;
    wire [31:0] formal_violation_detail;
    context_reservation_guard u_formal_guard (
        .tile_ctx(ctx_tiles),
        .array_ctx(ctx_array),
        .stream_ctx(ctx_stream),
        .resource_ctx(ctx_resource),
        .violation(formal_violation),
        .violation_code(formal_violation_code),
        .violation_detail(formal_violation_detail)
    );

    reg formal_past_valid;
    reg f_prev_stall;
    reg f_prev_done_wait;
    reg f_prev_fault_wait;
    reg [7:0] f_prev_pc;
    reg [15:0] f_prev_loop [0:3];
    integer formal_loop_id;
    reg [3:0] f_prev_done_event;
    reg f_prev_done_abort;
    reg [7:0] f_prev_fault_code;
    reg [7:0] f_prev_fault_pc;
    reg [31:0] f_prev_fault_detail;

    always @(posedge clk) begin
        if (!rst_n) begin
            formal_past_valid <= 1'b0;
            f_prev_stall <= 1'b0;
            f_prev_done_wait <= 1'b0;
            f_prev_fault_wait <= 1'b0;
        end else begin
            if (ctx_available && image_ok)
                assert(!formal_violation);
            if (execution_active) begin
                assert(image_ok);
                assert({1'b0, pc} < image_count);
            end
            formal_past_valid <= 1'b1;
            if (formal_past_valid && f_prev_stall) begin
                assert(pc == f_prev_pc);
                for (formal_loop_id = 0; formal_loop_id < 4;
                        formal_loop_id = formal_loop_id + 1)
                    assert(loop_count[formal_loop_id] ==
                           f_prev_loop[formal_loop_id]);
            end
            if (formal_past_valid && f_prev_done_wait) begin
                assert(done_valid);
                assert(done_event_id == f_prev_done_event);
                assert(done_aborted == f_prev_done_abort);
            end
            if (formal_past_valid && f_prev_fault_wait) begin
                assert(fault_valid);
                assert(fault_code == f_prev_fault_code);
                assert(fault_pc == f_prev_fault_pc);
                assert(fault_detail == f_prev_fault_detail);
            end
            assert(!(done_valid && fault_valid));
            assert(!cycle_commit || cycle_valid);
            if (cycle_valid && guaranteed_commit &&
                    !safe_abort)
                assert(cycle_commit);
            if (cycle_valid && guaranteed_commit) begin
                assert(next_mode != `RECON_NEXT_PC_MODE_WAIT_EVENT);
                assert(!stream_vector_active);
                assert(phi_command != `RECON_PHI_COMMAND_CONSUME);
                assert(!stream_stall_on_input && !stream_stall_on_output);
                assert(!resource_wait_for_ready && !resource_wait_for_result);
            end

            f_prev_stall <= cycle_stalled;
            f_prev_pc <= pc;
            for (formal_loop_id = 0; formal_loop_id < 4;
                    formal_loop_id = formal_loop_id + 1)
                f_prev_loop[formal_loop_id] <=
                    loop_count[formal_loop_id];
            f_prev_done_wait <= done_valid && !done_ready;
            f_prev_done_event <= done_event_id;
            f_prev_done_abort <= done_aborted;
            f_prev_fault_wait <= fault_valid && !fault_ready;
            f_prev_fault_code <= fault_code;
            f_prev_fault_pc <= fault_pc;
            f_prev_fault_detail <= fault_detail;
        end
    end
`endif
endmodule

`default_nettype wire
