`timescale 1ns/1ps
`default_nettype none

// Candidate-only ACC70 threshold transport.  A 128-bit beat carries the
// unsigned threshold in bits [69:0]; [127:70] must remain zero.
module candidate_acc70_threshold_codec (
    input wire pack_valid,
    input wire [69:0] pack_threshold,
    output wire [127:0] packed_beat,
    output wire packed_valid,
    input wire unpack_valid,
    input wire [127:0] unpack_beat,
    output wire [69:0] unpack_threshold,
    output wire unpack_valid_clean,
    output wire unpack_padding_error
);
    assign packed_beat = {58'd0, pack_threshold};
    assign packed_valid = pack_valid;
    assign unpack_threshold = unpack_beat[69:0];
    assign unpack_padding_error = unpack_valid && (|unpack_beat[127:70]);
    assign unpack_valid_clean = unpack_valid && !unpack_padding_error;
endmodule

`default_nettype wire
