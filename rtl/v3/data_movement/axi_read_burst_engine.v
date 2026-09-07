`timescale 1ns/1ps
`default_nettype none

// One-outstanding AXI4 INCR read engine. Requests are 16-byte aligned and are
// limited to one legal AXI burst (1..256 beats). The completion token is held
// until accepted and reports the first data/protocol error.
module axi_read_burst_engine #(
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

    output wire                   read_valid,
    input  wire                   read_ready,
    output wire [DATA_W-1:0]      read_data,
    output wire                   read_last,
    output wire [1:0]             read_response,
    output wire [TAG_W-1:0]       read_tag,

    output reg                    completion_valid,
    input  wire                   completion_ready,
    output reg  [TAG_W-1:0]       completion_tag,
    output reg                    completion_error,
    output reg  [1:0]             completion_response,
    output reg  [8:0]             completion_beat,

    output wire [ADDRESS_W-1:0]   m_axi_araddr,
    output wire [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    output wire                   m_axi_arvalid,
    input  wire                   m_axi_arready,
    input  wire [DATA_W-1:0]      m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_ADDRESS = 3'd1;
    localparam [2:0] STATE_DATA = 3'd2;
    localparam [2:0] STATE_COMPLETION = 3'd3;
    localparam [1:0] RESPONSE_OKAY = 2'b00;
    localparam [1:0] RESPONSE_SLVERR = 2'b10;

    reg [2:0] state;
    reg [ADDRESS_W-1:0] address_register;
    reg [8:0] expected_beats;
    reg [8:0] beat_index;
    reg [TAG_W-1:0] active_tag;
    reg first_error;
    reg [1:0] first_error_response;
    reg [8:0] first_error_beat;

    wire request_legal = (request_bytes != 16'd0) &&
        (request_bytes[3:0] == 4'd0) &&
        (request_bytes <= 16'd4096) &&
        (request_address[3:0] == 4'd0);
    wire expected_last_now = (beat_index == (expected_beats - 9'd1));
    wire current_protocol_error = (m_axi_rlast != expected_last_now);
    wire current_read_error = (m_axi_rresp != RESPONSE_OKAY) ||
        current_protocol_error;

    assign request_ready = (state == STATE_IDLE);
    assign m_axi_araddr = address_register;
    assign m_axi_arlen = expected_beats[7:0] - 8'd1;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == STATE_ADDRESS);
    assign read_valid = (state == STATE_DATA) && m_axi_rvalid;
    assign read_data = m_axi_rdata;
    assign read_last = m_axi_rlast;
    assign read_response = m_axi_rresp;
    assign read_tag = active_tag;
    assign m_axi_rready = (state == STATE_DATA) && read_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            address_register <= {ADDRESS_W{1'b0}};
            expected_beats <= 9'd0;
            beat_index <= 9'd0;
            active_tag <= {TAG_W{1'b0}};
            first_error <= 1'b0;
            first_error_response <= RESPONSE_OKAY;
            first_error_beat <= 9'd0;
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
                        first_error <= 1'b0;
                        first_error_response <= RESPONSE_OKAY;
                        first_error_beat <= 9'd0;
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
                    if (m_axi_arready)
                        state <= STATE_DATA;
                end
                STATE_DATA: begin
                    if (m_axi_rvalid && read_ready) begin
                        if (!first_error && current_read_error) begin
                            first_error <= 1'b1;
                            first_error_response <=
                                (m_axi_rresp != RESPONSE_OKAY) ?
                                m_axi_rresp : RESPONSE_SLVERR;
                            first_error_beat <= beat_index;
                        end
                        if (m_axi_rlast || expected_last_now) begin
                            completion_valid <= 1'b1;
                            completion_tag <= active_tag;
                            completion_error <= first_error || current_read_error;
                            if (first_error) begin
                                completion_response <= first_error_response;
                                completion_beat <= first_error_beat;
                            end else if (current_read_error) begin
                                completion_response <=
                                    (m_axi_rresp != RESPONSE_OKAY) ?
                                    m_axi_rresp : RESPONSE_SLVERR;
                                completion_beat <= beat_index;
                            end else begin
                                completion_response <= RESPONSE_OKAY;
                                completion_beat <= beat_index;
                            end
                            state <= STATE_COMPLETION;
                        end else begin
                            beat_index <= beat_index + 9'd1;
                        end
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
    reg f_arvalid;
    reg f_arready;
    reg [ADDRESS_W-1:0] f_araddr;
    reg [7:0] f_arlen;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_completion_valid <= completion_valid;
        f_completion_ready <= completion_ready;
        f_completion_tag <= completion_tag;
        f_completion_error <= completion_error;
        f_completion_response <= completion_response;
        f_completion_beat <= completion_beat;
        f_arvalid <= m_axi_arvalid;
        f_arready <= m_axi_arready;
        f_araddr <= m_axi_araddr;
        f_arlen <= m_axi_arlen;
        if (rst_n) begin
            assert(!(request_ready && completion_valid));
            assert(!m_axi_rready || (state == STATE_DATA));
            if (m_axi_arvalid) begin
                assert(m_axi_araddr[3:0] == 4'd0);
                assert(m_axi_arsize == 3'd4);
                assert(m_axi_arburst == 2'b01);
            end
            if (f_past_valid && f_completion_valid && !f_completion_ready) begin
                assert(completion_valid);
                assert(completion_tag == f_completion_tag);
                assert(completion_error == f_completion_error);
                assert(completion_response == f_completion_response);
                assert(completion_beat == f_completion_beat);
            end
            if (f_past_valid && f_arvalid && !f_arready) begin
                assert(m_axi_arvalid);
                assert(m_axi_araddr == f_araddr);
                assert(m_axi_arlen == f_arlen);
            end
        end
    end
`endif
endmodule

`default_nettype wire
