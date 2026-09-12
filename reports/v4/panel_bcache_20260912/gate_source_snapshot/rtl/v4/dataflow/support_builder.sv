`include "builder_defs.vh"
module support_builder (
    input wire clk, rst, cancel,
    input wire req_valid, output wire req_ready,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols,
    input wire [6:0] req_count,
    input wire [959:0] req_support,
    input wire [17:0] req_scale,
    input wire [127:0] req_phi_key, req_b_key,
    input wire [31:0] req_phi_generation, req_b_generation,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    input wire phi_valid,
    input wire [127:0] phi_key,
    input wire [31:0] phi_generation,
    input wire [7:0] phi_rows,
    input wire [10:0] phi_cols,
    output wire phi_invalidate,
    output wire phi_rd_valid, input wire phi_rd_ready,
    output wire [7:0] phi_rd_bank_mask,
    output reg [71:0] phi_rd_addresses,
    output wire [31:0] phi_rd_generation,
    output wire [15:0] phi_rd_tag,
    input wire phi_rsp_valid, output wire phi_rsp_ready,
    input wire [255:0] phi_rsp_signs, phi_rsp_masks,
    input wire [7:0] phi_rsp_bank_mask,
    input wire [31:0] phi_rsp_generation,
    input wire [15:0] phi_rsp_tag,
    input wire [3:0] phi_rsp_fault,
    output wire b_cancel,
    output wire b_begin_valid, input wire b_begin_ready,
    output wire [7:0] b_begin_rows,
    output wire [6:0] b_begin_cols,
    output wire [127:0] b_begin_key,
    output wire [31:0] b_begin_generation,
    output wire [15:0] b_begin_job,
    output wire [7:0] b_begin_fmt,
    output wire b_fill_valid, input wire b_fill_ready,
    output wire [6:0] b_fill_slot,
    output wire [1:0] b_fill_block,
    output wire [31:0] b_fill_mask,
    output reg [575:0] b_fill_data,
    output wire b_fill_last,
    input wire b_loading, b_valid,
    input wire [3:0] b_load_fault,
    output wire rsp_valid, input wire rsp_ready,
    output reg [3:0] rsp_fault,
    output reg [15:0] rsp_job, rsp_tag,
    output reg [7:0] rsp_fmt,
    output reg [31:0] rsp_cycles,
    output reg [15:0] rsp_words
);
    localparam [3:0] IDLE=0, CHECK=1, BEGIN_B=2, BEGIN_CHECK=3, READ=4,
                      WAIT_PHI=5, FILL=6, FILL_CHECK=7, ABORT=8, DONE=9;
    reg [3:0] state;
    reg [7:0] rows;
    reg [10:0] cols;
    reg [6:0] count, slot, check_slot;
    reg [1:0] block_idx;
    reg [959:0] support_q;
    reg [1023:0] seen;
    reg [17:0] scale;
    reg [127:0] phi_key_q, b_key;
    reg [31:0] phi_gen, b_gen, signs;
    reg pending;
    reg [31:0] mask;
    integer lane;
    wire active = !rst && !cancel;
    wire take = req_valid && req_ready;
    wire [9:0] column = support_q[int'(slot)*10 +: 10];
    wire [9:0] check_column = support_q[int'(check_slot)*10 +: 10];
    wire [2:0] bank = column[2:0];
    wire [8:0] address = 9'((int'(column)/8)*((int'(rows)+31)/32)+int'(block_idx));
    wire identity = phi_valid && phi_key == phi_key_q && phi_generation == phi_gen && phi_rows == rows && phi_cols == cols;
    wire last_block = (int'(block_idx)+1)*32 >= int'(rows);
    wire last_word = last_block && slot+1 == count;
    wire response_good = phi_rsp_fault == 0 && phi_rsp_bank_mask == phi_rd_bank_mask &&
                        phi_rsp_generation == phi_gen && phi_rsp_tag == phi_rd_tag &&
                        phi_rsp_masks == (256'(mask) << (int'(bank)*32)) &&
                        (phi_rsp_signs & ~(256'(mask) << (int'(bank)*32))) == 0;
    assign req_ready = active && state == IDLE && !phi_rsp_valid;
    assign rsp_valid = active && state == DONE;
    assign b_cancel = rst || cancel || take || state == ABORT;
    assign phi_invalidate = cancel || (state == ABORT && pending);
    assign b_begin_valid = active && state == BEGIN_B && identity;
    assign b_begin_rows = rows;
    assign b_begin_cols = count;
    assign b_begin_key = b_key;
    assign b_begin_generation = b_gen;
    assign b_begin_job = rsp_job;
    assign b_begin_fmt = rsp_fmt;
    assign phi_rd_valid = active && state == READ && identity;
    assign phi_rd_bank_mask = 8'b1 << bank;
    assign phi_rd_generation = phi_gen;
    assign phi_rd_tag = rsp_words;
    assign phi_rsp_ready = active && state == WAIT_PHI && identity;
    assign b_fill_valid = active && state == FILL && identity && b_load_fault == 0;
    assign b_fill_slot = slot;
    assign b_fill_block = block_idx;
    assign b_fill_mask = mask;
    assign b_fill_last = last_word;
    always @* begin
        phi_rd_addresses = '0;
        phi_rd_addresses[int'(bank)*9 +: 9] = address;
        mask = '0;
        b_fill_data = '0;
        for (lane=0; lane<32; lane=lane+1) begin
            mask[lane] = int'(block_idx)*32+lane < int'(rows);
            if (mask[lane]) b_fill_data[lane*18 +: 18] = signs[lane] ? scale : -scale;
        end
    end
    always @(posedge clk) begin
        if (rst || cancel) begin
            state<=IDLE; rows<=0; cols<=0; count<=0; slot<=0; check_slot<=0; block_idx<=0;
            support_q<=0; seen<=0; scale<=0; phi_key_q<=0; b_key<=0; phi_gen<=0; b_gen<=0;
            signs<=0; pending<=0; rsp_fault<=0; rsp_job<=0; rsp_tag<=0; rsp_fmt<=0; rsp_cycles<=0; rsp_words<=0;
        end else begin
            if (state != IDLE && state != DONE) rsp_cycles <= rsp_cycles+1;
            if (state != IDLE && state != DONE && state != ABORT && state != CHECK && !identity) begin
                rsp_fault <= `CSR_BUILD_FAULT_PHI_KEY; state <= ABORT;
            end else case (state)
                IDLE: if (take) begin
                    rows<=req_rows; cols<=req_cols; count<=req_count; support_q<=req_support; scale<=req_scale;
                    phi_key_q<=req_phi_key; b_key<=req_b_key; phi_gen<=req_phi_generation; b_gen<=req_b_generation;
                    rsp_job<=req_job; rsp_tag<=req_tag; rsp_fmt<=req_fmt; rsp_fault<=0; rsp_cycles<=0; rsp_words<=0;
                    seen<=0; slot<=0; block_idx<=0; check_slot<=0; pending<=0; state<=CHECK;
                end
                CHECK: begin
                    if (rows==0 || rows>128 || cols==0 || cols>1024 || count==0 || count>96 || scale==0 || scale[17]) begin
                        rsp_fault<=`CSR_BUILD_FAULT_SHAPE; state<=ABORT;
                    end else if (!identity) begin
                        rsp_fault<=`CSR_BUILD_FAULT_PHI_KEY; state<=ABORT;
                    end else if (int'(check_column)>=int'(cols) || seen[check_column]) begin
                        rsp_fault<=`CSR_BUILD_FAULT_SUPPORT; state<=ABORT;
                    end else begin
                        seen[check_column]<=1'b1;
                        if (check_slot+1==count) state<=BEGIN_B;
                        else check_slot<=check_slot+1'b1;
                    end
                end
                BEGIN_B: if (b_begin_ready) state<=BEGIN_CHECK;
                BEGIN_CHECK: begin
                    if (b_load_fault!=0 || !b_loading) begin rsp_fault<=`CSR_BUILD_FAULT_B; state<=ABORT; end
                    else state<=READ;
                end
                READ: if (phi_rd_ready) begin pending<=1'b1; state<=WAIT_PHI; end
                WAIT_PHI: if (phi_rsp_valid) begin
                    pending<=1'b0;
                    if (!response_good) begin rsp_fault<=`CSR_BUILD_FAULT_SOURCE; state<=ABORT; end
                    else begin signs<=phi_rsp_signs[int'(bank)*32 +: 32]; state<=FILL; end
                end
                FILL: begin
                    if (b_load_fault!=0 || !b_loading) begin rsp_fault<=`CSR_BUILD_FAULT_B; state<=ABORT; end
                    else if (b_fill_ready) begin rsp_words<=rsp_words+1'b1; state<=FILL_CHECK; end
                end
                FILL_CHECK: begin
                    if (b_load_fault!=0 || (last_word ? !b_valid : !b_loading)) begin rsp_fault<=`CSR_BUILD_FAULT_B; state<=ABORT; end
                    else if (last_word) state<=DONE;
                    else begin
                        if (last_block) begin block_idx<=0; slot<=slot+1'b1; end
                        else block_idx<=block_idx+1'b1;
                        state<=READ;
                    end
                end
                ABORT: begin pending<=0; state<=DONE; end
                DONE: if (rsp_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
