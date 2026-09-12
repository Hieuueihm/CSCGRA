`include "context_defs.vh"
module kernel_fabric (
    input wire clk,rst,cancel,
    input wire req_valid, output wire req_ready,
    input wire req_mode,
    input wire [63:0] req_word,
    input wire [863:0] req_a,req_b,
    input wire [31:0] req_mask,
    input wire [15:0] req_job,req_tag,
    input wire [7:0] req_fmt,
    output wire rsp_valid, input wire rsp_ready,
    output wire [863:0] rsp_data,
    output wire [2047:0] rsp_acc,
    output wire rsp_fault
);
    wire [1:0] ready,valid,fault;
    assign req_ready=(&ready)&&!rst&&!cancel;
    assign rsp_valid=(&valid)&&!rst&&!cancel;
    assign rsp_fault=|fault;
    genvar a;
    generate for(a=0;a<2;a=a+1) begin : arrays
        wire [63:0] unused_faults;
        wire [15:0] unused_store,unused_exec,unused_halt;
        pe_array #(.ARRAY_ID(a)) core (
            .clk(clk),.rst(rst),.cancel(cancel),.req_valid(req_valid&&req_ready),.req_ready(ready[a]),
            .req_words({16{req_word}}),.req_rev(8'(`CSR_CTX_REVISION)),.req_mode(req_mode),
            .req_mat(req_a[a*432 +: 432]),.req_vec(req_b[a*432 +: 432]),
            .req_mask(req_mask[a*16 +: 16]),.req_operand_valid(req_mask[a*16 +: 16]),
            .req_job(req_job),.req_tag(req_tag),.req_fmt(req_fmt),.req_last(1'b0),.link_ready(64'hffffffffffffffff),
            .rsp_valid(valid[a]),.rsp_ready(rsp_valid&&rsp_ready),.rsp_drop(rsp_fault),
            .rsp_data(rsp_data[a*432 +: 432]),.rsp_acc(rsp_acc[a*1024 +: 1024]),
            .rsp_fault(fault[a]),.rsp_faults(unused_faults),.rsp_store(unused_store),.rsp_exec(unused_exec),.rsp_halt(unused_halt));
    end endgenerate
endmodule
