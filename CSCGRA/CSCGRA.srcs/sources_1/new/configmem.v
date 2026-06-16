module configmem #(
    parameter integer NCTX   = 64,
    parameter integer CTX_W  = 64,
    parameter integer CTX_AW = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 wr_en,
    input  wire [CTX_AW-1:0]    wr_addr,
    input  wire                 wr_word,
    input  wire [31:0]          wr_data,

    input  wire [CTX_AW-1:0]    seq_addr,
    output wire [CTX_W-1:0]     seq_ctx,

    input  wire                 dbg_rd_en,
    input  wire [CTX_AW-1:0]    dbg_rd_addr,
    output reg  [CTX_W-1:0]     dbg_rd_data
);

    (* ram_style = "distributed" *) reg [31:0] mem_lo [0:NCTX-1];
    (* ram_style = "distributed" *) reg [31:0] mem_hi [0:NCTX-1];

    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_word)
                mem_hi[wr_addr] <= wr_data;
            else
                mem_lo[wr_addr] <= wr_data;
        end

        if (dbg_rd_en)
            dbg_rd_data <= {mem_hi[dbg_rd_addr], mem_lo[dbg_rd_addr]};
    end

    assign seq_ctx = {mem_hi[seq_addr], mem_lo[seq_addr]};

endmodule
