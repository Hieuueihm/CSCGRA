`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "architecture_guard_defs.vh"
`include "context_isa_defs.vh"

// Resident two-bank context image.  RAM contents are never reset; only the
// programmed high-water marks and output-valid state are reset.
//
// Plane encoding and programming transaction:
//   0..7 : two 36-bit tile words per 72-bit word
//   8    : {stream_ctx, array_ctx}; written last to commit
//   9    : resource_ctx in data[35:0]
//   10   : phase_word in data[35:0]
//
// A new array-context address is programmed in the fixed transaction order
// 0..7, 9, 8.  Plane 8 advances the committed high-water mark.  Existing
// inactive-bank addresses may be patched in any plane.  This two-bank loader
// protocol needs one four-bit step register per bank rather than one counter
// per physical plane.  Plane 8 advances the high-water mark but does not make
// the bank executable.  An explicit finalize request scans every control-flow
// successor; only a closed image is certified for launch.
module context_image_store (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         execution_active,
    input  wire         active_image_bank,
    output wire         active_image_ok,
    output wire [8:0]   active_ctx_count,

    input  wire         finalize_valid,
    output wire         finalize_ready,
    input  wire         finalize_req_bank,
    output reg          finalize_resp_valid,
    input  wire         finalize_resp_ready,
    output reg          finalize_resp_error,
    output reg  [7:0]   finalize_resp_code,
    output reg  [31:0]  finalize_resp_detail,

    input  wire         img_wr_valid,
    output wire         img_wr_ready,
    input  wire         img_wr_bank,
    input  wire [3:0]   img_wr_plane,
    input  wire [7:0]   img_wr_addr,
    input  wire [2*`RECON_TILE_CONTEXT_W-1:0] img_wr_data,
    output reg          img_wr_resp_valid,
    input  wire         img_wr_resp_ready,
    output reg          img_wr_resp_error,
    output reg  [7:0]   img_wr_resp_code,
    output reg  [31:0]  img_wr_resp_detail,

    input  wire         array_rd_en,
    input  wire [7:0]   array_rd_addr,
    output reg          array_rd_resp_valid,
    output reg          array_rd_valid,
    output reg  [7:0]   array_rd_pc,
    output wire [`RECON_PE_PER_CLUSTER*`RECON_TILE_CONTEXT_W-1:0] tile_ctx,
    output wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] array_ctx,
    output wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,
    output reg  [`RECON_RESOURCE_CONTEXT_W-1:0] resource_ctx,

    input  wire         phase_rd_en,
    input  wire [7:0]   phase_rd_addr,
    output reg          phase_rd_resp_valid,
    output reg          phase_rd_valid,
    output reg  [7:0]   phase_rd_pc,
    output reg  [`RECON_PHASE_INSTRUCTION_W-1:0] phase_word
);
    localparam integer IMAGE_WORD_W = 2 * `RECON_TILE_CONTEXT_W;
    localparam integer IMAGE_ENTRY_COUNT =
        `RECON_CONTEXT_IMAGE_BANKS * `RECON_CONTEXT_DEPTH;
    localparam integer TILE_PLANE_COUNT = `RECON_PE_PER_CLUSTER / 2;
    localparam [3:0] PLANE_ARRAY_STREAM =
        `RECON_ARRAY_CONTEXT_COMMIT_PLANE;
    localparam [3:0] PLANE_RESOURCE = PLANE_ARRAY_STREAM + 4'd1;
    localparam [3:0] PLANE_PHASE        =
        `RECON_PHASE_INSTRUCTION_COMMIT_PLANE;

    (* ram_style = "block" *) reg [IMAGE_WORD_W-1:0]
        array_stream_plane [0:IMAGE_ENTRY_COUNT-1];
    (* ram_style = "block" *) reg [`RECON_RESOURCE_CONTEXT_W-1:0]
        resource_plane [0:IMAGE_ENTRY_COUNT-1];
    (* ram_style = "block" *) reg [`RECON_PHASE_INSTRUCTION_W-1:0]
        phase_plane [0:IMAGE_ENTRY_COUNT-1];

    reg [8:0] array_count [0:1];
    reg [8:0] phase_count [0:1];
    reg [3:0] array_load_step [0:1];
    reg [1:0] image_ok;
    (* ram_style = "distributed" *) reg
        resource_wait_map [0:IMAGE_ENTRY_COUNT-1];
    (* ram_style = "distributed" *) reg
        guaranteed_map [0:IMAGE_ENTRY_COUNT-1];
`ifdef FORMAL
    reg prev_active_bank;
`endif
    reg [IMAGE_WORD_W-1:0] array_stream_word;
    reg [3:0] expected_plane;
    reg finalize_active;
    reg finalize_bank;
    reg [8:0] finalize_count;
    reg [8:0] finalize_issue_idx;
    reg finalize_chk_valid;
    reg [7:0] finalize_chk_pc;

    wire finalize_rd_en = finalize_active &&
        (finalize_issue_idx < finalize_count);
    wire [8:0] finalize_rd_idx =
        {finalize_bank, finalize_issue_idx[7:0]};
    wire [8:0] array_rd_idx = {active_image_bank,
                                   array_rd_addr};
    wire array_stream_rd_en = finalize_rd_en ||
        (array_rd_en && !finalize_active);
    wire [8:0] array_stream_rd_idx = finalize_active ?
        finalize_rd_idx : array_rd_idx;
    wire [8:0] phase_rd_idx = {active_image_bank,
                                   phase_rd_addr};
    wire [8:0] img_wr_idx = {img_wr_bank, img_wr_addr};
    wire [8:0] wr_array_count = array_count[img_wr_bank];
    wire [8:0] wr_phase_count = phase_count[img_wr_bank];
    wire [3:0] wr_load_step = array_load_step[img_wr_bank];
    wire img_plane_ok = (img_wr_plane <= PLANE_PHASE);
    wire narrow_high_nonzero =
        ((img_wr_plane == PLANE_RESOURCE) ||
         (img_wr_plane == PLANE_PHASE)) &&
        (|img_wr_data[`RECON_TILE_CONTEXT_W +: `RECON_TILE_CONTEXT_W]);
    wire active_bank_conflict = execution_active &&
        (img_wr_bank == active_image_bank);
    wire [8:0] wr_addr_ext =
        {1'b0, img_wr_addr};
    wire [8:0] wr_addr_next =
        wr_addr_ext + 9'd1;
    wire array_plane = img_wr_plane <= PLANE_RESOURCE;
    wire patch_existing = array_plane &&
        (wr_addr_ext < wr_array_count);
    wire append_plane = array_plane &&
        (wr_addr_ext == wr_array_count) &&
        (img_wr_plane == expected_plane);
    wire array_order_error = array_plane &&
        !patch_existing && !append_plane;
    wire phase_hole = (img_wr_plane == PLANE_PHASE) &&
        (wr_addr_ext > wr_phase_count);
    wire order_error = array_order_error ||
        phase_hole;
    wire wr_violation;
    wire [7:0] wr_violation_code;
    wire [31:0] wr_violation_detail;
    wire new_resource_wait;
    wire new_guaranteed;
    wire img_wr_error = !img_plane_ok ||
        narrow_high_nonzero || active_bank_conflict ||
        order_error ||
        (array_plane && wr_violation);
    wire img_wr_fire = img_wr_valid && img_wr_ready;
    wire finalize_fire = finalize_valid &&
                                     finalize_ready;

    wire [`RECON_ARRAY_CONTROL_CONTEXT_W-1:0] finalize_ctrl =
        array_stream_word[0 +: `RECON_ARRAY_CONTROL_CONTEXT_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W-1:0] finalize_mode =
        finalize_ctrl[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_LSB +:
                      `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_MODE_W];
    wire [`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_W-1:0] finalize_target =
        finalize_ctrl[`RECON_ARRAY_CONTROL_FIELD_NEXT_PC_LSB +:
                      `RECON_ARRAY_CONTROL_FIELD_NEXT_PC_W];
    wire finalize_done =
        finalize_ctrl[`RECON_ARRAY_CONTROL_FIELD_ROUTINE_DONE_LSB];
    wire [8:0] target_ext = {1'b0, finalize_target};
    wire [8:0] fallthrough_ext =
        {1'b0, finalize_chk_pc} + 9'd1;
    reg target_required;
    reg fallthrough_required;
    reg cfg_violation;
    reg [31:0] cfg_error_detail;

    assign img_wr_ready = !finalize_active &&
        !finalize_valid &&
        (!img_wr_resp_valid || img_wr_resp_ready);
    assign finalize_ready = !execution_active &&
        !finalize_active && !img_wr_valid &&
        (!finalize_resp_valid ||
         finalize_resp_ready);
    assign active_image_ok =
        image_ok[active_image_bank];
    assign active_ctx_count =
        array_count[active_image_bank];
    assign array_ctx =
        array_stream_word[0 +: `RECON_ARRAY_CONTROL_CONTEXT_W];
    assign stream_ctx =
        array_stream_word[`RECON_ARRAY_CONTROL_CONTEXT_W +:
                          `RECON_STREAM_CONTEXT_W];

    context_write_certifier u_write_check (
        .img_wr_plane(img_wr_plane),
        .img_wr_data(img_wr_data),
        .patch_existing(patch_existing),
        .old_resource_wait(
            resource_wait_map[img_wr_idx]),
        .old_guaranteed(
            guaranteed_map[img_wr_idx]),
        .violation(wr_violation),
        .violation_code(wr_violation_code),
        .violation_detail(wr_violation_detail),
        .new_resource_wait(new_resource_wait),
        .new_guaranteed(new_guaranteed)
    );

    genvar tile_plane_id;
    generate
        for (tile_plane_id = 0; tile_plane_id < TILE_PLANE_COUNT;
                tile_plane_id = tile_plane_id + 1) begin : g_tile_plane
            localparam [3:0] PLANE_ID = tile_plane_id;
            (* ram_style = "block" *) reg [IMAGE_WORD_W-1:0]
                words [0:IMAGE_ENTRY_COUNT-1];
            reg [IMAGE_WORD_W-1:0] read_word;

            assign tile_ctx[(tile_plane_id * IMAGE_WORD_W) +:
                            IMAGE_WORD_W] = read_word;

            always @(posedge clk) begin
                if (!rst_n) begin
                    read_word <= {IMAGE_WORD_W{1'b0}};
                end else begin
                    if (img_wr_fire && !img_wr_error &&
                            (img_wr_plane == PLANE_ID))
                        words[img_wr_idx] <= img_wr_data;
                    if (array_rd_en && !finalize_active)
                        read_word <= words[array_rd_idx];
                end
            end
        end
    endgenerate

    always @* begin
        if (wr_load_step <= 4'd7)
            expected_plane = wr_load_step;
        else if (wr_load_step == 4'd8)
            expected_plane = PLANE_RESOURCE;
        else
            expected_plane = PLANE_ARRAY_STREAM;
    end

    always @* begin
        target_required = 1'b0;
        fallthrough_required = 1'b0;
        if (!finalize_done) begin
            case (finalize_mode)
                `RECON_NEXT_PC_MODE_SEQUENTIAL:
                    fallthrough_required = 1'b1;
                `RECON_NEXT_PC_MODE_JUMP,
                `RECON_NEXT_PC_MODE_WAIT_EVENT:
                    target_required = 1'b1;
                `RECON_NEXT_PC_MODE_COUNTED_LOOP,
                `RECON_NEXT_PC_MODE_PREDICATE_SELECT: begin
                    target_required = 1'b1;
                    fallthrough_required = 1'b1;
                end
                `RECON_NEXT_PC_MODE_RETURN_TO_PHASE: begin end
                default: begin
                    target_required = 1'b1;
                    fallthrough_required = 1'b1;
                end
            endcase
        end

        cfg_violation = finalize_chk_valid &&
            ((target_required &&
              (target_ext >= finalize_count)) ||
             (fallthrough_required &&
              (fallthrough_ext >= finalize_count)));
        cfg_error_detail = {
            8'hfc, finalize_chk_pc, 3'd0,
            fallthrough_required &&
                (fallthrough_ext >= finalize_count),
            target_required &&
                (target_ext >= finalize_count),
            finalize_mode, finalize_target
        };
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            img_wr_resp_valid <= 1'b0;
            img_wr_resp_error <= 1'b0;
            img_wr_resp_code <= 8'd0;
            img_wr_resp_detail <= 32'd0;
            finalize_resp_valid <= 1'b0;
            finalize_resp_error <= 1'b0;
            finalize_resp_code <= 8'd0;
            finalize_resp_detail <= 32'd0;
            array_rd_resp_valid <= 1'b0;
            array_rd_valid <= 1'b0;
            array_rd_pc <= 8'd0;
            array_stream_word <= {IMAGE_WORD_W{1'b0}};
            resource_ctx <= {`RECON_RESOURCE_CONTEXT_W{1'b0}};
            phase_rd_resp_valid <= 1'b0;
            phase_rd_valid <= 1'b0;
            phase_rd_pc <= 8'd0;
            phase_word <= {`RECON_PHASE_INSTRUCTION_W{1'b0}};
            array_count[0] <= 9'd0;
            array_count[1] <= 9'd0;
            phase_count[0] <= 9'd0;
            phase_count[1] <= 9'd0;
            array_load_step[0] <= 4'd0;
            array_load_step[1] <= 4'd0;
            image_ok <= 2'b00;
            finalize_active <= 1'b0;
            finalize_bank <= 1'b0;
            finalize_count <= 9'd0;
            finalize_issue_idx <= 9'd0;
            finalize_chk_valid <= 1'b0;
            finalize_chk_pc <= 8'd0;
`ifdef FORMAL
            prev_active_bank <= 1'b0;
`endif
        end else begin
`ifdef FORMAL
            prev_active_bank <= active_image_bank;
`endif
            if (img_wr_resp_valid && img_wr_resp_ready)
                img_wr_resp_valid <= 1'b0;
            if (finalize_resp_valid &&
                    finalize_resp_ready)
                finalize_resp_valid <= 1'b0;

            if (finalize_fire) begin
                image_ok[finalize_req_bank] <= 1'b0;
                finalize_bank <= finalize_req_bank;
                finalize_count <=
                    array_count[finalize_req_bank];
                finalize_issue_idx <= 9'd0;
                finalize_chk_valid <= 1'b0;
                if ((array_load_step[finalize_req_bank] != 4'd0) ||
                        (array_count[finalize_req_bank] ==
                         9'd0)) begin
                    finalize_resp_valid <= 1'b1;
                    finalize_resp_error <= 1'b1;
                    finalize_resp_code <=
                        `RECON_CONTEXT_ERROR_IMAGE_WRITE;
                    finalize_resp_detail <= {
                        8'hfb, 10'd0, finalize_req_bank,
                        array_load_step[finalize_req_bank],
                        array_count[finalize_req_bank]
                    };
                end else begin
                    finalize_active <= 1'b1;
                end
            end

            if (finalize_active) begin
                if (finalize_rd_en) begin
                    finalize_chk_pc <= finalize_issue_idx[7:0];
                    finalize_chk_valid <= 1'b1;
                    finalize_issue_idx <= finalize_issue_idx + 9'd1;
                end else begin
                    finalize_chk_valid <= 1'b0;
                end

                if (finalize_chk_valid) begin
                    if (cfg_violation) begin
                        finalize_active <= 1'b0;
                        finalize_chk_valid <= 1'b0;
                        finalize_resp_valid <= 1'b1;
                        finalize_resp_error <= 1'b1;
                        finalize_resp_code <=
                            `RECON_CONTEXT_ERROR_ARRAY_CONTROL;
                        finalize_resp_detail <=
                            cfg_error_detail;
                    end else if (({1'b0, finalize_chk_pc} + 9'd1) ==
                                 finalize_count) begin
                        finalize_active <= 1'b0;
                        finalize_chk_valid <= 1'b0;
                        image_ok[finalize_bank] <= 1'b1;
                        finalize_resp_valid <= 1'b1;
                        finalize_resp_error <= 1'b0;
                        finalize_resp_code <= 8'd0;
                        finalize_resp_detail <= {
                            8'hfa, 14'd0, finalize_bank,
                            finalize_count
                        };
                    end
                end
            end

            if (img_wr_fire) begin
                img_wr_resp_valid <= 1'b1;
                img_wr_resp_error <= img_wr_error;
                img_wr_resp_code <= img_wr_error ?
                    `RECON_CONTEXT_ERROR_IMAGE_WRITE : 8'd0;
                img_wr_resp_detail <= wr_violation ?
                    wr_violation_detail :
                    {10'd0, execution_active, active_image_bank,
                     img_wr_bank, img_wr_plane,
                     img_wr_addr, 7'd0};

                if (!img_wr_error) begin
                    if (array_plane)
                        image_ok[img_wr_bank] <= 1'b0;
                    case (img_wr_plane)
                        PLANE_ARRAY_STREAM: begin
                            array_stream_plane[img_wr_idx] <= img_wr_data;
                            guaranteed_map[img_wr_idx] <=
                                new_guaranteed;
                            if (append_plane) begin
                                array_count[img_wr_bank] <=
                                    wr_addr_next;
                                array_load_step[img_wr_bank] <= 4'd0;
                            end
                        end
                        PLANE_RESOURCE: begin
                            resource_plane[img_wr_idx] <=
                                img_wr_data[0 +: `RECON_RESOURCE_CONTEXT_W];
                            resource_wait_map[img_wr_idx] <=
                                new_resource_wait;
                        end
                        PLANE_PHASE: begin
                            phase_plane[img_wr_idx] <=
                                img_wr_data[0 +: `RECON_PHASE_INSTRUCTION_W];
                            if (wr_addr_next >
                                    phase_count[img_wr_bank])
                                phase_count[img_wr_bank] <=
                                    wr_addr_next;
                        end
                        default: begin end
                    endcase
                    if (append_plane &&
                            (img_wr_plane != PLANE_ARRAY_STREAM))
                        array_load_step[img_wr_bank] <=
                            array_load_step[img_wr_bank] + 4'd1;
                end
            end

            array_rd_resp_valid <= array_rd_en;
            array_rd_valid <= array_rd_en &&
                active_image_ok;
            if (array_stream_rd_en)
                array_stream_word <=
                    array_stream_plane[array_stream_rd_idx];
            if (array_rd_en && !finalize_active) begin
                array_rd_pc <= array_rd_addr;
                resource_ctx <= resource_plane[array_rd_idx];
            end

            phase_rd_resp_valid <=
                phase_rd_en;
            phase_rd_valid <= phase_rd_en &&
                ({1'b0, phase_rd_addr} <
                 phase_count[active_image_bank]);
            if (phase_rd_en) begin
                phase_rd_pc <= phase_rd_addr;
                phase_word <= phase_plane[phase_rd_idx];
            end
        end
    end

`ifdef FORMAL
    reg f_prev_wr_error;
    reg f_prev_final_wait;
    reg f_prev_final_error;
    reg [7:0] f_prev_final_code;
    reg [31:0] f_prev_final_detail;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_prev_wr_error <= 1'b0;
            f_prev_final_wait <= 1'b0;
            f_prev_final_error <= 1'b0;
            f_prev_final_code <= 8'd0;
            f_prev_final_detail <= 32'd0;
        end else begin
            if (execution_active)
                assert(active_image_bank == prev_active_bank);
            if (f_prev_wr_error) begin
                assert(img_wr_resp_valid);
                assert(img_wr_resp_error);
                assert(img_wr_resp_code ==
                       `RECON_CONTEXT_ERROR_IMAGE_WRITE);
            end
            if (f_prev_final_wait) begin
                assert(finalize_resp_valid);
                assert(finalize_resp_error ==
                       f_prev_final_error);
                assert(finalize_resp_code ==
                       f_prev_final_code);
                assert(finalize_resp_detail ==
                       f_prev_final_detail);
            end
            f_prev_wr_error <= img_wr_fire &&
                img_wr_error;
            f_prev_final_wait <=
                finalize_resp_valid &&
                !finalize_resp_ready;
            f_prev_final_error <=
                finalize_resp_error;
            f_prev_final_code <=
                finalize_resp_code;
            f_prev_final_detail <=
                finalize_resp_detail;
            assert(!array_rd_valid ||
                   array_rd_resp_valid);
            assert(!phase_rd_valid ||
                   phase_rd_resp_valid);
            if (array_rd_valid)
                assert(array_rd_pc <
                       array_count[active_image_bank]);
            assert(array_load_step[0] <= 4'd9);
            assert(array_load_step[1] <= 4'd9);
            if (execution_active)
                assert(active_image_ok);
            assert(!(finalize_active && execution_active));
            assert(!(finalize_active && img_wr_fire));
            if (finalize_active)
                assert(!image_ok[finalize_bank]);
            if (finalize_resp_valid &&
                    !finalize_resp_error)
                assert(image_ok[finalize_bank]);
            if (phase_rd_valid)
                assert(phase_rd_pc <
                       phase_count[active_image_bank]);
        end
    end
`endif
endmodule

`default_nettype wire
