`timescale 1ns/1ps
`default_nettype none

// Fixed-priority, transaction-locking arbiter for four DMA clients.
// Priority is client 0 (run configuration), 1 (terminal drain), 2 (preload),
// then 3 (optional trace). Ownership is released only when the selected client
// accepts the completion token.
module dma_request_arbiter #(
    parameter integer ADDRESS_W = 64,
    parameter integer DATA_W = 128,
    parameter integer TAG_W = 8
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire [3:0]                 client_req_valid,
    output reg  [3:0]                 client_req_ready,
    input  wire [3:0]                 client_req_write,
    input  wire [(4*ADDRESS_W)-1:0]   client_req_addr,
    input  wire [(4*16)-1:0]          client_req_bytes,
    input  wire [(4*TAG_W)-1:0]       client_req_tag,
    input  wire [3:0]                 client_wr_valid,
    output reg  [3:0]                 client_wr_ready,
    input  wire [(4*DATA_W)-1:0]      client_wr_data,
    input  wire [(4*(DATA_W/8))-1:0]  client_wr_keep,
    input  wire [3:0]                 client_wr_last,
    output reg  [3:0]                 client_rd_valid,
    input  wire [3:0]                 client_rd_ready,
    output wire [(4*DATA_W)-1:0]      client_rd_data,
    output wire [3:0]                 client_rd_last,
    output wire [(4*2)-1:0]           client_rd_resp,
    output wire [(4*TAG_W)-1:0]       client_rd_tag,
    output reg  [3:0]                 client_done_valid,
    input  wire [3:0]                 client_done_ready,
    output wire [(4*TAG_W)-1:0]       client_done_tag,
    output wire [3:0]                 client_done_error,
    output wire [(4*2)-1:0]           client_done_resp,
    output wire [(4*9)-1:0]           client_done_beat,

    output reg                        engine_req_valid,
    input  wire                       engine_req_ready,
    output reg                        engine_req_write,
    output reg  [ADDRESS_W-1:0]       engine_req_addr,
    output reg  [15:0]                engine_req_bytes,
    output reg  [TAG_W-1:0]           engine_req_tag,
    output reg                        engine_wr_valid,
    input  wire                       engine_wr_ready,
    output reg  [DATA_W-1:0]          engine_wr_data,
    output reg  [(DATA_W/8)-1:0]      engine_wr_keep,
    output reg                        engine_wr_last,
    input  wire                       engine_rd_valid,
    output reg                        engine_rd_ready,
    input  wire [DATA_W-1:0]          engine_rd_data,
    input  wire                       engine_rd_last,
    input  wire [1:0]                 engine_rd_resp,
    input  wire [TAG_W-1:0]           engine_rd_tag,
    input  wire                       engine_done_valid,
    output reg                        engine_done_ready,
    input  wire [TAG_W-1:0]           engine_done_tag,
    input  wire                       engine_done_error,
    input  wire [1:0]                 engine_done_resp,
    input  wire [8:0]                 engine_done_beat,
    output wire                       dma_active
);
    reg owner_active;
    reg [1:0] owner;
    reg [1:0] grant;
    reg grant_valid;

    assign client_rd_data = {4{engine_rd_data}};
    assign client_rd_last = {4{engine_rd_last}};
    assign client_rd_resp = {4{engine_rd_resp}};
    assign client_rd_tag = {4{engine_rd_tag}};
    assign client_done_tag = {4{engine_done_tag}};
    assign client_done_error = {4{engine_done_error}};
    assign client_done_resp = {4{engine_done_resp}};
    assign client_done_beat = {4{engine_done_beat}};
    assign dma_active = owner_active;

    always @* begin
        grant = 2'd0;
        grant_valid = 1'b0;
        if (client_req_valid[0]) begin grant = 2'd0; grant_valid = 1'b1; end
        else if (client_req_valid[1]) begin grant = 2'd1; grant_valid = 1'b1; end
        else if (client_req_valid[2]) begin grant = 2'd2; grant_valid = 1'b1; end
        else if (client_req_valid[3]) begin grant = 2'd3; grant_valid = 1'b1; end
    end

    always @* begin
        client_req_ready = 4'b0000;
        client_wr_ready = 4'b0000;
        client_rd_valid = 4'b0000;
        client_done_valid = 4'b0000;
        engine_req_valid = 1'b0;
        engine_req_write = 1'b0;
        engine_req_addr = {ADDRESS_W{1'b0}};
        engine_req_bytes = 16'd0;
        engine_req_tag = {TAG_W{1'b0}};
        engine_wr_valid = 1'b0;
        engine_wr_data = {DATA_W{1'b0}};
        engine_wr_keep = {(DATA_W/8){1'b0}};
        engine_wr_last = 1'b0;
        engine_rd_ready = 1'b0;
        engine_done_ready = 1'b0;

        if (!owner_active && grant_valid) begin
            engine_req_valid = 1'b1;
            case (grant)
                2'd0: begin
                    engine_req_write = client_req_write[0];
                    engine_req_addr = client_req_addr[0*ADDRESS_W +: ADDRESS_W];
                    engine_req_bytes = client_req_bytes[0*16 +: 16];
                    engine_req_tag = client_req_tag[0*TAG_W +: TAG_W];
                    client_req_ready[0] = engine_req_ready;
                end
                2'd1: begin
                    engine_req_write = client_req_write[1];
                    engine_req_addr = client_req_addr[1*ADDRESS_W +: ADDRESS_W];
                    engine_req_bytes = client_req_bytes[1*16 +: 16];
                    engine_req_tag = client_req_tag[1*TAG_W +: TAG_W];
                    client_req_ready[1] = engine_req_ready;
                end
                2'd2: begin
                    engine_req_write = client_req_write[2];
                    engine_req_addr = client_req_addr[2*ADDRESS_W +: ADDRESS_W];
                    engine_req_bytes = client_req_bytes[2*16 +: 16];
                    engine_req_tag = client_req_tag[2*TAG_W +: TAG_W];
                    client_req_ready[2] = engine_req_ready;
                end
                default: begin
                    engine_req_write = client_req_write[3];
                    engine_req_addr = client_req_addr[3*ADDRESS_W +: ADDRESS_W];
                    engine_req_bytes = client_req_bytes[3*16 +: 16];
                    engine_req_tag = client_req_tag[3*TAG_W +: TAG_W];
                    client_req_ready[3] = engine_req_ready;
                end
            endcase
        end

        if (owner_active) begin
            case (owner)
                2'd0: begin
                    engine_wr_valid = client_wr_valid[0];
                    engine_wr_data = client_wr_data[0*DATA_W +: DATA_W];
                    engine_wr_keep = client_wr_keep[0*(DATA_W/8) +: (DATA_W/8)];
                    engine_wr_last = client_wr_last[0];
                    client_wr_ready[0] = engine_wr_ready;
                    client_rd_valid[0] = engine_rd_valid;
                    engine_rd_ready = client_rd_ready[0];
                    client_done_valid[0] = engine_done_valid;
                    engine_done_ready = client_done_ready[0];
                end
                2'd1: begin
                    engine_wr_valid = client_wr_valid[1];
                    engine_wr_data = client_wr_data[1*DATA_W +: DATA_W];
                    engine_wr_keep = client_wr_keep[1*(DATA_W/8) +: (DATA_W/8)];
                    engine_wr_last = client_wr_last[1];
                    client_wr_ready[1] = engine_wr_ready;
                    client_rd_valid[1] = engine_rd_valid;
                    engine_rd_ready = client_rd_ready[1];
                    client_done_valid[1] = engine_done_valid;
                    engine_done_ready = client_done_ready[1];
                end
                2'd2: begin
                    engine_wr_valid = client_wr_valid[2];
                    engine_wr_data = client_wr_data[2*DATA_W +: DATA_W];
                    engine_wr_keep = client_wr_keep[2*(DATA_W/8) +: (DATA_W/8)];
                    engine_wr_last = client_wr_last[2];
                    client_wr_ready[2] = engine_wr_ready;
                    client_rd_valid[2] = engine_rd_valid;
                    engine_rd_ready = client_rd_ready[2];
                    client_done_valid[2] = engine_done_valid;
                    engine_done_ready = client_done_ready[2];
                end
                default: begin
                    engine_wr_valid = client_wr_valid[3];
                    engine_wr_data = client_wr_data[3*DATA_W +: DATA_W];
                    engine_wr_keep = client_wr_keep[3*(DATA_W/8) +: (DATA_W/8)];
                    engine_wr_last = client_wr_last[3];
                    client_wr_ready[3] = engine_wr_ready;
                    client_rd_valid[3] = engine_rd_valid;
                    engine_rd_ready = client_rd_ready[3];
                    client_done_valid[3] = engine_done_valid;
                    engine_done_ready = client_done_ready[3];
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            owner_active <= 1'b0;
            owner <= 2'd0;
        end else begin
            if (!owner_active && engine_req_valid && engine_req_ready) begin
                owner_active <= 1'b1;
                owner <= grant;
            end else if (owner_active && engine_done_valid &&
                         engine_done_ready) begin
                owner_active <= 1'b0;
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert((client_req_ready == 4'b0000) ||
                   (client_req_ready == 4'b0001) ||
                   (client_req_ready == 4'b0010) ||
                   (client_req_ready == 4'b0100) ||
                   (client_req_ready == 4'b1000));
            assert((client_rd_valid == 4'b0000) ||
                   (client_rd_valid == 4'b0001) ||
                   (client_rd_valid == 4'b0010) ||
                   (client_rd_valid == 4'b0100) ||
                   (client_rd_valid == 4'b1000));
            assert((client_done_valid == 4'b0000) ||
                   (client_done_valid == 4'b0001) ||
                   (client_done_valid == 4'b0010) ||
                   (client_done_valid == 4'b0100) ||
                   (client_done_valid == 4'b1000));
            if (owner_active) begin
                assert(!engine_req_valid);
                assert(client_rd_valid[owner] == engine_rd_valid);
                assert(client_done_valid[owner] == engine_done_valid);
            end
        end
    end
`endif
endmodule

`default_nettype wire
