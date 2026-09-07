`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Dense-vector preload client for memory_dma_engine.
//
// The external representation is one sign-extended 32-bit element. The
// destination configuration is the same 64-bit word consumed by the stream
// engine. Baseline v3 preload supports the compiler-owned full eight-bank,
// cyclic, unit-stride D18/F14 and S27/F19 layouts. Unsupported layouts fail
// before issuing AXI traffic.
module scratchpad_preload_engine #(
    parameter integer ADDRESS_W = 64,
    parameter integer TAG_W = 8,
    parameter integer ADDR_W = 9
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       preload_valid,
    output wire                       preload_ready,
    input  wire [ADDRESS_W-1:0]       preload_src_addr,
    input  wire [5:0]                 preload_cfg_id,
    input  wire [63:0]                preload_cfg,

    output reg                        preload_done_valid,
    input  wire                       preload_done_ready,
    output reg  [5:0]                 preload_done_cfg_id,
    output reg                        preload_done_error,
    output reg  [7:0]                 preload_done_code,
    output wire                       preload_active,
    output reg                        load_begin,
    output reg  [5:0]                 load_begin_id,
    output reg                        load_commit,
    output reg  [5:0]                 load_commit_id,

    output wire                       dma_req_valid,
    input  wire                       dma_req_ready,
    output wire                       dma_req_write,
    output wire [ADDRESS_W-1:0]       dma_req_addr,
    output wire [15:0]                dma_req_bytes,
    output wire [TAG_W-1:0]           dma_req_tag,
    input  wire                       dma_rd_valid,
    output wire                       dma_rd_ready,
    input  wire [127:0]               dma_rd_data,
    input  wire                       dma_rd_last,
    input  wire [1:0]                 dma_rd_resp,
    input  wire [TAG_W-1:0]           dma_rd_tag,
    input  wire                       dma_done_valid,
    output wire                       dma_done_ready,
    input  wire [TAG_W-1:0]           dma_done_tag,
    input  wire                       dma_done_error,
    input  wire [1:0]                 dma_done_resp,

    output reg                        sp0_valid,
    input  wire                       sp0_ready,
    output wire                       sp0_write,
    output reg  [7:0]                 sp0_bank_mask,
    output reg  [8*ADDR_W-1:0]        sp0_addr,
    output reg  [575:0]               sp0_wr_data,
    output reg                        sp1_valid,
    input  wire                       sp1_ready,
    output wire                       sp1_write,
    output reg  [7:0]                 sp1_bank_mask,
    output reg  [8*ADDR_W-1:0]        sp1_addr,
    output reg  [575:0]               sp1_wr_data,
    input  wire                       sp_conflict
);
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_REQUEST = 2'd1;
    localparam [1:0] STATE_TRANSFER = 2'd2;

    localparam [7:0] ERROR_NONE = 8'd0;
    localparam [7:0] ERROR_CONFIGURATION = 8'd1;
    localparam [7:0] ERROR_DMA = 8'd2;
    localparam [7:0] ERROR_ELEMENT_RANGE = 8'd3;
    localparam [7:0] ERROR_ELEMENT_COUNT = 8'd4;

    reg [1:0] state;
    reg [ADDRESS_W-1:0] source_address;
    reg [5:0] configuration_id;
    reg [15:0] element_count;
    reg [ADDR_W-1:0] destination_base;
    reg [2:0] element_format;
    reg [2:0] packing_mode;
    reg source_data18_to_s27;
    reg [10:0] expected_bank_words;
    reg [10:0] accepted_bank_words;
    reg payload_last_seen;
    reg dma_terminal_seen;
    reg transfer_error;
    reg [7:0] transfer_error_code;
    reg packer_response_error;
    reg packer_tag_error;

    wire [15:0] command_element_count =
        preload_cfg[31:16];
    wire [15:0] command_base = preload_cfg[15:0];
    wire [11:0] command_stride = preload_cfg[43:32];
    wire [2:0] command_bank_base = preload_cfg[46:44];
    wire [1:0] command_bank_count_log2 =
        preload_cfg[48:47];
    wire [2:0] command_bank_mode = preload_cfg[51:49];
    wire [2:0] command_element_format =
        preload_cfg[54:52];
    wire [2:0] command_packing_mode =
        preload_cfg[57:55];
    wire [1:0] command_memory_space =
        preload_cfg[62:61];

    wire command_is_d18 =
        (command_element_format == `RECON_ELEMENT_FORMAT_DATA18) &&
        (command_packing_mode == `RECON_PACKING_MODE_FOUR);
    wire command_is_s27 =
        (command_element_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (command_packing_mode == `RECON_PACKING_MODE_TWO);
    wire command_source_data18_to_s27 = preload_cfg[63] && command_is_s27;
    wire [10:0] command_bank_words = command_is_d18 ?
        {1'b0, command_element_count[10:2]} :
        {1'b0, command_element_count[10:1]};
    wire [11:0] command_words_per_bank =
        ({1'b0, command_bank_words} + 12'd7) >> 3;
    wire cmd_cfg_error =
        (preload_src_addr[3:0] != 4'd0) ||
        (command_element_count == 16'd0) ||
        (command_element_count > `RECON_N_MAX) ||
        (command_element_count[1:0] != 2'b00) ||
        !(command_is_d18 || command_is_s27) ||
        (preload_cfg[63] && !command_is_s27) ||
        (command_memory_space != `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD) ||
        (command_bank_base != 3'd0) ||
        (command_bank_count_log2 != 2'd3) ||
        (command_bank_mode != `RECON_BANK_MODE_CYCLIC) ||
        (command_stride != 12'd1) ||
        (command_base >= `RECON_MEMORY_BANK_DEPTH) ||
        ({1'b0, command_base[8:0]} + command_words_per_bank >
         `RECON_MEMORY_BANK_DEPTH);

    assign preload_ready = (state == STATE_IDLE) &&
                           !preload_done_valid;
    assign preload_active = state != STATE_IDLE;
    assign dma_req_valid = state == STATE_REQUEST;
    assign dma_req_write = 1'b0;
    assign dma_req_addr = source_address;
    assign dma_req_bytes = {element_count[13:0], 2'b00};
    assign dma_req_tag = {{(TAG_W-6){1'b0}}, configuration_id};
    assign dma_done_ready = state == STATE_TRANSFER;
    assign sp0_write = 1'b1;
    assign sp1_write = 1'b1;

    wire norm_in_ready;
    wire norm_valid;
    wire norm_ready;
    wire [127:0] norm_data;
    wire [3:0] norm_elem_valid;
    wire norm_last;
    wire norm_error;
    wire [1:0] norm_error_lane;

    assign dma_rd_ready = (state == STATE_TRANSFER) && norm_in_ready;
    wire norm_in_fire = dma_rd_valid && dma_rd_ready;

    dma_element_normalizer u_normalizer (
        .clk(clk), .rst_n(rst_n),
        .input_valid(dma_rd_valid && (state == STATE_TRANSFER)),
        .input_ready(norm_in_ready), .input_data(dma_rd_data),
        .input_keep(16'hffff), .input_last(dma_rd_last),
        .element_format(source_data18_to_s27 ?
            `RECON_ELEMENT_FORMAT_DATA18 : element_format),
        .output_valid(norm_valid), .output_ready(norm_ready),
        .output_data(norm_data),
        .output_element_valid(norm_elem_valid),
        .output_last(norm_last), .output_error(norm_error),
        .output_error_lane(norm_error_lane)
    );

    wire [107:0] word0_d18_data = {
        norm_data[122:96], norm_data[90:64],
        norm_data[58:32], norm_data[26:0]};
    wire signed [31:0] converted_lane0 =
        $signed(norm_data[31:0]) <<< (`RECON_SOLVER_F-`RECON_DATA_F);
    wire signed [31:0] converted_lane1 =
        $signed(norm_data[63:32]) <<< (`RECON_SOLVER_F-`RECON_DATA_F);
    wire signed [31:0] converted_lane2 =
        $signed(norm_data[95:64]) <<< (`RECON_SOLVER_F-`RECON_DATA_F);
    wire signed [31:0] converted_lane3 =
        $signed(norm_data[127:96]) <<< (`RECON_SOLVER_F-`RECON_DATA_F);
    wire [127:0] pack_data = source_data18_to_s27 ?
        {converted_lane3, converted_lane2,
         converted_lane1, converted_lane0} : norm_data;
    wire [53:0] word0_s27_data = {
        pack_data[58:32], pack_data[26:0]};
    wire [53:0] word1_s27_data = {
        pack_data[122:96], pack_data[90:64]};
    wire word0_valid;
    wire [71:0] word0;
    wire word0_range_error;
    wire word1_valid;
    wire [71:0] word1;
    wire word1_range_error;

    scratchpad_word_codec u_word0_codec (
        .unpack_valid(1'b0), .unpack_word(72'd0),
        .unpack_element_format(3'd0), .unpack_packing_mode(3'd0),
        .unpack_format_valid(), .pe_lane_data(), .pe_lane_valid(),
        .sidecar_lane_data(), .sidecar_lane_valid(), .index_data(),
        .index_valid(), .raw_word_data(), .raw_word_valid(),
        .pack_valid(norm_valid),
        .pack_element_format(element_format), .pack_packing_mode(packing_mode),
        .pack_pe_lane_data(word0_d18_data),
        .pack_sidecar_lane_data(word0_s27_data),
        .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
        .packed_word_valid(word0_valid), .packed_word(word0),
        .pack_range_error(word0_range_error)
    );

    scratchpad_word_codec u_word1_codec (
        .unpack_valid(1'b0), .unpack_word(72'd0),
        .unpack_element_format(3'd0), .unpack_packing_mode(3'd0),
        .unpack_format_valid(), .pe_lane_data(), .pe_lane_valid(),
        .sidecar_lane_data(), .sidecar_lane_valid(), .index_data(),
        .index_valid(), .raw_word_data(), .raw_word_valid(),
        .pack_valid(norm_valid &&
                    (element_format == `RECON_ELEMENT_FORMAT_SOLVER27)),
        .pack_element_format(element_format), .pack_packing_mode(packing_mode),
        .pack_pe_lane_data(108'd0),
        .pack_sidecar_lane_data(word1_s27_data),
        .pack_index_data(70'd0), .pack_raw_word_data(72'd0),
        .packed_word_valid(word1_valid), .packed_word(word1),
        .pack_range_error(word1_range_error)
    );

    wire norm_meta_error = norm_error ||
        packer_response_error || packer_tag_error || word0_range_error ||
        ((element_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
         word1_range_error);
    wire output_uses_two_ports =
        element_format == `RECON_ELEMENT_FORMAT_SOLVER27;
    wire sp_accept = sp0_ready &&
        (!output_uses_two_ports || sp1_ready) &&
        !sp_conflict;
    assign norm_ready = norm_meta_error || sp_accept;
    wire norm_fire = norm_valid && norm_ready;
    wire [2:0] destination_bank0 = accepted_bank_words[2:0];
    wire [2:0] destination_bank1 = destination_bank0 + 3'd1;
    wire [ADDR_W-1:0] destination_address = destination_base +
        accepted_bank_words[10:3];

    integer address_lane;
    always @* begin
        sp0_valid = 1'b0;
        sp0_bank_mask = 8'd0;
        sp0_addr = {8*ADDR_W{1'b0}};
        // Payload buses are don't-care unless valid. Keep them broadcast at
        // all times so the valid bit does not infer a 576-bit enable mux.
        sp0_wr_data = {8{word0}};
        sp1_valid = 1'b0;
        sp1_bank_mask = 8'd0;
        sp1_addr = {8*ADDR_W{1'b0}};
        sp1_wr_data = {8{word1}};
        for (address_lane = 0; address_lane < 8;
                address_lane = address_lane + 1) begin
            sp0_addr[address_lane*ADDR_W +: ADDR_W] =
                destination_address;
            sp1_addr[address_lane*ADDR_W +: ADDR_W] =
                destination_address;
        end
        if (norm_valid && !norm_meta_error) begin
            sp0_valid = word0_valid;
            sp0_bank_mask[destination_bank0] = word0_valid;
            if (output_uses_two_ports) begin
                sp1_valid = word1_valid;
                sp1_bank_mask[destination_bank1] =
                    word1_valid;
            end
        end
    end

    wire dma_completion_fire = dma_done_valid && dma_done_ready;
    wire payload_last_fire = norm_fire && norm_last;
    wire [10:0] words_this_output = output_uses_two_ports ? 11'd2 : 11'd1;
    wire output_count_error = payload_last_fire &&
        ((accepted_bank_words + words_this_output) != expected_bank_words);
    wire final_dma_error = dma_done_error ||
        (dma_done_resp != 2'b00) ||
        (dma_done_tag != dma_req_tag);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            source_address <= {ADDRESS_W{1'b0}};
            configuration_id <= 6'd0;
            element_count <= 16'd0;
            destination_base <= {ADDR_W{1'b0}};
            element_format <= 3'd0;
            packing_mode <= 3'd0;
            source_data18_to_s27 <= 1'b0;
            expected_bank_words <= 11'd0;
            accepted_bank_words <= 11'd0;
            payload_last_seen <= 1'b0;
            dma_terminal_seen <= 1'b0;
            transfer_error <= 1'b0;
            transfer_error_code <= ERROR_NONE;
            packer_response_error <= 1'b0;
            packer_tag_error <= 1'b0;
            preload_done_valid <= 1'b0;
            preload_done_cfg_id <= 6'd0;
            preload_done_error <= 1'b0;
            preload_done_code <= ERROR_NONE;
            load_begin <= 1'b0;
            load_begin_id <= 6'd0;
            load_commit <= 1'b0;
            load_commit_id <= 6'd0;
        end else begin
            load_begin <= 1'b0;
            load_commit <= 1'b0;
            if (preload_done_valid && preload_done_ready)
                preload_done_valid <= 1'b0;

            if (preload_valid && preload_ready) begin
                configuration_id <= preload_cfg_id;
                preload_done_cfg_id <=
                    preload_cfg_id;
                load_begin <= 1'b1;
                load_begin_id <= preload_cfg_id;
                if (cmd_cfg_error) begin
                    preload_done_valid <= 1'b1;
                    preload_done_error <= 1'b1;
                    preload_done_code <= ERROR_CONFIGURATION;
                end else begin
                    source_address <= preload_src_addr;
                    element_count <= command_element_count;
                    destination_base <= command_base[ADDR_W-1:0];
                    element_format <= command_element_format;
                    packing_mode <= command_packing_mode;
                    source_data18_to_s27 <= command_source_data18_to_s27;
                    expected_bank_words <= command_bank_words;
                    accepted_bank_words <= 11'd0;
                    payload_last_seen <= 1'b0;
                    dma_terminal_seen <= 1'b0;
                    transfer_error <= 1'b0;
                    transfer_error_code <= ERROR_NONE;
                    state <= STATE_REQUEST;
                end
            end

            if (state == STATE_REQUEST && dma_req_ready)
                state <= STATE_TRANSFER;

            if (norm_in_fire) begin
                packer_response_error <= dma_rd_resp != 2'b00;
                packer_tag_error <= dma_rd_tag != dma_req_tag;
            end

            if (norm_fire) begin
                accepted_bank_words <= accepted_bank_words + words_this_output;
                if (norm_meta_error && !transfer_error) begin
                    transfer_error <= 1'b1;
                    transfer_error_code <= ERROR_ELEMENT_RANGE;
                end
                if (output_count_error && !transfer_error) begin
                    transfer_error <= 1'b1;
                    transfer_error_code <= ERROR_ELEMENT_COUNT;
                end
                if (norm_last)
                    payload_last_seen <= 1'b1;
            end

            if (dma_completion_fire) begin
                dma_terminal_seen <= 1'b1;
                if (final_dma_error && !transfer_error) begin
                    transfer_error <= 1'b1;
                    transfer_error_code <= ERROR_DMA;
                end
            end

            if (state == STATE_TRANSFER &&
                    ((dma_terminal_seen || dma_completion_fire) &&
                     (payload_last_seen || payload_last_fire ||
                      (dma_completion_fire && final_dma_error)))) begin
                state <= STATE_IDLE;
                preload_done_valid <= 1'b1;
                preload_done_cfg_id <= configuration_id;
                preload_done_error <= transfer_error ||
                    norm_meta_error || output_count_error ||
                    (dma_completion_fire && final_dma_error);
                if (transfer_error)
                    preload_done_code <= transfer_error_code;
                else if (dma_completion_fire && final_dma_error)
                    preload_done_code <= ERROR_DMA;
                else if (output_count_error)
                    preload_done_code <= ERROR_ELEMENT_COUNT;
                else if (norm_meta_error)
                    preload_done_code <= ERROR_ELEMENT_RANGE;
                else begin
                    preload_done_code <= ERROR_NONE;
                    load_commit <= 1'b1;
                    load_commit_id <= configuration_id;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_prev_done_wait;
    reg [5:0] f_prev_done_id;
    reg f_prev_done_error;
    reg [7:0] f_prev_done_code;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_prev_done_wait <= 1'b0;
        end else begin
            if (f_prev_done_wait) begin
                assert(preload_done_valid);
                assert(preload_done_cfg_id ==
                       f_prev_done_id);
                assert(preload_done_error ==
                       f_prev_done_error);
                assert(preload_done_code ==
                       f_prev_done_code);
            end
            assert(!load_commit ||
                   (!preload_done_error && preload_done_valid));
            assert(!(sp0_valid && !sp0_write));
            assert(!(sp1_valid && !sp1_write));
            f_prev_done_wait <= preload_done_valid &&
                                               !preload_done_ready;
            f_prev_done_id <=
                preload_done_cfg_id;
            f_prev_done_error <= preload_done_error;
            f_prev_done_code <= preload_done_code;
        end
    end
`endif
endmodule

`default_nettype wire
