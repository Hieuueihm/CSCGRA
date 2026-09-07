`timescale 1ns/1ps
`default_nettype none

// One-outstanding AXI4 INCR write engine. The engine owns WLAST generation and
// reports a mismatch if the client-provided write_last marker is inconsistent.
module axi_write_burst_engine #(
    parameter integer ADDRESS_W = 64,
    parameter integer DATA_W = 128,
    parameter integer TAG_W = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   request_valid,
    output wire                   request_ready,
    input  wire [ADDRESS_W-1:0]   request_address,
    input  wire [15:0]            request_bytes,
    input  wire [TAG_W-1:0]       request_tag,
    input  wire                   write_valid,
    output wire                   write_ready,
    input  wire [DATA_W-1:0]      write_data,
    input  wire [(DATA_W/8)-1:0]  write_keep,
    input  wire                   write_last,
    output reg                    completion_valid,
    input  wire                   completion_ready,
    output reg  [TAG_W-1:0]       completion_tag,
    output reg                    completion_error,
    output reg  [1:0]             completion_response,
    output reg  [8:0]             completion_beat,
    output wire [ADDRESS_W-1:0]   m_axi_awaddr,
    output wire [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,
    output wire                   m_axi_awvalid,
    input  wire                   m_axi_awready,
    output wire [DATA_W-1:0]      m_axi_wdata,
    output wire [(DATA_W/8)-1:0]  m_axi_wstrb,
    output wire                   m_axi_wlast,
    output wire                   m_axi_wvalid,
    input  wire                   m_axi_wready,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_ADDRESS = 3'd1;
    localparam [2:0] STATE_DATA = 3'd2;
    localparam [2:0] STATE_RESPONSE = 3'd3;
    localparam [2:0] STATE_COMPLETION = 3'd4;
    localparam [1:0] RESPONSE_OKAY = 2'b00;
    localparam [1:0] RESPONSE_SLVERR = 2'b10;

    reg [2:0] state;
    reg [ADDRESS_W-1:0] address_register;
    reg [8:0] expected_beats;
    reg [8:0] beat_index;
    reg [TAG_W-1:0] active_tag;
    reg stream_protocol_error;
    reg [8:0] stream_error_beat;

    wire request_legal = (request_bytes != 16'd0) &&
        (request_bytes[3:0] == 4'd0) &&
        (request_bytes <= 16'd4096) &&
        (request_address[3:0] == 4'd0);
    wire expected_last_now = (beat_index == (expected_beats - 9'd1));

    assign request_ready = (state == STATE_IDLE);
    assign m_axi_awaddr = address_register;
    assign m_axi_awlen = expected_beats[7:0] - 8'd1;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = (state == STATE_ADDRESS);
    assign write_ready = (state == STATE_DATA) && m_axi_wready;
    assign m_axi_wdata = write_data;
    assign m_axi_wstrb = write_keep;
    assign m_axi_wlast = expected_last_now;
    assign m_axi_wvalid = (state == STATE_DATA) && write_valid;
    assign m_axi_bready = (state == STATE_RESPONSE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            address_register <= {ADDRESS_W{1'b0}};
            expected_beats <= 9'd0;
            beat_index <= 9'd0;
            active_tag <= {TAG_W{1'b0}};
            stream_protocol_error <= 1'b0;
            stream_error_beat <= 9'd0;
            completion_valid <= 1'b0;
            completion_tag <= {TAG_W{1'b0}};
            completion_error <= 1'b0;
            completion_response <= RESPONSE_OKAY;
            completion_beat <= 9'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    completion_valid <= 1'b0;
                    if (request_valid) begin
                        active_tag <= request_tag;
                        completion_tag <= request_tag;
                        beat_index <= 9'd0;
                        stream_protocol_error <= 1'b0;
                        stream_error_beat <= 9'd0;
                        if (request_legal) begin
                            address_register <= request_address;
                            expected_beats <= request_bytes[12:4];
                            state <= STATE_ADDRESS;
                        end else begin
                            completion_valid <= 1'b1;
                            completion_error <= 1'b1;
                            completion_response <= RESPONSE_SLVERR;
                            completion_beat <= 9'd0;
                            state <= STATE_COMPLETION;
                        end
                    end
                end
                STATE_ADDRESS: begin
                    if (m_axi_awready)
                        state <= STATE_DATA;
                end
                STATE_DATA: begin
                    if (write_valid && m_axi_wready) begin
                        if (!stream_protocol_error &&
                            (write_last != expected_last_now)) begin
                            stream_protocol_error <= 1'b1;
                            stream_error_beat <= beat_index;
                        end
                        if (expected_last_now)
                            state <= STATE_RESPONSE;
                        else
                            beat_index <= beat_index + 9'd1;
                    end
                end
                STATE_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        completion_valid <= 1'b1;
                        completion_tag <= active_tag;
                        completion_error <= stream_protocol_error ||
                            (m_axi_bresp != RESPONSE_OKAY);
                        completion_response <= stream_protocol_error ?
                            RESPONSE_SLVERR : m_axi_bresp;
                        completion_beat <= stream_protocol_error ?
                            stream_error_beat : beat_index;
                        state <= STATE_COMPLETION;
                    end
                end
                STATE_COMPLETION: begin
                    if (completion_valid && completion_ready) begin
                        completion_valid <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_completion_valid;
    reg f_completion_ready;
    reg [TAG_W-1:0] f_completion_tag;
    reg f_completion_error;
    reg [1:0] f_completion_response;
    reg [8:0] f_completion_beat;
    reg f_awvalid;
    reg f_awready;
    reg [ADDRESS_W-1:0] f_awaddr;
    reg [7:0] f_awlen;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_completion_valid <= completion_valid;
        f_completion_ready <= completion_ready;
        f_completion_tag <= completion_tag;
        f_completion_error <= completion_error;
        f_completion_response <= completion_response;
        f_completion_beat <= completion_beat;
        f_awvalid <= m_axi_awvalid;
        f_awready <= m_axi_awready;
        f_awaddr <= m_axi_awaddr;
        f_awlen <= m_axi_awlen;
        if (rst_n) begin
            assert(!(request_ready && completion_valid));
            assert(!m_axi_bready || (state == STATE_RESPONSE));
            if (m_axi_awvalid) begin
                assert(m_axi_awaddr[3:0] == 4'd0);
                assert(m_axi_awsize == 3'd4);
                assert(m_axi_awburst == 2'b01);
            end
            if (m_axi_wvalid)
                assert(m_axi_wlast == expected_last_now);
            if (f_past_valid && f_completion_valid && !f_completion_ready) begin
                assert(completion_valid);
                assert(completion_tag == f_completion_tag);
                assert(completion_error == f_completion_error);
                assert(completion_response == f_completion_response);
                assert(completion_beat == f_completion_beat);
            end
            if (f_past_valid && f_awvalid && !f_awready) begin
                assert(m_axi_awvalid);
                assert(m_axi_awaddr == f_awaddr);
                assert(m_axi_awlen == f_awlen);
            end
        end
    end
`endif
endmodule

`default_nettype wire
