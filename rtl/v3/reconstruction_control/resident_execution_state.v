`timescale 1ns/1ps
`default_nettype none

module resident_execution_state (
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire scalar_state_clear,
    input wire scalar_preload_valid,
    input wire scalar_preload_accept,
    input wire [6:0] configured_work_count,
    input wire [6:0] active_support_count,
    output reg scalar_preload_ready,
    output reg algorithm_preload_seen,
    output reg [6:0] resident_work_count
);
    always @(posedge clk) begin
        if (!rst_n) begin
            scalar_preload_ready <= 1'b0;
            algorithm_preload_seen <= 1'b0;
        end else begin
            scalar_preload_ready <= scalar_preload_valid &&
                                    scalar_preload_accept;
            if (scalar_state_clear)
                algorithm_preload_seen <= 1'b0;
            else if (scalar_preload_valid && scalar_preload_accept)
                algorithm_preload_seen <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            if (!rst_n || abort_flush)
                resident_work_count <= configured_work_count;
            else
                resident_work_count <= (active_support_count != 0) ?
                    active_support_count : configured_work_count;
        end
    end
endmodule

`default_nettype wire
