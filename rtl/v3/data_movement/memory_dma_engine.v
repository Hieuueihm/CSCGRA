`timescale 1ns/1ps
`default_nettype none

// Four-client DMA spine. It deliberately permits one transaction at a time so
// client ownership, error attribution and terminal progress remain explicit.
module memory_dma_engine #(
    parameter integer ADDRESS_W = 64,
    parameter integer DATA_W = 128,
    parameter integer TAG_W = 8
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire [3:0]                 client_req_valid,
    output wire [3:0]                 client_req_ready,
    input  wire [3:0]                 client_req_write,
    input  wire [(4*ADDRESS_W)-1:0]   client_req_addr,
    input  wire [(4*16)-1:0]          client_req_bytes,
    input  wire [(4*TAG_W)-1:0]       client_req_tag,
    input  wire [3:0]                 client_wr_valid,
    output wire [3:0]                 client_wr_ready,
    input  wire [(4*DATA_W)-1:0]      client_wr_data,
    input  wire [(4*(DATA_W/8))-1:0]  client_wr_keep,
    input  wire [3:0]                 client_wr_last,
    output wire [3:0]                 client_rd_valid,
    input  wire [3:0]                 client_rd_ready,
    output wire [(4*DATA_W)-1:0]      client_rd_data,
    output wire [3:0]                 client_rd_last,
    output wire [(4*2)-1:0]           client_rd_resp,
    output wire [(4*TAG_W)-1:0]       client_rd_tag,
    output wire [3:0]                 client_done_valid,
    input  wire [3:0]                 client_done_ready,
    output wire [(4*TAG_W)-1:0]       client_done_tag,
    output wire [3:0]                 client_done_error,
    output wire [(4*2)-1:0]           client_done_resp,
    output wire [(4*9)-1:0]           client_done_beat,
    output wire                       dma_active,

    output wire [ADDRESS_W-1:0]       m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,
    input  wire [DATA_W-1:0]          m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready,
    output wire [ADDRESS_W-1:0]       m_axi_awaddr,
    output wire [7:0]                 m_axi_awlen,
    output wire [2:0]                 m_axi_awsize,
    output wire [1:0]                 m_axi_awburst,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,
    output wire [DATA_W-1:0]          m_axi_wdata,
    output wire [(DATA_W/8)-1:0]      m_axi_wstrb,
    output wire                       m_axi_wlast,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,
    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready
);
    wire engine_req_valid;
    wire engine_req_ready;
    wire engine_req_write;
    wire [ADDRESS_W-1:0] engine_req_addr;
    wire [15:0] engine_req_bytes;
    wire [TAG_W-1:0] engine_req_tag;
    wire engine_wr_valid;
    wire engine_wr_ready;
    wire [DATA_W-1:0] engine_wr_data;
    wire [(DATA_W/8)-1:0] engine_wr_keep;
    wire engine_wr_last;
    wire engine_rd_valid;
    wire engine_rd_ready;
    wire [DATA_W-1:0] engine_rd_data;
    wire engine_rd_last;
    wire [1:0] engine_rd_resp;
    wire [TAG_W-1:0] engine_rd_tag;
    wire engine_done_valid;
    wire engine_done_ready;
    wire [TAG_W-1:0] engine_done_tag;
    wire engine_done_error;
    wire [1:0] engine_done_resp;
    wire [8:0] engine_done_beat;

    wire rd_req_ready;
    wire wr_req_ready;
    wire rd_done_valid;
    wire rd_done_ready;
    wire [TAG_W-1:0] rd_done_tag;
    wire rd_done_error;
    wire [1:0] rd_done_resp;
    wire [8:0] rd_done_beat;
    wire wr_done_valid;
    wire wr_done_ready;
    wire [TAG_W-1:0] wr_done_tag;
    wire wr_done_error;
    wire [1:0] wr_done_resp;
    wire [8:0] wr_done_beat;

    assign engine_req_ready = engine_req_write ?
        wr_req_ready : rd_req_ready;
    assign engine_done_valid = wr_done_valid || rd_done_valid;
    assign engine_done_tag = wr_done_valid ?
        wr_done_tag : rd_done_tag;
    assign engine_done_error = wr_done_valid ?
        wr_done_error : rd_done_error;
    assign engine_done_resp = wr_done_valid ?
        wr_done_resp : rd_done_resp;
    assign engine_done_beat = wr_done_valid ?
        wr_done_beat : rd_done_beat;
    assign wr_done_ready = engine_done_ready && wr_done_valid;
    assign rd_done_ready = engine_done_ready && !wr_done_valid;

    dma_request_arbiter #(
        .ADDRESS_W(ADDRESS_W), .DATA_W(DATA_W), .TAG_W(TAG_W)
    ) u_dma_request_arbiter (
        .clk(clk), .rst_n(rst_n),
        .client_req_valid(client_req_valid),
        .client_req_ready(client_req_ready),
        .client_req_write(client_req_write),
        .client_req_addr(client_req_addr),
        .client_req_bytes(client_req_bytes),
        .client_req_tag(client_req_tag),
        .client_wr_valid(client_wr_valid),
        .client_wr_ready(client_wr_ready),
        .client_wr_data(client_wr_data),
        .client_wr_keep(client_wr_keep),
        .client_wr_last(client_wr_last),
        .client_rd_valid(client_rd_valid),
        .client_rd_ready(client_rd_ready),
        .client_rd_data(client_rd_data),
        .client_rd_last(client_rd_last),
        .client_rd_resp(client_rd_resp),
        .client_rd_tag(client_rd_tag),
        .client_done_valid(client_done_valid),
        .client_done_ready(client_done_ready),
        .client_done_tag(client_done_tag),
        .client_done_error(client_done_error),
        .client_done_resp(client_done_resp),
        .client_done_beat(client_done_beat),
        .engine_req_valid(engine_req_valid),
        .engine_req_ready(engine_req_ready),
        .engine_req_write(engine_req_write),
        .engine_req_addr(engine_req_addr),
        .engine_req_bytes(engine_req_bytes),
        .engine_req_tag(engine_req_tag),
        .engine_wr_valid(engine_wr_valid),
        .engine_wr_ready(engine_wr_ready),
        .engine_wr_data(engine_wr_data),
        .engine_wr_keep(engine_wr_keep),
        .engine_wr_last(engine_wr_last),
        .engine_rd_valid(engine_rd_valid),
        .engine_rd_ready(engine_rd_ready),
        .engine_rd_data(engine_rd_data),
        .engine_rd_last(engine_rd_last),
        .engine_rd_resp(engine_rd_resp),
        .engine_rd_tag(engine_rd_tag),
        .engine_done_valid(engine_done_valid),
        .engine_done_ready(engine_done_ready),
        .engine_done_tag(engine_done_tag),
        .engine_done_error(engine_done_error),
        .engine_done_resp(engine_done_resp),
        .engine_done_beat(engine_done_beat),
        .dma_active(dma_active)
    );

    axi_read_burst_engine #(
        .ADDRESS_W(ADDRESS_W), .DATA_W(DATA_W), .TAG_W(TAG_W)
    ) u_axi_rd (
        .clk(clk), .rst_n(rst_n),
        .request_valid(engine_req_valid && !engine_req_write),
        .request_ready(rd_req_ready),
        .request_address(engine_req_addr),
        .request_bytes(engine_req_bytes), .request_tag(engine_req_tag),
        .read_valid(engine_rd_valid), .read_ready(engine_rd_ready),
        .read_data(engine_rd_data), .read_last(engine_rd_last),
        .read_response(engine_rd_resp), .read_tag(engine_rd_tag),
        .completion_valid(rd_done_valid),
        .completion_ready(rd_done_ready),
        .completion_tag(rd_done_tag),
        .completion_error(rd_done_error),
        .completion_response(rd_done_resp),
        .completion_beat(rd_done_beat),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    axi_write_burst_engine #(
        .ADDRESS_W(ADDRESS_W), .DATA_W(DATA_W), .TAG_W(TAG_W)
    ) u_axi_wr (
        .clk(clk), .rst_n(rst_n),
        .request_valid(engine_req_valid && engine_req_write),
        .request_ready(wr_req_ready),
        .request_address(engine_req_addr),
        .request_bytes(engine_req_bytes), .request_tag(engine_req_tag),
        .write_valid(engine_wr_valid), .write_ready(engine_wr_ready),
        .write_data(engine_wr_data), .write_keep(engine_wr_keep),
        .write_last(engine_wr_last),
        .completion_valid(wr_done_valid),
        .completion_ready(wr_done_ready),
        .completion_tag(wr_done_tag),
        .completion_error(wr_done_error),
        .completion_response(wr_done_resp),
        .completion_beat(wr_done_beat),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert(!(rd_done_valid && wr_done_valid));
            assert(!(m_axi_arvalid && m_axi_awvalid));
        end
    end
`endif
endmodule

`default_nettype wire
