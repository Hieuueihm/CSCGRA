`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// One generated ADRES-like homogeneous cluster. Row memory/external data and
// scalar predicates use dedicated planes; only general values traverse mesh.
module cgra_cluster #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W,
    parameter [15:0] FULL_PE_MASK = 16'hffff
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire                         cluster_enable,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_PREDICATE_COUNT-1:0] predicate_values,
    input  wire [`RECON_PE_PER_CLUSTER*DATA_W-1:0] external_input_a,
    input  wire [`RECON_PE_PER_CLUSTER*DATA_W-1:0] external_input_b,
    input  wire [`RECON_PE_PER_CLUSTER-1:0] phi_nonzero,
    input  wire [`RECON_PE_PER_CLUSTER-1:0] phi_sign,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_input,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_input,
    input  wire [`RECON_PE_ROWS*DATA_W-1:0] west_boundary_input,
    input  wire [`RECON_PE_ROWS*DATA_W-1:0] east_boundary_input,
    output wire [`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_output,
    output wire [`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_output,
    output wire [`RECON_PE_ROWS*DATA_W-1:0] west_boundary_output,
    output wire [`RECON_PE_ROWS*DATA_W-1:0] east_boundary_output,
    output wire [`RECON_PE_PER_CLUSTER*DATA_W-1:0] lane_result,
    output wire [`RECON_PE_PER_CLUSTER*ACC_W-1:0] lane_accumulator,
    output wire [`RECON_PE_PER_CLUSTER-1:0] lane_result_valid,
    output wire                         saturation_event,
    output wire                         contract_error
);
    wire [`RECON_PE_PER_CLUSTER*DATA_W-1:0] row_north_output;
    wire [`RECON_PE_PER_CLUSTER*DATA_W-1:0] row_south_output;
    wire [`RECON_PE_ROWS-1:0] row_saturation;
    wire [`RECON_PE_ROWS-1:0] row_error;

    genvar row;
    generate
        for (row = 0; row < `RECON_PE_ROWS; row = row + 1) begin : g_row
            wire [`RECON_PE_COLUMNS*DATA_W-1:0] row_north_input;
            wire [`RECON_PE_COLUMNS*DATA_W-1:0] row_south_input;
            if (row == 0) begin : g_north_boundary
                assign row_north_input = north_boundary_input;
            end else begin : g_north_neighbor
                assign row_north_input =
                    row_south_output[(row-1)*`RECON_PE_COLUMNS*DATA_W +:
                                     `RECON_PE_COLUMNS*DATA_W];
            end
            if (row == `RECON_PE_ROWS-1) begin : g_south_boundary
                assign row_south_input = south_boundary_input;
            end else begin : g_south_neighbor
                assign row_south_input =
                    row_north_output[(row+1)*`RECON_PE_COLUMNS*DATA_W +:
                                     `RECON_PE_COLUMNS*DATA_W];
            end

            cgra_row #(
                .DATA_W(DATA_W), .ACC_W(ACC_W),
                .FULL_PE_MASK(FULL_PE_MASK[row*`RECON_PE_COLUMNS +:
                                           `RECON_PE_COLUMNS])
            ) cluster_row (
                .clk(clk), .rst_n(rst_n), .cycle_valid(cycle_valid),
                .cycle_commit(cycle_commit), .row_enable(cluster_enable),
                .tile_ctx(tile_ctx[row*`RECON_PE_COLUMNS*`RECON_TILE_CONTEXT_W +:
                                   `RECON_PE_COLUMNS*`RECON_TILE_CONTEXT_W]),
                .predicate_values(predicate_values),
                .north_input(row_north_input), .south_input(row_south_input),
                .west_input(west_boundary_input[row*DATA_W +: DATA_W]),
                .east_input(east_boundary_input[row*DATA_W +: DATA_W]),
                .external_input_a(external_input_a[
                    row*`RECON_PE_COLUMNS*DATA_W +: `RECON_PE_COLUMNS*DATA_W]),
                .external_input_b(external_input_b[
                    row*`RECON_PE_COLUMNS*DATA_W +: `RECON_PE_COLUMNS*DATA_W]),
                .phi_nonzero(phi_nonzero[
                    row*`RECON_PE_COLUMNS +: `RECON_PE_COLUMNS]),
                .phi_sign(phi_sign[
                    row*`RECON_PE_COLUMNS +: `RECON_PE_COLUMNS]),
                .north_output(row_north_output[
                    row*`RECON_PE_COLUMNS*DATA_W +: `RECON_PE_COLUMNS*DATA_W]),
                .south_output(row_south_output[
                    row*`RECON_PE_COLUMNS*DATA_W +: `RECON_PE_COLUMNS*DATA_W]),
                .west_output(west_boundary_output[row*DATA_W +: DATA_W]),
                .east_output(east_boundary_output[row*DATA_W +: DATA_W]),
                .lane_result(lane_result[
                    row*`RECON_PE_COLUMNS*DATA_W +: `RECON_PE_COLUMNS*DATA_W]),
                .lane_accumulator(lane_accumulator[
                    row*`RECON_PE_COLUMNS*ACC_W +: `RECON_PE_COLUMNS*ACC_W]),
                .lane_result_valid(lane_result_valid[
                    row*`RECON_PE_COLUMNS +: `RECON_PE_COLUMNS]),
                .saturation_event(row_saturation[row]),
                .contract_error(row_error[row])
            );
        end
    endgenerate

    assign north_boundary_output =
        row_north_output[0 +: `RECON_PE_COLUMNS*DATA_W];
    assign south_boundary_output = row_south_output[
        (`RECON_PE_ROWS-1)*`RECON_PE_COLUMNS*DATA_W +:
        `RECON_PE_COLUMNS*DATA_W];
    assign saturation_event = |row_saturation;
    assign contract_error = |row_error;
endmodule

`default_nettype wire
