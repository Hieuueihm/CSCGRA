`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"

module tb_m4_stream_transport;
    localparam integer BANKS = 8;
    localparam integer WORD_W = 72;
    localparam integer STRIPE_W = BANKS * WORD_W;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (!condition)
                fail(message);
        end
    endtask

    function [63:0] vector_configuration;
        input [15:0] base_address;
        input [15:0] element_count;
        input [2:0] element_format;
        input [2:0] packing_mode;
        input read_enable;
        input write_enable;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[15:0] = base_address;
            value[31:16] = element_count;
            value[43:32] = 12'd1;
            value[46:44] = 3'd0;
            value[48:47] = 2'd3;
            value[51:49] = `RECON_BANK_MODE_CYCLIC;
            value[54:52] = element_format;
            value[57:55] = packing_mode;
            value[58] = read_enable;
            value[59] = write_enable;
            value[60] = 1'b0;
            value[62:61] = `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD;
            value[63] = 1'b0;
            vector_configuration = value;
        end
    endfunction

    function [STRIPE_W-1:0] stripe_pattern;
        input [7:0] base_value;
        integer bank;
        reg [STRIPE_W-1:0] value;
        begin
            value = {STRIPE_W{1'b0}};
            for (bank = 0; bank < BANKS; bank = bank + 1)
                value[bank*WORD_W +: WORD_W] =
                    {56'd0, base_value, bank[7:0]};
            stripe_pattern = value;
        end
    endfunction

    function [STRIPE_W-1:0] indexed_stripe_pattern;
        input [8:0] word_address;
        integer pattern_bank;
        reg [STRIPE_W-1:0] value;
        begin
            value = {STRIPE_W{1'b0}};
            for (pattern_bank = 0; pattern_bank < BANKS;
                    pattern_bank = pattern_bank + 1)
                value[pattern_bank*WORD_W +: WORD_W] =
                    {55'd0, word_address, pattern_bank[7:0]};
            indexed_stripe_pattern = value;
        end
    endfunction

    function [31:0] lfsr_next;
        input [31:0] value;
        begin
            lfsr_next = {value[30:0],
                         value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    // ------------------------------------------------------------------
    // Gateway checks.
    // ------------------------------------------------------------------
    reg gateway_unpack_valid;
    reg [71:0] gateway_unpack_word;
    reg [2:0] gateway_unpack_format;
    reg [2:0] gateway_unpack_packing;
    wire gateway_unpack_format_valid;
    wire [107:0] gateway_pe_data;
    wire [3:0] gateway_pe_valid;
    wire [53:0] gateway_sidecar_data;
    wire [1:0] gateway_sidecar_valid;
    wire [69:0] gateway_index_data;
    wire [6:0] gateway_index_valid;
    wire [71:0] gateway_raw_data;
    wire gateway_raw_valid;
    reg gateway_pack_valid;
    reg [2:0] gateway_pack_format;
    reg [2:0] gateway_pack_packing;
    reg [107:0] gateway_pack_pe_data;
    reg [53:0] gateway_pack_sidecar_data;
    reg [69:0] gateway_pack_index_data;
    reg [71:0] gateway_pack_raw_data;
    wire gateway_packed_valid;
    wire [71:0] gateway_packed_word;
    wire gateway_pack_range_error;

    scratchpad_word_codec u_scratchpad_word_codec (
        .unpack_valid(gateway_unpack_valid),
        .unpack_word(gateway_unpack_word),
        .unpack_element_format(gateway_unpack_format),
        .unpack_packing_mode(gateway_unpack_packing),
        .unpack_format_valid(gateway_unpack_format_valid),
        .pe_lane_data(gateway_pe_data), .pe_lane_valid(gateway_pe_valid),
        .sidecar_lane_data(gateway_sidecar_data),
        .sidecar_lane_valid(gateway_sidecar_valid),
        .index_data(gateway_index_data), .index_valid(gateway_index_valid),
        .raw_word_data(gateway_raw_data), .raw_word_valid(gateway_raw_valid),
        .pack_valid(gateway_pack_valid),
        .pack_element_format(gateway_pack_format),
        .pack_packing_mode(gateway_pack_packing),
        .pack_pe_lane_data(gateway_pack_pe_data),
        .pack_sidecar_lane_data(gateway_pack_sidecar_data),
        .pack_index_data(gateway_pack_index_data),
        .pack_raw_word_data(gateway_pack_raw_data),
        .packed_word_valid(gateway_packed_valid),
        .packed_word(gateway_packed_word),
        .pack_range_error(gateway_pack_range_error)
    );

    // ------------------------------------------------------------------
    // Direct scratchpad instance for physical two-port legality.
    // ------------------------------------------------------------------
    reg direct_p0_valid, direct_p0_write;
    reg [7:0] direct_p0_mask;
    reg [71:0] direct_p0_addresses;
    reg [575:0] direct_p0_write_data;
    wire direct_p0_ready, direct_p0_read_valid;
    wire [7:0] direct_p0_read_mask;
    wire [575:0] direct_p0_read_data;
    reg direct_p1_valid, direct_p1_write;
    reg [7:0] direct_p1_mask;
    reg [71:0] direct_p1_addresses;
    reg [575:0] direct_p1_write_data;
    wire direct_p1_ready, direct_p1_read_valid;
    wire [7:0] direct_p1_read_mask;
    wire [575:0] direct_p1_read_data;
    wire direct_conflict;

    vector_scratchpad u_direct_scratchpad (
        .clk(clk), .rst_n(rst_n),
        .p0_valid(direct_p0_valid), .p0_ready(direct_p0_ready),
        .p0_write(direct_p0_write), .p0_bank_mask(direct_p0_mask),
        .p0_addr(direct_p0_addresses), .p0_wr_data(direct_p0_write_data),
        .p0_rd_valid(direct_p0_read_valid),
        .p0_rd_bank_mask(direct_p0_read_mask),
        .p0_rd_data(direct_p0_read_data),
        .p1_valid(direct_p1_valid), .p1_ready(direct_p1_ready),
        .p1_write(direct_p1_write), .p1_bank_mask(direct_p1_mask),
        .p1_addr(direct_p1_addresses), .p1_wr_data(direct_p1_write_data),
        .p1_rd_valid(direct_p1_read_valid),
        .p1_rd_bank_mask(direct_p1_read_mask),
        .p1_rd_data(direct_p1_read_data),
        .external_conflict(1'b0),
        .access_conflict(direct_conflict)
    );

    // ------------------------------------------------------------------
    // Stream engine with its own scratchpad.
    // ------------------------------------------------------------------
    reg routine_start;
    reg request_valid, cycle_commit;
    reg read_a_enable, read_b_enable, write_enable;
    reg [5:0] config_a_id, config_b_id, config_w_id;
    reg config_a_valid, config_b_valid, config_w_valid;
    reg [63:0] config_a, config_b, config_w;
    reg [575:0] engine_wr_data;
    wire engine_input_ready, engine_output_ready;
    wire engine_config_error, engine_access_conflict;
    wire engine_read_a_valid, engine_read_b_valid;
    wire [575:0] engine_read_a_data, engine_read_b_data;
    wire engine_p0_valid, engine_p0_ready, engine_p0_write;
    wire [7:0] engine_p0_mask;
    wire [71:0] engine_p0_addresses;
    wire [575:0] engine_p0_write_data;
    wire engine_p0_read_valid;
    wire [7:0] engine_p0_read_mask;
    wire [575:0] engine_p0_read_data;
    wire engine_p1_valid, engine_p1_ready, engine_p1_write;
    wire [7:0] engine_p1_mask;
    wire [71:0] engine_p1_addresses;
    wire [575:0] engine_p1_write_data;
    wire engine_p1_read_valid;
    wire [7:0] engine_p1_read_mask;
    wire [575:0] engine_p1_read_data;
    wire engine_physical_conflict;

    vector_stream_engine u_engine (
        .clk(clk), .rst_n(rst_n), .cursor_restart_valid(1'b0), .cursor_restart_mask(3'b000),
        .cursor_restart_ready(), .routine_start(routine_start),
        .req_valid(request_valid),
        .cycle_commit(cycle_commit),
        .vec_a_en(read_a_enable),
        .vec_b_en(read_b_enable),
        .vec_w_en(write_enable),
        .vec_a_restart(1'b0), .vec_b_restart(1'b0),
        .vec_cfg_a(config_a_id),
        .vec_cfg_b(config_b_id),
        .vec_cfg_w(config_w_id),
        .cfg_a_valid(config_a_valid),
        .cfg_a(config_a),
        .cfg_b_valid(config_b_valid),
        .cfg_b(config_b),
        .cfg_w_valid(config_w_valid),
        .cfg_w(config_w),
        .vec_w_data(engine_wr_data),
        .stream_in_ready(engine_input_ready),
        .stream_out_ready(engine_output_ready),
        .cfg_error(engine_config_error),
        .access_conflict(engine_access_conflict),
        .vec_a_valid(engine_read_a_valid),
        .vec_a_data(engine_read_a_data),
        .vec_b_valid(engine_read_b_valid),
        .vec_b_data(engine_read_b_data),
        .sp0_valid(engine_p0_valid),
        .sp0_ready(engine_p0_ready),
        .sp0_write(engine_p0_write),
        .sp0_bank_mask(engine_p0_mask),
        .sp0_addr(engine_p0_addresses),
        .sp0_wr_data(engine_p0_write_data),
        .sp0_rd_valid(engine_p0_read_valid),
        .sp0_rd_bank_mask(engine_p0_read_mask),
        .sp0_rd_data(engine_p0_read_data),
        .sp1_valid(engine_p1_valid),
        .sp1_ready(engine_p1_ready),
        .sp1_write(engine_p1_write),
        .sp1_bank_mask(engine_p1_mask),
        .sp1_addr(engine_p1_addresses),
        .sp1_wr_data(engine_p1_write_data),
        .sp1_rd_valid(engine_p1_read_valid),
        .sp1_rd_bank_mask(engine_p1_read_mask),
        .sp1_rd_data(engine_p1_read_data),
        .sp_conflict(engine_physical_conflict)
    );

    vector_scratchpad u_engine_scratchpad (
        .clk(clk), .rst_n(rst_n),
        .p0_valid(engine_p0_valid), .p0_ready(engine_p0_ready),
        .p0_write(engine_p0_write), .p0_bank_mask(engine_p0_mask),
        .p0_addr(engine_p0_addresses), .p0_wr_data(engine_p0_write_data),
        .p0_rd_valid(engine_p0_read_valid),
        .p0_rd_bank_mask(engine_p0_read_mask),
        .p0_rd_data(engine_p0_read_data),
        .p1_valid(engine_p1_valid), .p1_ready(engine_p1_ready),
        .p1_write(engine_p1_write), .p1_bank_mask(engine_p1_mask),
        .p1_addr(engine_p1_addresses), .p1_wr_data(engine_p1_write_data),
        .p1_rd_valid(engine_p1_read_valid),
        .p1_rd_bank_mask(engine_p1_read_mask),
        .p1_rd_data(engine_p1_read_data),
        .external_conflict(1'b0),
        .access_conflict(engine_physical_conflict)
    );

    // ------------------------------------------------------------------
    // Context-router checks use controlled provider responses.
    // ------------------------------------------------------------------
    reg router_cycle_valid, router_cycle_commit;
    reg [35:0] router_context;
    reg router_vector_input_ready, router_vector_output_ready;
    reg router_vector_configuration_error, router_vector_conflict;
    reg router_a_valid, router_b_valid, router_scalar_valid;
    reg [863:0] router_a_data, router_b_data;
    reg [26:0] router_scalar_data;
    reg router_phi_command_ready, router_phi_configuration_valid;
    reg router_phi_symbol_valid;
    reg [31:0] router_phi_nonzero, router_phi_sign;
    wire router_request_valid, router_vector_commit;
    wire router_read_a_enable, router_read_b_enable, router_write_enable;
    wire [5:0] router_config_a, router_config_b, router_config_w;
    wire [1:0] router_external_a_select, router_external_b_select;
    wire [863:0] router_routed_a, router_routed_b;
    wire [863:0] router_external_input_a, router_external_input_b;
    wire [26:0] router_routed_scalar;
    wire router_phi_command_valid;
    wire [1:0] router_phi_command;
    wire [5:0] router_phi_config_id;
    wire router_phi_symbol_ready;
    wire [31:0] router_nonzero, router_sign;
    wire router_input_ready, router_output_ready, router_contract_error;

    stream_context_router u_router (
        .clk(clk), .rst_n(rst_n),
        .cycle_valid(router_cycle_valid),
        .cycle_commit(router_cycle_commit),
        .stream_ctx(router_context),
        .vec_req_valid(router_request_valid),
        .vec_cycle_commit(router_vector_commit),
        .vec_a_en(router_read_a_enable),
        .vec_b_en(router_read_b_enable),
        .vec_w_en(router_write_enable),
        .vec_cfg_a(router_config_a),
        .vec_cfg_b(router_config_b),
        .vec_cfg_w(router_config_w),
        .vec_in_ready(router_vector_input_ready),
        .vec_out_ready(router_vector_output_ready),
        .vec_cfg_error(router_vector_configuration_error),
        .vec_access_conflict(router_vector_conflict),
        .vector_a_valid(router_a_valid), .vector_a_data(router_a_data),
        .vector_b_valid(router_b_valid), .vector_b_data(router_b_data),
        .scalar_a_valid(router_scalar_valid),
        .scalar_a_data(router_scalar_data),
        .scalar_b_valid(router_scalar_valid),
        .scalar_b_data(router_scalar_data),
        .ext_a_sel(router_external_a_select),
        .ext_b_sel(router_external_b_select),
        .out_vec_a(router_routed_a),
        .out_vec_b(router_routed_b),
        .out_scalar(router_routed_scalar),
        .external_input_a(router_external_input_a),
        .external_input_b(router_external_input_b),
        .phi_command_valid(router_phi_command_valid),
        .phi_command_ready(router_phi_command_ready),
        .phi_command(router_phi_command),
        .phi_cfg_id(router_phi_config_id),
        .phi_cfg_valid(router_phi_configuration_valid),
        .phi_symbol_valid(router_phi_symbol_valid),
        .phi_symbol_ready(router_phi_symbol_ready),
        .phi_nonzero(router_phi_nonzero), .phi_sign(router_phi_sign),
        .out_phi_nonzero(router_nonzero),
        .out_phi_sign(router_sign),
        .stream_in_ready(router_input_ready),
        .stream_out_ready(router_output_ready),
        .stream_contract_error(router_contract_error)
    );

    integer bank;
    integer stream_word;
    integer random_cycle;
    integer random_commit_count;
    integer random_mix;
    reg [31:0] random_lfsr;
    reg [575:0] held_stripe;
    initial begin
        gateway_unpack_valid = 0;
        gateway_unpack_word = 0;
        gateway_unpack_format = 0;
        gateway_unpack_packing = 0;
        gateway_pack_valid = 0;
        gateway_pack_format = 0;
        gateway_pack_packing = 0;
        gateway_pack_pe_data = 0;
        gateway_pack_sidecar_data = 0;
        gateway_pack_index_data = 0;
        gateway_pack_raw_data = 0;
        direct_p0_valid = 0; direct_p0_write = 0; direct_p0_mask = 0;
        direct_p0_addresses = 0; direct_p0_write_data = 0;
        direct_p1_valid = 0; direct_p1_write = 0; direct_p1_mask = 0;
        direct_p1_addresses = 0; direct_p1_write_data = 0;
        routine_start = 0; request_valid = 0; cycle_commit = 0;
        read_a_enable = 0; read_b_enable = 0; write_enable = 0;
        config_a_id = 0; config_b_id = 0; config_w_id = 0;
        config_a_valid = 0; config_b_valid = 0; config_w_valid = 0;
        config_a = 0; config_b = 0; config_w = 0;
        engine_wr_data = 0;
        router_cycle_valid = 0; router_cycle_commit = 0; router_context = 0;
        router_vector_input_ready = 1; router_vector_output_ready = 1;
        router_vector_configuration_error = 0; router_vector_conflict = 0;
        router_a_valid = 0; router_b_valid = 0; router_scalar_valid = 0;
        router_a_data = {32{27'h0123456}};
        router_b_data = {32{27'h0654321}};
        router_scalar_data = 27'h0001234;
        router_phi_command_ready = 1;
        router_phi_configuration_valid = 0;
        router_phi_symbol_valid = 0;
        router_phi_nonzero = 32'hffff0000;
        router_phi_sign = 32'ha5a55a5a;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // D18 exact sign-extension and round-trip packing.
        gateway_unpack_valid = 1;
        gateway_unpack_format = `RECON_ELEMENT_FORMAT_DATA18;
        gateway_unpack_packing = `RECON_PACKING_MODE_FOUR;
        gateway_unpack_word = {18'h3ffff, 18'h20000, 18'h00001, 18'h1ffff};
        #1;
        check(gateway_unpack_format_valid && gateway_pe_valid == 4'hf,
              "D18 gateway unpack validity");
        check(gateway_pe_data[26:0] == 27'h001ffff,
              "D18 positive sign extension");
        check(gateway_pe_data[53:27] == 27'h0000001,
              "D18 unit sign extension");
        check(gateway_pe_data[80:54] == 27'h7fe0000,
              "D18 negative sign extension");
        gateway_pack_valid = 1;
        gateway_pack_format = `RECON_ELEMENT_FORMAT_DATA18;
        gateway_pack_packing = `RECON_PACKING_MODE_FOUR;
        gateway_pack_pe_data = gateway_pe_data;
        #1;
        check(gateway_packed_valid &&
              gateway_packed_word == gateway_unpack_word,
              "D18 gateway round trip");
        gateway_pack_pe_data[26:18] = 9'h001;
        #1;
        check(!gateway_packed_valid && gateway_pack_range_error,
              "D18 gateway rejects implicit truncation");
        gateway_unpack_valid = 0; gateway_pack_valid = 0;

        // S27 is copied bit-for-bit; the remaining 18 physical bits are pad.
        gateway_unpack_valid = 1;
        gateway_unpack_format = `RECON_ELEMENT_FORMAT_SOLVER27;
        gateway_unpack_packing = `RECON_PACKING_MODE_TWO;
        gateway_unpack_word = {18'h2a155, 27'h7654321, 27'h0123456};
        #1;
        check(gateway_unpack_format_valid &&
              gateway_sidecar_valid == 2'b11 &&
              gateway_sidecar_data == {27'h7654321, 27'h0123456},
              "S27 gateway bit-exact unpack");
        gateway_pack_valid = 1;
        gateway_pack_format = `RECON_ELEMENT_FORMAT_SOLVER27;
        gateway_pack_packing = `RECON_PACKING_MODE_TWO;
        gateway_pack_sidecar_data = gateway_sidecar_data;
        #1;
        check(gateway_packed_valid &&
              gateway_packed_word[53:0] == gateway_sidecar_data &&
              gateway_packed_word[71:54] == 18'd0,
              "S27 gateway pack and zero padding");
        gateway_unpack_valid = 0; gateway_pack_valid = 0;

        // Seven index10 values fill 70 bits; the top two bits are pad.
        gateway_unpack_valid = 1;
        gateway_unpack_format = `RECON_ELEMENT_FORMAT_INDEX10;
        gateway_unpack_packing = `RECON_PACKING_MODE_SEVEN;
        gateway_unpack_word = {2'b11, 10'd1000, 10'd31, 10'd17,
                               10'd9, 10'd5, 10'd2, 10'd1};
        #1;
        check(gateway_unpack_format_valid &&
              gateway_index_valid == 7'h7f &&
              gateway_index_data[69:60] == 10'd1000 &&
              gateway_index_data[9:0] == 10'd1,
              "index10 gateway preserves first and seventh elements");
        gateway_pack_valid = 1;
        gateway_pack_format = `RECON_ELEMENT_FORMAT_INDEX10;
        gateway_pack_packing = `RECON_PACKING_MODE_SEVEN;
        gateway_pack_index_data = gateway_index_data;
        #1;
        check(gateway_packed_valid &&
              gateway_packed_word[69:0] == gateway_index_data &&
              gateway_packed_word[71:70] == 2'b00,
              "index10 gateway zeroes padding bits");
        gateway_unpack_valid = 0; gateway_pack_valid = 0;

        gateway_unpack_valid = 1;
        gateway_unpack_format = `RECON_ELEMENT_FORMAT_RAW64;
        gateway_unpack_packing = `RECON_PACKING_MODE_RAW72;
        gateway_unpack_word = 72'hdeadc0de123456789a;
        gateway_pack_valid = 1;
        gateway_pack_format = `RECON_ELEMENT_FORMAT_RAW64;
        gateway_pack_packing = `RECON_PACKING_MODE_RAW72;
        gateway_pack_raw_data = gateway_unpack_word;
        #1;
        check(gateway_raw_valid && gateway_raw_data == gateway_unpack_word &&
              gateway_packed_valid &&
              gateway_packed_word == gateway_unpack_word,
              "raw72 gateway passthrough");
        gateway_unpack_valid = 0; gateway_pack_valid = 0;

        // Direct bank write/read and conflict policy.
        direct_p0_valid = 1; direct_p0_write = 1; direct_p0_mask = 8'h01;
        direct_p0_addresses[8:0] = 9'd3;
        direct_p0_write_data[71:0] = 72'h123456789abcdef012;
        @(posedge clk); #1;
        direct_p0_write = 0;
        @(posedge clk); #1;
        check(direct_p0_read_valid &&
              direct_p0_read_data[71:0] == 72'h123456789abcdef012,
              "single-bank synchronous read");
        direct_p0_valid = 1; direct_p0_write = 0; direct_p0_mask = 8'h01;
        direct_p1_valid = 1; direct_p1_write = 0; direct_p1_mask = 8'h01;
        direct_p1_addresses[8:0] = 9'd3;
        #1;
        check(!direct_conflict && direct_p0_ready && direct_p1_ready,
              "two reads to one bank are legal");
        direct_p1_write = 1;
        #1;
        check(direct_conflict && !direct_p0_ready && !direct_p1_ready,
              "same-address read write conflict");
        direct_p1_addresses[8:0] = 9'd4;
        #1;
        check(!direct_conflict && direct_p0_ready && direct_p1_ready,
              "different-address read write is legal");
        direct_p0_valid = 0; direct_p1_valid = 0;
        @(posedge clk);

        // Write two complete D18 stripes through the stream engine.
        request_valid = 1; write_enable = 1; config_w_id = 6'd3;
        config_w_valid = 1;
        config_w = vector_configuration(16'd10, 16'd64,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 0, 1);
        engine_wr_data = stripe_pattern(8'h10);
        cycle_commit = 1;
        #1;
        check(engine_output_ready && !engine_config_error,
              "write stream configuration accepted");
        @(posedge clk); #1;
        engine_wr_data = stripe_pattern(8'h20);
        @(posedge clk); #1;
        cycle_commit = 0; request_valid = 0; write_enable = 0;

        // Reset stream ownership only; scratchpad content must survive.
        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        request_valid = 1; read_a_enable = 1; config_a_id = 6'd4;
        config_a_valid = 1;
        config_a = vector_configuration(16'd10, 16'd64,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
        cycle_commit = 0;
        #1;
        check(!engine_input_ready, "initial synchronous read fill stalls");
        @(posedge clk); #1;
        check(engine_input_ready && engine_read_a_valid &&
              engine_read_a_data == stripe_pattern(8'h10),
              "first stripe bypasses BRAM response");
        held_stripe = engine_read_a_data;
        @(posedge clk); #1;
        check(engine_input_ready && engine_read_a_data == held_stripe,
              "read stripe remains stable under backpressure");
        cycle_commit = 1;
        @(posedge clk); #1;
        check(engine_input_ready && engine_read_a_valid &&
              engine_read_a_data == stripe_pattern(8'h20),
              "steady stream has no prefetch bubble");
        @(posedge clk); #1;
        cycle_commit = 0; request_valid = 0; read_a_enable = 0;

        // Atomic read A + write uses both ports and advances only on commit.
        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        request_valid = 1; read_a_enable = 1; write_enable = 1;
        config_a_id = 6'd5; config_w_id = 6'd6;
        config_a = vector_configuration(16'd10, 16'd64,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
        config_w = vector_configuration(16'd20, 16'd64,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 0, 1);
        engine_wr_data = stripe_pattern(8'h30);
        cycle_commit = 0;
        @(posedge clk); #1;
        check(engine_input_ready && engine_output_ready,
              "read plus write inputs available");
        check(!engine_p1_write,
              "write cannot escape before cycle commit");
        cycle_commit = 1;
        @(posedge clk); #1;
        check(engine_read_a_data == stripe_pattern(8'h20),
              "read prefetch advances with atomic write");
        engine_wr_data = stripe_pattern(8'h40);
        @(posedge clk); #1;
        cycle_commit = 0; request_valid = 0;
        read_a_enable = 0; write_enable = 0;

        // Fill all 512 physical addresses, then exercise 2000 deterministic
        // cycles of independent producer and consumer backpressure. The data
        // embeds the physical address so a drop, duplicate or reorder fails.
        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        request_valid = 1; write_enable = 1; config_w_id = 6'd12;
        config_w_valid = 1;
        config_w = vector_configuration(16'd0, 16'd4096,
            `RECON_ELEMENT_FORMAT_RAW64, `RECON_PACKING_MODE_RAW72, 0, 1);
        cycle_commit = 1;
        for (stream_word = 0; stream_word < 512; stream_word = stream_word + 1) begin
            engine_wr_data = indexed_stripe_pattern(stream_word[8:0]);
            @(posedge clk); #1;
        end
        cycle_commit = 0; request_valid = 0; write_enable = 0;

        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        read_a_enable = 1; config_a_id = 6'd13; config_a_valid = 1;
        config_a = vector_configuration(16'd0, 16'd4096,
            `RECON_ELEMENT_FORMAT_RAW64, `RECON_PACKING_MODE_RAW72, 1, 0);
        random_lfsr = 32'h1aceb00c;
        random_commit_count = 0;
        $display("M4 random backpressure seed=0x%08x cycles=2000",
                 random_lfsr);
        for (random_cycle = 0; random_cycle < 2000;
                random_cycle = random_cycle + 1) begin
            request_valid = |random_lfsr[1:0];
            #1;
            cycle_commit = request_valid && engine_input_ready &&
                           (random_lfsr[3:2] == 2'b00);
            #1;
            if (cycle_commit) begin
                check(engine_read_a_valid,
                      "random commit requires a valid read stripe");
                check(engine_read_a_data ==
                      indexed_stripe_pattern(random_commit_count[8:0]),
                      "random backpressure preserves address order");
                random_commit_count = random_commit_count + 1;
            end
            @(posedge clk); #1;
            random_lfsr = lfsr_next(random_lfsr);
        end
        check(random_commit_count >= 300 && random_commit_count < 512,
              "random test must exercise substantial non-exhausted traffic");
        $display("M4 random backpressure commits=%0d", random_commit_count);
        cycle_commit = 0; request_valid = 0; read_a_enable = 0;

        // The first stripe at address 511 is legal. A second stripe would
        // address 512 and must raise the configuration/bounds flag instead of
        // silently wrapping to address zero.
        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        request_valid = 1; read_a_enable = 1; config_a_id = 6'd14;
        config_a_valid = 1;
        config_a = vector_configuration(16'd511, 16'd64,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
        cycle_commit = 0;
        @(posedge clk); #1;
        check(engine_input_ready && engine_read_a_valid,
              "boundary configuration serves address 511");
        cycle_commit = 1;
        @(posedge clk); #1;
        cycle_commit = 0;
        check(engine_config_error && !engine_input_ready && !engine_p0_valid &&
              !engine_p1_valid,
              "boundary overflow is flagged without address wrap");
        request_valid = 0; read_a_enable = 0;

        // Randomized legal R+R/R+W ownership and illegal R+R+W contexts use
        // different configuration IDs. Each iteration starts a new routine,
        // matching the engine's fixed logical-channel affinity contract.
        random_lfsr = 32'h5eed4a11;
        for (random_mix = 0; random_mix < 32;
                random_mix = random_mix + 1) begin
            routine_start = 1; request_valid = 0;
            @(posedge clk); #1;
            routine_start = 0;
            config_a_id = random_lfsr[5:0];
            config_b_id = random_lfsr[11:6];
            config_w_id = random_lfsr[17:12];
            config_a_valid = 1; config_b_valid = 1; config_w_valid = 1;
            config_a = vector_configuration(16'd0, 16'd32,
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
            config_b = vector_configuration(16'd1, 16'd32,
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
            config_w = vector_configuration(16'd2, 16'd32,
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 0, 1);
            read_a_enable = 0; read_b_enable = 0; write_enable = 0;
            case (random_lfsr[19:18])
                2'd0: begin read_a_enable = 1; read_b_enable = 1; end
                2'd1: begin read_a_enable = 1; write_enable = 1; end
                2'd2: begin read_b_enable = 1; write_enable = 1; end
                default: begin
                    read_a_enable = 1; read_b_enable = 1; write_enable = 1;
                end
            endcase
            request_valid = 1; cycle_commit = 0;
            #1;
            if (random_lfsr[19:18] == 2'd3) begin
                check(engine_access_conflict && !engine_p0_valid &&
                      !engine_p1_valid,
                      "random three-way context stalls before physical issue");
            end else begin
                check(!engine_access_conflict,
                      "random two-access context is structurally legal");
                @(posedge clk); #1;
                if (!(engine_input_ready && engine_output_ready))
                    $display("M4 random mix fail iter=%0d mode=%0d in=%0d out=%0d cfg=%0d a=%0d b=%0d p0v=%0d p1v=%0d bi=%0d br=%0d",
                        random_mix, random_lfsr[19:18], engine_input_ready,
                        engine_output_ready, engine_config_error,
                        engine_read_a_valid, engine_read_b_valid,
                        engine_p0_valid, engine_p1_valid,
                        u_engine.b_inflight, engine_p1_read_valid);
                check(engine_input_ready && engine_output_ready,
                      "random two-access context fills without ownership loss");
            end
            request_valid = 0; read_a_enable = 0; read_b_enable = 0;
            write_enable = 0;
            random_lfsr = lfsr_next(random_lfsr);
        end

        // Three logical accesses are rejected before any physical command.
        routine_start = 1;
        @(posedge clk); #1;
        routine_start = 0;
        request_valid = 1; read_a_enable = 1; read_b_enable = 1;
        write_enable = 1; config_a_id = 1; config_b_id = 2; config_w_id = 3;
        config_a = vector_configuration(0, 32,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1, 0);
        config_b = config_a;
        config_w = vector_configuration(0, 32,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 0, 1);
        #1;
        check(engine_access_conflict && !engine_input_ready &&
              !engine_output_ready && !engine_p0_valid && !engine_p1_valid,
              "three-access context stalls atomically");
        request_valid = 0; read_a_enable = 0; read_b_enable = 0;
        write_enable = 0;

        // Router source selection and Phi handshakes join the same commit.
        router_cycle_valid = 1;
        router_context = 36'd0;
        router_context[0] = 1'b1;
        router_context[8:3] = 6'd9;
        router_context[22:21] = `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A;
        router_context[24:23] =
            `RECON_EXTERNAL_STREAM_SOURCE_SCALAR_BROADCAST;
        router_context[33] = 1'b1;
        router_a_valid = 0; router_scalar_valid = 1;
        #1;
        check(!router_input_ready && !router_contract_error,
              "router propagates vector input stall");
        router_a_valid = 1;
        #1;
        check(router_input_ready &&
              router_external_a_select ==
                `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A &&
              router_external_b_select ==
                `RECON_EXTERNAL_STREAM_SOURCE_SCALAR_BROADCAST &&
              router_routed_a == router_a_data &&
              router_routed_b == router_b_data &&
              router_routed_scalar == router_scalar_data &&
              router_external_input_a == router_a_data &&
              router_external_input_b == {32{router_scalar_data}},
              "router distributes operand sources and selectors");
        router_cycle_commit = 1;
        #1;
        check(router_vector_commit,
              "router advances vector only with array commit");
        router_cycle_commit = 0;

        router_context = 36'd0;
        router_context[26:25] = `RECON_PHI_COMMAND_START;
        router_context[32:27] = 6'd7;
        router_phi_configuration_valid = 0;
        #1;
        check(!router_input_ready && !router_phi_command_valid,
              "Phi start waits for resident configuration");
        router_phi_configuration_valid = 1;
        #1;
        check(router_input_ready, "Phi start becomes ready");
        router_cycle_commit = 1;
        #1;
        check(router_phi_command_valid && router_phi_command_ready,
              "Phi start fires atomically with context commit");
        router_cycle_commit = 0;

        router_context = 36'd0;
        router_context[0] = 1; router_context[1] = 1; router_context[2] = 1;
        router_context[8:3] = 1; router_context[14:9] = 2;
        router_context[20:15] = 3; router_context[33] = 1;
        router_vector_conflict = 1;
        #1;
        check(router_contract_error && !router_input_ready &&
              !router_output_ready,
              "router exposes atomic stream conflict");

        $display("M4 STREAM TRANSPORT PASS");
        $finish;
    end
endmodule

`default_nettype wire
