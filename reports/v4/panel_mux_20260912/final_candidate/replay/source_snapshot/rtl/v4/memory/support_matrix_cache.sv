`include "memory_defs.vh"

module support_matrix_cache (
    input wire clk, rst, cancel,
    input wire begin_valid,
    output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [6:0] begin_cols,
    input wire [127:0] begin_key,
    input wire [31:0] begin_generation,
    input wire [15:0] begin_job,
    input wire [7:0] begin_fmt,
    input wire fill_valid,
    output wire fill_ready,
    input wire [6:0] fill_slot,
    input wire [1:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [32*`CSR_PE_C_W-1:0] fill_data,
    input wire fill_last,
    output reg loading, cache_valid,
    output reg [3:0] load_fault,
    input wire rd_valid,
    output wire rd_ready,
    input wire [31:0] rd_mask,
    input wire [32*`CSR_MEM_B_AW-1:0] rd_addr,
    input wire [127:0] rd_key,
    input wire [31:0] rd_generation,
    input wire [15:0] rd_job, rd_tag,
    input wire [7:0] rd_fmt,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [32*`CSR_PE_C_W-1:0] rsp_data,
    output reg [31:0] rsp_mask,
    output reg [31:0] rsp_generation,
    output reg [15:0] rsp_job, rsp_tag,
    output reg [7:0] rsp_fmt,
    output reg [3:0] rsp_fault
);
    localparam integer CW = `CSR_PE_C_W;
    reg [7:0] rows;
    reg [6:0] cols, next_slot;
    reg [1:0] next_block;
    reg [127:0] key;
    reg [31:0] generation;
    reg [15:0] job;
    reg [7:0] fmt;
    reg pending;
    reg [31:0] expected_mask;
    reg padding_bad;
    reg [3:0] read_fault;
    integer groups, bank_id, lane_id, address, row_idx, col_idx;
    wire active = !rst && !cancel;
    wire last_block = (int'(next_block)+1)*32 >= int'(rows);
    wire last_word = last_block && next_slot+1 == cols;
    wire fill_good = fill_slot == next_slot && fill_block == next_block && fill_mask == expected_mask &&
                     fill_last == last_word && !padding_bad;
    wire write_en = fill_valid && fill_ready && fill_good;
    wire take = rd_valid && rd_ready;
    assign begin_ready = active && !loading && !pending;
    assign fill_ready = active && loading;
    assign rd_ready = active && !loading && !pending && !begin_valid;
    assign rsp_valid = active && pending;
    always @* begin
        groups = (int'(cols)+31)/32;
        if (groups == 0) groups = 1;
        expected_mask = '0; padding_bad = 1'b0; read_fault = '0;
        address = 0; row_idx = 0; col_idx = 0;
        for (lane_id = 0; lane_id < 32; lane_id = lane_id + 1) begin
            expected_mask[lane_id] = int'(next_block)*32+lane_id < int'(rows);
            if (!expected_mask[lane_id] && fill_data[lane_id*CW +: CW] != 0) padding_bad = 1'b1;
        end
        if (!cache_valid || key != rd_key || generation != rd_generation || job != rd_job || fmt != rd_fmt)
            read_fault = `CSR_MEM_FAULT_KEY;
        else begin
            for (bank_id = 0; bank_id < 32; bank_id = bank_id + 1) begin
                address = int'(rd_addr[bank_id*9 +: 9]);
                row_idx = address/groups;
                col_idx = (address%groups)*32 + (bank_id+32-row_idx%32)%32;
                if (rd_mask[bank_id] && (address >= `CSR_MEM_B_DEPTH || row_idx >= int'(rows) || col_idx >= int'(cols)))
                    read_fault = `CSR_MEM_FAULT_RANGE;
            end
        end
    end
    genvar bank;
    generate
        for (bank = 0; bank < 32; bank = bank + 1) begin : bank_mem
            reg [CW-1:0] ram [0:`CSR_MEM_B_DEPTH-1];
            reg [CW-1:0] data;
            wire [4:0] lane = 5'(bank-int'(next_slot));
            wire [8:0] wr_addr = 9'((int'(next_block)*32+int'(lane))*groups+int'(next_slot)/32);
            assign rsp_data[bank*CW +: CW] = data;
            always @(posedge clk) begin
                if (write_en && fill_mask[lane]) ram[wr_addr] <= fill_data[int'(lane)*CW +: CW];
                if (!active) data <= '0;
                else if (take) data <= read_fault == 0 && rd_mask[bank] ? ram[rd_addr[bank*9 +: 9]] : {CW{1'b0}};
            end
        end
    endgenerate
    always @(posedge clk) begin
        if (!active) begin
            loading <= 1'b0; cache_valid <= 1'b0; load_fault <= '0; pending <= 1'b0;
            rows <= '0; cols <= '0; key <= '0; generation <= '0; job <= '0; fmt <= '0;
            next_slot <= '0; next_block <= '0;
            rsp_mask <= '0; rsp_generation <= '0; rsp_job <= '0; rsp_tag <= '0; rsp_fmt <= '0; rsp_fault <= '0;
        end else begin
            if (begin_valid && begin_ready) begin
                cache_valid <= 1'b0; load_fault <= '0; next_slot <= '0; next_block <= '0;
                if (begin_rows == 0 || begin_rows > `CSR_MEM_B_ROWS || begin_cols == 0 || begin_cols > `CSR_MEM_B_COLS)
                    load_fault <= `CSR_MEM_FAULT_SHAPE;
                else begin
                    loading <= 1'b1; rows <= begin_rows; cols <= begin_cols;
                    key <= begin_key; generation <= begin_generation; job <= begin_job; fmt <= begin_fmt;
                end
            end
            if (fill_valid && fill_ready) begin
                if (!fill_good) begin loading <= 1'b0; load_fault <= `CSR_MEM_FAULT_STREAM; end
                else if (last_word) begin loading <= 1'b0; cache_valid <= 1'b1; end
                else if (last_block) begin next_block <= '0; next_slot <= next_slot + 1'b1; end
                else next_block <= next_block + 1'b1;
            end
            if (rsp_valid && rsp_ready) pending <= 1'b0;
            if (take) begin
                pending <= 1'b1; rsp_fault <= read_fault; rsp_mask <= read_fault == 0 ? rd_mask : 32'b0;
                rsp_generation <= rd_generation; rsp_job <= rd_job; rsp_tag <= rd_tag; rsp_fmt <= rd_fmt;
            end
        end
    end
endmodule
