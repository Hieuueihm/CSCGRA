`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module topk_selection_unit #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer K_MAX = `RECON_K_MAX,
    parameter integer CANDIDATE_MAX = 64,
    parameter integer TAG_W = 3,
    parameter integer EXPOSE_RETAINED_VECTOR = 1
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             routine_start,
    input  wire                             selection_epoch_start,
    input  wire [5:0]                       selection_k,
    input  wire [6:0]                       candidate_limit,
    input  wire                             candidate_store_enable,
    input  wire                             cycle_valid,
    output wire                             cycle_ready,
    input  wire                             cycle_commit,
    input  wire [4:0]                       operation,
    input  wire [TAG_W-1:0]                 request_tag,
    input  wire signed [DATA_W-1:0]         candidate_score,
    input  wire [INDEX_W-1:0]               candidate_index,
    input  wire                             candidate_exclude,
    output reg                              response_valid,
    input  wire                             response_ready,
    output reg  [4:0]                       response_operation,
    output reg  [TAG_W-1:0]                 response_tag,
    output reg                              response_fault,
    output reg  [5:0]                       response_count,
    output wire [K_MAX*DATA_W-1:0]          result_scores,
    output wire [K_MAX*INDEX_W-1:0]         result_indices,
    output wire [6:0]                       retained_candidate_count,
    output wire [CANDIDATE_MAX*DATA_W-1:0]  retained_candidate_values,
    output wire [CANDIDATE_MAX*INDEX_W-1:0] retained_candidate_indices,
    output wire [CANDIDATE_MAX*6-1:0]       retained_candidate_symbol_slots,
    input  wire [6:0]                       retained_candidate_read_slot,
    output wire                             retained_candidate_read_valid,
    output wire signed [DATA_W-1:0]         retained_candidate_read_value,
    output wire [INDEX_W-1:0]               retained_candidate_read_index,
    output wire [5:0]                       retained_candidate_read_symbol_slot,
    output reg  [6:0]                       retained_candidate_read_sorted_slot,
    output reg                              candidate_store_valid,
    input  wire                             candidate_store_ready,
    output reg  [5:0]                       candidate_store_slot,
    output reg  [INDEX_W-1:0]               candidate_store_column,
    input  wire                             candidate_symbol_valid,
    input  wire [127:0]                     candidate_symbol_payload,
    output wire                             candidate_symbol_ready
);
    reg [5:0] active_k;
    reg [6:0] active_candidate_limit;
    reg [6:0] retained_count;
    reg [(1<<INDEX_W)-1:0] seen_indices;
    reg signed [DATA_W-1:0] score_state [0:CANDIDATE_MAX-1];
    reg [INDEX_W-1:0] index_state [0:CANDIDATE_MAX-1];
    reg [5:0] symbol_slot_state [0:CANDIDATE_MAX-1];

    reg push_stage0_valid;
    reg [TAG_W-1:0] push_stage0_tag;
    reg push_stage0_fault;
    reg [5:0] push_stage0_count;
    reg push_stage1_valid;
    reg [TAG_W-1:0] push_stage1_tag;
    reg push_stage1_fault;
    reg [5:0] push_stage1_count;
    reg terminal_pending_valid;
    reg [4:0] terminal_pending_operation;
    reg [TAG_W-1:0] terminal_pending_tag;
    reg terminal_pending_fault;
    reg [5:0] terminal_pending_count;

    function [DATA_W-1:0] magnitude;
        input signed [DATA_W-1:0] value;
        begin magnitude = value[DATA_W-1] ? (~value + 1'b1) : value; end
    endfunction

    function candidate_better;
        input signed [DATA_W-1:0] left_score;
        input [INDEX_W-1:0] left_index;
        input signed [DATA_W-1:0] right_score;
        input [INDEX_W-1:0] right_index;
        reg [DATA_W-1:0] left_magnitude;
        reg [DATA_W-1:0] right_magnitude;
        begin
            left_magnitude = magnitude(left_score);
            right_magnitude = magnitude(right_score);
            candidate_better = (left_magnitude > right_magnitude) ||
                ((left_magnitude == right_magnitude) &&
                 (left_index < right_index));
        end
    endfunction

    wire response_advance = !response_valid || response_ready;
    wire store_advance = !candidate_store_valid || candidate_store_ready;
    wire push_operation = operation == `RECON_RESOURCE_OP_TOPK_PUSH;
    wire commit_operation = operation == `RECON_RESOURCE_OP_TOPK_COMMIT;
    wire push_ready = response_advance && store_advance &&
        !terminal_pending_valid;
    wire terminal_ready = !response_valid && !push_stage0_valid &&
        !push_stage1_valid && !terminal_pending_valid && store_advance;
    assign cycle_ready = push_operation ? push_ready : terminal_ready;
    wire request_accept = cycle_valid && cycle_commit && cycle_ready;
    wire candidate_fire = request_accept && push_operation;
    wire active_k_valid = (active_k != 0) && (active_k <= K_MAX);
    wire active_candidate_limit_valid = (active_candidate_limit != 0) &&
        (active_candidate_limit <= CANDIDATE_MAX);
    wire duplicate = seen_indices[candidate_index] || candidate_exclude;

    assign candidate_symbol_ready = 1'b0;
    wire unused_candidate_symbol = candidate_symbol_valid ||
        (|candidate_symbol_payload);

    wire [CANDIDATE_MAX-1:0] occupied_mask;
    wire [CANDIDATE_MAX-1:0] better_mask;
    wire [CANDIDATE_MAX-1:0] first_better_mask;
    wire [CANDIDATE_MAX-1:0] insert_mask;
    wire [CANDIDATE_MAX-1:0] shift_mask;
    genvar compare_slot;
    generate
        for (compare_slot = 0; compare_slot < CANDIDATE_MAX;
             compare_slot = compare_slot + 1) begin : compare_candidates
            assign occupied_mask[compare_slot] = compare_slot < retained_count;
            assign better_mask[compare_slot] = occupied_mask[compare_slot] &&
                candidate_better(candidate_score, candidate_index,
                    score_state[compare_slot], index_state[compare_slot]);
            if (compare_slot == 0) begin : first_position
                assign first_better_mask[compare_slot] = better_mask[compare_slot];
                assign shift_mask[compare_slot] = 1'b0;
            end else begin : later_position
                assign first_better_mask[compare_slot] =
                    better_mask[compare_slot] && !better_mask[compare_slot-1];
                assign shift_mask[compare_slot] =
                    (compare_slot < active_candidate_limit) &&
                    (compare_slot <= retained_count) &&
                    better_mask[compare_slot-1];
            end
            assign insert_mask[compare_slot] = first_better_mask[compare_slot] ||
                (!(|better_mask) &&
                 (retained_count < active_candidate_limit) &&
                 (retained_count == compare_slot));
            if (EXPOSE_RETAINED_VECTOR != 0) begin : retained_vector_outputs
                assign retained_candidate_values[compare_slot*DATA_W +: DATA_W] =
                    score_state[compare_slot];
                assign retained_candidate_indices[compare_slot*INDEX_W +: INDEX_W] =
                    index_state[compare_slot];
                assign retained_candidate_symbol_slots[compare_slot*6 +: 6] =
                    symbol_slot_state[compare_slot];
            end else begin : no_retained_vector_outputs
                assign retained_candidate_values[compare_slot*DATA_W +: DATA_W] =
                    {DATA_W{1'b0}};
                assign retained_candidate_indices[compare_slot*INDEX_W +: INDEX_W] =
                    {INDEX_W{1'b0}};
                assign retained_candidate_symbol_slots[compare_slot*6 +: 6] =
                    6'd0;
            end
            if (compare_slot < K_MAX) begin : topk_outputs
                assign result_scores[compare_slot*DATA_W +: DATA_W] =
                    score_state[compare_slot];
                assign result_indices[compare_slot*INDEX_W +: INDEX_W] =
                    index_state[compare_slot];
            end
        end
    endgenerate

    wire [6:0] retained_candidate_read_safe_slot =
        retained_candidate_read_valid ? retained_candidate_read_slot : 7'd0;
    assign retained_candidate_read_valid =
        (retained_candidate_read_slot < retained_count) &&
        (retained_candidate_read_slot < CANDIDATE_MAX);
    assign retained_candidate_read_value =
        score_state[retained_candidate_read_safe_slot];
    assign retained_candidate_read_index =
        index_state[retained_candidate_read_safe_slot];
    assign retained_candidate_read_symbol_slot =
        symbol_slot_state[retained_candidate_read_safe_slot];

    integer retained_rank_index;
    always @* begin
        retained_candidate_read_sorted_slot = 7'd0;
        if (retained_candidate_read_valid)
            for (retained_rank_index = 0; retained_rank_index < K_MAX;
                 retained_rank_index = retained_rank_index + 1)
                if ((retained_rank_index < retained_count) &&
                    (index_state[retained_rank_index] <
                     retained_candidate_read_index))
                    retained_candidate_read_sorted_slot =
                        retained_candidate_read_sorted_slot + 1'b1;
    end

    reg [5:0] insertion_position;
    reg insertion_position_found;
    integer position_index;
    always @* begin
        insertion_position = retained_count[5:0];
        insertion_position_found = 1'b0;
        for (position_index = 0; position_index < CANDIDATE_MAX;
             position_index = position_index + 1)
            if (!insertion_position_found && first_better_mask[position_index]) begin
                insertion_position = position_index[5:0];
                insertion_position_found = 1'b1;
            end
    end

    wire state_has_space = retained_count < active_candidate_limit;
    wire candidate_enters = candidate_fire && active_candidate_limit_valid &&
        !duplicate &&
        (state_has_space || (insertion_position < active_candidate_limit));
    wire [6:0] updated_retained_count = state_has_space ?
        retained_count + 1'b1 : retained_count;
    wire [5:0] current_topk_count = (retained_count < active_k) ?
        retained_count[5:0] : active_k;
    wire [5:0] updated_topk_count = (updated_retained_count < active_k) ?
        updated_retained_count[5:0] : active_k;
    wire [5:0] insertion_symbol_slot = state_has_space ?
        retained_count[5:0] :
        symbol_slot_state[active_candidate_limit-1'b1];
    assign retained_candidate_count = retained_count;

    integer state_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            active_k <= 0;
            active_candidate_limit <= 0;
            retained_count <= 0;
            seen_indices <= 0;
            push_stage0_valid <= 0;
            push_stage1_valid <= 0;
            terminal_pending_valid <= 0;
            response_valid <= 0;
            response_operation <= `RECON_RESOURCE_OP_NOP;
            response_tag <= 0;
            response_fault <= 0;
            response_count <= 0;
            candidate_store_valid <= 0;
            candidate_store_slot <= 0;
            candidate_store_column <= 0;
            for (state_index = 0; state_index < CANDIDATE_MAX;
                 state_index = state_index + 1) begin
                score_state[state_index] <= 0;
                index_state[state_index] <= 0;
                symbol_slot_state[state_index] <= 0;
            end
        end else if (routine_start || selection_epoch_start) begin
            active_k <= selection_k;
            active_candidate_limit <= candidate_limit;
            retained_count <= 0;
            seen_indices <= 0;
            push_stage0_valid <= request_accept && push_operation;
            push_stage0_tag <= request_tag;
            push_stage0_fault <= (selection_k == 0) || (selection_k > K_MAX) ||
                (candidate_limit == 0) || (candidate_limit > CANDIDATE_MAX);
            push_stage0_count <= (request_accept && push_operation &&
                !candidate_exclude && (selection_k != 0) &&
                (candidate_limit != 0)) ? 6'd1 : 6'd0;
            push_stage1_valid <= 0;
            terminal_pending_valid <= 0;
            response_valid <= 0;
            response_operation <= `RECON_RESOURCE_OP_NOP;
            response_tag <= 0;
            response_fault <= 0;
            response_count <= 0;
            candidate_store_valid <= 0;
            candidate_store_slot <= 0;
            candidate_store_column <= 0;
            for (state_index = 0; state_index < CANDIDATE_MAX;
                 state_index = state_index + 1) begin
                score_state[state_index] <= 0;
                index_state[state_index] <= 0;
                symbol_slot_state[state_index] <= 0;
            end
            if (request_accept && push_operation && !candidate_exclude &&
                (selection_k != 0) && (selection_k <= K_MAX) &&
                (candidate_limit != 0) &&
                (candidate_limit <= CANDIDATE_MAX)) begin
                retained_count <= 1;
                seen_indices[candidate_index] <= 1'b1;
                score_state[0] <= candidate_score;
                index_state[0] <= candidate_index;
                symbol_slot_state[0] <= 0;
                if (candidate_store_enable) begin
                    candidate_store_valid <= 1;
                    candidate_store_slot <= 0;
                    candidate_store_column <= candidate_index;
                end
            end
        end else begin
            if (candidate_store_valid && candidate_store_ready)
                candidate_store_valid <= 0;
            if (response_advance) begin
                response_valid <= 0;
                response_fault <= 0;
                push_stage1_valid <= push_stage0_valid;
                push_stage1_tag <= push_stage0_tag;
                push_stage1_fault <= push_stage0_fault;
                push_stage1_count <= push_stage0_count;
                push_stage0_valid <= 0;
                terminal_pending_valid <= 0;
                if (push_stage1_valid) begin
                    response_valid <= 1;
                    response_operation <= `RECON_RESOURCE_OP_TOPK_PUSH;
                    response_tag <= push_stage1_tag;
                    response_fault <= push_stage1_fault;
                    response_count <= push_stage1_count;
                end else if (terminal_pending_valid) begin
                    response_valid <= 1;
                    response_operation <= terminal_pending_operation;
                    response_tag <= terminal_pending_tag;
                    response_fault <= terminal_pending_fault;
                    response_count <= terminal_pending_count;
                end
            end

            if (candidate_fire) begin
                push_stage0_valid <= 1;
                push_stage0_tag <= request_tag;
                push_stage0_fault <= !active_k_valid ||
                    !active_candidate_limit_valid;
                push_stage0_count <= candidate_enters ?
                    updated_topk_count : current_topk_count;
                if (active_candidate_limit_valid && !candidate_exclude)
                    seen_indices[candidate_index] <= 1'b1;
                if (candidate_enters) begin
                    retained_count <= updated_retained_count;
                    for (state_index = 0; state_index < CANDIDATE_MAX;
                         state_index = state_index + 1) begin
                        if (insert_mask[state_index]) begin
                            score_state[state_index] <= candidate_score;
                            index_state[state_index] <= candidate_index;
                            symbol_slot_state[state_index] <= insertion_symbol_slot;
                        end else if (shift_mask[state_index]) begin
                            score_state[state_index] <= score_state[state_index-1];
                            index_state[state_index] <= index_state[state_index-1];
                            symbol_slot_state[state_index] <=
                                symbol_slot_state[state_index-1];
                        end
                    end
                    if (candidate_store_enable) begin
                        candidate_store_valid <= 1;
                        candidate_store_slot <= insertion_symbol_slot;
                        candidate_store_column <= candidate_index;
                    end
                end
            end else if (request_accept) begin
                terminal_pending_valid <= 1;
                terminal_pending_operation <= operation;
                terminal_pending_tag <= request_tag;
                terminal_pending_fault <= !commit_operation || !active_k_valid ||
                    !active_candidate_limit_valid;
                terminal_pending_count <= current_topk_count;
            end
        end
    end

`ifdef FORMAL
    integer formal_rank;
    always @(posedge clk) begin
        if (rst_n) begin
            assert(retained_count <= CANDIDATE_MAX);
            assert(!candidate_symbol_ready);
            for (formal_rank = 0; formal_rank < CANDIDATE_MAX-1;
                 formal_rank = formal_rank + 1)
                if (formal_rank + 1 < retained_count)
                    assert(candidate_better(score_state[formal_rank],
                        index_state[formal_rank], score_state[formal_rank+1],
                        index_state[formal_rank+1]));
        end
    end
`endif

    wire unused_ok = unused_candidate_symbol;
endmodule

`default_nettype wire
