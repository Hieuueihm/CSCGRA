`timescale 1ns/1ps
`default_nettype none

module execution_event_profile_monitor (
    input  wire clk,
    input  wire rst_n,
    input  wire run_start,
    input  wire engine_busy,
    input  wire phi_generate_fire,
    input  wire phi_replay_request_fire,
    input  wire phi_replay_response_fire,
    input  wire phi_cache_fill_fire,
    input  wire phi_output_fire,
    input  wire selection_fire,
    input  wire dma_read_address_valid,
    input  wire dma_read_address_ready,
    input  wire dma_read_data_valid,
    input  wire dma_read_data_ready,
    input  wire dma_write_address_valid,
    input  wire dma_write_address_ready,
    input  wire dma_write_data_valid,
    input  wire dma_write_data_ready,
    input  wire dma_write_response_valid,
    input  wire dma_write_response_ready,
    input  wire writeback_active,
    output reg  [63:0] phi_generate_requests,
    output reg  [63:0] phi_replay_requests,
    output reg  [63:0] phi_replay_responses,
    output reg  [63:0] phi_cache_fills,
    output reg  [63:0] phi_output_symbols,
    output reg  [63:0] selection_accepts,
    output reg  [63:0] dma_read_requests,
    output reg  [63:0] dma_read_beats,
    output reg  [63:0] dma_write_requests,
    output reg  [63:0] dma_write_beats,
    output reg  [63:0] dma_write_responses,
    output reg  [63:0] result_drain_cycles,
    output reg  [63:0] result_drain_beats
);
    wire dma_read_address_fire =
        dma_read_address_valid && dma_read_address_ready;
    wire dma_read_data_fire = dma_read_data_valid && dma_read_data_ready;
    wire dma_write_address_fire =
        dma_write_address_valid && dma_write_address_ready;
    wire dma_write_data_fire = dma_write_data_valid && dma_write_data_ready;
    wire dma_write_response_fire =
        dma_write_response_valid && dma_write_response_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phi_generate_requests <= 64'd0;
            phi_replay_requests <= 64'd0;
            phi_replay_responses <= 64'd0;
            phi_cache_fills <= 64'd0;
            phi_output_symbols <= 64'd0;
            selection_accepts <= 64'd0;
            dma_read_requests <= 64'd0;
            dma_read_beats <= 64'd0;
            dma_write_requests <= 64'd0;
            dma_write_beats <= 64'd0;
            dma_write_responses <= 64'd0;
            result_drain_cycles <= 64'd0;
            result_drain_beats <= 64'd0;
        end else if (run_start) begin
            phi_generate_requests <= 64'd0;
            phi_replay_requests <= 64'd0;
            phi_replay_responses <= 64'd0;
            phi_cache_fills <= 64'd0;
            phi_output_symbols <= 64'd0;
            selection_accepts <= 64'd0;
            dma_read_requests <= 64'd0;
            dma_read_beats <= 64'd0;
            dma_write_requests <= 64'd0;
            dma_write_beats <= 64'd0;
            dma_write_responses <= 64'd0;
            result_drain_cycles <= 64'd0;
            result_drain_beats <= 64'd0;
        end else if (engine_busy) begin
            if (phi_generate_fire)
                phi_generate_requests <= phi_generate_requests + 64'd1;
            if (phi_replay_request_fire)
                phi_replay_requests <= phi_replay_requests + 64'd1;
            if (phi_replay_response_fire)
                phi_replay_responses <= phi_replay_responses + 64'd1;
            if (phi_cache_fill_fire)
                phi_cache_fills <= phi_cache_fills + 64'd1;
            if (phi_output_fire)
                phi_output_symbols <= phi_output_symbols + 64'd1;
            if (selection_fire)
                selection_accepts <= selection_accepts + 64'd1;
            if (dma_read_address_fire)
                dma_read_requests <= dma_read_requests + 64'd1;
            if (dma_read_data_fire)
                dma_read_beats <= dma_read_beats + 64'd1;
            if (dma_write_address_fire)
                dma_write_requests <= dma_write_requests + 64'd1;
            if (dma_write_data_fire)
                dma_write_beats <= dma_write_beats + 64'd1;
            if (dma_write_response_fire)
                dma_write_responses <= dma_write_responses + 64'd1;
            if (writeback_active)
                result_drain_cycles <= result_drain_cycles + 64'd1;
            if (writeback_active && dma_write_data_fire)
                result_drain_beats <= result_drain_beats + 64'd1;
        end
    end
endmodule

`default_nettype wire
