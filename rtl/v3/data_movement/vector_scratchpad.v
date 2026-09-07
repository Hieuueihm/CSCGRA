`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Eight independent 72x512 true-dual-port banks.  A logical command is
// accepted atomically across its bank mask; no subset of a stripe can fire.
// Data arrays are deliberately not reset so Vivado can infer block RAM.
module vector_scratchpad #(
    parameter integer BANK_COUNT = `RECON_VECTOR_MEMORY_BANKS,
    parameter integer BANK_DEPTH = `RECON_MEMORY_BANK_DEPTH,
    parameter integer BANK_WORD_W = `RECON_MEMORY_BANK_WORD_W,
    parameter integer ADDR_W = 9,
    parameter integer USE_EXTERNAL_CONFLICT = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         p0_valid,
    output wire                         p0_ready,
    input  wire                         p0_write,
    input  wire [BANK_COUNT-1:0]        p0_bank_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] p0_addr,
    input  wire [BANK_COUNT*BANK_WORD_W-1:0] p0_wr_data,
    output reg                          p0_rd_valid,
    output reg  [BANK_COUNT-1:0]        p0_rd_bank_mask,
    output wire [BANK_COUNT*BANK_WORD_W-1:0] p0_rd_data,

    input  wire                         p1_valid,
    output wire                         p1_ready,
    input  wire                         p1_write,
    input  wire [BANK_COUNT-1:0]        p1_bank_mask,
    input  wire [BANK_COUNT*ADDR_W-1:0] p1_addr,
    input  wire [BANK_COUNT*BANK_WORD_W-1:0] p1_wr_data,
    output reg                          p1_rd_valid,
    output reg  [BANK_COUNT-1:0]        p1_rd_bank_mask,
    output wire [BANK_COUNT*BANK_WORD_W-1:0] p1_rd_data,

    input  wire                         external_conflict,
    output wire                         access_conflict
);
    integer conflict_bank;
    reg conflict_comb;
    always @* begin
        conflict_comb = 1'b0;
        for (conflict_bank = 0; conflict_bank < BANK_COUNT;
                conflict_bank = conflict_bank + 1) begin
            if (p0_valid && p1_valid &&
                    p0_bank_mask[conflict_bank] &&
                    p1_bank_mask[conflict_bank]) begin
                if (p0_write && p1_write)
                    conflict_comb = 1'b1;
                else if ((p0_write || p1_write) &&
                        (p0_addr[conflict_bank*ADDR_W +: ADDR_W] ==
                         p1_addr[conflict_bank*ADDR_W +: ADDR_W]))
                    conflict_comb = 1'b1;
            end
        end
    end

    wire selected_conflict = USE_EXTERNAL_CONFLICT ?
        external_conflict : conflict_comb;
    assign access_conflict = selected_conflict;
    assign p0_ready = !selected_conflict;
    assign p1_ready = !selected_conflict;

    wire p0_fire = p0_valid && p0_ready;
    wire p1_fire = p1_valid && p1_ready;
    wire p0_read_fire = p0_fire && !p0_write && (|p0_bank_mask);
    wire p1_read_fire = p1_fire && !p1_write && (|p1_bank_mask);

    always @(posedge clk) begin
        if (!rst_n) begin
            p0_rd_valid <= 1'b0;
            p0_rd_bank_mask <= {BANK_COUNT{1'b0}};
            p1_rd_valid <= 1'b0;
            p1_rd_bank_mask <= {BANK_COUNT{1'b0}};
        end else begin
            p0_rd_valid <= p0_read_fire;
            p1_rd_valid <= p1_read_fire;
            if (p0_read_fire)
                p0_rd_bank_mask <= p0_bank_mask;
            if (p1_read_fire)
                p1_rd_bank_mask <= p1_bank_mask;
        end
    end

    genvar bank;
    generate
        for (bank = 0; bank < BANK_COUNT; bank = bank + 1) begin : g_bank
            (* ram_style = "block" *) reg [BANK_WORD_W-1:0] memory [0:BANK_DEPTH-1];
            reg [BANK_WORD_W-1:0] p0_rd_word;
            reg [BANK_WORD_W-1:0] p1_rd_word;

            always @(posedge clk) begin
                if (p0_fire && p0_bank_mask[bank]) begin
                    if (p0_write)
                        memory[p0_addr[bank*ADDR_W +: ADDR_W]] <=
                            p0_wr_data[bank*BANK_WORD_W +: BANK_WORD_W];
                    else
                        p0_rd_word <= memory[p0_addr[bank*ADDR_W +: ADDR_W]];
                end
            end

            always @(posedge clk) begin
                if (p1_fire && p1_bank_mask[bank]) begin
                    if (p1_write)
                        memory[p1_addr[bank*ADDR_W +: ADDR_W]] <=
                            p1_wr_data[bank*BANK_WORD_W +: BANK_WORD_W];
                    else
                        p1_rd_word <= memory[p1_addr[bank*ADDR_W +: ADDR_W]];
                end
            end

            assign p0_rd_data[bank*BANK_WORD_W +: BANK_WORD_W] = p0_rd_word;
            assign p1_rd_data[bank*BANK_WORD_W +: BANK_WORD_W] = p1_rd_word;
        end
    endgenerate

`ifdef FORMAL
    reg formal_past_valid;
    reg f_prev_p0_read;
    reg f_prev_p1_read;
    always @(posedge clk) begin
        if (!rst_n) begin
            formal_past_valid <= 1'b0;
            f_prev_p0_read <= 1'b0;
            f_prev_p1_read <= 1'b0;
        end else begin
            formal_past_valid <= 1'b1;
            if (access_conflict) begin
                assert(!p0_ready);
                assert(!p1_ready);
            end
            assert(!(p0_fire && p1_fire && access_conflict));
            if (formal_past_valid) begin
                assert(p0_rd_valid == f_prev_p0_read);
                assert(p1_rd_valid == f_prev_p1_read);
            end
            f_prev_p0_read <= p0_read_fire;
            f_prev_p1_read <= p1_read_fire;
        end
    end
`endif
endmodule

`default_nettype wire
