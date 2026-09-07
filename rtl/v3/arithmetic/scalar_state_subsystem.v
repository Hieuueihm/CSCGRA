`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

// Owns scalar register state, preload arbitration, and the gamma/beta shadows
// used by the scheduled CGLS update contexts.
module scalar_state_subsystem #(
    parameter integer ACC_W = `RECON_ACC_W
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear,
    input  wire                         cycle_commit,
    input  wire [`RECON_RESOURCE_CONTEXT_W-1:0] ctx,
    input  wire                         preload_valid,
    output wire                         preload_ready,
    input  wire                         preload_address,
    input  wire signed [ACC_W-1:0]      preload_data,
    input  wire                         fused_valid,
    output wire                         fused_ready,
    input  wire                         fused_address,
    input  wire signed [ACC_W-1:0]      fused_data,
    input  wire                         fused_is_gamma,
    input  wire                         vector_req_valid,
    input  wire                         scalar_req_valid,
    input  wire                         router_write_valid,
    input  wire                         router_write_address,
    input  wire signed [ACC_W-1:0]      router_write_data,
    output wire                         scalar0_valid,
    output wire signed [ACC_W-1:0]      scalar0_data,
    output wire                         scalar1_valid,
    output wire signed [ACC_W-1:0]      scalar1_data,
    output wire signed [ACC_W-1:0]      scalar0_router_data
);
    wire [4:0] operation =
        ctx[`RECON_RESOURCE_FIELD_OPERATION_LSB +:
            `RECON_RESOURCE_FIELD_OPERATION_W];
    wire [3:0] count_select =
        ctx[`RECON_RESOURCE_FIELD_COUNT_SELECT_LSB +:
            `RECON_RESOURCE_FIELD_COUNT_SELECT_W];
    wire [2:0] input_select =
        ctx[`RECON_RESOURCE_FIELD_INPUT_SELECT_LSB +:
            `RECON_RESOURCE_FIELD_INPUT_SELECT_W];
    wire [2:0] output_select =
        ctx[`RECON_RESOURCE_FIELD_OUTPUT_SELECT_LSB +:
            `RECON_RESOURCE_FIELD_OUTPUT_SELECT_W];

    reg algorithm_scalar_valid;
    reg signed [ACC_W-1:0] algorithm_scalar_data;
    reg gamma_capture_pending;
    reg gamma_shadow_valid;
    reg signed [ACC_W-1:0] gamma_shadow_data;
    reg beta_write_pending;
    reg beta_shadow_valid;
    reg signed [ACC_W-1:0] beta_shadow_data;

    wire algorithm_step = algorithm_scalar_valid &&
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) &&
        (count_select == `RECON_RESOURCE_COUNT_SIGNAL_LENGTH);
    wire update_p = beta_shadow_valid &&
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_AXPY) &&
        (input_select == `RECON_RESOURCE_INPUT_SCALAR_0) &&
        (output_select == `RECON_RESOURCE_OUTPUT_MEMORY_STREAM) &&
        (count_select == `RECON_RESOURCE_COUNT_ACTIVE_WORK_COUNT);
    assign scalar0_router_data = algorithm_step ? algorithm_scalar_data :
        update_p ? beta_shadow_data : scalar0_data;

    wire gamma_capture_issue = vector_req_valid &&
        (operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) &&
        (input_select == `RECON_RESOURCE_INPUT_MEMORY_STREAM) &&
        (output_select == `RECON_RESOURCE_OUTPUT_SCALAR_1) &&
        (count_select == `RECON_RESOURCE_COUNT_ACTIVE_WORK_COUNT);
    wire beta_issue = scalar_req_valid && gamma_shadow_valid &&
        (operation == `RECON_RESOURCE_OP_SCALAR_DIVIDE) &&
        (input_select == `RECON_RESOURCE_INPUT_SCALAR_1) &&
        (output_select == `RECON_RESOURCE_OUTPUT_SCALAR_0);
    wire gamma_capture = router_write_valid && router_write_address &&
                         gamma_capture_pending;
    wire beta_write = router_write_valid && !router_write_address &&
                      beta_write_pending;
    wire signed [ACC_W-1:0] register_write_data = beta_write ?
        gamma_shadow_data : router_write_data;
    wire register_preload_ready;
    wire fused_accept = fused_valid && fused_ready;
    wire selected_preload_valid = fused_valid || preload_valid;
    wire selected_preload_address = fused_valid ? fused_address : preload_address;
    wire signed [ACC_W-1:0] selected_preload_data = fused_valid ?
        fused_data : preload_data;

    assign fused_ready = register_preload_ready;
    assign preload_ready = register_preload_ready && !fused_valid;

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            algorithm_scalar_valid <= 1'b0;
            algorithm_scalar_data <= {ACC_W{1'b0}};
        end else if (preload_valid && preload_ready && !preload_address) begin
            algorithm_scalar_valid <= 1'b1;
            algorithm_scalar_data <= preload_data;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            gamma_capture_pending <= 1'b0;
            gamma_shadow_valid <= 1'b0;
            gamma_shadow_data <= {ACC_W{1'b0}};
            beta_write_pending <= 1'b0;
            beta_shadow_valid <= 1'b0;
            beta_shadow_data <= {ACC_W{1'b0}};
        end else begin
            if (gamma_capture_issue) begin
                gamma_capture_pending <= 1'b1;
                beta_shadow_valid <= 1'b0;
            end
            if (gamma_capture) begin
                gamma_capture_pending <= 1'b0;
                gamma_shadow_valid <= 1'b1;
                gamma_shadow_data <= router_write_data;
            end
            if (fused_accept && fused_is_gamma) begin
                gamma_capture_pending <= 1'b0;
                gamma_shadow_valid <= 1'b1;
                gamma_shadow_data <= fused_data;
                beta_shadow_valid <= 1'b0;
            end
            if (beta_issue)
                beta_write_pending <= 1'b1;
            if (beta_write) begin
                beta_write_pending <= 1'b0;
                gamma_shadow_valid <= 1'b0;
                beta_shadow_valid <= 1'b1;
                beta_shadow_data <= router_write_data;
            end
        end
    end

    scalar_register_file u_registers (
        .clk(clk), .rst_n(rst_n), .clear_all(clear),
        .read_address_a(1'b0), .read_data_a(scalar0_data),
        .read_valid_a(scalar0_valid), .read_address_b(1'b1),
        .read_data_b(scalar1_data), .read_valid_b(scalar1_valid),
        .preload_valid(selected_preload_valid),
        .preload_ready(register_preload_ready),
        .preload_address(selected_preload_address),
        .preload_data(selected_preload_data),
        .write_valid(router_write_valid), .cycle_commit(cycle_commit),
        .write_address(router_write_address), .write_data(register_write_data),
        .clear_valid(1'b0), .clear_address(1'b0)
    );
endmodule

`default_nettype wire
