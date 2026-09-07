`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m8_operator_harness;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam [35:0] STREAM_PHI_START = 36'h542000000;
    localparam [35:0] STREAM_CORRELATE = 36'h604200009;
    localparam [35:0] STREAM_PHI_STOP = 36'h006000000;
    localparam [35:0] RESOURCE_RESTART_A = 36'h002000800;
    localparam [35:0] RESOURCE_REDUCE_ISSUE = 36'h079e40541;
    localparam [35:0] RESOURCE_REDUCE_WAIT = 36'h080000501;
    localparam [35:0] RESOURCE_TOPK_PUSH = 36'h1400405e5;
    localparam [35:0] RESOURCE_TOPK_PUSH_WAIT = 36'h180000505;
    localparam [35:0] RESOURCE_TOPK_COMMIT = 36'h240000506;
    localparam [35:0] RESOURCE_TOPK_COMMIT_WAIT = 36'h280000506;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg abort_flush = 0;
    reg routine_start = 0;
    wire scalar_state_clear = routine_start;
    reg scalar_preload_valid = 0;
    wire scalar_preload_ready;
    reg scalar_preload_address = 0;
    reg signed [`RECON_ACC_W-1:0] scalar_preload_data = 0;
    wire phi_cache_clear = routine_start;
    reg execution_active = 0;
    reg cycle_valid = 0;
    reg cycle_commit = 0;
    reg [16*36-1:0] tile_ctx = 0;
    reg [35:0] array_ctx = 0;
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
    reg [4:0] normalizer_exponent = 0;
    reg cfg_a_valid = 1;
    reg [63:0] cfg_a_data = 0;
    reg cfg_b_valid = 0;
    reg [63:0] cfg_b_data = 0;
    reg cfg_w_valid = 0;
    reg [63:0] cfg_w_data = 0;
    reg phi_cfg_valid = 1;
    reg [63:0] phi_cfg_data = 0;
    reg support_column_valid = 0;
    wire support_column_ready;
    reg [9:0] support_column = 0;
    wire cache_replay_valid;
    reg cache_replay_ready = 0;
    wire [6:0] cache_replay_slot;
    wire [2:0] cache_replay_row_block;
    wire [7:0] cache_replay_tag;
    reg cache_symbol_valid = 0;
    wire cache_symbol_ready;
    reg [31:0] cache_nonzero = 0;
    reg [31:0] cache_sign = 0;
    reg [9:0] cache_column = 0;
    reg [2:0] cache_row_block = 0;
    reg [7:0] cache_tag = 0;
    reg cache_valid = 0;
    reg scratch_init_valid = 0;
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

    m8_operator_harness dut (
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

    integer residual [0:31];
    integer expected_score [0:1];
    integer lane;
    integer bank;
    integer column;
    integer cycle_count;
    reg [31:0] random_state = 32'h5a17c0de;

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
        begin
            tile_word = 36'd0;
            tile_word[4:0] = operation;
            tile_word[7:5] = source_a;
        end
    endfunction

    function [63:0] vector_configuration;
        input [15:0] element_count;
        reg [63:0] value;
        begin
            value = 0;
            value[31:16] = element_count;
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

    function [63:0] phi_configuration;
        input [15:0] column_count;
        reg [63:0] value;
        begin
            value = 0;
            value[31:16] = column_count;
            value[43:32] = 12'd1;
            value[48:47] = 2'd0;
            value[51:49] = `RECON_BANK_MODE_LINEAR;
            value[58] = 1'b1;
            value[62:61] = `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM;
            phi_configuration = value;
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s detail=%h time=%0t stream=%h resource=%h",
                     message, operator_fault_detail, $time, stream_ctx, resource_ctx);
            $display("internal stream_error=%b dispatch_error=%b phi_error=%b cgra_error=%b cgra_sat=%b m5_fault=%b pack_error=%b",
                     dut.stream_contract_error, dut.dispatcher_contract_error,
                     dut.u_column_flow.phi_order_error, dut.cgra_contract_error,
                     dut.cgra_saturation, dut.m5_fault_valid,
                     dut.u_vector_codec.write_pack_error);
            $display("provider_cfg=%b selection_fault=%b init_active=%b reduce_issue=%b reduce_accept=%b completed=%b current=%b sticky=%b",
                     dut.phi_cfg_error, dut.selection_fault_valid,
                     scratch_init_valid && execution_active,
                     dut.reduction_issue_context, dut.reduction_accept,
                     dut.u_column_flow.completed_column_valid,
                     dut.u_fault_encoder.fault_event,
                     dut.operator_fault);
            $display("ready stream=%b/%b resource=%b/%b m5=%b/%b pending=%b rsp=%b/%b normalizer=%b/%b colq=%0d reduceq=%0d",
                     stream_input_ready, stream_output_ready,
                     resource_req_ready, resource_rsp_valid,
                     dut.m5_resource_in_ready, dut.m5_resource_out_ready,
                     dut.u_m5.router.pending_valid,
                     dut.u_m5.reduction_rsp_valid,
                     dut.u_m5.reduction_rsp_ready,
                     dut.normalizer_input_ready, dut.normalizer_output_valid,
                     dut.u_column_flow.col_q_count,
                     dut.u_column_flow.reduce_col_count);
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

    task init_bank_word;
        input [2:0] selected_bank;
        input [71:0] data;
        begin
            @(negedge clk);
            scratch_init_bank = selected_bank;
            scratch_init_addr = 0;
            scratch_init_data = data;
            scratch_init_valid = 1;
            while (!scratch_init_ready) begin
                @(posedge clk); #1;
                if (operator_fault) fail("fault during scratchpad init");
            end
            @(posedge clk); #1;
            @(negedge clk);
            scratch_init_valid = 0;
        end
    endtask

    task apply_context;
        input [35:0] stream_word;
        input [35:0] resource_word;
        input [35:0] tile_value;
        integer stalls;
        begin
            @(negedge clk);
            stream_ctx = stream_word;
            resource_ctx = resource_word;
            set_tiles(tile_value);
            cycle_valid = 1;
            cycle_commit = 0;
            cycle_count = 0;
            #1;
            while ((stream_input_ready !== 1'b1) ||
                   (stream_output_ready !== 1'b1) ||
                   (resource_req_ready !== 1'b1) ||
                   (resource_rsp_valid !== 1'b1)) begin
                @(posedge clk); #1;
                cycle_count = cycle_count + 1;
                if (operator_fault) fail("fault while waiting for context");
                if (cycle_count > 500) fail("context readiness timeout");
            end
            random_state = lfsr_next(random_state);
            stalls = random_state[1:0];
            repeat (stalls) begin
                @(posedge clk); #1;
                if (operator_fault) fail("fault under injected stall");
            end
            while ((stream_input_ready !== 1'b1) ||
                   (stream_output_ready !== 1'b1) ||
                   (resource_req_ready !== 1'b1) ||
                   (resource_rsp_valid !== 1'b1)) begin
                @(posedge clk); #1;
                cycle_count = cycle_count + 1;
                if (operator_fault) fail("fault while rewaiting after stall");
                if (cycle_count > 500) fail("context re-readiness timeout");
            end
            @(negedge clk);
            cycle_commit = 1;
            @(posedge clk); #1;
            if (operator_fault) fail("fault on committed context");
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            stream_ctx = 0;
            resource_ctx = 0;
            set_tiles(0);
        end
    endtask

    task apply_correlation_body;
        integer sum;
        begin
            @(negedge clk);
            stream_ctx = STREAM_CORRELATE;
            resource_ctx = 0;
            set_tiles(tile_word(`RECON_TILE_OP_PHI_ACCUMULATE,
                                `RECON_OPERAND_SOURCE_EXTERNAL));
            cycle_valid = 1;
            cycle_commit = 0;
            cycle_count = 0;
            #1;
            while ((stream_input_ready !== 1'b1) ||
                   (stream_output_ready !== 1'b1) ||
                   (resource_req_ready !== 1'b1) ||
                   (resource_rsp_valid !== 1'b1)) begin
                @(posedge clk); #1;
                cycle_count = cycle_count + 1;
                if (operator_fault) fail("fault waiting correlation body");
                if (cycle_count > 500) fail("correlation body timeout");
            end
            sum = 0;
            for (lane = 0; lane < 32; lane = lane + 1)
                if (dut.u_cgra_fabric.routed_phi_nonzero[lane])
                    sum = sum + (dut.u_cgra_fabric.routed_phi_sign[lane] ?
                                residual[lane] : -residual[lane]);
            if (observed_phi_column != column || observed_phi_row_block != 0)
                fail("Phi metadata order mismatch");
            expected_score[column] = sum <<<
                (`RECON_SOLVER_F - `RECON_DATA_F);
            $display("BODY ready col=%0d row=%0d valid=%b ready=%b fire=%b final=%b blocks=%0d provider_active=%b current_col=%0d",
                observed_phi_column, observed_phi_row_block,
                dut.phi_symbol_valid, dut.u_phi_stream.provider_out_ready,
                dut.phi_symbol_fire,
                dut.u_column_flow.final_phi_row_block,
                dut.u_column_flow.active_row_block_count,
                dut.u_phi_stream.u_provider.active,
                dut.u_phi_stream.u_provider.current_column);
            $display("router cmd=%0d phi_input_ready=%b router_in=%b top_in=%b vec_in=%b ext_ready=%b/%b",
                dut.u_cgra_fabric.u_router.phi_cmd_dec,
                dut.u_cgra_fabric.u_router.phi_input_ready,
                dut.router_stream_in_ready, stream_input_ready,
                dut.raw_vec_in_ready, dut.u_cgra_fabric.u_router.ext_a_ready,
                dut.u_cgra_fabric.u_router.ext_b_ready);
            @(negedge clk);
            cycle_commit = 1;
            @(posedge clk); #1;
            if (operator_fault) fail("fault committing correlation body");
            @(negedge clk);
            cycle_valid = 0;
            cycle_commit = 0;
            stream_ctx = 0;
            set_tiles(0);
            $display("BODY done completed=%b completed_col=%0d open=%b",
                dut.u_column_flow.completed_column_valid,
                dut.u_column_flow.completed_phi_column,
                dut.u_column_flow.phi_column_open);
        end
    endtask

    integer best_first;
    integer expected_index0;
    integer expected_index1;
    integer magnitude0;
    integer magnitude1;
    initial begin
        array_ctx[32:31] = 2'b11;
        cfg_a_data = vector_configuration(16'd32);
        phi_cfg_data = phi_configuration(16'd2);
        for (lane = 0; lane < 32; lane = lane + 1)
            residual[lane] = lane + 1;

        repeat (4) @(posedge clk);
        rst_n = 1;
        for (bank = 0; bank < 8; bank = bank + 1)
            init_bank_word(bank[2:0],
                {residual[bank*4+3][17:0], residual[bank*4+2][17:0],
                 residual[bank*4+1][17:0], residual[bank*4][17:0]});

        execution_active = 1;
        @(negedge clk);
        routine_start = 1;
        @(posedge clk); #1;
        @(negedge clk);
        routine_start = 0;

        scalar_preload_address = 1'b0;
        scalar_preload_data = 62'sd131072;
        scalar_preload_valid = 1'b1;
        @(posedge clk); #1;
        while (!scalar_preload_ready) begin
            @(posedge clk); #1;
            if (operator_fault)
                fail("scalar preload not accepted while array idle");
        end
        scalar_preload_valid = 1'b0;
        if (!dut.m5_scalar0_valid || (dut.m5_scalar0_data != 62'sd131072))
            fail("scalar preload RF0 mismatch");

        apply_context(STREAM_PHI_START, 0, 0);
        for (column = 0; column < 2; column = column + 1) begin
            apply_context(0, RESOURCE_RESTART_A,
                tile_word(`RECON_TILE_OP_ACCUMULATOR_CLEAR,
                          `RECON_OPERAND_SOURCE_ZERO));
            apply_correlation_body();
            apply_context(0, RESOURCE_REDUCE_ISSUE, 0);
            apply_context(0, RESOURCE_TOPK_PUSH, 0);
            apply_context(0, RESOURCE_TOPK_PUSH_WAIT, 0);
        end
        apply_context(0, RESOURCE_TOPK_COMMIT, 0);
        apply_context(0, RESOURCE_TOPK_COMMIT_WAIT, 0);
        apply_context(STREAM_PHI_STOP, 0, 0);

        magnitude0 = expected_score[0] < 0 ? -expected_score[0] : expected_score[0];
        magnitude1 = expected_score[1] < 0 ? -expected_score[1] : expected_score[1];
        best_first = (magnitude0 > magnitude1) ||
                     ((magnitude0 == magnitude1) && (0 < 1));
        expected_index0 = best_first ? 0 : 1;
        expected_index1 = best_first ? 1 : 0;
        if (selection_count != 2)
            fail("TOP-K count mismatch");
        if (result_indices[0 +: 10] != expected_index0 ||
            result_indices[10 +: 10] != expected_index1)
            fail("TOP-K index order mismatch");
        if ($signed(result_scores[0 +: DATA_W]) != expected_score[expected_index0] ||
            $signed(result_scores[DATA_W +: DATA_W]) != expected_score[expected_index1]) begin
            fail("TOP-K score order mismatch");
        end
        if (operator_fault)
            fail("terminal operator fault");
        $display("M8 OPERATOR HARNESS PASS scores=%0d,%0d indices=%0d,%0d",
            expected_score[0], expected_score[1],
            result_indices[0 +: 10], result_indices[10 +: 10]);
        $finish;
    end
endmodule

`default_nettype wire
