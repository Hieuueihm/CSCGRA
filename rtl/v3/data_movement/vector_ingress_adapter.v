`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

module vector_ingress_adapter #(
    parameter integer DATA_W = `RECON_SOLVER_W
)(
    input wire clk,
    input wire rst_n,
    input wire routine_start,
    input wire abort_flush,
    input wire restart,
    input wire cycle_valid,
    input wire cycle_commit,
    input wire vector_cycle_commit,
    input wire vector_a_enable,
    input wire vector_b_enable,
    input wire vector_write_enable,
    input wire stream_a_metadata_valid,
    input wire [2:0] stream_a_format,
    input wire [2:0] stream_a_packing,
    input wire stream_b_metadata_valid,
    input wire [2:0] stream_b_format,
    input wire [2:0] stream_b_packing,
    input wire [1:0] external_a_select,
    input wire [4:0] resource_operation,
    input wire [4:0] tile_operation,
    input wire [2:0] phi_mode,
    input wire [8:0] measurement_count,
    input wire [6:0] work_count,
    input wire physical_a_valid,
    input wire physical_b_valid,
    input wire [32*DATA_W-1:0] expanded_a,
    input wire [15:0] sidecar_a_valid,
    input wire [15:0] sidecar_b_valid,
    input wire [16*DATA_W-1:0] sidecar_a,
    input wire [16*DATA_W-1:0] sidecar_b,
    input wire scalar_broadcast_valid,
    input wire signed [DATA_W-1:0] scalar_broadcast_data,
    input wire candidate_mode,
    input wire candidate_valid,
    input wire candidate_ready,
    input wire candidate_final_lane,
    input wire transpose_write_mode,
    input wire transpose_write_release,
    output wire support_mode,
    output wire d18_mode,
    output wire d18_valid,
    output wire [15:0] d18_lane_valid,
    output wire [16*DATA_W-1:0] d18_solver_data,
    output wire scalar_a_valid,
    output wire signed [DATA_W-1:0] scalar_a_data,
    output wire scalar_b_valid,
    output wire signed [DATA_W-1:0] scalar_b_data,
    output wire vector_a_valid,
    output wire [32*DATA_W-1:0] vector_a_data,
    output wire transport_commit
);
    reg [3:0] support_index;
    reg [6:0] support_count;
    reg [16*DATA_W-1:0] support_pack;
    reg support_pack_valid;

    reg [32*DATA_W-1:0] d18_buffer;
    reg d18_buffer_valid;
    reg d18_high_half;
    reg [8:0] d18_base;

    reg [16*DATA_W-1:0] transpose_low;
    reg [16*DATA_W-1:0] transpose_high;
    reg transpose_low_valid;
    reg transpose_high_valid;

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
                  (`RECON_SOLVER_F-`RECON_DATA_F-1))) >>
                (`RECON_SOLVER_F-`RECON_DATA_F);
            if (value[DATA_W-1]) begin
                if (rounded_magnitude >=
                        ({{DATA_W{1'b0}}, 1'b1} << (`RECON_DATA_W-1)))
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
                         data_value}) <<<
                (`RECON_SOLVER_F-`RECON_DATA_F);
        end
    endfunction

    wire support_payload_mode = vector_a_enable && stream_a_metadata_valid &&
        (stream_a_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (stream_a_packing == `RECON_PACKING_MODE_TWO);
    assign support_mode = support_payload_mode &&
        (external_a_select == `RECON_EXTERNAL_STREAM_SOURCE_SCALAR_BROADCAST);
    wire support_capture = support_mode && physical_a_valid &&
        (&sidecar_a_valid) && !support_pack_valid;
    wire support_valid = support_mode && support_pack_valid;
    wire residual_support_mode = support_mode &&
        (tile_operation == `RECON_TILE_OP_PHI_DATA_ACCUMULATE);
    wire signed [DATA_W-1:0] support_data = residual_support_mode ?
        canonical_data_coefficient(support_pack[DATA_W-1:0]) :
        support_pack[DATA_W-1:0];
    wire support_final =
        ({1'b0, support_count} + 8'd1 == {1'b0, work_count});
    wire support_release = (support_index == 4'd15) || support_final;

    assign d18_mode = vector_a_enable && stream_a_metadata_valid &&
        (stream_a_format == `RECON_ELEMENT_FORMAT_DATA18) &&
        (stream_a_packing == `RECON_PACKING_MODE_FOUR) &&
        ((resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_NORM_SQ) ||
         (resource_operation == `RECON_RESOURCE_OP_SHARED_VECTOR_COPY));
    wire d18_capture = cycle_valid && d18_mode && physical_a_valid &&
        !d18_buffer_valid;
    wire [16*DATA_W-1:0] d18_selected = d18_high_half ?
        d18_buffer[16*DATA_W +: 16*DATA_W] :
        d18_buffer[0 +: 16*DATA_W];
    assign d18_valid = d18_buffer_valid;

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_d18
            wire signed [DATA_W-1:0] source_value =
                d18_selected[lane*DATA_W +: DATA_W];
            assign d18_solver_data[lane*DATA_W +: DATA_W] =
                source_value <<< (`RECON_SOLVER_F-`RECON_DATA_F);
            assign d18_lane_valid[lane] =
                ({1'b0, d18_base} + lane) < {1'b0, measurement_count};
        end
    endgenerate

    assign scalar_a_valid = support_payload_mode ?
        support_valid : scalar_broadcast_valid;
    assign scalar_a_data = support_payload_mode ?
        support_data : scalar_broadcast_data;
    assign scalar_b_valid = support_mode ?
        support_valid : scalar_broadcast_valid;
    assign scalar_b_data = support_mode ?
        support_data : scalar_broadcast_data;

    wire transpose_mode = vector_a_enable &&
        (external_a_select == `RECON_EXTERNAL_STREAM_SOURCE_VECTOR_A) &&
        stream_a_metadata_valid &&
        (stream_a_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (stream_a_packing == `RECON_PACKING_MODE_TWO) &&
        (phi_mode == 3'd3);
    wire transpose_pair_mode = transpose_mode && vector_b_enable &&
        stream_b_metadata_valid &&
        (stream_b_format == `RECON_ELEMENT_FORMAT_SOLVER27) &&
        (stream_b_packing == `RECON_PACKING_MODE_TWO);
    wire transpose_pair_valid = physical_a_valid && physical_b_valid &&
        (&sidecar_a_valid) && (&sidecar_b_valid);
    wire transpose_low_capture = cycle_valid && transpose_mode &&
        !transpose_pair_mode && !transpose_low_valid && physical_a_valid &&
        (&sidecar_a_valid);
    wire transpose_high_capture = cycle_valid && transpose_mode &&
        !transpose_pair_mode && transpose_low_valid &&
        !transpose_high_valid && physical_a_valid && (&sidecar_a_valid);
    wire transpose_valid = transpose_low_valid && transpose_high_valid;

    assign vector_a_data = transpose_pair_mode ?
        {sidecar_b, sidecar_a} : transpose_mode ?
        {transpose_high, transpose_low} :
        d18_mode ? d18_buffer : expanded_a;
    assign vector_a_valid = transpose_pair_mode ?
        transpose_pair_valid : transpose_mode ?
        transpose_valid : d18_mode ? d18_buffer_valid : physical_a_valid;
    assign transport_commit = transpose_low_capture ||
        (vector_cycle_commit &&
         (!support_mode || support_release) &&
         (!d18_mode || d18_high_half) &&
         (!candidate_mode ||
          (candidate_valid && candidate_ready && candidate_final_lane)) &&
         (!vector_write_enable || !transpose_write_mode ||
          transpose_write_release));

    always @(posedge clk) begin
        if (!rst_n || routine_start || abort_flush) begin
            support_index <= 4'd0;
            support_count <= 7'd0;
            support_pack <= {16*DATA_W{1'b0}};
            support_pack_valid <= 1'b0;
            d18_buffer <= {32*DATA_W{1'b0}};
            d18_buffer_valid <= 1'b0;
            d18_high_half <= 1'b0;
            d18_base <= 9'd0;
            transpose_low <= {16*DATA_W{1'b0}};
            transpose_high <= {16*DATA_W{1'b0}};
            transpose_low_valid <= 1'b0;
            transpose_high_valid <= 1'b0;
        end else begin
            if (restart) begin
                transpose_low <= {16*DATA_W{1'b0}};
                transpose_high <= {16*DATA_W{1'b0}};
                transpose_low_valid <= 1'b0;
                transpose_high_valid <= 1'b0;
            end else begin
                if (transpose_low_capture) begin
                    transpose_low <= sidecar_a;
                    transpose_low_valid <= 1'b1;
                end
                if (transpose_high_capture) begin
                    transpose_high <= sidecar_a;
                    transpose_high_valid <= 1'b1;
                end
                if (cycle_valid && cycle_commit && transpose_mode) begin
                    transpose_low <= {16*DATA_W{1'b0}};
                    transpose_high <= {16*DATA_W{1'b0}};
                    transpose_low_valid <= 1'b0;
                    transpose_high_valid <= 1'b0;
                end
            end

            if (restart) begin
                support_index <= 4'd0;
                support_count <= 7'd0;
                support_pack <= {16*DATA_W{1'b0}};
                support_pack_valid <= 1'b0;
                d18_buffer <= {32*DATA_W{1'b0}};
                d18_buffer_valid <= 1'b0;
                d18_high_half <= 1'b0;
                d18_base <= 9'd0;
            end else begin
                if (d18_capture) begin
                    d18_buffer <= expanded_a;
                    d18_buffer_valid <= 1'b1;
                end
                if (cycle_valid && cycle_commit && d18_mode) begin
                    d18_base <= d18_base + 9'd16;
                    if (d18_high_half) begin
                        d18_buffer_valid <= 1'b0;
                        d18_high_half <= 1'b0;
                    end else begin
                        d18_high_half <= 1'b1;
                    end
                end
                if (support_capture) begin
                    support_pack <= sidecar_a;
                    support_pack_valid <= 1'b1;
                end
                if (cycle_valid && cycle_commit && support_mode) begin
                    if (support_final) begin
                        support_index <= 4'd0;
                        support_count <= 7'd0;
                    end else begin
                        support_count <= support_count + 1'b1;
                        support_index <= support_release ?
                            4'd0 : support_index + 1'b1;
                    end
                    if (support_release) begin
                        support_pack <= {16*DATA_W{1'b0}};
                        support_pack_valid <= 1'b0;
                    end else begin
                        support_pack <=
                            {{DATA_W{1'b0}},
                             support_pack[16*DATA_W-1:DATA_W]};
                    end
                end
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            if (cycle_commit && transpose_pair_mode) begin
                assert(transpose_pair_valid);
                assert(!transpose_low_valid);
                assert(!transpose_high_valid);
            end
            if (transpose_low_capture || transpose_high_capture)
                assert(!transpose_pair_mode);
        end
    end
`endif
endmodule

`default_nettype wire
