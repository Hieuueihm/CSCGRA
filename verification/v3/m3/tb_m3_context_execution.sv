`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "reconstruction_control_defs.vh"

module tb_m3_context_execution;
    `include "m3_control_image.vh"

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer failures = 0;

    reg img_wr_valid = 1'b0;
    wire img_wr_ready;
    reg img_wr_bank = 1'b0;
    reg [3:0] img_wr_plane = 4'd0;
    reg [7:0] img_wr_addr = 8'd0;
    reg [71:0] img_wr_data = 72'd0;
    wire img_wr_resp_valid;
    reg img_wr_resp_ready = 1'b0;
    wire img_wr_resp_error;
    wire [7:0] img_wr_resp_code;
    wire [31:0] img_wr_resp_detail;
    reg finalize_valid = 1'b0;
    wire finalize_ready;
    reg finalize_req_bank = 1'b0;
    wire finalize_resp_valid;
    reg finalize_resp_ready = 1'b0;
    wire finalize_resp_error;
    wire [7:0] finalize_resp_code;
    wire [31:0] finalize_resp_detail;

    wire ctx_rd_en;
    wire [7:0] ctx_rd_addr;
    wire ctx_rd_resp_valid;
    wire ctx_rd_valid;
    wire active_image_ok;
    wire [8:0] active_ctx_count;
    wire [7:0] ctx_rd_pc;
    wire [575:0] ctx_tiles;
    wire [35:0] ctx_array;
    wire [35:0] ctx_stream;
    wire [35:0] ctx_resource;
    wire phase_rd_en;
    wire [7:0] phase_rd_addr;
    wire phase_rd_resp_valid;
    wire phase_rd_valid;
    wire [7:0] phase_rd_pc;
    wire [35:0] phase_word;

    reg cfg_wr_valid = 1'b0;
    wire cfg_wr_ready;
    reg cfg_wr_bank = 1'b0;
    reg [5:0] cfg_wr_id = 6'd0;
    reg [63:0] cfg_wr_data = 64'd0;
    wire cfg_wr_resp_valid;
    reg cfg_wr_resp_ready = 1'b0;
    wire cfg_wr_resp_error;
    wire [7:0] cfg_wr_resp_code;
    wire [31:0] cfg_wr_resp_detail;
    reg [5:0] cfg_a_id = 6'd0;
    wire cfg_a_valid;
    wire [63:0] cfg_a_data;
    reg [5:0] cfg_b_id = 6'd0;
    wire cfg_b_valid;
    wire [63:0] cfg_b_data;
    reg [5:0] cfg_stream_id = 6'd0;
    wire cfg_stream_valid;
    wire [63:0] cfg_stream_data;
    reg [5:0] phi_cfg_id = 6'd0;
    wire phi_cfg_valid;
    wire [63:0] phi_cfg_data;

    reg start_request = 1'b0;
    reg [63:0] start_address = 64'd0;
    reg abort_request = 1'b0;
    wire cfg_start_valid;
    reg cfg_start_ready = 1'b0;
    wire [63:0] cfg_start_addr;
    reg cfg_fetch_active = 1'b0;
    reg active_cfg_valid = 1'b0;
    wire active_cfg_release;
    wire control_abort_pending;
    reg direct_abort_pending = 1'b0;
    reg pending_error = 1'b0;
    wire phase_array_launch_valid;
    wire phase_array_launch_ready;
    wire [7:0] phase_array_launch_entry_pc;
    wire [3:0] phase_array_launch_event_id;
    wire phase_array_done_ready;
    wire phase_array_fault_ready;
    reg support_stable = 1'b0;
    wire done_pulse;
    wire [3:0] stop_reason;
    wire control_error_pulse;
    wire [3:0] control_error_class;
    wire [7:0] control_error_code;
    wire [7:0] control_error_phase;
    wire [31:0] control_error_detail;
    wire phase_terminal_valid = done_pulse || control_error_pulse;
    wire phase_terminal_error = control_error_pulse;
    wire phase_terminal_aborted = done_pulse &&
        (stop_reason == `RECON_STOP_ABORTED);
    wire [3:0] phase_terminal_code = stop_reason;
    wire [3:0] phase_terminal_error_class = control_error_class;
    wire [7:0] phase_terminal_error_code = control_error_code;
    wire [7:0] phase_terminal_error_phase = control_error_phase;
    wire [31:0] phase_terminal_error_detail = control_error_detail;
    wire phase_trace_valid;
    wire [7:0] phase_trace_pc;
    wire [2:0] phase_trace_operation;
    wire phase_trace_condition;
    wire phase_active;
    wire [7:0] phase_pc;
    wire engine_busy;
    wire [2:0] control_state;

    reg direct_array_mode = 1'b0;
    reg direct_array_launch_valid = 1'b0;
    wire direct_array_launch_ready;
    reg [7:0] direct_array_entry_pc = 8'd0;
    reg [3:0] direct_array_event_id = 4'd0;
    reg direct_array_done_ready = 1'b0;
    reg direct_array_fault_ready = 1'b0;
    wire array_launch_valid_mux = direct_array_mode ?
        direct_array_launch_valid : phase_array_launch_valid;
    wire [7:0] array_launch_entry_mux = direct_array_mode ?
        direct_array_entry_pc : phase_array_launch_entry_pc;
    wire [3:0] array_launch_event_mux = direct_array_mode ?
        direct_array_event_id : phase_array_launch_event_id;
    wire array_done_ready_mux = direct_array_mode ?
        direct_array_done_ready : phase_array_done_ready;
    wire array_fault_ready_mux = direct_array_mode ?
        direct_array_fault_ready : phase_array_fault_ready;
    wire array_abort_pending = direct_array_mode ?
        direct_abort_pending : control_abort_pending;
    assign phase_array_launch_ready = !direct_array_mode &&
                                      direct_array_launch_ready;

    reg [7:0] predicate_values = 8'd0;
    reg stream_in_ready = 1'b0;
    reg stream_out_ready = 1'b1;
    reg resource_req_ready = 1'b1;
    reg resource_rsp_valid = 1'b1;
    wire cycle_valid;
    wire cycle_commit;
    wire cycle_stalled;
    wire [7:0] array_pc;
    wire [1:0] cluster_mask;
    wire [575:0] tile_ctx;
    wire [35:0] array_ctx;
    wire [35:0] stream_ctx;
    wire [35:0] resource_ctx;
    wire array_active;
    wire array_done_valid;
    wire [3:0] array_done_event_id;
    wire array_done_aborted;
    wire array_fault_valid;
    wire [7:0] array_fault_code;
    wire [7:0] array_fault_pc;
    wire [31:0] array_fault_detail;
    wire [31:0] commit_count;
    wire [31:0] guaranteed_count;
    wire [31:0] elastic_count;
    wire [31:0] stall_count;
    wire image_execution_active = phase_active ||
                                  array_active;

    reg [575:0] direct_guard_tiles = 576'd0;
    reg [35:0] direct_guard_control = 36'd0;
    reg [35:0] direct_guard_stream = 36'd0;
    reg [35:0] direct_guard_resource = 36'd0;
    wire direct_guard_violation;
    wire [7:0] direct_guard_code;
    wire [31:0] direct_guard_detail;
    reg [3:0] direct_cert_plane = 4'd8;
    reg [71:0] direct_cert_data = 72'd0;
    wire direct_cert_violation;
    wire [7:0] direct_cert_code;
    wire [31:0] direct_cert_detail;

    integer array_event_index = 0;
    integer phase_event_index = 0;
    integer relative_array_cycle = 0;
    integer pc3_stall_count = 0;
    reg normal_trace_check = 1'b0;
    reg normal_array_launch_seen = 1'b0;

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic finalize_array_image;
        input bank;
        input expected_error;
        input [7:0] expected_code;
        begin
            while (!finalize_ready) @(negedge clk);
            @(negedge clk);
            finalize_req_bank = bank;
            finalize_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            finalize_valid = 1'b0;
            while (!finalize_resp_valid) @(negedge clk);
            check(finalize_resp_error == expected_error,
                  "array image finalize error matches expectation");
            if (expected_error)
                check(finalize_resp_code == expected_code,
                      "array image finalize reports expected error code");
            finalize_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            finalize_resp_ready = 1'b0;
        end
    endtask

    task automatic write_image_word;
        input bank;
        input [3:0] plane;
        input [7:0] address;
        input [71:0] data;
        input expected_error;
        begin
            while (!img_wr_ready) @(negedge clk);
            @(negedge clk);
            img_wr_bank = bank;
            img_wr_plane = plane;
            img_wr_addr = address;
            img_wr_data = data;
            img_wr_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_wr_valid = 1'b0;
            check(img_wr_resp_valid,
                  "context image write returns a response token");
            check(img_wr_resp_error == expected_error,
                  "context image write error flag matches expectation");
            if (expected_error)
                check(img_wr_resp_code ==
                      `RECON_CONTEXT_ERROR_IMAGE_WRITE,
                      "context image write reports generated error code");
            img_wr_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            img_wr_resp_ready = 1'b0;
        end
    endtask

    task automatic write_memory_configuration;
        input [5:0] identifier;
        input [63:0] data;
        input expected_error;
        begin
            while (!cfg_wr_ready) @(negedge clk);
            @(negedge clk);
            cfg_wr_bank = 1'b0;
            cfg_wr_id = identifier;
            cfg_wr_data = data;
            cfg_wr_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cfg_wr_valid = 1'b0;
            check(cfg_wr_resp_valid,
                  "memory configuration write returns a response token");
            check(cfg_wr_resp_error == expected_error,
                  "memory configuration write error flag matches expectation");
            if (expected_error)
                check(cfg_wr_resp_code ==
                      `RECON_CONTEXT_ERROR_MEMORY_CONFIGURATION,
                      "memory configuration reports generated error code");
            cfg_wr_resp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cfg_wr_resp_ready = 1'b0;
        end
    endtask

    function automatic [63:0] phi_memory_configuration;
        input [2:0] bank_mode;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[31:16] = 16'd1;
            value[43:32] = 12'd1;
            value[51:49] = bank_mode;
            value[54:52] = `RECON_ELEMENT_FORMAT_DATA18;
            value[57:55] = `RECON_PACKING_MODE_ONE;
            value[58] = 1'b1;
            value[62:61] = `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM;
            phi_memory_configuration = value;
        end
    endfunction

    task automatic start_phase_program;
        begin
            @(negedge clk);
            start_address = 64'h0000_0000_0000_2000;
            start_request = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start_request = 1'b0;
            while (!cfg_start_valid) @(negedge clk);
            cfg_start_ready = 1'b1;
            cfg_fetch_active = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cfg_start_ready = 1'b0;
            cfg_fetch_active = 1'b0;
            active_cfg_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic consume_phase_terminal;
        begin
            @(posedge clk);
            @(negedge clk);
            active_cfg_valid = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic direct_array_launch;
        input [7:0] entry_pc;
        begin
            while (!direct_array_launch_ready) @(negedge clk);
            @(negedge clk);
            direct_array_entry_pc = entry_pc;
            direct_array_event_id = 4'he;
            direct_array_launch_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            direct_array_launch_valid = 1'b0;
        end
    endtask

    context_image_store u_context_image_store (
        .clk(clk), .rst_n(rst_n),
        .execution_active(image_execution_active),
        .active_image_bank(1'b0),
        .active_image_ok(active_image_ok),
        .active_ctx_count(active_ctx_count),
        .finalize_valid(finalize_valid),
        .finalize_ready(finalize_ready),
        .finalize_req_bank(finalize_req_bank),
        .finalize_resp_valid(
            finalize_resp_valid),
        .finalize_resp_ready(
            finalize_resp_ready),
        .finalize_resp_error(
            finalize_resp_error),
        .finalize_resp_code(
            finalize_resp_code),
        .finalize_resp_detail(
            finalize_resp_detail),
        .img_wr_valid(img_wr_valid),
        .img_wr_ready(img_wr_ready),
        .img_wr_bank(img_wr_bank),
        .img_wr_plane(img_wr_plane),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),
        .img_wr_resp_valid(img_wr_resp_valid),
        .img_wr_resp_ready(img_wr_resp_ready),
        .img_wr_resp_error(img_wr_resp_error),
        .img_wr_resp_code(img_wr_resp_code),
        .img_wr_resp_detail(img_wr_resp_detail),
        .array_rd_en(ctx_rd_en),
        .array_rd_addr(ctx_rd_addr),
        .array_rd_resp_valid(ctx_rd_resp_valid),
        .array_rd_valid(ctx_rd_valid),
        .array_rd_pc(ctx_rd_pc),
        .tile_ctx(ctx_tiles),
        .array_ctx(ctx_array),
        .stream_ctx(ctx_stream),
        .resource_ctx(ctx_resource),
        .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid),
        .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word)
    );

    memory_configuration_store u_memory_configuration_store (
        .clk(clk), .rst_n(rst_n),
        .execution_active(image_execution_active),
        .active_image_bank(1'b0),
        .cfg_wr_valid(cfg_wr_valid),
        .cfg_wr_ready(cfg_wr_ready),
        .cfg_wr_bank(cfg_wr_bank),
        .cfg_wr_id(cfg_wr_id),
        .cfg_wr_data(cfg_wr_data),
        .cfg_wr_resp_valid(cfg_wr_resp_valid),
        .cfg_wr_resp_ready(cfg_wr_resp_ready),
        .cfg_wr_resp_error(cfg_wr_resp_error),
        .cfg_wr_resp_code(cfg_wr_resp_code),
        .cfg_wr_resp_detail(cfg_wr_resp_detail),
        .cfg_a_id(cfg_a_id),
        .cfg_a_valid(cfg_a_valid),
        .cfg_a_data(cfg_a_data),
        .cfg_b_id(cfg_b_id),
        .cfg_b_valid(cfg_b_valid),
        .cfg_b_data(cfg_b_data),
        .cfg_stream_id(cfg_stream_id),
        .cfg_stream_valid(cfg_stream_valid),
        .cfg_stream_data(cfg_stream_data),
        .phi_cfg_id(phi_cfg_id),
        .phi_cfg_valid(phi_cfg_valid),
        .phi_cfg_data(phi_cfg_data)
    );

    array_context_sequencer u_array_context_sequencer (
        .clk(clk), .rst_n(rst_n),
        .launch_valid(array_launch_valid_mux),
        .launch_ready(direct_array_launch_ready),
        .entry_pc(array_launch_entry_mux),
        .event_id(array_launch_event_mux),
        .abort_pending(array_abort_pending),
        .predicate_values(predicate_values),
        .image_ok(active_image_ok),
        .image_count(active_ctx_count),
        .measurement_count(9'd32), .signal_length(11'd64),
        .sparsity(7'd8), .outer_limit(16'd8),
        .refine_limit(8'd4),
        .run_param0(16'd0), .run_param1(16'd0),
        .stream_in_ready(stream_in_ready),
        .stream_out_ready(stream_out_ready),
        .resource_req_ready(resource_req_ready),
        .resource_rsp_valid(resource_rsp_valid),
        .ctx_rd_en(ctx_rd_en),
        .ctx_rd_addr(ctx_rd_addr),
        .ctx_rd_resp_valid(ctx_rd_resp_valid),
        .ctx_rd_valid(ctx_rd_valid),
        .ctx_rd_pc(ctx_rd_pc),
        .ctx_tiles(ctx_tiles),
        .ctx_array(ctx_array),
        .ctx_stream(ctx_stream),
        .ctx_resource(ctx_resource),
        .cycle_valid(cycle_valid),
        .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled),
        .array_pc(array_pc),
        .cluster_mask(cluster_mask),
        .tile_ctx(tile_ctx),
        .array_ctx(array_ctx),
        .stream_ctx(stream_ctx),
        .resource_ctx(resource_ctx),
        .execution_active(array_active),
        .done_valid(array_done_valid),
        .done_ready(array_done_ready_mux),
        .done_event_id(array_done_event_id),
        .done_aborted(array_done_aborted),
        .fault_valid(array_fault_valid),
        .fault_ready(array_fault_ready_mux),
        .fault_code(array_fault_code), .fault_pc(array_fault_pc),
        .fault_detail(array_fault_detail),
        .commit_count(commit_count),
        .guaranteed_count(guaranteed_count),
        .elastic_count(elastic_count),
        .stall_count(stall_count)
    );

    reconstruction_phase_controller u_reconstruction_phase_controller (
        .clk(clk), .rst_n(rst_n),
        .start_request(start_request), .start_address(start_address),
        .abort_request(abort_request),
        .cfg_start_valid(cfg_start_valid),
        .cfg_start_ready(cfg_start_ready),
        .cfg_start_addr(cfg_start_addr),
        .cfg_fetch_active(cfg_fetch_active),
        .cfg_fetch_error_valid(1'b0),
        .cfg_fetch_error_ready(),
        .cfg_fetch_error_class(`RECON_ERROR_CLASS_NONE),
        .cfg_fetch_error_code(8'd0),
        .cfg_fetch_error_word(5'd0),
        .cfg_fetch_error_detail(32'd0),
        .active_cfg_valid(active_cfg_valid),
        .active_context_image_ok(active_image_ok),
        .active_cfg_release(active_cfg_release),
        .phase_rd_en(phase_rd_en),
        .phase_rd_addr(phase_rd_addr),
        .phase_rd_resp_valid(phase_rd_resp_valid),
        .phase_rd_valid(phase_rd_valid),
        .phase_rd_pc(phase_rd_pc),
        .phase_word(phase_word),
        .array_launch_valid(phase_array_launch_valid),
        .array_launch_ready(phase_array_launch_ready),
        .array_entry_pc(phase_array_launch_entry_pc),
        .array_event_id(phase_array_launch_event_id),
        .array_done_valid(array_done_valid),
        .array_done_ready(phase_array_done_ready),
        .array_done_event_id(array_done_event_id),
        .array_done_aborted(array_done_aborted),
        .array_fault_valid(array_fault_valid),
        .array_fault_ready(phase_array_fault_ready),
        .array_fault_code(array_fault_code),
        .array_fault_pc(array_fault_pc),
        .array_fault_detail(array_fault_detail),
        .resource_valid(1'b0), .resource_ready(),
        .resource_event(4'd0), .dma_done(1'b0),
        .residual_limit_reached(1'b0),
        .iteration_limit_reached(1'b0),
        .support_stable(support_stable),
        .residual_decreased(1'b0), .solver_converged(1'b0),
        .solver_fault(1'b0),
        .exec_error_pending(pending_error),
        .exec_error_class(`RECON_ERROR_CLASS_NONE),
        .exec_error_code(8'd0),
        .exec_error_detail(32'd0),
        .active_support(7'd8),
        .outer_iter(16'd0),
        .solver_iter(8'd0),
        .engine_busy(engine_busy),
        .phase_active(phase_active),
        .csr_cfg_fetch_active(),
        .writeback_active(),
        .abort_pending(control_abort_pending),
        .done_pulse(done_pulse),
        .stop_reason(stop_reason),
        .support_count(),
        .error_pulse(control_error_pulse),
        .error_class(control_error_class),
        .error_code(control_error_code),
        .error_phase(control_error_phase),
        .cfg_error_word(),
        .error_detail(control_error_detail),
        .phase_progress(phase_pc),
        .outer_progress(),
        .solver_progress(),
        .total_cycles(),
        .control_state(control_state),
        .active_image_bank(),
        .trace_valid(phase_trace_valid),
        .trace_phase_pc(phase_trace_pc),
        .trace_operation(phase_trace_operation),
        .trace_condition(phase_trace_condition)
    );

    context_reservation_guard u_direct_context_reservation_guard (
        .tile_ctx(direct_guard_tiles),
        .array_ctx(direct_guard_control),
        .stream_ctx(direct_guard_stream),
        .resource_ctx(direct_guard_resource),
        .violation(direct_guard_violation),
        .violation_code(direct_guard_code),
        .violation_detail(direct_guard_detail)
    );

    context_write_certifier u_direct_context_write_certifier (
        .img_wr_plane(direct_cert_plane), .img_wr_data(direct_cert_data),
        .patch_existing(1'b0), .old_resource_wait(1'b0),
        .old_guaranteed(1'b0), .violation(direct_cert_violation),
        .violation_code(direct_cert_code),
        .violation_detail(direct_cert_detail), .new_resource_wait(),
        .new_guaranteed()
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            array_event_index = 0;
            phase_event_index = 0;
            relative_array_cycle = 0;
            pc3_stall_count = 0;
            normal_array_launch_seen = 1'b0;
        end else if (normal_trace_check) begin
            if (phase_array_launch_valid && phase_array_launch_ready) begin
                normal_array_launch_seen = 1'b1;
                relative_array_cycle = 0;
            end else if (normal_array_launch_seen) begin
                relative_array_cycle = relative_array_cycle + 1;
                if (cycle_commit || cycle_stalled) begin
                    check(array_event_index < M3_EXPECTED_ARRAY_EVENT_COUNT,
                          "array trace contains no extra events");
                    if (array_event_index < M3_EXPECTED_ARRAY_EVENT_COUNT) begin
                        check(array_pc ==
                              m3_expected_array_pc(array_event_index),
                              "array trace PC matches compiler golden");
                        check(cycle_commit ==
                              m3_expected_array_commit(array_event_index),
                              "array trace commit/stall matches compiler golden");
                        check(relative_array_cycle ==
                              m3_expected_array_relative_cycle(
                                  array_event_index),
                              "array trace cycle matches compiler golden");
                    end
                    array_event_index = array_event_index + 1;
                    if (cycle_stalled && array_pc == 8'd3)
                        pc3_stall_count = pc3_stall_count + 1;
                end
            end
            if (phase_trace_valid) begin
                check(phase_trace_pc == phase_event_index,
                      "phase trace PC matches compiler golden");
                phase_event_index = phase_event_index + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (normal_trace_check && array_active &&
                array_pc == 8'd1 && stall_count >= 32'd2)
            stream_in_ready = 1'b1;
        if (normal_trace_check && pc3_stall_count >= 2)
            predicate_values[2] = 1'b1;
    end

    integer plane;
    integer address;
    integer timeout;
    reg [71:0] generated_word;
    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // Direct N2 guard checks before loading the resident image.
        generated_word = m3_generated_image_word(4'd8, 8'd0);
        direct_guard_control = generated_word[35:0];
        #1;
        check(!direct_guard_violation, "compiler legal context passes guard");
        direct_guard_tiles[4:0] = 5'd16;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_TILE_OPERATION,
              "retired tile opcode is rejected");
        direct_guard_tiles = 576'd0;
        direct_guard_tiles[26:24] =
            `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_ROUTE_CAPACITY,
              "disabled express route is rejected");
        direct_guard_tiles = 576'd0;
        direct_guard_stream = 36'd1;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_GUARANTEED_COMMIT,
              "guaranteed context cannot depend on vector ready");
        direct_guard_stream = 36'd0;
        direct_guard_resource[4:0] = 5'd31;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT,
              "illegal resource operation is rejected");
        direct_guard_resource = 36'd0;
        direct_guard_resource[4:0] = `RECON_RESOURCE_OP_ARGMAX;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT,
              "planned argmax opcode is rejected before image load");
        direct_guard_resource = 36'd0;
        direct_guard_control[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_MEASUREMENT_STRIPES_16;
        #1;
        check(!direct_guard_violation,
              "measurement-stripe loop limit is accepted");
        direct_guard_control[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_ACTIVE_WORK_STRIPES_16;
        #1;
        check(!direct_guard_violation,
              "active-work-stripe loop limit is accepted");
        direct_guard_control[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_SIGNAL_LENGTH_STRIPES_16;
        #1;
        check(!direct_guard_violation,
              "signal-length-stripe loop limit is accepted");
        direct_guard_control[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] = 4'd13;
        #1;
        check(direct_guard_violation && direct_guard_code ==
              `RECON_CONTEXT_ERROR_ARRAY_CONTROL,
              "unassigned loop-limit encoding is rejected");
        direct_guard_control = generated_word[35:0];
        direct_cert_data = generated_word;
        direct_cert_data[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_MEASUREMENT_STRIPES_16;
        #1;
        check(!direct_cert_violation,
              "write certifier accepts measurement-stripe loop limit");
        direct_cert_data[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_ACTIVE_WORK_STRIPES_16;
        #1;
        check(!direct_cert_violation,
              "write certifier accepts active-work-stripe loop limit");
        direct_cert_data[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] =
            `RECON_LOOP_LIMIT_SIGNAL_LENGTH_STRIPES_16;
        #1;
        check(!direct_cert_violation,
              "write certifier accepts signal-length-stripe loop limit");
        direct_cert_data[
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_LSB +:
            `RECON_ARRAY_CONTROL_FIELD_LOOP_LIMIT_SELECT_W] = 4'd13;
        #1;
        check(direct_cert_violation && direct_cert_code ==
              `RECON_CONTEXT_ERROR_ARRAY_CONTROL,
              "write certifier rejects unassigned loop-limit encoding");

        direct_cert_plane = 4'd2;
        direct_cert_data = 72'd0;
        #1;
        check(!direct_cert_violation,
              "write certifier accepts Phi-only NOP context");
        direct_cert_data[4:0] = `RECON_TILE_OP_ADD;
        #1;
        check(direct_cert_violation && direct_cert_code ==
              `RECON_CONTEXT_ERROR_TILE_OPERATION,
              "write certifier rejects general ALU op on Phi-only tile");
        direct_cert_data = 72'd0;
        direct_cert_data[`RECON_TILE_FIELD_RF_WRITE_ENABLE_LSB] = 1'b1;
        #1;
        check(direct_cert_violation && direct_cert_code ==
              `RECON_CONTEXT_ERROR_TILE_OPERATION,
              "write certifier rejects RF write on Phi-only tile");
        direct_cert_data = 72'd0;
        direct_cert_data[
            `RECON_TILE_FIELD_ROUTE_EAST_SELECT_LSB +:
            `RECON_TILE_FIELD_ROUTE_EAST_SELECT_W] =
            `RECON_ROUTE_SOURCE_PE_RESULT;
        #1;
        check(direct_cert_violation && direct_cert_code ==
              `RECON_CONTEXT_ERROR_ROUTE_CAPACITY,
              "write certifier rejects routing on Phi-only tile");
        direct_cert_plane = 4'd8;
        direct_cert_data = generated_word;

        write_memory_configuration(6'd0, M3_MEMORY_CONFIGURATION_0, 1'b0);
        @(posedge clk); #1;
        check(cfg_a_valid && cfg_b_valid &&
              cfg_stream_valid && phi_cfg_valid,
              "all four configuration read ports expose programmed ID zero");
        check(cfg_a_data == M3_MEMORY_CONFIGURATION_0 &&
              cfg_b_data == M3_MEMORY_CONFIGURATION_0 &&
              cfg_stream_data == M3_MEMORY_CONFIGURATION_0 &&
              phi_cfg_data == M3_MEMORY_CONFIGURATION_0,
              "replicated configuration ports remain bit identical");
        write_memory_configuration(6'd2, M3_MEMORY_CONFIGURATION_0, 1'b0);
        @(negedge clk);
        cfg_a_id = 6'd2;
        cfg_b_id = 6'd2;
        cfg_stream_id = 6'd2;
        phi_cfg_id = 6'd2;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check(cfg_a_valid && cfg_b_valid &&
              cfg_stream_valid && phi_cfg_valid,
              "sparse configuration ID is visible on all read ports");
        write_memory_configuration(6'd3,
            phi_memory_configuration(`RECON_BANK_MODE_SUPPORT_ROW_MAJOR),
            1'b0);
        write_memory_configuration(6'd4,
            phi_memory_configuration(`RECON_BANK_MODE_PING_PONG), 1'b1);
        write_memory_configuration(6'd1, M3_MEMORY_CONFIGURATION_0 + 64'd16,
                                 1'b0);
        @(negedge clk);
        cfg_a_id = 6'd1;
        cfg_b_id = 6'd1;
        cfg_stream_id = 6'd1;
        phi_cfg_id = 6'd1;
        check(cfg_a_data == M3_MEMORY_CONFIGURATION_0 &&
              cfg_b_data == M3_MEMORY_CONFIGURATION_0,
              "configuration outputs do not change before the read clock");
        @(posedge clk); #1;
        check(!cfg_a_valid && !cfg_b_valid &&
              !cfg_stream_valid && !phi_cfg_valid,
              "registered configuration outputs hold readiness for one cycle");
        @(posedge clk); #1;
        check(cfg_a_valid && cfg_b_valid &&
              cfg_stream_valid && phi_cfg_valid &&
              cfg_a_data == M3_MEMORY_CONFIGURATION_0 + 64'd16 &&
              cfg_b_data == M3_MEMORY_CONFIGURATION_0 + 64'd16 &&
              cfg_stream_data ==
                  M3_MEMORY_CONFIGURATION_0 + 64'd16 &&
              phi_cfg_data == M3_MEMORY_CONFIGURATION_0 + 64'd16,
              "four registered configuration ports return in two cycles");
        @(negedge clk);
        cfg_a_id = 6'd0;
        cfg_b_id = 6'd0;
        cfg_stream_id = 6'd0;
        phi_cfg_id = 6'd0;
        @(posedge clk);

        // A context cannot be committed before every dependency plane is
        // present, and no physical plane may be programmed with an address
        // hole.  Plane 8 is the array-context commit transaction.
        write_image_word(1'b0, 4'd0, 8'd0,
            m3_generated_image_word(4'd0, 8'd0), 1'b0);
        check(!active_image_ok,
              "partial context transaction leaves image uncertified");
        write_image_word(1'b0, 4'd1, 8'd2,
            m3_generated_image_word(4'd1, 8'd2), 1'b1);
        write_image_word(1'b0, 4'd8, 8'd0,
            m3_generated_image_word(4'd8, 8'd0), 1'b1);
        write_image_word(1'b0, 4'd10, 8'd2,
            m3_generated_image_word(4'd10, 8'd2), 1'b1);
        finalize_array_image(1'b0, 1'b1,
            `RECON_CONTEXT_ERROR_IMAGE_WRITE);

        direct_array_mode = 1'b1;
        direct_array_launch(8'd0);
        timeout = 0;
        while (!array_fault_valid && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(array_fault_valid && array_fault_code ==
              `RECON_CONTEXT_ERROR_IMAGE_WRITE &&
              commit_count == 32'd0,
              "uncertified image is rejected before context execution");
        @(negedge clk); direct_array_fault_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); direct_array_fault_ready = 1'b0;
        direct_array_mode = 1'b0;

        // Clear the intentionally partial loader transaction before loading
        // the compiler image.  RAM data is not reset, but all validity and
        // ownership state must restart from address zero.
        @(negedge clk); rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk);
        write_memory_configuration(6'd0, M3_MEMORY_CONFIGURATION_0, 1'b0);

        for (address = 0; address < M3_ARRAY_CONTEXT_COUNT;
                address = address + 1) begin
            for (plane = 0; plane < 8; plane = plane + 1)
                write_image_word(1'b0, plane[3:0], address[7:0],
                    m3_generated_image_word(plane[3:0], address[7:0]), 1'b0);
            write_image_word(1'b0, 4'd9, address[7:0],
                m3_generated_image_word(4'd9, address[7:0]), 1'b0);
            write_image_word(1'b0, 4'd8, address[7:0],
                m3_generated_image_word(4'd8, address[7:0]), 1'b0);
        end
        for (address = 0; address < M3_PHASE_INSTRUCTION_COUNT;
                address = address + 1)
            write_image_word(1'b0, 4'd10, address[7:0],
                m3_generated_image_word(4'd10, address[7:0]), 1'b0);
        check(!active_image_ok,
              "complete writes still require explicit CFG finalization");
        finalize_array_image(1'b0, 1'b0, 8'd0);
        check(active_image_ok &&
              active_ctx_count == M3_ARRAY_CONTEXT_COUNT,
              "complete compiler image passes CFG closure before launch");

        // Normal compiler-generated phase/array execution.
        normal_trace_check = 1'b1;
        stream_in_ready = 1'b0;
        predicate_values = 8'd0;
        start_phase_program();
        wait (phase_active);
        write_image_word(1'b0, 4'd0, 8'd0, 72'd0, 1'b1);
        write_memory_configuration(6'd0, M3_MEMORY_CONFIGURATION_0, 1'b1);
        timeout = 0;
        while (!phase_terminal_valid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(phase_terminal_valid && !phase_terminal_error &&
              !phase_terminal_aborted,
              "normal M3 image reaches one successful terminal token");
        check(phase_terminal_code == `RECON_STOP_ITERATION_LIMIT,
              "phase COMPLETE stop reason is preserved");
        check(array_event_index == M3_EXPECTED_ARRAY_EVENT_COUNT,
              "complete compiler array trace was observed");
        check(phase_event_index == M3_PHASE_INSTRUCTION_COUNT,
              "complete compiler phase trace was observed");
        check(commit_count == 32'd9 &&
              guaranteed_count == 32'd7 &&
              elastic_count == 32'd2 &&
              stall_count == 32'd4,
              "N1 guaranteed/elastic telemetry is exact");
        normal_trace_check = 1'b0;
        consume_phase_terminal();

        // Abort is delayed until array PC6, the first declared safe point.
        stream_in_ready = 1'b1;
        predicate_values[2] = 1'b1;
        abort_request = 1'b0;
        start_phase_program();
        wait (array_active);
        @(negedge clk); abort_request = 1'b1;
        @(posedge clk);
        @(negedge clk); abort_request = 1'b0;
        timeout = 0;
        while (!phase_terminal_valid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(phase_terminal_valid && phase_terminal_aborted &&
              !phase_terminal_error,
              "safe-point abort reaches an aborted terminal token");
        check(commit_count == 32'd8,
              "abort does not commit the safe-point context");
        consume_phase_terminal();

        // An entry outside the finalized image is rejected once at launch;
        // no per-cycle bounds comparator is needed on the execution path.
        direct_array_mode = 1'b1;
        direct_array_launch(8'd100);
        timeout = 0;
        while (!array_fault_valid && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(array_fault_valid && array_fault_code ==
              `RECON_CONTEXT_ERROR_ARRAY_CONTROL &&
              array_fault_pc == 8'd100,
              "missing array PC produces an address-specific context fault");
        @(negedge clk); direct_array_fault_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); direct_array_fault_ready = 1'b0;

        // Configuration-time certification rejects corruption before it can
        // enter the resident image.  The rejected patch must not invalidate
        // the already certified context bank.
        write_image_word(1'b0, 4'd0, 8'd0,
            {36'd0, 31'd0, 5'd16}, 1'b1);
        generated_word = m3_generated_image_word(4'd0, 8'd0);
        generated_word[26:24] =
            `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
        write_image_word(1'b0, 4'd0, 8'd0, generated_word, 1'b1);
        generated_word = m3_generated_image_word(4'd9, 8'd0);
        generated_word[4:0] = 5'd31;
        write_image_word(1'b0, 4'd9, 8'd0, generated_word, 1'b1);
        generated_word = m3_generated_image_word(4'd9, 8'd0);
        generated_word[4:0] = `RECON_RESOURCE_OP_ARGMAX;
        write_image_word(1'b0, 4'd9, 8'd0, generated_word, 1'b1);
        generated_word = m3_generated_image_word(4'd8, 8'd0);
        generated_word[36] = 1'b1;
        write_image_word(1'b0, 4'd8, 8'd0, generated_word, 1'b1);
        generated_word = m3_generated_image_word(4'd9, 8'd0);
        generated_word[30] = 1'b1;
        write_image_word(1'b0, 4'd9, 8'd0, generated_word, 1'b1);
        check(active_image_ok,
              "rejected tile/route/resource/cross-plane patches preserve certification");

        // A legal field-level patch can still break CFG closure. It enters the
        // inactive image, invalidates certification and is rejected by the
        // explicit finalize scan until the original target is restored.
        generated_word = m3_generated_image_word(4'd8, 8'd5);
        generated_word[7:0] = 8'd100;
        write_image_word(1'b0, 4'd8, 8'd5, generated_word, 1'b0);
        check(!active_image_ok,
              "legal patch invalidates bank until CFG is re-finalized");
        finalize_array_image(1'b0, 1'b1,
            `RECON_CONTEXT_ERROR_ARRAY_CONTROL);
        check(!active_image_ok,
              "out-of-range branch target fails CFG closure");
        write_image_word(1'b0, 4'd8, 8'd5,
            m3_generated_image_word(4'd8, 8'd5), 1'b0);
        finalize_array_image(1'b0, 1'b0, 8'd0);
        check(active_image_ok,
              "restored CFG can be certified again");

        // Closure covers implicit fallthrough as well as explicit targets.
        // Turning the terminal context into a sequential context is field
        // legal, but its pc+1 edge lies exactly beyond the finalized image.
        generated_word = m3_generated_image_word(
            4'd8, M3_ARRAY_CONTEXT_COUNT - 1);
        generated_word[33] = 1'b0;
        generated_word[10:8] = `RECON_NEXT_PC_MODE_SEQUENTIAL;
        write_image_word(1'b0, 4'd8, M3_ARRAY_CONTEXT_COUNT - 1,
            generated_word, 1'b0);
        finalize_array_image(1'b0, 1'b1,
            `RECON_CONTEXT_ERROR_ARRAY_CONTROL);
        check(!active_image_ok,
              "out-of-range final fallthrough fails CFG closure");
        write_image_word(1'b0, 4'd8, M3_ARRAY_CONTEXT_COUNT - 1,
            m3_generated_image_word(4'd8, M3_ARRAY_CONTEXT_COUNT - 1),
            1'b0);
        finalize_array_image(1'b0, 1'b0, 8'd0);
        check(active_image_ok,
              "terminal context restore closes fallthrough graph");

        if (failures == 0)
            $display("M3 CONTEXT EXECUTION PASS");
        else
            $display("M3 CONTEXT EXECUTION FAIL count=%0d", failures);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: M3 context execution timeout");
        $finish;
    end
endmodule

`default_nettype wire
