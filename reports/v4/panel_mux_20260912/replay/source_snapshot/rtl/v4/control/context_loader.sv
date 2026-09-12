`include "control_defs.vh"

module context_loader (
    input wire clk, rst, cancel,
    input wire idle,
    input wire begin_valid,
    output wire begin_ready,
    input wire [7:0] begin_rev,
    input wire [8:0] begin_depth,
    input wire begin_verified,
    input wire [31:0] begin_generation,
    input wire wr_valid,
    output wire wr_ready,
    input wire [7:0] wr_pc,
    input wire [5:0] wr_bank,
    input wire [191:0] wr_upper,
    input wire wr_last,
    output wire store_we,
    output wire invalidate,
    output reg image_ready,
    output reg [31:0] generation,
    output reg [3:0] fault,
    output reg loading
);
    reg [7:0] next_pc;
    reg [5:0] next_bank;
    wire active = !rst && !cancel;
    wire begin_take = begin_valid && begin_ready;
    wire last_word = next_pc == 255 && next_bank == 32;
    wire word_good = wr_pc == next_pc && wr_bank == next_bank && wr_last == last_word &&
                     (wr_bank == 32 || wr_upper == 0);
    assign begin_ready = active && idle && !loading;
    assign wr_ready = active && idle && loading;
    assign store_we = wr_valid && wr_ready && word_good;
    assign invalidate = !active || begin_take;
    always @(posedge clk) begin
        if (rst || cancel) begin
            loading <= 1'b0; image_ready <= 1'b0; generation <= '0;
            next_pc <= '0; next_bank <= '0; fault <= '0;
        end else begin
            if (begin_take) begin
                image_ready <= 1'b0; next_pc <= '0; next_bank <= '0;
                generation <= begin_generation; fault <= '0;
                if (begin_rev != `CSR_CTL_REV || begin_depth != `CSR_CTL_DEPTH || !begin_verified) begin
                    loading <= 1'b0; fault <= `CSR_CTL_FAULT_HEADER;
                end else loading <= 1'b1;
            end
            if (wr_valid && wr_ready) begin
                if (!word_good) begin loading <= 1'b0; fault <= `CSR_CTL_FAULT_STREAM; end
                else if (last_word) begin loading <= 1'b0; image_ready <= 1'b1; end
                else if (next_bank == 32) begin next_bank <= '0; next_pc <= next_pc + 1'b1; end
                else next_bank <= next_bank + 1'b1;
            end
        end
    end
endmodule
