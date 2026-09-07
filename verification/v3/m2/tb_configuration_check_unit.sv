`timescale 1ns/1ps
`default_nettype none

module tb_configuration_check_unit;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg run_configuration_valid = 1'b0;
    wire run_configuration_ready;
    reg [511:0] run_configuration_data = 512'd0;
    reg abort_request = 1'b0;
    wire validation_active;
    wire commit_valid;
    reg commit_ready = 1'b0;
    wire [511:0] commit_data;
    wire error_valid;
    reg error_ready = 1'b0;
    wire [7:0] error_code;
    wire [4:0] cfg_error_word;
    wire [31:0] error_detail;
    integer failures = 0;

    configuration_check_unit dut (.*);

    task automatic check;
        input condition;
        input [8*112-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic load_valid_configuration;
        begin
            run_configuration_data = 512'd0;
            run_configuration_data[31:0] =
                {2'd0, 2'd2, 4'd0, `RECON_RUN_CONFIGURATION_REVISION,
                 `RECON_RUN_CONFIGURATION_MAGIC};
            run_configuration_data[63:32] = 32'h0208_0080;
            run_configuration_data[95:64] = 32'h0410_0014;
            run_configuration_data[127:96] = 32'h0000_0000;
            run_configuration_data[159:128] = 32'h0000_0100;
            run_configuration_data[191:160] = 32'h0000_0000;
            run_configuration_data[223:192] = 32'h89ab_cdef;
            run_configuration_data[255:224] = 32'h0123_4567;
            run_configuration_data[287:256] = 32'h0000_1000;
            run_configuration_data[319:288] = 32'h0000_0000;
            run_configuration_data[351:320] = 32'h0000_2000;
            run_configuration_data[383:352] = 32'h0000_0000;
            run_configuration_data[415:384] = 32'h0000_3000;
            run_configuration_data[447:416] = 32'h0000_0000;
            run_configuration_data[479:448] = 32'h55aa_1234;
            run_configuration_data[511:480] = 32'h3f82_0000;
        end
    endtask

    task automatic begin_validation;
        begin
            @(negedge clk);
            run_configuration_valid = 1'b1;
        end
    endtask

    task automatic finish_input;
        begin
            @(negedge clk);
            run_configuration_valid = 1'b0;
            commit_ready = 1'b0;
            error_ready = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic expect_commit;
        integer timeout;
        reg [511:0] held_data;
        begin
            begin_validation();
            timeout = 0;
            while (!commit_valid && timeout < 40) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(commit_valid && !error_valid, "legal configuration reaches commit only");
            held_data = commit_data;
            repeat (3) begin
                @(posedge clk);
                check(commit_valid && commit_data == held_data,
                      "commit payload stable under backpressure");
            end
            @(negedge clk);
            run_configuration_valid = 1'b0;
            commit_ready = 1'b1;
            @(posedge clk);
            finish_input();
        end
    endtask

    task automatic expect_error;
        input [7:0] expected_code;
        input [4:0] expected_word;
        integer timeout;
        reg [31:0] held_detail;
        begin
            begin_validation();
            timeout = 0;
            while (!error_valid && timeout < 40) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!error_valid || commit_valid || error_code != expected_code ||
                cfg_error_word != expected_word)
                $display("VALIDATOR DEBUG expected=%02x/%0d actual=%02x/%0d error=%0d commit=%0d state=%0d index=%0d word0=%08x word15=%08x",
                         expected_code, expected_word, error_code,
                         cfg_error_word, error_valid, commit_valid,
                         dut.state, dut.check_index,
                         run_configuration_data[31:0],
                         run_configuration_data[511:480]);
            check(error_valid && !commit_valid, "invalid configuration reaches error only");
            check(error_code == expected_code &&
                  cfg_error_word == expected_word,
                  "deterministic validation error code and word");
            held_detail = error_detail;
            repeat (3) begin
                @(posedge clk);
                check(error_valid && error_code == expected_code &&
                      cfg_error_word == expected_word &&
                      error_detail == held_detail,
                      "validation error stable under backpressure");
            end
            @(negedge clk);
            run_configuration_valid = 1'b0;
            error_ready = 1'b1;
            @(posedge clk);
            finish_input();
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk);

        load_valid_configuration();
        expect_commit();

        load_valid_configuration();
        run_configuration_data[15:0] = 16'h0000;
        expect_error(8'h01, 5'd0);

        load_valid_configuration();
        run_configuration_data[23:16] = 8'd2;
        expect_error(8'h02, 5'd0);

        load_valid_configuration();
        run_configuration_data[31:30] = 2'd1;
        expect_error(8'h03, 5'd0);

        load_valid_configuration();
        run_configuration_data[191:160] = 32'h4000_0000;
        expect_error(8'h04, 5'd5);

        load_valid_configuration();
        run_configuration_data[63:32] = (32 << 20) | (64 << 9) | 32;
        run_configuration_data[511:480] = (31 << 23) | (1 << 17);
        expect_commit();

        load_valid_configuration();
        run_configuration_data[27:24] = 4'hf;
        expect_error(8'h03, 5'd0);

        load_valid_configuration();
        run_configuration_data[95:94] = 2'd3;
        expect_error(8'h20, 5'd2);

        load_valid_configuration();
        run_configuration_data[93] = 1'b1;
        expect_commit();

        load_valid_configuration();
        run_configuration_data[96] = 1'b1;
        expect_error(8'h04, 5'd3);

        load_valid_configuration();
        run_configuration_data[259:256] = 4'h4;
        expect_error(8'h30, 5'd8);

        load_valid_configuration();
        run_configuration_data[323:320] = 4'h4;
        expect_error(8'h30, 5'd10);

        load_valid_configuration();
        run_configuration_data[387:384] = 4'h4;
        expect_error(8'h30, 5'd12);

        load_valid_configuration();
        run_configuration_data[497:480] = 18'd0;
        expect_error(8'h40, 5'd15);

        load_valid_configuration();
        run_configuration_data[502:498] = 5'd12;
        expect_error(8'h43, 5'd15);

        load_valid_configuration();
        run_configuration_data[509:503] = 7'd63;
        expect_error(8'h41, 5'd15);

        load_valid_configuration();
        run_configuration_data[510] = 1'b1;
        expect_error(8'h42, 5'd15);

        load_valid_configuration();
        run_configuration_data[511:480] =
            (1 << 30) | (127 << 23) | (5'b11100 << 18) | 18'd185364;
        expect_commit();

        if (failures == 0)
            $display("PASS: exhaustive run-configuration validator testbench");
        else
            $display("FAIL: run-configuration validator testbench (%0d failures)",
                     failures);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "validator testbench timeout");
    end
endmodule

`default_nettype wire
