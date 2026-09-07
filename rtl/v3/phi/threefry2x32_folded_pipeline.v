`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"

module threefry2x32_folded_pipeline (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         flush,
    input  wire         request_valid,
    output wire         request_ready,
    input  wire [63:0]  request_seed,
    input  wire [`RECON_PHI_COLUMN_W-1:0] request_column,
    input  wire [`RECON_PHI_ROW_PAIR_W-1:0] request_row_pair,
    input  wire [`RECON_PHI_TAG_W-1:0] request_tag,
    input  wire [8:0]   request_measurement_count,
    output wire         response_valid,
    input  wire         response_ready,
    output wire [31:0]  response_word0,
    output wire [31:0]  response_word1,
    output wire [`RECON_PHI_COLUMN_W-1:0] response_column,
    output wire [`RECON_PHI_ROW_PAIR_W-1:0] response_row_pair,
    output wire [`RECON_PHI_TAG_W-1:0] response_tag,
    output wire [8:0]   response_measurement_count
);
    localparam [31:0] PARITY = 32'h1bd11bda;
    localparam integer STAGES = 10;

    function [4:0] rotation_amount;
        input integer round_index;
        begin
            case (round_index & 7)
                0: rotation_amount = 5'd13;
                1: rotation_amount = 5'd15;
                2: rotation_amount = 5'd26;
                3: rotation_amount = 5'd6;
                4: rotation_amount = 5'd17;
                5: rotation_amount = 5'd29;
                6: rotation_amount = 5'd16;
                default: rotation_amount = 5'd24;
            endcase
        end
    endfunction

    function [63:0] round_value;
        input [31:0] input_x0;
        input [31:0] input_x1;
        input [31:0] key0;
        input [31:0] key1;
        input [31:0] key2;
        input integer round_index;
        reg [31:0] mixed_x0;
        reg [31:0] mixed_x1;
        reg [31:0] rotated;
        reg [31:0] injection_key0;
        reg [31:0] injection_key1;
        integer injection;
        begin
            mixed_x0 = input_x0 + input_x1;
            rotated = (input_x1 << rotation_amount(round_index)) |
                      (input_x1 >> (32 - rotation_amount(round_index)));
            mixed_x1 = rotated ^ mixed_x0;
            if (((round_index + 1) & 3) == 0) begin
                injection = (round_index + 1) >> 2;
                case (injection % 3)
                    0: injection_key0 = key0;
                    1: injection_key0 = key1;
                    default: injection_key0 = key2;
                endcase
                case ((injection + 1) % 3)
                    0: injection_key1 = key0;
                    1: injection_key1 = key1;
                    default: injection_key1 = key2;
                endcase
                mixed_x0 = mixed_x0 + injection_key0;
                mixed_x1 = mixed_x1 + injection_key1 + injection;
            end
            round_value = {mixed_x1, mixed_x0};
        end
    endfunction

    reg stage_valid [0:STAGES-1];
    reg stage_second_pass [0:STAGES-1];
    reg [31:0] stage_x0 [0:STAGES-1];
    reg [31:0] stage_x1 [0:STAGES-1];
    reg [31:0] stage_key0 [0:STAGES-1];
    reg [31:0] stage_key1 [0:STAGES-1];
    reg [31:0] stage_key2 [0:STAGES-1];
    reg [`RECON_PHI_COLUMN_W-1:0] stage_column [0:STAGES-1];
    reg [`RECON_PHI_ROW_PAIR_W-1:0] stage_row_pair [0:STAGES-1];
    reg [`RECON_PHI_TAG_W-1:0] stage_tag [0:STAGES-1];
    reg [8:0] stage_measurement_count [0:STAGES-1];

    reg feedback_valid;
    reg [31:0] feedback_x0;
    reg [31:0] feedback_x1;
    reg [31:0] feedback_key0;
    reg [31:0] feedback_key1;
    reg [31:0] feedback_key2;
    reg [`RECON_PHI_COLUMN_W-1:0] feedback_column;
    reg [`RECON_PHI_ROW_PAIR_W-1:0] feedback_row_pair;
    reg [`RECON_PHI_TAG_W-1:0] feedback_tag;
    reg [8:0] feedback_measurement_count;
    reg external_phase;

    assign response_valid = stage_valid[STAGES-1] &&
                            stage_second_pass[STAGES-1];
    assign response_word0 = stage_x0[STAGES-1];
    assign response_word1 = stage_x1[STAGES-1];
    assign response_column = stage_column[STAGES-1];
    assign response_row_pair = stage_row_pair[STAGES-1];
    assign response_tag = stage_tag[STAGES-1];
    assign response_measurement_count = stage_measurement_count[STAGES-1];

    wire pipeline_advance = !response_valid || response_ready;
    assign request_ready = pipeline_advance && external_phase;
    wire request_fire = request_valid && request_ready;
    wire [31:0] request_key0 = request_seed[31:0];
    wire [31:0] request_key1 = request_seed[63:32];
    wire [31:0] request_key2 = PARITY ^ request_seed[31:0] ^ request_seed[63:32];
    wire [31:0] request_x0 = {22'd0, request_column} + request_key0;
    wire [31:0] request_x1 = {29'd0, request_row_pair} + request_key1;
    wire [63:0] request_mixed = round_value(
        request_x0, request_x1,
        request_key0, request_key1, request_key2, 0);
    wire [63:0] feedback_mixed = round_value(
        feedback_x0, feedback_x1,
        feedback_key0, feedback_key1, feedback_key2, 10);

    wire [63:0] stage_mixed [1:STAGES-1];
    genvar mix_index;
    generate
        for (mix_index = 1; mix_index < STAGES; mix_index = mix_index + 1) begin : g_stage_mix
            assign stage_mixed[mix_index] = round_value(
                stage_x0[mix_index-1], stage_x1[mix_index-1],
                stage_key0[mix_index-1], stage_key1[mix_index-1],
                stage_key2[mix_index-1],
                (stage_second_pass[mix_index-1] ? 10 : 0) + mix_index);
        end
    endgenerate

    integer index;
    always @(posedge clk) begin
        if (!rst_n || flush) begin
            external_phase <= 1'b1;
            feedback_valid <= 1'b0;
            for (index = 0; index < STAGES; index = index + 1)
                stage_valid[index] <= 1'b0;
        end else if (pipeline_advance) begin
            external_phase <= !external_phase;

            if (stage_valid[STAGES-1] && !stage_second_pass[STAGES-1]) begin
                feedback_valid <= 1'b1;
                feedback_x0 <= stage_x0[STAGES-1];
                feedback_x1 <= stage_x1[STAGES-1];
                feedback_key0 <= stage_key0[STAGES-1];
                feedback_key1 <= stage_key1[STAGES-1];
                feedback_key2 <= stage_key2[STAGES-1];
                feedback_column <= stage_column[STAGES-1];
                feedback_row_pair <= stage_row_pair[STAGES-1];
                feedback_tag <= stage_tag[STAGES-1];
                feedback_measurement_count <= stage_measurement_count[STAGES-1];
            end else if (!external_phase && feedback_valid) begin
                feedback_valid <= 1'b0;
            end

            for (index = STAGES-1; index > 0; index = index - 1) begin
                stage_valid[index] <= stage_valid[index-1];
                stage_second_pass[index] <= stage_second_pass[index-1];
                stage_x0[index] <= stage_mixed[index][31:0];
                stage_x1[index] <= stage_mixed[index][63:32];
                stage_key0[index] <= stage_key0[index-1];
                stage_key1[index] <= stage_key1[index-1];
                stage_key2[index] <= stage_key2[index-1];
                stage_column[index] <= stage_column[index-1];
                stage_row_pair[index] <= stage_row_pair[index-1];
                stage_tag[index] <= stage_tag[index-1];
                stage_measurement_count[index] <= stage_measurement_count[index-1];
            end

            stage_valid[0] <= 1'b0;
            if (external_phase && request_fire) begin
                stage_valid[0] <= 1'b1;
                stage_second_pass[0] <= 1'b0;
                stage_x0[0] <= request_mixed[31:0];
                stage_x1[0] <= request_mixed[63:32];
                stage_key0[0] <= request_key0;
                stage_key1[0] <= request_key1;
                stage_key2[0] <= request_key2;
                stage_column[0] <= request_column;
                stage_row_pair[0] <= request_row_pair;
                stage_tag[0] <= request_tag;
                stage_measurement_count[0] <= request_measurement_count;
            end else if (!external_phase && feedback_valid) begin
                stage_valid[0] <= 1'b1;
                stage_second_pass[0] <= 1'b1;
                stage_x0[0] <= feedback_mixed[31:0];
                stage_x1[0] <= feedback_mixed[63:32];
                stage_key0[0] <= feedback_key0;
                stage_key1[0] <= feedback_key1;
                stage_key2[0] <= feedback_key2;
                stage_column[0] <= feedback_column;
                stage_row_pair[0] <= feedback_row_pair;
                stage_tag[0] <= feedback_tag;
                stage_measurement_count[0] <= feedback_measurement_count;
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [31:0] f_word0;
    reg [31:0] f_word1;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled && !flush) begin
            assert(response_valid);
            assert(response_word0 == f_word0);
            assert(response_word1 == f_word1);
            assert(response_tag == f_tag);
        end
        f_stalled <= (!rst_n || flush) ? 1'b0 :
                     (response_valid && !response_ready);
        f_word0 <= response_word0;
        f_word1 <= response_word1;
        f_tag <= response_tag;
    end
`endif
endmodule

`default_nettype wire
