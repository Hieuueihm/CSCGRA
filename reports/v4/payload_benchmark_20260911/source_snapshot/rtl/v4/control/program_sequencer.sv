`include "program_interface.vh"
`include "kernel_interface.vh"
module program_sequencer #(
    // The sole instruction buffer is filled when the resolved successor
    // retires.  Tests may set this to zero to measure the legacy FETCH gap.
    parameter RETIRE_TIME_FETCH=1'b1
) (
    input wire clk,rst,cancel,
    input wire load_begin_valid,output wire load_begin_ready,
    input wire [7:0] load_begin_revision,input wire load_begin_verified,
    input wire [10:0] load_begin_program_count,load_begin_constant_count,
    input wire [4:0] load_begin_template_count,input wire [5:0] load_begin_vector_count,
    input wire load_valid,output wire load_ready,input wire [2:0] load_kind,
    input wire [15:0] load_index,input wire [127:0] load_data,input wire load_last,
    output wire load_status_valid,input wire load_status_ready,output reg [3:0] load_status_fault,output reg image_valid,
    input wire start_valid,output wire start_ready,input wire [7:0] start_rows,
    input wire [10:0] start_cols,input wire [127:0] start_key,input wire [31:0] start_generation,
    input wire [17:0] start_scale,input wire [15:0] start_job,start_tag,input wire [7:0] start_fmt,
    input wire [31:0] start_instruction_limit,
    output wire kernel_valid,input wire kernel_ready,
    output wire [5:0] kernel_op,
    output wire [2047:0] kernel_contexts,
    output wire [31:0] kernel_descriptor,
    output wire [8:0] kernel_src_a,
    output wire [8:0] kernel_src_b,
    output wire [8:0] kernel_dst,
    output wire [10:0] kernel_length,
    output wire [7:0] kernel_rows,
    output wire [10:0] kernel_cols,
    output wire kernel_matrix_dense,
    output wire kernel_trans,
    output wire kernel_r4,
    output wire [26:0] kernel_scalar_a,
    output wire [26:0] kernel_scalar_b,
    output wire [31:0] kernel_scalar_bind_a,
    output wire [31:0] kernel_scalar_bind_b,
    output wire [5:0] kernel_shift,
    output wire [10:0] kernel_k,
    output wire [17:0] kernel_scale,
    output wire [127:0] kernel_key,
    output wire [31:0] kernel_generation,
    output wire [15:0] kernel_job,
    output wire [15:0] kernel_tag,
    output wire [7:0] kernel_fmt,
    output wire [7:0] kernel_frame_count,
    output wire [31:0] kernel_tail_mask,
    output wire [1:0] kernel_store_mode,
    output wire [8:0] kernel_support_base,
    output wire [8:0] kernel_aux_base,
    output wire [10:0] kernel_support_length,
    output wire [10:0] kernel_aux_length,
    output wire [10:0] kernel_index,
    output wire [7:0] kernel_flags,
    input wire kernel_rsp_valid,output wire kernel_rsp_ready,
    input wire [3:0] kernel_rsp_fault,
    input wire [3:0] kernel_rsp_detail,
    input wire [63:0] kernel_rsp_data,
    input wire kernel_rsp_nonzero,
    input wire [10:0] kernel_rsp_count,
    input wire [15:0] kernel_rsp_job,
    input wire [15:0] kernel_rsp_tag,
    input wire [7:0] kernel_rsp_fmt,
    output wire scalar_valid,input wire scalar_ready,output wire [1:0] scalar_op,
    output wire signed [63:0] scalar_a,scalar_b,output wire [7:0] scalar_source_frac,
    output wire [15:0] scalar_job,scalar_tag,output wire [7:0] scalar_fmt,
    input wire scalar_rsp_valid,output wire scalar_rsp_ready,input wire signed [26:0] scalar_rsp_data,
    input wire [2:0] scalar_rsp_fault,input wire [15:0] scalar_rsp_job,scalar_rsp_tag,input wire [7:0] scalar_rsp_fmt,
    output wire build_valid,input wire build_ready,output wire [8:0] build_support_base,
    output wire [10:0] build_support_count,output wire [15:0] build_job,build_tag,output wire [7:0] build_fmt,
    input wire build_rsp_valid,output wire build_rsp_ready,input wire [3:0] build_rsp_fault,
    input wire [15:0] build_rsp_job,build_rsp_tag,input wire [7:0] build_rsp_fmt,
    output wire done_valid,input wire done_ready,output reg [3:0] done_fault,done_detail,
    output reg [7:0] done_status,output wire [15:0] done_outer_iterations,done_inner_iterations,
    output reg [4:0] done_output_vector,done_residual_vector,done_support_vector,output wire [10:0] done_support_count,
    output wire [8:0] done_output_base,done_residual_base,done_support_base,
    output wire [10:0] done_output_capacity,done_residual_capacity,done_support_capacity,
    output reg [15:0] done_job,done_tag,output reg [7:0] done_fmt,
    output wire running,output reg [9:0] trace_pc,output reg [127:0] trace_word,output reg trace_retire
);

    localparam IDLE=0,LOAD=1,FETCH=2,EXEC=3,KREQ=4,KWAIT=5,SREQ=6,SWAIT=7,BREQ=8,BWAIT=9,CERTIFY=10,DONE=11;
    reg [3:0] state;
    reg load_pending;
    reg [2:0] load_phase;
    reg [15:0] next_load;
    reg [10:0] program_count,constant_count;
    reg [4:0] template_count;
    reg [5:0] vector_count;
    reg [127:0] program_mem[0:1023],word;
    reg [63:0] constants[0:1023];
    reg [95:0] template_meta[0:15];
    reg [2047:0] templates[0:15];
    reg [19:0] vectors[0:31];
    reg signed [63:0] rf[0:31];
    reg [9:0] pc,return_stack[0:3];
    reg [2:0] stack_depth;
    reg [31:0] limit,retired_count,generation;
    reg [15:0] operation_tag;
    reg [7:0] rows;
    reg [10:0] cols;
    reg [17:0] scale;
    reg [127:0] key;
    reg [127:0] sum_a,sum_b,term_a,term_b;
    reg [63:0] factor_a,factor_b;
    reg [5:0] cert_step;
    reg malformed;
    reg [127:0] allowed;
    reg [10:0] template_need_a,template_need_b;
    reg panel_context_valid;
    reg [63:0] checked_context,panel_context_word;
    integer check_lane,panel_lane,last_frame,needed_a,needed_b;
    integer n,e,tid,lane;
    wire active=!rst&&!cancel;
    wire signed [64:0] rf_sum=$signed({rf[f_a_s][63],rf[f_a_s]})+
        (f_kind==`CSR_PROGRAM_KIND_SUB64 ? -$signed({rf[f_b_s][63],rf[f_b_s]}) : $signed({rf[f_b_s][63],rf[f_b_s]}));
    wire [4:0] f_kind=word[`CSR_PROGRAM_FIELD_KIND_LSB +: `CSR_PROGRAM_FIELD_KIND_W];
    wire [5:0] f_kernel=word[`CSR_PROGRAM_FIELD_KERNEL_LSB +: `CSR_PROGRAM_FIELD_KERNEL_W];
    wire [4:0] f_dst_v=word[`CSR_PROGRAM_FIELD_DST_V_LSB +: `CSR_PROGRAM_FIELD_DST_V_W];
    wire [4:0] f_a_v=word[`CSR_PROGRAM_FIELD_A_V_LSB +: `CSR_PROGRAM_FIELD_A_V_W];
    wire [4:0] f_b_v=word[`CSR_PROGRAM_FIELD_B_V_LSB +: `CSR_PROGRAM_FIELD_B_V_W];
    wire [4:0] f_dst_s=word[`CSR_PROGRAM_FIELD_DST_S_LSB +: `CSR_PROGRAM_FIELD_DST_S_W];
    wire [4:0] f_a_s=word[`CSR_PROGRAM_FIELD_A_S_LSB +: `CSR_PROGRAM_FIELD_A_S_W];
    wire [4:0] f_b_s=word[`CSR_PROGRAM_FIELD_B_S_LSB +: `CSR_PROGRAM_FIELD_B_S_W];
    wire [4:0] f_flag_s=word[`CSR_PROGRAM_FIELD_FLAG_S_LSB +: `CSR_PROGRAM_FIELD_FLAG_S_W];
    wire [1:0] f_length_mode=word[`CSR_PROGRAM_FIELD_LENGTH_MODE_LSB +: `CSR_PROGRAM_FIELD_LENGTH_MODE_W];
    wire [4:0] f_shift_s=word[`CSR_PROGRAM_FIELD_SHIFT_S_LSB +: `CSR_PROGRAM_FIELD_SHIFT_S_W];
    wire [9:0] f_target=word[`CSR_PROGRAM_FIELD_TARGET_LSB +: `CSR_PROGRAM_FIELD_TARGET_W];
    wire [63:0] f_immediate=word[`CSR_PROGRAM_FIELD_IMMEDIATE_LSB +: `CSR_PROGRAM_FIELD_IMMEDIATE_W];
    wire [0:0] f_reserved=word[`CSR_PROGRAM_FIELD_RESERVED_LSB +: `CSR_PROGRAM_FIELD_RESERVED_W];
    wire [0:0] i_transpose=f_immediate[`CSR_PROGRAM_IMM_TRANSPOSE_LSB +: `CSR_PROGRAM_IMM_TRANSPOSE_W];
    wire [0:0] i_dense=f_immediate[`CSR_PROGRAM_IMM_DENSE_LSB +: `CSR_PROGRAM_IMM_DENSE_W];
    wire [0:0] i_r4=f_immediate[`CSR_PROGRAM_IMM_R4_LSB +: `CSR_PROGRAM_IMM_R4_W];
    wire [1:0] i_store_mode=f_immediate[`CSR_PROGRAM_IMM_STORE_MODE_LSB +: `CSR_PROGRAM_IMM_STORE_MODE_W];
    wire [3:0] i_template=f_immediate[`CSR_PROGRAM_IMM_TEMPLATE_LSB +: `CSR_PROGRAM_IMM_TEMPLATE_W];
    wire [7:0] i_flags=f_immediate[`CSR_PROGRAM_IMM_FLAGS_LSB +: `CSR_PROGRAM_IMM_FLAGS_W];
    wire [4:0] i_support_v=f_immediate[`CSR_PROGRAM_IMM_SUPPORT_V_LSB +: `CSR_PROGRAM_IMM_SUPPORT_V_W];
    wire [4:0] i_aux_v=f_immediate[`CSR_PROGRAM_IMM_AUX_V_LSB +: `CSR_PROGRAM_IMM_AUX_V_W];
    wire [4:0] i_k_s=f_immediate[`CSR_PROGRAM_IMM_K_S_LSB +: `CSR_PROGRAM_IMM_K_S_W];
    wire [4:0] i_support_length_s=f_immediate[`CSR_PROGRAM_IMM_SUPPORT_LENGTH_S_LSB +: `CSR_PROGRAM_IMM_SUPPORT_LENGTH_S_W];
    wire [4:0] i_aux_length_s=f_immediate[`CSR_PROGRAM_IMM_AUX_LENGTH_S_LSB +: `CSR_PROGRAM_IMM_AUX_LENGTH_S_W];
    wire [4:0] i_index_s=f_immediate[`CSR_PROGRAM_IMM_INDEX_S_LSB +: `CSR_PROGRAM_IMM_INDEX_S_W];
    wire [10:0] i_length=f_immediate[`CSR_PROGRAM_IMM_LENGTH_LSB +: `CSR_PROGRAM_IMM_LENGTH_W];
    wire [5:0] i_reserved=f_immediate[`CSR_PROGRAM_IMM_RESERVED_LSB +: `CSR_PROGRAM_IMM_RESERVED_W];
    wire [63:0] length_value=f_length_mode==0 ? {56'b0,rows} : f_length_mode==1 ? {53'b0,cols} :
        f_length_mode==2 ? {53'b0,i_length} : rf[i_length[4:0]];
    wire [63:0] columns_value=i_dense ? rf[i_support_length_s] : {53'b0,cols};
    wire [127:0] next_sum_a=sum_a+(factor_a[0] ? term_a : 128'd0);
    wire [127:0] next_sum_b=sum_b+(factor_b[0] ? term_b : 128'd0);
    wire [64:0] constant_address={1'b0,$unsigned(rf[f_a_s])}+{1'b0,f_immediate};
    wire scalar_template_command=f_kernel==`CSR_PROGRAM_KERNEL_SCALAR_TEMPLATE;
    wire [63:0] scalar_lane_context=templates[i_template][63:0];
    wire factor_extend_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_EXTEND;
    wire factor_command=(f_kernel>=`CSR_PROGRAM_KERNEL_FACTOR_INIT&&f_kernel<=`CSR_PROGRAM_KERNEL_FACTOR_WRITE)||factor_extend_command;
    wire factor_matvec_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_MATVEC;
    wire factor_rank1_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_RANK1;
    wire factor_project_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_PROJECT_UPDATE;
    wire scalar_insert_command=f_kernel==`CSR_PROGRAM_KERNEL_SCALAR_INSERT;
    wire range_template_command=f_kernel==`CSR_PROGRAM_KERNEL_RANGE_TEMPLATE;
    wire rounded_affine_command=f_kernel==`CSR_PROGRAM_KERNEL_ROUNDED_AFFINE;
    // FACTOR_RANGE_TEMPLATE is a factor-service command with a public
    // source/tap boundary.  It deliberately remains separate from the
    // legacy FACTOR_READ/WRITE validation: its source range has an
    // independent common offset and its response carries raw ACC64.
    wire factor_range_template_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_RANGE_TEMPLATE;
    // FACTOR_ENERGY_TAP is a factor-private square/MAC statistic and full tap.
    // It has no public A/B provider; its boolean tail statistic is returned
    // through the existing flag destination.
    wire factor_energy_tap_command=f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_ENERGY_TAP;
    wire rounded_affine_scalar_y=kernel_scalar_bind_b==32'h0000ffff;
    wire factor_panel_command=factor_matvec_command||factor_rank1_command||factor_project_command;
    wire range_command=f_kernel==`CSR_PROGRAM_KERNEL_SLICE||f_kernel==`CSR_PROGRAM_KERNEL_REPLACE_RANGE||scalar_insert_command;
    wire [11:0] factor_range_end={1'b0,rf[i_aux_length_s][10:0]}+{1'b0,length_value[10:0]};
    wire scalar_insert_bad=kernel_descriptor!=0||kernel_contexts!=0||kernel_scalar_bind_a!=0||kernel_scalar_bind_b!=0||
        !fits_state(rf[f_a_s])||f_b_v!=0||i_support_v!=0||i_aux_v!=0||f_b_s!=0||f_dst_s!=0||f_flag_s!=0||
        i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags!=0||rf[i_k_s]!=0||rf[i_support_length_s]!=0||
        rf[i_aux_length_s]!=0||rf[f_shift_s]!=0||f_target!=0||length_value==0||rf[i_index_s]>=length_value;
    // RANGE_TEMPLATE uses the ordinary loaded TEMPLATE arithmetic image, but
    // `index` and `aux_length` are independent A/B element offsets.  Keep
    // their capacity sums widened: a signed/high-bit value is rejected before
    // this 11-bit view can be used, and an unused RAM operand must be offset0.
    wire [11:0] range_template_a_end={1'b0,rf[i_index_s][10:0]}+{1'b0,template_need_a};
    wire [11:0] range_template_b_end={1'b0,rf[i_aux_length_s][10:0]}+{1'b0,template_need_b};
    wire range_template_bad=i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags!=0||
        rf[i_k_s]!=0||i_support_v!=0||i_aux_v!=0||rf[i_support_length_s]!=0||
        rf[f_shift_s]!=0||f_target!=0||kernel_descriptor[2:0]!=3'b111||
        rf[i_index_s]<0||rf[i_index_s]>1023||rf[i_aux_length_s]<0||rf[i_aux_length_s]>1023||
        (template_need_a==0 ? rf[i_index_s]!=0 : range_template_a_end>{1'b0,vectors[f_a_v][19:9]})||
        (template_need_b==0 ? rf[i_aux_length_s]!=0 : range_template_b_end>{1'b0,vectors[f_b_v][19:9]});
    // ROUNDED_AFFINE keeps a public command boundary while executing the
    // rounded low MUL and high C +/- product inside one Cascade16 fabric run.
    // The scalar-Y form deliberately permits RF0: every other unused raw
    // control is canonicalized at the kernel boundary.
    reg rounded_affine_context_valid;
    reg [63:0] rounded_affine_context_word;
    integer rounded_affine_lane;
    always @* begin
        rounded_affine_context_valid=kernel_descriptor==32'd7;
        for(rounded_affine_lane=0;rounded_affine_lane<32;rounded_affine_lane=rounded_affine_lane+1) begin
            rounded_affine_context_word=templates[i_template][rounded_affine_lane*64 +: 64];
            if(rounded_affine_context_word[63:10]!=0) rounded_affine_context_valid=0;
            if(rounded_affine_lane<16 &&
               (rounded_affine_context_word[4:0]!=`CSR_STREAM_OP_MUL ||
                !rounded_affine_context_word[5] ||
                rounded_affine_context_word[7:6]!=`CSR_STREAM_SRC_A ||
                rounded_affine_context_word[9:8]!=`CSR_STREAM_SRC_B))
                rounded_affine_context_valid=0;
            if(rounded_affine_lane>=16 &&
               ((rounded_affine_context_word[4:0]!=`CSR_STREAM_OP_ADD &&
                 rounded_affine_context_word[4:0]!=`CSR_STREAM_OP_SUB) ||
                rounded_affine_context_word[4:0]!=templates[i_template][16*64 +: 5] ||
                !rounded_affine_context_word[5] ||
                rounded_affine_context_word[7:6]!=`CSR_STREAM_SRC_A ||
                rounded_affine_context_word[9:8]!=`CSR_STREAM_SRC_B))
                rounded_affine_context_valid=0;
        end
    end
    wire rounded_affine_bad=!rounded_affine_context_valid ||
        i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags!=0||
        i_support_v!=0||i_k_s!=0||i_support_length_s!=0||i_aux_length_s!=0||
        i_index_s!=0||f_a_s!=0||f_dst_s!=0||f_flag_s!=0||f_shift_s!=0||f_target!=0||
        kernel_scalar_bind_a!=0||
        !((kernel_scalar_bind_b==0 && f_b_s==0) ||
          (kernel_scalar_bind_b==32'h0000ffff && f_b_v==0 && fits_state(rf[f_b_s])));
    // The op24 template is intentionally fixed: direct MAC contexts feed a
    // SUM_ACC terminal.  The factor-panel service owns execution and
    // publication, while this boundary rejects malformed programs before any
    // request is made.
    reg factor_range_context_valid;
    reg [63:0] factor_range_context_word;
    integer factor_range_lane;
    always @* begin
        factor_range_context_valid=kernel_descriptor==32'd23 &&
            kernel_scalar_bind_a==0 && kernel_scalar_bind_b==0 &&
            kernel_descriptor[4:3]==`CSR_STREAM_OUTPUT_SUM_ACC;
        for(factor_range_lane=0;factor_range_lane<32;factor_range_lane=factor_range_lane+1) begin
            factor_range_context_word=templates[i_template][factor_range_lane*64 +: 64];
            if(factor_range_context_word!=64'd297) factor_range_context_valid=0;
        end
    end
    wire factor_range_template_bad=!factor_range_context_valid ||
        !i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags[7:3]!=0||
        i_support_v!=0||i_aux_v!=0||i_k_s!=0||f_shift_s!=0||
        f_b_v!=0||f_b_s!=0||f_flag_s!=0||f_target!=0||
        columns_value==0||columns_value>96||length_value==0||length_value>128||
        rf[i_support_length_s]<0||rf[i_support_length_s]>96||
        rf[i_index_s]<0||rf[i_aux_length_s]<0||
        (i_flags[2] ? !fits_state(rf[f_a_s]) : f_a_s!=0) ||
        (i_flags[0] ?
         (rf[i_index_s]>={56'b0,rows}||factor_range_end>{1'b0,columns_value[10:0]}) :
         (rf[i_index_s]>=columns_value||factor_range_end>{4'b0,rows}));
    wire factor_energy_tap_bad=!factor_range_context_valid ||
        !i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags[7:1]!=0||
        i_support_v!=0||i_aux_v!=0||i_k_s!=0||f_shift_s!=0||f_target!=10'd1||
        f_a_v!=0||f_b_v!=0||f_a_s!=0||f_b_s!=0||f_dst_s==0||f_flag_s==0||f_dst_s==f_flag_s||
        columns_value==0||columns_value>96||length_value==0||length_value>128||
        rf[i_support_length_s]<0||rf[i_support_length_s]>96||
        rf[i_index_s]<0||rf[i_aux_length_s]<0||
        (i_flags[0] ?
         (rf[i_index_s]>={56'b0,rows}||factor_range_end>{1'b0,columns_value[10:0]}) :
         (rf[i_index_s]>=columns_value||factor_range_end>{4'b0,rows}));
    wire factor_extend_bad=!i_dense||columns_value>96||length_value>128||i_flags!=0||
        i_transpose||i_r4||i_store_mode!=0||rf[i_k_s]!=0||length_value!=rows||
        rf[i_index_s]<=0||rf[i_index_s]>=columns_value||rf[i_aux_length_s]!=0||
        kernel_descriptor!=0||kernel_contexts!=0||kernel_scalar_bind_a!=0||kernel_scalar_bind_b!=0||
        f_a_v!=0||f_b_v!=0||f_dst_v!=0||i_support_v!=0||i_aux_v!=0||
        f_a_s!=0||f_b_s!=0||f_dst_s!=0||f_flag_s!=0||rf[f_shift_s]!=0||f_target!=0;
    wire factor_legacy_bad=!i_dense||columns_value>96||length_value>128||i_flags[7:1]!=0||
        i_transpose||i_r4||i_store_mode!=0||rf[i_k_s]!=0||
        (f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_INIT ?
         (length_value!=rows||rf[i_index_s]!=0||rf[i_aux_length_s]!=0||i_flags!=0) :
         (rf[i_index_s]>=(i_flags[0] ? {56'b0,rows} : columns_value)||
          factor_range_end>(i_flags[0] ? {1'b0,columns_value[10:0]} : {4'b0,rows})));
    wire [10:0] panel_columns=columns_value[10:0]-rf[i_index_s][10:0];
    wire [11:0] panel_row_end={1'b0,rf[i_aux_length_s][10:0]}+{1'b0,length_value[10:0]};
    wire panel_operand_bad=factor_project_command ? (f_b_v!=0||f_dst_v!=0||vectors[f_a_v][19:9]<length_value) :
        factor_matvec_command ? (f_a_s!=0||f_b_v!=0||vectors[f_dst_v][19:9]<panel_columns) :
        (f_a_s!=0||f_dst_v!=0||vectors[f_b_v][19:9]<panel_columns);
    wire [10:0] source_need=(scalar_template_command||range_template_command||factor_energy_tap_command) ? 11'd0 : factor_range_template_command ? factor_range_end[10:0] : (f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_INIT||f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_READ||f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_EXTEND) ? 11'd0 : f_kernel==`CSR_PROGRAM_KERNEL_TEMPLATE ? template_need_a : f_kernel==`CSR_PROGRAM_KERNEL_UNION ? 11'd0 : f_kernel==`CSR_PROGRAM_KERNEL_SCATTER ? rf[i_support_length_s][10:0] : f_kernel==`CSR_PROGRAM_KERNEL_GEMV ? (i_transpose ? {3'b0,rows} : columns_value[10:0]) : length_value[10:0];
    wire [10:0] range_template_output_need=kernel_descriptor[4:3]==`CSR_STREAM_OUTPUT_SUM_ACC ? 11'd0 :
        kernel_descriptor[4:3]==`CSR_STREAM_OUTPUT_LAST_ACC ? (length_value[10:0]>11'd32 ? 11'd32 : length_value[10:0]) : length_value[10:0];
    wire [10:0] output_need=scalar_template_command ? 11'd0 : factor_energy_tap_command ? length_value[10:0] : factor_range_template_command ? (i_flags[1] ? 11'd1 : length_value[10:0]) : range_template_command ? range_template_output_need : f_kernel==`CSR_PROGRAM_KERNEL_GEMV ? (i_transpose ? columns_value[10:0] : {3'b0,rows}) :
        (f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_INIT||f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_WRITE||f_kernel==`CSR_PROGRAM_KERNEL_FACTOR_EXTEND||factor_rank1_command||factor_project_command) ? 11'd0 :
        factor_matvec_command ? panel_columns :
        f_kernel==`CSR_PROGRAM_KERNEL_SLICE ? rf[i_aux_length_s][10:0] :
        (f_kernel==`CSR_PROGRAM_KERNEL_TOPK||f_kernel==`CSR_PROGRAM_KERNEL_UNION) ? rf[i_k_s][10:0] :
        f_kernel==`CSR_PROGRAM_KERNEL_GATHER ? rf[i_support_length_s][10:0] : f_kernel==`CSR_PROGRAM_KERNEL_PICK ? 11'd0 : length_value[10:0];
    assign running=state!=IDLE&&state!=LOAD&&state!=DONE;
    assign load_begin_ready=active&&state==IDLE&&!load_pending;
    assign load_ready=active&&state==LOAD;
    assign load_status_valid=active&&load_pending;
    assign start_ready=active&&state==IDLE&&!load_pending&&image_valid&&!load_begin_valid;
    assign done_valid=active&&state==DONE;
    assign done_outer_iterations=rf[26][15:0];assign done_inner_iterations=rf[25][15:0];
    assign done_support_count=rf[29][10:0];
    assign done_output_base=vectors[done_output_vector][8:0];assign done_output_capacity=vectors[done_output_vector][19:9];
    assign done_residual_base=vectors[done_residual_vector][8:0];assign done_residual_capacity=vectors[done_residual_vector][19:9];
    assign done_support_base=vectors[done_support_vector][8:0];assign done_support_capacity=vectors[done_support_vector][19:9];
    assign kernel_valid=active&&state==KREQ;
    assign kernel_rsp_ready=active&&state==KWAIT;
    assign kernel_op=f_kernel;assign kernel_contexts=templates[i_template];
    assign kernel_descriptor=template_meta[i_template][31:0];
    assign kernel_scalar_bind_a=template_meta[i_template][63:32];
    assign kernel_scalar_bind_b=template_meta[i_template][95:64];
    // Bound only RAM elements actually selected by active template lanes.
    // Scalar bindings replace input buses; MOV never consumes source B.
    always @* begin
        template_need_a=0;template_need_b=0;checked_context=0;
        last_frame=0;needed_a=0;needed_b=0;
        for(check_lane=0;check_lane<32;check_lane=check_lane+1)begin
            checked_context=templates[i_template][check_lane*64 +:64];
            if(length_value>check_lane&&length_value<=1024)begin
                last_frame=(int'(length_value)-1-check_lane)>>5;
                needed_a=(kernel_descriptor[0] ? last_frame*32 : 0)+check_lane+1;
                needed_b=(kernel_descriptor[1] ? last_frame*32 : 0)+check_lane+1;
                if(!kernel_scalar_bind_a[check_lane]&&
                   (checked_context[7:6]==0||(checked_context[4:0]!=1&&checked_context[9:8]==0))&&needed_a>template_need_a)
                    template_need_a=needed_a[10:0];
                if(!kernel_scalar_bind_b[check_lane]&&
                   (checked_context[7:6]==1||(checked_context[4:0]!=1&&checked_context[9:8]==1))&&needed_b>template_need_b)
                    template_need_b=needed_b[10:0];
            end
        end
    end
    // These operations are transport-specialized only.  They remain bound to
    // explicit, unbound direct-A/direct-B loaded PE images.
    always @* begin
        panel_context_valid=template_meta[i_template][31:0]==(factor_matvec_command ? 32'd23 : factor_rank1_command ? 32'd7 : `CSR_KERNEL_PROJECT_DESCRIPTOR)&&
            template_meta[i_template][95:32]==64'd0;
        for(panel_lane=0;panel_lane<32;panel_lane=panel_lane+1)begin
            panel_context_word=templates[i_template][panel_lane*64 +:64];
            if(factor_matvec_command&&panel_context_word!=64'd297)panel_context_valid=0;
            if(factor_rank1_command&&panel_context_word!=(panel_lane<16 ? 64'd296 : 64'd291))panel_context_valid=0;
            if(factor_project_command&&panel_context_word!=(panel_lane==0 ? `CSR_KERNEL_PROJECT_DOT_CONTEXT : panel_lane==1 ? `CSR_KERNEL_PROJECT_SCALE_CONTEXT : panel_lane==2 ? `CSR_KERNEL_PROJECT_RANK_CONTEXT : `CSR_KERNEL_PROJECT_PADDING_CONTEXT))panel_context_valid=0;
        end
    end
    assign kernel_src_a=factor_energy_tap_command ? 9'd0 : vectors[f_a_v][8:0];assign kernel_src_b=(scalar_insert_command||factor_range_template_command||factor_energy_tap_command||(rounded_affine_command&&rounded_affine_scalar_y)) ? 9'd0 : vectors[f_b_v][8:0];assign kernel_dst=vectors[f_dst_v][8:0];
    assign kernel_length=length_value[10:0];assign kernel_rows=rows;assign kernel_cols=columns_value[10:0];
    assign kernel_matrix_dense=i_dense;assign kernel_trans=i_transpose;assign kernel_r4=i_r4;
    assign kernel_scalar_a=factor_range_template_command ? (i_flags[2] ? rf[f_a_s][26:0] : 27'd0) : (factor_energy_tap_command||rounded_affine_command) ? 27'd0 : rf[f_a_s][26:0];assign kernel_scalar_b=(factor_range_template_command||factor_energy_tap_command||(rounded_affine_command&&!rounded_affine_scalar_y)) ? 27'd0 : rf[f_b_s][26:0];assign kernel_shift=(factor_range_template_command||factor_energy_tap_command||rounded_affine_command) ? 6'd0 : rf[f_shift_s][5:0];
    assign kernel_k=(factor_range_template_command||factor_energy_tap_command||rounded_affine_command) ? 11'd0 : rf[i_k_s][10:0];assign kernel_scale=scale;assign kernel_key=key;assign kernel_generation=generation;
    assign kernel_job=done_job;assign kernel_tag=operation_tag;assign kernel_fmt=done_fmt;
    assign kernel_frame_count=(factor_range_template_command||factor_energy_tap_command) ? 8'd0 : (length_value[10:0]+11'd31)>>5;
    assign kernel_tail_mask=(factor_range_template_command||factor_energy_tap_command) ? 32'd0 : (length_value[4:0]==0 ? 32'hffffffff : (32'd1<<length_value[4:0])-1'b1);
    assign kernel_store_mode=i_store_mode;assign kernel_support_base=(scalar_insert_command||range_template_command||factor_range_template_command||factor_energy_tap_command||rounded_affine_command) ? 9'd0 : vectors[i_support_v][8:0];
    assign kernel_aux_base=(scalar_insert_command||range_template_command||factor_range_template_command||factor_energy_tap_command) ? 9'd0 : vectors[i_aux_v][8:0];assign kernel_support_length=rounded_affine_command ? 11'd0 : rf[i_support_length_s][10:0];
    assign kernel_aux_length=rounded_affine_command ? 11'd0 : rf[i_aux_length_s][10:0];assign kernel_index=rounded_affine_command ? 11'd0 : rf[i_index_s][10:0];assign kernel_flags=i_flags;
    assign scalar_valid=active&&state==SREQ;assign scalar_rsp_ready=active&&state==SWAIT;
    assign scalar_op=f_kind==`CSR_PROGRAM_KIND_DIV ? 2'd0 : f_kind==`CSR_PROGRAM_KIND_RESCALE ? 2'd2 : 2'd1;
    assign scalar_a=rf[f_a_s];assign scalar_b=rf[f_b_s];
    assign scalar_source_frac=f_kind==`CSR_PROGRAM_KIND_DIV ? f_immediate[7:0] : 8'd44;
    assign scalar_job=done_job;assign scalar_tag=operation_tag;assign scalar_fmt=done_fmt;
    assign build_valid=active&&state==BREQ;assign build_rsp_ready=active&&state==BWAIT;
    assign build_support_base=vectors[f_a_v][8:0];assign build_support_count=rf[f_a_s][10:0];
    assign build_job=done_job;assign build_tag=operation_tag;assign build_fmt=done_fmt;

    function automatic fits_state(input signed [63:0] value);
        fits_state=value>=-64'sd67108864&&value<=64'sd67108863;
    endfunction
    function automatic compare(input signed [63:0] a,b,input [2:0] predicate);
        case(predicate)
            0:compare=a==b;1:compare=a!=b;2:compare=a<b;3:compare=a<=b;4:compare=a>b;5:compare=a>=b;
            default:compare=0;
        endcase
    endfunction
    task fail(input [3:0] fault,detail);
        begin done_fault<=fault;done_detail<=detail;done_status<=`CSR_PROGRAM_STATUS_NUMERIC_FAULT;state<=DONE;end
    endtask
    task retire(input [10:0] next_pc);
        begin
            trace_pc<=pc;trace_word<=word;trace_retire<=1;retired_count<=retired_count+1'b1;
            if (next_pc>=program_count) fail(`CSR_PROGRAM_FAULT_PROGRAM,0);
            else begin
                pc<=next_pc[9:0];
                // `word` is the one-word synchronous instruction buffer.  Do
                // not read until the executing instruction has resolved and
                // validated its successor; services retire only after a
                // matching response, so this has no speculative side effect.
                if(RETIRE_TIME_FETCH)begin
                    word<=program_mem[next_pc[9:0]];
                    state<=EXEC;
                end else state<=FETCH;
            end
        end
    endtask
    task load_fail;
        begin image_valid<=0;load_status_fault<=`CSR_PROGRAM_FAULT_LOAD;load_pending<=1;state<=IDLE;end
    endtask
    // Every non-reserved field still has instruction-specific validation below.
    always @* begin
        allowed=0;
        case(f_kind)
            `CSR_PROGRAM_KIND_NOP:allowed=`CSR_PROGRAM_ALLOWED_NOP;
            `CSR_PROGRAM_KIND_KERNEL:allowed=`CSR_PROGRAM_ALLOWED_KERNEL;
            `CSR_PROGRAM_KIND_DIV:allowed=`CSR_PROGRAM_ALLOWED_DIV;
            `CSR_PROGRAM_KIND_SQRT:allowed=`CSR_PROGRAM_ALLOWED_SQRT;
            `CSR_PROGRAM_KIND_SET:allowed=`CSR_PROGRAM_ALLOWED_SET;
            `CSR_PROGRAM_KIND_MOV:allowed=`CSR_PROGRAM_ALLOWED_MOV;
            `CSR_PROGRAM_KIND_NEG:allowed=`CSR_PROGRAM_ALLOWED_NEG;
            `CSR_PROGRAM_KIND_RECIP_PREP:allowed=`CSR_PROGRAM_ALLOWED_RECIP_PREP;
            `CSR_PROGRAM_KIND_BR_ZERO:allowed=`CSR_PROGRAM_ALLOWED_BR_ZERO;
            `CSR_PROGRAM_KIND_BR_NONZERO:allowed=`CSR_PROGRAM_ALLOWED_BR_NONZERO;
            `CSR_PROGRAM_KIND_JUMP:allowed=`CSR_PROGRAM_ALLOWED_JUMP;
            `CSR_PROGRAM_KIND_CERT:allowed=`CSR_PROGRAM_ALLOWED_CERT;
            `CSR_PROGRAM_KIND_INC:allowed=`CSR_PROGRAM_ALLOWED_INC;
            `CSR_PROGRAM_KIND_BR_GE:allowed=`CSR_PROGRAM_ALLOWED_BR_GE;
            `CSR_PROGRAM_KIND_SUCCESS:allowed=`CSR_PROGRAM_ALLOWED_SUCCESS;
            `CSR_PROGRAM_KIND_FAIL:allowed=`CSR_PROGRAM_ALLOWED_FAIL;
            `CSR_PROGRAM_KIND_CALL:allowed=`CSR_PROGRAM_ALLOWED_CALL;
            `CSR_PROGRAM_KIND_RET:allowed=`CSR_PROGRAM_ALLOWED_RET;
            `CSR_PROGRAM_KIND_CONST_LOAD:allowed=`CSR_PROGRAM_ALLOWED_CONST_LOAD;
            `CSR_PROGRAM_KIND_BR_COMPARE:allowed=`CSR_PROGRAM_ALLOWED_BR_COMPARE;
            `CSR_PROGRAM_KIND_HALT_STATUS:allowed=`CSR_PROGRAM_ALLOWED_HALT_STATUS;
            `CSR_PROGRAM_KIND_BUILD_B:allowed=`CSR_PROGRAM_ALLOWED_BUILD_B;
            `CSR_PROGRAM_KIND_ADD64:allowed=`CSR_PROGRAM_ALLOWED_ADD64;
            `CSR_PROGRAM_KIND_SUB64:allowed=`CSR_PROGRAM_ALLOWED_SUB64;
            `CSR_PROGRAM_KIND_RESCALE:allowed=`CSR_PROGRAM_ALLOWED_RESCALE;
            default:allowed=0;
        endcase
        malformed=(word&~allowed)!=0||f_kind>`CSR_PROGRAM_KIND_RESCALE;
        if ((f_kind==`CSR_PROGRAM_KIND_DIV||f_kind==`CSR_PROGRAM_KIND_SQRT||f_kind==`CSR_PROGRAM_KIND_SET||
             f_kind==`CSR_PROGRAM_KIND_MOV||f_kind==`CSR_PROGRAM_KIND_NEG||f_kind==`CSR_PROGRAM_KIND_RECIP_PREP||
             f_kind==`CSR_PROGRAM_KIND_CERT||f_kind==`CSR_PROGRAM_KIND_INC||f_kind==`CSR_PROGRAM_KIND_CONST_LOAD||
             f_kind==`CSR_PROGRAM_KIND_ADD64||f_kind==`CSR_PROGRAM_KIND_SUB64||f_kind==`CSR_PROGRAM_KIND_RESCALE)&&f_dst_s==0)
            malformed=1;
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;image_valid<=0;load_pending<=0;load_status_fault<=0;load_phase<=0;next_load<=0;
            program_count<=0;constant_count<=0;template_count<=0;vector_count<=0;pc<=0;word<=0;stack_depth<=0;
            limit<=0;retired_count<=0;generation<=0;operation_tag<=0;rows<=0;cols<=0;scale<=0;key<=0;
            done_fault<=0;done_detail<=0;done_status<=0;done_output_vector<=0;done_residual_vector<=1;done_support_vector<=2;
            done_job<=0;done_tag<=0;done_fmt<=0;trace_pc<=0;trace_word<=0;trace_retire<=0;
            sum_a<=0;sum_b<=0;term_a<=0;term_b<=0;factor_a<=0;factor_b<=0;cert_step<=0;
            for(n=0;n<32;n=n+1)rf[n]<=0;
        end else if(cancel) begin
            state<=IDLE;load_pending<=0;trace_retire<=0;stack_depth<=0;word<=0;
            done_fault<=0;done_detail<=0;done_status<=0;
        end else begin
            trace_retire<=0;rf[0]<=0;
            if(load_pending&&load_status_ready)load_pending<=0;
            case(state)
                IDLE: if(load_begin_valid&&load_begin_ready)begin
                    image_valid<=0;load_status_fault<=0;load_phase<=0;next_load<=0;
                    program_count<=load_begin_program_count;constant_count<=load_begin_constant_count;
                    template_count<=load_begin_template_count;vector_count<=load_begin_vector_count;
                    if(load_begin_revision!=`CSR_PROGRAM_REVISION||!load_begin_verified||load_begin_program_count==0||load_begin_program_count>1024||
                       load_begin_template_count==0||load_begin_template_count>16||load_begin_vector_count==0||load_begin_vector_count>32||
                       load_begin_constant_count>1024)load_fail();else state<=LOAD;
                end else if(start_valid&&start_ready)begin
                    for(n=0;n<32;n=n+1)rf[n]<=0;
                    rows<=start_rows;cols<=start_cols;key<=start_key;generation<=start_generation;scale<=start_scale;
                    done_job<=start_job;done_tag<=start_tag;done_fmt<=start_fmt;operation_tag<=start_tag;
                    limit<=start_instruction_limit;retired_count<=0;pc<=0;stack_depth<=0;
                    done_fault<=0;done_detail<=0;done_status<=0;done_output_vector<=0;
                    done_residual_vector<=vector_count>1 ? 5'd1 : 5'd0;done_support_vector<=vector_count>2 ? 5'd2 : 5'd0;
                    if(start_rows==0||start_rows>128||start_cols==0||start_cols>1024||start_fmt!=1||start_instruction_limit==0)
                        fail(`CSR_PROGRAM_FAULT_MODE,0);else state<=FETCH;
                end
                LOAD: if(load_valid&&load_ready)begin
                    if(load_kind!=load_phase||load_index!=next_load)load_fail();
                    else case(load_phase)
                        0: if(load_last||load_data[127]||load_data[4:0]>`CSR_PROGRAM_KIND_RESCALE)load_fail();else begin
                            program_mem[next_load[9:0]]<=load_data;
                            if(next_load+1==program_count)begin next_load<=0;load_phase<=1;end else next_load<=next_load+1'b1;
                        end
                        1: begin
                            tid=next_load/33;lane=next_load%33;
                            if(load_last||(lane==0 ? load_data[127:96]!=0||load_data[31:11]!=0||load_data[4:3]>`CSR_KERNEL_PROJECT_DESCRIPTOR_KIND||
                                (load_data[4:3]==`CSR_KERNEL_PROJECT_DESCRIPTOR_KIND ? (load_data[95:32]!=0||load_data[31:0]!=`CSR_KERNEL_PROJECT_DESCRIPTOR) : (load_data[4:3]!=1&&load_data[10:5]!=0)) : load_data[127:37]!=0||
                                (template_meta[tid]==0 ? load_data[63:0]!=0 :
                                 (template_meta[tid][4:3]==`CSR_KERNEL_PROJECT_DESCRIPTOR_KIND ? load_data[63:0]!=(lane==1 ? `CSR_KERNEL_PROJECT_DOT_CONTEXT : lane==2 ? `CSR_KERNEL_PROJECT_SCALE_CONTEXT : lane==3 ? `CSR_KERNEL_PROJECT_RANK_CONTEXT : `CSR_KERNEL_PROJECT_PADDING_CONTEXT) :
                                  (template_meta[tid][4:3]==0 ? !(load_data[4:0]==1||load_data[4:0]==2||load_data[4:0]==3||load_data[4:0]==8) : load_data[4:0]!=9)))))load_fail();
                            else begin
                                if(lane==0)template_meta[tid]<=load_data[95:0];else templates[tid][(lane-1)*64 +:64]<=load_data[63:0];
                                if(next_load+1==template_count*33)begin next_load<=0;load_phase<=2;end else next_load<=next_load+1'b1;
                            end
                        end
                        2: if(load_data[127:20]!=0||load_data[19:9]==0||load_data[19:9]>1024||
                              {2'b0,load_data[8:0]}+((load_data[19:9]+11'd31)>>5)>480||
                              load_last!=(next_load+1==vector_count&&constant_count==0))load_fail();else begin
                            vectors[next_load[4:0]]<=load_data[19:0];
                            if(next_load+1==vector_count)begin
                                if(constant_count==0)begin image_valid<=1;load_pending<=1;state<=IDLE;end
                                else begin next_load<=0;load_phase<=3;end
                            end else next_load<=next_load+1'b1;
                        end
                        3: if(load_data[127:64]!=0||load_last!=(next_load+1==constant_count))load_fail();else begin
                            constants[next_load[9:0]]<=load_data[63:0];
                            if(load_last)begin image_valid<=1;load_pending<=1;state<=IDLE;end else next_load<=next_load+1'b1;
                        end
                        default:load_fail();
                    endcase
                end
                FETCH:begin word<=program_mem[pc];state<=EXEC;end
                EXEC:if(retired_count>=limit)fail(`CSR_PROGRAM_FAULT_WATCHDOG,0);
                    else if(malformed)fail(`CSR_PROGRAM_FAULT_PROGRAM,0);
                    else case(f_kind)
                        0:retire({1'b0,pc}+11'd1);
                        1:if(f_kernel>`CSR_PROGRAM_KERNEL_FACTOR_ENERGY_TAP||i_reserved!=0||i_template>=template_count||f_a_v>=vector_count||f_b_v>=vector_count||f_dst_v>=vector_count||
                             i_support_v>=vector_count||i_aux_v>=vector_count||length_value==0||length_value>1024||columns_value==0||columns_value>1024||
                             (f_length_mode==3&&i_length>31)||(!rounded_affine_command&&(
                              rf[f_shift_s]<0||rf[f_shift_s]>63||rf[i_k_s]<0||rf[i_k_s]>1024||
                              rf[i_support_length_s]<0||rf[i_support_length_s]>1024||rf[i_aux_length_s]<0||rf[i_aux_length_s]>1024||
                              rf[i_index_s]<0||rf[i_index_s]>(f_kernel>=`CSR_PROGRAM_KERNEL_SLICE ? 64'sd1024 : 64'sd1023)))||f_target>1||
                             (range_command&&
                              (({1'b0,rf[i_index_s][10:0]}+{1'b0,rf[i_aux_length_s][10:0]})>{1'b0,length_value[10:0]}||
                               i_flags!=0||rf[i_k_s]!=0||rf[i_support_length_s]!=0||(!scalar_insert_command&&vectors[i_support_v][8:0]!=0)))||
                             (factor_command&&(factor_extend_command ? factor_extend_bad : factor_legacy_bad))||
                             (scalar_insert_command&&scalar_insert_bad)||
                             (range_template_command&&range_template_bad)||
                             (factor_range_template_command&&factor_range_template_bad)||
                             (factor_energy_tap_command&&factor_energy_tap_bad)||
                              (rounded_affine_command&&rounded_affine_bad)||
                             (!factor_project_command&&kernel_descriptor[4:3]==`CSR_KERNEL_PROJECT_DESCRIPTOR_KIND)||
                             (factor_panel_command&&(!i_dense||!panel_context_valid||columns_value==0||columns_value>96||length_value>128||
                              i_transpose||i_r4||i_store_mode!=0||i_flags!=0||rf[i_k_s]!=0||rf[f_shift_s]!=0||f_target!=0||
                              i_support_v!=0||i_aux_v!=0||f_b_s!=0||f_dst_s!=0||f_flag_s!=0||
                              rf[i_aux_length_s]>=rows||panel_row_end>{4'b0,rows}||rf[i_index_s]>=columns_value||panel_operand_bad))||
                             (scalar_template_command&&(length_value!=1||template_need_a!=0||template_need_b!=0||
                              kernel_descriptor[31:3]!=0||!scalar_lane_context[5]||
                              (scalar_lane_context[4:0]!=1&&scalar_lane_context[4:0]!=2&&scalar_lane_context[4:0]!=3&&scalar_lane_context[4:0]!=8)||
                              i_dense||i_transpose||i_r4||i_store_mode!=0||i_flags!=0||rf[i_k_s]!=0||
                              rf[i_support_length_s]!=0||rf[i_aux_length_s]!=0||rf[i_index_s]!=0||rf[f_shift_s]!=0))||
                             (kernel_scalar_bind_a!=0&&!fits_state(rf[f_a_s]))||(kernel_scalar_bind_b!=0&&!fits_state(rf[f_b_s]))||
                             ((f_kernel==2||f_kernel==4||factor_project_command)&&!fits_state(rf[f_a_s]))||
                             vectors[f_a_v][19:9]<source_need||vectors[f_dst_v][19:9]<output_need||
                             (f_kernel==0&&vectors[f_b_v][19:9]<template_need_b)||
                              (rounded_affine_command&&!rounded_affine_scalar_y&&vectors[f_b_v][19:9]<length_value)||
                              (rounded_affine_command&&vectors[i_aux_v][19:9]<length_value)||
                             (!factor_command&&!factor_panel_command&&!factor_range_template_command&&!factor_energy_tap_command&&!rounded_affine_command&&vectors[i_support_v][19:9]<rf[i_support_length_s])||
                             (!factor_command&&!factor_panel_command&&!factor_range_template_command&&!factor_energy_tap_command&&f_kernel!=`CSR_PROGRAM_KERNEL_SLICE&&!range_template_command&&!rounded_affine_command&&vectors[i_aux_v][19:9]<rf[i_aux_length_s])||
                             (f_dst_s!=0&&f_dst_s==f_flag_s))
                            fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else state<=KREQ;
                        2:if(f_immediate!=0&&f_immediate!=246)fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else state<=SREQ;
                        3:state<=SREQ;
                        4:begin rf[f_dst_s]<=$signed(f_immediate);retire({1'b0,pc}+11'd1);end
                        5:begin rf[f_dst_s]<=rf[f_a_s];retire({1'b0,pc}+11'd1);end
                        6:if(rf[f_a_s]==64'sh8000000000000000)fail(`CSR_PROGRAM_FAULT_NUMERIC,0);else begin rf[f_dst_s]<=-rf[f_a_s];retire({1'b0,pc}+11'd1);end
                        7:if(rf[f_a_s]<=0||!fits_state(rf[f_a_s])||f_shift_s==0||f_shift_s==f_dst_s)fail(`CSR_PROGRAM_FAULT_NUMERIC,0);else begin
                            e=0;for(n=0;n<27;n=n+1)if(rf[f_a_s][n])e=n+1;
                            rf[f_dst_s]<=64'd1<<e;rf[f_shift_s]<=e;retire({1'b0,pc}+11'd1);
                        end
                        8:retire(rf[f_a_s]==0?{1'b0,f_target}:{1'b0,pc}+11'd1);
                        9:retire(rf[f_a_s]!=0?{1'b0,f_target}:{1'b0,pc}+11'd1);
                        10:retire(f_target);
                        11:if(f_immediate[63:20]!=0||f_immediate[9:0]>=constant_count||f_immediate[19:10]>=constant_count||rf[f_a_s]<0||rf[f_b_s]<0)
                            fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else begin
                            sum_a<=0;sum_b<=0;term_a<={64'b0,rf[f_a_s]};term_b<={64'b0,rf[f_b_s]};
                            factor_a<=constants[f_immediate[9:0]];factor_b<=constants[f_immediate[19:10]];cert_step<=0;state<=CERTIFY;
                        end
                        12:if(rf[f_a_s]==64'sh7fffffffffffffff)fail(`CSR_PROGRAM_FAULT_NUMERIC,0);else begin rf[f_dst_s]<=rf[f_a_s]+1'b1;retire({1'b0,pc}+11'd1);end
                        13:retire(rf[f_a_s]>=rf[f_b_s]?{1'b0,f_target}:{1'b0,pc}+11'd1);
                        14:fail(`CSR_PROGRAM_FAULT_PROGRAM,0);
                        15:begin done_status<=f_immediate[7:0];trace_pc<=pc;trace_word<=word;trace_retire<=1;state<=DONE;end
                        16:if(stack_depth==4||{1'b0,pc}+1>=program_count)fail(`CSR_PROGRAM_FAULT_STACK,0);else begin
                            return_stack[stack_depth]<=pc+1'b1;stack_depth<=stack_depth+1'b1;retire(f_target);
                        end
                        17:if(stack_depth==0)fail(`CSR_PROGRAM_FAULT_STACK,0);else begin stack_depth<=stack_depth-1'b1;retire(return_stack[stack_depth-1'b1]);end
                        18:if(rf[f_a_s]<0||constant_address>={54'b0,constant_count})fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else begin rf[f_dst_s]<=constants[constant_address[9:0]];retire({1'b0,pc}+11'd1);end
                        19:if(f_immediate>5)fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else retire(compare(rf[f_a_s],rf[f_b_s],f_immediate[2:0])?{1'b0,f_target}:{1'b0,pc}+11'd1);
                        20:if(f_immediate[63:8]!=0||f_dst_v>=vector_count||f_a_v>=vector_count||f_b_v>=vector_count)fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else begin
                            done_output_vector<=f_dst_v;done_residual_vector<=f_a_v;done_support_vector<=f_b_v;done_status<=f_immediate[7:0];trace_pc<=pc;trace_word<=word;trace_retire<=1;state<=DONE;
                        end
                        21:if(f_a_v>=vector_count||rf[f_a_s]<=0||rf[f_a_s]>96||vectors[f_a_v][19:9]<rf[f_a_s])fail(`CSR_PROGRAM_FAULT_PROGRAM,0);else state<=BREQ;
                        22,23:if(rf_sum[64]!=rf_sum[63])fail(`CSR_PROGRAM_FAULT_NUMERIC,0);
                            else begin rf[f_dst_s]<=rf_sum[63:0];retire({1'b0,pc}+11'd1);end
                        24:state<=SREQ;
                        default:fail(`CSR_PROGRAM_FAULT_PROGRAM,0);
                    endcase
                KREQ:if(kernel_ready)state<=KWAIT;
                KWAIT:if(kernel_rsp_valid)begin
                    if(kernel_rsp_job!=done_job||kernel_rsp_tag!=operation_tag||kernel_rsp_fmt!=done_fmt)fail(`CSR_PROGRAM_FAULT_IDENTITY,0);
                    else if(kernel_rsp_fault!=0)fail(`CSR_PROGRAM_FAULT_KERNEL,kernel_rsp_detail);
                    else if(factor_energy_tap_command&&kernel_rsp_count>11'd1)fail(`CSR_PROGRAM_FAULT_IDENTITY,0);
                    else begin
                        if(f_dst_s!=0)rf[f_dst_s]<=$signed(kernel_rsp_data);
                        if(f_flag_s!=0)rf[f_flag_s]<=f_target[0]?{53'b0,kernel_rsp_count}:{63'b0,kernel_rsp_nonzero};
                        operation_tag<=operation_tag+1'b1;retire({1'b0,pc}+11'd1);
                    end
                end
                SREQ:if(scalar_ready)state<=SWAIT;
                SWAIT:if(scalar_rsp_valid)begin
                    if(scalar_rsp_job!=done_job||scalar_rsp_tag!=operation_tag||scalar_rsp_fmt!=done_fmt)fail(`CSR_PROGRAM_FAULT_IDENTITY,0);
                    else if(scalar_rsp_fault!=0)fail(`CSR_PROGRAM_FAULT_SCALAR,{1'b0,scalar_rsp_fault});
                    else begin rf[f_dst_s]<={{37{scalar_rsp_data[26]}},scalar_rsp_data};operation_tag<=operation_tag+1'b1;retire({1'b0,pc}+11'd1);end
                end
                BREQ:if(build_ready)state<=BWAIT;
                BWAIT:if(build_rsp_valid)begin
                    if(build_rsp_job!=done_job||build_rsp_tag!=operation_tag||build_rsp_fmt!=done_fmt)fail(`CSR_PROGRAM_FAULT_IDENTITY,0);
                    else if(build_rsp_fault!=0)fail(`CSR_PROGRAM_FAULT_BUILD,build_rsp_fault);
                    else begin operation_tag<=operation_tag+1'b1;retire({1'b0,pc}+11'd1);end
                end
                CERTIFY:begin
                    sum_a<=next_sum_a;sum_b<=next_sum_b;term_a<=term_a<<1;term_b<=term_b<<1;factor_a<=factor_a>>1;factor_b<=factor_b>>1;
                    if(cert_step==63)begin rf[f_dst_s]<={63'b0,next_sum_a<=next_sum_b};retire({1'b0,pc}+11'd1);end else cert_step<=cert_step+1'b1;
                end
                DONE:if(done_ready)state<=IDLE;
                default:fail(`CSR_PROGRAM_FAULT_PROGRAM,0);
            endcase
        end
    end
endmodule
