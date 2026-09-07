`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "architecture_guard_defs.vh"
`include "context_isa_defs.vh"

// Four-read-port resident memory-configuration table.  Two true-dual-port block
// RAM copies provide four synchronous reads per cycle.  Programming is legal
// only while execution is idle, so each copy can reuse one read port as its
// write port without an arbiter or a third RAM copy.
module memory_configuration_store (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         execution_active,
    input  wire         active_image_bank,

    input  wire         cfg_wr_valid,
    output wire         cfg_wr_ready,
    input  wire         cfg_wr_bank,
    input  wire [5:0]   cfg_wr_id,
    input  wire [63:0]  cfg_wr_data,
    output reg          cfg_wr_resp_valid,
    input  wire         cfg_wr_resp_ready,
    output reg          cfg_wr_resp_error,
    output reg  [7:0]   cfg_wr_resp_code,
    output reg  [31:0]  cfg_wr_resp_detail,

    input  wire [5:0]   cfg_a_id,
    output wire         cfg_a_valid,
    output reg  [63:0]  cfg_a_data,
    input  wire [5:0]   cfg_b_id,
    output wire         cfg_b_valid,
    output reg  [63:0]  cfg_b_data,
    input  wire [5:0]   cfg_stream_id,
    output wire         cfg_stream_valid,
    output reg  [63:0]  cfg_stream_data,
    input  wire [5:0]   phi_cfg_id,
    output wire         phi_cfg_valid,
    output reg  [63:0]  phi_cfg_data
);
    (* ram_style = "block" *) reg [63:0] cfg_read_copy [0:127];
    (* ram_style = "block" *) reg [63:0] cfg_stream_copy [0:127];

    reg [63:0] cfg_valid_bitmap [0:1];
    reg [63:0] cfg_a_read_data;
    reg [63:0] cfg_b_read_data;
    reg [63:0] cfg_stream_read_data;
    reg [63:0] phi_cfg_read_data;
    reg cfg_a_read_valid;
    reg cfg_b_read_valid;
    reg cfg_stream_read_valid;
    reg phi_cfg_read_valid;
    reg cfg_a_response_valid;
    reg cfg_b_response_valid;
    reg cfg_stream_response_valid;
    reg phi_cfg_response_valid;
    reg cfg_a_read_bank;
    reg cfg_b_read_bank;
    reg cfg_stream_read_bank;
    reg phi_cfg_read_bank;
    reg cfg_a_response_bank;
    reg cfg_b_response_bank;
    reg cfg_stream_response_bank;
    reg phi_cfg_response_bank;
    reg [5:0] cfg_a_read_id;
    reg [5:0] cfg_b_read_id;
    reg [5:0] cfg_stream_read_id;
    reg [5:0] phi_cfg_read_id;
    reg [5:0] cfg_a_response_id;
    reg [5:0] cfg_b_response_id;
    reg [5:0] cfg_stream_response_id;
    reg [5:0] phi_cfg_response_id;
`ifdef FORMAL
    reg prev_active_bank;
`endif
    wire [6:0] wr_idx = {cfg_wr_bank, cfg_wr_id};
    wire [6:0] rd_a_idx = {active_image_bank, cfg_a_id};
    wire [6:0] rd_b_idx = {active_image_bank, cfg_b_id};
    wire [6:0] stream_idx = {active_image_bank,
                                     cfg_stream_id};
    wire [6:0] phi_idx = {active_image_bank, phi_cfg_id};

    assign cfg_a_valid = cfg_a_response_valid &&
        (cfg_a_response_bank == active_image_bank) &&
        (cfg_a_response_id == cfg_a_id);
    assign cfg_b_valid = cfg_b_response_valid &&
        (cfg_b_response_bank == active_image_bank) &&
        (cfg_b_response_id == cfg_b_id);
    assign cfg_stream_valid = cfg_stream_response_valid &&
        (cfg_stream_response_bank == active_image_bank) &&
        (cfg_stream_response_id == cfg_stream_id);
    assign phi_cfg_valid = phi_cfg_response_valid &&
        (phi_cfg_response_bank == active_image_bank) &&
        (phi_cfg_response_id == phi_cfg_id);

    wire [2:0] bank_mode = cfg_wr_data[51:49];
    wire [2:0] element_format = cfg_wr_data[54:52];
    wire [2:0] packing_mode = cfg_wr_data[57:55];
    wire read_enable = cfg_wr_data[58];
    wire write_enable = cfg_wr_data[59];
    wire atomic_commit = cfg_wr_data[60];
    wire [1:0] memory_space = cfg_wr_data[62:61];
    wire [2:0] bank_base = cfg_wr_data[46:44];
    wire [1:0] bank_count_log2 = cfg_wr_data[48:47];
    wire [4:0] bank_limit = {2'd0, bank_base} +
                            (5'd1 << bank_count_log2);
    wire enum_error =
        (bank_mode > `RECON_BANK_MODE_SUPPORT_ROW_MAJOR) ||
        (element_format > 3'd6) ||
                       (packing_mode > 3'd5);
    wire permission_error = !(read_enable || write_enable);
    wire bank_error = (memory_space != 2'd3) && (bank_limit > 5'd8);
    wire vector_address_error = (memory_space == 2'd0) &&
        ((cfg_wr_data[15:0] >= `RECON_MEMORY_BANK_DEPTH) ||
         (cfg_wr_data[43:32] >= `RECON_MEMORY_BANK_DEPTH));
    wire phi_error = (memory_space == 2'd3) &&
        ((bank_mode == `RECON_BANK_MODE_PING_PONG) ||
         (bank_mode > `RECON_BANK_MODE_SUPPORT_ROW_MAJOR) ||
         !read_enable || write_enable || atomic_commit);
    wire reserved_error = cfg_wr_data[63];
    wire active_bank_conflict = execution_active &&
        (cfg_wr_bank == active_image_bank);
    wire cfg_error = enum_error || permission_error || bank_error ||
        vector_address_error || phi_error || reserved_error ||
        active_bank_conflict;
    wire cfg_wr_fire = cfg_wr_valid &&
                                  cfg_wr_ready;
    wire cfg_wr_commit = cfg_wr_fire &&
                                    !cfg_error;

    assign cfg_wr_ready = !cfg_wr_resp_valid ||
                                     cfg_wr_resp_ready;
    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_wr_resp_valid <= 1'b0;
            cfg_wr_resp_error <= 1'b0;
            cfg_wr_resp_code <= 8'd0;
            cfg_wr_resp_detail <= 32'd0;
            cfg_valid_bitmap[0] <= 64'd0;
            cfg_valid_bitmap[1] <= 64'd0;
`ifdef FORMAL
            prev_active_bank <= 1'b0;
`endif
        end else begin
`ifdef FORMAL
            prev_active_bank <= active_image_bank;
`endif
            if (cfg_wr_resp_valid &&
                    cfg_wr_resp_ready)
                cfg_wr_resp_valid <= 1'b0;
            if (cfg_wr_fire) begin
                cfg_wr_resp_valid <= 1'b1;
                cfg_wr_resp_error <= cfg_error;
                cfg_wr_resp_code <= cfg_error ?
                    `RECON_CONTEXT_ERROR_MEMORY_CONFIGURATION : 8'd0;
                cfg_wr_resp_detail <= {
                    9'd0, active_bank_conflict,
                    reserved_error, phi_error, vector_address_error,
                    bank_error, permission_error, enum_error,
                    cfg_wr_bank, cfg_wr_id, 9'd0
                };
                if (!cfg_error)
                    cfg_valid_bitmap[cfg_wr_bank][cfg_wr_id] <= 1'b1;
            end
        end
    end

    // Copy 0: vector read A/B. Port A becomes the programming port while idle.
    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_a_read_valid <= 1'b0;
            cfg_b_read_valid <= 1'b0;
            cfg_a_response_valid <= 1'b0;
            cfg_b_response_valid <= 1'b0;
        end else if (cfg_wr_commit) begin
            cfg_read_copy[wr_idx] <= cfg_wr_data;
            cfg_a_read_valid <= 1'b0;
            cfg_b_read_valid <= 1'b0;
            cfg_a_response_valid <= 1'b0;
            cfg_b_response_valid <= 1'b0;
        end else begin
            cfg_a_read_data <= cfg_read_copy[rd_a_idx];
            cfg_b_read_data <= cfg_read_copy[rd_b_idx];
            cfg_a_read_valid <= cfg_valid_bitmap[active_image_bank][cfg_a_id];
            cfg_b_read_valid <= cfg_valid_bitmap[active_image_bank][cfg_b_id];
            cfg_a_read_bank <= active_image_bank;
            cfg_b_read_bank <= active_image_bank;
            cfg_a_read_id <= cfg_a_id;
            cfg_b_read_id <= cfg_b_id;
            cfg_a_data <= cfg_a_read_data;
            cfg_b_data <= cfg_b_read_data;
            cfg_a_response_valid <= cfg_a_read_valid;
            cfg_b_response_valid <= cfg_b_read_valid;
            cfg_a_response_bank <= cfg_a_read_bank;
            cfg_b_response_bank <= cfg_b_read_bank;
            cfg_a_response_id <= cfg_a_read_id;
            cfg_b_response_id <= cfg_b_read_id;
        end
    end

    // Copy 1: vector write/Phi. Port A becomes the programming port while idle.
    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_stream_read_valid <= 1'b0;
            phi_cfg_read_valid <= 1'b0;
            cfg_stream_response_valid <= 1'b0;
            phi_cfg_response_valid <= 1'b0;
        end else if (cfg_wr_commit) begin
            cfg_stream_copy[wr_idx] <= cfg_wr_data;
            cfg_stream_read_valid <= 1'b0;
            phi_cfg_read_valid <= 1'b0;
            cfg_stream_response_valid <= 1'b0;
            phi_cfg_response_valid <= 1'b0;
        end else begin
            cfg_stream_read_data <= cfg_stream_copy[stream_idx];
            phi_cfg_read_data <= cfg_stream_copy[phi_idx];
            cfg_stream_read_valid <=
                cfg_valid_bitmap[active_image_bank][cfg_stream_id];
            phi_cfg_read_valid <= cfg_valid_bitmap[active_image_bank][phi_cfg_id];
            cfg_stream_read_bank <= active_image_bank;
            phi_cfg_read_bank <= active_image_bank;
            cfg_stream_read_id <= cfg_stream_id;
            phi_cfg_read_id <= phi_cfg_id;
            cfg_stream_data <= cfg_stream_read_data;
            phi_cfg_data <= phi_cfg_read_data;
            cfg_stream_response_valid <= cfg_stream_read_valid;
            phi_cfg_response_valid <= phi_cfg_read_valid;
            cfg_stream_response_bank <= cfg_stream_read_bank;
            phi_cfg_response_bank <= phi_cfg_read_bank;
            cfg_stream_response_id <= cfg_stream_read_id;
            phi_cfg_response_id <= phi_cfg_read_id;
        end
    end

`ifdef FORMAL
    reg f_prev_wr_error;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_prev_wr_error <= 1'b0;
        end else begin
            if (execution_active)
                assert(active_image_bank == prev_active_bank);
            if (f_prev_wr_error) begin
                assert(cfg_wr_resp_valid);
                assert(cfg_wr_resp_error);
                assert(cfg_wr_resp_code ==
                       `RECON_CONTEXT_ERROR_MEMORY_CONFIGURATION);
            end
            f_prev_wr_error <=
                cfg_wr_fire && cfg_error;
        end
    end
`endif
endmodule

`default_nettype wire
