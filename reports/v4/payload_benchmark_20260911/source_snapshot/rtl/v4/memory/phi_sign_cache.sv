`include "phi_interface.vh"

module phi_sign_cache (
    input  wire clk,
    input  wire rst,
    input  wire invalidate,
    input  wire begin_valid,
    output wire begin_ready,
    input  wire [`CSR_PHI_ROWS_W-1:0] begin_rows,
    input  wire [`CSR_PHI_COLUMNS_W-1:0] begin_columns,
    input  wire [`CSR_PHI_JOB_TAG_W-1:0] begin_job_tag,
    input  wire [`CSR_PHI_OP_TAG_W-1:0] begin_op_tag,
    input  wire [`CSR_PHI_FORMAT_TAG_W-1:0] begin_format_tag,
    input  wire [`CSR_PHI_GENERATION_W-1:0] begin_generation,
    input  wire [`CSR_PHI_KEY_W-1:0] begin_key,
    output reg  filling,
    input  wire fill_valid,
    output wire fill_ready,
    input  wire [`CSR_PHI_WORD_BITS-1:0] fill_signs,
    input  wire [`CSR_PHI_WORD_BITS-1:0] fill_mask,
    input  wire [`CSR_PHI_COLUMN_W-1:0] fill_column,
    input  wire [`CSR_PHI_ROW_BLOCK_W-1:0] fill_row_block,
    input  wire [`CSR_PHI_JOB_TAG_W-1:0] fill_job_tag,
    input  wire [`CSR_PHI_OP_TAG_W-1:0] fill_op_tag,
    input  wire [`CSR_PHI_FORMAT_TAG_W-1:0] fill_format_tag,
    input  wire [`CSR_PHI_GENERATION_W-1:0] fill_generation,
    input  wire fill_last,
    output reg  cache_valid,
    output reg  published,
    output reg  [`CSR_PHI_KEY_W-1:0] cache_key,
    output reg  [`CSR_PHI_GENERATION_W-1:0] cache_generation,
    output reg  [`CSR_PHI_FAULT_W-1:0] fault_code,
    input  wire rd_valid,
    output wire rd_ready,
    input  wire [`CSR_PHI_BANKS-1:0] rd_bank_mask,
    input  wire [`CSR_PHI_BANKS*`CSR_PHI_ADDR_W-1:0] rd_addresses,
    input  wire [`CSR_PHI_GENERATION_W-1:0] rd_generation,
    input  wire [`CSR_PHI_READ_TAG_W-1:0] rd_tag,
    output wire rsp_valid,
    input  wire rsp_ready,
    output wire [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] rsp_signs,
    output reg  [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] rsp_masks,
    output reg  [`CSR_PHI_BANKS-1:0] rsp_bank_mask,
    output reg  [`CSR_PHI_GENERATION_W-1:0] rsp_generation,
    output reg  [`CSR_PHI_READ_TAG_W-1:0] rsp_tag,
    output reg  [`CSR_PHI_FAULT_W-1:0] rsp_fault
);
    reg [`CSR_PHI_ROWS_W-1:0] rows;
    reg [`CSR_PHI_COLUMNS_W-1:0] cols;
    reg [`CSR_PHI_JOB_TAG_W-1:0] job_tag;
    reg [`CSR_PHI_OP_TAG_W-1:0] op_tag;
    reg [`CSR_PHI_FORMAT_TAG_W-1:0] fmt_tag;
    reg [`CSR_PHI_COLUMN_W-1:0] wr_col;
    reg [`CSR_PHI_ROW_BLOCK_W-1:0] wr_block;
    reg [`CSR_PHI_WORD_BITS-1:0] wr_mask;
    reg [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] rd_masks;
    reg rd_good;
    reg rsp_pending;
    integer blocks;
    reg [`CSR_PHI_ADDR_W-1:0] wr_addr;
    integer bank;
    integer lane;
    integer addr;
    integer block_idx;
    integer col_idx;

    wire active = !rst && !invalidate;
    wire wr_last = int'(wr_col) + 1 == int'(cols) && int'(wr_block) + 1 == blocks;
    wire fill_good = fill_column == wr_col && fill_row_block == wr_block &&
        fill_mask == wr_mask && (fill_signs & ~wr_mask) == 0 &&
        fill_job_tag == job_tag && fill_op_tag == op_tag &&
        fill_format_tag == fmt_tag && fill_generation == cache_generation &&
        fill_last == wr_last;
    wire wr_en = fill_valid && fill_ready && fill_good;
    wire rd_en = rd_valid && rd_ready;

    assign begin_ready = active && !filling && !rsp_valid;
    assign fill_ready = active && filling;
    assign rsp_valid = active && rsp_pending;
    assign rd_ready = active && cache_valid && !filling && (!rsp_pending || rsp_ready) && !begin_valid;

    always @* begin
        blocks = (int'(rows) + `CSR_PHI_WORD_BITS - 1) / `CSR_PHI_WORD_BITS;
        wr_addr = `CSR_PHI_ADDR_W'((int'(wr_col) / `CSR_PHI_BANKS) * blocks + int'(wr_block));
        wr_mask = '0;
        for (lane = 0; lane < `CSR_PHI_WORD_BITS; lane = lane + 1)
            if (int'(wr_block) * `CSR_PHI_WORD_BITS + lane < int'(rows))
                wr_mask[lane] = 1'b1;
        rd_good = rd_bank_mask != 0 && rd_generation == cache_generation && blocks != 0;
        rd_masks = '0;
        addr = 0;
        block_idx = 0;
        col_idx = 0;
        for (bank = 0; bank < `CSR_PHI_BANKS; bank = bank + 1) begin
            addr = int'(rd_addresses[bank*`CSR_PHI_ADDR_W +: `CSR_PHI_ADDR_W]);
            if (rd_bank_mask[bank] && blocks != 0) begin
                case (blocks)
                    1: begin col_idx = addr; block_idx = 0; end
                    2: begin col_idx = addr >> 1; block_idx = addr & 1; end
                    3: begin col_idx = addr / 3; block_idx = addr % 3; end
                    4: begin col_idx = addr >> 2; block_idx = addr & 3; end
                    default: begin col_idx = 0; block_idx = 0; end
                endcase
                col_idx = col_idx * `CSR_PHI_BANKS + bank;
                if (col_idx >= int'(cols))
                    rd_good = 1'b0;
                for (lane = 0; lane < `CSR_PHI_WORD_BITS; lane = lane + 1)
                    if (block_idx * `CSR_PHI_WORD_BITS + lane < int'(rows))
                        rd_masks[bank*`CSR_PHI_WORD_BITS + lane] = 1'b1;
            end
        end
    end

    genvar bank_id;
    generate
        for (bank_id = 0; bank_id < `CSR_PHI_BANKS; bank_id = bank_id + 1) begin : banks
            reg [`CSR_PHI_WORD_BITS-1:0] mem [0:`CSR_PHI_BANK_DEPTH-1];
            reg [`CSR_PHI_WORD_BITS-1:0] data;
            assign rsp_signs[bank_id*`CSR_PHI_WORD_BITS +: `CSR_PHI_WORD_BITS] = data;
            always @(posedge clk) begin
                if (wr_en && int'(wr_col) % `CSR_PHI_BANKS == bank_id)
                    mem[wr_addr] <= fill_signs;
                if (rst || invalidate)
                    data <= '0;
                else if (rd_en) begin
                    if (rd_good && rd_bank_mask[bank_id])
                        data <= mem[rd_addresses[bank_id*`CSR_PHI_ADDR_W +: `CSR_PHI_ADDR_W]];
                    else
                        data <= '0;
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst || invalidate) begin
            rows <= '0;
            cols <= '0;
            job_tag <= '0;
            op_tag <= '0;
            fmt_tag <= '0;
            wr_col <= '0;
            wr_block <= '0;
            filling <= 1'b0;
            cache_valid <= 1'b0;
            published <= 1'b0;
            cache_key <= '0;
            cache_generation <= '0;
            fault_code <= `CSR_PHI_FAULT_NONE;
            rsp_pending <= 1'b0;
            rsp_masks <= '0;
            rsp_bank_mask <= '0;
            rsp_generation <= '0;
            rsp_tag <= '0;
            rsp_fault <= `CSR_PHI_FAULT_NONE;
        end else begin
            published <= 1'b0;
            if (rsp_valid && rsp_ready)
                rsp_pending <= 1'b0;
            if (begin_valid && begin_ready) begin
                cache_valid <= 1'b0;
                fault_code <= `CSR_PHI_FAULT_NONE;
                if (begin_rows == 0 || int'(begin_rows) > `CSR_PHI_MAX_ROWS ||
                    begin_columns == 0 || int'(begin_columns) > `CSR_PHI_MAX_COLUMNS) begin
                    fault_code <= `CSR_PHI_FAULT_DESCRIPTOR;
                end else begin
                    rows <= begin_rows;
                    cols <= begin_columns;
                    job_tag <= begin_job_tag;
                    op_tag <= begin_op_tag;
                    fmt_tag <= begin_format_tag;
                    cache_key <= begin_key;
                    cache_generation <= begin_generation;
                    wr_col <= '0;
                    wr_block <= '0;
                    filling <= 1'b1;
                end
            end else if (fill_valid && fill_ready) begin
                if (!fill_good) begin
                    fault_code <= `CSR_PHI_FAULT_FILL;
                    filling <= 1'b0;
                    cache_valid <= 1'b0;
                end else if (wr_last) begin
                    filling <= 1'b0;
                    cache_valid <= 1'b1;
                    published <= 1'b1;
                end else if (int'(wr_block) + 1 == blocks) begin
                    wr_block <= '0;
                    wr_col <= wr_col + 1'b1;
                end else begin
                    wr_block <= wr_block + 1'b1;
                end
            end else if (rd_en) begin
                rsp_pending <= 1'b1;
                rsp_masks <= rd_good ? rd_masks : '0;
                rsp_bank_mask <= rd_bank_mask;
                rsp_generation <= rd_generation;
                rsp_tag <= rd_tag;
                rsp_fault <= rd_good ? `CSR_PHI_FAULT_NONE : `CSR_PHI_FAULT_READ;
                if (!rd_good)
                    fault_code <= `CSR_PHI_FAULT_READ;
            end
        end
    end
endmodule
