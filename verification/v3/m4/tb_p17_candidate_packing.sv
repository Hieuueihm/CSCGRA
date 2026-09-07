`timescale 1ns/1ps
`default_nettype none

module tb_p17_candidate_packing;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;

    reg scratch_d22_valid = 1'b0;
    reg [215:0] scratch_d22_in = 216'd0;
    wire scratch_d22_out_valid;
    wire [65:0] scratch_d22_out;
    wire scratch_d22_pad_error;
    wire [71:0] scratch_d22_word;
    wire scratch_d22_word_valid;
    wire scratch_d22_range_error;

    candidate_scratchpad_word_codec #(
        .ELEMENT_W(22), .ELEMENTS_PER_WORD(3), .INPUT_W(72)
    ) u_d22 (
        .unpack_valid(1'b1), .unpack_word(scratch_d22_word),
        .unpack_elements(scratch_d22_out),
        .unpack_padding_error(scratch_d22_pad_error),
        .pack_valid(scratch_d22_valid), .pack_elements(scratch_d22_in),
        .packed_word_valid(scratch_d22_word_valid),
        .packed_word(scratch_d22_word),
        .pack_range_error(scratch_d22_range_error)
    );

    reg [143:0] scratch_s31_in = 144'd0;
    reg scratch_s31_valid = 1'b0;
    wire [61:0] scratch_s31_out;
    wire [71:0] scratch_s31_word;
    wire scratch_s31_word_valid, scratch_s31_range_error, scratch_s31_pad_error;
    candidate_scratchpad_word_codec #(
        .ELEMENT_W(31), .ELEMENTS_PER_WORD(2), .INPUT_W(72)
    ) u_s31 (
        .unpack_valid(1'b1), .unpack_word(scratch_s31_word),
        .unpack_elements(scratch_s31_out),
        .unpack_padding_error(scratch_s31_pad_error),
        .pack_valid(scratch_s31_valid), .pack_elements(scratch_s31_in),
        .packed_word_valid(scratch_s31_word_valid),
        .packed_word(scratch_s31_word),
        .pack_range_error(scratch_s31_range_error)
    );

    reg [71:0] scratch_acc_in = 72'd0;
    reg scratch_acc_valid = 1'b0;
    wire [69:0] scratch_acc_out;
    wire [71:0] scratch_acc_word;
    wire scratch_acc_word_valid, scratch_acc_range_error, scratch_acc_pad_error;
    candidate_scratchpad_word_codec #(
        .ELEMENT_W(70), .ELEMENTS_PER_WORD(1), .INPUT_W(72)
    ) u_acc70 (
        .unpack_valid(1'b1), .unpack_word(scratch_acc_word),
        .unpack_elements(scratch_acc_out),
        .unpack_padding_error(scratch_acc_pad_error),
        .pack_valid(scratch_acc_valid), .pack_elements(scratch_acc_in),
        .packed_word_valid(scratch_acc_word_valid),
        .packed_word(scratch_acc_word),
        .pack_range_error(scratch_acc_range_error)
    );

    reg d22_input_valid = 1'b0;
    wire d22_input_ready;
    reg [127:0] d22_input_data = 128'd0;
    reg [15:0] d22_input_keep = 16'd0;
    reg d22_input_last = 1'b0;
    wire d22_output_valid;
    reg d22_output_ready = 1'b0;
    wire [127:0] d22_output_data;
    wire [3:0] d22_output_element_valid;
    wire d22_output_last, d22_output_error;
    wire [1:0] d22_output_error_lane;
    candidate_dma_element_normalizer #(.ELEMENT_W(22)) u_dma_d22 (
        .clk(clk), .rst_n(rst_n), .input_valid(d22_input_valid),
        .input_ready(d22_input_ready), .input_data(d22_input_data),
        .input_keep(d22_input_keep), .input_last(d22_input_last),
        .output_valid(d22_output_valid), .output_ready(d22_output_ready),
        .output_data(d22_output_data),
        .output_element_valid(d22_output_element_valid),
        .output_last(d22_output_last), .output_error(d22_output_error),
        .output_error_lane(d22_output_error_lane)
    );

    reg s31_input_valid = 1'b0;
    wire s31_input_ready;
    reg [127:0] s31_input_data = 128'd0;
    reg [15:0] s31_input_keep = 16'd0;
    reg s31_input_last = 1'b0;
    wire s31_output_valid;
    reg s31_output_ready = 1'b0;
    wire [127:0] s31_output_data;
    wire [3:0] s31_output_element_valid;
    wire s31_output_last, s31_output_error;
    wire [1:0] s31_output_error_lane;
    candidate_dma_element_normalizer #(.ELEMENT_W(31)) u_dma_s31 (
        .clk(clk), .rst_n(rst_n), .input_valid(s31_input_valid),
        .input_ready(s31_input_ready), .input_data(s31_input_data),
        .input_keep(s31_input_keep), .input_last(s31_input_last),
        .output_valid(s31_output_valid), .output_ready(s31_output_ready),
        .output_data(s31_output_data),
        .output_element_valid(s31_output_element_valid),
        .output_last(s31_output_last), .output_error(s31_output_error),
        .output_error_lane(s31_output_error_lane)
    );

    reg threshold_pack_valid = 1'b0;
    reg [69:0] threshold_in = 70'd0;
    wire [127:0] threshold_beat;
    wire threshold_beat_valid;
    wire [69:0] threshold_out;
    wire threshold_clean_valid, threshold_padding_error;
    candidate_acc70_threshold_codec u_threshold (
        .pack_valid(threshold_pack_valid), .pack_threshold(threshold_in),
        .packed_beat(threshold_beat), .packed_valid(threshold_beat_valid),
        .unpack_valid(1'b1), .unpack_beat(threshold_beat),
        .unpack_threshold(threshold_out),
        .unpack_valid_clean(threshold_clean_valid),
        .unpack_padding_error(threshold_padding_error)
    );

    task automatic check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s at %0t", message, $time);
            end
        end
    endtask

    initial begin
        #20;
        rst_n = 1'b1;

        scratch_d22_in[0 +: 72] = {{50{1'b1}}, 22'h20_0000};
        scratch_d22_in[72 +: 72] = {{50{1'b1}}, 22'h3f_ffff};
        scratch_d22_in[144 +: 72] = 72'd1;
        scratch_d22_valid = 1'b1;
        #1;
        check(scratch_d22_word_valid && !scratch_d22_range_error,
              "D22 boundary pack");
        check(scratch_d22_word[71:66] == 6'd0, "D22 zero padding");
        check(scratch_d22_out[21:0] == 22'h20_0000 &&
              scratch_d22_out[43:22] == 22'h3f_ffff &&
              scratch_d22_out[65:44] == 22'd1, "D22 round trip");
        scratch_d22_in[72 +: 72] = 72'h0000_0000_0040_0000;
        #1;
        check(!scratch_d22_word_valid && scratch_d22_range_error,
              "D22 overflow rejection");
        scratch_d22_valid = 1'b0;

        scratch_s31_in[0 +: 72] = {{41{1'b1}}, 31'h4000_0000};
        scratch_s31_in[72 +: 72] = {{41{1'b0}}, 31'h3fff_ffff};
        scratch_s31_valid = 1'b1;
        #1;
        check(scratch_s31_word_valid && !scratch_s31_range_error,
              "S31 boundary pack");
        check(scratch_s31_word[71:62] == 10'd0, "S31 zero padding");
        check(scratch_s31_out[30:0] == 31'h4000_0000 &&
              scratch_s31_out[61:31] == 31'h3fff_ffff, "S31 round trip");
        scratch_s31_in[72 +: 72] = {{41{1'b0}}, 31'h4000_0000};
        #1;
        check(!scratch_s31_word_valid && scratch_s31_range_error,
              "S31 overflow rejection");
        scratch_s31_valid = 1'b0;

        scratch_acc_in = {{2{1'b1}}, 70'h20_0000_0000_0000_0000};
        scratch_acc_valid = 1'b1;
        #1;
        check(scratch_acc_word_valid && !scratch_acc_range_error,
              "ACC70 boundary pack");
        check(scratch_acc_word[71:70] == 2'd0, "ACC70 zero padding");
        check(scratch_acc_out == 70'h20_0000_0000_0000_0000,
              "ACC70 round trip");
        scratch_acc_valid = 1'b0;

        threshold_in = {70{1'b1}};
        threshold_pack_valid = 1'b1;
        #1;
        check(threshold_beat_valid && threshold_clean_valid &&
              threshold_out == threshold_in && !threshold_padding_error,
              "ACC70 threshold transport");
        threshold_pack_valid = 1'b0;

        @(negedge clk);
        d22_input_data = 128'd0;
        d22_input_data[31:0] = 32'hffff_ffff;
        d22_input_data[63:32] = 32'd0;
        d22_input_data[95:64] = 32'd1;
        d22_input_keep = 16'h0fff;
        d22_input_last = 1'b1;
        d22_input_valid = 1'b1;
        d22_output_ready = 1'b0;
        @(posedge clk);
        #1;
        d22_input_valid = 1'b0;
        check(d22_output_valid && !d22_output_error &&
              d22_output_element_valid == 4'b0111 && d22_output_last,
              "D22 DMA valid lanes");
        check(d22_output_data[31:0] == 32'hffff_ffff &&
              d22_output_data[95:64] == 32'd1, "D22 DMA payload");
        @(posedge clk);
        #1;
        check(d22_output_valid && d22_output_data[31:0] == 32'hffff_ffff,
              "D22 DMA backpressure hold");
        d22_output_ready = 1'b1;
        @(posedge clk);
        #1;
        check(!d22_output_valid, "D22 DMA release");

        @(negedge clk);
        d22_input_data[31:0] = 32'h0020_0000;
        d22_input_keep = 16'h000f;
        d22_input_last = 1'b0;
        d22_input_valid = 1'b1;
        @(posedge clk);
        #1;
        d22_input_valid = 1'b0;
        check(d22_output_error && d22_output_error_lane == 2'd0,
              "D22 DMA overflow error");
        d22_output_ready = 1'b1;
        @(posedge clk);

        @(negedge clk);
        s31_input_data[31:0] = 32'hc000_0000;
        s31_input_data[63:32] = 32'h3fff_ffff;
        s31_input_keep = 16'h00ff;
        s31_input_last = 1'b1;
        s31_input_valid = 1'b1;
        s31_output_ready = 1'b1;
        @(posedge clk);
        #1;
        s31_input_valid = 1'b0;
        check(s31_output_valid && !s31_output_error &&
              s31_output_element_valid == 4'b0011,
              "S31 DMA valid lanes");
        check(s31_output_data[31:0] == 32'hc000_0000 &&
              s31_output_data[63:32] == 32'h3fff_ffff,
              "S31 DMA payload");
        @(posedge clk);

        if (failures == 0)
            $display("P17 CANDIDATE PACKING PASS");
        else
            $display("FAIL: P17 candidate packing failures=%0d", failures);
        $finish;
    end
endmodule

`default_nettype wire
