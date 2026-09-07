`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Converts three logical vector streams into at most two atomic scratchpad
// accesses. Read A always owns scratchpad port 0 and read B always owns port 1;
// a write uses the unused port. This fixed ownership makes response tagging
// structural and permits one read stripe/cycle after the initial BRAM fill.
module vector_stream_engine #(
    parameter integer BANK_COUNT = `RECON_VECTOR_MEMORY_BANKS,
    parameter integer BANK_DEPTH = `RECON_MEMORY_BANK_DEPTH,
    parameter integer BANK_WORD_W = `RECON_MEMORY_BANK_WORD_W,
    parameter integer ADDR_W = 9
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         routine_start,
    input  wire                         cursor_restart_valid,
    input  wire [2:0]                   cursor_restart_mask,
    output wire                         cursor_restart_ready,

    input  wire                         req_valid,
    input  wire                         cycle_commit,
    input  wire                         vec_a_en,
    input  wire                         vec_b_en,
    input  wire                         vec_w_en,
    input  wire                         vec_a_restart,
    input  wire                         vec_b_restart,
    input  wire [5:0]                   vec_cfg_a,
    input  wire [5:0]                   vec_cfg_b,
    input  wire [5:0]                   vec_cfg_w,

    input  wire                         cfg_a_valid,
    input  wire [63:0]                  cfg_a,
    input  wire                         cfg_b_valid,
    input  wire [63:0]                  cfg_b,
    input  wire                         cfg_w_valid,
    input  wire [63:0]                  cfg_w,
    input  wire [BANK_COUNT*BANK_WORD_W-1:0] vec_w_data,

    output wire                         stream_in_ready,
    output wire                         stream_out_ready,
    output wire                         cfg_error,
    output wire                         access_conflict,
    output wire                         vec_a_valid,
    output wire [BANK_COUNT*BANK_WORD_W-1:0] vec_a_data,
    output wire                         vec_a_metadata_valid,
    output wire [2:0]                   vec_a_element_format,
    output wire [2:0]                   vec_a_packing_mode,
    output wire [15:0]                  vec_a_element_count,
    output wire                         vec_b_valid,
    output wire [BANK_COUNT*BANK_WORD_W-1:0] vec_b_data,
    output wire                         vec_b_metadata_valid,
    output wire [2:0]                   vec_b_element_format,
    output wire [2:0]                   vec_b_packing_mode,

    output reg                          sp0_valid,
    input  wire                         sp0_ready,
    output reg                          sp0_write,
    output reg  [BANK_COUNT-1:0]        sp0_bank_mask,
    output reg  [BANK_COUNT*ADDR_W-1:0] sp0_addr,
    output reg  [BANK_COUNT*BANK_WORD_W-1:0]
                                                sp0_wr_data,
    input  wire                         sp0_rd_valid,
    input  wire [BANK_COUNT-1:0]        sp0_rd_bank_mask,
    input  wire [BANK_COUNT*BANK_WORD_W-1:0]
                                                sp0_rd_data,

    output reg                          sp1_valid,
    input  wire                         sp1_ready,
    output reg                          sp1_write,
    output reg  [BANK_COUNT-1:0]        sp1_bank_mask,
    output reg  [BANK_COUNT*ADDR_W-1:0] sp1_addr,
    output reg  [BANK_COUNT*BANK_WORD_W-1:0]
                                                sp1_wr_data,
    input  wire                         sp1_rd_valid,
    input  wire [BANK_COUNT-1:0]        sp1_rd_bank_mask,
    input  wire [BANK_COUNT*BANK_WORD_W-1:0]
                                                sp1_rd_data,
    input  wire                         sp_conflict
);
    localparam integer STRIPE_W = BANK_COUNT * BANK_WORD_W;

    function packing_format_legal;
        input [2:0] element_format;
        input [2:0] packing_mode;
        begin
            packing_format_legal =
                ((element_format == `RECON_ELEMENT_FORMAT_DATA18) &&
                 (packing_mode == `RECON_PACKING_MODE_FOUR)) ||
                ((element_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
                 (packing_mode == `RECON_PACKING_MODE_TWO)) ||
                ((element_format == `RECON_ELEMENT_FORMAT_INDEX10) &&
                 (packing_mode == `RECON_PACKING_MODE_SEVEN)) ||
                (((element_format == `RECON_ELEMENT_FORMAT_RAW32) ||
                  (element_format == `RECON_ELEMENT_FORMAT_RAW64)) &&
                 (packing_mode == `RECON_PACKING_MODE_RAW72));
        end
    endfunction

    function configuration_legal;
        input [63:0] configuration;
        input require_read;
        input require_write;
        reg [4:0] bank_limit;
        begin
            bank_limit = {2'd0, configuration[46:44]} +
                         (5'd1 << configuration[48:47]);
            configuration_legal =
                !configuration[63] &&
                (configuration[62:61] ==
                    `RECON_MEMORY_SPACE_VECTOR_SCRATCHPAD) &&
                (!require_read || configuration[58]) &&
                (!require_write || configuration[59]) &&
                (configuration[31:16] != 16'd0) &&
                (configuration[15:0] < BANK_DEPTH) &&
                (configuration[43:32] < BANK_DEPTH) &&
                (bank_limit <= BANK_COUNT) &&
                (configuration[51:49] <= `RECON_BANK_MODE_PING_PONG) &&
                packing_format_legal(configuration[54:52],
                                     configuration[57:55]);
        end
    endfunction

    function [BANK_COUNT-1:0] configuration_bank_mask;
        input [63:0] configuration;
        integer mask_index;
        integer first_bank;
        integer selected_count;
        begin
            configuration_bank_mask = {BANK_COUNT{1'b0}};
            first_bank = configuration[46:44];
            selected_count = 1 << configuration[48:47];
            for (mask_index = 0; mask_index < BANK_COUNT;
                    mask_index = mask_index + 1)
                if ((mask_index >= first_bank) &&
                        (mask_index < first_bank + selected_count))
                    configuration_bank_mask[mask_index] = 1'b1;
        end
    endfunction

    function [6:0] cfg_elements_per_stripe;
        input [63:0] configuration;
        begin
            case ({configuration[57:55], configuration[48:47]})
                {`RECON_PACKING_MODE_TWO, 2'd0}:
                    cfg_elements_per_stripe = 7'd2;
                {`RECON_PACKING_MODE_TWO, 2'd1}:
                    cfg_elements_per_stripe = 7'd4;
                {`RECON_PACKING_MODE_TWO, 2'd2}:
                    cfg_elements_per_stripe = 7'd8;
                {`RECON_PACKING_MODE_TWO, 2'd3}:
                    cfg_elements_per_stripe = 7'd16;
                {`RECON_PACKING_MODE_FOUR, 2'd0}:
                    cfg_elements_per_stripe = 7'd4;
                {`RECON_PACKING_MODE_FOUR, 2'd1}:
                    cfg_elements_per_stripe = 7'd8;
                {`RECON_PACKING_MODE_FOUR, 2'd2}:
                    cfg_elements_per_stripe = 7'd16;
                {`RECON_PACKING_MODE_FOUR, 2'd3}:
                    cfg_elements_per_stripe = 7'd32;
                {`RECON_PACKING_MODE_SEVEN, 2'd0}:
                    cfg_elements_per_stripe = 7'd7;
                {`RECON_PACKING_MODE_SEVEN, 2'd1}:
                    cfg_elements_per_stripe = 7'd14;
                {`RECON_PACKING_MODE_SEVEN, 2'd2}:
                    cfg_elements_per_stripe = 7'd28;
                {`RECON_PACKING_MODE_SEVEN, 2'd3}:
                    cfg_elements_per_stripe = 7'd56;
                default: begin
                    case (configuration[48:47])
                        2'd0: cfg_elements_per_stripe = 7'd1;
                        2'd1: cfg_elements_per_stripe = 7'd2;
                        2'd2: cfg_elements_per_stripe = 7'd4;
                        default: cfg_elements_per_stripe = 7'd8;
                    endcase
                end
            endcase
        end
    endfunction

    function [15:0] elements_after_stripe;
        input [15:0] element_count;
        input [6:0] elements_per_stripe;
        begin
            elements_after_stripe =
                (element_count > {9'd0, elements_per_stripe}) ?
                element_count - {9'd0, elements_per_stripe} : 16'd0;
        end
    endfunction

    function [BANK_COUNT*ADDR_W-1:0] replicated_address;
        input [ADDR_W-1:0] address;
        integer bank_index;
        begin
            replicated_address = {BANK_COUNT*ADDR_W{1'b0}};
            for (bank_index = 0; bank_index < BANK_COUNT;
                    bank_index = bank_index + 1)
                replicated_address[bank_index*ADDR_W +: ADDR_W] = address;
        end
    endfunction

    reg a_active;
    reg [5:0] a_configuration_id;
    reg [ADDR_W-1:0] a_stride;
    reg [BANK_COUNT-1:0] a_bank_mask;
    reg [ADDR_W:0] a_next_address;
    reg [15:0] a_remaining_elements;
    reg [6:0] a_elements_per_stripe;
    reg a_inflight;
    reg a_response_held;
    reg a_restart_seen;
    reg [2:0] a_element_format;
    reg [2:0] a_packing_mode;
    reg [15:0] a_element_count;

    reg b_active;
    reg [5:0] b_configuration_id;
    reg [ADDR_W-1:0] b_stride;
    reg [BANK_COUNT-1:0] b_bank_mask;
    reg [ADDR_W:0] b_next_address;
    reg [15:0] b_remaining_elements;
    reg [6:0] b_elements_per_stripe;
    reg b_inflight;
    reg b_response_held;
    reg b_restart_seen;
    reg [2:0] b_element_format;
    reg [2:0] b_packing_mode;

    reg w_active;
    reg [5:0] w_configuration_id;
    reg [ADDR_W-1:0] w_stride;
    reg [BANK_COUNT-1:0] w_bank_mask;
    reg [ADDR_W:0] w_next_address;
    reg [15:0] w_remaining_elements;
    reg [6:0] w_elements_per_stripe;

    wire a_exhausted = a_active && (a_remaining_elements == 0) &&
        !a_inflight && !a_response_held;
    wire b_exhausted = b_active && (b_remaining_elements == 0) &&
        !b_inflight && !b_response_held;
    wire w_exhausted = w_active && (w_remaining_elements == 0);
    wire a_restart_request = vec_a_restart && !a_restart_seen;
    wire b_restart_request = vec_b_restart && !b_restart_seen;
    wire a_id_matches = a_restart_request || !a_active || a_exhausted ||
                        (a_configuration_id == vec_cfg_a);
    wire b_id_matches = b_restart_request || !b_active || b_exhausted ||
                        (b_configuration_id == vec_cfg_b);
    wire w_id_matches = !w_active || w_exhausted ||
                        (w_configuration_id == vec_cfg_w);

    assign cursor_restart_ready = !req_valid &&
        (!cursor_restart_mask[0] || !a_inflight) &&
        (!cursor_restart_mask[1] || !b_inflight);

    wire a_response_available = sp0_rd_valid && a_inflight &&
                                (|sp0_rd_bank_mask);
    wire b_response_available = sp1_rd_valid && b_inflight &&
                                (|sp1_rd_bank_mask);
    wire a_available = a_response_held || a_response_available;
    wire b_available = b_response_held || b_response_available;
    wire a_cfg_present = (!a_restart_request && a_active && !a_exhausted) ||
                         cfg_a_valid;
    wire b_cfg_present = (!b_restart_request && b_active && !b_exhausted) ||
                         cfg_b_valid;
    wire w_cfg_present = (w_active && !w_exhausted) || cfg_w_valid;
    wire a_cfg_legal = (!a_restart_request && a_active && !a_exhausted) ||
        (cfg_a_valid &&
         configuration_legal(cfg_a, 1'b1, 1'b0));
    wire b_cfg_legal = (!b_restart_request && b_active && !b_exhausted) ||
        (cfg_b_valid &&
         configuration_legal(cfg_b, 1'b1, 1'b0));
    wire w_cfg_legal = (w_active && !w_exhausted) ||
        (cfg_w_valid &&
         configuration_legal(cfg_w, 1'b0, 1'b1));

    wire a_address_in_range = !a_active || (a_next_address < BANK_DEPTH);
    wire b_address_in_range = !b_active || (b_next_address < BANK_DEPTH);
    wire w_address_in_range = !w_active || (w_next_address < BANK_DEPTH);
    wire too_many_accesses = vec_a_en && vec_b_en &&
                             vec_w_en;
    wire configuration_error = req_valid && (
        (vec_a_en && (!a_id_matches ||
            (a_cfg_present && !a_cfg_legal) ||
            (!a_restart_request && a_active && (a_remaining_elements != 0) &&
             !a_address_in_range &&
             !a_available))) ||
        (vec_b_en && (!b_id_matches ||
            (b_cfg_present && !b_cfg_legal) ||
            (!b_restart_request && b_active && (b_remaining_elements != 0) &&
             !b_address_in_range &&
             !b_available))) ||
        (vec_w_en && (!w_id_matches ||
            (w_cfg_present && !w_cfg_legal) ||
            (w_active && (w_remaining_elements != 0) && !w_address_in_range))));

    assign access_conflict = req_valid &&
                                    too_many_accesses;
    assign cfg_error = configuration_error;
    assign vec_a_valid = req_valid && vec_a_en &&
                                 !a_restart_request && a_id_matches &&
                                 a_available;
    assign vec_b_valid = req_valid && vec_b_en &&
                                 !b_restart_request && b_id_matches &&
                                 b_available;
    // Port affinity and commit-gated issuing guarantee that a scratchpad read
    // output is not overwritten while its response is held. The BRAM output
    // therefore acts as the skid payload register; only the valid bit is kept
    // here instead of duplicating two full 576-bit stripes in flip-flops.
    assign vec_a_data = sp0_rd_data;
    assign vec_b_data = sp1_rd_data;
    assign vec_a_metadata_valid = a_active || cfg_a_valid;
    assign vec_a_element_format = (a_active && !a_restart_request) ?
                                  a_element_format : cfg_a[54:52];
    assign vec_a_packing_mode = (a_active && !a_restart_request) ?
                                a_packing_mode : cfg_a[57:55];
    assign vec_a_element_count = (a_active && !a_restart_request) ?
                                 a_element_count : cfg_a[31:16];
    assign vec_b_metadata_valid = b_active || cfg_b_valid;
    assign vec_b_element_format = (b_active && !b_restart_request) ?
                                  b_element_format : cfg_b[54:52];
    assign vec_b_packing_mode = (b_active && !b_restart_request) ?
                                b_packing_mode : cfg_b[57:55];

    assign stream_in_ready = !req_valid ||
        (!too_many_accesses && !configuration_error &&
         (!vec_a_en || vec_a_valid) &&
         (!vec_b_en || vec_b_valid));
    assign stream_out_ready = !req_valid ||
        (!too_many_accesses && !configuration_error &&
          (!vec_w_en ||
           (w_cfg_present && w_cfg_legal &&
            (!w_active || w_exhausted || ((w_remaining_elements != 0) &&
                           w_address_in_range)))));

    wire consume_a = cycle_commit && req_valid &&
                     vec_a_en && vec_a_valid;
    wire consume_b = cycle_commit && req_valid &&
                     vec_b_en && vec_b_valid;
    wire perform_write = cycle_commit && req_valid &&
                         vec_w_en && stream_out_ready;

    // Initial reads are speculative only with respect to context commit. Once
    // active, the next address is issued exclusively when the current stripe
    // commits. A returned BRAM word feeds the consumer directly; a held-valid
    // bit prevents that BRAM output from being overwritten under backpressure.
    wire issue_a_initial = req_valid && vec_a_en &&
        (a_restart_request || !a_active || a_exhausted) &&
        !too_many_accesses && !configuration_error &&
        a_cfg_legal && !a_inflight &&
        (!a_response_held || a_restart_request);
    wire issue_b_initial = req_valid && vec_b_en &&
        (b_restart_request || !b_active || b_exhausted) &&
        !too_many_accesses && !configuration_error &&
        b_cfg_legal && !b_inflight &&
        (!b_response_held || b_restart_request);
    wire issue_a_next = consume_a && a_active && !a_restart_request &&
                        (a_remaining_elements != 0) && a_address_in_range;
    wire issue_b_next = consume_b && b_active && !b_restart_request &&
                        (b_remaining_elements != 0) && b_address_in_range;
    wire issue_a = issue_a_initial || issue_a_next;
    wire issue_b = issue_b_initial || issue_b_next;

    wire [BANK_COUNT-1:0] a_issue_bank_mask = issue_a_initial ?
        configuration_bank_mask(cfg_a) : a_bank_mask;
    wire [BANK_COUNT-1:0] b_issue_bank_mask = issue_b_initial ?
        configuration_bank_mask(cfg_b) : b_bank_mask;
    wire [ADDR_W-1:0] a_issue_address = issue_a_initial ?
        cfg_a[ADDR_W-1:0] : a_next_address[ADDR_W-1:0];
    wire [ADDR_W-1:0] b_issue_address = issue_b_initial ?
        cfg_b[ADDR_W-1:0] : b_next_address[ADDR_W-1:0];
    wire [ADDR_W-1:0] w_issue_address = (w_active && !w_exhausted) ?
        w_next_address[ADDR_W-1:0] : cfg_w[ADDR_W-1:0];
    wire [BANK_COUNT-1:0] w_issue_bank_mask = (w_active && !w_exhausted) ?
        w_bank_mask :
        configuration_bank_mask(cfg_w);

    always @* begin
        sp0_valid = 1'b0;
        sp0_write = 1'b0;
        sp0_bank_mask = {BANK_COUNT{1'b0}};
        sp0_addr = {BANK_COUNT*ADDR_W{1'b0}};
        sp0_wr_data = vec_w_data;
        sp1_valid = 1'b0;
        sp1_write = 1'b0;
        sp1_bank_mask = {BANK_COUNT{1'b0}};
        sp1_addr = {BANK_COUNT*ADDR_W{1'b0}};
        sp1_wr_data = vec_w_data;

        if (issue_a) begin
            sp0_valid = 1'b1;
            sp0_bank_mask = a_issue_bank_mask;
            sp0_addr = replicated_address(a_issue_address);
        end else if (perform_write) begin
            sp0_valid = 1'b1;
            sp0_write = 1'b1;
            sp0_bank_mask = w_issue_bank_mask;
            sp0_addr = replicated_address(w_issue_address);
        end

        if (issue_b) begin
            sp1_valid = 1'b1;
            sp1_bank_mask = b_issue_bank_mask;
            sp1_addr = replicated_address(b_issue_address);
        end else if (perform_write && issue_a) begin
            sp1_valid = 1'b1;
            sp1_write = 1'b1;
            sp1_bank_mask = w_issue_bank_mask;
            sp1_addr = replicated_address(w_issue_address);
        end
    end

    wire issue_a_fire = issue_a && sp0_ready &&
                        !sp_conflict;
    wire issue_b_fire = issue_b && sp1_ready &&
                        !sp_conflict;
    wire write_uses_port1 = perform_write && issue_a;
    wire write_fire = perform_write && !sp_conflict &&
        (write_uses_port1 ? sp1_ready : sp0_ready);
    wire w_initial_context = req_valid && vec_w_en && cfg_w_valid &&
        (!w_active || w_exhausted);

    always @(posedge clk) begin
        if (!rst_n || routine_start) begin
            a_active <= 1'b0;
            a_configuration_id <= 6'd0;
            a_stride <= {ADDR_W{1'b0}};
            a_bank_mask <= {BANK_COUNT{1'b0}};
            a_next_address <= {(ADDR_W+1){1'b0}};
            a_remaining_elements <= 16'd0;
            a_elements_per_stripe <= 7'd0;
            a_inflight <= 1'b0;
            a_response_held <= 1'b0;
            a_restart_seen <= 1'b0;
            a_element_format <= 3'd0;
            a_packing_mode <= 3'd0;
            a_element_count <= 16'd0;
            b_active <= 1'b0;
            b_configuration_id <= 6'd0;
            b_stride <= {ADDR_W{1'b0}};
            b_bank_mask <= {BANK_COUNT{1'b0}};
            b_next_address <= {(ADDR_W+1){1'b0}};
            b_remaining_elements <= 16'd0;
            b_elements_per_stripe <= 7'd0;
            b_inflight <= 1'b0;
            b_response_held <= 1'b0;
            b_restart_seen <= 1'b0;
            b_element_format <= 3'd0;
            b_packing_mode <= 3'd0;
            w_active <= 1'b0;
            w_configuration_id <= 6'd0;
            w_stride <= {ADDR_W{1'b0}};
            w_bank_mask <= {BANK_COUNT{1'b0}};
            w_next_address <= {(ADDR_W+1){1'b0}};
            w_remaining_elements <= 16'd0;
            w_elements_per_stripe <= 7'd0;
        end else begin
            if (!vec_a_restart)
                a_restart_seen <= 1'b0;
            if (!vec_b_restart)
                b_restart_seen <= 1'b0;
            if (cursor_restart_valid && cursor_restart_ready) begin
                if (cursor_restart_mask[0]) begin
                    a_active <= 1'b0;
                    a_configuration_id <= 6'd0;
                    a_next_address <= {(ADDR_W+1){1'b0}};
                    a_remaining_elements <= 16'd0;
                    a_elements_per_stripe <= 7'd0;
                    a_inflight <= 1'b0;
                    a_response_held <= 1'b0;
                    a_element_format <= 3'd0;
                    a_packing_mode <= 3'd0;
                end
                if (cursor_restart_mask[1]) begin
                    b_active <= 1'b0;
                    b_configuration_id <= 6'd0;
                    b_next_address <= {(ADDR_W+1){1'b0}};
                    b_remaining_elements <= 16'd0;
                    b_elements_per_stripe <= 7'd0;
                    b_inflight <= 1'b0;
                    b_response_held <= 1'b0;
                    b_element_format <= 3'd0;
                    b_packing_mode <= 3'd0;
                end
                if (cursor_restart_mask[2]) begin
                    w_active <= 1'b0;
                    w_configuration_id <= 6'd0;
                    w_next_address <= {(ADDR_W+1){1'b0}};
                    w_remaining_elements <= 16'd0;
                    w_elements_per_stripe <= 7'd0;
                end
            end
            if (consume_a)
                a_response_held <= 1'b0;
            if (consume_b)
                b_response_held <= 1'b0;
            if (w_initial_context) begin
                w_configuration_id <= vec_cfg_w;
                w_stride <= cfg_w[32 +: ADDR_W];
                w_bank_mask <= configuration_bank_mask(cfg_w);
                w_elements_per_stripe <= cfg_elements_per_stripe(cfg_w);
            end

            if (a_response_available) begin
                if (!consume_a)
                    a_response_held <= 1'b1;
                a_inflight <= 1'b0;
            end
            if (b_response_available) begin
                if (!consume_b)
                    b_response_held <= 1'b1;
                b_inflight <= 1'b0;
            end

            if (issue_a_fire) begin
                a_inflight <= 1'b1;
                if (a_restart_request) begin
                    a_response_held <= 1'b0;
                    a_restart_seen <= 1'b1;
                end
                if (issue_a_initial) begin
                    a_active <= 1'b1;
                    a_configuration_id <= vec_cfg_a;
                    a_stride <= cfg_a[32 +: ADDR_W];
                    a_bank_mask <= configuration_bank_mask(
                        cfg_a);
                    a_next_address <= {1'b0,
                        cfg_a[ADDR_W-1:0]} +
                        {1'b0, cfg_a[32 +: ADDR_W]};
                    a_elements_per_stripe <= cfg_elements_per_stripe(cfg_a);
                    a_element_format <= cfg_a[54:52];
                    a_packing_mode <= cfg_a[57:55];
                    a_element_count <= cfg_a[31:16];
                    a_remaining_elements <= elements_after_stripe(
                        cfg_a[31:16], cfg_elements_per_stripe(cfg_a));
                end else begin
                    a_next_address <= a_next_address + {1'b0, a_stride};
                    a_remaining_elements <= elements_after_stripe(
                        a_remaining_elements, a_elements_per_stripe);
                end
            end
            if (issue_b_fire) begin
                b_inflight <= 1'b1;
                if (b_restart_request) begin
                    b_response_held <= 1'b0;
                    b_restart_seen <= 1'b1;
                end
                if (issue_b_initial) begin
                    b_active <= 1'b1;
                    b_configuration_id <= vec_cfg_b;
                    b_stride <= cfg_b[32 +: ADDR_W];
                    b_bank_mask <= configuration_bank_mask(
                        cfg_b);
                    b_next_address <= {1'b0,
                        cfg_b[ADDR_W-1:0]} +
                        {1'b0, cfg_b[32 +: ADDR_W]};
                    b_elements_per_stripe <= cfg_elements_per_stripe(cfg_b);
                    b_element_format <= cfg_b[54:52];
                    b_packing_mode <= cfg_b[57:55];
                    b_remaining_elements <= elements_after_stripe(
                        cfg_b[31:16], cfg_elements_per_stripe(cfg_b));
                end else begin
                    b_next_address <= b_next_address + {1'b0, b_stride};
                    b_remaining_elements <= elements_after_stripe(
                        b_remaining_elements, b_elements_per_stripe);
                end
            end

            if (write_fire) begin
                if (!w_active || w_exhausted) begin
                    w_active <= 1'b1;
                    w_next_address <= {1'b0,
                        cfg_w[ADDR_W-1:0]} +
                        {1'b0, cfg_w[32 +: ADDR_W]};
                    w_remaining_elements <= elements_after_stripe(
                        cfg_w[31:16], cfg_elements_per_stripe(cfg_w));
                end else begin
                    w_next_address <= w_next_address + {1'b0, w_stride};
                    w_remaining_elements <= elements_after_stripe(
                        w_remaining_elements, w_elements_per_stripe);
                end
            end
        end
    end

`ifdef FORMAL
    reg f_routine_start_q;
    initial f_routine_start_q = 1'b0;
    always @(posedge clk) begin
        f_routine_start_q <= routine_start;
        if (rst_n && f_routine_start_q) begin
            assert(!a_active && !a_inflight && !a_response_held);
            assert(!b_active && !b_inflight && !b_response_held);
            assert(!w_active);
        end
    end

    reg formal_past_valid;
    reg [ADDR_W:0] f_prev_a_addr;
    reg [ADDR_W:0] f_prev_b_addr;
    reg [ADDR_W:0] f_prev_w_addr;
    reg f_prev_a_issue;
    reg f_prev_b_issue;
    reg f_prev_write;
    reg [STRIPE_W-1:0] f_prev_sp0_data;
    reg [STRIPE_W-1:0] f_prev_sp1_data;
    always @(posedge clk) begin
        if (!rst_n || routine_start) begin
            formal_past_valid <= 1'b0;
            f_prev_a_addr <= {(ADDR_W+1){1'b0}};
            f_prev_b_addr <= {(ADDR_W+1){1'b0}};
            f_prev_w_addr <= {(ADDR_W+1){1'b0}};
            f_prev_a_issue <= 1'b0;
            f_prev_b_issue <= 1'b0;
            f_prev_write <= 1'b0;
            f_prev_sp0_data <= {STRIPE_W{1'b0}};
            f_prev_sp1_data <= {STRIPE_W{1'b0}};
        end else begin
            formal_past_valid <= 1'b1;
            assert(!(sp0_write && sp1_write));
            if (cursor_restart_valid && cursor_restart_ready)
                assert(!req_valid && (cursor_restart_mask != 3'b000));
            assert(!(issue_a && sp0_write));
            assert(!(issue_b && sp1_write));
            if (cycle_commit)
                assert(stream_in_ready && stream_out_ready);
            if (consume_a)
                assert(vec_a_valid);
            if (consume_b)
                assert(vec_b_valid);
            if (perform_write)
                assert(stream_out_ready);
            if (formal_past_valid && a_active && !f_prev_a_issue)
                assert(a_next_address == f_prev_a_addr);
            if (formal_past_valid && b_active && !f_prev_b_issue)
                assert(b_next_address == f_prev_b_addr);
            if (formal_past_valid && w_active && !f_prev_write)
                assert(w_next_address == f_prev_w_addr);
            if (formal_past_valid && a_response_held)
                assert(sp0_rd_data == f_prev_sp0_data);
            if (formal_past_valid && b_response_held)
                assert(sp1_rd_data == f_prev_sp1_data);
            if (sp0_rd_valid)
                assert(sp0_rd_bank_mask == a_bank_mask);
            if (sp1_rd_valid)
                assert(sp1_rd_bank_mask == b_bank_mask);
            f_prev_a_addr <= a_next_address;
            f_prev_b_addr <= b_next_address;
            f_prev_w_addr <= w_next_address;
            f_prev_a_issue <= issue_a_fire;
            f_prev_b_issue <= issue_b_fire;
            f_prev_write <= write_fire;
            f_prev_sp0_data <= sp0_rd_data;
            f_prev_sp1_data <= sp1_rd_data;
        end
    end
`endif
endmodule

`default_nettype wire
