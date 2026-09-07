`timescale 1ns/1ps
`default_nettype none

`include "reconstruction_control_defs.vh"

module tb_m2_dma_and_run_configuration;
    localparam integer ADDRESS_W = 64;
    localparam integer DATA_W = 128;
    localparam integer TAG_W = 8;
    localparam [63:0] CONFIGURATION_ADDRESS = 64'h0000_0000_0000_1000;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer cycle_count = 0;

    reg start_valid = 1'b0;
    wire start_ready;
    reg [63:0] start_address = CONFIGURATION_ADDRESS;
    reg terminal_release = 1'b0;
    wire fetch_active;
    wire validation_active;
    wire control_busy;
    wire configuration_error_valid;
    reg configuration_error_ready = 1'b1;
    wire [3:0] configuration_error_class;
    wire [7:0] configuration_error_code;
    wire [4:0] cfg_error_word;
    wire [31:0] configuration_error_detail;
    wire active_valid;
    wire [1:0] result_mode;
    wire [1:0] matrix_kind;
    wire [8:0] measurement_count;
    wire [4:0] measurement_row_blocks;
    wire [10:0] signal_length;
    wire [6:0] sparsity;
    wire [15:0] outer_limit;
    wire [7:0] refine_limit;
    wire [4:0] normal_residual_shift;
    wire [1:0] refinement_profile;
    wire [61:0] residual_limit;
    wire [63:0] phi_seed;
    wire [63:0] measurement_address;
    wire [63:0] dense_result_address;
    wire [63:0] sparse_result_address;
    wire [31:0] user_tag;
    wire [17:0] phi_scale_mantissa_uq17;
    wire [4:0] phi_scale_exponent;
    wire [7:0] phi_column_weight;
    wire require_unit_norm;

    wire configuration_dma_request_valid;
    wire configuration_dma_request_ready;
    wire configuration_dma_request_write;
    wire [63:0] configuration_dma_request_address;
    wire [15:0] configuration_dma_request_bytes;
    wire [7:0] configuration_dma_request_tag;
    wire configuration_dma_read_valid;
    wire configuration_dma_read_ready;
    wire [127:0] configuration_dma_read_data;
    wire configuration_dma_read_last;
    wire [1:0] configuration_dma_read_response;
    wire [7:0] configuration_dma_read_tag;
    wire configuration_dma_completion_valid;
    wire configuration_dma_completion_ready;
    wire [7:0] configuration_dma_completion_tag;
    wire configuration_dma_completion_error;
    wire [1:0] configuration_dma_completion_response;
    wire [8:0] configuration_dma_completion_beat;

    reg client1_request_valid = 1'b0;
    reg client1_request_write = 1'b0;
    reg [63:0] client1_request_address = 64'd0;
    reg [15:0] client1_request_bytes = 16'd0;
    reg [7:0] client1_request_tag = 8'd0;
    reg client2_request_valid = 1'b0;
    reg client2_request_write = 1'b0;
    reg [63:0] client2_request_address = 64'd0;
    reg [15:0] client2_request_bytes = 16'd0;
    reg [7:0] client2_request_tag = 8'd0;
    reg client1_write_valid = 1'b0;
    wire client1_write_ready;
    reg [127:0] client1_write_data = 128'd0;
    reg [15:0] client1_write_keep = 16'd0;
    reg client1_write_last = 1'b0;
    reg client2_read_ready = 1'b0;

    wire [3:0] client_req_valid;
    wire [3:0] client_req_ready;
    wire [3:0] client_req_write;
    wire [255:0] client_req_addr;
    wire [63:0] client_req_bytes;
    wire [31:0] client_req_tag;
    wire [3:0] client_wr_valid;
    wire [3:0] client_wr_ready;
    wire [511:0] client_wr_data;
    wire [63:0] client_wr_keep;
    wire [3:0] client_wr_last;
    wire [3:0] client_rd_valid;
    wire [3:0] client_rd_ready;
    wire [511:0] client_rd_data;
    wire [3:0] client_rd_last;
    wire [7:0] client_rd_resp;
    wire [31:0] client_rd_tag;
    wire [3:0] client_done_valid;
    wire [3:0] client_done_ready;
    wire [31:0] client_done_tag;
    wire [3:0] client_done_error;
    wire [7:0] client_done_resp;
    wire [35:0] client_done_beat;
    wire dma_transaction_active;

    assign client_req_valid = {1'b0, client2_request_valid,
                                   client1_request_valid,
                                   configuration_dma_request_valid};
    assign client_req_write = {1'b0, client2_request_write,
                                   client1_request_write,
                                   configuration_dma_request_write};
    assign client_req_addr[63:0] = configuration_dma_request_address;
    assign client_req_addr[127:64] = client1_request_address;
    assign client_req_addr[191:128] = client2_request_address;
    assign client_req_addr[255:192] = 64'd0;
    assign client_req_bytes[15:0] = configuration_dma_request_bytes;
    assign client_req_bytes[31:16] = client1_request_bytes;
    assign client_req_bytes[47:32] = client2_request_bytes;
    assign client_req_bytes[63:48] = 16'd0;
    assign client_req_tag[7:0] = configuration_dma_request_tag;
    assign client_req_tag[15:8] = client1_request_tag;
    assign client_req_tag[23:16] = client2_request_tag;
    assign client_req_tag[31:24] = 8'd0;
    assign client_wr_valid = {2'b00, client1_write_valid, 1'b0};
    assign client_wr_data[127:0] = 128'd0;
    assign client_wr_data[255:128] = client1_write_data;
    assign client_wr_data[511:256] = 256'd0;
    assign client_wr_keep[15:0] = 16'd0;
    assign client_wr_keep[31:16] = client1_write_keep;
    assign client_wr_keep[63:32] = 32'd0;
    assign client_wr_last = {2'b00, client1_write_last, 1'b0};
    assign client_rd_ready = {1'b0, client2_read_ready, 1'b0,
                                configuration_dma_read_ready};
    assign client_done_ready = {1'b0, 1'b1, 1'b1,
                                      configuration_dma_completion_ready};
    assign configuration_dma_request_ready = client_req_ready[0];
    assign client1_write_ready = client_wr_ready[1];
    assign configuration_dma_read_valid = client_rd_valid[0];
    assign configuration_dma_read_data = client_rd_data[127:0];
    assign configuration_dma_read_last = client_rd_last[0];
    assign configuration_dma_read_response = client_rd_resp[1:0];
    assign configuration_dma_read_tag = client_rd_tag[7:0];
    assign configuration_dma_completion_valid = client_done_valid[0];
    assign configuration_dma_completion_tag = client_done_tag[7:0];
    assign configuration_dma_completion_error = client_done_error[0];
    assign configuration_dma_completion_response = client_done_resp[1:0];
    assign configuration_dma_completion_beat = client_done_beat[8:0];

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
    wire m_axi_awready;
    wire [127:0] m_axi_wdata;
    wire [15:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_wready;
    reg [1:0] m_axi_bresp = 2'b00;
    reg m_axi_bvalid = 1'b0;
    wire m_axi_bready;

    reg [127:0] configuration_beats [0:3];
    reg read_active = 1'b0;
    reg [63:0] read_address = 64'd0;
    reg [7:0] read_length = 8'd0;
    reg [7:0] read_index = 8'd0;
    reg inject_read_error = 1'b0;
    reg [7:0] injected_read_error_beat = 8'd0;
    reg write_active = 1'b0;
    reg [63:0] write_address = 64'd0;
    reg [7:0] write_length = 8'd0;
    reg [7:0] wr_idx = 8'd0;
    reg inject_write_error = 1'b0;
    integer observed_ar_count = 0;
    integer observed_aw_count = 0;
    reg [63:0] first_observed_ar = 64'd0;
    reg [7:0] first_observed_arlen = 8'd0;
    reg [63:0] first_observed_aw = 64'd0;
    integer configuration_error_count = 0;
    reg [3:0] captured_configuration_error_class = 4'd0;
    reg [7:0] captured_configuration_error_code = 8'd0;
    reg [4:0] captured_cfg_error_word = 5'd0;

    assign m_axi_arready = !read_active && !m_axi_rvalid && cycle_count[0];
    assign m_axi_awready = !write_active && !m_axi_bvalid && cycle_count[1];
    assign m_axi_wready = write_active && cycle_count[0];

    function automatic [127:0] read_payload;
        input [63:0] address;
        input [7:0] index;
        begin
            if (address == CONFIGURATION_ADDRESS) begin
                case (index)
                    8'd0: read_payload = configuration_beats[0];
                    8'd1: read_payload = configuration_beats[1];
                    8'd2: read_payload = configuration_beats[2];
                    default: read_payload = configuration_beats[3];
                endcase
            end else begin
                read_payload = {address[31:0], index, 24'h5a5a5a,
                                address[31:0], index, 24'ha5a5a5};
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            read_active <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_rdata <= 128'd0;
            m_axi_rresp <= 2'b00;
            m_axi_rlast <= 1'b0;
            write_active <= 1'b0;
            m_axi_bvalid <= 1'b0;
            m_axi_bresp <= 2'b00;
            observed_ar_count <= 0;
            observed_aw_count <= 0;
            configuration_error_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (configuration_error_valid && configuration_error_ready) begin
                configuration_error_count <= configuration_error_count + 1;
                captured_configuration_error_class <= configuration_error_class;
                captured_configuration_error_code <= configuration_error_code;
                captured_cfg_error_word <= cfg_error_word;
            end

            if (m_axi_arvalid && m_axi_arready) begin
                read_active <= 1'b1;
                read_address <= m_axi_araddr;
                read_length <= m_axi_arlen;
                read_index <= 8'd0;
                observed_ar_count <= observed_ar_count + 1;
                if (observed_ar_count == 0)
                    first_observed_ar <= m_axi_araddr;
                if (observed_ar_count == 0)
                    first_observed_arlen <= m_axi_arlen;
            end
            if (read_active && !m_axi_rvalid && cycle_count[1]) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata <= read_payload(read_address, read_index);
                m_axi_rresp <= (inject_read_error &&
                                (read_index == injected_read_error_beat)) ?
                               2'b10 : 2'b00;
                m_axi_rlast <= (read_index == read_length);
            end else if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast) begin
                    m_axi_rvalid <= 1'b0;
                    read_active <= 1'b0;
                end else begin
                    read_index <= read_index + 8'd1;
                    if (cycle_count[2]) begin
                        m_axi_rvalid <= 1'b0;
                    end else begin
                        m_axi_rdata <= read_payload(read_address,
                                                   read_index + 8'd1);
                        m_axi_rresp <= (inject_read_error &&
                            ((read_index + 8'd1) == injected_read_error_beat)) ?
                            2'b10 : 2'b00;
                        m_axi_rlast <= ((read_index + 8'd1) == read_length);
                    end
                end
            end

            if (m_axi_awvalid && m_axi_awready) begin
                write_active <= 1'b1;
                write_address <= m_axi_awaddr;
                write_length <= m_axi_awlen;
                wr_idx <= 8'd0;
                observed_aw_count <= observed_aw_count + 1;
                if (observed_aw_count == 0)
                    first_observed_aw <= m_axi_awaddr;
            end
            if (m_axi_wvalid && m_axi_wready) begin
                if (m_axi_wlast != (wr_idx == write_length)) begin
                    $display("FAIL: AXI WLAST mismatch at beat %0d", wr_idx);
                    failures = failures + 1;
                end
                if (m_axi_wstrb != 16'hffff) begin
                    $display("FAIL: AXI write strobe mismatch");
                    failures = failures + 1;
                end
                if (wr_idx == write_length) begin
                    write_active <= 1'b0;
                    m_axi_bvalid <= 1'b1;
                    m_axi_bresp <= inject_write_error ? 2'b10 : 2'b00;
                end else begin
                    wr_idx <= wr_idx + 8'd1;
                end
            end
            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;
        end
    end

    reconstruction_configuration_unit u_reconstruction_configuration_unit (
        .clk(clk), .rst_n(rst_n), .start_valid(start_valid),
        .start_ready(start_ready), .start_address(start_address),
        .abort_request(1'b0),
        .terminal_release(terminal_release), .fetch_active(fetch_active),
        .validation_active(validation_active), .control_busy(control_busy),
        .dma_req_valid(configuration_dma_request_valid),
        .dma_req_ready(configuration_dma_request_ready),
        .dma_req_write(configuration_dma_request_write),
        .dma_req_addr(configuration_dma_request_address),
        .dma_req_bytes(configuration_dma_request_bytes),
        .dma_req_tag(configuration_dma_request_tag),
        .dma_rd_valid(configuration_dma_read_valid),
        .dma_rd_ready(configuration_dma_read_ready),
        .dma_rd_data(configuration_dma_read_data),
        .dma_rd_last(configuration_dma_read_last),
        .dma_rd_resp(configuration_dma_read_response),
        .dma_rd_tag(configuration_dma_read_tag),
        .dma_done_valid(configuration_dma_completion_valid),
        .dma_done_ready(configuration_dma_completion_ready),
        .dma_done_tag(configuration_dma_completion_tag),
        .dma_done_error(configuration_dma_completion_error),
        .dma_done_resp(configuration_dma_completion_response),
        .dma_completion_beat(configuration_dma_completion_beat),
        .error_valid(configuration_error_valid),
        .error_ready(configuration_error_ready),
        .error_class(configuration_error_class),
        .error_code(configuration_error_code),
        .cfg_error_word(cfg_error_word),
        .error_detail(configuration_error_detail),
        .active_valid(active_valid),
        .result_mode(result_mode), .matrix_kind(matrix_kind),
        .measurement_count(measurement_count),
        .measurement_row_blocks(measurement_row_blocks),
        .signal_length(signal_length),
        .sparsity(sparsity), .outer_limit(outer_limit),
        .refine_limit(refine_limit),
        .normal_residual_shift(normal_residual_shift),
        .refinement_profile(refinement_profile),
        .residual_limit(residual_limit),
        .phi_seed(phi_seed), .measurement_address(measurement_address),
        .dense_result_address(dense_result_address),
        .sparse_result_address(sparse_result_address), .user_tag(user_tag),
        .phi_scale_mantissa_uq17(phi_scale_mantissa_uq17),
        .phi_scale_exponent(phi_scale_exponent),
        .phi_column_weight(phi_column_weight),
        .require_unit_norm(require_unit_norm)
    );

    memory_dma_engine u_memory_dma_engine (
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
        .dma_active(dma_transaction_active),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

    reg packer_input_valid = 1'b0;
    wire packer_input_ready;
    reg [127:0] packer_input_data = 128'd0;
    reg [15:0] packer_input_keep = 16'd0;
    reg packer_input_last = 1'b0;
    reg [2:0] packer_element_format = 3'd0;
    wire packer_output_valid;
    reg packer_output_ready = 1'b0;
    wire [127:0] packer_output_data;
    wire [3:0] packer_output_element_valid;
    wire packer_output_last;
    wire packer_output_error;
    wire [1:0] packer_output_error_lane;

    dma_element_normalizer u_dma_element_normalizer (
        .clk(clk), .rst_n(rst_n), .input_valid(packer_input_valid),
        .input_ready(packer_input_ready), .input_data(packer_input_data),
        .input_keep(packer_input_keep), .input_last(packer_input_last),
        .element_format(packer_element_format),
        .output_valid(packer_output_valid),
        .output_ready(packer_output_ready), .output_data(packer_output_data),
        .output_element_valid(packer_output_element_valid),
        .output_last(packer_output_last), .output_error(packer_output_error),
        .output_error_lane(packer_output_error_lane)
    );

    task automatic check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic load_valid_configuration;
        begin
            configuration_beats[0] = 128'd0;
            configuration_beats[1] = 128'd0;
            configuration_beats[2] = 128'd0;
            configuration_beats[3] = 128'd0;
            configuration_beats[0][31:0] =
                {2'd0, 2'd2, 4'd0, `RECON_RUN_CONFIGURATION_REVISION,
                 `RECON_RUN_CONFIGURATION_MAGIC};
            configuration_beats[0][63:32] = 32'h0208_0080;
            configuration_beats[0][95:64] = 32'h0410_0014;
            configuration_beats[0][127:96] = 32'h0000_0000;
            configuration_beats[1][31:0] = 32'h0000_0100;
            configuration_beats[1][63:32] = 32'h0000_0000;
            configuration_beats[1][95:64] = 32'h89ab_cdef;
            configuration_beats[1][127:96] = 32'h0123_4567;
            configuration_beats[2][31:0] = 32'h0000_1000;
            configuration_beats[2][63:32] = 32'h0000_0000;
            configuration_beats[2][95:64] = 32'h0000_2000;
            configuration_beats[2][127:96] = 32'h0000_0000;
            configuration_beats[3][31:0] = 32'h0000_3000;
            configuration_beats[3][63:32] = 32'h0000_0000;
            configuration_beats[3][95:64] = 32'h55aa_1234;
            configuration_beats[3][127:96] = 32'h3f82_0000;
        end
    endtask

    task automatic launch_configuration;
        begin
            while (!start_ready) @(posedge clk);
            @(negedge clk);
            start_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start_valid = 1'b0;
        end
    endtask

    task automatic wait_for_active;
        integer timeout;
        begin
            timeout = 0;
            while (!active_valid && timeout < 300) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(active_valid, "valid run configuration committed");
        end
    endtask

    task automatic wait_for_error_count;
        input integer target;
        integer timeout;
        begin
            timeout = 0;
            while ((configuration_error_count < target) && timeout < 300) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(configuration_error_count >= target,
                  "run configuration terminal error observed");
        end
    endtask

    initial begin
        load_valid_configuration();
        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // Packer: valid D18 lanes, then a held sign-extension error on lane 2.
        @(negedge clk);
        packer_input_data = {32'hffff_ffff, 32'h0000_0001,
                             32'hffff_ffff, 32'h0000_0001};
        packer_input_keep = 16'hffff;
        packer_input_last = 1'b1;
        packer_element_format = 3'd0;
        packer_input_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        packer_input_valid = 1'b0;
        repeat (3) begin
            @(posedge clk);
            check(packer_output_valid && !packer_output_error,
                  "D18 packer output held clean under backpressure");
        end
        @(negedge clk); packer_output_ready = 1'b1;
        @(posedge clk); @(negedge clk); packer_output_ready = 1'b0;

        @(negedge clk);
        packer_input_data = {32'h0000_0000, 32'h0004_0000,
                             32'hffff_ffff, 32'h0000_0001};
        packer_input_keep = 16'hffff;
        packer_input_valid = 1'b1;
        @(posedge clk);
        @(negedge clk); packer_input_valid = 1'b0;
        @(posedge clk);
        check(packer_output_valid && packer_output_error &&
              (packer_output_error_lane == 2'd2),
              "D18 sign-extension error identifies first invalid lane");
        @(negedge clk); packer_output_ready = 1'b1;
        @(posedge clk); @(negedge clk); packer_output_ready = 1'b0;

        // Valid end-to-end fetch: one ARLEN=3 request, sixteen validation cycles,
        // then atomic active views.
        observed_ar_count = 0;
        inject_read_error = 1'b0;
        launch_configuration();
        wait_for_active();
        check(observed_ar_count == 1 && first_observed_ar == CONFIGURATION_ADDRESS,
              "run configuration uses one aligned AXI read burst");
        check(measurement_count == 9'd128 && signal_length == 11'd1024 &&
              sparsity == 7'd32, "active M/N/K views");
        check(measurement_row_blocks == 5'd4,
              "active measurement row-block view");
        check(result_mode == 2'd2 && phi_column_weight == 8'd128 &&
              measurement_address == 64'h1000 &&
              dense_result_address == 64'h2000 &&
              sparse_result_address == 64'h3000 &&
              user_tag == 32'h55aa_1234,
              "active DMA/Phi views decode exactly");
        @(negedge clk); terminal_release = 1'b1;
        @(posedge clk); @(negedge clk); terminal_release = 1'b0;
        @(posedge clk); check(!active_valid, "terminal release clears ownership");

        // Invalid dimensions must produce one deterministic validator error and
        // must not update active state.
        load_valid_configuration();
        configuration_beats[0][63:32] = 32'h0208_0000;
        launch_configuration();
        wait_for_error_count(1);
        check(captured_configuration_error_class ==
              `RECON_ERROR_CLASS_RUN_CONFIGURATION &&
              captured_configuration_error_code == 8'h10 &&
              captured_cfg_error_word == 5'd1,
              "dimension validation error class, code and word");
        check(!active_valid, "invalid run configuration cannot partial commit");

        // AXI RRESP fault on beat 2 terminates fetch and identifies word 8.
        load_valid_configuration();
        inject_read_error = 1'b1;
        injected_read_error_beat = 8'd2;
        launch_configuration();
        wait_for_error_count(2);
        check(captured_configuration_error_class ==
              `RECON_ERROR_CLASS_DMA_READ &&
              captured_configuration_error_code == 8'h01 &&
              captured_cfg_error_word == 5'd8,
              "AXI read error class preserves beat-to-word attribution");
        check(!active_valid, "AXI-failed configuration cannot commit");
        inject_read_error = 1'b0;

        // Arbiter priority: client 1 terminal write wins over client 2 preload
        // read, then client 2 proceeds after the completion token is accepted.
        while (dma_transaction_active) @(posedge clk);
        observed_ar_count = 0;
        observed_aw_count = 0;
        client1_request_write = 1'b1;
        client1_request_address = 64'h4000;
        client1_request_bytes = 16'd32;
        client1_request_tag = 8'h21;
        client2_request_write = 1'b0;
        client2_request_address = 64'h5000;
        client2_request_bytes = 16'd32;
        client2_request_tag = 8'h32;
        @(negedge clk);
        client1_request_valid = 1'b1;
        client2_request_valid = 1'b1;
        while (!client_req_ready[1]) @(posedge clk);
        check(!client_req_ready[2],
              "fixed priority blocks preload while terminal request wins");
        @(negedge clk); client1_request_valid = 1'b0;

        client1_write_keep = 16'hffff;
        client1_write_data = 128'h1111;
        client1_write_last = 1'b0;
        client1_write_valid = 1'b1;
        while (!client1_write_ready) @(posedge clk);
        @(negedge clk);
        client1_write_data = 128'h2222;
        client1_write_last = 1'b1;
        while (!client1_write_ready) @(posedge clk);
        @(negedge clk); client1_write_valid = 1'b0;
        while (!client_done_valid[1]) @(posedge clk);
        check(!client_done_error[1] &&
              client_done_tag[15:8] == 8'h21,
              "two-beat write completion is clean and tagged");

        while (!client_req_ready[2]) @(posedge clk);
        @(negedge clk); client2_request_valid = 1'b0;
        repeat (4) @(posedge clk);
        check(m_axi_rvalid, "client 2 read data held while client backpressures");
        client2_read_ready = 1'b1;
        while (!client_done_valid[2]) @(posedge clk);
        check(!client_done_error[2] &&
              client_done_tag[23:16] == 8'h32,
              "preload read completes after terminal owner release");
        @(negedge clk); client2_read_ready = 1'b0;
        check(observed_aw_count == 1 && first_observed_aw == 64'h4000 &&
              observed_ar_count == 1 && first_observed_ar == 64'h5000,
              "arbiter preserves request order and addresses");

        // Dense N=1024 output occupies exactly 4096 bytes. This boundary must
        // retain the ninth beat-count bit and emit ARLEN=255.
        while (dma_transaction_active) @(posedge clk);
        observed_ar_count = 0;
        client2_request_address = 64'h7000;
        client2_request_bytes = 16'd4096;
        client2_request_tag = 8'h34;
        client2_read_ready = 1'b1;
        @(negedge clk); client2_request_valid = 1'b1;
        while (!client_req_ready[2]) @(posedge clk);
        @(negedge clk); client2_request_valid = 1'b0;
        while (!client_done_valid[2]) @(posedge clk);
        check(!client_done_error[2] &&
              client_done_beat[26:18] == 9'd255 &&
              observed_ar_count == 1 && first_observed_arlen == 8'hff,
              "4096-byte read preserves 256-beat boundary");
        @(negedge clk); client2_read_ready = 1'b0;

        // A request larger than one AXI burst terminates locally and must not
        // issue an external address transaction.
        while (dma_transaction_active) @(posedge clk);
        observed_ar_count = 0;
        client2_request_address = 64'h8000;
        client2_request_bytes = 16'd4112;
        client2_request_tag = 8'h35;
        @(negedge clk); client2_request_valid = 1'b1;
        while (!client_req_ready[2]) @(posedge clk);
        @(negedge clk); client2_request_valid = 1'b0;
        while (!client_done_valid[2]) @(posedge clk);
        check(client_done_error[2] && observed_ar_count == 0,
              "oversized read fails locally without AXI traffic");

        // BRESP error is terminal and attributed to the selected write client.
        while (dma_transaction_active) @(posedge clk);
        inject_write_error = 1'b1;
        client1_request_address = 64'h6000;
        client1_request_bytes = 16'd16;
        client1_request_tag = 8'h23;
        @(negedge clk); client1_request_valid = 1'b1;
        while (!client_req_ready[1]) @(posedge clk);
        @(negedge clk); client1_request_valid = 1'b0;
        client1_write_data = 128'h3333;
        client1_write_keep = 16'hffff;
        client1_write_last = 1'b1;
        client1_write_valid = 1'b1;
        while (!client1_write_ready) @(posedge clk);
        @(negedge clk); client1_write_valid = 1'b0;
        while (!client_done_valid[1]) @(posedge clk);
        check(client_done_error[1] &&
              client_done_resp[3:2] == 2'b10,
              "AXI write response error reaches owning client");
        inject_write_error = 1'b0;

        repeat (5) @(posedge clk);
        if (failures == 0)
            $display("PASS: complete M2 DMA and run-configuration testbench");
        else
            $display("FAIL: M2 DMA and run-configuration testbench (%0d failures)",
                     failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "M2 testbench timeout");
    end
endmodule

`default_nettype wire
