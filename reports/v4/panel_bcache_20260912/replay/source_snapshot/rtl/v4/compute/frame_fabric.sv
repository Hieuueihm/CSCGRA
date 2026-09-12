`include "context_defs.vh"

// Expanded-frame entry: exactly two arrays, no operand feeder.
module frame_fabric (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [2047:0] req_words,
    input wire [863:0] req_mat, req_vec,
    input wire [31:0] req_mask, req_operand_valid,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    input wire req_last,
    input wire [127:0] link_ready,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [863:0] rsp_data,
    output wire [31:0] rsp_store,
    output wire rsp_fault
);
    wire [1:0] ready, valid, fault;
    wire [31:0] stores;
    wire active = !rst && !cancel;
    assign req_ready = active && (&ready);
    assign rsp_valid = active && (&valid);
    assign rsp_fault = |fault;
    assign rsp_store = rsp_fault ? 32'b0 : stores;
    genvar cluster;
    generate for (cluster = 0; cluster < 2; cluster = cluster + 1) begin : array_pair
        wire [1023:0] unused_acc;
        wire [63:0] unused_faults;
        wire [15:0] unused_exec, unused_halt;
        pe_array #(.ARRAY_ID(cluster)) core (
            .clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid && req_ready), .req_ready(ready[cluster]),
            .req_words(req_words[cluster*1024 +: 1024]), .req_rev(8'(`CSR_CTX_REVISION)), .req_mode(1'b0),
            .req_mat(req_mat[cluster*432 +: 432]), .req_vec(req_vec[cluster*432 +: 432]),
            .req_mask(req_mask[cluster*16 +: 16]), .req_operand_valid(req_operand_valid[cluster*16 +: 16]),
            .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last),
            .link_ready(link_ready[cluster*64 +: 64]), .rsp_valid(valid[cluster]),
            .rsp_ready(rsp_valid && rsp_ready), .rsp_drop(rsp_fault),
            .rsp_data(rsp_data[cluster*432 +: 432]), .rsp_acc(unused_acc), .rsp_faults(unused_faults),
            .rsp_store(stores[cluster*16 +: 16]), .rsp_exec(unused_exec), .rsp_halt(unused_halt), .rsp_fault(fault[cluster])
        );
    end endgenerate
endmodule
