`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Sixteen-lane scratchpad sidecar. Each lane forms an exact product in two
// phases from one 27x18 primary product plus one small signed cross-product.
// COPY has II=1; multiply-based
// operations have II=2. Operation families are not mixed until their response
// pipeline drains, which avoids hidden cross-operation structural hazards.
module shared_vector_arithmetic_unit #(
    parameter integer LANES = `RECON_SHARED_VECTOR_LANES,
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer FRACTION_W = `RECON_SOLVER_F,
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [4:0]                   req_operation,
    input  wire [TAG_W-1:0]             req_tag,
    input  wire [LANES-1:0]             req_lane_valid,
    input  wire [LANES*DATA_W-1:0]      req_vector_a,
    input  wire [LANES*DATA_W-1:0]      req_vector_b,
    input  wire signed [DATA_W-1:0]     req_scalar,
    input  wire                         req_clear_before,
    input  wire                         req_accumulate,
    input  wire                         req_emit_result,
    input  wire                         req_subtract,

    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire [4:0]                   rsp_operation,
    output wire [TAG_W-1:0]             rsp_tag,
    output wire [LANES-1:0]             rsp_lane_valid,
    output wire [LANES*DATA_W-1:0]      rsp_vector,
    output wire signed [ACC_W-1:0]      rsp_scalar,
    output wire [LANES-1:0]             rsp_saturated,
    output wire                         rsp_fault
);
    localparam integer PRODUCT_W = 2*DATA_W;
    localparam integer MULTIPLIER_LEFT_W = 27;
    localparam integer MULTIPLIER_RIGHT_W = 18;
    localparam integer LEFT_HIGH_W = DATA_W - MULTIPLIER_LEFT_W + 1;
    localparam integer RIGHT_HIGH_W = DATA_W - MULTIPLIER_RIGHT_W + 1;
    localparam integer DOT_INTERNAL_W = PRODUCT_W + $clog2(`RECON_N_MAX);
    localparam [1:0] FAMILY_NONE = 2'd0;
    localparam [1:0] FAMILY_COPY = 2'd1;
    localparam [1:0] FAMILY_VECTOR = 2'd2;
    localparam [1:0] FAMILY_DOT = 2'd3;

    function [1:0] operation_family;
        input [4:0] operation;
        begin
            case (operation)
                `RECON_RESOURCE_OP_SHARED_VECTOR_COPY:
                    operation_family = FAMILY_COPY;
                `RECON_RESOURCE_OP_SHARED_VECTOR_SCALE,
                `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY:
                    operation_family = FAMILY_VECTOR;
                `RECON_RESOURCE_OP_SHARED_VECTOR_DOT,
                `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ:
                    operation_family = FAMILY_DOT;
                default: operation_family = FAMILY_NONE;
            endcase
        end
    endfunction

    function [DATA_W:0] narrow_product;
        input signed [PRODUCT_W-1:0] value;
        reg [PRODUCT_W-1:0] absolute_value;
        reg [PRODUCT_W-1:0] rounded;
        reg [DATA_W-1:0] result;
        reg saturated;
        begin
            absolute_value = value[PRODUCT_W-1] ?
                (~value + {{PRODUCT_W-1{1'b0}},1'b1}) : value;
            rounded = (absolute_value + ({{PRODUCT_W-1{1'b0}},1'b1} <<
                                         (FRACTION_W-1))) >>
                                         FRACTION_W;
            saturated = 1'b0;
            if (!value[PRODUCT_W-1] &&
                (rounded > {1'b0, {DATA_W-1{1'b1}}})) begin
                result = {1'b0, {DATA_W-1{1'b1}}};
                saturated = 1'b1;
            end else if (value[PRODUCT_W-1] &&
                         (rounded > ({{PRODUCT_W-1{1'b0}},1'b1} <<
                                     (DATA_W-1)))) begin
                result = {1'b1, {DATA_W-1{1'b0}}};
                saturated = 1'b1;
            end else if (value[PRODUCT_W-1]) begin
                result = -$signed(rounded[DATA_W-1:0]);
            end else begin
                result = rounded[DATA_W-1:0];
            end
            narrow_product = {saturated, result};
        end
    endfunction

    function [DATA_W:0] saturating_add;
        input signed [DATA_W-1:0] left;
        input signed [DATA_W-1:0] right;
        reg signed [DATA_W:0] sum;
        reg [DATA_W-1:0] result;
        reg saturated;
        begin
            sum = left + right;
            saturated = 1'b0;
            if (sum > $signed({1'b0, {DATA_W-1{1'b1}}})) begin
                result = {1'b0, {DATA_W-1{1'b1}}};
                saturated = 1'b1;
            end else if (sum < $signed({1'b1, {DATA_W-1{1'b0}}})) begin
                result = {1'b1, {DATA_W-1{1'b0}}};
                saturated = 1'b1;
            end else begin
                result = sum[DATA_W-1:0];
            end
            saturating_add = {saturated, result};
        end
    endfunction

    function [ACC_W:0] narrow_dot_accumulator;
        input signed [DOT_INTERNAL_W-1:0] value;
        reg signed [ACC_W-1:0] result;
        reg saturated;
        begin
            saturated = 1'b0;
            if (value[DOT_INTERNAL_W-1:ACC_W-1] ==
                    {(DOT_INTERNAL_W-ACC_W+1){value[ACC_W-1]}}) begin
                result = value[ACC_W-1:0];
            end else begin
                result = value[DOT_INTERNAL_W-1] ?
                    {1'b1, {(ACC_W-1){1'b0}}} :
                    {1'b0, {(ACC_W-1){1'b1}}};
                saturated = 1'b1;
            end
            narrow_dot_accumulator = {saturated, result};
        end
    endfunction

    function [DATA_W:0] saturating_subtract;
        input signed [DATA_W-1:0] left;
        input signed [DATA_W-1:0] right;
        reg signed [DATA_W:0] difference;
        reg [DATA_W-1:0] result;
        reg saturated;
        begin
            difference = left - right;
            saturated = 1'b0;
            if (difference > $signed({1'b0, {DATA_W-1{1'b1}}})) begin
                result = {1'b0, {DATA_W-1{1'b1}}};
                saturated = 1'b1;
            end else if (difference < $signed({1'b1, {DATA_W-1{1'b0}}})) begin
                result = {1'b1, {DATA_W-1{1'b0}}};
                saturated = 1'b1;
            end else begin
                result = difference[DATA_W-1:0];
            end
            saturating_subtract = {saturated, result};
        end
    endfunction

    reg [1:0] active_family;
    reg multiply_busy;
    reg multiply_high_phase;
    reg [4:0] multiply_operation;
    reg [TAG_W-1:0] multiply_tag;
    reg [LANES-1:0] multiply_lane_valid;
    reg multiply_clear_before;
    reg multiply_accumulate;
    reg multiply_emit_result;
    reg multiply_subtract;
    reg signed [DATA_W-1:0] multiply_left [0:LANES-1];
    reg signed [DATA_W-1:0] multiply_right [0:LANES-1];
    reg signed [DATA_W-1:0] multiply_addend [0:LANES-1];
    reg signed [PRODUCT_W-1:0] low_partial [0:LANES-1];

    wire [1:0] requested_family = operation_family(req_operation);

    // COPY: input capture, one delay register, output register.
    reg copy0_valid;
    reg [TAG_W-1:0] copy0_tag;
    reg [LANES-1:0] copy0_lane_valid;
    reg [LANES*DATA_W-1:0] copy0_vector;
    reg copy1_valid;
    reg [TAG_W-1:0] copy1_tag;
    reg [LANES-1:0] copy1_lane_valid;
    reg [LANES*DATA_W-1:0] copy1_vector;
    reg copy_out_valid;
    reg [TAG_W-1:0] copy_out_tag;
    reg [LANES-1:0] copy_out_lane_valid;
    reg [LANES*DATA_W-1:0] copy_out_vector;

    // SCALE/AXPY: exact product, narrow/post-add, output.
    reg vector_raw_valid;
    reg [4:0] vector_raw_operation;
    reg [TAG_W-1:0] vector_raw_tag;
    reg [LANES-1:0] vector_raw_lane_valid;
    reg vector_raw_subtract;
    reg signed [PRODUCT_W-1:0] vector_raw_product [0:LANES-1];
    reg signed [DATA_W-1:0] vector_raw_addend [0:LANES-1];
    reg vector_narrow_valid;
    reg [4:0] vector_narrow_operation;
    reg [TAG_W-1:0] vector_narrow_tag;
    reg [LANES-1:0] vector_narrow_lane_valid;
    reg [LANES*DATA_W-1:0] vector_narrow_data;
    reg [LANES-1:0] vector_narrow_saturated;
    reg vector_out_valid;
    reg [4:0] vector_out_operation;
    reg [TAG_W-1:0] vector_out_tag;
    reg [LANES-1:0] vector_out_lane_valid;
    reg [LANES*DATA_W-1:0] vector_out_data;
    reg [LANES-1:0] vector_out_saturated;

    // DOT/NORM: products, four group sums, total, delay, output.
    reg dot_product_valid;
    reg [4:0] dot_product_operation;
    reg [TAG_W-1:0] dot_product_tag;
    reg dot_product_clear_before;
    reg dot_product_accumulate;
    reg dot_product_emit_result;
    reg signed [PRODUCT_W-1:0] dot_product [0:LANES-1];
    reg dot_group_valid;
    reg [4:0] dot_group_operation;
    reg [TAG_W-1:0] dot_group_tag;
    reg dot_group_clear_before;
    reg dot_group_accumulate;
    reg dot_group_emit_result;
    reg signed [DOT_INTERNAL_W-1:0] dot_group [0:3];
    reg dot_total_valid;
    reg [4:0] dot_total_operation;
    reg [TAG_W-1:0] dot_total_tag;
    reg dot_total_clear_before;
    reg dot_total_accumulate;
    reg dot_total_emit_result;
    reg signed [DOT_INTERNAL_W-1:0] dot_total;
    reg dot_delay_valid;
    reg [4:0] dot_delay_operation;
    reg [TAG_W-1:0] dot_delay_tag;
    reg dot_delay_clear_before;
    reg dot_delay_accumulate;
    reg dot_delay_emit_result;
    reg signed [DOT_INTERNAL_W-1:0] dot_delay;
    reg dot_out_valid;
    reg [4:0] dot_out_operation;
    reg [TAG_W-1:0] dot_out_tag;
    reg signed [DOT_INTERNAL_W-1:0] dot_out_data;
    reg signed [DOT_INTERNAL_W-1:0] dot_accumulator;

    wire output_valid = copy_out_valid || vector_out_valid || dot_out_valid;
    wire response_slot_ready = !output_valid;
    wire pipeline_advance = response_slot_ready || rsp_ready;
    wire family_allowed = (active_family == FAMILY_NONE) ||
                          (active_family == requested_family);
    wire multiply_request = (requested_family == FAMILY_VECTOR) ||
                            (requested_family == FAMILY_DOT);
    wire can_start_multiply = !multiply_busy || multiply_high_phase;
    assign req_ready = response_slot_ready && family_allowed &&
        (((requested_family == FAMILY_COPY) && !multiply_busy) ||
         (multiply_request && can_start_multiply));

    wire accept_request = req_valid && req_ready;
    wire accept_copy = accept_request && (requested_family == FAMILY_COPY);
    wire accept_multiply = accept_request && multiply_request;
    wire complete_multiply = pipeline_advance && multiply_busy && multiply_high_phase;

    wire [LANES*PRODUCT_W-1:0] lane_phase_product;
    wire [LANES*PRODUCT_W-1:0] lane_completed_product;
    genvar generate_lane;
    generate
        for (generate_lane = 0; generate_lane < LANES; generate_lane = generate_lane + 1) begin : g_multiply_lane
            wire signed [MULTIPLIER_LEFT_W-1:0] left_low =
                multiply_left[generate_lane][MULTIPLIER_LEFT_W-1:0];
            wire signed [MULTIPLIER_RIGHT_W-1:0] right_low =
                multiply_right[generate_lane][MULTIPLIER_RIGHT_W-1:0];
            wire signed [DATA_W-1:0] left_shifted =
                $signed(multiply_left[generate_lane]) >>> MULTIPLIER_LEFT_W;
            wire signed [DATA_W-1:0] right_shifted =
                $signed(multiply_right[generate_lane]) >>> MULTIPLIER_RIGHT_W;
            wire signed [LEFT_HIGH_W-1:0] left_high =
                $signed(left_shifted[LEFT_HIGH_W-1:0]) +
                $signed({{(LEFT_HIGH_W-1){1'b0}},
                         multiply_left[generate_lane][MULTIPLIER_LEFT_W-1]});
            wire signed [RIGHT_HIGH_W-1:0] right_high =
                $signed(right_shifted[RIGHT_HIGH_W-1:0]) +
                $signed({{(RIGHT_HIGH_W-1){1'b0}},
                         multiply_right[generate_lane][MULTIPLIER_RIGHT_W-1]});
            wire signed [MULTIPLIER_RIGHT_W-1:0] right_high_extended =
                {{(MULTIPLIER_RIGHT_W-RIGHT_HIGH_W){
                    right_high[RIGHT_HIGH_W-1]}}, right_high};
            wire signed [MULTIPLIER_RIGHT_W-1:0] selected_right =
                multiply_high_phase ? right_high_extended : right_low;
            wire signed [MULTIPLIER_LEFT_W+MULTIPLIER_RIGHT_W-1:0]
                primary_product = left_low * selected_right;
            wire signed [LEFT_HIGH_W+MULTIPLIER_RIGHT_W-1:0]
                cross_product = left_high * selected_right;
            wire signed [PRODUCT_W-1:0] primary_product_extended =
                {{(PRODUCT_W-(MULTIPLIER_LEFT_W+MULTIPLIER_RIGHT_W)){
                    primary_product[MULTIPLIER_LEFT_W+MULTIPLIER_RIGHT_W-1]}},
                  primary_product};
            wire signed [PRODUCT_W-1:0] cross_product_extended =
                {{(PRODUCT_W-(LEFT_HIGH_W+MULTIPLIER_RIGHT_W)){
                    cross_product[LEFT_HIGH_W+MULTIPLIER_RIGHT_W-1]}},
                  cross_product};
            wire signed [PRODUCT_W-1:0] phase_product =
                multiply_high_phase ?
                ((primary_product_extended <<< MULTIPLIER_RIGHT_W) +
                 (cross_product_extended <<<
                    (MULTIPLIER_LEFT_W+MULTIPLIER_RIGHT_W))) :
                (primary_product_extended +
                 (cross_product_extended <<< MULTIPLIER_LEFT_W));
            wire signed [PRODUCT_W-1:0] completed_product =
                low_partial[generate_lane] + phase_product;
            assign lane_phase_product[generate_lane*PRODUCT_W +: PRODUCT_W] =
                phase_product;
            assign lane_completed_product[generate_lane*PRODUCT_W +: PRODUCT_W] =
                completed_product;
        end
    endgenerate

    integer lane_index;
    integer group_index;
    reg [DATA_W:0] narrowed_lane;
    reg [DATA_W:0] added_lane;
    wire all_internal_empty = !multiply_busy &&
        !copy0_valid && !copy1_valid && !copy_out_valid &&
        !vector_raw_valid && !vector_narrow_valid && !vector_out_valid &&
        !dot_product_valid && !dot_group_valid && !dot_total_valid &&
        !dot_delay_valid && !dot_out_valid;

    assign rsp_valid = output_valid;
    assign rsp_operation = copy_out_valid ? `RECON_RESOURCE_OP_SHARED_VECTOR_COPY :
                           vector_out_valid ? vector_out_operation : dot_out_operation;
    assign rsp_tag = copy_out_valid ? copy_out_tag :
                     vector_out_valid ? vector_out_tag : dot_out_tag;
    assign rsp_lane_valid = copy_out_valid ? copy_out_lane_valid :
                            vector_out_valid ? vector_out_lane_valid : {LANES{1'b0}};
    assign rsp_vector = copy_out_valid ? copy_out_vector :
                        vector_out_valid ? vector_out_data : {LANES*DATA_W{1'b0}};
    wire [ACC_W:0] narrowed_dot_output = narrow_dot_accumulator(dot_out_data);
    assign rsp_scalar = dot_out_valid ? narrowed_dot_output[ACC_W-1:0] :
                        {ACC_W{1'b0}};
    assign rsp_saturated = vector_out_valid ? vector_out_saturated : {LANES{1'b0}};
    assign rsp_fault = dot_out_valid && narrowed_dot_output[ACC_W];

    always @(posedge clk) begin
        if (!rst_n) begin
            active_family <= FAMILY_NONE;
            multiply_busy <= 1'b0;
            multiply_high_phase <= 1'b0;
            copy0_valid <= 1'b0;
            copy1_valid <= 1'b0;
            copy_out_valid <= 1'b0;
            vector_raw_valid <= 1'b0;
            vector_narrow_valid <= 1'b0;
            vector_out_valid <= 1'b0;
            dot_product_valid <= 1'b0;
            dot_group_valid <= 1'b0;
            dot_total_valid <= 1'b0;
            dot_delay_valid <= 1'b0;
            dot_out_valid <= 1'b0;
            dot_accumulator <= {ACC_W{1'b0}};
        end else if (pipeline_advance) begin
            copy_out_valid <= copy1_valid;
            copy_out_tag <= copy1_tag;
            copy_out_lane_valid <= copy1_lane_valid;
            copy_out_vector <= copy1_vector;
            copy1_valid <= copy0_valid;
            copy1_tag <= copy0_tag;
            copy1_lane_valid <= copy0_lane_valid;
            copy1_vector <= copy0_vector;
            copy0_valid <= accept_copy;
            if (accept_copy) begin
                copy0_tag <= req_tag;
                copy0_lane_valid <= req_lane_valid;
                copy0_vector <= req_vector_a;
            end

            vector_out_valid <= vector_narrow_valid;
            vector_out_operation <= vector_narrow_operation;
            vector_out_tag <= vector_narrow_tag;
            vector_out_lane_valid <= vector_narrow_lane_valid;
            vector_out_data <= vector_narrow_data;
            vector_out_saturated <= vector_narrow_saturated;
            vector_narrow_valid <= vector_raw_valid;
            vector_narrow_operation <= vector_raw_operation;
            vector_narrow_tag <= vector_raw_tag;
            vector_narrow_lane_valid <= vector_raw_lane_valid;
            for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1) begin
                narrowed_lane = narrow_product(vector_raw_product[lane_index]);
                if (vector_raw_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) begin
                    if (vector_raw_subtract)
                        added_lane = saturating_subtract(
                            vector_raw_addend[lane_index],
                            $signed(narrowed_lane[DATA_W-1:0]));
                    else
                        added_lane = saturating_add(
                            vector_raw_addend[lane_index],
                            $signed(narrowed_lane[DATA_W-1:0]));
                    vector_narrow_data[lane_index*DATA_W +: DATA_W] <=
                        added_lane[DATA_W-1:0];
                    vector_narrow_saturated[lane_index] <=
                        narrowed_lane[DATA_W] || added_lane[DATA_W];
                end else begin
                    vector_narrow_data[lane_index*DATA_W +: DATA_W] <=
                        narrowed_lane[DATA_W-1:0];
                    vector_narrow_saturated[lane_index] <= narrowed_lane[DATA_W];
                end
            end
            vector_raw_valid <= complete_multiply &&
                (active_family == FAMILY_VECTOR);
            if (complete_multiply && (active_family == FAMILY_VECTOR)) begin
                vector_raw_operation <= multiply_operation;
                vector_raw_tag <= multiply_tag;
                vector_raw_lane_valid <= multiply_lane_valid;
                vector_raw_subtract <= multiply_subtract;
                for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1) begin
                    vector_raw_product[lane_index] <=
                        lane_completed_product[lane_index*PRODUCT_W +: PRODUCT_W];
                    vector_raw_addend[lane_index] <= multiply_addend[lane_index];
                end
            end

            dot_out_valid <= dot_delay_valid && dot_delay_emit_result;
            dot_out_operation <= dot_delay_operation;
            dot_out_tag <= dot_delay_tag;
            if (dot_delay_valid) begin
                if (dot_delay_accumulate) begin
                    if (dot_delay_clear_before) begin
                        dot_accumulator <= dot_delay;
                        dot_out_data <= dot_delay;
                    end else begin
                        dot_accumulator <= dot_accumulator + dot_delay;
                        dot_out_data <= dot_accumulator + dot_delay;
                    end
                end else begin
                    if (dot_delay_clear_before)
                        dot_accumulator <= {ACC_W{1'b0}};
                    dot_out_data <= dot_delay;
                end
            end
            dot_delay_valid <= dot_total_valid;
            dot_delay_operation <= dot_total_operation;
            dot_delay_tag <= dot_total_tag;
            dot_delay_clear_before <= dot_total_clear_before;
            dot_delay_accumulate <= dot_total_accumulate;
            dot_delay_emit_result <= dot_total_emit_result;
            dot_delay <= dot_total;
            dot_total_valid <= dot_group_valid;
            dot_total_operation <= dot_group_operation;
            dot_total_tag <= dot_group_tag;
            dot_total_clear_before <= dot_group_clear_before;
            dot_total_accumulate <= dot_group_accumulate;
            dot_total_emit_result <= dot_group_emit_result;
            dot_total <= dot_group[0] + dot_group[1] +
                         dot_group[2] + dot_group[3];
            dot_group_valid <= dot_product_valid;
            dot_group_operation <= dot_product_operation;
            dot_group_tag <= dot_product_tag;
            dot_group_clear_before <= dot_product_clear_before;
            dot_group_accumulate <= dot_product_accumulate;
            dot_group_emit_result <= dot_product_emit_result;
            for (group_index = 0; group_index < 4; group_index = group_index + 1)
                dot_group[group_index] <=
                    {{(DOT_INTERNAL_W-PRODUCT_W){
                        dot_product[group_index*4][PRODUCT_W-1]}},
                      dot_product[group_index*4]} +
                    {{(DOT_INTERNAL_W-PRODUCT_W){
                        dot_product[group_index*4+1][PRODUCT_W-1]}},
                      dot_product[group_index*4+1]} +
                    {{(DOT_INTERNAL_W-PRODUCT_W){
                        dot_product[group_index*4+2][PRODUCT_W-1]}},
                      dot_product[group_index*4+2]} +
                    {{(DOT_INTERNAL_W-PRODUCT_W){
                        dot_product[group_index*4+3][PRODUCT_W-1]}},
                      dot_product[group_index*4+3]};
            dot_product_valid <= complete_multiply &&
                (active_family == FAMILY_DOT);
            if (complete_multiply && (active_family == FAMILY_DOT)) begin
                dot_product_operation <= multiply_operation;
                dot_product_tag <= multiply_tag;
                dot_product_clear_before <= multiply_clear_before;
                dot_product_accumulate <= multiply_accumulate;
                dot_product_emit_result <= multiply_emit_result;
                for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
                    dot_product[lane_index] <= multiply_lane_valid[lane_index] ?
                        lane_completed_product[lane_index*PRODUCT_W +: PRODUCT_W] :
                        {PRODUCT_W{1'b0}};
            end

            if (multiply_busy) begin
                if (!multiply_high_phase) begin
                    for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
                        low_partial[lane_index] <=
                            lane_phase_product[lane_index*PRODUCT_W +: PRODUCT_W];
                    multiply_high_phase <= 1'b1;
                end else if (accept_multiply) begin
                    multiply_operation <= req_operation;
                    multiply_tag <= req_tag;
                    multiply_lane_valid <= req_lane_valid;
                    multiply_clear_before <= req_clear_before;
                    multiply_accumulate <= req_accumulate;
                    multiply_emit_result <= req_emit_result;
                    multiply_subtract <= req_subtract;
                    for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1) begin
                        multiply_left[lane_index] <=
                            (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) ?
                            req_vector_a[lane_index*DATA_W +: DATA_W] :
                            (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) ?
                            req_vector_b[lane_index*DATA_W +: DATA_W] :
                            req_vector_a[lane_index*DATA_W +: DATA_W];
                        multiply_right[lane_index] <=
                            ((req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_SCALE) ||
                             (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY)) ?
                            req_scalar :
                            (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) ?
                            req_vector_a[lane_index*DATA_W +: DATA_W] :
                            req_vector_b[lane_index*DATA_W +: DATA_W];
                        multiply_addend[lane_index] <=
                            req_vector_a[lane_index*DATA_W +: DATA_W];
                    end
                    multiply_high_phase <= 1'b0;
                end else begin
                    multiply_busy <= 1'b0;
                    multiply_high_phase <= 1'b0;
                end
            end else if (accept_multiply) begin
                multiply_busy <= 1'b1;
                multiply_high_phase <= 1'b0;
                multiply_operation <= req_operation;
                multiply_tag <= req_tag;
                multiply_lane_valid <= req_lane_valid;
                multiply_clear_before <= req_clear_before;
                multiply_accumulate <= req_accumulate;
                multiply_emit_result <= req_emit_result;
                multiply_subtract <= req_subtract;
                for (lane_index = 0; lane_index < LANES; lane_index = lane_index + 1) begin
                    multiply_left[lane_index] <=
                        (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) ?
                        req_vector_a[lane_index*DATA_W +: DATA_W] :
                        (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) ?
                        req_vector_b[lane_index*DATA_W +: DATA_W] :
                        req_vector_a[lane_index*DATA_W +: DATA_W];
                    multiply_right[lane_index] <=
                        ((req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_SCALE) ||
                         (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY)) ?
                        req_scalar :
                        (req_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) ?
                        req_vector_a[lane_index*DATA_W +: DATA_W] :
                        req_vector_b[lane_index*DATA_W +: DATA_W];
                    multiply_addend[lane_index] <= req_vector_a[lane_index*DATA_W +: DATA_W];
                end
            end

            if (accept_request && (active_family == FAMILY_NONE))
                active_family <= requested_family;
            else if (all_internal_empty && !accept_request)
                active_family <= FAMILY_NONE;
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [4:0] f_operation;
    reg [TAG_W-1:0] f_tag;
    reg [LANES*DATA_W-1:0] f_vector;
    reg signed [ACC_W-1:0] f_scalar;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled) begin
            assert(rsp_valid);
            assert(rsp_operation == f_operation);
            assert(rsp_tag == f_tag);
            assert(rsp_vector == f_vector);
            assert(rsp_scalar == f_scalar);
        end
        if (rst_n && f_past_valid) begin
            if (req_valid && req_ready)
                assert(requested_family != FAMILY_NONE);
            assert(!(copy_out_valid && vector_out_valid));
            assert(!(copy_out_valid && dot_out_valid));
            assert(!(vector_out_valid && dot_out_valid));
        end
        f_stalled <= rsp_valid && !rsp_ready;
        f_operation <= rsp_operation;
        f_tag <= rsp_tag;
        f_vector <= rsp_vector;
        f_scalar <= rsp_scalar;
    end
`endif
endmodule

`default_nettype wire
