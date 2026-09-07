`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Generated physical clusters driven by one spatial context and one atomic
// commit. The two 4x4 clusters share a PC and are joined vertically by a
// four-lane bidirectional column connector.
module cgra_cluster_pair #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer LOCAL_ACC_W = `RECON_LOCAL_ACC_W,
    parameter integer REDUCTION_W = `RECON_ACC_W,
    parameter [15:0] FULL_PE_MASK = 16'hffff
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             cycle_valid,
    input  wire                             cycle_commit,
    input  wire [`RECON_CLUSTER_COUNT-1:0] cluster_enable_mask,
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0] predicate_values,
    input  wire [`RECON_PE_COUNT*DATA_W-1:0] external_input_a,
    input  wire [`RECON_PE_COUNT*DATA_W-1:0] external_input_b,
    input  wire [`RECON_PE_COUNT-1:0] phi_nonzero,
    input  wire [`RECON_PE_COUNT-1:0] phi_sign,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_input,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_input,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] west_boundary_input,
    input  wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] east_boundary_input,
    output wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_output,
    output wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_output,
    output wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] west_boundary_output,
    output wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] east_boundary_output,
    output wire [`RECON_PE_COUNT*DATA_W-1:0] lane_result,
    output wire [`RECON_PE_COUNT*LOCAL_ACC_W-1:0] lane_accumulator,
    output wire [`RECON_PE_COUNT*REDUCTION_W-1:0] reduction_lane_data,
    output wire [`RECON_PE_COUNT-1:0] lane_result_valid,
    output wire [`RECON_CLUSTER_COUNT-1:0] saturation_event,
    output wire [`RECON_CLUSTER_COUNT-1:0] contract_error
);
    localparam integer COLUMN_PLANE_W =
        `RECON_PE_COLUMNS * DATA_W;
    localparam integer UPPER_CLUSTER = 0;
    localparam integer LOWER_CLUSTER = 1;

    wire [`RECON_CLUSTER_COUNT*COLUMN_PLANE_W-1:0]
        cluster_north_input;
    wire [`RECON_CLUSTER_COUNT*COLUMN_PLANE_W-1:0]
        cluster_south_input;

    assign cluster_north_input[
        UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] =
        north_boundary_input[
            UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W];
    assign cluster_south_input[
        LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] =
        south_boundary_input[
            LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W];

    assign cluster_north_input[
        LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] =
        south_boundary_output[
            UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W];
    assign cluster_south_input[
        UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] =
        north_boundary_output[
            LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W];

    genvar cluster;
    generate
        for (cluster = 0; cluster < `RECON_CLUSTER_COUNT;
                cluster = cluster + 1) begin : g_cluster
            cgra_cluster #(
                .DATA_W(DATA_W), .ACC_W(LOCAL_ACC_W),
                .FULL_PE_MASK(FULL_PE_MASK)
            ) cluster_array (
                .clk(clk), .rst_n(rst_n), .cycle_valid(cycle_valid),
                .cycle_commit(cycle_commit),
                .cluster_enable(cluster_enable_mask[cluster]),
                .tile_ctx(tile_ctx),
                .predicate_values(predicate_values[
                    cluster*`RECON_PREDICATE_COUNT +: `RECON_PREDICATE_COUNT]),
                .external_input_a(external_input_a[
                    cluster*`RECON_PE_PER_CLUSTER*DATA_W +:
                    `RECON_PE_PER_CLUSTER*DATA_W]),
                .external_input_b(external_input_b[
                    cluster*`RECON_PE_PER_CLUSTER*DATA_W +:
                    `RECON_PE_PER_CLUSTER*DATA_W]),
                .phi_nonzero(phi_nonzero[
                    cluster*`RECON_PE_PER_CLUSTER +: `RECON_PE_PER_CLUSTER]),
                .phi_sign(phi_sign[
                    cluster*`RECON_PE_PER_CLUSTER +: `RECON_PE_PER_CLUSTER]),
                .north_boundary_input(
                    cluster_north_input[
                        cluster*`RECON_PE_COLUMNS*DATA_W +:
                        `RECON_PE_COLUMNS*DATA_W]),
                .south_boundary_input(
                    cluster_south_input[
                        cluster*`RECON_PE_COLUMNS*DATA_W +:
                        `RECON_PE_COLUMNS*DATA_W]),
                .west_boundary_input(
                    west_boundary_input[
                        cluster*`RECON_PE_ROWS*DATA_W +:
                        `RECON_PE_ROWS*DATA_W]),
                .east_boundary_input(
                    east_boundary_input[
                        cluster*`RECON_PE_ROWS*DATA_W +:
                        `RECON_PE_ROWS*DATA_W]),
                .north_boundary_output(
                    north_boundary_output[
                        cluster*`RECON_PE_COLUMNS*DATA_W +:
                        `RECON_PE_COLUMNS*DATA_W]),
                .south_boundary_output(
                    south_boundary_output[
                        cluster*`RECON_PE_COLUMNS*DATA_W +:
                        `RECON_PE_COLUMNS*DATA_W]),
                .west_boundary_output(
                    west_boundary_output[
                        cluster*`RECON_PE_ROWS*DATA_W +:
                        `RECON_PE_ROWS*DATA_W]),
                .east_boundary_output(
                    east_boundary_output[
                        cluster*`RECON_PE_ROWS*DATA_W +:
                        `RECON_PE_ROWS*DATA_W]),
                .lane_result(lane_result[
                    cluster*`RECON_PE_PER_CLUSTER*DATA_W +:
                    `RECON_PE_PER_CLUSTER*DATA_W]),
                .lane_accumulator(
                    lane_accumulator[
                        cluster*`RECON_PE_PER_CLUSTER*LOCAL_ACC_W +:
                        `RECON_PE_PER_CLUSTER*LOCAL_ACC_W]),
                .lane_result_valid(lane_result_valid[
                    cluster*`RECON_PE_PER_CLUSTER +: `RECON_PE_PER_CLUSTER]),
                .saturation_event(saturation_event[cluster]),
                .contract_error(contract_error[cluster])
            );
        end

        for (cluster = 0; cluster < `RECON_PE_COUNT;
                cluster = cluster + 1) begin : g_reduction
            assign reduction_lane_data[cluster*REDUCTION_W +: REDUCTION_W] =
                {{(REDUCTION_W-LOCAL_ACC_W){
                    lane_accumulator[cluster*LOCAL_ACC_W + LOCAL_ACC_W-1]}},
                 lane_accumulator[cluster*LOCAL_ACC_W +: LOCAL_ACC_W]};
        end
    endgenerate

    wire unused_internal_boundary_inputs =
        (|north_boundary_input[
            LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W]) ||
        (|south_boundary_input[
            UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W]);

`ifdef FORMAL
    reg f_past_valid;
    reg f_prev_stalled;
    reg [`RECON_PE_COUNT*DATA_W-1:0] f_lane_result;
    reg [`RECON_PE_COUNT*LOCAL_ACC_W-1:0] f_lane_accumulator;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_prev_stalled) begin
            assert(lane_result == f_lane_result);
            assert(lane_accumulator == f_lane_accumulator);
        end
        f_prev_stalled <= cycle_valid && !cycle_commit;
        f_lane_result <= lane_result;
        f_lane_accumulator <= lane_accumulator;
        if (rst_n) begin
            assert(cluster_north_input[
                LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] ==
                south_boundary_output[
                    UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W]);
            assert(cluster_south_input[
                UPPER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W] ==
                north_boundary_output[
                    LOWER_CLUSTER*COLUMN_PLANE_W +: COLUMN_PLANE_W]);
        end
    end
`endif
    wire unused_ok = unused_internal_boundary_inputs;
endmodule

`default_nettype wire
