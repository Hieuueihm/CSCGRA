`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module support_state_manager #(
    parameter integer DATA_W = `RECON_SOLVER_W,
    parameter integer INDEX_W = 10,
    parameter integer CANDIDATE_MAX = 64,
    parameter integer WORK_MAX = 96,
    parameter integer TAG_W = 3,
    parameter integer USE_INDEXED_CANDIDATE_READ = 0,
    parameter integer EXPOSE_ACTIVE_BITMAP = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire routine_start,
    input  wire abort_transaction,
    input  wire certificate_fail,
    input  wire cycle_valid,
    output wire cycle_ready,
    input  wire cycle_commit,
    input  wire [4:0] operation,
    input  wire [TAG_W-1:0] request_tag,
    input  wire [6:0] request_slot,
    input  wire request_cache_from_candidates,
    input  wire request_candidate_coefficients,
    input  wire request_zero_candidate_coefficient,
    input  wire request_defer_activation,
    input  wire request_sort_by_index,
    input  wire request_scatter_active,
    input  wire signed [DATA_W-1:0] scatter_coefficient,
    input  wire [6:0] candidate_count,
    input  wire [CANDIDATE_MAX*DATA_W-1:0] candidate_values,
    input  wire [CANDIDATE_MAX*INDEX_W-1:0] candidate_indices,
    input  wire [CANDIDATE_MAX*6-1:0] candidate_symbol_slots,
    output wire [6:0] candidate_read_slot,
    input  wire candidate_read_valid,
    input  wire signed [DATA_W-1:0] candidate_read_value,
    input  wire [INDEX_W-1:0] candidate_read_index,
    input  wire [5:0] candidate_read_symbol_slot,
    input  wire [6:0] candidate_read_sorted_slot,
    input  wire [INDEX_W-1:0] membership_query_atom,
    output wire membership_query_member,
    output wire [6:0] membership_query_slot,
    output reg  append_gradient_valid,
    output reg  [6:0] append_gradient_slot,
    output reg  signed [DATA_W-1:0] append_gradient_value,
    output reg  response_valid,
    input  wire response_ready,
    output reg  [4:0] response_operation,
    output reg  [TAG_W-1:0] response_tag,
    output reg  response_fault,
    output reg  [6:0] response_count,
    output reg  response_member,
    output reg  [6:0] response_slot,
    output reg  [INDEX_W-1:0] response_atom,
    output reg  signed [DATA_W-1:0] response_coefficient,
    output wire transaction_open,
    output wire current_bank,
    output wire [6:0] current_count,
    output wire [6:0] proposed_count,
    output wire [6:0] view_count,
    output reg  proposal_view_active,
    output reg  [31:0] rollback_count,
    output reg  [31:0] rollback_cycle_count,
    output wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank0_entries,
    output wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] bank1_entries,
    output wire [WORK_MAX-1:0] bank0_slot_valid,
    output wire [WORK_MAX-1:0] bank1_slot_valid,
    output wire [(1<<INDEX_W)-1:0] active_support_bitmap,
    output wire [WORK_MAX*INDEX_W-1:0] active_support_indices,
    output wire [WORK_MAX*DATA_W-1:0] active_support_coefficients,
    input  wire coefficient_stripe_read_enable,
    input  wire [2:0] coefficient_stripe_read_index,
    output wire coefficient_stripe_read_valid,
    output wire [16*DATA_W-1:0] coefficient_stripe_read_coefficients,
    output reg  remap_event_valid,
    output reg  remap_event_fault,
    output wire [6:0] remap_dropped_count,
    output wire [WORK_MAX*INDEX_W-1:0] remap_dropped_indices,
    output wire [WORK_MAX*DATA_W-1:0] remap_dropped_coefficients,
    output wire cache_prepare_valid,
    input  wire cache_prepare_ready,
    output wire cache_prepare_from_candidates,
    output wire [6:0] cache_prepare_support_count,
    output wire [6:0] cache_prepare_preserve_count,
    output wire cache_promote_valid,
    input  wire cache_promote_ready,
    output wire [5:0] cache_promote_candidate_slot,
    output wire [6:0] cache_promote_support_slot,
    input  wire cache_valid,
    input  wire cache_fault,
    output reg  cache_invalidate,
    output wire cache_refill_pending,
    output wire [6:0] cache_refill_support_count,
    output wire cache_refill_column_valid,
    input  wire cache_refill_column_ready,
    output wire [6:0] cache_refill_column_slot,
    output wire [INDEX_W-1:0] cache_refill_column
);
    localparam [3:0] STATE_IDLE = 4'd0;
    localparam [3:0] STATE_CLONE = 4'd1;
    localparam [3:0] STATE_APPEND = 4'd2;
    localparam [3:0] STATE_UNION = 4'd3;
    localparam [3:0] STATE_CACHE_PREPARE = 4'd4;
    localparam [3:0] STATE_CACHE_PROMOTE = 4'd5;
    localparam [3:0] STATE_CACHE_WAIT = 4'd6;
    localparam [3:0] STATE_REMAP_START = 4'd7;
    localparam [3:0] STATE_REMAP_WAIT = 4'd8;
    localparam [3:0] STATE_GATHER_WAIT = 4'd9;
    localparam [3:0] STATE_APPEND_WRITE = 4'd10;
    localparam [3:0] STATE_UNION_WRITE = 4'd11;
    localparam integer DATA_CANONICAL_SHIFT =
        `RECON_SOLVER_F - `RECON_DATA_F;

    function signed [DATA_W-1:0] canonical_data_coefficient;
        input signed [DATA_W-1:0] value;
        reg [DATA_W:0] magnitude;
        reg [DATA_W:0] rounded_magnitude;
        reg signed [`RECON_DATA_W-1:0] data_value;
        begin
            magnitude = value[DATA_W-1] ?
                {1'b0, (~value + {{DATA_W-1{1'b0}}, 1'b1})} :
                {1'b0, value};
            rounded_magnitude =
                (magnitude +
                 ({{DATA_W{1'b0}}, 1'b1} <<
                  (DATA_CANONICAL_SHIFT-1))) >> DATA_CANONICAL_SHIFT;
            if (value[DATA_W-1]) begin
                if (rounded_magnitude >=
                        ({{DATA_W{1'b0}}, 1'b1} <<
                         (`RECON_DATA_W-1)))
                    data_value = {1'b1, {`RECON_DATA_W-1{1'b0}}};
                else
                    data_value = -$signed(
                        rounded_magnitude[`RECON_DATA_W-1:0]);
            end else if (rounded_magnitude >
                    {{(DATA_W+1-`RECON_DATA_W){1'b0}},
                     1'b0, {`RECON_DATA_W-1{1'b1}}}) begin
                data_value = {1'b0, {`RECON_DATA_W-1{1'b1}}};
            end else begin
                data_value = rounded_magnitude[`RECON_DATA_W-1:0];
            end
            canonical_data_coefficient =
                $signed({{(DATA_W-`RECON_DATA_W){
                              data_value[`RECON_DATA_W-1]}},
                         data_value}) <<< DATA_CANONICAL_SHIFT;
        end
    endfunction

    reg [3:0] state;
    reg active_bank;
    reg proposal_open;
    reg [6:0] bank_count [0:1];
    reg [6:0] union_index;
    reg [6:0] clone_index;
    reg clone_all_issued;
    reg [6:0] clone_response_slot;
    reg [INDEX_W-1:0] clone_response_atom;
    reg [5:0] clone_response_candidate_slot;
    reg [6:0] active_request_slot;
    reg [4:0] active_operation;
    reg [TAG_W-1:0] active_tag;
    reg [6:0] proposal_preserve_count;
    reg active_cache_from_candidates;
    reg active_candidate_coefficients;
    reg active_zero_candidate_coefficient;
    reg active_defer_activation;
    reg active_sort_by_index;
    reg [6:0] promotion_index;
    reg [WORK_MAX-1:0] proposal_coefficient_written;
    reg request_pending;
    reg [4:0] request_operation_reg;
    reg [TAG_W-1:0] request_tag_reg;
    reg [6:0] request_slot_reg;
    reg request_cache_from_candidates_reg;
    reg request_candidate_coefficients_reg;
    reg request_zero_candidate_coefficient_reg;
    reg request_defer_activation_reg;
    reg request_sort_by_index_reg;
    reg request_scatter_active_reg;
    reg signed [DATA_W-1:0] scatter_coefficient_reg;
    reg [5:0] candidate_slot_state [0:1][0:WORK_MAX-1];
    reg cache_refill_pending_reg;
    reg [6:0] refill_column_slot;

    wire response_advance = !response_valid || response_ready;
    assign cycle_ready = (state == STATE_IDLE) && !response_valid &&
                         !request_pending;
    wire request_capture = cycle_valid && cycle_commit && cycle_ready;
    wire request_accept = request_pending;
    wire proposal_bank = ~active_bank;
    wire view_bank = proposal_view_active ? proposal_bank : active_bank;
    assign transaction_open = proposal_open;
    assign current_bank = active_bank;
    assign current_count = bank_count[active_bank];
    assign proposed_count = bank_count[proposal_bank];
    assign view_count = bank_count[view_bank];

    assign candidate_read_slot =
        ((state == STATE_UNION) || (state == STATE_UNION_WRITE)) ?
        union_index : ((state == STATE_IDLE) ? request_slot_reg :
                       active_request_slot);
    wire selected_candidate_valid = USE_INDEXED_CANDIDATE_READ ?
        candidate_read_valid :
        ((candidate_read_slot < candidate_count) &&
         (candidate_read_slot < CANDIDATE_MAX));
    wire [INDEX_W-1:0] selected_candidate_atom =
        USE_INDEXED_CANDIDATE_READ ? candidate_read_index :
        candidate_indices[candidate_read_slot*INDEX_W +: INDEX_W];
    wire signed [DATA_W-1:0] selected_candidate_value =
        USE_INDEXED_CANDIDATE_READ ? candidate_read_value :
        candidate_values[candidate_read_slot*DATA_W +: DATA_W];
    wire [5:0] selected_candidate_symbol_slot =
        USE_INDEXED_CANDIDATE_READ ? candidate_read_symbol_slot :
        candidate_symbol_slots[candidate_read_slot*6 +: 6];
    reg [6:0] selected_candidate_sorted_slot;
    integer candidate_sort_index;

    always @* begin
        if (USE_INDEXED_CANDIDATE_READ)
            selected_candidate_sorted_slot = candidate_read_sorted_slot;
        else begin
            selected_candidate_sorted_slot = 7'd0;
            for (candidate_sort_index = 0;
                 candidate_sort_index < `RECON_K_MAX;
                 candidate_sort_index = candidate_sort_index + 1) begin
                if ((candidate_sort_index < candidate_count) &&
                    (candidate_indices[candidate_sort_index*INDEX_W +: INDEX_W] <
                     selected_candidate_atom))
                    selected_candidate_sorted_slot =
                        selected_candidate_sorted_slot + 1'b1;
            end
        end
    end

    assign cache_prepare_valid = state == STATE_CACHE_PREPARE;
    assign cache_prepare_from_candidates = active_cache_from_candidates;
    assign cache_prepare_support_count = bank_count[proposal_bank];
    assign cache_prepare_preserve_count = active_cache_from_candidates ?
        proposal_preserve_count : 7'd0;
    assign cache_promote_valid = state == STATE_CACHE_PROMOTE;
    assign cache_promote_candidate_slot = candidate_slot_state[proposal_bank][promotion_index];
    assign cache_promote_support_slot = promotion_index;
    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] proposal_entries = proposal_bank ?
        bank1_entries : bank0_entries;
    assign cache_refill_pending = cache_refill_pending_reg;
    assign cache_refill_support_count = bank_count[proposal_bank];
    assign cache_refill_column_valid = cache_refill_pending_reg &&
        (refill_column_slot < bank_count[proposal_bank]);
    assign cache_refill_column_slot = refill_column_slot;
    assign cache_refill_column = proposal_entries[
        refill_column_slot*(INDEX_W+DATA_W)+DATA_W +: INDEX_W];
    wire cache_refill_column_fire = cache_refill_column_valid &&
        cache_refill_column_ready;

    reg workspace_clear_valid;
    reg workspace_clear_bank;
    reg workspace_write_valid;
    reg workspace_write_bank;
    reg [6:0] workspace_write_slot;
    reg [INDEX_W-1:0] workspace_write_atom;
    reg signed [DATA_W-1:0] workspace_write_coefficient;
    reg workspace_write_atom_enable;
    reg workspace_write_coefficient_enable;
    reg workspace_read_bank;
    reg [6:0] workspace_read_slot;
    reg workspace_query_bank;
    reg [INDEX_W-1:0] workspace_query_atom;
    wire workspace_read_valid;
    wire [INDEX_W-1:0] workspace_read_atom;
    wire workspace_coefficient_scalar_read_valid;
    wire signed [DATA_W-1:0]
        workspace_coefficient_scalar_read_coefficient;
    wire remapper_coefficient_read_enable;
    wire remapper_coefficient_read_current_bank;
    wire [6:0] remapper_coefficient_read_slot;
    wire workspace_query_member;
    wire [6:0] workspace_query_slot;
    wire workspace_membership_query_member;
    wire [6:0] workspace_membership_query_slot;
    wire [2*(1<<INDEX_W)-1:0] unused_bitmaps;
    assign active_support_bitmap = view_bank ?
        unused_bitmaps[(1<<INDEX_W) +: (1<<INDEX_W)] :
        unused_bitmaps[0 +: (1<<INDEX_W)];
    wire [WORK_MAX*(INDEX_W+DATA_W)-1:0] active_entries = view_bank ?
        bank1_entries : bank0_entries;
    genvar active_slot;
    generate
        for (active_slot = 0; active_slot < WORK_MAX;
             active_slot = active_slot + 1) begin : g_active_coefficients
            assign active_support_indices[active_slot*INDEX_W +: INDEX_W] =
                active_entries[active_slot*(INDEX_W+DATA_W)+DATA_W +: INDEX_W];
            assign active_support_coefficients[active_slot*DATA_W +: DATA_W] =
                active_entries[active_slot*(INDEX_W+DATA_W) +: DATA_W];
        end
    endgenerate
    assign membership_query_member = workspace_membership_query_member;
    assign membership_query_slot = workspace_membership_query_slot;

    support_workspace #(
        .DATA_W(DATA_W), .INDEX_W(INDEX_W), .WORK_MAX(WORK_MAX),
        .EXPOSE_BITMAP(EXPOSE_ACTIVE_BITMAP)
    ) u_workspace (
        .clk(clk), .rst_n(rst_n),
        .clear_valid(workspace_clear_valid), .clear_bank(workspace_clear_bank),
        .write_valid(workspace_write_valid), .write_bank(workspace_write_bank),
        .write_slot(workspace_write_slot), .write_atom(workspace_write_atom),
        .write_coefficient(workspace_write_coefficient),
        .write_atom_enable(workspace_write_atom_enable),
        .write_coefficient_enable(workspace_write_coefficient_enable),
        .read_bank(workspace_read_bank), .read_slot(workspace_read_slot),
        .read_valid(workspace_read_valid), .read_atom(workspace_read_atom),
        .read_coefficient(),
        .coefficient_scalar_read_enable(
            remapper_coefficient_read_enable ||
            ((state == STATE_CLONE) && !clone_all_issued &&
             workspace_read_valid) ||
            (request_accept &&
             (request_operation == `RECON_RESOURCE_OP_SUPPORT_GATHER) &&
             request_support_slot_valid &&
             (command_slot < bank_count[active_bank]) &&
             workspace_read_valid)),
        .coefficient_scalar_read_bank(remapper_coefficient_read_enable ?
            (remapper_coefficient_read_current_bank ? active_bank :
                                                       proposal_bank) :
            ((state == STATE_CLONE) ? active_bank : view_bank)),
        .coefficient_scalar_read_slot(remapper_coefficient_read_enable ?
            remapper_coefficient_read_slot :
            ((state == STATE_CLONE) ? clone_index : command_slot)),
        .coefficient_scalar_read_valid(
            workspace_coefficient_scalar_read_valid),
        .coefficient_scalar_read_coefficient(
            workspace_coefficient_scalar_read_coefficient),
        .coefficient_stripe_read_enable(coefficient_stripe_read_enable),
        .coefficient_stripe_read_bank(view_bank),
        .coefficient_stripe_read_index(coefficient_stripe_read_index),
        .coefficient_stripe_read_valid(coefficient_stripe_read_valid),
        .coefficient_stripe_read_coefficients(
            coefficient_stripe_read_coefficients),
        .query_bank(workspace_query_bank), .query_atom(workspace_query_atom),
        .query_member(workspace_query_member), .query_slot(workspace_query_slot),
        .membership_query_bank(view_bank),
        .membership_query_atom(membership_query_atom),
        .membership_query_member(workspace_membership_query_member),
        .membership_query_slot(workspace_membership_query_slot),
        .bank0_entries(bank0_entries), .bank1_entries(bank1_entries),
        .bank0_slot_valid(bank0_slot_valid), .bank1_slot_valid(bank1_slot_valid),
        .debug_bitmaps(unused_bitmaps)
    );

    wire remap_start_ready;
    wire remap_done_valid;
    wire remap_fault;
    wire remap_coefficient_valid;
    wire [6:0] remap_coefficient_slot;
    wire signed [DATA_W-1:0] remap_coefficient;
    wire [6:0] remapper_dropped_count;
    wire [WORK_MAX*INDEX_W-1:0] remapper_dropped_indices;
    wire [WORK_MAX*DATA_W-1:0] remapper_dropped_coefficients;
    wire remapper_query_valid;
    wire remapper_query_current_bank;
    wire [INDEX_W-1:0] remapper_query_atom;
    wire remapper_read_current_bank;
    wire [6:0] remapper_read_slot;
    wire remapper_cancel = routine_start || abort_transaction || certificate_fail;
    assign remap_dropped_count = remapper_dropped_count;
    assign remap_dropped_indices = remapper_dropped_indices;
    assign remap_dropped_coefficients = remapper_dropped_coefficients;

    support_coefficient_remapper #(.DATA_W(DATA_W), .INDEX_W(INDEX_W),
        .WORK_MAX(WORK_MAX)) u_remapper (
        .clk(clk), .rst_n(rst_n), .cancel(remapper_cancel),
        .start_valid(state == STATE_REMAP_START), .start_ready(remap_start_ready),
        .current_count(bank_count[active_bank]),
        .proposed_count(bank_count[proposal_bank]),
        .read_current_bank(remapper_read_current_bank),
        .read_slot(remapper_read_slot),
        .read_atom(workspace_read_atom),
        .coefficient_read_enable(remapper_coefficient_read_enable),
        .coefficient_read_current_bank(
            remapper_coefficient_read_current_bank),
        .coefficient_read_slot(remapper_coefficient_read_slot),
        .coefficient_read_valid(workspace_coefficient_scalar_read_valid),
        .coefficient_read_data(
            workspace_coefficient_scalar_read_coefficient),
        .query_valid(remapper_query_valid),
        .query_current_bank(remapper_query_current_bank),
        .query_atom(remapper_query_atom),
        .query_member(workspace_query_member),
        .query_slot(workspace_query_slot),
        .done_valid(remap_done_valid), .done_ready(state == STATE_REMAP_WAIT),
        .fault(remap_fault),
        .remap_coefficient_valid(remap_coefficient_valid),
        .remap_coefficient_slot(remap_coefficient_slot),
        .remap_coefficient(remap_coefficient),
        .dropped_count(remapper_dropped_count),
        .dropped_indices(remapper_dropped_indices),
        .dropped_coefficients(remapper_dropped_coefficients)
    );

    wire [4:0] request_operation = request_operation_reg;
    wire [TAG_W-1:0] command_tag = request_tag_reg;
    wire [6:0] command_slot = request_slot_reg;
    wire command_cache_from_candidates = request_cache_from_candidates_reg;
    wire command_candidate_coefficients = request_candidate_coefficients_reg;
    wire command_zero_candidate_coefficient = request_zero_candidate_coefficient_reg;
    wire command_defer_activation = request_defer_activation_reg;
    wire command_sort_by_index = request_sort_by_index_reg;
    wire command_scatter_active = request_scatter_active_reg;
    wire signed [DATA_W-1:0] command_scatter_coefficient = scatter_coefficient_reg;
    wire request_is_support = (request_operation >= `RECON_RESOURCE_OP_SUPPORT_CLEAR) &&
                              (request_operation <= `RECON_RESOURCE_OP_SUPPORT_ROLLBACK);
    wire request_candidate_slot_valid = (command_slot < CANDIDATE_MAX) &&
                                        (command_slot < candidate_count);
    wire request_support_slot_valid = command_slot < WORK_MAX;

    always @* begin
        workspace_clear_valid = 0;
        workspace_clear_bank = proposal_bank;
        workspace_write_valid = 0;
        workspace_write_bank = proposal_bank;
        workspace_write_slot = bank_count[proposal_bank];
        workspace_write_atom = selected_candidate_atom;
        workspace_write_coefficient = selected_candidate_value;
        workspace_write_atom_enable = 0;
        workspace_write_coefficient_enable = 0;
        workspace_read_bank = view_bank;
        workspace_read_slot = (state == STATE_CLONE) ? clone_index : command_slot;
        workspace_query_bank = (state == STATE_IDLE) ? view_bank : proposal_bank;
        workspace_query_atom = selected_candidate_atom;

        if (state == STATE_CLONE)
            workspace_read_bank = active_bank;
        if (state == STATE_REMAP_WAIT) begin
            workspace_read_bank = remapper_read_current_bank ? active_bank : proposal_bank;
            workspace_read_slot = remapper_read_slot;
        end
        if ((state == STATE_REMAP_WAIT) && remapper_query_valid) begin
            workspace_query_bank = remapper_query_current_bank ? active_bank : proposal_bank;
            workspace_query_atom = remapper_query_atom;
        end

        if (request_accept && !cache_refill_pending_reg &&
            ((request_operation == `RECON_RESOURCE_OP_SUPPORT_CLEAR) ||
            ((request_operation == `RECON_RESOURCE_OP_SUPPORT_APPEND) && !proposal_open) ||
            ((request_operation == `RECON_RESOURCE_OP_SUPPORT_UNION) &&
             !proposal_open)))
            workspace_clear_valid = 1;
        if ((state == STATE_CLONE) &&
            workspace_coefficient_scalar_read_valid) begin
            workspace_write_valid = 1;
            workspace_write_slot = clone_response_slot;
            workspace_write_atom = clone_response_atom;
            workspace_write_coefficient =
                workspace_coefficient_scalar_read_coefficient;
            workspace_write_atom_enable = 1;
            workspace_write_coefficient_enable = 1;
        end
        if ((state == STATE_APPEND_WRITE) && selected_candidate_valid &&
            (bank_count[proposal_bank] < WORK_MAX)) begin
            workspace_write_valid = 1;
            workspace_write_atom_enable = 1;
            workspace_write_coefficient = active_zero_candidate_coefficient ?
                {DATA_W{1'b0}} :
                (active_candidate_coefficients ?
                 canonical_data_coefficient(selected_candidate_value) :
                 selected_candidate_value);
            workspace_write_coefficient_enable = 1;
        end
        if ((state == STATE_UNION_WRITE) && selected_candidate_valid &&
            (bank_count[proposal_bank] < WORK_MAX)) begin
            workspace_write_valid = 1;
            if (active_sort_by_index)
                workspace_write_slot = selected_candidate_sorted_slot;
            workspace_write_atom_enable = 1;
            workspace_write_coefficient = active_candidate_coefficients ?
                canonical_data_coefficient(selected_candidate_value) :
                selected_candidate_value;
            workspace_write_coefficient_enable = 1;
        end
        if (request_accept && (request_operation == `RECON_RESOURCE_OP_SUPPORT_SCATTER) &&
            request_support_slot_valid &&
            (command_scatter_active ?
             (command_slot < bank_count[active_bank]) :
             (proposal_open && (command_slot < bank_count[proposal_bank])))) begin
            workspace_write_valid = 1;
            workspace_write_bank = command_scatter_active ? active_bank : proposal_bank;
            workspace_write_slot = command_slot;
            workspace_write_atom = 0;
            workspace_write_coefficient = command_scatter_active ||
                (bank_count[proposal_bank] <= bank_count[active_bank]) ?
                canonical_data_coefficient(command_scatter_coefficient) :
                command_scatter_coefficient;
            workspace_write_atom_enable = 0;
            workspace_write_coefficient_enable = 1;
        end
        if ((state == STATE_REMAP_WAIT) && remap_coefficient_valid &&
            !proposal_coefficient_written[remap_coefficient_slot]) begin
            workspace_write_valid = 1;
            workspace_write_slot = remap_coefficient_slot;
            workspace_write_atom = 0;
            workspace_write_coefficient = remap_coefficient;
            workspace_write_atom_enable = 0;
            workspace_write_coefficient_enable = 1;
        end
        if (request_accept && (request_operation == `RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP)) begin
            workspace_query_bank = active_bank;
            workspace_query_atom = request_candidate_slot_valid ?
                selected_candidate_atom : 0;
        end
    end

    task set_response;
        input [4:0] response_op;
        input [TAG_W-1:0] response_request_tag;
        input response_has_fault;
        input [6:0] response_support_count;
        begin
            response_valid <= 1;
            response_operation <= response_op;
            response_tag <= response_request_tag;
            response_fault <= response_has_fault;
            response_count <= response_support_count;
        end
    endtask

    integer reset_index;
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            active_bank <= 0;
            proposal_open <= 0;
            bank_count[0] <= 0;
            bank_count[1] <= 0;
            union_index <= 0;
            clone_index <= 0;
            clone_all_issued <= 1'b0;
            clone_response_slot <= 7'd0;
            clone_response_atom <= {INDEX_W{1'b0}};
            clone_response_candidate_slot <= 6'd0;
            active_request_slot <= 0;
            active_operation <= 0;
            active_tag <= 0;
            proposal_preserve_count <= 0;
            active_cache_from_candidates <= 1'b1;
            active_candidate_coefficients <= 1'b0;
            active_zero_candidate_coefficient <= 1'b0;
            active_defer_activation <= 1'b0;
            active_sort_by_index <= 1'b0;
            proposal_view_active <= 1'b0;
            promotion_index <= 0;
            proposal_coefficient_written <= 0;
            request_pending <= 1'b0;
            request_operation_reg <= 5'd0;
            request_tag_reg <= {TAG_W{1'b0}};
            request_slot_reg <= 7'd0;
            request_cache_from_candidates_reg <= 1'b0;
            request_candidate_coefficients_reg <= 1'b0;
            request_zero_candidate_coefficient_reg <= 1'b0;
            request_defer_activation_reg <= 1'b0;
            request_sort_by_index_reg <= 1'b0;
            request_scatter_active_reg <= 1'b0;
            scatter_coefficient_reg <= {DATA_W{1'b0}};
            cache_refill_pending_reg <= 1'b0;
            refill_column_slot <= 7'd0;
            remap_event_valid <= 0;
            remap_event_fault <= 0;
            cache_invalidate <= 0;
            response_valid <= 0;
            append_gradient_valid <= 1'b0;
            append_gradient_slot <= 7'd0;
            append_gradient_value <= {DATA_W{1'b0}};
            response_operation <= 0;
            response_tag <= 0;
            response_fault <= 0;
            response_count <= 0;
            response_member <= 0;
            response_slot <= 0;
            response_atom <= 0;
            response_coefficient <= 0;
            rollback_count <= 0;
            rollback_cycle_count <= 0;
        end else begin
            append_gradient_valid <= 1'b0;
            cache_invalidate <= 1'b0;
            remap_event_valid <= 1'b0;
            if (request_accept)
                request_pending <= 1'b0;
            if (request_capture) begin
                request_pending <= 1'b1;
                request_operation_reg <= operation;
                request_tag_reg <= request_tag;
                request_slot_reg <= request_slot;
                request_cache_from_candidates_reg <= request_cache_from_candidates;
                request_candidate_coefficients_reg <= request_candidate_coefficients;
                request_zero_candidate_coefficient_reg <= request_zero_candidate_coefficient;
                request_defer_activation_reg <= request_defer_activation;
                request_sort_by_index_reg <= request_sort_by_index;
                request_scatter_active_reg <= request_scatter_active;
                scatter_coefficient_reg <= scatter_coefficient;
            end
            if (response_valid && response_ready)
                response_valid <= 0;
            if (routine_start) begin
                state <= STATE_IDLE;
                request_pending <= 1'b0;
                response_valid <= 0;
                cache_invalidate <= cache_refill_pending_reg;
                proposal_coefficient_written <= 0;
                clone_all_issued <= 1'b0;
                cache_refill_pending_reg <= 1'b0;
                refill_column_slot <= 7'd0;
                proposal_view_active <= 1'b0;
                if (proposal_open) begin
                    proposal_open <= 0;
                    rollback_count <= rollback_count + 1'b1;
                    rollback_cycle_count <= rollback_cycle_count + 1'b1;
                end
            end else if (abort_transaction || certificate_fail) begin
                state <= STATE_IDLE;
                request_pending <= 1'b0;
                cache_invalidate <= 1'b1;
                proposal_coefficient_written <= 0;
                clone_all_issued <= 1'b0;
                cache_refill_pending_reg <= 1'b0;
                refill_column_slot <= 7'd0;
                proposal_view_active <= 1'b0;
                if (proposal_open) begin
                    proposal_open <= 0;
                    rollback_count <= rollback_count + 1'b1;
                    rollback_cycle_count <= rollback_cycle_count + 1'b1;
                end
                if (state != STATE_IDLE)
                    set_response(active_operation, active_tag, 1,
                                 bank_count[active_bank]);
                else
                    response_valid <= 0;
            end else begin
                if (request_accept) begin
                    response_member <= 0;
                    response_slot <= 0;
                    response_atom <= 0;
                    response_coefficient <= 0;
                    case (request_operation)
                        `RECON_RESOURCE_OP_SUPPORT_CLEAR: begin
                            if (cache_refill_pending_reg)
                                set_response(request_operation, command_tag, 1,
                                             bank_count[active_bank]);
                            else begin
                                if (!command_defer_activation)
                                    proposal_view_active <= 1'b0;
                                bank_count[proposal_bank] <= 0;
                                proposal_preserve_count <= 0;
                                proposal_coefficient_written <= 0;
                                proposal_open <= 1;
                                set_response(request_operation, command_tag, 0, 0);
                            end
                        end
                        `RECON_RESOURCE_OP_SUPPORT_APPEND: begin
                            if (cache_refill_pending_reg)
                                set_response(request_operation, command_tag, 1,
                                             bank_count[active_bank]);
                            else begin
                                proposal_open <= 1;
                                active_request_slot <= command_slot;
                                active_candidate_coefficients <=
                                    command_candidate_coefficients;
                                active_zero_candidate_coefficient <=
                                    command_zero_candidate_coefficient;
                                active_operation <= request_operation;
                                active_tag <= command_tag;
                                if (proposal_open)
                                    state <= STATE_APPEND;
                                else begin
                                    proposal_preserve_count <= bank_count[active_bank];
                                    proposal_coefficient_written <= 0;
                                    bank_count[proposal_bank] <= 0;
                                    clone_index <= 0;
                                    clone_all_issued <= 1'b0;
                                    state <= (bank_count[active_bank] == 0) ? STATE_APPEND : STATE_CLONE;
                                end
                            end
                        end
                        `RECON_RESOURCE_OP_SUPPORT_UNION: begin
                            if (cache_refill_pending_reg)
                                set_response(request_operation, command_tag, 1,
                                             bank_count[active_bank]);
                            else begin
                                bank_count[proposal_bank] <= proposal_open ?
                                    bank_count[proposal_bank] : 7'd0;
                                if (!proposal_open)
                                    proposal_preserve_count <= bank_count[active_bank];
                                proposal_coefficient_written <= 0;
                                proposal_open <= 1;
                                union_index <= 0;
                                clone_index <= 0;
                                clone_all_issued <= 1'b0;
                                active_candidate_coefficients <=
                                    command_candidate_coefficients;
                                active_zero_candidate_coefficient <= 1'b0;
                                active_sort_by_index <= command_sort_by_index;
                                active_operation <= request_operation;
                                active_tag <= command_tag;
                                if (candidate_count > CANDIDATE_MAX)
                                    set_response(request_operation, command_tag, 1, bank_count[active_bank]);
                                else if (candidate_count == 0)
                                    set_response(request_operation, command_tag, 0,
                                        proposal_open ? bank_count[proposal_bank] :
                                                        bank_count[active_bank]);
                                else if (proposal_open || (bank_count[active_bank] == 0))
                                    state <= STATE_UNION;
                                else
                                    state <= STATE_CLONE;
                            end
                        end
                        `RECON_RESOURCE_OP_SUPPORT_MEMBERSHIP: begin
                            response_member <= request_candidate_slot_valid && workspace_query_member;
                            response_slot <= workspace_query_slot;
                            response_atom <= request_candidate_slot_valid ?
                                selected_candidate_atom : 0;
                            set_response(request_operation, command_tag,
                                         !request_candidate_slot_valid, bank_count[active_bank]);
                        end
                        `RECON_RESOURCE_OP_SUPPORT_GATHER: begin
                            if (!request_support_slot_valid ||
                                (command_slot >= bank_count[active_bank]) ||
                                !workspace_read_valid) begin
                                set_response(request_operation, command_tag, 1'b1,
                                             bank_count[active_bank]);
                            end else begin
                                response_atom <= workspace_read_atom;
                                response_slot <= command_slot;
                                active_operation <= request_operation;
                                active_tag <= command_tag;
                                state <= STATE_GATHER_WAIT;
                            end
                        end
                        `RECON_RESOURCE_OP_SUPPORT_SCATTER: begin
                            response_slot <= command_slot;
                            response_coefficient <= command_scatter_coefficient;
                            set_response(request_operation, command_tag,
                                         cache_refill_pending_reg ||
                                         (!command_scatter_active && !proposal_open) ||
                                         !request_support_slot_valid ||
                                         (command_slot >= bank_count[
                                            command_scatter_active ? active_bank :
                                                                     proposal_bank]),
                                         bank_count[command_scatter_active ?
                                                    active_bank : proposal_bank]);
                            if (!command_scatter_active &&
                                !cache_refill_pending_reg && proposal_open &&
                                request_support_slot_valid &&
                                (command_slot < bank_count[proposal_bank]))
                                proposal_coefficient_written[command_slot] <= 1'b1;
                        end
                        `RECON_RESOURCE_OP_SUPPORT_COMMIT: begin
                            if (proposal_view_active && proposal_open &&
                                !cache_refill_pending_reg &&
                                !command_defer_activation) begin
                                active_bank <= proposal_bank;
                                proposal_open <= 1'b0;
                                proposal_view_active <= 1'b0;
                                proposal_coefficient_written <= 0;
                                remap_event_valid <= 1'b1;
                                remap_event_fault <= 1'b0;
                                set_response(request_operation, command_tag, 0,
                                             bank_count[proposal_bank]);
                            end else if (proposal_open && cache_refill_pending_reg) begin
                                if (cache_fault) begin
                                    proposal_open <= 1'b0;
                                    cache_refill_pending_reg <= 1'b0;
                                    proposal_coefficient_written <= 0;
                                    cache_invalidate <= 1'b1;
                                    set_response(request_operation, command_tag, 1,
                                                 bank_count[active_bank]);
                                end else if (cache_valid) begin
                                    if (command_defer_activation)
                                        proposal_view_active <= 1'b1;
                                    else begin
                                        active_bank <= proposal_bank;
                                        proposal_open <= 1'b0;
                                    end
                                    cache_refill_pending_reg <= 1'b0;
                                    proposal_coefficient_written <= 0;
                                    remap_event_valid <= 1'b1;
                                    remap_event_fault <= 1'b0;
                                    set_response(request_operation, command_tag, 0,
                                                 bank_count[proposal_bank]);
                                end else begin
                                    set_response(request_operation, command_tag, 1,
                                                 bank_count[active_bank]);
                                end
                            end else if (proposal_open) begin
                                active_operation <= request_operation;
                                active_tag <= command_tag;
                                active_cache_from_candidates <=
                                    command_cache_from_candidates;
                                active_defer_activation <=
                                    command_defer_activation;
                                state <= STATE_REMAP_START;
                            end else
                                set_response(request_operation, command_tag, 1,
                                             bank_count[active_bank]);
                        end
                        `RECON_RESOURCE_OP_SUPPORT_ROLLBACK: begin
                            if (proposal_open) begin
                                proposal_open <= 0;
                                proposal_view_active <= 1'b0;
                                if (cache_refill_pending_reg)
                                    cache_invalidate <= 1'b1;
                                cache_refill_pending_reg <= 1'b0;
                                proposal_coefficient_written <= 0;
                                rollback_count <= rollback_count + 1'b1;
                                rollback_cycle_count <= rollback_cycle_count + 1'b1;
                                set_response(request_operation, command_tag, 0,
                                             bank_count[active_bank]);
                            end else
                                set_response(request_operation, command_tag, 1,
                                             bank_count[active_bank]);
                        end
                        default: set_response(request_operation, command_tag,
                                              !request_is_support, bank_count[active_bank]);
                    endcase
                end

                if ((state == STATE_APPEND_WRITE) && selected_candidate_valid &&
                    (bank_count[proposal_bank] < WORK_MAX)) begin
                    candidate_slot_state[proposal_bank][bank_count[proposal_bank]] <=
                        selected_candidate_symbol_slot;
                    if (active_candidate_coefficients)
                        proposal_coefficient_written[bank_count[proposal_bank]] <= 1'b1;
                end
                if ((state == STATE_UNION_WRITE) && selected_candidate_valid &&
                    (bank_count[proposal_bank] < WORK_MAX)) begin
                    candidate_slot_state[proposal_bank][active_sort_by_index ?
                        selected_candidate_sorted_slot : bank_count[proposal_bank]] <=
                        selected_candidate_symbol_slot;
                    if (active_candidate_coefficients)
                        proposal_coefficient_written[active_sort_by_index ?
                            selected_candidate_sorted_slot :
                            bank_count[proposal_bank]] <= 1'b1;
                end

                if (state == STATE_CLONE) begin
                    if (!clone_all_issued && !workspace_read_valid) begin
                        set_response(active_operation, active_tag, 1, bank_count[proposal_bank]);
                        clone_all_issued <= 1'b0;
                        state <= STATE_IDLE;
                    end else begin
                        if (!clone_all_issued) begin
                            clone_response_slot <= clone_index;
                            clone_response_atom <= workspace_read_atom;
                            clone_response_candidate_slot <=
                                candidate_slot_state[active_bank][clone_index];
                            if (clone_index + 1'b1 == bank_count[active_bank])
                                clone_all_issued <= 1'b1;
                            else
                                clone_index <= clone_index + 1'b1;
                        end
                        if (workspace_coefficient_scalar_read_valid) begin
                            bank_count[proposal_bank] <=
                                bank_count[proposal_bank] + 1'b1;
                            candidate_slot_state[proposal_bank][clone_response_slot] <=
                                clone_response_candidate_slot;
                            if (clone_response_slot + 1'b1 ==
                                bank_count[active_bank]) begin
                                clone_index <= 0;
                                clone_all_issued <= 1'b0;
                                if (active_operation ==
                                    `RECON_RESOURCE_OP_SUPPORT_APPEND)
                                    state <= STATE_APPEND;
                                else if (candidate_count == 0) begin
                                    set_response(active_operation, active_tag, 0,
                                                 bank_count[proposal_bank] + 1'b1);
                                    state <= STATE_IDLE;
                                end else
                                    state <= STATE_UNION;
                            end
                        end
                    end
                end

                if ((state == STATE_GATHER_WAIT) &&
                    workspace_coefficient_scalar_read_valid) begin
                    response_coefficient <=
                        workspace_coefficient_scalar_read_coefficient;
                    set_response(active_operation, active_tag, 1'b0,
                                 bank_count[active_bank]);
                    state <= STATE_IDLE;
                end

                if (state == STATE_APPEND) begin
                    if (!selected_candidate_valid) begin
                        set_response(active_operation, active_tag, 1, bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end else if (!workspace_query_member && (bank_count[proposal_bank] >= WORK_MAX)) begin
                        set_response(active_operation, active_tag, 1, bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end else if (!workspace_query_member) begin
                        state <= STATE_APPEND_WRITE;
                    end else begin
                        set_response(active_operation, active_tag, 0,
                                     bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end
                end

                if (state == STATE_APPEND_WRITE) begin
                    bank_count[proposal_bank] <= bank_count[proposal_bank] + 1'b1;
                    append_gradient_valid <= 1'b1;
                    append_gradient_slot <= bank_count[proposal_bank];
                    append_gradient_value <= selected_candidate_value;
                    set_response(active_operation, active_tag, 0,
                                 bank_count[proposal_bank] + 1'b1);
                    state <= STATE_IDLE;
                end

                if (state == STATE_UNION) begin
                    if (!selected_candidate_valid) begin
                        set_response(active_operation, active_tag, 1, bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end else if (!workspace_query_member && (bank_count[proposal_bank] >= WORK_MAX)) begin
                        set_response(active_operation, active_tag, 1, bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end else if (!workspace_query_member) begin
                        state <= STATE_UNION_WRITE;
                    end else begin
                        if (union_index + 1'b1 == candidate_count) begin
                            set_response(active_operation, active_tag, 0,
                                         bank_count[proposal_bank]);
                            state <= STATE_IDLE;
                        end else
                            union_index <= union_index + 1'b1;
                    end
                end

                if (state == STATE_UNION_WRITE) begin
                    bank_count[proposal_bank] <= bank_count[proposal_bank] + 1'b1;
                    append_gradient_valid <= 1'b1;
                    append_gradient_slot <= active_sort_by_index ?
                        selected_candidate_sorted_slot : bank_count[proposal_bank];
                    append_gradient_value <= selected_candidate_value;
                    if (union_index + 1'b1 == candidate_count) begin
                        set_response(active_operation, active_tag, 0,
                                     bank_count[proposal_bank] + 1'b1);
                        state <= STATE_IDLE;
                    end else begin
                        union_index <= union_index + 1'b1;
                        state <= STATE_UNION;
                    end
                end

                if ((state == STATE_REMAP_START) && remap_start_ready)
                    state <= STATE_REMAP_WAIT;

                if ((state == STATE_REMAP_WAIT) && remap_done_valid) begin
                    if (remap_fault) begin
                        proposal_open <= 1'b0;
                        proposal_coefficient_written <= 0;
                        rollback_count <= rollback_count + 1'b1;
                        rollback_cycle_count <= rollback_cycle_count + 1'b1;
                        cache_invalidate <= 1'b1;
                        remap_event_valid <= 1'b1;
                        remap_event_fault <= 1'b1;
                        set_response(active_operation, active_tag, 1,
                                     bank_count[active_bank]);
                        state <= STATE_IDLE;
                    end else begin
                        state <= STATE_CACHE_PREPARE;
                    end
                end

                if ((state == STATE_CACHE_PREPARE) && cache_prepare_ready) begin
                    if (!active_cache_from_candidates) begin
                        cache_refill_pending_reg <= 1'b1;
                        refill_column_slot <= 7'd0;
                        set_response(active_operation, active_tag, 0,
                                     bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end else if (bank_count[proposal_bank] == proposal_preserve_count)
                        state <= STATE_CACHE_WAIT;
                    else begin
                        promotion_index <= proposal_preserve_count;
                        state <= STATE_CACHE_PROMOTE;
                    end
                end

                if ((state == STATE_CACHE_PROMOTE) && cache_promote_ready) begin
                    if (promotion_index + 1'b1 == bank_count[proposal_bank])
                        state <= STATE_CACHE_WAIT;
                    else
                        promotion_index <= promotion_index + 1'b1;
                end

                if (state == STATE_CACHE_WAIT) begin
                    if (cache_fault) begin
                        proposal_open <= 1'b0;
                        proposal_view_active <= 1'b0;
                        proposal_coefficient_written <= 0;
                        cache_invalidate <= 1'b1;
                        set_response(active_operation, active_tag, 1, bank_count[active_bank]);
                        state <= STATE_IDLE;
                    end else if (cache_valid) begin
                        if (active_defer_activation)
                            proposal_view_active <= 1'b1;
                        else begin
                            active_bank <= proposal_bank;
                            proposal_open <= 1'b0;
                        end
                        proposal_coefficient_written <= 0;
                        remap_event_valid <= 1'b1;
                        remap_event_fault <= 1'b0;
                        set_response(active_operation, active_tag, 0, bank_count[proposal_bank]);
                        state <= STATE_IDLE;
                    end
                end

                if (cache_refill_column_fire)
                    refill_column_slot <= refill_column_slot + 1'b1;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_response_stalled;
    reg [4:0] f_response_operation;
    reg [TAG_W-1:0] f_response_tag;
    reg f_response_fault;
    reg [6:0] f_response_count;
    reg f_active_bank;
    initial f_past_valid = 0;
    always @(posedge clk) begin
        if (rst_n && f_past_valid) begin
            assert(bank_count[0] <= WORK_MAX);
            assert(bank_count[1] <= WORK_MAX);
            if (f_response_stalled) begin
                assert(response_valid);
                assert(response_operation == f_response_operation);
                assert(response_tag == f_response_tag);
                assert(response_fault == f_response_fault);
                assert(response_count == f_response_count);
            end
            if ((active_bank != f_active_bank))
                assert(response_valid && (response_operation == `RECON_RESOURCE_OP_SUPPORT_COMMIT));
        end
        f_past_valid <= 1;
        f_response_stalled <= response_valid && !response_ready;
        f_response_operation <= response_operation;
        f_response_tag <= response_tag;
        f_response_fault <= response_fault;
        f_response_count <= response_count;
        f_active_bank <= active_bank;
    end
`endif
endmodule

`default_nettype wire
