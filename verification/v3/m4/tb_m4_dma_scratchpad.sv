`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"

module tb_m4_dma_scratchpad;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer accepted_read_beats = 0;
    reg [31:0] random_lfsr = 32'h6d41_2f93;

    function automatic [31:0] lfsr_next(input [31:0] value);
        lfsr_next = {value[30:0],
                     value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    task automatic check(input condition, input [8*96-1:0] message);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s at %0t", message, $time);
            end
        end
    endtask

    function automatic [63:0] vector_configuration;
        input [15:0] base_word;
        input [15:0] count;
        input [2:0] format;
        input [2:0] packing;
        reg [63:0] word;
        begin
            word = 64'd0;
            word[15:0] = base_word;
            word[31:16] = count;
            word[43:32] = 12'd1;
            word[46:44] = 3'd0;
            word[48:47] = 2'd3;
            word[51:49] = `RECON_BANK_MODE_CYCLIC;
            word[54:52] = format;
            word[57:55] = packing;
            word[58] = 1'b1;
            word[62:61] = `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD;
            vector_configuration = word;
        end
    endfunction

    function automatic [127:0] memory_payload;
        input [63:0] address;
        input [7:0] beat;
        integer lane;
        integer signed value;
        reg [127:0] payload;
        begin
            payload = 128'd0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (address == 64'h1000)
                    value = (beat * 4 + lane) - 16;
                else if (address == 64'h2000)
                    value = 1000 + (beat * 4 + lane) * 17;
                else if (address == 64'h3000 && beat == 0 && lane == 0)
                    value = 32'h0004_0000;
                else
                    value = beat * 4 + lane;
                payload[lane*32 +: 32] = value[31:0];
            end
            memory_payload = payload;
        end
    endfunction

    function automatic [575:0] expected_d18_stripe;
        integer bank;
        integer lane;
        integer signed value;
        reg [575:0] stripe;
        begin
            stripe = 576'd0;
            for (bank = 0; bank < 8; bank = bank + 1)
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    value = bank * 4 + lane - 16;
                    stripe[bank*72 + lane*18 +: 18] = value[17:0];
                end
            expected_d18_stripe = stripe;
        end
    endfunction

    function automatic [575:0] expected_s27_stripe;
        integer bank;
        integer lane;
        integer signed value;
        reg [575:0] stripe;
        begin
            stripe = 576'd0;
            for (bank = 0; bank < 8; bank = bank + 1)
                for (lane = 0; lane < 2; lane = lane + 1) begin
                    value = 1000 + (bank * 2 + lane) * 17;
                    stripe[bank*72 + lane*27 +: 27] = value[26:0];
                end
            expected_s27_stripe = stripe;
        end
    endfunction

    reg preload_valid = 1'b0;
    wire preload_ready;
    reg [63:0] preload_src_addr = 64'd0;
    reg [5:0] preload_cfg_id = 6'd0;
    reg [63:0] preload_cfg = 64'd0;
    wire preload_done_valid;
    reg preload_done_ready = 1'b0;
    wire [5:0] preload_done_cfg_id;
    wire preload_done_error;
    wire [7:0] preload_done_code;
    wire preload_active;
    wire load_begin;
    wire [5:0] load_begin_id;
    wire load_commit;
    wire [5:0] load_commit_id;

    wire preload_dma_request_valid;
    wire preload_dma_request_ready;
    wire preload_dma_request_write;
    wire [63:0] preload_dma_request_address;
    wire [15:0] preload_dma_request_bytes;
    wire [7:0] preload_dma_request_tag;
    wire preload_dma_read_valid;
    wire preload_dma_read_ready;
    wire [127:0] preload_dma_read_data;
    wire preload_dma_read_last;
    wire [1:0] preload_dma_read_response;
    wire [7:0] preload_dma_read_tag;
    wire preload_dma_completion_valid;
    wire preload_dma_completion_ready;
    wire [7:0] preload_dma_completion_tag;
    wire preload_dma_completion_error;
    wire [1:0] preload_dma_completion_response;

    wire preload_p0_valid, preload_p0_ready, preload_p0_write;
    wire [7:0] preload_p0_mask;
    wire [71:0] preload_p0_addresses;
    wire [575:0] preload_p0_write_data;
    wire preload_p1_valid, preload_p1_ready, preload_p1_write;
    wire [7:0] preload_p1_mask;
    wire [71:0] preload_p1_addresses;
    wire [575:0] preload_p1_write_data;

    scratchpad_preload_engine u_scratchpad_preload_engine (
        .clk(clk), .rst_n(rst_n),
        .preload_valid(preload_valid), .preload_ready(preload_ready),
        .preload_src_addr(preload_src_addr),
        .preload_cfg_id(preload_cfg_id),
        .preload_cfg(preload_cfg),
        .preload_done_valid(preload_done_valid),
        .preload_done_ready(preload_done_ready),
        .preload_done_cfg_id(
            preload_done_cfg_id),
        .preload_done_error(preload_done_error),
        .preload_done_code(preload_done_code),
        .preload_active(preload_active),
        .load_begin(load_begin),
        .load_begin_id(load_begin_id),
        .load_commit(load_commit),
        .load_commit_id(load_commit_id),
        .dma_req_valid(preload_dma_request_valid),
        .dma_req_ready(preload_dma_request_ready),
        .dma_req_write(preload_dma_request_write),
        .dma_req_addr(preload_dma_request_address),
        .dma_req_bytes(preload_dma_request_bytes),
        .dma_req_tag(preload_dma_request_tag),
        .dma_rd_valid(preload_dma_read_valid),
        .dma_rd_ready(preload_dma_read_ready),
        .dma_rd_data(preload_dma_read_data),
        .dma_rd_last(preload_dma_read_last),
        .dma_rd_resp(preload_dma_read_response),
        .dma_rd_tag(preload_dma_read_tag),
        .dma_done_valid(preload_dma_completion_valid),
        .dma_done_ready(preload_dma_completion_ready),
        .dma_done_tag(preload_dma_completion_tag),
        .dma_done_error(preload_dma_completion_error),
        .dma_done_resp(preload_dma_completion_response),
        .sp0_valid(preload_p0_valid),
        .sp0_ready(preload_p0_ready),
        .sp0_write(preload_p0_write),
        .sp0_bank_mask(preload_p0_mask),
        .sp0_addr(preload_p0_addresses),
        .sp0_wr_data(preload_p0_write_data),
        .sp1_valid(preload_p1_valid),
        .sp1_ready(preload_p1_ready),
        .sp1_write(preload_p1_write),
        .sp1_bank_mask(preload_p1_mask),
        .sp1_addr(preload_p1_addresses),
        .sp1_wr_data(preload_p1_write_data),
        .sp_conflict(scratchpad_conflict)
    );

    wire [3:0] client_req_valid =
        {1'b0, preload_dma_request_valid, 2'b00};
    wire [3:0] client_req_ready;
    wire [3:0] client_req_write =
        {1'b0, preload_dma_request_write, 2'b00};
    wire [255:0] client_req_addr =
        {64'd0, preload_dma_request_address, 128'd0};
    wire [63:0] client_req_bytes =
        {16'd0, preload_dma_request_bytes, 32'd0};
    wire [31:0] client_req_tag =
        {8'd0, preload_dma_request_tag, 16'd0};
    wire [3:0] client_wr_ready;
    wire [3:0] client_rd_valid;
    wire [511:0] client_rd_data;
    wire [3:0] client_rd_last;
    wire [7:0] client_rd_resp;
    wire [31:0] client_rd_tag;
    wire [3:0] client_done_valid;
    wire [31:0] client_done_tag;
    wire [3:0] client_done_error;
    wire [7:0] client_done_resp;
    wire [35:0] client_done_beat;
    wire dma_transaction_active;

    assign preload_dma_request_ready = client_req_ready[2];
    assign preload_dma_read_valid = client_rd_valid[2];
    assign preload_dma_read_data = client_rd_data[383:256];
    assign preload_dma_read_last = client_rd_last[2];
    assign preload_dma_read_response = client_rd_resp[5:4];
    assign preload_dma_read_tag = client_rd_tag[23:16];
    assign preload_dma_completion_valid = client_done_valid[2];
    assign preload_dma_completion_tag = client_done_tag[23:16];
    assign preload_dma_completion_error = client_done_error[2];
    assign preload_dma_completion_response = client_done_resp[5:4];

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

    memory_dma_engine u_memory_dma_engine (
        .clk(clk), .rst_n(rst_n),
        .client_req_valid(client_req_valid),
        .client_req_ready(client_req_ready),
        .client_req_write(client_req_write),
        .client_req_addr(client_req_addr),
        .client_req_bytes(client_req_bytes),
        .client_req_tag(client_req_tag),
        .client_wr_valid(4'd0), .client_wr_ready(client_wr_ready),
        .client_wr_data(512'd0), .client_wr_keep(64'd0),
        .client_wr_last(4'd0), .client_rd_valid(client_rd_valid),
        .client_rd_ready({1'b0, preload_dma_read_ready, 2'b00}),
        .client_rd_data(client_rd_data), .client_rd_last(client_rd_last),
        .client_rd_resp(client_rd_resp),
        .client_rd_tag(client_rd_tag),
        .client_done_valid(client_done_valid),
        .client_done_ready(
            {1'b0, preload_dma_completion_ready, 2'b00}),
        .client_done_tag(client_done_tag),
        .client_done_error(client_done_error),
        .client_done_resp(client_done_resp),
        .client_done_beat(client_done_beat),
        .dma_active(dma_transaction_active),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(1'b1), .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(1'b1),
        .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0),
        .m_axi_bready(m_axi_bready)
    );

    reg read_active = 1'b0;
    reg [63:0] read_address = 64'd0;
    reg [7:0] read_length = 8'd0;
    reg [7:0] read_index = 8'd0;
    assign m_axi_arready = !read_active && !m_axi_rvalid && random_lfsr[0];
    always @(posedge clk) begin
        if (!rst_n) begin
            random_lfsr <= 32'h6d41_2f93;
            read_active <= 1'b0;
            m_axi_rvalid <= 1'b0;
            accepted_read_beats <= 0;
        end else begin
            random_lfsr <= lfsr_next(random_lfsr);
            if (m_axi_arvalid && m_axi_arready) begin
                read_active <= 1'b1;
                read_address <= m_axi_araddr;
                read_length <= m_axi_arlen;
                read_index <= 8'd0;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                accepted_read_beats <= accepted_read_beats + 1;
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast)
                    read_active <= 1'b0;
                else
                    read_index <= read_index + 8'd1;
            end
            if (read_active && !m_axi_rvalid && random_lfsr[2]) begin
                m_axi_rdata <= memory_payload(read_address, read_index);
                m_axi_rresp <= 2'b00;
                m_axi_rlast <= read_index == read_length;
                m_axi_rvalid <= 1'b1;
            end
        end
    end

    reg routine_start = 1'b0;
    reg req_valid = 1'b0;
    reg cycle_commit = 1'b0;
    reg stream_read_a_enable = 1'b0;
    reg [5:0] stream_configuration_id = 6'd0;
    reg [63:0] stream_configuration = 64'd0;
    wire stream_in_ready;
    wire stream_out_ready;
    wire cfg_error;
    wire access_conflict;
    wire stream_read_a_valid;
    wire [575:0] stream_read_a_data;
    wire stream_p0_valid, stream_p0_ready, stream_p0_write;
    wire [7:0] stream_p0_mask;
    wire [71:0] stream_p0_addresses;
    wire [575:0] stream_p0_write_data;
    wire stream_p0_read_valid;
    wire [7:0] stream_p0_read_mask;
    wire [575:0] stream_p0_read_data;
    wire stream_p1_valid, stream_p1_ready, stream_p1_write;
    wire [7:0] stream_p1_mask;
    wire [71:0] stream_p1_addresses;
    wire [575:0] stream_p1_write_data;
    wire stream_p1_read_valid;
    wire [7:0] stream_p1_read_mask;
    wire [575:0] stream_p1_read_data;

    vector_stream_engine u_vector_stream_engine (
        .clk(clk), .rst_n(rst_n), .cursor_restart_valid(1'b0), .cursor_restart_mask(3'b000),
        .cursor_restart_ready(), .routine_start(routine_start),
        .req_valid(req_valid),
        .cycle_commit(cycle_commit),
        .vec_a_en(stream_read_a_enable),
        .vec_b_en(1'b0), .vec_w_en(1'b0),
        .vec_a_restart(1'b0), .vec_b_restart(1'b0),
        .vec_cfg_a(stream_configuration_id),
        .vec_cfg_b(6'd0), .vec_cfg_w(6'd0),
        .cfg_a_valid(1'b1),
        .cfg_a(stream_configuration),
        .cfg_b_valid(1'b0), .cfg_b(64'd0),
        .cfg_w_valid(1'b0), .cfg_w(64'd0),
        .vec_w_data(576'd0), .stream_in_ready(stream_in_ready),
        .stream_out_ready(stream_out_ready),
        .cfg_error(cfg_error),
        .access_conflict(access_conflict),
        .vec_a_valid(stream_read_a_valid),
        .vec_a_data(stream_read_a_data), .vec_b_valid(),
        .vec_b_data(), .sp0_valid(stream_p0_valid),
        .sp0_ready(stream_p0_ready),
        .sp0_write(stream_p0_write),
        .sp0_bank_mask(stream_p0_mask),
        .sp0_addr(stream_p0_addresses),
        .sp0_wr_data(stream_p0_write_data),
        .sp0_rd_valid(stream_p0_read_valid),
        .sp0_rd_bank_mask(stream_p0_read_mask),
        .sp0_rd_data(stream_p0_read_data),
        .sp1_valid(stream_p1_valid),
        .sp1_ready(stream_p1_ready),
        .sp1_write(stream_p1_write),
        .sp1_bank_mask(stream_p1_mask),
        .sp1_addr(stream_p1_addresses),
        .sp1_wr_data(stream_p1_write_data),
        .sp1_rd_valid(stream_p1_read_valid),
        .sp1_rd_bank_mask(stream_p1_read_mask),
        .sp1_rd_data(stream_p1_read_data),
        .sp_conflict(scratchpad_conflict)
    );

    wire scratchpad_p0_valid = preload_active ? preload_p0_valid : stream_p0_valid;
    wire scratchpad_p0_ready;
    wire scratchpad_p0_write = preload_active ? preload_p0_write : stream_p0_write;
    wire [7:0] scratchpad_p0_mask = preload_active ? preload_p0_mask : stream_p0_mask;
    wire [71:0] scratchpad_p0_addresses = preload_active ?
        preload_p0_addresses : stream_p0_addresses;
    wire [575:0] scratchpad_p0_write_data = preload_active ?
        preload_p0_write_data : stream_p0_write_data;
    wire scratchpad_p1_valid = preload_active ? preload_p1_valid : stream_p1_valid;
    wire scratchpad_p1_ready;
    wire scratchpad_p1_write = preload_active ? preload_p1_write : stream_p1_write;
    wire [7:0] scratchpad_p1_mask = preload_active ? preload_p1_mask : stream_p1_mask;
    wire [71:0] scratchpad_p1_addresses = preload_active ?
        preload_p1_addresses : stream_p1_addresses;
    wire [575:0] scratchpad_p1_write_data = preload_active ?
        preload_p1_write_data : stream_p1_write_data;
    wire scratchpad_p0_read_valid, scratchpad_p1_read_valid;
    wire [7:0] scratchpad_p0_read_mask, scratchpad_p1_read_mask;
    wire [575:0] scratchpad_p0_read_data, scratchpad_p1_read_data;
    wire scratchpad_conflict;

    assign preload_p0_ready = preload_active && scratchpad_p0_ready;
    assign preload_p1_ready = preload_active && scratchpad_p1_ready;
    assign stream_p0_ready = !preload_active && scratchpad_p0_ready;
    assign stream_p1_ready = !preload_active && scratchpad_p1_ready;
    assign stream_p0_read_valid = !preload_active && scratchpad_p0_read_valid;
    assign stream_p0_read_mask = scratchpad_p0_read_mask;
    assign stream_p0_read_data = scratchpad_p0_read_data;
    assign stream_p1_read_valid = !preload_active && scratchpad_p1_read_valid;
    assign stream_p1_read_mask = scratchpad_p1_read_mask;
    assign stream_p1_read_data = scratchpad_p1_read_data;

    vector_scratchpad u_vector_scratchpad (
        .clk(clk), .rst_n(rst_n), .p0_valid(scratchpad_p0_valid),
        .p0_ready(scratchpad_p0_ready), .p0_write(scratchpad_p0_write),
        .p0_bank_mask(scratchpad_p0_mask),
        .p0_addr(scratchpad_p0_addresses),
        .p0_wr_data(scratchpad_p0_write_data),
        .p0_rd_valid(scratchpad_p0_read_valid),
        .p0_rd_bank_mask(scratchpad_p0_read_mask),
        .p0_rd_data(scratchpad_p0_read_data),
        .p1_valid(scratchpad_p1_valid),
        .p1_ready(scratchpad_p1_ready), .p1_write(scratchpad_p1_write),
        .p1_bank_mask(scratchpad_p1_mask),
        .p1_addr(scratchpad_p1_addresses),
        .p1_wr_data(scratchpad_p1_write_data),
        .p1_rd_valid(scratchpad_p1_read_valid),
        .p1_rd_bank_mask(scratchpad_p1_read_mask),
        .p1_rd_data(scratchpad_p1_read_data),
        .external_conflict(1'b0),
        .access_conflict(scratchpad_conflict)
    );

    reg clear_residency = 1'b0;
    reg invalidate_configuration = 1'b0;
    reg [5:0] invalidate_configuration_id = 6'd0;
    reg residency_context_valid = 1'b0;
    reg [35:0] residency_context = 36'd0;
    wire configs_resident;
    wire reservation_violation;
    wire missing_valid;
    wire [5:0] missing_id;
    wire [63:0] resident_bitmap_out;

    scratchpad_residency_tracker u_residency_tracker (
        .clk(clk), .rst_n(rst_n), .clear_all(clear_residency),
        .load_begin(load_begin),
        .load_begin_id(load_begin_id),
        .load_commit(load_commit),
        .load_commit_id(load_commit_id),
        .invalidate(invalidate_configuration),
        .invalidate_id(invalidate_configuration_id),
        .ctx_valid(residency_context_valid),
        .stream_ctx(residency_context),
        .configs_resident(configs_resident),
        .reservation_violation(reservation_violation),
        .missing_valid(missing_valid),
        .missing_id(missing_id),
        .resident_bitmap_out(resident_bitmap_out)
    );

    task automatic issue_preload;
        input [63:0] address;
        input [5:0] identifier;
        input [63:0] configuration;
        input expected_error;
        begin
            while (!preload_ready) @(posedge clk);
            @(negedge clk);
            preload_src_addr = address;
            preload_cfg_id = identifier;
            preload_cfg = configuration;
            preload_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            preload_valid = 1'b0;
            // Command payload is no longer owned after the handshake. Event
            // IDs must come from the preload engine's latched transaction.
            preload_cfg_id = 6'd63;
            preload_src_addr = 64'hffff_ffff_ffff_fff0;
            preload_cfg = 64'd0;
            timeout = 0;
            while (!preload_done_valid && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(preload_done_valid, "preload reaches terminal token");
            check(preload_done_cfg_id == identifier,
                  "preload completion keeps configuration id");
            check(preload_done_error == expected_error,
                  "preload completion error matches expectation");
            repeat (2) begin
                @(posedge clk);
                check(preload_done_valid,
                      "preload completion holds under backpressure");
            end
            @(negedge clk); preload_done_ready = 1'b1;
            @(posedge clk);
            @(negedge clk); preload_done_ready = 1'b0;
        end
    endtask

    task automatic read_and_check_stripe;
        input [5:0] identifier;
        input [63:0] configuration;
        input [575:0] expected;
        begin
            @(negedge clk); routine_start = 1'b1;
            @(posedge clk);
            @(negedge clk); routine_start = 1'b0;
            stream_configuration_id = identifier;
            stream_configuration = configuration;
            stream_read_a_enable = 1'b1;
            req_valid = 1'b1;
            cycle_commit = 1'b0;
            timeout = 0;
            while (!(stream_in_ready && stream_read_a_valid) &&
                    timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            #1;
            check(stream_in_ready && stream_read_a_valid,
                  "stream engine returns preloaded stripe");
            if (stream_read_a_data != expected) begin
                $display("READBACK id=%0d actual=%0144x", identifier,
                         stream_read_a_data);
                $display("READBACK id=%0d expect=%0144x", identifier,
                         expected);
            end
            check(stream_read_a_data == expected,
                  "preloaded stripe is bit exact through stream engine");
            check(!cfg_error && !access_conflict,
                  "readback has no configuration or port error");
            @(negedge clk); cycle_commit = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cycle_commit = 1'b0;
            req_valid = 1'b0;
            stream_read_a_enable = 1'b0;
        end
    endtask

    reg [63:0] d18_configuration;
    reg [63:0] s27_configuration;
    reg [63:0] bad_configuration;
    initial begin
        d18_configuration = vector_configuration(16'd10, 16'd32,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR);
        s27_configuration = vector_configuration(16'd20, 16'd16,
            `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO);
        bad_configuration = vector_configuration(16'd30, 16'd4,
            `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR);

        repeat (6) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (3) @(posedge clk);

        residency_context_valid = 1'b1;
        residency_context = 36'd0;
        residency_context[0] = 1'b1;
        residency_context[8:3] = 6'd5;
        residency_context[34] = 1'b1;
        #1;
        check(!configs_resident &&
              missing_valid &&
              missing_id == 6'd5 && !reservation_violation,
              "missing preload creates an elastic residency stall");
        residency_context[34] = 1'b0;
        #1;
        check(reservation_violation,
              "non-stalling context exposes missing-residency violation");
        residency_context[34] = 1'b1;

        fork
            begin
                issue_preload(64'h1000, 6'd5, d18_configuration, 1'b0);
            end
            begin
                wait(load_begin);
                @(posedge clk); #1;
                check(!resident_bitmap_out[5],
                      "load begin invalidates destination configuration");
                wait(preload_active);
                repeat (3) @(posedge clk);
                check(!configs_resident,
                      "consumer remains blocked while DMA is active");
            end
        join
        @(posedge clk); #1;
        check(resident_bitmap_out[5] &&
              configs_resident && !reservation_violation,
              "successful terminal commit makes D18 configuration resident");
        read_and_check_stripe(6'd5, d18_configuration,
                              expected_d18_stripe());

        residency_context[8:3] = 6'd6;
        issue_preload(64'h2000, 6'd6, s27_configuration, 1'b0);
        @(posedge clk); #1;
        check(resident_bitmap_out[6],
              "S27 configuration becomes resident");
        read_and_check_stripe(6'd6, s27_configuration,
                              expected_s27_stripe());

        residency_context[8:3] = 6'd7;
        issue_preload(64'h3000, 6'd7, bad_configuration, 1'b1);
        @(posedge clk); #1;
        check(!resident_bitmap_out[7] &&
              !configs_resident,
              "range-error preload cannot publish residency");

        bad_configuration[51:49] = `RECON_BANK_MODE_LINEAR;
        issue_preload(64'h4000, 6'd8, bad_configuration, 1'b1);
        check(preload_done_code == 8'd1,
              "unsupported layout fails before AXI request");

        check(accepted_read_beats == 13,
              "random AXI backpressure preserves all accepted read beats");
        check(!m_axi_awvalid && !m_axi_wvalid,
              "preload seam never emits AXI write traffic");
        $display("M4.1 AXI random backpressure seed=0x6d412f93 beats=%0d",
                 accepted_read_beats);
        if (failures == 0)
            $display("M4.1 DMA SCRATCHPAD PASS");
        else
            $display("FAIL: M4.1 DMA scratchpad testbench (%0d failures)",
                     failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "M4.1 testbench timeout");
    end
endmodule

`default_nettype wire
