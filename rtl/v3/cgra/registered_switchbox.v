`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Static circuit-switched nearest-neighbor router. Every output is registered;
// there is no packet header, arbitration, FIFO or combinational multi-hop.
module registered_switchbox #(
    parameter integer DATA_W = `RECON_SOLVER_W
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    update_enable,
    input  wire [2:0]              north_select,
    input  wire [2:0]              east_select,
    input  wire [2:0]              south_select,
    input  wire [2:0]              west_select,
    input  wire [DATA_W-1:0]       pe_result,
    input  wire [DATA_W-1:0]       north_input,
    input  wire [DATA_W-1:0]       east_input,
    input  wire [DATA_W-1:0]       south_input,
    input  wire [DATA_W-1:0]       west_input,
    input  wire [DATA_W-1:0]       external_input,
    output reg  [DATA_W-1:0]       north_output,
    output reg  [DATA_W-1:0]       east_output,
    output reg  [DATA_W-1:0]       south_output,
    output reg  [DATA_W-1:0]       west_output,
    output wire                    selection_error
);
    function [DATA_W-1:0] selected_data;
        input [2:0] select_value;
        begin
            case (select_value)
                `RECON_ROUTE_SOURCE_PE_RESULT: selected_data = pe_result;
                `RECON_ROUTE_SOURCE_NORTH: selected_data = north_input;
                `RECON_ROUTE_SOURCE_EAST: selected_data = east_input;
                `RECON_ROUTE_SOURCE_SOUTH: selected_data = south_input;
                `RECON_ROUTE_SOURCE_WEST: selected_data = west_input;
                `RECON_ROUTE_SOURCE_EXTERNAL: selected_data = external_input;
                default: selected_data = {DATA_W{1'b0}};
            endcase
        end
    endfunction

    wire invalid_north =
        north_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
    wire invalid_east =
        east_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
    wire invalid_south =
        south_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
    wire invalid_west =
        west_select == `RECON_ROUTE_SOURCE_ROW_OR_COLUMN_EXPRESS;
    assign selection_error = update_enable &&
        (invalid_north || invalid_east || invalid_south || invalid_west);

    always @(posedge clk) begin
        if (!rst_n) begin
            north_output <= {DATA_W{1'b0}};
            east_output <= {DATA_W{1'b0}};
            south_output <= {DATA_W{1'b0}};
            west_output <= {DATA_W{1'b0}};
        end else if (update_enable) begin
            if (north_select != `RECON_ROUTE_SOURCE_HOLD && !invalid_north)
                north_output <= selected_data(north_select);
            if (east_select != `RECON_ROUTE_SOURCE_HOLD && !invalid_east)
                east_output <= selected_data(east_select);
            if (south_select != `RECON_ROUTE_SOURCE_HOLD && !invalid_south)
                south_output <= selected_data(south_select);
            if (west_select != `RECON_ROUTE_SOURCE_HOLD && !invalid_west)
                west_output <= selected_data(west_select);
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_prev_no_update;
    reg [4*DATA_W-1:0] f_outputs;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_prev_no_update)
            assert({north_output,east_output,south_output,west_output} == f_outputs);
        f_prev_no_update <= !update_enable;
        f_outputs <= {north_output,east_output,south_output,west_output};
    end
`endif
endmodule

`default_nettype wire
