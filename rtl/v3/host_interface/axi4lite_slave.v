`timescale 1ns/1ps
`default_nettype none

// CSCGRA architecture revision 3: AXI4-Lite protocol transport only.

module axilite_slave #(
    parameter integer AXIL_AW = 12,
    parameter integer AXIL_DW = 32
)(
    input  wire                     aclk,
    input  wire                     aresetn,

    input  wire [AXIL_AW-1:0]       s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [AXIL_DW-1:0]       s_axi_wdata,
    input  wire [(AXIL_DW/8)-1:0]   s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [AXIL_AW-1:0]       s_axi_araddr,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,
    output reg  [AXIL_DW-1:0]       s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    output wire                     csr_wr_valid,
    output wire [AXIL_AW-1:0]       csr_wr_addr,
    output wire [AXIL_DW-1:0]       csr_wr_data,
    output wire [(AXIL_DW/8)-1:0]   csr_wr_strb,
    input  wire [1:0]               csr_wr_resp,

    output wire                     csr_rd_valid,
    output wire [AXIL_AW-1:0]       csr_rd_addr,
    input  wire [AXIL_DW-1:0]       csr_rd_data,
    input  wire [1:0]               csr_rd_resp
);

    reg                     aw_hold_valid;
    reg [AXIL_AW-1:0]       aw_hold_addr;
    reg                     w_hold_valid;
    reg [AXIL_DW-1:0]       w_hold_data;
    reg [(AXIL_DW/8)-1:0]   w_hold_strb;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;
    wire have_aw = aw_hold_valid || aw_fire;
    wire have_w  = w_hold_valid  || w_fire;

    assign s_axi_awready = aresetn && !s_axi_bvalid && !aw_hold_valid;
    assign s_axi_wready  = aresetn && !s_axi_bvalid && !w_hold_valid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;

    assign csr_wr_valid = aresetn && !s_axi_bvalid && have_aw && have_w;
    assign csr_wr_addr  = aw_hold_valid ? aw_hold_addr : s_axi_awaddr;
    assign csr_wr_data  = w_hold_valid ? w_hold_data : s_axi_wdata;
    assign csr_wr_strb  = w_hold_valid ? w_hold_strb : s_axi_wstrb;

    assign csr_rd_valid = ar_fire;
    assign csr_rd_addr  = s_axi_araddr;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_hold_valid <= 1'b0;
            aw_hold_addr  <= {AXIL_AW{1'b0}};
            w_hold_valid  <= 1'b0;
            w_hold_data   <= {AXIL_DW{1'b0}};
            w_hold_strb   <= {(AXIL_DW/8){1'b0}};
            s_axi_bresp   <= 2'b00;
            s_axi_bvalid  <= 1'b0;
            s_axi_rdata   <= {AXIL_DW{1'b0}};
            s_axi_rresp   <= 2'b00;
            s_axi_rvalid  <= 1'b0;
        end else begin
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (csr_wr_valid) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                s_axi_bresp   <= csr_wr_resp;
                s_axi_bvalid  <= 1'b1;
            end else begin
                if (aw_fire) begin
                    aw_hold_valid <= 1'b1;
                    aw_hold_addr  <= s_axi_awaddr;
                end
                if (w_fire) begin
                    w_hold_valid <= 1'b1;
                    w_hold_data  <= s_axi_wdata;
                    w_hold_strb  <= s_axi_wstrb;
                end
            end

            if (csr_rd_valid) begin
                s_axi_rdata  <= csr_rd_data;
                s_axi_rresp  <= csr_rd_resp;
                s_axi_rvalid <= 1'b1;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_aresetn;
    reg f_bvalid;
    reg f_bready;
    reg [1:0] f_bresp;
    reg f_rvalid;
    reg f_rready;
    reg [AXIL_DW-1:0] f_rdata;
    reg [1:0] f_rresp;
    reg f_aw_hold_valid;
    reg [AXIL_AW-1:0] f_aw_hold_addr;
    reg f_w_hold_valid;
    reg [AXIL_DW-1:0] f_w_hold_data;
    reg [(AXIL_DW/8)-1:0] f_w_hold_strb;
    reg f_csr_wr_valid;
    reg [1:0] f_csr_wr_resp;
    reg f_csr_rd_valid;
    reg [AXIL_DW-1:0] f_csr_rd_data;
    reg [1:0] f_csr_rd_resp;
    reg f_aw_fire;
    reg f_w_fire;
    initial f_past_valid = 1'b0;
    always @(posedge aclk) begin
        f_past_valid <= 1'b1;
        f_aresetn <= aresetn;
        f_bvalid <= s_axi_bvalid;
        f_bready <= s_axi_bready;
        f_bresp <= s_axi_bresp;
        f_rvalid <= s_axi_rvalid;
        f_rready <= s_axi_rready;
        f_rdata <= s_axi_rdata;
        f_rresp <= s_axi_rresp;
        f_aw_hold_valid <= aw_hold_valid;
        f_aw_hold_addr <= aw_hold_addr;
        f_w_hold_valid <= w_hold_valid;
        f_w_hold_data <= w_hold_data;
        f_w_hold_strb <= w_hold_strb;
        f_csr_wr_valid <= csr_wr_valid;
        f_csr_wr_resp <= csr_wr_resp;
        f_csr_rd_valid <= csr_rd_valid;
        f_csr_rd_data <= csr_rd_data;
        f_csr_rd_resp <= csr_rd_resp;
        f_aw_fire <= aw_fire;
        f_w_fire <= w_fire;
        if (f_past_valid && aresetn && f_aresetn) begin
            if (f_bvalid && !f_bready) begin
                assert(s_axi_bvalid);
                assert(s_axi_bresp == f_bresp);
            end
            if (f_rvalid && !f_rready) begin
                assert(s_axi_rvalid);
                assert(s_axi_rdata == f_rdata);
                assert(s_axi_rresp == f_rresp);
            end
            if (f_aw_hold_valid && !f_csr_wr_valid) begin
                assert(aw_hold_valid);
                assert(aw_hold_addr == f_aw_hold_addr);
            end
            if (f_w_hold_valid && !f_csr_wr_valid) begin
                assert(w_hold_valid);
                assert(w_hold_data == f_w_hold_data);
                assert(w_hold_strb == f_w_hold_strb);
            end
            if (f_aw_fire && !f_w_fire && !f_w_hold_valid)
                assert(aw_hold_valid);
            if (f_w_fire && !f_aw_fire && !f_aw_hold_valid)
                assert(w_hold_valid);
            if (f_csr_wr_valid) begin
                assert(s_axi_bvalid);
                assert(s_axi_bresp == f_csr_wr_resp);
            end
            if (f_csr_rd_valid) begin
                assert(s_axi_rvalid);
                assert(s_axi_rdata == f_csr_rd_data);
                assert(s_axi_rresp == f_csr_rd_resp);
            end
        end
        assert(!csr_wr_valid || (have_aw && have_w));
        assert(csr_rd_valid == ar_fire);
        assert(!(s_axi_bvalid && (s_axi_awready || s_axi_wready)));
        assert(!(s_axi_rvalid && s_axi_arready));
        assert(!(csr_wr_valid && s_axi_bvalid));
    end
`endif

endmodule

`default_nettype wire
