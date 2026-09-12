`include "stream_interface.vh"
`include "kernel_interface.vh"
module stream_kernel #(parameter RESIDENT_WRITEBACK=1, parameter GEMV_GROUP_PREFETCH=1) (
    input wire clk, rst, cancel,
    input wire host_enable,
    input wire req_valid, output wire req_ready,
    input wire [5:0] req_op,
    input wire [2047:0] req_contexts,
    input wire [31:0] req_descriptor,
    input wire [8:0] req_src_a,
    input wire [8:0] req_src_b,
    input wire [8:0] req_dst,
    input wire [10:0] req_length,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols,
    input wire req_matrix_dense,
    input wire req_trans,
    input wire req_r4,
    input wire [26:0] req_scalar_a,
    input wire [26:0] req_scalar_b,
    input wire [31:0] req_scalar_bind_a,
    input wire [31:0] req_scalar_bind_b,
    input wire [5:0] req_shift,
    input wire [10:0] req_k,
    input wire [17:0] req_scale,
    input wire [127:0] req_key,
    input wire [31:0] req_generation,
    input wire [15:0] req_job,
    input wire [15:0] req_tag,
    input wire [7:0] req_fmt,
    input wire [7:0] req_frame_count,
    input wire [31:0] req_tail_mask,
    input wire [1:0] req_store_mode,
    input wire [8:0] req_support_base,
    input wire [8:0] req_aux_base,
    input wire [10:0] req_support_length,
    input wire [10:0] req_aux_length,
    input wire [10:0] req_index,
    input wire [7:0] req_flags,
    output wire rsp_valid, input wire rsp_ready,
    output wire [3:0] rsp_fault,
    output wire [3:0] rsp_detail,
    output wire [63:0] rsp_data,
    output wire rsp_nonzero,
    output wire [10:0] rsp_count,
    output wire [15:0] rsp_job,
    output wire [15:0] rsp_tag,
    output wire [7:0] rsp_fmt,
    input wire host_valid, output wire host_ready,
    input wire host_write, input wire [8:0] host_block,
    input wire [31:0] host_mask, input wire [863:0] host_data,
    input wire [15:0] host_tag,
    output reg host_rsp_valid, input wire host_rsp_ready,
    output reg host_rsp_write, output reg [863:0] host_rsp_data,
    output reg [31:0] host_rsp_mask, output reg [15:0] host_rsp_tag,
    output reg [3:0] host_rsp_fault,
    input wire matrix_valid,
    input wire [7:0] matrix_rows,
    input wire [10:0] matrix_cols,
    input wire [127:0] matrix_key,
    input wire [31:0] matrix_generation,
    input wire [15:0] matrix_job,
    input wire [7:0] matrix_fmt,
    output wire mat_valid,input wire mat_ready,
    output wire mat_dense,
    output reg [31:0] mat_mask,
    output reg [287:0] mat_addr,
    output wire [127:0] mat_key,
    output wire [31:0] mat_generation,
    output wire [15:0] mem_job,mem_tag,
    output wire [7:0] mem_fmt,
    input wire mat_rsp_valid,output wire mat_rsp_ready,
    input wire [575:0] mat_rsp_data,
    input wire [255:0] mat_rsp_masks,
    input wire [31:0] mat_rsp_mask,mat_rsp_generation,
    input wire [15:0] mat_rsp_job,mat_rsp_tag,
    input wire [7:0] mat_rsp_fmt,
    input wire [3:0] mat_rsp_fault,
    output wire operator_cancel,
    output wire matrix_select,
    output wire busy,
    output wire [4:0] events
    );
    localparam [5:0] IDLE=0,CHECK=1,CONFIG=2,CONFIG_WAIT=3,LAUNCH=4,RUN=5,
    INVALIDATE=7,COPY_READ=8,COPY_WAIT=9,COPY_WRITE=10,PUBLISH=11,FAIL=12,RESPONSE=13,LAST_WRITE=14,GEMV_REQ=15,GEMV_WAIT=16,REMAP=17,GEMV_WRITE=18,SUPPORT_START=19,SUPPORT_WAIT=20,SUPPORT_VALIDATE=21,AFFINE_WRITE=22,AFFINE_WAIT=23;
    reg [10:0] support_length,aux_length,k,index_value,result_count,result_length;
    reg [8:0] support_base,aux_base;
    reg [7:0] flags;
    reg [5:0] allocated_count;
    wire factor_active=(operation>=`CSR_KERNEL_OP_FACTOR_INIT&&operation<=`CSR_KERNEL_OP_FACTOR_WRITE)||operation==`CSR_KERNEL_OP_FACTOR_EXTEND;
    wire panel_active=operation==`CSR_KERNEL_OP_FACTOR_MATVEC||operation==`CSR_KERNEL_OP_FACTOR_RANK1||operation==`CSR_KERNEL_OP_FACTOR_PROJECT_UPDATE||operation==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE||operation==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP;
    wire panel_matvec=operation==`CSR_KERNEL_OP_FACTOR_MATVEC;
    wire factor_range_template=operation==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE;
    wire factor_energy_tap=operation==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP;
    wire adjunct=(operation>=`CSR_KERNEL_OP_TOPK&&operation<=`CSR_KERNEL_OP_SCALAR_INSERT)||factor_range_template||factor_energy_tap;
    wire rounded_affine=operation==`CSR_KERNEL_OP_ROUNDED_AFFINE;
    wire [10:0] requested_extent=(req_op==`CSR_KERNEL_OP_FACTOR_INIT||req_op==`CSR_KERNEL_OP_FACTOR_WRITE||req_op==`CSR_KERNEL_OP_FACTOR_RANK1||req_op==`CSR_KERNEL_OP_FACTOR_EXTEND||req_op==`CSR_KERNEL_OP_FACTOR_PROJECT_UPDATE) ? 11'd0 :
        req_op==`CSR_KERNEL_OP_FACTOR_MATVEC ? req_support_length-req_index : req_op==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE ? (req_flags[1] ? 11'd1 : req_length) : req_op==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP ? req_length : (req_op==`CSR_KERNEL_OP_TOPK||req_op==`CSR_KERNEL_OP_UNION) ? req_k :
        req_op==`CSR_KERNEL_OP_SLICE ? req_aux_length : req_op==`CSR_KERNEL_OP_GATHER ? req_support_length : req_op==`CSR_KERNEL_OP_PICK ? 11'd0 : req_length;
    wire [5:0] clear_count=adjunct ? allocated_count : output_count;
    wire support_ready,support_valid;
    wire support_vec_valid,support_vec_ready,support_vec_rsp_ready;
    wire [8:0] support_vec_block;
    wire [31:0] support_vec_mask;
    wire [15:0] support_vec_tag;
    reg [3:0] support_vec_fault;
    wire candidate_valid,candidate_ready;
    wire [4:0] candidate_block;
    wire [31:0] candidate_mask;
    wire [863:0] candidate_data;
    wire [3:0] support_fault,support_detail;
    wire [10:0] support_count,support_output_length;
    wire [63:0] support_data;
    wire support_nonzero;
    wire [15:0] support_job,support_tag;
    wire [7:0] support_fmt;
    wire selection_support_ready,factor_support_ready,panel_support_ready;
    assign support_ready=panel_active ? panel_support_ready : factor_active ? factor_support_ready : selection_support_ready;
    wire selection_support_valid,factor_support_valid,panel_support_valid;
    assign support_valid=panel_active ? panel_support_valid : factor_active ? factor_support_valid : selection_support_valid;
    wire selection_support_vec_valid,factor_support_vec_valid,panel_support_vec_valid;
    assign support_vec_valid=panel_active ? panel_support_vec_valid : factor_active ? factor_support_vec_valid : selection_support_vec_valid;
    wire selection_support_vec_rsp_ready,factor_support_vec_rsp_ready,panel_support_vec_rsp_ready;
    assign support_vec_rsp_ready=panel_active ? panel_support_vec_rsp_ready : factor_active ? factor_support_vec_rsp_ready : selection_support_vec_rsp_ready;
    wire [8:0] selection_support_vec_block,factor_support_vec_block,panel_support_vec_block;
    assign support_vec_block=panel_active ? panel_support_vec_block : factor_active ? factor_support_vec_block : selection_support_vec_block;
    wire [31:0] selection_support_vec_mask,factor_support_vec_mask,panel_support_vec_mask;
    assign support_vec_mask=panel_active ? panel_support_vec_mask : factor_active ? factor_support_vec_mask : selection_support_vec_mask;
    wire [15:0] selection_support_vec_tag,factor_support_vec_tag,panel_support_vec_tag;
    assign support_vec_tag=panel_active ? panel_support_vec_tag : factor_active ? factor_support_vec_tag : selection_support_vec_tag;
    wire selection_candidate_valid,factor_candidate_valid,panel_candidate_valid;
    assign candidate_valid=panel_active ? panel_candidate_valid : factor_active ? factor_candidate_valid : selection_candidate_valid;
    wire [4:0] selection_candidate_block,factor_candidate_block,panel_candidate_block;
    assign candidate_block=panel_active ? panel_candidate_block : factor_active ? factor_candidate_block : selection_candidate_block;
    wire [31:0] selection_candidate_mask,factor_candidate_mask,panel_candidate_mask;
    assign candidate_mask=panel_active ? panel_candidate_mask : factor_active ? factor_candidate_mask : selection_candidate_mask;
    wire [863:0] selection_candidate_data,factor_candidate_data,panel_candidate_data;
    assign candidate_data=panel_active ? panel_candidate_data : factor_active ? factor_candidate_data : selection_candidate_data;
    wire [3:0] selection_support_fault,factor_support_fault,panel_support_fault;
    assign support_fault=panel_active ? panel_support_fault : factor_active ? factor_support_fault : selection_support_fault;
    wire [3:0] selection_support_detail,factor_support_detail,panel_support_detail;
    assign support_detail=panel_active ? panel_support_detail : factor_active ? factor_support_detail : selection_support_detail;
    wire [10:0] selection_support_count,factor_support_count,panel_support_count;
    assign support_count=panel_active ? panel_support_count : factor_active ? factor_support_count : selection_support_count;
    wire [10:0] selection_support_output_length,factor_support_output_length,panel_support_output_length;
    assign support_output_length=panel_active ? panel_support_output_length : factor_active ? factor_support_output_length : selection_support_output_length;
    wire [63:0] selection_support_data,factor_support_data,panel_support_data;
    assign support_data=panel_active ? panel_support_data : factor_active ? factor_support_data : selection_support_data;
    wire selection_support_nonzero,factor_support_nonzero,panel_support_nonzero;
    assign support_nonzero=panel_active ? panel_support_nonzero : factor_active ? factor_support_nonzero : selection_support_nonzero;
    wire [15:0] selection_support_job,factor_support_job,panel_support_job;
    assign support_job=panel_active ? panel_support_job : factor_active ? factor_support_job : selection_support_job;
    wire [15:0] selection_support_tag,factor_support_tag,panel_support_tag;
    assign support_tag=panel_active ? panel_support_tag : factor_active ? factor_support_tag : selection_support_tag;
    wire [7:0] selection_support_fmt,factor_support_fmt,panel_support_fmt;
    assign support_fmt=panel_active ? panel_support_fmt : factor_active ? factor_support_fmt : selection_support_fmt;
    wire feeder_mat_valid,factor_mat_valid;
    assign mat_valid=factor_active ? factor_mat_valid : feeder_mat_valid;
    wire feeder_mat_dense,factor_mat_dense;
    assign mat_dense=factor_active ? factor_mat_dense : feeder_mat_dense;
    wire [31:0] feeder_mat_mask,factor_mat_mask;
    assign mat_mask=factor_active ? factor_mat_mask : feeder_mat_mask;
    wire [287:0] feeder_mat_addr,factor_mat_addr;
    assign mat_addr=factor_active ? factor_mat_addr : feeder_mat_addr;
    wire [127:0] feeder_mat_key,factor_mat_key;
    assign mat_key=factor_active ? factor_mat_key : feeder_mat_key;
    wire [31:0] feeder_mat_generation,factor_mat_generation;
    assign mat_generation=factor_active ? factor_mat_generation : feeder_mat_generation;
    wire [15:0] feeder_mem_job,factor_mem_job;
    assign mem_job=factor_active ? factor_mem_job : feeder_mem_job;
    wire [15:0] feeder_mem_tag,factor_mem_tag;
    assign mem_tag=factor_active ? factor_mem_tag : feeder_mem_tag;
    wire [7:0] feeder_mem_fmt,factor_mem_fmt;
    assign mem_fmt=factor_active ? factor_mem_fmt : feeder_mem_fmt;
    wire feeder_mat_rsp_ready,factor_mat_rsp_ready;
    assign mat_rsp_ready=factor_active ? factor_mat_rsp_ready : feeder_mat_rsp_ready;
    wire candidate_bad=!writes_vector||candidate_block>=allocated_count;
    wire [31:0] support_expected_mask=(check_frame+1==count&&result_length[4:0]!=0) ?
        (32'hffffffff>>(32-result_length[4:0])) : 32'hffffffff;
    assign candidate_ready=state==SUPPORT_WAIT&&(candidate_bad||mem_ready);
    assign support_vec_ready=state==SUPPORT_WAIT&&!candidate_valid&&mem_ready;
    reg dense,trans,rfour;
    reg [7:0] rows;
    // Active compute coordinates stay fixed through terminal reduction and
    // scratch write.  Issue coordinates may run ahead into the four-slot
    // feeder, but never feed a future group into the active fabric command.
    reg [10:0] cols,gemv_out,issue_out,issue_red;
    reg [2:0] issue_step, delivered_step;
    reg [10:0] delivered_red;
    reg [13:0] delivered_frame;
    reg issue_done,delivery_group_done;
    wire [13:0] feeder_frame;
    wire delivered_last=rfour ? (delivered_red+11'd32>=reductions &&
        ({8'b0,delivered_step}+11'd1==((reductions-delivered_red)<8 ? reductions-delivered_red : 11'd8))) : delivered_red+1==reductions;
    reg [17:0] scale;
    reg [127:0] key;
    reg [31:0] generation;
    reg [31:0] gemv_write_mask;
    wire gemv=operation==1;
    wire writes_vector=(operation<=`CSR_KERNEL_OP_FACTOR_WRITE||panel_matvec||operation==`CSR_KERNEL_OP_SCALAR_INSERT||operation==`CSR_KERNEL_OP_RANGE_TEMPLATE||factor_range_template||factor_energy_tap||rounded_affine)&&operation!=`CSR_KERNEL_OP_PICK&&
        operation!=`CSR_KERNEL_OP_FACTOR_INIT&&operation!=`CSR_KERNEL_OP_FACTOR_WRITE&&kind!=2;
    wire [10:0] outputs=trans ? cols : {3'b0,rows};
    wire [10:0] reductions=trans ? {3'b0,rows} : cols;
    wire [5:0] source_blocks=(reductions+11'd31)>>5;
    wire [10:0] gemv_group_width=rfour ? 11'd8 : 11'd32;
    wire issue_frame_last=rfour ? (issue_red+11'd32>=reductions &&
        ({8'b0,issue_step}+11'd1==((reductions-issue_red)<8 ? reductions-issue_red : 11'd8))) :
        issue_red+1==reductions;
    wire feeder_issue_valid=state==GEMV_WAIT&&!issue_done&&
        (GEMV_GROUP_PREFETCH||issue_out==gemv_out);
    wire feeder_req_ready,feeder_rsp_valid,feeder_rsp_ready;
    wire [863:0] feeder_mat,feeder_vec;
    wire [31:0] feeder_mask;
    wire [3:0] feeder_fault;
    wire [15:0] feeder_job,feeder_tag;
    wire [7:0] feeder_fmt;
    wire feeder_last;
    wire vec_valid,vec_ready,vec_rsp_ready;
    wire [8:0] vec_block;
    wire [31:0] vec_mask;
    wire [15:0] vec_tag;
    wire [3:0] vec_fault=(vec_block>=480 || (vec_block<480&&(valid_masks[vec_block]&vec_mask)!=vec_mask)) ? 4'd7 : 4'd0;
    wire feeder_bad=feeder_fault!=0||feeder_job!=job||feeder_tag!=tag||feeder_fmt!=fmt||feeder_last!=delivered_last||feeder_frame!=delivered_frame;
    wire gemv_state=state==GEMV_REQ||state==GEMV_WAIT;
    // A held future-group response must neither enter the fabric nor be
    // checked against the retiring group until its LAUNCH handoff.
    wire gemv_input=state==GEMV_WAIT&&!delivery_group_done&&feeder_rsp_valid&&!feeder_bad;
    assign operator_cancel=cancel||state==FAIL;
    assign matrix_select=dense;
    assign vec_ready=gemv_state&&mem_ready;
    // Hold every prefetched future-group response until LAUNCH resets the
    // active group.  It must not be compared against the retiring group.
    assign feeder_rsp_ready=state==GEMV_WAIT&&!delivery_group_done&&(feeder_bad||in_ready);
    reg [5:0] state;
    reg [5:0] operation,shift;
    reg [1:0] store_mode;
    reg [10:0] length;
    reg [26:0] scalar_a,scalar_b;
    reg [31:0] bind_a,bind_b;
    reg nonzero;
    reg [31:0] soft_zero;
    reg soft_pending;
    reg command_bad;
    reg [863:0] fabric_a,fabric_b,store_data;
    reg store_bad;
    reg signed [64:0] stored_value,stored_mag;
    integer narrow_lane;
    wire scalar_template=operation==`CSR_KERNEL_OP_SCALAR_TEMPLATE;
    wire range_template=operation==`CSR_KERNEL_OP_RANGE_TEMPLATE;
    wire normalize=operation==2;
    wire store=operation==3;
    wire thresholding=operation==4;
    reg host_pending;
    reg [31:0] valid_masks[0:479];
    wire active=!rst&&!cancel;
    reg [8:0] src_a,src_b,dst;
    reg [7:0] count,fmt;
    reg [15:0] job,tag;
    reg [31:0] descriptor,tail_mask,needs_a,needs_b,needs_c;
    reg [2047:0] contexts;
    reg [5:0] check_frame,input_frame,output_frame,copy_frame;
    reg [1:0] read_phase;
    reg a_valid,b_valid,c_valid;
    reg affine_half,affine_input_done,affine_out_half;
    reg range_inflight;
    reg [863:0] a_buffer,b_buffer,copy_buffer;
    // Public validity stays in the 480 logical-address domain. The address
    // map and 32 handles only choose physical vector-RAM locations.
    reg [31:0] scratch_masks[0:31];
    (* ram_style = "distributed" *) reg [8:0] public_map[0:479];
    (* ram_style = "distributed" *) reg public_map_valid[0:479];
    reg [8:0] scratch_handle[0:31];
    reg [5:0] remap_frame;
    reg mem_scratch;
    reg [4:0] mem_scratch_index;
    reg [3:0] fault,detail;
    reg [63:0] scalar;
    wire [1:0] kind=normalize ? 2'd0 : descriptor[4:3];
    wire affine_scalar_y=bind_b==32'h0000ffff;
    wire [31:0] input_mask=input_frame+1==count ? tail_mask : 32'hffffffff;
    wire [31:0] fabric_input_mask=rounded_affine ? {affine_half_mask,affine_half_mask} : (gemv ? feeder_mask : input_mask);
    wire [31:0] check_mask=gemv ? ((check_frame+1==source_blocks&&reductions[4:0]!=0) ? (32'hffffffff>>(32-reductions[4:0])) : 32'hffffffff) : check_frame+1==count ? tail_mask : 32'hffffffff;
    wire [31:0] final_mask=count==1 ? tail_mask : 32'hffffffff;
    wire [5:0] output_count=kind==0 ? count[5:0] : 6'd1;
    // A non-incrementing vector destination deliberately writes one logical
    // block repeatedly. Keep its qualified copy path until it has a direct
    // resident remap contract of its own.
    wire resident_remap=RESIDENT_WRITEBACK&&!(kind==0&&!descriptor[2]&&output_count>1);
    integer i,j,ca,cb,cc,cd;
    reg [8:0] mem_block,mem_logical_block;
    wire [8:0] remap_logical=dst+(descriptor[2]&&kind==0 ? remap_frame : 0);
    // REMAP has no vector-RAM transaction, so one address selector shares the
    // distributed map read between final memory arbitration and ownership swaps.
    wire [8:0] map_lookup_logical=state==REMAP ? remap_logical : mem_logical_block;
    wire [8:0] map_lookup_physical=(map_lookup_logical<480&&public_map_valid[map_lookup_logical]) ?
        public_map[map_lookup_logical] : map_lookup_logical;
    reg [31:0] selected_a,selected_b;
    reg source_bad,bounds_bad,range_source_bad;
    integer range_check_lane,range_check_position,range_check_address;
    reg [63:0] context_word;
    wire range_start_ready,range_provider_valid,range_provider_rsp_ready,range_done_valid;
    wire [8:0] range_provider_address;
    wire [31:0] range_provider_mask;
    wire [15:0] range_provider_tag;
    wire [1:0] range_done_fault;
    wire [863:0] range_a_data,range_b_data;
    wire range_start_valid=state==RUN&&range_template&&!range_inflight&&!a_valid&&!b_valid&&input_frame<count;
    wire range_done_ready=state==RUN&&range_template&&range_inflight&&!a_valid&&!b_valid;
    reg [8:0] range_issued_address;
    reg [31:0] range_issued_mask;
    wire [3:0] range_provider_fault=(range_issued_address>=480||
        (range_issued_address<480&&(valid_masks[range_issued_address]&range_issued_mask)!=range_issued_mask)) ?
        `CSR_KERNEL_FAULT_OPERAND : `CSR_KERNEL_FAULT_NONE;
    wire mem_ready,mem_rsp_valid;
    reg mem_valid,mem_write,mem_rsp_ready;
    reg [31:0] mem_mask;
    reg [863:0] mem_data;
    reg [15:0] pool_tag;
    wire [863:0] mem_rsp_data;
    wire [31:0] mem_rsp_mask;
    wire [15:0] mem_rsp_tag;
    wire cfg_ready,cfg_loaded,fabric_cmd_ready,in_ready,out_valid,out_last,fabric_done;
    wire affine_terminal_bad=rounded_affine&&fabric_done&&
        (fabric_fault!=0||fabric_job!=job||fabric_tag!=tag||fabric_fmt!=fmt);
    wire [3:0] cfg_fault,fabric_fault;
    wire panel_cfg_valid,panel_cmd_valid,panel_in_valid,panel_out_ready,panel_done_ready;
    wire [2047:0] panel_cfg_contexts;
    wire [15:0] panel_cmd_job,panel_cmd_tag;
    wire [7:0] panel_cmd_fmt;
    wire [1:0] panel_cmd_terminal,panel_cmd_flow;
    wire [5:0] panel_cmd_shift;
    wire [31:0] panel_cmd_terminal_mask,panel_in_mask;
    wire [863:0] panel_in_a,panel_in_b;
    wire panel_in_last;
    wire panel_req_valid,panel_req_ready,panel_req_write,panel_invalidate;
    wire [31:0] panel_req_mask,panel_rsp_mask,panel_rsp_generation;
    wire [287:0] panel_req_addr;
    wire [863:0] panel_req_data,panel_rsp_data;
    wire [7:0] panel_req_rows,panel_req_fmt,panel_rsp_fmt;
    wire [10:0] panel_req_cols;
    wire [127:0] panel_req_key;
    wire [31:0] panel_req_generation;
    wire [15:0] panel_req_job,panel_req_tag,panel_rsp_job,panel_rsp_tag;
    wire panel_rsp_valid,panel_rsp_ready,panel_rsp_write;
    wire [3:0] panel_rsp_fault;
    wire [3:0] terminal_error;
    wire [2047:0] terminal_acc;
    wire [1:0] terminal_mode=gemv ? (rfour ? 2'd1 : 2'd3) :
        normalize||kind==1 ? 2'd3 : kind==2 ? 2'd2 : 2'd0;
    reg [31:0] terminal_mask;
    integer terminal_lane;
    always @* begin
        terminal_mask=normalize ? input_mask : final_mask;
        if(gemv) begin
            terminal_mask=0;
            for(terminal_lane=0;terminal_lane<32;terminal_lane=terminal_lane+1)
                if((!rfour||terminal_lane%4==0)&&
                    gemv_out+(rfour ? terminal_lane/4 : terminal_lane)<outputs)
                    terminal_mask[terminal_lane]=1;
        end
    end
    wire [863:0] out_data;
    wire [2047:0] out_acc;
    wire [31:0] out_mask;
    wire [127:0] out_faults;
    wire [15:0] fabric_job,fabric_tag;
    wire [7:0] fabric_fmt;
    // Template contexts may consume either source, neither source, or the
    // same vector block twice.  Keep the validation masks unchanged, but do
    // not issue RAM traffic for a statically unused operand.
    wire [8:0] read_a=src_a+(descriptor[0] ? input_frame : 0);
    wire [8:0] read_b=src_b+(descriptor[1] ? input_frame : 0);
    wire [8:0] read_c=aux_base+input_frame;
    // Ordinary templates may reuse an aliased A/B response. Affine keeps each
    // source tagged separately so C can share any public block safely.
    wire source_alias=!rounded_affine&&needs_a!=0&&needs_b!=0&&read_a==read_b;
    wire issue_a=needs_a!=0&&read_phase==0;
    wire issue_b=needs_b!=0&&((needs_a==0&&read_phase==0)||(needs_a!=0&&!source_alias&&read_phase==1));
    wire [1:0] affine_c_phase=(needs_a!=0 ? 1 : 0)+(needs_b!=0 ? 1 : 0);
    wire issue_c=rounded_affine&&needs_c!=0&&read_phase==affine_c_phase;
    wire [1:0] read_limit=(needs_a!=0 ? 1 : 0)+(needs_b!=0&&!source_alias ? 1 : 0)+(rounded_affine&&needs_c!=0 ? 1 : 0);
    wire issue_source=issue_a||issue_b||issue_c;
    wire issue_b_tag=issue_b&&!source_alias;
    wire [1:0] issue_kind=issue_a ? 2'd0 : issue_b ? 2'd1 : 2'd2;
    wire [31:0] issue_mask=(rounded_affine ? (issue_a ? needs_a : issue_b ? needs_b : needs_c) : (source_alias ? (needs_a|needs_b) : (issue_a ? needs_a : needs_b)))&input_mask;
    wire [8:0] issue_block=issue_a ? read_a : issue_b ? read_b : read_c;
    wire [15:0] affine_half_mask=affine_half ? input_mask[31:16] : input_mask[15:0];
    wire affine_last_input=input_frame+1==count&&(affine_half||input_mask[31:16]==0);
    wire input_valid=gemv ? gemv_input : rounded_affine ? (state==RUN&&a_valid&&b_valid&&c_valid&&input_frame<count&&!affine_input_done) : state==RUN&&a_valid&&b_valid&&input_frame<count&&!soft_pending;    wire affine_reply_bad=rounded_affine&&mem_rsp_valid&&mem_rsp_ready&&
        (mem_rsp_tag[15:2]!={8'b0,input_frame} || mem_rsp_tag[1:0]>2 ||
         mem_rsp_mask!=((mem_rsp_tag[1:0]==0 ? needs_a : mem_rsp_tag[1:0]==1 ? needs_b : needs_c)&input_mask) ||
         (mem_rsp_tag[1:0]==0&&a_valid) || (mem_rsp_tag[1:0]==1&&b_valid) ||
         (mem_rsp_tag[1:0]==2&&c_valid));
    reg out_ready;
    reg [863:0] last_data;
    wire host_open=active&&host_enable&&state==IDLE&&!host_pending&&!host_rsp_valid;
    wire host_bad=host_block>=480 || (!host_write && host_block<480 && (valid_masks[host_block]&host_mask)!=host_mask);
    assign busy=state!=IDLE||host_pending||host_rsp_valid;
    assign host_ready=host_open&&(host_bad||mem_ready);
    assign req_ready=active&&state==IDLE&&!host_pending&&!host_rsp_valid&&!(host_enable&&host_valid);
    assign rsp_valid=active&&state==RESPONSE;
    assign rsp_fault=fault;
    assign rsp_detail=detail;
    assign rsp_data=fault==0 ? scalar : 64'd0;
    assign rsp_nonzero=fault==0&&nonzero;
    assign rsp_count=fault==0 ? result_count : 11'd0;
    assign rsp_job=job;
    assign rsp_tag=tag;
    assign rsp_fmt=fmt;
    assign events={((mem_valid&&!mem_ready)||(input_valid&&!in_ready)||(out_valid&&!out_ready)),
    mem_valid&&mem_ready&&mem_write,mem_valid&&mem_ready&&!mem_write,
    out_valid&&out_ready,input_valid&&in_ready};
    range_reader range_operands (
    .clk(clk),.rst(rst),.cancel(cancel||state==FAIL),
    .start_valid(range_start_valid),.start_ready(range_start_ready),
    .source_a_used(needs_a!=0),.source_b_used(needs_b!=0),
    .source_a_base(src_a),.source_b_base(src_b),
    .source_a_offset(index_value),.source_b_offset(aux_length),.frame_index(input_frame),
    .source_a_select(needs_a&input_mask),.source_b_select(needs_b&input_mask),.command_tag(tag),
    .provider_valid(range_provider_valid),.provider_ready(mem_ready&&state==RUN&&range_template&&
        !(out_valid&&kind==0&&!normalize&&!scalar_template)),
    .provider_address(range_provider_address),.provider_mask(range_provider_mask),.provider_tag(range_provider_tag),
    .provider_rsp_valid(mem_rsp_valid),.provider_rsp_ready(range_provider_rsp_ready),
    .provider_rsp_data(mem_rsp_data),.provider_rsp_mask(mem_rsp_mask),.provider_rsp_tag(mem_rsp_tag),.provider_rsp_fault(range_provider_fault),
    .done_valid(range_done_valid),.done_ready(range_done_ready),.done_fault(range_done_fault),
    .source_a_data(range_a_data),.source_b_data(range_b_data));
    stream_vector_store memory (
    .clk(clk),.rst(rst),.cancel(cancel||state==FAIL),.req_valid(mem_valid),.req_ready(mem_ready),.req_write(mem_write),
    .req_block(mem_block),.req_mask(mem_mask),.req_data(mem_data),.req_tag(pool_tag),
    .rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),.rsp_data(mem_rsp_data),.rsp_mask(mem_rsp_mask),.rsp_tag(mem_rsp_tag));
    stream_fabric #(.TERMINAL_ENABLE(1),.CASCADE_ENABLE(1)) fabric (
    .clk(clk),.rst(rst),.abort(cancel||state==FAIL),.cfg_valid(panel_active ? panel_cfg_valid : state==CONFIG),.cfg_ready(cfg_ready),.cfg_contexts(panel_active ? panel_cfg_contexts : contexts),
    .cfg_fault(cfg_fault),.cfg_loaded(cfg_loaded),.cmd_valid(panel_active ? panel_cmd_valid : state==LAUNCH),.cmd_ready(fabric_cmd_ready),
    .cmd_job(panel_active ? panel_cmd_job : job),.cmd_tag(panel_active ? panel_cmd_tag : tag),.cmd_fmt(panel_active ? panel_cmd_fmt : fmt),
    .cmd_terminal(panel_active ? panel_cmd_terminal : (rounded_affine ? 2'd0 : terminal_mode)),.cmd_shift(panel_active ? panel_cmd_shift : (rounded_affine ? 6'd0 : (gemv ? 6'd16 : normalize ? shift : descriptor[10:5]))),
    .cmd_terminal_mask(panel_active ? panel_cmd_terminal_mask : (rounded_affine ? 32'd0 : terminal_mask)),.cmd_flow(panel_active ? panel_cmd_flow : (rounded_affine ? 2'd1 : 2'd0)),.terminal_acc(terminal_acc),.terminal_error(terminal_error),.in_valid(panel_active ? panel_in_valid : input_valid),.in_ready(in_ready),.in_a(panel_active ? panel_in_a : fabric_a),.in_b(panel_active ? panel_in_b : fabric_b),
    .in_mask(panel_active ? panel_in_mask : fabric_input_mask),.in_last(panel_active ? panel_in_last : (gemv ? feeder_last : rounded_affine ? affine_last_input : normalize||input_frame+1==count)),.out_valid(out_valid),.out_ready(panel_active ? panel_out_ready : out_ready),
    .out_data(out_data),.out_acc(out_acc),.out_mask(out_mask),.out_faults(out_faults),.out_last(out_last),
    .done_valid(fabric_done),.done_ready(panel_active ? panel_done_ready : (rounded_affine ? (state==RUN||state==AFFINE_WAIT) : (state==RUN||gemv_state))),.done_fault(fabric_fault),.done_job(fabric_job),.done_tag(fabric_tag),.done_fmt(fabric_fmt));
    operator_frame_feeder feeder (
    .clk(clk),.rst(rst),.cancel(operator_cancel),
    .command_start(state==IDLE&&req_valid&&req_ready),
    .req_valid(feeder_issue_valid),.req_ready(feeder_req_ready),
    .req_dense(dense),.req_rfour(rfour),.req_trans(trans),.req_rows(rows),.req_cols(cols),
    .req_out(issue_out),.req_red(issue_red),.req_step(issue_step),.req_vec_base(src_a),.req_vec_length(length),
    .req_scale(scale),.req_key(key),.req_generation(generation),.req_job(job),.req_tag(tag),.req_fmt(fmt),.req_last(issue_frame_last),
    .matrix_valid(matrix_valid),
    .matrix_rows(matrix_rows),
    .matrix_cols(matrix_cols),
    .matrix_key(matrix_key),
    .matrix_generation(matrix_generation),
    .matrix_job(matrix_job),
    .matrix_fmt(matrix_fmt),
    .mat_valid(feeder_mat_valid),
    .mat_ready(mat_ready&&!factor_active),
    .mat_dense(feeder_mat_dense),
    .mat_mask(feeder_mat_mask),
    .mat_addr(feeder_mat_addr),
    .mat_key(feeder_mat_key),
    .mat_generation(feeder_mat_generation),
    .mem_job(feeder_mem_job),
    .mem_tag(feeder_mem_tag),
    .mem_fmt(feeder_mem_fmt),
    .mat_rsp_valid(mat_rsp_valid&&!factor_active),
    .mat_rsp_ready(feeder_mat_rsp_ready),
    .mat_rsp_data(mat_rsp_data),
    .mat_rsp_masks(mat_rsp_masks),
    .mat_rsp_mask(mat_rsp_mask),
    .mat_rsp_generation(mat_rsp_generation),
    .mat_rsp_job(mat_rsp_job),
    .mat_rsp_tag(mat_rsp_tag),
    .mat_rsp_fmt(mat_rsp_fmt),
    .mat_rsp_fault(mat_rsp_fault),
    .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_block(vec_block),.vec_mask(vec_mask),.vec_tag(vec_tag),
    .vec_rsp_valid(mem_rsp_valid&&gemv_state),.vec_rsp_ready(vec_rsp_ready),.vec_rsp_data(mem_rsp_data),
    .vec_rsp_mask(mem_rsp_mask),.vec_rsp_tag(mem_rsp_tag),.vec_rsp_fault(vec_fault),
    .rsp_valid(feeder_rsp_valid),.rsp_ready(feeder_rsp_ready),.rsp_mat(feeder_mat),.rsp_vec(feeder_vec),
    .rsp_mask(feeder_mask),.rsp_fault(feeder_fault),.rsp_job(feeder_job),.rsp_tag(feeder_tag),.rsp_fmt(feeder_fmt),.rsp_last(feeder_last),.rsp_frame(feeder_frame)
    );
    support_service selection (
        .clk(clk),.rst(rst),.cancel(operator_cancel),.req_valid(state==SUPPORT_START&&!factor_active&&!panel_active),.req_ready(selection_support_ready),
        .req_op(operation),.req_src_a(src_a),.req_src_b(src_b),.req_dst(dst),.req_length(length),.req_k(k),.req_scalar_a(scalar_a),
        .req_support_base(support_base),.req_aux_base(aux_base),.req_support_length(support_length),.req_aux_length(aux_length),
        .req_index(index_value),.req_flags(flags),.req_job(job),.req_tag(tag),.req_fmt(fmt),
        .vec_valid(selection_support_vec_valid),.vec_ready(support_vec_ready&&!factor_active&&!panel_active),.vec_block(selection_support_vec_block),.vec_mask(selection_support_vec_mask),.vec_tag(selection_support_vec_tag),
        .vec_rsp_valid(state==SUPPORT_WAIT&&mem_rsp_valid&&!factor_active&&!panel_active),.vec_rsp_ready(selection_support_vec_rsp_ready),.vec_rsp_data(mem_rsp_data),
        .vec_rsp_mask(mem_rsp_mask),.vec_rsp_tag(mem_rsp_tag),.vec_rsp_fault(support_vec_fault),
        .candidate_valid(selection_candidate_valid),.candidate_ready(candidate_ready&&!factor_active&&!panel_active),.candidate_block(selection_candidate_block),.candidate_mask(selection_candidate_mask),.candidate_data(selection_candidate_data),
        .rsp_valid(selection_support_valid),.rsp_ready(state==SUPPORT_WAIT&&!factor_active&&!panel_active),.rsp_fault(selection_support_fault),.rsp_detail(selection_support_detail),
        .rsp_count(selection_support_count),.rsp_length(selection_support_output_length),.rsp_data(selection_support_data),.rsp_nonzero(selection_support_nonzero),
        .rsp_job(selection_support_job),.rsp_tag(selection_support_tag),.rsp_fmt(selection_support_fmt)
    );
    factor_service #(.ENABLE_PANEL_BRIDGE(1)) factors (
        .clk(clk),.rst(rst),.cancel(operator_cancel),
        .req_valid(state==SUPPORT_START&&factor_active),.req_ready(factor_support_ready),
        .req_op(operation),.req_src_a(src_a),.req_dst(dst),.req_rows(rows),.req_cols(cols),
        .req_length(length),.req_index(index_value),.req_aux_length(aux_length),.req_flags(flags),.req_matrix_dense(dense),
        .req_key(key),.req_generation(generation),.req_job(job),.req_tag(tag),.req_fmt(fmt),
        .matrix_valid(matrix_valid),.matrix_rows(matrix_rows),.matrix_cols(matrix_cols),.matrix_key(matrix_key),
        .matrix_generation(matrix_generation),.matrix_job(matrix_job),.matrix_fmt(matrix_fmt),
        .mat_valid(factor_mat_valid),.mat_ready(mat_ready&&factor_active),.mat_dense(factor_mat_dense),
        .mat_mask(factor_mat_mask),.mat_addr(factor_mat_addr),.mat_key(factor_mat_key),.mat_generation(factor_mat_generation),
        .mat_job(factor_mem_job),.mat_tag(factor_mem_tag),.mat_fmt(factor_mem_fmt),
        .mat_rsp_valid(mat_rsp_valid&&factor_active),.mat_rsp_ready(factor_mat_rsp_ready),.mat_rsp_data(mat_rsp_data),
        .mat_rsp_mask(mat_rsp_mask),.mat_rsp_generation(mat_rsp_generation),.mat_rsp_job(mat_rsp_job),
        .mat_rsp_tag(mat_rsp_tag),.mat_rsp_fmt(mat_rsp_fmt),.mat_rsp_fault(mat_rsp_fault),
        .vec_valid(factor_support_vec_valid),.vec_ready(support_vec_ready&&factor_active),
        .vec_block(factor_support_vec_block),.vec_mask(factor_support_vec_mask),.vec_tag(factor_support_vec_tag),
        .vec_rsp_valid(state==SUPPORT_WAIT&&mem_rsp_valid&&factor_active),.vec_rsp_ready(factor_support_vec_rsp_ready),
        .vec_rsp_data(mem_rsp_data),.vec_rsp_mask(mem_rsp_mask),.vec_rsp_tag(mem_rsp_tag),.vec_rsp_fault(support_vec_fault),
        .candidate_valid(factor_candidate_valid),.candidate_ready(candidate_ready&&factor_active),
        .candidate_block(factor_candidate_block),.candidate_mask(factor_candidate_mask),.candidate_data(factor_candidate_data),
        .rsp_valid(factor_support_valid),.rsp_ready(state==SUPPORT_WAIT&&factor_active),
        .rsp_fault(factor_support_fault),.rsp_detail(factor_support_detail),.rsp_count(factor_support_count),
        .rsp_length(factor_support_output_length),.rsp_data(factor_support_data),.rsp_nonzero(factor_support_nonzero),
        .rsp_job(factor_support_job),.rsp_tag(factor_support_tag),.rsp_fmt(factor_support_fmt),.factor_valid(),
        .panel_req_valid(panel_req_valid),.panel_req_ready(panel_req_ready),.panel_req_write(panel_req_write),
        .panel_req_mask(panel_req_mask),.panel_req_addr(panel_req_addr),.panel_req_data(panel_req_data),
        .panel_req_rows(panel_req_rows),.panel_req_cols(panel_req_cols),.panel_req_key(panel_req_key),.panel_req_generation(panel_req_generation),
        .panel_req_job(panel_req_job),.panel_req_tag(panel_req_tag),.panel_req_fmt(panel_req_fmt),.panel_invalidate(panel_invalidate),
        .panel_rsp_valid(panel_rsp_valid),.panel_rsp_ready(panel_rsp_ready),.panel_rsp_write(panel_rsp_write),.panel_rsp_data(panel_rsp_data),
        .panel_rsp_mask(panel_rsp_mask),.panel_rsp_generation(panel_rsp_generation),.panel_rsp_job(panel_rsp_job),.panel_rsp_tag(panel_rsp_tag),
        .panel_rsp_fmt(panel_rsp_fmt),.panel_rsp_fault(panel_rsp_fault)
    );
    factor_panel_service panels (
        .clk(clk),.rst(rst),.cancel(operator_cancel),.req_valid(state==SUPPORT_START&&panel_active),.req_ready(panel_support_ready),.req_op(operation),
        .req_contexts(contexts),.req_src_a(src_a),.req_src_b(src_b),.req_dst(dst),.req_scalar_a(scalar_a),.req_rows(rows),.req_support_length(support_length),
        .req_aux_length(aux_length),.req_length(length),.req_index(index_value),.req_flags(flags),.req_matrix_dense(dense),
        .req_key(key),.req_generation(generation),.req_job(job),.req_tag(tag),.req_fmt(fmt),
        .matrix_valid(matrix_valid),.matrix_rows(matrix_rows),.matrix_cols(matrix_cols),.matrix_key(matrix_key),.matrix_generation(matrix_generation),.matrix_job(matrix_job),.matrix_fmt(matrix_fmt),
        .vec_valid(panel_support_vec_valid),.vec_ready(support_vec_ready&&panel_active),.vec_block(panel_support_vec_block),.vec_mask(panel_support_vec_mask),.vec_tag(panel_support_vec_tag),
        .vec_rsp_valid(state==SUPPORT_WAIT&&mem_rsp_valid&&panel_active),.vec_rsp_ready(panel_support_vec_rsp_ready),.vec_rsp_data(mem_rsp_data),.vec_rsp_mask(mem_rsp_mask),.vec_rsp_tag(mem_rsp_tag),.vec_rsp_fault(support_vec_fault),
        .candidate_valid(panel_candidate_valid),.candidate_ready(candidate_ready&&panel_active),.candidate_block(panel_candidate_block),.candidate_mask(panel_candidate_mask),.candidate_data(panel_candidate_data),
        .rsp_valid(panel_support_valid),.rsp_ready(state==SUPPORT_WAIT&&panel_active),.rsp_fault(panel_support_fault),.rsp_detail(panel_support_detail),.rsp_count(panel_support_count),
        .rsp_length(panel_support_output_length),.rsp_data(panel_support_data),.rsp_nonzero(panel_support_nonzero),.rsp_job(panel_support_job),.rsp_tag(panel_support_tag),.rsp_fmt(panel_support_fmt),
        .panel_req_valid(panel_req_valid),.panel_req_ready(panel_req_ready),.panel_req_write(panel_req_write),.panel_req_mask(panel_req_mask),.panel_req_addr(panel_req_addr),.panel_req_data(panel_req_data),
        .panel_req_rows(panel_req_rows),.panel_req_cols(panel_req_cols),.panel_req_key(panel_req_key),.panel_req_generation(panel_req_generation),.panel_req_job(panel_req_job),.panel_req_tag(panel_req_tag),.panel_req_fmt(panel_req_fmt),.panel_invalidate(panel_invalidate),
        .panel_rsp_valid(panel_rsp_valid),.panel_rsp_ready(panel_rsp_ready),.panel_rsp_write(panel_rsp_write),.panel_rsp_data(panel_rsp_data),.panel_rsp_mask(panel_rsp_mask),.panel_rsp_generation(panel_rsp_generation),.panel_rsp_job(panel_rsp_job),.panel_rsp_tag(panel_rsp_tag),.panel_rsp_fmt(panel_rsp_fmt),.panel_rsp_fault(panel_rsp_fault),
        .fabric_cfg_valid(panel_cfg_valid),.fabric_cfg_ready(cfg_ready),.fabric_cfg_contexts(panel_cfg_contexts),.fabric_cfg_fault(cfg_fault),.fabric_cfg_loaded(cfg_loaded),
        .fabric_cmd_valid(panel_cmd_valid),.fabric_cmd_ready(fabric_cmd_ready),.fabric_cmd_job(panel_cmd_job),.fabric_cmd_tag(panel_cmd_tag),.fabric_cmd_fmt(panel_cmd_fmt),
        .fabric_cmd_terminal(panel_cmd_terminal),.fabric_cmd_shift(panel_cmd_shift),.fabric_cmd_terminal_mask(panel_cmd_terminal_mask),.fabric_cmd_flow(panel_cmd_flow),
        .fabric_in_valid(panel_in_valid),.fabric_in_ready(in_ready),.fabric_in_a(panel_in_a),.fabric_in_b(panel_in_b),.fabric_in_mask(panel_in_mask),.fabric_in_last(panel_in_last),
        .fabric_out_valid(out_valid),.fabric_out_ready(panel_out_ready),.fabric_out_data(out_data),.fabric_out_acc(out_acc),.fabric_out_mask(out_mask),.fabric_out_faults(out_faults),.fabric_out_last(out_last),
        .fabric_done_valid(fabric_done),.fabric_done_ready(panel_done_ready),.fabric_done_fault(fabric_fault),.fabric_done_job(fabric_job),.fabric_done_tag(fabric_tag),.fabric_done_fmt(fabric_fmt),
        .terminal_acc(terminal_acc),.terminal_error(terminal_error)
    );
    always @*
    begin
        selected_a=0;
        selected_b=0;
        context_word=0;
        for(i=0;i<32;i=i+1)
        begin
            context_word=req_contexts[i*64 +: 64];
            selected_a[i]=context_word[7:6]==0 || (context_word[4:0]!=1&&context_word[9:8]==0);
            selected_b[i]=context_word[7:6]==1 || (context_word[4:0]!=1&&context_word[9:8]==1);
        end
        selected_a=selected_a & ~req_scalar_bind_a;
        selected_b=selected_b & ~req_scalar_bind_b;
        if(req_op==1||req_op==2||req_op==3||req_op==4)
        begin
            selected_a=32'hffffffff;
            selected_b=0;
        end
        fabric_a=a_buffer;
        fabric_b=b_buffer;
        store_data=out_data;
        store_bad=0;
        stored_value=0;
        stored_mag=0;
        for(narrow_lane=0;narrow_lane<32;narrow_lane=narrow_lane+1)
        begin
            if(bind_a[narrow_lane]) fabric_a[narrow_lane*27 +: 27]=scalar_a;
            if(bind_b[narrow_lane]) fabric_b[narrow_lane*27 +: 27]=scalar_b;
            if(normalize) fabric_b[narrow_lane*27 +: 27]=scalar_a;
            if(thresholding)
            begin
                fabric_b[narrow_lane*27 +: 27]=a_buffer[narrow_lane*27+26] ? -$signed(scalar_a) : scalar_a;
            end
            stored_value=$signed(out_data[narrow_lane*27 +: 27]);
            stored_mag=stored_value<0 ? -stored_value : stored_value;
            if(store&&out_mask[narrow_lane])
            begin
                if(store_mode==1)
                begin
                    stored_mag=(stored_mag+2)>>2;
                    stored_value=stored_value<0 ? -stored_mag : stored_mag;
                    if(stored_value>8388607||stored_value< -8388608) store_bad=1;
                    stored_value=stored_value<<<2;
                end
                else if(store_mode==2)
                begin
                    stored_mag=(stored_mag+128)>>8;
                    stored_value=stored_value<0 ? -stored_mag : stored_mag;
                    if(stored_value>131071||stored_value< -131072) store_bad=1;
                    stored_value=stored_value<<<8;
                end
                store_data[narrow_lane*27 +: 27]=stored_value[26:0];
            end
            // Thresholding clamps a PE-computed signed subtraction; no multiplier adjunct.
            if(thresholding&&out_mask[narrow_lane]&&soft_zero[narrow_lane]) store_data[narrow_lane*27 +: 27]=0;
        end
        if(rounded_affine)
        begin
            // One paired cascade frame owns logical lanes half*16..half*16+15.
            // Low A/B carry X/Y; high A carries C and high B is replaced by
            // the rounded low result inside stream_fabric.
            fabric_a=0;
            fabric_b=0;
            for(narrow_lane=0;narrow_lane<16;narrow_lane=narrow_lane+1)
            begin
                fabric_a[narrow_lane*27 +: 27]=a_buffer[(int'(affine_half)*16+narrow_lane)*27 +: 27];
                fabric_b[narrow_lane*27 +: 27]=b_buffer[(int'(affine_half)*16+narrow_lane)*27 +: 27];
                fabric_a[(16+narrow_lane)*27 +: 27]=copy_buffer[(int'(affine_half)*16+narrow_lane)*27 +: 27];
                if(bind_b[narrow_lane]) fabric_b[narrow_lane*27 +: 27]=scalar_b;
            end
        end
        if(gemv)
        begin
            fabric_a=feeder_vec;
            fabric_b=feeder_mat;
        end
        ca=int'(src_a)+(descriptor[0] ? int'(check_frame) : 0);
        cb=int'(src_b)+(descriptor[1] ? int'(check_frame) : 0);
        cc=int'(aux_base)+int'(check_frame);
        cd=int'(dst)+(descriptor[2]&&kind==0 ? int'(check_frame) : 0);
        bounds_bad=(needs_a!=0&&ca>=480)||(needs_b!=0&&cb>=480)||(rounded_affine&&needs_c!=0&&cc>=480)||(kind!=2&&(gemv ? int'(dst)+int'(count)>480 : cd>=480));
        source_bad=0;
        // RANGE_TEMPLATE validates every selected shifted lane before CONFIG.
        // This preserves ordinary TEMPLATE's no-PE-work-before-source-fault
        // behavior while leaving the reader to validate live response tags/masks.
        range_source_bad=0;
        for(range_check_lane=0;range_check_lane<32;range_check_lane=range_check_lane+1) begin
            if(needs_a[range_check_lane]&&check_mask[range_check_lane]) begin
                range_check_position=int'(index_value)+int'(check_frame)*32+range_check_lane;
                range_check_address=int'(src_a)+(range_check_position>>5);
                if(range_check_position>=1024||range_check_address>=480)range_source_bad=1;
                else if(!valid_masks[range_check_address][range_check_position[4:0]])range_source_bad=1;
            end
            if(needs_b[range_check_lane]&&check_mask[range_check_lane]) begin
                range_check_position=int'(aux_length)+int'(check_frame)*32+range_check_lane;
                range_check_address=int'(src_b)+(range_check_position>>5);
                if(range_check_position>=1024||range_check_address>=480)range_source_bad=1;
                else if(!valid_masks[range_check_address][range_check_position[4:0]])range_source_bad=1;
            end
        end
        if(needs_a!=0&&ca<480) source_bad=((valid_masks[ca]&needs_a&check_mask)!=(needs_a&check_mask));
        if(needs_b!=0&&cb<480) source_bad=source_bad||((valid_masks[cb]&needs_b&check_mask)!=(needs_b&check_mask));
        if(rounded_affine&&needs_c!=0&&cc<480) source_bad=source_bad||((valid_masks[cc]&needs_c&check_mask)!=(needs_c&check_mask));
        mem_valid=0;
        mem_write=0;
        mem_block=0;
        mem_logical_block=0;
        mem_mask=0;
        mem_data=0;
        pool_tag=0;
        mem_rsp_ready=0;
        mem_scratch=0;
        mem_scratch_index=0;
        out_ready=0;
        if(host_open&&host_valid&&!host_bad)
        begin
            mem_valid=1;
            mem_write=host_write;
            mem_logical_block=host_block;
            mem_mask=host_mask;
            mem_data=host_data;
            pool_tag=host_tag;
        end
        if(host_pending) mem_rsp_ready=!host_rsp_valid;
        if(state==RUN)
        begin
            mem_rsp_ready=1;
            // Drain output first; input buffers allow compute to overlap the next read pair.
            if(out_valid&&kind==0&&!normalize&&!scalar_template&&!rounded_affine)
            begin
                mem_valid=1;
                mem_write=1;
                mem_logical_block=9'd480+output_frame;
                mem_scratch=1;
                mem_scratch_index=output_frame;
                mem_mask=out_mask;
                mem_data=store_data;
                out_ready=mem_ready;
            end
            else
            begin
                out_ready=1;
                if(range_template&&range_provider_valid) begin
                    mem_valid=1;
                    mem_logical_block=range_provider_address;
                    mem_mask=range_provider_mask;
                    pool_tag=range_provider_tag;
                    mem_rsp_ready=range_provider_rsp_ready;
                end else if(!range_template&&!scalar_template&&input_frame<count&&read_phase<read_limit&&issue_source)
                begin
                    mem_valid=1;
                    mem_logical_block=issue_block;
                    mem_mask=issue_mask;
                    pool_tag=rounded_affine ? {8'b0,input_frame,issue_kind} : {9'b0,input_frame,issue_b_tag};
                end
            end
        end
        if(gemv_state)
        begin
            mem_valid=vec_valid;
            mem_logical_block=vec_block;
            mem_mask=vec_mask;
            pool_tag=vec_tag;
            mem_rsp_ready=vec_rsp_ready;
            out_ready=1;
        end
        if(state==SUPPORT_WAIT) begin
            mem_rsp_ready=support_vec_rsp_ready;
            if(candidate_valid&&!candidate_bad) begin
                mem_valid=1;
                mem_write=1;
                mem_logical_block=9'd480+candidate_block;
                mem_scratch=1;
                mem_scratch_index=candidate_block;
                mem_mask=candidate_mask;
                mem_data=candidate_data;
            end else if(support_vec_valid&&!candidate_valid) begin
                mem_valid=1;
                mem_logical_block=support_vec_block;
                mem_mask=support_vec_mask;
                pool_tag=support_vec_tag;
            end
        end
        if(state==AFFINE_WRITE)
        begin
            mem_valid=1;
            mem_write=1;
            mem_logical_block=9'd480+input_frame;
            mem_scratch=1;
            mem_scratch_index=input_frame;
            mem_mask=input_mask;
            mem_data=last_data;
        end
        if(state==GEMV_WRITE)
        begin
            mem_valid=1;
            mem_write=1;
            mem_logical_block=9'd480+gemv_out[10:5];
            mem_scratch=1;
            mem_scratch_index=gemv_out[10:5];
            mem_mask=gemv_write_mask;
            mem_data=last_data;
        end
        if(state==LAST_WRITE)
        begin
            mem_valid=1;
            mem_write=1;
            mem_logical_block=9'd480+(normalize ? output_frame-1'b1 : 0);
            mem_scratch=1;
            mem_scratch_index=normalize ? output_frame-1'b1 : 0;
            mem_mask=normalize ? (output_frame==count ? tail_mask : 32'hffffffff) : final_mask;
            mem_data=last_data;
        end
        if(state==COPY_READ)
        begin
            mem_valid=1;
            mem_logical_block=9'd480+copy_frame;
            mem_scratch=1;
            mem_scratch_index=copy_frame;
            mem_mask=scratch_masks[copy_frame];
            pool_tag=16'hc000+copy_frame;
        end
        if(state==COPY_WAIT) mem_rsp_ready=1;
        if(state==COPY_WRITE)
        begin
            mem_valid=1;
            mem_write=1;
            mem_logical_block=dst+(descriptor[2]&&kind==0 ? copy_frame : 0);
            mem_mask=scratch_masks[copy_frame];
            mem_data=copy_buffer;
        end
        // All public users retain logical addresses until this final arbitration
        // point. Scratch traffic uses a currently-owned physical handle.
        if(mem_valid)
        begin
            if(mem_scratch) mem_block=scratch_handle[mem_scratch_index];
            else if(mem_logical_block<480) mem_block=map_lookup_physical;
            else mem_block=mem_logical_block;
        end
    end
    always @(posedge clk)
    begin
        if(!active)
        begin
            state<=IDLE;
            host_pending<=0;
            host_rsp_valid<=0;
            host_rsp_write<=0;
            host_rsp_data<=0;
            host_rsp_mask<=0;
            host_rsp_tag<=0;
            host_rsp_fault<=0;
            a_valid<=0;
            b_valid<=0;
            read_phase<=0;
            range_inflight<=0;
            range_issued_address<=0;
            range_issued_mask<=0;
            fault<=0;
            detail<=0;
            scalar<=0;
            nonzero<=0;
            result_count<=0;
            soft_pending<=0;
            soft_zero<=0;
            if(rst)
            begin
                support_length<=0;aux_length<=0;k<=0;index_value<=0;result_length<=0;
                support_base<=0;aux_base<=0;flags<=0;allocated_count<=0;support_vec_fault<=0;
                dense<=0;
                trans<=0;
                rfour<=0;
                rows<=0;
                cols<=0;
                gemv_out<=0;
                issue_out<=0;
                issue_red<=0;
                issue_step<=0; delivered_red<=0;delivered_step<=0;delivered_frame<=0;
                issue_done<=0;delivery_group_done<=0;
                scale<=0;
                key<=0;
                generation<=0;
                gemv_write_mask<=0;
                operation<=0;
                shift<=0;
                store_mode<=0;
                length<=0;
                scalar_a<=0;
                scalar_b<=0;
                bind_a<=0;
                bind_b<=0;
                command_bad<=0;
                src_a<=0;
                src_b<=0;
                dst<=0;
                count<=0;
                fmt<=0;
                job<=0;
                tag<=0;
                descriptor<=0;
                tail_mask<=0;
                contexts<=0;
                needs_a<=0;
                needs_b<=0;
                needs_c<=0;
                check_frame<=0;
                input_frame<=0;
                output_frame<=0;
                copy_frame<=0;
                a_buffer<=0;
                b_buffer<=0;
                c_valid<=0;
                affine_half<=0;
                affine_input_done<=0;
                affine_out_half<=0;
                copy_buffer<=0;
                last_data<=0;
                for(j=0;j<480;j=j+1)
                begin
                    valid_masks[j]<=0;
                    public_map_valid[j]<=0;
                end
                for(j=0;j<32;j=j+1)
                begin
                    scratch_masks[j]<=0;
                    scratch_handle[j]<=9'd480+j;
                end
                remap_frame<=0;
            end
            else if(state!=IDLE&&state!=RESPONSE&&writes_vector)
            begin
                // Cancel discards this CALL's whole destination blocks; older CALLs remain published.
                for(j=0;j<32;j=j+1) if(j<clear_count&&int'(dst)+(descriptor[2]&&kind==0 ? j : 0)<480)
                valid_masks[int'(dst)+(descriptor[2]&&kind==0 ? j : 0)]<=0;
            end
        end
        else
        begin
            if(host_rsp_valid&&host_rsp_ready) host_rsp_valid<=0;
            if(host_valid&&host_ready)
            begin
                host_rsp_write<=host_write;
                host_rsp_tag<=host_tag;
                host_rsp_mask<=host_mask;
                host_rsp_data<=0;
                host_rsp_fault<=host_bad ? 4'd2 : 4'd0;
                if(host_bad||host_write) host_rsp_valid<=1;
                else host_pending<=1;
                if(host_write&&!host_bad) valid_masks[host_block]<=valid_masks[host_block]|host_mask;
            end
            if(host_pending&&mem_rsp_valid&&mem_rsp_ready)
            begin
                host_pending<=0;
                host_rsp_valid<=1;
                host_rsp_data<=mem_rsp_data;
                if(mem_rsp_tag!=host_rsp_tag||mem_rsp_mask!=host_rsp_mask)
                begin
                    host_rsp_fault<=6;
                    host_rsp_data<=0;
                end
            end
            if(support_vec_valid&&support_vec_ready) begin
                support_vec_fault<=(support_vec_block>=480 ||
                    (support_vec_block<480&&(valid_masks[support_vec_block]&support_vec_mask)!=support_vec_mask)) ?
                    `CSR_KERNEL_FAULT_UNINITIALIZED : `CSR_KERNEL_FAULT_NONE;
            end
            case(state)
                IDLE: if(req_valid&&req_ready)
                begin
                    support_length<=req_support_length;aux_length<=req_aux_length;k<=req_k;index_value<=req_index;
                    support_base<=req_support_base;aux_base<=req_aux_base;flags<=req_flags;
                    allocated_count<=(requested_extent+11'd31)>>5;
                    result_length<=0;
                    dense<=req_matrix_dense;
                    trans<=req_trans;
                    rfour<=req_r4;
                    rows<=req_rows;
                    cols<=req_cols;
                    scale<=req_scale;
                    key<=req_key;
                    generation<=req_generation;
                    gemv_out<=0;
                    issue_out<=0;
                    issue_red<=0;
                    issue_step<=0; delivered_red<=0;delivered_step<=0;delivered_frame<=0;
                    issue_done<=0;delivery_group_done<=0;
                    gemv_write_mask<=0;
                    if(req_op!=`CSR_KERNEL_OP_SCALAR_TEMPLATE)
                        for(j=0;j<32;j=j+1) scratch_masks[j]<=0;
                    operation<=req_op;
                    shift<=req_shift;
                    store_mode<=req_store_mode;
                    length<=req_length;
                    scalar_a<=req_scalar_a;
                    scalar_b<=req_scalar_b;
                    bind_a<=req_scalar_bind_a;
                    bind_b<=req_scalar_bind_b;
                    nonzero<=0;
            result_count<=0;
                    soft_pending<=0;
                    // A context selected only beyond a short tail is not a RAM
                    // source for RANGE_TEMPLATE.  Such unused operands retain
                    // offset zero and cause no reader transaction.
                    command_bad<=req_op>`CSR_KERNEL_OP_FACTOR_ENERGY_TAP||(req_op!=`CSR_KERNEL_OP_FACTOR_PROJECT_UPDATE&&req_descriptor[4:3]==`CSR_KERNEL_PROJECT_DESCRIPTOR_KIND)||(req_op<`CSR_KERNEL_OP_TOPK&&req_flags!=0)||req_fmt!=1||
                    (req_op>0&&req_op<`CSR_KERNEL_OP_TOPK&&(req_length==0||req_length>1024))||
                    ((req_op==0||req_op==`CSR_KERNEL_OP_RANGE_TEMPLATE)&&(req_tail_mask==0||req_descriptor[31:11]!=0||req_descriptor[4:3]>2||
                    (req_descriptor[4:3]!=1&&req_descriptor[10:5]!=0)))||
                    (req_op==1&&(req_rows==0||req_rows>128||req_cols==0||req_cols>(req_matrix_dense ? 96 : 1024)||req_length!=(req_trans ? {3'b0,req_rows} : req_cols)||req_scalar_bind_a!=0||req_scalar_bind_b!=0))||
                    (req_op==`CSR_KERNEL_OP_SCALAR_TEMPLATE&&(
                    req_length!=1||req_frame_count!=1||req_tail_mask!=1||req_descriptor[31:3]!=0||
                    !req_contexts[5]||!(req_contexts[4:0]==1||req_contexts[4:0]==2||req_contexts[4:0]==3||req_contexts[4:0]==8)||
                    req_contexts[63:37]!=0||selected_a[0]||selected_b[0]||req_matrix_dense||req_trans||req_r4||
                    req_store_mode!=0||req_flags!=0||req_k!=0||req_support_length!=0||req_aux_length!=0||req_index!=0||req_shift!=0))||
                    ((req_op==`CSR_KERNEL_OP_FACTOR_MATVEC||req_op==`CSR_KERNEL_OP_FACTOR_RANK1)&&
                     (req_descriptor!=(req_op==`CSR_KERNEL_OP_FACTOR_MATVEC ? 32'd23 : 32'd7)||req_scalar_bind_a!=0||req_scalar_bind_b!=0||!req_matrix_dense||req_trans||req_r4||req_store_mode!=0||
                      req_flags!=0||req_k!=0||req_shift!=0||req_support_base!=0||req_aux_base!=0||req_support_length==0||req_support_length>96||
                       req_aux_length>=req_rows||req_length==0||req_length>128||req_aux_length+req_length>req_rows||req_index>=req_support_length))||
                    (req_op==`CSR_KERNEL_OP_FACTOR_PROJECT_UPDATE&&
                     (req_descriptor!=`CSR_KERNEL_PROJECT_DESCRIPTOR||req_contexts[63:0]!=`CSR_KERNEL_PROJECT_DOT_CONTEXT||req_contexts[127:64]!=`CSR_KERNEL_PROJECT_SCALE_CONTEXT||req_contexts[191:128]!=`CSR_KERNEL_PROJECT_RANK_CONTEXT||req_contexts[2047:192]!=`CSR_KERNEL_PROJECT_PADDING_CONTEXT||
                      req_scalar_bind_a!=0||req_scalar_bind_b!=0||!req_matrix_dense||req_trans||req_r4||req_store_mode!=0||req_flags!=0||req_k!=0||req_shift!=0||
                      req_src_b!=0||req_dst!=0||req_support_base!=0||req_aux_base!=0||req_support_length==0||req_support_length>96||
                      req_aux_length>=req_rows||req_length==0||req_length>128||req_aux_length+req_length>req_rows||req_index>=req_support_length))||
                    (req_op==`CSR_KERNEL_OP_FACTOR_EXTEND&&(req_descriptor!=0||req_contexts!=0||req_scalar_bind_a!=0||req_scalar_bind_b!=0||!req_matrix_dense||req_trans||req_r4||req_store_mode!=0||req_flags!=0||req_k!=0||req_shift!=0||req_src_a!=0||req_src_b!=0||req_dst!=0||req_support_base!=0||req_aux_base!=0||req_aux_length!=0||req_length!=req_rows||req_index==0||req_index>=req_support_length))||
                    (req_op==`CSR_KERNEL_OP_SCALAR_INSERT&&
                     (req_descriptor!=0||req_contexts!=0||req_scalar_bind_a!=0||req_scalar_bind_b!=0||req_matrix_dense||req_trans||req_r4||req_store_mode!=0||req_flags!=0||req_k!=0||req_shift!=0||
                      req_src_b!=0||req_support_base!=0||req_support_length!=0||req_aux_base!=0||req_aux_length!=0||req_length==0||req_length>1024||req_index>=req_length))||
                    (req_op==`CSR_KERNEL_OP_RANGE_TEMPLATE&&
                     (req_length==0||req_length>1024||req_frame_count!=((req_length+11'd31)>>5)||
                      req_tail_mask!=(req_length[4:0]==0 ? 32'hffffffff : (32'hffffffff>>(32-req_length[4:0])) )||
                      req_descriptor[2:0]!=3'b111||req_matrix_dense||req_trans||req_r4||req_store_mode!=0||req_flags!=0||req_k!=0||
                      req_support_base!=0||req_support_length!=0||req_aux_base!=0||req_shift!=0||req_index>1023||req_aux_length>1023||
                      ((req_length>32 ? selected_a!=0 : (selected_a&req_tail_mask)!=0) ? 1'b0 : req_index!=0)||
                      ((req_length>32 ? selected_b!=0 : (selected_b&req_tail_mask)!=0) ? 1'b0 : req_aux_length!=0)))||
                    (req_op==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE&&
                     (req_descriptor!=32'd23||req_scalar_bind_a!=0||req_scalar_bind_b!=0||!req_matrix_dense||req_trans||req_r4||req_store_mode!=0||
                      req_src_b!=0||req_scalar_b!=0||req_support_base!=0||req_aux_base!=0||req_k!=0||req_shift!=0||
                      req_frame_count!=0||req_tail_mask!=0||req_flags[7:3]!=0||(!req_flags[2]&&req_scalar_a!=0)||
                      req_rows==0||req_rows>128||req_support_length==0||req_support_length>96||req_length==0||req_length>128||
                      (req_flags[0] ? (req_index>=req_rows||{1'b0,req_aux_length}+{1'b0,req_length}>{1'b0,req_support_length}) :
                                      (req_index>=req_support_length||{1'b0,req_aux_length}+{1'b0,req_length}>{3'b0,req_rows}))))||
                    (req_op==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP&&
                     (req_descriptor!=32'd23||req_scalar_bind_a!=0||req_scalar_bind_b!=0||!req_matrix_dense||req_trans||req_r4||req_store_mode!=0||
                      req_src_a!=0||req_src_b!=0||req_scalar_a!=0||req_scalar_b!=0||req_support_base!=0||req_aux_base!=0||req_k!=0||req_shift!=0||
                      req_frame_count!=0||req_tail_mask!=0||req_flags[7:1]!=0||
                      req_rows==0||req_rows>128||req_support_length==0||req_support_length>96||req_length==0||req_length>128||
                      (req_flags[0] ? (req_index>=req_rows||{1'b0,req_aux_length}+{1'b0,req_length}>{1'b0,req_support_length}) :
                                      (req_index>=req_support_length||{1'b0,req_aux_length}+{1'b0,req_length}>{3'b0,req_rows}))))||
                    (req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE&&
                     (req_length==0||req_length>1024||req_frame_count!=((req_length+11'd31)>>5)||
                      req_tail_mask!=(req_length[4:0]==0 ? 32'hffffffff : (32'hffffffff>>(32-req_length[4:0])) )||
                      req_descriptor!=32'd7||req_matrix_dense||req_trans||req_r4||req_store_mode!=0||req_flags!=0||req_k!=0||
                      req_support_base!=0||req_support_length!=0||req_aux_length!=0||req_index!=0||req_shift!=0||
                      req_scalar_bind_a!=0||req_scalar_a!=0||!((req_scalar_bind_b==0)||(req_scalar_bind_b==32'h0000ffff))||
                      (req_scalar_bind_b==0&&req_scalar_b!=0)||(req_scalar_bind_b==32'h0000ffff&&(req_src_b!=0||req_scalar_a!=0))))||
                    (req_op==3&&req_store_mode>2)||(req_op==4&&$signed(req_scalar_a)<0);
                    for(j=0;j<32;j=j+1)
                    begin
                        if((req_op==0||req_op==`CSR_KERNEL_OP_RANGE_TEMPLATE) && (req_descriptor[4:3]==0 ?
                        !(req_contexts[j*64 +: 5]==1||req_contexts[j*64 +: 5]==2||req_contexts[j*64 +: 5]==3||req_contexts[j*64 +: 5]==8) :
                        req_contexts[j*64 +: 5]!=9)) command_bad<=1;
                        if(req_op==1 && (req_contexts[j*64 +: 10]!=10'd265)) command_bad<=1;
                        if(req_op==2 && (req_contexts[j*64 +: 10]!=10'd297)) command_bad<=1;
                        if(req_op==3 && (req_contexts[j*64 +: 5]!=1||req_contexts[j*64+6 +: 2]!=0)) command_bad<=1;
                        if(req_op==4 && ((req_contexts[j*64 +: 10]&10'h3df)!=10'd259)) command_bad<=1;
                        if((req_op==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE||req_op==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP)&&req_contexts[j*64 +: 64]!=64'd297) command_bad<=1;
                        if(req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE) begin
                            if(req_contexts[j*64+10 +: 54]!=0) command_bad<=1;
                            if(j<16 && (req_contexts[j*64 +: 5]!=`CSR_STREAM_OP_MUL||!req_contexts[j*64+5]||req_contexts[j*64+6 +: 2]!=`CSR_STREAM_SRC_A||req_contexts[j*64+8 +: 2]!=`CSR_STREAM_SRC_B)) command_bad<=1;
                            if(j>=16 && ((req_contexts[j*64 +: 5]!=`CSR_STREAM_OP_ADD&&req_contexts[j*64 +: 5]!=`CSR_STREAM_OP_SUB)||req_contexts[j*64 +: 5]!=req_contexts[16*64 +: 5]||!req_contexts[j*64+5]||req_contexts[j*64+6 +: 2]!=`CSR_STREAM_SRC_A||req_contexts[j*64+8 +: 2]!=`CSR_STREAM_SRC_B)) command_bad<=1;
                        end
                    end
                    src_a<=req_src_a;
                    src_b<=req_src_b;
                    dst<=req_dst;
                    count<=req_op==`CSR_KERNEL_OP_SCALAR_TEMPLATE ? 8'd1 : req_op>=`CSR_KERNEL_OP_TOPK ? (requested_extent+11'd31)>>5 : req_op==0 ? req_frame_count : ((req_op==1 ? (req_trans ? req_cols : {3'b0,req_rows}) : req_length)+11'd31)>>5;
                    fmt<=req_fmt;
                    job<=req_job;
                    tag<=req_tag;
                    descriptor<=req_op==0||req_op==`CSR_KERNEL_OP_SCALAR_TEMPLATE||req_op==`CSR_KERNEL_OP_RANGE_TEMPLATE||req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE ? req_descriptor : 32'd5;
                    tail_mask<=req_op==0||req_op==`CSR_KERNEL_OP_SCALAR_TEMPLATE||req_op==`CSR_KERNEL_OP_RANGE_TEMPLATE||req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE ? req_tail_mask : req_length[4:0]==0 ? 32'hffffffff : (32'hffffffff>>(32-req_length[4:0]));
                    contexts<=req_contexts;
                    needs_a<=req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE ? 32'hffffffff : selected_a;
                    needs_b<=req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE ? (req_scalar_bind_b==0 ? 32'hffffffff : 32'd0) : selected_b;
                    needs_c<=req_op==`CSR_KERNEL_OP_ROUNDED_AFFINE ? 32'hffffffff : 32'd0;
                    check_frame<=0;
                    input_frame<=0;
                    output_frame<=0;
                    copy_frame<=0;
                    read_phase<=0;
                    a_valid<=0;
                    b_valid<=0;
                    c_valid<=0;
                    affine_half<=0;
                    affine_input_done<=0;
                    affine_out_half<=0;
                    last_data<=0;
                    fault<=0;
                    detail<=0;
                    scalar<=0;
                    state<=CHECK;
                end
                CHECK:
                begin
                    if(scalar_template) begin
                        if(command_bad) begin fault<=`CSR_KERNEL_FAULT_COMMAND;state<=FAIL;end
                        else state<=CONFIG;
                    end else if(adjunct) begin
                        if(command_bad||allocated_count>32||(writes_vector&&int'(dst)+int'(allocated_count)>480)) begin
                            fault<=`CSR_KERNEL_FAULT_COMMAND;state<=FAIL;
                        end else state<=SUPPORT_START;
                    end else
                    if(command_bad||count==0||count>32||kind==3||descriptor[31:11]!=0||
                       (range_template ? (kind!=2&&cd>=480) : bounds_bad))
                    begin
                        fault<=1;
                        state<=FAIL;
                    end
                    else if(range_template ? range_source_bad : source_bad)
                    begin
                        fault<=5;
                        state<=FAIL;
                    end
                    else if(check_frame+1==(gemv ? source_blocks : count)) state<=CONFIG;
                    else check_frame<=check_frame+1'b1;
                end
                CONFIG: if(cfg_ready) state<=CONFIG_WAIT;
                CONFIG_WAIT: if(cfg_fault!=0||!cfg_loaded)
                begin
                    detail<=cfg_fault;
                    fault<=3;
                    state<=FAIL;
                end
                else state<=LAUNCH;
                LAUNCH: if(fabric_cmd_ready) begin
                    state<=gemv ? GEMV_REQ : RUN;
                    if(scalar_template) begin
                        a_valid<=1;
                        b_valid<=1;
                    end
                    else if(range_template) begin
                        a_valid<=0;
                        b_valid<=0;
                        range_inflight<=0;
                    end else if(!gemv) begin
                        // NORMALIZE returns through LAUNCH for every frame.
                        // Its next source frame may already be prefetched in
                        // RUN, so only initialize operands which cannot need
                        // a RAM response.  Needed buffers retain their valid
                        // prefetched data across this command handoff.
                        if(needs_a==0) begin
                            a_valid<=1;
                            a_buffer<=0;
                        end
                        if(needs_b==0) begin
                            b_valid<=1;
                            b_buffer<=0;
                        end
                    end
                end
                SUPPORT_START: if(support_ready) state<=SUPPORT_WAIT;
                SUPPORT_WAIT: begin
                    if(candidate_valid&&candidate_ready) begin
                        if(candidate_bad) begin fault<=`CSR_KERNEL_FAULT_IDENTITY;state<=FAIL;end
                        else scratch_masks[candidate_block]<=scratch_masks[candidate_block]|candidate_mask;
                    end
                    if(support_valid) begin
                        if(support_job!=job||support_tag!=tag||support_fmt!=fmt) begin fault<=`CSR_KERNEL_FAULT_IDENTITY;state<=FAIL;end
                        else if(support_fault!=0) begin fault<=support_fault;detail<=support_detail;state<=FAIL;end
                        else if(support_output_length>1024||((support_output_length+11'd31)>>5)>allocated_count) begin fault<=`CSR_KERNEL_FAULT_IDENTITY;state<=FAIL;end
                        // Op25's count is a boolean statistic, not a candidate
                        // length.  Keep its full candidate extent independent of
                        // tail_nonzero so a zero tail still publishes its head.
                        else if(factor_energy_tap&&(support_count>11'd1||support_output_length!=length)) begin
                            fault<=`CSR_KERNEL_FAULT_IDENTITY;
                            state<=FAIL;
                        end
                        else begin
                            scalar<=support_data;nonzero<=support_nonzero;result_count<=support_count;result_length<=support_output_length;
                            count<=(support_output_length+11'd31)>>5;check_frame<=0;
                            state<=writes_vector ? SUPPORT_VALIDATE : RESPONSE;
                        end
                    end
                    if(candidate_valid&&candidate_ready&&candidate_bad) begin fault<=`CSR_KERNEL_FAULT_IDENTITY;state<=FAIL;end
                end
                SUPPORT_VALIDATE: begin
                    if(count==0) state<=INVALIDATE;
                    else if(scratch_masks[check_frame]!=support_expected_mask) begin fault<=`CSR_KERNEL_FAULT_IDENTITY;state<=FAIL;end
                    else if(check_frame+1==count) state<=INVALIDATE;
                    else check_frame<=check_frame+1'b1;
                end
                GEMV_REQ: state<=GEMV_WAIT;
                GEMV_WAIT:
                begin
                    if(feeder_rsp_valid&&feeder_rsp_ready)
                    begin
                        if(feeder_bad)
                        begin
                            fault<=7;
                            detail<=feeder_fault!=0 ? feeder_fault : 4'd8;
                            state<=FAIL;
                        end
                        else begin
                            delivered_frame<=delivered_frame+1'b1;
                            if(delivered_last) delivery_group_done<=1;
                            if(rfour) begin
                                if(delivered_step==7) begin
                                    delivered_step<=0;
                                    delivered_red<=delivered_red+32;
                                end else delivered_step<=delivered_step+1'b1;
                            end else delivered_red<=delivered_red+1'b1;
                        end
                    end
                    // Allocation is command-global.  With prefetch enabled it
                    // advances into future output groups while the active group
                    // drains its terminal reduction.  The four-slot feeder
                    // bounds that speculation to transport payload only.
                    if(feeder_issue_valid&&feeder_req_ready) begin
                        if(issue_frame_last) begin
                            if(issue_out+gemv_group_width>=outputs) issue_done<=1;
                            else begin
                                issue_out<=issue_out+gemv_group_width;
                                issue_red<=0;
                                issue_step<=0;
                            end
                        end else if(rfour) begin
                            if(issue_step==7) begin
                                issue_step<=0;
                                issue_red<=issue_red+32;
                            end else issue_step<=issue_step+1'b1;
                        end else issue_red<=issue_red+1'b1;
                    end
                    if(fabric_done)
                    begin
                        if(fabric_fault!=0||fabric_job!=job||fabric_tag!=tag||fabric_fmt!=fmt)
                        begin
                            fault<=terminal_error!=0 ? 4 : 3;
                            state<=FAIL;
                        end
                        else
                        begin
                            // Row reduction and single rounding finished in the PEs.
                            // Only routing and mask packing remain; no central adder.
                            last_data<=0;
                            gemv_write_mask<=0;
                            for(j=0;j<32;j=j+1)
                                if((!rfour||j%4==0)&&gemv_out+(rfour ? j/4 : j)<outputs)
                                begin
                                    last_data[((gemv_out+(rfour ? j/4 : j))%32)*27 +: 27]<=out_data[j*27 +: 27];
                                    gemv_write_mask[(gemv_out+(rfour ? j/4 : j))%32]<=1;
                                    if(out_data[j*27 +: 27]!=0) nonzero<=1;
                                end
                            state<=GEMV_WRITE;
                        end
                    end
                end
                GEMV_WRITE: if(mem_ready)
                begin
                    scratch_masks[gemv_out[10:5]]<=scratch_masks[gemv_out[10:5]]|gemv_write_mask;
                    if(gemv_out+(rfour ? 8 : 32)>=outputs) state<=INVALIDATE;
                    else
                    begin
                        gemv_out<=gemv_out+gemv_group_width;
                        // Issue coordinates remain command-global.  Only the
                        // retiring compute group resets its delivery cursor.
                        delivered_red<=0;
                        delivered_step<=0;
                        delivery_group_done<=0;
                        state<=LAUNCH;
                    end
                end
                RUN:
                begin
                    // RANGE_TEMPLATE owns its tagged provider responses through
                    // range_reader. Ordinary templates retain the existing join.
                    if(mem_valid&&mem_ready&&!mem_write&&range_template&&range_provider_valid) begin
                        range_issued_address<=range_provider_address;
                        range_issued_mask<=range_provider_mask;
                    end
                    if(range_start_valid&&range_start_ready)range_inflight<=1;
                    if(range_done_valid&&range_done_ready) begin
                        range_inflight<=0;
                        if(range_done_fault!=0) begin
                            fault<=range_done_fault==1 ? `CSR_KERNEL_FAULT_RANGE : `CSR_KERNEL_FAULT_OPERAND;
                            state<=FAIL;
                        end else begin
                            a_buffer<=range_a_data;b_buffer<=range_b_data;a_valid<=1;b_valid<=1;
                        end
                    end
                    if(mem_valid&&mem_ready&&!mem_write&&!range_template) read_phase<=read_phase+1'b1;
                    if(mem_rsp_valid&&mem_rsp_ready&&!range_template)
                    begin
                        if(rounded_affine) begin
                            if(affine_reply_bad)
                            begin
                                fault<=6;
                                state<=FAIL;
                            end
                            else if(mem_rsp_tag[1:0]==0) begin a_buffer<=mem_rsp_data;a_valid<=1;end
                            else if(mem_rsp_tag[1:0]==1) begin b_buffer<=mem_rsp_data;b_valid<=1;end
                            else begin copy_buffer<=mem_rsp_data;c_valid<=1;end
                        end else if(mem_rsp_tag!={9'b0,input_frame,(source_alias ? 1'b0 : mem_rsp_tag[0])} ||
                        mem_rsp_mask!=(source_alias ? (needs_a|needs_b)&input_mask :
                        (mem_rsp_tag[0] ? needs_b : needs_a)&input_mask))
                        begin
                            fault<=6;
                            state<=FAIL;
                        end
                        else if(mem_rsp_tag[0])
                        begin
                            b_buffer<=mem_rsp_data;
                            b_valid<=1;
                        end
                        else
                        begin
                            a_buffer<=mem_rsp_data;
                            a_valid<=1;
                            if(source_alias) begin
                                b_buffer<=mem_rsp_data;
                                b_valid<=1;
                            end
                        end
                    end
                    if(input_valid&&in_ready)
                    begin
                        if(rounded_affine) begin
                            if(!affine_half&&input_mask[31:16]!=0) affine_half<=1;
                            else affine_input_done<=1;
                        end else begin
                        if(thresholding)
                        begin
                            soft_pending<=1;
                            for(j=0;j<32;j=j+1) soft_zero[j]<=
                            ($signed(a_buffer[j*27 +: 27])>= -$signed(scalar_a))&&
                            ($signed(a_buffer[j*27 +: 27])<= $signed(scalar_a));
                        end
                        input_frame<=input_frame+1'b1;
                        read_phase<=0;
                        a_valid<=range_template ? 0 : needs_a==0;
                        b_valid<=range_template ? 0 : needs_b==0;
                        if(range_template||needs_a==0) a_buffer<=0;
                        if(range_template||needs_b==0) b_buffer<=0;
                        end
                    end
                    if(out_valid&&out_ready)
                    begin
                        if(rounded_affine) begin
                            // Cascade16 exposes the high-array result repacked in output
                            // lanes 0..15. Its upper mask is intentionally always zero.
                            if(out_last!=(input_frame+1==count && (affine_out_half || input_mask[31:16]==0)) || out_mask[31:16]!=0 ||
                               out_mask[15:0]!=(affine_out_half ? input_mask[31:16] : input_mask[15:0])) begin
                                fault<=6;
                                state<=FAIL;
                            end else begin
                                for(j=0;j<16;j=j+1) begin
                                    last_data[(int'(affine_out_half)*16+j)*27 +: 27]<=out_data[j*27 +: 27];
                                    if(out_mask[j]&&out_data[j*27 +: 27]!=0) nonzero<=1;
                                end
                                if(affine_out_half||input_mask[31:16]==0) state<=AFFINE_WRITE;
                                else affine_out_half<=1;
                            end
                        end else begin
                        output_frame<=output_frame+1'b1;
                        if(thresholding) soft_pending<=0;
                        if(scalar_template) begin
                            scalar<={{37{out_data[26]}},out_data[26:0]};
                            nonzero<=out_data[26:0]!=0;
                        end
                        if(kind==0&&!scalar_template) scratch_masks[output_frame]<=out_mask;
                        if(kind==0&&!normalize&&!scalar_template)
                        begin
                            for(j=0;j<32;j=j+1) if(out_mask[j]&&store_data[j*27 +: 27]!=0) nonzero<=1;
                        end
                        else if(out_last&&!scalar_template)
                        begin
                            if(!normalize) scratch_masks[0]<=final_mask;
                        end
                        end
                    end
                    // The affine result has to be privately written before a normal
                    // terminal completion is accepted. A completion in RUN therefore
                    // indicates a malformed/aborted fabric transaction and wins.
                    if(rounded_affine&&fabric_done) begin
                        fault<=fabric_fault!=0 ? `CSR_KERNEL_FAULT_FABRIC : `CSR_KERNEL_FAULT_IDENTITY;
                        detail<=fabric_fault;
                        state<=FAIL;
                    end
                    if(fabric_done&&!rounded_affine)
                    begin
                        if(fabric_job!=job||fabric_tag!=tag||fabric_fmt!=fmt)
                        begin
                            fault<=6;
                            state<=FAIL;
                        end
                        else if(fabric_fault!=0)
                        begin
                            detail<=terminal_error!=0 ? 0 : fabric_fault;
                            fault<=terminal_error!=0 ? 4 : 3;
                            state<=FAIL;
                        end
                        else if(scalar_template) state<=RESPONSE;
                        else if(kind==2)
                        begin
                            scalar<=terminal_acc[63:0];
                            state<=RESPONSE;
                        end
                        else if(kind==1||normalize)
                        begin
                            // Terminal lane rounding reuses PE arithmetic and returns
                            // only after its range flags have been checked.
                            last_data<=0;
                            for(j=0;j<32;j=j+1)
                                if(normalize ? scratch_masks[output_frame-1'b1][j] : final_mask[j])
                                begin
                                    last_data[j*27 +: 27]<=out_data[j*27 +: 27];
                                    if(out_data[j*27 +: 27]!=0) nonzero<=1;
                                end
                            state<=LAST_WRITE;
                        end
                        else state<=INVALIDATE;
                    end
                    if(out_valid&&out_ready&&store&&store_bad)
                    begin
                        fault<=4;
                        state<=FAIL;
                    end
                    // Any fault detected on this edge wins over successful done.
                    // A malformed affine reply wins over a simultaneous final
                    // cascade output, so an invalid private block cannot publish.
                    if(affine_reply_bad) begin
                        fault<=`CSR_KERNEL_FAULT_IDENTITY;
                        detail<=0;
                        state<=FAIL;
                    end                    if(!range_template&&!rounded_affine&&mem_rsp_valid&&mem_rsp_ready && (mem_rsp_tag!={9'b0,input_frame,(source_alias ? 1'b0 : mem_rsp_tag[0])} ||
                    mem_rsp_mask!=(source_alias ? (needs_a|needs_b)&input_mask :
                    (mem_rsp_tag[0] ? needs_b : needs_a)&input_mask) ||
                    (mem_rsp_tag[0] ? b_valid : a_valid)))
                    begin
                        fault<=6;
                        state<=FAIL;
                    end
                end
                AFFINE_WRITE: if(mem_ready)
                begin
                    scratch_masks[input_frame]<=input_mask;
                    if(input_frame+1==count) state<=AFFINE_WAIT;
                    else begin
                        input_frame<=input_frame+1'b1;
                        read_phase<=0;
                        a_valid<=0;
                        b_valid<=affine_scalar_y;
                        c_valid<=0;
                        affine_half<=0;
                        affine_input_done<=0;
                        affine_out_half<=0;
                        last_data<=0;
                        state<=RUN;
                    end
                end
                AFFINE_WAIT: if(fabric_done)
                begin
                    if(fabric_fault!=0) begin
                        detail<=fabric_fault;
                        fault<=`CSR_KERNEL_FAULT_FABRIC;
                        state<=FAIL;
                    end else if(fabric_job!=job||fabric_tag!=tag||fabric_fmt!=fmt) begin
                        detail<=0;
                        fault<=`CSR_KERNEL_FAULT_IDENTITY;
                        state<=FAIL;
                    end else state<=INVALIDATE;
                end
                LAST_WRITE: if(mem_ready)
                begin
                    if(normalize&&input_frame<count) state<=LAUNCH;
                    else state<=INVALIDATE;
                end
                INVALIDATE:
                begin
                    // Source reads are complete. Invalidate the full prior public
                    // result before either legacy copying or resident ownership swaps.
                    for(j=0;j<32;j=j+1) if(j<clear_count)
                        valid_masks[int'(dst)+(descriptor[2]&&kind==0 ? j : 0)]<=0;
                    remap_frame<=0;
                    state<=output_count==0 ? RESPONSE : resident_remap ? REMAP : COPY_READ;
                end
                REMAP:
                begin
                    // One block ownership swap per clock preserves the 512-block
                    // permutation without a 32-way mapping crossbar. Busy stays
                    // asserted and validity remains clear until PUBLISH.
                    public_map[int'(dst)+(descriptor[2]&&kind==0 ? remap_frame : 0)]<=scratch_handle[remap_frame];
                    public_map_valid[int'(dst)+(descriptor[2]&&kind==0 ? remap_frame : 0)]<=1;
                    scratch_handle[remap_frame]<=map_lookup_physical;
                    if(remap_frame+1==output_count) state<=PUBLISH;
                    else remap_frame<=remap_frame+1'b1;
                end
                COPY_READ: if(mem_ready) state<=COPY_WAIT;
                COPY_WAIT: if(mem_rsp_valid)
                begin
                    if(mem_rsp_tag!=16'hc000+copy_frame||mem_rsp_mask!=scratch_masks[copy_frame])
                    begin
                        fault<=6;
                        state<=FAIL;
                    end
                    else
                    begin
                        copy_buffer<=mem_rsp_data;
                        state<=COPY_WRITE;
                    end
                end
                COPY_WRITE: if(mem_ready)
                begin
                    if(copy_frame+1==output_count) state<=PUBLISH;
                    else
                    begin
                        copy_frame<=copy_frame+1'b1;
                        state<=COPY_READ;
                    end
                end
                PUBLISH:
                begin
                    if(kind==0&&!descriptor[2]) valid_masks[dst]<=final_mask;
                    else for(j=0;j<32;j=j+1) if(j<output_count) valid_masks[int'(dst)+(descriptor[2]&&kind==0 ? j : 0)]<=scratch_masks[j];
                    state<=RESPONSE;
                end
                FAIL:
                begin
                    if(writes_vector) for(j=0;j<32;j=j+1) if(j<clear_count&&int'(dst)+(descriptor[2]&&kind==0 ? j : 0)<480)
                    valid_masks[int'(dst)+(descriptor[2]&&kind==0 ? j : 0)]<=0;
                    state<=RESPONSE;
                end
                RESPONSE: if(rsp_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
