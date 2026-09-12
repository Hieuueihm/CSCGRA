`include "control_defs.vh"

module context_store (
    input wire clk, rst, cancel, invalidate,
    input wire image_ready,
    input wire [31:0] generation,
    input wire wr_en,
    input wire [7:0] wr_pc,
    input wire [5:0] wr_bank,
    input wire [255:0] wr_data,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_pc,
    input wire [31:0] rd_generation,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [2047:0] rsp_words,
    output reg [255:0] rsp_control,
    output reg [7:0] rsp_pc,
    output reg [31:0] rsp_generation,
    output reg [3:0] rsp_fault
);
    reg pending;
    reg [255:0] controls [0:255];
    wire active = !rst && !cancel && !invalidate;
    wire good = image_ready && generation == rd_generation;
    wire take = rd_valid && rd_ready;
    assign rd_ready = active && !pending && !wr_en;
    assign rsp_valid = active && pending;
    genvar bank;
    generate
        for (bank = 0; bank < 32; bank = bank + 1) begin : tile_bank
            reg [63:0] words [0:255];
            reg [63:0] data;
            assign rsp_words[bank*64 +: 64] = data;
            always @(posedge clk) begin
                if (wr_en && wr_bank == bank && active) words[wr_pc] <= wr_data[63:0];
                if (!active) data <= '0;
                else if (take) data <= good ? words[rd_pc] : 64'b0;
            end
        end
    endgenerate
    always @(posedge clk) begin
        if (wr_en && wr_bank == 32 && active) controls[wr_pc] <= wr_data;
        if (!active) begin
            pending <= 1'b0; rsp_control <= '0; rsp_pc <= '0; rsp_generation <= '0; rsp_fault <= '0;
        end else begin
            if (rsp_valid && rsp_ready) pending <= 1'b0;
            if (take) begin
                pending <= 1'b1;
                rsp_control <= good ? controls[rd_pc] : 256'b0;
                rsp_pc <= rd_pc; rsp_generation <= rd_generation;
                rsp_fault <= good ? 4'b0 : `CSR_CTL_FAULT_FETCH;
            end
        end
    end
endmodule
