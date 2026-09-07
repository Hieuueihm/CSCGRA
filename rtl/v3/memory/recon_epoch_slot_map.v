`timescale 1ns/1ps
`default_nettype none

module recon_epoch_slot_map #(
    parameter integer INDEX_W = 10,
    parameter integer SLOT_W = 7,
    parameter integer EPOCH_W = 16,
    parameter integer DEPTH = (1 << INDEX_W)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clear_valid,
    input  wire                  write_valid,
    input  wire [INDEX_W-1:0]    write_index,
    input  wire [SLOT_W-1:0]     write_slot,
    input  wire                  query0_valid,
    input  wire [INDEX_W-1:0]    query0_index,
    output wire                  query0_response_valid,
    output wire                  query0_member,
    output wire [SLOT_W-1:0]     query0_slot,
    input  wire                  query1_valid,
    input  wire [INDEX_W-1:0]    query1_index,
    output wire                  query1_response_valid,
    output wire                  query1_member,
    output wire [SLOT_W-1:0]     query1_slot,
    output reg                   epoch_wrap_fault
);
    localparam integer MAP_W = EPOCH_W + SLOT_W;

    reg [EPOCH_W-1:0] active_epoch;
    wire map_write_enable = write_valid && !clear_valid && !epoch_wrap_fault;
    wire query0_enable = query0_valid && !clear_valid && !epoch_wrap_fault;
    wire query1_enable = query1_valid && !clear_valid && !epoch_wrap_fault;
    wire [MAP_W-1:0] map_write_data = {active_epoch, write_slot};
    wire map0_valid;
    wire map1_valid;
    wire [MAP_W-1:0] map0_data;
    wire [MAP_W-1:0] map1_data;

    recon_1w2r_ram #(
        .DATA_W(MAP_W),
        .DEPTH(DEPTH),
        .ADDR_W(INDEX_W),
        .INITIALIZE_TO_ZERO(1)
    ) u_map_memory (
        .clk(clk),
        .rst_n(rst_n),
        .write_enable(map_write_enable),
        .write_address(write_index),
        .write_data(map_write_data),
        .read0_enable(query0_enable),
        .read0_address(query0_index),
        .read0_valid(map0_valid),
        .read0_data(map0_data),
        .read1_enable(query1_enable),
        .read1_address(query1_index),
        .read1_valid(map1_valid),
        .read1_data(map1_data)
    );

    assign query0_response_valid = map0_valid;
    assign query0_slot = map0_data[SLOT_W-1:0];
    assign query0_member = map0_valid && !epoch_wrap_fault &&
        (map0_data[MAP_W-1:SLOT_W] == active_epoch);
    assign query1_response_valid = map1_valid;
    assign query1_slot = map1_data[SLOT_W-1:0];
    assign query1_member = map1_valid && !epoch_wrap_fault &&
        (map1_data[MAP_W-1:SLOT_W] == active_epoch);

    always @(posedge clk) begin
        if (!rst_n) begin
            active_epoch <= {{(EPOCH_W-1){1'b0}}, 1'b1};
            epoch_wrap_fault <= 1'b0;
        end else if (clear_valid && !epoch_wrap_fault) begin
            if (&active_epoch)
                epoch_wrap_fault <= 1'b1;
            else
                active_epoch <= active_epoch + 1'b1;
        end
    end
endmodule

`default_nettype wire
