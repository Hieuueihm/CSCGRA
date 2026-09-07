`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Pure transport/control boundary between one stream-context word and the
// vector/Phi providers. No algorithm state or arithmetic is owned here.
module stream_context_router (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         cycle_valid,
    input  wire         cycle_commit,
    input  wire [`RECON_STREAM_CONTEXT_W-1:0] stream_ctx,

    output wire         vec_req_valid,
    output wire         vec_cycle_commit,
    output wire         vec_a_en,
    output wire         vec_b_en,
    output wire         vec_w_en,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W-1:0] vec_cfg_a,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W-1:0] vec_cfg_b,
    output wire [`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_W-1:0] vec_cfg_w,
    input  wire         vec_in_ready,
    input  wire         vec_out_ready,
    input  wire         vec_cfg_error,
    input  wire         vec_access_conflict,

    input  wire         vector_a_valid,
    input  wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] vector_a_data,
    input  wire         vector_b_valid,
    input  wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] vector_b_data,
    input  wire         scalar_a_valid,
    input  wire [`RECON_SOLVER_W-1:0] scalar_a_data,
    input  wire         scalar_b_valid,
    input  wire [`RECON_SOLVER_W-1:0] scalar_b_data,
    output wire [`RECON_STREAM_FIELD_EXTERNAL_A_SELECT_W-1:0] ext_a_sel,
    output wire [`RECON_STREAM_FIELD_EXTERNAL_B_SELECT_W-1:0] ext_b_sel,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] out_vec_a,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] out_vec_b,
    output wire [`RECON_SOLVER_W-1:0] out_scalar,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] external_input_a,
    output wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] external_input_b,

    output wire         phi_command_valid,
    input  wire         phi_command_ready,
    output wire [`RECON_STREAM_FIELD_PHI_COMMAND_W-1:0] phi_command,
    output wire [`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_W-1:0] phi_cfg_id,
    input  wire         phi_cfg_valid,
    input  wire         phi_symbol_valid,
    output wire         phi_symbol_ready,
    input  wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] phi_nonzero,
    input  wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] phi_sign,
    output wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] out_phi_nonzero,
    output wire [`RECON_PHI_SIGNS_PER_CYCLE-1:0] out_phi_sign,

    output wire         stream_in_ready,
    output wire         stream_out_ready,
    output wire         stream_contract_error
);
    assign ext_a_sel = stream_ctx[`RECON_STREAM_FIELD_EXTERNAL_A_SELECT_LSB +:
                                  `RECON_STREAM_FIELD_EXTERNAL_A_SELECT_W];
    assign ext_b_sel = stream_ctx[`RECON_STREAM_FIELD_EXTERNAL_B_SELECT_LSB +:
                                  `RECON_STREAM_FIELD_EXTERNAL_B_SELECT_W];
    wire [`RECON_STREAM_FIELD_PHI_COMMAND_W-1:0] phi_cmd_dec =
        stream_ctx[`RECON_STREAM_FIELD_PHI_COMMAND_LSB +:
                   `RECON_STREAM_FIELD_PHI_COMMAND_W];
    wire vec_advance =
        stream_ctx[`RECON_STREAM_FIELD_ADVANCE_VECTOR_STREAMS_LSB];

    assign vec_a_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_A_ENABLE_LSB];
    assign vec_b_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_READ_B_ENABLE_LSB];
    assign vec_w_en =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_WRITE_ENABLE_LSB];
    wire vec_any = vec_a_en || vec_b_en || vec_w_en;
    assign vec_cfg_a =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_A_W];
    assign vec_cfg_b =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_B_W];
    assign vec_cfg_w =
        stream_ctx[`RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_LSB +:
                   `RECON_STREAM_FIELD_VECTOR_CONFIGURATION_WRITE_W];
    assign phi_command = phi_cmd_dec;
    assign phi_cfg_id =
        stream_ctx[`RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_LSB +:
                   `RECON_STREAM_FIELD_PHI_CONFIGURATION_ID_W];

    assign vec_req_valid = cycle_valid && vec_any;
    assign vec_cycle_commit = cycle_commit &&
                                        vec_advance;

    assign out_vec_a = vector_a_data;
    assign out_vec_b = vector_b_data;
    assign out_scalar = scalar_a_data;

    wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] scalar_a_broadcast =
        {`RECON_PE_COUNT{scalar_a_data}};
    wire [`RECON_PE_COUNT*`RECON_SOLVER_W-1:0] scalar_b_broadcast =
        {`RECON_PE_COUNT{scalar_b_data}};
    assign external_input_a =
        (ext_a_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ? vector_a_data :
        (ext_a_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B) ? vector_b_data :
        (ext_a_sel == `RECON_EXTERNAL_STREAM_SOURCE_SCALAR_BROADCAST) ?
            scalar_a_broadcast :
            {`RECON_PE_COUNT*`RECON_SOLVER_W{1'b0}};
    assign external_input_b =
        (ext_b_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ? vector_a_data :
        (ext_b_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B) ? vector_b_data :
        (ext_b_sel == `RECON_EXTERNAL_STREAM_SOURCE_SCALAR_BROADCAST) ?
            scalar_b_broadcast :
            {`RECON_PE_COUNT*`RECON_SOLVER_W{1'b0}};

    wire [3:0] source_a_ready = {
        scalar_a_valid, vector_b_valid, vector_a_valid, 1'b1
    };
    wire [3:0] source_b_ready = {
        scalar_b_valid, vector_b_valid, vector_a_valid, 1'b1
    };
    wire ext_a_ready = source_a_ready[ext_a_sel];
    wire ext_b_ready = source_b_ready[ext_b_sel];

    wire [3:0] phi_ready = {
        phi_command_ready,
        phi_symbol_valid,
        phi_cfg_valid && phi_command_ready,
        1'b1
    };
    wire phi_input_ready = phi_ready[phi_cmd_dec];

    // Side-effecting provider handshakes occur only on the same edge as the
    // array context commit. This prevents a START/STOP from escaping while a
    // vector input is still filling.
    assign phi_command_valid = cycle_commit &&
        ((phi_cmd_dec == `RECON_PHI_COMMAND_START) ||
         (phi_cmd_dec == `RECON_PHI_COMMAND_STOP));
    assign phi_symbol_ready = cycle_commit &&
                              (phi_cmd_dec ==
                               `RECON_PHI_COMMAND_CONSUME);
    assign out_phi_nonzero = phi_symbol_valid ? phi_nonzero :
                             {`RECON_PHI_SIGNS_PER_CYCLE{1'b0}};
    assign out_phi_sign = phi_symbol_valid ? phi_sign :
                          {`RECON_PHI_SIGNS_PER_CYCLE{1'b0}};

    wire disabled_a_cfg = !vec_a_en &&
                                        (vec_cfg_a != 6'd0);
    wire disabled_b_cfg = !vec_b_en &&
                                        (vec_cfg_b != 6'd0);
    wire disabled_w_cfg = !vec_w_en &&
                                        (vec_cfg_w != 6'd0);
    wire vec_a_missing_read =
        ((ext_a_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) ||
         (ext_b_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A)) &&
        !vec_a_en;
    wire vec_b_missing_read =
        ((ext_a_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B) ||
         (ext_b_sel == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_B)) &&
        !vec_b_en;
    wire phi_id_without_start =
        (phi_cmd_dec != `RECON_PHI_COMMAND_START) &&
        (phi_cfg_id != 6'd0);
    wire advance_mismatch = vec_any !=
                                   vec_advance;
    wire local_error = disabled_a_cfg ||
        disabled_b_cfg || disabled_w_cfg ||
        vec_a_missing_read || vec_b_missing_read ||
        phi_id_without_start || advance_mismatch;

    assign stream_contract_error = cycle_valid &&
        (local_error || vec_cfg_error ||
         vec_access_conflict);
    assign stream_in_ready = !cycle_valid ||
        (!stream_contract_error && vec_in_ready &&
         ext_a_ready && ext_b_ready && phi_input_ready);
    assign stream_out_ready = !cycle_valid ||
        (!stream_contract_error && vec_out_ready);

`ifdef FORMAL
    reg formal_past_valid;
    reg f_prev_stall;
    reg [`RECON_STREAM_CONTEXT_W-1:0] f_prev_ctx;
    always @(posedge clk) begin
        if (!rst_n) begin
            formal_past_valid <= 1'b0;
            f_prev_stall <= 1'b0;
            f_prev_ctx <= {`RECON_STREAM_CONTEXT_W{1'b0}};
        end else begin
            formal_past_valid <= 1'b1;
            if (cycle_commit) begin
                assert(stream_in_ready);
                assert(stream_out_ready);
                assert(!stream_contract_error);
            end
            if (vec_cycle_commit)
                assert(vec_any);
            if (phi_command_valid)
                assert(phi_command_ready);
            if (phi_symbol_ready)
                assert(phi_symbol_valid);
            if (formal_past_valid && f_prev_stall)
                assert(stream_ctx == f_prev_ctx);
            f_prev_stall <= cycle_valid &&
                !(stream_in_ready && stream_out_ready);
            f_prev_ctx <= stream_ctx;
        end
    end
`endif
endmodule

`default_nettype wire
