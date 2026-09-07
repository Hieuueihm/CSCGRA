`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module proxy_candidate_collector #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer CANDIDATE_MAX = 64,
    parameter integer SUPPORT_MAX = 96
)(
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire selection_epoch_start,
    input  wire [6:0] candidate_limit,
    input  wire candidate_store_enable,
    input  wire candidate_valid,
    output wire candidate_ready,
    input  wire signed [DATA_W-1:0] candidate_value,
    input  wire [INDEX_W-1:0] candidate_index,
    output reg  candidate_store_valid,
    input  wire candidate_store_ready,
    output reg  [5:0] candidate_store_slot,
    output reg  [INDEX_W-1:0] candidate_store_column,
    input  wire gradient_valid,
    input  wire [6:0] gradient_slot,
    input  wire signed [DATA_W-1:0] gradient_value,
    output wire [6:0] candidate_count,
    output wire [CANDIDATE_MAX*DATA_W-1:0] candidate_values,
    output wire [CANDIDATE_MAX*INDEX_W-1:0] candidate_indices,
    output wire [CANDIDATE_MAX*6-1:0] candidate_symbol_slots,
    output wire [SUPPORT_MAX*DATA_W-1:0] support_gradients,
    output wire [SUPPORT_MAX-1:0] support_gradient_valid
);
    reg [6:0] retained_count;
    reg [6:0] active_candidate_limit;
    reg [(1<<INDEX_W)-1:0] seen_indices;
    reg signed [DATA_W-1:0] value_state [0:CANDIDATE_MAX-1];
    reg [INDEX_W-1:0] index_state [0:CANDIDATE_MAX-1];
    reg [5:0] symbol_slot_state [0:CANDIDATE_MAX-1];
    reg signed [DATA_W-1:0] gradient_state [0:SUPPORT_MAX-1];
    reg [SUPPORT_MAX-1:0] gradient_valid_state;

    function [DATA_W-1:0] magnitude;
        input signed [DATA_W-1:0] value;
        begin magnitude = value[DATA_W-1] ? (~value + 1'b1) : value; end
    endfunction

    function candidate_better;
        input signed [DATA_W-1:0] left_value;
        input [INDEX_W-1:0] left_index;
        input signed [DATA_W-1:0] right_value;
        input [INDEX_W-1:0] right_index;
        reg [DATA_W-1:0] left_magnitude;
        reg [DATA_W-1:0] right_magnitude;
        begin
            left_magnitude = magnitude(left_value);
            right_magnitude = magnitude(right_value);
            candidate_better = (left_magnitude > right_magnitude) ||
                ((left_magnitude == right_magnitude) && (left_index < right_index));
        end
    endfunction

    wire event_advance = !candidate_store_enable ||
                         !candidate_store_valid || candidate_store_ready;
    assign candidate_ready = event_advance;
    wire candidate_fire = candidate_valid && candidate_ready;
    wire [6:0] effective_candidate_limit = selection_epoch_start ?
        candidate_limit : active_candidate_limit;
    wire limit_valid = (effective_candidate_limit != 0) &&
        (effective_candidate_limit <= CANDIDATE_MAX);
    wire duplicate = seen_indices[candidate_index];

    wire [CANDIDATE_MAX-1:0] occupied_mask;
    wire [CANDIDATE_MAX-1:0] better_mask;
    wire [CANDIDATE_MAX-1:0] first_better_mask;
    wire [CANDIDATE_MAX-1:0] append_mask;
    wire [CANDIDATE_MAX-1:0] insert_mask;
    wire [CANDIDATE_MAX-1:0] shift_mask;
    genvar compare_index;
    generate
        for (compare_index = 0; compare_index < CANDIDATE_MAX; compare_index = compare_index + 1) begin : g_compare
            assign occupied_mask[compare_index] = compare_index < retained_count;
            assign better_mask[compare_index] = occupied_mask[compare_index] &&
                candidate_better(candidate_value, candidate_index,
                                 value_state[compare_index], index_state[compare_index]);
            assign append_mask[compare_index] =
                                                !(|better_mask) &&
                                                (retained_count < effective_candidate_limit) &&
                                                (retained_count == compare_index);
            if (compare_index == 0) begin : g_first_shift
                assign first_better_mask[compare_index] = better_mask[compare_index];
                assign shift_mask[compare_index] = 1'b0;
            end else begin : g_later_shift
                assign first_better_mask[compare_index] =
                    better_mask[compare_index] && !better_mask[compare_index-1];
                assign shift_mask[compare_index] =
                    (compare_index < effective_candidate_limit) &&
                    (compare_index <= retained_count) &&
                    better_mask[compare_index-1];
            end
        end
    endgenerate
    assign insert_mask = first_better_mask | append_mask;
    wire insertion_found = |better_mask;
    wire qualifies = limit_valid && !duplicate &&
        ((retained_count < effective_candidate_limit) || insertion_found);
    wire [5:0] insertion_symbol_slot =
        (retained_count < effective_candidate_limit) ? retained_count[5:0] :
        symbol_slot_state[effective_candidate_limit-1'b1];

    genvar output_index;
    generate
        for (output_index = 0; output_index < CANDIDATE_MAX; output_index = output_index + 1) begin : g_outputs
            assign candidate_values[output_index*DATA_W +: DATA_W] =
                value_state[output_index];
            assign candidate_indices[output_index*INDEX_W +: INDEX_W] =
                index_state[output_index];
            assign candidate_symbol_slots[output_index*6 +: 6] =
                symbol_slot_state[output_index];
        end
        for (output_index = 0; output_index < SUPPORT_MAX; output_index = output_index + 1) begin : g_gradients
            assign support_gradients[output_index*DATA_W +: DATA_W] = gradient_state[output_index];
        end
    endgenerate
    assign candidate_count = retained_count;
    assign support_gradient_valid = gradient_valid_state;

    integer rank_index;
    always @(posedge clk) begin
        if (!rst_n || routine_start || selection_epoch_start) begin
            retained_count <= 0;
            active_candidate_limit <= candidate_limit;
            seen_indices <= 0;
            gradient_valid_state <= 0;
            candidate_store_valid <= 0;
            candidate_store_slot <= 0;
            candidate_store_column <= 0;
            if (selection_epoch_start && candidate_fire && limit_valid) begin
                retained_count <= 1;
                seen_indices[candidate_index] <= 1'b1;
                value_state[0] <= candidate_value;
                index_state[0] <= candidate_index;
                symbol_slot_state[0] <= 0;
                if (candidate_store_enable) begin
                    candidate_store_valid <= 1;
                    candidate_store_slot <= 0;
                    candidate_store_column <= candidate_index;
                end
            end
            if (selection_epoch_start && gradient_valid &&
                    (gradient_slot < SUPPORT_MAX)) begin
                gradient_state[gradient_slot] <= gradient_value;
                gradient_valid_state[gradient_slot] <= 1'b1;
            end
        end else begin
            if (candidate_store_valid && candidate_store_ready)
                candidate_store_valid <= 0;
            if (gradient_valid && (gradient_slot < SUPPORT_MAX)) begin
                gradient_state[gradient_slot] <= gradient_value;
                gradient_valid_state[gradient_slot] <= 1'b1;
            end
            if (candidate_fire) begin
                seen_indices[candidate_index] <= 1'b1;
                if (qualifies) begin
                    if (insert_mask[0]) begin
                        value_state[0] <= candidate_value;
                        index_state[0] <= candidate_index;
                        symbol_slot_state[0] <= insertion_symbol_slot;
                    end
                    for (rank_index = 1; rank_index < CANDIDATE_MAX; rank_index = rank_index + 1) begin
                        if (insert_mask[rank_index]) begin
                            value_state[rank_index] <= candidate_value;
                            index_state[rank_index] <= candidate_index;
                            symbol_slot_state[rank_index] <= insertion_symbol_slot;
                        end else if (shift_mask[rank_index]) begin
                            value_state[rank_index] <= value_state[rank_index-1];
                            index_state[rank_index] <= index_state[rank_index-1];
                            symbol_slot_state[rank_index] <= symbol_slot_state[rank_index-1];
                        end
                    end
                    if (retained_count < effective_candidate_limit)
                        retained_count <= retained_count + 1'b1;
                    if (candidate_store_enable) begin
                        candidate_store_valid <= 1;
                        candidate_store_slot <= insertion_symbol_slot;
                        candidate_store_column <= candidate_index;
                    end
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [5:0] f_store_slot;
    reg [INDEX_W-1:0] f_store_column;
    integer f_rank;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        if (rst_n && f_past_valid) begin
            assert(retained_count <= CANDIDATE_MAX);
            if (limit_valid && !selection_epoch_start)
                assert(retained_count <= effective_candidate_limit);
            if (f_stalled) begin
                assert(candidate_store_valid);
                assert(candidate_store_slot == f_store_slot);
                assert(candidate_store_column == f_store_column);
            end
            for (f_rank = 0; f_rank < CANDIDATE_MAX-1; f_rank = f_rank + 1)
                if (f_rank + 1 < retained_count)
                    assert(candidate_better(value_state[f_rank], index_state[f_rank],
                                            value_state[f_rank+1], index_state[f_rank+1]));
        end
        f_past_valid <= 1;
        f_stalled <= candidate_store_valid && !candidate_store_ready;
        f_store_slot <= candidate_store_slot;
        f_store_column <= candidate_store_column;
    end
`endif
endmodule

module support_gradient_store #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer SUPPORT_MAX = 96
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clear,
    input  wire gradient_valid,
    input  wire [6:0] gradient_slot,
    input  wire signed [DATA_W-1:0] gradient_value,
    output wire [SUPPORT_MAX*DATA_W-1:0] support_gradients,
    output wire [SUPPORT_MAX-1:0] support_gradient_valid
);
    reg signed [DATA_W-1:0] gradient_state [0:SUPPORT_MAX-1];
    reg [SUPPORT_MAX-1:0] gradient_valid_state;

    genvar output_index;
    generate
        for (output_index = 0; output_index < SUPPORT_MAX;
             output_index = output_index + 1) begin : g_outputs
            assign support_gradients[output_index*DATA_W +: DATA_W] =
                gradient_state[output_index];
        end
    endgenerate
    assign support_gradient_valid = gradient_valid_state;

    always @(posedge clk) begin
        if (!rst_n)
            gradient_valid_state <= 0;
        else if (clear) begin
            gradient_valid_state <= 0;
            if (gradient_valid && (gradient_slot < SUPPORT_MAX)) begin
                gradient_state[gradient_slot] <= gradient_value;
                gradient_valid_state[gradient_slot] <= 1'b1;
            end
        end else if (gradient_valid && (gradient_slot < SUPPORT_MAX)) begin
            gradient_state[gradient_slot] <= gradient_value;
            gradient_valid_state[gradient_slot] <= 1'b1;
        end
    end
endmodule

`default_nettype wire
