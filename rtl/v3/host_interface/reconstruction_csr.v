`timescale 1ns/1ps
`default_nettype none

// Compact software-visible control/status block. All run parameters are fetched
// from one 64-byte run-configuration block. The fetcher captures the aligned
// address with run_start; address writes are rejected while busy.

`include "reconstruction_control_defs.vh"

module reconstruction_csr #(
    parameter integer AXIL_AW = 12,
    parameter integer TRACE_ENABLE = 0
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 csr_wr_valid,
    input  wire [AXIL_AW-1:0]   csr_wr_addr,
    input  wire [31:0]          csr_wr_data,
    input  wire [3:0]           csr_wr_strb,
    output reg  [1:0]           csr_wr_resp,
    input  wire                 csr_rd_valid,
    input  wire [AXIL_AW-1:0]   csr_rd_addr,
    output reg  [31:0]          csr_rd_data,
    output reg  [1:0]           csr_rd_resp,

    output reg                  run_start,
    output reg                  abort_request,
    output wire                 irq,
    output wire [63:0]          run_cfg_addr,

    input  wire                 engine_busy,
    input  wire                 cfg_fetch_active,
    input  wire                 array_active,
    input  wire                 writeback_active,
    input  wire                 abort_pending,
    input  wire                 done_pulse,
    input  wire [3:0]           stop_reason,
    input  wire [6:0]           support_count,
    input  wire                 error_pulse,
    input  wire [3:0]           error_class,
    input  wire [7:0]           error_code,
    input  wire [7:0]           error_phase,
    input  wire [4:0]           cfg_error_word,
    input  wire [31:0]          error_detail,
    input  wire [7:0]           phase_progress,
    input  wire [15:0]          outer_progress,
    input  wire [7:0]           solver_progress,
    input  wire [63:0]          total_cycles
);

    localparam [31:0] VERSION_VALUE = {
        `RECON_ARCHITECTURE_REVISION,
        `RECON_RTL_MINOR_REVISION,
        `RECON_CONTEXT_FORMAT_REVISION,
        `RECON_RUN_CONFIGURATION_REVISION
    };
    localparam [31:0] CAPABILITY_VALUE =
        (32'd64 << 24) | (32'd32 << 18) |
        (`RECON_NUMERIC_PROFILE_ID << 14) |
        ((TRACE_ENABLE != 0) << 13) | (1 << 12) | (1 << 11) |
        (1 << 10) | (1 << 9) | (1 << 8) | 32'h0000_00ff;
    localparam [31:0] BUILD_LIMITS_VALUE =
        (`RECON_K_MAX << 20) | (`RECON_M_MAX << 11) | `RECON_N_MAX;

    reg [63:0] run_cfg_addr_reg;
    reg completion_irq_enable;
    reg error_irq_enable;
    reg completion_pending;
    reg error_pending;
    reg [3:0] captured_stop_reason;
    reg [6:0] captured_support_count;
    reg [3:0] captured_error_class;
    reg [7:0] captured_error_code;
    reg [7:0] captured_error_phase;
    reg [4:0] captured_cfg_error_word;
    reg [31:0] captured_error_detail;

    wire [31:0] write_byte_mask = {
        {8{csr_wr_strb[3]}}, {8{csr_wr_strb[2]}},
        {8{csr_wr_strb[1]}}, {8{csr_wr_strb[0]}}
    };
    wire [31:0] effective_write_data = csr_wr_data & write_byte_mask;
    wire command_start = effective_write_data[0];
    wire command_abort = effective_write_data[1];
    wire command_reserved = |effective_write_data[31:2];
    wire run_cfg_addr_aligned =
        (run_cfg_addr_reg[5:0] == 6'd0);
    wire command_write_ok = !command_reserved &&
        !(command_start && command_abort) &&
        (!command_start || (!engine_busy && run_cfg_addr_aligned)) &&
        (!command_abort || engine_busy);
    wire event_control_write_ok =
        !(|(effective_write_data & 32'hffff_fcfc));
    wire clear_done_req = csr_wr_valid &&
        (csr_wr_addr == `RECON_CSR_EVENT_CONTROL) &&
        event_control_write_ok && csr_wr_strb[0] && csr_wr_data[0];
    wire clear_error_req = csr_wr_valid &&
        (csr_wr_addr == `RECON_CSR_EVENT_CONTROL) &&
        event_control_write_ok && csr_wr_strb[0] && csr_wr_data[1];

    assign irq = (completion_pending && completion_irq_enable) ||
                 (error_pending && error_irq_enable);
    assign run_cfg_addr = run_cfg_addr_reg;

    always @* begin
        csr_wr_resp = `AXI_RESP_DECERR;
        if (csr_wr_addr[1:0] != 2'b00) begin
            csr_wr_resp = `AXI_RESP_DECERR;
        end else begin
            case (csr_wr_addr)
                `RECON_CSR_COMMAND:
                    csr_wr_resp = command_write_ok ?
                        `AXI_RESP_OKAY : `AXI_RESP_SLVERR;
                `RECON_CSR_EVENT_CONTROL:
                    csr_wr_resp = event_control_write_ok ?
                        `AXI_RESP_OKAY : `AXI_RESP_SLVERR;
                `RECON_CSR_RUN_CONFIGURATION_LO,
                `RECON_CSR_RUN_CONFIGURATION_HI:
                    csr_wr_resp = engine_busy ?
                        `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
                `RECON_CSR_IDENTIFICATION,
                `RECON_CSR_VERSION,
                `RECON_CSR_CAPABILITY,
                `RECON_CSR_BUILD_LIMITS,
                `RECON_CSR_STATUS,
                `RECON_CSR_ERROR_INFO,
                `RECON_CSR_ERROR_DETAIL,
                `RECON_CSR_PROGRESS,
                `RECON_CSR_TOTAL_CYCLES_LO,
                `RECON_CSR_TOTAL_CYCLES_HI:
                    csr_wr_resp = `AXI_RESP_SLVERR;
                default:
                    csr_wr_resp = `AXI_RESP_DECERR;
            endcase
        end
    end

    always @* begin
        csr_rd_data = 32'd0;
        csr_rd_resp = `AXI_RESP_DECERR;
        if (!csr_rd_valid) begin
            csr_rd_data = 32'd0;
            csr_rd_resp = `AXI_RESP_DECERR;
        end else if (csr_rd_addr[1:0] != 2'b00) begin
            csr_rd_resp = `AXI_RESP_DECERR;
        end else begin
            case (csr_rd_addr)
                `RECON_CSR_IDENTIFICATION: begin
                    csr_rd_data = `RECON_IP_ID;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_VERSION: begin
                    csr_rd_data = VERSION_VALUE;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_CAPABILITY: begin
                    csr_rd_data = CAPABILITY_VALUE;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_BUILD_LIMITS: begin
                    csr_rd_data = BUILD_LIMITS_VALUE;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_COMMAND: begin
                    csr_rd_data = 32'd0;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_EVENT_CONTROL: begin
                    csr_rd_data = {22'd0, error_irq_enable,
                        completion_irq_enable, 6'd0, error_pending,
                        completion_pending};
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_STATUS: begin
                    csr_rd_data = {13'd0, captured_support_count,
                        captured_stop_reason, irq, error_pending,
                        completion_pending, abort_pending,
                        writeback_active, array_active,
                        cfg_fetch_active, engine_busy};
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_ERROR_INFO: begin
                    csr_rd_data = {7'd0, captured_cfg_error_word,
                        captured_error_phase, captured_error_code,
                        captured_error_class};
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_ERROR_DETAIL: begin
                    csr_rd_data = captured_error_detail;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_RUN_CONFIGURATION_LO: begin
                    csr_rd_data = run_cfg_addr_reg[31:0];
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_RUN_CONFIGURATION_HI: begin
                    csr_rd_data = run_cfg_addr_reg[63:32];
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_PROGRESS: begin
                    csr_rd_data = {solver_progress,
                        outer_progress, phase_progress};
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_TOTAL_CYCLES_LO: begin
                    csr_rd_data = total_cycles[31:0];
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_CSR_TOTAL_CYCLES_HI: begin
                    csr_rd_data = total_cycles[63:32];
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                default: begin
                    csr_rd_data = 32'd0;
                    csr_rd_resp = `AXI_RESP_DECERR;
                end
            endcase
        end
    end

    // M1 is a single-clock boundary. Reset is sampled synchronously, matching
    // axilite_slave; the final top will feed both from one synchronized core reset.
    always @(posedge clk) begin
        if (!rst_n) begin
            run_cfg_addr_reg <= 64'd0;
            completion_irq_enable <= 1'b0;
            error_irq_enable <= 1'b0;
            completion_pending <= 1'b0;
            error_pending <= 1'b0;
            captured_stop_reason <= `RECON_STOP_NONE;
            captured_support_count <= 7'd0;
            captured_error_class <= `RECON_ERROR_CLASS_NONE;
            captured_error_code <= 8'd0;
            captured_error_phase <= 8'd0;
            captured_cfg_error_word <= 5'd0;
            captured_error_detail <= 32'd0;
            run_start <= 1'b0;
            abort_request <= 1'b0;
        end else begin
            run_start <= 1'b0;
            abort_request <= 1'b0;

            if (csr_wr_valid && csr_wr_resp == `AXI_RESP_OKAY) begin
                case (csr_wr_addr)
                    `RECON_CSR_RUN_CONFIGURATION_LO: begin
                        if (csr_wr_strb[0]) run_cfg_addr_reg[7:0] <= csr_wr_data[7:0];
                        if (csr_wr_strb[1]) run_cfg_addr_reg[15:8] <= csr_wr_data[15:8];
                        if (csr_wr_strb[2]) run_cfg_addr_reg[23:16] <= csr_wr_data[23:16];
                        if (csr_wr_strb[3]) run_cfg_addr_reg[31:24] <= csr_wr_data[31:24];
                    end
                    `RECON_CSR_RUN_CONFIGURATION_HI: begin
                        if (csr_wr_strb[0]) run_cfg_addr_reg[39:32] <= csr_wr_data[7:0];
                        if (csr_wr_strb[1]) run_cfg_addr_reg[47:40] <= csr_wr_data[15:8];
                        if (csr_wr_strb[2]) run_cfg_addr_reg[55:48] <= csr_wr_data[23:16];
                        if (csr_wr_strb[3]) run_cfg_addr_reg[63:56] <= csr_wr_data[31:24];
                    end
                    `RECON_CSR_EVENT_CONTROL: begin
                        if (csr_wr_strb[0]) begin
                            if (csr_wr_data[0]) completion_pending <= 1'b0;
                            if (csr_wr_data[1]) error_pending <= 1'b0;
                        end
                        if (csr_wr_strb[1]) begin
                            completion_irq_enable <= csr_wr_data[8];
                            error_irq_enable <= csr_wr_data[9];
                        end
                    end
                    `RECON_CSR_COMMAND: begin
                        if (command_start) begin
                            run_start <= 1'b1;
                            completion_pending <= 1'b0;
                            error_pending <= 1'b0;
                            captured_stop_reason <= `RECON_STOP_NONE;
                            captured_support_count <= 7'd0;
                            captured_error_class <= `RECON_ERROR_CLASS_NONE;
                            captured_error_code <= 8'd0;
                            captured_error_phase <= 8'd0;
                            captured_cfg_error_word <= 5'd0;
                            captured_error_detail <= 32'd0;
                        end
                        if (command_abort)
                            abort_request <= 1'b1;
                    end
                    default: begin end
                endcase
            end

            if (done_pulse) begin
                completion_pending <= 1'b1;
                captured_stop_reason <= stop_reason;
                captured_support_count <= support_count;
            end
            if (error_pulse) begin
                error_pending <= 1'b1;
                if (!error_pending || clear_error_req) begin
                    captured_error_class <= error_class;
                    captured_error_code <= error_code;
                    captured_error_phase <= error_phase;
                    captured_cfg_error_word <= cfg_error_word;
                    captured_error_detail <= error_detail;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_start_accepted;
    reg f_abort_accepted;
    reg f_done_pulse;
    reg f_error_pulse;
    reg f_engine_busy;
    reg [63:0] f_run_cfg_addr;
    reg f_done_pending;
    reg f_error_pending;
    reg f_clear_done_req;
    reg f_clear_error_req;
    reg [3:0] f_stop_reason;
    reg [6:0] f_support_count;
    reg [3:0] f_error_class;
    reg [7:0] f_error_code;
    reg [7:0] f_error_phase;
    reg [4:0] f_cfg_error_word;
    reg [31:0] f_error_detail;
    reg [3:0] f_captured_error_class;
    reg [7:0] f_captured_error_code;
    reg [7:0] f_captured_error_phase;
    reg [4:0] f_saved_cfg_error;
    reg [31:0] f_captured_error_detail;

    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!rst_n) begin
            f_start_accepted <= 1'b0;
            f_abort_accepted <= 1'b0;
            f_done_pulse <= 1'b0;
            f_error_pulse <= 1'b0;
            f_engine_busy <= 1'b0;
            f_run_cfg_addr <= 64'd0;
            f_done_pending <= 1'b0;
            f_error_pending <= 1'b0;
            f_clear_done_req <= 1'b0;
            f_clear_error_req <= 1'b0;
            f_stop_reason <= 4'd0;
            f_support_count <= 7'd0;
            f_error_class <= 4'd0;
            f_error_code <= 8'd0;
            f_error_phase <= 8'd0;
            f_cfg_error_word <= 5'd0;
            f_error_detail <= 32'd0;
            f_captured_error_class <= 4'd0;
            f_captured_error_code <= 8'd0;
            f_captured_error_phase <= 8'd0;
            f_saved_cfg_error <= 5'd0;
            f_captured_error_detail <= 32'd0;
        end else begin
            f_start_accepted <= csr_wr_valid &&
                (csr_wr_resp == `AXI_RESP_OKAY) &&
                (csr_wr_addr == `RECON_CSR_COMMAND) && command_start;
            f_abort_accepted <= csr_wr_valid &&
                (csr_wr_resp == `AXI_RESP_OKAY) &&
                (csr_wr_addr == `RECON_CSR_COMMAND) && command_abort;
            f_done_pulse <= done_pulse;
            f_error_pulse <= error_pulse;
            f_engine_busy <= engine_busy;
            f_run_cfg_addr <= run_cfg_addr;
            f_done_pending <= completion_pending;
            f_error_pending <= error_pending;
            f_clear_done_req <= clear_done_req;
            f_clear_error_req <= clear_error_req;
            f_stop_reason <= stop_reason;
            f_support_count <= support_count;
            f_error_class <= error_class;
            f_error_code <= error_code;
            f_error_phase <= error_phase;
            f_cfg_error_word <= cfg_error_word;
            f_error_detail <= error_detail;
            f_captured_error_class <= captured_error_class;
            f_captured_error_code <= captured_error_code;
            f_captured_error_phase <= captured_error_phase;
            f_saved_cfg_error <= captured_cfg_error_word;
            f_captured_error_detail <= captured_error_detail;

            assert(!(run_start && abort_request));
            if (run_start)
                assert(run_cfg_addr[5:0] == 6'd0);
            assert(irq == ((completion_pending && completion_irq_enable) ||
                           (error_pending && error_irq_enable)));
            if (csr_wr_valid && csr_wr_addr[1:0] != 2'b00)
                assert(csr_wr_resp == `AXI_RESP_DECERR);
            if (csr_rd_valid && csr_rd_addr[1:0] != 2'b00)
                assert(csr_rd_resp == `AXI_RESP_DECERR);

            if (f_past_valid) begin
                assert(run_start == f_start_accepted);
                assert(abort_request == f_abort_accepted);
                if (f_engine_busy)
                    assert(run_cfg_addr == f_run_cfg_addr);
                if (f_done_pulse)
                    assert(completion_pending);
                if (f_error_pulse)
                    assert(error_pending);
                if (f_clear_done_req && !f_done_pulse)
                    assert(!completion_pending);
                if (f_clear_error_req && !f_error_pulse)
                    assert(!error_pending);
                if (f_done_pulse) begin
                    assert(captured_stop_reason == f_stop_reason);
                    assert(captured_support_count == f_support_count);
                end
                if (f_error_pulse &&
                    (!f_error_pending || f_clear_error_req)) begin
                    assert(captured_error_class == f_error_class);
                    assert(captured_error_code == f_error_code);
                    assert(captured_error_phase == f_error_phase);
                    assert(captured_cfg_error_word ==
                           f_cfg_error_word);
                    assert(captured_error_detail == f_error_detail);
                end
                if (f_error_pulse && f_error_pending &&
                    !f_clear_error_req) begin
                    assert(captured_error_class == f_captured_error_class);
                    assert(captured_error_code == f_captured_error_code);
                    assert(captured_error_phase == f_captured_error_phase);
                    assert(captured_cfg_error_word ==
                           f_saved_cfg_error);
                    assert(captured_error_detail == f_captured_error_detail);
                end
            end
        end
    end
`endif

endmodule

`default_nettype wire
