`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"

// Runtime legality guard for one compiler-issued array-context bundle.
//
// detail[31:24] : check class
// detail[23:16] : tile index (zero for global words)
// detail[15:8]  : field identifier
// detail[7:0]   : offending value
//
// This guard does not arbitrate resources.  It detects an image/architecture
// mismatch before the context can commit any architectural side effect.
module context_reservation_guard (
    input  wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    input  wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx,
    output reg          violation,
    output reg  [7:0]   violation_code,
    output reg  [31:0]  violation_detail
);
    localparam [31:0] TILE_OP_LEGAL =
        `RECON_TILE_OPERATION_LEGAL_MASK;
    localparam [31:0] RESOURCE_OP_IMPLEMENTED =
        `RECON_RESOURCE_OPERATION_IMPLEMENTED_MASK;
    localparam [7:0] ROUTE_SOURCE_LEGAL_MASK =
        `RECON_ROUTE_SOURCE_LEGAL_MASK;
    localparam [7:0] NEXT_PC_MODE_LEGAL_MASK =
        `RECON_NEXT_PC_MODE_LEGAL_MASK;

    localparam [7:0] CLASS_ARRAY_CONTROL = 8'd1;
    localparam [7:0] CLASS_TILE_OPERATION = 8'd2;
    localparam [7:0] CLASS_ROUTE = 8'd3;
    localparam [7:0] CLASS_STREAM = 8'd4;
    localparam [7:0] CLASS_RESOURCE = 8'd5;
    localparam [7:0] CLASS_GUARANTEED = 8'd6;

    localparam [7:0] FIELD_NEXT_PC_MODE = 8'd1;
    localparam [7:0] FIELD_LOOP_LIMIT_SELECT = 8'd2;
    localparam [7:0] FIELD_CLUSTER_EN = 8'd3;
    localparam [7:0] FIELD_TILE_OPERATION = 8'd1;
    localparam [7:0] FIELD_ROUTE_NORTH = 8'd2;
    localparam [7:0] FIELD_ROUTE_EAST = 8'd3;
    localparam [7:0] FIELD_ROUTE_SOUTH = 8'd4;
    localparam [7:0] FIELD_ROUTE_WEST = 8'd5;
    localparam [7:0] FIELD_VEC_CFG_A = 8'd1;
    localparam [7:0] FIELD_VEC_CFG_B = 8'd2;
    localparam [7:0] FIELD_VEC_CFG_W = 8'd3;
    localparam [7:0] FIELD_EXTERNAL_A = 8'd4;
    localparam [7:0] FIELD_EXTERNAL_B = 8'd5;
    localparam [7:0] FIELD_PHI_CONFIGURATION = 8'd6;
    localparam [7:0] FIELD_STREAM_ADVANCE = 8'd7;
    localparam [7:0] FIELD_RESOURCE_OP = 8'd1;
    localparam [7:0] FIELD_RESOURCE_COUNT = 8'd2;
    localparam [7:0] FIELD_GUAR_NEXT_PC = 8'd1;
    localparam [7:0] FIELD_GUARANTEED_VECTOR = 8'd2;
    localparam [7:0] FIELD_GUARANTEED_PHI = 8'd3;
    localparam [7:0] FIELD_GUAR_STREAM_WAIT = 8'd4;
    localparam [7:0] FIELD_GUAR_RES_WAIT = 8'd5;

    integer tile_index;
    reg [`RECON_TILE_CONTEXT_W-1:0] tile_word;
    reg [4:0] tile_operation;
    reg [2:0] route_source;
    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W-1:0] next_mode =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W-1:0] limit_sel =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_W-1:0] cluster_mask =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_LSB +:
                  `RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_W];
    wire [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] resource_operation =
        resource_ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                     `RECON_RESOURCE_FIELD_OPERATION_W];
    wire [`RECON_RESOURCE_FIELD_COUNT_SELECT_W-1:0] resource_count_select =
        resource_ctx[`RECON_RESOURCE_FIELD_COUNT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_COUNT_SELECT_W];
    wire guaranteed_commit =
        array_ctx[`RECON_ARRAY_CONTROL_FIELD_GUARANTEED_COMMIT_LSB];
    wire stream_vec_a_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_A_ENABLE_LSB];
    wire stream_vec_b_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_B_ENABLE_LSB];
    wire stream_vec_w_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_WRITE_ENABLE_LSB];
    wire [2:0] stream_vector_en = {
        stream_vec_w_en, stream_vec_b_en, stream_vec_a_en};
    wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W-1:0] stream_vec_cfg_a =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W];
    wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W-1:0] stream_vec_cfg_b =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W];
    wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_W-1:0] stream_vec_cfg_w =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_W];
    wire [`RECON_STREAM_FIELD_EXTERNAL_A_SELECT_W-1:0] stream_ext_a =
        stream_ctx[`RECON_STREAM_FIELD_EXTERNAL_A_SELECT_LSB +:
                   `RECON_STREAM_FIELD_EXTERNAL_A_SELECT_W];
    wire [`RECON_STREAM_FIELD_EXTERNAL_B_SELECT_W-1:0] stream_ext_b =
        stream_ctx[`RECON_STREAM_FIELD_EXTERNAL_B_SELECT_LSB +:
                   `RECON_STREAM_FIELD_EXTERNAL_B_SELECT_W];
    wire [`RECON_STREAM_FIELD_PHI_COMMAND_W-1:0] stream_phi_command =
        stream_ctx[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                   `RECON_STREAM_FIELD_PHI_COMMAND_W];
    wire [`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_W-1:0] stream_phi_cfg =
        stream_ctx[`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_LSB +:
                   `RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_W];
    wire stream_advance =
        stream_ctx[`RECON_STREAM_FIELD_ADVANCE_VECTOR_STREAMS_LSB];
    wire [1:0] stream_wait = {
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_OUTPUT_LSB],
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB]};
    wire [1:0] resource_wait = {
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB],
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB]};

    always @* begin
        violation = 1'b0;
        violation_code = 8'd0;
        violation_detail = 32'd0;
        tile_word = 36'd0;
        tile_operation = 5'd0;
        route_source = 3'd0;

        if (!NEXT_PC_MODE_LEGAL_MASK[next_mode]) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
            violation_detail = {CLASS_ARRAY_CONTROL, 8'd0,
                                FIELD_NEXT_PC_MODE, 5'd0, next_mode};
        end else if (limit_sel >
                     `RECON_LOOP_LIMIT_SIGNAL_LENGTH_STRIPES_16) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
            violation_detail = {CLASS_ARRAY_CONTROL, 8'd0,
                                FIELD_LOOP_LIMIT_SELECT, 4'd0,
                                limit_sel};
        end else if (cluster_mask == 2'b00) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
            violation_detail = {CLASS_ARRAY_CONTROL, 8'd0,
                                FIELD_CLUSTER_EN, 6'd0,
                                cluster_mask};
        end

        for (tile_index = 0; tile_index < `RECON_PE_PER_CLUSTER;
                tile_index = tile_index + 1) begin
            tile_word = tile_ctx[tile_index*`RECON_TILE_CONTEXT_W +:
                                 `RECON_TILE_CONTEXT_W];
            tile_operation = tile_word[`RECON_TILE_FIELD_OPERATION_LSB +:
                                       `RECON_TILE_FIELD_OPERATION_W];
            if (!violation && !TILE_OP_LEGAL[tile_operation]) begin
                violation = 1'b1;
                violation_code = `RECON_CONTEXT_ERROR_TILE_OPERATION;
                violation_detail = {CLASS_TILE_OPERATION, tile_index[7:0],
                                    FIELD_TILE_OPERATION, 3'd0,
                                    tile_operation};
            end

            route_source =
                tile_word[`RECON_TILE_FIELD_ROUTE_NORTH_SELECT_LSB +:
                          `RECON_TILE_FIELD_ROUTE_NORTH_SELECT_W];
            if (!violation && !ROUTE_SOURCE_LEGAL_MASK[route_source]) begin
                violation = 1'b1;
                violation_code = `RECON_CONTEXT_ERROR_ROUTE_CAPACITY;
                violation_detail = {CLASS_ROUTE, tile_index[7:0],
                                    FIELD_ROUTE_NORTH, 5'd0, route_source};
            end
            route_source =
                tile_word[`RECON_TILE_FIELD_ROUTE_EAST_SELECT_LSB +:
                          `RECON_TILE_FIELD_ROUTE_EAST_SELECT_W];
            if (!violation && !ROUTE_SOURCE_LEGAL_MASK[route_source]) begin
                violation = 1'b1;
                violation_code = `RECON_CONTEXT_ERROR_ROUTE_CAPACITY;
                violation_detail = {CLASS_ROUTE, tile_index[7:0],
                                    FIELD_ROUTE_EAST, 5'd0, route_source};
            end
            route_source =
                tile_word[`RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_LSB +:
                          `RECON_TILE_FIELD_ROUTE_SOUTH_SELECT_W];
            if (!violation && !ROUTE_SOURCE_LEGAL_MASK[route_source]) begin
                violation = 1'b1;
                violation_code = `RECON_CONTEXT_ERROR_ROUTE_CAPACITY;
                violation_detail = {CLASS_ROUTE, tile_index[7:0],
                                    FIELD_ROUTE_SOUTH, 5'd0, route_source};
            end
            route_source =
                tile_word[`RECON_TILE_FIELD_ROUTE_WEST_SELECT_LSB +:
                          `RECON_TILE_FIELD_ROUTE_WEST_SELECT_W];
            if (!violation && !ROUTE_SOURCE_LEGAL_MASK[route_source]) begin
                violation = 1'b1;
                violation_code = `RECON_CONTEXT_ERROR_ROUTE_CAPACITY;
                violation_detail = {CLASS_ROUTE, tile_index[7:0],
                                    FIELD_ROUTE_WEST, 5'd0, route_source};
            end
        end

        if (!violation && !stream_vec_a_en && (stream_vec_cfg_a != 0)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0,
                                FIELD_VEC_CFG_A, 2'd0,
                                stream_vec_cfg_a};
        end else if (!violation && !stream_vec_b_en &&
                (stream_vec_cfg_b != 0)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0,
                                FIELD_VEC_CFG_B, 2'd0,
                                stream_vec_cfg_b};
        end else if (!violation && !stream_vec_w_en &&
                (stream_vec_cfg_w != 0)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0,
                                FIELD_VEC_CFG_W, 2'd0,
                                stream_vec_cfg_w};
        end else if (!violation &&
                ((stream_ext_a ==
                  `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ||
                 (stream_ext_b ==
                  `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A)) &&
                !stream_vec_a_en) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0, FIELD_EXTERNAL_A,
                                6'd0, stream_ext_a};
        end else if (!violation &&
                ((stream_ext_a ==
                  `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B) ||
                 (stream_ext_b ==
                  `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B)) &&
                !stream_vec_b_en) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0, FIELD_EXTERNAL_B,
                                6'd0, stream_ext_b};
        end else if (!violation &&
                (stream_phi_command != `RECON_PHI_COMMAND_START) &&
                (stream_phi_cfg != 0)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0, FIELD_PHI_CONFIGURATION,
                                2'd0, stream_phi_cfg};
        end else if (!violation && stream_advance &&
                !(|stream_vector_en)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_STREAM_CONTRACT;
            violation_detail = {CLASS_STREAM, 8'd0, FIELD_STREAM_ADVANCE,
                                7'd0, stream_advance};
        end

        if (!violation &&
                !RESOURCE_OP_IMPLEMENTED[resource_operation]) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT;
            violation_detail = {CLASS_RESOURCE, 8'd0,
                                FIELD_RESOURCE_OP, 3'd0,
                                resource_operation};
        end else if (!violation && resource_count_select >
                     `RECON_RESOURCE_COUNT_REFINEMENT_ITERATION_LIMIT) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT;
            violation_detail = {CLASS_RESOURCE, 8'd0,
                                FIELD_RESOURCE_COUNT, 4'd0,
                                resource_count_select};
        end

        if (!violation && guaranteed_commit &&
                (next_mode == `RECON_NEXT_PC_MODE_WAIT_EVENT)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT;
            violation_detail = {CLASS_GUARANTEED, 8'd0,
                                FIELD_GUAR_NEXT_PC, 5'd0,
                                next_mode};
        end else if (!violation && guaranteed_commit &&
                (|stream_vector_en)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT;
            violation_detail = {CLASS_GUARANTEED, 8'd0,
                                FIELD_GUARANTEED_VECTOR, 5'd0,
                                stream_vector_en};
        end else if (!violation && guaranteed_commit &&
                (stream_phi_command == `RECON_PHI_COMMAND_CONSUME)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT;
            violation_detail = {CLASS_GUARANTEED, 8'd0,
                                FIELD_GUARANTEED_PHI, 6'd0,
                                stream_phi_command};
        end else if (!violation && guaranteed_commit &&
                (|stream_wait)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT;
            violation_detail = {CLASS_GUARANTEED, 8'd0,
                                FIELD_GUAR_STREAM_WAIT, 6'd0,
                                stream_wait};
        end else if (!violation && guaranteed_commit &&
                (|resource_wait)) begin
            violation = 1'b1;
            violation_code = `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT;
            violation_detail = {CLASS_GUARANTEED, 8'd0,
                                FIELD_GUAR_RES_WAIT, 6'd0,
                                resource_wait};
        end
    end

endmodule

`default_nettype wire
