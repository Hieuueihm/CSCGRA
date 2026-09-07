`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "run_configuration_defs.vh"

module m13_termination_monitor (
    input  wire clk,
    input  wire rst_n,
    input  wire run_active,
    input  wire [15:0] outer_limit,
    input  wire [7:0] refine_limit,
    input  wire termination_mode,
    input  wire termination_event_valid,
    input  wire termination_residual_limit_reached,
    input  wire [`RECON_ACC_W-1:0] termination_residual_sq,
    input  wire refinement_event_valid,
    input  wire refinement_iteration_advance,
    input  wire refinement_certificate_pass,
    input  wire [6:0] support_count,
    input  wire [`RECON_K_MAX*10-1:0] support_indices,
    output reg  residual_limit_reached,
    output reg  iteration_limit_reached,
    output reg  support_stable,
    output reg  residual_decreased,
    output reg  solver_converged,
    output reg  [15:0] outer_iter,
    output reg  [7:0] solver_iter
);
    reg previous_residual_valid;
    reg [`RECON_ACC_W-1:0] previous_residual_sq;
    reg previous_support_valid;
    reg [6:0] previous_support_count;
    reg [`RECON_K_MAX*10-1:0] previous_support_indices;
    reg support_indices_match;
    integer support_compare_index;

    wire [15:0] next_outer_iter = outer_iter + 16'd1;
    wire [7:0] next_solver_iter = solver_iter + 8'd1;
    wire force_outer_iterations =
        (termination_mode == `RECON_TERMINATION_MODE_FORCE_OUTER_ITERATIONS);

    always @* begin
        support_indices_match = 1'b1;
        for (support_compare_index = 0;
             support_compare_index < `RECON_K_MAX;
             support_compare_index = support_compare_index + 1) begin
            if (support_compare_index < support_count)
                support_indices_match = support_indices_match &&
                    (support_indices[support_compare_index*10 +: 10] ==
                     previous_support_indices[
                         support_compare_index*10 +: 10]);
        end
    end

    always @(posedge clk) begin
        if (!rst_n || !run_active) begin
            residual_limit_reached <= 1'b0;
            iteration_limit_reached <= 1'b0;
            support_stable <= 1'b0;
            residual_decreased <= 1'b0;
            solver_converged <= 1'b0;
            outer_iter <= 16'd0;
            solver_iter <= 8'd0;
            previous_residual_valid <= 1'b0;
            previous_residual_sq <= {`RECON_ACC_W{1'b0}};
            previous_support_valid <= 1'b0;
            previous_support_count <= 7'd0;
            previous_support_indices <= {`RECON_K_MAX*10{1'b0}};
        end else begin
            if (refinement_event_valid && refinement_iteration_advance) begin
                solver_iter <= next_solver_iter;
                solver_converged <= refinement_certificate_pass ||
                    ((refine_limit != 0) &&
                     (next_solver_iter >= refine_limit));
            end else if (refinement_event_valid) begin
                solver_converged <= refinement_certificate_pass;
            end
            if (termination_event_valid) begin
                residual_limit_reached <= force_outer_iterations ?
                    1'b0 : termination_residual_limit_reached;
                iteration_limit_reached <= (outer_limit != 0) &&
                    (next_outer_iter >= outer_limit);
                residual_decreased <= force_outer_iterations ? 1'b1 :
                    (!previous_residual_valid ||
                     (termination_residual_sq < previous_residual_sq));
                support_stable <= force_outer_iterations ? 1'b0 :
                    (previous_support_valid &&
                     (support_count == previous_support_count) &&
                     support_indices_match);
                outer_iter <= next_outer_iter;
                solver_iter <= 8'd0;
                solver_converged <= 1'b0;
                previous_residual_valid <= 1'b1;
                previous_residual_sq <= termination_residual_sq;
                previous_support_valid <= 1'b1;
                previous_support_count <= support_count;
                previous_support_indices <= support_indices;
            end
        end
    end
endmodule

`default_nettype wire
