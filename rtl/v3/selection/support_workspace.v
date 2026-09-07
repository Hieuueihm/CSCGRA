`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module support_workspace #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer WORK_MAX = 96,
    parameter integer EXPOSE_BITMAP = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clear_valid,
    input  wire clear_bank,
    input  wire write_valid,
    input  wire write_bank,
    input  wire [6:0] write_slot,
    input  wire [INDEX_W-1:0] write_atom,
    input  wire signed [DATA_W-1:0] write_coefficient,
    input  wire write_atom_enable,
    input  wire write_coefficient_enable,
    input  wire read_bank,
    input  wire [6:0] read_slot,
    output wire read_valid,
    output wire [INDEX_W-1:0] read_atom,
    output wire signed [DATA_W-1:0] read_coefficient,
    input  wire coefficient_scalar_read_enable,
    input  wire coefficient_scalar_read_bank,
    input  wire [6:0] coefficient_scalar_read_slot,
    output wire coefficient_scalar_read_valid,
    output wire signed [DATA_W-1:0] coefficient_scalar_read_coefficient,
    input  wire coefficient_stripe_read_enable,
    input  wire coefficient_stripe_read_bank,
    input  wire [2:0] coefficient_stripe_read_index,
    output wire coefficient_stripe_read_valid,
    output wire [16*DATA_W-1:0] coefficient_stripe_read_coefficients,
    input  wire query_bank,
    input  wire [INDEX_W-1:0] query_atom,
    output wire query_member,
    output wire [6:0] query_slot,
    input  wire membership_query_bank,
    input  wire [INDEX_W-1:0] membership_query_atom,
    output wire membership_query_member,
    output wire [6:0] membership_query_slot,
    output wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank0_entries,
    output wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank1_entries,
    output wire [WORK_MAX-1:0] bank0_slot_valid,
    output wire [WORK_MAX-1:0] bank1_slot_valid,
    output wire [2*(1<<INDEX_W)-1:0] debug_bitmaps
);
    localparam integer COEFFICIENT_SHADOW_MAX =
        WORK_MAX < `RECON_K_MAX ? WORK_MAX : `RECON_K_MAX;

    reg [INDEX_W-1:0] entry_bank0 [0:WORK_MAX-1];
    reg [INDEX_W-1:0] entry_bank1 [0:WORK_MAX-1];
    reg [DATA_W-1:0] coefficient_shadow_bank0
        [0:COEFFICIENT_SHADOW_MAX-1];
    reg [DATA_W-1:0] coefficient_shadow_bank1
        [0:COEFFICIENT_SHADOW_MAX-1];
    reg [WORK_MAX-1:0] slot_valid_bank0;
    reg [WORK_MAX-1:0] slot_valid_bank1;
    reg [(1<<INDEX_W)-1:0] bitmap_bank0;
    reg [(1<<INDEX_W)-1:0] bitmap_bank1;
    reg [6:0] atom_slot_bank0 [0:(1<<INDEX_W)-1];
    reg [6:0] atom_slot_bank1 [0:(1<<INDEX_W)-1];
    reg [WORK_MAX-1:0] write_bank0_slot_select;
    reg [WORK_MAX-1:0] write_bank1_slot_select;
    wire [WORK_MAX-1:0] write_bank0_atom_select =
        write_bank0_slot_select & {WORK_MAX{write_atom_enable}};
    wire [WORK_MAX-1:0] write_bank1_atom_select =
        write_bank1_slot_select & {WORK_MAX{write_atom_enable}};
    wire write_accept = write_valid && (write_slot < WORK_MAX);
    wire [INDEX_W-1:0] selected_read_atom = read_bank ?
        entry_bank1[read_slot] : entry_bank0[read_slot];
    wire [DATA_W-1:0] selected_shadow_coefficient =
        (read_slot < COEFFICIENT_SHADOW_MAX) ?
        (read_bank ? coefficient_shadow_bank1[read_slot] :
                     coefficient_shadow_bank0[read_slot]) :
        {DATA_W{1'b0}};
    assign read_valid = (read_slot < WORK_MAX) &&
        (read_bank ? slot_valid_bank1[read_slot] : slot_valid_bank0[read_slot]);
    assign read_atom = selected_read_atom;
    assign read_coefficient = selected_shadow_coefficient;
    wire [6:0] query_slot_candidate = query_bank ?
        atom_slot_bank1[query_atom] : atom_slot_bank0[query_atom];
    wire query_atom_present = query_bank ?
        bitmap_bank1[query_atom] : bitmap_bank0[query_atom];
    wire query_slot_candidate_valid = query_atom_present &&
        (query_slot_candidate < WORK_MAX) &&
        (query_bank ? slot_valid_bank1[query_slot_candidate] :
                      slot_valid_bank0[query_slot_candidate]);
    wire [INDEX_W-1:0] query_slot_candidate_atom = query_bank ?
        entry_bank1[query_slot_candidate] : entry_bank0[query_slot_candidate];
    wire [6:0] membership_slot_candidate = membership_query_bank ?
        atom_slot_bank1[membership_query_atom] :
        atom_slot_bank0[membership_query_atom];
    wire membership_atom_present = membership_query_bank ?
        bitmap_bank1[membership_query_atom] :
        bitmap_bank0[membership_query_atom];
    wire membership_slot_candidate_valid =
        membership_atom_present && (membership_slot_candidate < WORK_MAX) &&
        (membership_query_bank ? slot_valid_bank1[membership_slot_candidate] :
                                 slot_valid_bank0[membership_slot_candidate]);
    wire [INDEX_W-1:0] membership_slot_candidate_atom =
        membership_query_bank ? entry_bank1[membership_slot_candidate] :
                                entry_bank0[membership_slot_candidate];
    assign query_member = query_slot_candidate_valid &&
        (query_slot_candidate_atom == query_atom);
    assign membership_query_member = membership_slot_candidate_valid &&
        (membership_slot_candidate_atom == membership_query_atom);
    assign query_slot = query_member ? query_slot_candidate : 7'd0;
    assign membership_query_slot = membership_query_member ?
        membership_slot_candidate : 7'd0;
    assign bank0_slot_valid = slot_valid_bank0;
    assign bank1_slot_valid = slot_valid_bank1;
    assign debug_bitmaps = EXPOSE_BITMAP ?
        {bitmap_bank1, bitmap_bank0} : {2*(1<<INDEX_W){1'b0}};

    support_coefficient_stripe_store #(
        .DATA_W(DATA_W), .LANES(16), .WORK_MAX(WORK_MAX)
    ) u_coefficient_store (
        .clk(clk), .rst_n(rst_n),
        .write_enable(write_accept && write_coefficient_enable),
        .write_bank(write_bank), .write_slot(write_slot),
        .write_coefficient(write_coefficient),
        .scalar_read_enable(coefficient_scalar_read_enable),
        .scalar_read_bank(coefficient_scalar_read_bank),
        .scalar_read_slot(coefficient_scalar_read_slot),
        .scalar_read_valid(coefficient_scalar_read_valid),
        .scalar_read_coefficient(coefficient_scalar_read_coefficient),
        .stripe_read_enable(coefficient_stripe_read_enable),
        .stripe_read_bank(coefficient_stripe_read_bank),
        .stripe_read_index(coefficient_stripe_read_index),
        .stripe_read_valid(coefficient_stripe_read_valid),
        .stripe_read_coefficients(coefficient_stripe_read_coefficients)
    );

    genvar flatten_index;
    generate
        for (flatten_index = 0; flatten_index < WORK_MAX; flatten_index = flatten_index + 1) begin : g_flatten
            assign bank0_entries[
                flatten_index*(INDEX_W+DATA_W)+DATA_W +: INDEX_W] =
                entry_bank0[flatten_index];
            assign bank1_entries[
                flatten_index*(INDEX_W+DATA_W)+DATA_W +: INDEX_W] =
                entry_bank1[flatten_index];
            if (flatten_index < COEFFICIENT_SHADOW_MAX) begin : g_shadow
                assign bank0_entries[
                    flatten_index*(INDEX_W+DATA_W) +: DATA_W] =
                    coefficient_shadow_bank0[flatten_index];
                assign bank1_entries[
                    flatten_index*(INDEX_W+DATA_W) +: DATA_W] =
                    coefficient_shadow_bank1[flatten_index];
            end else begin : g_no_shadow
                assign bank0_entries[
                    flatten_index*(INDEX_W+DATA_W) +: DATA_W] =
                    {DATA_W{1'b0}};
                assign bank1_entries[
                    flatten_index*(INDEX_W+DATA_W) +: DATA_W] =
                    {DATA_W{1'b0}};
            end
        end
    endgenerate

    always @* begin
        write_bank0_slot_select = {WORK_MAX{1'b0}};
        write_bank1_slot_select = {WORK_MAX{1'b0}};
        if (write_accept) begin
            if (write_bank)
                write_bank1_slot_select[write_slot] = 1'b1;
            else
                write_bank0_slot_select[write_slot] = 1'b1;
        end
    end

    integer write_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            slot_valid_bank0 <= 0;
            slot_valid_bank1 <= 0;
            bitmap_bank0 <= 0;
            bitmap_bank1 <= 0;
        end else begin
            if (clear_valid) begin
                if (clear_bank) begin
                    slot_valid_bank1 <= 0;
                    bitmap_bank1 <= 0;
                end else begin
                    slot_valid_bank0 <= 0;
                    bitmap_bank0 <= 0;
                end
            end
            for (write_index = 0; write_index < WORK_MAX;
                write_index = write_index + 1) begin
                if (write_bank0_atom_select[write_index]) begin
                    entry_bank0[write_index] <= write_atom;
                    slot_valid_bank0[write_index] <= 1'b1;
                end
                if (write_bank1_atom_select[write_index]) begin
                    entry_bank1[write_index] <= write_atom;
                    slot_valid_bank1[write_index] <= 1'b1;
                end
            end
            if (write_accept && write_coefficient_enable &&
                (write_slot < COEFFICIENT_SHADOW_MAX)) begin
                if (write_bank)
                    coefficient_shadow_bank1[write_slot] <= write_coefficient;
                else
                    coefficient_shadow_bank0[write_slot] <= write_coefficient;
            end
            if (write_accept && write_atom_enable) begin
                if (write_bank) begin
                    bitmap_bank1[write_atom] <= 1'b1;
                    atom_slot_bank1[write_atom] <= write_slot;
                end else begin
                    bitmap_bank0[write_atom] <= 1'b1;
                    atom_slot_bank0[write_atom] <= write_slot;
                end
            end
        end
    end

`ifdef FORMAL
    integer f_left;
    integer f_right;
    always @(posedge clk) begin
        if (rst_n) begin
            for (f_left = 0; f_left < WORK_MAX; f_left = f_left + 1) begin
                if (EXPOSE_BITMAP && slot_valid_bank0[f_left])
                    assert(bitmap_bank0[entry_bank0[f_left]]);
                if (EXPOSE_BITMAP && slot_valid_bank1[f_left])
                    assert(bitmap_bank1[entry_bank1[f_left]]);
                for (f_right = f_left + 1; f_right < WORK_MAX; f_right = f_right + 1) begin
                    if (slot_valid_bank0[f_left] && slot_valid_bank0[f_right])
                        assert(entry_bank0[f_left] != entry_bank0[f_right]);
                    if (slot_valid_bank1[f_left] && slot_valid_bank1[f_right])
                        assert(entry_bank1[f_left] != entry_bank1[f_right]);
                end
            end
        end
    end
`endif
endmodule

`default_nettype wire
