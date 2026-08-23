// Focused unit verification for rtl/v2/control/dma_ctrl.v.
//
// Covers the AXI-master corners the K-sweep testbench cannot reach (its
// transfers are always single 256-beat bursts while the core is idle):
//   - multi-burst reads (length > 256): the DDR address must advance by one
//     whole burst at each re-issue and every word must land in order;
//   - RRESP SLVERR mid-burst: the master must keep accepting beats through
//     rlast, write only the beats that preceded the error, and finish with
//     ERR_READ;
//   - single-burst read, exact-256 read, and multi-burst write regression.
//
// Standalone; not part of the canonical K-sweep regression.  Run with:
//   iverilog -g2005 -o tb_dma_ctrl.vvp verification/v2/dma/tb_dma_ctrl.v \
//            rtl/v2/control/dma_ctrl.v && vvp tb_dma_ctrl.vvp
// or the same two files through xvlog/xelab/xsim.  PASS criterion:
// "DMA-CTRL: ALL TESTS PASSED".
`timescale 1ns/1ps
module tb_dma_ctrl;
    localparam AXI_AW = 32, AXI_DW = 32, COLS = 8, MEM_AW = 10;
    localparam DATA_W = 24, IDX_W = 10;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg                 start_r;
    reg                 dir_r;
    reg  [2:0]          vec_id_r;
    reg  [IDX_W-1:0]    length_r;
    reg  [AXI_AW-1:0]   ddr_r;
    wire                done_w, error_w, busy_w;
    wire [3:0]          error_code_w;

    wire [AXI_AW-1:0]   m_axi_araddr;
    wire [7:0]          m_axi_arlen;
    wire [2:0]          m_axi_arsize;
    wire [1:0]          m_axi_arburst;
    wire                m_axi_arvalid;
    reg                 m_axi_arready = 1'b1;
    wire [AXI_DW-1:0]   m_axi_rdata;
    wire [1:0]          m_axi_rresp;
    wire                m_axi_rvalid;
    wire                m_axi_rlast;
    wire                m_axi_rready;

    wire [AXI_AW-1:0]   m_axi_awaddr;
    wire [7:0]          m_axi_awlen;
    wire [1:0]          m_axi_awburst;
    wire                m_axi_awvalid;
    reg                 m_axi_awready = 1'b1;
    wire [AXI_DW-1:0]   m_axi_wdata;
    wire [AXI_DW/8-1:0] m_axi_wstrb;
    wire                m_axi_wlast;
    wire                m_axi_wvalid;
    reg                 m_axi_wready = 1'b1;
    reg  [1:0]          m_axi_bresp = 2'b00;
    reg                 m_axi_bvalid = 0;
    wire                m_axi_bready;

    wire [COLS*MEM_AW-1:0]  spm_addr;
    wire [COLS*DATA_W-1:0]  spm_wdata;
    wire [COLS-1:0]         spm_wen;
    reg  [COLS*DATA_W-1:0]  spm_rdata;

    dma_ctrl #(.AXI_AW(AXI_AW), .AXI_DW(AXI_DW), .COLS(COLS),
               .MEM_AW(MEM_AW), .DATA_W(DATA_W), .IDX_W(IDX_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start_r), .dir(dir_r), .vec_id(vec_id_r),
        .length(length_r), .ddr_addr(ddr_r),
        .done(done_w), .error(error_w), .error_code(error_code_w), .busy(busy_w),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rlast(m_axi_rlast),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_arsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .spm_addr(spm_addr), .spm_wdata(spm_wdata), .spm_wen(spm_wen),
        .spm_rdata(spm_rdata)
    );

    // ------------------------------------------------------------------
    // SPM model: one flat word per {bank address, lane}; first-write wins
    // so double writes are detectable.
    // ------------------------------------------------------------------
    reg [DATA_W-1:0] spm_word [0:(1<<MEM_AW)*COLS-1];
    reg [DATA_W-1:0] first_wr [0:(1<<MEM_AW)*COLS-1];
    reg              wr_seen  [0:(1<<MEM_AW)*COLS-1];
    integer wr_count;
    integer wi;
    always @(posedge clk) begin
        for (wi = 0; wi < COLS; wi = wi + 1) begin
            if (spm_wen[wi] && !wr_seen[spm_addr[wi*MEM_AW +: MEM_AW]*COLS + wi]) begin
                first_wr[spm_addr[wi*MEM_AW +: MEM_AW]*COLS + wi] <=
                    spm_wdata[wi*DATA_W +: DATA_W];
                wr_seen[spm_addr[wi*MEM_AW +: MEM_AW]*COLS + wi] <= 1'b1;
                wr_count = wr_count + 1;
            end
        end
    end
    integer ri;
    always @(*) begin
        for (ri = 0; ri < COLS; ri = ri + 1)
            spm_rdata[ri*DATA_W +: DATA_W] =
                spm_word[spm_addr[ri*MEM_AW +: MEM_AW]*COLS + ri];
    end

    // ------------------------------------------------------------------
    // AXI read responder: streams ARLEN+1 beats; optional SLVERR on a
    // configured beat index of the current burst (negative = none).
    // ------------------------------------------------------------------
    reg         rch_active = 0;
    reg  [8:0]  rbeats_left = 0;
    reg  [8:0]  rbeat_no = 0;
    integer     err_beat_cfg = -1;
    reg  [AXI_DW-1:0] rdata_val = 0;
    integer     r_total = 0;

    wire ar_fire = m_axi_arvalid && m_axi_arready;
    wire r_fire  = m_axi_rvalid && m_axi_rready;

    assign m_axi_rvalid = rch_active;
    assign m_axi_rlast  = rch_active && (rbeats_left == 9'd1);
    assign m_axi_rdata  = rdata_val;
    assign m_axi_rresp  = (rbeat_no == err_beat_cfg) ? 2'b10 : 2'b00;

    always @(posedge clk) begin
        if (ar_fire) begin
            rch_active  <= 1'b1;
            rbeats_left <= m_axi_arlen + 9'd1;
            rbeat_no    <= 9'd0;
            rdata_val   <= r_total;
        end else if (rch_active && r_fire) begin
            rdata_val  <= rdata_val + 1'b1;
            rbeat_no   <= rbeat_no + 1'b1;
            rbeats_left <= rbeats_left - 1'b1;
            if (m_axi_rlast)
                rch_active <= 1'b0;
        end
        if (r_fire)
            r_total = r_total + 1;
    end

    // AR address monitor
    integer ar_seen = 0;
    reg [AXI_AW-1:0] ar_addr_log [0:7];
    always @(posedge clk) begin
        if (ar_fire) begin
            ar_addr_log[ar_seen] <= m_axi_araddr;
            ar_seen = ar_seen + 1;
        end
    end

    // ------------------------------------------------------------------
    // AXI write responder: always ready; BVALID two cycles after WLAST.
    // ------------------------------------------------------------------
    wire w_fire = m_axi_wvalid && m_axi_wready;
    integer w_total = 0;
    reg [1:0] b_delay = 0;
    always @(posedge clk) begin
        if (w_fire) begin
            w_total = w_total + 1;
            if (m_axi_wlast)
                b_delay <= 2'd2;
        end else if (b_delay != 0) begin
            b_delay <= b_delay - 1'b1;
            if (b_delay == 2'd1)
                m_axi_bvalid <= 1'b1;
        end
        if (m_axi_bvalid && m_axi_bready)
            m_axi_bvalid <= 1'b0;
    end

    // ------------------------------------------------------------------
    // Test driver
    // ------------------------------------------------------------------
    integer errors = 0;
    integer k;
    reg [DATA_W-1:0] expw;
    // The DUT clears error/error_code one cycle after done (S_IDLE default);
    // capture them on the done cycle itself.
    reg done_error_q = 0;
    reg [3:0] done_ecode_q = 0;
    always @(posedge clk) begin
        if (done_w) begin
            done_error_q <= error_w;
            done_ecode_q <= error_code_w;
        end
    end

    task clearspm;
        begin
            for (k = 0; k < (1<<MEM_AW)*COLS; k = k + 1) begin
                wr_seen[k] = 1'b0;
                first_wr[k] = {DATA_W{1'bx}};
                spm_word[k] = k;  // distinct preload for the write path
            end
            wr_count = 0;
        end
    endtask

    task run_xfer(input do_dir, input [IDX_W-1:0] len, input [AXI_AW-1:0] base);
        begin
            @(negedge clk);
            dir_r    = do_dir;
            vec_id_r = 3'd0;
            length_r = len;
            ddr_r    = base;
            start_r  = 1'b1;
            @(negedge clk);
            start_r  = 1'b0;
            r_total  = 0;
            w_total  = 0;
            ar_seen  = 0;
            k = 0;
            while (!done_w && k < 20000) begin
                @(negedge clk);
                k = k + 1;
            end
            if (!done_w) begin
                $display("FAIL: timeout waiting for done");
                errors = errors + 1;
            end
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task check_words(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                expw = i;
                if (first_wr[i] !== expw) begin
                    $display("FAIL: word %0d = %h expected %0d", i, first_wr[i], i);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        start_r = 0; dir_r = 0; vec_id_r = 0; length_r = 0; ddr_r = 0;
        clearspm;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // Test 1: normal single-burst read, length 16.
        clearspm;
        err_beat_cfg = -1;
        run_xfer(1'b0, 16, 32'h0000_1000);
        if (done_error_q) begin $display("FAIL t1: unexpected error"); errors = errors + 1; end
        if (wr_count != 16) begin $display("FAIL t1: wr_count=%0d expected 16", wr_count); errors = errors + 1; end
        check_words(16);
        $display("TEST1 single-burst read 16: done (wr_count=%0d)", wr_count);

        // Test 2 (H1): multi-burst read, length 300 = 256 + 44.
        // The second burst must start at base + 256*4 and all 300 words
        // must land in order with no overlap.
        clearspm;
        err_beat_cfg = -1;
        run_xfer(1'b0, 300, 32'h0000_2000);
        if (done_error_q) begin $display("FAIL t2: unexpected error"); errors = errors + 1; end
        if (ar_seen !== 2) begin
            $display("FAIL t2: ar_seen=%0d expected 2", ar_seen); errors = errors + 1;
        end
        if (ar_addr_log[1] !== 32'h0000_2000 + 256*4) begin
            $display("FAIL t2 (H1): second burst araddr=%h expected %h",
                     ar_addr_log[1], 32'h0000_2000 + 256*4);
            errors = errors + 1;
        end
        if (wr_count != 300) begin $display("FAIL t2: wr_count=%0d expected 300", wr_count); errors = errors + 1; end
        check_words(300);
        $display("TEST2 multi-burst read 300: done (ar2=%h wr_count=%0d)", ar_addr_log[1], wr_count);

        // Test 3 (H2): SLVERR on beat 10 of a 256-beat read burst.
        // The master must keep rready through rlast (256 accepted beats),
        // write only beats 0..9, and finish with ERR_READ.
        clearspm;
        err_beat_cfg = 10;
        run_xfer(1'b0, 256, 32'h0000_3000);
        if (!done_error_q) begin $display("FAIL t3: error not flagged"); errors = errors + 1; end
        if (done_ecode_q !== 4'd1) begin $display("FAIL t3: error_code=%0d expected 1", error_code_w); errors = errors + 1; end
        if (r_total !== 256) begin
            $display("FAIL t3 (H2): only %0d beats accepted, expected 256 (drain through rlast)", r_total);
            errors = errors + 1;
        end
        if (wr_count !== 10) begin $display("FAIL t3: wr_count=%0d expected 10", wr_count); errors = errors + 1; end
        check_words(10);
        $display("TEST3 SLVERR drain: done (accepted=%0d wrote=%0d err_code=%0d)",
                 r_total, wr_count, error_code_w);

        // Test 4: multi-burst write, length 300 (write-path regression).
        clearspm;
        err_beat_cfg = -1;
        run_xfer(1'b1, 300, 32'h0000_4000);
        if (done_error_q) begin $display("FAIL t4: unexpected error"); errors = errors + 1; end
        if (w_total !== 300) begin $display("FAIL t4: w_total=%0d expected 300", w_total); errors = errors + 1; end
        $display("TEST4 multi-burst write 300: done (w_total=%0d)", w_total);

        // Test 5: read length 256 (exactly one full burst).
        clearspm;
        err_beat_cfg = -1;
        run_xfer(1'b0, 256, 32'h0000_5000);
        if (done_error_q) begin $display("FAIL t5: unexpected error"); errors = errors + 1; end
        if (wr_count != 256) begin $display("FAIL t5: wr_count=%0d expected 256", wr_count); errors = errors + 1; end
        check_words(256);
        $display("TEST5 exact-256 read: done (wr_count=%0d)", wr_count);

        if (errors == 0)
            $display("DMA-CTRL: ALL TESTS PASSED");
        else
            $display("DMA-CTRL: %0d FAILURES", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("DMA-CTRL: GLOBAL TIMEOUT");
        $finish;
    end
endmodule
