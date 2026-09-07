`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module support_coefficient_remapper #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer WORK_MAX = 96
)(
    input  wire clk,
    input  wire rst_n,
    input  wire cancel,
    input  wire start_valid,
    output wire start_ready,
    input  wire [6:0] current_count,
    input  wire [6:0] proposed_count,
    output wire read_current_bank,
    output wire [6:0] read_slot,
    input  wire [INDEX_W-1:0] read_atom,
    output wire coefficient_read_enable,
    output wire coefficient_read_current_bank,
    output wire [6:0] coefficient_read_slot,
    input  wire coefficient_read_valid,
    input  wire signed [DATA_W-1:0] coefficient_read_data,
    output wire query_valid,
    output wire query_current_bank,
    output wire [INDEX_W-1:0] query_atom,
    input  wire query_member,
    input  wire [6:0] query_slot,
    output reg  done_valid,
    input  wire done_ready,
    output reg  fault,
    output wire remap_coefficient_valid,
    output wire [6:0] remap_coefficient_slot,
    output wire signed [DATA_W-1:0] remap_coefficient,
    output reg  [6:0] dropped_count,
    output reg  [WORK_MAX*INDEX_W-1:0] dropped_indices,
    output reg  [WORK_MAX*DATA_W-1:0] dropped_coefficients
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_REMAP_QUERY = 3'd1;
    localparam [2:0] STATE_REMAP_READ = 3'd2;
    localparam [2:0] STATE_REMAP_COEFFICIENT_WAIT = 3'd3;
    localparam [2:0] STATE_DROP = 3'd4;
    localparam [2:0] STATE_DROP_COEFFICIENT_WAIT = 3'd5;

    reg [2:0] state;
    reg [6:0] current_count_latched;
    reg [6:0] proposed_count_latched;
    reg [6:0] current_cursor;
    reg [6:0] proposed_cursor;
    reg remap_match_latched;
    reg [6:0] remap_match_slot;
    reg [INDEX_W-1:0] dropped_atom_latched;

    assign start_ready = (state == STATE_IDLE) && (!done_valid || done_ready);
    wire start_fire = start_valid && start_ready;
    assign read_current_bank = (state == STATE_REMAP_READ) || (state == STATE_DROP);
    assign read_slot = (state == STATE_DROP) ? current_cursor :
                       (state == STATE_REMAP_READ) ? remap_match_slot : proposed_cursor;
    assign query_valid = (state == STATE_REMAP_QUERY) || (state == STATE_DROP);
    assign query_current_bank = state == STATE_REMAP_QUERY;
    assign query_atom = read_atom;
    assign coefficient_read_enable =
        ((state == STATE_REMAP_READ) && remap_match_latched) ||
        ((state == STATE_DROP) && !query_member);
    assign coefficient_read_current_bank = 1'b1;
    assign coefficient_read_slot = (state == STATE_DROP) ? current_cursor :
                                   remap_match_slot;
    assign remap_coefficient_valid =
        ((state == STATE_REMAP_READ) && !remap_match_latched) ||
        ((state == STATE_REMAP_COEFFICIENT_WAIT) && coefficient_read_valid);
    assign remap_coefficient_slot = proposed_cursor;
    assign remap_coefficient = remap_match_latched ? coefficient_read_data :
                                {DATA_W{1'b0}};

    task finish_or_advance_remap;
        begin
            if (proposed_cursor + 1'b1 == proposed_count_latched) begin
                proposed_cursor <= 0;
                if (current_count_latched == 0) begin
                    state <= STATE_IDLE;
                    done_valid <= 1;
                end else
                    state <= STATE_DROP;
            end else begin
                proposed_cursor <= proposed_cursor + 1'b1;
                state <= STATE_REMAP_QUERY;
            end
        end
    endtask

    task finish_or_advance_drop;
        begin
            if (current_cursor + 1'b1 == current_count_latched) begin
                current_cursor <= 0;
                state <= STATE_IDLE;
                done_valid <= 1;
            end else begin
                current_cursor <= current_cursor + 1'b1;
                state <= STATE_DROP;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            done_valid <= 0;
            fault <= 0;
            current_count_latched <= 0;
            proposed_count_latched <= 0;
            current_cursor <= 0;
            proposed_cursor <= 0;
            remap_match_latched <= 0;
            remap_match_slot <= 0;
            dropped_atom_latched <= 0;
            dropped_count <= 0;
            dropped_indices <= 0;
            dropped_coefficients <= 0;
        end else begin
            if (start_fire) begin
                dropped_indices <= 0;
                dropped_coefficients <= 0;
            end else begin
                if ((state == STATE_DROP_COEFFICIENT_WAIT) &&
                    coefficient_read_valid) begin
                    dropped_indices[dropped_count*INDEX_W +: INDEX_W] <=
                        dropped_atom_latched;
                    dropped_coefficients[dropped_count*DATA_W +: DATA_W] <=
                        coefficient_read_data;
                end
            end

            if (cancel) begin
                state <= STATE_IDLE;
                done_valid <= 0;
                fault <= 0;
                current_count_latched <= 0;
                proposed_count_latched <= 0;
                current_cursor <= 0;
                proposed_cursor <= 0;
                remap_match_latched <= 0;
                remap_match_slot <= 0;
                dropped_atom_latched <= 0;
                dropped_count <= 0;
            end else begin
                if (done_valid && done_ready)
                    done_valid <= 0;
                if (start_fire) begin
                    fault <= (current_count > WORK_MAX) || (proposed_count > WORK_MAX);
                    current_count_latched <= current_count;
                    proposed_count_latched <= proposed_count;
                    current_cursor <= 0;
                    proposed_cursor <= 0;
                    remap_match_latched <= 0;
                    remap_match_slot <= 0;
                    dropped_atom_latched <= 0;
                    dropped_count <= 0;
                    if ((current_count > WORK_MAX) || (proposed_count > WORK_MAX)) begin
                        state <= STATE_IDLE;
                        done_valid <= 1;
                    end else if (proposed_count == 0) begin
                        if (current_count == 0) begin
                            state <= STATE_IDLE;
                            done_valid <= 1;
                        end else
                            state <= STATE_DROP;
                    end else
                        state <= STATE_REMAP_QUERY;
                end else if (state == STATE_REMAP_QUERY) begin
                    remap_match_latched <= query_member;
                    remap_match_slot <= query_slot;
                    state <= STATE_REMAP_READ;
                end else if (state == STATE_REMAP_READ) begin
                    if (remap_match_latched)
                        state <= STATE_REMAP_COEFFICIENT_WAIT;
                    else
                        finish_or_advance_remap();
                end else if (state == STATE_REMAP_COEFFICIENT_WAIT) begin
                    if (coefficient_read_valid)
                        finish_or_advance_remap();
                end else if (state == STATE_DROP) begin
                    if (query_member)
                        finish_or_advance_drop();
                    else begin
                        dropped_atom_latched <= read_atom;
                        state <= STATE_DROP_COEFFICIENT_WAIT;
                    end
                end else if (state == STATE_DROP_COEFFICIENT_WAIT) begin
                    if (coefficient_read_valid) begin
                        dropped_count <= dropped_count + 1'b1;
                        finish_or_advance_drop();
                    end
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [6:0] f_dropped_count;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        if (rst_n && f_past_valid) begin
            assert(current_cursor < WORK_MAX);
            assert(proposed_cursor < WORK_MAX);
            assert(dropped_count <= WORK_MAX);
            if (f_stalled) begin
                assert(done_valid);
                assert(dropped_count == f_dropped_count);
            end
        end
        f_past_valid <= 1;
        f_stalled <= !cancel && done_valid && !done_ready;
        f_dropped_count <= dropped_count;
    end
`endif
endmodule

`default_nettype wire
