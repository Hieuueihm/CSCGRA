`timescale 1ns/1ps
module tb_pe_stream_top1_service;
    localparam COLS = 8;
    localparam DATA_W = 24;
    localparam IDX_W = 10;
    localparam MAX_SUPPORT = 32;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg stream_valid = 1'b0;
    reg stream_done = 1'b0;
    reg [IDX_W-1:0] stream_base_idx = 0;
    reg [COLS-1:0] stream_lane_valid = 0;
    reg [COLS*DATA_W-1:0] stream_data = 0;
    reg exclude_support = 1'b0;
    reg [5:0] support_depth = 0;
    reg [MAX_SUPPORT*IDX_W-1:0] support_bus = 0;
    wire candidate_valid;
    wire [IDX_W-1:0] candidate_idx;
    wire [DATA_W-1:0] candidate_value;
    wire busy;
    wire done;
    integer fails = 0;
    integer passes = 0;

    pe_stream_top1_service #(
        .COLS(COLS), .DATA_W(DATA_W), .IDX_W(IDX_W), .MAX_SUPPORT(MAX_SUPPORT)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .stream_valid(stream_valid), .stream_done(stream_done),
        .stream_base_idx(stream_base_idx), .stream_lane_valid(stream_lane_valid), .stream_data(stream_data),
        .exclude_support(exclude_support), .support_depth(support_depth), .support_bus(support_bus),
        .candidate_valid(candidate_valid), .candidate_idx(candidate_idx), .candidate_value(candidate_value),
        .busy(busy), .done(done)
    );

    always #5 clk = ~clk;

    task set_lane;
        input integer lane;
        input signed [DATA_W-1:0] value;
        begin
            stream_data[lane*DATA_W +: DATA_W] = value[DATA_W-1:0];
        end
    endtask

    task pulse_start;
        begin
            @(posedge clk); start <= 1'b1;
            @(posedge clk); start <= 1'b0;
        end
    endtask

    task send_block;
        input [IDX_W-1:0] base;
        input [COLS-1:0] valid;
        begin
            @(negedge clk);
            stream_base_idx = base;
            stream_lane_valid = valid;
            stream_valid = 1'b1;
            @(negedge clk);
            stream_valid = 1'b0;
            stream_lane_valid = 0;
        end
    endtask

    task finish_stream;
        begin
            @(posedge clk); stream_done <= 1'b1;
            @(posedge clk); stream_done <= 1'b0;
            wait(done === 1'b1);
            @(posedge clk);
        end
    endtask

    task expect_result;
        input [IDX_W-1:0] exp_idx;
        input signed [DATA_W-1:0] exp_value;
        begin
            if (candidate_valid && candidate_idx == exp_idx && candidate_value == exp_value[DATA_W-1:0]) begin
                passes = passes + 1;
            end else begin
                fails = fails + 1;
                $display("FAIL expected idx=%0d value=%0d got valid=%0d idx=%0d value=%0d", exp_idx, exp_value, candidate_valid, candidate_idx, $signed(candidate_value));
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        stream_data = 0;
        pulse_start();
        set_lane(0, 24'sd3); set_lane(1, -24'sd9); set_lane(2, 24'sd8); set_lane(3, 24'sd1);
        set_lane(4, -24'sd2); set_lane(5, 24'sd7); set_lane(6, 24'sd0); set_lane(7, -24'sd4);
        send_block(10'd0, 8'hff);
        finish_stream();
        expect_result(10'd1, -24'sd9);

        stream_data = 0;
        pulse_start();
        set_lane(0, 24'sd6); set_lane(1, -24'sd6); set_lane(2, 24'sd5); set_lane(3, -24'sd1);
        send_block(10'd20, 8'h0f);
        finish_stream();
        expect_result(10'd20, 24'sd6);

        stream_data = 0;
        support_bus = 0;
        support_depth = 6'd1;
        support_bus[0 +: IDX_W] = 10'd31;
        exclude_support = 1'b1;
        pulse_start();
        set_lane(0, 24'sd1); set_lane(1, -24'sd20); set_lane(2, 24'sd19); set_lane(3, 24'sd0);
        send_block(10'd30, 8'h0f);
        finish_stream();
        expect_result(10'd32, 24'sd19);
        exclude_support = 1'b0;
        support_depth = 0;

        stream_data = 0;
        pulse_start();
        set_lane(0, 24'sd2); set_lane(1, 24'sd3); set_lane(2, -24'sd7); set_lane(3, 24'sd4);
        send_block(10'd40, 8'h0f);
        stream_data = 0;
        set_lane(0, 24'sd8); set_lane(1, -24'sd6); set_lane(2, 24'sd1); set_lane(3, 24'sd0);
        send_block(10'd48, 8'h0f);
        finish_stream();
        expect_result(10'd48, 24'sd8);

        $display("tb_pe_stream_top1_service: %0d PASS, %0d FAIL", passes, fails);
        if (fails != 0) $fatal(1);
        $finish;
    end
endmodule

