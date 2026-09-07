`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "m6_golden.vh"

module tb_m6_cgra;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer LOCAL_ACC_W = `RECON_LOCAL_ACC_W;
    localparam integer REDUCTION_W = `RECON_ACC_W;
    localparam integer CASE_COUNT = `M6_CASE_COUNT;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg [4:0] alu_operation;
    reg signed [LOCAL_ACC_W-1:0] alu_operand_a;
    reg signed [LOCAL_ACC_W-1:0] alu_operand_b;
    reg signed [LOCAL_ACC_W-1:0] alu_accumulator;
    reg alu_predicate;
    reg alu_phi_nonzero;
    reg alu_phi_sign;
    wire signed [DATA_W-1:0] alu_result;
    wire signed [LOCAL_ACC_W-1:0] alu_accumulator_next;
    wire alu_accumulator_write;
    wire alu_comparison;
    wire alu_saturated;
    wire alu_illegal;

    pe_alu alu (
        .operation(alu_operation), .operand_a(alu_operand_a),
        .operand_b(alu_operand_b), .accumulator(alu_accumulator),
        .selected_predicate(alu_predicate),
        .phi_nonzero(alu_phi_nonzero), .phi_sign(alu_phi_sign),
        .result(alu_result), .accumulator_next(alu_accumulator_next),
        .accumulator_write(alu_accumulator_write),
        .comparison_result(alu_comparison), .saturated(alu_saturated),
        .illegal_operation(alu_illegal)
    );

    wire [CASE_COUNT*5-1:0] golden_operations = `M6_CASE_OPERATIONS;
    wire [CASE_COUNT*LOCAL_ACC_W-1:0] golden_operand_a = `M6_CASE_OPERAND_A;
    wire [CASE_COUNT*LOCAL_ACC_W-1:0] golden_operand_b = `M6_CASE_OPERAND_B;
    wire [CASE_COUNT*LOCAL_ACC_W-1:0] golden_accumulator = `M6_CASE_ACCUMULATOR;
    wire [CASE_COUNT-1:0] golden_predicate = `M6_CASE_PREDICATE;
    wire [CASE_COUNT-1:0] golden_phi_nonzero = `M6_CASE_PHI_NONZERO;
    wire [CASE_COUNT-1:0] golden_phi_sign = `M6_CASE_PHI_SIGN;
    wire [CASE_COUNT*27-1:0] golden_result = `M6_CASE_RESULT;
    wire [CASE_COUNT*LOCAL_ACC_W-1:0] golden_accumulator_next =
        `M6_CASE_ACCUMULATOR_NEXT;
    wire [CASE_COUNT-1:0] golden_accumulator_write =
        `M6_CASE_ACCUMULATOR_WRITE;
    wire [CASE_COUNT-1:0] golden_comparison = `M6_CASE_COMPARISON;
    wire [CASE_COUNT-1:0] golden_saturated = `M6_CASE_SATURATED;

    reg pair_cycle_valid;
    reg pair_cycle_commit;
    reg [1:0] cluster_enable_mask;
    reg [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx;
    reg [`RECON_CLUSTER_COUNT*`RECON_PREDICATE_COUNT-1:0] predicate_values;
    reg [`RECON_PE_COUNT*DATA_W-1:0] external_input;
    reg [`RECON_PE_COUNT*DATA_W-1:0] external_input_b_override;
    reg dual_external_mode;
    wire [`RECON_PE_COUNT*DATA_W-1:0] external_input_a = external_input;
    wire [`RECON_PE_COUNT*DATA_W-1:0] external_input_b =
        dual_external_mode ? external_input_b_override : external_input;
    reg [`RECON_PE_COUNT-1:0] phi_nonzero;
    reg [`RECON_PE_COUNT-1:0] phi_sign;
    reg [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_input;
    reg [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_input;
    reg [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] west_boundary_input;
    reg [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] east_boundary_input;
    wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] north_boundary_output;
    wire [`RECON_CLUSTER_COUNT*`RECON_PE_COLUMNS*DATA_W-1:0] south_boundary_output;
    wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] west_boundary_output;
    wire [`RECON_CLUSTER_COUNT*`RECON_PE_ROWS*DATA_W-1:0] east_boundary_output;
    wire [`RECON_PE_COUNT*DATA_W-1:0] lane_result;
    wire [`RECON_PE_COUNT*LOCAL_ACC_W-1:0] lane_accumulator;
    wire [`RECON_PE_COUNT*REDUCTION_W-1:0] reduction_lane_data;
    wire [`RECON_PE_COUNT-1:0] lane_result_valid;
    wire [1:0] saturation_event;
    wire [1:0] contract_error;

    reg result_clear_event;
    reg result_capture_start_event;
    reg result_capture_valid;
    reg [4:0] result_capture_index;
    reg [DATA_W-1:0] result_capture_data;
    reg result_capture_low_complete;
    reg result_capture_high_complete;
    reg result_consume_d18_event;
    reg result_consume_s27_event;
    wire [`RECON_PE_COUNT*DATA_W-1:0] result_buffer_data;
    wire result_buffer_low_valid;
    wire result_buffer_high_valid;
    wire result_buffer_s27_high_select;
    wire result_buffer_busy;

    cgra_cluster_pair pair (
        .clk(clk), .rst_n(rst_n), .cycle_valid(pair_cycle_valid),
        .cycle_commit(pair_cycle_commit),
        .cluster_enable_mask(cluster_enable_mask), .tile_ctx(tile_ctx),
        .predicate_values(predicate_values),
        .external_input_a(external_input_a),
        .external_input_b(external_input_b),
        .phi_nonzero(phi_nonzero), .phi_sign(phi_sign),
        .north_boundary_input(north_boundary_input),
        .south_boundary_input(south_boundary_input),
        .west_boundary_input(west_boundary_input),
        .east_boundary_input(east_boundary_input),
        .north_boundary_output(north_boundary_output),
        .south_boundary_output(south_boundary_output),
        .west_boundary_output(west_boundary_output),
        .east_boundary_output(east_boundary_output),
        .lane_result(lane_result), .lane_accumulator(lane_accumulator),
        .reduction_lane_data(reduction_lane_data),
        .lane_result_valid(lane_result_valid),
        .saturation_event(saturation_event), .contract_error(contract_error)
    );

    cgra_result_buffer result_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .clear_event(result_clear_event),
        .capture_start_event(result_capture_start_event),
        .capture_valid(result_capture_valid),
        .capture_index(result_capture_index),
        .capture_data(result_capture_data),
        .capture_low_complete(result_capture_low_complete),
        .capture_high_complete(result_capture_high_complete),
        .consume_d18_event(result_consume_d18_event),
        .consume_s27_event(result_consume_s27_event),
        .result_data(result_buffer_data),
        .low_valid(result_buffer_low_valid),
        .high_valid(result_buffer_high_valid),
        .s27_high_select(result_buffer_s27_high_select),
        .busy(result_buffer_busy)
    );

    function [35:0] make_tile_context;
        input [4:0] operation;
        input [2:0] source_a;
        input [2:0] source_b;
        input [2:0] rf_write_address;
        input rf_write_enable;
        input [1:0] predicate_select;
        input predicate_invert;
        input [2:0] north_select;
        input [2:0] east_select;
        input [2:0] south_select;
        input [2:0] west_select;
        reg [35:0] word;
        begin
            word = 36'd0;
            word[4:0] = operation;
            word[7:5] = source_a;
            word[10:8] = source_b;
            word[19:17] = rf_write_address;
            word[20] = rf_write_enable;
            word[22:21] = predicate_select;
            word[23] = predicate_invert;
            word[26:24] = north_select;
            word[29:27] = east_select;
            word[32:30] = south_select;
            word[35:33] = west_select;
            make_tile_context = word;
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task set_all_tiles;
        input [35:0] word;
        integer tile;
        begin
            for (tile = 0; tile < `RECON_PE_PER_CLUSTER; tile = tile + 1)
                tile_ctx[tile*`RECON_TILE_CONTEXT_W +:
                         `RECON_TILE_CONTEXT_W] = word;
        end
    endtask

    task apply_pair_cycle;
        input commit;
        begin
            @(negedge clk);
            pair_cycle_valid = 1'b1;
            pair_cycle_commit = commit;
            @(posedge clk);
            #1;
            @(negedge clk);
            pair_cycle_valid = 1'b0;
            pair_cycle_commit = 1'b0;
        end
    endtask

    integer case_index;
    integer lane;
    integer cluster;
    reg signed [DATA_W-1:0] held_result [0:`RECON_PE_COUNT-1];
    reg signed [LOCAL_ACC_W-1:0] held_accumulator [0:`RECON_PE_COUNT-1];
    reg [35:0] context_word;
    reg signed [DATA_W-1:0] expected_lane;
    reg signed [LOCAL_ACC_W-1:0] expected_accumulator;

    initial begin
        alu_operation = 0;
        alu_operand_a = 0;
        alu_operand_b = 0;
        alu_accumulator = 0;
        alu_predicate = 0;
        alu_phi_nonzero = 0;
        alu_phi_sign = 0;
        pair_cycle_valid = 0;
        pair_cycle_commit = 0;
        cluster_enable_mask = 2'b11;
        tile_ctx = 0;
        predicate_values = 8'h11; // predicate 0 is architected ALWAYS.
        external_input = 0;
        external_input_b_override = 0;
        dual_external_mode = 1'b0;
        phi_nonzero = 32'hffffffff;
        phi_sign = 0;
        north_boundary_input = 0;
        south_boundary_input = 0;
        west_boundary_input = 0;
        east_boundary_input = 0;
        result_clear_event = 0;
        result_capture_start_event = 0;
        result_capture_valid = 0;
        result_capture_index = 0;
        result_capture_data = 0;
        result_capture_low_complete = 0;
        result_capture_high_complete = 0;
        result_consume_d18_event = 0;
        result_consume_s27_event = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Combinational ALU must agree with hardware.py for every legal opcode.
        for (case_index = 0; case_index < CASE_COUNT;
             case_index = case_index + 1) begin
            alu_operation = golden_operations[case_index*5 +: 5];
            alu_operand_a = golden_operand_a[
                case_index*LOCAL_ACC_W +: LOCAL_ACC_W];
            alu_operand_b = golden_operand_b[
                case_index*LOCAL_ACC_W +: LOCAL_ACC_W];
            alu_accumulator = golden_accumulator[
                case_index*LOCAL_ACC_W +: LOCAL_ACC_W];
            alu_predicate = golden_predicate[case_index];
            alu_phi_nonzero = golden_phi_nonzero[case_index];
            alu_phi_sign = golden_phi_sign[case_index];
            #1;
            if (alu_result !== golden_result[case_index*27 +: 27] ||
                alu_accumulator_next !==
                    golden_accumulator_next[
                        case_index*LOCAL_ACC_W +: LOCAL_ACC_W] ||
                alu_accumulator_write !== golden_accumulator_write[case_index] ||
                alu_comparison !== golden_comparison[case_index] ||
                alu_saturated !== golden_saturated[case_index] || alu_illegal)
                fail("PE ALU golden mismatch");
        end
        alu_operation = 5'd16;
        #1;
        if (!alu_illegal)
            fail("reserved tile operation was not rejected");
        $display("M6 PE ALU golden PASS");

        // All 32 PEs consume one shared spatial context, but retain lane data.
        context_word = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 3, 1, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        set_all_tiles(context_word);
        for (lane = 0; lane < 16; lane = lane + 1) begin
            external_input[lane*DATA_W +: DATA_W] = lane + 1;
            external_input[(lane+16)*DATA_W +: DATA_W] = lane + 101;
        end
        apply_pair_cycle(1'b1);
        if (lane_result_valid !== 32'hffffffff)
            fail("shared context did not commit all enabled PEs");
        for (lane = 0; lane < 16; lane = lane + 1) begin
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != lane + 1 ||
                $signed(lane_result[(lane+16)*DATA_W +: DATA_W]) != lane + 101)
                fail("corresponding tile data separation mismatch");
        end

        // The first cycle also wrote RF[3]; two-read local RF must replay it.
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_LOCAL_RF,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD));
        for (lane = 0; lane < 16; lane = lane + 1)
            tile_ctx[lane*36 + 11 +: 3] = 3'd3;
        apply_pair_cycle(1'b1);
        for (lane = 0; lane < 16; lane = lane + 1) begin
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != lane + 1 ||
                $signed(lane_result[(lane+16)*DATA_W +: DATA_W]) != lane + 101)
                fail("local RF replay mismatch");
        end
        set_all_tiles(context_word);

        // Pair-wide stall holds every architectural data state.
        for (lane = 0; lane < 32; lane = lane + 1) begin
            held_result[lane] = lane_result[lane*DATA_W +: DATA_W];
            held_accumulator[lane] =
                lane_accumulator[lane*LOCAL_ACC_W +: LOCAL_ACC_W];
            external_input[lane*DATA_W +: DATA_W] = 27'sd999;
        end
        apply_pair_cycle(1'b0);
        for (lane = 0; lane < 32; lane = lane + 1)
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != held_result[lane] ||
                $signed(lane_accumulator[lane*LOCAL_ACC_W +: LOCAL_ACC_W]) !=
                    held_accumulator[lane])
                fail("pair-wide stall changed PE state");

        // Tail mask updates cluster 0 only.
        cluster_enable_mask = 2'b01;
        apply_pair_cycle(1'b1);
        for (lane = 0; lane < 16; lane = lane + 1) begin
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != 999)
                fail("enabled tail cluster did not update");
            if ($signed(lane_result[(lane+16)*DATA_W +: DATA_W]) != lane + 101)
                fail("disabled cluster changed state");
        end

        // Phi symbol is a zero/sign gate at every homogeneous tile.
        cluster_enable_mask = 2'b11;
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_PHI_SIGN_SCALE, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD));
        phi_nonzero = 32'h55555555;
        phi_sign = 32'h33333333;
        for (lane = 0; lane < 32; lane = lane + 1)
            external_input[lane*DATA_W +: DATA_W] = lane + 1;
        apply_pair_cycle(1'b1);
        for (lane = 0; lane < 32; lane = lane + 1) begin
            expected_lane = !phi_nonzero[lane] ? 0 :
                (phi_sign[lane] ? lane+1 : -(lane+1));
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != expected_lane) begin
                $display("Phi lane=%0d actual=%0d expected=%0d nz=%0b sign=%0b",
                    lane, $signed(lane_result[lane*DATA_W +: DATA_W]),
                    expected_lane, phi_nonzero[lane], phi_sign[lane]);
                fail("Phi lane mapping mismatch");
            end
        end

        // Dedicated boundary planes exercise all four route destinations and
        // EXTERNAL selection; HOLD must preserve their registered values.
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_NOP, `RECON_OPERAND_SOURCE_ZERO,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_EXTERNAL, `RECON_ROUTE_SOURCE_EXTERNAL,
            `RECON_ROUTE_SOURCE_EXTERNAL, `RECON_ROUTE_SOURCE_EXTERNAL));
        apply_pair_cycle(1'b1);
        for (cluster = 0; cluster < `RECON_CLUSTER_COUNT;
                cluster = cluster + 1) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if ($signed(north_boundary_output[
                        (cluster*4+lane)*DATA_W +: DATA_W]) != cluster*16+lane+1 ||
                    $signed(south_boundary_output[
                        (cluster*4+lane)*DATA_W +: DATA_W]) !=
                            cluster*16+12+lane+1 ||
                    $signed(west_boundary_output[
                        (cluster*4+lane)*DATA_W +: DATA_W]) !=
                            cluster*16+lane*4+1 ||
                    $signed(east_boundary_output[
                        (cluster*4+lane)*DATA_W +: DATA_W]) !=
                            cluster*16+lane*4+4)
                    fail("four-direction boundary route mismatch");
            end
        end
        set_all_tiles(36'd0);
        for (lane = 0; lane < 32; lane = lane + 1)
            external_input[lane*DATA_W +: DATA_W] = 27'sd2047;
        apply_pair_cycle(1'b1);
        if ($signed(north_boundary_output[0 +: DATA_W]) != 1 ||
            $signed(east_boundary_output[7*DATA_W +: DATA_W]) != 32)
            fail("switchbox HOLD changed route state");

        cluster_enable_mask = 2'b01;
        set_all_tiles(36'd0);
        tile_ctx[12*36 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_PE_RESULT, `RECON_ROUTE_SOURCE_HOLD);
        external_input[12*DATA_W +: DATA_W] = 27'sd31337;
        apply_pair_cycle(1'b1);
        set_all_tiles(36'd0);
        tile_ctx[12*36 +: 36] = make_tile_context(
            `RECON_TILE_OP_NOP, `RECON_OPERAND_SOURCE_ZERO,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_PE_RESULT, `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        cluster_enable_mask = 2'b10;
        set_all_tiles(36'd0);
        tile_ctx[0 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_NORTH,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        if ($signed(lane_result[16*DATA_W +: DATA_W]) != 31337)
            fail("upper-to-lower column connector mismatch");

        cluster_enable_mask = 2'b10;
        set_all_tiles(36'd0);
        tile_ctx[1*36 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_PE_RESULT, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        external_input[17*DATA_W +: DATA_W] = -27'sd27182;
        apply_pair_cycle(1'b1);
        set_all_tiles(36'd0);
        tile_ctx[1*36 +: 36] = make_tile_context(
            `RECON_TILE_OP_NOP, `RECON_OPERAND_SOURCE_ZERO,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_PE_RESULT, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        cluster_enable_mask = 2'b01;
        set_all_tiles(36'd0);
        tile_ctx[13*36 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_SOUTH,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        if ($signed(lane_result[13*DATA_W +: DATA_W]) != -27182)
            fail("lower-to-upper column connector mismatch");
        cluster_enable_mask = 2'b11;

        // Four registered east hops; no combinational multi-hop exists.
        phi_nonzero = 32'hffffffff;
        phi_sign = 0;
        set_all_tiles(36'd0);
        tile_ctx[0 +: 36] = context_word;
        external_input[0 +: DATA_W] = 27'sd77;
        external_input[16*DATA_W +: DATA_W] = 27'sd177;
        apply_pair_cycle(1'b1);
        tile_ctx[0 +: 36] = make_tile_context(
            `RECON_TILE_OP_NOP, `RECON_OPERAND_SOURCE_ZERO,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_PE_RESULT,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        for (lane = 1; lane < 4; lane = lane + 1) begin
            set_all_tiles(36'd0);
            tile_ctx[lane*36 +: 36] = make_tile_context(
                `RECON_TILE_OP_NOP, `RECON_OPERAND_SOURCE_ZERO,
                `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
                `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_WEST,
                `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD);
            apply_pair_cycle(1'b1);
        end
        if ($signed(east_boundary_output[0 +: DATA_W]) != 77 ||
            $signed(east_boundary_output[4*DATA_W +: DATA_W]) != 177)
            fail("registered east mesh route mismatch");

        // Operand A and B consume independent external planes.
        dual_external_mode = 1'b1;
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_SUB, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_EXTERNAL, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD));
        for (lane = 0; lane < 32; lane = lane + 1) begin
            external_input[lane*DATA_W +: DATA_W] = lane + 100;
            external_input_b_override[lane*DATA_W +: DATA_W] = lane + 1;
        end
        apply_pair_cycle(1'b1);
        for (lane = 0; lane < 32; lane = lane + 1)
            if ($signed(lane_result[lane*DATA_W +: DATA_W]) != 99)
                fail("dual external SUB mismatch");
        dual_external_mode = 1'b0;

        // Predicate false suppresses result, RF, accumulator and route state.
        held_result[0] = lane_result[0 +: DATA_W];
        set_all_tiles(36'd0);
        tile_ctx[0 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 3, 1, 1, 0,
            `RECON_ROUTE_SOURCE_EXTERNAL, `RECON_ROUTE_SOURCE_EXTERNAL,
            `RECON_ROUTE_SOURCE_EXTERNAL, `RECON_ROUTE_SOURCE_EXTERNAL);
        external_input[0 +: DATA_W] = 27'sd1234;
        apply_pair_cycle(1'b1);
        if ($signed(lane_result[0 +: DATA_W]) != held_result[0])
            fail("false predicate changed PE result");

        // Illegal express selection is caught and commits no state.
        tile_ctx[0 +: 36] = make_tile_context(
            `RECON_TILE_OP_PASS, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD);
        apply_pair_cycle(1'b1);
        if (!contract_error[0] ||
            $signed(lane_result[0 +: DATA_W]) != held_result[0])
            fail("illegal express route was not atomic");

        // Fused Phi MAC updates L48 in one context; M5-facing output
        // sign-extends the accumulator to A62.
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_ACCUMULATOR_CLEAR, `RECON_OPERAND_SOURCE_ZERO,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD));
        apply_pair_cycle(1'b1);
        set_all_tiles(make_tile_context(
            `RECON_TILE_OP_PHI_ACCUMULATE, `RECON_OPERAND_SOURCE_EXTERNAL,
            `RECON_OPERAND_SOURCE_ZERO, 0, 0, 0, 0,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD,
            `RECON_ROUTE_SOURCE_HOLD, `RECON_ROUTE_SOURCE_HOLD));
        for (lane = 0; lane < 32; lane = lane + 1)
            external_input[lane*DATA_W +: DATA_W] = lane + 1;
        phi_sign = 32'hffff_ffff;
        apply_pair_cycle(1'b1);
        apply_pair_cycle(1'b1);
        for (lane = 0; lane < 32; lane = lane + 1) begin
            expected_accumulator = 2*(lane+1);
            if ($signed(lane_accumulator[lane*LOCAL_ACC_W +: LOCAL_ACC_W]) !=
                    expected_accumulator ||
                $signed(reduction_lane_data[lane*REDUCTION_W +: REDUCTION_W]) !=
                    expected_accumulator)
                fail("local accumulator/reduction gateway mismatch");
        end

        @(negedge clk);
        result_capture_start_event = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        result_capture_start_event = 1'b0;
        for (lane = 0; lane < `RECON_PE_COUNT; lane = lane + 1) begin
            result_capture_valid = 1'b1;
            result_capture_index = lane[4:0];
            result_capture_data = lane + 100;
            result_capture_low_complete = lane == 15;
            result_capture_high_complete = lane == 31;
            @(posedge clk);
            #1;
            if ((lane == 15) &&
                    (!result_buffer_low_valid || result_buffer_high_valid))
                fail("result buffer low-half completion mismatch");
            @(negedge clk);
        end
        result_capture_valid = 1'b0;
        result_capture_low_complete = 1'b0;
        result_capture_high_complete = 1'b0;
        if (!result_buffer_low_valid || !result_buffer_high_valid ||
                !result_buffer_busy)
            fail("result buffer full capture mismatch");
        for (lane = 0; lane < `RECON_PE_COUNT; lane = lane + 1)
            if ($signed(result_buffer_data[lane*DATA_W +: DATA_W]) !=
                    lane + 100)
                fail("result buffer payload mismatch");

        result_consume_s27_event = 1'b1;
        @(posedge clk);
        #1;
        if (result_buffer_low_valid || !result_buffer_high_valid ||
                !result_buffer_s27_high_select)
            fail("result buffer low S27 consume mismatch");
        @(negedge clk);
        @(posedge clk);
        #1;
        if (result_buffer_low_valid || result_buffer_high_valid ||
                result_buffer_s27_high_select || result_buffer_busy)
            fail("result buffer high S27 consume mismatch");
        @(negedge clk);
        result_consume_s27_event = 1'b0;

        result_capture_valid = 1'b1;
        result_capture_index = 5'd3;
        result_capture_data = 27'sd777;
        result_capture_high_complete = 1'b1;
        result_consume_d18_event = 1'b1;
        @(posedge clk);
        #1;
        if (result_buffer_low_valid || result_buffer_high_valid ||
                result_buffer_busy)
            fail("result buffer D18 consume priority mismatch");
        if ($signed(result_buffer_data[3*DATA_W +: DATA_W]) != 777)
            fail("result buffer capture lost during consume");
        @(negedge clk);
        result_capture_valid = 1'b0;
        result_capture_high_complete = 1'b0;
        result_consume_d18_event = 1'b0;
        $display("M6 RESULT BUFFER PASS");

        if (|saturation_event || |contract_error)
            fail("unexpected terminal event");
        $display("M6 CLUSTER PAIR PASS");
        $finish;
    end
endmodule

`default_nettype wire
