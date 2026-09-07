`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "m10_full_refinement_golden.vh"

module tb_m8_nested_operators;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam [35:0] ARRAY_ENABLE = 36'h180000000;
    localparam [35:0] RESOURCE_RESTART_A = 36'h002000800;

    localparam [35:0] STREAM_FORWARD_START = 36'h54a000000;
    localparam [35:0] STREAM_FORWARD_BODY = 36'h604600099;
    localparam [35:0] STREAM_FORWARD_WRITE = 36'ha00080004;
    localparam [35:0] STREAM_RESIDUAL_BODY = 36'h604600089;
    localparam [35:0] STREAM_RESIDUAL_SUB = 36'h600400002;
    localparam [35:0] STREAM_RESIDUAL_WRITE = 36'ha00010004;
    localparam [35:0] STREAM_TRANSPOSE_START = 36'h552000000;
    localparam [35:0] STREAM_TRANSPOSE_BODY = 36'h604200081;
    localparam [35:0] STREAM_TRANSPOSE_WRITE = 36'ha00090004;
    localparam [35:0] STREAM_PHI_STOP = 36'h006000000;
    localparam [35:0] RESOURCE_TRANSPOSE_REDUCE = 36'h079e09341;
    localparam [35:0] RESOURCE_TRANSPOSE_WAIT = 36'h080000301;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg abort_flush = 1'b0;
    reg routine_start = 1'b0;
    wire scalar_state_clear = routine_start;
    reg scalar_preload_valid = 1'b0;
    wire scalar_preload_ready;
    reg scalar_preload_address = 1'b0;
    reg signed [`RECON_ACC_W-1:0] scalar_preload_data = 0;
    wire phi_cache_clear = routine_start;
    reg execution_active = 1'b0;
    reg cycle_valid = 1'b0;
    reg cycle_commit = 1'b0;
    reg [16*36-1:0] tile_ctx = 0;
    reg [35:0] array_ctx = ARRAY_ENABLE;
    reg [35:0] stream_ctx = 0;
    reg [35:0] resource_ctx = 0;
    reg [7:0] predicate_values = 8'h11;
    reg [63:0] active_seed = 64'h0123456789abcdef;
    reg [8:0] active_measurement_count = 9'd32;
    reg [10:0] active_signal_length = 11'd2;
    reg [6:0] active_work_count = 7'd2;
    reg [5:0] selection_k = 6'd2;
    reg [1:0] active_refinement_profile = 2'd0;
    reg [7:0] active_refine_limit = 8'd1;
    reg [4:0] active_normal_residual_shift = 5'd14;
    reg [`RECON_ACC_W-1:0] active_residual_limit = {`RECON_ACC_W{1'b1}};
    reg [17:0] normalizer_mantissa_uq17 = 18'd131072;
    reg [4:0] normalizer_exponent = 5'd0;
    reg cfg_a_valid = 1'b0;
    reg [63:0] cfg_a_data = 0;
    reg cfg_b_valid = 1'b0;
    reg [63:0] cfg_b_data = 0;
    reg cfg_w_valid = 1'b0;
    reg [63:0] cfg_w_data = 0;
    reg phi_cfg_valid = 1'b1;
    reg [63:0] phi_cfg_data = 0;
    reg support_column_valid = 1'b0;
    wire support_column_ready;
    reg [9:0] support_column = 0;
    wire cache_replay_valid;
    wire cache_replay_ready;
    wire [6:0] cache_replay_slot;
    wire [2:0] cache_replay_row_block;
    wire [7:0] cache_replay_tag;
    wire cache_symbol_valid = cache_replay_valid;
    wire cache_symbol_ready;
    wire [31:0] cache_nonzero = 32'hffff_ffff;
    wire [31:0] cache_sign = {32{cache_replay_slot[0]}};
    wire [9:0] cache_column = {3'd0, cache_replay_slot};
    wire [2:0] cache_row_block = cache_replay_row_block;
    wire [7:0] cache_tag = cache_replay_tag;
    reg cache_valid = 1'b1;
    reg scratch_init_valid = 1'b0;
    wire scratch_init_ready;
    reg [2:0] scratch_init_bank = 0;
    reg [8:0] scratch_init_addr = 0;
    reg [71:0] scratch_init_data = 0;
    wire scratch_preload_active = 1'b0;
    wire scratch_preload_p0_valid = 1'b0;
    wire scratch_preload_p0_ready;
    wire scratch_preload_p0_write = 1'b1;
    wire [7:0] scratch_preload_p0_mask = 8'd0;
    wire [71:0] scratch_preload_p0_addr = 72'd0;
    wire [575:0] scratch_preload_p0_data = 576'd0;
    wire scratch_preload_p1_valid = 1'b0;
    wire scratch_preload_p1_ready;
    wire scratch_preload_p1_write = 1'b1;
    wire [7:0] scratch_preload_p1_mask = 8'd0;
    wire [71:0] scratch_preload_p1_addr = 72'd0;
    wire [575:0] scratch_preload_p1_data = 576'd0;
    wire scratch_preload_conflict;
    wire stream_input_ready;
    wire stream_output_ready;
    wire resource_req_ready;
    wire resource_rsp_valid;
    wire operator_fault;
    wire [15:0] operator_fault_detail;
    wire support_remap_event_valid;
    wire support_remap_event_fault;
    wire [6:0] support_remap_dropped_count;
    wire [96*10-1:0] support_remap_dropped_indices;
    wire [96*`RECON_SOLVER_W-1:0] support_remap_dropped_coefficients;
    wire refinement_event_valid;
    wire refinement_certificate_pass;
    wire refinement_restart_required;
    wire refinement_recompute_required;
    wire refinement_replacement_required;
    wire refinement_iteration_advance;
    wire [2:0] refinement_stop_reason;
    wire termination_event_valid;
    wire termination_residual_limit_reached;
    wire [`RECON_ACC_W-1:0] termination_residual_sq;
    wire [5:0] selection_count;
    wire [6:0] resident_work_count;
    wire [6:0] final_support_count;
    wire [96*10-1:0] final_support_indices;
    wire [96*DATA_W-1:0] final_support_coefficients;
    wire [32*DATA_W-1:0] result_scores;
    wire [319:0] result_indices;
    wire [9:0] observed_phi_column;
    wire [2:0] observed_phi_row_block;

    assign cache_replay_ready = cache_symbol_ready;

    m8_operator_harness #(.USE_INTERNAL_PHI_CACHE(0)) dut (
        .run_abort(abort_flush),
        .run_start(routine_start),
        .scalar_clear(scalar_state_clear),
        .scalar_load_valid(scalar_preload_valid),
        .scalar_load_ready(scalar_preload_ready),
        .scalar_load_select(scalar_preload_address),
        .scalar_load_data(scalar_preload_data),
        .cfg_seed(active_seed),
        .cfg_measurement_count(active_measurement_count),
        .cfg_signal_length(active_signal_length),
        .cfg_work_count(active_work_count),
        .cfg_selection_k(selection_k),
        .cfg_normal_residual_shift(active_normal_residual_shift),
        .cfg_refinement_profile(active_refinement_profile),
        .cfg_refine_limit(active_refine_limit),
        .cfg_residual_limit(active_residual_limit),
        .cfg_phi_scale_mantissa_uq17(normalizer_mantissa_uq17),
        .cfg_phi_scale_exponent(normalizer_exponent),
        .phi_support_valid(support_column_valid),
        .phi_support_ready(support_column_ready),
        .phi_support_col(support_column),
        .phi_cache_req_valid(cache_replay_valid),
        .phi_cache_req_ready(cache_replay_ready),
        .phi_cache_req_slot(cache_replay_slot),
        .phi_cache_req_row(cache_replay_row_block),
        .phi_cache_req_tag(cache_replay_tag),
        .phi_cache_rsp_valid(cache_symbol_valid),
        .phi_cache_rsp_ready(cache_symbol_ready),
        .phi_cache_rsp_mask(cache_nonzero),
        .phi_cache_rsp_sign(cache_sign),
        .phi_cache_rsp_col(cache_column),
        .phi_cache_rsp_row(cache_row_block),
        .phi_cache_rsp_tag(cache_tag),
        .phi_cache_ext_valid(cache_valid),
        .scratch_init_wr_data(scratch_init_data),
        .scratch_load_active(scratch_preload_active),
        .scratch_load_p0_valid(scratch_preload_p0_valid),
        .scratch_load_p0_ready(scratch_preload_p0_ready),
        .scratch_load_p0_write(scratch_preload_p0_write),
        .scratch_load_p0_bank_mask(scratch_preload_p0_mask),
        .scratch_load_p0_addr(scratch_preload_p0_addr),
        .scratch_load_p0_wr_data(scratch_preload_p0_data),
        .scratch_load_p1_valid(scratch_preload_p1_valid),
        .scratch_load_p1_ready(scratch_preload_p1_ready),
        .scratch_load_p1_write(scratch_preload_p1_write),
        .scratch_load_p1_bank_mask(scratch_preload_p1_mask),
        .scratch_load_p1_addr(scratch_preload_p1_addr),
        .scratch_load_p1_wr_data(scratch_preload_p1_data),
        .scratch_load_conflict(scratch_preload_conflict),
        .ctx_tile(tile_ctx),
        .ctx_array(array_ctx),
        .ctx_stream(stream_ctx),
        .ctx_resource(resource_ctx),
        .ctx_predicates(predicate_values),
        .resident_count(resident_work_count),
        .profile_phi_generate_fire(),
        .profile_phi_replay_request_fire(),
        .profile_phi_replay_response_fire(),
        .profile_phi_cache_fill_fire(),
        .profile_phi_output_fire(),
        .profile_selection_fire(),
        .*
    );

    integer bank;
    integer context_cycles;
    integer injected_stalls;
    integer transaction_cycles;
    reg enable_random_stalls = 1'b1;
    reg [31:0] random_state = 32'hc001d00d;
    reg phase_begin_valid = 1'b0;
    wire phase_begin_ready;
    reg [2:0] phase_begin_tag = 3'd3;
    reg phase_step_valid = 1'b0;
    wire phase_step_ready;
    wire phase_recompute_request_valid;
    reg phase_recompute_request_ready = 1'b1;
    wire [2:0] phase_recompute_request_tag;
    reg phase_recompute_result_valid = 1'b0;
    wire phase_recompute_result_ready;
    reg [2:0] phase_recompute_result_tag = 3'd3;
    wire phase_result_valid;
    reg phase_result_ready = 1'b1;
    wire [2:0] phase_result_tag;
    wire phase_result_commit;
    wire phase_result_rollback;
    wire phase_result_restart_required;
    wire phase_result_fault;

    m10_refinement_integration u_phase (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .abort_transaction(abort_flush), .begin_valid(phase_begin_valid),
        .begin_ready(phase_begin_ready), .begin_tag(phase_begin_tag),
        .profile(2'd0), .support_count(`M10_SUPPORT_COUNT),
        .measurement_count(active_measurement_count),
        .iteration_limit(8'd1), .max_iterations(8'd1),
        .normal_residual_shift(active_normal_residual_shift),
        .gamma_reference(`M10_GAMMA), .step_valid(phase_step_valid),
        .step_ready(phase_step_ready), .gamma(`M10_GAMMA),
        .gamma_new(`M10_GAMMA_NEXT), .delta(`M10_DELTA),
        .step_saturation(1'b0),
        .recompute_request_valid(phase_recompute_request_valid),
        .recompute_request_ready(phase_recompute_request_ready),
        .recompute_request_tag(phase_recompute_request_tag),
        .recompute_support_count(), .recompute_iterations_used(),
        .trigger_cheap(), .trigger_reliable(), .trigger_profile_boundary(),
        .trigger_final(), .recompute_result_valid(phase_recompute_result_valid),
        .recompute_result_ready(phase_recompute_result_ready),
        .recompute_result_tag(phase_recompute_result_tag),
        .normal_residual_sq(`M10_GAMMA_NEXT), .recompute_breakdown(1'b0),
        .recompute_saturation(1'b0), .result_valid(phase_result_valid),
        .result_ready(phase_result_ready), .result_tag(phase_result_tag),
        .commit_valid(phase_result_commit),
        .rollback_valid(phase_result_rollback),
        .restart_required(phase_result_restart_required),
        .result_fault(phase_result_fault), .iterations_used(),
        .certificate_fail_pulse(), .transaction_active(),
        .full_checks_requested(), .full_checks_completed(),
        .full_checks_skipped(), .reliable_replacements(), .certificate_failures(),
        .committed_transactions(), .rolled_back_transactions()
    );

    function [31:0] lfsr_next;
        input [31:0] value;
        begin
            lfsr_next = {value[30:0],
                value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    function [35:0] tile_word;
        input [4:0] operation;
        input [2:0] source_a;
        input [2:0] source_b;
        begin
            tile_word = 36'd0;
            tile_word[4:0] = operation;
            tile_word[7:5] = source_a;
            tile_word[10:8] = source_b;
        end
    endfunction

    function [63:0] vector_configuration;
        input [8:0] base_address;
        input [15:0] element_count;
        input [2:0] element_format;
        input [2:0] packing_mode;
        input read_enable;
        input write_enable;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[8:0] = base_address;
            value[31:16] = element_count;
            value[43:32] = 12'd1;
            value[48:47] = 2'd3;
            value[51:49] = `RECON_BANK_MODE_CYCLIC;
            value[54:52] = element_format;
            value[57:55] = packing_mode;
            value[58] = read_enable;
            value[59] = write_enable;
            value[62:61] = `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD;
            vector_configuration = value;
        end
    endfunction

    function [63:0] phi_configuration;
        input [2:0] mode;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[31:16] = 16'd2;
            value[43:32] = 12'd1;
            value[48:47] = 2'd0;
            value[51:49] = mode;
            value[54:52] = `RECON_ELEMENT_FORMAT_INDEX10;
            value[57:55] = `RECON_PACKING_MODE_SEVEN;
            value[58] = 1'b1;
            value[62:61] = `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM;
            phi_configuration = value;
        end
    endfunction

    function [35:0] resource_operation;
        input [4:0] operation;
        input [2:0] input_select;
        input [2:0] output_select;
        input [5:0] configuration_id;
        input clear_before;
        input accumulate;
        input commit_after;
        input wait_for_ready;
        input wait_for_result;
        input [3:0] event_id;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[4:0] = operation;
            value[7:5] = input_select;
            value[10:8] = output_select;
            value[16:11] = configuration_id;
            value[20:17] = `RECON_RESOURCE_COUNT_ACTIVE_WORK_COUNT;
            value[24:21] = 4'hf;
            value[27] = clear_before;
            value[28] = accumulate;
            value[29] = commit_after;
            value[30] = wait_for_ready;
            value[31] = wait_for_result;
            value[35:32] = event_id;
            resource_operation = value;
        end
    endfunction

    function [35:0] vector_stream;
        input read_a;
        input read_b;
        input write_w;
        input [5:0] config_a;
        input [5:0] config_b;
        input [5:0] config_w;
        reg [35:0] value;
        begin
            value = 36'd0;
            value[0] = read_a;
            value[1] = read_b;
            value[2] = write_w;
            value[8:3] = config_a;
            value[14:9] = config_b;
            value[20:15] = config_w;
            value[33] = read_a || read_b || write_w;
            value[34] = read_a || read_b;
            value[35] = write_w;
            vector_stream = value;
        end
    endfunction

    function [71:0] s27_word;
        input integer lane0;
        input integer lane1;
        reg signed [26:0] value0;
        reg signed [26:0] value1;
        begin
            value0 = lane0;
            value1 = lane1;
            s27_word = 72'd0;
            s27_word[26:0] = value0;
            s27_word[53:27] = value1;
        end
    endfunction

    function [71:0] d18_word;
        input integer lane0;
        input integer lane1;
        input integer lane2;
        input integer lane3;
        reg signed [17:0] value0;
        reg signed [17:0] value1;
        reg signed [17:0] value2;
        reg signed [17:0] value3;
        begin
            value0 = lane0;
            value1 = lane1;
            value2 = lane2;
            value3 = lane3;
            d18_word = {value3, value2, value1, value0};
        end
    endfunction

    function [71:0] memory_word;
        input integer selected_bank;
        input integer address;
        begin
            case (selected_bank)
                0: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[0].memory[address];
                1: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[1].memory[address];
                2: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[2].memory[address];
                3: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[3].memory[address];
                4: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[4].memory[address];
                5: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[5].memory[address];
                6: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[6].memory[address];
                default: memory_word = dut.u_scratchpad_subsystem.u_memory.g_bank[7].memory[address];
            endcase
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s detail=%h time=%0t stream=%h resource=%h",
                message, operator_fault_detail, $time, stream_ctx, resource_ctx);
            $display("gather=%b low_valid=%b phi_mode=%0d row=%0d item=%0d complete=%b",
                dut.u_vector_ingress.transpose_mode,
                dut.u_vector_ingress.transpose_low_valid,
                dut.phi_mode,
                dut.u_column_flow.expected_row_major_row_block,
                dut.u_column_flow.row_major_item_count,
                dut.u_column_flow.row_major_stream_complete);
            $finish;
        end
    endtask

    task set_tiles;
        input [35:0] word;
        integer tile;
        begin
            for (tile = 0; tile < 16; tile = tile + 1)
                tile_ctx[tile*36 +: 36] = word;
        end
    endtask

    task reset_operator;
        begin
            execution_active = 1'b0;
            cycle_valid = 1'b0;
            cycle_commit = 1'b0;
            stream_ctx = 36'd0;
            resource_ctx = 36'd0;
            set_tiles(36'd0);
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task init_bank_word;
        input [2:0] selected_bank;
        input [8:0] address;
        input [71:0] data;
        begin
            @(negedge clk);
            scratch_init_bank = selected_bank;
            scratch_init_addr = address;
            scratch_init_data = data;
            scratch_init_valid = 1'b1;
            while (scratch_init_ready !== 1'b1) begin
                @(posedge clk); #1;
                if (operator_fault) fail("fault during scratchpad init");
            end
            @(posedge clk); #1;
            @(negedge clk);
            scratch_init_valid = 1'b0;
        end
    endtask

    task start_routine;
        begin
            execution_active = 1'b1;
            @(negedge clk);
            routine_start = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            routine_start = 1'b0;
        end
    endtask

    task apply_context;
        input [35:0] stream_word;
        input [35:0] resource_word;
        input [35:0] tile_value;
        begin
            @(negedge clk);
            stream_ctx = stream_word;
            resource_ctx = resource_word;
            set_tiles(tile_value);
            cycle_valid = 1'b1;
            cycle_commit = 1'b0;
            context_cycles = 0;
            #1;
            while ((stream_input_ready !== 1'b1) ||
                   (stream_output_ready !== 1'b1) ||
                   (resource_req_ready !== 1'b1) ||
                   (resource_rsp_valid !== 1'b1)) begin
                @(posedge clk); #1;
                context_cycles = context_cycles + 1;
                if (operator_fault) fail("fault while waiting for context");
                if (context_cycles > 800) begin
                    $display("timeout m5_pending=%b rsp=%b/%b c0=%b/%b c1=%b/%b stages=%b%b%b%b normal=%b/%b completed=%b",
                        dut.u_m5.router.pending_valid,
                        dut.u_m5.reduction_rsp_valid, dut.u_m5.reduction_rsp_ready,
                        dut.u_m5.reduction_fabric.cluster0_valid,
                        dut.u_m5.reduction_fabric.cluster0_ready,
                        dut.u_m5.reduction_fabric.cluster1_valid,
                        dut.u_m5.reduction_fabric.cluster1_ready,
                        dut.u_m5.reduction_fabric.merge.stage1_valid,
                        dut.u_m5.reduction_fabric.merge.stage2_valid,
                        dut.u_m5.reduction_fabric.merge.stage3_valid,
                        dut.u_m5.reduction_fabric.merge.stage4_valid,
                        dut.normalizer_input_ready, dut.normalizer_output_valid,
                        dut.u_column_flow.completed_column_valid);
                    $display("cursor ready=%b req=%b a_active=%b inflight=%b held=%b remaining=%0d spvalid=%b physical=%b lowcap=%b transport_commit=%b",
                        dut.cursor_restart_ready, dut.vec_req_valid,
                        dut.u_stream_engine.a_active, dut.u_stream_engine.a_inflight,
                        dut.u_stream_engine.a_response_held,
                        dut.u_stream_engine.a_remaining_elements,
                        dut.stream_p0_rd_valid, dut.physical_vec_a_valid,
                        dut.u_vector_ingress.transpose_low_capture,
                        dut.vec_transport_commit);
                    $display("vector rsp=%b/%b tag=%0d pending_tag=%0d raw_out=%b w_active=%b w_id=%0d cfg_w=%0d w_remaining=%0d result=%b ready=%b",
                        dut.u_m5.vector_rsp_valid, dut.u_m5.vector_rsp_ready,
                        dut.u_m5.vector_rsp_tag, dut.u_m5.router.pending_tag[2],
                        dut.raw_vec_out_ready, dut.u_stream_engine.w_active,
                        dut.u_stream_engine.w_configuration_id, dut.vec_cfg_w,
                        dut.u_stream_engine.w_remaining_elements,
                        dut.vector_result_valid, dut.m5_vector_result_ready);
                    fail("context readiness timeout");
                end
            end
            random_state = lfsr_next(random_state);
            injected_stalls = enable_random_stalls ? random_state[1:0] : 0;
            repeat (injected_stalls) begin
                @(posedge clk); #1;
                if (operator_fault) fail("fault under injected stall");
            end
            while ((stream_input_ready !== 1'b1) ||
                   (stream_output_ready !== 1'b1) ||
                   (resource_req_ready !== 1'b1) ||
                   (resource_rsp_valid !== 1'b1)) begin
                @(posedge clk); #1;
                if (operator_fault) fail("fault while rewaiting context");
            end
            @(negedge clk);
            cycle_commit = 1'b1;
            @(posedge clk); #1;
            if (operator_fault) fail("fault on committed context");
            @(negedge clk);
            cycle_valid = 1'b0;
            cycle_commit = 1'b0;
            stream_ctx = 36'd0;
            resource_ctx = 36'd0;
            set_tiles(36'd0);
            transaction_cycles = transaction_cycles + context_cycles +
                                 injected_stalls + 1;
        end
    endtask

    task phase_begin;
        begin
            @(negedge clk);
            phase_begin_valid = 1'b1;
            while (!phase_begin_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            phase_begin_valid = 1'b0;
        end
    endtask

    task phase_step;
        begin
            @(negedge clk);
            phase_step_valid = 1'b1;
            while (!phase_step_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            phase_step_valid = 1'b0;
            while (!phase_recompute_request_valid) @(posedge clk);
            if (phase_recompute_request_tag != phase_begin_tag)
                fail("phase recompute tag mismatch");
        end
    endtask

    task phase_complete_recompute;
        begin
            @(negedge clk);
            phase_recompute_result_valid = 1'b1;
            while (!phase_recompute_result_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            phase_recompute_result_valid = 1'b0;
            while (!phase_result_valid) @(posedge clk);
            if (phase_result_tag != phase_begin_tag || !phase_result_commit ||
                phase_result_rollback || phase_result_restart_required ||
                phase_result_fault) begin
                $display("phase result tag=%0d commit=%b rollback=%b restart=%b fault=%b gamma=%h delta=%h gamma_new=%h state=%0d",
                    phase_result_tag, phase_result_commit,
                    phase_result_rollback, phase_result_restart_required,
                    phase_result_fault, `M10_GAMMA, `M10_DELTA,
                    `M10_GAMMA_NEXT, u_phase.u_state.state);
                fail("phase terminal result mismatch");
            end
            @(posedge clk);
        end
    endtask

    task vector_norm;
        input [8:0] base_address;
        input [5:0] configuration_id;
        input [15:0] element_count;
        input [2:0] output_select;
        integer stripe;
        integer stripe_count;
        reg [35:0] issue_resource;
        begin
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(base_address, element_count,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO,
                1'b1, 1'b0);
            cfg_b_valid = 1'b0;
            cfg_w_valid = 1'b0;
            apply_context(36'd0, `M10_RESOURCE_RESTART_A, 36'd0);
            stripe_count = (element_count + 15) / 16;
            for (stripe = 0; stripe < stripe_count; stripe = stripe + 1) begin
                issue_resource = resource_operation(
                    `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ,
                    `RECON_RESOURCE_INPUT_MEMORY_STREAM,
                    (stripe + 1 == stripe_count) ? output_select :
                    `RECON_RESOURCE_OUTPUT_DISCARD, 6'd0,
                    stripe == 0, 1'b1, stripe + 1 == stripe_count,
                    1'b1, 1'b0, 4'd0);
                apply_context(vector_stream(1'b1, 1'b0, 1'b0,
                    configuration_id, 6'd0, 6'd0), issue_resource, 36'd0);
            end
            apply_context(36'd0, resource_operation(
                `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ,
                `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
                6'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 4'd0), 36'd0);
        end
    endtask

    task scalar_divide;
        input [2:0] input_select;
        input [2:0] output_select;
        begin
            apply_context(36'd0, resource_operation(
                `RECON_RESOURCE_OP_SCALAR_DIVIDE, input_select, output_select,
                6'd0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 4'd0), 36'd0);
            apply_context(36'd0, resource_operation(
                `RECON_RESOURCE_OP_SCALAR_DIVIDE,
                `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
                6'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 4'd0), 36'd0);
        end
    endtask

    task vector_axpy;
        input [8:0] base_a;
        input [5:0] config_a;
        input [8:0] base_b;
        input [5:0] config_b;
        input [8:0] base_w;
        input [5:0] config_w;
        input [15:0] element_count;
        input [2:0] scalar_select;
        input subtract;
        integer stripe;
        integer stripe_count;
        begin
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(base_a, element_count,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO,
                1'b1, 1'b0);
            cfg_b_valid = 1'b1;
            cfg_b_data = vector_configuration(base_b, element_count,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO,
                1'b1, 1'b0);
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(base_w, element_count,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO,
                1'b0, 1'b1);
            apply_context(36'd0, `M10_RESOURCE_RESTART_ABW, 36'd0);
            stripe_count = (element_count + 15) / 16;
            for (stripe = 0; stripe < stripe_count; stripe = stripe + 1) begin
                apply_context(vector_stream(1'b1, 1'b1, 1'b0,
                    config_a, config_b, 6'd0), resource_operation(
                    `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY, scalar_select,
                    `RECON_RESOURCE_OUTPUT_MEMORY_STREAM, subtract,
                    1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 4'd0), 36'd0);
                apply_context(vector_stream(1'b0, 1'b0, 1'b1,
                    6'd0, 6'd0, config_w), resource_operation(
                    `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY,
                    `RECON_RESOURCE_INPUT_NONE, `RECON_RESOURCE_OUTPUT_DISCARD,
                    6'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 4'd0), 36'd0);
            end
        end
    endtask

    task run_full_refinement;
        integer phase_start;
        integer forward_cycles;
        integer arithmetic_cycles;
        integer transpose_cycles;
        reg [71:0] expected_word;
        begin
            reset_operator();
            enable_random_stalls = 1'b0;
            transaction_cycles = 0;
            active_measurement_count = `M10_MEASUREMENT_COUNT;
            active_signal_length = 11'd2;
            active_work_count = `M10_SUPPORT_COUNT;
            normalizer_mantissa_uq17 = 18'd131072;
            normalizer_exponent = 5'd0;
            for (bank = 0; bank < 8; bank = bank + 1) begin
                init_bank_word(bank[2:0], `M10_P_BASE,
                    bank == 0 ? s27_word($signed(`M10_P0), $signed(`M10_P1)) : 72'd0);
                init_bank_word(bank[2:0], `M10_G_BASE,
                    bank == 0 ? s27_word($signed(`M10_P0), $signed(`M10_P1)) : 72'd0);
                init_bank_word(bank[2:0], `M10_X_BASE, 72'd0);
                init_bank_word(bank[2:0], `M10_D_BASE, 72'd0);
                init_bank_word(bank[2:0], `M10_D_BASE + 1'b1, 72'd0);
                init_bank_word(bank[2:0], `M10_R_BASE,
                    s27_word($signed(`M10_R_INITIAL), $signed(`M10_R_INITIAL)));
                init_bank_word(bank[2:0], `M10_R_BASE + 1'b1,
                    s27_word($signed(`M10_R_INITIAL), $signed(`M10_R_INITIAL)));
            end
            start_routine();
            phase_begin();

            vector_norm(`M10_G_BASE, 6'd18, 16'd2,
                        `RECON_RESOURCE_OUTPUT_SCALAR_0);
            if (!dut.m5_scalar0_valid || dut.m5_scalar0_data !== `M10_GAMMA)
                fail("full refinement gamma mismatch");

            phase_start = transaction_cycles;
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(`M10_P_BASE, 16'd2,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            cfg_b_valid = 1'b0;
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(`M10_D_BASE, 16'd32,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            phi_cfg_data = phi_configuration(`RECON_BANK_MODE_SUPPORT_ROW_MAJOR);
            apply_context(36'd0, `M10_RESOURCE_RESTART_ABW, 36'd0);
            apply_context(`M10_STREAM_PHI_FORWARD_START, 36'd0, 36'd0);
            apply_context(36'd0, `M10_RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(`M10_STREAM_PHI_FORWARD_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(`M10_STREAM_PHI_FORWARD_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATOR_CAPTURE,
                          `RECON_OPERAND_SOURCE_ZERO, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(`M10_STREAM_PHI_FORWARD_WRITE, 36'd0, 36'd0);
            apply_context(`M10_STREAM_PHI_FORWARD_WRITE, 36'd0, 36'd0);
            apply_context(`M10_STREAM_PHI_STOP, 36'd0, 36'd0);
            forward_cycles = transaction_cycles - phase_start;
            expected_word = s27_word($signed(`M10_D), $signed(`M10_D));
            for (bank = 0; bank < 8; bank = bank + 1)
                if (memory_word(bank, `M10_D_BASE) !== expected_word ||
                    memory_word(bank, `M10_D_BASE + 1'b1) !== expected_word)
                    fail("full refinement d mismatch");

            phase_start = transaction_cycles;
            vector_norm(`M10_D_BASE, 6'd16, 16'd32,
                        `RECON_RESOURCE_OUTPUT_SCALAR_1);
            if (dut.m5_scalar1_data !== `M10_DELTA)
                fail("full refinement delta mismatch");
            scalar_divide(`RECON_RESOURCE_INPUT_SCALAR_0,
                          `RECON_RESOURCE_OUTPUT_SCALAR_1);
            if (dut.m5_scalar1_data[DATA_W-1:0] !== `M10_ALPHA)
                fail("full refinement alpha mismatch");
            vector_axpy(`M10_X_BASE, 6'd17, `M10_P_BASE, 6'd19,
                        `M10_X_BASE, 6'd17, 16'd2,
                        `RECON_RESOURCE_INPUT_SCALAR_1, 1'b0);
            vector_axpy(`M10_R_BASE, 6'd20, `M10_D_BASE, 6'd16,
                        `M10_R_BASE, 6'd20, 16'd32,
                        `RECON_RESOURCE_INPUT_SCALAR_1, 1'b1);
            arithmetic_cycles = transaction_cycles - phase_start;

            phase_start = transaction_cycles;
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(`M10_R_BASE, 16'd32,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            cfg_b_valid = 1'b0;
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(`M10_G_BASE, 16'd2,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            phi_cfg_data = phi_configuration(`RECON_BANK_MODE_CLUSTER_LOCAL);
            apply_context(36'd0, `M10_RESOURCE_RESTART_ABW, 36'd0);
            apply_context(`M10_STREAM_PHI_TRANSPOSE_START, 36'd0, 36'd0);
            apply_context(36'd0, `M10_RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(`M10_STREAM_PHI_TRANSPOSE_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, `M10_RESOURCE_TRANSPOSE_REDUCE, 36'd0);
            apply_context(36'd0, `M10_RESOURCE_TRANSPOSE_WAIT, 36'd0);
            apply_context(`M10_STREAM_PHI_TRANSPOSE_WRITE, 36'd0, 36'd0);
            apply_context(36'd0, `M10_RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(`M10_STREAM_PHI_TRANSPOSE_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL, `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, `M10_RESOURCE_TRANSPOSE_REDUCE, 36'd0);
            apply_context(36'd0, `M10_RESOURCE_TRANSPOSE_WAIT, 36'd0);
            apply_context(`M10_STREAM_PHI_TRANSPOSE_WRITE, 36'd0, 36'd0);
            apply_context(`M10_STREAM_PHI_STOP, 36'd0, 36'd0);
            transpose_cycles = transaction_cycles - phase_start;

            vector_norm(`M10_G_BASE, 6'd18, 16'd2,
                        `RECON_RESOURCE_OUTPUT_SCALAR_1);
            if (dut.m5_scalar1_data !== `M10_GAMMA_NEXT)
                fail("full refinement gamma next mismatch");
            phase_step();
            phase_complete_recompute();

            if (memory_word(0, `M10_X_BASE) !==
                s27_word($signed(`M10_X0_NEXT), $signed(`M10_X1_NEXT)))
                fail("full refinement x mismatch");
            if (memory_word(0, `M10_P_BASE) !==
                s27_word($signed(`M10_P0), $signed(`M10_P1)))
                fail("full refinement p mismatch");
            if (memory_word(0, `M10_G_BASE) !== 72'd0)
                fail("full refinement g mismatch");
            for (bank = 0; bank < 8; bank = bank + 1)
                if (memory_word(bank, `M10_R_BASE) !== 72'd0 ||
                    memory_word(bank, `M10_R_BASE + 1'b1) !== 72'd0)
                    fail("full refinement r mismatch");
            if (forward_cycles != `M10_FORWARD_CYCLES ||
                arithmetic_cycles != `M10_ARITHMETIC_CYCLES ||
                transpose_cycles != `M10_TRANSPOSE_CYCLES ||
                transaction_cycles != `M10_TRANSACTION_CYCLES) begin
                $display("M10 cycle actual forward=%0d arithmetic=%0d transpose=%0d total=%0d expected=%0d,%0d,%0d,%0d",
                    forward_cycles, arithmetic_cycles, transpose_cycles,
                    transaction_cycles, `M10_FORWARD_CYCLES,
                    `M10_ARITHMETIC_CYCLES, `M10_TRANSPOSE_CYCLES,
                    `M10_TRANSACTION_CYCLES);
                fail("full refinement measured cycle mismatch");
            end
            $display("M10 FULL REFINEMENT CYCLES forward=%0d arithmetic=%0d transpose=%0d total=%0d",
                forward_cycles, arithmetic_cycles, transpose_cycles,
                transaction_cycles);
            $display("M10 FULL REFINEMENT TRANSACTION PASS");
            enable_random_stalls = 1'b1;
        end
    endtask

    task run_forward;
        reg [71:0] expected_word;
        begin
            reset_operator();
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(9'd0, 16'd2,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            cfg_b_valid = 1'b0;
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(9'd4, 16'd32,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            phi_cfg_data = phi_configuration(`RECON_BANK_MODE_SUPPORT_ROW_MAJOR);
            init_bank_word(3'd0, 9'd0, s27_word(3, 1));
            for (bank = 1; bank < 8; bank = bank + 1)
                init_bank_word(bank[2:0], 9'd0, 72'd0);
            start_routine();
            apply_context(STREAM_FORWARD_START, 36'd0, 36'd0);
            apply_context(36'd0, RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_FORWARD_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_FORWARD_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATOR_CAPTURE,
                          `RECON_OPERAND_SOURCE_ZERO,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_FORWARD_WRITE, 36'd0, 36'd0);
            apply_context(STREAM_FORWARD_WRITE, 36'd0, 36'd0);
            apply_context(STREAM_PHI_STOP, 36'd0, 36'd0);
            expected_word = s27_word(-2, -2);
            for (bank = 0; bank < 8; bank = bank + 1) begin
                if (memory_word(bank, 4) !== expected_word)
                    fail("forward low stripe mismatch");
                if (memory_word(bank, 5) !== expected_word) begin
                    $display("forward high bank=%0d actual=%h expected=%h lane16=%0d lane31=%0d phase=%b available=%b",
                        bank, memory_word(bank, 5), expected_word,
                        $signed(dut.lane_result[16*DATA_W +: DATA_W]),
                        $signed(dut.lane_result[31*DATA_W +: DATA_W]),
                        dut.u_cgra_fabric.u_result_buffer.s27_high_select,
                        dut.cgra_result_available);
                    fail("forward high stripe mismatch");
                end
            end
            if (!dut.u_column_flow.row_major_stream_complete)
                fail("forward row-major stream incomplete");
            $display("M8 NESTED FORWARD PASS");
        end
    endtask

    task run_residual;
        reg [71:0] expected_word;
        begin
            reset_operator();
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(9'd0, 16'd2,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            cfg_b_valid = 1'b1;
            cfg_b_data = vector_configuration(9'd4, 16'd32,
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1'b1, 1'b0);
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(9'd8, 16'd32,
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR, 1'b0, 1'b1);
            phi_cfg_data = phi_configuration(`RECON_BANK_MODE_SUPPORT_ROW_MAJOR);
            init_bank_word(3'd0, 9'd0, s27_word(3 <<<
                (`RECON_SOLVER_F - `RECON_DATA_F), 1 <<<
                (`RECON_SOLVER_F - `RECON_DATA_F)));
            for (bank = 1; bank < 8; bank = bank + 1)
                init_bank_word(bank[2:0], 9'd0, 72'd0);
            for (bank = 0; bank < 8; bank = bank + 1)
                init_bank_word(bank[2:0], 9'd4, d18_word(10, 10, 10, 10));
            start_routine();
            apply_context(STREAM_FORWARD_START, 36'd0, 36'd0);
            apply_context(36'd0, RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_RESIDUAL_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_RESIDUAL_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_RESIDUAL_SUB, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_RESIDUAL_CAPTURE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ACCUMULATOR));
            apply_context(STREAM_RESIDUAL_WRITE, 36'd0, 36'd0);
            apply_context(STREAM_PHI_STOP, 36'd0, 36'd0);
            expected_word = d18_word(12, 12, 12, 12);
            for (bank = 0; bank < 8; bank = bank + 1)
                if (memory_word(bank, 8) !== expected_word)
                    fail("residual writeback mismatch");
            if (!dut.u_column_flow.row_major_stream_complete)
                fail("residual row-major stream incomplete");
            $display("M8 NESTED RESIDUAL PASS");
        end
    endtask

    task run_transpose;
        reg [71:0] expected_word;
        begin
            reset_operator();
            cfg_a_valid = 1'b1;
            cfg_a_data = vector_configuration(9'd0, 16'd32,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            cfg_b_valid = 1'b0;
            cfg_w_valid = 1'b1;
            cfg_w_data = vector_configuration(9'd4, 16'd2,
                `RECON_ELEMENT_FORMAT_SOLVER27, `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            phi_cfg_data = phi_configuration(`RECON_BANK_MODE_CLUSTER_LOCAL);
            for (bank = 0; bank < 8; bank = bank + 1) begin
                init_bank_word(bank[2:0], 9'd0, s27_word(1, 1));
                init_bank_word(bank[2:0], 9'd1, s27_word(2, 2));
            end
            start_routine();
            apply_context(STREAM_TRANSPOSE_START, 36'd0, 36'd0);

            apply_context(36'd0, RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_TRANSPOSE_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, RESOURCE_TRANSPOSE_REDUCE, 36'd0);
            apply_context(36'd0, RESOURCE_TRANSPOSE_WAIT, 36'd0);
            apply_context(STREAM_TRANSPOSE_WRITE, 36'd0, 36'd0);

            apply_context(36'd0, RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(STREAM_TRANSPOSE_BODY, 36'd0,
                tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                          `RECON_OPERAND_SOURCE_EXTERNAL,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_context(36'd0, RESOURCE_TRANSPOSE_REDUCE, 36'd0);
            apply_context(36'd0, RESOURCE_TRANSPOSE_WAIT, 36'd0);
            apply_context(STREAM_TRANSPOSE_WRITE, 36'd0, 36'd0);
            apply_context(STREAM_PHI_STOP, 36'd0, 36'd0);

            expected_word = s27_word(-48, 48);
            if (memory_word(0, 4) !== expected_word)
                fail("transpose packed scalar mismatch");
            for (bank = 1; bank < 8; bank = bank + 1)
                if (memory_word(bank, 4) !== 72'd0)
                    fail("transpose unused bank mismatch");
            if (dut.u_vector_ingress.transpose_low_valid)
                fail("transpose gather retained stale stripe");
            $display("M8 NESTED TRANSPOSE PASS");
        end
    endtask

    initial begin
        set_tiles(36'd0);
        run_forward();
        run_residual();
        run_transpose();
        run_full_refinement();
        if (operator_fault)
            fail("terminal operator fault");
        $display("M8 NESTED OPERATORS PASS");
        $finish;
    end
endmodule

`default_nettype wire
