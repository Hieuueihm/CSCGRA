`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_symbol_generator (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         flush,
    input  wire         phi_request_valid,
    output wire         phi_request_ready,
    input  wire [63:0]  phi_request_seed,
    input  wire [`RECON_PHI_COLUMN_W-1:0] phi_request_column,
    input  wire [`RECON_PHI_ROW_PAIR_W-1:0] phi_request_row_pair,
    input  wire [`RECON_PHI_TAG_W-1:0] phi_request_tag,
    input  wire [8:0]   phi_request_measurement_count,
    output wire         phi_symbol_valid,
    input  wire         phi_symbol_ready,
    output wire [31:0]  phi_nonzero_bits,
    output wire [31:0]  phi_sign_bits,
    output wire [`RECON_PHI_COLUMN_W-1:0] phi_symbol_column,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_symbol_row_block,
    output wire [`RECON_PHI_TAG_W-1:0] phi_symbol_tag
);
    wire queued_valid;
    wire queued_ready;
    wire [63:0] queued_seed;
    wire [`RECON_PHI_COLUMN_W-1:0] queued_column;
    wire [`RECON_PHI_ROW_PAIR_W-1:0] queued_row_pair;
    wire [`RECON_PHI_TAG_W-1:0] queued_tag;
    wire [8:0] queued_measurement_count;

    phi_request_queue u_request_queue (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .input_valid(phi_request_valid), .input_ready(phi_request_ready),
        .input_seed(phi_request_seed), .input_column(phi_request_column),
        .input_row_pair(phi_request_row_pair), .input_tag(phi_request_tag),
        .input_measurement_count(phi_request_measurement_count),
        .output_valid(queued_valid), .output_ready(queued_ready),
        .output_seed(queued_seed), .output_column(queued_column),
        .output_row_pair(queued_row_pair), .output_tag(queued_tag),
        .output_measurement_count(queued_measurement_count)
    );

    wire core_valid;
    wire core_ready;
    wire [31:0] core_word0;
    wire [31:0] core_word1;
    wire [`RECON_PHI_COLUMN_W-1:0] core_column;
    wire [`RECON_PHI_ROW_PAIR_W-1:0] core_row_pair;
    wire [`RECON_PHI_TAG_W-1:0] core_tag;
    wire [8:0] core_measurement_count;

    threefry2x32_folded_pipeline u_threefry (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .request_valid(queued_valid), .request_ready(queued_ready),
        .request_seed(queued_seed), .request_column(queued_column),
        .request_row_pair(queued_row_pair), .request_tag(queued_tag),
        .request_measurement_count(queued_measurement_count),
        .response_valid(core_valid), .response_ready(core_ready),
        .response_word0(core_word0), .response_word1(core_word1),
        .response_column(core_column), .response_row_pair(core_row_pair),
        .response_tag(core_tag),
        .response_measurement_count(core_measurement_count)
    );

    wire built_valid;
    wire built_ready;
    wire [31:0] built_nonzero0;
    wire [31:0] built_sign0;
    wire [31:0] built_nonzero1;
    wire [31:0] built_sign1;
    wire [`RECON_PHI_COLUMN_W-1:0] built_column;
    wire [`RECON_PHI_ROW_PAIR_W-1:0] built_row_pair;
    wire [`RECON_PHI_TAG_W-1:0] built_tag;

    phi_symbol_builder u_symbol_builder (
        .input_valid(core_valid), .input_ready(core_ready),
        .input_word0(core_word0), .input_word1(core_word1),
        .input_column(core_column), .input_row_pair(core_row_pair),
        .input_tag(core_tag), .input_measurement_count(core_measurement_count),
        .output_valid(built_valid), .output_ready(built_ready),
        .output_nonzero0(built_nonzero0), .output_sign0(built_sign0),
        .output_nonzero1(built_nonzero1), .output_sign1(built_sign1),
        .output_column(built_column), .output_row_pair(built_row_pair),
        .output_tag(built_tag)
    );

    phi_response_gearbox u_response_gearbox (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .input_valid(built_valid), .input_ready(built_ready),
        .input_nonzero0(built_nonzero0), .input_sign0(built_sign0),
        .input_nonzero1(built_nonzero1), .input_sign1(built_sign1),
        .input_column(built_column), .input_row_pair(built_row_pair),
        .input_tag(built_tag), .output_valid(phi_symbol_valid),
        .output_ready(phi_symbol_ready), .output_nonzero(phi_nonzero_bits),
        .output_sign(phi_sign_bits), .output_column(phi_symbol_column),
        .output_row_block(phi_symbol_row_block), .output_tag(phi_symbol_tag)
    );
endmodule

`default_nettype wire
