`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"
`include "reconstruction_control_defs.vh"
`include "result_format_defs.vh"

module tb_p17_candidate_result_writer;
    localparam integer SUPPORT_MAX = 2;
    localparam integer DATA_W = 31;
    localparam integer INDEX_W = 10;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    integer body_beats;
    reg saw_dense_body;
    reg saw_sparse_body;

    reg start_valid = 1'b0;
    wire start_ready;
    reg abort_request = 1'b0;
    reg [1:0] result_mode = 2'd0;
    reg [10:0] signal_length = 11'd0;
    reg [6:0] support_count = 7'd0;
    reg [SUPPORT_MAX*INDEX_W-1:0] support_indices = 0;
    reg [SUPPORT_MAX*DATA_W-1:0] support_coefficients = 0;
    reg [63:0] dense_result_address = 64'h1000;
    reg [63:0] sparse_result_address = 64'h2000;
    reg [31:0] user_tag = 32'h1234_5678;
    reg [3:0] stop_reason = `RECON_STOP_ITERATION_LIMIT;
    wire busy;

    wire dma_req_valid;
    wire dma_req_ready = 1'b1;
    wire dma_req_write;
    wire [63:0] dma_req_addr;
    wire [15:0] dma_req_bytes;
    wire [7:0] dma_req_tag;
    wire dma_wr_valid;
    wire dma_wr_ready = 1'b1;
    wire [127:0] dma_wr_data;
    wire [15:0] dma_wr_keep;
    wire dma_wr_last;
    reg dma_done_valid = 1'b0;
    wire dma_done_ready;
    reg [7:0] dma_done_tag = 8'd0;
    reg dma_done_error = 1'b0;
    reg [1:0] dma_done_resp = 2'd0;
    reg [8:0] dma_done_beat = 9'd0;
    reg [7:0] request_tag = 8'd0;

    wire completion_valid;
    wire completion_ready = 1'b1;
    wire [3:0] completion_stop_reason;
    wire error_valid;
    wire error_ready = 1'b1;
    wire [7:0] error_code;
    wire [1:0] error_response;
    wire [8:0] error_beat;
    wire [7:0] error_tag;

    reconstruction_result_writer #(
        .DATA_W(DATA_W), .SUPPORT_MAX(SUPPORT_MAX), .INDEX_W(INDEX_W)
    ) u_dut (
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
        .completion_valid(completion_valid), .completion_ready(completion_ready),
        .completion_stop_reason(completion_stop_reason),
        .error_valid(error_valid), .error_ready(error_ready),
        .error_code(error_code), .error_response(error_response),
        .error_beat(error_beat), .error_tag(error_tag)
    );

    task automatic check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s at %0t", message, $time);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            dma_done_valid <= 1'b0;
            request_tag <= 8'd0;
        end else begin
            if (dma_req_valid)
                request_tag <= dma_req_tag;
            if (dma_done_valid)
                dma_done_valid <= 1'b0;
            if (dma_wr_valid && dma_wr_last) begin
                dma_done_valid <= 1'b1;
                dma_done_tag <= request_tag;
            end
        end
    end

    task automatic launch;
        begin
            while (!start_ready) @(posedge clk);
            @(negedge clk);
            start_valid = 1'b1;
            @(posedge clk);
            #1;
            start_valid = 1'b0;
        end
    endtask

    task automatic wait_done;
        begin
            timeout = 0;
            while (!completion_valid && !error_valid && timeout < 200) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 200, "candidate result writer timeout");
            check(completion_valid && !error_valid, "candidate result completion");
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && dma_wr_valid && dma_wr_ready) begin
            if (result_mode == `RECON_RESULT_MODE_DENSE &&
                dma_req_addr == dense_result_address + 64'd16) begin
                body_beats = body_beats + 1;
                if (body_beats == 1) begin
                    saw_dense_body = 1'b1;
                    check(dma_wr_data[95:64] == 32'hc000_0000,
                          "D22 dense sign extension");
                end
            end
            if (result_mode == `RECON_RESULT_MODE_SPARSE &&
                dma_req_addr == sparse_result_address + 64'd16) begin
                saw_sparse_body = 1'b1;
                check(dma_wr_data[31:0] == 32'h3fff_ffff &&
                      dma_wr_data[63:32] == 32'd7,
                      "S31 sparse coefficient and index");
            end
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        result_mode = `RECON_RESULT_MODE_DENSE;
        signal_length = 11'd5;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd2;
        support_coefficients[0 +: DATA_W] = 31'h4000_0000;
        body_beats = 0;
        saw_dense_body = 1'b0;
        launch();
        wait_done();
        check(saw_dense_body, "D22 dense body observed");

        @(negedge clk);
        result_mode = `RECON_RESULT_MODE_SPARSE;
        signal_length = 11'd8;
        support_count = 7'd1;
        support_indices[0 +: INDEX_W] = 10'd7;
        support_coefficients[0 +: DATA_W] = 31'h3fff_ffff;
        body_beats = 0;
        saw_sparse_body = 1'b0;
        launch();
        wait_done();
        check(saw_sparse_body, "S31 sparse body observed");

        if (failures == 0)
            $display("P17 CANDIDATE RESULT PASS");
        else
            $display("FAIL: P17 candidate result failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
