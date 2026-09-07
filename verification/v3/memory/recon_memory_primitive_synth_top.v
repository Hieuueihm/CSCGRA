`timescale 1ns/1ps
`default_nettype none

module recon_memory_primitive_synth_top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         entry_write_enable,
    input  wire [6:0]   entry_write_address,
    input  wire [36:0]  entry_write_data,
    input  wire         entry_read_enable,
    input  wire [6:0]   entry_read_address,
    output wire         entry_read_valid,
    output wire [36:0]  entry_read_data,
    input  wire         map_clear_valid,
    input  wire         map_write_valid,
    input  wire [9:0]   map_write_index,
    input  wire [6:0]   map_write_slot,
    input  wire         map_query0_valid,
    input  wire [9:0]   map_query0_index,
    output wire         map_query0_response_valid,
    output wire         map_query0_member,
    output wire [6:0]   map_query0_slot,
    input  wire         map_query1_valid,
    input  wire [9:0]   map_query1_index,
    output wire         map_query1_response_valid,
    output wire         map_query1_member,
    output wire [6:0]   map_query1_slot,
    output wire         map_epoch_wrap_fault
);
    recon_sdp_ram #(
        .DATA_W(37), .DEPTH(96), .ADDR_W(7), .INITIALIZE_TO_ZERO(0)
    ) u_entry_ram (
        .clk(clk), .rst_n(rst_n),
        .write_enable(entry_write_enable),
        .write_address(entry_write_address), .write_data(entry_write_data),
        .read_enable(entry_read_enable), .read_address(entry_read_address),
        .read_valid(entry_read_valid), .read_data(entry_read_data)
    );

    recon_epoch_slot_map #(
        .INDEX_W(10), .SLOT_W(7), .EPOCH_W(16), .DEPTH(1024)
    ) u_slot_map (
        .clk(clk), .rst_n(rst_n), .clear_valid(map_clear_valid),
        .write_valid(map_write_valid), .write_index(map_write_index),
        .write_slot(map_write_slot), .query0_valid(map_query0_valid),
        .query0_index(map_query0_index),
        .query0_response_valid(map_query0_response_valid),
        .query0_member(map_query0_member), .query0_slot(map_query0_slot),
        .query1_valid(map_query1_valid), .query1_index(map_query1_index),
        .query1_response_valid(map_query1_response_valid),
        .query1_member(map_query1_member), .query1_slot(map_query1_slot),
        .epoch_wrap_fault(map_epoch_wrap_fault)
    );
endmodule

`default_nettype wire
