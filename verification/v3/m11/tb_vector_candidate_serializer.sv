`timescale 1ns/1ps
`default_nettype none

module tb_vector_candidate_serializer;
    localparam integer DATA_W = 27;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg routine_start = 0;
    reg source_active = 0;
    reg [10:0] element_count = 11'd18;
    reg stripe_valid = 0;
    reg [15:0] stripe_lane_valid = 16'hffff;
    reg [16*DATA_W-1:0] stripe_data = 0;
    wire stripe_release;
    wire candidate_valid;
    reg candidate_ready = 0;
    wire signed [DATA_W-1:0] candidate_score;
    wire [9:0] candidate_index;
    wire candidate_fault;
    wire stream_done;
    integer index;
    integer observed = 0;

    vector_candidate_serializer dut (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .source_active(source_active), .element_count(element_count),
        .stripe_valid(stripe_valid), .stripe_lane_valid(stripe_lane_valid),
        .stripe_data(stripe_data), .stripe_release(stripe_release),
        .candidate_valid(candidate_valid), .candidate_ready(candidate_ready),
        .candidate_score(candidate_score), .candidate_index(candidate_index),
        .candidate_fault(candidate_fault), .stream_done(stream_done)
    );

    task load_stripe(input integer base);
        begin
            for (index = 0; index < 16; index = index + 1)
                stripe_data[index*DATA_W +: DATA_W] = base + index;
            stripe_valid = 1;
            @(posedge clk);
            stripe_valid = 0;
        end
    endtask

    always @(posedge clk) begin
        if (candidate_valid && candidate_ready) begin
            if (candidate_index !== observed[9:0]) $fatal(1, "index mismatch");
            if (candidate_score !== observed + 27'sd100) $fatal(1, "score mismatch");
            if (candidate_fault) $fatal(1, "unexpected fault");
            observed <= observed + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        source_active = 1;
        load_stripe(100);
        candidate_ready = 1;
        repeat (5) @(posedge clk);
        candidate_ready = 0;
        repeat (3) @(posedge clk);
        candidate_ready = 1;
        wait (candidate_index == 10'd15);
        candidate_ready = 0;
        #1;
        if (!stripe_release) $fatal(1, "final-lane release look-ahead missing");
        repeat (2) @(posedge clk);
        if (!candidate_valid || candidate_index != 10'd15)
            $fatal(1, "final lane changed under backpressure");
        candidate_ready = 1;
        wait (stripe_release && candidate_ready);
        @(posedge clk);
        load_stripe(116);
        wait (stream_done);
        @(posedge clk);
        #1;
        if (observed != 18) $fatal(1, "candidate count mismatch");
        $display("PASS vector candidate serializer");
        $finish;
    end
endmodule

`default_nettype wire
