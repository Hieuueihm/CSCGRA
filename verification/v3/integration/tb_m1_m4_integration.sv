`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_m1_m4_integration;
    `include "m3_control_image.vh"

    localparam [63:0] RUN_CFG_ADDRESS = 64'h0000_0000_0000_4000;
    localparam [63:0] VECTOR_ADDRESS  = 64'h0000_0000_0000_1000;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer pc1_stalls = 0;
    integer integration_errors = 0;
    integer cfg_reads = 0;
    integer vector_reads = 0;

    reg [11:0] s_axi_awaddr = 12'd0;
    reg s_axi_awvalid = 1'b0;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata = 32'd0;
    reg [3:0] s_axi_wstrb = 4'd0;
    reg s_axi_wvalid = 1'b0;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready = 1'b0;
    reg [11:0] s_axi_araddr = 12'd0;
    reg s_axi_arvalid = 1'b0;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready = 1'b0;

    wire [63:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [127:0] m_axi_rdata = 128'd0;
    reg [1:0] m_axi_rresp = 2'b00;
    reg m_axi_rlast = 1'b0;
    reg m_axi_rvalid = 1'b0;
    wire m_axi_rready;
    wire [63:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire m_axi_awvalid;
    wire [127:0] m_axi_wdata;
    wire [15:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_bready;

    reg img_wr_valid = 1'b0;
    wire img_wr_ready;
    reg img_wr_bank = 1'b0;
    reg [3:0] img_wr_plane = 4'd0;
    reg [7:0] img_wr_addr = 8'd0;
    reg [71:0] img_wr_data = 72'd0;
    wire img_wr_resp_valid;
    reg img_wr_resp_ready = 1'b0;
    wire img_wr_resp_error;
    wire [7:0] img_wr_resp_code;
    wire [31:0] img_wr_resp_detail;
    reg img_finalize_valid = 1'b0;
    wire img_finalize_ready;
    reg img_finalize_bank = 1'b0;
    wire img_finalize_resp_valid;
    reg img_finalize_resp_ready = 1'b0;
    wire img_finalize_resp_error;
    wire [7:0] img_finalize_resp_code;
    wire [31:0] img_finalize_resp_detail;

    reg mem_cfg_wr_valid = 1'b0;
    wire mem_cfg_wr_ready;
    reg mem_cfg_wr_bank = 1'b0;
    reg [5:0] mem_cfg_wr_id = 6'd0;
    reg [63:0] mem_cfg_wr_data = 64'd0;
    wire mem_cfg_wr_resp_valid;
    reg mem_cfg_wr_resp_ready = 1'b0;
    wire mem_cfg_wr_resp_error;
    wire [7:0] mem_cfg_wr_resp_code;
    wire [31:0] mem_cfg_wr_resp_detail;

    reg preload_valid = 1'b0;
    wire preload_ready;
    reg [63:0] preload_src_addr = VECTOR_ADDRESS;
    reg [5:0] preload_cfg_id = 6'd0;
    reg [63:0] preload_cfg = M3_MEMORY_CONFIGURATION_0;
    wire preload_done_valid;
    reg preload_done_ready = 1'b0;
    wire [5:0] preload_done_cfg_id;
    wire preload_done_error;
    wire [7:0] preload_done_code;
    wire preload_active;

    reg [7:0] predicate_values = 8'b0000_0100;
    reg array_sink_ready = 1'b0;
    wire irq, engine_busy, cfg_fetch_active, array_active;
    wire cycle_valid, cycle_commit, cycle_stalled;
    wire [7:0] array_pc;
    wire [1:0] cluster_mask;
    wire [575:0] tile_ctx;
    wire [35:0] array_ctx, stream_ctx, resource_ctx;
    wire [863:0] vector_a_data, vector_b_data;
    wire vector_a_valid, vector_b_valid;
    wire [26:0] routed_scalar;
    wire [31:0] array_commit_count, array_stall_count;
    wire [63:0] resident_bitmap;
    wire integration_error;

    m1_m4_integration_harness dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready), .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(1'b1),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(1'b1), .m_axi_bresp(2'b00),
        .m_axi_bvalid(1'b0), .m_axi_bready(m_axi_bready),
        .img_wr_valid(img_wr_valid), .img_wr_ready(img_wr_ready),
        .img_wr_bank(img_wr_bank), .img_wr_plane(img_wr_plane),
        .img_wr_addr(img_wr_addr), .img_wr_data(img_wr_data),
        .img_wr_resp_valid(img_wr_resp_valid),
        .img_wr_resp_ready(img_wr_resp_ready),
        .img_wr_resp_error(img_wr_resp_error),
        .img_wr_resp_code(img_wr_resp_code),
        .img_wr_resp_detail(img_wr_resp_detail),
        .img_finalize_valid(img_finalize_valid),
        .img_finalize_ready(img_finalize_ready),
        .img_finalize_bank(img_finalize_bank),
        .img_finalize_resp_valid(img_finalize_resp_valid),
        .img_finalize_resp_ready(img_finalize_resp_ready),
        .img_finalize_resp_error(img_finalize_resp_error),
        .img_finalize_resp_code(img_finalize_resp_code),
        .img_finalize_resp_detail(img_finalize_resp_detail),
        .mem_cfg_wr_valid(mem_cfg_wr_valid),
        .mem_cfg_wr_ready(mem_cfg_wr_ready),
        .mem_cfg_wr_bank(mem_cfg_wr_bank), .mem_cfg_wr_id(mem_cfg_wr_id),
        .mem_cfg_wr_data(mem_cfg_wr_data),
        .mem_cfg_wr_resp_valid(mem_cfg_wr_resp_valid),
        .mem_cfg_wr_resp_ready(mem_cfg_wr_resp_ready),
        .mem_cfg_wr_resp_error(mem_cfg_wr_resp_error),
        .mem_cfg_wr_resp_code(mem_cfg_wr_resp_code),
        .mem_cfg_wr_resp_detail(mem_cfg_wr_resp_detail),
        .preload_valid(preload_valid), .preload_ready(preload_ready),
        .preload_src_addr(preload_src_addr), .preload_cfg_id(preload_cfg_id),
        .preload_cfg(preload_cfg), .preload_done_valid(preload_done_valid),
        .preload_done_ready(preload_done_ready),
        .preload_done_cfg_id(preload_done_cfg_id),
        .preload_done_error(preload_done_error),
        .preload_done_code(preload_done_code),
        .preload_active(preload_active), .residency_clear(1'b0),
        .residency_invalidate(1'b0), .residency_invalidate_id(6'd0),
        .predicate_values(predicate_values), .resource_req_ready(1'b1),
        .resource_rsp_valid(1'b1), .resource_event_valid(1'b0),
        .resource_event_id(4'd0), .residual_limit_reached(1'b0),
        .iteration_limit_reached(1'b0), .support_stable(1'b0),
        .residual_decreased(1'b0), .solver_converged(1'b0),
        .solver_fault(1'b0), .active_support(7'd8),
        .outer_iteration(16'd0), .solver_iteration(8'd0),
        .array_sink_ready(array_sink_ready), .vector_write_data(576'd0),
        .scalar_valid(1'b1), .scalar_data(27'd0),
        .phi_command_valid(), .phi_command_ready(1'b1), .phi_command(),
        .phi_cfg_id(), .phi_cfg_data(), .phi_symbol_valid(1'b0),
        .phi_symbol_ready(), .phi_nonzero(32'd0), .phi_sign(32'd0),
        .irq(irq), .engine_busy(engine_busy),
        .cfg_fetch_active(cfg_fetch_active), .array_active(array_active),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled), .array_pc(array_pc),
        .cluster_mask(cluster_mask), .tile_ctx(tile_ctx),
        .array_ctx(array_ctx), .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx), .vector_a_data(vector_a_data),
        .vector_a_valid(vector_a_valid), .vector_b_data(vector_b_data),
        .vector_b_valid(vector_b_valid), .routed_scalar(routed_scalar),
        .array_commit_count(array_commit_count),
        .array_stall_count(array_stall_count),
        .resident_bitmap(resident_bitmap),
        .integration_error(integration_error)
    );

    task automatic check(input condition, input [8*128-1:0] message);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s at %0t", message, $time);
            end
        end
    endtask

    task automatic send_aw(input [11:0] address);
        begin
            @(negedge clk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            do @(posedge clk); while (!s_axi_awready);
            @(negedge clk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task automatic send_w(input [31:0] data);
        begin
            @(negedge clk);
            s_axi_wdata = data;
            s_axi_wstrb = 4'hf;
            s_axi_wvalid = 1'b1;
            do @(posedge clk); while (!s_axi_wready);
            @(negedge clk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task automatic axil_write(
        input [11:0] address,
        input [31:0] data,
        input [1:0] expected_response
    );
        begin
            fork
                send_aw(address);
                send_w(data);
            join
            while (!s_axi_bvalid) @(posedge clk);
            check(s_axi_bresp == expected_response,
                  "AXI-Lite write response matches contract");
            @(negedge clk);
            s_axi_bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    task automatic axil_read(
        input [11:0] address,
        output [31:0] data,
        output [1:0] response
    );
        begin
            @(negedge clk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            do @(posedge clk); while (!s_axi_arready);
            @(negedge clk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            response = s_axi_rresp;
            @(negedge clk);
            s_axi_rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    task automatic write_image_word(
        input [3:0] plane,
        input [7:0] address,
        input [71:0] data
    );
        begin
            while (!img_wr_ready) @(negedge clk);
            @(negedge clk);
            img_wr_plane = plane;
            img_wr_addr = address;
            img_wr_data = data;
            img_wr_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_wr_valid = 1'b0;
            while (!img_wr_resp_valid) @(negedge clk);
            check(!img_wr_resp_error, "context image word accepted");
            img_wr_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_wr_resp_ready = 1'b0;
        end
    endtask

    task automatic finalize_image;
        begin
            while (!img_finalize_ready) @(negedge clk);
            @(negedge clk);
            img_finalize_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_finalize_valid = 1'b0;
            while (!img_finalize_resp_valid) @(negedge clk);
            check(!img_finalize_resp_error, "context image CFG closure passes");
            img_finalize_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_finalize_resp_ready = 1'b0;
        end
    endtask

    task automatic write_memory_configuration;
        begin
            while (!mem_cfg_wr_ready) @(negedge clk);
            @(negedge clk);
            mem_cfg_wr_id = 6'd0;
            mem_cfg_wr_data = M3_MEMORY_CONFIGURATION_0;
            mem_cfg_wr_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mem_cfg_wr_valid = 1'b0;
            while (!mem_cfg_wr_resp_valid) @(negedge clk);
            check(!mem_cfg_wr_resp_error, "memory configuration accepted");
            mem_cfg_wr_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mem_cfg_wr_resp_ready = 1'b0;
        end
    endtask

    task automatic preload_vector;
        begin
            while (!preload_ready) @(negedge clk);
            @(negedge clk);
            preload_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            preload_valid = 1'b0;
            timeout = 0;
            while (!preload_done_valid && timeout < 500) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(preload_done_valid && !preload_done_error,
                  "DMA preload reaches a successful terminal token");
            check(preload_done_cfg_id == 6'd0,
                  "DMA preload preserves memory configuration id");
            @(negedge clk);
            preload_done_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            preload_done_ready = 1'b0;
        end
    endtask

    reg [127:0] cfg_beats [0:3];
    reg read_active = 1'b0;
    reg [63:0] read_address = 64'd0;
    reg [7:0] read_length = 8'd0;
    reg [7:0] read_index = 8'd0;
    reg [31:0] memory_cycle = 32'd0;
    assign m_axi_arready = !read_active && !m_axi_rvalid && memory_cycle[0];

    function automatic [127:0] memory_payload(
        input [63:0] address,
        input [7:0] index
    );
        integer lane;
        integer signed value;
        reg [127:0] payload;
        begin
            payload = 128'd0;
            if (address == RUN_CFG_ADDRESS) begin
                case (index)
                    0: payload = cfg_beats[0];
                    1: payload = cfg_beats[1];
                    2: payload = cfg_beats[2];
                    default: payload = cfg_beats[3];
                endcase
            end else begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    value = index * 4 + lane - 16;
                    payload[lane*32 +: 32] = value[31:0];
                end
            end
            memory_payload = payload;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            read_active <= 1'b0;
            m_axi_rvalid <= 1'b0;
            memory_cycle <= 32'd0;
            cfg_reads <= 0;
            vector_reads <= 0;
        end else begin
            memory_cycle <= memory_cycle + 32'd1;
            if (m_axi_arvalid && m_axi_arready) begin
                read_active <= 1'b1;
                read_address <= m_axi_araddr;
                read_length <= m_axi_arlen;
                read_index <= 8'd0;
                if (m_axi_araddr == RUN_CFG_ADDRESS)
                    cfg_reads <= cfg_reads + 1;
                if (m_axi_araddr == VECTOR_ADDRESS)
                    vector_reads <= vector_reads + 1;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast)
                    read_active <= 1'b0;
                else
                    read_index <= read_index + 8'd1;
            end
            if (read_active && !m_axi_rvalid && memory_cycle[1]) begin
                m_axi_rdata <= memory_payload(read_address, read_index);
                m_axi_rresp <= 2'b00;
                m_axi_rlast <= read_index == read_length;
                m_axi_rvalid <= 1'b1;
            end
        end
    end

    integer lane;
    integer signed lane_value;
    always @(posedge clk) begin
        if (!rst_n) begin
            pc1_stalls <= 0;
            integration_errors <= 0;
            array_sink_ready <= 1'b0;
        end else begin
            if (integration_error)
                integration_errors <= integration_errors + 1;
            if (cycle_valid && array_pc == 8'd1 && cycle_stalled) begin
                pc1_stalls <= pc1_stalls + 1;
                if (pc1_stalls == 1)
                    array_sink_ready <= 1'b1;
            end
            if (cycle_commit && array_pc == 8'd1) begin
                check(vector_a_valid,
                      "PC1 commits with a valid scratchpad vector");
                for (lane = 0; lane < 32; lane = lane + 1) begin
                    lane_value = $signed(vector_a_data[lane*27 +: 27]);
                    check(lane_value == lane - 16,
                          "D18 preload is sign-extended bit-exactly to PE lanes");
                end
            end
        end
    end

    integer address;
    integer plane;
    reg [31:0] status_word;
    reg [1:0] response;
    initial begin
        cfg_beats[0] = 128'd0;
        cfg_beats[1] = 128'd0;
        cfg_beats[2] = 128'd0;
        cfg_beats[3] = 128'd0;
        cfg_beats[0][31:0] =
            {2'd0, 2'd2, 4'd0, `RECON_RUN_CONFIGURATION_REVISION,
             `RECON_RUN_CONFIGURATION_MAGIC};
        cfg_beats[0][63:32] = 32'h0208_0080;
        cfg_beats[0][95:64] = 32'h0410_0014;
        cfg_beats[0][127:96] = 32'h0000_0000;
        cfg_beats[1][31:0] = 32'h0000_0100;
        cfg_beats[1][63:32] = 32'h0000_0000;
        cfg_beats[1][95:64] = 32'h89ab_cdef;
        cfg_beats[1][127:96] = 32'h0123_4567;
        cfg_beats[2][31:0] = VECTOR_ADDRESS[31:0];
        cfg_beats[2][63:32] = VECTOR_ADDRESS[63:32];
        cfg_beats[2][95:64] = 32'h0000_2000;
        cfg_beats[2][127:96] = 32'h0000_0000;
        cfg_beats[3][31:0] = 32'h0000_3000;
        cfg_beats[3][63:32] = 32'h0000_0000;
        cfg_beats[3][95:64] = 32'h55aa_1234;
        cfg_beats[3][127:96] = 32'h3f82_0000;

        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        write_memory_configuration();
        for (address = 0; address < M3_ARRAY_CONTEXT_COUNT;
                address = address + 1) begin
            for (plane = 0; plane < 8; plane = plane + 1)
                write_image_word(plane[3:0], address[7:0],
                    m3_generated_image_word(plane[3:0], address[7:0]));
            write_image_word(4'd9, address[7:0],
                m3_generated_image_word(4'd9, address[7:0]));
            write_image_word(4'd8, address[7:0],
                m3_generated_image_word(4'd8, address[7:0]));
        end
        for (address = 0; address < M3_PHASE_INSTRUCTION_COUNT;
                address = address + 1)
            write_image_word(4'd10, address[7:0],
                m3_generated_image_word(4'd10, address[7:0]));
        finalize_image();

        preload_vector();
        check(resident_bitmap[0],
              "successful preload publishes configuration residency");
        check(vector_reads == 1 && cfg_reads == 0,
              "preload owns exactly one DMA transaction before run start");

        axil_write(`RECON_CSR_RUN_CONFIGURATION_LO,
                   RUN_CFG_ADDRESS[31:0], `AXI_RESP_OKAY);
        axil_write(`RECON_CSR_RUN_CONFIGURATION_HI,
                   RUN_CFG_ADDRESS[63:32], `AXI_RESP_OKAY);
        axil_write(`RECON_CSR_EVENT_CONTROL, 32'h0000_0100,
                   `AXI_RESP_OKAY);
        axil_write(`RECON_CSR_COMMAND, 32'd1, `AXI_RESP_OKAY);

        timeout = 0;
        while (!irq && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(irq, "CSR START reaches one completion interrupt");
        axil_read(`RECON_CSR_STATUS, status_word, response);
        check(response == `AXI_RESP_OKAY,
              "CSR status read returns OKAY");
        check(!status_word[0] && status_word[5] && !status_word[6],
              "terminal CSR status is idle, complete and error-free");
        check(status_word[11:8] == `RECON_STOP_ITERATION_LIMIT,
              "phase terminal code reaches CSR status");
        check(cfg_reads == 1 && vector_reads == 1,
              "shared DMA executes one preload and one run-config fetch");
        check(pc1_stalls >= 2,
              "elastic vector context absorbs controlled sink backpressure");
        check(array_commit_count == 32'd9,
              "M3 compiler image commits the expected nine contexts");
        check(integration_errors == 0,
              "M1-M4 run has no stream or residency contract error");
        check(!m_axi_awvalid && !m_axi_wvalid,
              "M1-M4 read-only scenario emits no AXI write traffic");

        $display("M1-M4 metrics: commits=%0d stalls=%0d pc1_stalls=%0d cfg_dma=%0d vector_dma=%0d",
                 array_commit_count, array_stall_count, pc1_stalls,
                 cfg_reads, vector_reads);
        if (failures == 0)
            $display("M1-M4 INTEGRATION PASS");
        else
            $display("M1-M4 INTEGRATION FAIL: %0d checks", failures);
        $finish;
    end
endmodule

`default_nettype wire
