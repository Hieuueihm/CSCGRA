`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"
`include "m5_golden.vh"

module tb_m5_arithmetic;
    localparam integer ACC_W = `RECON_ACC_W;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer LANES = `RECON_SHARED_VECTOR_LANES;
    localparam integer TAG_W = 3;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer cycle_count = 0;
    always @(posedge clk)
        if (rst_n) cycle_count <= cycle_count + 1;
        else cycle_count <= 0;

    reg reduction_req_valid;
    wire reduction_req_ready0;
    wire reduction_req_ready1;
    reg [4:0] reduction_operation;
    reg [TAG_W-1:0] reduction_tag;
    reg [3:0] reduction_lane_mask;
    reg [15:0] reduction_lane_valid;
    reg [16*ACC_W-1:0] cluster0_lane_data;
    reg [16*ACC_W-1:0] cluster1_lane_data;
    reg [159:0] cluster0_lane_index;
    reg [159:0] cluster1_lane_index;
    reg reduction_clear;
    reg reduction_accumulate;
    reg reduction_emit;

    wire c0_valid;
    wire c0_ready;
    wire [4:0] c0_operation;
    wire [TAG_W-1:0] c0_tag;
    wire signed [ACC_W-1:0] c0_data;
    wire [9:0] c0_index;
    wire c0_any;
    wire c0_clear;
    wire c0_accumulate;
    wire c0_emit;
    wire c0_fault;
    wire c1_valid;
    wire c1_ready;
    wire [4:0] c1_operation;
    wire [TAG_W-1:0] c1_tag;
    wire signed [ACC_W-1:0] c1_data;
    wire [9:0] c1_index;
    wire c1_any;
    wire c1_clear;
    wire c1_accumulate;
    wire c1_emit;
    wire c1_fault;
    wire reduction_rsp_valid;
    reg reduction_rsp_ready;
    wire [4:0] reduction_rsp_operation;
    wire [TAG_W-1:0] reduction_rsp_tag;
    wire signed [ACC_W-1:0] reduction_rsp_data;
    wire [9:0] reduction_rsp_index;
    wire reduction_rsp_fault;

    cluster_reduction_unit cluster0 (
        .clk(clk), .rst_n(rst_n), .req_valid(reduction_req_valid),
        .req_ready(reduction_req_ready0), .req_operation(reduction_operation),
        .req_tag(reduction_tag), .req_lane_mask(reduction_lane_mask),
        .req_lane_valid(reduction_lane_valid), .req_lane_data(cluster0_lane_data),
        .req_lane_index(cluster0_lane_index), .req_clear_before(reduction_clear),
        .req_accumulate(reduction_accumulate), .req_emit_result(reduction_emit),
        .rsp_valid(c0_valid), .rsp_ready(c0_ready), .rsp_operation(c0_operation),
        .rsp_tag(c0_tag), .rsp_data(c0_data), .rsp_index(c0_index),
        .rsp_any(c0_any), .rsp_clear_before(c0_clear),
        .rsp_accumulate(c0_accumulate), .rsp_emit_result(c0_emit),
        .rsp_fault(c0_fault)
    );
    cluster_reduction_unit cluster1 (
        .clk(clk), .rst_n(rst_n), .req_valid(reduction_req_valid),
        .req_ready(reduction_req_ready1), .req_operation(reduction_operation),
        .req_tag(reduction_tag), .req_lane_mask(reduction_lane_mask),
        .req_lane_valid(reduction_lane_valid), .req_lane_data(cluster1_lane_data),
        .req_lane_index(cluster1_lane_index), .req_clear_before(reduction_clear),
        .req_accumulate(reduction_accumulate), .req_emit_result(reduction_emit),
        .rsp_valid(c1_valid), .rsp_ready(c1_ready), .rsp_operation(c1_operation),
        .rsp_tag(c1_tag), .rsp_data(c1_data), .rsp_index(c1_index),
        .rsp_any(c1_any), .rsp_clear_before(c1_clear),
        .rsp_accumulate(c1_accumulate), .rsp_emit_result(c1_emit),
        .rsp_fault(c1_fault)
    );
    global_reduction_merge reduction_merge (
        .clk(clk), .rst_n(rst_n),
        .cluster0_valid(c0_valid), .cluster0_ready(c0_ready),
        .cluster0_operation(c0_operation), .cluster0_tag(c0_tag),
        .cluster0_data(c0_data), .cluster0_index(c0_index), .cluster0_any(c0_any),
        .cluster0_clear_before(c0_clear), .cluster0_accumulate(c0_accumulate),
        .cluster0_emit_result(c0_emit), .cluster0_fault(c0_fault),
        .cluster1_valid(c1_valid), .cluster1_ready(c1_ready),
        .cluster1_operation(c1_operation), .cluster1_tag(c1_tag),
        .cluster1_data(c1_data), .cluster1_index(c1_index), .cluster1_any(c1_any),
        .cluster1_clear_before(c1_clear), .cluster1_accumulate(c1_accumulate),
        .cluster1_emit_result(c1_emit), .cluster1_fault(c1_fault),
        .rsp_valid(reduction_rsp_valid), .rsp_ready(reduction_rsp_ready),
        .rsp_operation(reduction_rsp_operation), .rsp_tag(reduction_rsp_tag),
        .rsp_data(reduction_rsp_data), .rsp_index(reduction_rsp_index),
        .rsp_fault(reduction_rsp_fault)
    );

    reg scalar_req_valid;
    wire scalar_req_ready;
    reg [4:0] scalar_operation;
    reg [TAG_W-1:0] scalar_tag;
    reg signed [ACC_W-1:0] scalar_numerator;
    reg signed [ACC_W-1:0] scalar_denominator;
    wire scalar_rsp_valid;
    reg scalar_rsp_ready;
    wire [TAG_W-1:0] scalar_rsp_tag;
    wire signed [DATA_W-1:0] scalar_rsp_result;
    wire scalar_rsp_fault;
    wire [7:0] scalar_rsp_fault_code;
    wire [15:0] scalar_rsp_fault_detail;
    wire scalar_divide_by_zero;
    wire scalar_saturated;

    scalar_function_unit scalar_unit (
        .clk(clk), .rst_n(rst_n), .req_valid(scalar_req_valid),
        .req_ready(scalar_req_ready), .req_operation(scalar_operation),
        .req_tag(scalar_tag), .req_numerator(scalar_numerator),
        .req_denominator(scalar_denominator), .rsp_valid(scalar_rsp_valid),
        .rsp_ready(scalar_rsp_ready), .rsp_tag(scalar_rsp_tag),
        .rsp_result(scalar_rsp_result), .rsp_fault(scalar_rsp_fault),
        .rsp_fault_code(scalar_rsp_fault_code),
        .rsp_fault_detail(scalar_rsp_fault_detail),
        .rsp_divide_by_zero(scalar_divide_by_zero),
        .rsp_saturated(scalar_saturated)
    );

    reg vector_req_valid;
    wire vector_req_ready;
    reg [4:0] vector_operation;
    reg [TAG_W-1:0] vector_tag;
    reg [LANES-1:0] vector_lane_valid;
    reg [LANES*DATA_W-1:0] vector_a;
    reg [LANES*DATA_W-1:0] vector_b;
    reg signed [DATA_W-1:0] vector_scalar;
    reg vector_clear_before;
    reg vector_accumulate;
    reg vector_emit_result;
    reg vector_subtract;
    wire vector_rsp_valid;
    reg vector_rsp_ready;
    wire [4:0] vector_rsp_operation;
    wire [TAG_W-1:0] vector_rsp_tag;
    wire [LANES-1:0] vector_rsp_lane_valid;
    wire [LANES*DATA_W-1:0] vector_rsp_data;
    wire signed [ACC_W-1:0] vector_rsp_scalar;
    wire [LANES-1:0] vector_rsp_saturated;
    wire vector_rsp_fault;

    shared_vector_arithmetic_unit vector_unit (
        .clk(clk), .rst_n(rst_n), .req_valid(vector_req_valid),
        .req_ready(vector_req_ready), .req_operation(vector_operation),
        .req_tag(vector_tag), .req_lane_valid(vector_lane_valid),
        .req_vector_a(vector_a), .req_vector_b(vector_b),
        .req_scalar(vector_scalar), .req_clear_before(vector_clear_before),
        .req_accumulate(vector_accumulate),
        .req_emit_result(vector_emit_result), .req_subtract(vector_subtract),
        .rsp_valid(vector_rsp_valid),
        .rsp_ready(vector_rsp_ready), .rsp_operation(vector_rsp_operation),
        .rsp_tag(vector_rsp_tag), .rsp_lane_valid(vector_rsp_lane_valid),
        .rsp_vector(vector_rsp_data), .rsp_scalar(vector_rsp_scalar),
        .rsp_saturated(vector_rsp_saturated), .rsp_fault(vector_rsp_fault)
    );

    reg rf_write_valid;
    reg rf_commit;
    reg rf_write_address;
    reg [ACC_W-1:0] rf_write_data;
    reg rf_clear_valid;
    reg rf_clear_address;
    reg rf_read_a;
    reg rf_read_b;
    wire [ACC_W-1:0] rf_data_a;
    wire [ACC_W-1:0] rf_data_b;
    wire rf_valid_a;
    wire rf_valid_b;
    reg rf_preload_valid;
    wire rf_preload_ready;
    reg rf_preload_address;
    reg [ACC_W-1:0] rf_preload_data;
    integer last_reduction_accept_cycle;
    integer last_vector_accept_cycle;
    integer first_accept_cycle;
    integer response_count;
    scalar_register_file scalar_rf (
        .clk(clk), .rst_n(rst_n), .clear_all(1'b0), .read_address_a(rf_read_a),
        .read_data_a(rf_data_a), .read_valid_a(rf_valid_a),
        .read_address_b(rf_read_b), .read_data_b(rf_data_b),
        .read_valid_b(rf_valid_b), .preload_valid(rf_preload_valid),
        .preload_ready(rf_preload_ready),
        .preload_address(rf_preload_address), .preload_data(rf_preload_data),
        .write_valid(rf_write_valid),
        .cycle_commit(rf_commit), .write_address(rf_write_address),
        .write_data(rf_write_data), .clear_valid(rf_clear_valid),
        .clear_address(rf_clear_address)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task issue_reduction;
        input [4:0] op;
        input clear;
        input acc;
        input emit;
        begin
            @(negedge clk);
            reduction_operation = op;
            reduction_clear = clear;
            reduction_accumulate = acc;
            reduction_emit = emit;
            reduction_req_valid = 1'b1;
            while (!(reduction_req_ready0 && reduction_req_ready1)) @(negedge clk);
            @(posedge clk);
            while (!(reduction_req_ready0 && reduction_req_ready1)) @(posedge clk);
            #1;
            last_reduction_accept_cycle = cycle_count;
            @(negedge clk);
            reduction_req_valid = 1'b0;
        end
    endtask

    task check_divide;
        input [61:0] numerator;
        input [61:0] denominator;
        input [26:0] expected;
        input expected_zero;
        input expected_sat;
        integer accepted_cycle;
        begin
            @(negedge clk);
            scalar_operation = `RECON_RESOURCE_OP_SCALAR_DIVIDE;
            scalar_numerator = numerator;
            scalar_denominator = denominator;
            scalar_req_valid = 1'b1;
            while (!scalar_req_ready) @(negedge clk);
            @(posedge clk);
            #1;
            accepted_cycle = cycle_count;
            @(negedge clk);
            scalar_req_valid = 1'b0;
            while (!scalar_rsp_valid) @(negedge clk);
            if ((cycle_count - accepted_cycle) !=
                    `RECON_SCALAR_DIVIDE_LATENCY) begin
                $display("DIV LATENCY observed=%0d accepted=%0d current=%0d",
                         cycle_count-accepted_cycle, accepted_cycle, cycle_count);
                fail("scalar divide latency differs from numeric authority");
            end
            if (scalar_rsp_result !== expected)
                fail("scalar divide result mismatch");
            if (scalar_divide_by_zero !== expected_zero)
                fail("scalar divide-by-zero event mismatch");
            if (scalar_saturated !== expected_sat)
                fail("scalar divide saturation mismatch");
            if (scalar_rsp_fault)
                fail("scalar divide raised contract fault");
            @(posedge clk);
        end
    endtask

    task check_reserved_scalar;
        input [4:0] op;
        integer accepted_cycle;
        begin
            @(negedge clk);
            scalar_operation = op;
            scalar_req_valid = 1'b1;
            while (!scalar_req_ready) @(negedge clk);
            @(posedge clk);
            while (!scalar_req_ready) @(posedge clk);
            #1;
            accepted_cycle = cycle_count;
            @(negedge clk);
            scalar_req_valid = 1'b0;
            while (!scalar_rsp_valid) @(negedge clk);
            if ((cycle_count-accepted_cycle) != 1)
                fail("reserved scalar latency is not 1 cycle");
            if (!scalar_rsp_fault ||
                scalar_rsp_fault_code != `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT ||
                scalar_rsp_fault_detail != {3'd1, op, 8'd0})
                fail("reserved scalar operation fault mismatch");
            @(posedge clk);
        end
    endtask

    task check_reserved_scalar_pair;
        integer first_cycle;
        integer second_cycle;
        integer reserved_response_count;
        begin
            @(negedge clk);
            scalar_operation = `RECON_RESOURCE_OP_SCALAR_RECIPROCAL;
            scalar_tag = 3'b001;
            scalar_req_valid = 1'b1;
            while (!scalar_req_ready) @(negedge clk);
            @(posedge clk);
            #1;
            first_cycle = cycle_count;

            @(negedge clk);
            scalar_operation = `RECON_RESOURCE_OP_SCALAR_SQRT;
            scalar_tag = 3'b010;
            while (!scalar_req_ready) @(negedge clk);
            @(posedge clk);
            #1;
            second_cycle = cycle_count;
            if ((second_cycle-first_cycle) != 1)
                fail("reserved scalar initiation interval is not 1");

            @(negedge clk);
            scalar_req_valid = 1'b0;
            reserved_response_count = 0;
            while (reserved_response_count < 2) begin
                if (scalar_rsp_valid) begin
                    if (!scalar_rsp_fault ||
                        scalar_rsp_fault_code != `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT)
                        fail("reserved scalar pipelined fault mismatch");
                    if ((reserved_response_count == 0 &&
                         (scalar_rsp_tag != 3'b001 ||
                          scalar_rsp_fault_detail !=
                          {3'd1, `RECON_RESOURCE_OP_SCALAR_RECIPROCAL, 8'd0})) ||
                        (reserved_response_count == 1 &&
                         (scalar_rsp_tag != 3'b010 ||
                          scalar_rsp_fault_detail !=
                          {3'd1, `RECON_RESOURCE_OP_SCALAR_SQRT, 8'd0})))
                        fail("reserved scalar pipelined ordering mismatch");
                    reserved_response_count = reserved_response_count + 1;
                end
                @(negedge clk);
            end
        end
    endtask

    task issue_vector;
        input [4:0] op;
        input [2:0] tag;
        begin
            @(negedge clk);
            vector_operation = op;
            vector_tag = tag;
            vector_req_valid = 1'b1;
            @(posedge clk);
            while (!vector_req_ready) @(posedge clk);
            #1;
            last_vector_accept_cycle = cycle_count;
            @(negedge clk);
            vector_req_valid = 1'b0;
        end
    endtask

    task check_subtract_axpy;
        reg [LANES*DATA_W-1:0] expected;
        reg signed [DATA_W-1:0] lane_a;
        reg signed [DATA_W-1:0] lane_b;
        reg signed [2*DATA_W-1:0] product;
        integer subtract_lane;
        begin
            expected = 0;
            for (subtract_lane = 0; subtract_lane < LANES;
                 subtract_lane = subtract_lane + 1) begin
                lane_a = vector_a[subtract_lane*DATA_W +: DATA_W];
                lane_b = vector_b[subtract_lane*DATA_W +: DATA_W];
                product = lane_b * vector_scalar;
                expected[subtract_lane*DATA_W +: DATA_W] =
                    lane_a - ((product + (1 <<< (`RECON_SOLVER_F-1))) >>>
                              `RECON_SOLVER_F);
            end
            vector_subtract = 1'b1;
            issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_AXPY, 3'b011);
            while (!vector_rsp_valid) @(negedge clk);
            if (vector_rsp_data !== expected)
                fail("vector subtract AXPY mismatch");
            @(posedge clk);
            vector_subtract = 1'b0;
        end
    endtask

    task issue_reduction_pair;
        begin
            @(negedge clk);
            reduction_operation = `RECON_RESOURCE_OP_REDUCE_SUM;
            reduction_clear = 1'b1;
            reduction_accumulate = 1'b1;
            reduction_emit = 1'b0;
            reduction_req_valid = 1'b1;
            while (!(reduction_req_ready0 && reduction_req_ready1)) @(negedge clk);
            @(posedge clk);
            while (!(reduction_req_ready0 && reduction_req_ready1)) @(posedge clk);
            #1;
            first_accept_cycle = cycle_count;
            @(negedge clk);
            reduction_clear = 1'b0;
            reduction_emit = 1'b1;
            @(posedge clk);
            while (!(reduction_req_ready0 && reduction_req_ready1)) @(posedge clk);
            #1;
            last_reduction_accept_cycle = cycle_count;
            @(negedge clk);
            reduction_req_valid = 1'b0;
        end
    endtask

    task issue_vector_pair;
        input [4:0] op;
        input [2:0] first_tag;
        input [2:0] second_tag;
        begin
            @(negedge clk);
            vector_operation = op;
            vector_tag = first_tag;
            vector_req_valid = 1'b1;
            while (!vector_req_ready) @(negedge clk);
            @(posedge clk);
            while (!vector_req_ready) @(posedge clk);
            #1;
            first_accept_cycle = cycle_count;
            @(negedge clk);
            vector_tag = second_tag;
            @(posedge clk);
            while (!vector_req_ready) @(posedge clk);
            #1;
            last_vector_accept_cycle = cycle_count;
            @(negedge clk);
            vector_req_valid = 1'b0;
        end
    endtask

    task check_random_copy_backpressure;
        reg [15:0] lfsr;
        reg [LANES*DATA_W-1:0] held_data;
        integer held_valid;
        integer forced_stalls;
        integer attempts;
        integer done;
        begin
            issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_COPY, 3'b101);
            vector_rsp_ready = 1'b0;
            lfsr = 16'h1ace;
            held_data = {LANES*DATA_W{1'b0}};
            held_valid = 0;
            forced_stalls = 0;
            attempts = 0;
            done = 0;
            while (!done && attempts < 32) begin
                @(negedge clk);
                attempts = attempts + 1;
                lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                if (vector_rsp_valid) begin
                    if (!held_valid) begin
                        held_data = vector_rsp_data;
                        held_valid = 1;
                    end else if (vector_rsp_data !== held_data) begin
                        fail("random-backpressure COPY data changed while stalled");
                    end
                    if (vector_rsp_data !== `M5_VECTOR_A)
                        fail("random-backpressure COPY result mismatch");
                    if (forced_stalls < 3) begin
                        vector_rsp_ready = 1'b0;
                        forced_stalls = forced_stalls + 1;
                    end else begin
                        vector_rsp_ready = lfsr[0];
                        if (lfsr[0]) begin
                            @(posedge clk);
                            #1;
                            done = 1;
                        end
                    end
                end else begin
                    vector_rsp_ready = 1'b0;
                end
            end
            if (!done)
                fail("random-backpressure COPY timeout");
            @(negedge clk);
            vector_rsp_ready = 1'b1;
        end
    endtask

    integer lane;
    reg signed [61:0] sum0;
    reg signed [61:0] sum1;
    reg [431:0] held_vector;
    initial begin
        reduction_req_valid = 0;
        reduction_operation = 0;
        reduction_tag = 3'b001;
        reduction_lane_mask = 4'hf;
        reduction_lane_valid = 16'hffff;
        cluster0_lane_data = 0;
        cluster1_lane_data = 0;
        cluster0_lane_index = 0;
        cluster1_lane_index = 0;
        reduction_clear = 0;
        reduction_accumulate = 0;
        reduction_emit = 0;
        reduction_rsp_ready = 1;
        scalar_req_valid = 0;
        scalar_operation = 0;
        scalar_tag = 3'b010;
        scalar_numerator = 0;
        scalar_denominator = 1;
        scalar_rsp_ready = 1;
        vector_req_valid = 0;
        vector_operation = 0;
        vector_tag = 0;
        vector_lane_valid = 16'hffff;
        vector_a = `M5_VECTOR_A;
        vector_b = `M5_VECTOR_B;
        vector_scalar = `M5_VECTOR_SCALAR;
        vector_clear_before = 0;
        vector_accumulate = 0;
        vector_emit_result = 1;
        vector_subtract = 0;
        vector_rsp_ready = 1;
        rf_write_valid = 0;
        rf_commit = 0;
        rf_write_address = 0;
        rf_write_data = 0;
        rf_clear_valid = 0;
        rf_clear_address = 0;
        rf_read_a = 0;
        rf_read_b = 1;
        rf_preload_valid = 0;
        rf_preload_address = 0;
        rf_preload_data = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // RF commit gating and two simultaneous reads.
        @(negedge clk);
        rf_write_valid = 1;
        rf_write_address = 0;
        rf_write_data = 62'd123;
        rf_commit = 0;
        @(posedge clk);
        if (rf_valid_a) fail("RF wrote without cycle_commit");
        @(negedge clk);
        rf_commit = 1;
        @(posedge clk);
        #1;
        if (!rf_valid_a || rf_data_a != 62'd123) fail("RF committed write mismatch");
        @(negedge clk);
        rf_write_address = 1;
        rf_write_data = -62'sd77;
        @(posedge clk);
        #1;
        if (!rf_valid_b || $signed(rf_data_b) != -62'sd77) fail("RF second port mismatch");
        @(negedge clk);
        rf_write_valid = 0;
        rf_commit = 0;

        // Reduction sum across 32 values is 496 and has five registered levels.
        sum0 = 0;
        sum1 = 0;
        for (lane = 0; lane < 16; lane = lane + 1) begin
            cluster0_lane_data[lane*ACC_W +: ACC_W] = lane;
            cluster1_lane_data[lane*ACC_W +: ACC_W] = lane + 16;
            cluster0_lane_index[lane*10 +: 10] = lane;
            cluster1_lane_index[lane*10 +: 10] = lane + 16;
            sum0 = sum0 + lane;
            sum1 = sum1 + lane + 16;
        end
        reduction_rsp_ready = 0;
        issue_reduction(`RECON_RESOURCE_OP_REDUCE_SUM, 1, 1, 1);
        while (!reduction_rsp_valid) @(negedge clk);
        $display("REDUCE latency=%0d", cycle_count-last_reduction_accept_cycle);
        if ((cycle_count-last_reduction_accept_cycle) != 5)
            fail("reduction latency is not 5 cycles");
        if (reduction_rsp_data != sum0 + sum1 || reduction_rsp_fault)
            fail("global reduction sum mismatch");
        held_vector = reduction_rsp_data;
        repeat (4) begin
            @(posedge clk);
            if (!reduction_rsp_valid || reduction_rsp_data != held_vector[61:0])
                fail("reduction response changed under backpressure");
        end
        @(negedge clk);
        reduction_rsp_ready = 1;
        @(posedge clk);

        // MAX_ABS tie keeps lower index and lane mask removes rows 2/3.
        cluster0_lane_data = 0;
        cluster1_lane_data = 0;
        cluster0_lane_index = 0;
        cluster1_lane_index = 0;
        reduction_lane_mask = 4'b0011;
        cluster0_lane_data[0 +: ACC_W] = -62'sd7;
        cluster0_lane_index[0 +: 10] = 10'd9;
        cluster1_lane_data[ACC_W +: ACC_W] = 62'sd7;
        cluster1_lane_index[10 +: 10] = 10'd3;
        issue_reduction(`RECON_RESOURCE_OP_REDUCE_MAX_ABS, 1, 0, 1);
        while (!reduction_rsp_valid) @(posedge clk);
        if ($signed(reduction_rsp_data) != 62'sd7 || reduction_rsp_index != 10'd3)
            fail("MAX_ABS tie-break/lane-mask mismatch");
        @(posedge clk);
        $display("M5 reduction checks complete at cycle %0d", cycle_count);

        // Two accumulator beats must launch one cycle apart; only the final
        // beat emits, and its result includes both 32-lane contributions.
        @(negedge clk);
        reduction_lane_mask = 4'hf;
        for (lane = 0; lane < 16; lane = lane + 1) begin
            cluster0_lane_data[lane*ACC_W +: ACC_W] = 62'sd1;
            cluster1_lane_data[lane*ACC_W +: ACC_W] = 62'sd1;
        end
        issue_reduction_pair();
        if ((last_reduction_accept_cycle-first_accept_cycle) != 1)
            fail("reduction initiation interval is not 1");
        while (!reduction_rsp_valid) @(negedge clk);
        if ((cycle_count-last_reduction_accept_cycle) != 5)
            fail("multi-beat reduction latency is not 5 cycles");
        if ($signed(reduction_rsp_data) != 62'sd64 || reduction_rsp_fault)
            fail("multi-beat reduction accumulator mismatch");
        @(posedge clk);

        check_divide(`M5_DIV_NUM_0, `M5_DIV_DEN_0, `M5_DIV_RESULT_0,
                     `M5_DIV_ZERO_0, `M5_DIV_SAT_0);
        check_divide(`M5_DIV_NUM_1, `M5_DIV_DEN_1, `M5_DIV_RESULT_1,
                     `M5_DIV_ZERO_1, `M5_DIV_SAT_1);
        check_divide(`M5_DIV_NUM_2, `M5_DIV_DEN_2, `M5_DIV_RESULT_2,
                     `M5_DIV_ZERO_2, `M5_DIV_SAT_2);
        check_divide(`M5_DIV_NUM_3, `M5_DIV_DEN_3, `M5_DIV_RESULT_3,
                     `M5_DIV_ZERO_3, `M5_DIV_SAT_3);
        check_divide(`M5_DIV_NUM_4, `M5_DIV_DEN_4, `M5_DIV_RESULT_4,
                     `M5_DIV_ZERO_4, `M5_DIV_SAT_4);
        check_divide(`M5_DIV_NUM_5, `M5_DIV_DEN_5, `M5_DIV_RESULT_5,
                     `M5_DIV_ZERO_5, `M5_DIV_SAT_5);
        $display("M5 divide checks complete at cycle %0d", cycle_count);

        // Both reserved encodings are one-cycle deterministic faults.
        check_reserved_scalar(`RECON_RESOURCE_OP_SCALAR_RECIPROCAL);
        check_reserved_scalar(`RECON_RESOURCE_OP_SCALAR_SQRT);
        check_reserved_scalar_pair();
        $display("M5 reserved-op check complete at cycle %0d", cycle_count);

        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_COPY, 3'b100);
        while (!vector_rsp_valid) @(negedge clk);
        $display("COPY latency=%0d", cycle_count-last_vector_accept_cycle);
        if ((cycle_count-last_vector_accept_cycle) != 2)
            fail("vector COPY latency is not 2 cycles");
        if (vector_rsp_data !== `M5_VECTOR_A || vector_rsp_lane_valid != 16'hffff)
            fail("vector COPY mismatch");
        @(posedge clk);
        $display("M5 COPY check complete at cycle %0d", cycle_count);

        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_SCALE, 3'b101);
        while (!vector_rsp_valid) @(negedge clk);
        $display("SCALE latency=%0d", cycle_count-last_vector_accept_cycle);
        if ((cycle_count-last_vector_accept_cycle) != 4)
            fail("vector SCALE latency is not 4 cycles");
        if (vector_rsp_data !== `M5_VECTOR_SCALE ||
            vector_rsp_saturated !== `M5_VECTOR_SCALE_SAT)
            fail("vector SCALE mismatch");
        @(posedge clk);
        $display("M5 SCALE check complete at cycle %0d", cycle_count);

        @(negedge clk);
        vector_rsp_ready = 0;
        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_AXPY, 3'b110);
        while (!vector_rsp_valid) @(negedge clk);
        $display("AXPY latency=%0d", cycle_count-last_vector_accept_cycle);
        if ((cycle_count-last_vector_accept_cycle) != 4)
            fail("vector AXPY latency is not 4 cycles");
        if (vector_rsp_data !== `M5_VECTOR_AXPY ||
            vector_rsp_saturated !== `M5_VECTOR_AXPY_SAT)
            fail("vector AXPY mismatch");
        held_vector = vector_rsp_data;
        repeat (7) begin
            @(posedge clk);
            if (!vector_rsp_valid || vector_rsp_data !== held_vector)
                fail("vector response changed under backpressure");
        end
        @(negedge clk);
        vector_rsp_ready = 1;
        @(posedge clk);
        $display("M5 AXPY check complete at cycle %0d", cycle_count);

        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT, 3'b111);
        while (!vector_rsp_valid) @(negedge clk);
        $display("DOT latency=%0d", cycle_count-last_vector_accept_cycle);
        if ((cycle_count-last_vector_accept_cycle) != 6)
            fail("vector DOT latency is not 6 cycles");
        if (vector_rsp_scalar !== `M5_VECTOR_DOT)
            fail("vector DOT mismatch");
        @(posedge clk);
        $display("M5 DOT check complete at cycle %0d", cycle_count);

        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ, 3'b100);
        while (!vector_rsp_valid) @(negedge clk);
        $display("NORM latency=%0d", cycle_count-last_vector_accept_cycle);
        if ((cycle_count-last_vector_accept_cycle) != 6)
            fail("vector NORM latency is not 6 cycles");
        if (vector_rsp_scalar !== `M5_VECTOR_NORM)
            fail("vector NORM_SQ mismatch");
        @(posedge clk);

        // COPY is fully pipelined (II=1).
        issue_vector_pair(`RECON_RESOURCE_OP_SHARED_VECTOR_COPY, 3'b000, 3'b001);
        if ((last_vector_accept_cycle-first_accept_cycle) != 1)
            fail("vector COPY initiation interval is not 1");
        response_count = 0;
        while (response_count < 2) begin
            if (vector_rsp_valid) begin
                if (vector_rsp_data !== `M5_VECTOR_A)
                    fail("pipelined COPY result mismatch");
                if ((response_count == 0 && vector_rsp_tag != 3'b000) ||
                    (response_count == 1 && vector_rsp_tag != 3'b001))
                    fail("pipelined COPY tag ordering mismatch");
                response_count = response_count + 1;
            end
            @(negedge clk);
        end

        // Folded multiply accepts one request every two cycles.
        issue_vector_pair(`RECON_RESOURCE_OP_SHARED_VECTOR_SCALE, 3'b010, 3'b011);
        if ((last_vector_accept_cycle-first_accept_cycle) != 2)
            fail("vector multiply initiation interval is not 2");
        response_count = 0;
        while (response_count < 2) begin
            if (vector_rsp_valid) begin
                if (vector_rsp_data !== `M5_VECTOR_SCALE)
                    fail("pipelined SCALE result mismatch");
                if ((response_count == 0 && vector_rsp_tag != 3'b010) ||
                    (response_count == 1 && vector_rsp_tag != 3'b011))
                    fail("pipelined SCALE tag ordering mismatch");
                response_count = response_count + 1;
            end
            @(negedge clk);
        end

        check_random_copy_backpressure();
        check_subtract_axpy();

        $display("M5 ARITHMETIC PASS");
        $finish;
    end

    initial begin
        #200000;
        fail("timeout");
    end
endmodule

`default_nettype wire
