`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"
`include "reconstruction_control_defs.vh"
`include "result_format_defs.vh"

module tb_reconstruction_result_writer;
    localparam integer SUPPORT_MAX = 4;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer INDEX_W = 10;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer cycle_count = 0;
    integer failures = 0;

    reg start_valid = 1'b0;
    wire start_ready;
    reg abort_request = 1'b0;
    reg [1:0] result_mode = 2'd0;
    reg [10:0] signal_length = 11'd0;
    reg [6:0] support_count = 7'd0;
    reg [SUPPORT_MAX*INDEX_W-1:0] support_indices = 0;
    reg [SUPPORT_MAX*DATA_W-1:0] support_coefficients = 0;
    reg [63:0] dense_result_address = 64'd0;
    reg [63:0] sparse_result_address = 64'd0;
    reg [31:0] user_tag = 32'd0;
    reg [3:0] stop_reason = 4'd0;
    wire busy;

    wire dma_req_valid;
    wire dma_req_ready = (cycle_count[1:0] != 2'b00);
    wire dma_req_write;
    wire [63:0] dma_req_addr;
    wire [15:0] dma_req_bytes;
    wire [7:0] dma_req_tag;
    wire dma_wr_valid;
    wire dma_wr_ready = (cycle_count[2:0] != 3'b011);
    wire [127:0] dma_wr_data;
    wire [15:0] dma_wr_keep;
    wire dma_wr_last;
    reg dma_done_valid = 1'b0;
    wire dma_done_ready;
    reg [7:0] dma_done_tag = 8'd0;
    reg dma_done_error = 1'b0;
    reg [1:0] dma_done_resp = 2'd0;
    reg [8:0] dma_done_beat = 9'd0;

    wire completion_valid;
    reg completion_ready = 1'b1;
    wire [3:0] completion_stop_reason;
    wire error_valid;
    reg error_ready = 1'b1;
    wire [7:0] error_code;
    wire [1:0] error_response;
    wire [8:0] error_beat;
    wire [7:0] error_tag;

    reg [63:0] request_addresses [0:15];
    reg [15:0] request_bytes [0:15];
    reg [7:0] request_tags [0:15];
    reg [127:0] captured_beats [0:63];
    reg captured_last [0:63];
    integer request_count = 0;
    integer beat_count = 0;
    integer active_request = -1;
    integer active_expected_beats = 0;
    integer active_seen_beats = 0;
    integer completion_delay = 0;
    integer pending_request = -1;
    integer inject_error_request = -1;
    reg completion_seen = 1'b0;
    reg [3:0] observed_completion_stop = 4'd0;
    reg error_seen = 1'b0;
    reg [7:0] observed_error_code = 8'd0;

    reconstruction_result_writer #(.SUPPORT_MAX(SUPPORT_MAX)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .start_valid(start_valid), .start_ready(start_ready),
        .abort_request(abort_request), .result_mode(result_mode),
        .signal_length(signal_length), .support_count(support_count),
        .support_indices(support_indices),
        .support_coefficients(support_coefficients),
        .dense_result_address(dense_result_address),
        .sparse_result_address(sparse_result_address),
        .user_tag(user_tag), .stop_reason(stop_reason), .busy(busy),
        .dma_req_valid(dma_req_valid), .dma_req_ready(dma_req_ready),
        .dma_req_write(dma_req_write), .dma_req_addr(dma_req_addr),
        .dma_req_bytes(dma_req_bytes), .dma_req_tag(dma_req_tag),
        .dma_wr_valid(dma_wr_valid), .dma_wr_ready(dma_wr_ready),
        .dma_wr_data(dma_wr_data), .dma_wr_keep(dma_wr_keep),
        .dma_wr_last(dma_wr_last), .dma_done_valid(dma_done_valid),
        .dma_done_ready(dma_done_ready), .dma_done_tag(dma_done_tag),
        .dma_done_error(dma_done_error), .dma_done_resp(dma_done_resp),
        .dma_done_beat(dma_done_beat),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_stop_reason(completion_stop_reason),
        .error_valid(error_valid), .error_ready(error_ready),
        .error_code(error_code), .error_response(error_response),
        .error_beat(error_beat), .error_tag(error_tag)
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
            start_valid = 1'b0;
            abort_request = 1'b0;
            completion_seen = 1'b0;
            error_seen = 1'b0;
            request_count = 0;
            beat_count = 0;
            active_request = -1;
            active_expected_beats = 0;
            active_seen_beats = 0;
            completion_delay = 0;
            pending_request = -1;
            inject_error_request = -1;
            dma_done_valid = 1'b0;
            support_indices = 0;
            support_coefficients = 0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic launch;
        begin
            while (!start_ready) @(posedge clk);
            start_valid = 1'b1;
            @(posedge clk);
            start_valid = 1'b0;
        end
    endtask

    task automatic wait_terminal;
        integer timeout;
        begin
            timeout = 0;
            while (!completion_seen && !error_seen && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 2000, "terminal timeout");
            repeat (3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!rst_n) begin
            dma_done_valid <= 1'b0;
            completion_delay <= 0;
        end else begin
            if (dma_req_valid && dma_req_ready) begin
                request_addresses[request_count] <= dma_req_addr;
                request_bytes[request_count] <= dma_req_bytes;
                request_tags[request_count] <= dma_req_tag;
                active_request <= request_count;
                active_expected_beats <= dma_req_bytes >> 4;
                active_seen_beats <= 0;
                request_count <= request_count + 1;
                check(dma_req_write, "result request must be write");
                check(dma_req_addr[3:0] == 0, "request alignment");
                check(({1'b0, dma_req_addr[11:0]} + dma_req_bytes) <= 4096,
                      "request crosses 4KiB");
            end
            if (dma_wr_valid && dma_wr_ready) begin
                captured_beats[beat_count] <= dma_wr_data;
                captured_last[beat_count] <= dma_wr_last;
                beat_count <= beat_count + 1;
                active_seen_beats <= active_seen_beats + 1;
                check(dma_wr_keep == 16'hffff, "write keep must be full beat");
                check(dma_wr_last ==
                      (active_seen_beats == active_expected_beats - 1),
                      "write last mismatch");
                if (dma_wr_last) begin
                    pending_request <= active_request;
                    completion_delay <= 2;
                    active_request <= -1;
                end
            end
            if (completion_delay > 0) begin
                completion_delay <= completion_delay - 1;
                if (completion_delay == 1) begin
                    dma_done_valid <= 1'b1;
                    dma_done_tag <= request_tags[pending_request];
                    dma_done_error <= pending_request == inject_error_request;
                    dma_done_resp <= (pending_request == inject_error_request) ?
                        2'b10 : 2'b00;
                    dma_done_beat <= request_bytes[pending_request] / 16 - 1;
                end
            end
            if (dma_done_valid && dma_done_ready)
                dma_done_valid <= 1'b0;
            if (completion_valid) begin
                completion_seen <= 1'b1;
                observed_completion_stop <= completion_stop_reason;
            end
            if (error_valid) begin
                error_seen <= 1'b1;
                observed_error_code <= error_code;
            end
        end
    end

    initial begin
        reset_case();
        result_mode = `RECON_RESULT_MODE_DENSE;
        signal_length = 11'd7;
        support_count = 7'd2;
        support_indices[0 +: INDEX_W] = 10'd1;
        support_indices[INDEX_W +: INDEX_W] = 10'd6;
        support_coefficients[0 +: DATA_W] = 27'sd5;
        support_coefficients[DATA_W +: DATA_W] = -27'sd3;
        dense_result_address = 64'h1000;
        user_tag = 32'h1122_3344;
        stop_reason = `RECON_STOP_ITERATION_LIMIT;
        launch();
        wait_terminal();
        check(completion_seen && !error_seen, "dense completion");
        check(request_count == 2, "dense request count");
        check(request_addresses[0] == 64'h1010 && request_bytes[0] == 32,
              "dense body request");
        check(request_addresses[1] == 64'h1000 && request_bytes[1] == 16,
              "dense header request");
        check(captured_beats[0] ==
              {32'd0, 32'd0, 32'd5, 32'd0}, "dense beat zero");
        check(captured_beats[1] ==
              {32'd0, 32'hffff_fffd, 32'd0, 32'd0}, "dense beat one");
        check(captured_beats[2] == expected_header(
              `RECON_RESULT_MODE_DENSE, 11'd7, 7'd2, 32'h1122_3344,
              `RECON_STOP_ITERATION_LIMIT), "dense header");

        reset_case();
        result_mode = `RECON_RESULT_MODE_SPARSE;
        signal_length = 11'd16;
        support_count = 7'd3;
        support_indices[0 +: INDEX_W] = 10'd2;
        support_indices[INDEX_W +: INDEX_W] = 10'd5;
        support_indices[2*INDEX_W +: INDEX_W] = 10'd9;
        support_coefficients[0 +: DATA_W] = 27'sd7;
        support_coefficients[DATA_W +: DATA_W] = -27'sd4;
        support_coefficients[2*DATA_W +: DATA_W] = 27'sd12;
        sparse_result_address = 64'h2000;
        user_tag = 32'ha5a5_55aa;
        stop_reason = `RECON_STOP_RESIDUAL_LIMIT;
        launch();
        wait_terminal();
        check(completion_seen && !error_seen, "sparse completion");
        check(request_count == 2, "sparse request count");
        check(request_addresses[0] == 64'h2010 && request_bytes[0] == 32,
              "sparse body request");
        check(captured_beats[0] ==
              {32'd5, 32'hffff_fffc, 32'd2, 32'd7}, "sparse beat zero");
        check(captured_beats[1] ==
              {64'd0, 32'd9, 32'd12}, "sparse beat one");
        check(captured_beats[2] == expected_header(
              `RECON_RESULT_MODE_SPARSE, 11'd16, 7'd3, 32'ha5a5_55aa,
              `RECON_STOP_RESIDUAL_LIMIT), "sparse header");

        reset_case();
        result_mode = `RECON_RESULT_MODE_BOTH;
        signal_length = 11'd4;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd3;
        support_coefficients[0 +: DATA_W] = 27'sd9;
        dense_result_address = 64'h3000;
        sparse_result_address = 64'h4000;
        user_tag = 32'h0102_0304;
        stop_reason = `RECON_STOP_SUPPORT_STABLE;
        launch();
        wait_terminal();
        check(request_count == 3, "both request count");
        check(request_addresses[0] == 64'h3010, "both dense body");
        check(request_addresses[1] == 64'h4010, "both sparse body");
        check(request_addresses[2] == 64'h4000, "both primary header");
        check(captured_beats[2] == expected_header(
              `RECON_RESULT_MODE_BOTH, 11'd4, 7'd1, 32'h0102_0304,
              `RECON_STOP_SUPPORT_STABLE), "both header");

        reset_case();
        result_mode = `RECON_RESULT_MODE_DENSE;
        signal_length = 11'd8;
        support_count = 7'd0;
        dense_result_address = 64'h0fe0;
        user_tag = 32'h55;
        stop_reason = `RECON_STOP_ITERATION_LIMIT;
        launch();
        wait_terminal();
        check(request_count == 3, "4KiB split request count");
        check(request_addresses[0] == 64'h0ff0 && request_bytes[0] == 16,
              "4KiB first chunk");
        check(request_addresses[1] == 64'h1000 && request_bytes[1] == 16,
              "4KiB second chunk");
        check(request_addresses[2] == 64'h0fe0, "4KiB header");

        reset_case();
        result_mode = `RECON_RESULT_MODE_BOTH;
        signal_length = 11'd4;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd0;
        support_coefficients[0 +: DATA_W] = 27'sd1;
        dense_result_address = 64'h5000;
        sparse_result_address = 64'h6000;
        inject_error_request = 1;
        launch();
        wait_terminal();
        check(error_seen && !completion_seen, "DMA error terminal");
        check(observed_error_code == 8'h10, "DMA error code");
        check(request_count == 2, "DMA error blocks header");

        reset_case();
        result_mode = `RECON_RESULT_MODE_DENSE;
        signal_length = 11'd8;
        support_count = 7'd0;
        dense_result_address = 64'h7000;
        launch();
        while (!dma_wr_valid) @(posedge clk);
        abort_request = 1'b1;
        @(posedge clk);
        abort_request = 1'b0;
        wait_terminal();
        check(completion_seen && !error_seen, "abort completion");
        check(observed_completion_stop == `RECON_STOP_ABORTED,
              "abort stop reason");
        check(request_count == 1, "abort blocks success header");

        if (failures == 0)
            $display("M12 RESULT WRITER PASS");
        else
            $display("FAIL: M12 RESULT WRITER failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
