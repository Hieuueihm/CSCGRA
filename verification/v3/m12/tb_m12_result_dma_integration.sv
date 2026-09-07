`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"
`include "reconstruction_control_defs.vh"
`include "result_format_defs.vh"

module tb_m12_result_dma_integration;
    localparam integer SUPPORT_MAX = 4;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer INDEX_W = 10;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer cycle_count = 0;
    integer failures = 0;

    reg result_start_valid = 1'b0;
    wire result_start_ready;
    reg result_abort_request = 1'b0;
    reg [1:0] result_mode = 2'd0;
    reg [10:0] signal_length = 11'd0;
    reg [6:0] support_count = 7'd0;
    reg [SUPPORT_MAX*INDEX_W-1:0] support_indices = 0;
    reg [SUPPORT_MAX*DATA_W-1:0] support_coefficients = 0;
    reg [63:0] dense_result_address = 64'd0;
    reg [63:0] sparse_result_address = 64'd0;
    reg [31:0] user_tag = 32'd0;
    reg [3:0] stop_reason = 4'd0;
    wire writeback_active;
    wire completion_valid;
    reg completion_ready = 1'b1;
    wire [3:0] completion_stop_reason;
    wire error_valid;
    reg error_ready = 1'b1;
    wire [3:0] error_class;
    wire [7:0] error_code;
    wire [1:0] error_response;
    wire [8:0] error_beat;
    wire [7:0] error_tag;
    wire dma_active;

    wire [63:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    reg m_axi_arready = 1'b0;
    reg [127:0] m_axi_rdata = 128'd0;
    reg [1:0] m_axi_rresp = 2'd0;
    reg m_axi_rlast = 1'b0;
    reg m_axi_rvalid = 1'b0;
    wire m_axi_rready;
    wire [63:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire m_axi_awvalid;
    wire m_axi_awready = cycle_count[1:0] != 2'b00;
    wire [127:0] m_axi_wdata;
    wire [15:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_wready = cycle_count[2:0] != 3'b101;
    reg [1:0] m_axi_bresp = 2'd0;
    reg m_axi_bvalid = 1'b0;
    wire m_axi_bready;

    reg [63:0] burst_addresses [0:7];
    reg [7:0] burst_lengths [0:7];
    reg [63:0] beat_addresses [0:31];
    reg [127:0] beat_data [0:31];
    integer burst_count = 0;
    integer beat_count = 0;
    integer active_burst = -1;
    integer active_burst_beats = 0;
    integer active_burst_seen = 0;
    integer response_delay = 0;
    integer response_burst = -1;
    integer inject_error_burst = -1;
    integer completion_count = 0;
    integer error_count = 0;
    reg [3:0] observed_stop_reason = 4'd0;

    m12_result_dma_integration #(.SUPPORT_MAX(SUPPORT_MAX)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .result_start_valid(result_start_valid),
        .result_start_ready(result_start_ready),
        .result_abort_request(result_abort_request),
        .result_mode(result_mode), .signal_length(signal_length),
        .support_count(support_count), .support_indices(support_indices),
        .support_coefficients(support_coefficients),
        .dense_result_address(dense_result_address),
        .sparse_result_address(sparse_result_address),
        .user_tag(user_tag), .stop_reason(stop_reason),
        .writeback_active(writeback_active),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_stop_reason(completion_stop_reason),
        .error_valid(error_valid), .error_ready(error_ready),
        .error_class(error_class), .error_code(error_code),
        .error_response(error_response), .error_beat(error_beat),
        .error_tag(error_tag),
        .aux_req_valid(3'b000), .aux_req_ready(),
        .aux_req_write(3'b000), .aux_req_addr(192'd0),
        .aux_req_bytes(48'd0), .aux_req_tag(24'd0),
        .aux_wr_valid(3'b000), .aux_wr_ready(),
        .aux_wr_data(384'd0), .aux_wr_keep(48'd0),
        .aux_wr_last(3'b000), .aux_rd_valid(),
        .aux_rd_ready(3'b000), .aux_rd_data(), .aux_rd_last(),
        .aux_rd_resp(), .aux_rd_tag(), .aux_done_valid(),
        .aux_done_ready(3'b000), .aux_done_tag(), .aux_done_error(),
        .aux_done_resp(), .aux_done_beat(), .dma_active(dma_active),
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

    function automatic [127:0] expected_header;
        input [1:0] mode;
        input [10:0] length;
        input [6:0] count;
        input [31:0] tag_value;
        input [3:0] stop_value;
        reg [12:0] dense_bytes;
        reg [10:0] sparse_bytes;
        begin
            dense_bytes = length << 2;
            sparse_bytes = count << 3;
            expected_header = {
                7'd0, 1'b1, sparse_bytes, dense_bytes,
                `RECON_RESULT_FORMAT_REVISION, mode, stop_value,
                count, length, tag_value, `RECON_RESULT_HEADER_MAGIC
            };
        end
    endfunction

    task automatic check;
        input condition;
        input [1023:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic reset_case;
        begin
            rst_n = 1'b0;
            result_start_valid = 1'b0;
            result_abort_request = 1'b0;
            support_indices = 0;
            support_coefficients = 0;
            burst_count = 0;
            beat_count = 0;
            active_burst = -1;
            active_burst_beats = 0;
            active_burst_seen = 0;
            response_delay = 0;
            response_burst = -1;
            inject_error_burst = -1;
            completion_count = 0;
            error_count = 0;
            m_axi_bvalid = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic launch;
        begin
            while (!result_start_ready) @(posedge clk);
            @(negedge clk);
            result_start_valid = 1'b1;
            @(negedge clk);
            result_start_valid = 1'b0;
        end
    endtask

    task automatic wait_terminal;
        integer timeout;
        begin
            timeout = 0;
            while ((completion_count + error_count) == 0 && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 2000, "integration terminal timeout");
            repeat (4) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!rst_n) begin
            m_axi_bvalid <= 1'b0;
            response_delay <= 0;
        end else begin
            check(!m_axi_arvalid, "result-only integration must not issue AXI reads");
            if (m_axi_awvalid && m_axi_awready) begin
                burst_addresses[burst_count] <= m_axi_awaddr;
                burst_lengths[burst_count] <= m_axi_awlen;
                active_burst <= burst_count;
                active_burst_beats <= m_axi_awlen + 1;
                active_burst_seen <= 0;
                burst_count <= burst_count + 1;
                check(m_axi_awsize == 3'd4, "AXI write size");
                check(m_axi_awburst == 2'b01, "AXI write burst");
            end
            if (m_axi_wvalid && m_axi_wready) begin
                beat_addresses[beat_count] <=
                    burst_addresses[active_burst] + active_burst_seen * 16;
                beat_data[beat_count] <= m_axi_wdata;
                beat_count <= beat_count + 1;
                active_burst_seen <= active_burst_seen + 1;
                check(m_axi_wstrb == 16'hffff, "AXI WSTRB");
                check(m_axi_wlast ==
                      (active_burst_seen == active_burst_beats - 1),
                      "AXI WLAST");
                if (m_axi_wlast) begin
                    response_burst <= active_burst;
                    response_delay <= 2;
                    active_burst <= -1;
                end
            end
            if (response_delay > 0) begin
                response_delay <= response_delay - 1;
                if (response_delay == 1) begin
                    m_axi_bvalid <= 1'b1;
                    m_axi_bresp <= (response_burst == inject_error_burst) ?
                        2'b10 : 2'b00;
                end
            end
            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;
            if (completion_valid) begin
                completion_count <= completion_count + 1;
                observed_stop_reason <= completion_stop_reason;
            end
            if (error_valid)
                error_count <= error_count + 1;
        end
    end

    initial begin
        reset_case();
        result_mode = `RECON_RESULT_MODE_BOTH;
        signal_length = 11'd4;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd2;
        support_coefficients[0 +: DATA_W] = -27'sd6;
        dense_result_address = 64'h8000;
        sparse_result_address = 64'h9000;
        user_tag = 32'hfeed_1234;
        stop_reason = `RECON_STOP_SUPPORT_STABLE;
        launch();
        wait_terminal();
        check(completion_count == 1 && error_count == 0,
              "one successful terminal");
        check(observed_stop_reason == `RECON_STOP_SUPPORT_STABLE,
              "completion stop reason");
        check(burst_count == 3 && beat_count == 3, "both-mode AXI count");
        check(burst_addresses[0] == 64'h8010, "dense body address");
        check(burst_addresses[1] == 64'h9010, "sparse body address");
        check(burst_addresses[2] == 64'h9000, "success header last");
        check(beat_data[0] == {32'd0, 32'hffff_fffa, 64'd0},
              "dense expanded beat");
        check(beat_data[1] == {64'd0, 32'd2, 32'hffff_fffa},
              "sparse record beat");
        check(beat_data[2] == expected_header(
              `RECON_RESULT_MODE_BOTH, 11'd4, 7'd1, 32'hfeed_1234,
              `RECON_STOP_SUPPORT_STABLE), "integration header");
        check(!writeback_active && !dma_active, "integration returns idle");

        reset_case();
        result_mode = `RECON_RESULT_MODE_BOTH;
        signal_length = 11'd4;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd0;
        support_coefficients[0 +: DATA_W] = 27'sd2;
        dense_result_address = 64'ha000;
        sparse_result_address = 64'hb000;
        inject_error_burst = 1;
        launch();
        wait_terminal();
        check(completion_count == 0 && error_count == 1,
              "one DMA error terminal");
        check(error_class == `RECON_ERROR_CLASS_DMA_WRITE,
              "DMA write error class");
        check(error_code == 8'h10 && error_response == 2'b10,
              "DMA write error detail");
        check(burst_count == 2, "error suppresses success header");

        if (failures == 0)
            $display("M12 RESULT DMA INTEGRATION PASS");
        else
            $display("FAIL: M12 RESULT DMA INTEGRATION failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
