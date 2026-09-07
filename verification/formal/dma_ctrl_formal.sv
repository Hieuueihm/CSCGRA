`default_nettype none

module dma_ctrl_formal;
    localparam integer AXI_AW = 32;
    localparam integer AXI_DW = 32;
    localparam integer COLS = 8;
    localparam integer MEM_AW = 10;
    localparam integer DATA_W = 24;
    localparam integer IDX_W = 10;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    (* anyseq *) reg start;
    (* anyseq *) reg dir;
    (* anyseq *) reg [2:0] vec_id;
    (* anyseq *) reg [IDX_W-1:0] length;
    (* anyseq *) reg [AXI_AW-1:0] ddr_addr;
    (* anyseq *) reg m_axi_arready;
    (* anyseq *) reg [AXI_DW-1:0] m_axi_rdata;
    (* anyseq *) reg [1:0] m_axi_rresp;
    (* anyseq *) reg m_axi_rvalid;
    (* anyseq *) reg m_axi_rlast;
    (* anyseq *) reg m_axi_awready;
    (* anyseq *) reg m_axi_wready;
    (* anyseq *) reg [1:0] m_axi_bresp;
    (* anyseq *) reg m_axi_bvalid;
    (* anyseq *) reg [COLS*DATA_W-1:0] spm_rdata;

    wire done, error, busy;
    wire [3:0] error_code;
    wire [AXI_AW-1:0] m_axi_araddr, m_axi_awaddr;
    wire [7:0] m_axi_arlen, m_axi_awlen;
    wire [2:0] m_axi_arsize, m_axi_awsize;
    wire [1:0] m_axi_arburst, m_axi_awburst;
    wire m_axi_arvalid, m_axi_rready, m_axi_awvalid;
    wire [AXI_DW-1:0] m_axi_wdata;
    wire [AXI_DW/8-1:0] m_axi_wstrb;
    wire m_axi_wlast, m_axi_wvalid, m_axi_bready;
    wire [COLS*MEM_AW-1:0] spm_addr;
    wire [COLS*DATA_W-1:0] spm_wdata;
    wire [COLS-1:0] spm_wen;

    reg f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!f_past_valid)
            assume(!rst_n);
        else
            assume(rst_n);
    end

    dma_ctrl #(
        .AXI_AW(AXI_AW), .AXI_DW(AXI_DW), .COLS(COLS),
        .MEM_AW(MEM_AW), .DATA_W(DATA_W), .IDX_W(IDX_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .dir(dir), .vec_id(vec_id),
        .length(length), .ddr_addr(ddr_addr), .done(done), .error(error),
        .error_code(error_code), .busy(busy),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rlast(m_axi_rlast),
        .m_axi_rready(m_axi_rready), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready), .spm_addr(spm_addr),
        .spm_wdata(spm_wdata), .spm_wen(spm_wen), .spm_rdata(spm_rdata)
    );
endmodule

`default_nettype wire
