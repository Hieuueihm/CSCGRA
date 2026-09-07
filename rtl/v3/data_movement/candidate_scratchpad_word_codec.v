`timescale 1ns/1ps
`default_nettype none

// Candidate-only fixed-width leaf.  It is intentionally not in files.f:
// active production keeps scratchpad_word_codec and its D18/S27 ABI.
module candidate_scratchpad_word_codec #(
    parameter integer ELEMENT_W = 22,
    parameter integer ELEMENTS_PER_WORD = 3,
    parameter integer INPUT_W = 72
) (
    input wire unpack_valid,
    input wire [71:0] unpack_word,
    output wire [ELEMENTS_PER_WORD*ELEMENT_W-1:0] unpack_elements,
    output wire unpack_padding_error,
    input wire pack_valid,
    input wire [ELEMENTS_PER_WORD*INPUT_W-1:0] pack_elements,
    output reg packed_word_valid,
    output reg [71:0] packed_word,
    output reg pack_range_error
);
    localparam integer PAYLOAD_W = ELEMENTS_PER_WORD * ELEMENT_W;
    integer slot;
    reg lane_error;

    assign unpack_elements = unpack_word[PAYLOAD_W-1:0];
    assign unpack_padding_error = unpack_valid && (|unpack_word[71:PAYLOAD_W]);

    always @* begin
        packed_word = 72'd0;
        packed_word_valid = 1'b0;
        pack_range_error = 1'b0;
        if (pack_valid) begin
            for (slot = 0; slot < ELEMENTS_PER_WORD; slot = slot + 1) begin
                lane_error = 1'b0;
                if (ELEMENT_W < INPUT_W &&
                    pack_elements[slot*INPUT_W+INPUT_W-1 -: INPUT_W-ELEMENT_W] !=
                    {(INPUT_W-ELEMENT_W){pack_elements[slot*INPUT_W+ELEMENT_W-1]}})
                    lane_error = 1'b1;
                if (lane_error)
                    pack_range_error = 1'b1;
                packed_word[slot*ELEMENT_W +: ELEMENT_W] =
                    pack_elements[slot*INPUT_W +: ELEMENT_W];
            end
            packed_word_valid = !pack_range_error;
        end
    end
endmodule

`default_nettype wire
