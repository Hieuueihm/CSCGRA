`timescale 1ns/1ps
`default_nettype none

`include "reconstruction_control_defs.vh"

// Fetches exactly one aligned 64-byte run configuration through DMA client 0.
// No field is decoded here; a payload is published only after a clean terminal
// DMA completion.
module configuration_fetch_unit #(
    parameter integer ADDRESS_W = 64,
    parameter integer TAG_W = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start_valid,
    output wire                   start_ready,
    input  wire [ADDRESS_W-1:0]   start_address,
    input  wire                   abort_request,
    output wire                   fetch_active,
    output wire                   dma_req_valid,
    input  wire                   dma_req_ready,
    output wire                   dma_req_write,
    output wire [ADDRESS_W-1:0]   dma_req_addr,
    output wire [15:0]            dma_req_bytes,
    output wire [TAG_W-1:0]       dma_req_tag,
    input  wire                   dma_rd_valid,
    output wire                   dma_rd_ready,
    input  wire [`RECON_DMA_DATA_W-1:0] dma_rd_data,
    input  wire                   dma_rd_last,
    input  wire [1:0]             dma_rd_resp,
    input  wire [TAG_W-1:0]       dma_rd_tag,
    input  wire                   dma_done_valid,
    output wire                   dma_done_ready,
    input  wire [TAG_W-1:0]       dma_done_tag,
    input  wire                   dma_done_error,
    input  wire [1:0]             dma_done_resp,
    input  wire [8:0]             dma_completion_beat,
    output wire                   run_configuration_valid,
    input  wire                   run_configuration_ready,
    output wire [`RECON_RUN_CONFIGURATION_BITS-1:0]
                                   run_configuration_data,
    output wire                   error_valid,
    input  wire                   error_ready,
    output reg  [7:0]             error_code,
    output reg  [4:0]             cfg_error_word,
    output reg  [31:0]            error_detail
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_REQUEST = 3'd1;
    localparam [2:0] STATE_RECEIVE = 3'd2;
    localparam [2:0] STATE_RUN_CONFIGURATION = 3'd3;
    localparam [2:0] STATE_ERROR = 3'd4;
    localparam [TAG_W-1:0] CONFIGURATION_TAG = {{(TAG_W-1){1'b0}}, 1'b1};
    localparam [2:0] CONFIGURATION_BEATS =
        `RECON_RUN_CONFIGURATION_BITS / `RECON_DMA_DATA_W;

    reg [2:0] state;
    reg [ADDRESS_W-1:0] address_register;
    reg [2:0] beat_count;
    reg [`RECON_RUN_CONFIGURATION_BITS-1:0] beat_buffer;
    reg observed_read_error;
    reg abort_pending;
    reg [1:0] observed_read_response;
    reg [2:0] observed_error_beat;

    assign start_ready = (state == STATE_IDLE);
    assign fetch_active = (state == STATE_REQUEST) || (state == STATE_RECEIVE);
    assign dma_req_valid = (state == STATE_REQUEST);
    assign dma_req_write = 1'b0;
    assign dma_req_addr = address_register;
    assign dma_req_bytes = `RECON_RUN_CONFIGURATION_BYTES;
    assign dma_req_tag = CONFIGURATION_TAG;
    assign dma_rd_ready = (state == STATE_RECEIVE);
    assign dma_done_ready = (state == STATE_RECEIVE);
    assign run_configuration_valid = (state == STATE_RUN_CONFIGURATION);
    assign run_configuration_data = beat_buffer;
    assign error_valid = (state == STATE_ERROR);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            address_register <= {ADDRESS_W{1'b0}};
            beat_count <= 3'd0;
            observed_read_error <= 1'b0;
            abort_pending <= 1'b0;
            observed_read_response <= 2'b00;
            observed_error_beat <= 3'd0;
            error_code <= 8'd0;
            cfg_error_word <= 5'd0;
            error_detail <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    abort_pending <= 1'b0;
                    if (start_valid) begin
                        address_register <= start_address;
                        beat_count <= 3'd0;
                        observed_read_error <= 1'b0;
                        observed_read_response <= 2'b00;
                        observed_error_beat <= 3'd0;
                        state <= STATE_REQUEST;
                    end
                end
                STATE_REQUEST: begin
                    if (abort_request)
                        state <= STATE_IDLE;
                    else if (dma_req_ready)
                        state <= STATE_RECEIVE;
                end
                STATE_RECEIVE: begin
                    if (abort_request)
                        abort_pending <= 1'b1;
                    if (dma_rd_valid) begin
                        case (beat_count)
                            3'd0: beat_buffer[(0*`RECON_DMA_DATA_W) +:
                                `RECON_DMA_DATA_W] <= dma_rd_data;
                            3'd1: beat_buffer[(1*`RECON_DMA_DATA_W) +:
                                `RECON_DMA_DATA_W] <= dma_rd_data;
                            3'd2: beat_buffer[(2*`RECON_DMA_DATA_W) +:
                                `RECON_DMA_DATA_W] <= dma_rd_data;
                            3'd3: beat_buffer[(3*`RECON_DMA_DATA_W) +:
                                `RECON_DMA_DATA_W] <= dma_rd_data;
                            default: begin end
                        endcase
                        if (beat_count < 3'd7)
                            beat_count <= beat_count + 3'd1;
                        if (!observed_read_error &&
                            ((dma_rd_resp != 2'b00) ||
                             (dma_rd_last !=
                              (beat_count == (CONFIGURATION_BEATS - 3'd1))) ||
                             (dma_rd_tag != CONFIGURATION_TAG))) begin
                            observed_read_error <= 1'b1;
                            observed_read_response <=
                                (dma_rd_resp != 2'b00) ?
                                dma_rd_resp : 2'b10;
                            observed_error_beat <= beat_count;
                        end
                    end
                    if (dma_done_valid) begin
                        abort_pending <= 1'b0;
                        if (abort_pending || abort_request) begin
                            state <= STATE_IDLE;
                        end else if (dma_done_error || observed_read_error ||
                            (dma_done_tag != CONFIGURATION_TAG)) begin
                            error_code <= 8'h01;
                            cfg_error_word <= dma_done_error ?
                                {dma_completion_beat[2:0], 2'b00} :
                                {observed_error_beat, 2'b00};
                            error_detail <= {
                                13'd0,
                                dma_done_error ? dma_completion_beat :
                                    {6'd0, observed_error_beat},
                                6'd0,
                                dma_done_error ? dma_done_resp :
                                    observed_read_response,
                                2'd0
                            };
                            state <= STATE_ERROR;
                        end else if (beat_count != CONFIGURATION_BEATS) begin
                            error_code <= 8'h02;
                            cfg_error_word <= 5'd0;
                            error_detail <= {29'd0, beat_count};
                            state <= STATE_ERROR;
                        end else begin
                            state <= STATE_RUN_CONFIGURATION;
                        end
                    end
                end
                STATE_RUN_CONFIGURATION: begin
                    if (abort_request || run_configuration_ready)
                        state <= STATE_IDLE;
                end
                STATE_ERROR: begin
                    if (error_ready)
                        state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_run_cfg_valid;
    reg f_run_cfg_ready;
    reg [`RECON_RUN_CONFIGURATION_BITS-1:0] f_run_cfg_data;
    reg f_error_valid;
    reg f_error_ready;
    reg [7:0] f_error_code;
    reg [4:0] f_error_word;
    reg [31:0] f_error_detail;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_run_cfg_valid <= run_configuration_valid;
        f_run_cfg_ready <= run_configuration_ready;
        f_run_cfg_data <= run_configuration_data;
        f_error_valid <= error_valid;
        f_error_ready <= error_ready;
        f_error_code <= error_code;
        f_error_word <= cfg_error_word;
        f_error_detail <= error_detail;
        if (rst_n) begin
            assert(!(run_configuration_valid && error_valid));
            assert(!dma_req_valid || !dma_req_write);
            assert(!dma_rd_ready || (state == STATE_RECEIVE));
            if (abort_pending)
                assert(state == STATE_RECEIVE);
            if (run_configuration_valid)
                assert(beat_count == CONFIGURATION_BEATS);
            if (f_past_valid && f_run_cfg_valid && !f_run_cfg_ready) begin
                assert(run_configuration_valid);
                assert(run_configuration_data == f_run_cfg_data);
            end
            if (f_past_valid && f_error_valid && !f_error_ready) begin
                assert(error_valid);
                assert(error_code == f_error_code);
                assert(cfg_error_word == f_error_word);
                assert(error_detail == f_error_detail);
            end
        end
    end
`endif
endmodule

`default_nettype wire
