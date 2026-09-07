`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module tb_p15_candidate_arithmetic;
    localparam integer DATA_W = `RECON_CANDIDATE_SOLVER_W;
    localparam integer FRACTION_W = `RECON_CANDIDATE_SOLVER_F;
    localparam integer ACC_W = `RECON_CANDIDATE_ACC_W;
    localparam integer LANES = 16;
    localparam integer TAG_W = 3;
    localparam signed [DATA_W-1:0] DATA_MAX =
        {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] DATA_MIN =
        {1'b1, {(DATA_W-1){1'b0}}};
    localparam signed [ACC_W-1:0] ACC_MAX =
        {1'b0, {(ACC_W-1){1'b1}}};
    localparam signed [ACC_W-1:0] ACC_MIN =
        {1'b1, {(ACC_W-1){1'b0}}};

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    integer cycle_count = 0;
    always @(posedge clk)
        if (rst_n) cycle_count <= cycle_count + 1;
        else cycle_count <= 0;

    reg vector_req_valid = 0;
    wire vector_req_ready;
    reg [4:0] vector_req_operation = 0;
    reg [TAG_W-1:0] vector_req_tag = 0;
    reg [LANES-1:0] vector_req_lane_valid = 0;
    reg [LANES*DATA_W-1:0] vector_req_a = 0;
    reg [LANES*DATA_W-1:0] vector_req_b = 0;
    reg signed [DATA_W-1:0] vector_req_scalar = 0;
    reg vector_req_clear = 0;
    reg vector_req_accumulate = 0;
    reg vector_req_emit = 0;
    reg vector_req_subtract = 0;
    wire vector_rsp_valid;
    reg vector_rsp_ready = 0;
    wire [4:0] vector_rsp_operation;
    wire [TAG_W-1:0] vector_rsp_tag;
    wire [LANES-1:0] vector_rsp_lane_valid;
    wire [LANES*DATA_W-1:0] vector_rsp_data;
    wire signed [ACC_W-1:0] vector_rsp_scalar;
    wire [LANES-1:0] vector_rsp_saturated;
    wire vector_rsp_fault;

    shared_vector_arithmetic_unit #(
        .LANES(LANES), .DATA_W(DATA_W), .FRACTION_W(FRACTION_W),
        .ACC_W(ACC_W), .TAG_W(TAG_W)
    ) vector_unit (
        .clk(clk), .rst_n(rst_n), .req_valid(vector_req_valid),
        .req_ready(vector_req_ready), .req_operation(vector_req_operation),
        .req_tag(vector_req_tag), .req_lane_valid(vector_req_lane_valid),
        .req_vector_a(vector_req_a), .req_vector_b(vector_req_b),
        .req_scalar(vector_req_scalar), .req_clear_before(vector_req_clear),
        .req_accumulate(vector_req_accumulate),
        .req_emit_result(vector_req_emit), .req_subtract(vector_req_subtract),
        .rsp_valid(vector_rsp_valid), .rsp_ready(vector_rsp_ready),
        .rsp_operation(vector_rsp_operation), .rsp_tag(vector_rsp_tag),
        .rsp_lane_valid(vector_rsp_lane_valid), .rsp_vector(vector_rsp_data),
        .rsp_scalar(vector_rsp_scalar), .rsp_saturated(vector_rsp_saturated),
        .rsp_fault(vector_rsp_fault)
    );

    reg scalar_req_valid = 0;
    wire scalar_req_ready;
    reg signed [ACC_W-1:0] scalar_numerator = 0;
    reg signed [ACC_W-1:0] scalar_denominator = 0;
    reg [TAG_W-1:0] scalar_tag = 0;
    wire scalar_rsp_valid;
    reg scalar_rsp_ready = 1;
    wire [TAG_W-1:0] scalar_rsp_tag;
    wire signed [DATA_W-1:0] scalar_rsp_result;
    wire scalar_rsp_fault;
    wire [7:0] scalar_rsp_fault_code;
    wire [15:0] scalar_rsp_fault_detail;
    wire scalar_divide_by_zero;
    wire scalar_saturated;

    scalar_function_unit #(
        .ACC_W(ACC_W), .OUT_W(DATA_W), .FRACTION_W(FRACTION_W),
        .TAG_W(TAG_W)
    ) scalar_unit (
        .clk(clk), .rst_n(rst_n), .req_valid(scalar_req_valid),
        .req_ready(scalar_req_ready),
        .req_operation(`RECON_RESOURCE_OP_SCALAR_DIVIDE),
        .req_tag(scalar_tag), .req_numerator(scalar_numerator),
        .req_denominator(scalar_denominator), .rsp_valid(scalar_rsp_valid),
        .rsp_ready(scalar_rsp_ready), .rsp_tag(scalar_rsp_tag),
        .rsp_result(scalar_rsp_result), .rsp_fault(scalar_rsp_fault),
        .rsp_fault_code(scalar_rsp_fault_code),
        .rsp_fault_detail(scalar_rsp_fault_detail),
        .rsp_divide_by_zero(scalar_divide_by_zero),
        .rsp_saturated(scalar_saturated)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $finish;
        end
    endtask

    task issue_vector;
        input [4:0] operation;
        input clear_before;
        input accumulate;
        input emit_result;
        begin
            @(negedge clk);
            vector_req_operation = operation;
            vector_req_clear = clear_before;
            vector_req_accumulate = accumulate;
            vector_req_emit = emit_result;
            vector_req_valid = 1'b1;
            @(posedge clk);
            while (!vector_req_ready) @(posedge clk);
            #1;
            @(negedge clk);
            vector_req_valid = 1'b0;
        end
    endtask

    task wait_vector_response;
        input [TAG_W-1:0] expected_tag;
        begin
            while (!vector_rsp_valid || vector_rsp_tag != expected_tag)
                @(negedge clk);
        end
    endtask

    task consume_vector_response;
        begin
            @(negedge clk);
            vector_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            vector_rsp_ready = 1'b0;
        end
    endtask

    task check_divide;
        input signed [ACC_W-1:0] numerator;
        input signed [ACC_W-1:0] denominator;
        input signed [DATA_W-1:0] expected;
        input expected_zero;
        input expected_saturated;
        integer accepted_cycle;
        begin
            @(negedge clk);
            scalar_numerator = numerator;
            scalar_denominator = denominator;
            scalar_req_valid = 1'b1;
            @(posedge clk);
            while (!scalar_req_ready) @(posedge clk);
            #1 accepted_cycle = cycle_count;
            @(negedge clk);
            scalar_req_valid = 1'b0;
            while (!scalar_rsp_valid) @(negedge clk);
            if (cycle_count - accepted_cycle !=
                    `RECON_CANDIDATE_SCALAR_DIVIDE_LATENCY)
                fail("candidate divide latency mismatch");
            if (scalar_rsp_result !== expected)
                fail("candidate divide result mismatch");
            if (scalar_divide_by_zero !== expected_zero)
                fail("candidate divide-by-zero mismatch");
            if (scalar_saturated !== expected_saturated)
                fail("candidate divide saturation mismatch");
            if (scalar_rsp_fault)
                fail("candidate divide raised contract fault");
            @(posedge clk);
        end
    endtask

    integer lane;
    integer stripe;
    reg signed [2*DATA_W-1:0] expected_product;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        vector_req_lane_valid = 16'h0001;
        vector_req_a = 0;
        vector_req_b = 0;
        vector_req_a[0 +: DATA_W] = DATA_MIN;
        vector_req_b[0 +: DATA_W] = DATA_MIN;
        vector_req_tag = 3'd1;
        expected_product = $signed(DATA_MIN) * $signed(DATA_MIN);
        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT, 1'b1, 1'b0, 1'b1);
        wait_vector_response(3'd1);
        if (vector_rsp_scalar !== $signed(expected_product))
            fail("S31 minimum product reconstruction mismatch");
        if (vector_rsp_fault)
            fail("in-range S31 product raised fault");
        consume_vector_response();

        vector_req_a[0 +: DATA_W] = DATA_MAX;
        vector_req_b[0 +: DATA_W] = DATA_MIN;
        vector_req_tag = 3'd2;
        expected_product = $signed(DATA_MAX) * $signed(DATA_MIN);
        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT, 1'b1, 1'b0, 1'b1);
        wait_vector_response(3'd2);
        if (vector_rsp_scalar !== $signed(expected_product)) begin
            $display("mixed product got=%0d expected=%0d",
                     $signed(vector_rsp_scalar), $signed(expected_product));
            fail("S31 mixed-sign product reconstruction mismatch");
        end
        consume_vector_response();

        vector_req_lane_valid = 16'h0003;
        vector_req_a = 0;
        vector_req_a[0 +: DATA_W] = {{(DATA_W-1){1'b0}}, 1'b1};
        vector_req_a[DATA_W +: DATA_W] = {DATA_W{1'b1}};
        vector_req_scalar = 1 <<< (FRACTION_W-1);
        vector_req_tag = 3'd3;
        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_SCALE, 1'b0, 1'b0, 1'b1);
        wait_vector_response(3'd3);
        if ($signed(vector_rsp_data[0 +: DATA_W]) !== 1 ||
            $signed(vector_rsp_data[DATA_W +: DATA_W]) !== -1)
            fail("S31 half-LSB ties are not away from zero");
        if (vector_rsp_saturated != 0)
            fail("S31 tie case saturated unexpectedly");
        consume_vector_response();

        vector_req_a[0 +: DATA_W] = DATA_MAX;
        vector_req_a[DATA_W +: DATA_W] = DATA_MIN;
        vector_req_scalar = 2 <<< FRACTION_W;
        vector_req_tag = 3'd4;
        issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_SCALE, 1'b0, 1'b0, 1'b1);
        wait_vector_response(3'd4);
        if ($signed(vector_rsp_data[0 +: DATA_W]) !== DATA_MAX ||
            $signed(vector_rsp_data[DATA_W +: DATA_W]) !== DATA_MIN)
            fail("S31 signed saturation result mismatch");
        if (vector_rsp_saturated[1:0] !== 2'b11)
            fail("S31 signed saturation flags missing");
        consume_vector_response();

        vector_req_lane_valid = {LANES{1'b1}};
        for (lane = 0; lane < LANES; lane = lane + 1)
            vector_req_a[lane*DATA_W +: DATA_W] = DATA_MIN;
        vector_req_tag = 3'd5;
        for (stripe = 0; stripe < 32; stripe = stripe + 1)
            issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ,
                         stripe == 0, 1'b1, stripe == 31);
        wait_vector_response(3'd5);
        if (vector_rsp_scalar !== ACC_MAX)
            fail("ACC70 overflow did not saturate positive");
        if (!vector_rsp_fault)
            fail("ACC70 overflow did not raise resource fault");
        consume_vector_response();

        for (lane = 0; lane < LANES; lane = lane + 1) begin
            vector_req_a[lane*DATA_W +: DATA_W] = DATA_MAX;
            vector_req_b[lane*DATA_W +: DATA_W] = DATA_MIN;
        end
        vector_req_tag = 3'd6;
        for (stripe = 0; stripe < 33; stripe = stripe + 1)
            issue_vector(`RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
                         stripe == 0, 1'b1, stripe == 32);
        wait_vector_response(3'd6);
        if (vector_rsp_scalar !== ACC_MIN)
            fail("ACC70 negative overflow did not saturate");
        if (!vector_rsp_fault)
            fail("ACC70 negative overflow did not raise resource fault");
        consume_vector_response();

        check_divide(70'sd1, 70'sd16777216, 31'sd1, 1'b0, 1'b0);
        check_divide(-70'sd1, 70'sd16777216, -31'sd1, 1'b0, 1'b0);
        check_divide(70'sd3, 70'sd2, 31'sd12582912, 1'b0, 1'b0);
        check_divide(ACC_MAX, 70'sd1, DATA_MAX, 1'b0, 1'b1);
        check_divide(ACC_MIN, 70'sd1, DATA_MIN, 1'b0, 1'b1);
        check_divide(70'sd7, 70'sd0, 31'sd0, 1'b1, 1'b0);

        $display("P1.5 CANDIDATE ARITHMETIC PASS");
        $finish;
    end

    initial begin
        #1000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
