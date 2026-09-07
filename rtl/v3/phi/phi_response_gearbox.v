`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module phi_response_gearbox #(
    parameter integer DEPTH = `RECON_PHI_RESPONSE_QUEUE_DEPTH
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         flush,
    input  wire         input_valid,
    output wire         input_ready,
    input  wire [31:0]  input_nonzero0,
    input  wire [31:0]  input_sign0,
    input  wire [31:0]  input_nonzero1,
    input  wire [31:0]  input_sign1,
    input  wire [`RECON_PHI_COLUMN_W-1:0] input_column,
    input  wire [`RECON_PHI_ROW_PAIR_W-1:0] input_row_pair,
    input  wire [`RECON_PHI_TAG_W-1:0] input_tag,
    output wire         output_valid,
    input  wire         output_ready,
    output wire [31:0]  output_nonzero,
    output wire [31:0]  output_sign,
    output wire [`RECON_PHI_COLUMN_W-1:0] output_column,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] output_row_block,
    output wire [`RECON_PHI_TAG_W-1:0] output_tag
);
    localparam integer POINTER_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_W = $clog2(DEPTH + 1);

    reg [63:0] word0_mem [0:DEPTH-1];
    reg [63:0] word1_mem [0:DEPTH-1];
    reg [`RECON_PHI_COLUMN_W-1:0] column_mem [0:DEPTH-1];
    reg [`RECON_PHI_ROW_PAIR_W-1:0] row_pair_mem [0:DEPTH-1];
    reg [`RECON_PHI_TAG_W-1:0] tag_mem [0:DEPTH-1];
    reg [POINTER_W-1:0] read_pointer;
    reg [POINTER_W-1:0] write_pointer;
    reg [COUNT_W-1:0] count;
    reg word_select;

    wire stored_valid = count != 0;
    assign output_valid = stored_valid || input_valid;
    assign output_nonzero = stored_valid ?
        (word_select ? word1_mem[read_pointer][63:32] :
                       word0_mem[read_pointer][63:32]) : input_nonzero0;
    assign output_sign = stored_valid ?
        (word_select ? word1_mem[read_pointer][31:0] :
                       word0_mem[read_pointer][31:0]) : input_sign0;
    assign output_column = stored_valid ? column_mem[read_pointer] : input_column;
    assign output_row_block = stored_valid ?
        {row_pair_mem[read_pointer], word_select} : {input_row_pair, 1'b0};
    assign output_tag = stored_valid ? tag_mem[read_pointer] : input_tag;

    wire output_fire = output_valid && output_ready;
    wire bypass_first_word = !stored_valid && input_valid && output_ready;
    wire pop_pair = stored_valid && output_fire && word_select;
    assign input_ready = (count < DEPTH) || pop_pair;
    wire input_fire = input_valid && input_ready;

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            read_pointer <= {POINTER_W{1'b0}};
            write_pointer <= {POINTER_W{1'b0}};
            count <= {COUNT_W{1'b0}};
            word_select <= 1'b0;
        end else begin
            if (input_fire) begin
                word0_mem[write_pointer] <= {input_nonzero0, input_sign0};
                word1_mem[write_pointer] <= {input_nonzero1, input_sign1};
                column_mem[write_pointer] <= input_column;
                row_pair_mem[write_pointer] <= input_row_pair;
                tag_mem[write_pointer] <= input_tag;
                write_pointer <= write_pointer + {{POINTER_W-1{1'b0}}, 1'b1};
            end
            if (bypass_first_word) begin
                word_select <= 1'b1;
            end else if (output_fire) begin
                if (word_select) begin
                    word_select <= 1'b0;
                    read_pointer <= read_pointer + {{POINTER_W-1{1'b0}}, 1'b1};
                end else begin
                    word_select <= 1'b1;
                end
            end
            case ({input_fire, pop_pair})
                2'b10: count <= count + {{COUNT_W-1{1'b0}}, 1'b1};
                2'b01: count <= count - {{COUNT_W-1{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [31:0] f_nonzero;
    reg [31:0] f_sign;
    reg [`RECON_PHI_COLUMN_W-1:0] f_column;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] f_row_block;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && !flush) begin
            assert(count <= DEPTH);
            if (f_stalled) begin
                assert(output_valid);
                assert(output_nonzero == f_nonzero);
                assert(output_sign == f_sign);
                assert(output_column == f_column);
                assert(output_row_block == f_row_block);
                assert(output_tag == f_tag);
            end
        end
        f_stalled <= (!rst_n || flush) ? 1'b0 :
                     (output_valid && !output_ready);
        f_nonzero <= output_nonzero;
        f_sign <= output_sign;
        f_column <= output_column;
        f_row_block <= output_row_block;
        f_tag <= output_tag;
    end
`endif
endmodule

`default_nettype wire
