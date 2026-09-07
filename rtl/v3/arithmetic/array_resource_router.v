`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "architecture_guard_defs.vh"

// Decodes the 36-bit resource context and presents the M5 arithmetic leaves as
// compiler-scheduled MRRG resources. Scalar and vector classes still allow one
// outstanding transaction. Reduction keeps a 4-deep tag queue so dense
// correlation can issue the next column before TOPK/writeback drains the
// previous result. MEMORY_STREAM reductions still retire on wait_for_result;
// TOPK_STATE results auto-retire into the operator queue. Requests and
// response side effects occur only on cycle_commit.
module array_resource_router #(
    parameter integer ACC_W = `RECON_ACC_W,
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer LANES = `RECON_SHARED_VECTOR_LANES,
    parameter integer TAG_W = 3
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         routine_start,
    input  wire                         cycle_valid,
    input  wire                         cycle_commit,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx,

    input  wire [LANES-1:0]             vector_lane_valid,
    input  wire [LANES*DATA_W-1:0]      vector_a,
    input  wire [LANES*DATA_W-1:0]      vector_b,
    input  wire signed [ACC_W-1:0]      scalar_0,
    input  wire signed [ACC_W-1:0]      scalar_1,

    output wire                         reduction_req_valid,
    input  wire                         reduction_req_ready,
    output wire [4:0]                   reduction_req_operation,
    output wire [TAG_W-1:0]             reduction_req_tag,
    output wire [3:0]                   reduction_req_lane_mask,
    output wire                         reduction_req_clear_before,
    output wire                         reduction_req_accumulate,
    output wire                         reduction_req_emit_result,

    output wire                         scalar_req_valid,
    input  wire                         scalar_req_ready,
    output wire [4:0]                   scalar_req_operation,
    output wire [TAG_W-1:0]             scalar_req_tag,
    output wire signed [ACC_W-1:0]      scalar_req_numerator,
    output wire signed [ACC_W-1:0]      scalar_req_denominator,

    output wire                         vector_req_valid,
    input  wire                         vector_req_ready,
    output wire [4:0]                   vector_req_operation,
    output wire [TAG_W-1:0]             vector_req_tag,
    output wire [LANES-1:0]             vector_req_lane_valid,
    output wire [LANES*DATA_W-1:0]      vector_req_a,
    output wire [LANES*DATA_W-1:0]      vector_req_b,
    output wire signed [DATA_W-1:0]     vector_req_scalar,
    output wire                         vector_req_clear_before,
    output wire                         vector_req_accumulate,
    output wire                         vector_req_emit_result,
    output wire                         vector_req_subtract,

    input  wire                         reduction_rsp_valid,
    output wire                         reduction_rsp_ready,
    input  wire [TAG_W-1:0]             reduction_rsp_tag,
    input  wire signed [ACC_W-1:0]      reduction_rsp_data,
    input  wire [9:0]                   reduction_rsp_index,
    input  wire                         reduction_rsp_fault,

    input  wire                         scalar_rsp_valid,
    output wire                         scalar_rsp_ready,
    input  wire [TAG_W-1:0]             scalar_rsp_tag,
    input  wire signed [DATA_W-1:0]     scalar_rsp_data,
    input  wire                         scalar_rsp_fault,
    input  wire [7:0]                   scalar_rsp_fault_code,
    input  wire [15:0]                  scalar_rsp_fault_detail,
    input  wire                         scalar_rsp_divide_by_zero,
    input  wire                         scalar_rsp_saturated,

    input  wire                         vector_rsp_valid,
    output wire                         vector_rsp_ready,
    input  wire [TAG_W-1:0]             vector_rsp_tag,
    input  wire [LANES-1:0]             vector_rsp_lane_valid,
    input  wire [LANES*DATA_W-1:0]      vector_rsp_data,
    input  wire signed [ACC_W-1:0]      vector_rsp_scalar,
    input  wire [LANES-1:0]             vector_rsp_saturated,
    input  wire                         vector_rsp_fault,

    input  wire                         vector_result_ready,
    input  wire                         reduction_result_ready,
    output wire                         vector_result_valid,
    output wire [LANES-1:0]             vector_result_lane_valid,
    output wire [LANES*DATA_W-1:0]      vector_result_data,
    output wire                         scalar_write_valid,
    output wire                         scalar_write_address,
    output wire signed [ACC_W-1:0]      scalar_write_data,
    output wire                         scalar_broadcast_valid,
    output wire signed [DATA_W-1:0]     scalar_broadcast_data,
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
    localparam [1:0] CLASS_REDUCTION = 2'd0;
    localparam [1:0] CLASS_SCALAR = 2'd1;
    localparam [1:0] CLASS_VECTOR = 2'd2;
    localparam [1:0] CLASS_NONE = 2'd3;

    wire [`RECON_RESOURCE_FIELD_OPERATION_W-1:0] operation =
        resource_ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
                     `RECON_RESOURCE_FIELD_OPERATION_W];
    wire [`RECON_RESOURCE_FIELD_INPUT_SELECT_W-1:0] input_select =
        resource_ctx[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_INPUT_SELECT_W];
    wire [`RECON_RESOURCE_FIELD_OUTPUT_SELECT_W-1:0] output_select =
        resource_ctx[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
                     `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W];
    wire [`RECON_RESOURCE_FIELD_CONFIGURATION_ID_W-1:0] configuration_id =
        resource_ctx[`RECON_RESOURCE_FIELD_CONFIGURATION_ID_LSB +:
                     `RECON_RESOURCE_FIELD_CONFIGURATION_ID_W];
    wire [`RECON_RESOURCE_FIELD_LANE_MASK_W-1:0] lane_mask =
        resource_ctx[`RECON_RESOURCE_FIELD_LANE_MASK_LSB +:
                     `RECON_RESOURCE_FIELD_LANE_MASK_W];
    wire clear_before =
        resource_ctx[`RECON_RESOURCE_FIELD_CLEAR_BEFORE_LSB];
    wire accumulate =
        resource_ctx[`RECON_RESOURCE_FIELD_ACCUMULATE_LSB];
    wire commit_after =
        resource_ctx[`RECON_RESOURCE_FIELD_COMMIT_AFTER_LSB];
    wire wait_for_ready =
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_READY_LSB];
    wire wait_for_result =
        resource_ctx[`RECON_RESOURCE_FIELD_WAIT_FOR_RESULT_LSB];
    wire [`RECON_RESOURCE_FIELD_EVENT_ID_W-1:0] context_event_id =
        resource_ctx[`RECON_RESOURCE_FIELD_EVENT_ID_LSB +:
                     `RECON_RESOURCE_FIELD_EVENT_ID_W];

    function [1:0] operation_class;
        input [4:0] op;
        begin
            if ((op >= `RECON_RESOURCE_OP_REDUCE_SUM) &&
                (op <= `RECON_RESOURCE_OP_REDUCE_MAX_ABS))
                operation_class = CLASS_REDUCTION;
            else if ((op >= `RECON_RESOURCE_OP_SCALAR_RECIPROCAL) &&
                     (op <= `RECON_RESOURCE_OP_SCALAR_SQRT))
                operation_class = CLASS_SCALAR;
            else if ((op >= `RECON_RESOURCE_OP_SHARED_VECTOR_DOT) &&
                     (op <= `RECON_RESOURCE_OP_SHARED_VECTOR_COPY))
                operation_class = CLASS_VECTOR;
            else
                operation_class = CLASS_NONE;
        end
    endfunction

    wire [1:0] selected_class = operation_class(operation);
    wire m5_owned = selected_class != CLASS_NONE;
    wire unsupported_operation = !m5_owned &&
        (operation != `RECON_RESOURCE_OP_NOP);
    reg [2:0] sequence_bits;
    reg [2:0] pending_valid;
    reg [2:0] pending_tag [0:2];
    reg [2:0] pending_output [0:2];
    reg [3:0] pending_event [0:2];
    reg [1:0] reduction_seq;
    reg [2:0] reduction_outstanding;
    reg [2:0] red_tag_q [0:3];
    reg [2:0] red_out_q [0:3];
    reg [1:0] red_rd;
    reg [1:0] red_wr;
    reg broadcast_valid_reg;
    reg signed [DATA_W-1:0] broadcast_data_reg;

    wire [TAG_W-1:0] reduction_tag = {1'b0, reduction_seq};
    wire [TAG_W-1:0] scalar_tag = {CLASS_SCALAR, sequence_bits[1]};
    wire [TAG_W-1:0] vector_tag = {CLASS_VECTOR, sequence_bits[2]};
    wire selected_pending = (selected_class == CLASS_REDUCTION) ?
                            (reduction_outstanding != 3'd0) :
                            (selected_class == CLASS_SCALAR) ? pending_valid[1] :
                            (selected_class == CLASS_VECTOR) ? pending_valid[2] : 1'b0;
    wire selected_req_ready = (selected_class == CLASS_REDUCTION) ?
                                  reduction_req_ready :
                              (selected_class == CLASS_SCALAR) ? scalar_req_ready :
                              (selected_class == CLASS_VECTOR) ? vector_req_ready : 1'b1;
    wire vector_reduction_operation =
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_DOT) ||
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ);
    wire request_creates_response = (selected_class == CLASS_REDUCTION) ?
                                        commit_after :
                                    (selected_class == CLASS_VECTOR) ?
                                        (!vector_reduction_operation || commit_after) :
                                        m5_owned;
    wire reduction_issue_allowed = reduction_outstanding < 3'd4;
    wire issue_allowed = !request_creates_response ||
        ((selected_class == CLASS_REDUCTION) ? reduction_issue_allowed :
         !selected_pending);

    wire [TAG_W-1:0] expected_tag = (selected_class == CLASS_REDUCTION) ?
                                    red_tag_q[red_rd] :
                                    (selected_class == CLASS_SCALAR) ? pending_tag[1] :
                                    pending_tag[2];
    wire selected_rsp_valid = (selected_class == CLASS_REDUCTION) ? reduction_rsp_valid :
                              (selected_class == CLASS_SCALAR) ? scalar_rsp_valid :
                              (selected_class == CLASS_VECTOR) ? vector_rsp_valid : 1'b0;
    wire [TAG_W-1:0] selected_rsp_tag = (selected_class == CLASS_REDUCTION) ?
                                            reduction_rsp_tag :
                                        (selected_class == CLASS_SCALAR) ? scalar_rsp_tag :
                                        vector_rsp_tag;
    wire [2:0] selected_pending_output =
        (selected_class == CLASS_REDUCTION) ? red_out_q[red_rd] :
        (selected_class == CLASS_SCALAR) ? pending_output[1] : pending_output[2];
    wire selected_fault = (selected_class == CLASS_REDUCTION) ? reduction_rsp_fault :
                          (selected_class == CLASS_SCALAR) ? scalar_rsp_fault :
                          vector_rsp_fault;
    wire signed [ACC_W-1:0] selected_scalar_data =
        (selected_class == CLASS_REDUCTION) ? reduction_rsp_data :
        (selected_class == CLASS_SCALAR) ?
            {{(ACC_W-DATA_W){scalar_rsp_data[DATA_W-1]}}, scalar_rsp_data} :
            vector_rsp_scalar;
    wire response_sink_ready =
        (selected_class == CLASS_REDUCTION) ? reduction_result_ready :
        ((selected_class == CLASS_VECTOR) &&
         (selected_pending_output == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM)) ?
            vector_result_ready : 1'b1;
    wire response_available = selected_pending && selected_rsp_valid &&
                              (selected_rsp_tag == expected_tag) && response_sink_ready;
    wire selected_broadcast_output =
        selected_pending_output == `RECON_RESOURCE_OUTPUT_PE_SCALAR_BROADCAST;
    wire capture_broadcast = cycle_valid && m5_owned && wait_for_result &&
        response_available && selected_broadcast_output && !selected_fault &&
        !broadcast_valid_reg;
    wire selected_response_ready = selected_broadcast_output && !selected_fault ?
        broadcast_valid_reg : response_available;

    assign resource_in_ready = !cycle_valid || !m5_owned || !wait_for_ready ||
                               (selected_req_ready && issue_allowed);
    wire red_head_auto_retires = (reduction_outstanding != 3'd0) &&
        (red_out_q[red_rd] == `RECON_RESOURCE_OUTPUT_TOPK_STATE);
    wire reduction_head_match = (reduction_outstanding != 3'd0) &&
        reduction_rsp_valid && (reduction_rsp_tag == red_tag_q[red_rd]) &&
        reduction_result_ready;
    wire reduction_auto_retire = reduction_head_match && red_head_auto_retires;
    wire reduction_wait_match = reduction_head_match;
    assign resource_out_ready = !cycle_valid || !m5_owned || !wait_for_result ||
        ((selected_class == CLASS_REDUCTION) ? reduction_wait_match :
         selected_response_ready);
    assign resource_contract_error = cycle_valid &&
        (unsupported_operation ||
         (m5_owned &&
          (((operation == `RECON_RESOURCE_OP_NOP) &&
            (wait_for_ready || wait_for_result)) ||
           (wait_for_result && selected_rsp_valid &&
            (selected_class != CLASS_REDUCTION) &&
            (!selected_pending || (selected_rsp_tag != expected_tag))))));

    wire issue = cycle_valid && cycle_commit && m5_owned && !wait_for_result;
    assign reduction_req_valid = issue && (selected_class == CLASS_REDUCTION);
    assign reduction_req_operation = operation;
    assign reduction_req_tag = reduction_tag;
    assign reduction_req_lane_mask = lane_mask;
    assign reduction_req_clear_before = clear_before;
    assign reduction_req_accumulate = accumulate;
    assign reduction_req_emit_result = commit_after;

    assign scalar_req_valid = issue && (selected_class == CLASS_SCALAR);
    assign scalar_req_operation = operation;
    assign scalar_req_tag = scalar_tag;
    assign scalar_req_numerator =
        (input_select == `RECON_RESOURCE_INPUT_SCALAR_1) ? scalar_1 : scalar_0;
    assign scalar_req_denominator =
        (input_select == `RECON_RESOURCE_INPUT_SCALAR_1) ? scalar_0 : scalar_1;

    assign vector_req_valid = issue && (selected_class == CLASS_VECTOR);
    assign vector_req_operation = operation;
    assign vector_req_tag = vector_tag;
    assign vector_req_lane_valid = vector_lane_valid;
    assign vector_req_a = vector_a;
    assign vector_req_b = vector_b;
    assign vector_req_scalar =
        (input_select == `RECON_RESOURCE_INPUT_SCALAR_1) ?
        scalar_1[DATA_W-1:0] : scalar_0[DATA_W-1:0];
    assign vector_req_clear_before = clear_before;
    assign vector_req_accumulate = accumulate;
    assign vector_req_emit_result = commit_after || !vector_reduction_operation;
    assign vector_req_subtract =
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) && configuration_id[0];

    wire consume_response = cycle_valid && cycle_commit && m5_owned && wait_for_result;
    wire reduction_wait_retire = consume_response &&
        (selected_class == CLASS_REDUCTION) && reduction_wait_match;
    wire reduction_pop = reduction_auto_retire || reduction_wait_retire;
    wire reduction_push = issue && (selected_class == CLASS_REDUCTION) &&
        selected_req_ready && issue_allowed && request_creates_response;
    assign reduction_rsp_ready = reduction_auto_retire || reduction_wait_retire;
    assign scalar_rsp_ready = consume_response && (selected_class == CLASS_SCALAR);
    assign vector_rsp_ready = consume_response && (selected_class == CLASS_VECTOR);

    assign vector_result_valid = consume_response &&
        (selected_class == CLASS_VECTOR) &&
        (selected_pending_output == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        !selected_fault;
    assign vector_result_lane_valid = vector_rsp_lane_valid;
    assign vector_result_data = vector_rsp_data;
    assign scalar_write_valid = consume_response && !selected_fault &&
        ((selected_pending_output == `RECON_RESOURCE_OUTPUT_SCALAR_0) ||
         (selected_pending_output == `RECON_RESOURCE_OUTPUT_SCALAR_1));
    assign scalar_write_address =
        selected_pending_output == `RECON_RESOURCE_OUTPUT_SCALAR_1;
    assign scalar_write_data = selected_scalar_data;
    assign scalar_broadcast_valid = cycle_valid && m5_owned &&
        wait_for_result && broadcast_valid_reg && selected_broadcast_output;
    assign scalar_broadcast_data = broadcast_data_reg;
    assign event_valid = consume_response && !selected_fault &&
        (selected_pending_output == `RECON_RESOURCE_OUTPUT_EVENT);
    assign event_id = (selected_class == CLASS_REDUCTION) ? pending_event[0] :
                      (selected_class == CLASS_SCALAR) ? pending_event[1] :
                      pending_event[2];
    assign result_index = reduction_rsp_index;
    assign divide_by_zero_event = consume_response &&
                                  (selected_class == CLASS_SCALAR) &&
                                  scalar_rsp_divide_by_zero;
    assign saturation_event = consume_response &&
        (((selected_class == CLASS_SCALAR) && scalar_rsp_saturated) ||
         ((selected_class == CLASS_VECTOR) && |vector_rsp_saturated));
    assign fault_valid = consume_response && selected_fault;
    assign fault_code = (selected_class == CLASS_SCALAR) ?
                        scalar_rsp_fault_code :
                        `RECON_CONTEXT_ERROR_RESOURCE_CONTRACT;
    assign fault_detail = (selected_class == CLASS_SCALAR) ?
                          scalar_rsp_fault_detail :
                          {3'd0, operation, 8'd0};

    integer class_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            sequence_bits <= 3'd0;
            pending_valid <= 3'd0;
            reduction_seq <= 2'd0;
            reduction_outstanding <= 3'd0;
            red_rd <= 2'd0;
            red_wr <= 2'd0;
            broadcast_valid_reg <= 1'b0;
            broadcast_data_reg <= {DATA_W{1'b0}};
            for (class_index = 0; class_index < 3; class_index = class_index + 1) begin
                pending_tag[class_index] <= 3'd0;
                pending_output[class_index] <= `RECON_RESOURCE_OUTPUT_DISCARD;
                pending_event[class_index] <= 4'd0;
            end
        end else begin
            if (routine_start) begin
                sequence_bits <= 3'd0;
                pending_valid <= 3'd0;
                reduction_seq <= 2'd0;
                reduction_outstanding <= 3'd0;
                red_rd <= 2'd0;
                red_wr <= 2'd0;
                broadcast_valid_reg <= 1'b0;
                broadcast_data_reg <= {DATA_W{1'b0}};
                for (class_index = 0; class_index < 3;
                        class_index = class_index + 1) begin
                    pending_tag[class_index] <= 3'd0;
                    pending_output[class_index] <=
                        `RECON_RESOURCE_OUTPUT_DISCARD;
                    pending_event[class_index] <= 4'd0;
                end
            end else begin
                if (capture_broadcast) begin
                    broadcast_valid_reg <= 1'b1;
                    broadcast_data_reg <= selected_scalar_data[DATA_W-1:0];
                end
                if (consume_response) begin
                    if (selected_broadcast_output)
                        broadcast_valid_reg <= 1'b0;
                    case (selected_class)
                        CLASS_SCALAR: pending_valid[1] <= 1'b0;
                        CLASS_VECTOR: pending_valid[2] <= 1'b0;
                        default: begin end
                    endcase
                end
                if (reduction_pop) begin
                    red_rd <= red_rd + 2'd1;
                    if (!reduction_push)
                        reduction_outstanding <= reduction_outstanding - 3'd1;
                end
            end
            if (issue && selected_req_ready && issue_allowed && request_creates_response) begin
                case (selected_class)
                    CLASS_REDUCTION: begin
                        red_tag_q[red_wr] <= reduction_tag;
                        red_out_q[red_wr] <= output_select;
                        red_wr <= red_wr + 2'd1;
                        if (!reduction_pop)
                            reduction_outstanding <=
                                reduction_outstanding + 3'd1;
                        reduction_seq <= reduction_seq + 2'd1;
                    end
                    CLASS_SCALAR: begin
                        pending_valid[1] <= 1'b1;
                        pending_tag[1] <= scalar_tag;
                        pending_output[1] <= output_select;
                        pending_event[1] <= context_event_id;
                        sequence_bits[1] <= ~sequence_bits[1];
                    end
                    CLASS_VECTOR: begin
                        pending_valid[2] <= 1'b1;
                        pending_tag[2] <= vector_tag;
                        pending_output[2] <= output_select;
                        pending_event[2] <= context_event_id;
                        sequence_bits[2] <= ~sequence_bits[2];
                    end
                    default: begin end
                endcase
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [`RECON_RESOURCE_CONTEXT_W-1:0] f_context;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled)
            assert(resource_ctx == f_context);
        if (reduction_req_valid || scalar_req_valid || vector_req_valid)
            assert(cycle_commit);
        if (scalar_write_valid || vector_result_valid || event_valid || fault_valid)
            assert(cycle_commit && wait_for_result);
        if (scalar_broadcast_valid)
            assert(broadcast_valid_reg && selected_broadcast_output && !selected_fault);
        if (consume_response && selected_broadcast_output && !selected_fault)
            assert(broadcast_valid_reg);
        assert(!(reduction_req_valid && scalar_req_valid));
        assert(!(reduction_req_valid && vector_req_valid));
        assert(!(scalar_req_valid && vector_req_valid));
        f_stalled <= cycle_valid && !(resource_in_ready && resource_out_ready);
        f_context <= resource_ctx;
    end
`endif
endmodule

`default_nettype wire
