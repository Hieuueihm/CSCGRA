`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_column_flow #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer COLUMN_W = `RECON_PHI_COLUMN_W,
    parameter integer ROW_W = `RECON_PHI_ROW_BLOCK_W,
    parameter integer TAG_W = `RECON_PHI_TAG_W,
    parameter integer MANTISSA_W = `RECON_PHI_SCALE_MANTISSA_W,
    parameter integer EXPONENT_W = `RECON_PHI_SCALE_EXPONENT_W
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire cycle_valid,
    input wire cycle_commit,
    input wire phi_start_fire,
    input wire phi_consume_context,
    input wire phi_stop_context,
    input wire phi_symbol_valid,
    input wire phi_symbol_fire,
    input wire phi_refill_active,
    input wire [2:0] phi_mode,
    input wire [COLUMN_W-1:0] phi_column,
    input wire [ROW_W-1:0] phi_row_block,
    input wire [8:0] measurement_count,
    input wire [6:0] work_count,
    input wire reduction_issue_context,
    input wire reduction_result_valid,
    input wire signed [ACC_W-1:0] reduction_result_data,
    input wire normalizer_input_ready,
    input wire normalizer_memory_mode,
    input wire phi_lane_normalize_active,
    input wire [MANTISSA_W-1:0] normalizer_mantissa,
    input wire [EXPONENT_W-1:0] normalizer_exponent,
    input wire normalized_candidate_fire,
    input wire signed [DATA_W-1:0] normalized_candidate_score,
    input wire normalized_candidate_saturated,
    input wire vector_candidate_mode,
    input wire vector_candidate_valid,
    input wire vector_candidate_fault,
    input wire signed [DATA_W-1:0] vector_candidate_score,
    input wire [COLUMN_W-1:0] vector_candidate_index,
    input wire dispatcher_candidate_ready,
    output wire reduction_result_ready,
    output wire reduction_accept,
    output wire reduction_column_available,
    output wire reduction_source_missing,
    output wire normalizer_request_valid,
    output wire signed [ACC_W-1:0] normalizer_request_data,
    output wire [TAG_W-1:0] normalizer_request_tag,
    output wire [MANTISSA_W-1:0] normalizer_request_mantissa,
    output wire [EXPONENT_W-1:0] normalizer_request_exponent,
    output wire normalizer_request_is_data18,
    output wire normalized_candidate_ready,
    output wire selected_candidate_valid,
    output wire signed [DATA_W-1:0] selected_candidate_score,
    output wire [COLUMN_W-1:0] selected_candidate_index,
    output wire selected_candidate_saturated,
    output wire candidate_release_event,
    output wire [COLUMN_W-1:0] candidate_release_column,
    output wire [ROW_W-1:0] completed_row_major_row_block,
    output wire order_error_now,
    output wire order_error
);
    localparam integer FIFO_DEPTH = 4;

    reg phi_column_open;
    reg completed_column_valid;
    reg [COLUMN_W-1:0] active_phi_column;
    reg [COLUMN_W-1:0] completed_phi_column;
    reg [ROW_W-1:0] expected_phi_row_block;
    reg [ROW_W-1:0] expected_row_major_row_block;
    reg [ROW_W-1:0] completed_row_major_row_block_reg;
    reg [6:0] row_major_item_count;
    reg row_major_stream_complete;
    reg phi_order_error;

    reg signed [DATA_W-1:0] col_score_q [0:FIFO_DEPTH-1];
    reg [COLUMN_W-1:0] col_index_q [0:FIFO_DEPTH-1];
    reg col_sat_q [0:FIFO_DEPTH-1];
    reg [2:0] col_q_count;
    reg [1:0] col_q_rd;
    reg [1:0] col_q_wr;

    reg [COLUMN_W-1:0] reduce_col_q [0:FIFO_DEPTH-1];
    reg [2:0] reduce_col_count;
    reg [1:0] reduce_col_rd;
    reg [1:0] reduce_col_wr;
    reg [COLUMN_W-1:0] normalizer_column;

    reg reduction_response_valid;
    reg signed [ACC_W-1:0] reduction_response_data;
    reg [TAG_W-1:0] reduction_response_tag;
    reg [MANTISSA_W-1:0] reduction_response_mantissa;
    reg [EXPONENT_W-1:0] reduction_response_exponent;
    reg reduction_response_is_data18;

    wire [3:0] active_row_block_count =
        ({1'b0, measurement_count} + 10'd31) >> 5;
    wire final_phi_row_block =
        ({1'b0, phi_row_block} + 4'd1) == active_row_block_count;
    wire row_major_item_final =
        ({1'b0, row_major_item_count} + 8'd1 == {1'b0, work_count});
    wire phi_metadata_error_now = !phi_refill_active &&
        (phi_mode != 3'd5) && cycle_valid && phi_consume_context &&
        phi_symbol_valid &&
        ((active_row_block_count == 0) ||
         (!phi_column_open &&
          ((phi_row_block != 0) || completed_column_valid)) ||
         (phi_column_open &&
          ((phi_column != active_phi_column) ||
           (phi_row_block != expected_phi_row_block))));
    wire row_major_metadata_error_now = (phi_mode == 3'd5) &&
        cycle_valid && phi_consume_context && phi_symbol_valid &&
        ((active_row_block_count == 0) || (work_count == 0) ||
         row_major_stream_complete ||
         (phi_row_block != expected_row_major_row_block));
    wire row_major_incomplete_stop = (phi_mode == 3'd5) &&
        cycle_valid && phi_stop_context && !row_major_stream_complete;

    wire [COLUMN_W-1:0] reduce_col_head =
        (reduce_col_count != 3'd0) ?
        reduce_col_q[reduce_col_rd] : completed_phi_column;
    assign reduction_column_available = (reduce_col_count != 3'd0) ||
        completed_column_valid;
    assign reduction_source_missing = reduction_issue_context &&
        !completed_column_valid && (reduce_col_count == 3'd0);
    assign reduction_accept = reduction_result_valid &&
        (normalizer_memory_mode || reduction_column_available);

    assign reduction_result_ready = !reduction_response_valid &&
        !phi_lane_normalize_active;
    assign normalizer_request_valid = reduction_response_valid ||
        (reduction_result_valid &&
         (normalizer_memory_mode || reduction_column_available));
    assign normalizer_request_data = reduction_response_valid ?
        reduction_response_data : reduction_result_data;
    assign normalizer_request_tag = reduction_response_valid ?
        reduction_response_tag : reduce_col_head[TAG_W-1:0];
    assign normalizer_request_mantissa = reduction_response_valid ?
        reduction_response_mantissa : normalizer_mantissa;
    assign normalizer_request_exponent = reduction_response_valid ?
        reduction_response_exponent : normalizer_exponent;
    assign normalizer_request_is_data18 = reduction_response_valid ?
        reduction_response_is_data18 : (phi_mode == 3'd0);

    assign normalized_candidate_ready = col_q_count != FIFO_DEPTH;
    wire normalized_candidate_valid = col_q_count != 3'd0;
    assign selected_candidate_valid = vector_candidate_valid ?
        !vector_candidate_fault : normalized_candidate_valid;
    assign selected_candidate_score = vector_candidate_valid ?
        vector_candidate_score : col_score_q[col_q_rd];
    assign selected_candidate_index = vector_candidate_valid ?
        vector_candidate_index : col_index_q[col_q_rd];
    assign selected_candidate_saturated = vector_candidate_valid ? 1'b0 :
        (normalized_candidate_valid && col_sat_q[col_q_rd]);
    assign candidate_release_event = dispatcher_candidate_ready &&
        !vector_candidate_valid && normalized_candidate_valid;
    assign candidate_release_column = selected_candidate_index;
    assign completed_row_major_row_block =
        completed_row_major_row_block_reg;
    assign order_error_now = phi_metadata_error_now ||
        row_major_metadata_error_now || row_major_incomplete_stop;
    assign order_error = phi_order_error;

    wire reduction_response_capture = reduction_result_valid &&
        !normalizer_input_ready;
    wire reduction_response_drain = reduction_response_valid &&
        normalizer_input_ready;
    wire reduce_column_push = reduction_issue_context && cycle_commit &&
        completed_column_valid &&
        ((reduce_col_count != FIFO_DEPTH) || reduction_accept);
    wire candidate_pop = candidate_release_event;

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            phi_column_open <= 1'b0;
            completed_column_valid <= 1'b0;
            active_phi_column <= {COLUMN_W{1'b0}};
            completed_phi_column <= {COLUMN_W{1'b0}};
            expected_phi_row_block <= {ROW_W{1'b0}};
            expected_row_major_row_block <= {ROW_W{1'b0}};
            completed_row_major_row_block_reg <= {ROW_W{1'b0}};
            row_major_item_count <= 7'd0;
            row_major_stream_complete <= 1'b0;
            phi_order_error <= 1'b0;
            col_q_count <= 3'd0;
            col_q_rd <= 2'd0;
            col_q_wr <= 2'd0;
            reduce_col_count <= 3'd0;
            reduce_col_rd <= 2'd0;
            reduce_col_wr <= 2'd0;
            normalizer_column <= {COLUMN_W{1'b0}};
            reduction_response_valid <= 1'b0;
            reduction_response_data <= {ACC_W{1'b0}};
            reduction_response_tag <= {TAG_W{1'b0}};
            reduction_response_mantissa <= {MANTISSA_W{1'b0}};
            reduction_response_exponent <= {EXPONENT_W{1'b0}};
            reduction_response_is_data18 <= 1'b0;
            col_score_q[0] <= {DATA_W{1'b0}};
            col_score_q[1] <= {DATA_W{1'b0}};
            col_score_q[2] <= {DATA_W{1'b0}};
            col_score_q[3] <= {DATA_W{1'b0}};
            col_index_q[0] <= {COLUMN_W{1'b0}};
            col_index_q[1] <= {COLUMN_W{1'b0}};
            col_index_q[2] <= {COLUMN_W{1'b0}};
            col_index_q[3] <= {COLUMN_W{1'b0}};
            col_sat_q[0] <= 1'b0;
            col_sat_q[1] <= 1'b0;
            col_sat_q[2] <= 1'b0;
            col_sat_q[3] <= 1'b0;
            reduce_col_q[0] <= {COLUMN_W{1'b0}};
            reduce_col_q[1] <= {COLUMN_W{1'b0}};
            reduce_col_q[2] <= {COLUMN_W{1'b0}};
            reduce_col_q[3] <= {COLUMN_W{1'b0}};
        end else begin
            if (phi_start_fire) begin
                expected_row_major_row_block <= {ROW_W{1'b0}};
                completed_row_major_row_block_reg <= {ROW_W{1'b0}};
                row_major_item_count <= 7'd0;
                row_major_stream_complete <= 1'b0;
            end
            if (phi_symbol_fire && (phi_mode == 3'd5)) begin
                if ((active_row_block_count == 0) || (work_count == 0) ||
                    row_major_stream_complete ||
                    (phi_row_block != expected_row_major_row_block))
                    phi_order_error <= 1'b1;
                if (row_major_item_final) begin
                    row_major_item_count <= 7'd0;
                    completed_row_major_row_block_reg <= phi_row_block;
                    if (final_phi_row_block)
                        row_major_stream_complete <= 1'b1;
                    else
                        expected_row_major_row_block <=
                            expected_row_major_row_block + 1'b1;
                end else begin
                    row_major_item_count <= row_major_item_count + 1'b1;
                end
            end
            if (phi_symbol_fire && !phi_refill_active &&
                (phi_mode != 3'd5)) begin
                if (active_row_block_count == 0)
                    phi_order_error <= 1'b1;
                if (!phi_column_open) begin
                    if (phi_row_block != 0 || completed_column_valid)
                        phi_order_error <= 1'b1;
                    active_phi_column <= phi_column;
                    expected_phi_row_block <= {{(ROW_W-1){1'b0}}, 1'b1};
                    phi_column_open <= !final_phi_row_block;
                end else begin
                    if ((phi_column != active_phi_column) ||
                        (phi_row_block != expected_phi_row_block))
                        phi_order_error <= 1'b1;
                    expected_phi_row_block <= expected_phi_row_block + 1'b1;
                    if (final_phi_row_block)
                        phi_column_open <= 1'b0;
                end
                if (final_phi_row_block) begin
                    completed_column_valid <= 1'b1;
                    completed_phi_column <= phi_column;
                end
            end
            if (reduce_column_push) begin
                reduce_col_q[reduce_col_wr] <= completed_phi_column;
                reduce_col_wr <= reduce_col_wr + 1'b1;
                completed_column_valid <= 1'b0;
            end
            if (reduction_accept) begin
                normalizer_column <= reduce_col_head;
                if (reduce_col_count != 3'd0)
                    reduce_col_rd <= reduce_col_rd + 1'b1;
            end
            if (reduce_column_push) begin
                if (!(reduction_accept && (reduce_col_count != 3'd0)))
                    reduce_col_count <= reduce_col_count + 1'b1;
            end else if (reduction_accept && (reduce_col_count != 3'd0)) begin
                reduce_col_count <= reduce_col_count - 1'b1;
            end
            if (normalized_candidate_fire) begin
                col_score_q[col_q_wr] <= normalized_candidate_score;
                col_index_q[col_q_wr] <= normalizer_column;
                col_sat_q[col_q_wr] <= normalized_candidate_saturated;
                col_q_wr <= col_q_wr + 1'b1;
            end
            if (candidate_pop)
                col_q_rd <= col_q_rd + 1'b1;
            if (normalized_candidate_fire) begin
                if (!candidate_pop)
                    col_q_count <= col_q_count + 1'b1;
            end else if (candidate_pop) begin
                col_q_count <= col_q_count - 1'b1;
            end
            if (reduction_response_capture) begin
                reduction_response_valid <= 1'b1;
                reduction_response_data <= reduction_result_data;
                reduction_response_tag <= reduce_col_head[TAG_W-1:0];
                reduction_response_mantissa <= normalizer_mantissa;
                reduction_response_exponent <= normalizer_exponent;
                reduction_response_is_data18 <= phi_mode == 3'd0;
            end else if (reduction_response_drain) begin
                reduction_response_valid <= 1'b0;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid) begin
            if (reduction_result_valid)
                assert(reduction_result_ready && reduction_column_available);
            if (phi_symbol_fire && phi_column_open)
                assert(phi_column == active_phi_column);
            if (phi_symbol_fire && (phi_mode == 3'd5))
                assert(phi_row_block == expected_row_major_row_block);
        end
    end
`endif
endmodule

`default_nettype wire
