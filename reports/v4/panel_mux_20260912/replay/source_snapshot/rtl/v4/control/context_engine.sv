module context_engine (
    input wire clk, rst, cancel,
    input wire begin_valid,
    output wire begin_ready,
    input wire [7:0] begin_rev,
    input wire [8:0] begin_depth,
    input wire begin_verified,
    input wire [31:0] begin_generation,
    input wire wr_valid,
    output wire wr_ready,
    input wire [7:0] wr_pc,
    input wire [5:0] wr_bank,
    input wire [255:0] wr_data,
    input wire wr_last,
    output wire image_ready, loading,
    output wire [3:0] load_fault,
    input wire start_valid,
    output wire start_ready,
    input wire [7:0] start_pc,
    input wire [31:0] start_limit,
    input wire [15:0] start_job,
    input wire [7:0] start_fmt,
    input wire [2:0] predicates,
    output wire addr_valid,
    input wire addr_ready,
    output wire [2:0] addr_mode,
    output wire [23:0] addr_value,
    output wire [15:0] addr_stride,
    input wire addr_rsp_valid,
    output wire addr_rsp_ready,
    input wire addr_rsp_fault,
    input wire [15:0] addr_rsp_job, addr_rsp_tag,
    output wire exec_valid,
    input wire exec_ready,
    output wire [2047:0] exec_words,
    output wire [15:0] exec_job, exec_tag,
    output wire [7:0] exec_fmt,
    output wire exec_last, exec_cancel,
    input wire exec_rsp_valid,
    output wire exec_rsp_ready,
    input wire exec_rsp_fault,
    input wire [15:0] exec_rsp_job, exec_rsp_tag,
    input wire [7:0] exec_rsp_fmt,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_fault,
    output wire [7:0] pc,
    output wire [31:0] retired
);
    wire idle, seq_ready, store_we, invalidate;
    wire [31:0] generation;
    wire fetch_valid, fetch_ready, mem_valid, mem_ready;
    wire [7:0] fetch_pc, mem_pc;
    wire [31:0] fetch_generation, mem_generation;
    wire [2047:0] mem_words;
    wire [255:0] mem_control;
    wire [3:0] mem_fault;
    assign start_ready = seq_ready && !begin_valid && !loading;
    context_loader loader (
        .clk(clk), .rst(rst), .cancel(cancel), .idle(idle), .begin_valid(begin_valid), .begin_ready(begin_ready),
        .begin_rev(begin_rev), .begin_depth(begin_depth), .begin_verified(begin_verified), .begin_generation(begin_generation),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_pc(wr_pc), .wr_bank(wr_bank), .wr_upper(wr_data[255:64]), .wr_last(wr_last),
        .store_we(store_we), .invalidate(invalidate), .image_ready(image_ready), .generation(generation),
        .fault(load_fault), .loading(loading)
    );
    context_store store (
        .clk(clk), .rst(rst), .cancel(cancel), .invalidate(invalidate), .image_ready(image_ready), .generation(generation),
        .wr_en(store_we), .wr_pc(wr_pc), .wr_bank(wr_bank), .wr_data(wr_data),
        .rd_valid(fetch_valid), .rd_ready(fetch_ready), .rd_pc(fetch_pc), .rd_generation(fetch_generation),
        .rsp_valid(mem_valid), .rsp_ready(mem_ready), .rsp_words(mem_words), .rsp_control(mem_control),
        .rsp_pc(mem_pc), .rsp_generation(mem_generation), .rsp_fault(mem_fault)
    );
    context_sequencer sequencer (
        .clk(clk), .rst(rst), .cancel(cancel), .start_valid(start_valid && !begin_valid && !loading), .start_ready(seq_ready),
        .image_ready(image_ready), .image_generation(generation), .start_pc(start_pc), .start_limit(start_limit),
        .start_job(start_job), .start_fmt(start_fmt), .predicates(predicates), .idle(idle),
        .fetch_valid(fetch_valid), .fetch_ready(fetch_ready), .fetch_pc(fetch_pc), .fetch_generation(fetch_generation),
        .mem_valid(mem_valid), .mem_ready(mem_ready), .mem_words(mem_words), .mem_control(mem_control),
        .mem_pc(mem_pc), .mem_generation(mem_generation), .mem_fault(mem_fault),
        .addr_valid(addr_valid), .addr_ready(addr_ready), .addr_mode(addr_mode), .addr_value(addr_value), .addr_stride(addr_stride),
        .addr_rsp_valid(addr_rsp_valid), .addr_rsp_ready(addr_rsp_ready), .addr_rsp_fault(addr_rsp_fault),
        .addr_rsp_job(addr_rsp_job), .addr_rsp_tag(addr_rsp_tag),
        .exec_valid(exec_valid), .exec_ready(exec_ready), .exec_words(exec_words), .exec_job(exec_job), .exec_tag(exec_tag),
        .exec_fmt(exec_fmt), .exec_last(exec_last), .exec_cancel(exec_cancel), .exec_rsp_valid(exec_rsp_valid),
        .exec_rsp_ready(exec_rsp_ready), .exec_rsp_fault(exec_rsp_fault), .exec_rsp_job(exec_rsp_job),
        .exec_rsp_tag(exec_rsp_tag), .exec_rsp_fmt(exec_rsp_fmt), .done_valid(done_valid), .done_ready(done_ready),
        .done_fault(done_fault), .pc(pc), .retired(retired)
    );
endmodule
