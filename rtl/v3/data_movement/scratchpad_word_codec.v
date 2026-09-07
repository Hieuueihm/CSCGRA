`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"

// Packing boundary for one physical scratchpad bank (one cluster row).
// Arithmetic rounding is forbidden here: D18 writes must already be exact
// sign-extended D18 values and S27 values are copied bit-for-bit.
module scratchpad_word_codec (
    input  wire         unpack_valid,
    input  wire [71:0]  unpack_word,
    input  wire [2:0]   unpack_element_format,
    input  wire [2:0]   unpack_packing_mode,
    output wire         unpack_format_valid,
    output wire [107:0] pe_lane_data,
    output wire [3:0]   pe_lane_valid,
    output wire [53:0]  sidecar_lane_data,
    output wire [1:0]   sidecar_lane_valid,
    output wire [69:0]  index_data,
    output wire [6:0]   index_valid,
    output wire [71:0]  raw_word_data,
    output wire         raw_word_valid,

    input  wire         pack_valid,
    input  wire [2:0]   pack_element_format,
    input  wire [2:0]   pack_packing_mode,
    input  wire [107:0] pack_pe_lane_data,
    input  wire [53:0]  pack_sidecar_lane_data,
    input  wire [69:0]  pack_index_data,
    input  wire [71:0]  pack_raw_word_data,
    output reg          packed_word_valid,
    output reg  [71:0]  packed_word,
    output reg          pack_range_error
);
    wire unpack_d18 = unpack_valid &&
        (unpack_element_format == `RECON_ELEMENT_FORMAT_DATA18) &&
        (unpack_packing_mode == `RECON_PACKING_MODE_FOUR);
    wire unpack_s27 = unpack_valid &&
        (unpack_element_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (unpack_packing_mode == `RECON_PACKING_MODE_TWO);
    wire unpack_index = unpack_valid &&
        (unpack_element_format == `RECON_ELEMENT_FORMAT_INDEX10) &&
        (unpack_packing_mode == `RECON_PACKING_MODE_SEVEN);
    wire unpack_raw = unpack_valid &&
        ((unpack_element_format == `RECON_ELEMENT_FORMAT_RAW32) ||
         (unpack_element_format == `RECON_ELEMENT_FORMAT_RAW64)) &&
        (unpack_packing_mode == `RECON_PACKING_MODE_RAW72);

    assign unpack_format_valid = unpack_d18 || unpack_s27 ||
                                 unpack_index || unpack_raw;
    assign pe_lane_valid = {4{unpack_d18}};
    assign sidecar_lane_valid = {2{unpack_s27}};
    assign index_valid = {7{unpack_index}};
    assign raw_word_valid = unpack_raw;

    // Payload has meaning only when its matching valid output is asserted.
    // Keeping these paths as pure wiring avoids four wide format muxes at every
    // bank-to-consumer boundary.
    assign pe_lane_data[26:0] = {{9{unpack_word[17]}}, unpack_word[17:0]};
    assign pe_lane_data[53:27] = {{9{unpack_word[35]}}, unpack_word[35:18]};
    assign pe_lane_data[80:54] = {{9{unpack_word[53]}}, unpack_word[53:36]};
    assign pe_lane_data[107:81] = {{9{unpack_word[71]}}, unpack_word[71:54]};
    assign sidecar_lane_data = unpack_word[53:0];
    assign index_data = unpack_word[69:0];
    assign raw_word_data = unpack_word;

    wire d18_range_error =
        (pack_pe_lane_data[26:18] != {9{pack_pe_lane_data[17]}}) ||
        (pack_pe_lane_data[53:45] != {9{pack_pe_lane_data[44]}}) ||
        (pack_pe_lane_data[80:72] != {9{pack_pe_lane_data[71]}}) ||
        (pack_pe_lane_data[107:99] != {9{pack_pe_lane_data[98]}});

    always @* begin
        packed_word_valid = 1'b0;
        packed_word = 72'd0;
        pack_range_error = 1'b0;
        if (pack_valid) begin
            case ({pack_element_format, pack_packing_mode})
                {`RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR}: begin
                    packed_word = {
                        pack_pe_lane_data[98:81],
                        pack_pe_lane_data[71:54],
                        pack_pe_lane_data[44:27],
                        pack_pe_lane_data[17:0]
                    };
                    pack_range_error = d18_range_error;
                    packed_word_valid = !d18_range_error;
                end
                {`RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO}: begin
                    packed_word[53:0] = pack_sidecar_lane_data;
                    packed_word_valid = 1'b1;
                end
                {`RECON_ELEMENT_FORMAT_INDEX10, `RECON_PACKING_MODE_SEVEN}: begin
                    packed_word[69:0] = pack_index_data;
                    packed_word_valid = 1'b1;
                end
                {`RECON_ELEMENT_FORMAT_RAW32, `RECON_PACKING_MODE_RAW72},
                {`RECON_ELEMENT_FORMAT_RAW64, `RECON_PACKING_MODE_RAW72}: begin
                    packed_word = pack_raw_word_data;
                    packed_word_valid = 1'b1;
                end
                default: begin
                    pack_range_error = 1'b1;
                end
            endcase
        end
    end

`ifdef FORMAL
    always @* begin
        #0;
        if (unpack_valid && unpack_format_valid)
            assert((pe_lane_valid == 4'hf) ||
                   (sidecar_lane_valid == 2'b11) ||
                   (index_valid == 7'h7f) || raw_word_valid);
        if (packed_word_valid)
            assert(pack_valid && !pack_range_error);
    end
`endif
endmodule

`default_nettype wire
