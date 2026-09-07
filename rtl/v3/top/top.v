`timescale 1ns/1ps
`default_nettype none

// Top-level package wrapper ONLY.  `top` owns no logic and no lifecycle
// state: it re-exports the complete compressive-sensing reconstruction
// system (compute fabric + lifecycle + loader aperture) packaged by
// `m13_zcu106_shell_core`, for flows that need a plain-RTL chip top.
//
// Hierarchy:
//   top -> m13_zcu106_shell_core -> { m13_compute_lifecycle_integration,
//                                     m13_loader_aperture }
//
// The ZCU106 block design does not use this wrapper; it instantiates
// `m13_zcu106_shell_core` directly through `m13_zcu106_bd_wrapper`.
// Lifecycle-only consumers (M12 boundary) instantiate `m12_lifecycle_top`.
module top #(
    parameter integer AXIL_AW = 12,
    parameter integer TAG_W = 8
)(
    input  wire ap_clk,
    input  wire ap_rst_n,

    input  wire [AXIL_AW-1:0] s_axi_control_awaddr,
    input  wire s_axi_control_awvalid,
    output wire s_axi_control_awready,
    input  wire [31:0] s_axi_control_wdata,
    input  wire [3:0] s_axi_control_wstrb,
    input  wire s_axi_control_wvalid,
    output wire s_axi_control_wready,
    output wire [1:0] s_axi_control_bresp,
    output wire s_axi_control_bvalid,
    input  wire s_axi_control_bready,
    input  wire [AXIL_AW-1:0] s_axi_control_araddr,
    input  wire s_axi_control_arvalid,
    output wire s_axi_control_arready,
    output wire [31:0] s_axi_control_rdata,
    output wire [1:0] s_axi_control_rresp,
    output wire s_axi_control_rvalid,
    input  wire s_axi_control_rready,

    input  wire [AXIL_AW-1:0] s_axi_loader_awaddr,
    input  wire s_axi_loader_awvalid,
    output wire s_axi_loader_awready,
    input  wire [31:0] s_axi_loader_wdata,
    input  wire [3:0] s_axi_loader_wstrb,
    input  wire s_axi_loader_wvalid,
    output wire s_axi_loader_wready,
    output wire [1:0] s_axi_loader_bresp,
    output wire s_axi_loader_bvalid,
    input  wire s_axi_loader_bready,
    input  wire [AXIL_AW-1:0] s_axi_loader_araddr,
    input  wire s_axi_loader_arvalid,
    output wire s_axi_loader_arready,
    output wire [31:0] s_axi_loader_rdata,
    output wire [1:0] s_axi_loader_rresp,
    output wire s_axi_loader_rvalid,
    input  wire s_axi_loader_rready,

    output wire [63:0] m_axi_gmem_araddr,
    output wire [7:0] m_axi_gmem_arlen,
    output wire [2:0] m_axi_gmem_arsize,
    output wire [1:0] m_axi_gmem_arburst,
    output wire m_axi_gmem_arvalid,
    input  wire m_axi_gmem_arready,
    input  wire [127:0] m_axi_gmem_rdata,
    input  wire [1:0] m_axi_gmem_rresp,
    input  wire m_axi_gmem_rlast,
    input  wire m_axi_gmem_rvalid,
    output wire m_axi_gmem_rready,
    output wire [63:0] m_axi_gmem_awaddr,
    output wire [7:0] m_axi_gmem_awlen,
    output wire [2:0] m_axi_gmem_awsize,
    output wire [1:0] m_axi_gmem_awburst,
    output wire m_axi_gmem_awvalid,
    input  wire m_axi_gmem_awready,
    output wire [127:0] m_axi_gmem_wdata,
    output wire [15:0] m_axi_gmem_wstrb,
    output wire m_axi_gmem_wlast,
    output wire m_axi_gmem_wvalid,
    input  wire m_axi_gmem_wready,
    input  wire [1:0] m_axi_gmem_bresp,
    input  wire m_axi_gmem_bvalid,
    output wire m_axi_gmem_bready,

    output wire interrupt
);
    m13_zcu106_shell_core #(
        .AXIL_AW(AXIL_AW),
        .TAG_W(TAG_W)
    ) u_shell_core (.*);
endmodule

`default_nettype wire
