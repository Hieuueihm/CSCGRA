`include "stream_interface.vh"
module stream_engine (
    input wire clk, rst, cancel,
    input wire load_begin_valid,
    output wire load_begin_ready,
    input wire [7:0] load_begin_revision,
    input wire load_begin_verified,
    input wire [8:0] load_begin_program_count,
    input wire [4:0] load_begin_template_count,
    input wire load_program_valid,
    output wire load_program_ready,
    input wire [7:0] load_program_index,
    input wire [127:0] load_program_word,
    input wire load_program_last,
    input wire load_template_valid,
    output wire load_template_ready,
    input wire [3:0] load_template_id,
    input wire [5:0] load_template_lane,
    input wire [63:0] load_template_word,
    input wire load_template_last,
    output wire load_status_valid,
    input wire load_status_ready,
    output wire [3:0] load_status_fault,
    output wire image_valid,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] start_job, start_tag,
    input wire [7:0] start_fmt,
    input wire host_valid, output wire host_ready,
    input wire host_write, input wire [8:0] host_block,
    input wire [31:0] host_mask, input wire [863:0] host_data,
    input wire [15:0] host_tag,
    output wire host_rsp_valid, input wire host_rsp_ready,
    output wire host_rsp_write, output reg [863:0] host_rsp_data,
    output reg [31:0] host_rsp_mask, output reg [15:0] host_rsp_tag,
    output reg [3:0] host_rsp_fault,
    output wire busy,
    output reg [63:0] job_cycles, frames_in, frames_out, memory_reads, memory_writes, stall_cycles,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_fault, done_detail,
    output wire [63:0] done_scalar,
    output wire [15:0] done_job, done_tag,
    output wire [7:0] done_fmt,
    output wire [7:0] trace_pc,
    output wire [3:0] trace_template
    );
    wire active=!rst&&!cancel;
    reg running,loading;
    wire kernel_busy,control_start_ready,control_begin_ready;
    wire cmd_valid,cmd_ready,rsp_ready,kernel_rsp_valid;
    wire [3:0] cmd_template,kernel_fault;
    wire [8:0] cmd_src_a,cmd_src_b,cmd_dst;
    wire [7:0] cmd_frame_count,cmd_fmt,kernel_fmt;
    wire [31:0] cmd_tail_mask,cmd_descriptor;
    wire [2047:0] cmd_contexts;
    wire [15:0] cmd_job,cmd_tag,kernel_job,kernel_tag;
    wire [63:0] kernel_scalar;
    wire [4:0] events;
    assign busy=running||loading||kernel_busy;
    assign start_ready=control_start_ready&&active&&!busy&&!host_valid&&!load_begin_valid;
    assign load_begin_ready=control_begin_ready&&active&&!running&&!kernel_busy;
    stream_program_control control (
    .clk(clk),.rst(rst),.cancel(cancel),
    .load_begin_valid(load_begin_valid&&!running&&!kernel_busy),.load_begin_ready(control_begin_ready),
    .load_begin_revision(load_begin_revision),.load_begin_verified(load_begin_verified),
    .load_begin_program_count(load_begin_program_count),.load_begin_template_count(load_begin_template_count),
    .load_program_valid(load_program_valid),.load_program_ready(load_program_ready),.load_program_index(load_program_index),
    .load_program_word(load_program_word),.load_program_last(load_program_last),
    .load_template_valid(load_template_valid),.load_template_ready(load_template_ready),.load_template_id(load_template_id),
    .load_template_lane(load_template_lane),.load_template_word(load_template_word),.load_template_last(load_template_last),
    .load_status_valid(load_status_valid),.load_status_ready(load_status_ready),.load_status_fault(load_status_fault),.image_valid(image_valid),
    .start_valid(start_valid&&active&&!busy&&!host_valid&&!load_begin_valid),.start_ready(control_start_ready),
    .start_job(start_job),.start_tag(start_tag),.start_fmt(start_fmt),
    .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_template(cmd_template),.cmd_src_a(cmd_src_a),.cmd_src_b(cmd_src_b),.cmd_dst(cmd_dst),
    .cmd_frame_count(cmd_frame_count),.cmd_tail_mask(cmd_tail_mask),.cmd_descriptor(cmd_descriptor),.cmd_contexts(cmd_contexts),
    .cmd_job(cmd_job),.cmd_tag(cmd_tag),.cmd_fmt(cmd_fmt),
    .rsp_valid(kernel_rsp_valid),.rsp_ready(rsp_ready),.rsp_fault(kernel_fault),.rsp_scalar(kernel_scalar),.rsp_job(kernel_job),.rsp_tag(kernel_tag),.rsp_fmt(kernel_fmt),
    .done_valid(done_valid),.done_ready(done_ready),.done_fault(done_fault),.done_detail(done_detail),.done_scalar(done_scalar),
    .done_job(done_job),.done_tag(done_tag),.done_fmt(done_fmt),.trace_pc(trace_pc),.trace_template(trace_template));
    stream_kernel kernel (
    .clk(clk),.rst(rst),.cancel(cancel),
    .host_enable(!running&&!loading&&!load_begin_valid),
    .req_valid(cmd_valid&&running),.req_ready(cmd_ready),
    .req_op(6'd0),
    .req_contexts(cmd_contexts),
    .req_descriptor(cmd_descriptor),
    .req_src_a(cmd_src_a),
    .req_src_b(cmd_src_b),
    .req_dst(cmd_dst),
    .req_length(11'd0),
    .req_rows(8'd0),
    .req_cols(11'd0),
    .req_matrix_dense(1'd0),
    .req_trans(1'd0),
    .req_r4(1'd0),
    .req_scalar_a(27'd0),
    .req_scalar_b(27'd0),
    .req_scalar_bind_a(32'd0),
    .req_scalar_bind_b(32'd0),
    .req_shift(6'd0),
    .req_k(11'd0),
    .req_scale(18'd0),
    .req_key(128'd0),
    .req_generation(32'd0),
    .req_job(cmd_job),
    .req_tag(cmd_tag),
    .req_fmt(cmd_fmt),
    .req_frame_count(cmd_frame_count),
    .req_tail_mask(cmd_tail_mask),
    .req_store_mode(2'd0),
    .req_support_base(9'd0),
    .req_aux_base(9'd0),
    .req_support_length(11'd0),
    .req_aux_length(11'd0),
    .req_index(11'd0),
    .req_flags(8'd0),
    .rsp_valid(kernel_rsp_valid),.rsp_ready(rsp_ready),.rsp_fault(kernel_fault),.rsp_detail(),
    .rsp_data(kernel_scalar),.rsp_nonzero(),.rsp_count(),.rsp_job(kernel_job),.rsp_tag(kernel_tag),.rsp_fmt(kernel_fmt),
    .host_valid(host_valid),
    .host_ready(host_ready),
    .host_write(host_write),
    .host_block(host_block),
    .host_mask(host_mask),
    .host_data(host_data),
    .host_tag(host_tag),
    .host_rsp_valid(host_rsp_valid),
    .host_rsp_ready(host_rsp_ready),
    .host_rsp_write(host_rsp_write),
    .host_rsp_data(host_rsp_data),
    .host_rsp_mask(host_rsp_mask),
    .host_rsp_tag(host_rsp_tag),
    .host_rsp_fault(host_rsp_fault),
    .matrix_valid(0),
    .matrix_rows(0),
    .matrix_cols(0),
    .matrix_key(0),
    .matrix_generation(0),
    .matrix_job(0),
    .matrix_fmt(0),
    .mat_valid(),
    .mat_ready(0),
    .mat_dense(),
    .mat_mask(),
    .mat_addr(),
    .mat_key(),
    .mat_generation(),
    .mem_job(),
    .mem_fmt(),
    .mat_rsp_valid(0),
    .mat_rsp_ready(),
    .mat_rsp_data(0),
    .mat_rsp_masks(0),
    .mat_rsp_mask(0),
    .mat_rsp_job(0),
    .mat_rsp_fmt(0),
    .mat_rsp_fault(0),
    .operator_cancel(),.matrix_select(),
    .busy(kernel_busy),.events(events)
    );
    always @(posedge clk)
    begin
        if(rst||cancel)
        begin
            running<=0;
            loading<=0;
            if(rst)
            begin
                job_cycles<=0;
                frames_in<=0;
                frames_out<=0;
                memory_reads<=0;
                memory_writes<=0;
                stall_cycles<=0;
            end
        end
        else
        begin
            if(start_valid&&start_ready)
            begin
                running<=1;
                job_cycles<=0;
                frames_in<=0;
                frames_out<=0;
                memory_reads<=0;
                memory_writes<=0;
                stall_cycles<=0;
            end
            else if(running&&!done_valid)
            begin
                job_cycles<=job_cycles+1'b1;
                if(events[0]) frames_in<=frames_in+1'b1;
                if(events[1]) frames_out<=frames_out+1'b1;
                if(events[2]) memory_reads<=memory_reads+1'b1;
                if(events[3]) memory_writes<=memory_writes+1'b1;
                if(events[4]) stall_cycles<=stall_cycles+1'b1;
            end
            if(done_valid&&done_ready) running<=0;
            if(load_begin_valid&&load_begin_ready) loading<=1;
            if(load_status_valid&&load_status_ready) loading<=0;
        end
    end
endmodule
