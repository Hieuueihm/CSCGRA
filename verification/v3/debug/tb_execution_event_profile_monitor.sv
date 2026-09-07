`timescale 1ns/1ps
`default_nettype none

module tb_execution_event_profile_monitor;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg run_start = 1'b0;
    reg engine_busy = 1'b0;
    reg phi_generate_fire = 1'b0;
    reg phi_replay_request_fire = 1'b0;
    reg phi_replay_response_fire = 1'b0;
    reg phi_cache_fill_fire = 1'b0;
    reg phi_output_fire = 1'b0;
    reg selection_fire = 1'b0;
    reg dma_read_address_valid = 1'b0;
    reg dma_read_address_ready = 1'b0;
    reg dma_read_data_valid = 1'b0;
    reg dma_read_data_ready = 1'b0;
    reg dma_write_address_valid = 1'b0;
    reg dma_write_address_ready = 1'b0;
    reg dma_write_data_valid = 1'b0;
    reg dma_write_data_ready = 1'b0;
    reg dma_write_response_valid = 1'b0;
    reg dma_write_response_ready = 1'b0;
    reg writeback_active = 1'b0;
    wire [63:0] phi_generate_requests;
    wire [63:0] phi_replay_requests;
    wire [63:0] phi_replay_responses;
    wire [63:0] phi_cache_fills;
    wire [63:0] phi_output_symbols;
    wire [63:0] selection_accepts;
    wire [63:0] dma_read_requests;
    wire [63:0] dma_read_beats;
    wire [63:0] dma_write_requests;
    wire [63:0] dma_write_beats;
    wire [63:0] dma_write_responses;
    wire [63:0] result_drain_cycles;
    wire [63:0] result_drain_beats;

    integer failures = 0;
    task automatic check;
        input condition;
        input [255:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic clock_once;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    execution_event_profile_monitor dut (.*);

    initial begin
        repeat (3) clock_once();
        rst_n = 1'b1;
        run_start = 1'b1;
        clock_once();
        run_start = 1'b0;
        engine_busy = 1'b1;

        phi_generate_fire = 1'b1;
        phi_replay_request_fire = 1'b1;
        phi_replay_response_fire = 1'b1;
        phi_cache_fill_fire = 1'b1;
        phi_output_fire = 1'b1;
        selection_fire = 1'b1;
        dma_read_address_valid = 1'b1;
        dma_read_address_ready = 1'b1;
        dma_read_data_valid = 1'b1;
        dma_read_data_ready = 1'b1;
        dma_write_address_valid = 1'b1;
        dma_write_address_ready = 1'b1;
        dma_write_data_valid = 1'b1;
        dma_write_data_ready = 1'b1;
        dma_write_response_valid = 1'b1;
        dma_write_response_ready = 1'b1;
        writeback_active = 1'b1;
        clock_once();

        phi_generate_fire = 1'b0;
        phi_replay_request_fire = 1'b0;
        phi_replay_response_fire = 1'b0;
        phi_cache_fill_fire = 1'b0;
        phi_output_fire = 1'b0;
        selection_fire = 1'b0;
        dma_read_address_ready = 1'b0;
        dma_read_data_ready = 1'b0;
        dma_write_address_ready = 1'b0;
        dma_write_data_ready = 1'b0;
        dma_write_response_ready = 1'b0;
        clock_once();

        dma_read_address_valid = 1'b0;
        dma_read_address_ready = 1'b1;
        dma_read_data_valid = 1'b0;
        dma_read_data_ready = 1'b1;
        dma_write_address_valid = 1'b0;
        dma_write_address_ready = 1'b1;
        dma_write_data_valid = 1'b0;
        dma_write_data_ready = 1'b1;
        dma_write_response_valid = 1'b0;
        dma_write_response_ready = 1'b1;
        writeback_active = 1'b0;
        clock_once();

        check(phi_generate_requests == 1, "Phi generate pulse count");
        check(phi_replay_requests == 1, "Phi replay request count");
        check(phi_replay_responses == 1, "Phi replay response count");
        check(phi_cache_fills == 1, "Phi cache fill count");
        check(phi_output_symbols == 1, "Phi output symbol count");
        check(selection_accepts == 1, "selection accept count");
        check(dma_read_requests == 1, "DMA read request handshake");
        check(dma_read_beats == 1, "DMA read beat handshake");
        check(dma_write_requests == 1, "DMA write request handshake");
        check(dma_write_beats == 1, "DMA write beat handshake");
        check(dma_write_responses == 1, "DMA write response handshake");
        check(result_drain_cycles == 2, "result drain active cycles");
        check(result_drain_beats == 1, "result drain accepted beats");

        phi_generate_fire = 1'b1;
        phi_replay_request_fire = 1'b1;
        phi_replay_response_fire = 1'b1;
        phi_cache_fill_fire = 1'b1;
        phi_output_fire = 1'b1;
        selection_fire = 1'b1;
        dma_read_address_valid = 1'b1;
        dma_read_address_ready = 1'b1;
        dma_read_data_valid = 1'b1;
        dma_read_data_ready = 1'b1;
        dma_write_address_valid = 1'b1;
        dma_write_address_ready = 1'b1;
        dma_write_data_valid = 1'b1;
        dma_write_data_ready = 1'b1;
        dma_write_response_valid = 1'b1;
        dma_write_response_ready = 1'b1;
        writeback_active = 1'b1;
        run_start = 1'b1;
        clock_once();
        check(phi_generate_requests == 0, "run start resets Phi counters");
        check(dma_read_requests == 0, "run start resets DMA counters");
        check(result_drain_cycles == 0, "run start resets drain counters");

        run_start = 1'b0;
        engine_busy = 1'b0;
        phi_generate_fire = 1'b1;
        phi_replay_request_fire = 1'b0;
        phi_replay_response_fire = 1'b0;
        phi_cache_fill_fire = 1'b0;
        phi_output_fire = 1'b0;
        selection_fire = 1'b0;
        dma_read_address_ready = 1'b1;
        writeback_active = 1'b0;
        clock_once();
        check(phi_generate_requests == 0, "idle Phi event ignored");
        check(dma_read_requests == 0, "idle DMA event ignored");

        if (failures == 0)
            $display("EXECUTION EVENT PROFILE MONITOR PASS");
        else
            $display("FAIL: execution event profile failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
