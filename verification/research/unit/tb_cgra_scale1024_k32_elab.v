`timescale 1ns/1ps
// Elaboration/smoke top for the scalable compile-time profile. The normal
// regression keeps its N256/K16 resource point; this instance proves that all
// controller, support, top-K and LS widths compose at N1024/K32.
module tb_cgra_scale1024_k32_elab;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    cgra_top #(
        .IDX_W(11),
        .SPARSE_MAX_N(1024),
        .SPARSE_MAX_K(32)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(14'd0), .s_axi_awvalid(1'b0),
        .s_axi_wdata(32'd0), .s_axi_wstrb(4'd0), .s_axi_wvalid(1'b0),
        .s_axi_bready(1'b1), .s_axi_araddr(14'd0), .s_axi_arvalid(1'b0),
        .s_axi_rready(1'b1), .m_axi_arready(1'b1),
        .m_axi_rdata(32'd0), .m_axi_rvalid(1'b0), .m_axi_rlast(1'b0),
        .m_axi_awready(1'b1), .m_axi_wready(1'b1),
        .m_axi_bresp(2'd0), .m_axi_bvalid(1'b0)
    );

    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        repeat (8) @(negedge clk);
        $display("CGRA_SCALE1024_K32_ELAB PASS");
        $finish;
    end
endmodule
