`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m7_phi_stream_provider;
    reg clk = 1'b0;
    always #3.333 clk = ~clk;
    reg rst_n = 1'b0;
    reg abort_flush = 1'b0;
    reg [63:0] active_seed = 64'h0123_4567_89ab_cdef;
    reg [8:0] active_measurement_count = 9'd128;
    reg [10:0] active_signal_length = 11'd1024;
    reg [6:0] active_work_count = 7'd2;
    reg command_valid = 1'b0;
    wire command_ready;
    reg [1:0] command = `RECON_PHI_COMMAND_IDLE;
    reg [5:0] configuration_id = 0;
    reg configuration_valid = 1'b0;
    reg [`RECON_MEMORY_CONFIGURATION_W-1:0] configuration_data = 0;
    reg support_column_valid = 1'b0;
    wire support_column_ready;
    reg [`RECON_PHI_COLUMN_W-1:0] support_column = 0;
    wire cache_replay_valid;
    wire cache_replay_ready;
    wire [6:0] cache_replay_slot;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_replay_row_block;
    wire [`RECON_PHI_TAG_W-1:0] cache_replay_tag;
    wire cache_symbol_valid;
    wire cache_symbol_ready;
    wire [31:0] cache_nonzero;
    wire [31:0] cache_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] cache_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_row_block;
    wire [`RECON_PHI_TAG_W-1:0] cache_tag;
    reg cache_valid = 1'b0;
    wire phi_symbol_valid;
    reg phi_symbol_ready = 1'b0;
    wire [31:0] phi_nonzero;
    wire [31:0] phi_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] phi_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_row_block;
    wire [`RECON_PHI_TAG_W-1:0] phi_tag;
    wire provider_busy;
    wire stream_done;
    wire configuration_error;

    assign cache_symbol_valid = cache_replay_valid;
    assign cache_replay_ready = cache_symbol_ready;
    assign cache_nonzero = 32'hffff_ffff;
    assign cache_sign = {22'd0, cache_replay_slot} ^
                        {29'd0, cache_replay_row_block};
    assign cache_column = 10'd100 + cache_replay_slot;
    assign cache_row_block = cache_replay_row_block;
    assign cache_tag = cache_replay_tag;

    phi_stream_provider dut (
        .clk(clk), .rst_n(rst_n), .abort_flush(abort_flush),
        .active_seed(active_seed),
        .active_measurement_count(active_measurement_count),
        .active_signal_length(active_signal_length),
        .active_work_count(active_work_count),
        .support_list_count(active_work_count),
        .command_valid(command_valid), .command_ready(command_ready),
        .command(command), .configuration_id(configuration_id),
        .configuration_valid(configuration_valid),
        .configuration_data(configuration_data),
        .support_column_valid(support_column_valid),
        .support_column_ready(support_column_ready),
        .support_column(support_column),
        .cache_replay_valid(cache_replay_valid),
        .cache_replay_ready(cache_replay_ready),
        .cache_replay_slot(cache_replay_slot),
        .cache_replay_row_block(cache_replay_row_block),
        .cache_replay_tag(cache_replay_tag),
        .cache_symbol_valid(cache_symbol_valid),
        .cache_symbol_ready(cache_symbol_ready),
        .cache_nonzero(cache_nonzero), .cache_sign(cache_sign),
        .cache_column(cache_column), .cache_row_block(cache_row_block),
        .cache_tag(cache_tag), .cache_valid(cache_valid),
        .phi_symbol_valid(phi_symbol_valid),
        .phi_symbol_ready(phi_symbol_ready), .phi_nonzero(phi_nonzero),
        .phi_sign(phi_sign), .phi_column(phi_column),
        .phi_row_block(phi_row_block), .phi_tag(phi_tag),
        .provider_busy(provider_busy), .stream_done(stream_done),
        .configuration_error(configuration_error)
    );

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task build_configuration;
        input [15:0] base;
        input [15:0] count;
        input [11:0] stride;
        input [2:0] first_pair;
        input [1:0] pair_count_log2;
        input [2:0] mode;
        begin
            configuration_data = 0;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BASE_WORD_ADDRESS_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_BASE_WORD_ADDRESS_W] = base;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_COUNT_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_COUNT_W] = count;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_STRIDE_WORDS_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_STRIDE_WORDS_W] = stride;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_BASE_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_BANK_BASE_W] = first_pair;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_COUNT_LOG2_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_BANK_COUNT_LOG2_W] =
                               pair_count_log2;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_MODE_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_BANK_MODE_W] = mode;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_READ_ENABLE_LSB] = 1'b1;
            configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_MEMORY_SPACE_LSB +:
                               `RECON_MEMORY_CONFIGURATION_FIELD_MEMORY_SPACE_W] =
                               `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM;
        end
    endtask

    task start_stream;
        input [5:0] cfg_id;
        begin
            @(negedge clk);
            configuration_id = cfg_id;
            configuration_valid = 1'b1;
            command = `RECON_PHI_COMMAND_START;
            command_valid = 1'b1;
            #1;
            while (!command_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            command_valid = 1'b0;
            command = `RECON_PHI_COMMAND_IDLE;
        end
    endtask

    task stop_stream;
        begin
            @(negedge clk);
            command = `RECON_PHI_COMMAND_STOP;
            command_valid = 1'b1;
            #1;
            while (!command_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            command_valid = 1'b0;
            command = `RECON_PHI_COMMAND_IDLE;
        end
    endtask

    task send_support_column;
        input [`RECON_PHI_COLUMN_W-1:0] column;
        begin
            @(negedge clk);
            support_column = column;
            support_column_valid = 1'b1;
            #1;
            while (!support_column_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            support_column_valid = 1'b0;
        end
    endtask

    task consume_direct;
        input integer expected_words;
        input integer mode;
        input integer use_stalls;
        integer output_index;
        integer expected_column;
        integer expected_row;
        reg [31:0] held_nonzero;
        reg [31:0] held_sign;
        reg [`RECON_PHI_COLUMN_W-1:0] held_column;
        reg [`RECON_PHI_ROW_BLOCK_W-1:0] held_row;
        reg [`RECON_PHI_TAG_W-1:0] held_tag;
        reg stalled;
        integer stall_phase;
        begin
            output_index = 0;
            stalled = 1'b0;
            stall_phase = 0;
            while (output_index < expected_words) begin
                @(negedge clk);
                phi_symbol_ready = use_stalls ? ((stall_phase % 5) != 1 &&
                                                 (stall_phase % 5) != 2) : 1'b1;
                stall_phase = stall_phase + 1;
                @(posedge clk);
                if (stalled && (!phi_symbol_valid ||
                    phi_nonzero !== held_nonzero || phi_sign !== held_sign ||
                    phi_column !== held_column || phi_row_block !== held_row ||
                    phi_tag !== held_tag))
                    fail("provider payload changed while stalled");
                if (phi_symbol_valid && phi_symbol_ready) begin
                    case (mode)
                        0: begin
                            expected_column = output_index >> 2;
                            expected_row = output_index & 3;
                        end
                        1: begin
                            expected_column = output_index < 2 ? 3 : 17;
                            expected_row = output_index & 1;
                        end
                        2: begin
                            expected_column = 9;
                            expected_row = output_index & 1;
                        end
                        4: begin
                            expected_column = 100 + (output_index & 1);
                            expected_row = output_index >> 1;
                        end
                        default: begin
                            expected_column = 102 + (output_index >> 1);
                            expected_row = output_index & 1;
                        end
                    endcase
                    if (phi_column !== expected_column ||
                        phi_row_block !== expected_row)
                        fail("provider coordinate schedule mismatch");
                    if (phi_tag !== {2'b00, configuration_id})
                        fail("provider transaction tag mismatch");
                    if (mode != 3 && phi_nonzero !== 32'hffff_ffff)
                        fail("provider dense nonzero mask mismatch");
                    output_index = output_index + 1;
                end
                stalled = phi_symbol_valid && !phi_symbol_ready;
                held_nonzero = phi_nonzero;
                held_sign = phi_sign;
                held_column = phi_column;
                held_row = phi_row_block;
                held_tag = phi_tag;
            end
            @(negedge clk);
            phi_symbol_ready = 1'b0;
            if (!stream_done && provider_busy)
                fail("provider did not terminate after exact word count");
        end
    endtask

    task consume_tail;
        input integer expected_words;
        input integer blocks_per_column;
        integer output_index;
        integer drain_cycles;
        begin
            output_index = 0;
            phi_symbol_ready = 1'b1;
            while (output_index < expected_words) begin
                @(posedge clk);
                if (phi_symbol_valid && phi_symbol_ready) begin
                    if (phi_column !== output_index / blocks_per_column ||
                        phi_row_block !== output_index % blocks_per_column)
                        fail("provider tail coordinate schedule mismatch");
                    output_index = output_index + 1;
                end
            end
            @(negedge clk);
            phi_symbol_ready = 1'b0;
            drain_cycles = 0;
            while (provider_busy && drain_cycles < 16) begin
                @(posedge clk);
                drain_cycles = drain_cycles + 1;
                if (phi_symbol_valid)
                    fail("provider exposed padded row block");
            end
            if (provider_busy || !stream_done)
                fail("provider did not internally drain padded row block");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        build_configuration(0, 2, 1, 0, 1, 0);
        start_stream(6'd7);
        consume_direct(8, 0, 1);
        if (configuration_error)
            fail("sequential provider raised configuration error");
        $display("M7 PROVIDER SEQUENTIAL PASS");

        active_measurement_count = 9'd64;
        build_configuration(0, 2, 1, 0, 0, 1);
        start_stream(6'd8);
        fork
            begin
                send_support_column(10'd3);
                send_support_column(10'd17);
            end
            begin
                consume_direct(4, 1, 0);
            end
        join
        $display("M7 PROVIDER SUPPORT-LIST PASS");

        build_configuration(9, 2, 0, 0, 0, 2);
        start_stream(6'd9);
        consume_direct(4, 2, 0);
        $display("M7 PROVIDER REPEAT PASS");

        cache_valid = 1'b1;
        build_configuration(2, 2, 1, 0, 0, 3);
        start_stream(6'd10);
        consume_direct(4, 3, 1);
        $display("M7 PROVIDER CACHE PASS");

        active_work_count = 7'd2;
        build_configuration(0, 96, 1, 0, 0, 5);
        start_stream(6'd15);
        consume_direct(4, 4, 1);
        $display("M7 PROVIDER ROW-MAJOR CACHE PASS");

        cache_valid = 1'b0;
        build_configuration(0, 1, 1, 0, 0, 4);
        start_stream(6'd11);
        #1;
        if (!configuration_error || provider_busy)
            fail("provider accepted illegal mode");
        $display("M7 PROVIDER ERROR PASS");

        active_measurement_count = 9'd65;
        build_configuration(0, 2, 1, 0, 1, 0);
        start_stream(6'd13);
        consume_tail(6, 3);
        $display("M7 PROVIDER M65 TAIL PASS");

        active_measurement_count = 9'd96;
        build_configuration(0, 2, 1, 0, 1, 0);
        start_stream(6'd14);
        consume_tail(6, 3);
        $display("M7 PROVIDER M96 TAIL PASS");

        active_measurement_count = 9'd128;
        build_configuration(5, 16, 0, 0, 0, 2);
        start_stream(6'd12);
        while (!phi_symbol_valid) @(negedge clk);
        stop_stream();
        repeat (3) @(posedge clk);
        if (provider_busy || phi_symbol_valid)
            fail("STOP did not flush provider/generator");
        $display("M7 PROVIDER STOP PASS");
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        fail("provider timeout");
    end
endmodule

`default_nettype wire
