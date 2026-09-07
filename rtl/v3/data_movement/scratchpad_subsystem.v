`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module scratchpad_subsystem #(
    parameter integer BANK_COUNT = `RECON_VECTOR_MEMORY_BANKS,
    parameter integer ADDR_W = 9,
    parameter integer WORD_W = `RECON_MEMORY_BANK_WORD_W
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         execution_active,

    input  wire                         init_valid,
    output wire                         init_ready,
    input  wire [2:0]                   init_bank,
    input  wire [ADDR_W-1:0]            init_addr,
    input  wire [WORD_W-1:0]            init_data,

    input  wire                         preload_active,
    input  wire                         preload_p0_valid,
    output wire                         preload_p0_ready,
    input  wire                         preload_p0_write,
    input  wire [BANK_COUNT-1:0]        preload_p0_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] preload_p0_addr,
    input  wire [BANK_COUNT*WORD_W-1:0] preload_p0_data,
    input  wire                         preload_p1_valid,
    output wire                         preload_p1_ready,
    input  wire                         preload_p1_write,
    input  wire [BANK_COUNT-1:0]        preload_p1_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] preload_p1_addr,
    input  wire [BANK_COUNT*WORD_W-1:0] preload_p1_data,
    output wire                         preload_conflict,

    input  wire                         stream_p0_valid,
    output wire                         stream_p0_ready,
    input  wire                         stream_p0_write,
    input  wire [BANK_COUNT-1:0]        stream_p0_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] stream_p0_addr,
    input  wire [BANK_COUNT*WORD_W-1:0] stream_p0_wr_data,
    output wire                         stream_p0_rd_valid,
    output wire [BANK_COUNT-1:0]        stream_p0_rd_mask,
    output wire [BANK_COUNT*WORD_W-1:0] stream_p0_rd_data,
    input  wire                         stream_p1_valid,
    output wire                         stream_p1_ready,
    input  wire                         stream_p1_write,
    input  wire [BANK_COUNT-1:0]        stream_p1_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] stream_p1_addr,
    input  wire [BANK_COUNT*WORD_W-1:0] stream_p1_wr_data,
    output wire                         stream_p1_rd_valid,
    output wire [BANK_COUNT-1:0]        stream_p1_rd_mask,
    output wire [BANK_COUNT*WORD_W-1:0] stream_p1_rd_data,

    output wire                         stream_conflict,
    output wire                         status_conflict
);
    wire preload_select = !execution_active && preload_active;
    wire init_select = init_valid && !execution_active &&
                       !preload_select &&
                       !stream_p0_valid && !stream_p1_valid;

    wire [BANK_COUNT-1:0] init_mask =
        {{(BANK_COUNT-1){1'b0}}, 1'b1} << init_bank;
    wire [BANK_COUNT*ADDR_W-1:0] init_addr_bus =
        {BANK_COUNT{init_addr}};
    wire [BANK_COUNT*WORD_W-1:0] init_data_bus =
        {BANK_COUNT{init_data}};

    wire memory_p0_valid = preload_select ?
        preload_p0_valid : (init_select || stream_p0_valid);
    wire memory_p0_write = preload_select ?
        preload_p0_write : (init_select ? 1'b1 : stream_p0_write);
    wire [BANK_COUNT-1:0] memory_p0_mask = preload_select ?
        preload_p0_mask : (init_select ? init_mask : stream_p0_mask);
    wire [BANK_COUNT*ADDR_W-1:0] memory_p0_addr = preload_select ?
        preload_p0_addr : (init_select ? init_addr_bus : stream_p0_addr);
    wire [BANK_COUNT*WORD_W-1:0] memory_p0_data = preload_select ?
        preload_p0_data : (init_select ? init_data_bus : stream_p0_wr_data);

    wire memory_p1_valid = preload_select ?
        preload_p1_valid : stream_p1_valid;
    wire memory_p1_write = preload_select ?
        preload_p1_write : stream_p1_write;
    wire [BANK_COUNT-1:0] memory_p1_mask = preload_select ?
        preload_p1_mask : stream_p1_mask;
    wire [BANK_COUNT*ADDR_W-1:0] memory_p1_addr = preload_select ?
        preload_p1_addr : stream_p1_addr;
    wire [BANK_COUNT*WORD_W-1:0] memory_p1_data = preload_select ?
        preload_p1_data : stream_p1_wr_data;

    wire stream_address_match =
        stream_p0_addr[ADDR_W-1:0] == stream_p1_addr[ADDR_W-1:0];
    assign stream_conflict = stream_p0_valid && stream_p1_valid &&
        (|(stream_p0_mask & stream_p1_mask)) &&
        ((stream_p0_write && stream_p1_write) ||
         ((stream_p0_write || stream_p1_write) && stream_address_match));

    wire preload_ports_conflict = preload_p0_valid && preload_p1_valid &&
        (|(preload_p0_mask & preload_p1_mask));
    wire memory_conflict = preload_select && preload_ports_conflict;

    assign preload_p0_ready = preload_select && !preload_ports_conflict;
    assign preload_p1_ready = preload_select && !preload_ports_conflict;
    assign preload_conflict = preload_select && preload_ports_conflict;
    assign stream_p0_ready = !preload_select && !init_select;
    assign stream_p1_ready = !preload_select;

    reg init_ready_q;
    always @(posedge clk) begin
        if (!rst_n)
            init_ready_q <= 1'b0;
        else
            init_ready_q <= init_select;
    end
    assign init_ready = init_ready_q;

    wire memory_p0_ready;
    wire memory_p1_ready;
    vector_scratchpad #(
        .BANK_COUNT(BANK_COUNT),
        .ADDR_W(ADDR_W),
        .BANK_WORD_W(WORD_W),
        .USE_EXTERNAL_CONFLICT(1)
    ) u_memory (
        .clk(clk),
        .rst_n(rst_n),
        .p0_valid(memory_p0_valid),
        .p0_ready(memory_p0_ready),
        .p0_write(memory_p0_write),
        .p0_bank_mask(memory_p0_mask),
        .p0_addr(memory_p0_addr),
        .p0_wr_data(memory_p0_data),
        .p0_rd_valid(stream_p0_rd_valid),
        .p0_rd_bank_mask(stream_p0_rd_mask),
        .p0_rd_data(stream_p0_rd_data),
        .p1_valid(memory_p1_valid),
        .p1_ready(memory_p1_ready),
        .p1_write(memory_p1_write),
        .p1_bank_mask(memory_p1_mask),
        .p1_addr(memory_p1_addr),
        .p1_wr_data(memory_p1_data),
        .p1_rd_valid(stream_p1_rd_valid),
        .p1_rd_bank_mask(stream_p1_rd_mask),
        .p1_rd_data(stream_p1_rd_data),
        .external_conflict(memory_conflict),
        .access_conflict(status_conflict)
    );

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            if (init_valid)
                assert(!execution_active);
            if (preload_active || preload_p0_valid || preload_p1_valid)
                assert(!execution_active);
        end
    end
`endif
endmodule

`default_nettype wire
