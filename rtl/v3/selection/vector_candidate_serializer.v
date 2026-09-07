`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module vector_candidate_serializer #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer LANES = `RECON_SHARED_VECTOR_LANES,
    parameter integer INDEX_W = 10
)(
    input wire clk, input wire rst_n, input wire routine_start,
    input wire source_active, input wire [INDEX_W:0] element_count,
    input wire stripe_valid, input wire [LANES-1:0] stripe_lane_valid,
    input wire [LANES*DATA_W-1:0] stripe_data,
    output wire stripe_release, output wire candidate_valid,
    input wire candidate_ready,
    output wire signed [DATA_W-1:0] candidate_score,
    output wire [INDEX_W-1:0] candidate_index,
    output wire candidate_fault, output wire stream_done
);
    reg [LANES*DATA_W-1:0] buffered_data;
    reg [LANES-1:0] buffered_lane_valid;
    reg buffer_valid;
    reg [INDEX_W:0] item_count;
    wire count_valid = (element_count != 0) &&
                       (element_count <= (1 << INDEX_W));
    wire capture_stripe = source_active && !buffer_valid && stripe_valid &&
                          (item_count < element_count);
    assign candidate_valid = source_active && buffer_valid &&
                             (item_count < element_count);
    assign candidate_score = buffered_data[DATA_W-1:0];
    assign candidate_index = item_count[INDEX_W-1:0];
    assign candidate_fault = candidate_valid &&
                             (!count_valid || !buffered_lane_valid[0]);
    wire candidate_fire = candidate_valid && candidate_ready;
    wire candidate_is_final = candidate_valid &&
        ((item_count + 1'b1) == element_count);
    wire candidate_is_final_lane = candidate_valid &&
        ((item_count[$clog2(LANES)-1:0] == LANES-1) || candidate_is_final);
    wire final_candidate = candidate_fire && candidate_is_final;
    wire final_lane = candidate_fire && candidate_is_final_lane;
    assign stripe_release = candidate_is_final_lane;
    assign stream_done = final_candidate;
    always @(posedge clk) begin
        if (!rst_n || routine_start) begin
            buffered_data <= {LANES*DATA_W{1'b0}};
            buffered_lane_valid <= {LANES{1'b0}};
            buffer_valid <= 1'b0;
            item_count <= {(INDEX_W+1){1'b0}};
        end else begin
            if (capture_stripe) begin
                buffered_data <= stripe_data;
                buffered_lane_valid <= stripe_lane_valid;
                buffer_valid <= 1'b1;
            end
            if (candidate_fire) begin
                item_count <= item_count + 1'b1;
                if (final_lane) begin
                    buffered_data <= {LANES*DATA_W{1'b0}};
                    buffered_lane_valid <= {LANES{1'b0}};
                    buffer_valid <= 1'b0;
                end else begin
                    buffered_data <= {{DATA_W{1'b0}},
                                      buffered_data[LANES*DATA_W-1:DATA_W]};
                    buffered_lane_valid <= {1'b0,
                        buffered_lane_valid[LANES-1:1]};
                end
            end
        end
    end
endmodule

`default_nettype wire
