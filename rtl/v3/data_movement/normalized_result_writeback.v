`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module normalized_result_writeback #(
    parameter integer DATA_W = `RECON_SOLVER_W
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire cycle_valid,
    input wire cycle_commit,
    input wire vector_write_enable,
    input wire [2:0] write_format,
    input wire [4:0] resource_operation,
    input wire resource_wait_for_result,
    input wire [2:0] resource_output_select,
    input wire [2:0] phi_mode,
    input wire [10:0] signal_length,
    input wire [6:0] work_count,
    input wire reduction_accept,
    input wire normalizer_output_valid,
    input wire signed [DATA_W-1:0] normalizer_output_data,
    output wire normalizer_memory_mode,
    output wire normalizer_ready,
    output wire reduction_memory_context,
    output wire write_mode,
    output wire write_final,
    output wire write_release,
    output reg scalar_pending,
    output reg [16*DATA_W-1:0] scalar_pack,
    output reg [3:0] pack_index,
    output reg [10:0] output_count
);
    reg memory_pending;

    assign normalizer_memory_mode = (phi_mode == 3'd3) || memory_pending;
    assign normalizer_ready = normalizer_memory_mode && !scalar_pending;
    assign reduction_memory_context = cycle_valid && vector_write_enable &&
        (resource_operation == `RECON_RESOURCE_OP_REDUCE_SUM) &&
        resource_wait_for_result &&
        (resource_output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM);
    assign write_mode =
        (write_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (reduction_memory_context || memory_pending || scalar_pending);
    assign write_final =
        (output_count + 11'd1 ==
         ((phi_mode == 3'd3) ? {4'd0, work_count} : signal_length));
    assign write_release = scalar_pending &&
        ((pack_index == 4'd15) || write_final);

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            scalar_pack <= {16*DATA_W{1'b0}};
            pack_index <= 4'd0;
            output_count <= 11'd0;
            scalar_pending <= 1'b0;
            memory_pending <= 1'b0;
        end else begin
            if (reduction_accept)
                memory_pending <= 1'b1;
            else if (normalizer_output_valid && normalizer_ready)
                memory_pending <= 1'b0;

            if (normalizer_output_valid && normalizer_ready) begin
                scalar_pack[pack_index*DATA_W +: DATA_W] <=
                    normalizer_output_data;
                scalar_pending <= 1'b1;
            end
            if (cycle_valid && cycle_commit && vector_write_enable &&
                    write_mode && scalar_pending) begin
                scalar_pending <= 1'b0;
                if (write_final) begin
                    scalar_pack <= {16*DATA_W{1'b0}};
                    pack_index <= 4'd0;
                    output_count <= 11'd0;
                end else begin
                    output_count <= output_count + 1'b1;
                    if (write_release) begin
                        scalar_pack <= {16*DATA_W{1'b0}};
                        pack_index <= 4'd0;
                    end else begin
                        pack_index <= pack_index + 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
