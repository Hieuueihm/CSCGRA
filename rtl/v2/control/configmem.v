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
    input  wire [3:0]           wr_strb,

    input  wire [CTX_AW-1:0]    seq_addr,
    output wire [CTX_W-1:0]     seq_ctx,

    input  wire                 dbg_rd_en,
    input  wire [CTX_AW-1:0]    dbg_rd_addr,
    output reg  [CTX_W-1:0]     dbg_rd_data
);

    (* ram_style = "block" *) reg [31:0] mem_lo [0:NCTX-1];
    (* ram_style = "block" *) reg [31:0] mem_hi [0:NCTX-1];
    reg [CTX_W-1:0] seq_ctx_q;

    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_word) begin
                if (wr_strb[0]) mem_hi[wr_addr][7:0]   <= wr_data[7:0];
                if (wr_strb[1]) mem_hi[wr_addr][15:8]  <= wr_data[15:8];
                if (wr_strb[2]) mem_hi[wr_addr][23:16] <= wr_data[23:16];
                if (wr_strb[3]) mem_hi[wr_addr][31:24] <= wr_data[31:24];
            end else begin
                if (wr_strb[0]) mem_lo[wr_addr][7:0]   <= wr_data[7:0];
                if (wr_strb[1]) mem_lo[wr_addr][15:8]  <= wr_data[15:8];
                if (wr_strb[2]) mem_lo[wr_addr][23:16] <= wr_data[23:16];
                if (wr_strb[3]) mem_lo[wr_addr][31:24] <= wr_data[31:24];
            end
        end

        seq_ctx_q <= {mem_hi[seq_addr], mem_lo[seq_addr]};
        if (dbg_rd_en)
            dbg_rd_data <= {mem_hi[dbg_rd_addr], mem_lo[dbg_rd_addr]};
    end

    assign seq_ctx = seq_ctx_q;

endmodule
