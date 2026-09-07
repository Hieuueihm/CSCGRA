`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"
`include "reconstruction_control_defs.vh"
`include "result_format_defs.vh"

module reconstruction_result_writer #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer SUPPORT_MAX = `RECON_K_MAX,
    parameter integer TAG_W = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_valid,
    output wire start_ready,
    input  wire abort_request,
    input  wire [1:0] result_mode,
    input  wire [10:0] signal_length,
    input  wire [6:0] support_count,
    input  wire [SUPPORT_MAX*INDEX_W-1:0] support_indices,
    input  wire [SUPPORT_MAX*DATA_W-1:0] support_coefficients,
    input  wire [63:0] dense_result_address,
    input  wire [63:0] sparse_result_address,
    input  wire [31:0] user_tag,
    input  wire [3:0] stop_reason,
    output wire busy,

    output wire dma_req_valid,
    input  wire dma_req_ready,
    output wire dma_req_write,
    output wire [63:0] dma_req_addr,
    output wire [15:0] dma_req_bytes,
    output wire [TAG_W-1:0] dma_req_tag,
    output wire dma_wr_valid,
    input  wire dma_wr_ready,
    output wire [127:0] dma_wr_data,
    output wire [15:0] dma_wr_keep,
    output wire dma_wr_last,
    input  wire dma_done_valid,
    output wire dma_done_ready,
    input  wire [TAG_W-1:0] dma_done_tag,
    input  wire dma_done_error,
    input  wire [1:0] dma_done_resp,
    input  wire [8:0] dma_done_beat,

    output reg completion_valid,
    input  wire completion_ready,
    output reg [3:0] completion_stop_reason,
    output reg error_valid,
    input  wire error_ready,
    output reg [7:0] error_code,
    output reg [1:0] error_response,
    output reg [8:0] error_beat,
    output reg [TAG_W-1:0] error_tag
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_REQUEST = 3'd1;
    localparam [2:0] STATE_DATA = 3'd2;
    localparam [2:0] STATE_WAIT = 3'd3;
    localparam [2:0] STATE_COMPLETION = 3'd4;
    localparam [2:0] STATE_ERROR = 3'd5;
    localparam [2:0] STATE_BUILD_DENSE = 3'd6;
    localparam [2:0] STATE_BUILD_SPARSE = 3'd7;

    localparam [1:0] PHASE_DENSE = 2'd0;
    localparam [1:0] PHASE_SPARSE = 2'd1;
    localparam [1:0] PHASE_HEADER = 2'd2;

    reg [2:0] state;
    reg [1:0] active_mode;
    reg [1:0] phase_kind;
    reg [10:0] active_signal_length;
    reg [6:0] active_support_count;
    reg [SUPPORT_MAX*INDEX_W-1:0] active_support_indices;
    reg [SUPPORT_MAX*DATA_W-1:0] active_support_coefficients;
    reg [63:0] active_dense_address;
    reg [63:0] active_sparse_address;
    reg [31:0] active_user_tag;
    reg [3:0] active_stop_reason;
    reg abort_pending;
    reg [63:0] phase_address;
    reg [8:0] phase_total_beats;
    reg [8:0] beats_sent;
    reg [8:0] chunk_beats;
    reg [8:0] chunk_beats_sent;
    reg [TAG_W-1:0] active_dma_tag;
    reg [1:0] dense_build_lane;
    reg [31:0] dense_buffer [0:3];
    reg sparse_build_lane;
    reg [63:0] sparse_buffer [0:1];

    wire request_fire = dma_req_valid && dma_req_ready;
    wire write_fire = dma_wr_valid && dma_wr_ready;
    wire chunk_last = (chunk_beats_sent == chunk_beats - 9'd1);
    wire [8:0] remaining_beats = phase_total_beats - beats_sent;
    wire [8:0] boundary_beats = 9'd256 - {1'b0, phase_address[11:4]};
    wire [8:0] next_chunk_beats =
        (remaining_beats < boundary_beats) ? remaining_beats : boundary_beats;
    wire mode_has_dense = (active_mode == `RECON_RESULT_MODE_DENSE) ||
                          (active_mode == `RECON_RESULT_MODE_BOTH);
    wire mode_has_sparse = (active_mode == `RECON_RESULT_MODE_SPARSE) ||
                           (active_mode == `RECON_RESULT_MODE_BOTH);
    wire [12:0] dense_payload_bytes = {active_signal_length, 2'b00};
    wire [10:0] sparse_payload_bytes = {active_support_count, 3'b000};
    wire [127:0] header_word = {
        7'd0, 1'b1, sparse_payload_bytes, dense_payload_bytes,
        `RECON_RESULT_FORMAT_REVISION, active_mode, active_stop_reason,
        active_support_count, active_signal_length,
        active_user_tag, `RECON_RESULT_HEADER_MAGIC
    };

    function [31:0] dense_word_for_atom;
        input integer atom;
        integer slot;
        reg signed [DATA_W-1:0] coefficient;
        begin
            coefficient = {DATA_W{1'b0}};
            for (slot = 0; slot < SUPPORT_MAX; slot = slot + 1)
                if ((slot < active_support_count) &&
                    (active_support_indices[slot*INDEX_W +: INDEX_W] ==
                     atom[INDEX_W-1:0]))
                    coefficient = active_support_coefficients[
                        slot*DATA_W +: DATA_W];
            if (atom < active_signal_length)
                dense_word_for_atom =
                    {{(32-DATA_W){coefficient[DATA_W-1]}}, coefficient};
            else
                dense_word_for_atom = 32'd0;
        end
    endfunction

    function [63:0] sparse_record_for_slot;
        input integer slot;
        begin
            if (slot < active_support_count)
                sparse_record_for_slot = {
                    {(32-INDEX_W){1'b0}},
                    active_support_indices[slot*INDEX_W +: INDEX_W],
                    {(32-DATA_W){active_support_coefficients[
                        slot*DATA_W + DATA_W-1]}},
                    active_support_coefficients[slot*DATA_W +: DATA_W]
                };
            else
                sparse_record_for_slot = 64'd0;
        end
    endfunction

    assign start_ready = state == STATE_IDLE;
    assign busy = state != STATE_IDLE;
    assign dma_req_valid = (state == STATE_REQUEST) && (chunk_beats != 0) &&
                           !abort_request;
    assign dma_req_write = 1'b1;
    assign dma_req_addr = phase_address;
    assign dma_req_bytes = {chunk_beats, 4'b0000};
    assign dma_req_tag = active_dma_tag;
    assign dma_wr_valid = state == STATE_DATA;
    assign dma_wr_keep = 16'hffff;
    assign dma_wr_last = chunk_last;
    assign dma_done_ready = state == STATE_WAIT;

    assign dma_wr_data = (phase_kind == PHASE_DENSE) ?
        {dense_buffer[3], dense_buffer[2], dense_buffer[1], dense_buffer[0]} :
        (phase_kind == PHASE_SPARSE) ?
        {sparse_buffer[1], sparse_buffer[0]} : header_word;

    task begin_header;
        begin
            phase_kind <= PHASE_HEADER;
            phase_address <= (active_mode == `RECON_RESULT_MODE_DENSE) ?
                active_dense_address : active_sparse_address;
            phase_total_beats <= 9'd1;
            beats_sent <= 9'd0;
            chunk_beats <= 9'd1;
            chunk_beats_sent <= 9'd0;
            active_dma_tag <= 8'hf0;
            state <= STATE_REQUEST;
        end
    endtask

    task begin_sparse_or_header;
        reg [8:0] sparse_beats;
        begin
            sparse_beats = (active_support_count + 7'd1) >> 1;
            if (mode_has_sparse && sparse_beats != 0) begin
                phase_kind <= PHASE_SPARSE;
                phase_address <= active_sparse_address + 64'd16;
                phase_total_beats <= sparse_beats;
                beats_sent <= 9'd0;
                chunk_beats_sent <= 9'd0;
                active_dma_tag <= 8'he0;
                state <= STATE_REQUEST;
            end else begin_header();
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            active_mode <= 2'd0;
            phase_kind <= PHASE_DENSE;
            active_signal_length <= 11'd0;
            active_support_count <= 7'd0;
            active_support_indices <= {SUPPORT_MAX*INDEX_W{1'b0}};
            active_support_coefficients <= {SUPPORT_MAX*DATA_W{1'b0}};
            active_dense_address <= 64'd0;
            active_sparse_address <= 64'd0;
            active_user_tag <= 32'd0;
            active_stop_reason <= `RECON_STOP_NONE;
            abort_pending <= 1'b0;
            phase_address <= 64'd0;
            phase_total_beats <= 9'd0;
            beats_sent <= 9'd0;
            chunk_beats <= 9'd0;
            chunk_beats_sent <= 9'd0;
            active_dma_tag <= {TAG_W{1'b0}};
            dense_build_lane <= 2'd0;
            dense_buffer[0] <= 32'd0;
            dense_buffer[1] <= 32'd0;
            dense_buffer[2] <= 32'd0;
            dense_buffer[3] <= 32'd0;
            sparse_build_lane <= 1'b0;
            sparse_buffer[0] <= 64'd0;
            sparse_buffer[1] <= 64'd0;
            completion_valid <= 1'b0;
            completion_stop_reason <= `RECON_STOP_NONE;
            error_valid <= 1'b0;
            error_code <= 8'd0;
            error_response <= 2'd0;
            error_beat <= 9'd0;
            error_tag <= {TAG_W{1'b0}};
        end else begin
            if (state != STATE_IDLE && abort_request)
                abort_pending <= 1'b1;
            case (state)
                STATE_IDLE: begin
                    completion_valid <= 1'b0;
                    error_valid <= 1'b0;
                    abort_pending <= 1'b0;
                    if (start_valid && !abort_request) begin
                        active_mode <= result_mode;
                        active_signal_length <= signal_length;
                        active_support_count <= support_count;
                        active_support_indices <= support_indices;
                        active_support_coefficients <= support_coefficients;
                        active_dense_address <= dense_result_address;
                        active_sparse_address <= sparse_result_address;
                        active_user_tag <= user_tag;
                        active_stop_reason <= stop_reason;
                        if ((result_mode > `RECON_RESULT_MODE_BOTH) ||
                            (signal_length == 0) ||
                            (support_count > SUPPORT_MAX)) begin
                            error_valid <= 1'b1;
                            error_code <= 8'h01;
                            error_response <= 2'b10;
                            error_beat <= 9'd0;
                            error_tag <= {TAG_W{1'b0}};
                            state <= STATE_ERROR;
                        end else if ((result_mode == `RECON_RESULT_MODE_DENSE) ||
                                     (result_mode == `RECON_RESULT_MODE_BOTH)) begin
                            phase_kind <= PHASE_DENSE;
                            phase_address <= dense_result_address + 64'd16;
                            phase_total_beats <= (signal_length + 11'd3) >> 2;
                            beats_sent <= 9'd0;
                            chunk_beats <= 9'd0;
                            chunk_beats_sent <= 9'd0;
                            active_dma_tag <= 8'hd0;
                            state <= STATE_REQUEST;
                        end else if (support_count != 0) begin
                            phase_kind <= PHASE_SPARSE;
                            phase_address <= sparse_result_address + 64'd16;
                            phase_total_beats <= (support_count + 7'd1) >> 1;
                            beats_sent <= 9'd0;
                            chunk_beats <= 9'd0;
                            chunk_beats_sent <= 9'd0;
                            active_dma_tag <= 8'he0;
                            state <= STATE_REQUEST;
                        end else begin
                            phase_kind <= PHASE_HEADER;
                            phase_address <= sparse_result_address;
                            phase_total_beats <= 9'd1;
                            beats_sent <= 9'd0;
                            chunk_beats <= 9'd1;
                            chunk_beats_sent <= 9'd0;
                            active_dma_tag <= 8'hf0;
                            state <= STATE_REQUEST;
                        end
                    end
                end
                STATE_REQUEST: begin
                    if (chunk_beats == 0)
                        chunk_beats <= next_chunk_beats;
                    if (abort_pending || abort_request) begin
                        completion_stop_reason <= `RECON_STOP_ABORTED;
                        completion_valid <= 1'b1;
                        state <= STATE_COMPLETION;
                    end else if (request_fire) begin
                        chunk_beats_sent <= 9'd0;
                        if (phase_kind == PHASE_DENSE) begin
                            dense_build_lane <= 2'd0;
                            state <= STATE_BUILD_DENSE;
                        end else if (phase_kind == PHASE_SPARSE) begin
                            sparse_build_lane <= 1'b0;
                            state <= STATE_BUILD_SPARSE;
                        end else
                            state <= STATE_DATA;
                    end
                end
                STATE_BUILD_DENSE: begin
                    dense_buffer[dense_build_lane] <= dense_word_for_atom(
                        beats_sent * 4 + dense_build_lane);
                    if (dense_build_lane == 2'd3)
                        state <= STATE_DATA;
                    else
                        dense_build_lane <= dense_build_lane + 1'b1;
                end
                STATE_BUILD_SPARSE: begin
                    sparse_buffer[sparse_build_lane] <= sparse_record_for_slot(
                        beats_sent * 2 + sparse_build_lane);
                    if (sparse_build_lane)
                        state <= STATE_DATA;
                    else
                        sparse_build_lane <= 1'b1;
                end
                STATE_DATA: begin
                    if (write_fire) begin
                        beats_sent <= beats_sent + 9'd1;
                        if (chunk_last)
                            state <= STATE_WAIT;
                        else begin
                            chunk_beats_sent <= chunk_beats_sent + 9'd1;
                            if (phase_kind == PHASE_DENSE) begin
                                dense_build_lane <= 2'd0;
                                state <= STATE_BUILD_DENSE;
                            end else if (phase_kind == PHASE_SPARSE) begin
                                sparse_build_lane <= 1'b0;
                                state <= STATE_BUILD_SPARSE;
                            end
                        end
                    end
                end
                STATE_WAIT: begin
                    if (dma_done_valid) begin
                        if (dma_done_error || (dma_done_tag != active_dma_tag)) begin
                            error_valid <= 1'b1;
                            error_code <= (dma_done_tag != active_dma_tag) ?
                                8'h02 : 8'h10;
                            error_response <= dma_done_resp;
                            error_beat <= dma_done_beat;
                            error_tag <= dma_done_tag;
                            state <= STATE_ERROR;
                        end else if (abort_pending || abort_request) begin
                            completion_stop_reason <= `RECON_STOP_ABORTED;
                            completion_valid <= 1'b1;
                            state <= STATE_COMPLETION;
                        end else if (beats_sent < phase_total_beats) begin
                            phase_address <= phase_address + {chunk_beats, 4'b0000};
                            chunk_beats <= 9'd0;
                            chunk_beats_sent <= 9'd0;
                            active_dma_tag <= active_dma_tag + 1'b1;
                            state <= STATE_REQUEST;
                        end else if (phase_kind == PHASE_DENSE) begin
                            chunk_beats <= 9'd0;
                            begin_sparse_or_header();
                        end else if (phase_kind == PHASE_SPARSE) begin
                            chunk_beats <= 9'd0;
                            begin_header();
                        end else begin
                            completion_stop_reason <= active_stop_reason;
                            completion_valid <= 1'b1;
                            state <= STATE_COMPLETION;
                        end
                    end
                end
                STATE_COMPLETION: begin
                    if (completion_valid && completion_ready) begin
                        completion_valid <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
                STATE_ERROR: begin
                    if (error_valid && error_ready) begin
                        error_valid <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_req_valid;
    reg f_req_ready;
    reg [63:0] f_req_addr;
    reg [15:0] f_req_bytes;
    reg [TAG_W-1:0] f_req_tag;
    reg f_wr_valid;
    reg f_wr_ready;
    reg [127:0] f_wr_data;
    reg f_wr_last;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_req_valid <= dma_req_valid;
        f_req_ready <= dma_req_ready;
        f_req_addr <= dma_req_addr;
        f_req_bytes <= dma_req_bytes;
        f_req_tag <= dma_req_tag;
        f_wr_valid <= dma_wr_valid;
        f_wr_ready <= dma_wr_ready;
        f_wr_data <= dma_wr_data;
        f_wr_last <= dma_wr_last;
        if (rst_n) begin
            assert(!(completion_valid && error_valid));
            if (dma_req_valid) begin
                assert(dma_req_write);
                assert(dma_req_addr[3:0] == 0);
                assert(dma_req_bytes != 0);
                assert(dma_req_bytes <= 4096);
                assert({1'b0, dma_req_addr[11:0]} + dma_req_bytes <= 4096);
            end
            if (f_past_valid && f_req_valid && !f_req_ready) begin
                assert(dma_req_valid);
                assert(dma_req_addr == f_req_addr);
                assert(dma_req_bytes == f_req_bytes);
                assert(dma_req_tag == f_req_tag);
            end
            if (f_past_valid && f_wr_valid && !f_wr_ready) begin
                assert(dma_wr_valid);
                assert(dma_wr_data == f_wr_data);
                assert(dma_wr_last == f_wr_last);
            end
            if (completion_valid)
                assert(!error_valid);
        end
    end
`endif
endmodule

`default_nettype wire
