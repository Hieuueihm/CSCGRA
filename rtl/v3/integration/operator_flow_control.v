`timescale 1ns/1ps
`default_nettype none

module operator_flow_control (
    input wire operator_fault,
    input wire phi_capture_enable,
    input wire cycle_valid,
    input wire phi_consume_context,
    input wire phi_symbol_valid,
    input wire phi_capture_ready,
    input wire d18_split_mode,
    input wire d18_split_valid,
    input wire vector_candidate_mode,
    input wire vector_candidate_valid,
    input wire router_stream_in_ready,
    input wire router_stream_out_ready,
    input wire dispatcher_resource_in_ready,
    input wire dispatcher_resource_out_ready,
    output wire stream_input_ready,
    output wire stream_output_ready,
    output wire resource_req_ready,
    output wire resource_rsp_valid
);
    wire cache_capture_blocked = phi_capture_enable && cycle_valid &&
        phi_consume_context && phi_symbol_valid && !phi_capture_ready;
    wire buffered_vector_candidate_ready = vector_candidate_mode &&
        vector_candidate_valid;

    assign stream_input_ready = !operator_fault && !cache_capture_blocked &&
        (!d18_split_mode || d18_split_valid) &&
        (buffered_vector_candidate_ready || router_stream_in_ready);
    assign stream_output_ready = !operator_fault && !cache_capture_blocked &&
        router_stream_out_ready;
    assign resource_req_ready = !operator_fault &&
        dispatcher_resource_in_ready;
    assign resource_rsp_valid = !operator_fault &&
        dispatcher_resource_out_ready;
endmodule

`default_nettype wire
