`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "reconstruction_control_defs.vh"

module m12_result_dma_integration #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer SUPPORT_MAX = `RECON_K_MAX,
    parameter integer TAG_W = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire result_start_valid,
    output wire result_start_ready,
    input  wire result_abort_request,
    input  wire [1:0] result_mode,
    input  wire [10:0] signal_length,
    input  wire [6:0] support_count,
    input  wire [SUPPORT_MAX*INDEX_W-1:0] support_indices,
    input  wire [SUPPORT_MAX*DATA_W-1:0] support_coefficients,
    input  wire [63:0] dense_result_address,
    input  wire [63:0] sparse_result_address,
    input  wire [31:0] user_tag,
    input  wire [3:0] stop_reason,
    output wire writeback_active,
    output wire completion_valid,
    input  wire completion_ready,
    output wire [3:0] completion_stop_reason,
    output wire error_valid,
    input  wire error_ready,
    output wire [3:0] error_class,
    output wire [7:0] error_code,
    output wire [1:0] error_response,
    output wire [8:0] error_beat,
    output wire [TAG_W-1:0] error_tag,

    input  wire [2:0] aux_req_valid,
    output wire [2:0] aux_req_ready,
    input  wire [2:0] aux_req_write,
    input  wire [3*64-1:0] aux_req_addr,
    input  wire [3*16-1:0] aux_req_bytes,
    input  wire [3*TAG_W-1:0] aux_req_tag,
    input  wire [2:0] aux_wr_valid,
    output wire [2:0] aux_wr_ready,
    input  wire [3*128-1:0] aux_wr_data,
    input  wire [3*16-1:0] aux_wr_keep,
    input  wire [2:0] aux_wr_last,
    output wire [2:0] aux_rd_valid,
    input  wire [2:0] aux_rd_ready,
    output wire [3*128-1:0] aux_rd_data,
    output wire [2:0] aux_rd_last,
    output wire [3*2-1:0] aux_rd_resp,
    output wire [3*TAG_W-1:0] aux_rd_tag,
    output wire [2:0] aux_done_valid,
    input  wire [2:0] aux_done_ready,
    output wire [3*TAG_W-1:0] aux_done_tag,
    output wire [2:0] aux_done_error,
    output wire [3*2-1:0] aux_done_resp,
    output wire [3*9-1:0] aux_done_beat,
    output wire dma_active,

    output wire [63:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input  wire m_axi_arready,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0] m_axi_rresp,
    input  wire m_axi_rlast,
    input  wire m_axi_rvalid,
    output wire m_axi_rready,
    output wire [63:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input  wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,
    input  wire [1:0] m_axi_bresp,
    input  wire m_axi_bvalid,
    output wire m_axi_bready
);
    wire writer_req_valid;
    wire writer_req_ready;
    wire writer_req_write;
    wire [63:0] writer_req_addr;
    wire [15:0] writer_req_bytes;
    wire [TAG_W-1:0] writer_req_tag;
    wire writer_wr_valid;
    wire writer_wr_ready;
    wire [127:0] writer_wr_data;
    wire [15:0] writer_wr_keep;
    wire writer_wr_last;
    wire writer_done_valid;
    wire writer_done_ready;
    wire [TAG_W-1:0] writer_done_tag;
    wire writer_done_error;
    wire [1:0] writer_done_resp;
    wire [8:0] writer_done_beat;

    wire [3:0] client_req_valid = {writer_req_valid, aux_req_valid};
    wire [3:0] client_req_ready;
    wire [3:0] client_req_write = {writer_req_write, aux_req_write};
    wire [4*64-1:0] client_req_addr = {writer_req_addr, aux_req_addr};
    wire [4*16-1:0] client_req_bytes = {writer_req_bytes, aux_req_bytes};
    wire [4*TAG_W-1:0] client_req_tag = {writer_req_tag, aux_req_tag};
    wire [3:0] client_wr_valid = {writer_wr_valid, aux_wr_valid};
    wire [3:0] client_wr_ready;
    wire [4*128-1:0] client_wr_data = {writer_wr_data, aux_wr_data};
    wire [4*16-1:0] client_wr_keep = {writer_wr_keep, aux_wr_keep};
    wire [3:0] client_wr_last = {writer_wr_last, aux_wr_last};
    wire [3:0] client_rd_valid;
    wire [3:0] client_rd_ready = {1'b0, aux_rd_ready};
    wire [4*128-1:0] client_rd_data;
    wire [3:0] client_rd_last;
    wire [4*2-1:0] client_rd_resp;
    wire [4*TAG_W-1:0] client_rd_tag;
    wire [3:0] client_done_valid;
    wire [3:0] client_done_ready = {writer_done_ready, aux_done_ready};
    wire [4*TAG_W-1:0] client_done_tag;
    wire [3:0] client_done_error;
    wire [4*2-1:0] client_done_resp;
    wire [4*9-1:0] client_done_beat;

    assign aux_req_ready = client_req_ready[2:0];
    assign aux_wr_ready = client_wr_ready[2:0];
    assign aux_rd_valid = client_rd_valid[2:0];
    assign aux_rd_data = client_rd_data[3*128-1:0];
    assign aux_rd_last = client_rd_last[2:0];
    assign aux_rd_resp = client_rd_resp[3*2-1:0];
    assign aux_rd_tag = client_rd_tag[3*TAG_W-1:0];
    assign aux_done_valid = client_done_valid[2:0];
    assign aux_done_tag = client_done_tag[3*TAG_W-1:0];
    assign aux_done_error = client_done_error[2:0];
    assign aux_done_resp = client_done_resp[3*2-1:0];
    assign aux_done_beat = client_done_beat[3*9-1:0];
    assign writer_req_ready = client_req_ready[3];
    assign writer_wr_ready = client_wr_ready[3];
    assign writer_done_valid = client_done_valid[3];
    assign writer_done_tag = client_done_tag[3*TAG_W +: TAG_W];
    assign writer_done_error = client_done_error[3];
    assign writer_done_resp = client_done_resp[3*2 +: 2];
    assign writer_done_beat = client_done_beat[3*9 +: 9];
    assign error_class = `RECON_ERROR_CLASS_DMA_WRITE;

    reconstruction_result_writer #(
        .DATA_W(DATA_W), .INDEX_W(INDEX_W),
        .SUPPORT_MAX(SUPPORT_MAX), .TAG_W(TAG_W)
    ) u_result_writer (
        .clk(clk), .rst_n(rst_n),
        .start_valid(result_start_valid), .start_ready(result_start_ready),
        .abort_request(result_abort_request), .result_mode(result_mode),
        .signal_length(signal_length), .support_count(support_count),
        .support_indices(support_indices),
        .support_coefficients(support_coefficients),
        .dense_result_address(dense_result_address),
        .sparse_result_address(sparse_result_address),
        .user_tag(user_tag), .stop_reason(stop_reason), .busy(writeback_active),
        .dma_req_valid(writer_req_valid), .dma_req_ready(writer_req_ready),
        .dma_req_write(writer_req_write), .dma_req_addr(writer_req_addr),
        .dma_req_bytes(writer_req_bytes), .dma_req_tag(writer_req_tag),
        .dma_wr_valid(writer_wr_valid), .dma_wr_ready(writer_wr_ready),
        .dma_wr_data(writer_wr_data), .dma_wr_keep(writer_wr_keep),
        .dma_wr_last(writer_wr_last), .dma_done_valid(writer_done_valid),
        .dma_done_ready(writer_done_ready), .dma_done_tag(writer_done_tag),
        .dma_done_error(writer_done_error), .dma_done_resp(writer_done_resp),
        .dma_done_beat(writer_done_beat),
        .completion_valid(completion_valid), .completion_ready(completion_ready),
        .completion_stop_reason(completion_stop_reason),
        .error_valid(error_valid), .error_ready(error_ready),
        .error_code(error_code), .error_response(error_response),
        .error_beat(error_beat), .error_tag(error_tag)
    );

    memory_dma_engine #(.TAG_W(TAG_W)) u_dma (
        .clk(clk), .rst_n(rst_n),
        .client_req_valid(client_req_valid), .client_req_ready(client_req_ready),
        .client_req_write(client_req_write), .client_req_addr(client_req_addr),
        .client_req_bytes(client_req_bytes), .client_req_tag(client_req_tag),
        .client_wr_valid(client_wr_valid), .client_wr_ready(client_wr_ready),
        .client_wr_data(client_wr_data), .client_wr_keep(client_wr_keep),
        .client_wr_last(client_wr_last), .client_rd_valid(client_rd_valid),
        .client_rd_ready(client_rd_ready), .client_rd_data(client_rd_data),
        .client_rd_last(client_rd_last), .client_rd_resp(client_rd_resp),
        .client_rd_tag(client_rd_tag), .client_done_valid(client_done_valid),
        .client_done_ready(client_done_ready), .client_done_tag(client_done_tag),
        .client_done_error(client_done_error),
        .client_done_resp(client_done_resp), .client_done_beat(client_done_beat),
        .dma_active(dma_active),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );
endmodule

`default_nettype wire
