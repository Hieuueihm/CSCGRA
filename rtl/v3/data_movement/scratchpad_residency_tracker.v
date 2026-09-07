`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Runtime residency state for the 64 compiler-visible memory configurations.
// A preload begin invalidates the destination immediately; only a successful
// terminal commit makes it visible to vector-read contexts. Missing data can
// either create an elastic input stall or expose a reservation violation when
// the context incorrectly promises that it cannot stall.
module scratchpad_residency_tracker (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clear_all,
    input  wire         load_begin,
    input  wire [5:0]   load_begin_id,
    input  wire         load_commit,
    input  wire [5:0]   load_commit_id,
    input  wire         invalidate,
    input  wire [5:0]   invalidate_id,
    input  wire         ctx_valid,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,
    output wire         configs_resident,
    output wire         reservation_violation,
    output wire         missing_valid,
    output wire [5:0]   missing_id,
    output wire [63:0]  resident_bitmap_out
);
    reg [63:0] resident_bitmap;
    wire read_a_enable =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_A_ENABLE_LSB];
    wire read_b_enable =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_B_ENABLE_LSB];
    wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W-1:0] read_a_id =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W];
    wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W-1:0] read_b_id =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W];
    wire stall_on_input =
        stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB];
    wire read_a_missing = ctx_valid && read_a_enable &&
                          !resident_bitmap[read_a_id];
    wire read_b_missing = ctx_valid && read_b_enable &&
                          !resident_bitmap[read_b_id];

    assign missing_valid = read_a_missing || read_b_missing;
    assign missing_id = read_a_missing ? read_a_id : read_b_id;
    assign configs_resident = !missing_valid;
    assign reservation_violation = missing_valid && !stall_on_input;
    assign resident_bitmap_out = resident_bitmap;

    always @(posedge clk) begin
        if (!rst_n || clear_all) begin
            resident_bitmap <= 64'd0;
        end else begin
            if (load_commit)
                resident_bitmap[load_commit_id] <= 1'b1;
            // Invalidation has safety priority over a simultaneous commit.
            if (load_begin)
                resident_bitmap[load_begin_id] <= 1'b0;
            if (invalidate)
                resident_bitmap[invalidate_id] <= 1'b0;
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            if (configs_resident && ctx_valid) begin
                if (read_a_enable)
                    assert(resident_bitmap[read_a_id]);
                if (read_b_enable)
                    assert(resident_bitmap[read_b_id]);
            end
            if (reservation_violation)
                assert(missing_valid && !stall_on_input);
        end
    end
`endif
endmodule

`default_nettype wire
