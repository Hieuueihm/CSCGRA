`include "recovery_interface.vh"
module recovery_engine (
    input wire clk,rst,cancel,
    input wire load_begin_valid,output wire load_begin_ready,
    input wire [7:0] load_begin_revision,input wire load_begin_verified,
    input wire [10:0] load_begin_program_count,load_begin_constant_count,
    input wire [4:0] load_begin_template_count,input wire [5:0] load_begin_vector_count,
    input wire load_valid,output wire load_ready,input wire [2:0] load_kind,
    input wire [15:0] load_index,input wire [127:0] load_data,input wire load_last,
    output wire load_status_valid,input wire load_status_ready,output wire [3:0] load_status_fault,
    output wire image_valid,
    input wire p_begin_valid,output wire p_begin_ready,
    input wire [31:0] p_begin_seed,
    input wire [7:0] p_begin_rows,
    input wire [10:0] p_begin_cols,
    input wire [127:0] p_begin_key,
    input wire [31:0] p_begin_generation,
    input wire [15:0] p_begin_job,
    input wire [7:0] p_begin_fmt,
    output wire p_loading,output wire [3:0] p_fault,output wire p_valid,
    input wire host_valid,output wire host_ready,input wire host_write,
    input wire [8:0] host_block,input wire [31:0] host_mask,
    input wire [863:0] host_data,input wire [15:0] host_tag,
    output wire host_rsp_valid,input wire host_rsp_ready,
    output wire host_rsp_write,output wire [863:0] host_rsp_data,
    output wire [31:0] host_rsp_mask,output wire [15:0] host_rsp_tag,output wire [3:0] host_rsp_fault,
    input wire start_valid,output wire start_ready,
    input wire [7:0] start_rows,input wire [10:0] start_cols,
    input wire [127:0] start_key,input wire [31:0] start_generation,
    input wire [17:0] start_scale,input wire [15:0] start_job,start_tag,
    input wire [7:0] start_fmt,input wire [31:0] start_instruction_limit,
    input wire [1:0] start_storage_mode,input wire signed [6:0] start_exponent,
    input wire start_active_support,
    output wire done_valid,input wire done_ready,
    output reg [3:0] done_fault,done_detail,
    output reg [7:0] done_status,
    output reg [15:0] done_outer_iterations,done_inner_iterations,
    output reg [6:0] done_support_count,
    output reg done_committed,
    output reg [15:0] done_job,done_tag,output reg [7:0] done_fmt,
    output reg [63:0] job_cycles,
    output wire [9:0] trace_pc,output wire [127:0] trace_word,output wire trace_retire,
    output wire busy,
    output wire committed_valid,
    output wire [7:0] committed_rows,
    output wire [10:0] committed_length,
    output wire [1:0] committed_mode,
    output wire signed [6:0] committed_exponent,
    output wire committed_active_support,
    output wire [6:0] committed_support_count,
    output wire [959:0] committed_support,
    output wire [7:0] committed_status,
    output wire [15:0] committed_outer_iterations,committed_inner_iterations,committed_job,committed_tag,
    output wire [7:0] committed_fmt,
    output wire [127:0] committed_key,output wire [31:0] committed_generation,
    input wire read_valid,output wire read_ready,input wire [9:0] read_index,input wire [15:0] read_tag,
    output wire read_rsp_valid,input wire read_rsp_ready,output wire [26:0] read_rsp_data,
    output wire [9:0] read_rsp_index,output wire [15:0] read_rsp_request_tag,
    output wire [3:0] read_rsp_fault,output wire [1:0] read_rsp_mode,
    output wire signed [6:0] read_rsp_exponent,output wire [10:0] read_rsp_length,
    output wire [15:0] read_rsp_job,read_rsp_tag,output wire [7:0] read_rsp_fmt
);


    localparam [4:0] IDLE=0,LAUNCH=1,RUN=2,COLLECT_READ=3,COLLECT_WAIT=4,
        COLLECT_WORD=5,BUILD_REQUEST=6,BUILD_WAIT=7,BUILD_RETURN=8,
        RESULT_BEGIN=9,RESULT_READ=10,RESULT_WAIT=11,RESULT_FILL=12,
        RESULT_APPROVE=13,RESULT_STATUS=14,ABORT=15,DONE=16;
    reg [4:0] state;
    reg loading;
    reg [7:0] rows;
    reg [10:0] columns;
    reg [127:0] key;
    reg [31:0] generation,instruction_limit,b_token,build_generation;
    reg [17:0] scale;
    reg [1:0] storage_mode;
    reg signed [6:0] exponent;
    reg active_support,collect_for_build;
    reg [8:0] collect_base,output_base;
    reg [6:0] collect_count,collect_position;
    reg [959:0] ordered_support;
    reg [1023:0] seen;
    reg [863:0] read_buffer;
    reg [4:0] result_block;
    reg [15:0] build_job_q,build_tag_q;
    reg [7:0] build_fmt_q;
    reg [26:0] index_value;
    wire idle=state==IDLE;
    wire service_flush=cancel || state==ABORT;
    wire load_open=idle && !p_loading && !kernel_busy;
    wire phi_open=idle && !loading && !load_begin_valid && !kernel_busy;
    wire external_host=idle && !loading && !load_begin_valid && !p_begin_valid && !p_loading;
    wire internal_read=state==COLLECT_READ || state==RESULT_READ;
    wire internal_wait=state==COLLECT_WAIT || state==RESULT_WAIT;
    wire host_access=external_host || internal_read || internal_wait;
    wire  seq_load_begin_ready;
    wire  seq_load_ready;
    wire  seq_start_ready;
    wire  kernel_valid;
    wire  kernel_ready;
    wire [5:0] kernel_op;
    wire [2047:0] kernel_contexts;
    wire [31:0] kernel_descriptor;
    wire [8:0] kernel_src_a;
    wire [8:0] kernel_src_b;
    wire [8:0] kernel_dst;
    wire [10:0] kernel_length;
    wire [7:0] kernel_rows;
    wire [10:0] kernel_cols;
    wire  kernel_matrix_dense;
    wire  kernel_trans;
    wire  kernel_r4;
    wire [26:0] kernel_scalar_a;
    wire [26:0] kernel_scalar_b;
    wire [31:0] kernel_scalar_bind_a;
    wire [31:0] kernel_scalar_bind_b;
    wire [5:0] kernel_shift;
    wire [10:0] kernel_k;
    wire [17:0] kernel_scale;
    wire [127:0] kernel_key;
    wire [31:0] kernel_generation;
    wire [15:0] kernel_job;
    wire [15:0] kernel_tag;
    wire [7:0] kernel_fmt;
    wire [7:0] kernel_frame_count;
    wire [31:0] kernel_tail_mask;
    wire [1:0] kernel_store_mode;
    wire [8:0] kernel_support_base;
    wire [8:0] kernel_aux_base;
    wire [10:0] kernel_support_length;
    wire [10:0] kernel_aux_length;
    wire [10:0] kernel_index;
    wire [7:0] kernel_flags;
    wire  kernel_rsp_valid;
    wire  kernel_rsp_ready;
    wire [3:0] kernel_rsp_fault;
    wire [3:0] kernel_rsp_detail;
    wire [63:0] kernel_rsp_data;
    wire  kernel_rsp_nonzero;
    wire [10:0] kernel_rsp_count;
    wire [15:0] kernel_rsp_job;
    wire [15:0] kernel_rsp_tag;
    wire [7:0] kernel_rsp_fmt;
    wire  scalar_valid;
    wire  scalar_ready;
    wire [1:0] scalar_op;
    wire signed [63:0] scalar_a;
    wire signed [63:0] scalar_b;
    wire [7:0] scalar_source_frac;
    wire [15:0] scalar_job;
    wire [15:0] scalar_tag;
    wire [7:0] scalar_fmt;
    wire  scalar_rsp_valid;
    wire  scalar_rsp_ready;
    wire signed [26:0] scalar_rsp_data;
    wire [2:0] scalar_rsp_fault;
    wire [15:0] scalar_rsp_job;
    wire [15:0] scalar_rsp_tag;
    wire [7:0] scalar_rsp_fmt;
    wire  build_valid;
    wire  build_ready;
    wire [8:0] build_support_base;
    wire [10:0] build_support_count;
    wire [15:0] build_job;
    wire [15:0] build_tag;
    wire [7:0] build_fmt;
    wire  build_rsp_valid;
    wire  build_rsp_ready;
    wire [3:0] build_rsp_fault;
    wire [15:0] build_rsp_job;
    wire [15:0] build_rsp_tag;
    wire [7:0] build_rsp_fmt;
    wire  seq_done_valid;
    wire  seq_done_ready;
    wire [3:0] seq_done_fault;
    wire [3:0] seq_done_detail;
    wire [7:0] seq_done_status;
    wire [15:0] seq_done_outer_iterations;
    wire [15:0] seq_done_inner_iterations;
    wire [4:0] seq_done_output_vector;
    wire [4:0] seq_done_residual_vector;
    wire [4:0] seq_done_support_vector;
    wire [10:0] seq_done_support_count;
    wire [8:0] seq_done_output_base;
    wire [8:0] seq_done_residual_base;
    wire [8:0] seq_done_support_base;
    wire [10:0] seq_done_output_capacity;
    wire [10:0] seq_done_residual_capacity;
    wire [10:0] seq_done_support_capacity;
    wire [15:0] seq_done_job;
    wire [15:0] seq_done_tag;
    wire [7:0] seq_done_fmt;
    wire  seq_running;
    wire  core_host_enable;
    wire  core_host_valid;
    wire  core_host_ready;
    wire  core_host_write;
    wire [8:0] core_host_block;
    wire [31:0] core_host_mask;
    wire [863:0] core_host_data;
    wire [15:0] core_host_tag;
    wire  core_host_rsp_valid;
    wire  core_host_rsp_ready;
    wire  core_host_rsp_write;
    wire [863:0] core_host_rsp_data;
    wire [31:0] core_host_rsp_mask;
    wire [15:0] core_host_rsp_tag;
    wire [3:0] core_host_rsp_fault;
    wire  selected_valid;
    wire [7:0] selected_rows;
    wire [10:0] selected_cols;
    wire [127:0] selected_key;
    wire [31:0] selected_generation;
    wire [15:0] selected_job;
    wire [7:0] selected_fmt;
    wire  mat_valid;
    wire  mat_ready;
    wire  mat_dense;
    wire [31:0] mat_mask;
    wire [287:0] mat_addr;
    wire [127:0] mat_key;
    wire [31:0] mat_generation;
    wire [15:0] mem_job;
    wire [15:0] mem_tag;
    wire [7:0] mem_fmt;
    wire  mat_rsp_valid;
    wire  mat_rsp_ready;
    wire [575:0] mat_rsp_data;
    wire [255:0] mat_rsp_masks;
    wire [31:0] mat_rsp_mask;
    wire [31:0] mat_rsp_generation;
    wire [15:0] mat_rsp_job;
    wire [15:0] mat_rsp_tag;
    wire [7:0] mat_rsp_fmt;
    wire [3:0] mat_rsp_fault;
    wire  selected_select;
    wire  core_req_ready;
    wire  kernel_operator_cancel;
    wire  kernel_busy;
    wire [4:0] kernel_events;
    wire  matrix_select;
    wire  b_loading;
    wire [3:0] b_load_fault;
    wire  live_build_req_valid;
    wire  live_build_req_ready;
    wire [7:0] live_build_req_rows;
    wire [10:0] live_build_req_cols;
    wire [6:0] live_build_req_count;
    wire [959:0] live_build_req_support;
    wire [17:0] live_build_req_scale;
    wire [127:0] live_build_req_phi_key;
    wire [127:0] live_build_req_b_key;
    wire [31:0] live_build_req_phi_generation;
    wire [31:0] live_build_req_b_generation;
    wire [15:0] live_build_req_job;
    wire [15:0] live_build_req_tag;
    wire [7:0] live_build_req_fmt;
    wire  live_build_rsp_valid;
    wire  live_build_rsp_ready;
    wire [3:0] live_build_rsp_fault;
    wire [15:0] live_build_rsp_job;
    wire [15:0] live_build_rsp_tag;
    wire [7:0] live_build_rsp_fmt;
    wire [31:0] live_build_rsp_cycles;
    wire [15:0] live_build_rsp_words;
    wire  live_build_busy;
    wire [7:0] p_rows;
    wire [10:0] p_cols;
    wire [127:0] p_key;
    wire [31:0] p_generation;
    wire [15:0] p_job;
    wire [7:0] p_fmt;
    wire  b_valid;
    wire [7:0] b_rows;
    wire [6:0] b_cols;
    wire [127:0] b_key;
    wire [31:0] b_generation;
    wire [15:0] b_job;
    wire [7:0] b_fmt;
    wire  live_p_begin_ready;
    wire  result_begin_valid;
    wire  result_begin_ready;
    wire [7:0] result_begin_rows;
    wire [10:0] result_begin_length;
    wire [1:0] result_begin_mode;
    wire signed [6:0] result_begin_exponent;
    wire  result_begin_active_support;
    wire [6:0] result_begin_support_count;
    wire [959:0] result_begin_support;
    wire [7:0] result_begin_status;
    wire [15:0] result_begin_outer_iterations;
    wire [15:0] result_begin_inner_iterations;
    wire [15:0] result_begin_job;
    wire [15:0] result_begin_tag;
    wire [7:0] result_begin_fmt;
    wire [127:0] result_begin_key;
    wire [31:0] result_begin_generation;
    wire  result_fill_valid;
    wire  result_fill_ready;
    wire [4:0] result_fill_block;
    wire [31:0] result_fill_mask;
    wire [863:0] result_fill_data;
    wire  result_fill_last;
    wire [15:0] result_fill_job;
    wire [15:0] result_fill_tag;
    wire [7:0] result_fill_fmt;
    wire  result_approve_valid;
    wire  result_approve_ready;
    wire  result_approve;
    wire [15:0] result_approve_job;
    wire [15:0] result_approve_tag;
    wire [7:0] result_approve_fmt;
    wire  result_status_valid;
    wire  result_status_ready;
    wire [3:0] result_status_fault;
    wire  result_status_committed;
    program_sequencer program_control (
        .clk(clk),
        .rst(rst),
        .cancel(service_flush),
        .load_begin_valid(load_begin_valid && load_open),
        .load_begin_ready(seq_load_begin_ready),
        .load_begin_revision(load_begin_revision),
        .load_begin_verified(load_begin_verified),
        .load_begin_program_count(load_begin_program_count),
        .load_begin_constant_count(load_begin_constant_count),
        .load_begin_template_count(load_begin_template_count),
        .load_begin_vector_count(load_begin_vector_count),
        .load_valid(load_valid && idle),
        .load_ready(seq_load_ready),
        .load_kind(load_kind),
        .load_index(load_index),
        .load_data(load_data),
        .load_last(load_last),
        .load_status_valid(load_status_valid),
        .load_status_ready(load_status_ready),
        .load_status_fault(load_status_fault),
        .image_valid(image_valid),
        .start_valid(state==LAUNCH),
        .start_ready(seq_start_ready),
        .start_rows(rows),
        .start_cols(columns),
        .start_key(key),
        .start_generation(generation),
        .start_scale(scale),
        .start_job(done_job),
        .start_tag(done_tag),
        .start_fmt(done_fmt),
        .start_instruction_limit(instruction_limit),
        .kernel_valid(kernel_valid),
        .kernel_ready(kernel_ready),
        .kernel_op(kernel_op),
        .kernel_contexts(kernel_contexts),
        .kernel_descriptor(kernel_descriptor),
        .kernel_src_a(kernel_src_a),
        .kernel_src_b(kernel_src_b),
        .kernel_dst(kernel_dst),
        .kernel_length(kernel_length),
        .kernel_rows(kernel_rows),
        .kernel_cols(kernel_cols),
        .kernel_matrix_dense(kernel_matrix_dense),
        .kernel_trans(kernel_trans),
        .kernel_r4(kernel_r4),
        .kernel_scalar_a(kernel_scalar_a),
        .kernel_scalar_b(kernel_scalar_b),
        .kernel_scalar_bind_a(kernel_scalar_bind_a),
        .kernel_scalar_bind_b(kernel_scalar_bind_b),
        .kernel_shift(kernel_shift),
        .kernel_k(kernel_k),
        .kernel_scale(kernel_scale),
        .kernel_key(kernel_key),
        .kernel_generation(kernel_generation),
        .kernel_job(kernel_job),
        .kernel_tag(kernel_tag),
        .kernel_fmt(kernel_fmt),
        .kernel_frame_count(kernel_frame_count),
        .kernel_tail_mask(kernel_tail_mask),
        .kernel_store_mode(kernel_store_mode),
        .kernel_support_base(kernel_support_base),
        .kernel_aux_base(kernel_aux_base),
        .kernel_support_length(kernel_support_length),
        .kernel_aux_length(kernel_aux_length),
        .kernel_index(kernel_index),
        .kernel_flags(kernel_flags),
        .kernel_rsp_valid(kernel_rsp_valid),
        .kernel_rsp_ready(kernel_rsp_ready),
        .kernel_rsp_fault(kernel_rsp_fault),
        .kernel_rsp_detail(kernel_rsp_detail),
        .kernel_rsp_data(kernel_rsp_data),
        .kernel_rsp_nonzero(kernel_rsp_nonzero),
        .kernel_rsp_count(kernel_rsp_count),
        .kernel_rsp_job(kernel_rsp_job),
        .kernel_rsp_tag(kernel_rsp_tag),
        .kernel_rsp_fmt(kernel_rsp_fmt),
        .scalar_valid(scalar_valid),
        .scalar_ready(scalar_ready),
        .scalar_op(scalar_op),
        .scalar_a(scalar_a),
        .scalar_b(scalar_b),
        .scalar_source_frac(scalar_source_frac),
        .scalar_job(scalar_job),
        .scalar_tag(scalar_tag),
        .scalar_fmt(scalar_fmt),
        .scalar_rsp_valid(scalar_rsp_valid),
        .scalar_rsp_ready(scalar_rsp_ready),
        .scalar_rsp_data(scalar_rsp_data),
        .scalar_rsp_fault(scalar_rsp_fault),
        .scalar_rsp_job(scalar_rsp_job),
        .scalar_rsp_tag(scalar_rsp_tag),
        .scalar_rsp_fmt(scalar_rsp_fmt),
        .build_valid(build_valid),
        .build_ready(build_ready),
        .build_support_base(build_support_base),
        .build_support_count(build_support_count),
        .build_job(build_job),
        .build_tag(build_tag),
        .build_fmt(build_fmt),
        .build_rsp_valid(build_rsp_valid),
        .build_rsp_ready(build_rsp_ready),
        .build_rsp_fault(build_rsp_fault),
        .build_rsp_job(build_rsp_job),
        .build_rsp_tag(build_rsp_tag),
        .build_rsp_fmt(build_rsp_fmt),
        .done_valid(seq_done_valid),
        .done_ready(seq_done_ready),
        .done_fault(seq_done_fault),
        .done_detail(seq_done_detail),
        .done_status(seq_done_status),
        .done_outer_iterations(seq_done_outer_iterations),
        .done_inner_iterations(seq_done_inner_iterations),
        .done_output_vector(seq_done_output_vector),
        .done_residual_vector(seq_done_residual_vector),
        .done_support_vector(seq_done_support_vector),
        .done_support_count(seq_done_support_count),
        .done_output_base(seq_done_output_base),
        .done_residual_base(seq_done_residual_base),
        .done_support_base(seq_done_support_base),
        .done_output_capacity(seq_done_output_capacity),
        .done_residual_capacity(seq_done_residual_capacity),
        .done_support_capacity(seq_done_support_capacity),
        .done_job(seq_done_job),
        .done_tag(seq_done_tag),
        .done_fmt(seq_done_fmt),
        .running(seq_running),
        .trace_pc(trace_pc),
        .trace_word(trace_word),
        .trace_retire(trace_retire)
    );
    stream_kernel kernel (
        .clk(clk),
        .rst(rst),
        .cancel(service_flush),
        .host_enable(host_access),
        .req_valid(kernel_valid && state==RUN),
        .req_ready(core_req_ready),
        .req_op(kernel_op),
        .req_contexts(kernel_contexts),
        .req_descriptor(kernel_descriptor),
        .req_src_a(kernel_src_a),
        .req_src_b(kernel_src_b),
        .req_dst(kernel_dst),
        .req_length(kernel_length),
        .req_rows(kernel_rows),
        .req_cols(kernel_cols),
        .req_matrix_dense(kernel_matrix_dense),
        .req_trans(kernel_trans),
        .req_r4(kernel_r4),
        .req_scalar_a(kernel_scalar_a),
        .req_scalar_b(kernel_scalar_b),
        .req_scalar_bind_a(kernel_scalar_bind_a),
        .req_scalar_bind_b(kernel_scalar_bind_b),
        .req_shift(kernel_shift),
        .req_k(kernel_k),
        .req_scale(kernel_scale),
        .req_key(kernel_key),
        .req_generation(kernel_matrix_dense ? b_generation : generation),
        .req_job(kernel_job),
        .req_tag(kernel_tag),
        .req_fmt(kernel_fmt),
        .req_frame_count(kernel_frame_count),
        .req_tail_mask(kernel_tail_mask),
        .req_store_mode(kernel_store_mode),
        .req_support_base(kernel_support_base),
        .req_aux_base(kernel_aux_base),
        .req_support_length(kernel_support_length),
        .req_aux_length(kernel_aux_length),
        .req_index(kernel_index),
        .req_flags(kernel_flags),
        .rsp_valid(kernel_rsp_valid),
        .rsp_ready(kernel_rsp_ready),
        .rsp_fault(kernel_rsp_fault),
        .rsp_detail(kernel_rsp_detail),
        .rsp_data(kernel_rsp_data),
        .rsp_nonzero(kernel_rsp_nonzero),
        .rsp_count(kernel_rsp_count),
        .rsp_job(kernel_rsp_job),
        .rsp_tag(kernel_rsp_tag),
        .rsp_fmt(kernel_rsp_fmt),
        .host_valid(core_host_valid),
        .host_ready(core_host_ready),
        .host_write(core_host_write),
        .host_block(core_host_block),
        .host_mask(core_host_mask),
        .host_data(core_host_data),
        .host_tag(core_host_tag),
        .host_rsp_valid(core_host_rsp_valid),
        .host_rsp_ready(core_host_rsp_ready),
        .host_rsp_write(core_host_rsp_write),
        .host_rsp_data(core_host_rsp_data),
        .host_rsp_mask(core_host_rsp_mask),
        .host_rsp_tag(core_host_rsp_tag),
        .host_rsp_fault(core_host_rsp_fault),
        .matrix_valid(selected_valid),
        .matrix_rows(selected_rows),
        .matrix_cols(selected_cols),
        .matrix_key(selected_key),
        .matrix_generation(selected_generation),
        .matrix_job(selected_job),
        .matrix_fmt(selected_fmt),
        .mat_valid(mat_valid),
        .mat_ready(mat_ready),
        .mat_dense(mat_dense),
        .mat_mask(mat_mask),
        .mat_addr(mat_addr),
        .mat_key(mat_key),
        .mat_generation(mat_generation),
        .mem_job(mem_job),
        .mem_tag(mem_tag),
        .mem_fmt(mem_fmt),
        .mat_rsp_valid(mat_rsp_valid),
        .mat_rsp_ready(mat_rsp_ready),
        .mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks),
        .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation),
        .mat_rsp_job(mat_rsp_job),
        .mat_rsp_tag(mat_rsp_tag),
        .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault),
        .operator_cancel(kernel_operator_cancel),
        .matrix_select(matrix_select),
        .busy(kernel_busy),
        .events(kernel_events)
    );
    live_operator_memory operator_memory (
        .clk(clk),
        .rst(rst),
        .cancel(service_flush || kernel_operator_cancel),
        .compute_active(kernel_busy || (kernel_valid && state==RUN)),
        .p_begin_valid(p_begin_valid && phi_open),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_begin_ready(live_p_begin_ready),
        .p_loading(p_loading),
        .p_fault(p_fault),
        .b_begin_valid(1'b0),
        .b_begin_ready(),
        .b_begin_rows(8'b0),
        .b_begin_cols(7'b0),
        .b_begin_key(128'b0),
        .b_begin_generation(32'b0),
        .b_begin_job(16'b0),
        .b_begin_fmt(8'b0),
        .b_fill_valid(1'b0),
        .b_fill_ready(),
        .b_fill_slot(7'b0),
        .b_fill_block(2'b0),
        .b_fill_mask(32'b0),
        .b_fill_data(576'b0),
        .b_fill_last(1'b0),
        .b_loading(b_loading),
        .b_load_fault(b_load_fault),
        .build_req_valid(live_build_req_valid),
        .build_req_ready(live_build_req_ready),
        .build_req_rows(live_build_req_rows),
        .build_req_cols(live_build_req_cols),
        .build_req_count(live_build_req_count),
        .build_req_support(live_build_req_support),
        .build_req_scale(live_build_req_scale),
        .build_req_phi_key(live_build_req_phi_key),
        .build_req_b_key(live_build_req_b_key),
        .build_req_phi_generation(live_build_req_phi_generation),
        .build_req_b_generation(live_build_req_b_generation),
        .build_req_job(live_build_req_job),
        .build_req_tag(live_build_req_tag),
        .build_req_fmt(live_build_req_fmt),
        .build_rsp_valid(live_build_rsp_valid),
        .build_rsp_ready(live_build_rsp_ready),
        .build_rsp_fault(live_build_rsp_fault),
        .build_rsp_job(live_build_rsp_job),
        .build_rsp_tag(live_build_rsp_tag),
        .build_rsp_fmt(live_build_rsp_fmt),
        .build_rsp_cycles(live_build_rsp_cycles),
        .build_rsp_words(live_build_rsp_words),
        .build_busy(live_build_busy),
        .p_valid(p_valid),
        .p_rows(p_rows),
        .p_cols(p_cols),
        .p_key(p_key),
        .p_generation(p_generation),
        .p_job(p_job),
        .p_fmt(p_fmt),
        .b_valid(b_valid),
        .b_rows(b_rows),
        .b_cols(b_cols),
        .b_key(b_key),
        .b_generation(b_generation),
        .b_job(b_job),
        .b_fmt(b_fmt),
        .mat_valid(mat_valid),
        .mat_ready(mat_ready),
        .mat_mask(mat_mask),
        .mat_addr(mat_addr),
        .mat_key(mat_key),
        .mat_generation(mat_generation),
        .mat_rsp_valid(mat_rsp_valid),
        .mat_rsp_ready(mat_rsp_ready),
        .mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks),
        .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation),
        .mat_rsp_job(mat_rsp_job),
        .mat_rsp_tag(mat_rsp_tag),
        .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault),
        .mat_dense(mat_dense),
        .mem_job(mem_job),
        .mem_tag(mem_tag),
        .mem_fmt(mem_fmt)
    );
    arithmetic_service arithmetic (
        .clk(clk),
        .rst(rst),
        .cancel(service_flush),
        .req_valid(scalar_valid),
        .req_ready(scalar_ready),
        .req_op(scalar_op),
        .req_a(scalar_a),
        .req_b(scalar_b),
        .req_source_frac(scalar_source_frac),
        .req_job(scalar_job),
        .req_tag(scalar_tag),
        .req_fmt(scalar_fmt),
        .rsp_valid(scalar_rsp_valid),
        .rsp_ready(scalar_rsp_ready),
        .rsp_data(scalar_rsp_data),
        .rsp_fault(scalar_rsp_fault),
        .rsp_job(scalar_rsp_job),
        .rsp_tag(scalar_rsp_tag),
        .rsp_fmt(scalar_rsp_fmt)
    );
    result_store results (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .abort(state==ABORT),
        .begin_valid(result_begin_valid),
        .begin_ready(result_begin_ready),
        .begin_rows(result_begin_rows),
        .begin_length(result_begin_length),
        .begin_mode(result_begin_mode),
        .begin_exponent(result_begin_exponent),
        .begin_active_support(result_begin_active_support),
        .begin_support_count(result_begin_support_count),
        .begin_support(result_begin_support),
        .begin_status(result_begin_status),
        .begin_outer_iterations(result_begin_outer_iterations),
        .begin_inner_iterations(result_begin_inner_iterations),
        .begin_job(result_begin_job),
        .begin_tag(result_begin_tag),
        .begin_fmt(result_begin_fmt),
        .begin_key(result_begin_key),
        .begin_generation(result_begin_generation),
        .fill_valid(result_fill_valid),
        .fill_ready(result_fill_ready),
        .fill_block(result_fill_block),
        .fill_mask(result_fill_mask),
        .fill_data(result_fill_data),
        .fill_last(result_fill_last),
        .fill_job(result_fill_job),
        .fill_tag(result_fill_tag),
        .fill_fmt(result_fill_fmt),
        .approve_valid(result_approve_valid),
        .approve_ready(result_approve_ready),
        .approve(result_approve),
        .approve_job(result_approve_job),
        .approve_tag(result_approve_tag),
        .approve_fmt(result_approve_fmt),
        .status_valid(result_status_valid),
        .status_ready(result_status_ready),
        .status_fault(result_status_fault),
        .status_committed(result_status_committed),
        .committed_valid(committed_valid),
        .committed_rows(committed_rows),
        .committed_length(committed_length),
        .committed_mode(committed_mode),
        .committed_exponent(committed_exponent),
        .committed_active_support(committed_active_support),
        .committed_support_count(committed_support_count),
        .committed_support(committed_support),
        .committed_status(committed_status),
        .committed_outer_iterations(committed_outer_iterations),
        .committed_inner_iterations(committed_inner_iterations),
        .committed_job(committed_job),
        .committed_tag(committed_tag),
        .committed_fmt(committed_fmt),
        .committed_key(committed_key),
        .committed_generation(committed_generation),
        .read_valid(read_valid),
        .read_ready(read_ready),
        .read_index(read_index),
        .read_tag(read_tag),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .read_rsp_data(read_rsp_data),
        .read_rsp_index(read_rsp_index),
        .read_rsp_request_tag(read_rsp_request_tag),
        .read_rsp_fault(read_rsp_fault),
        .read_rsp_mode(read_rsp_mode),
        .read_rsp_exponent(read_rsp_exponent),
        .read_rsp_length(read_rsp_length),
        .read_rsp_job(read_rsp_job),
        .read_rsp_tag(read_rsp_tag),
        .read_rsp_fmt(read_rsp_fmt)
    );

    assign busy=state!=IDLE;
    assign done_valid=state==DONE && !rst && !cancel;
    assign load_begin_ready=load_open && seq_load_begin_ready;
    assign load_ready=idle && seq_load_ready;
    assign p_begin_ready=phi_open && live_p_begin_ready;
    assign start_ready=idle && !loading && !load_begin_valid && !p_begin_valid && !p_loading &&
        !host_valid && !kernel_busy && seq_start_ready && !rst && !cancel;
    assign kernel_ready=state==RUN && core_req_ready;
    assign seq_done_ready=state==RUN;
    assign build_ready=state==RUN && !kernel_busy;
    assign build_rsp_valid=state==BUILD_RETURN;
    assign build_rsp_fault=0;
    assign build_rsp_job=build_job_q;
    assign build_rsp_tag=build_tag_q;
    assign build_rsp_fmt=build_fmt_q;

    // Existing host replies drain independently of new-request loader priority.
    assign host_ready=external_host && core_host_ready;
    assign host_rsp_valid=idle && core_host_rsp_valid;
    assign host_rsp_write=core_host_rsp_write;
    assign host_rsp_data=core_host_rsp_data;
    assign host_rsp_mask=core_host_rsp_mask;
    assign host_rsp_tag=core_host_rsp_tag;
    assign host_rsp_fault=core_host_rsp_fault;
    assign core_host_valid=(external_host && host_valid) || internal_read;
    assign core_host_write=external_host && host_write;
    assign core_host_block=external_host ? host_block :
        (state==RESULT_READ || state==RESULT_WAIT) ? output_base+result_block : collect_base+collect_position[6:5];
    assign core_host_mask=external_host ? host_mask :
        (state==RESULT_READ || state==RESULT_WAIT) ? mask_for(columns,result_block) : mask_for({4'b0,collect_count},{3'b0,collect_position[6:5]});
    assign core_host_data=external_host ? host_data : 864'b0;
    assign core_host_tag=external_host ? host_tag :
        (state==RESULT_READ || state==RESULT_WAIT) ? 16'he000+result_block :
        (collect_for_build ? 16'hb000 : 16'hd000)+collect_position[6:5];
    assign core_host_rsp_ready=idle ? host_rsp_ready : internal_wait;

    assign selected_valid=matrix_select ? b_valid : p_valid;
    assign selected_rows=matrix_select ? b_rows : p_rows;
    assign selected_cols=matrix_select ? {4'b0,b_cols} : p_cols;
    assign selected_key=matrix_select ? b_key : p_key;
    assign selected_generation=matrix_select ? b_generation : p_generation;
    assign selected_job=matrix_select ? b_job : p_job;
    assign selected_fmt=matrix_select ? b_fmt : p_fmt;
    assign live_build_req_valid=state==BUILD_REQUEST;
    assign live_build_req_rows=rows;
    assign live_build_req_cols=columns;
    assign live_build_req_count=collect_count;
    assign live_build_req_support=ordered_support;
    assign live_build_req_scale=scale;
    assign live_build_req_phi_key=key;
    assign live_build_req_b_key=key;
    assign live_build_req_phi_generation=generation;
    assign live_build_req_b_generation=build_generation;
    assign live_build_req_job=build_job_q;
    assign live_build_req_tag=build_tag_q;
    assign live_build_req_fmt=build_fmt_q;
    assign live_build_rsp_ready=state==BUILD_WAIT;

    assign result_begin_valid=state==RESULT_BEGIN;
    assign result_begin_rows=rows;
    assign result_begin_length=columns;
    assign result_begin_mode=storage_mode;
    assign result_begin_exponent=exponent;
    assign result_begin_active_support=active_support;
    assign result_begin_support_count=done_support_count;
    assign result_begin_support=ordered_support;
    assign result_begin_status=done_status;
    assign result_begin_outer_iterations=done_outer_iterations;
    assign result_begin_inner_iterations=done_inner_iterations;
    assign result_begin_job=done_job;
    assign result_begin_tag=done_tag;
    assign result_begin_fmt=done_fmt;
    assign result_begin_key=key;
    assign result_begin_generation=generation;
    assign result_fill_valid=state==RESULT_FILL;
    assign result_fill_block=result_block;
    assign result_fill_mask=mask_for(columns,result_block);
    assign result_fill_data=read_buffer;
    assign result_fill_last=(int'(result_block)+1)*32>=int'(columns);
    assign result_fill_job=done_job;
    assign result_fill_tag=done_tag;
    assign result_fill_fmt=done_fmt;
    assign result_approve_valid=state==RESULT_APPROVE;
    assign result_approve=1;
    assign result_approve_job=done_job;
    assign result_approve_tag=done_tag;
    assign result_approve_fmt=done_fmt;
    assign result_status_ready=state==RESULT_STATUS;

    function automatic [31:0] mask_for(input [10:0] size,input [4:0] block_number);
        integer i;
        begin
            mask_for=0;
            for(i=0;i<32;i=i+1) if(int'(block_number)*32+i<int'(size)) mask_for[i]=1;
        end
    endfunction
    function automatic span_ok(input [8:0] base,input [10:0] size);
        span_ok=size==0 || (int'(base)<480 && int'(base)+(int'(size)+31)/32<=480);
    endfunction
    task automatic fail(input [3:0] fault,input [3:0] detail);
        begin
            done_fault<=fault;
            done_detail<=detail;
            done_committed<=0;
            state<=ABORT;
        end
    endtask

    always @(posedge clk) begin
        if(rst || cancel) begin
            state<=IDLE;
            loading<=0;
            done_fault<=0;
            done_detail<=0;
            done_status<=0;
            done_outer_iterations<=0;
            done_inner_iterations<=0;
            done_support_count<=0;
            done_committed<=0;
            done_job<=0;
            done_tag<=0;
            done_fmt<=0;
            job_cycles<=0;
            if(rst) b_token<=0;
        end else begin
            if(load_begin_valid && load_begin_ready) loading<=1;
            if(load_status_valid && load_status_ready) loading<=0;
            if(state!=IDLE && state!=DONE) job_cycles<=job_cycles+1'b1;
            // A serializer fault can arrive while the next public block is prefetched.
            if(state>=RESULT_BEGIN && state<=RESULT_STATUS && result_status_valid && result_status_fault!=0)
                fail(`CSR_RECOVERY_FAULT_RESULT,result_status_fault);
            else case(state)
                IDLE: if(start_valid && start_ready) begin
                    rows<=start_rows;
                    columns<=start_cols;
                    key<=start_key;
                    generation<=start_generation;
                    scale<=start_scale;
                    instruction_limit<=start_instruction_limit;
                    storage_mode<=start_storage_mode;
                    exponent<=start_exponent;
                    active_support<=start_active_support;
                    done_job<=start_job;
                    done_tag<=start_tag;
                    done_fmt<=start_fmt;
                    done_fault<=0;
                    done_detail<=0;
                    done_status<=0;
                    done_outer_iterations<=0;
                    done_inner_iterations<=0;
                    done_support_count<=0;
                    done_committed<=0;
                    ordered_support<=0;
                    job_cycles<=0;
                    state<=LAUNCH;
                    if(start_rows==0 || start_rows>128 || start_cols==0 || start_cols>1024 ||
                       start_scale==0 || start_scale[17] || start_fmt!=1 || start_instruction_limit==0 ||
                       start_exponent< -31 || start_exponent>31 ||
                       (start_storage_mode!=1 && start_storage_mode!=2) || !p_valid ||
                       p_rows!=start_rows || p_cols!=start_cols || p_key!=start_key ||
                       p_generation!=start_generation || p_job!=start_job || p_fmt!=start_fmt)
                        fail(`CSR_RECOVERY_FAULT_START,0);
                end
                LAUNCH: if(seq_start_ready) state<=RUN;
                RUN: begin
                    if(build_valid && build_ready) begin
                        collect_for_build<=1;
                        collect_base<=build_support_base;
                        collect_count<=build_support_count[6:0];
                        collect_position<=0;
                        ordered_support<=0;
                        seen<=0;
                        build_job_q<=build_job;
                        build_tag_q<=build_tag;
                        build_fmt_q<=build_fmt;
                        build_generation<=b_token+1'b1;
                        state<=COLLECT_READ;
                        if(build_job!=done_job || build_fmt!=done_fmt)
                            fail(`CSR_RECOVERY_FAULT_IDENTITY,0);
                        else if(build_support_count==0 || build_support_count>96 || build_support_count>rows ||
                                !span_ok(build_support_base,build_support_count)) fail(`CSR_RECOVERY_FAULT_BUILD,1);
                        else if(b_token==32'hffffffff) fail(`CSR_RECOVERY_FAULT_GENERATION,0);
                    end else if(seq_done_valid) begin
                        done_status<=seq_done_status;
                        done_outer_iterations<=seq_done_outer_iterations;
                        done_inner_iterations<=seq_done_inner_iterations;
                        output_base<=seq_done_output_base;
                        result_block<=0;
                        ordered_support<=0;
                        if(seq_done_job!=done_job || seq_done_tag!=done_tag || seq_done_fmt!=done_fmt)
                            fail(`CSR_RECOVERY_FAULT_IDENTITY,0);
                        else if(seq_done_fault!=0 || seq_done_status>5)
                            fail(`CSR_RECOVERY_FAULT_PROGRAM,seq_done_fault!=0 ? seq_done_fault : seq_done_status[3:0]);
                        else if(seq_done_output_capacity<columns || !span_ok(seq_done_output_base,columns))
                            fail(`CSR_RECOVERY_FAULT_READ,1);
                        else if(active_support && (seq_done_support_count>96 || seq_done_support_count>columns ||
                                seq_done_support_capacity<seq_done_support_count || !span_ok(seq_done_support_base,seq_done_support_count)))
                            fail(`CSR_RECOVERY_FAULT_READ,2);
                        else begin
                            done_support_count<=active_support ? seq_done_support_count[6:0] : 0;
                            if(active_support && seq_done_support_count!=0) begin
                                collect_for_build<=0;
                                collect_base<=seq_done_support_base;
                                collect_count<=seq_done_support_count[6:0];
                                collect_position<=0;
                                seen<=0;
                                state<=COLLECT_READ;
                            end else state<=RESULT_BEGIN;
                        end
                    end
                end
                COLLECT_READ: if(core_host_ready) state<=COLLECT_WAIT;
                COLLECT_WAIT: if(core_host_rsp_valid) begin
                    if(core_host_rsp_fault!=0 || core_host_rsp_write || core_host_rsp_tag!=core_host_tag || core_host_rsp_mask!=core_host_mask)
                        fail(`CSR_RECOVERY_FAULT_READ,core_host_rsp_fault!=0 ? core_host_rsp_fault : 3);
                    else begin
                        read_buffer<=core_host_rsp_data;
                        state<=COLLECT_WORD;
                    end
                end
                COLLECT_WORD: begin
                    index_value=read_buffer[collect_position[4:0]*27 +: 27];
                    if(index_value>=columns || seen[index_value[9:0]])
                        fail(collect_for_build ? `CSR_RECOVERY_FAULT_BUILD : `CSR_RECOVERY_FAULT_READ,4);
                    else begin
                        seen[index_value[9:0]]<=1;
                        ordered_support[collect_position*10 +: 10]<=index_value[9:0];
                        collect_position<=collect_position+1'b1;
                        if(collect_position+1==collect_count) state<=collect_for_build ? BUILD_REQUEST : RESULT_BEGIN;
                        else if(collect_position[4:0]==31) state<=COLLECT_READ;
                    end
                end
                BUILD_REQUEST: if(live_build_req_ready) begin
                    b_token<=build_generation;
                    state<=BUILD_WAIT;
                end
                BUILD_WAIT: if(live_build_rsp_valid) begin
                    if(live_build_rsp_job!=build_job_q || live_build_rsp_tag!=build_tag_q || live_build_rsp_fmt!=build_fmt_q)
                        fail(`CSR_RECOVERY_FAULT_IDENTITY,1);
                    else if(live_build_rsp_fault!=0) fail(`CSR_RECOVERY_FAULT_BUILD,live_build_rsp_fault);
                    else state<=BUILD_RETURN;
                end
                BUILD_RETURN: if(build_rsp_ready) state<=RUN;
                RESULT_BEGIN: if(result_begin_ready) state<=RESULT_READ;
                RESULT_READ: if(core_host_ready) state<=RESULT_WAIT;
                RESULT_WAIT: if(core_host_rsp_valid) begin
                    if(core_host_rsp_fault!=0 || core_host_rsp_write || core_host_rsp_tag!=core_host_tag || core_host_rsp_mask!=core_host_mask)
                        fail(`CSR_RECOVERY_FAULT_READ,core_host_rsp_fault!=0 ? core_host_rsp_fault : 3);
                    else begin
                        read_buffer<=core_host_rsp_data;
                        state<=RESULT_FILL;
                    end
                end
                RESULT_FILL: if(result_fill_ready) begin
                    if((int'(result_block)+1)*32>=int'(columns)) state<=RESULT_APPROVE;
                    else begin
                        result_block<=result_block+1'b1;
                        state<=RESULT_READ;
                    end
                end
                RESULT_APPROVE: if(result_approve_ready) state<=RESULT_STATUS;
                RESULT_STATUS: if(result_status_valid) begin
                    done_committed<=result_status_committed;
                    if(!result_status_committed) fail(`CSR_RECOVERY_FAULT_RESULT,6);
                    else state<=DONE;
                end
                ABORT: state<=DONE;
                DONE: if(done_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
