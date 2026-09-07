`timescale 1ns/1ps
`default_nettype none

// Synthesis-only harness for the stateful M4 path. The scratchpad remains a
// separate RTL owner; this wrapper only closes its two ports around the stream
// engine so Vivado reports the real control-to-BRAM timing and RAM mapping.
module m4_vector_transport_ooc (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         routine_start,
    input  wire         req_valid,
    input  wire         cycle_commit,
    input  wire         vec_a_en,
    input  wire         vec_b_en,
    input  wire         vec_w_en,
    input  wire [5:0]   vec_cfg_a,
    input  wire [5:0]   vec_cfg_b,
    input  wire [5:0]   vec_cfg_w,
    input  wire         cfg_a_valid,
    input  wire [63:0]  cfg_a,
    input  wire         cfg_b_valid,
    input  wire [63:0]  cfg_b,
    input  wire         cfg_w_valid,
    input  wire [63:0]  cfg_w,
    input  wire [575:0] vec_w_data,
    output wire         stream_in_ready,
    output wire         stream_out_ready,
    output wire         cfg_error,
    output wire         access_conflict,
    output wire         vec_a_valid,
    output wire [575:0] vec_a_data,
    output wire         vec_b_valid,
    output wire [575:0] vec_b_data
);
    wire p0_valid, p0_ready, p0_write;
    wire [7:0] p0_mask;
    wire [71:0] p0_addresses;
    wire [575:0] p0_write_data;
    wire p0_read_valid;
    wire [7:0] p0_read_mask;
    wire [575:0] p0_read_data;
    wire p1_valid, p1_ready, p1_write;
    wire [7:0] p1_mask;
    wire [71:0] p1_addresses;
    wire [575:0] p1_write_data;
    wire p1_read_valid;
    wire [7:0] p1_read_mask;
    wire [575:0] p1_read_data;
    wire physical_conflict;

    vector_stream_engine u_vector_stream_engine (
        .clk(clk), .rst_n(rst_n), .cursor_restart_valid(1'b0), .cursor_restart_mask(3'b000),
        .cursor_restart_ready(), .routine_start(routine_start),
        .req_valid(req_valid),
        .cycle_commit(cycle_commit),
        .vec_a_en(vec_a_en),
        .vec_b_en(vec_b_en),
        .vec_w_en(vec_w_en),
        .vec_a_restart(1'b0), .vec_b_restart(1'b0),
        .vec_cfg_a(vec_cfg_a),
        .vec_cfg_b(vec_cfg_b),
        .vec_cfg_w(vec_cfg_w),
        .cfg_a_valid(cfg_a_valid),
        .cfg_a(cfg_a),
        .cfg_b_valid(cfg_b_valid),
        .cfg_b(cfg_b),
        .cfg_w_valid(cfg_w_valid),
        .cfg_w(cfg_w),
        .vec_w_data(vec_w_data),
        .stream_in_ready(stream_in_ready),
        .stream_out_ready(stream_out_ready),
        .cfg_error(cfg_error),
        .access_conflict(access_conflict),
        .vec_a_valid(vec_a_valid),
        .vec_a_data(vec_a_data),
        .vec_b_valid(vec_b_valid),
        .vec_b_data(vec_b_data),
        .sp0_valid(p0_valid),
        .sp0_ready(p0_ready),
        .sp0_write(p0_write),
        .sp0_bank_mask(p0_mask),
        .sp0_addr(p0_addresses),
        .sp0_wr_data(p0_write_data),
        .sp0_rd_valid(p0_read_valid),
        .sp0_rd_bank_mask(p0_read_mask),
        .sp0_rd_data(p0_read_data),
        .sp1_valid(p1_valid),
        .sp1_ready(p1_ready),
        .sp1_write(p1_write),
        .sp1_bank_mask(p1_mask),
        .sp1_addr(p1_addresses),
        .sp1_wr_data(p1_write_data),
        .sp1_rd_valid(p1_read_valid),
        .sp1_rd_bank_mask(p1_read_mask),
        .sp1_rd_data(p1_read_data),
        .sp_conflict(physical_conflict)
    );

    vector_scratchpad u_vector_scratchpad (
        .clk(clk), .rst_n(rst_n),
        .p0_valid(p0_valid), .p0_ready(p0_ready),
        .p0_write(p0_write), .p0_bank_mask(p0_mask),
        .p0_addr(p0_addresses), .p0_wr_data(p0_write_data),
        .p0_rd_valid(p0_read_valid), .p0_rd_bank_mask(p0_read_mask),
        .p0_rd_data(p0_read_data),
        .p1_valid(p1_valid), .p1_ready(p1_ready),
        .p1_write(p1_write), .p1_bank_mask(p1_mask),
        .p1_addr(p1_addresses), .p1_wr_data(p1_write_data),
        .p1_rd_valid(p1_read_valid), .p1_rd_bank_mask(p1_read_mask),
        .p1_rd_data(p1_read_data), .external_conflict(1'b0),
        .access_conflict(physical_conflict)
    );
endmodule

`default_nettype wire
