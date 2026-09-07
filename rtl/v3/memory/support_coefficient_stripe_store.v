`timescale 1ns/1ps
`default_nettype none

module support_coefficient_stripe_store #(
    parameter integer DATA_W = 27,
    parameter integer LANES = 16,
    parameter integer WORK_MAX = 96
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      write_enable,
    input  wire                      write_bank,
    input  wire [6:0]                write_slot,
    input  wire [DATA_W-1:0]         write_coefficient,
    input  wire                      scalar_read_enable,
    input  wire                      scalar_read_bank,
    input  wire [6:0]                scalar_read_slot,
    output wire                      scalar_read_valid,
    output reg  [DATA_W-1:0]         scalar_read_coefficient,
    input  wire                      stripe_read_enable,
    input  wire                      stripe_read_bank,
    input  wire [2:0]                stripe_read_index,
    output wire                      stripe_read_valid,
    output wire [LANES*DATA_W-1:0]   stripe_read_coefficients
);
    localparam integer ROW_COUNT = (WORK_MAX + LANES - 1) / LANES;
    localparam integer STORE_DEPTH = 2 * ROW_COUNT;
    localparam integer STORE_ADDR_W = 4;

    wire write_accept = write_enable && (write_slot < WORK_MAX);
    wire [3:0] write_lane = write_slot[3:0];
    wire [2:0] write_row = write_slot[6:4];
    wire scalar_read_accept = scalar_read_enable &&
        (scalar_read_slot < WORK_MAX);
    wire [2:0] scalar_read_row = scalar_read_slot[6:4];
    wire stripe_read_accept = stripe_read_enable &&
        (stripe_read_index < ROW_COUNT);
    wire [STORE_ADDR_W-1:0] write_address = {write_bank, write_row};
    wire [STORE_ADDR_W-1:0] scalar_read_address =
        {scalar_read_bank, scalar_read_row};
    wire [STORE_ADDR_W-1:0] stripe_read_address =
        {stripe_read_bank, stripe_read_index};
    wire read_accept = scalar_read_accept || stripe_read_accept;
    wire [STORE_ADDR_W-1:0] read_address = scalar_read_accept ?
        scalar_read_address : stripe_read_address;

    reg [3:0] scalar_read_lane_q;
    reg read_is_scalar_q;
    wire [LANES-1:0] lane_read_valid;
    wire [LANES*DATA_W-1:0] lane_read_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            scalar_read_lane_q <= 4'd0;
            read_is_scalar_q <= 1'b0;
        end else if (read_accept) begin
            read_is_scalar_q <= scalar_read_accept;
            if (scalar_read_accept)
                scalar_read_lane_q <= scalar_read_slot[3:0];
        end
    end

    integer scalar_lane_index;
    always @* begin
        scalar_read_coefficient = {DATA_W{1'b0}};
        for (scalar_lane_index = 0; scalar_lane_index < LANES;
             scalar_lane_index = scalar_lane_index + 1)
            if (scalar_read_lane_q == scalar_lane_index)
                scalar_read_coefficient = lane_read_data[
                    scalar_lane_index*DATA_W +: DATA_W];
    end

    assign scalar_read_valid = lane_read_valid[0] && read_is_scalar_q;
    assign stripe_read_valid = lane_read_valid[0] && !read_is_scalar_q;
    assign stripe_read_coefficients = lane_read_data;

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
            recon_sdp_ram #(
                .DATA_W(DATA_W), .DEPTH(STORE_DEPTH),
                .ADDR_W(STORE_ADDR_W), .INITIALIZE_TO_ZERO(1)
            ) u_lane_store (
                .clk(clk), .rst_n(rst_n),
                .write_enable(write_accept && (write_lane == lane)),
                .write_address(write_address),
                .write_data(write_coefficient),
                .read_enable(read_accept),
                .read_address(read_address),
                .read_valid(lane_read_valid[lane]),
                .read_data(lane_read_data[lane*DATA_W +: DATA_W])
            );
        end
    endgenerate

`ifdef FORMAL
    always @(posedge clk)
        if (rst_n)
            assert(!(scalar_read_accept && stripe_read_accept));
`endif
endmodule

`default_nettype wire
