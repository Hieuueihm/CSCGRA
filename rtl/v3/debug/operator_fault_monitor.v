`timescale 1ns/1ps
`default_nettype none

module operator_fault_monitor #(
    parameter integer DETAIL_W = 16
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire fault_event,
    input wire [DETAIL_W-1:0] fault_event_detail,
    output reg fault_active,
    output reg [DETAIL_W-1:0] fault_detail
);
    reg fault_pending;
    reg [DETAIL_W-1:0] fault_detail_pending;

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            fault_active <= 1'b0;
            fault_detail <= {DETAIL_W{1'b0}};
            fault_pending <= 1'b0;
            fault_detail_pending <= {DETAIL_W{1'b0}};
        end else begin
            fault_pending <= fault_event;
            if (fault_event)
                fault_detail_pending <= fault_event_detail;
            if (fault_pending && !fault_active) begin
                fault_active <= 1'b1;
                fault_detail <= fault_detail_pending;
            end
        end
    end
endmodule

`default_nettype wire
