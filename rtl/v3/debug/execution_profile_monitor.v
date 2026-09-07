`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module execution_profile_monitor (
    input  wire clk,
    input  wire rst_n,
    input  wire run_start,
    input  wire engine_busy,
    input  wire phase_active,
    input  wire execution_active,
    input  wire cycle_valid,
    input  wire cycle_commit,
    input  wire cycle_stalled,
    input  wire [`RECON_CLUSTER_COUNT-1:0] cluster_mask,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0]
        tile_ctx,
    input  wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0]
        predicate_values,
    input  wire stream_input_ready,
    input  wire stream_output_ready,
    input  wire resource_req_ready,
    input  wire resource_rsp_valid,
    output reg  [63:0] total_cycles,
    output reg  [63:0] phase_cycles,
    output reg  [63:0] execution_cycles,
    output reg  [63:0] array_commit_cycles,
    output reg  [63:0] array_stall_cycles,
    output reg  [63:0] useful_pe_cycles,
    output reg  [63:0] useful_pe_slots,
    output reg  [63:0] resource_stall_cycles
);
    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W-1:0] next_mode =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_W-1:0]
        predicate_select =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_PREDICATE_SELECT_W];
    wire predicate_invert =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_PREDICATE_INVERT_LSB];
    wire predicate_true = predicate_values[predicate_select] ^
        predicate_invert;
    wire wait_event_stalled =
        (next_mode == `RECON_NEXT_PC_MODE_WAIT_EVENT) && !predicate_true;
    wire stream_input_stalled =
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB] &&
        !stream_input_ready;
    wire stream_output_stalled =
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_OUTPUT_LSB] &&
        !stream_output_ready;
    wire resource_wait_for_ready =
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire resource_wait_for_result =
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire resource_stalled = cycle_stalled && !wait_event_stalled &&
        !stream_input_stalled && !stream_output_stalled &&
        ((resource_wait_for_ready && !resource_req_ready) ||
         (resource_wait_for_result && !resource_rsp_valid));

    reg [5:0] useful_slot_increment;
    integer tile_index;
    always @* begin
        useful_slot_increment = 6'd0;
        for (tile_index = 0; tile_index < `RECON_PE_PER_CLUSTER;
                tile_index = tile_index + 1) begin
            if (tile_ctx[
                    tile_index*`RECON_TILE_CONTEXT_W +
                    `RECON_TILE_FIELD_OPERATION_LSB +:
                    `RECON_TILE_FIELD_OPERATION_W] != `RECON_TILE_OP_NOP) begin
                if (cluster_mask[0])
                    useful_slot_increment = useful_slot_increment + 6'd1;
                if (cluster_mask[1])
                    useful_slot_increment = useful_slot_increment + 6'd1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles <= 64'd0;
            phase_cycles <= 64'd0;
            execution_cycles <= 64'd0;
            array_commit_cycles <= 64'd0;
            array_stall_cycles <= 64'd0;
            useful_pe_cycles <= 64'd0;
            useful_pe_slots <= 64'd0;
            resource_stall_cycles <= 64'd0;
        end else if (run_start) begin
            total_cycles <= 64'd0;
            phase_cycles <= 64'd0;
            execution_cycles <= 64'd0;
            array_commit_cycles <= 64'd0;
            array_stall_cycles <= 64'd0;
            useful_pe_cycles <= 64'd0;
            useful_pe_slots <= 64'd0;
            resource_stall_cycles <= 64'd0;
        end else begin
            if (engine_busy)
                total_cycles <= total_cycles + 64'd1;
            if (engine_busy && phase_active)
                phase_cycles <= phase_cycles + 64'd1;
            if (engine_busy && execution_active)
                execution_cycles <= execution_cycles + 64'd1;
            if (engine_busy && cycle_valid && cycle_commit) begin
                array_commit_cycles <= array_commit_cycles + 64'd1;
                if (useful_slot_increment != 0) begin
                    useful_pe_cycles <= useful_pe_cycles + 64'd1;
                    useful_pe_slots <= useful_pe_slots +
                        {{58{1'b0}}, useful_slot_increment};
                end
            end
            if (engine_busy && cycle_stalled)
                array_stall_cycles <= array_stall_cycles + 64'd1;
            if (engine_busy && resource_stalled)
                resource_stall_cycles <= resource_stall_cycles + 64'd1;
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert(!(cycle_commit && cycle_stalled));
            assert(!cycle_commit || cycle_valid);
            assert(!cycle_stalled || cycle_valid);
        end
    end
`endif
endmodule

`default_nettype wire
