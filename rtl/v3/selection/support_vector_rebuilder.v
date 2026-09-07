`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module support_vector_rebuilder #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer LANES = 16,
    parameter integer WORK_MAX = 96,
    parameter integer SELECT_MAX = `RECON_K_MAX
)(
    input  wire [2:0] rebuild_mode,
    input  wire [INDEX_W:0] stripe_base,
    input  wire [INDEX_W:0] signal_length,
    input  wire [6:0] support_count,
    input  wire [5:0] selected_count,
    input  wire [SELECT_MAX*INDEX_W-1:0] selected_indices,
    input  wire [WORK_MAX*INDEX_W-1:0] support_indices,
    input  wire [WORK_MAX*DATA_W-1:0] support_coefficients,
    input  wire support_coefficient_stripe_valid,
    input  wire [LANES*DATA_W-1:0] support_coefficient_stripe,
    input  wire [WORK_MAX*DATA_W-1:0] support_gradients,
    input  wire [WORK_MAX-1:0] support_gradient_valid,
    input  wire [LANES*DATA_W-1:0] dense_input,
    output wire [LANES*DATA_W-1:0] rebuilt_output
);
    localparam integer LANE_INDEX_W = 4;
    wire [SELECT_MAX*LANES-1:0] selected_lane_match;
    wire [SELECT_MAX*LANES-1:0] support_lane_match;

    genvar selected_slot;
    generate
        for (selected_slot = 0; selected_slot < SELECT_MAX;
             selected_slot = selected_slot + 1) begin : g_selected_match
            wire [INDEX_W-1:0] selected_atom = selected_indices[
                selected_slot*INDEX_W +: INDEX_W];
            wire selected_in_stripe =
                (selected_slot < selected_count) &&
                (selected_atom[INDEX_W-1:LANE_INDEX_W] ==
                 stripe_base[INDEX_W-1:LANE_INDEX_W]);
            genvar selected_lane;
            for (selected_lane = 0; selected_lane < LANES;
                 selected_lane = selected_lane + 1) begin : g_lane_decode
                assign selected_lane_match[selected_slot*LANES +
                    selected_lane] = selected_in_stripe &&
                    (selected_atom[LANE_INDEX_W-1:0] == selected_lane);
            end
        end
    endgenerate

    genvar support_slot;
    generate
        for (support_slot = 0; support_slot < SELECT_MAX;
             support_slot = support_slot + 1) begin : g_support_match
            wire [INDEX_W-1:0] support_atom = support_indices[
                support_slot*INDEX_W +: INDEX_W];
            wire support_in_stripe = (support_slot < support_count) &&
                (support_atom[INDEX_W-1:LANE_INDEX_W] ==
                 stripe_base[INDEX_W-1:LANE_INDEX_W]);
            genvar support_lane;
            for (support_lane = 0; support_lane < LANES;
                 support_lane = support_lane + 1) begin : g_lane_decode
                assign support_lane_match[support_slot*LANES +
                    support_lane] = support_in_stripe &&
                    (support_atom[LANE_INDEX_W-1:0] == support_lane);
            end
        end
    endgenerate

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
            wire [INDEX_W:0] item_index = stripe_base + lane;
            wire [SELECT_MAX-1:0] selected_match;
            wire [SELECT_MAX-1:0] support_match;
            genvar match_slot;
            for (match_slot = 0; match_slot < SELECT_MAX;
                 match_slot = match_slot + 1) begin : g_match
                assign selected_match[match_slot] =
                    selected_lane_match[match_slot*LANES + lane];
            end
            genvar support_match_slot;
            for (support_match_slot = 0; support_match_slot < SELECT_MAX;
                 support_match_slot = support_match_slot + 1) begin : g_support
                assign support_match[support_match_slot] =
                    support_lane_match[support_match_slot*LANES + lane];
            end
            wire dense_selected = |selected_match;
            wire support_selected = item_index < support_count;
            reg signed [DATA_W-1:0] support_coefficient;
            reg signed [DATA_W-1:0] support_gradient;
            reg support_gradient_present;
            reg [INDEX_W-1:0] support_atom;
            wire support_atom_is_top1 = (selected_count != 0) &&
                (support_atom == selected_indices[0 +: INDEX_W]);
            wire dense_support_selected = |support_match;
            reg signed [DATA_W-1:0] dense_support_coefficient;
            integer dense_support_slot;
            always @* begin
                dense_support_coefficient = {DATA_W{1'b0}};
                for (dense_support_slot = 0;
                     dense_support_slot < SELECT_MAX;
                     dense_support_slot = dense_support_slot + 1)
                    if (support_match[dense_support_slot])
                        dense_support_coefficient = support_coefficients[
                            dense_support_slot*DATA_W +: DATA_W];
            end
            always @* begin
                case (stripe_base[6:4])
                    3'd0: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+0)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+0];
                        support_atom = support_indices[(lane+0)*INDEX_W +: INDEX_W];
                    end
                    3'd1: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+16)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+16];
                        support_atom = support_indices[(lane+16)*INDEX_W +: INDEX_W];
                    end
                    3'd2: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+32)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+32];
                        support_atom = support_indices[(lane+32)*INDEX_W +: INDEX_W];
                    end
                    3'd3: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+48)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+48];
                        support_atom = support_indices[(lane+48)*INDEX_W +: INDEX_W];
                    end
                    3'd4: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+64)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+64];
                        support_atom = support_indices[(lane+64)*INDEX_W +: INDEX_W];
                    end
                    3'd5: begin
                        support_coefficient = support_coefficient_stripe[
                            lane*DATA_W +: DATA_W];
                        support_gradient = support_gradients[(lane+80)*DATA_W +: DATA_W];
                        support_gradient_present = support_gradient_valid[lane+80];
                        support_atom = support_indices[(lane+80)*INDEX_W +: INDEX_W];
                    end
                    default: begin
                        support_coefficient = {DATA_W{1'b0}};
                        support_gradient = {DATA_W{1'b0}};
                        support_gradient_present = 1'b0;
                        support_atom = {INDEX_W{1'b0}};
                    end
                endcase
            end
            reg signed [DATA_W-1:0] rebuilt_lane;
            always @* begin
                rebuilt_lane = {DATA_W{1'b0}};
                case (rebuild_mode)
                    3'd1: begin
                        if (support_selected && support_coefficient_stripe_valid)
                            rebuilt_lane = support_coefficient;
                    end
                    3'd2: begin
                        if ((item_index < signal_length) && dense_support_selected)
                            rebuilt_lane = dense_support_coefficient;
                    end
                    3'd3: begin
                        if (support_selected && support_gradient_present)
                            rebuilt_lane = support_gradient;
                    end
                    3'd4: begin
                        if (support_selected && support_gradient_present &&
                            support_atom_is_top1)
                            rebuilt_lane = support_gradient;
                    end
                    default: begin
                        if ((item_index < signal_length) && dense_selected)
                            rebuilt_lane = dense_input[lane*DATA_W +: DATA_W];
                    end
                endcase
            end
            assign rebuilt_output[lane*DATA_W +: DATA_W] = rebuilt_lane;
        end
    endgenerate
endmodule

`default_nettype wire
