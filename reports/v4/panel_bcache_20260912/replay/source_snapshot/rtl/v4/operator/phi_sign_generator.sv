`include "phi_interface.vh"

module phi_sign_generator (
    input  wire clk,
    input  wire rst,
    input  wire cancel,
    input  wire start_valid,
    output wire start_ready,
    input  wire [7:0] start_family,
    input  wire [7:0] start_revision,
    input  wire [31:0] start_seed,
    input  wire [`CSR_PHI_ROWS_W-1:0] start_rows,
    input  wire [`CSR_PHI_COLUMNS_W-1:0] start_columns,
    input  wire [`CSR_PHI_JOB_TAG_W-1:0] start_job_tag,
    input  wire [`CSR_PHI_OP_TAG_W-1:0] start_op_tag,
    input  wire [`CSR_PHI_FORMAT_TAG_W-1:0] start_format_tag,
    input  wire [`CSR_PHI_GENERATION_W-1:0] start_generation,
    output reg  busy,
    output wire out_valid,
    input  wire out_ready,
    output reg  [`CSR_PHI_WORD_BITS-1:0] out_signs,
    output reg  [`CSR_PHI_WORD_BITS-1:0] out_mask,
    output reg  [`CSR_PHI_COLUMN_W-1:0] out_column,
    output reg  [`CSR_PHI_ROW_BLOCK_W-1:0] out_row_block,
    output reg  [`CSR_PHI_JOB_TAG_W-1:0] out_job_tag,
    output reg  [`CSR_PHI_OP_TAG_W-1:0] out_op_tag,
    output reg  [`CSR_PHI_FORMAT_TAG_W-1:0] out_format_tag,
    output reg  [`CSR_PHI_GENERATION_W-1:0] out_generation,
    output wire out_last,
    output reg  done,
    output reg  [`CSR_PHI_FAULT_W-1:0] fault_code
);
    reg [`CSR_PHI_ROWS_W-1:0] rows;
    reg [`CSR_PHI_COLUMNS_W-1:0] cols;
    reg [31:0] state;
    reg [31:0] next_state;
    integer lane;
    integer row_base;
    wire col_last = (int'(out_row_block) + 1) * `CSR_PHI_WORD_BITS >= int'(rows);

    assign start_ready = !rst && !cancel && !busy;
    assign out_valid = busy && !rst && !cancel;
    assign out_last = col_last && (int'(out_column) + 1 == int'(cols));

    always @* begin
        next_state = state;
        out_signs = '0;
        out_mask = '0;
        row_base = int'(out_row_block) * `CSR_PHI_WORD_BITS;
        for (lane = 0; lane < `CSR_PHI_WORD_BITS; lane = lane + 1) begin
            if (row_base + lane < int'(rows)) begin
                out_signs[lane] = next_state[0];
                out_mask[lane] = 1'b1;
                next_state = (next_state >> 1) ^ (next_state[0] ? `CSR_PHI_TAPS : 32'b0);
            end
        end
    end

    always @(posedge clk) begin
        if (rst || cancel) begin
            busy <= 1'b0;
            done <= 1'b0;
            fault_code <= `CSR_PHI_FAULT_NONE;
            rows <= '0;
            cols <= '0;
            state <= '0;
            out_column <= '0;
            out_row_block <= '0;
            out_job_tag <= '0;
            out_op_tag <= '0;
            out_format_tag <= '0;
            out_generation <= '0;
        end else begin
            done <= 1'b0;
            if (start_valid && start_ready) begin
                fault_code <= `CSR_PHI_FAULT_NONE;
                if (start_family != 8'(`CSR_PHI_FAMILY) ||
                    start_revision != 8'(`CSR_PHI_REVISION) ||
                    start_rows == 0 || int'(start_rows) > `CSR_PHI_MAX_ROWS ||
                    start_columns == 0 || int'(start_columns) > `CSR_PHI_MAX_COLUMNS) begin
                    fault_code <= `CSR_PHI_FAULT_DESCRIPTOR;
                end else begin
                    busy <= 1'b1;
                    rows <= start_rows;
                    cols <= start_columns;
                    state <= start_seed == 0 ? `CSR_PHI_DEFAULT_SEED : start_seed;
                    out_column <= '0;
                    out_row_block <= '0;
                    out_job_tag <= start_job_tag;
                    out_op_tag <= start_op_tag;
                    out_format_tag <= start_format_tag;
                    out_generation <= start_generation;
                end
            end else if (out_valid && out_ready) begin
                state <= next_state;
                if (out_last) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else if (col_last) begin
                    out_column <= out_column + 1'b1;
                    out_row_block <= '0;
                end else begin
                    out_row_block <= out_row_block + 1'b1;
                end
            end
        end
    end
endmodule
