`timescale 1ns/1ps
`default_nettype none

`include "run_configuration_defs.vh"

// Single committed run-configuration owner. Consumer-facing views are decoded
// once at commit and remain stable until terminal_release.
module active_configuration_store (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         commit_valid,
    output wire         commit_ready,
    input  wire [`RECON_RUN_CONFIGURATION_BITS-1:0] commit_data,
    input  wire         terminal_release,
    output reg          active_valid,
    output reg  [1:0]   result_mode,
    output reg  [1:0]   matrix_kind,
    output reg  [8:0]   measurement_count,
    output reg  [4:0]   measurement_row_blocks,
    output reg  [10:0]  signal_length,
    output reg  [6:0]   sparsity,
    output reg  [15:0]  outer_limit,
    output reg  [7:0]   refine_limit,
    output reg  [4:0]   normal_residual_shift,
    output reg          termination_mode,
    output reg  [1:0]   refinement_profile,
    output reg  [61:0]  residual_limit,
    output reg  [63:0]  phi_seed,
    output reg  [63:0]  measurement_address,
    output reg  [63:0]  dense_result_address,
    output reg  [63:0]  sparse_result_address,
    output reg  [31:0]  user_tag,
    output reg  [17:0]  phi_scale_mantissa_uq17,
    output reg  [4:0]   phi_scale_exponent,
    output reg  [7:0]   phi_column_weight,
    output reg          require_unit_norm
);
    assign commit_ready = !active_valid || terminal_release;

    always @(posedge clk) begin
        if (!rst_n) begin
            active_valid <= 1'b0;
            result_mode <= 2'd0;
            matrix_kind <= 2'd0;
            measurement_count <= 9'd0;
            measurement_row_blocks <= 5'd0;
            signal_length <= 11'd0;
            sparsity <= 7'd0;
            outer_limit <= 16'd0;
            refine_limit <= 8'd0;
            normal_residual_shift <= 5'd0;
            termination_mode <= 1'b0;
            refinement_profile <= 2'd0;
            residual_limit <= 62'd0;
            phi_seed <= 64'd0;
            measurement_address <= 64'd0;
            dense_result_address <= 64'd0;
            sparse_result_address <= 64'd0;
            user_tag <= 32'd0;
            phi_scale_mantissa_uq17 <= 18'd0;
            phi_scale_exponent <= 5'd0;
            phi_column_weight <= 8'd0;
            require_unit_norm <= 1'b0;
        end else begin
            if (terminal_release)
                active_valid <= 1'b0;
            if (commit_valid && commit_ready) begin
                active_valid <= 1'b1;
                result_mode <= commit_data[29:28];
                matrix_kind <= commit_data[31:30];
                measurement_count <= commit_data[40:32];
                measurement_row_blocks <=
                    {1'b0, commit_data[40:37]} +
                    {4'd0, |commit_data[36:32]};
                signal_length <= commit_data[51:41];
                sparsity <= commit_data[58:52];
                outer_limit <= commit_data[79:64];
                refine_limit <= commit_data[87:80];
                normal_residual_shift <= commit_data[92:88];
                termination_mode <= commit_data[93];
                refinement_profile <= commit_data[95:94];
                residual_limit <= commit_data[189:128];
                phi_seed <= commit_data[255:192];
                measurement_address <= commit_data[319:256];
                dense_result_address <= commit_data[383:320];
                sparse_result_address <= commit_data[447:384];
                user_tag <= commit_data[479:448];
                phi_scale_mantissa_uq17 <= commit_data[497:480];
                phi_scale_exponent <= commit_data[502:498];
                phi_column_weight <= {1'b0, commit_data[509:503]} + 8'd1;
                require_unit_norm <= commit_data[510];
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_active_valid;
    reg f_terminal_release;
    reg f_commit_fire;
    reg [`RECON_RUN_CONFIGURATION_BITS-1:0] f_commit_data;
    reg [8:0] f_measurement_count;
    reg [4:0] f_measurement_row_blocks;
    reg [10:0] f_signal_length;
    reg [6:0] f_sparsity;
    reg [63:0] f_phi_seed;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_active_valid <= active_valid;
        f_terminal_release <= terminal_release;
        f_commit_fire <= commit_valid && commit_ready;
        f_commit_data <= commit_data;
        f_measurement_count <= measurement_count;
        f_measurement_row_blocks <= measurement_row_blocks;
        f_signal_length <= signal_length;
        f_sparsity <= sparsity;
        f_phi_seed <= phi_seed;
        if (rst_n && f_past_valid) begin
            if (f_commit_fire) begin
                assert(active_valid);
                assert(measurement_count == f_commit_data[40:32]);
                assert(measurement_row_blocks ==
                    ({1'b0, f_commit_data[40:37]} +
                     {4'd0, |f_commit_data[36:32]}));
                assert(signal_length == f_commit_data[51:41]);
                assert(sparsity == f_commit_data[58:52]);
                assert(phi_seed == f_commit_data[255:192]);
            end else if (f_active_valid && !f_terminal_release) begin
                assert(active_valid);
                assert(measurement_count == f_measurement_count);
                assert(measurement_row_blocks == f_measurement_row_blocks);
                assert(signal_length == f_signal_length);
                assert(sparsity == f_sparsity);
                assert(phi_seed == f_phi_seed);
            end
        end
    end
`endif
endmodule

`default_nettype wire
