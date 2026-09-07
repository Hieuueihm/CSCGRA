`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module support_phi_symbol_cache (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         invalidate,
    input  wire [8:0]   measurement_count,

    input  wire         prepare_valid,
    output wire         prepare_ready,
    input  wire         prepare_from_candidates,
    input  wire [6:0]   prepare_support_count,
    input  wire [6:0]   prepare_preserve_count,
    input  wire [2:0]   prepare_row_block_count,

    input  wire         fill_valid,
    output wire         fill_ready,
    input  wire [6:0]   fill_slot,
    input  wire [2:0]   fill_row_block,
    input  wire [`RECON_PHI_COLUMN_W-1:0] fill_column,
    input  wire [31:0]  fill_nonzero,
    input  wire [31:0]  fill_sign,

    input  wire         capture_valid,
    output wire         capture_ready,
    input  wire [`RECON_PHI_COLUMN_W-1:0] capture_column,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] capture_row_block,
    input  wire [31:0]  capture_nonzero,
    input  wire [31:0]  capture_sign,
    input  wire         candidate_store_valid,
    output wire         candidate_store_ready,
    input  wire [5:0]   candidate_store_slot,
    input  wire [`RECON_PHI_COLUMN_W-1:0] candidate_store_column,
    input  wire         candidate_release_valid,
    input  wire [`RECON_PHI_COLUMN_W-1:0] candidate_release_column,

    input  wire         promote_valid,
    output wire         promote_ready,
    input  wire [5:0]   promote_candidate_slot,
    input  wire [6:0]   promote_support_slot,

    input  wire         replay_valid,
    output wire         replay_ready,
    input  wire [6:0]   replay_slot,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] replay_row_block,
    input  wire [`RECON_PHI_TAG_W-1:0] replay_tag,
    output wire         replay_response_valid,
    input  wire         replay_response_ready,
    output wire [31:0]  replay_nonzero,
    output wire [31:0]  replay_sign,
    output wire [`RECON_PHI_COLUMN_W-1:0] replay_column,
    output wire [6:0]   replay_response_slot,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] replay_response_row_block,
    output wire [`RECON_PHI_TAG_W-1:0] replay_response_tag,

    output reg          cache_valid,
    output wire         cache_busy,
    output reg          cache_fault
);
    localparam integer ROWS = `RECON_PHI_MAX_ROW_BLOCKS;
    localparam integer CANDIDATE_WORDS =
        `RECON_PHI_CANDIDATE_CACHE_SLOTS * ROWS;
    localparam integer ACTIVE_WORDS =
        `RECON_PHI_SUPPORT_CACHE_SLOTS * ROWS;
    localparam integer TOTAL_WORDS = CANDIDATE_WORDS + ACTIVE_WORDS;
    localparam integer ADDRESS_W = $clog2(TOTAL_WORDS);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_CANDIDATE_COPY = 3'd1;
    localparam [2:0] STATE_PROMOTE_READ = 3'd2;
    localparam [2:0] STATE_PROMOTE_WRITE = 3'd3;

    function [31:0] lane_mask;
        input [8:0] count;
        input [2:0] row_block;
        reg [9:0] row_base;
        reg [9:0] remaining;
        begin
            row_base = {2'b00, row_block, 5'b00000};
            if ({1'b0, count} <= row_base)
                lane_mask = 32'd0;
            else begin
                remaining = {1'b0, count} - row_base;
                if (remaining >= 10'd32)
                    lane_mask = 32'hffff_ffff;
                else
                    lane_mask = (32'h0000_0001 << remaining[4:0]) - 1'b1;
            end
        end
    endfunction

    function [ADDRESS_W-1:0] candidate_address;
        input [5:0] slot;
        input [2:0] row_block;
        begin
            candidate_address = ({slot, 2'b00} + row_block);
        end
    endfunction

    function [ADDRESS_W-1:0] active_address;
        input [6:0] slot;
        input [2:0] row_block;
        begin
            active_address = CANDIDATE_WORDS + ({slot, 2'b00} + row_block);
        end
    endfunction

    (* ram_style = "block" *) reg [31:0] sign_memory [0:TOTAL_WORDS-1];
    localparam integer HOLD_DEPTH = 4;
    reg [31:0] skid_sign [0:ROWS-1];
    reg [3:0] skid_valid_mask;
    reg [`RECON_PHI_COLUMN_W-1:0] skid_column;
    reg hold_valid [0:HOLD_DEPTH-1];
    reg [`RECON_PHI_COLUMN_W-1:0] hold_column [0:HOLD_DEPTH-1];
    reg [3:0] hold_mask [0:HOLD_DEPTH-1];
    reg [31:0] hold_sign [0:HOLD_DEPTH-1][0:ROWS-1];
    reg copy_from_hold;
    reg [1:0] copy_hold_slot;
    reg [`RECON_PHI_COLUMN_W-1:0] copy_column;
    reg [63:0] candidate_valid_bits;
    reg [`RECON_PHI_COLUMN_W-1:0] candidate_columns [0:`RECON_PHI_CANDIDATE_CACHE_SLOTS-1];
    reg [`RECON_PHI_SUPPORT_CACHE_SLOTS-1:0] support_valid_bits;
    reg [(`RECON_PHI_SUPPORT_CACHE_SLOTS * `RECON_PHI_COLUMN_W)-1:0]
        support_columns;

    reg [2:0] state;
    reg prepare_active;
    reg prepare_candidate_mode;
    reg [6:0] active_support_count;
    reg [2:0] active_row_block_count;
    reg [6:0] expected_fill_slot;
    reg [2:0] expected_fill_row;
    reg [6:0] expected_promote_slot;
    reg [5:0] copy_candidate_slot;
    reg [2:0] copy_row;
    localparam integer RESPONSE_FIFO_DEPTH = 2;
    reg [1:0] replay_response_count;
    reg replay_response_read_ptr;
    reg replay_response_write_ptr;
    reg [31:0] replay_response_sign_fifo [0:RESPONSE_FIFO_DEPTH-1];
    reg [6:0] replay_response_slot_fifo [0:RESPONSE_FIFO_DEPTH-1];
    reg [`RECON_PHI_ROW_BLOCK_W-1:0]
        replay_response_row_fifo [0:RESPONSE_FIFO_DEPTH-1];
    reg [`RECON_PHI_TAG_W-1:0]
        replay_response_tag_fifo [0:RESPONSE_FIFO_DEPTH-1];
    reg [`RECON_PHI_COLUMN_W-1:0]
        replay_response_column_fifo [0:RESPONSE_FIFO_DEPTH-1];
    reg replay_read_valid;
    reg replay_read_padding;
    reg [6:0] replay_read_slot;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] replay_read_row;
    reg [`RECON_PHI_TAG_W-1:0] replay_read_tag;
    reg [`RECON_PHI_COLUMN_W-1:0] replay_read_column;
    reg memory_write_enable;
    reg [ADDRESS_W-1:0] memory_write_address;
    reg [31:0] memory_write_data;
    reg memory_read_enable;
    reg [ADDRESS_W-1:0] memory_read_address;
    reg [31:0] memory_read_data;

    wire [2:0] capture_row_block_count =
        (measurement_count + 9'd31) >> 5;
    wire skid_complete =
        (capture_row_block_count != 0) &&
        ((skid_valid_mask & ((4'b0001 << capture_row_block_count) - 1'b1)) ==
         ((4'b0001 << capture_row_block_count) - 1'b1));
    wire replay_response_valid_int = replay_response_count != 0;
    wire replay_response_pop = replay_response_valid_int &&
                               replay_response_ready;
    wire replay_fifo_can_accept =
        (replay_response_count < RESPONSE_FIFO_DEPTH) || replay_response_pop;
    wire replay_read_advance = replay_read_valid && replay_fifo_can_accept;
    wire replay_pipeline_ready = !replay_read_valid || replay_read_advance;
    wire replay_pipeline_empty = !replay_read_valid &&
                                 (replay_response_count == 0);
    assign cache_busy = prepare_active || (state != STATE_IDLE) ||
                        replay_read_valid;
    assign prepare_ready = (state == STATE_IDLE) && !prepare_active &&
                           replay_pipeline_empty;
    assign fill_ready = (state == STATE_IDLE) && prepare_active &&
                        !prepare_candidate_mode;
    wire hold_has_room = !hold_valid[0] || !hold_valid[1] ||
                         !hold_valid[2] || !hold_valid[3];
    wire capture_would_evict = skid_complete &&
        (capture_row_block == {`RECON_PHI_ROW_BLOCK_W{1'b0}}) &&
        (capture_column != skid_column);
    wire live_store_match = skid_complete &&
        (candidate_store_column == skid_column);
    reg hold_store_match;
    reg [1:0] hold_store_slot;
    reg hold_release_match;
    reg [1:0] hold_release_slot;
    reg [1:0] hold_free_slot;
    integer hold_scan;
    always @* begin
        hold_store_match = 1'b0;
        hold_store_slot = 2'd0;
        hold_release_match = 1'b0;
        hold_release_slot = 2'd0;
        hold_free_slot = 2'd0;
        for (hold_scan = 0; hold_scan < HOLD_DEPTH; hold_scan = hold_scan + 1) begin
            if (!hold_store_match && hold_valid[hold_scan] &&
                    (hold_column[hold_scan] == candidate_store_column)) begin
                hold_store_match = 1'b1;
                hold_store_slot = hold_scan[1:0];
            end
            if (!hold_release_match && hold_valid[hold_scan] &&
                    (hold_column[hold_scan] == candidate_release_column)) begin
                hold_release_match = 1'b1;
                hold_release_slot = hold_scan[1:0];
            end
            if (!hold_valid[hold_scan])
                hold_free_slot = hold_scan[1:0];
        end
    end
    assign capture_ready = (state == STATE_IDLE) && !prepare_active &&
        !(capture_would_evict && !hold_has_room);
    assign candidate_store_ready = (state == STATE_IDLE) && !prepare_active &&
        (live_store_match || hold_store_match);
    assign promote_ready = (state == STATE_IDLE) && prepare_active &&
                           prepare_candidate_mode &&
                           (promote_support_slot == expected_promote_slot) &&
                           candidate_valid_bits[promote_candidate_slot];
    wire replay_padding = replay_row_block >= active_row_block_count;
    assign replay_ready = (state == STATE_IDLE) && cache_valid &&
                          replay_pipeline_ready && !prepare_valid &&
                          (replay_slot < active_support_count) &&
                          (replay_row_block < ROWS) &&
                          support_valid_bits[replay_slot];

    assign replay_response_valid = replay_response_valid_int;
    assign replay_nonzero = lane_mask(measurement_count,
        replay_response_row_fifo[replay_response_read_ptr]);
    assign replay_sign = replay_response_sign_fifo[replay_response_read_ptr];
    assign replay_column =
        replay_response_column_fifo[replay_response_read_ptr];
    assign replay_response_slot =
        replay_response_slot_fifo[replay_response_read_ptr];
    assign replay_response_row_block =
        replay_response_row_fifo[replay_response_read_ptr];
    assign replay_response_tag =
        replay_response_tag_fifo[replay_response_read_ptr];

    wire prepare_fire = prepare_valid && prepare_ready;
    wire fill_fire = fill_valid && fill_ready;
    wire capture_fire = capture_valid && capture_ready;
    wire candidate_store_fire = candidate_store_valid && candidate_store_ready;
    wire promote_fire = promote_valid && promote_ready;
    wire replay_fire = replay_valid && replay_ready;
    reg preserve_prefix_valid;
    integer preserve_index;
    always @* begin
        preserve_prefix_valid = 1'b1;
        for (preserve_index = 0; preserve_index < `RECON_PHI_SUPPORT_CACHE_SLOTS;
             preserve_index = preserve_index + 1)
            if ((preserve_index < prepare_preserve_count) &&
                !support_valid_bits[preserve_index])
                preserve_prefix_valid = 1'b0;
    end

    wire fill_payload_legal =
        (fill_slot == expected_fill_slot) &&
        (fill_row_block == expected_fill_row) &&
        (fill_nonzero == lane_mask(measurement_count, fill_row_block));

    always @* begin
        memory_write_enable = 1'b0;
        memory_write_address = {ADDRESS_W{1'b0}};
        memory_write_data = 32'd0;
        memory_read_enable = 1'b0;
        memory_read_address = {ADDRESS_W{1'b0}};

        if (fill_fire && fill_payload_legal) begin
            memory_write_enable = 1'b1;
            memory_write_address = active_address(fill_slot, fill_row_block);
            memory_write_data = fill_sign;
        end else if (state == STATE_CANDIDATE_COPY) begin
            memory_write_enable = 1'b1;
            memory_write_address = candidate_address(copy_candidate_slot,
                                                       copy_row);
            memory_write_data = copy_from_hold ?
                hold_sign[copy_hold_slot][copy_row] : skid_sign[copy_row];
        end else if (state == STATE_PROMOTE_WRITE) begin
            memory_write_enable = 1'b1;
            memory_write_address = active_address(expected_promote_slot,
                                                  copy_row);
            memory_write_data = memory_read_data;
        end

        if (state == STATE_PROMOTE_READ) begin
            memory_read_enable = 1'b1;
            memory_read_address = candidate_address(copy_candidate_slot,
                                                      copy_row);
        end else if (replay_fire && !replay_padding) begin
            memory_read_enable = 1'b1;
            memory_read_address = active_address(replay_slot,
                                                  replay_row_block);
        end
    end

    integer index;
    always @(posedge clk) begin
        if (!rst_n || invalidate) begin
            state <= STATE_IDLE;
            prepare_active <= 1'b0;
            prepare_candidate_mode <= 1'b0;
            active_support_count <= 7'd0;
            active_row_block_count <= 3'd0;
            expected_fill_slot <= 7'd0;
            expected_fill_row <= 3'd0;
            expected_promote_slot <= 7'd0;
            skid_valid_mask <= 4'd0;
            hold_valid[0] <= 1'b0;
            hold_valid[1] <= 1'b0;
            hold_valid[2] <= 1'b0;
            hold_valid[3] <= 1'b0;
            candidate_valid_bits <= 64'd0;
            support_valid_bits <= {`RECON_PHI_SUPPORT_CACHE_SLOTS{1'b0}};
            replay_response_count <= 2'd0;
            replay_response_read_ptr <= 1'b0;
            replay_response_write_ptr <= 1'b0;
            replay_read_valid <= 1'b0;
            cache_valid <= 1'b0;
            cache_fault <= 1'b0;
        end else begin
            if (memory_write_enable)
                sign_memory[memory_write_address] <= memory_write_data;
            if (memory_read_enable)
                memory_read_data <= sign_memory[memory_read_address];

            case ({replay_read_advance, replay_response_pop})
                2'b10: replay_response_count <= replay_response_count + 1'b1;
                2'b01: replay_response_count <= replay_response_count - 1'b1;
                default: replay_response_count <= replay_response_count;
            endcase
            if (replay_response_pop)
                replay_response_read_ptr <= replay_response_read_ptr + 1'b1;
            if (replay_read_advance) begin
                replay_response_sign_fifo[replay_response_write_ptr] <=
                    replay_read_padding ? 32'd0 : memory_read_data;
                replay_response_slot_fifo[replay_response_write_ptr] <=
                    replay_read_slot;
                replay_response_row_fifo[replay_response_write_ptr] <=
                    replay_read_row;
                replay_response_tag_fifo[replay_response_write_ptr] <=
                    replay_read_tag;
                replay_response_column_fifo[replay_response_write_ptr] <=
                    replay_read_column;
                replay_response_write_ptr <= replay_response_write_ptr + 1'b1;
            end
            if (replay_fire) begin
                replay_read_valid <= 1'b1;
                replay_read_padding <= replay_padding;
                replay_read_slot <= replay_slot;
                replay_read_row <= replay_row_block;
                replay_read_tag <= replay_tag;
                replay_read_column <= support_columns[
                    (replay_slot * `RECON_PHI_COLUMN_W) +:
                    `RECON_PHI_COLUMN_W];
            end else if (replay_read_advance) begin
                replay_read_valid <= 1'b0;
            end

            if (prepare_fire) begin
                cache_valid <= 1'b0;
                expected_fill_slot <= 7'd0;
                expected_fill_row <= 3'd0;
                expected_promote_slot <= 7'd0;
                for (index = 0; index < `RECON_PHI_SUPPORT_CACHE_SLOTS; index = index + 1)
                    if (!prepare_from_candidates || (index >= prepare_preserve_count))
                        support_valid_bits[index] <= 1'b0;
                if ((prepare_support_count > `RECON_PHI_SUPPORT_CACHE_SLOTS) ||
                    (prepare_preserve_count > prepare_support_count) ||
                    (prepare_preserve_count > active_support_count) ||
                    (prepare_from_candidates && !preserve_prefix_valid) ||
                    (!prepare_from_candidates && (prepare_preserve_count != 0)) ||
                    (prepare_row_block_count == 0) ||
                    (prepare_row_block_count > ROWS)) begin
                    cache_fault <= 1'b1;
                    prepare_active <= 1'b0;
                end else begin
                    prepare_candidate_mode <= prepare_from_candidates;
                    active_support_count <= prepare_support_count;
                    active_row_block_count <= prepare_row_block_count;
                    expected_promote_slot <= prepare_preserve_count;
                    if (prepare_support_count == 0) begin
                        cache_valid <= 1'b1;
                        prepare_active <= 1'b0;
                    end else if (prepare_from_candidates &&
                        (prepare_support_count == prepare_preserve_count)) begin
                        cache_valid <= 1'b1;
                        prepare_active <= 1'b0;
                    end else begin
                        prepare_active <= 1'b1;
                    end
                end
            end

            if (fill_fire) begin
                if (!fill_payload_legal) begin
                    cache_fault <= 1'b1;
                    cache_valid <= 1'b0;
                    prepare_active <= 1'b0;
                end else begin
                    if (fill_row_block == 0)
                        support_columns[
                            (fill_slot * `RECON_PHI_COLUMN_W) +:
                            `RECON_PHI_COLUMN_W] <= fill_column;
                    if (fill_row_block + 1'b1 == active_row_block_count) begin
                        support_valid_bits[fill_slot] <= 1'b1;
                        expected_fill_row <= 3'd0;
                        if (fill_slot + 1'b1 == active_support_count) begin
                            cache_valid <= 1'b1;
                            prepare_active <= 1'b0;
                        end else begin
                            expected_fill_slot <= fill_slot + 1'b1;
                        end
                    end else begin
                        expected_fill_row <= fill_row_block + 1'b1;
                    end
                end
            end

            if (capture_fire) begin
                if ((capture_nonzero != lane_mask(measurement_count,
                                                  capture_row_block)) ||
                    (capture_row_block >= capture_row_block_count) ||
                    ((capture_row_block != 0) &&
                     ((capture_column != skid_column) ||
                      !skid_valid_mask[capture_row_block-1]))) begin
                    cache_fault <= 1'b1;
                    skid_valid_mask <= 4'd0;
                end else begin
                    if (capture_row_block == 0) begin
                        if (skid_complete &&
                                (capture_column != skid_column) &&
                                hold_has_room) begin
                            hold_valid[hold_free_slot] <= 1'b1;
                            hold_column[hold_free_slot] <= skid_column;
                            hold_mask[hold_free_slot] <= skid_valid_mask;
                            for (index = 0; index < ROWS; index = index + 1)
                                hold_sign[hold_free_slot][index] <=
                                    skid_sign[index];
                        end
                        skid_valid_mask <= 4'b0001;
                        skid_column <= capture_column;
                    end else begin
                        skid_valid_mask[capture_row_block] <= 1'b1;
                    end
                    skid_sign[capture_row_block] <= capture_sign;
                end
            end

            if (candidate_store_fire) begin
                copy_candidate_slot <= candidate_store_slot;
                copy_row <= 3'd0;
                copy_from_hold <= hold_store_match && !live_store_match;
                copy_hold_slot <= hold_store_slot;
                copy_column <= candidate_store_column;
                state <= STATE_CANDIDATE_COPY;
            end else if (candidate_release_valid && hold_release_match &&
                    !((state == STATE_CANDIDATE_COPY) && copy_from_hold &&
                      (copy_hold_slot == hold_release_slot))) begin
                hold_valid[hold_release_slot] <= 1'b0;
            end

            if (promote_fire) begin
                copy_candidate_slot <= promote_candidate_slot;
                copy_row <= 3'd0;
                state <= STATE_PROMOTE_READ;
            end

            case (state)
                STATE_CANDIDATE_COPY: begin
                    if (copy_row + 1'b1 == capture_row_block_count) begin
                        candidate_valid_bits[copy_candidate_slot] <= 1'b1;
                        candidate_columns[copy_candidate_slot] <= copy_column;
                        if (copy_from_hold)
                            hold_valid[copy_hold_slot] <= 1'b0;
                        else
                            skid_valid_mask <= 4'd0;
                        state <= STATE_IDLE;
                    end else begin
                        copy_row <= copy_row + 1'b1;
                    end
                end
                STATE_PROMOTE_READ: begin
                    state <= STATE_PROMOTE_WRITE;
                end
                STATE_PROMOTE_WRITE: begin
                    if (copy_row + 1'b1 == active_row_block_count) begin
                        support_valid_bits[expected_promote_slot] <= 1'b1;
                        support_columns[
                            (expected_promote_slot * `RECON_PHI_COLUMN_W) +:
                            `RECON_PHI_COLUMN_W] <=
                                candidate_columns[copy_candidate_slot];
                        if (expected_promote_slot + 1'b1 ==
                            active_support_count) begin
                            cache_valid <= 1'b1;
                            prepare_active <= 1'b0;
                        end else begin
                            expected_promote_slot <=
                                expected_promote_slot + 1'b1;
                        end
                        state <= STATE_IDLE;
                    end else begin
                        copy_row <= copy_row + 1'b1;
                        state <= STATE_PROMOTE_READ;
                    end
                end
                default: begin end
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [31:0] f_nonzero;
    reg [31:0] f_sign;
    reg [6:0] f_slot;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] f_row;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid) begin
            if (f_stalled) begin
                assert(replay_response_valid);
                assert(replay_nonzero == f_nonzero);
                assert(replay_sign == f_sign);
                assert(replay_response_slot == f_slot);
                assert(replay_response_row_block == f_row);
                assert(replay_response_tag == f_tag);
            end
            if (replay_response_valid)
                assert(cache_valid);
            assert(replay_response_count <= RESPONSE_FIFO_DEPTH);
            if (replay_read_valid && !replay_fifo_can_accept)
                assert(!replay_ready);
        end
        f_stalled <= replay_response_valid && !replay_response_ready;
        f_nonzero <= replay_nonzero;
        f_sign <= replay_sign;
        f_slot <= replay_response_slot;
        f_row <= replay_response_row_block;
        f_tag <= replay_response_tag;
    end
`endif
endmodule

`default_nettype wire
