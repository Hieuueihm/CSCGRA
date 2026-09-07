`timescale 1ns/1ps
`default_nettype none

// Legacy M1 compact AXI4-Lite control verification boundary. Run parameters
// are supplied through one DMA-fetched run-configuration block.

module m1_control_top #(
    parameter integer AXIL_AW = 12,
    parameter integer TRACE_ENABLE = 0
)(
    input  wire                 aclk,
    input  wire                 aresetn,
    input  wire [AXIL_AW-1:0]   s_axi_awaddr,
    input  wire                 s_axi_awvalid,
    output wire                 s_axi_awready,
    input  wire [31:0]          s_axi_wdata,
    input  wire [3:0]           s_axi_wstrb,
    input  wire                 s_axi_wvalid,
    output wire                 s_axi_wready,
    output wire [1:0]           s_axi_bresp,
    output wire                 s_axi_bvalid,
    input  wire                 s_axi_bready,
    input  wire [AXIL_AW-1:0]   s_axi_araddr,
    input  wire                 s_axi_arvalid,
    output wire                 s_axi_arready,
    output wire [31:0]          s_axi_rdata,
    output wire [1:0]           s_axi_rresp,
    output wire                 s_axi_rvalid,
    input  wire                 s_axi_rready,

    // M1 integration seam. These lifecycle ports connect to the run-configuration
    // fetcher/run controller in M2/M3 and are not part of the final external
    // product interface.
    output wire                 run_start,
    output wire                 abort_request,
    output wire                 irq,
    output wire [63:0]          run_cfg_addr,

    input  wire                 engine_busy,
    input  wire                 cfg_fetch_active,
    input  wire                 array_active,
    input  wire                 writeback_active,
    input  wire                 abort_pending,
    input  wire                 done_pulse,
    input  wire [3:0]           stop_reason,
    input  wire [6:0]           support_count,
    input  wire                 error_pulse,
    input  wire [3:0]           error_class,
    input  wire [7:0]           error_code,
    input  wire [7:0]           error_phase,
    input  wire [4:0]           cfg_error_word,
    input  wire [31:0]          error_detail,
    input  wire [7:0]           phase_progress,
    input  wire [15:0]          outer_progress,
    input  wire [7:0]           solver_progress,
    input  wire [63:0]          total_cycles
);

    wire                 csr_wr_valid;
    wire [AXIL_AW-1:0]   csr_wr_addr;
    wire [31:0]          csr_wr_data;
    wire [3:0]           csr_wr_strb;
    wire [1:0]           csr_wr_resp;
    wire                 csr_rd_valid;
    wire [AXIL_AW-1:0]   csr_rd_addr;
    wire [31:0]          csr_rd_data;
    wire [1:0]           csr_rd_resp;

    axilite_slave #(.AXIL_AW(AXIL_AW), .AXIL_DW(32)) u_axilite_slave (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .csr_wr_valid(csr_wr_valid), .csr_wr_addr(csr_wr_addr),
        .csr_wr_data(csr_wr_data), .csr_wr_strb(csr_wr_strb),
        .csr_wr_resp(csr_wr_resp), .csr_rd_valid(csr_rd_valid),
        .csr_rd_addr(csr_rd_addr), .csr_rd_data(csr_rd_data),
        .csr_rd_resp(csr_rd_resp)
    );

    reconstruction_csr #(
        .AXIL_AW(AXIL_AW),
        .TRACE_ENABLE(TRACE_ENABLE)
    ) u_reconstruction_csr (
        .clk(aclk), .rst_n(aresetn),
        .csr_wr_valid(csr_wr_valid), .csr_wr_addr(csr_wr_addr),
        .csr_wr_data(csr_wr_data), .csr_wr_strb(csr_wr_strb),
        .csr_wr_resp(csr_wr_resp),
        .csr_rd_valid(csr_rd_valid), .csr_rd_addr(csr_rd_addr),
        .csr_rd_data(csr_rd_data), .csr_rd_resp(csr_rd_resp),
        .run_start(run_start),
        .abort_request(abort_request),
        .irq(irq),
        .run_cfg_addr(run_cfg_addr),
        .engine_busy(engine_busy),
        .cfg_fetch_active(cfg_fetch_active),
        .array_active(array_active),
        .writeback_active(writeback_active),
        .abort_pending(abort_pending),
        .done_pulse(done_pulse),
        .stop_reason(stop_reason),
        .support_count(support_count),
        .error_pulse(error_pulse), .error_class(error_class),
        .error_code(error_code), .error_phase(error_phase),
        .cfg_error_word(cfg_error_word),
        .error_detail(error_detail),
        .phase_progress(phase_progress),
        .outer_progress(outer_progress),
        .solver_progress(solver_progress),
        .total_cycles(total_cycles)
    );

endmodule

`default_nettype wire

