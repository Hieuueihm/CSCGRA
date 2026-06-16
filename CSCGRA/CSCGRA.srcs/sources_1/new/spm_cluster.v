module spm_cluster #(
    parameter integer COLS       = 8,
    parameter integer WORD_W     = 24,
    parameter integer MEM_AW     = 10,
    parameter integer BANK_DEPTH = 1024
)(
    input  wire                       clk,

    input  wire [COLS*MEM_AW-1:0]     pa_addr,
    input  wire [COLS*WORD_W-1:0]     pa_wdata,
    input  wire [COLS-1:0]            pa_wen,
    output reg  [COLS*WORD_W-1:0]     pa_rdata,

    input  wire [COLS*MEM_AW-1:0]     pb_addr,
    input  wire [COLS*WORD_W-1:0]     pb_wdata,
    input  wire [COLS-1:0]            pb_wen,
    output reg  [COLS*WORD_W-1:0]     pb_rdata,

    input  wire [COLS*MEM_AW-1:0]     pc_addr,
    input  wire [COLS*WORD_W-1:0]     pc_wdata,
    input  wire [COLS-1:0]            pc_wen
);

    genvar b;
    generate
        for (b = 0; b < COLS; b = b + 1) begin : gen_bank
            (* ram_style = "block" *) reg [WORD_W-1:0] mem_pa [0:BANK_DEPTH-1];
            (* ram_style = "block" *) reg [WORD_W-1:0] mem_pb [0:BANK_DEPTH-1];

            wire [MEM_AW-1:0] pa_addr_i = pa_addr[b*MEM_AW +: MEM_AW];
            wire [MEM_AW-1:0] pb_addr_i = pb_addr[b*MEM_AW +: MEM_AW];
            wire [WORD_W-1:0] pa_wdata_i = pa_wdata[b*WORD_W +: WORD_W];
            wire [WORD_W-1:0] pb_wdata_i = pb_wdata[b*WORD_W +: WORD_W];
            wire [MEM_AW-1:0] pc_addr_i = pc_addr[b*MEM_AW +: MEM_AW];
            wire [WORD_W-1:0] pc_wdata_i = pc_wdata[b*WORD_W +: WORD_W];
            wire wr_en_i = pc_wen[b] || pa_wen[b] || pb_wen[b];
            wire [MEM_AW-1:0] wr_addr_i = pc_wen[b] ? pc_addr_i :
                                           (pa_wen[b] ? pa_addr_i : pb_addr_i);
            wire [WORD_W-1:0] wr_data_i = pc_wen[b] ? pc_wdata_i :
                                           (pa_wen[b] ? pa_wdata_i : pb_wdata_i);

            always @(posedge clk) begin
                pa_rdata[b*WORD_W +: WORD_W] <= mem_pa[pa_addr_i];
                pb_rdata[b*WORD_W +: WORD_W] <= mem_pb[pb_addr_i];
                if (wr_en_i) begin
                    mem_pa[wr_addr_i] <= wr_data_i;
                    mem_pb[wr_addr_i] <= wr_data_i;
                end
            end
        end
    endgenerate

endmodule

module scratchpad #(
    parameter WORD_W = 24,
    parameter AW     = 10,
    parameter DEPTH  = 1024
)(
    input  wire              clk,

    input  wire [AW-1:0]     pa_addr,
    input  wire [WORD_W-1:0] pa_wdata,
    input  wire              pa_wen,
    output reg  [WORD_W-1:0] pa_rdata,

    input  wire [AW-1:0]     pb_addr,
    input  wire [WORD_W-1:0] pb_wdata,
    input  wire              pb_wen,
    output reg  [WORD_W-1:0] pb_rdata
);

    reg [WORD_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        pa_rdata <= mem[pa_addr];
        pb_rdata <= mem[pb_addr];

        if (pa_wen)
            mem[pa_addr] <= pa_wdata;
        if (pb_wen && !(pa_wen && (pa_addr == pb_addr)))
            mem[pb_addr] <= pb_wdata;
    end

endmodule

