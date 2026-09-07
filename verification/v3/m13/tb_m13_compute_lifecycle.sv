`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "loader_control_defs.vh"
`include "reconstruction_control_defs.vh"
`include "run_configuration_defs.vh"

module tb_m13_compute_lifecycle #(
    parameter integer E2E_ALGORITHM_SELECT = 0,
    parameter integer E2E_PROFILE_SELECT = 0
);
`ifdef M13_E2E_SMOKE
`include "e2e_smoke_golden.vh"
`endif
    localparam [63:0] CFG_ADDR = 64'h1000;
    localparam [63:0] PRELOAD_ADDR = 64'h2000;
    localparam [63:0] DENSE_ADDR = 64'h8000;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer timeout;
    reg [31:0] loader_readback;

    reg [11:0] s_axi_awaddr = 0;
    reg s_axi_awvalid = 0;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata = 0;
    reg [3:0] s_axi_wstrb = 4'hf;
    reg s_axi_wvalid = 0;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready = 1'b1;
    reg [11:0] s_axi_araddr = 0;
    reg s_axi_arvalid = 0;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready = 1'b1;
    wire irq;

    reg [11:0] s_loader_axi_awaddr = 0;
    reg s_loader_axi_awvalid = 0;
    wire s_loader_axi_awready;
    reg [31:0] s_loader_axi_wdata = 0;
    reg [3:0] s_loader_axi_wstrb = 4'hf;
    reg s_loader_axi_wvalid = 0;
    wire s_loader_axi_wready;
    wire [1:0] s_loader_axi_bresp;
    wire s_loader_axi_bvalid;
    reg s_loader_axi_bready = 1'b1;
    reg [11:0] s_loader_axi_araddr = 0;
    reg s_loader_axi_arvalid = 0;
    wire s_loader_axi_arready;
    wire [31:0] s_loader_axi_rdata;
    wire [1:0] s_loader_axi_rresp;
    wire s_loader_axi_rvalid;
    reg s_loader_axi_rready = 1'b1;

    reg [7:0] predicate_values = 8'h11;
    reg compute_dma_done = 0;

    reg [1:0] aux_req_valid = 0;
    wire [1:0] aux_req_ready;
    reg [1:0] aux_req_write = 0;
    reg [127:0] aux_req_addr = 0;
    reg [31:0] aux_req_bytes = 0;
    reg [15:0] aux_req_tag = 0;
    reg [1:0] aux_wr_valid = 0;
    wire [1:0] aux_wr_ready;
    reg [255:0] aux_wr_data = 0;
    reg [31:0] aux_wr_keep = 0;
    reg [1:0] aux_wr_last = 0;
    wire [1:0] aux_rd_valid;
    reg [1:0] aux_rd_ready = 0;
    wire [255:0] aux_rd_data;
    wire [1:0] aux_rd_last;
    wire [3:0] aux_rd_resp;
    wire [15:0] aux_rd_tag;
    wire [1:0] aux_done_valid;
    reg [1:0] aux_done_ready = 0;
    wire [15:0] aux_done_tag;
    wire [1:0] aux_done_error;
    wire [3:0] aux_done_resp;
    wire [17:0] aux_done_beat;

    wire [63:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [127:0] m_axi_rdata = 0;
    reg [1:0] m_axi_rresp = 0;
    reg m_axi_rlast = 0;
    reg m_axi_rvalid = 0;
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
    reg [1:0] m_axi_bresp = 0;
    reg m_axi_bvalid = 0;
    wire m_axi_bready;
    wire engine_busy;
    wire phase_active;
    wire execution_active;
    wire writeback_active;
    wire [2:0] lifecycle_state;
    wire active_image_ok;
    wire [8:0] active_context_count;
    wire operator_fault;
    wire [15:0] operator_fault_detail;
    wire [63:0] profile_total_cycles;
    wire [63:0] profile_phase_cycles;
    wire [63:0] profile_execution_cycles;
    wire [63:0] profile_array_commit_cycles;
    wire [63:0] profile_array_stall_cycles;
    wire [63:0] profile_useful_pe_cycles;
    wire [63:0] profile_useful_pe_slots;
    wire [63:0] profile_resource_stall_cycles;
    wire [63:0] profile_phi_generate_requests;
    wire [63:0] profile_phi_replay_requests;
    wire [63:0] profile_phi_replay_responses;
    wire [63:0] profile_phi_cache_fills;
    wire [63:0] profile_phi_output_symbols;
    wire [63:0] profile_selection_accepts;
    wire [63:0] profile_dma_read_requests;
    wire [63:0] profile_dma_read_beats;
    wire [63:0] profile_dma_write_requests;
    wire [63:0] profile_dma_write_beats;
    wire [63:0] profile_dma_write_responses;
    wire [63:0] profile_result_drain_cycles;
    wire [63:0] profile_result_drain_beats;
    wire [6:0] final_support_count;
    wire [`RECON_K_MAX*10-1:0] final_support_indices;
    wire [`RECON_K_MAX*`RECON_SOLVER_W-1:0] final_support_coefficients;

    reg monitor_run_active = 0;
    reg monitor_termination_valid = 0;
    reg monitor_residual_limit = 0;
    reg [`RECON_ACC_W-1:0] monitor_residual_sq = 0;
    reg monitor_refinement_valid = 0;
    reg monitor_certificate_pass = 0;
    reg [6:0] monitor_support_count = 0;
    reg [`RECON_K_MAX*10-1:0] monitor_support_indices = 0;
    wire monitor_residual_limit_reached;
    wire monitor_iteration_limit_reached;
    wire monitor_support_stable;
    wire monitor_residual_decreased;
    wire monitor_solver_converged;
    wire [15:0] monitor_outer_iter;
    wire [7:0] monitor_solver_iter;

    m13_termination_monitor monitor_dut (
        .clk(clk), .rst_n(rst_n), .run_active(monitor_run_active),
        .outer_limit(16'd2), .refine_limit(8'd3),
        .termination_mode(`RECON_TERMINATION_MODE_NORMAL),
        .termination_event_valid(monitor_termination_valid),
        .termination_residual_limit_reached(monitor_residual_limit),
        .termination_residual_sq(monitor_residual_sq),
        .refinement_event_valid(monitor_refinement_valid),
        .refinement_certificate_pass(monitor_certificate_pass),
        .support_count(monitor_support_count),
        .support_indices(monitor_support_indices),
        .residual_limit_reached(monitor_residual_limit_reached),
        .iteration_limit_reached(monitor_iteration_limit_reached),
        .support_stable(monitor_support_stable),
        .residual_decreased(monitor_residual_decreased),
        .solver_converged(monitor_solver_converged),
        .outer_iter(monitor_outer_iter), .solver_iter(monitor_solver_iter)
    );

    reg [127:0] cfg_beats [0:3];
    reg read_active = 0;
    reg [63:0] read_address = 0;
    reg [7:0] read_idx = 0;
    reg [7:0] read_len = 0;
    reg write_active = 0;
    reg [7:0] write_idx = 0;
    reg [7:0] write_len = 0;
    integer write_bursts = 0;
    integer write_beats = 0;
    reg [63:0] write_address [0:511];
    reg [127:0] write_data [0:511];

    assign m_axi_arready = !read_active && !m_axi_rvalid;
    assign m_axi_awready = !write_active && !m_axi_bvalid;
    assign m_axi_wready = write_active;

    function automatic [35:0] array_control_word;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +: 3] =
                `RECON_NEXT_PC_MODE_RETURN_TO_PHASE;
            value[`RECON_ARRAY_CONTROL_FIELD_CLUSTER_ENABLE_MASK_LSB +: 2] =
                2'b11;
            value[`RECON_ARRAY_CONTROL_FIELD_ROUTINE_DONE_LSB] = 1'b1;
            value[`RECON_ARRAY_CONTROL_FIELD_SAFE_ABORT_POINT_LSB] = 1'b1;
            array_control_word = value;
        end
    endfunction

    function automatic [35:0] phase_launch_word;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[2:0] = `RECON_PHASE_OP_LAUNCH_ARRAY;
            value[10:3] = 8'd0;
            value[27:24] = 4'd1;
            value[32] = 1'b1;
            phase_launch_word = value;
        end
    endfunction

    function automatic [35:0] phase_wait_word;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[2:0] = `RECON_PHASE_OP_WAIT_CONDITION;
            value[14:11] = `RECON_PHASE_CONDITION_ARRAY_ROUTINE_DONE;
            value[27:24] = 4'd1;
            value[32] = 1'b1;
            phase_wait_word = value;
        end
    endfunction

    function automatic [35:0] phase_complete_word;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[2:0] = `RECON_PHASE_OP_COMPLETE;
            value[31:28] = `RECON_STOP_SUPPORT_STABLE;
            value[32] = 1'b1;
            phase_complete_word = value;
        end
    endfunction

    function automatic [63:0] vector_configuration;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[31:16] = 16'd32;
            value[43:32] = 12'd1;
            value[48:47] = 2'd3;
            value[51:49] = `RECON_BANK_MODE_CYCLIC;
            value[54:52] = `RECON_ELEMENT_FORMAT_DATA18;
            value[57:55] = `RECON_PACKING_MODE_FOUR;
            value[58] = 1'b1;
            value[62:61] = `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD;
            vector_configuration = value;
        end
    endfunction

    function automatic [71:0] expected_d18_word;
        input integer first_value;
        integer lane;
        reg [71:0] value;
        begin
            value = 72'd0;
            for (lane = 0; lane < 4; lane = lane + 1)
                value[lane*18 +: 18] = first_value + lane;
            expected_d18_word = value;
        end
    endfunction

    function automatic [127:0] preload_payload;
        input [7:0] beat;
        integer lane;
        reg [127:0] value;
        begin
            value = 128'd0;
            for (lane = 0; lane < 4; lane = lane + 1)
                value[lane*32 +: 32] = beat * 4 + lane;
            preload_payload = value;
        end
    endfunction

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

    task automatic image_write;
        input [3:0] plane;
        input [7:0] address;
        input [71:0] data;
        begin
            loader_write(`RECON_LOADER_CSR_IMAGE_META,
                {16'd0, address, plane, 3'd0, 1'b0}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_IMAGE_DATA_LO,
                data[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_IMAGE_DATA_MID,
                data[63:32], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_IMAGE_DATA_HI,
                {24'd0, data[71:64]}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_IMAGE_WRITE, `AXI_RESP_OKAY);
            loader_wait_completion(`RECON_LOADER_COMMAND_IMAGE_WRITE,
                "context image write accepted");
        end
    endtask

    task automatic finalize_image;
        begin
            loader_write(`RECON_LOADER_CSR_IMAGE_META, 32'd0,
                `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_IMAGE_FINALIZE, `AXI_RESP_OKAY);
            loader_wait_completion(`RECON_LOADER_COMMAND_IMAGE_FINALIZE,
                "context image finalize accepted");
        end
    endtask

    task automatic csr_write;
        input [11:0] address;
        input [31:0] data;
        reg address_done;
        reg data_done;
        begin
            address_done = 0;
            data_done = 0;
            @(negedge clk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wvalid = 1;
            while (!address_done || !data_done) begin
                @(posedge clk);
                if (s_axi_awvalid && s_axi_awready) address_done = 1;
                if (s_axi_wvalid && s_axi_wready) data_done = 1;
                @(negedge clk);
                if (address_done) s_axi_awvalid = 0;
                if (data_done) s_axi_wvalid = 0;
            end
            while (!s_axi_bvalid) @(posedge clk);
            check(s_axi_bresp == `AXI_RESP_OKAY, "CSR write response");
            @(posedge clk);
        end
    endtask

    task automatic loader_write;
        input [11:0] address;
        input [31:0] data;
        input [1:0] expected_response;
        reg address_done;
        reg data_done;
        begin
            address_done = 0;
            data_done = 0;
            @(negedge clk);
            s_loader_axi_awaddr = address;
            s_loader_axi_awvalid = 1;
            s_loader_axi_wdata = data;
            s_loader_axi_wvalid = 1;
            while (!address_done || !data_done) begin
                @(posedge clk);
                if (s_loader_axi_awvalid && s_loader_axi_awready)
                    address_done = 1;
                if (s_loader_axi_wvalid && s_loader_axi_wready)
                    data_done = 1;
                @(negedge clk);
                if (address_done) s_loader_axi_awvalid = 0;
                if (data_done) s_loader_axi_wvalid = 0;
            end
            while (!s_loader_axi_bvalid) @(posedge clk);
            check(s_loader_axi_bresp == expected_response,
                  "loader AXI write response");
            @(posedge clk);
        end
    endtask

    task automatic loader_read;
        input [11:0] address;
        output [31:0] data;
        begin
            @(negedge clk);
            s_loader_axi_araddr = address;
            s_loader_axi_arvalid = 1'b1;
            while (!(s_loader_axi_arvalid && s_loader_axi_arready))
                @(posedge clk);
            @(negedge clk);
            s_loader_axi_arvalid = 1'b0;
            while (!s_loader_axi_rvalid) @(posedge clk);
            check(s_loader_axi_rresp == `AXI_RESP_OKAY,
                  "loader AXI read response");
            data = s_loader_axi_rdata;
            @(posedge clk);
        end
    endtask

    task automatic loader_wait_completion;
        input [2:0] command;
        input [8*120-1:0] message;
        reg [31:0] status;
`ifdef M13_E2E_SMOKE
        reg [31:0] detail;
`endif
        begin
            status = 32'd0;
            timeout = 0;
            while (!status[1] && timeout < 3000) begin
                loader_read(`RECON_LOADER_CSR_STATUS, status);
                timeout = timeout + 1;
            end
            check(timeout < 3000, message);
            check(status[5:3] == command,
                  "loader completed command identity");
`ifdef M13_E2E_SMOKE
            if (status[2] || status[13:6] != 8'd0) begin
                loader_read(`RECON_LOADER_CSR_DETAIL, detail);
                $display("E2E LOADER REJECT command=%0d status=%08x detail=%08x",
                    command, status, detail);
                $fatal(1, "end-to-end loader rejected production artifact");
            end
`endif
            check(!status[2] && status[13:6] == 8'd0,
                  "loader backend completion status");
            loader_write(`RECON_LOADER_CSR_STATUS, 32'd2,
                `AXI_RESP_OKAY);
        end
    endtask

    task automatic memory_configuration_write;
        input [5:0] configuration_id;
        input [63:0] configuration;
        begin
            loader_write(`RECON_LOADER_CSR_MEMORY_META,
                {18'd0, configuration_id, 7'd0, 1'b0}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_MEMORY_DATA_LO,
                configuration[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_MEMORY_DATA_HI,
                configuration[63:32], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_MEMORY_WRITE, `AXI_RESP_OKAY);
            loader_wait_completion(`RECON_LOADER_COMMAND_MEMORY_WRITE,
                "memory configuration write accepted");
        end
    endtask

    task automatic scalar_preload;
        input address;
        input signed [`RECON_ACC_W-1:0] data;
        begin
            loader_write(`RECON_LOADER_CSR_SCALAR_META,
                {31'd0, address}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_SCALAR_DATA_LO,
                data[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_SCALAR_DATA_HI,
                {2'd0, data[`RECON_ACC_W-1:32]}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_SCALAR_PRELOAD, `AXI_RESP_OKAY);
            loader_wait_completion(`RECON_LOADER_COMMAND_SCALAR_PRELOAD,
                "scalar preload accepted");
        end
    endtask

    task automatic scratch_write;
        input [2:0] bank;
        input [8:0] address;
        input [71:0] data;
        begin
            loader_write(`RECON_LOADER_CSR_SCRATCH_META,
                {14'd0, address, 6'd0, bank}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_SCRATCH_DATA_LO,
                data[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_SCRATCH_DATA_MID,
                data[63:32], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_SCRATCH_DATA_HI,
                {24'd0, data[71:64]}, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_SCRATCH_WRITE, `AXI_RESP_OKAY);
            loader_wait_completion(`RECON_LOADER_COMMAND_SCRATCH_WRITE,
                "scratchpad direct write accepted");
        end
    endtask

    task automatic issue_preload;
        reg [31:0] status;
        reg [63:0] configuration;
        begin
            configuration = vector_configuration();
            loader_write(`RECON_LOADER_CSR_PRELOAD_SRC_LO,
                PRELOAD_ADDR[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_PRELOAD_SRC_HI,
                PRELOAD_ADDR[63:32], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_PRELOAD_META,
                32'd40, `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_PRELOAD_CFG_LO,
                configuration[31:0], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_PRELOAD_CFG_HI,
                configuration[63:32], `AXI_RESP_OKAY);
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_SCRATCH_PRELOAD, `AXI_RESP_OKAY);
            loader_read(`RECON_LOADER_CSR_STATUS, status);
            check(status[0], "loader reports scratchpad preload busy");
            loader_write(`RECON_LOADER_CSR_COMMAND,
                `RECON_LOADER_COMMAND_SCRATCH_WRITE, `AXI_RESP_SLVERR);
            loader_wait_completion(`RECON_LOADER_COMMAND_SCRATCH_PRELOAD,
                "scratchpad DMA preload completion");
            check(dut.u_operator.u_scratchpad_subsystem.u_memory.g_bank[0].memory[0] ==
                  expected_d18_word(0), "preload writes scratchpad bank0");
            check(dut.u_operator.u_scratchpad_subsystem.u_memory.g_bank[7].memory[0] ==
                  expected_d18_word(28), "preload writes scratchpad bank7");
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            read_active <= 0;
            m_axi_rvalid <= 0;
            write_active <= 0;
            m_axi_bvalid <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
`ifdef M13_E2E_SMOKE
                if (!((m_axi_araddr == E2E_CFG_ADDR && m_axi_arlen == 3) ||
                      (m_axi_araddr == E2E_MEAS_ADDR &&
                       m_axi_arlen == E2E_MEAS_BEATS-1)))
                    $display("E2E UNKNOWN AXI READ addr=%016x len=%0d size=%0d",
                        m_axi_araddr, m_axi_arlen, m_axi_arsize);
                check((m_axi_araddr == E2E_CFG_ADDR && m_axi_arlen == 3) ||
                      (m_axi_araddr == E2E_MEAS_ADDR &&
                       m_axi_arlen == E2E_MEAS_BEATS-1),
                      "known end-to-end read transaction");
`else
                check((m_axi_araddr == CFG_ADDR && m_axi_arlen == 3) ||
                      (m_axi_araddr == PRELOAD_ADDR && m_axi_arlen == 7),
                      "known read transaction");
`endif
                read_active <= 1;
                read_address <= m_axi_araddr;
                read_idx <= 0;
                read_len <= m_axi_arlen;
            end
            if (read_active && !m_axi_rvalid) begin
                m_axi_rvalid <= 1;
`ifdef M13_E2E_SMOKE
                if (read_address == E2E_CFG_ADDR)
                    m_axi_rdata <= cfg_beats[read_idx];
                else
                    m_axi_rdata <= E2E_MEAS[read_idx*128 +: 128];
`else
                if (read_address == CFG_ADDR)
                    m_axi_rdata <= cfg_beats[read_idx];
                else
                    m_axi_rdata <= preload_payload(read_idx);
`endif
                m_axi_rresp <= 0;
                m_axi_rlast <= read_idx == read_len;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 0;
                if (m_axi_rlast) read_active <= 0;
                else read_idx <= read_idx + 1'b1;
            end
            if (m_axi_awvalid && m_axi_awready) begin
                write_address[write_bursts] <= m_axi_awaddr;
                write_bursts <= write_bursts + 1;
                write_active <= 1;
                write_idx <= 0;
                write_len <= m_axi_awlen;
            end
            if (m_axi_wvalid && m_axi_wready) begin
                write_data[write_beats] <= m_axi_wdata;
                write_beats <= write_beats + 1;
                check(m_axi_wstrb == 16'hffff, "result WSTRB");
                check(m_axi_wlast == (write_idx == write_len), "result WLAST");
                if (m_axi_wlast) begin
                    write_active <= 0;
                    m_axi_bvalid <= 1;
                    m_axi_bresp <= 0;
                end else write_idx <= write_idx + 1'b1;
            end
            if (m_axi_bvalid && m_axi_bready) m_axi_bvalid <= 0;
        end
    end

    m13_compute_lifecycle_integration dut (.*);

    integer plane;
`ifdef M13_E2E_SMOKE
    reg [71:0] e2e_plane_0 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_1 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_2 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_3 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_4 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_5 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_6 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_7 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_8 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [71:0] e2e_plane_9 [0:E2E_ARRAY_CONTEXT_COUNT-1];
    reg [35:0] e2e_phase_words [0:255];
    reg [63:0] e2e_memory_configurations [0:63];
    reg e2e_fault_seen = 1'b0;
    integer e2e_algorithm = E2E_ALGORITHM_SELECT;
    integer e2e_profile = E2E_PROFILE_SELECT;
    integer e2e_case_index = 0;
    integer e2e_residual_captures = 0;
    integer e2e_outer_iteration_events = 0;
    integer e2e_paired_transpose_commits = 0;
    integer e2e_serial_transpose_captures = 0;
    integer e2e_forward_mode_cycles = 0;
    integer e2e_support_pack_empty_stalls = 0;
    integer e2e_cache_replay_backpressure_cycles = 0;
    integer e2e_cache_control_busy_cycles = 0;
    integer e2e_cache_pipeline_full_cycles = 0;
    integer e2e_cache_invalid_cycles = 0;
    integer e2e_cache_consumer_stall_cycles = 0;
    integer e2e_refill_request_valid_cycles = 0;
    integer e2e_refill_request_fires = 0;
    integer e2e_support_pack_captures = 0;
    integer e2e_support_pack_releases = 0;
    integer e2e_transpose_issue_cycles = 0;
    integer e2e_transpose_wait_cycles = 0;
    integer e2e_transpose_writeback_cycles = 0;
    integer e2e_transpose_wait_stalls = 0;
    integer e2e_transpose_writeback_stalls = 0;
    integer e2e_cursor_restart_commits = 0;
    integer e2e_cursor_restart_mask_a = 0;
    integer e2e_cursor_restart_mask_ab = 0;
    integer e2e_total_cycles = 0;
    integer e2e_phase_cycles = 0;
    integer e2e_execution_cycles = 0;
    integer e2e_writeback_cycles = 0;
    integer e2e_pe_useful_cycles = 0;
    integer e2e_stream_input_stalls = 0;
    integer e2e_stream_output_stalls = 0;
    integer e2e_resource_request_stalls = 0;
    integer e2e_resource_response_stalls = 0;
    integer e2e_other_commit_stalls = 0;
    integer e2e_phi_generate_fires = 0;
    integer e2e_phi_replay_fires = 0;
    integer e2e_phi_replay_response_fires = 0;
    integer e2e_phi_cache_fill_fires = 0;
    integer e2e_phi_output_fires = 0;
    integer e2e_selection_fires = 0;
    integer e2e_dma_read_address_fires = 0;
    integer e2e_dma_read_beat_fires = 0;
    integer e2e_dma_write_address_fires = 0;
    integer e2e_dma_write_beat_fires = 0;
    integer e2e_dma_write_response_fires = 0;
    integer e2e_result_drain_cycles = 0;
    integer e2e_result_drain_beats = 0;
    integer e2e_capture_lane;
    reg signed [17:0] e2e_last_residual [0:E2E_M-1];
    reg [8*128-1:0] e2e_phase_file;

    always @(posedge clk) begin
        if (!rst_n || dut.run_start_pulse) begin
            e2e_residual_captures <= 0;
            e2e_outer_iteration_events <= 0;
            e2e_paired_transpose_commits <= 0;
            e2e_serial_transpose_captures <= 0;
            e2e_forward_mode_cycles <= 0;
            e2e_support_pack_empty_stalls <= 0;
            e2e_cache_replay_backpressure_cycles <= 0;
            e2e_cache_control_busy_cycles <= 0;
            e2e_cache_pipeline_full_cycles <= 0;
            e2e_cache_invalid_cycles <= 0;
            e2e_cache_consumer_stall_cycles <= 0;
            e2e_refill_request_valid_cycles <= 0;
            e2e_refill_request_fires <= 0;
            e2e_support_pack_captures <= 0;
            e2e_support_pack_releases <= 0;
            e2e_transpose_issue_cycles <= 0;
            e2e_transpose_wait_cycles <= 0;
            e2e_transpose_writeback_cycles <= 0;
            e2e_transpose_wait_stalls <= 0;
            e2e_transpose_writeback_stalls <= 0;
            e2e_cursor_restart_commits <= 0;
            e2e_cursor_restart_mask_a <= 0;
            e2e_cursor_restart_mask_ab <= 0;
            e2e_total_cycles <= 0;
            e2e_phase_cycles <= 0;
            e2e_execution_cycles <= 0;
            e2e_writeback_cycles <= 0;
            e2e_pe_useful_cycles <= 0;
            e2e_stream_input_stalls <= 0;
            e2e_stream_output_stalls <= 0;
            e2e_resource_request_stalls <= 0;
            e2e_resource_response_stalls <= 0;
            e2e_other_commit_stalls <= 0;
            e2e_phi_generate_fires <= 0;
            e2e_phi_replay_fires <= 0;
            e2e_phi_replay_response_fires <= 0;
            e2e_phi_cache_fill_fires <= 0;
            e2e_phi_output_fires <= 0;
            e2e_selection_fires <= 0;
            e2e_dma_read_address_fires <= 0;
            e2e_dma_read_beat_fires <= 0;
            e2e_dma_write_address_fires <= 0;
            e2e_dma_write_beat_fires <= 0;
            e2e_dma_write_response_fires <= 0;
            e2e_result_drain_cycles <= 0;
            e2e_result_drain_beats <= 0;
            for (e2e_capture_lane = 0; e2e_capture_lane < E2E_M;
                    e2e_capture_lane = e2e_capture_lane + 1)
                e2e_last_residual[e2e_capture_lane] <= 0;
        end else if (engine_busy) begin
            e2e_total_cycles <= e2e_total_cycles + 1;
            if (phase_active)
                e2e_phase_cycles <= e2e_phase_cycles + 1;
            if (execution_active)
                e2e_execution_cycles <= e2e_execution_cycles + 1;
            if (writeback_active) begin
                e2e_writeback_cycles <= e2e_writeback_cycles + 1;
                e2e_result_drain_cycles <= e2e_result_drain_cycles + 1;
            end
            if (dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
                    (dut.u_operator.active_tile_operation !=
                     `RECON_TILE_OP_NOP))
                e2e_pe_useful_cycles <= e2e_pe_useful_cycles + 1;
            if (dut.u_operator.cycle_valid && !dut.u_operator.cycle_commit) begin
                if (!dut.stream_input_ready)
                    e2e_stream_input_stalls <= e2e_stream_input_stalls + 1;
                else if (!dut.stream_output_ready)
                    e2e_stream_output_stalls <= e2e_stream_output_stalls + 1;
                else if (!dut.resource_req_ready)
                    e2e_resource_request_stalls <=
                        e2e_resource_request_stalls + 1;
                else if (!dut.resource_rsp_valid)
                    e2e_resource_response_stalls <=
                        e2e_resource_response_stalls + 1;
                else
                    e2e_other_commit_stalls <= e2e_other_commit_stalls + 1;
            end
            if (dut.u_operator.u_phi_stream.u_provider.generator_request_fire)
                e2e_phi_generate_fires <= e2e_phi_generate_fires + 1;
            if (dut.u_operator.u_phi_stream.u_provider.cache_replay_valid &&
                    dut.u_operator.u_phi_stream.u_provider.cache_replay_ready)
                e2e_phi_replay_fires <= e2e_phi_replay_fires + 1;
            if (dut.u_operator.profile_phi_replay_response_fire)
                e2e_phi_replay_response_fires <=
                    e2e_phi_replay_response_fires + 1;
            if (dut.u_operator.profile_phi_cache_fill_fire)
                e2e_phi_cache_fill_fires <= e2e_phi_cache_fill_fires + 1;
            if (dut.u_operator.profile_phi_output_fire)
                e2e_phi_output_fires <= e2e_phi_output_fires + 1;
            if (dut.u_operator.selected_candidate_valid &&
                    dut.u_operator.dispatcher_candidate_ready)
                e2e_selection_fires <= e2e_selection_fires + 1;
            if (dut.termination_event_valid)
                e2e_outer_iteration_events <= e2e_outer_iteration_events + 1;
            if (dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
                    dut.u_operator.d18_split_mode) begin
                e2e_residual_captures <= e2e_residual_captures + 1;
                for (e2e_capture_lane = 0; e2e_capture_lane < 16;
                        e2e_capture_lane = e2e_capture_lane + 1)
                    if ((dut.u_operator.u_vector_ingress.d18_base +
                            e2e_capture_lane) < E2E_M)
                        e2e_last_residual[
                            dut.u_operator.u_vector_ingress.d18_base +
                            e2e_capture_lane] <=
                            $signed(dut.u_operator.d18_split_solver_data[
                                e2e_capture_lane*`RECON_SOLVER_W +:
                                `RECON_SOLVER_W]) >>> 5;
            end
            if (dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
                    dut.u_operator.u_vector_ingress.transpose_pair_mode)
                e2e_paired_transpose_commits <=
                    e2e_paired_transpose_commits + 1;
            if (dut.u_operator.u_vector_ingress.transpose_low_capture ||
                    dut.u_operator.u_vector_ingress.transpose_high_capture)
                e2e_serial_transpose_captures <=
                    e2e_serial_transpose_captures + 1;
            if (dut.u_operator.phi_mode == 3'd5)
                e2e_forward_mode_cycles <= e2e_forward_mode_cycles + 1;
            if (dut.u_operator.cycle_valid && dut.u_operator.support_scalar_mode &&
                    !dut.u_operator.u_vector_ingress.support_pack_valid)
                e2e_support_pack_empty_stalls <=
                    e2e_support_pack_empty_stalls + 1;
            if (dut.u_operator.u_phi_stream.u_provider.cache_replay_valid &&
                    !dut.u_operator.u_phi_stream.u_provider.cache_replay_ready)
                e2e_cache_replay_backpressure_cycles <=
                    e2e_cache_replay_backpressure_cycles + 1;
            if (dut.u_operator.u_phi_stream.u_provider.cache_replay_valid &&
                    !dut.u_operator.u_phi_stream.u_provider.cache_replay_ready) begin
                if (dut.u_operator.u_phi_stream.u_cache.state != 0)
                    e2e_cache_control_busy_cycles <=
                        e2e_cache_control_busy_cycles + 1;
                if (!dut.u_operator.u_phi_stream.u_cache.cache_valid)
                    e2e_cache_invalid_cycles <=
                        e2e_cache_invalid_cycles + 1;
            end
            if (dut.u_operator.u_phi_stream.internal_rsp_valid &&
                    !dut.u_operator.phi_cache_rsp_ready)
                e2e_cache_consumer_stall_cycles <=
                    e2e_cache_consumer_stall_cycles + 1;
            if (dut.u_operator.phi_refill_active &&
                    dut.u_operator.u_phi_stream.u_provider.generator_request_valid)
                e2e_refill_request_valid_cycles <=
                    e2e_refill_request_valid_cycles + 1;
            if (dut.u_operator.phi_refill_active &&
                    dut.u_operator.u_phi_stream.u_provider.generator_request_fire)
                e2e_refill_request_fires <= e2e_refill_request_fires + 1;
            if (dut.u_operator.u_vector_ingress.support_capture)
                e2e_support_pack_captures <= e2e_support_pack_captures + 1;
            if (dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
                    dut.u_operator.support_scalar_mode &&
                    dut.u_operator.u_vector_ingress.support_release)
                e2e_support_pack_releases <= e2e_support_pack_releases + 1;
            if (dut.u_operator.cycle_valid &&
                    (dut.u_array_context_sequencer.pc == 8'd33))
                e2e_transpose_issue_cycles <= e2e_transpose_issue_cycles + 1;
            if (dut.u_operator.cycle_valid &&
                    (dut.u_array_context_sequencer.pc == 8'd34)) begin
                e2e_transpose_wait_cycles <= e2e_transpose_wait_cycles + 1;
                if (!dut.u_operator.cycle_commit)
                    e2e_transpose_wait_stalls <= e2e_transpose_wait_stalls + 1;
            end
            if (dut.u_operator.cycle_valid &&
                    (dut.u_array_context_sequencer.pc == 8'd35)) begin
                e2e_transpose_writeback_cycles <=
                    e2e_transpose_writeback_cycles + 1;
                if (!dut.u_operator.cycle_commit)
                    e2e_transpose_writeback_stalls <=
                        e2e_transpose_writeback_stalls + 1;
            end
            if (dut.u_operator.cursor_restart_valid &&
                    dut.u_operator.cursor_restart_ready) begin
                e2e_cursor_restart_commits <= e2e_cursor_restart_commits + 1;
                if (dut.u_operator.cursor_restart_mask == 3'b001)
                    e2e_cursor_restart_mask_a <= e2e_cursor_restart_mask_a + 1;
                if (dut.u_operator.cursor_restart_mask == 3'b011)
                    e2e_cursor_restart_mask_ab <= e2e_cursor_restart_mask_ab + 1;
            end
        end
        if (rst_n && !dut.run_start_pulse && engine_busy) begin
            if (m_axi_arvalid && m_axi_arready)
                e2e_dma_read_address_fires <=
                    e2e_dma_read_address_fires + 1;
            if (m_axi_rvalid && m_axi_rready)
                e2e_dma_read_beat_fires <= e2e_dma_read_beat_fires + 1;
            if (m_axi_awvalid && m_axi_awready)
                e2e_dma_write_address_fires <=
                    e2e_dma_write_address_fires + 1;
            if (m_axi_wvalid && m_axi_wready) begin
                e2e_dma_write_beat_fires <= e2e_dma_write_beat_fires + 1;
                if (writeback_active)
                    e2e_result_drain_beats <= e2e_result_drain_beats + 1;
            end
            if (m_axi_bvalid && m_axi_bready)
                e2e_dma_write_response_fires <=
                    e2e_dma_write_response_fires + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_operator.u_phi_stream.u_provider.command_fire &&
                dut.u_operator.u_phi_stream.u_provider.start_selected) begin
            $display("E2E PHI START id=%0d valid=%b data=%016x legal=%b M=%0d N=%0d",
                dut.u_operator.u_phi_stream.u_provider.configuration_id,
                dut.u_operator.u_phi_stream.u_provider.configuration_valid,
                dut.u_operator.u_phi_stream.u_provider.configuration_data,
                dut.u_operator.u_phi_stream.u_provider.cfg_legal,
                dut.u_operator.u_phi_stream.u_provider.active_measurement_count,
                dut.u_operator.u_phi_stream.u_provider.active_signal_length);
            $display("E2E PHI CFG base=%0d count=%0d stride=%0d first_pair=%0d pair_log2=%0d mode=%0d space=%0d read=%b write=%b atomic=%b reserved=%b row_limit=%0d last=%0d direct=%b sequential=%b cache=%b",
                dut.u_operator.u_phi_stream.u_provider.cfg_base,
                dut.u_operator.u_phi_stream.u_provider.cfg_count,
                dut.u_operator.u_phi_stream.u_provider.cfg_stride,
                dut.u_operator.u_phi_stream.u_provider.cfg_first_row_pair,
                dut.u_operator.u_phi_stream.u_provider.cfg_row_pair_count_log2,
                dut.u_operator.u_phi_stream.u_provider.cfg_mode,
                dut.u_operator.u_phi_stream.u_provider.cfg_memory_space,
                dut.u_operator.u_phi_stream.u_provider.cfg_read_enable,
                dut.u_operator.u_phi_stream.u_provider.cfg_write_enable,
                dut.u_operator.u_phi_stream.u_provider.cfg_atomic_commit,
                dut.u_operator.u_phi_stream.u_provider.cfg_reserved,
                dut.u_operator.u_phi_stream.u_provider.active_row_pair_limit,
                dut.u_operator.u_phi_stream.u_provider.cfg_last_item,
                dut.u_operator.u_phi_stream.u_provider.direct_base_legal,
                dut.u_operator.u_phi_stream.u_provider.sequential_legal,
                dut.u_operator.u_phi_stream.u_provider.cache_legal);
        end
        if (rst_n && operator_fault && !e2e_fault_seen) begin
            e2e_fault_seen <= 1'b1;
            $display("E2E OPERATOR FAULT detail=%04x phase_pc=%0d array_pc=%0d",
                operator_fault_detail,
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc);
            $display("E2E FAULT SOURCES stream=%b dispatch=%b provider=%b cgra=%h sat=%h m5=%b m5sat=%b redfault=%b select=%b pack=%h phi_order=%b cache=%b metadata=%b row_metadata=%b row_stop=%b",
                dut.u_operator.stream_contract_error,
                dut.u_operator.dispatcher_contract_error,
                dut.u_operator.phi_cfg_error,
                dut.u_operator.cgra_contract_error,
                dut.u_operator.cgra_saturation,
                dut.u_operator.m5_fault_valid,
                dut.u_operator.m5_saturation_event,
                dut.u_operator.reduction_result_valid &&
                    dut.u_operator.reduction_result_fault,
                dut.u_operator.selection_fault_valid,
                dut.u_operator.u_vector_codec.write_pack_error,
                dut.u_operator.u_column_flow.phi_order_error,
                dut.u_operator.phi_cache_fault,
                dut.u_operator.u_column_flow.phi_metadata_error_now,
                dut.u_operator.u_column_flow.row_major_metadata_error_now,
                dut.u_operator.u_column_flow.row_major_incomplete_stop);
            $display("E2E FAULT EXTRA scratch=%b%b%b%b support=%b conflict=%b cand=%b red_issue=%b op=%0d wait=%b%b completed=%b red_col=%0d mode=%0d",
                dut.u_operator.scratch_init_valid && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_active && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_p0_valid && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_p1_valid && dut.u_operator.execution_active,
                dut.u_operator.support_scalar_mode &&
                    (dut.u_operator.stream_a_element_count <
                     {9'd0, dut.u_operator.resident_count}),
                dut.u_operator.stream_scratch_conflict,
                dut.u_operator.vector_candidate_mode &&
                    dut.u_operator.vector_candidate_fault,
                dut.u_operator.reduction_issue_context &&
                    !dut.u_operator.u_column_flow.completed_column_valid &&
                    (dut.u_operator.u_column_flow.reduce_col_count == 3'd0),
                dut.u_operator.resource_operation,
                dut.u_operator.resource_wait_for_ready,
                dut.u_operator.resource_wait_for_result,
                dut.u_operator.u_column_flow.completed_column_valid,
                dut.u_operator.u_column_flow.reduce_col_count,
                dut.u_operator.phi_mode);
        end
    end

`ifdef M13_E2E_VERBOSE
    always @(posedge clk) begin
        if (rst_n && dut.u_operator.u_fault_encoder.fault_event &&
            !dut.u_operator.operator_fault) begin
            $display("E2E CONTRACT NOW phase_pc=%0d array_pc=%0d stream=%b dispatch=%b provider=%b cgra=%h sat=%h m5sat=%b m5fault=%b redfault=%b select=%b pack=%h init=%b preload=%b p0=%b p1=%b support_size=%b candidate=%b transpose_cfg=%b red_issue_missing=%b red_accept_missing=%b phi_meta=%b row_meta=%b row_stop=%b phi_order=%b cache=%b completed=%b phi_col=%0d row_block=%0d",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.u_operator.stream_contract_error,
                dut.u_operator.dispatcher_contract_error,
                dut.u_operator.phi_cfg_error,
                dut.u_operator.cgra_contract_error,
                dut.u_operator.cgra_saturation,
                dut.u_operator.m5_saturation_event,
                dut.u_operator.m5_fault_valid,
                dut.u_operator.reduction_result_valid &&
                    dut.u_operator.reduction_result_fault,
                dut.u_operator.selection_fault_valid,
                dut.u_operator.u_vector_codec.write_pack_error,
                dut.u_operator.scratch_init_valid && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_active && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_p0_valid && dut.u_operator.execution_active,
                dut.u_operator.scratch_load_p1_valid && dut.u_operator.execution_active,
                dut.u_operator.support_scalar_mode &&
                    (dut.u_operator.cfg_a_data[31:16] < dut.u_operator.resident_count),
                dut.u_operator.vector_candidate_mode && dut.u_operator.vector_candidate_fault,
                (dut.u_operator.phi_mode == 3'd3) &&
                    dut.u_operator.phi_consume_context && dut.u_operator.vec_a_en &&
                    ((dut.u_operator.ext_a_sel != `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ||
                     !dut.u_operator.cfg_a_valid ||
                     (dut.u_operator.cfg_a_data[54:52] != `RECON_ELEMENT_FORMAT_SOLVER27) ||
                     (dut.u_operator.cfg_a_data[57:55] != `RECON_PACKING_MODE_TWO) ||
                     (dut.u_operator.cfg_a_data[31:16] <
                      dut.u_operator.u_fault_encoder.padded_measurement_count) ||
                     (|dut.u_operator.cfg_a_data[20:16])),
                dut.u_operator.reduction_issue_context &&
                    !dut.u_operator.u_column_flow.completed_column_valid,
                dut.u_operator.reduction_accept &&
                    !dut.u_operator.u_column_flow.completed_column_valid,
                dut.u_operator.u_column_flow.phi_metadata_error_now,
                dut.u_operator.u_column_flow.row_major_metadata_error_now,
                dut.u_operator.u_column_flow.row_major_incomplete_stop,
                dut.u_operator.u_column_flow.phi_order_error,
                dut.u_operator.phi_cache_fault,
                dut.u_operator.u_column_flow.completed_column_valid,
                dut.u_operator.phi_column,
                dut.u_operator.phi_row_block);
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_operator.cycle_valid &&
            (dut.u_array_context_sequencer.pc == 8'd255)) begin
            $display("E2E FRESH MARKER commit=%b clear=%b active=%b operation=%0d cfg=%0d boundary=%0d",
                dut.u_operator.cycle_commit,
                dut.scalar_state_clear,
                dut.u_operator.u_support_refinement.fresh_refinement_active,
                dut.u_operator.resource_operation,
                dut.u_operator.resource_configuration_id,
                dut.u_operator.resource_stream_boundary);
        end
        if (rst_n && dut.u_operator.cycle_valid &&
            dut.u_operator.cycle_commit && dut.u_operator.vec_w_en &&
            dut.u_operator.write_is_d18 && (e2e_algorithm == 2))
            $display("E2E RESIDUAL WRITE VECTOR %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                $signed(dut.u_operator.cgra_result_buffer[0*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[1*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[2*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[3*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[4*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[5*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[6*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[7*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[8*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[9*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[10*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[11*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[12*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[13*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[14*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[15*27 +: 27]));
        if (rst_n && dut.u_operator.u_dispatcher.cycle_valid &&
            dut.u_operator.u_dispatcher.topk_owned &&
            dut.u_operator.u_dispatcher.push_context &&
            dut.u_operator.u_dispatcher.candidate_valid &&
            ((dut.u_operator.u_dispatcher.candidate_index == 10'd9) ||
             (dut.u_operator.u_dispatcher.candidate_index == 10'd2) ||
             (dut.u_operator.u_dispatcher.candidate_index == 10'd16) ||
             (dut.u_operator.u_dispatcher.candidate_index == 10'd17) ||
             (dut.u_operator.u_dispatcher.candidate_index == 10'd19) ||
             (dut.u_operator.u_dispatcher.candidate_index == 10'd22))) begin
            $display("E2E GRADIENT candidate=%0d score=%0d cfg=%0d issue=%b pending=%b lookup=%b match=%b member=%b slot=%0d ready=%b grad_enable=%b grad_valid=%b",
                dut.u_operator.u_dispatcher.candidate_index,
                $signed(dut.u_operator.u_dispatcher.candidate_score),
                dut.u_operator.u_dispatcher.configuration_id,
                dut.u_operator.u_dispatcher.issue_fire,
                dut.u_operator.u_dispatcher.pending_valid,
                dut.u_operator.u_dispatcher.candidate_membership_valid,
                dut.u_operator.u_dispatcher.candidate_membership_matches,
                dut.u_operator.u_dispatcher.candidate_membership_member,
                dut.u_operator.u_dispatcher.candidate_membership_slot,
                dut.u_operator.u_dispatcher.topk_request_ready,
                dut.u_operator.u_dispatcher.support_gradient_capture_enabled,
                dut.u_operator.u_dispatcher.u_collector.gradient_valid);
        end
        if (rst_n && dut.u_operator.cycle_valid &&
            ((dut.u_array_context_sequencer.pc == 8'd55) ||
             (dut.u_array_context_sequencer.pc == 8'd56))) begin
            $display("E2E CURSOR pc=%0d commit=%b restart_ctx=%b restart_valid=%b ready=%b mask=%b a_active=%b a_id=%0d remain=%0d inflight=%b held=%b req=%b",
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_commit,
                dut.u_operator.u_dispatcher.restart_context,
                dut.u_operator.cursor_restart_valid,
                dut.u_operator.cursor_restart_ready,
                dut.u_operator.cursor_restart_mask,
                dut.u_operator.u_stream_engine.a_active,
                dut.u_operator.u_stream_engine.a_configuration_id,
                dut.u_operator.u_stream_engine.a_remaining_elements,
                dut.u_operator.u_stream_engine.a_inflight,
                dut.u_operator.u_stream_engine.a_response_held,
                dut.u_operator.vec_req_valid);
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_operator.stream_contract_error) begin
            $display("E2E STREAM ERROR phase_pc=%0d array_pc=%0d local=%b cfg=%b conflict=%b vec_en=%b%b%b cfg_id=%0d/%0d/%0d cfg_valid=%b%b%b active=%b%b%b active_id=%0d/%0d/%0d id_match=%b%b%b cfg_legal=%b%b%b remain=%0d/%0d/%0d",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.u_operator.u_cgra_fabric.u_router.local_error,
                dut.u_operator.vec_cfg_error,
                dut.u_operator.vec_access_conflict,
                dut.u_operator.vec_a_en, dut.u_operator.vec_b_en,
                dut.u_operator.vec_w_en,
                dut.u_operator.vec_cfg_a, dut.u_operator.vec_cfg_b,
                dut.u_operator.vec_cfg_w,
                dut.u_operator.cfg_a_valid, dut.u_operator.cfg_b_valid,
                dut.u_operator.cfg_w_valid,
                dut.u_operator.u_stream_engine.a_active,
                dut.u_operator.u_stream_engine.b_active,
                dut.u_operator.u_stream_engine.w_active,
                dut.u_operator.u_stream_engine.a_configuration_id,
                dut.u_operator.u_stream_engine.b_configuration_id,
                dut.u_operator.u_stream_engine.w_configuration_id,
                dut.u_operator.u_stream_engine.a_id_matches,
                dut.u_operator.u_stream_engine.b_id_matches,
                dut.u_operator.u_stream_engine.w_id_matches,
                dut.u_operator.u_stream_engine.a_cfg_legal,
                dut.u_operator.u_stream_engine.b_cfg_legal,
                dut.u_operator.u_stream_engine.w_cfg_legal,
                dut.u_operator.u_stream_engine.a_remaining_elements,
                dut.u_operator.u_stream_engine.b_remaining_elements,
                dut.u_operator.u_stream_engine.w_remaining_elements);
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_operator.cycle_valid &&
            dut.u_operator.cycle_commit &&
            (dut.u_operator.resource_operation ==
             `RECON_RESOURCE_OP_SUPPORT_UNION)) begin
            $display("E2E UNION phase=%0d selection=%0d candidates=%0d,%0d,%0d,%0d active_count=%0d active=%0d,%0d,%0d,%0d proposed_count=%0d",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_operator.selection_count,
                dut.u_operator.result_indices[0*10 +: 10],
                dut.u_operator.result_indices[1*10 +: 10],
                dut.u_operator.result_indices[2*10 +: 10],
                dut.u_operator.result_indices[3*10 +: 10],
                dut.u_operator.active_support_count,
                dut.u_operator.active_support_indices[0*10 +: 10],
                dut.u_operator.active_support_indices[1*10 +: 10],
                dut.u_operator.active_support_indices[2*10 +: 10],
                dut.u_operator.active_support_indices[3*10 +: 10],
                dut.u_operator.u_dispatcher.u_support.proposed_count);
        end
        if (rst_n && dut.u_operator.cycle_valid &&
            dut.u_operator.cycle_commit &&
            (dut.u_operator.resource_operation == 5'd12) &&
            !dut.u_operator.resource_wait_for_result) begin
            $display("E2E SCATTER COMMIT phase=%0d pc=%0d support=%0d candidate=%b score=%0d index=%0d source_index=%0d final=%b serializer_count=%0d buffer=%b physical=%b",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.final_support_count,
                dut.u_operator.vector_candidate_valid,
                $signed(dut.u_operator.vector_candidate_score),
                dut.u_operator.vector_candidate_index,
                dut.u_operator.u_candidate_stream.source_index,
                dut.u_operator.vector_candidate_final_lane,
                dut.u_operator.u_candidate_stream.u_serializer.item_count,
                dut.u_operator.u_candidate_stream.u_serializer.buffer_valid,
                dut.u_operator.physical_vec_a_valid);
        end
        if (rst_n && dut.u_operator.cycle_valid &&
            (dut.u_array_context_sequencer.pc >= 8'd37) &&
            (dut.u_array_context_sequencer.pc <= 8'd46)) begin
            $display("E2E INIT pc=%0d commit=%b restart=%b/%b/%b fresh=%b zero=%b support_count=%0d idx0=%0d coeff0=%0d grad_valid=%h grad0=%0d masked0=%0d selected0=%0d vector0=%0d result_valid=%b lane_valid=%h write_en=%b write_cfg=%0d stream_active=%b%b%b stream_id=%0d/%0d/%0d remain=%0d/%0d/%0d",
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_commit,
                dut.u_operator.cursor_restart_valid,
                dut.u_operator.cursor_restart_ready,
                dut.u_operator.cursor_restart_mask,
                dut.u_operator.u_support_refinement.fresh_refinement_active,
                dut.u_operator.u_support_refinement.fresh_refinement_zero_estimate,
                dut.u_operator.active_support_count,
                dut.u_operator.active_support_indices[9:0],
                $signed(dut.u_operator.active_support_coefficients[`RECON_SOLVER_W-1:0]),
                dut.u_operator.active_support_gradient_valid[15:0],
                $signed(dut.u_operator.active_support_gradients[`RECON_SOLVER_W-1:0]),
                $signed(dut.u_operator.u_support_refinement.masked_vector_result_data[`RECON_SOLVER_W-1:0]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[`RECON_SOLVER_W-1:0]),
                $signed(dut.u_operator.vector_result_data[`RECON_SOLVER_W-1:0]),
                dut.u_operator.vector_result_valid,
                dut.u_operator.vector_result_lane_valid,
                dut.u_operator.vec_w_en,
                dut.u_operator.vec_cfg_w,
                dut.u_operator.u_stream_engine.a_active,
                dut.u_operator.u_stream_engine.b_active,
                dut.u_operator.u_stream_engine.w_active,
                dut.u_operator.u_stream_engine.a_configuration_id,
                dut.u_operator.u_stream_engine.b_configuration_id,
                dut.u_operator.u_stream_engine.w_configuration_id,
                dut.u_operator.u_stream_engine.a_remaining_elements,
                dut.u_operator.u_stream_engine.b_remaining_elements,
                dut.u_operator.u_stream_engine.w_remaining_elements);
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_operator.cycle_valid &&
            (dut.u_array_context_sequencer.pc == 8'd18)) begin
            $display("E2E PC18 commit=%b in_ready=%b vec_valid=%b lane_valid=%h capture=%b pack_valid=%b scalar_valid=%b scalar=%0d ext0=%0d phi_valid=%b phi_nz=%h phi_sign=%h",
                dut.u_operator.cycle_commit,
                dut.u_operator.stream_input_ready,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.sidecar_valid_a,
                dut.u_operator.u_vector_ingress.support_capture,
                dut.u_operator.u_vector_ingress.support_pack_valid,
                dut.u_operator.u_vector_ingress.support_valid,
                $signed(dut.u_operator.u_vector_ingress.support_data),
                $signed(dut.u_operator.external_input_a[`RECON_SOLVER_W-1:0]),
                dut.u_operator.phi_symbol_valid,
                dut.u_operator.phi_nonzero,
                dut.u_operator.phi_sign);
        end
    end

    always @(posedge clk) begin
        if (rst_n && engine_busy &&
            ((dut.u_array_context_sequencer.pc == 8'd233) ||
             (dut.u_array_context_sequencer.pc == 8'd236))) begin
            $display("E2E D18 SPLIT pc=%0d commit=%b mode=%b capture=%b valid=%b high=%b base=%0d physical=%b lane_valid=%h data0=%0d scalar1=%0d",
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_commit,
                dut.u_operator.d18_split_mode,
                dut.u_operator.u_vector_ingress.d18_capture,
                dut.u_operator.d18_split_valid,
                dut.u_operator.u_vector_ingress.d18_high_half,
                dut.u_operator.u_vector_ingress.d18_base,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.d18_split_lane_valid,
                $signed(dut.u_operator.d18_split_solver_data[0 +: 27]),
                $signed(dut.u_operator.m5_scalar1_data));
            if (dut.u_operator.cycle_commit && dut.u_operator.d18_split_mode &&
                !dut.u_operator.u_vector_ingress.d18_high_half)
                $display("E2E RESIDUAL VECTOR iter=%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.outer_iter,
                    $signed(dut.u_operator.d18_split_solver_data[0*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[1*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[2*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[3*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[4*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[5*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[6*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[7*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[8*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[9*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[10*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[11*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[12*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[13*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[14*27 +: 27]) >>> 5,
                    $signed(dut.u_operator.d18_split_solver_data[15*27 +: 27]) >>> 5);
        end
        if (rst_n && engine_busy && dut.u_operator.cycle_valid &&
            (dut.u_operator.active_tile_operation ==
             `RECON_TILE_OP_PHI_DATA_ACCUMULATE)) begin
            $display("E2E PHI DATA ACC iter=%0d commit=%b coeff=%0d phi0=%b/%b acc0=%0d",
                dut.outer_iter, dut.u_operator.cycle_commit,
                $signed(dut.u_operator.external_input_a[0 +: 27]),
                dut.u_operator.phi_nonzero[0], dut.u_operator.phi_sign[0],
                $signed(dut.u_operator.lane_accumulator[0 +: 48]));
        end
        if (rst_n && engine_busy &&
            dut.u_operator.u_phi_lane_flow.capture_event &&
            (dut.u_operator.active_tile_operation ==
             `RECON_TILE_OP_PHI_RESIDUAL_CAPTURE)) begin
            $display("E2E PHI DATA CAP iter=%0d acc0=%0d meas0=%0d",
                dut.outer_iter,
                $signed(dut.u_operator.lane_accumulator[0 +: 48]),
                $signed(dut.u_operator.external_input_a[0 +: 27]));
        end
        if (rst_n && engine_busy &&
            dut.u_operator.u_phi_lane_flow.lane_output_fire &&
            dut.u_operator.u_phi_lane_flow.residual_mode) begin
            $display("E2E PHI DATA OUT iter=%0d lane=%0d acc=%0d fit=%0d meas=%0d",
                dut.outer_iter, dut.u_operator.normalizer_output_tag[4:0],
                $signed(dut.u_operator.u_phi_lane_flow.selected_accumulator),
                $signed(dut.u_operator.normalizer_output_data),
                $signed(dut.u_operator.u_phi_lane_flow.measurement_buffer[
                    dut.u_operator.normalizer_output_tag[4:0]*27 +: 27]));
        end
        if (rst_n && engine_busy && (e2e_algorithm == 1) &&
            dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
            dut.u_operator.vec_w_en &&
            (dut.u_operator.vec_cfg_w == 6'd16) &&
            dut.u_operator.cgra_result_available &&
            !dut.u_operator.u_cgra_fabric.u_result_buffer.s27_high_select) begin
            $display("E2E PCG D iter=%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.solver_iter,
                $signed(dut.u_operator.cgra_result_buffer[0*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[1*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[2*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[3*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[4*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[5*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[6*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[7*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[8*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[9*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[10*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[11*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[12*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[13*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[14*27 +: 27]),
                $signed(dut.u_operator.cgra_result_buffer[15*27 +: 27]));
        end
        if (rst_n && engine_busy && dut.u_operator.cycle_valid &&
            ((dut.u_array_context_sequencer.pc == 8'd89) ||
             (dut.u_array_context_sequencer.pc == 8'd90))) begin
            $display("E2E RESTART COPY pc=%0d commit=%b routine=%b vec_req=%b vec_commit=%b raw=%b/%b side=%h m5=%b/%b ready=%b/%b vreq=%b/%b vrsp=%b tag=%0d pending=%b ptag=%0d result=%b rready=%b w=%b rem=%0d exh=%b",
                dut.u_array_context_sequencer.pc, dut.u_operator.cycle_commit,
                dut.u_operator.run_start, dut.u_operator.vec_req_valid,
                dut.u_operator.vec_transport_commit,
                dut.u_operator.raw_vec_in_ready,
                dut.u_operator.raw_vec_out_ready,
                dut.u_operator.sidecar_valid_a,
                dut.u_operator.m5_cycle_valid,
                dut.u_operator.m5_cycle_commit,
                dut.u_operator.m5_resource_in_ready,
                dut.u_operator.m5_resource_out_ready,
                dut.u_operator.u_m5.vector_req_valid,
                dut.u_operator.u_m5.vector_req_ready,
                dut.u_operator.u_m5.vector_rsp_valid,
                dut.u_operator.u_m5.vector_rsp_tag,
                dut.u_operator.u_m5.router.pending_valid[2],
                dut.u_operator.u_m5.router.pending_tag[2],
                dut.u_operator.vector_result_valid,
                dut.u_operator.m5_vector_result_ready,
                dut.u_operator.u_stream_engine.w_active,
                dut.u_operator.u_stream_engine.w_remaining_elements,
                dut.u_operator.u_stream_engine.w_exhausted);
        end
        if (rst_n && engine_busy &&
            ((e2e_algorithm == 0) || (e2e_algorithm == 1)) &&
            dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
            dut.u_operator.vec_w_en &&
            (dut.u_operator.vec_cfg_w == 6'd18) &&
            dut.u_operator.transpose_write_mode &&
            dut.u_operator.transpose_write_final) begin
            $display("E2E PCG G iter=%0d %0d %0d %0d %0d",
                dut.solver_iter,
                $signed(dut.u_operator.u_normalized_writeback.scalar_pack[0*27 +: 27]),
                $signed(dut.u_operator.u_normalized_writeback.scalar_pack[1*27 +: 27]),
                $signed(dut.u_operator.u_normalized_writeback.scalar_pack[2*27 +: 27]),
                $signed(dut.u_operator.u_normalized_writeback.scalar_pack[3*27 +: 27]));
        end
        if (rst_n && engine_busy && (e2e_algorithm == 1) &&
            dut.u_operator.cycle_valid && dut.u_operator.cycle_commit &&
            dut.u_operator.vec_w_en &&
            ((dut.u_operator.vec_cfg_w == 6'd17) ||
             (dut.u_operator.vec_cfg_w == 6'd20)) &&
            !dut.u_operator.cgra_result_available &&
            !dut.u_operator.transpose_write_mode) begin
            $display("E2E PCG V cfg=%0d iter=%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.u_operator.vec_cfg_w, dut.solver_iter,
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[0*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[1*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[2*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[3*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[4*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[5*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[6*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[7*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[8*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[9*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[10*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[11*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[12*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[13*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[14*27 +: 27]),
                $signed(dut.u_operator.u_support_refinement.selected_vector_result_data[15*27 +: 27]));
        end
        if (rst_n && engine_busy &&
            ((e2e_algorithm == 0) || (e2e_algorithm == 1)) &&
            dut.u_operator.normalizer_output_valid &&
            dut.u_operator.transpose_normalizer_ready) begin
            $display("E2E PCG TRANSPOSE OUT iter=%0d tag=%0d data=%0d pack=%0d count=%0d",
                dut.solver_iter, dut.u_operator.normalizer_output_tag,
                $signed(dut.u_operator.normalizer_output_data),
                dut.u_operator.u_normalized_writeback.pack_index,
                dut.u_operator.u_normalized_writeback.output_count);
        end
        if (rst_n && engine_busy &&
            ((e2e_algorithm == 1) || (e2e_algorithm == 2)) &&
            dut.u_operator.cycle_valid &&
            (dut.u_operator.resource_operation ==
             `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY)) begin
            $display("E2E PCG AXPY pc=%0d iter=%0d commit=%b ready=%b cfga=%0d cfgb=%0d scalar=%0d a0=%0d a1=%0d a2=%0d a3=%0d b0=%0d b1=%0d b2=%0d b3=%0d",
                dut.u_array_context_sequencer.pc, dut.solver_iter,
                dut.u_operator.m5_cycle_commit,
                dut.u_operator.m5_resource_in_ready,
                dut.u_operator.vec_cfg_a, dut.u_operator.vec_cfg_b,
                $signed(dut.u_operator.scalar_broadcast_data),
                $signed(dut.u_operator.sidecar_vec_a[0*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_a[1*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_a[2*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_a[3*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_b[0*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_b[1*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_b[2*27 +: 27]),
                $signed(dut.u_operator.sidecar_vec_b[3*27 +: 27]));
        end
        if (rst_n && dut.u_lifecycle.u_phase_controller.trace_valid) begin
            $display("E2E PHASE TRACE pc=%0d op=%0d condition=%b support=%0d solver_fault=%b converged=%b iter=%0d/%0d scalar_valid=%b%b scalar=%0d/%0d",
                dut.u_lifecycle.u_phase_controller.trace_phase_pc,
                dut.u_lifecycle.u_phase_controller.trace_operation,
                dut.u_lifecycle.u_phase_controller.trace_condition,
                dut.final_support_count,
                dut.solver_fault,
                dut.solver_converged,
                dut.outer_iter,
                dut.solver_iter,
                dut.u_operator.m5_scalar1_valid,
                dut.u_operator.m5_scalar0_valid,
                $signed(dut.u_operator.m5_scalar0_data),
                $signed(dut.u_operator.m5_scalar1_data));
        end
        if (rst_n && dut.refinement_event_valid) begin
            $display("E2E REFINEMENT pass=%b restart=%b stop=%0d support=%0d m5_fault=%b m5_sat=%b scalar_valid=%b%b scalar=%0d/%0d",
                dut.refinement_certificate_pass,
                dut.refinement_restart_required,
                dut.refinement_stop_reason,
                dut.final_support_count,
                dut.u_operator.m5_fault_valid,
                dut.u_operator.m5_saturation_event,
                dut.u_operator.m5_scalar1_valid,
                dut.u_operator.m5_scalar0_valid,
                $signed(dut.u_operator.m5_scalar0_data),
                $signed(dut.u_operator.m5_scalar1_data));
        end
        if (rst_n && dut.u_lifecycle.phase_error_pulse) begin
            $display("E2E PHASE ERROR class=%0d code=%0d phase=%0d cfg_word=%0d detail=%08x support=%0d solver_fault=%b operator_fault=%b remap_fault=%b",
                dut.u_lifecycle.phase_error_class,
                dut.u_lifecycle.phase_error_code,
                dut.u_lifecycle.phase_error_phase,
                dut.u_lifecycle.phase_cfg_error_word,
                dut.u_lifecycle.phase_error_detail,
                dut.final_support_count,
                dut.solver_fault,
                operator_fault,
                dut.support_remap_event_fault);
        end
        if (rst_n && dut.u_lifecycle.csr_error_pulse) begin
            $display("E2E CSR ERROR class=%0d code=%0d phase=%0d cfg_word=%0d detail=%08x",
                dut.u_lifecycle.csr_error_class,
                dut.u_lifecycle.csr_error_code,
                dut.u_lifecycle.csr_error_phase,
                dut.u_lifecycle.csr_cfg_error_word,
                dut.u_lifecycle.csr_error_detail);
        end
        if (rst_n && engine_busy && (E2E_M == 64) &&
                (E2E_N == 128) && (e2e_algorithm == 0) &&
                dut.u_operator.u_m5.vector_req_valid &&
                dut.u_operator.u_m5.vector_req_ready &&
                (|dut.u_operator.u_m5.vector_req_lane_valid) &&
                (((^dut.u_operator.u_m5.vector_req_a) === 1'bx) ||
                 ((((dut.u_operator.u_m5.vector_req_operation ==
                      `RECON_RESOURCE_OP_SHARED_VECTOR_DOT) ||
                     (dut.u_operator.u_m5.vector_req_operation ==
                      `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY)) &&
                    ((^dut.u_operator.u_m5.vector_req_b) === 1'bx))) ||
                 (((dut.u_operator.u_m5.vector_req_operation ==
                    `RECON_RESOURCE_OP_SHARED_VECTOR_SCALE) ||
                   (dut.u_operator.u_m5.vector_req_operation ==
                    `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY)) &&
                  ((^dut.u_operator.u_m5.vector_req_scalar) === 1'bx)))) begin
            $display("E2E FIRST X REQUEST phase=%0d pc=%0d outer=%0d solver=%0d op=%0d cfga=%0d cfgb=%0d lane=%h a_x=%b b_x=%b scalar_x=%b",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.outer_iter, dut.solver_iter,
                dut.u_operator.u_m5.vector_req_operation,
                dut.u_operator.vec_cfg_a, dut.u_operator.vec_cfg_b,
                dut.u_operator.u_m5.vector_req_lane_valid,
                ((^dut.u_operator.u_m5.vector_req_a) === 1'bx),
                ((^dut.u_operator.u_m5.vector_req_b) === 1'bx),
                ((^dut.u_operator.u_m5.vector_req_scalar) === 1'bx));
            $finish;
        end
        if (rst_n && engine_busy && (E2E_M == 64) &&
                (E2E_N == 128) && (e2e_algorithm == 0) &&
                (dut.outer_iter >= 6) &&
                dut.u_operator.u_stream_engine.perform_write &&
                (dut.u_operator.vec_cfg_w == 6'd18)) begin
            $display("E2E CFG18 WRITE phase=%0d pc=%0d solver=%0d addr=%h pack=%h data=%h",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc, dut.solver_iter,
                dut.u_operator.u_stream_engine.w_issue_address,
                dut.u_operator.u_normalized_writeback.scalar_pack,
                dut.u_operator.u_vector_codec.write_data);
        end
        if (rst_n && engine_busy && (E2E_M == 64) &&
                (E2E_N == 128) && (e2e_algorithm == 0) &&
                (dut.outer_iter >= 6) &&
                dut.u_operator.physical_vec_a_valid &&
                (dut.u_operator.vec_cfg_a == 6'd18)) begin
            $display("E2E CFG18 READ phase=%0d pc=%0d solver=%0d addr=%h physical=%h side=%h valid=%h",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc, dut.solver_iter,
                dut.u_operator.u_stream_engine.a_issue_address,
                dut.u_operator.physical_vec_a,
                dut.u_operator.sidecar_vec_a,
                dut.u_operator.sidecar_valid_a);
        end
        if (rst_n && engine_busy && (E2E_M == 64) &&
                (E2E_N == 128) && (e2e_algorithm == 0) &&
                dut.u_operator.u_stream_engine.perform_write &&
                ((^dut.u_operator.u_vector_codec.write_data) === 1'bx)) begin
            $display("E2E FIRST X WRITE phase=%0d pc=%0d outer=%0d solver=%0d cfgw=%0d source_vec=%b cgra=%b transpose=%b d18=%b",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.outer_iter, dut.solver_iter,
                dut.u_operator.vec_cfg_w,
                dut.u_operator.vector_result_valid,
                dut.u_operator.cgra_result_available,
                dut.u_operator.transpose_write_mode,
                dut.u_operator.d18_split_mode);
            $finish;
        end
        if (rst_n && dut.u_operator.cycle_valid &&
                (dut.u_array_context_sequencer.pc >= 8'd53) &&
                (dut.u_array_context_sequencer.pc <= 8'd58) &&
                (dut.outer_iter == 0) && (dut.solver_iter == 0) &&
                (dut.u_operator.cycle_commit ||
                 dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_delay_valid ||
                 dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_out_valid)) begin
            $display("E2E NORM pc=%0d commit=%b physical=%b raw_ready=%b cfga=%0d cfgfmt=%0d/%0d op=%0d clear=%b accum=%b emit=%b req=%b/%b lane=%h delay=%b/%b/%b/%0d acc=%0d out=%b/%0d scalar1=%0d loop=%0d",
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_commit,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.raw_vec_in_ready,
                dut.u_operator.vec_cfg_a,
                dut.u_operator.cfg_a_data[54:52],
                dut.u_operator.cfg_a_data[57:55],
                dut.u_operator.u_m5.vector_req_operation,
                dut.u_operator.u_m5.vector_req_clear_before,
                dut.u_operator.u_m5.vector_req_accumulate,
                dut.u_operator.u_m5.vector_req_emit_result,
                dut.u_operator.u_m5.vector_req_valid,
                dut.u_operator.u_m5.vector_req_ready,
                dut.u_operator.u_m5.vector_req_lane_valid,
                dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_delay_valid,
                dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_delay_clear_before,
                dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_delay_accumulate,
                $signed(dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_delay),
                $signed(dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_accumulator),
                dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_out_valid,
                $signed(dut.u_operator.u_m5.vector_arithmetic.u_unit.dot_out_data),
                $signed(dut.u_operator.m5_scalar1_data),
                dut.u_array_context_sequencer.loop_count[0]);
        end
        if (rst_n && dut.u_operator.cycle_valid &&
                ((dut.u_array_context_sequencer.pc == 8'd48) ||
                 ((dut.u_array_context_sequencer.pc >= 8'd59) &&
                  (dut.u_array_context_sequencer.pc <= 8'd66)))) begin
            $display("E2E SOLVER VECTOR pc=%0d commit=%b a_valid=%b b_valid=%b lane_valid=%h a0=%0d b0=%0d scalar0=%0d scalar1=%0d req=%b/%b op=%0d req_scalar=%0d result_valid=%b result0=%0d rsp_sat=%h sat_event=%b",
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_commit,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.physical_vec_b_valid,
                dut.u_operator.sidecar_valid_a | dut.u_operator.sidecar_valid_b,
                $signed(dut.u_operator.sidecar_vec_a[`RECON_SOLVER_W-1:0]),
                $signed(dut.u_operator.sidecar_vec_b[`RECON_SOLVER_W-1:0]),
                $signed(dut.u_operator.m5_scalar0_data),
                $signed(dut.u_operator.m5_scalar1_data),
                dut.u_operator.u_m5.vector_req_valid,
                dut.u_operator.u_m5.vector_req_ready,
                dut.u_operator.u_m5.vector_req_operation,
                $signed(dut.u_operator.u_m5.vector_req_scalar),
                dut.u_operator.vector_result_valid,
                $signed(dut.u_operator.vector_result_data[`RECON_SOLVER_W-1:0]),
                dut.u_operator.u_m5.vector_rsp_saturated,
                dut.u_operator.m5_saturation_event);
        end
    end

    genvar diagnostic_cluster;
    genvar diagnostic_row;
    genvar diagnostic_lane;
    generate
        for (diagnostic_cluster = 0;
             diagnostic_cluster < `RECON_CLUSTER_COUNT;
             diagnostic_cluster = diagnostic_cluster + 1) begin : g_e2e_cluster_diagnostic
            for (diagnostic_row = 0;
                 diagnostic_row < `RECON_PE_ROWS;
                 diagnostic_row = diagnostic_row + 1) begin : g_e2e_row_diagnostic
                for (diagnostic_lane = 0;
                     diagnostic_lane < `RECON_PE_COLUMNS;
                     diagnostic_lane = diagnostic_lane + 1) begin : g_e2e_lane_diagnostic
                    always @(posedge clk) begin
                        if (rst_n &&
                            dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                .g_row[diagnostic_row].cluster_row
                                .g_tile[diagnostic_lane].tile.state_write_enable &&
                            dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                .g_row[diagnostic_row].cluster_row
                                .g_tile[diagnostic_lane].tile.alu_saturated) begin
                            $display("E2E PE SAT cluster=%0d row=%0d lane=%0d pe=%0d phase_pc=%0d array_pc=%0d op=%0d acc=%0d data_a=%0d ext_a=%0d phi_nz=%b phi_sign=%b result=%0d",
                                diagnostic_cluster, diagnostic_row, diagnostic_lane,
                                diagnostic_cluster*`RECON_PE_PER_CLUSTER +
                                    diagnostic_row*`RECON_PE_COLUMNS + diagnostic_lane,
                                dut.u_lifecycle.u_phase_controller.phase_pc,
                                dut.u_array_context_sequencer.pc,
                                dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.operation,
                                $signed(dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.accumulator_reg),
                                $signed(dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.data_operand_a),
                                $signed(dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.external_input_a),
                                dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.phi_nonzero,
                                dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.phi_sign,
                                $signed(dut.u_operator.u_cgra_fabric.u_clusters.g_cluster[diagnostic_cluster].cluster_array
                                    .g_row[diagnostic_row].cluster_row
                                    .g_tile[diagnostic_lane].tile.alu_result));
                        end
                    end
                end
            end
        end
    endgenerate
`endif

    task automatic load_e2e_resident_image;
        integer address;
        integer phase_pc;
        begin
            for (address = 0; address < E2E_ARRAY_CONTEXT_COUNT;
                 address = address + 1) begin
                image_write(4'd0, address[7:0], e2e_plane_0[address]);
                image_write(4'd1, address[7:0], e2e_plane_1[address]);
                image_write(4'd2, address[7:0], e2e_plane_2[address]);
                image_write(4'd3, address[7:0], e2e_plane_3[address]);
                image_write(4'd4, address[7:0], e2e_plane_4[address]);
                image_write(4'd5, address[7:0], e2e_plane_5[address]);
                image_write(4'd6, address[7:0], e2e_plane_6[address]);
                image_write(4'd7, address[7:0], e2e_plane_7[address]);
                image_write(4'd9, address[7:0], e2e_plane_9[address]);
                image_write(4'd8, address[7:0], e2e_plane_8[address]);
            end
            for (phase_pc = 0;
                    phase_pc < E2E_PHASE_LEN[e2e_algorithm*8 +: 8];
                    phase_pc = phase_pc + 1)
                image_write(`RECON_PHASE_INSTRUCTION_COMMIT_PLANE,
                    phase_pc[7:0], {36'd0, e2e_phase_words[phase_pc]});
            finalize_image();
        end
    endtask

    task automatic load_e2e_memory_configurations;
        integer configuration_id;
        begin
            for (configuration_id = 0; configuration_id < 64;
                    configuration_id = configuration_id + 1)
                if (e2e_memory_configurations[configuration_id] != 64'd0)
                    memory_configuration_write(configuration_id[5:0],
                        e2e_memory_configurations[configuration_id]);
        end
    endtask

    task automatic issue_e2e_preload;
        integer preload_step;
        integer preload_id;
        reg [31:0] status;
        reg [63:0] configuration;
        begin
            for (preload_step = 0; preload_step < 3;
                 preload_step = preload_step + 1) begin
                preload_id = (preload_step < 2) ? preload_step : 20;
                configuration = e2e_memory_configurations[preload_id];
                configuration[31:16] = E2E_M;
                configuration[63] = preload_id == 20;
                loader_write(`RECON_LOADER_CSR_PRELOAD_SRC_LO,
                    E2E_MEAS_ADDR[31:0], `AXI_RESP_OKAY);
                loader_write(`RECON_LOADER_CSR_PRELOAD_SRC_HI,
                    E2E_MEAS_ADDR[63:32], `AXI_RESP_OKAY);
                loader_write(`RECON_LOADER_CSR_PRELOAD_META,
                    preload_id, `AXI_RESP_OKAY);
                loader_write(`RECON_LOADER_CSR_PRELOAD_CFG_LO,
                    configuration[31:0], `AXI_RESP_OKAY);
                loader_write(`RECON_LOADER_CSR_PRELOAD_CFG_HI,
                    configuration[63:32], `AXI_RESP_OKAY);
                loader_write(`RECON_LOADER_CSR_COMMAND,
                    `RECON_LOADER_COMMAND_SCRATCH_PRELOAD, `AXI_RESP_OKAY);
                loader_read(`RECON_LOADER_CSR_STATUS, status);
                check(status[0], "end-to-end input preload busy");
                loader_wait_completion(`RECON_LOADER_COMMAND_SCRATCH_PRELOAD,
                    "end-to-end input preload completion");
            end
        end
    endtask

    function automatic [127:0] e2e_expected_dense_beat;
        input integer algorithm;
        input integer beat;
        integer lane;
        reg [127:0] value;
        begin
            value = 128'd0;
            for (lane = 0; lane < 4; lane = lane + 1)
                value[lane*32 +: 32] = E2E_DENSE_LANES[
                    (algorithm*E2E_N + beat*4 + lane)*32 +: 32];
            e2e_expected_dense_beat = value;
        end
    endfunction

    function automatic [127:0] e2e_expected_sparse_beat;
        input integer algorithm;
        input integer beat;
        integer lane;
        integer slot;
        reg [127:0] value;
        reg [9:0] index;
        reg [31:0] coefficient;
        begin
            value = 128'd0;
            for (lane = 0; lane < 2; lane = lane + 1) begin
                slot = beat*2 + lane;
                index = E2E_SUPPORT_INDEX[
                    (algorithm*E2E_SUPPORT_SLOTS + slot)*10 +: 10];
                coefficient = E2E_SUPPORT_COEFF[
                    (algorithm*E2E_SUPPORT_SLOTS + slot)*32 +: 32];
                value[lane*64 +: 64] = {22'd0, index, coefficient};
            end
            e2e_expected_sparse_beat = value;
        end
    endfunction

    task automatic check_e2e_result;
        integer beat;
        integer slot;
        integer sparse_beats;
        integer header_beat;
        reg [7:0] expected_count;
        reg [9:0] expected_index;
        reg [31:0] expected_coefficient;
        reg signed [31:0] expected_residual;
        reg [127:0] expected_header;
        reg [12:0] expected_dense_bytes;
        reg [10:0] expected_sparse_bytes;
        begin
            expected_count = E2E_SUPPORT_COUNT[e2e_case_index*8 +: 8];
            sparse_beats = (expected_count + 1) >> 1;
            header_beat = E2E_DENSE_BEATS + sparse_beats;
            $display("E2E RESULT actual_count=%0d expected_count=%0d stop_reason=%0d writes=%0d/%0d benchmark=%0d",
                final_support_count, expected_count,
                dut.u_lifecycle.terminal_stop_reason,
                write_bursts, write_beats, E2E_BENCHMARK_MODE);
            for (slot = 0; slot < expected_count; slot = slot + 1)
                $display("E2E RESULT SLOT %0d actual_idx=%0d expected_idx=%0d actual_coeff=%0d expected_coeff=%0d",
                    slot,
                    final_support_indices[slot*10 +: 10],
                    E2E_SUPPORT_INDEX[
                        (e2e_case_index*E2E_SUPPORT_SLOTS + slot)*10 +: 10],
                    $signed(final_support_coefficients[slot*`RECON_SOLVER_W +:
                        `RECON_SOLVER_W]),
                    $signed(E2E_SUPPORT_COEFF[
                        (e2e_case_index*E2E_SUPPORT_SLOTS + slot)*32 +:
                        `RECON_SOLVER_W]));
            if (E2E_BENCHMARK_MODE) begin
                check(dut.u_lifecycle.terminal_stop_reason ==
                        `RECON_STOP_ITERATION_LIMIT,
                    "force-iter run stops on iteration limit");
                check(e2e_outer_iteration_events ==
                        E2E_OUTER_ITERATIONS[e2e_case_index*16 +: 16],
                    "force-iter outer iteration count matches limit");
                check(write_bursts == 3,
                    "force-iter completed dense sparse and header writeback");
                check(e2e_residual_captures != 0,
                    "force-iter captured a residual");
                check(!operator_fault && !e2e_fault_seen,
                    "force-iter reports no operator fault");
                check(e2e_serial_transpose_captures == 0,
                    "compiled E2E path never falls back to serial transpose gather");
            end else begin
            check(final_support_count == expected_count[6:0],
                "final support count matches hardware golden");
            for (slot = 0; slot < expected_count; slot = slot + 1) begin
                expected_index = E2E_SUPPORT_INDEX[
                    (e2e_case_index*E2E_SUPPORT_SLOTS + slot)*10 +: 10];
                expected_coefficient = E2E_SUPPORT_COEFF[
                    (e2e_case_index*E2E_SUPPORT_SLOTS + slot)*32 +: 32];
                check(final_support_indices[slot*10 +: 10] == expected_index,
                    "final support index matches hardware golden");
                check(final_support_coefficients[slot*`RECON_SOLVER_W +:
                        `RECON_SOLVER_W] ==
                      expected_coefficient[`RECON_SOLVER_W-1:0],
                    "final coefficient matches hardware golden");
            end
            check(dut.u_lifecycle.terminal_stop_reason ==
                    E2E_STOP_CODE[e2e_case_index*4 +: 4],
                "terminal stop reason matches hardware golden");
            check(e2e_outer_iteration_events ==
                    E2E_OUTER_ITERATIONS[e2e_case_index*16 +: 16],
                "outer iteration count matches hardware golden");
            check(write_bursts == 3 && write_beats == header_beat + 1,
                "dense sparse and header write counts");
            check(write_address[0] == E2E_DENSE_ADDR + 64'd16,
                "dense payload address");
            check(write_address[1] == E2E_SPARSE_ADDR + 64'd16,
                "sparse payload address");
            check(write_address[2] == E2E_SPARSE_ADDR,
                "result header address");
            for (beat = 0; beat < E2E_DENSE_BEATS; beat = beat + 1)
                check(write_data[beat] ==
                      e2e_expected_dense_beat(e2e_case_index, beat),
                    "dense result matches hardware golden");
            for (beat = 0; beat < sparse_beats; beat = beat + 1)
                check(write_data[E2E_DENSE_BEATS + beat] ==
                      e2e_expected_sparse_beat(e2e_case_index, beat),
                    "sparse result matches hardware golden");
            check(e2e_residual_captures != 0,
                "final residual was captured");
            for (beat = 0; beat < E2E_M; beat = beat + 1) begin
                expected_residual = E2E_RESIDUAL_LANES[
                    (e2e_case_index*E2E_M + beat)*32 +: 32];
                if ($signed(e2e_last_residual[beat]) != expected_residual)
                    $display("E2E RESIDUAL MISMATCH lane=%0d actual=%0d expected=%0d",
                        beat, $signed(e2e_last_residual[beat]), expected_residual);
                check($signed(e2e_last_residual[beat]) == expected_residual,
                    "final residual matches hardware golden");
            end
            check(E2E_EVENT_FLAGS[e2e_case_index*5 +: 5] == 0,
                "golden expects no saturation or arithmetic fault events");
            check(!operator_fault && !e2e_fault_seen,
                "RTL reports no saturation or operator fault events");
            if ((e2e_algorithm == 0) || (e2e_algorithm == 1) ||
                    (e2e_algorithm == 3) || (e2e_algorithm == 4) ||
                    (e2e_algorithm == 6))
                check(e2e_paired_transpose_commits != 0,
                    "LS path exercised paired CGRA transpose reads");
            check(e2e_serial_transpose_captures == 0,
                "compiled E2E path never falls back to serial transpose gather");
            expected_dense_bytes = E2E_N << 2;
            expected_sparse_bytes = expected_count << 3;
            expected_header = {
                7'd0, 1'b1, expected_sparse_bytes, expected_dense_bytes,
                8'd1, `RECON_RESULT_MODE_BOTH,
                E2E_STOP_CODE[e2e_case_index*4 +: 4],
                expected_count[6:0],
                E2E_N[10:0], E2E_USER_TAG, 32'h43535233
            };
            $display("E2E HEADER actual=%032x expected=%032x",
                write_data[header_beat], expected_header);
            check(write_data[header_beat] == expected_header,
                "result header and stop reason match hardware golden");
            end
        end
    endtask

    integer word;
    integer e2e_timeout_limit;
    initial begin
        if (!$value$plusargs("+E2E_ALGORITHM=%d", e2e_algorithm))
            e2e_algorithm = E2E_ALGORITHM_SELECT;
        if (!$value$plusargs("+E2E_PROFILE=%d", e2e_profile))
            e2e_profile = E2E_PROFILE_SELECT;
        if (!$value$plusargs("+E2E_TIMEOUT_OVERRIDE=%d", e2e_timeout_limit))
            e2e_timeout_limit = E2E_TIMEOUT_CYCLES;
        if ((e2e_algorithm < 0) || (e2e_algorithm >= E2E_ALG_COUNT) ||
                (e2e_profile < 0) || (e2e_profile >= E2E_PROFILE_COUNT)) begin
            $display("FAIL: invalid E2E selection algorithm=%0d profile=%0d",
                e2e_algorithm, e2e_profile);
            $finish;
        end
        e2e_case_index = e2e_profile*E2E_ALG_COUNT + e2e_algorithm;
        $sformat(e2e_phase_file,
            "../../reports/v3/context_images/program_%02d_phase.mem",
            e2e_algorithm);
        $readmemh("../../reports/v3/context_images/array_plane_0.mem", e2e_plane_0);
        $readmemh("../../reports/v3/context_images/array_plane_1.mem", e2e_plane_1);
        $readmemh("../../reports/v3/context_images/array_plane_2.mem", e2e_plane_2);
        $readmemh("../../reports/v3/context_images/array_plane_3.mem", e2e_plane_3);
        $readmemh("../../reports/v3/context_images/array_plane_4.mem", e2e_plane_4);
        $readmemh("../../reports/v3/context_images/array_plane_5.mem", e2e_plane_5);
        $readmemh("../../reports/v3/context_images/array_plane_6.mem", e2e_plane_6);
        $readmemh("../../reports/v3/context_images/array_plane_7.mem", e2e_plane_7);
        $readmemh("../../reports/v3/context_images/array_plane_8.mem", e2e_plane_8);
        $readmemh("../../reports/v3/context_images/array_plane_9.mem", e2e_plane_9);
        $readmemh(e2e_phase_file, e2e_phase_words);
        for (word = 0; word < 4; word = word + 1)
            cfg_beats[word] = E2E_CFG_WORDS[
                (e2e_profile*16 + word*4)*32 +: 128];
        for (word = 0; word < 64; word = word + 1)
            e2e_memory_configurations[word] =
                E2E_MEMORY_CONFIGURATIONS[word*64 +: 64];

        repeat (6) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
        load_e2e_memory_configurations();
        load_e2e_resident_image();
        check(active_image_ok && active_context_count == E2E_ARRAY_CONTEXT_COUNT,
            "production resident context image certified");
        issue_e2e_preload();
        if (E2E_SCALAR_NEED[e2e_algorithm])
            scalar_preload(1'b0,
                $signed(E2E_SCALAR_VALUE[e2e_algorithm*62 +: 62]));

        csr_write(`RECON_CSR_RUN_CONFIGURATION_LO, E2E_CFG_ADDR[31:0]);
        csr_write(`RECON_CSR_RUN_CONFIGURATION_HI, E2E_CFG_ADDR[63:32]);
        csr_write(`RECON_CSR_COMMAND, 32'd1);
        timeout = 0;
        while (!engine_busy && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "production lifecycle start");
        timeout = 0;
        while (engine_busy && timeout < e2e_timeout_limit) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout == 20000) begin
            $display("E2E TIMEOUT phase_pc=%0d array_pc=%0d cycle_valid=%b commit=%b stream_in=%b stream_out=%b resource_in=%b resource_out=%b resource_op=%0d wait_ready=%b wait_result=%b provider_busy=%b phi_valid=%b vec_a_valid=%b vec_result_valid=%b refinement_valid=%b refinement_restart=%b operator_fault=%b detail=%04x",
                dut.u_lifecycle.u_phase_controller.phase_pc,
                dut.u_array_context_sequencer.pc,
                dut.u_operator.cycle_valid,
                dut.u_operator.cycle_commit,
                dut.u_operator.stream_input_ready,
                dut.u_operator.stream_output_ready,
                dut.u_operator.resource_req_ready,
                dut.u_operator.resource_rsp_valid,
                dut.u_operator.resource_operation,
                dut.u_operator.resource_wait_for_ready,
                dut.u_operator.resource_wait_for_result,
                dut.u_operator.phi_busy,
                dut.u_operator.phi_symbol_valid,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.vector_result_valid,
                dut.u_operator.refinement_event_valid,
                dut.u_operator.refinement_restart_required,
                operator_fault,
                operator_fault_detail);
            $display("E2E PHI LANE active=%b residual=%b issue=%0d output=%0d available=%b phase=%b input=%b/%b output=%b/%b/%0d/tag%0d acc0=%0d meas0=%0d result0=%0d write_ready=%b cfg=%b fmt=%0d pack=%h err=%h",
                dut.u_operator.u_phi_lane_flow.lane_active,
                dut.u_operator.u_phi_lane_flow.residual_mode,
                dut.u_operator.u_phi_lane_flow.issue_count,
                dut.u_operator.u_phi_lane_flow.output_count,
                dut.u_operator.cgra_result_available,
                dut.u_operator.u_cgra_fabric.u_result_buffer.s27_high_select,
                dut.u_operator.u_phi_lane_flow.lane_input_valid,
                dut.u_operator.normalizer_input_ready,
                dut.u_operator.normalizer_output_valid,
                dut.u_operator.normalizer_output_ready,
                $signed(dut.u_operator.normalizer_output_data),
                dut.u_operator.normalizer_output_tag,
                $signed(dut.u_operator.u_phi_lane_flow.accumulator_buffer[0 +: 48]),
                $signed(dut.u_operator.u_phi_lane_flow.measurement_buffer[0 +: 27]),
                $signed(dut.u_operator.u_cgra_fabric.u_result_buffer.result_data[0 +: 27]),
                dut.u_operator.u_vector_codec.write_payload_ready,
                dut.u_operator.cfg_w_valid,
                dut.u_operator.cfg_w_data[54:52],
                dut.u_operator.u_vector_codec.write_pack_valid,
                dut.u_operator.u_vector_codec.write_pack_error);
            $display("E2E CACHE valid=%b busy=%b fault=%b refill=%b count=%0d replay=%b/%b slot=%0d row=%0d response=%b/%b cache_symbol=%b/%b provider=%b done=%b",
                dut.u_operator.phi_cache_valid,
                dut.u_operator.u_phi_stream.status_cache_busy,
                dut.u_operator.phi_cache_fault,
                dut.u_operator.phi_cache_refill_pending,
                dut.u_operator.phi_cache_refill_support_count,
                dut.u_operator.phi_cache_req_valid,
                dut.u_operator.phi_cache_req_ready,
                dut.u_operator.phi_cache_req_slot,
                dut.u_operator.phi_cache_req_row,
                dut.u_operator.u_phi_stream.internal_rsp_valid,
                dut.u_operator.u_phi_stream.internal_req_ready,
                dut.u_operator.phi_cache_rsp_valid,
                dut.u_operator.phi_cache_rsp_ready,
                dut.u_operator.phi_busy,
                dut.u_operator.phi_done);
            $display("E2E SCATTER pending=%b owner=%0d op=%0d tag=%0d issue=%b response_ctx=%b match=%b support_ready=%b state=%0d req_pending=%b response=%b/%b resp_op=%0d resp_tag=%0d candidate=%b/%b score=%0d index=%0d serializer=%b/%b/%b source=%b/%b/%b",
                dut.u_operator.u_dispatcher.pending_valid,
                dut.u_operator.u_dispatcher.pending_owner,
                dut.u_operator.u_dispatcher.pending_operation,
                dut.u_operator.u_dispatcher.pending_tag,
                dut.u_operator.u_dispatcher.issue_context,
                dut.u_operator.u_dispatcher.response_context,
                dut.u_operator.u_dispatcher.response_matches,
                dut.u_operator.u_dispatcher.support_request_ready,
                dut.u_operator.u_dispatcher.u_support.state,
                dut.u_operator.u_dispatcher.u_support.request_pending,
                dut.u_operator.u_dispatcher.support_response_valid,
                dut.u_operator.u_dispatcher.u_support.response_ready,
                dut.u_operator.u_dispatcher.support_response_operation,
                dut.u_operator.u_dispatcher.support_response_tag,
                dut.u_operator.vector_candidate_valid,
                dut.u_operator.dispatcher_candidate_ready,
                $signed(dut.u_operator.vector_candidate_score),
                dut.u_operator.vector_candidate_index,
                dut.u_operator.u_candidate_stream.source_active,
                dut.u_operator.u_candidate_stream.source_valid,
                dut.u_operator.u_candidate_stream.source_ready,
                dut.u_operator.physical_vec_a_valid,
                dut.u_operator.u_candidate_stream.u_serializer.buffer_valid,
                dut.u_operator.u_candidate_stream.u_serializer.stream_done);
            $display("E2E COLQ count=%0d rd=%0d wr=%0d cand=%b sat=%b red_col=%0d completed=%b outstanding=%0d auto=%b",
                dut.u_operator.u_column_flow.col_q_count,
                dut.u_operator.u_column_flow.col_q_rd,
                dut.u_operator.u_column_flow.col_q_wr,
                dut.u_operator.selected_candidate_valid,
                dut.u_operator.selected_candidate_saturated,
                dut.u_operator.u_column_flow.reduce_col_count,
                dut.u_operator.u_column_flow.completed_column_valid,
                dut.u_operator.u_m5.router.reduction_outstanding,
                dut.u_operator.u_m5.router.reduction_auto_retire);
            end
        end
        check(timeout < e2e_timeout_limit, "production lifecycle completion");
        check_e2e_result();
        check(profile_total_cycles >= profile_phase_cycles,
            "profile phase cycles bounded by total cycles");
        check(profile_total_cycles == timeout,
            "profile total cycles match lifecycle wait count");
        check(profile_phase_cycles >= profile_execution_cycles,
            "profile execution cycles bounded by phase cycles");
        check(profile_useful_pe_cycles <= profile_array_commit_cycles,
            "profile useful PE cycles bounded by commits");
        check(profile_useful_pe_slots <=
            (profile_array_commit_cycles * `RECON_PE_COUNT),
            "profile useful PE slots bounded by physical PE capacity");
        check(profile_resource_stall_cycles <= profile_array_stall_cycles,
            "profile resource stalls bounded by array stalls");
        check(profile_phi_generate_requests == e2e_phi_generate_fires,
            "profile Phi generate request count");
        check(profile_phi_replay_requests == e2e_phi_replay_fires,
            "profile Phi replay request count");
        check(profile_phi_replay_responses ==
            e2e_phi_replay_response_fires,
            "profile Phi replay response count");
        check(profile_phi_cache_fills == e2e_phi_cache_fill_fires,
            "profile Phi cache fill count");
        check(profile_phi_output_symbols == e2e_phi_output_fires,
            "profile Phi output symbol count");
        check(profile_selection_accepts == e2e_selection_fires,
            "profile selection accept count");
        $display("M13 DMA READ DEBUG rtl_requests=%0d tb_requests=%0d rtl_beats=%0d tb_beats=%0d",
            profile_dma_read_requests, e2e_dma_read_address_fires,
            profile_dma_read_beats, e2e_dma_read_beat_fires);
        check(profile_dma_read_requests == e2e_dma_read_address_fires,
            "profile DMA read request count");
        check(profile_dma_read_beats == e2e_dma_read_beat_fires,
            "profile DMA read beat count");
        check(profile_dma_write_requests == e2e_dma_write_address_fires,
            "profile DMA write request count");
        check(profile_dma_write_beats == e2e_dma_write_beat_fires,
            "profile DMA write beat count");
        check(profile_dma_write_responses == e2e_dma_write_response_fires,
            "profile DMA write response count");
        check(profile_result_drain_cycles == e2e_result_drain_cycles,
            "profile result drain cycle count");
        check(profile_result_drain_beats == e2e_result_drain_beats,
            "profile result drain beat count");
        check(profile_result_drain_beats <= profile_dma_write_beats,
            "profile result drain beats bounded by DMA write beats");
        if (failures == 0) begin
            $display("M13 E2E ITERATIONS algorithm=%0d profile=%0d actual=%0d expected=%0d",
                e2e_algorithm, e2e_profile, e2e_outer_iteration_events,
                E2E_OUTER_ITERATIONS[e2e_case_index*16 +: 16]);
            $display("M13 FORWARD ATTRIBUTION cycles=%0d pack_empty=%0d cache_backpressure=%0d refill_request_valid=%0d refill_request_fires=%0d pack_captures=%0d pack_releases=%0d",
                e2e_forward_mode_cycles, e2e_support_pack_empty_stalls,
                e2e_cache_replay_backpressure_cycles,
                e2e_refill_request_valid_cycles, e2e_refill_request_fires,
                e2e_support_pack_captures, e2e_support_pack_releases);
            $display("M13 CACHE ATTRIBUTION control_busy=%0d pipeline_full=%0d invalid=%0d consumer_stall=%0d",
                e2e_cache_control_busy_cycles, e2e_cache_pipeline_full_cycles,
                e2e_cache_invalid_cycles, e2e_cache_consumer_stall_cycles);
            $display("M13 TRANSPOSE ATTRIBUTION issue=%0d wait=%0d wait_stall=%0d writeback=%0d writeback_stall=%0d",
                e2e_transpose_issue_cycles, e2e_transpose_wait_cycles,
                e2e_transpose_wait_stalls, e2e_transpose_writeback_cycles,
                e2e_transpose_writeback_stalls);
            $display("M13 CURSOR ATTRIBUTION commits=%0d mask_a=%0d mask_ab=%0d",
                e2e_cursor_restart_commits, e2e_cursor_restart_mask_a,
                e2e_cursor_restart_mask_ab);
            $display("M13 PROFILE total_cycles=%0d phase_cycles=%0d execution_cycles=%0d writeback_cycles=%0d pe_useful_cycles=%0d stall_stream_input=%0d stall_stream_output=%0d stall_resource_request=%0d stall_resource_response=%0d stall_other=%0d phi_generate=%0d phi_replay=%0d selection=%0d dma_read_address=%0d dma_read_beats=%0d dma_write_address=%0d dma_write_beats=%0d dma_write_responses=%0d result_drain_cycles=%0d result_drain_beats=%0d",
                e2e_total_cycles, e2e_phase_cycles, e2e_execution_cycles,
                e2e_writeback_cycles, e2e_pe_useful_cycles,
                e2e_stream_input_stalls, e2e_stream_output_stalls,
                e2e_resource_request_stalls, e2e_resource_response_stalls,
                e2e_other_commit_stalls, e2e_phi_generate_fires,
                e2e_phi_replay_fires, e2e_selection_fires,
                e2e_dma_read_address_fires, e2e_dma_read_beat_fires,
                e2e_dma_write_address_fires, e2e_dma_write_beat_fires,
                e2e_dma_write_response_fires, e2e_result_drain_cycles,
                e2e_result_drain_beats);
            $display("M13 RTL PROFILE total=%0d phase=%0d execution=%0d commits=%0d stalls=%0d useful_cycles=%0d useful_slots=%0d resource_stalls=%0d",
                profile_total_cycles, profile_phase_cycles,
                profile_execution_cycles, profile_array_commit_cycles,
                profile_array_stall_cycles, profile_useful_pe_cycles,
                profile_useful_pe_slots, profile_resource_stall_cycles);
            $display("M13 RTL EVENTS phi_generate=%0d phi_replay_requests=%0d phi_replay_responses=%0d phi_cache_fills=%0d phi_output_symbols=%0d selection=%0d dma_read_requests=%0d dma_read_beats=%0d dma_write_requests=%0d dma_write_beats=%0d dma_write_responses=%0d result_drain_cycles=%0d result_drain_beats=%0d",
                profile_phi_generate_requests, profile_phi_replay_requests,
                profile_phi_replay_responses, profile_phi_cache_fills,
                profile_phi_output_symbols, profile_selection_accepts,
                profile_dma_read_requests, profile_dma_read_beats,
                profile_dma_write_requests, profile_dma_write_beats,
                profile_dma_write_responses, profile_result_drain_cycles,
                profile_result_drain_beats);
            $display("M13 E2E CASE PASS m=%0d n=%0d k=%0d algorithm=%0d profile=%0d cycles=%0d",
                E2E_M, E2E_N, E2E_K, e2e_algorithm, e2e_profile, timeout);
            if ((e2e_algorithm == 0) && (e2e_profile == 0))
                $display("M13 E2E OMP STRICT PASS");
        end else
            $display("FAIL: M13 E2E CASE algorithm=%0d profile=%0d failures=%0d",
                e2e_algorithm, e2e_profile, failures);
        $finish;
    end
`else
    initial begin
        cfg_beats[0] = 0;
        cfg_beats[1] = 0;
        cfg_beats[2] = 0;
        cfg_beats[3] = 0;
        cfg_beats[0][31:0] =
            {2'd0, 2'd0, 4'd0, `RECON_RUN_CONFIGURATION_REVISION,
             `RECON_RUN_CONFIGURATION_MAGIC};
        cfg_beats[0][63:32] = {5'd0, 7'd1, 11'd4, 9'd4};
        cfg_beats[0][95:64] = 32'h04100014;
        cfg_beats[1][31:0] = 32'h100;
        cfg_beats[1][95:64] = 32'h89abcdef;
        cfg_beats[1][127:96] = 32'h01234567;
        cfg_beats[2][31:0] = 32'h4000;
        cfg_beats[2][95:64] = DENSE_ADDR[31:0];
        cfg_beats[2][127:96] = DENSE_ADDR[63:32];
        cfg_beats[3][95:64] = 32'hfeed1234;
        cfg_beats[3][127:96] = 32'h01820000;

        repeat (6) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        loader_read(`RECON_LOADER_CSR_IDENTIFICATION, loader_readback);
        check(loader_readback == `RECON_LOADER_IDENTIFICATION,
              "loader aperture identification");
        memory_configuration_write(6'd40, vector_configuration());
        check(dut.u_memory_configuration_store.cfg_read_copy[40] ==
              vector_configuration(),
              "loader programs sparse memory configuration ID40");
        scalar_preload(1'b0, 62'sd12345);
        check(dut.u_operator.u_m5.u_scalar_state.u_registers.valid_bits[0] &&
              dut.u_operator.u_m5.u_scalar_state.u_registers.data[0] == 62'sd12345,
              "loader programs scalar preload state");
        loader_write(`RECON_LOADER_CSR_COMMAND,
            `RECON_LOADER_COMMAND_SCALAR_CLEAR, `AXI_RESP_OKAY);
        loader_wait_completion(`RECON_LOADER_COMMAND_SCALAR_CLEAR,
            "scalar state clear accepted");
        check(!dut.u_operator.u_m5.u_scalar_state.u_registers.valid_bits[0],
              "loader clears scalar state");
        scratch_write(3'd3, 9'd5, 72'h0123456789abcdef12);
        check(dut.u_operator.u_scratchpad_subsystem.u_memory.g_bank[3].memory[5] ==
              72'h0123456789abcdef12,
              "loader programs direct scratchpad word");

        @(negedge clk);
        monitor_run_active = 1;
        monitor_support_count = 2;
        monitor_support_indices[9:0] = 10'd3;
        monitor_support_indices[19:10] = 10'd7;
        monitor_refinement_valid = 1;
        @(posedge clk);
        #1;
        monitor_refinement_valid = 0;
        check(monitor_solver_iter == 1 && !monitor_solver_converged,
              "termination monitor refinement count");
        @(negedge clk);
        monitor_certificate_pass = 1;
        monitor_refinement_valid = 1;
        @(posedge clk);
        #1;
        monitor_refinement_valid = 0;
        check(monitor_solver_iter == 2 && monitor_solver_converged,
              "termination monitor convergence");
        @(negedge clk);
        monitor_residual_sq = 80;
        monitor_termination_valid = 1;
        @(posedge clk);
        #1;
        monitor_termination_valid = 0;
        check(monitor_outer_iter == 1 && monitor_solver_iter == 0 &&
              monitor_residual_decreased && !monitor_support_stable &&
              !monitor_iteration_limit_reached,
              "termination monitor first outer event");
        @(negedge clk);
        monitor_residual_sq = 90;
        monitor_residual_limit = 1;
        monitor_termination_valid = 1;
        @(posedge clk);
        #1;
        monitor_termination_valid = 0;
        check(monitor_outer_iter == 2 && monitor_residual_limit_reached &&
              monitor_iteration_limit_reached && monitor_support_stable &&
              !monitor_residual_decreased,
              "termination monitor measured predicates");
        monitor_run_active = 0;
        monitor_residual_limit = 0;
        monitor_certificate_pass = 0;
        @(posedge clk);

        for (plane = 0; plane < 8; plane = plane + 1)
            image_write(plane[3:0], 8'd0, 72'd0);
        image_write(4'd9, 8'd0, 72'd0);
        image_write(4'd8, 8'd0, {36'd0, array_control_word()});
        image_write(`RECON_PHASE_INSTRUCTION_COMMIT_PLANE, 8'd0,
                    {36'd0, phase_launch_word()});
        image_write(`RECON_PHASE_INSTRUCTION_COMMIT_PLANE, 8'd1,
                    {36'd0, phase_wait_word()});
        image_write(`RECON_PHASE_INSTRUCTION_COMMIT_PLANE, 8'd2,
                    {36'd0, phase_complete_word()});
        finalize_image();
        check(active_image_ok && active_context_count == 1,
              "resident image certified");

        issue_preload();

        csr_write(`RECON_CSR_RUN_CONFIGURATION_LO, CFG_ADDR[31:0]);
        csr_write(`RECON_CSR_RUN_CONFIGURATION_HI, CFG_ADDR[63:32]);
        csr_write(`RECON_CSR_COMMAND, 32'd1);
        timeout = 0;
        while (!engine_busy && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "lifecycle start");
        loader_write(`RECON_LOADER_CSR_COMMAND,
            `RECON_LOADER_COMMAND_SCALAR_CLEAR, `AXI_RESP_SLVERR);
        timeout = 0;
        while (!dut.active_cfg_valid && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "active configuration commit");
        check(dut.active_measurement_row_blocks == 5'd1,
              "configuration owns measurement row-block count");
        check(dut.u_array_context_sequencer.run_param0 == 16'd1,
              "sequencer receives registered measurement row-block count");
        timeout = 0;
        while (engine_busy && timeout < 3000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 3000, "lifecycle completion");
        check(!operator_fault, "operator remains fault free");
        check(write_bursts == 2 && write_beats == 2,
              "dense payload and header written");
        check(write_address[0] == DENSE_ADDR + 16,
              "dense payload address");
        check(write_address[1] == DENSE_ADDR, "dense header address");
        check(write_data[0] == 128'd0, "zero dense result payload");
        if (failures == 0)
            $display("M13 COMPUTE LIFECYCLE PASS");
        else
            $display("FAIL: M13 COMPUTE LIFECYCLE failures=%0d", failures);
        $finish;
    end
`endif
endmodule

`default_nettype wire
