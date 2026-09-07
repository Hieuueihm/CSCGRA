`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "m7_golden.vh"

module tb_m7_phi_generator;
    reg clk = 1'b0;
    always #3.333 clk = ~clk;

    reg rst_n = 1'b0;
    reg flush = 1'b0;
    reg request_valid = 1'b0;
    wire request_ready;
    reg [63:0] request_seed = 64'd0;
    reg [`RECON_PHI_COLUMN_W-1:0] request_column = 0;
    reg [`RECON_PHI_ROW_PAIR_W-1:0] request_row_pair = 0;
    reg [`RECON_PHI_TAG_W-1:0] request_tag = 0;
    reg [8:0] request_measurement_count = 0;
    wire symbol_valid;
    reg symbol_ready = 1'b0;
    wire [31:0] symbol_nonzero;
    wire [31:0] symbol_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] symbol_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] symbol_row_block;
    wire [`RECON_PHI_TAG_W-1:0] symbol_tag;

    reg [63:0] case_seed [0:`M7_PHI_CASE_COUNT-1];
    reg [`RECON_PHI_COLUMN_W-1:0] case_column [0:`M7_PHI_CASE_COUNT-1];
    reg [`RECON_PHI_ROW_PAIR_W-1:0] case_row_pair [0:`M7_PHI_CASE_COUNT-1];
    reg [`RECON_PHI_TAG_W-1:0] case_tag [0:`M7_PHI_CASE_COUNT-1];
    reg [8:0] case_measurement [0:`M7_PHI_CASE_COUNT-1];
    reg [31:0] case_word0 [0:`M7_PHI_CASE_COUNT-1];
    reg [31:0] case_word1 [0:`M7_PHI_CASE_COUNT-1];
    reg [31:0] case_mask0 [0:`M7_PHI_CASE_COUNT-1];
    reg [31:0] case_mask1 [0:`M7_PHI_CASE_COUNT-1];

    phi_symbol_generator dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .phi_request_valid(request_valid),
        .phi_request_ready(request_ready),
        .phi_request_seed(request_seed), .phi_request_column(request_column),
        .phi_request_row_pair(request_row_pair), .phi_request_tag(request_tag),
        .phi_request_measurement_count(request_measurement_count),
        .phi_symbol_valid(symbol_valid), .phi_symbol_ready(symbol_ready),
        .phi_nonzero_bits(symbol_nonzero), .phi_sign_bits(symbol_sign),
        .phi_symbol_column(symbol_column),
        .phi_symbol_row_block(symbol_row_block), .phi_symbol_tag(symbol_tag)
    );

    integer cycle_count = 0;
    always @(posedge clk)
        cycle_count = cycle_count + 1;

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task drive_case;
        input integer case_index;
        output integer accept_cycle;
        begin
            @(negedge clk);
            request_seed = case_seed[case_index];
            request_column = case_column[case_index];
            request_row_pair = case_row_pair[case_index];
            request_tag = case_tag[case_index];
            request_measurement_count = case_measurement[case_index];
            request_valid = 1'b1;
            while (!request_ready) @(negedge clk);
            @(posedge clk);
            accept_cycle = cycle_count;
            @(negedge clk);
            request_valid = 1'b0;
        end
    endtask

    integer first_accept_cycle;
    integer first_response_cycle;
    integer first_core_cycle;
    integer accepted_cycle;
    integer output_index;
    integer previous_output_cycle;
    integer expected_case;
    reg expected_word_select;
    reg [31:0] held_nonzero;
    reg [31:0] held_sign;
    reg [`RECON_PHI_COLUMN_W-1:0] held_column;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] held_row;
    reg [`RECON_PHI_TAG_W-1:0] held_tag;
    reg was_stalled;

    task consume_sequence;
        input integer use_stalls;
        input integer check_rate;
        begin
            output_index = 0;
            previous_output_cycle = -1;
            first_response_cycle = -1;
            first_core_cycle = -1;
            was_stalled = 1'b0;
            while (output_index < 2 * `M7_PHI_CASE_COUNT) begin
                @(negedge clk);
                symbol_ready = use_stalls ? ((cycle_count % 7) != 2 &&
                                             (cycle_count % 7) != 3) : 1'b1;
                @(posedge clk);
                if (dut.core_valid && first_core_cycle < 0)
                    first_core_cycle = cycle_count;
                if (was_stalled) begin
                    if (!symbol_valid || symbol_nonzero !== held_nonzero ||
                        symbol_sign !== held_sign || symbol_column !== held_column ||
                        symbol_row_block !== held_row || symbol_tag !== held_tag)
                        fail("generator payload changed while stalled");
                end
                if (symbol_valid && symbol_ready) begin
                    expected_case = output_index >> 1;
                    expected_word_select = output_index[0];
                    if (symbol_column !== case_column[expected_case] ||
                        symbol_row_block !==
                            {case_row_pair[expected_case], expected_word_select} ||
                        symbol_tag !== case_tag[expected_case])
                        fail("generator coordinate/tag mismatch");
                    if (symbol_sign !== (expected_word_select ?
                                         case_word1[expected_case] :
                                         case_word0[expected_case]))
                        fail("generator Threefry KAT mismatch");
                    if (symbol_nonzero !== (expected_word_select ?
                                            case_mask1[expected_case] :
                                            case_mask0[expected_case]))
                        fail("generator tail lane mask mismatch");
                    if (first_response_cycle < 0)
                        first_response_cycle = cycle_count;
                    if (check_rate && previous_output_cycle >= 0 &&
                        cycle_count != previous_output_cycle + 1)
                        fail("gearbox did not sustain one word per cycle");
                    previous_output_cycle = cycle_count;
                    output_index = output_index + 1;
                end
                was_stalled = symbol_valid && !symbol_ready;
                held_nonzero = symbol_nonzero;
                held_sign = symbol_sign;
                held_column = symbol_column;
                held_row = symbol_row_block;
                held_tag = symbol_tag;
            end
            @(negedge clk);
            symbol_ready = 1'b0;
        end
    endtask

    integer drive_index;
    initial begin
        case_seed[0] = `M7_PHI_SEED_0;
        case_column[0] = `M7_PHI_COLUMN_0;
        case_row_pair[0] = `M7_PHI_ROW_PAIR_0;
        case_measurement[0] = `M7_PHI_MEASUREMENT_0;
        case_tag[0] = `M7_PHI_TAG_0;
        case_word0[0] = `M7_PHI_WORD0_0;
        case_word1[0] = `M7_PHI_WORD1_0;
        case_mask0[0] = `M7_PHI_MASK0_0;
        case_mask1[0] = `M7_PHI_MASK1_0;
        case_seed[1] = `M7_PHI_SEED_1;
        case_column[1] = `M7_PHI_COLUMN_1;
        case_row_pair[1] = `M7_PHI_ROW_PAIR_1;
        case_measurement[1] = `M7_PHI_MEASUREMENT_1;
        case_tag[1] = `M7_PHI_TAG_1;
        case_word0[1] = `M7_PHI_WORD0_1;
        case_word1[1] = `M7_PHI_WORD1_1;
        case_mask0[1] = `M7_PHI_MASK0_1;
        case_mask1[1] = `M7_PHI_MASK1_1;
        case_seed[2] = `M7_PHI_SEED_2;
        case_column[2] = `M7_PHI_COLUMN_2;
        case_row_pair[2] = `M7_PHI_ROW_PAIR_2;
        case_measurement[2] = `M7_PHI_MEASUREMENT_2;
        case_tag[2] = `M7_PHI_TAG_2;
        case_word0[2] = `M7_PHI_WORD0_2;
        case_word1[2] = `M7_PHI_WORD1_2;
        case_mask0[2] = `M7_PHI_MASK0_2;
        case_mask1[2] = `M7_PHI_MASK1_2;
        case_seed[3] = `M7_PHI_SEED_3;
        case_column[3] = `M7_PHI_COLUMN_3;
        case_row_pair[3] = `M7_PHI_ROW_PAIR_3;
        case_measurement[3] = `M7_PHI_MEASUREMENT_3;
        case_tag[3] = `M7_PHI_TAG_3;
        case_word0[3] = `M7_PHI_WORD0_3;
        case_word1[3] = `M7_PHI_WORD1_3;
        case_mask0[3] = `M7_PHI_MASK0_3;
        case_mask1[3] = `M7_PHI_MASK1_3;
        case_seed[4] = `M7_PHI_SEED_4;
        case_column[4] = `M7_PHI_COLUMN_4;
        case_row_pair[4] = `M7_PHI_ROW_PAIR_4;
        case_measurement[4] = `M7_PHI_MEASUREMENT_4;
        case_tag[4] = `M7_PHI_TAG_4;
        case_word0[4] = `M7_PHI_WORD0_4;
        case_word1[4] = `M7_PHI_WORD1_4;
        case_mask0[4] = `M7_PHI_MASK0_4;
        case_mask1[4] = `M7_PHI_MASK1_4;
        case_seed[5] = `M7_PHI_SEED_5;
        case_column[5] = `M7_PHI_COLUMN_5;
        case_row_pair[5] = `M7_PHI_ROW_PAIR_5;
        case_measurement[5] = `M7_PHI_MEASUREMENT_5;
        case_tag[5] = `M7_PHI_TAG_5;
        case_word0[5] = `M7_PHI_WORD0_5;
        case_word1[5] = `M7_PHI_WORD1_5;
        case_mask0[5] = `M7_PHI_MASK0_5;
        case_mask1[5] = `M7_PHI_MASK1_5;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        fork
            begin
                for (drive_index = 0; drive_index < `M7_PHI_CASE_COUNT;
                     drive_index = drive_index + 1) begin
                    drive_case(drive_index, accepted_cycle);
                    if (drive_index == 0)
                        first_accept_cycle = accepted_cycle;
                end
            end
            begin
                consume_sequence(0, 1);
            end
        join
        if (first_response_cycle - first_accept_cycle - 1 != 21) begin
            fail("Threefry first response latency is not 21 cycles");
        end

        @(negedge clk);
        flush = 1'b1;
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        fork
            begin
                for (drive_index = 0; drive_index < `M7_PHI_CASE_COUNT;
                     drive_index = drive_index + 1)
                    drive_case(drive_index, accepted_cycle);
            end
            begin
                consume_sequence(1, 0);
            end
        join

        $display("M7 THREEFRY/GEARBOX PASS");
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk);
        fail("generator timeout");
    end
endmodule

`default_nettype wire
