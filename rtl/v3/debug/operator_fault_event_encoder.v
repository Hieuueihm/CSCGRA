`timescale 1ns/1ps
`default_nettype none

`include "context_isa_defs.vh"

module operator_fault_event_encoder (
    input wire [8:0] measurement_count,
    input wire stream_contract_error,
    input wire dispatcher_contract_error,
    input wire phi_config_error,
    input wire [1:0] cgra_contract_error,
    input wire [1:0] cgra_saturation,
    input wire m5_saturation_event,
    input wire m5_fault_valid,
    input wire reduction_result_valid,
    input wire reduction_result_fault,
    input wire lane_normalizer_output_fire,
    input wire normalizer_output_saturated,
    input wire selection_fault_valid,
    input wire [7:0] write_pack_error,
    input wire scratch_init_valid,
    input wire scratch_preload_active,
    input wire scratch_preload_p0_valid,
    input wire scratch_preload_p1_valid,
    input wire execution_active,
    input wire support_scalar_mode,
    input wire [15:0] stream_a_element_count,
    input wire [6:0] resident_work_count,
    input wire stream_scratch_conflict,
    input wire vector_candidate_mode,
    input wire vector_support_scatter_mode,
    input wire vector_topk_support_slot_mode,
    input wire [10:0] signal_length,
    input wire vector_candidate_fault,
    input wire [2:0] phi_mode,
    input wire phi_consume_context,
    input wire vec_a_enable,
    input wire [1:0] external_a_select,
    input wire config_a_valid,
    input wire [63:0] config_a_data,
    input wire reduction_source_missing,
    input wire phi_stream_order_error_now,
    input wire phi_order_error,
    input wire phi_cache_fault,
    output wire [8:0] padded_measurement_count,
    output wire fault_event,
    output wire [15:0] fault_event_detail
);
    wire [9:0] rounded_measurement_count =
        {1'b0, measurement_count} + 10'd31;
    wire support_scalar_count_error = support_scalar_mode &&
        (stream_a_element_count < {9'd0, resident_work_count});
    wire [10:0] vector_required_count =
        (vector_support_scatter_mode || vector_topk_support_slot_mode) ?
        {4'd0, resident_work_count} : signal_length;
    wire vector_candidate_error = vector_candidate_mode &&
        ((stream_a_element_count < {5'd0, vector_required_count}) ||
         vector_candidate_fault);
    wire transpose_config_error = (phi_mode == 3'd3) &&
        phi_consume_context && vec_a_enable &&
        ((external_a_select != `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ||
         (config_a_valid &&
          ((config_a_data[54:52] != `RECON_ELEMENT_FORMAT_SOLVER27) ||
           (config_a_data[57:55] != `RECON_PACKING_MODE_TWO) ||
           (config_a_data[31:16] < {7'd0, padded_measurement_count}) ||
           (|config_a_data[20:16]))));
    wire lane_normalizer_fault = lane_normalizer_output_fire &&
        normalizer_output_saturated;

    assign padded_measurement_count =
        {rounded_measurement_count[8:5], 5'd0};
    assign fault_event = stream_contract_error ||
        dispatcher_contract_error || phi_config_error ||
        (|cgra_contract_error) || (|cgra_saturation) ||
        m5_saturation_event || m5_fault_valid ||
        (reduction_result_valid && reduction_result_fault) ||
        lane_normalizer_fault || selection_fault_valid ||
        (|write_pack_error) ||
        (scratch_init_valid && execution_active) ||
        (scratch_preload_active && execution_active) ||
        (scratch_preload_p0_valid && execution_active) ||
        (scratch_preload_p1_valid && execution_active) ||
        support_scalar_count_error || stream_scratch_conflict ||
        vector_candidate_error || transpose_config_error ||
        reduction_source_missing || phi_stream_order_error_now ||
        phi_order_error || phi_cache_fault;
    assign fault_event_detail =
        {phi_config_error, |cgra_contract_error, |cgra_saturation,
         m5_fault_valid,
         (reduction_result_valid && reduction_result_fault),
         selection_fault_valid, |write_pack_error, stream_contract_error,
         dispatcher_contract_error, phi_order_error, phi_cache_fault,
         4'd0, lane_normalizer_fault};
endmodule

`default_nettype wire
