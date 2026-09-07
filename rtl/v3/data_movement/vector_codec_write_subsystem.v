`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module vector_codec_write_subsystem #(
    parameter integer DATA_W = `RECON_SOLVER_W
)(
    input wire physical_a_valid,
    input wire [575:0] physical_a,
    input wire [2:0] format_a,
    input wire [2:0] packing_a,
    input wire physical_b_valid,
    input wire [575:0] physical_b,
    input wire [2:0] format_b,
    input wire [2:0] packing_b,
    input wire write_enable,
    input wire write_config_valid,
    input wire [2:0] write_format,
    input wire [2:0] write_packing,
    input wire write_is_d18,
    input wire write_is_s27,
    input wire cgra_result_available,
    input wire cgra_s27_high_select,
    input wire [32*DATA_W-1:0] cgra_result,
    input wire [32*DATA_W-1:0] lane_result,
    input wire transpose_write_mode,
    input wire scalar_pending,
    input wire reduction_memory_context,
    input wire [16*DATA_W-1:0] scalar_pack,
    input wire [16*DATA_W-1:0] vector_result,
    input wire vector_result_ready,
    output wire [32*DATA_W-1:0] expanded_a,
    output wire [32*DATA_W-1:0] expanded_b,
    output wire [15:0] sidecar_valid_a,
    output wire [15:0] sidecar_valid_b,
    output wire [16*DATA_W-1:0] sidecar_a,
    output wire [16*DATA_W-1:0] sidecar_b,
    output wire [7:0] write_pack_valid,
    output wire [7:0] write_pack_error,
    output wire [575:0] write_data,
    output wire write_payload_ready
);
    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < 8;
                bank_index = bank_index + 1) begin : g_bank_codec
            scratchpad_word_codec u_read_a (
                .unpack_valid(physical_a_valid),
                .unpack_word(physical_a[bank_index*72 +: 72]),
                .unpack_element_format(format_a),
                .unpack_packing_mode(packing_a),
                .unpack_format_valid(),
                .pe_lane_data(expanded_a[bank_index*4*DATA_W +: 4*DATA_W]),
                .pe_lane_valid(),
                .sidecar_lane_data(sidecar_a[bank_index*2*DATA_W +:
                                              2*DATA_W]),
                .sidecar_lane_valid(sidecar_valid_a[bank_index*2 +: 2]),
                .index_data(), .index_valid(),
                .raw_word_data(), .raw_word_valid(),
                .pack_valid(1'b0), .pack_element_format(3'd0),
                .pack_packing_mode(3'd0),
                .pack_pe_lane_data({4*DATA_W{1'b0}}),
                .pack_sidecar_lane_data({2*DATA_W{1'b0}}),
                .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
                .packed_word_valid(), .packed_word(), .pack_range_error()
            );
            scratchpad_word_codec u_read_b (
                .unpack_valid(physical_b_valid),
                .unpack_word(physical_b[bank_index*72 +: 72]),
                .unpack_element_format(format_b),
                .unpack_packing_mode(packing_b),
                .unpack_format_valid(),
                .pe_lane_data(expanded_b[bank_index*4*DATA_W +: 4*DATA_W]),
                .pe_lane_valid(),
                .sidecar_lane_data(sidecar_b[bank_index*2*DATA_W +:
                                              2*DATA_W]),
                .sidecar_lane_valid(sidecar_valid_b[bank_index*2 +: 2]),
                .index_data(), .index_valid(),
                .raw_word_data(), .raw_word_valid(),
                .pack_valid(1'b0), .pack_element_format(3'd0),
                .pack_packing_mode(3'd0),
                .pack_pe_lane_data({4*DATA_W{1'b0}}),
                .pack_sidecar_lane_data({2*DATA_W{1'b0}}),
                .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
                .packed_word_valid(), .packed_word(), .pack_range_error()
            );
            scratchpad_word_codec u_write (
                .unpack_valid(1'b0), .unpack_word(72'd0),
                .unpack_element_format(3'd0), .unpack_packing_mode(3'd0),
                .unpack_format_valid(), .pe_lane_data(), .pe_lane_valid(),
                .sidecar_lane_data(), .sidecar_lane_valid(),
                .index_data(), .index_valid(),
                .raw_word_data(), .raw_word_valid(),
                .pack_valid(write_enable && write_config_valid),
                .pack_element_format(write_format),
                .pack_packing_mode(write_packing),
                .pack_pe_lane_data(
                    (cgra_result_available && write_is_d18) ?
                    cgra_result[bank_index*4*DATA_W +: 4*DATA_W] :
                    lane_result[bank_index*4*DATA_W +: 4*DATA_W]),
                .pack_sidecar_lane_data(transpose_write_mode ?
                    scalar_pack[bank_index*2*DATA_W +: 2*DATA_W] :
                    cgra_result_available ?
                    (cgra_s27_high_select ?
                     cgra_result[(16*DATA_W)+(bank_index*2*DATA_W) +:
                                 2*DATA_W] :
                     cgra_result[bank_index*2*DATA_W +: 2*DATA_W]) :
                    vector_result[bank_index*2*DATA_W +: 2*DATA_W]),
                .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
                .packed_word_valid(write_pack_valid[bank_index]),
                .packed_word(write_data[bank_index*72 +: 72]),
                .pack_range_error(write_pack_error[bank_index])
            );
        end
    endgenerate

    assign write_payload_ready = !write_enable ||
        (write_config_valid && (&write_pack_valid) &&
         ((write_is_d18 && cgra_result_available) ||
          (write_is_s27 &&
           ((transpose_write_mode &&
             (scalar_pending || reduction_memory_context)) ||
            cgra_result_available || vector_result_ready))));
endmodule

`default_nettype wire
