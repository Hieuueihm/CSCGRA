`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_m8_nested_sequencer;
    localparam [7:0] PC_RESIDUAL_UPDATE = 8'd15;
    localparam [7:0] PC_PHI_SUPPORT_FORWARD = 8'd21;
    localparam [7:0] PC_PHI_SUPPORT_TRANSPOSE = 8'd28;
    localparam [7:0] PC_REFINEMENT_TRANSPOSE = 8'd40;
    localparam [7:0] PC_REFINEMENT_INITIALIZE = 8'd52;
    localparam [7:0] PC_REFINEMENT_PRE_TRANSPOSE = 8'd68;
    localparam [7:0] PC_REFINEMENT_CERTIFICATE = 8'd77;
    localparam [7:0] PC_DENSE_CORRELATION = 8'd102;
    localparam [7:0] PC_TOPK_STREAM = 8'd119;
    localparam [7:0] PC_IHT_SUPPORT_REPLACE = 8'd124;
    localparam [7:0] PC_IHT_DENSE_REBUILD = 8'd134;
    localparam [7:0] PC_IHT_SUPPORT_PACK = 8'd138;
    localparam [7:0] PC_HTP_COEFFICIENT_SCATTER = 8'd142;
    localparam [7:0] PC_HTP_DENSE_SCATTER = 8'd146;
    localparam [7:0] PC_COSAMP_COEFFICIENT_TOPK = 8'd155;
    localparam [7:0] PC_COSAMP_PRUNE = 8'd160;
    localparam [7:0] PC_SP_UNION = 8'd170;
    localparam [7:0] PC_SP_PRUNE = 8'd175;
    localparam [7:0] PC_SP_COEFFICIENT_SCATTER = 8'd185;
    localparam [7:0] PC_SP_ACCEPT = 8'd189;
    localparam [7:0] PC_SP_ROLLBACK = 8'd192;
    localparam [7:0] PC_GP_TOP1 = 8'd195;
    localparam [7:0] PC_GP_LINE_SEARCH = 8'd200;
    localparam [7:0] PC_GP_UPDATE = 8'd215;
    localparam [7:0] PC_GOMP_TOP2 = 8'd219;
    localparam [7:0] PC_GOMP_SUPPORT_UNION = 8'd224;
    localparam [7:0] PC_GP_SUPPORT_POLICY = 8'd232;
    localparam [7:0] PC_GP_DIRECTION_PACK = 8'd237;
    localparam [7:0] PC_MP_DIRECTION_PACK = 8'd241;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer CONTEXT_COUNT = 255;
    localparam [63:0] PRODUCTION_SEED = 64'd23;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg launch_valid = 1'b0;
    wire scalar_state_clear = 1'b0;
    wire phi_cache_clear = 1'b0;
    wire launch_ready;
    reg [7:0] entry_pc = 8'd0;
    reg [3:0] event_id = 4'd0;
    reg abort_pending = 1'b0;
    reg [7:0] sequencer_predicates = 8'h11;
    reg [8:0] active_measurement_count = 9'd33;
    reg [10:0] active_signal_length = 11'd64;
    reg [6:0] active_work_count = 7'd3;
    reg [5:0] selection_k = 6'd3;
    reg [15:0] run_param0 = 16'd2;
    wire [6:0] resident_work_count;
    wire [15:0] run_param1 = {9'd0, resident_work_count};

    wire ctx_rd_en;
    wire [7:0] ctx_rd_addr;
    reg ctx_rd_resp_valid = 1'b0;
    reg ctx_rd_valid = 1'b0;
    reg [7:0] ctx_rd_pc = 8'd0;
    reg [16*36-1:0] ctx_tiles = 0;
    reg [35:0] ctx_array = 0;
    reg [35:0] ctx_stream = 0;
    reg [35:0] ctx_resource = 0;
    wire cycle_valid;
    wire cycle_commit;
    wire cycle_stalled;
    wire [7:0] array_pc;
    wire [1:0] cluster_mask;
    wire [16*36-1:0] tile_ctx;
    wire [35:0] array_ctx;
    wire [35:0] stream_ctx;
    wire [35:0] resource_ctx;
    wire execution_active;
    wire done_valid;
    wire [3:0] done_event_id;
    wire done_aborted;
    wire fault_valid;
    wire [7:0] fault_code;
    wire [7:0] fault_pc;
    wire [31:0] fault_detail;
    wire [31:0] commit_count;
    wire [31:0] guaranteed_count;
    wire [31:0] elastic_count;
    wire [31:0] stall_count;

    reg [71:0] plane0 [0:CONTEXT_COUNT-1];
    reg [71:0] plane1 [0:CONTEXT_COUNT-1];
    reg [71:0] plane2 [0:CONTEXT_COUNT-1];
    reg [71:0] plane3 [0:CONTEXT_COUNT-1];
    reg [71:0] plane4 [0:CONTEXT_COUNT-1];
    reg [71:0] plane5 [0:CONTEXT_COUNT-1];
    reg [71:0] plane6 [0:CONTEXT_COUNT-1];
    reg [71:0] plane7 [0:CONTEXT_COUNT-1];
    reg [71:0] plane8 [0:CONTEXT_COUNT-1];
    reg [35:0] plane9 [0:CONTEXT_COUNT-1];

    initial begin
        $readmemh("array_plane_0.mem", plane0);
        $readmemh("array_plane_1.mem", plane1);
        $readmemh("array_plane_2.mem", plane2);
        $readmemh("array_plane_3.mem", plane3);
        $readmemh("array_plane_4.mem", plane4);
        $readmemh("array_plane_5.mem", plane5);
        $readmemh("array_plane_6.mem", plane6);
        $readmemh("array_plane_7.mem", plane7);
        $readmemh("array_plane_8.mem", plane8);
        $readmemh("array_plane_9.mem", plane9);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ctx_rd_resp_valid <= 1'b0;
            ctx_rd_valid <= 1'b0;
            ctx_rd_pc <= 8'd0;
            ctx_tiles <= 0;
            ctx_array <= 0;
            ctx_stream <= 0;
            ctx_resource <= 0;
        end else begin
            ctx_rd_resp_valid <= ctx_rd_en;
            ctx_rd_valid <= ctx_rd_en && (ctx_rd_addr < CONTEXT_COUNT);
            if (ctx_rd_en) begin
                ctx_rd_pc <= ctx_rd_addr;
                ctx_tiles <= {plane7[ctx_rd_addr], plane6[ctx_rd_addr],
                    plane5[ctx_rd_addr], plane4[ctx_rd_addr],
                    plane3[ctx_rd_addr], plane2[ctx_rd_addr],
                    plane1[ctx_rd_addr], plane0[ctx_rd_addr]};
                ctx_array <= plane8[ctx_rd_addr][35:0];
                ctx_stream <= plane8[ctx_rd_addr][71:36];
                ctx_resource <= plane9[ctx_rd_addr];
            end
        end
    end

    wire harness_stream_input_ready;
    wire harness_stream_output_ready;
    wire harness_resource_req_ready;
    wire harness_resource_rsp_valid;
    reg random_stalls_enabled = 1'b0;
    reg [31:0] random_state = 32'h5eedc0de;
    integer randomized_stall_count = 0;
    integer cycle_valid_count = 0;
    integer observed_commit_count = 0;
    reg check_expected_pc = 1'b1;
    reg [7:0] expected_pc [0:127];
    integer expected_pc_count = 0;

    function [31:0] lfsr_next;
        input [31:0] value;
        begin
            lfsr_next = {value[30:0],
                value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    wire allow_stream_in = !random_stalls_enabled || random_state[0];
    wire allow_stream_out = !random_stalls_enabled || random_state[5];
    wire allow_resource_in = !random_stalls_enabled || random_state[11];
    wire allow_resource_out = !random_stalls_enabled || random_state[17];
    wire sequencer_stream_input_ready =
        harness_stream_input_ready && allow_stream_in;
    wire sequencer_stream_output_ready =
        harness_stream_output_ready && allow_stream_out;
    wire sequencer_resource_req_ready =
        harness_resource_req_ready && allow_resource_in;
    wire sequencer_resource_rsp_valid =
        harness_resource_rsp_valid && allow_resource_out;
    wire stream_waits_input = stream_ctx[`RECON_STREAM_FIELD_STALL_ON_INPUT_LSB];
    wire stream_waits_output = stream_ctx[`RECON_STREAM_FIELD_STALL_ON_OUTPUT_LSB];
    wire resource_waits_ready = resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire resource_waits_result = resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire injected_dependency_block = cycle_valid &&
        ((stream_waits_input && !allow_stream_in) ||
         (stream_waits_output && !allow_stream_out) ||
         (resource_waits_ready && !allow_resource_in) ||
         (resource_waits_result && !allow_resource_out));
    wire harness_cycle_valid = cycle_valid && !injected_dependency_block;
    wire launch_fire = launch_valid && launch_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            random_state <= 32'h5eedc0de;
            randomized_stall_count <= 0;
            cycle_valid_count <= 0;
            observed_commit_count <= 0;
        end else if (launch_fire) begin
            random_state <= 32'h5eedc0de;
            randomized_stall_count <= 0;
            cycle_valid_count <= 0;
            observed_commit_count <= 0;
        end else if (execution_active) begin
            random_state <= lfsr_next(random_state);
            if (cycle_valid)
                cycle_valid_count <= cycle_valid_count + 1;
            if (cycle_stalled && injected_dependency_block)
                randomized_stall_count <= randomized_stall_count + 1;
            if (cycle_commit && check_expected_pc) begin
                if (observed_commit_count >= expected_pc_count ||
                        array_pc !== expected_pc[observed_commit_count]) begin
                    $display("FAIL: sequencer PC mismatch index=%0d pc=%0d expected=%0d",
                        observed_commit_count, array_pc,
                        expected_pc[observed_commit_count]);
                    $finish;
                end
                observed_commit_count <= observed_commit_count + 1;
            end
        end
    end

    array_context_sequencer u_sequencer (
        .clk(clk), .rst_n(rst_n), .launch_valid(launch_valid),
        .launch_ready(launch_ready), .entry_pc(entry_pc), .event_id(event_id),
        .abort_pending(abort_pending), .predicate_values(sequencer_predicates),
        .image_ok(1'b1), .image_count(CONTEXT_COUNT[8:0]),
        .measurement_count(active_measurement_count),
        .signal_length(active_signal_length), .sparsity(active_work_count),
        .outer_limit(16'd8), .refine_limit(8'd4),
        .run_param0(run_param0), .run_param1(run_param1),
        .stream_in_ready(sequencer_stream_input_ready),
        .stream_out_ready(sequencer_stream_output_ready),
        .resource_req_ready(sequencer_resource_req_ready),
        .resource_rsp_valid(sequencer_resource_rsp_valid),
        .ctx_rd_en(ctx_rd_en), .ctx_rd_addr(ctx_rd_addr),
        .ctx_rd_resp_valid(ctx_rd_resp_valid), .ctx_rd_valid(ctx_rd_valid),
        .ctx_rd_pc(ctx_rd_pc), .ctx_tiles(ctx_tiles), .ctx_array(ctx_array),
        .ctx_stream(ctx_stream), .ctx_resource(ctx_resource),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .cycle_stalled(cycle_stalled), .array_pc(array_pc),
        .cluster_mask(cluster_mask), .tile_ctx(tile_ctx), .array_ctx(array_ctx),
        .stream_ctx(stream_ctx), .resource_ctx(resource_ctx),
        .execution_active(execution_active), .done_valid(done_valid),
        .done_ready(1'b1), .done_event_id(done_event_id),
        .done_aborted(done_aborted), .fault_valid(fault_valid),
        .fault_ready(1'b1), .fault_code(fault_code), .fault_pc(fault_pc),
        .fault_detail(fault_detail), .commit_count(commit_count),
        .guaranteed_count(guaranteed_count), .elastic_count(elastic_count),
        .stall_count(stall_count)
    );

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
            value[31:16] = {9'd0, active_work_count};
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

    function [63:0] phi_dense_configuration;
        reg [63:0] value;
        begin
            value = 64'd0;
            value[31:16] = {5'd0, active_signal_length};
            value[43:32] = 12'd1;
            value[48:47] = 2'd0;
            value[51:49] = `RECON_BANK_MODE_LINEAR;
            value[54:52] = `RECON_ELEMENT_FORMAT_RAW32;
            value[57:55] = `RECON_PACKING_MODE_ONE;
            value[58] = 1'b1;
            value[62:61] = `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM;
            phi_dense_configuration = value;
        end
    endfunction

    wire [5:0] cfg_a_id = stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_LSB +: 6];
    wire [5:0] cfg_b_id = stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_LSB +: 6];
    wire [5:0] cfg_w_id = stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_LSB +: 6];
    wire [5:0] phi_cfg_id = stream_ctx[`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_LSB +: 6];
    wire vec_a_enable = stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_A_ENABLE_LSB];
    wire vec_b_enable = stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_B_ENABLE_LSB];
    wire vec_w_enable = stream_ctx[`RECON_STREAM_FIELD_VECTOR_WRITE_ENABLE_LSB];
    wire [1:0] phi_command = stream_ctx[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +: 2];
    reg cfg_a_valid;
    reg [63:0] cfg_a_data;
    reg cfg_b_valid;
    reg [63:0] cfg_b_data;
    reg cfg_w_valid;
    reg [63:0] cfg_w_data;
    reg phi_cfg_valid;
    reg [63:0] phi_cfg_data;
    wire [15:0] padded_measurement_count =
        ({7'd0, active_measurement_count} + 16'd31) & 16'hffe0;

    always @* begin
        cfg_a_valid = vec_a_enable;
        cfg_a_data = 64'd0;
        case (cfg_a_id)
            6'd1: cfg_a_data = vector_configuration(9'd4,
                {7'd0, active_measurement_count},
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR,
                1'b1, 1'b0);
            6'd16: cfg_a_data = vector_configuration(9'd12,
                padded_measurement_count, `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd17: cfg_a_data = vector_configuration(9'd20, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd18: cfg_a_data = vector_configuration(9'd26, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd19: cfg_a_data = vector_configuration(9'd32, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd20: cfg_a_data = vector_configuration(9'd38,
                {7'd0, active_measurement_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd21: cfg_a_data = vector_configuration(9'd46,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd22: cfg_a_data = vector_configuration(9'd110,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd23: cfg_a_data = vector_configuration(9'd174,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd24: begin
                cfg_a_data = vector_configuration(9'd12,
                    padded_measurement_count,
                    `RECON_ELEMENT_FORMAT_SOLVER27,
                    `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
                cfg_a_data[43:32] = 12'd2;
            end
            6'd26: begin
                cfg_a_data = vector_configuration(9'd38,
                    padded_measurement_count,
                    `RECON_ELEMENT_FORMAT_SOLVER27,
                    `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
                cfg_a_data[43:32] = 12'd2;
            end
            default: cfg_a_valid = 1'b0;
        endcase
        cfg_b_valid = vec_b_enable;
        cfg_b_data = 64'd0;
        case (cfg_b_id)
            6'd0: cfg_b_data = vector_configuration(9'd0,
                {7'd0, active_measurement_count},
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR,
                1'b1, 1'b0);
            6'd16: cfg_b_data = vector_configuration(9'd12,
                padded_measurement_count, `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd19: cfg_b_data = vector_configuration(9'd32,
                {9'd0, active_work_count}, `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
            6'd25: begin
                cfg_b_data = vector_configuration(9'd13,
                    padded_measurement_count,
                    `RECON_ELEMENT_FORMAT_SOLVER27,
                    `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
                cfg_b_data[43:32] = 12'd2;
            end
            6'd27: begin
                cfg_b_data = vector_configuration(9'd39,
                    padded_measurement_count,
                    `RECON_ELEMENT_FORMAT_SOLVER27,
                    `RECON_PACKING_MODE_TWO, 1'b1, 1'b0);
                cfg_b_data[43:32] = 12'd2;
            end
            default: cfg_b_valid = 1'b0;
        endcase
        cfg_w_valid = vec_w_enable;
        cfg_w_data = 64'd0;
        case (cfg_w_id)
            6'd1, 6'd2: cfg_w_data = vector_configuration(9'd8,
                {7'd0, active_measurement_count},
                `RECON_ELEMENT_FORMAT_DATA18, `RECON_PACKING_MODE_FOUR,
                1'b0, 1'b1);
            6'd16: cfg_w_data = vector_configuration(9'd12, padded_measurement_count,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd18: cfg_w_data = vector_configuration(9'd26, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd17: cfg_w_data = vector_configuration(9'd20, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd19: cfg_w_data = vector_configuration(9'd32, {9'd0, active_work_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd20: cfg_w_data = vector_configuration(9'd38,
                {7'd0, active_measurement_count},
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd21: cfg_w_data = vector_configuration(9'd46,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd22: cfg_w_data = vector_configuration(9'd110,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            6'd23: cfg_w_data = vector_configuration(9'd174,
                active_signal_length,
                `RECON_ELEMENT_FORMAT_SOLVER27,
                `RECON_PACKING_MODE_TWO, 1'b0, 1'b1);
            default: cfg_w_valid = 1'b0;
        endcase
        phi_cfg_valid = (phi_command != `RECON_PHI_COMMAND_IDLE);
        phi_cfg_data = 64'd0;
        case (phi_cfg_id)
            6'd40, 6'd44: phi_cfg_data = phi_dense_configuration();
            6'd43: phi_cfg_data = phi_configuration(3'd1);
            6'd41: phi_cfg_data = phi_configuration(3'd5);
            6'd42: phi_cfg_data = phi_configuration(3'd3);
            default: if (phi_command == `RECON_PHI_COMMAND_START)
                phi_cfg_valid = 1'b0;
        endcase
    end

    wire support_column_ready;
    wire cache_replay_valid;
    wire cache_replay_ready;
    wire [6:0] cache_replay_slot;
    wire [2:0] cache_replay_row_block;
    wire [7:0] cache_replay_tag;
    wire cache_symbol_valid = cache_replay_valid;
    wire cache_symbol_ready;
    wire [31:0] cache_nonzero =
        (cache_replay_row_block == 0) ? 32'hffff_ffff : 32'h0000_0001;
    function [31:0] production_sign_word;
        input [6:0] slot;
        input [2:0] row_block;
        begin
            case ({slot, row_block})
                10'h000: production_sign_word = 32'h2b71e171;
                10'h001: production_sign_word = 32'hb67dd29e;
                10'h008: production_sign_word = 32'hb339d6ec;
                10'h009: production_sign_word = 32'hc20a7662;
                10'h010: production_sign_word = 32'h4c8e091f;
                10'h011: production_sign_word = 32'hf4df1dbd;
                default: production_sign_word = 32'd0;
            endcase
        end
    endfunction

    wire [31:0] cache_sign =
        production_sign_word(cache_replay_slot, cache_replay_row_block);
    wire [9:0] cache_column = {3'd0, cache_replay_slot};
    wire [2:0] cache_row_block = cache_replay_row_block;
    wire [7:0] cache_tag = cache_replay_tag;
    assign cache_replay_ready = cache_symbol_ready;

    reg scratch_init_valid = 1'b0;
    wire scratch_init_ready;
    reg [2:0] scratch_init_bank = 0;
    reg [8:0] scratch_init_addr = 0;
    reg [71:0] scratch_init_data = 0;
    wire operator_fault;
    wire [15:0] operator_fault_detail;
    wire [5:0] selection_count;
    wire [32*DATA_W-1:0] result_scores;
    wire [319:0] result_indices;
    wire [9:0] observed_phi_column;
    wire [2:0] observed_phi_row_block;

    m8_operator_harness #(.USE_INTERNAL_PHI_CACHE(0)) u_harness (
        .clk(clk), .rst_n(rst_n), .run_abort(1'b0),
        .run_start(launch_fire), .scalar_clear(scalar_state_clear),
        .scalar_load_valid(1'b0), .scalar_load_ready(),
        .scalar_load_select(1'b0),
        .scalar_load_data({`RECON_ACC_W{1'b0}}),
        .phi_cache_clear(phi_cache_clear),
        .execution_active(execution_active),
        .cycle_valid(harness_cycle_valid), .cycle_commit(cycle_commit),
        .ctx_tile(tile_ctx), .ctx_array(array_ctx), .ctx_stream(stream_ctx),
        .ctx_resource(resource_ctx), .ctx_predicates(8'h11),
        .cfg_seed(PRODUCTION_SEED),
        .cfg_measurement_count(active_measurement_count),
        .cfg_signal_length(active_signal_length),
        .cfg_work_count(active_work_count), .cfg_selection_k(selection_k),
        .cfg_refinement_profile(2'd0),
        .cfg_refine_limit(8'd1),
        .cfg_normal_residual_shift(5'd14),
        .cfg_residual_limit({`RECON_ACC_W{1'b1}}),
        .cfg_phi_scale_mantissa_uq17(18'd131072),
        .cfg_phi_scale_exponent(5'd0),
        .cfg_a_valid(cfg_a_valid), .cfg_a_data(cfg_a_data),
        .cfg_b_valid(cfg_b_valid), .cfg_b_data(cfg_b_data),
        .cfg_w_valid(cfg_w_valid), .cfg_w_data(cfg_w_data),
        .phi_cfg_valid(phi_cfg_valid), .phi_cfg_data(phi_cfg_data),
        .phi_support_valid(1'b0), .phi_support_ready(support_column_ready),
        .phi_support_col(10'd0), .phi_cache_req_valid(cache_replay_valid),
        .phi_cache_req_ready(cache_replay_ready),
        .phi_cache_req_slot(cache_replay_slot),
        .phi_cache_req_row(cache_replay_row_block),
        .phi_cache_req_tag(cache_replay_tag),
        .phi_cache_rsp_valid(cache_symbol_valid),
        .phi_cache_rsp_ready(cache_symbol_ready),
        .phi_cache_rsp_mask(cache_nonzero),
        .phi_cache_rsp_sign(cache_sign), .phi_cache_rsp_col(cache_column),
        .phi_cache_rsp_row(cache_row_block), .phi_cache_rsp_tag(cache_tag),
        .phi_cache_ext_valid(1'b1), .scratch_init_valid(scratch_init_valid),
        .scratch_init_ready(scratch_init_ready),
        .scratch_init_bank(scratch_init_bank),
        .scratch_init_addr(scratch_init_addr),
        .scratch_init_wr_data(scratch_init_data),
        .scratch_load_active(1'b0),
        .scratch_load_p0_valid(1'b0), .scratch_load_p0_ready(),
        .scratch_load_p0_write(1'b1),
        .scratch_load_p0_bank_mask(8'd0), .scratch_load_p0_addr(72'd0),
        .scratch_load_p0_wr_data(576'd0),
        .scratch_load_p1_valid(1'b0), .scratch_load_p1_ready(),
        .scratch_load_p1_write(1'b1),
        .scratch_load_p1_bank_mask(8'd0), .scratch_load_p1_addr(72'd0),
        .scratch_load_p1_wr_data(576'd0), .scratch_load_conflict(),
        .stream_input_ready(harness_stream_input_ready),
        .stream_output_ready(harness_stream_output_ready),
        .resource_req_ready(harness_resource_req_ready),
        .resource_rsp_valid(harness_resource_rsp_valid),
        .operator_fault(operator_fault),
        .operator_fault_detail(operator_fault_detail),
        .termination_event_valid(),
        .termination_residual_limit_reached(), .termination_residual_sq(),
        .resident_count(resident_work_count),
        .profile_phi_generate_fire(),
        .profile_phi_replay_request_fire(),
        .profile_phi_replay_response_fire(),
        .profile_phi_cache_fill_fire(),
        .profile_phi_output_fire(),
        .profile_selection_fire(),
        .selection_count(selection_count), .result_scores(result_scores),
        .result_indices(result_indices), .observed_phi_column(observed_phi_column),
        .observed_phi_row_block(observed_phi_row_block)
    );

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
                0: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[0].memory[address];
                1: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[1].memory[address];
                2: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[2].memory[address];
                3: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[3].memory[address];
                4: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[4].memory[address];
                5: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[5].memory[address];
                6: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[6].memory[address];
                default: memory_word = u_harness.u_scratchpad_subsystem.u_memory.g_bank[7].memory[address];
            endcase
        end
    endfunction

    function integer memory_s27_element;
        input integer base_address;
        input integer element_index;
        reg [71:0] word;
        begin
            word = memory_word((element_index % 16) / 2,
                base_address + (element_index / 16));
            if (element_index[0])
                memory_s27_element = $signed(word[53:27]);
            else
                memory_s27_element = $signed(word[26:0]);
        end
    endfunction

    function integer memory_d18_element;
        input integer base_address;
        input integer element_index;
        reg [71:0] word;
        integer lane_index;
        begin
            word = memory_word((element_index % 32) / 4,
                base_address + (element_index / 32));
            lane_index = element_index % 4;
            case (lane_index)
                0: memory_d18_element = $signed(word[17:0]);
                1: memory_d18_element = $signed(word[35:18]);
                2: memory_d18_element = $signed(word[53:36]);
                default: memory_d18_element = $signed(word[71:54]);
            endcase
        end
    endfunction

    function integer signed_phi;
        input integer slot;
        input integer row_index;
        reg [31:0] sign_word;
        begin
            sign_word = production_sign_word(slot[6:0], row_index / 32);
            signed_phi = sign_word[row_index % 32] ? 1 : -1;
        end
    endfunction

    function integer forward_golden;
        input integer row_index;
        begin
            if (row_index >= active_measurement_count)
                forward_golden = 0;
            else
                forward_golden = 3 * signed_phi(0, row_index) +
                    signed_phi(1, row_index) +
                    2 * signed_phi(2, row_index);
        end
    endfunction

    function integer transpose_golden;
        input integer slot;
        integer row_index;
        begin
            transpose_golden = 0;
            for (row_index = 0; row_index < active_measurement_count;
                    row_index = row_index + 1)
                transpose_golden = transpose_golden +
                    signed_phi(slot, row_index);
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s pc=%0d fault=%h seq_fault=%b/%h/%0d/%h time=%0t",
                message, array_pc, operator_fault_detail, fault_valid,
                fault_code, fault_pc, fault_detail, $time);
            $display("phi_lane active=%b residual=%b issue=%0d output=%0d available=%b phase=%b acc0=%0d buffer0=%0d norm=%b/%b/%0d/tag%0d",
                u_harness.u_phi_lane_flow.lane_active,
                u_harness.u_phi_lane_flow.residual_mode,
                u_harness.u_phi_lane_flow.issue_count,
                u_harness.u_phi_lane_flow.output_count,
                u_harness.cgra_result_available,
                u_harness.u_cgra_fabric.u_result_buffer.s27_high_select,
                $signed(u_harness.u_phi_lane_flow.accumulator_buffer[0 +: 48]),
                $signed(u_harness.u_cgra_fabric.u_result_buffer.result_data[0 +: 27]),
                u_harness.normalizer_output_valid,
                u_harness.normalizer_output_ready,
                $signed(u_harness.normalizer_output_data),
                u_harness.normalizer_output_tag);
            $finish;
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

    task clear_words;
        input integer first_address;
        input integer word_count;
        integer selected_bank;
        integer offset;
        begin
            for (offset = 0; offset < word_count; offset = offset + 1)
                for (selected_bank = 0; selected_bank < 8;
                        selected_bank = selected_bank + 1)
                    init_bank_word(selected_bank[2:0], first_address + offset, 72'd0);
        end
    endtask

    task build_expected;
        input [7:0] routine_pc;
        integer outer_index;
        integer inner_index;
        begin
            expected_pc_count = 0;
            expected_pc[expected_pc_count] = routine_pc;
            expected_pc_count = expected_pc_count + 1;
            if (routine_pc == PC_RESIDUAL_UPDATE) begin
                for (outer_index = 0; outer_index < run_param0;
                        outer_index = outer_index + 1) begin
                    expected_pc[expected_pc_count] = PC_RESIDUAL_UPDATE + 1'b1;
                    expected_pc_count = expected_pc_count + 1;
                    for (inner_index = 0; inner_index < active_work_count;
                            inner_index = inner_index + 1) begin
                        expected_pc[expected_pc_count] = PC_RESIDUAL_UPDATE + 2'd2;
                        expected_pc_count = expected_pc_count + 1;
                    end
                    expected_pc[expected_pc_count] = PC_RESIDUAL_UPDATE + 2'd3;
                    expected_pc_count = expected_pc_count + 1;
                    expected_pc[expected_pc_count] = PC_RESIDUAL_UPDATE + 3'd4;
                    expected_pc_count = expected_pc_count + 1;
                end
                expected_pc[expected_pc_count] = PC_RESIDUAL_UPDATE + 3'd5;
                expected_pc_count = expected_pc_count + 1;
            end else if (routine_pc == PC_PHI_SUPPORT_FORWARD) begin
                for (outer_index = 0; outer_index < run_param0;
                        outer_index = outer_index + 1) begin
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 1'b1;
                    expected_pc_count = expected_pc_count + 1;
                    for (inner_index = 0; inner_index < active_work_count;
                            inner_index = inner_index + 1) begin
                        expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 2'd2;
                        expected_pc_count = expected_pc_count + 1;
                    end
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 2'd3;
                    expected_pc_count = expected_pc_count + 1;
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 3'd4;
                    expected_pc_count = expected_pc_count + 1;
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 3'd5;
                    expected_pc_count = expected_pc_count + 1;
                end
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_FORWARD + 3'd6;
                expected_pc_count = expected_pc_count + 1;
            end else begin
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 1'b1;
                expected_pc_count = expected_pc_count + 1;
                for (inner_index = 0; inner_index < run_param0;
                        inner_index = inner_index + 1) begin
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 2'd2;
                    expected_pc_count = expected_pc_count + 1;
                end
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 2'd3;
                expected_pc_count = expected_pc_count + 1;
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 3'd4;
                expected_pc_count = expected_pc_count + 1;
                if (active_work_count == 1) begin
                    expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 3'd5;
                    expected_pc_count = expected_pc_count + 1;
                end else begin
                    for (outer_index = 1; outer_index < active_work_count;
                            outer_index = outer_index + 1) begin
                        expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 3'd6;
                        expected_pc_count = expected_pc_count + 1;
                        for (inner_index = 0; inner_index < run_param0;
                                inner_index = inner_index + 1) begin
                            expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 3'd7;
                            expected_pc_count = expected_pc_count + 1;
                        end
                        expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 4'd8;
                        expected_pc_count = expected_pc_count + 1;
                        expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 4'd9;
                        expected_pc_count = expected_pc_count + 1;
                    end
                end
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 4'd10;
                expected_pc_count = expected_pc_count + 1;
                expected_pc[expected_pc_count] = PC_PHI_SUPPORT_TRANSPOSE + 4'd11;
                expected_pc_count = expected_pc_count + 1;
            end
        end
    endtask

    task reset_system;
        begin
            launch_valid = 1'b0;
            random_stalls_enabled = 1'b0;
            scratch_init_valid = 1'b0;
            rst_n = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk); rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task launch_and_wait;
        input [7:0] routine_pc;
        integer timeout;
        begin
            build_expected(routine_pc);
            check_expected_pc = 1'b1;
            entry_pc = routine_pc;
            event_id = routine_pc[3:0];
            @(negedge clk); launch_valid = 1'b1;
            while (!launch_ready) @(posedge clk);
            @(posedge clk); #1;
            @(negedge clk); launch_valid = 1'b0;
            random_stalls_enabled = 1'b1;
            timeout = 0;
            while (!done_valid) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (operator_fault) fail("operator fault during replay");
                if (fault_valid) fail("sequencer fault during replay");
                if (timeout > 5000) fail("sequencer replay timeout");
            end
            random_stalls_enabled = 1'b0;
            if (done_aborted || done_event_id != routine_pc[3:0])
                fail("done response mismatch");
            if (commit_count != expected_pc_count ||
                    observed_commit_count != expected_pc_count)
                fail("compiler schedule commit count mismatch");
            if (cycle_valid_count != commit_count + stall_count)
                fail("cycle accounting mismatch");
            if (randomized_stall_count == 0)
                fail("random dependency stall not exercised");
            if (guaranteed_count != 1 ||
                    elastic_count + guaranteed_count != commit_count)
                fail("commit class accounting mismatch");
            @(posedge clk); #1;
        end
    endtask

    task launch_and_wait_unchecked;
        input [7:0] routine_pc;
        integer timeout;
        begin
            $display("resident launch pc=%0d", routine_pc);
            check_expected_pc = 1'b0;
            entry_pc = routine_pc;
            event_id = routine_pc[3:0];
            @(negedge clk); launch_valid = 1'b1;
            timeout = 0;
            while (!launch_ready) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (timeout > 100) fail("resident launch-ready timeout");
            end
            @(posedge clk); #1;
            @(negedge clk); launch_valid = 1'b0;
            timeout = 0;
            while (!done_valid) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (operator_fault) fail("operator fault during resident replay");
                if (fault_valid) fail("sequencer fault during resident replay");
                if (timeout > 5000) begin
                    $display("resident debug op=%0d in/out=%b/%b pending=%b owner=%0d support_state=%0d support_rsp=%b refill=%b cache=%b/%b provider=%b done=%b columns=%0d/%0d",
                        u_harness.resource_operation,
                        harness_resource_req_ready, harness_resource_rsp_valid,
                        u_harness.u_dispatcher.pending_valid,
                        u_harness.u_dispatcher.pending_owner,
                        u_harness.u_dispatcher.u_support.state,
                        u_harness.u_dispatcher.support_response_valid,
                        u_harness.phi_cache_refill_pending,
                        u_harness.phi_cache_valid,
                        u_harness.u_phi_stream.status_cache_busy,
                        u_harness.phi_busy, u_harness.phi_done,
                        u_harness.u_dispatcher.u_support.refill_column_slot,
                        u_harness.phi_cache_refill_support_count);
                    fail("resident replay timeout");
                end
            end
            if (done_aborted || done_event_id != routine_pc[3:0])
                fail("resident done response mismatch");
            if (commit_count == 0 || elastic_count + guaranteed_count != commit_count)
                fail("resident commit accounting mismatch");
            $display("resident done pc=%0d commits=%0d", routine_pc,
                commit_count);
            @(posedge clk); #1;
        end
    endtask

    integer bank;
    task run_forward_tail;
        integer row_index;
        integer actual_value;
        integer expected_value;
        begin
            reset_system();
            clear_words(12, 4);
            clear_words(32, 1);
            init_bank_word(3'd0, 9'd32, s27_word(3, 1));
            init_bank_word(3'd1, 9'd32, s27_word(2, 0));
            launch_and_wait(PC_PHI_SUPPORT_FORWARD);
            for (row_index = 0; row_index < 64; row_index = row_index + 1) begin
                actual_value = memory_s27_element(12, row_index);
                expected_value = forward_golden(row_index);
                if (actual_value != expected_value) begin
                    $display("forward row=%0d actual=%0d expected=%0d",
                        row_index, actual_value, expected_value);
                    fail("forward Threefry golden mismatch");
                end
            end
            $display("M8 SEQUENCER FORWARD TAIL PASS commits=%0d stalls=%0d",
                commit_count, stall_count);
        end
    endtask

    task run_residual_tail;
        integer row_index;
        integer actual_value;
        integer expected_value;
        begin
            reset_system();
            clear_words(0, 2);
            clear_words(8, 2);
            clear_words(20, 1);
            init_bank_word(3'd0, 9'd20, s27_word(3 <<<
                (`RECON_SOLVER_F - `RECON_DATA_F), 1 <<<
                (`RECON_SOLVER_F - `RECON_DATA_F)));
            init_bank_word(3'd1, 9'd20, s27_word(2 <<<
                (`RECON_SOLVER_F - `RECON_DATA_F), 0));
            for (bank = 0; bank < 8; bank = bank + 1)
                init_bank_word(bank[2:0], 9'd0, d18_word(10, 10, 10, 10));
            init_bank_word(3'd0, 9'd1, d18_word(10, 0, 0, 0));
            launch_and_wait(PC_RESIDUAL_UPDATE);
            for (row_index = 0; row_index < 64; row_index = row_index + 1) begin
                actual_value = memory_d18_element(8, row_index);
                expected_value = (row_index < active_measurement_count) ?
                    10 - forward_golden(row_index) : 0;
                if (actual_value != expected_value) begin
                    $display("residual row=%0d actual=%0d expected=%0d",
                        row_index, actual_value, expected_value);
                    fail("residual Threefry golden mismatch");
                end
            end
            $display("M8 SEQUENCER RESIDUAL TAIL PASS commits=%0d stalls=%0d",
                commit_count, stall_count);
        end
    endtask

    task run_transpose_tail;
        integer slot_index;
        integer actual_value;
        integer expected_value;
        begin
            reset_system();
            clear_words(12, 4);
            clear_words(26, 1);
            for (bank = 0; bank < 8; bank = bank + 1) begin
                init_bank_word(bank[2:0], 9'd12, s27_word(1, 1));
                init_bank_word(bank[2:0], 9'd13, s27_word(1, 1));
            end
            init_bank_word(3'd0, 9'd14, s27_word(1, 0));
            launch_and_wait(PC_PHI_SUPPORT_TRANSPOSE);
            for (slot_index = 0; slot_index < 16; slot_index = slot_index + 1) begin
                actual_value = memory_s27_element(26, slot_index);
                expected_value = (slot_index < active_work_count) ?
                    transpose_golden(slot_index) : 0;
                if (actual_value != expected_value) begin
                    $display("transpose slot=%0d actual=%0d expected=%0d",
                        slot_index, actual_value, expected_value);
                    fail("transpose Threefry golden mismatch");
                end
            end
            $display("M8 SEQUENCER TRANSPOSE TAIL PASS commits=%0d stalls=%0d",
                commit_count, stall_count);
        end
    endtask

    task run_restricted_refinement_resident;
        begin
            reset_system();
            active_measurement_count = 9'd32;
            active_work_count = 7'd1;
            run_param0 = 16'd1;
            clear_words(12, 4);
            clear_words(20, 1);
            clear_words(26, 1);
            clear_words(32, 1);
            clear_words(38, 2);
            init_bank_word(3'd0, 9'd26, s27_word(3, 1));
            init_bank_word(3'd0, 9'd32, s27_word(3, 1));
            for (bank = 0; bank < 8; bank = bank + 1) begin
                init_bank_word(bank[2:0], 9'd38, s27_word(10, 10));
                init_bank_word(bank[2:0], 9'd39, s27_word(10, 10));
            end
            launch_and_wait_unchecked(PC_REFINEMENT_INITIALIZE);
            launch_and_wait(PC_PHI_SUPPORT_FORWARD);
            launch_and_wait_unchecked(PC_REFINEMENT_PRE_TRANSPOSE);
            launch_and_wait_unchecked(PC_REFINEMENT_TRANSPOSE);
            launch_and_wait_unchecked(PC_REFINEMENT_CERTIFICATE);
            if (!u_harness.m5_scalar0_valid)
                fail("resident scalar state not preserved");
            $display("M10 RESIDENT REFINEMENT REPLAY PASS");
        end
    endtask

    task run_iht_state_resident;
        integer element_index;
        integer actual_value;
        integer expected_value;
        begin
            reset_system();
            active_measurement_count = 9'd32;
            active_signal_length = 11'd20;
            active_work_count = 7'd2;
            selection_k = 6'd2;
            clear_words(174, 2);
            clear_words(46, 2);
            clear_words(20, 1);
            init_bank_word(3'd0, 9'd174, s27_word(1, 100));
            init_bank_word(3'd0, 9'd175, s27_word(2, 200));

            launch_and_wait_unchecked(PC_TOPK_STREAM);
            if (selection_count != 2 ||
                result_indices[0 +: 10] != 10'd17 ||
                result_indices[10 +: 10] != 10'd1)
                fail("IHT TOP-K result mismatch");
            launch_and_wait_unchecked(PC_IHT_SUPPORT_REPLACE);
            launch_and_wait_unchecked(PC_IHT_DENSE_REBUILD);
            for (element_index = 0; element_index < 32;
                    element_index = element_index + 1) begin
                actual_value = memory_s27_element(46, element_index);
                expected_value = (element_index == 1) ? 96 :
                    ((element_index == 17) ? 192 : 0);
                if (actual_value != expected_value) begin
                    $display("IHT dense element=%0d actual=%0d expected=%0d support=%0d,%0d coeff=%0d,%0d",
                        element_index, actual_value, expected_value,
                        u_harness.u_dispatcher.active_support_indices[0 +: 10],
                        u_harness.u_dispatcher.active_support_indices[10 +: 10],
                        $signed(u_harness.u_dispatcher.active_support_coefficients[0 +: 27]),
                        $signed(u_harness.u_dispatcher.active_support_coefficients[27 +: 27]));
                    $display("collector count=%0d req_slot=%0d rsp_valid=%b rsp_index=%0d rsp_value=%0d sorted=%0d",
                        u_harness.u_dispatcher.collector_count,
                        u_harness.u_dispatcher.collector_read_slot,
                        u_harness.u_dispatcher.collector_read_valid,
                        u_harness.u_dispatcher.collector_read_index,
                        $signed(u_harness.u_dispatcher.collector_read_value),
                        u_harness.u_dispatcher.collector_read_sorted_slot);
                    $display("support state=%0d active_bank=%b proposal_bank=%b open=%b view=%b count=%0d/%0d valid0=%h valid1=%h",
                        u_harness.u_dispatcher.u_support.state,
                        u_harness.u_dispatcher.u_support.active_bank,
                        u_harness.u_dispatcher.u_support.proposal_bank,
                        u_harness.u_dispatcher.u_support.proposal_open,
                        u_harness.u_dispatcher.u_support.proposal_view_active,
                        u_harness.u_dispatcher.u_support.bank_count[0],
                        u_harness.u_dispatcher.u_support.bank_count[1],
                        u_harness.u_dispatcher.u_support.bank0_slot_valid,
                        u_harness.u_dispatcher.u_support.bank1_slot_valid);
                    fail("IHT dense rebuild mismatch");
                end
            end
            launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
            if (memory_s27_element(20, 0) != 96 ||
                memory_s27_element(20, 1) != 192)
                fail("IHT support-packed solver_x mismatch");
            init_bank_word(3'd0, 9'd20, s27_word(333, -444));
            launch_and_wait_unchecked(PC_HTP_COEFFICIENT_SCATTER);
            clear_words(46, 2);
            launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
            for (element_index = 0; element_index < 32;
                    element_index = element_index + 1) begin
                actual_value = memory_s27_element(46, element_index);
                expected_value = (element_index == 1) ? 320 :
                    ((element_index == 17) ? -448 : 0);
                if (actual_value != expected_value)
                    fail("HTP refined dense scatter mismatch");
            end
            launch_and_wait_unchecked(PC_COSAMP_COEFFICIENT_TOPK);
            if (selection_count != 2 ||
                result_indices[0 +: 10] != 10'd17 ||
                result_indices[10 +: 10] != 10'd1 ||
                $signed(result_scores[0 +: DATA_W]) != -444 ||
                $signed(result_scores[DATA_W +: DATA_W]) != 333) begin
                $display("CoSaMP topk count=%0d index=%0d,%0d score=%0d,%0d support=%0d,%0d coeff=%0d,%0d",
                    selection_count,
                    result_indices[0 +: 10], result_indices[10 +: 10],
                    $signed(result_scores[0 +: DATA_W]),
                    $signed(result_scores[DATA_W +: DATA_W]),
                    u_harness.u_dispatcher.active_support_indices[0 +: 10],
                    u_harness.u_dispatcher.active_support_indices[10 +: 10],
                    $signed(u_harness.u_dispatcher.active_support_coefficients[0 +: DATA_W]),
                    $signed(u_harness.u_dispatcher.active_support_coefficients[DATA_W +: DATA_W]));
                fail("CoSaMP coefficient TOP-K slot-to-atom remap mismatch");
            end
            launch_and_wait_unchecked(PC_COSAMP_PRUNE);
            launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
            if (memory_s27_element(20, 0) != 320 ||
                memory_s27_element(20, 1) != -448)
                fail("CoSaMP pruned solver_x pack mismatch");
            clear_words(46, 2);
            launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
            for (element_index = 0; element_index < 32;
                    element_index = element_index + 1) begin
                actual_value = memory_s27_element(46, element_index);
                expected_value = (element_index == 1) ? 320 :
                    ((element_index == 17) ? -448 : 0);
                if (actual_value != expected_value)
                    fail("CoSaMP pruned dense scatter mismatch");
            end

            clear_words(174, 2);
            init_bank_word(3'd1, 9'd174, s27_word(10, 300));
            init_bank_word(3'd1, 9'd175, s27_word(20, 400));
            launch_and_wait_unchecked(PC_TOPK_STREAM);
            if (selection_count != 2 ||
                result_indices[0 +: 10] != 10'd19 ||
                result_indices[10 +: 10] != 10'd3)
                fail("SP proposal candidate TOP-K mismatch");
            launch_and_wait_unchecked(PC_SP_UNION);
            if (!u_harness.u_dispatcher.support_proposal_view_active ||
                u_harness.u_dispatcher.active_support_count != 4 ||
                u_harness.u_dispatcher.active_support_indices[0 +: 10] != 10'd1 ||
                u_harness.u_dispatcher.active_support_indices[10 +: 10] != 10'd17 ||
                u_harness.u_dispatcher.active_support_indices[20 +: 10] != 10'd19 ||
                u_harness.u_dispatcher.active_support_indices[30 +: 10] != 10'd3)
                fail("SP deferred union proposal view mismatch");
            active_work_count = 7'd4;
            launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
            if (memory_s27_element(20, 0) != 320 ||
                memory_s27_element(20, 1) != -448 ||
                memory_s27_element(20, 2) != 0 ||
                memory_s27_element(20, 3) != 0)
                fail("SP LS_2K support pack mismatch");
            init_bank_word(3'd0, 9'd20, s27_word(32, -128));
            init_bank_word(3'd1, 9'd20, s27_word(96, 64));
            launch_and_wait_unchecked(PC_SP_COEFFICIENT_SCATTER);
            if ($signed(u_harness.u_dispatcher.active_support_coefficients[
                    0*DATA_W +: DATA_W]) != 32 ||
                $signed(u_harness.u_dispatcher.active_support_coefficients[
                    1*DATA_W +: DATA_W]) != -128 ||
                $signed(u_harness.u_dispatcher.active_support_coefficients[
                    2*DATA_W +: DATA_W]) != 96 ||
                $signed(u_harness.u_dispatcher.active_support_coefficients[
                    3*DATA_W +: DATA_W]) != 64)
                fail("SP proposal coefficient scatter mismatch");
            launch_and_wait_unchecked(PC_COSAMP_COEFFICIENT_TOPK);
            if (selection_count != 2 ||
                result_indices[0 +: 10] != 10'd17 ||
                result_indices[10 +: 10] != 10'd19)
                fail("SP coefficient prune TOP-K mismatch");
            launch_and_wait_unchecked(PC_SP_PRUNE);
            active_work_count = 7'd2;
            if (!u_harness.u_dispatcher.support_proposal_view_active ||
                u_harness.u_dispatcher.active_support_count != 2 ||
                u_harness.u_dispatcher.active_support_indices[0 +: 10] != 10'd17 ||
                u_harness.u_dispatcher.active_support_indices[10 +: 10] != 10'd19)
                fail("SP pruned proposal view mismatch");
            launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
            if (memory_s27_element(20, 0) != -128 ||
                memory_s27_element(20, 1) != 96)
                fail("SP LS_K support pack mismatch");
            init_bank_word(3'd0, 9'd20, s27_word(-500, 600));
            launch_and_wait_unchecked(PC_SP_COEFFICIENT_SCATTER);
            clear_words(46, 2);
            launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
            for (element_index = 0; element_index < 32;
                    element_index = element_index + 1) begin
                actual_value = memory_s27_element(46, element_index);
                expected_value = (element_index == 17) ? -512 :
                    ((element_index == 19) ? 608 : 0);
                if (actual_value != expected_value)
                    fail("SP proposal dense scatter mismatch");
            end
            launch_and_wait_unchecked(PC_SP_ACCEPT);
            if (u_harness.u_dispatcher.support_proposal_view_active ||
                u_harness.u_dispatcher.u_support.transaction_open ||
                u_harness.u_dispatcher.active_support_count != 2)
                fail("SP accepted proposal resolution mismatch");

            clear_words(174, 2);
            init_bank_word(3'd2, 9'd174, s27_word(10, 700));
            init_bank_word(3'd2, 9'd175, s27_word(20, 800));
            launch_and_wait_unchecked(PC_TOPK_STREAM);
            launch_and_wait_unchecked(PC_SP_UNION);
            if (!u_harness.u_dispatcher.support_proposal_view_active ||
                u_harness.u_dispatcher.active_support_count != 4)
                fail("SP rollback proposal view mismatch");
            launch_and_wait_unchecked(PC_SP_ROLLBACK);
            if (u_harness.u_dispatcher.support_proposal_view_active ||
                u_harness.u_dispatcher.u_support.transaction_open ||
                u_harness.u_dispatcher.active_support_count != 2 ||
                u_harness.u_dispatcher.active_support_indices[0 +: 10] != 10'd17 ||
                u_harness.u_dispatcher.active_support_indices[10 +: 10] != 10'd19)
                fail("SP rollback did not preserve accepted support");
            clear_words(46, 2);
            launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
            for (element_index = 0; element_index < 32;
                    element_index = element_index + 1) begin
                actual_value = memory_s27_element(46, element_index);
                expected_value = (element_index == 17) ? -512 :
                    ((element_index == 19) ? 608 : 0);
                if (actual_value != expected_value)
                    fail("SP rollback dense restore mismatch");
            end
            $display("M11 IHT RESIDENT STATE REPLAY PASS");
            $display("M11 HTP COEFFICIENT/DENSE SCATTER REPLAY PASS");
            $display("M11 COSAMP COEFFICIENT PRUNE REPLAY PASS");
            $display("M11 SP PROPOSAL ACCEPT/ROLLBACK REPLAY PASS");
        end
    endtask

    task run_gp_state_resident;
        integer iteration;
        begin
            reset_system();
            active_measurement_count = 9'd32;
            active_signal_length = 11'd20;
            active_work_count = 7'd1;
            selection_k = 6'd1;
            run_param0 = 16'd1;
            clear_words(0, 12);
            clear_words(12, 1);
            clear_words(20, 1);
            clear_words(32, 1);
            clear_words(46, 2);
            clear_words(110, 2);
            for (iteration = 0; iteration < 2; iteration = iteration + 1) begin
                launch_and_wait_unchecked(PC_DENSE_CORRELATION);
                launch_and_wait_unchecked(PC_GP_TOP1);
                if (selection_count != 1)
                    fail("GP top1 selection count mismatch");
                launch_and_wait_unchecked(PC_GP_SUPPORT_POLICY);
                if (u_harness.u_dispatcher.active_support_count != 1 ||
                    u_harness.u_dispatcher.active_support_indices[0 +: 10] !=
                        result_indices[0 +: 10])
                    fail("GP support append/reselection mismatch");
                if (!u_harness.u_dispatcher.active_support_gradient_valid[0])
                    fail("GP active gradient sideband missing");
                launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
                launch_and_wait_unchecked(PC_GP_DIRECTION_PACK);
                launch_and_wait_unchecked(PC_PHI_SUPPORT_FORWARD);
                launch_and_wait_unchecked(PC_GP_LINE_SEARCH);
                launch_and_wait_unchecked(PC_GP_UPDATE);
                launch_and_wait_unchecked(PC_HTP_COEFFICIENT_SCATTER);
                clear_words(46, 2);
                launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
                launch_and_wait_unchecked(PC_RESIDUAL_UPDATE);
            end
            if (u_harness.u_dispatcher.active_support_count != 1)
                fail("GP reselection changed support count");
            $display("M11 GP RESIDENT REPLAY PASS support=%0d gradient_valid=%b",
                u_harness.u_dispatcher.active_support_count,
                u_harness.u_dispatcher.active_support_gradient_valid[0]);
        end
    endtask

    task run_gomp_state_resident;
        begin
            reset_system();
            active_measurement_count = 9'd32;
            active_signal_length = 11'd20;
            active_work_count = 7'd2;
            selection_k = 6'd1;
            run_param0 = 16'd1;
            clear_words(0, 12);
            clear_words(12, 1);
            clear_words(20, 1);
            clear_words(32, 1);
            clear_words(46, 2);
            launch_and_wait_unchecked(PC_DENSE_CORRELATION);
            launch_and_wait_unchecked(PC_GOMP_TOP2);
            if (selection_count != 2)
                fail("gOMP context literal TOP2 mismatch");
            launch_and_wait_unchecked(PC_GOMP_SUPPORT_UNION);
            if (u_harness.u_dispatcher.active_support_count != 2)
                fail("gOMP support union count mismatch");
            launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
            launch_and_wait_unchecked(PC_REFINEMENT_INITIALIZE);
            launch_and_wait_unchecked(PC_PHI_SUPPORT_FORWARD);
            launch_and_wait_unchecked(PC_REFINEMENT_PRE_TRANSPOSE);
            launch_and_wait_unchecked(PC_REFINEMENT_TRANSPOSE);
            launch_and_wait_unchecked(PC_REFINEMENT_CERTIFICATE);
            launch_and_wait_unchecked(PC_HTP_COEFFICIENT_SCATTER);
            launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
            launch_and_wait_unchecked(PC_RESIDUAL_UPDATE);
            $display("M11 GOMP RESIDENT REPLAY PASS support=%0d selection=%0d",
                u_harness.u_dispatcher.active_support_count, selection_count);
        end
    endtask

    task run_mp_state_resident;
        integer iteration;
        begin
            reset_system();
            active_measurement_count = 9'd32;
            active_signal_length = 11'd20;
            active_work_count = 7'd1;
            selection_k = 6'd1;
            run_param0 = 16'd1;
            clear_words(0, 12);
            clear_words(12, 1);
            clear_words(20, 1);
            clear_words(32, 1);
            clear_words(46, 2);
            clear_words(110, 2);
            for (iteration = 0; iteration < 2; iteration = iteration + 1) begin
                launch_and_wait_unchecked(PC_DENSE_CORRELATION);
                launch_and_wait_unchecked(PC_GP_TOP1);
                if (selection_count != 1)
                    fail("MP context literal TOP1 mismatch");
                launch_and_wait_unchecked(PC_GP_SUPPORT_POLICY);
                if (u_harness.u_dispatcher.active_support_count != 1 ||
                    u_harness.u_dispatcher.active_support_indices[0 +: 10] !=
                        result_indices[0 +: 10])
                    fail("MP support append/reselection mismatch");
                if (!u_harness.u_dispatcher.active_support_gradient_valid[0])
                    fail("MP selected gradient sideband missing");
                if (|u_harness.u_dispatcher.active_support_gradient_valid[95:1])
                    fail("MP direction is not rank-one");
                launch_and_wait_unchecked(PC_IHT_SUPPORT_PACK);
                launch_and_wait_unchecked(PC_MP_DIRECTION_PACK);
                launch_and_wait_unchecked(PC_PHI_SUPPORT_FORWARD);
                launch_and_wait_unchecked(PC_GP_LINE_SEARCH);
                launch_and_wait_unchecked(PC_GP_UPDATE);
                launch_and_wait_unchecked(PC_HTP_COEFFICIENT_SCATTER);
                clear_words(46, 2);
                launch_and_wait_unchecked(PC_HTP_DENSE_SCATTER);
                launch_and_wait_unchecked(PC_RESIDUAL_UPDATE);
            end
            if (u_harness.u_dispatcher.active_support_count != 1)
                fail("MP reselection changed support count");
            $display("M11 MP RESIDENT REPLAY PASS support=%0d selection=%0d",
                u_harness.u_dispatcher.active_support_count, selection_count);
        end
    endtask

    initial begin
        run_forward_tail();
        run_residual_tail();
        run_transpose_tail();
        run_restricted_refinement_resident();
        run_iht_state_resident();
        run_gp_state_resident();
        run_gomp_state_resident();
        run_mp_state_resident();
        if (operator_fault || fault_valid)
            fail("terminal replay fault");
        $display("M8 NESTED SEQUENCER PASS seed=%0d M=%0d S=%0d",
            PRODUCTION_SEED, active_measurement_count, active_work_count);
        $finish;
    end
endmodule

`default_nettype wire
