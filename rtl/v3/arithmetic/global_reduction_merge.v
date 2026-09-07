`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// The global half contains merge, accumulator and two elastic output registers.
// Together with the two cluster levels, a request accepted in cycle C is
// observable at the interface in cycle C+5; initiation interval remains one.
module global_reduction_merge #(
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer INDEX_W = 10,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         cluster0_valid,
    output wire                         cluster0_ready,
    input  wire [4:0]                   cluster0_operation,
    input  wire [TAG_W-1:0]             cluster0_tag,
    input  wire signed [ACC_W-1:0]      cluster0_data,
    input  wire [INDEX_W-1:0]           cluster0_index,
    input  wire                         cluster0_any,
    input  wire                         cluster0_clear_before,
    input  wire                         cluster0_accumulate,
    input  wire                         cluster0_emit_result,
    input  wire                         cluster0_fault,

    input  wire                         cluster1_valid,
    output wire                         cluster1_ready,
    input  wire [4:0]                   cluster1_operation,
    input  wire [TAG_W-1:0]             cluster1_tag,
    input  wire signed [ACC_W-1:0]      cluster1_data,
    input  wire [INDEX_W-1:0]           cluster1_index,
    input  wire                         cluster1_any,
    input  wire                         cluster1_clear_before,
    input  wire                         cluster1_accumulate,
    input  wire                         cluster1_emit_result,
    input  wire                         cluster1_fault,

    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire [4:0]                   rsp_operation,
    output wire [TAG_W-1:0]             rsp_tag,
    output wire signed [ACC_W-1:0]      rsp_data,
    output wire [INDEX_W-1:0]           rsp_index,
    output wire                         rsp_fault
);
    function [ACC_W-1:0] magnitude;
        input signed [ACC_W-1:0] value;
        begin
            magnitude = value[ACC_W-1] ? (~value + {{ACC_W-1{1'b0}},1'b1}) : value;
        end
    endfunction

    reg stage1_valid;
    reg [4:0] stage1_operation;
    reg [TAG_W-1:0] stage1_tag;
    reg signed [ACC_W-1:0] stage1_data;
    reg [INDEX_W-1:0] stage1_index;
    reg stage1_any;
    reg stage1_clear_before;
    reg stage1_accumulate;
    reg stage1_emit_result;
    reg stage1_fault;

    reg stage2_valid;
    reg [4:0] stage2_operation;
    reg [TAG_W-1:0] stage2_tag;
    reg signed [ACC_W-1:0] stage2_data;
    reg [INDEX_W-1:0] stage2_index;
    reg stage2_emit_result;
    reg stage2_fault;

    reg stage3_valid;
    reg [4:0] stage3_operation;
    reg [TAG_W-1:0] stage3_tag;
    reg signed [ACC_W-1:0] stage3_data;
    reg [INDEX_W-1:0] stage3_index;
    reg stage3_fault;

    reg stage4_valid;
    reg [4:0] stage4_operation;
    reg [TAG_W-1:0] stage4_tag;
    reg signed [ACC_W-1:0] stage4_data;
    reg [INDEX_W-1:0] stage4_index;
    reg stage4_fault;

    reg accumulator_valid;
    reg signed [ACC_W-1:0] accumulator_data;
    reg [INDEX_W-1:0] accumulator_index;

    wire response_slot_ready = !stage4_valid;
    wire advance = response_slot_ready || rsp_ready;
    wire joined_valid = cluster0_valid && cluster1_valid;
    wire joined_accept = joined_valid && response_slot_ready;
    assign cluster0_ready = response_slot_ready && cluster1_valid;
    assign cluster1_ready = response_slot_ready && cluster0_valid;

    wire controls_match =
        (cluster0_operation == cluster1_operation) &&
        (cluster0_tag == cluster1_tag) &&
        (cluster0_clear_before == cluster1_clear_before) &&
        (cluster0_accumulate == cluster1_accumulate) &&
        (cluster0_emit_result == cluster1_emit_result);

    reg signed [ACC_W-1:0] merged_data;
    reg [INDEX_W-1:0] merged_index;
    reg merged_any;
    always @* begin
        merged_data = {ACC_W{1'b0}};
        merged_index = {INDEX_W{1'b0}};
        merged_any = cluster0_any || cluster1_any;
        if (cluster0_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
            if (!cluster0_any) begin
                merged_data = cluster1_data;
                merged_index = cluster1_index;
            end else if (!cluster1_any ||
                         (magnitude(cluster0_data) > magnitude(cluster1_data)) ||
                         ((magnitude(cluster0_data) == magnitude(cluster1_data)) &&
                          (cluster0_index <= cluster1_index))) begin
                merged_data = cluster0_data;
                merged_index = cluster0_index;
            end else begin
                merged_data = cluster1_data;
                merged_index = cluster1_index;
            end
        end else begin
            merged_data = cluster0_data + cluster1_data;
        end
    end

    reg signed [ACC_W-1:0] accumulated_data;
    reg [INDEX_W-1:0] accumulated_index;
    always @* begin
        accumulated_data = stage1_data;
        accumulated_index = stage1_index;
        if (stage1_accumulate && accumulator_valid && !stage1_clear_before) begin
            if (stage1_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
                if ((magnitude(accumulator_data) > magnitude(stage1_data)) ||
                    ((magnitude(accumulator_data) == magnitude(stage1_data)) &&
                     (accumulator_index <= stage1_index))) begin
                    accumulated_data = accumulator_data;
                    accumulated_index = accumulator_index;
                end
            end else begin
                accumulated_data = accumulator_data + stage1_data;
            end
        end
    end

    assign rsp_valid = stage4_valid;
    assign rsp_operation = stage4_operation;
    assign rsp_tag = stage4_tag;
    assign rsp_data = stage4_data;
    assign rsp_index = stage4_index;
    assign rsp_fault = stage4_fault;

    always @(posedge clk) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            stage3_valid <= 1'b0;
            stage4_valid <= 1'b0;
            accumulator_valid <= 1'b0;
        end else if (advance) begin
            stage4_valid <= stage3_valid;
            if (stage3_valid) begin
                stage4_operation <= stage3_operation;
                stage4_tag <= stage3_tag;
                stage4_data <= stage3_data;
                stage4_index <= stage3_index;
                stage4_fault <= stage3_fault;
            end

            stage3_valid <= stage2_valid && stage2_emit_result;
            if (stage2_valid) begin
                stage3_operation <= stage2_operation;
                stage3_tag <= stage2_tag;
                stage3_data <= stage2_data;
                stage3_index <= stage2_index;
                stage3_fault <= stage2_fault;
            end

            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                stage2_operation <= stage1_operation;
                stage2_tag <= stage1_tag;
                stage2_data <= accumulated_data;
                stage2_index <= accumulated_index;
                stage2_emit_result <= stage1_emit_result;
                stage2_fault <= stage1_fault || !stage1_any;
                accumulator_data <= accumulated_data;
                accumulator_index <= accumulated_index;
                accumulator_valid <= stage1_any && !stage1_fault;
            end

            stage1_valid <= joined_accept;
            if (joined_accept) begin
                stage1_operation <= cluster0_operation;
                stage1_tag <= cluster0_tag;
                stage1_data <= merged_data;
                stage1_index <= merged_index;
                stage1_any <= merged_any;
                stage1_clear_before <= cluster0_clear_before;
                stage1_accumulate <= cluster0_accumulate;
                stage1_emit_result <= cluster0_emit_result;
                stage1_fault <= cluster0_fault || cluster1_fault || !controls_match;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [TAG_W-1:0] f_tag;
    reg signed [ACC_W-1:0] f_data;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled) begin
            assert(rsp_valid);
            assert(rsp_tag == f_tag);
            assert(rsp_data == f_data);
        end
        if (cluster0_valid && cluster0_ready)
            assert(cluster1_valid && cluster1_ready);
        f_stalled <= rsp_valid && !rsp_ready;
        f_tag <= rsp_tag;
        f_data <= rsp_data;
    end
`endif
endmodule

`default_nettype wire
