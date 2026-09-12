`include "memory_defs.vh"
`include "scalar_interface.vh"
module lsqr_engine (
    input wire  clk,
    input wire  rst,
    input wire  cancel,
    input wire  p_begin_valid,
    input wire [31:0] p_begin_seed,
    input wire [7:0] p_begin_rows,
    input wire [10:0] p_begin_cols,
    input wire [127:0] p_begin_key,
    input wire [31:0] p_begin_generation,
    input wire [15:0] p_begin_job,
    input wire [7:0] p_begin_fmt,
    output wire  p_begin_ready,
    output wire  p_loading,
    output wire [3:0] p_fault,
    input wire  b_begin_valid,
    output wire  b_begin_ready,
    input wire [7:0] b_begin_rows,
    input wire [6:0] b_begin_cols,
    input wire [127:0] b_begin_key,
    input wire [31:0] b_begin_generation,
    input wire [15:0] b_begin_job,
    input wire [7:0] b_begin_fmt,
    input wire  b_fill_valid,
    output wire  b_fill_ready,
    input wire [6:0] b_fill_slot,
    input wire [1:0] b_fill_block,
    input wire [31:0] b_fill_mask,
    input wire [32*`CSR_PE_C_W-1:0] b_fill_data,
    input wire  b_fill_last,
    output wire  b_loading,
    output wire [3:0] b_load_fault,
    input wire  y_begin_valid,
    output wire  y_begin_ready,
    input wire [7:0] y_begin_rows,
    input wire [15:0] y_begin_job,
    input wire [7:0] y_begin_fmt,
    input wire  y_fill_valid,
    output wire  y_fill_ready,
    input wire [1:0] y_fill_block,
    input wire [31:0] y_fill_mask,
    input wire [575:0] y_fill_data,
    input wire  y_fill_last,
    output wire  y_loading,
    output wire  y_valid,
    output wire [3:0] y_fault,
    output wire [7:0] y_rows,
    output wire [7:0] y_fmt,
    output wire [15:0] y_job,
    input wire  program_load_begin_valid,
    output wire  program_load_begin_ready,
    input wire [7:0] program_load_revision,
    input wire  program_load_verified,
    input wire [8:0] program_load_depth,
    input wire  program_load_valid,
    output wire  program_load_ready,
    input wire [7:0] program_load_pc,
    input wire [127:0] program_load_word,
    input wire  program_load_last,
    output wire  program_image_valid,
    output wire [3:0] program_load_fault,
    input wire  start_valid,
    input wire  start_generated,
    input wire [7:0] start_rows,
    input wire [10:0] start_columns,
    input wire [6:0] start_count,
    input wire [959:0] start_support,
    input wire [17:0] start_scale,
    input wire [127:0] start_phi_key,
    input wire [31:0] start_phi_generation,
    input wire [127:0] start_b_key,
    input wire [31:0] start_b_generation,
    input wire [15:0] start_job,
    input wire [15:0] start_tag,
    input wire [7:0] start_fmt,
    input wire signed [6:0] start_exponent,
    input wire [7:0] start_max_iterations,
    input wire [31:0] start_instruction_limit,
    output wire  start_ready,
    output wire  done_valid,
    output wire [3:0] done_fault,
    output wire [3:0] done_detail,
    output wire  done_committed,
    output wire [7:0] done_iterations,
    output wire [63:0] done_normal_energy,
    output wire [63:0] done_rhs_energy,
    output wire [15:0] done_job,
    output wire [15:0] done_tag,
    output wire [7:0] done_fmt,
    input wire  done_ready,
    output wire  committed_valid,
    output wire [6:0] committed_count,
    output wire [7:0] committed_rows,
    input wire  read_valid,
    output wire  read_ready,
    input wire [6:0] read_slot,
    output wire  rsp_valid,
    input wire  rsp_ready,
    output wire signed [23:0] rsp_x,
    output wire [9:0] rsp_index,
    output wire signed [6:0] rsp_exponent,
    output wire [15:0] rsp_job,
    output wire [15:0] rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire [3:0] rsp_fault
);
    wire  op_p_begin_ready;
    wire  op_b_begin_ready;
    wire  op_b_fill_ready;
    wire  op_build_req_ready;
    wire  op_build_rsp_valid;
    wire [3:0] op_build_rsp_fault;
    wire [15:0] op_build_rsp_job;
    wire [15:0] op_build_rsp_tag;
    wire [7:0] op_build_rsp_fmt;
    wire [31:0] unused_op_build_rsp_cycles;
    wire [15:0] unused_op_build_rsp_words;
    wire  op_build_busy;
    wire  op_p_valid;
    wire [7:0] op_p_rows;
    wire [10:0] op_p_cols;
    wire [127:0] op_p_key;
    wire [31:0] op_p_generation;
    wire [15:0] op_p_job;
    wire [7:0] op_p_fmt;
    wire  op_b_valid;
    wire [7:0] op_b_rows;
    wire [6:0] op_b_cols;
    wire [127:0] op_b_key;
    wire [31:0] op_b_generation;
    wire [15:0] op_b_job;
    wire [7:0] op_b_fmt;
    wire  mat_valid;
    wire  mat_ready;
    wire [31:0] mat_mask;
    wire [287:0] mat_addr;
    wire [127:0] mat_key;
    wire [31:0] mat_generation;
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
    wire  mat_dense;
    wire [15:0] mem_job;
    wire [15:0] mem_tag;
    wire [7:0] mem_fmt;
    wire  host_begin_valid;
    wire  host_begin_ready;
    wire [3:0] host_slot;
    wire [7:0] host_length;
    wire [15:0] host_job;
    wire [15:0] host_tag;
    wire [7:0] host_fmt;
    wire  host_fill_valid;
    wire  host_fill_ready;
    wire [1:0] host_fill_block;
    wire [31:0] host_fill_mask;
    wire [863:0] host_fill_data;
    wire  host_fill_last;
    wire [3:0] host_fault;
    wire  kernel_valid;
    wire  kernel_ready;
    wire [3:0] kernel_op;
    wire [3:0] kernel_src_a;
    wire [3:0] kernel_src_b;
    wire [3:0] kernel_dst;
    wire [7:0] kernel_length;
    wire [7:0] kernel_rows;
    wire [6:0] kernel_cols;
    wire  kernel_trans;
    wire [26:0] kernel_scalar_a;
    wire [26:0] kernel_scalar_b;
    wire [5:0] kernel_shift;
    wire [127:0] kernel_key;
    wire [31:0] kernel_generation;
    wire [15:0] kernel_job;
    wire [15:0] kernel_tag;
    wire [7:0] kernel_fmt;
    wire  kernel_rsp_valid;
    wire  kernel_rsp_ready;
    wire [3:0] kernel_rsp_fault;
    wire [63:0] kernel_rsp_data;
    wire  kernel_rsp_nonzero;
    wire [15:0] kernel_rsp_job;
    wire [15:0] kernel_rsp_tag;
    wire [7:0] kernel_rsp_fmt;
    wire  k_debug_ready;
    wire  k_debug_rsp_valid;
    wire [863:0] k_debug_rsp_data;
    wire [31:0] k_debug_rsp_mask;
    wire [3:0] k_debug_rsp_fault;
    wire  s_load_begin_ready;
    wire  s_load_ready;
    wire  s_start_ready;
    wire  s_done_valid;
    wire [3:0] s_done_fault;
    wire [7:0] s_done_iterations;
    wire [63:0] s_done_normal_energy;
    wire [63:0] s_done_rhs_energy;
    wire [15:0] s_done_job;
    wire [15:0] s_done_tag;
    wire [7:0] s_done_fmt;
    wire  scalar_valid;
    wire  scalar_ready;
    wire [`CSR_SCALAR_OP_W-1:0] scalar_op;
    wire signed [`CSR_SCALAR_N_W-1:0] scalar_a;
    wire signed [`CSR_SCALAR_N_W-1:0] scalar_b;
    wire [`CSR_SCALAR_FRAC_W-1:0] scalar_source_frac;
    wire [`CSR_SCALAR_JOB_W-1:0] scalar_job;
    wire [`CSR_SCALAR_TAG_W-1:0] scalar_tag;
    wire [`CSR_SCALAR_FMT_W-1:0] scalar_fmt;
    wire  scalar_rsp_valid;
    wire  scalar_rsp_ready;
    wire signed [`CSR_SCALAR_S_W-1:0] scalar_rsp_data;
    wire [`CSR_SCALAR_FAULT_W-1:0] scalar_rsp_fault;
    wire [`CSR_SCALAR_JOB_W-1:0] scalar_rsp_job;
    wire [`CSR_SCALAR_TAG_W-1:0] scalar_rsp_tag;
    wire [`CSR_SCALAR_FMT_W-1:0] scalar_rsp_fmt;
    wire  unused_s_running;
    wire [7:0] unused_s_trace_pc;
    wire [127:0] unused_s_trace_word;
    wire  unused_s_trace_retire;
    wire  w_begin_ready;
    wire  w_fill_ready;
    wire  w_decision_ready;
    wire  w_status_valid;
    wire [3:0] w_status_fault;
    wire  w_status_committed;
    wire [15:0] w_status_job;
    wire [15:0] w_status_tag;
    wire [7:0] w_status_fmt;
    localparam [4:0] IDLE=0,CHECK=1,COMMIT_BEGIN=2,COMMIT_CHECK=3,BUILD=4,BUILD_WAIT=5,
        SEQ_START=6,RUN=7,READ_X=8,WRITE_X=9,APPROVE=10,STATUS=11,ABORT=12,DRAIN=13,DONE=14,CANCEL_WAIT=15,CHECK_SUPPORT=16;
    reg [4:0] state;
    reg generated,candidate_started;
    reg [7:0] rows,fmt,max_iterations;
    reg [10:0] columns;
    reg [6:0] count;
    reg [959:0] support;
    reg [17:0] scale;
    reg [127:0] phi_key,b_key;
    reg [31:0] phi_generation,b_generation,instruction_limit;
    reg [15:0] job,tag;
    reg signed [6:0] exponent;
    wire [3:0] s_done_candidate_slot;
    reg [3:0] candidate_slot;
    reg [1:0] result_block;
    reg [6:0] check_slot;
    reg [3:0] fault_q,detail_q;
    reg committed_q;
    reg [7:0] iterations_q;
    reg [63:0] normal_q,rhs_q;
    wire active=!rst&&!cancel;
    wire backend_cancel=cancel || state==ABORT;
    wire host_idle=active&&state==IDLE;
    wire host_request=p_begin_valid||b_begin_valid||y_begin_valid||program_load_begin_valid||program_load_valid;
    wire stores_busy=p_loading||b_loading||y_loading||op_build_busy;
    wire phi_good=op_p_valid&&op_p_rows==rows&&op_p_cols==columns&&op_p_key==phi_key&&
        op_p_generation==phi_generation&&op_p_job==job&&op_p_fmt==fmt;
    wire b_good=op_b_valid&&op_b_rows==rows&&op_b_cols==count&&op_b_key==b_key&&
        op_b_generation==b_generation&&op_b_job==job&&op_b_fmt==fmt;
    wire header_good=rows>0&&rows<=128&&columns>0&&columns<=1024&&count>0&&count<=96&&count<=columns&&
        fmt==1&&exponent>=-31&&exponent<=31&&max_iterations>0&&max_iterations<=128&&instruction_limit>0&&program_image_valid;
    assign start_ready=host_idle&&!stores_busy&&!host_request&&w_begin_ready&&s_start_ready;
    assign p_begin_ready=host_idle&&op_p_begin_ready;
    assign b_begin_ready=host_idle&&op_b_begin_ready;
    assign b_fill_ready=host_idle&&op_b_fill_ready;
    assign program_load_begin_ready=host_idle&&s_load_begin_ready;
    assign program_load_ready=host_idle&&s_load_ready;
    assign done_valid=active&&state==DONE;
    assign done_fault=fault_q;assign done_detail=detail_q;assign done_committed=committed_q;
    assign done_iterations=iterations_q;assign done_normal_energy=normal_q;assign done_rhs_energy=rhs_q;
    assign done_job=job;assign done_tag=tag;assign done_fmt=fmt;
    always @(posedge clk)begin
        if(rst)begin
            state<=IDLE;generated<=0;candidate_started<=0;rows<=0;columns<=0;count<=0;support<=0;scale<=0;
            phi_key<=0;b_key<=0;phi_generation<=0;b_generation<=0;job<=0;tag<=0;fmt<=0;exponent<=0;
            max_iterations<=0;instruction_limit<=0;result_block<=0;candidate_slot<=0;check_slot<=0;fault_q<=0;detail_q<=0;committed_q<=0;
            iterations_q<=0;normal_q<=0;rhs_q<=0;
        end else if(cancel)begin
            // Publication is irreversible at the accepted approval edge. A later
            // cancel flushes compute ownership but must report the committed result.
            if(state==STATUS)state<=STATUS;
            else if(state!=IDLE&&state!=DONE)begin state<=CANCEL_WAIT;fault_q<=8;detail_q<=0;committed_q<=0;end
        end else begin
            case(state)
                IDLE:if(start_valid&&start_ready)begin
                    generated<=start_generated;rows<=start_rows;columns<=start_columns;count<=start_count;support<=start_support;
                    scale<=start_scale;phi_key<=start_phi_key;b_key<=start_b_key;phi_generation<=start_phi_generation;
                    b_generation<=start_b_generation;job<=start_job;tag<=start_tag;fmt<=start_fmt;exponent<=start_exponent;
                    max_iterations<=start_max_iterations;instruction_limit<=start_instruction_limit;
                    fault_q<=0;detail_q<=0;committed_q<=0;iterations_q<=0;normal_q<=0;rhs_q<=0;candidate_started<=0;state<=CHECK;
                end
                CHECK:begin
                    if(!header_good)begin fault_q<=1;state<=DONE;end
                    else if(!y_valid||y_rows!=rows||y_job!=job||y_fmt!=fmt)begin fault_q<=2;detail_q<=y_fault;state<=DONE;end
                    else if(generated ? !phi_good : !b_good)begin fault_q<=3;state<=DONE;end
                    else begin check_slot<=0;state<=CHECK_SUPPORT;end;
                end
                CHECK_SUPPORT:begin
                    if({1'b0,support[int'(check_slot)*10+:10]}>=columns)begin fault_q<=1;state<=DONE;end
                    else if(check_slot+1==count)state<=COMMIT_BEGIN;
                    else check_slot<=check_slot+1'b1;
                end
                COMMIT_BEGIN:if(w_begin_ready)begin candidate_started<=1;state<=COMMIT_CHECK;end
                COMMIT_CHECK:begin
                    if(w_status_valid)begin fault_q<=7;detail_q<=w_status_fault;state<=DRAIN;end
                    else if(w_fill_ready)state<=generated ? BUILD : SEQ_START;
                end
                BUILD:if(op_build_req_ready)state<=BUILD_WAIT;
                BUILD_WAIT:if(op_build_rsp_valid)begin
                    if(op_build_rsp_fault!=0||op_build_rsp_job!=job||op_build_rsp_tag!=tag||op_build_rsp_fmt!=fmt||!b_good)begin
                        fault_q<=4;detail_q<=op_build_rsp_fault;state<=ABORT;
                    end else state<=SEQ_START;
                end
                SEQ_START:if(s_start_ready)state<=RUN;
                RUN:if(s_done_valid)begin
                    iterations_q<=s_done_iterations;normal_q<=s_done_normal_energy;rhs_q<=s_done_rhs_energy;
                    if(s_done_fault!=0||s_done_job!=job||s_done_tag!=tag||s_done_fmt!=fmt)begin fault_q<=5;detail_q<=s_done_fault;state<=ABORT;end
                    else begin result_block<=0;candidate_slot<=s_done_candidate_slot;state<=READ_X;end
                end
                READ_X:if(k_debug_ready)state<=WRITE_X;
                WRITE_X:begin
                    if(k_debug_rsp_valid&&k_debug_rsp_fault!=0)begin fault_q<=7;detail_q<=k_debug_rsp_fault;state<=ABORT;end
                    else if(w_status_valid)begin fault_q<=7;detail_q<=w_status_fault;state<=ABORT;end
                    else if(k_debug_rsp_valid&&w_fill_ready)begin
                        if((int'(result_block)+1)*32>=int'(count))state<=APPROVE;
                        else begin result_block<=result_block+1'b1;state<=READ_X;end
                    end
                end
                APPROVE:begin
                    if(w_status_valid)begin fault_q<=7;detail_q<=w_status_fault;state<=DRAIN;end
                    else if(w_decision_ready)state<=STATUS;
                end
                STATUS:if(w_status_valid)begin
                    if(w_status_fault!=0||!w_status_committed||w_status_job!=job||w_status_tag!=tag||w_status_fmt!=fmt)begin fault_q<=7;detail_q<=w_status_fault;end
                    else committed_q<=1;
                    candidate_started<=0;state<=DONE;
                end
                ABORT:state<=DRAIN;
                CANCEL_WAIT:state<=DRAIN;
                DRAIN:if(w_status_valid||!candidate_started)begin candidate_started<=0;state<=DONE;end
                DONE:if(done_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    operator_memory memory (
        .clk(clk), .rst(rst), .cancel(backend_cancel), .compute_active(state != IDLE && state != BUILD && state != BUILD_WAIT),
        .p_begin_valid(p_begin_valid && host_idle), .p_begin_seed(p_begin_seed), .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols), .p_begin_key(p_begin_key), .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job), .p_begin_fmt(p_begin_fmt), .p_begin_ready(op_p_begin_ready), .p_loading(p_loading),
        .p_fault(p_fault), .b_begin_valid(b_begin_valid && host_idle), .b_begin_ready(op_b_begin_ready),
        .b_begin_rows(b_begin_rows), .b_begin_cols(b_begin_cols), .b_begin_key(b_begin_key),
        .b_begin_generation(b_begin_generation), .b_begin_job(b_begin_job), .b_begin_fmt(b_begin_fmt),
        .b_fill_valid(b_fill_valid && host_idle), .b_fill_ready(op_b_fill_ready), .b_fill_slot(b_fill_slot),
        .b_fill_block(b_fill_block), .b_fill_mask(b_fill_mask), .b_fill_data(b_fill_data), .b_fill_last(b_fill_last),
        .b_loading(b_loading), .b_load_fault(b_load_fault), .build_req_valid(state == BUILD),
        .build_req_ready(op_build_req_ready), .build_req_rows(rows), .build_req_cols(columns), .build_req_count(count),
        .build_req_support(support), .build_req_scale(scale), .build_req_phi_key(phi_key), .build_req_b_key(b_key),
        .build_req_phi_generation(phi_generation), .build_req_b_generation(b_generation), .build_req_job(job),
        .build_req_tag(tag), .build_req_fmt(fmt), .build_rsp_valid(op_build_rsp_valid), .build_rsp_ready(state == BUILD_WAIT),
        .build_rsp_fault(op_build_rsp_fault), .build_rsp_job(op_build_rsp_job), .build_rsp_tag(op_build_rsp_tag),
        .build_rsp_fmt(op_build_rsp_fmt), .build_rsp_cycles(unused_op_build_rsp_cycles),
        .build_rsp_words(unused_op_build_rsp_words), .build_busy(op_build_busy), .p_valid(op_p_valid), .p_rows(op_p_rows),
        .p_cols(op_p_cols), .p_key(op_p_key), .p_generation(op_p_generation), .p_job(op_p_job), .p_fmt(op_p_fmt),
        .b_valid(op_b_valid), .b_rows(op_b_rows), .b_cols(op_b_cols), .b_key(op_b_key), .b_generation(op_b_generation),
        .b_job(op_b_job), .b_fmt(op_b_fmt), .mat_valid(mat_valid), .mat_ready(mat_ready), .mat_mask(mat_mask),
        .mat_addr(mat_addr), .mat_key(mat_key), .mat_generation(mat_generation), .mat_rsp_valid(mat_rsp_valid),
        .mat_rsp_ready(mat_rsp_ready), .mat_rsp_data(mat_rsp_data), .mat_rsp_masks(mat_rsp_masks), .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation), .mat_rsp_job(mat_rsp_job), .mat_rsp_tag(mat_rsp_tag), .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault), .mat_dense(mat_dense), .mem_job(mem_job), .mem_tag(mem_tag), .mem_fmt(mem_fmt)
    );
    measurement_loader measurement (
        .clk(clk), .rst(rst), .cancel(backend_cancel), .idle(host_idle), .begin_valid(y_begin_valid), .begin_ready(y_begin_ready),
        .begin_rows(y_begin_rows), .begin_job(y_begin_job), .begin_fmt(y_begin_fmt), .fill_valid(y_fill_valid),
        .fill_ready(y_fill_ready), .fill_block(y_fill_block), .fill_mask(y_fill_mask), .fill_data(y_fill_data),
        .fill_last(y_fill_last), .loading(y_loading), .valid(y_valid), .fault(y_fault), .rows(y_rows), .fmt(y_fmt), .job(y_job),
        .host_begin_valid(host_begin_valid), .host_begin_ready(host_begin_ready), .host_slot(host_slot),
        .host_length(host_length), .host_job(host_job), .host_tag(host_tag), .host_fmt(host_fmt),
        .host_fill_valid(host_fill_valid), .host_fill_ready(host_fill_ready), .host_fill_block(host_fill_block),
        .host_fill_mask(host_fill_mask), .host_fill_data(host_fill_data), .host_fill_last(host_fill_last), .host_fault(host_fault)
    );
    kernel_engine kernel (
        .clk(clk), .rst(rst), .cancel(backend_cancel), .req_valid(kernel_valid), .req_ready(kernel_ready), .req_op(kernel_op),
        .req_src_a(kernel_src_a), .req_src_b(kernel_src_b), .req_dst(kernel_dst), .req_length(kernel_length),
        .req_rows(kernel_rows), .req_cols(kernel_cols), .req_trans(kernel_trans), .req_scalar_a(kernel_scalar_a),
        .req_scalar_b(kernel_scalar_b), .req_shift(kernel_shift), .req_key(kernel_key), .req_generation(kernel_generation),
        .req_job(kernel_job), .req_tag(kernel_tag), .req_fmt(kernel_fmt), .rsp_valid(kernel_rsp_valid),
        .rsp_ready(kernel_rsp_ready), .rsp_fault(kernel_rsp_fault), .rsp_data(kernel_rsp_data), .rsp_nonzero(kernel_rsp_nonzero),
        .rsp_job(kernel_rsp_job), .rsp_tag(kernel_rsp_tag), .rsp_fmt(kernel_rsp_fmt), .host_begin_valid(host_begin_valid),
        .host_begin_ready(host_begin_ready), .host_slot(host_slot), .host_length(host_length), .host_job(host_job),
        .host_tag(host_tag), .host_fmt(host_fmt), .host_fill_valid(host_fill_valid), .host_fill_ready(host_fill_ready),
        .host_fill_block(host_fill_block), .host_fill_mask(host_fill_mask), .host_fill_data(host_fill_data),
        .host_fill_last(host_fill_last), .host_fault(host_fault), .debug_valid(state == READ_X), .debug_ready(k_debug_ready),
        .debug_slot(candidate_slot), .debug_block(result_block), .debug_rsp_valid(k_debug_rsp_valid),
        .debug_rsp_ready(state == WRITE_X && w_fill_ready), .debug_rsp_data(k_debug_rsp_data), .debug_rsp_mask(k_debug_rsp_mask),
        .debug_rsp_fault(k_debug_rsp_fault), .mat_valid(mat_valid), .mat_ready(mat_ready), .mat_dense(mat_dense),
        .mat_mask(mat_mask), .mat_addr(mat_addr), .mat_key(mat_key), .mat_generation(mat_generation), .mem_job(mem_job),
        .mem_tag(mem_tag), .mem_fmt(mem_fmt), .mat_rsp_valid(mat_rsp_valid), .mat_rsp_ready(mat_rsp_ready),
        .mat_rsp_data(mat_rsp_data), .mat_rsp_masks(mat_rsp_masks), .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation), .mat_rsp_job(mat_rsp_job), .mat_rsp_tag(mat_rsp_tag), .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault)
    );
    solver_sequencer sequencer (
        .clk(clk), .rst(rst), .cancel(backend_cancel), .load_begin_valid(program_load_begin_valid && host_idle),
        .load_begin_ready(s_load_begin_ready), .load_revision(program_load_revision), .load_verified(program_load_verified),
        .load_depth(program_load_depth), .load_valid(program_load_valid && host_idle), .load_ready(s_load_ready),
        .load_pc(program_load_pc), .load_word(program_load_word), .load_last(program_load_last),
        .image_valid(program_image_valid), .load_fault(program_load_fault), .start_valid(state == SEQ_START),
        .start_ready(s_start_ready), .start_rows(rows), .start_cols(count), .start_key(b_key), .start_generation(b_generation),
        .start_job(job), .start_tag(tag), .start_fmt(fmt), .start_max_iterations(max_iterations),
        .start_instruction_limit(instruction_limit), .done_valid(s_done_valid), .done_candidate_slot(s_done_candidate_slot), .done_ready(state == RUN),
        .done_fault(s_done_fault), .done_iterations(s_done_iterations), .done_normal_energy(s_done_normal_energy),
        .done_rhs_energy(s_done_rhs_energy), .done_job(s_done_job), .done_tag(s_done_tag), .done_fmt(s_done_fmt),
        .kernel_valid(kernel_valid), .kernel_ready(kernel_ready), .kernel_op(kernel_op), .kernel_src_a(kernel_src_a),
        .kernel_src_b(kernel_src_b), .kernel_dst(kernel_dst), .kernel_length(kernel_length), .kernel_rows(kernel_rows),
        .kernel_cols(kernel_cols), .kernel_trans(kernel_trans), .kernel_scalar_a(kernel_scalar_a),
        .kernel_scalar_b(kernel_scalar_b), .kernel_shift(kernel_shift), .kernel_key(kernel_key),
        .kernel_generation(kernel_generation), .kernel_job(kernel_job), .kernel_tag(kernel_tag), .kernel_fmt(kernel_fmt),
        .kernel_rsp_valid(kernel_rsp_valid), .kernel_rsp_ready(kernel_rsp_ready), .kernel_rsp_fault(kernel_rsp_fault),
        .kernel_rsp_data(kernel_rsp_data), .kernel_rsp_nonzero(kernel_rsp_nonzero), .kernel_rsp_job(kernel_rsp_job),
        .kernel_rsp_tag(kernel_rsp_tag), .kernel_rsp_fmt(kernel_rsp_fmt), .scalar_valid(scalar_valid),
        .scalar_ready(scalar_ready), .scalar_op(scalar_op), .scalar_a(scalar_a), .scalar_b(scalar_b),
        .scalar_source_frac(scalar_source_frac), .scalar_job(scalar_job), .scalar_tag(scalar_tag), .scalar_fmt(scalar_fmt),
        .scalar_rsp_valid(scalar_rsp_valid), .scalar_rsp_ready(scalar_rsp_ready), .scalar_rsp_data(scalar_rsp_data),
        .scalar_rsp_fault(scalar_rsp_fault), .scalar_rsp_job(scalar_rsp_job), .scalar_rsp_tag(scalar_rsp_tag),
        .scalar_rsp_fmt(scalar_rsp_fmt), .running(unused_s_running), .trace_pc(unused_s_trace_pc),
        .trace_word(unused_s_trace_word), .trace_retire(unused_s_trace_retire)
    );
    commit_controller commit (
        .clk(clk), .rst(rst), .cancel(cancel || state == ABORT), .begin_valid(state == COMMIT_BEGIN), .begin_ready(w_begin_ready),
        .begin_rows(rows), .begin_count(count), .begin_support(support), .begin_job(job), .begin_tag(tag), .begin_fmt(fmt),
        .begin_exponent(exponent), .fill_valid(state == WRITE_X && k_debug_rsp_valid && k_debug_rsp_fault == 0),
        .fill_ready(w_fill_ready), .fill_block(result_block), .fill_mask(k_debug_rsp_mask), .fill_data(k_debug_rsp_data),
        .fill_last((int'(result_block)+1)*32>=int'(count)), .fill_job(job), .fill_tag(tag), .fill_fmt(fmt),
        .decision_valid(state == APPROVE), .decision_ready(w_decision_ready), .decision_approve(1'b1), .decision_job(job),
        .decision_tag(tag), .decision_fmt(fmt), .status_valid(w_status_valid), .status_ready(state == STATUS || state == DRAIN),
        .status_fault(w_status_fault), .status_committed(w_status_committed), .status_job(w_status_job),
        .status_tag(w_status_tag), .status_fmt(w_status_fmt), .committed_valid(committed_valid),
        .committed_count(committed_count), .committed_rows(committed_rows), .read_valid(read_valid), .read_ready(read_ready),
        .read_slot(read_slot), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_x(rsp_x), .rsp_index(rsp_index),
        .rsp_exponent(rsp_exponent), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_fault(rsp_fault)
    );
    scalar_service scalar (
        .clk(clk), .rst(rst), .cancel(backend_cancel), .req_valid(scalar_valid), .req_ready(scalar_ready), .req_op(scalar_op),
        .req_a(scalar_a), .req_b(scalar_b), .req_source_frac(scalar_source_frac), .req_job(scalar_job), .req_tag(scalar_tag),
        .req_fmt(scalar_fmt), .rsp_valid(scalar_rsp_valid), .rsp_ready(scalar_rsp_ready), .rsp_data(scalar_rsp_data),
        .rsp_fault(scalar_rsp_fault), .rsp_job(scalar_rsp_job), .rsp_tag(scalar_rsp_tag), .rsp_fmt(scalar_rsp_fmt)
    );
endmodule
