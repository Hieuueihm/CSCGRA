`timescale 1ns/1ps
`default_nettype none

`include "reconstruction_control_defs.vh"
`include "architecture_guard_defs.vh"

// Sixteen-cycle deterministic validator. The check_index defines first-failure
// priority and guarantees that no partial parameter state is ever committed.
(* use_dsp = "no" *) module configuration_check_unit (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         run_configuration_valid,
    output wire         run_configuration_ready,
    input  wire [`RECON_RUN_CONFIGURATION_BITS-1:0] run_configuration_data,
    input  wire         abort_request,
    output wire         validation_active,
    output wire         commit_valid,
    input  wire         commit_ready,
    output wire [`RECON_RUN_CONFIGURATION_BITS-1:0] commit_data,
    output wire         error_valid,
    input  wire         error_ready,
    output reg  [7:0]   error_code,
    output reg  [4:0]   cfg_error_word,
    output reg  [31:0]  error_detail
);
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_CHECK = 2'd1;
    localparam [1:0] STATE_COMMIT = 2'd2;
    localparam [1:0] STATE_ERROR = 2'd3;
    localparam signed [5:0] PHI_DATA_NORMALIZER_MAX_EXPONENT =
        `RECON_PHI_DATA_NORMALIZER_MAX_EXPONENT;

    reg [1:0] state;
    reg [4:0] check_index;
    wire [31:0] word0 = run_configuration_data[31:0];
    wire [31:0] word1 = run_configuration_data[63:32];
    wire [31:0] word2 = run_configuration_data[95:64];
    wire [31:0] word3 = run_configuration_data[127:96];
    wire [31:0] word5 = run_configuration_data[191:160];
    wire [63:0] measurement_address = run_configuration_data[319:256];
    wire [63:0] dense_result_address = run_configuration_data[383:320];
    wire [63:0] sparse_result_address = run_configuration_data[447:384];
    wire [31:0] word15 = run_configuration_data[511:480];
    wire [1:0] result_mode = word0[29:28];
    wire [1:0] matrix_kind = word0[31:30];
    wire [8:0] measurement_count = word1[8:0];
    wire [10:0] signal_length = word1[19:9];
    wire [6:0] sparsity = word1[26:20];
    wire [7:0] phi_column_weight = {1'b0, word15[29:23]} + 8'd1;
    wire [10:0] measurement_capacity = {2'd0, measurement_count};
    wire [10:0] work_capacity = `RECON_WORK_MAX;
    wire [10:0] base_capacity =
        (measurement_capacity < signal_length) ?
            ((measurement_capacity < work_capacity) ? measurement_capacity : work_capacity) :
            ((signal_length < work_capacity) ? signal_length : work_capacity);
    wire signed [5:0] phi_scale_exponent_signed =
        {word15[22], word15[22:18]};
    reg [35:0] phi_scale_square;
    reg [44:0] phi_norm_product;
    wire signed [6:0] unit_norm_shift = 7'sd34 -
        ({{1{phi_scale_exponent_signed[5]}}, phi_scale_exponent_signed} <<< 1);
    reg [66:0] unit_norm_target_next;
    always @* begin
        if ((unit_norm_shift >= 0) && (unit_norm_shift <= 66))
            unit_norm_target_next = 67'd1 << unit_norm_shift;
        else
            unit_norm_target_next = 67'd0;
    end
    reg [66:0] unit_norm_target;
    wire [66:0] phi_norm_product_extended = {22'd0, phi_norm_product};
    reg [66:0] unit_norm_difference;
    wire [66:0] unit_norm_tolerance = unit_norm_target >> 10;
    wire unit_norm_ok = (unit_norm_target != 0) &&
        (unit_norm_difference <= unit_norm_tolerance);

    assign run_configuration_ready =
        ((state == STATE_COMMIT) && commit_ready) ||
        ((state == STATE_ERROR) && error_ready);
    assign validation_active = (state == STATE_CHECK);
    assign commit_valid = (state == STATE_COMMIT);
    assign commit_data = run_configuration_data;
    assign error_valid = (state == STATE_ERROR);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            check_index <= 5'd0;
            error_code <= 8'd0;
            cfg_error_word <= 5'd0;
            error_detail <= 32'd0;
            phi_scale_square <= 36'd0;
            phi_norm_product <= 45'd0;
            unit_norm_target <= 67'd0;
            unit_norm_difference <= 67'd0;
        end else begin
            if (abort_request) begin
                state <= STATE_IDLE;
                check_index <= 5'd0;
            end else case (state)
                STATE_IDLE: begin
                    if (run_configuration_valid) begin
                        check_index <= 5'd0;
                        state <= STATE_CHECK;
                    end
                end
                STATE_CHECK: begin
                    case (check_index)
                        5'd0: begin
                            if (word0[15:0] != `RECON_RUN_CONFIGURATION_MAGIC) begin
                                error_code <= 8'h01; cfg_error_word <= 5'd0;
                                error_detail <= word0; state <= STATE_ERROR;
                            end else if (word0[23:16] != `RECON_RUN_CONFIGURATION_REVISION) begin
                                error_code <= 8'h02; cfg_error_word <= 5'd0;
                                error_detail <= word0; state <= STATE_ERROR;
                            end else if ((|word0[27:24]) ||
                                         (result_mode > 2'd2) ||
                                         (matrix_kind != `RECON_MATRIX_KIND_DENSE_RADEMACHER)) begin
                                error_code <= 8'h03; cfg_error_word <= 5'd0;
                                error_detail <= word0; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd1: begin
                            if (|word1[31:27]) begin
                                error_code <= 8'h04; cfg_error_word <= 5'd1;
                                error_detail <= word1; state <= STATE_ERROR;
                            end else if (|word5[31:30]) begin
                                error_code <= 8'h04; cfg_error_word <= 5'd5;
                                error_detail <= word5; state <= STATE_ERROR;
                            end else if (word15[31]) begin
                                error_code <= 8'h04; cfg_error_word <= 5'd15;
                                error_detail <= word15; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd2: begin
                            if ((measurement_count == 9'd0) ||
                                (measurement_count > `RECON_M_MAX) ||
                                (signal_length == 11'd0) ||
                                (signal_length > `RECON_N_MAX) ||
                                (sparsity == 7'd0) ||
                                (sparsity > `RECON_K_MAX) ||
                                ({4'd0, sparsity} > base_capacity)) begin
                                error_code <= 8'h10; cfg_error_word <= 5'd1;
                                error_detail <= word1; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd3:
                            check_index <= check_index + 5'd1;
                        5'd4: begin
                            if ((word2[15:0] == 16'd0) ||
                                (word2[23:16] == 8'd0) ||
                                (word2[31:30] > 2'd2)) begin
                                error_code <= 8'h20; cfg_error_word <= 5'd2;
                                error_detail <= word2; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd5: begin
                            if (word3 != 32'd0) begin
                                error_code <= 8'h04; cfg_error_word <= 5'd3;
                                error_detail <= word3; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd6:
                            check_index <= check_index + 5'd1;
                        5'd7: begin
                            if (measurement_address[3:0] != 4'd0) begin
                                error_code <= 8'h30; cfg_error_word <= 5'd8;
                                error_detail <= measurement_address[31:0];
                                state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd8: begin
                            if (((result_mode == 2'd0) || (result_mode == 2'd2)) &&
                                (dense_result_address[3:0] != 4'd0)) begin
                                error_code <= 8'h30; cfg_error_word <= 5'd10;
                                error_detail <= dense_result_address[31:0];
                                state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd9: begin
                            if (((result_mode == 2'd1) || (result_mode == 2'd2)) &&
                                (sparse_result_address[3:0] != 4'd0)) begin
                                error_code <= 8'h30; cfg_error_word <= 5'd12;
                                error_detail <= sparse_result_address[31:0];
                                state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd10: begin
                            if (phi_scale_exponent_signed >
                                PHI_DATA_NORMALIZER_MAX_EXPONENT) begin
                                error_code <= 8'h43; cfg_error_word <= 5'd15;
                                error_detail <= word15; state <= STATE_ERROR;
                            end else if (word15[17:0] < 18'h2_0000) begin
                                error_code <= 8'h40; cfg_error_word <= 5'd15;
                                error_detail <= word15; state <= STATE_ERROR;
                            end else begin
                                phi_scale_square <= word15[17:0] * word15[17:0];
                                unit_norm_target <= unit_norm_target_next;
                                check_index <= check_index + 5'd1;
                            end
                        end
                        5'd11: begin
                            if ((matrix_kind == 2'd0) &&
                                (phi_column_weight != measurement_count)) begin
                                error_code <= 8'h41; cfg_error_word <= 5'd15;
                                error_detail <= {15'd0, measurement_count,
                                                 phi_column_weight};
                                state <= STATE_ERROR;
                            end else begin
                                phi_norm_product <= measurement_count * phi_scale_square;
                                check_index <= check_index + 5'd1;
                            end
                        end
                        5'd12: begin
                            if (phi_norm_product_extended >= unit_norm_target)
                                unit_norm_difference <=
                                    phi_norm_product_extended - unit_norm_target;
                            else
                                unit_norm_difference <=
                                    unit_norm_target - phi_norm_product_extended;
                            check_index <= check_index + 5'd1;
                        end
                        5'd13: begin
                            if (word15[30] && !unit_norm_ok) begin
                                error_code <= 8'h42; cfg_error_word <= 5'd15;
                                error_detail <= word15; state <= STATE_ERROR;
                            end else check_index <= check_index + 5'd1;
                        end
                        5'd15: state <= STATE_COMMIT;
                        default: check_index <= check_index + 5'd1;
                    endcase
                end
                STATE_COMMIT: begin
                    if (commit_ready)
                        state <= STATE_IDLE;
                end
                STATE_ERROR: begin
                    if (error_ready)
                        state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_commit_valid;
    reg f_commit_ready;
    reg [`RECON_RUN_CONFIGURATION_BITS-1:0] f_commit_data;
    reg f_error_valid;
    reg f_error_ready;
    reg [7:0] f_error_code;
    reg [4:0] f_error_word;
    reg [31:0] f_error_detail;
    reg [`RECON_RUN_CONFIGURATION_BITS-1:0] f_run_cfg_data;
    reg f_run_cfg_ready;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_commit_valid <= commit_valid;
        f_commit_ready <= commit_ready;
        f_commit_data <= commit_data;
        f_error_valid <= error_valid;
        f_error_ready <= error_ready;
        f_error_code <= error_code;
        f_error_word <= cfg_error_word;
        f_error_detail <= error_detail;
        f_run_cfg_data <= run_configuration_data;
        f_run_cfg_ready <= run_configuration_ready;
        if (rst_n) begin
            assert(!(commit_valid && error_valid));
            if (abort_request)
                assert(!commit_valid && !error_valid);
            assert(!run_configuration_ready || !validation_active);
            if (f_past_valid &&
                ((state == STATE_CHECK) || (state == STATE_COMMIT) ||
                 (state == STATE_ERROR)) && !f_run_cfg_ready)
                assert(run_configuration_data == f_run_cfg_data);
            if (f_past_valid && f_commit_valid && !f_commit_ready) begin
                assert(commit_valid);
                assert(commit_data == f_commit_data);
            end
            if (f_past_valid && f_error_valid && !f_error_ready) begin
                assert(error_valid);
                assert(error_code == f_error_code);
                assert(cfg_error_word == f_error_word);
                assert(error_detail == f_error_detail);
            end
        end
    end
`endif
endmodule

`default_nettype wire
