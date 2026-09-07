`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Two registered levels reduce the sixteen PE results of one 4x4 cluster.
// SUM and NORM_SQ consume already-formed A62 partials. MAX_ABS compares the
// magnitude and keeps the lower global index on a tie.
module cluster_reduction_unit #(
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer INDEX_W = 10,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] req_operation,
    input  wire [TAG_W-1:0]             req_tag,
    input  wire [`RECON_PE_ROWS-1:0]    req_lane_mask,
    input  wire [`RECON_PE_PER_CLUSTER-1:0] req_lane_valid,
    input  wire [`RECON_PE_PER_CLUSTER*ACC_W-1:0] req_lane_data,
    input  wire [`RECON_PE_PER_CLUSTER*INDEX_W-1:0] req_lane_index,
    input  wire                         req_clear_before,
    input  wire                         req_accumulate,
    input  wire                         req_emit_result,

    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] rsp_operation,
    output wire [TAG_W-1:0]             rsp_tag,
    output wire signed [ACC_W-1:0]      rsp_data,
    output wire [INDEX_W-1:0]           rsp_index,
    output wire                         rsp_any,
    output wire                         rsp_clear_before,
    output wire                         rsp_accumulate,
    output wire                         rsp_emit_result,
    output wire                         rsp_fault
);
    localparam integer PAIR_COUNT = `RECON_PE_PER_CLUSTER / 2;
    localparam integer CLUSTER_PAIR_COUNT = `RECON_PE_ROWS / 2;

    integer row;
    integer lane;
    integer pair;

    function [ACC_W-1:0] magnitude;
        input signed [ACC_W-1:0] value;
        begin
            magnitude = value[ACC_W-1] ? (~value + {{ACC_W-1{1'b0}},1'b1}) : value;
        end
    endfunction

    function candidate_right_wins;
        input left_any;
        input signed [ACC_W-1:0] left_data;
        input [INDEX_W-1:0] left_index;
        input right_any;
        input signed [ACC_W-1:0] right_data;
        input [INDEX_W-1:0] right_index;
        begin
            candidate_right_wins = right_any &&
                (!left_any ||
                 (magnitude(right_data) > magnitude(left_data)) ||
                 ((magnitude(right_data) == magnitude(left_data)) &&
                  (right_index < left_index)));
        end
    endfunction

    reg signed [ACC_W-1:0] lane_data_comb [0:`RECON_PE_PER_CLUSTER-1];
    reg [INDEX_W-1:0] lane_index_comb [0:`RECON_PE_PER_CLUSTER-1];
    reg lane_any_comb [0:`RECON_PE_PER_CLUSTER-1];
    reg signed [ACC_W-1:0] pair_data_comb [0:PAIR_COUNT-1];
    reg [INDEX_W-1:0] pair_index_comb [0:PAIR_COUNT-1];
    reg pair_any_comb [0:PAIR_COUNT-1];
    reg signed [ACC_W-1:0] row_data_comb [0:`RECON_PE_ROWS-1];
    reg [INDEX_W-1:0] row_index_comb [0:`RECON_PE_ROWS-1];
    reg row_any_comb [0:`RECON_PE_ROWS-1];
    reg row_fault_comb;

    always @* begin
        row_fault_comb = !((req_operation == `RECON_RESOURCE_OP_REDUCE_SUM) ||
                           (req_operation == `RECON_RESOURCE_OP_REDUCE_NORM_SQ) ||
                           (req_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS));

        for (lane = 0; lane < `RECON_PE_PER_CLUSTER; lane = lane + 1) begin
            lane_data_comb[lane] = req_lane_data[lane*ACC_W +: ACC_W];
            lane_index_comb[lane] = req_lane_index[lane*INDEX_W +: INDEX_W];
            lane_any_comb[lane] =
                req_lane_mask[lane/`RECON_PE_COLUMNS] && req_lane_valid[lane];
        end

        // Explicit pair tree prevents the source-order loop from becoming a
        // four-deep adder/comparator chain in Vivado.
        for (pair = 0; pair < PAIR_COUNT; pair = pair + 1) begin
            pair_any_comb[pair] = lane_any_comb[pair*2] || lane_any_comb[pair*2+1];
            if (req_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
                if (candidate_right_wins(
                        lane_any_comb[pair*2], lane_data_comb[pair*2],
                        lane_index_comb[pair*2], lane_any_comb[pair*2+1],
                        lane_data_comb[pair*2+1], lane_index_comb[pair*2+1])) begin
                    pair_data_comb[pair] = lane_data_comb[pair*2+1];
                    pair_index_comb[pair] = lane_index_comb[pair*2+1];
                end else begin
                    pair_data_comb[pair] = lane_data_comb[pair*2];
                    pair_index_comb[pair] = lane_index_comb[pair*2];
                end
            end else begin
                pair_data_comb[pair] =
                    (lane_any_comb[pair*2] ? lane_data_comb[pair*2] : {ACC_W{1'b0}}) +
                    (lane_any_comb[pair*2+1] ? lane_data_comb[pair*2+1] : {ACC_W{1'b0}});
                pair_index_comb[pair] = lane_any_comb[pair*2] ?
                    lane_index_comb[pair*2] : lane_index_comb[pair*2+1];
            end
        end

        for (row = 0; row < `RECON_PE_ROWS; row = row + 1) begin
            row_any_comb[row] = pair_any_comb[row*2] || pair_any_comb[row*2+1];
            if (req_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
                if (candidate_right_wins(
                        pair_any_comb[row*2], pair_data_comb[row*2],
                        pair_index_comb[row*2], pair_any_comb[row*2+1],
                        pair_data_comb[row*2+1], pair_index_comb[row*2+1])) begin
                    row_data_comb[row] = pair_data_comb[row*2+1];
                    row_index_comb[row] = pair_index_comb[row*2+1];
                end else begin
                    row_data_comb[row] = pair_data_comb[row*2];
                    row_index_comb[row] = pair_index_comb[row*2];
                end
            end else begin
                row_data_comb[row] = pair_data_comb[row*2] + pair_data_comb[row*2+1];
                row_index_comb[row] = pair_any_comb[row*2] ?
                    pair_index_comb[row*2] : pair_index_comb[row*2+1];
            end
        end
    end

    reg stage1_valid;
    reg [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] stage1_operation;
    reg [TAG_W-1:0] stage1_tag;
    reg signed [ACC_W-1:0] stage1_data [0:`RECON_PE_ROWS-1];
    reg [INDEX_W-1:0] stage1_index [0:`RECON_PE_ROWS-1];
    reg [`RECON_PE_ROWS-1:0] stage1_any;
    reg stage1_clear_before;
    reg stage1_accumulate;
    reg stage1_emit_result;
    reg stage1_fault;

    reg signed [ACC_W-1:0] cluster_data_comb;
    reg [INDEX_W-1:0] cluster_index_comb;
    reg cluster_any_comb;
    reg signed [ACC_W-1:0] cluster_pair_data [0:CLUSTER_PAIR_COUNT-1];
    reg [INDEX_W-1:0] cluster_pair_index [0:CLUSTER_PAIR_COUNT-1];
    reg cluster_pair_any [0:CLUSTER_PAIR_COUNT-1];
    integer reduce_pair;
    always @* begin
        for (reduce_pair = 0; reduce_pair < CLUSTER_PAIR_COUNT;
                reduce_pair = reduce_pair + 1) begin
            cluster_pair_any[reduce_pair] =
                stage1_any[reduce_pair*2] || stage1_any[reduce_pair*2+1];
            if (stage1_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
                if (candidate_right_wins(
                        stage1_any[reduce_pair*2], stage1_data[reduce_pair*2],
                        stage1_index[reduce_pair*2], stage1_any[reduce_pair*2+1],
                        stage1_data[reduce_pair*2+1], stage1_index[reduce_pair*2+1])) begin
                    cluster_pair_data[reduce_pair] = stage1_data[reduce_pair*2+1];
                    cluster_pair_index[reduce_pair] = stage1_index[reduce_pair*2+1];
                end else begin
                    cluster_pair_data[reduce_pair] = stage1_data[reduce_pair*2];
                    cluster_pair_index[reduce_pair] = stage1_index[reduce_pair*2];
                end
            end else begin
                cluster_pair_data[reduce_pair] =
                    (stage1_any[reduce_pair*2] ? stage1_data[reduce_pair*2] : {ACC_W{1'b0}}) +
                    (stage1_any[reduce_pair*2+1] ? stage1_data[reduce_pair*2+1] : {ACC_W{1'b0}});
                cluster_pair_index[reduce_pair] = stage1_any[reduce_pair*2] ?
                    stage1_index[reduce_pair*2] : stage1_index[reduce_pair*2+1];
            end
        end

        cluster_any_comb = cluster_pair_any[0] || cluster_pair_any[1];
        if (stage1_operation == `RECON_RESOURCE_OP_REDUCE_MAX_ABS) begin
            if (candidate_right_wins(
                    cluster_pair_any[0], cluster_pair_data[0], cluster_pair_index[0],
                    cluster_pair_any[1], cluster_pair_data[1], cluster_pair_index[1])) begin
                cluster_data_comb = cluster_pair_data[1];
                cluster_index_comb = cluster_pair_index[1];
            end else begin
                cluster_data_comb = cluster_pair_data[0];
                cluster_index_comb = cluster_pair_index[0];
            end
        end else begin
            cluster_data_comb = cluster_pair_data[0] + cluster_pair_data[1];
            cluster_index_comb = cluster_pair_any[0] ?
                cluster_pair_index[0] : cluster_pair_index[1];
        end
    end

    reg stage2_valid;
    reg [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] stage2_operation;
    reg [TAG_W-1:0] stage2_tag;
    reg signed [ACC_W-1:0] stage2_data;
    reg [INDEX_W-1:0] stage2_index;
    reg stage2_any;
    reg stage2_clear_before;
    reg stage2_accumulate;
    reg stage2_emit_result;
    reg stage2_fault;

    wire advance = !stage2_valid || rsp_ready;
    assign req_ready = advance;
    assign rsp_valid = stage2_valid;
    assign rsp_operation = stage2_operation;
    assign rsp_tag = stage2_tag;
    assign rsp_data = stage2_data;
    assign rsp_index = stage2_index;
    assign rsp_any = stage2_any;
    assign rsp_clear_before = stage2_clear_before;
    assign rsp_accumulate = stage2_accumulate;
    assign rsp_emit_result = stage2_emit_result;
    assign rsp_fault = stage2_fault;

    always @(posedge clk) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
        end else if (advance) begin
            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                stage2_operation <= stage1_operation;
                stage2_tag <= stage1_tag;
                stage2_data <= cluster_data_comb;
                stage2_index <= cluster_index_comb;
                stage2_any <= cluster_any_comb;
                stage2_clear_before <= stage1_clear_before;
                stage2_accumulate <= stage1_accumulate;
                stage2_emit_result <= stage1_emit_result;
                stage2_fault <= stage1_fault;
            end

            stage1_valid <= req_valid;
            if (req_valid) begin
                stage1_operation <= req_operation;
                stage1_tag <= req_tag;
                for (row = 0; row < `RECON_PE_ROWS; row = row + 1) begin
                    stage1_data[row] <= row_data_comb[row];
                    stage1_index[row] <= row_index_comb[row];
                    stage1_any[row] <= row_any_comb[row];
                end
                stage1_clear_before <= req_clear_before;
                stage1_accumulate <= req_accumulate;
                stage1_emit_result <= req_emit_result;
                stage1_fault <= row_fault_comb;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] f_operation;
    reg [TAG_W-1:0] f_tag;
    reg signed [ACC_W-1:0] f_data;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled) begin
            assert(rsp_valid);
            assert(rsp_operation == f_operation);
            assert(rsp_tag == f_tag);
            assert(rsp_data == f_data);
        end
        if (req_valid && req_ready)
            assert(req_lane_mask != {`RECON_PE_ROWS{1'b0}});
        f_stalled <= rsp_valid && !rsp_ready;
        f_operation <= rsp_operation;
        f_tag <= rsp_tag;
        f_data <= rsp_data;
    end
`endif
endmodule

`default_nettype wire
