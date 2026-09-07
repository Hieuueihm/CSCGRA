`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Production arithmetic subsystem. It joins the context router, both reduction
// trees, scalar state, divider and vector sidecar without algorithm control.
module m5_arithmetic_subsystem (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         routine_start,
    input  wire                         scalar_state_clear,
    input  wire                         scalar_preload_valid,
    output wire                         scalar_preload_ready,
    input  wire                         scalar_preload_address,
    input  wire signed [`RECON_ACC_W-1:0] scalar_preload_data,
    input  wire                         fused_scalar_valid,
    output wire                         fused_scalar_ready,
    input  wire                         fused_scalar_address,
    input  wire signed [`RECON_ACC_W-1:0] fused_scalar_data,
    input  wire                         fused_scalar_is_gamma,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire [35:0]                  resource_ctx,
    input  wire [31:0]                  reduction_lane_valid_pair,
    input  wire [16*`RECON_ACC_W-1:0]   cluster0_lane_data,
    input  wire [16*`RECON_ACC_W-1:0]   cluster1_lane_data,
    input  wire [159:0]                 cluster0_lane_index,
    input  wire [159:0]                 cluster1_lane_index,
    input  wire [`RECON_SHARED_VECTOR_LANES-1:0] vector_lane_valid,
    input  wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0] vector_a,
    input  wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0] vector_b,
    input  wire                         vector_result_ready,
    input  wire                         reduction_result_ready,
    output wire                         vector_result_valid,
    output wire [`RECON_SHARED_VECTOR_LANES-1:0] vector_result_lane_valid,
    output wire [`RECON_SHARED_VECTOR_LANES*`RECON_SOLVER_W-1:0]
                                                vector_result_data,
    output wire                         scalar0_valid,
    output wire signed [`RECON_ACC_W-1:0] scalar0_data,
    output wire                         scalar1_valid,
    output wire signed [`RECON_ACC_W-1:0] scalar1_data,
    output wire                         scalar_broadcast_valid,
    output wire signed [`RECON_SOLVER_W-1:0] scalar_broadcast_data,
    output wire                         reduction_result_valid,
    output wire signed [`RECON_ACC_W-1:0] reduction_result_data,
    output wire [9:0]                   reduction_result_index,
    output wire                         reduction_result_fault,
    output wire                         event_valid,
    output wire [3:0]                   event_id,
    output wire [9:0]                   result_index,
    output wire                         divide_by_zero_event,
    output wire                         saturation_event,
    output wire                         fault_valid,
    output wire [7:0]                   fault_code,
    output wire [15:0]                  fault_detail,
    output wire                         resource_in_ready,
    output wire                         resource_out_ready,
    output wire                         resource_contract_error
);
    localparam integer ACC_W = `RECON_ACC_W;
    localparam integer DATA_W = `RECON_SOLVER_W;
    localparam integer LANES = `RECON_SHARED_VECTOR_LANES;
    localparam integer TAG_W = 3;

    wire reduction_req_valid;
    wire reduction_req_ready;
    wire [4:0] reduction_req_operation;
    wire [TAG_W-1:0] reduction_req_tag;
    wire [3:0] reduction_req_lane_mask;
    wire reduction_req_clear;
    wire reduction_req_accumulate;
    wire reduction_req_emit;
    wire scalar_req_valid;
    wire scalar_req_ready;
    wire [4:0] scalar_req_operation;
    wire [TAG_W-1:0] scalar_req_tag;
    wire signed [ACC_W-1:0] scalar_req_numerator;
    wire signed [ACC_W-1:0] scalar_req_denominator;
    wire vector_req_valid;
    wire vector_req_ready;
    wire [4:0] vector_req_operation;
    wire [TAG_W-1:0] vector_req_tag;
    wire [LANES-1:0] vector_req_lane_valid;
    wire [LANES*DATA_W-1:0] vector_req_a;
    wire [LANES*DATA_W-1:0] vector_req_b;
    wire signed [DATA_W-1:0] vector_req_scalar;
    wire vector_req_clear_before;
    wire vector_req_accumulate;
    wire vector_req_emit_result;
    wire vector_req_subtract;

    wire reduction_rsp_valid;
    wire reduction_rsp_ready;
    wire [4:0] reduction_rsp_operation;
    wire [TAG_W-1:0] reduction_rsp_tag;
    wire signed [ACC_W-1:0] reduction_rsp_data;
    wire [9:0] reduction_rsp_index;
    wire reduction_rsp_fault;

    reduction_pipeline reduction_fabric (
        .clk(clk), .rst_n(rst_n), .req_valid(reduction_req_valid),
        .req_ready(reduction_req_ready),
        .req_operation(reduction_req_operation), .req_tag(reduction_req_tag),
        .req_lane_mask(reduction_req_lane_mask),
        .req_lane_valid(reduction_lane_valid_pair),
        .req_cluster0_data(cluster0_lane_data),
        .req_cluster1_data(cluster1_lane_data),
        .req_cluster0_index(cluster0_lane_index),
        .req_cluster1_index(cluster1_lane_index),
        .req_clear_before(reduction_req_clear),
        .req_accumulate(reduction_req_accumulate),
        .req_emit_result(reduction_req_emit),
        .rsp_valid(reduction_rsp_valid), .rsp_ready(reduction_rsp_ready),
        .rsp_operation(reduction_rsp_operation), .rsp_tag(reduction_rsp_tag),
        .rsp_data(reduction_rsp_data), .rsp_index(reduction_rsp_index),
        .rsp_fault(reduction_rsp_fault)
    );

    wire scalar_rsp_valid;
    wire scalar_rsp_ready;
    wire [TAG_W-1:0] scalar_rsp_tag;
    wire signed [DATA_W-1:0] scalar_rsp_data;
    wire scalar_rsp_fault;
    wire [7:0] scalar_rsp_fault_code;
    wire [15:0] scalar_rsp_fault_detail;
    wire scalar_rsp_divide_by_zero;
    wire scalar_rsp_saturated;
    scalar_function_unit scalar_function (
        .clk(clk), .rst_n(rst_n), .req_valid(scalar_req_valid),
        .req_ready(scalar_req_ready), .req_operation(scalar_req_operation),
        .req_tag(scalar_req_tag), .req_numerator(scalar_req_numerator),
        .req_denominator(scalar_req_denominator), .rsp_valid(scalar_rsp_valid),
        .rsp_ready(scalar_rsp_ready), .rsp_tag(scalar_rsp_tag),
        .rsp_result(scalar_rsp_data), .rsp_fault(scalar_rsp_fault),
        .rsp_fault_code(scalar_rsp_fault_code),
        .rsp_fault_detail(scalar_rsp_fault_detail),
        .rsp_divide_by_zero(scalar_rsp_divide_by_zero),
        .rsp_saturated(scalar_rsp_saturated)
    );

    wire vector_rsp_valid;
    wire vector_rsp_ready;
    wire [4:0] vector_rsp_operation;
    wire [TAG_W-1:0] vector_rsp_tag;
    wire [LANES-1:0] vector_rsp_lane_valid;
    wire [LANES*DATA_W-1:0] vector_rsp_data;
    wire signed [ACC_W-1:0] vector_rsp_scalar;
    wire [LANES-1:0] vector_rsp_saturated;
    wire vector_rsp_fault;
    shared_vector_pipeline vector_arithmetic (
        .clk(clk), .rst_n(rst_n), .req_valid(vector_req_valid),
        .req_ready(vector_req_ready), .req_operation(vector_req_operation),
        .req_tag(vector_req_tag), .req_lane_valid(vector_req_lane_valid),
        .req_a(vector_req_a), .req_b(vector_req_b),
        .req_scalar(vector_req_scalar),
        .req_clear(vector_req_clear_before),
        .req_accumulate(vector_req_accumulate),
        .req_emit(vector_req_emit_result),
        .req_subtract(vector_req_subtract), .rsp_valid(vector_rsp_valid),
        .rsp_ready(vector_rsp_ready), .rsp_operation(vector_rsp_operation),
        .rsp_tag(vector_rsp_tag), .rsp_lane_valid(vector_rsp_lane_valid),
        .rsp_data(vector_rsp_data), .rsp_scalar(vector_rsp_scalar),
        .rsp_saturated(vector_rsp_saturated), .rsp_fault(vector_rsp_fault)
    );

    wire scalar_write_valid;
    wire scalar_write_address;
    wire signed [ACC_W-1:0] scalar_write_data;
    wire signed [ACC_W-1:0] scalar0_router_data;
    assign reduction_result_valid = reduction_rsp_valid &&
        reduction_rsp_ready;
    assign reduction_result_data = reduction_rsp_data;
    assign reduction_result_index = reduction_rsp_index;
    assign reduction_result_fault = reduction_rsp_fault;

    scalar_state_subsystem u_scalar_state (
        .clk(clk), .rst_n(rst_n), .clear(scalar_state_clear),
        .cycle_commit(cycle_commit), .ctx(resource_ctx),
        .preload_valid(scalar_preload_valid),
        .preload_ready(scalar_preload_ready),
        .preload_address(scalar_preload_address),
        .preload_data(scalar_preload_data),
        .fused_valid(fused_scalar_valid), .fused_ready(fused_scalar_ready),
        .fused_address(fused_scalar_address), .fused_data(fused_scalar_data),
        .fused_is_gamma(fused_scalar_is_gamma),
        .vector_req_valid(vector_req_valid),
        .scalar_req_valid(scalar_req_valid),
        .router_write_valid(scalar_write_valid),
        .router_write_address(scalar_write_address),
        .router_write_data(scalar_write_data),
        .scalar0_valid(scalar0_valid), .scalar0_data(scalar0_data),
        .scalar1_valid(scalar1_valid), .scalar1_data(scalar1_data),
        .scalar0_router_data(scalar0_router_data)
    );

    array_resource_router router (
        .clk(clk), .rst_n(rst_n), .routine_start(routine_start),
        .cycle_valid(cycle_valid), .cycle_commit(cycle_commit),
        .resource_ctx(resource_ctx),
        .vector_lane_valid(vector_lane_valid), .vector_a(vector_a),
        .vector_b(vector_b), .scalar_0(scalar0_router_data),
        .scalar_1(scalar1_data),
        .reduction_req_valid(reduction_req_valid),
        .reduction_req_ready(reduction_req_ready),
        .reduction_req_operation(reduction_req_operation),
        .reduction_req_tag(reduction_req_tag),
        .reduction_req_lane_mask(reduction_req_lane_mask),
        .reduction_req_clear_before(reduction_req_clear),
        .reduction_req_accumulate(reduction_req_accumulate),
        .reduction_req_emit_result(reduction_req_emit),
        .scalar_req_valid(scalar_req_valid), .scalar_req_ready(scalar_req_ready),
        .scalar_req_operation(scalar_req_operation), .scalar_req_tag(scalar_req_tag),
        .scalar_req_numerator(scalar_req_numerator),
        .scalar_req_denominator(scalar_req_denominator),
        .vector_req_valid(vector_req_valid), .vector_req_ready(vector_req_ready),
        .vector_req_operation(vector_req_operation), .vector_req_tag(vector_req_tag),
        .vector_req_lane_valid(vector_req_lane_valid), .vector_req_a(vector_req_a),
        .vector_req_b(vector_req_b), .vector_req_scalar(vector_req_scalar),
        .vector_req_clear_before(vector_req_clear_before),
        .vector_req_accumulate(vector_req_accumulate),
        .vector_req_emit_result(vector_req_emit_result),
        .vector_req_subtract(vector_req_subtract),
        .reduction_rsp_valid(reduction_rsp_valid),
        .reduction_rsp_ready(reduction_rsp_ready), .reduction_rsp_tag(reduction_rsp_tag),
        .reduction_rsp_data(reduction_rsp_data),
        .reduction_rsp_index(reduction_rsp_index),
        .reduction_rsp_fault(reduction_rsp_fault),
        .scalar_rsp_valid(scalar_rsp_valid), .scalar_rsp_ready(scalar_rsp_ready),
        .scalar_rsp_tag(scalar_rsp_tag), .scalar_rsp_data(scalar_rsp_data),
        .scalar_rsp_fault(scalar_rsp_fault),
        .scalar_rsp_fault_code(scalar_rsp_fault_code),
        .scalar_rsp_fault_detail(scalar_rsp_fault_detail),
        .scalar_rsp_divide_by_zero(scalar_rsp_divide_by_zero),
        .scalar_rsp_saturated(scalar_rsp_saturated),
        .vector_rsp_valid(vector_rsp_valid), .vector_rsp_ready(vector_rsp_ready),
        .vector_rsp_tag(vector_rsp_tag), .vector_rsp_lane_valid(vector_rsp_lane_valid),
        .vector_rsp_data(vector_rsp_data), .vector_rsp_scalar(vector_rsp_scalar),
        .vector_rsp_saturated(vector_rsp_saturated),
        .vector_rsp_fault(vector_rsp_fault),
        .vector_result_ready(vector_result_ready),
        .reduction_result_ready(reduction_result_ready),
        .vector_result_valid(vector_result_valid),
        .vector_result_lane_valid(vector_result_lane_valid),
        .vector_result_data(vector_result_data),
        .scalar_write_valid(scalar_write_valid),
        .scalar_write_address(scalar_write_address),
        .scalar_write_data(scalar_write_data),
        .scalar_broadcast_valid(scalar_broadcast_valid),
        .scalar_broadcast_data(scalar_broadcast_data),
        .event_valid(event_valid), .event_id(event_id),
        .result_index(result_index), .divide_by_zero_event(divide_by_zero_event),
        .saturation_event(saturation_event), .fault_valid(fault_valid),
        .fault_code(fault_code), .fault_detail(fault_detail),
        .resource_in_ready(resource_in_ready),
        .resource_out_ready(resource_out_ready),
        .resource_contract_error(resource_contract_error)
    );

endmodule

`default_nettype wire
