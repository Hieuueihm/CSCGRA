`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

// Vivado/XSim testbench for compact CSR revision 3.  Revision fields are
// compared against the generated architecture authority, never a stale literal.

module tb_axilite_control;
    localparam integer AXIL_AW = 12;

    reg aclk = 1'b0;
    always #5 aclk = ~aclk;
    reg aresetn = 1'b0;

    reg [AXIL_AW-1:0] s_axi_awaddr = 0;
    reg s_axi_awvalid = 0;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata = 0;
    reg [3:0] s_axi_wstrb = 0;
    reg s_axi_wvalid = 0;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready = 0;
    reg [AXIL_AW-1:0] s_axi_araddr = 0;
    reg s_axi_arvalid = 0;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready = 0;

    wire run_start;
    wire abort_request;
    wire irq;
    wire [63:0] run_cfg_addr;

    reg engine_busy = 0;
    reg cfg_fetch_active = 0;
    reg array_active = 0;
    reg writeback_active = 0;
    reg abort_pending = 0;
    reg done_pulse = 0;
    reg [3:0] stop_reason = 0;
    reg [6:0] support_count = 0;
    reg error_pulse = 0;
    reg [3:0] error_class = 0;
    reg [7:0] error_code = 0;
    reg [7:0] error_phase = 0;
    reg [4:0] cfg_error_word = 0;
    reg [31:0] error_detail = 0;
    reg [7:0] phase_progress = 8'h34;
    reg [15:0] outer_progress = 16'h1234;
    reg [7:0] solver_progress = 8'h56;
    reg [63:0] total_cycles = 64'h0123_4567_89ab_cdef;

    integer failures = 0;
    integer start_count = 0;
    integer abort_count = 0;
    reg [31:0] read_value;
    reg [1:0] read_response;
    reg [1:0] write_response;

    m1_control_top #(.AXIL_AW(AXIL_AW)) dut (.*);

    always @(posedge aclk) begin
        if (run_start)
            start_count <= start_count + 1;
        if (abort_request)
            abort_count <= abort_count + 1;
    end

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task send_aw;
        input [AXIL_AW-1:0] address;
        begin
            @(negedge aclk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            do @(posedge aclk); while (!s_axi_awready);
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task send_w;
        input [31:0] data;
        input [3:0] strobe;
        begin
            @(negedge aclk);
            s_axi_wdata = data;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;
            do @(posedge aclk); while (!s_axi_wready);
            @(negedge aclk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task accept_b;
        output [1:0] response;
        begin
            while (!s_axi_bvalid) @(posedge aclk);
            response = s_axi_bresp;
            @(negedge aclk);
            s_axi_bready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_write;
        input [AXIL_AW-1:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input [1:0] channel_order;
        output [1:0] response;
        begin
            case (channel_order)
                2'd1: begin
                    send_aw(address);
                    repeat (2) @(posedge aclk);
                    send_w(data, strobe);
                end
                2'd2: begin
                    send_w(data, strobe);
                    repeat (2) @(posedge aclk);
                    send_aw(address);
                end
                default: fork
                    send_aw(address);
                    send_w(data, strobe);
                join
            endcase
            accept_b(response);
        end
    endtask

    task axi_write_backpressured;
        input [AXIL_AW-1:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input integer stall_cycles;
        output [1:0] response;
        reg [1:0] held_response;
        integer cycle;
        begin
            fork
                send_aw(address);
                send_w(data, strobe);
            join
            while (!s_axi_bvalid) @(posedge aclk);
            held_response = s_axi_bresp;
            for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                @(negedge aclk);
                check(s_axi_bvalid && s_axi_bresp == held_response,
                      "B response stable under backpressure");
                check(!s_axi_awready && !s_axi_wready,
                      "write request blocked while B pending");
            end
            response = held_response;
            @(negedge aclk);
            s_axi_bready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_read;
        input [AXIL_AW-1:0] address;
        output [31:0] data;
        output [1:0] response;
        begin
            @(negedge aclk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            do @(posedge aclk); while (!s_axi_arready);
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge aclk);
            data = s_axi_rdata;
            response = s_axi_rresp;
            @(negedge aclk);
            s_axi_rready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    task axi_read_backpressured;
        input [AXIL_AW-1:0] address;
        input integer stall_cycles;
        output [31:0] data;
        output [1:0] response;
        reg [31:0] held_data;
        reg [1:0] held_response;
        integer cycle;
        begin
            @(negedge aclk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            do @(posedge aclk); while (!s_axi_arready);
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge aclk);
            held_data = s_axi_rdata;
            held_response = s_axi_rresp;
            for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                @(negedge aclk);
                check(s_axi_rvalid && s_axi_rdata == held_data &&
                      s_axi_rresp == held_response,
                      "R payload stable under backpressure");
                check(!s_axi_arready, "read request blocked while R pending");
            end
            data = held_data;
            response = held_response;
            @(negedge aclk);
            s_axi_rready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    task clear_completion_with_simultaneous_event;
        begin
            @(negedge aclk);
            s_axi_awaddr = 12'h014;
            s_axi_awvalid = 1'b1;
            s_axi_wdata = 32'd1;
            s_axi_wstrb = 4'b0001;
            s_axi_wvalid = 1'b1;
            done_pulse = 1'b1;
            do @(posedge aclk); while (!(s_axi_awready && s_axi_wready));
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            done_pulse = 1'b0;
            accept_b(write_response);
        end
    endtask

    task clear_error_with_simultaneous_event;
        input [3:0] class_value;
        input [7:0] code_value;
        input [7:0] phase_value;
        input [4:0] word_value;
        input [31:0] detail_value;
        begin
            @(negedge aclk);
            error_class = class_value;
            error_code = code_value;
            error_phase = phase_value;
            cfg_error_word = word_value;
            error_detail = detail_value;
            s_axi_awaddr = 12'h014;
            s_axi_awvalid = 1'b1;
            s_axi_wdata = 32'd2;
            s_axi_wstrb = 4'b0001;
            s_axi_wvalid = 1'b1;
            error_pulse = 1'b1;
            do @(posedge aclk); while (!(s_axi_awready && s_axi_wready));
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            error_pulse = 1'b0;
            accept_b(write_response);
        end
    endtask

    task pulse_completion;
        begin
            @(negedge aclk);
            done_pulse = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            done_pulse = 1'b0;
        end
    endtask

    task pulse_error_event;
        input [3:0] class_value;
        input [7:0] code_value;
        input [7:0] phase_value;
        input [4:0] word_value;
        input [31:0] detail_value;
        begin
            @(negedge aclk);
            error_class = class_value;
            error_code = code_value;
            error_phase = phase_value;
            cfg_error_word = word_value;
            error_detail = detail_value;
            error_pulse = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            error_pulse = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(posedge aclk);
        @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        axi_read_backpressured(12'h000, 4, read_value, read_response);
        check(read_response == 2'b00 && read_value == 32'h4353_4733,
              "identification");
        axi_read(12'h004, read_value, read_response);
        check(read_value == {`RECON_ARCHITECTURE_REVISION,
                             `RECON_RTL_MINOR_REVISION,
                             `RECON_CONTEXT_FORMAT_REVISION,
                             `RECON_RUN_CONFIGURATION_REVISION},
              "version revision fields");
        axi_read(12'h008, read_value, read_response);
        check(read_value == 32'h4080_5fff, "compact capabilities");
        axi_read(12'h00c, read_value, read_response);
        check(read_value == 32'h0204_0400, "N/M/K build limits");

        // AW-before-W, W-before-AW and WSTRB on the only 64-bit pointer.
        axi_write_backpressured(12'h024, 32'h3456_78c0, 4'hf, 4,
                               write_response);
        check(write_response == 2'b00, "B backpressure write response");
        axi_write(12'h028, 32'h0000_0012, 4'hf, 2'd2, write_response);
        axi_write(12'h024, 32'h0000_ab00, 4'b0010, 2'd0, write_response);
        axi_read(12'h024, read_value, read_response);
        check(read_value == 32'h3456_abc0, "pointer byte strobe");
        check(run_cfg_addr == 64'h0000_0012_3456_abc0,
              "single run-configuration address state");

        axi_write(12'h010, 32'd3, 4'h1, 2'd0, write_response);
        check(write_response == 2'b10 && start_count == 0 && abort_count == 0,
              "START and ABORT together rejected");
        axi_write(12'h010, 32'h0000_0010, 4'h1, 2'd0, write_response);
        check(write_response == 2'b10, "reserved command bit rejected");
        axi_write(12'h010, 32'd2, 4'h1, 2'd0, write_response);
        check(write_response == 2'b10 && abort_count == 0,
              "ABORT rejected while idle");
        axi_write(12'h010, 32'd1, 4'h0, 2'd0, write_response);
        check(write_response == 2'b00 && start_count == 0,
              "unstrobed START is a no-op");
        axi_write(12'h010, 32'd1, 4'h1, 2'd0, write_response);
        repeat (2) @(posedge aclk);
        check(write_response == 2'b00 && start_count == 1,
              "aligned START accepted once");

        engine_busy = 1'b1;
        axi_write(12'h024, 32'h1111_1100, 4'hf, 2'd0, write_response);
        check(write_response == 2'b10 &&
              run_cfg_addr == 64'h0000_0012_3456_abc0,
              "pointer write rejected while busy");
        axi_write(12'h010, 32'd1, 4'h1, 2'd0, write_response);
        check(write_response == 2'b10 && start_count == 1,
              "START rejected while busy");
        cfg_fetch_active = 1'b1;
        array_active = 1'b1;
        writeback_active = 1'b1;
        abort_pending = 1'b1;
        axi_read(12'h018, read_value, read_response);
        check(read_value[4:0] == 5'b11111,
              "lifecycle status projection");
        axi_write(12'h010, 32'd2, 4'h1, 2'd0, write_response);
        repeat (2) @(posedge aclk);
        check(write_response == 2'b00 && abort_count == 1,
              "ABORT accepted while busy");
        engine_busy = 1'b0;
        cfg_fetch_active = 1'b0;
        array_active = 1'b0;
        writeback_active = 1'b0;
        abort_pending = 1'b0;

        axi_write(12'h024, 32'h3456_abc4, 4'hf, 2'd0, write_response);
        axi_write(12'h010, 32'd1, 4'h1, 2'd0, write_response);
        check(write_response == 2'b10 && start_count == 1,
              "misaligned run-configuration address rejected");
        axi_write(12'h024, 32'h3456_abc0, 4'hf, 2'd0, write_response);

        axi_write(12'h014, 32'h0000_0300, 4'b0010, 2'd0, write_response);
        stop_reason = 4'h1;
        support_count = 7'd32;
        pulse_completion();
        axi_read(12'h018, read_value, read_response);
        check(read_value[5] && read_value[11:8] == 4'h1 &&
              read_value[18:12] == 7'd32 && irq,
              "completion summary and IRQ");
        stop_reason = 4'h3;
        support_count = 7'd17;
        clear_completion_with_simultaneous_event();
        axi_read(12'h018, read_value, read_response);
        check(read_value[5] && read_value[11:8] == 4'h3 &&
              read_value[18:12] == 7'd17 && irq,
              "completion event wins simultaneous W1C");
        axi_write(12'h014, 32'd1, 4'b0001, 2'd0, write_response);
        check(!irq, "completion W1C");

        pulse_error_event(4'h2, 8'h5a, 8'h11, 5'd3, 32'hdead_beef);
        pulse_error_event(4'h4, 8'h99, 8'h22, 5'd7, 32'hbad0_bad0);
        axi_read(12'h01c, read_value, read_response);
        check(read_value[3:0] == 4'h2 && read_value[11:4] == 8'h5a &&
              read_value[19:12] == 8'h11 && read_value[24:20] == 5'd3,
              "first error wins");
        axi_read(12'h020, read_value, read_response);
        check(read_value == 32'hdead_beef, "first error detail");
        check(irq, "error IRQ asserted");
        clear_error_with_simultaneous_event(
            4'h4, 8'h99, 8'h22, 5'd7, 32'hbad0_bad0);
        axi_read(12'h01c, read_value, read_response);
        check(read_value[3:0] == 4'h4 && read_value[11:4] == 8'h99 &&
              read_value[19:12] == 8'h22 && read_value[24:20] == 5'd7,
              "new error captured when W1C coincides with event");
        axi_read(12'h020, read_value, read_response);
        check(read_value == 32'hbad0_bad0,
              "simultaneous error clear/event detail");
        axi_write(12'h014, 32'd2, 4'b0001, 2'd0, write_response);
        check(!irq, "error W1C");

        axi_read(12'h02c, read_value, read_response);
        check(read_value == 32'h5612_3434, "progress projection");
        axi_read(12'h030, read_value, read_response);
        check(read_value == 32'h89ab_cdef, "cycle count low");
        axi_read(12'h034, read_value, read_response);
        check(read_value == 32'h0123_4567, "cycle count high");

        axi_write(12'h000, 32'd1, 4'hf, 2'd0, write_response);
        check(write_response == 2'b10, "read-only write returns SLVERR");
        axi_read(12'h019, read_value, read_response);
        check(read_response == 2'b11, "misaligned read returns DECERR");
        axi_write(12'h038, 32'd1, 4'hf, 2'd0, write_response);
        check(write_response == 2'b11, "unmapped write returns DECERR");

        if (failures == 0)
            $display("PASS: compact AXI4-Lite CSR revision 3");
        else
            $display("FAIL: compact AXI4-Lite CSR (%0d failures)", failures);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
