`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_request_queue #(
    parameter integer DEPTH = `RECON_PHI_REQUEST_QUEUE_DEPTH
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         flush,
    input  wire         input_valid,
    output wire         input_ready,
    input  wire [63:0]  input_seed,
    input  wire [`RECON_PHI_COLUMN_W-1:0] input_column,
    input  wire [`RECON_PHI_ROW_PAIR_W-1:0] input_row_pair,
    input  wire [`RECON_PHI_TAG_W-1:0] input_tag,
    input  wire [8:0]   input_measurement_count,
    output wire         output_valid,
    input  wire         output_ready,
    output wire [63:0]  output_seed,
    output wire [`RECON_PHI_COLUMN_W-1:0] output_column,
    output wire [`RECON_PHI_ROW_PAIR_W-1:0] output_row_pair,
    output wire [`RECON_PHI_TAG_W-1:0] output_tag,
    output wire [8:0]   output_measurement_count
);
    localparam integer POINTER_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_W = $clog2(DEPTH + 1);

    reg [63:0] seed_mem [0:DEPTH-1];
    reg [`RECON_PHI_COLUMN_W-1:0] column_mem [0:DEPTH-1];
    reg [`RECON_PHI_ROW_PAIR_W-1:0] row_pair_mem [0:DEPTH-1];
    reg [`RECON_PHI_TAG_W-1:0] tag_mem [0:DEPTH-1];
    reg [8:0] measurement_mem [0:DEPTH-1];
    reg [POINTER_W-1:0] read_pointer;
    reg [POINTER_W-1:0] write_pointer;
    reg [COUNT_W-1:0] count;

    wire stored_valid = count != 0;
    wire bypass = !stored_valid;
    assign output_valid = stored_valid || input_valid;
    assign output_seed = bypass ? input_seed : seed_mem[read_pointer];
    assign output_column = bypass ? input_column : column_mem[read_pointer];
    assign output_row_pair = bypass ? input_row_pair : row_pair_mem[read_pointer];
    assign output_tag = bypass ? input_tag : tag_mem[read_pointer];
    assign output_measurement_count = bypass ? input_measurement_count :
                                                      measurement_mem[read_pointer];
    assign input_ready = (count < DEPTH) ||
                         (stored_valid && output_ready);

    wire input_fire = input_valid && input_ready;
    wire output_fire = output_valid && output_ready;
    wire bypass_fire = bypass && input_fire && output_fire;
    wire store_input = input_fire && !bypass_fire;
    wire remove_stored = stored_valid && output_fire;

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            read_pointer <= {POINTER_W{1'b0}};
            write_pointer <= {POINTER_W{1'b0}};
            count <= {COUNT_W{1'b0}};
        end else begin
            if (store_input) begin
                seed_mem[write_pointer] <= input_seed;
                column_mem[write_pointer] <= input_column;
                row_pair_mem[write_pointer] <= input_row_pair;
                tag_mem[write_pointer] <= input_tag;
                measurement_mem[write_pointer] <= input_measurement_count;
                write_pointer <= write_pointer + {{POINTER_W-1{1'b0}}, 1'b1};
            end
            if (remove_stored)
                read_pointer <= read_pointer + {{POINTER_W-1{1'b0}}, 1'b1};
            case ({store_input, remove_stored})
                2'b10: count <= count + {{COUNT_W-1{1'b0}}, 1'b1};
                2'b01: count <= count - {{COUNT_W-1{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [63:0] f_seed;
    reg [`RECON_PHI_COLUMN_W-1:0] f_column;
    reg [`RECON_PHI_ROW_PAIR_W-1:0] f_row_pair;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid) begin
            assert(count <= DEPTH);
            if (f_stalled) begin
                assert(output_valid);
                assert(output_seed == f_seed);
                assert(output_column == f_column);
                assert(output_row_pair == f_row_pair);
                assert(output_tag == f_tag);
            end
        end
        f_stalled <= (!rst_n || flush) ? 1'b0 :
                     (output_valid && !output_ready);
        f_seed <= output_seed;
        f_column <= output_column;
        f_row_pair <= output_row_pair;
        f_tag <= output_tag;
    end
`endif
endmodule

`default_nettype wire
