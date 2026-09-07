`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// One homogeneous PE row with local east/west wiring. North/south planes are
// exposed for composition into the generated cluster topology.
module cgra_row #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer ACC_W = `RECON_LOCAL_ACC_W,
    parameter [3:0] FULL_PE_MASK = 4'hf
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire                         row_enable,
    input  wire [`RECON_PE_COLUMNS*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_PREDICATE_COUNT-1:0] predicate_values,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] north_input,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] south_input,
    input  wire [DATA_W-1:0]            west_input,
    input  wire [DATA_W-1:0]            east_input,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] external_input_a,
    input  wire [`RECON_PE_COLUMNS*DATA_W-1:0] external_input_b,
    input  wire [`RECON_PE_COLUMNS-1:0] phi_nonzero,
    input  wire [`RECON_PE_COLUMNS-1:0] phi_sign,
    output wire [`RECON_PE_COLUMNS*DATA_W-1:0] north_output,
    output wire [`RECON_PE_COLUMNS*DATA_W-1:0] south_output,
    output wire [DATA_W-1:0]            west_output,
    output wire [DATA_W-1:0]            east_output,
    output wire [`RECON_PE_COLUMNS*DATA_W-1:0] lane_result,
    output wire [`RECON_PE_COLUMNS*ACC_W-1:0] lane_accumulator,
    output wire [`RECON_PE_COLUMNS-1:0] lane_result_valid,
    output wire                         saturation_event,
    output wire                         contract_error
);
    wire [`RECON_PE_COLUMNS*DATA_W-1:0] east_routes;
    wire [`RECON_PE_COLUMNS*DATA_W-1:0] west_routes;
    wire [`RECON_PE_COLUMNS-1:0] lane_saturation;
    wire [`RECON_PE_COLUMNS-1:0] lane_error;

    genvar column;
    generate
        for (column = 0; column < `RECON_PE_COLUMNS;
                column = column + 1) begin : g_tile
            wire [DATA_W-1:0] tile_west_input;
            wire [DATA_W-1:0] tile_east_input;
            if (column == 0) begin : g_west_boundary
                assign tile_west_input = west_input;
            end else begin : g_west_neighbor
                assign tile_west_input =
                    east_routes[(column-1)*DATA_W +: DATA_W];
            end
            if (column == `RECON_PE_COLUMNS-1) begin : g_east_boundary
                assign tile_east_input = east_input;
            end else begin : g_east_neighbor
                assign tile_east_input =
                    west_routes[(column+1)*DATA_W +: DATA_W];
            end

            if (FULL_PE_MASK[column]) begin : g_full_tile
            pe_tile #(.DATA_W(DATA_W), .ACC_W(ACC_W)) tile (
                .clk(clk), .rst_n(rst_n), .cycle_valid(cycle_valid),
                .cycle_commit(cycle_commit), .tile_enable(row_enable),
                .tile_ctx(tile_ctx[column*`RECON_TILE_CONTEXT_W +:
                                   `RECON_TILE_CONTEXT_W]),
                .predicate_values(predicate_values),
                .north_input(north_input[column*DATA_W +: DATA_W]),
                .east_input(tile_east_input),
                .south_input(south_input[column*DATA_W +: DATA_W]),
                .west_input(tile_west_input),
                .external_input_a(external_input_a[column*DATA_W +: DATA_W]),
                .external_input_b(external_input_b[column*DATA_W +: DATA_W]),
                .phi_nonzero(phi_nonzero[column]), .phi_sign(phi_sign[column]),
                .north_output(north_output[column*DATA_W +: DATA_W]),
                .east_output(east_routes[column*DATA_W +: DATA_W]),
                .south_output(south_output[column*DATA_W +: DATA_W]),
                .west_output(west_routes[column*DATA_W +: DATA_W]),
                .result(lane_result[column*DATA_W +: DATA_W]),
                .accumulator(lane_accumulator[column*ACC_W +: ACC_W]),
                .result_valid(lane_result_valid[column]),
                .saturation_event(lane_saturation[column]),
                .contract_error(lane_error[column])
            );
            end else begin : g_phi_tile
            phi_pe_tile #(.DATA_W(DATA_W), .ACC_W(ACC_W)) tile (
                .clk(clk), .rst_n(rst_n), .cycle_valid(cycle_valid),
                .cycle_commit(cycle_commit), .tile_enable(row_enable),
                .tile_ctx(tile_ctx[column*`RECON_TILE_CONTEXT_W +:
                                   `RECON_TILE_CONTEXT_W]),
                .predicate_values(predicate_values),
                .external_input_a(external_input_a[column*DATA_W +: DATA_W]),
                .phi_nonzero(phi_nonzero[column]), .phi_sign(phi_sign[column]),
                .north_output(north_output[column*DATA_W +: DATA_W]),
                .east_output(east_routes[column*DATA_W +: DATA_W]),
                .south_output(south_output[column*DATA_W +: DATA_W]),
                .west_output(west_routes[column*DATA_W +: DATA_W]),
                .result(lane_result[column*DATA_W +: DATA_W]),
                .accumulator(lane_accumulator[column*ACC_W +: ACC_W]),
                .result_valid(lane_result_valid[column]),
                .saturation_event(lane_saturation[column]),
                .contract_error(lane_error[column])
            );
            end
        end
    endgenerate

    assign west_output = west_routes[0 +: DATA_W];
    assign east_output =
        east_routes[(`RECON_PE_COLUMNS-1)*DATA_W +: DATA_W];
    assign saturation_event = |lane_saturation;
    assign contract_error = |lane_error;
endmodule

`default_nettype wire
