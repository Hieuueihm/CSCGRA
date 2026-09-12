`include "commit_interface.vh"
// Private trusted write port; commit_controller validates every candidate input.
module result_writeback (
    input wire clk, rst, cancel,
    input wire start, write_en, publish,
    input wire [7:0] rows,
    input wire [6:0] count,
    input wire [959:0] support,
    input wire [15:0] job, tag,
    input wire [7:0] fmt,
    input wire signed [6:0] exponent,
    input wire [1:0] block,
    input wire [31:0] mask,
    input wire [863:0] data,
    output reg committed_valid,
    output wire [6:0] committed_count,
    output wire [7:0] committed_rows,
    input wire read_valid,
    output wire read_ready,
    input wire [6:0] read_slot,
    output wire rsp_valid,
    input wire rsp_ready,
    output reg signed [23:0] rsp_x,
    output reg [9:0] rsp_index,
    output reg signed [6:0] rsp_exponent,
    output reg [15:0] rsp_job, rsp_tag,
    output reg [7:0] rsp_fmt,
    output reg [3:0] rsp_fault
);
    reg bank, pending;
    reg signed [23:0] x [0:191];
    reg [9:0] indices [0:191];
    reg [7:0] bank_rows [0:1], bank_fmt [0:1];
    reg [6:0] bank_count [0:1];
    reg signed [6:0] bank_exponent [0:1];
    reg [15:0] bank_job [0:1], bank_tag [0:1];
    integer i, address;
    wire active = !rst && !cancel;
    assign committed_count = committed_valid ? bank_count[bank] : 7'd0;
    assign committed_rows = committed_valid ? bank_rows[bank] : 8'd0;
    assign read_ready = active && !pending;
    assign rsp_valid = active && pending;
    always @(posedge clk) begin
        if (rst) begin
            bank <= 0; committed_valid <= 0; pending <= 0;
            rsp_x <= 0; rsp_index <= 0; rsp_exponent <= 0;
            rsp_job <= 0; rsp_tag <= 0; rsp_fmt <= 0; rsp_fault <= 0;
        end else if (cancel) begin
            pending <= 0;
            rsp_x <= 0; rsp_index <= 0; rsp_exponent <= 0;
            rsp_job <= 0; rsp_tag <= 0; rsp_fmt <= 0; rsp_fault <= 0;
        end else begin
            if (start) begin
                bank_rows[!bank] <= rows; bank_count[!bank] <= count;
                bank_job[!bank] <= job; bank_tag[!bank] <= tag;
                bank_fmt[!bank] <= fmt; bank_exponent[!bank] <= exponent;
                for (i=0;i<96;i=i+1) indices[int'(!bank)*96+i] <= support[i*10 +: 10];
            end
            if (write_en) begin
                for (i=0;i<32;i=i+1) begin
                    address=int'(!bank)*96+int'(block)*32+i;
                    if (mask[i]) x[address] <= data[i*27+2 +: 24];
                end
            end
            if (publish) begin bank <= !bank; committed_valid <= 1; end
            if (pending && rsp_ready) begin
                pending <= 0;
                rsp_x <= 0; rsp_index <= 0; rsp_exponent <= 0;
                rsp_job <= 0; rsp_tag <= 0; rsp_fmt <= 0; rsp_fault <= 0;
            end
            if (read_valid && read_ready) begin
                pending <= 1;
                rsp_x <= 0; rsp_index <= 0; rsp_exponent <= 0;
                rsp_job <= 0; rsp_tag <= 0; rsp_fmt <= 0;
                rsp_fault <= `CSR_COMMIT_FAULT_READ;
                if (committed_valid && read_slot < bank_count[bank]) begin
                    rsp_x <= x[int'(bank)*96+int'(read_slot)];
                    rsp_index <= indices[int'(bank)*96+int'(read_slot)];
                    rsp_exponent <= bank_exponent[bank];
                    rsp_job <= bank_job[bank]; rsp_tag <= bank_tag[bank]; rsp_fmt <= bank_fmt[bank];
                    rsp_fault <= `CSR_COMMIT_FAULT_NONE;
                end
            end
        end
    end
endmodule
