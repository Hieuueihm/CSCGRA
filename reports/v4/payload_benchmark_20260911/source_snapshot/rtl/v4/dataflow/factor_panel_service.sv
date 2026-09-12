`include "kernel_interface.vh"
`include "stream_interface.vh"
// Bounded private-factor panel worker.  Four tagged row slots overlap store
// reads, PE frames, and rank-one write acknowledgements without a response FIFO.
module factor_panel_service #(
    parameter NARROW_PANEL_MAPPING=1'b1,
    parameter PROJECT_DOT_SPLIT_ENABLE=1'b1,
    parameter [10:0] PROJECT_DOT_SPLIT_MIN_ROWS=11'd24
) (
input wire clk,rst,cancel,
input wire req_valid,output wire req_ready,input wire [5:0] req_op,
input wire [2047:0] req_contexts,input wire [8:0] req_src_a,req_src_b,req_dst,input wire [26:0] req_scalar_a,
input wire [7:0] req_rows,input wire [10:0] req_support_length,req_aux_length,req_length,req_index,
input wire [7:0] req_flags,input wire req_matrix_dense,input wire [127:0] req_key,
input wire [31:0] req_generation,input wire [15:0] req_job,req_tag,input wire [7:0] req_fmt,
input wire matrix_valid,input wire [7:0] matrix_rows,input wire [10:0] matrix_cols,
input wire [127:0] matrix_key,input wire [31:0] matrix_generation,input wire [15:0] matrix_job,input wire [7:0] matrix_fmt,
output wire vec_valid,input wire vec_ready,output reg [8:0] vec_block,
output reg [31:0] vec_mask,output wire [15:0] vec_tag,input wire vec_rsp_valid,
output wire vec_rsp_ready,input wire [863:0] vec_rsp_data,input wire [31:0] vec_rsp_mask,
input wire [15:0] vec_rsp_tag,input wire [3:0] vec_rsp_fault,
output wire candidate_valid,input wire candidate_ready,output reg [4:0] candidate_block,output reg [31:0] candidate_mask,output reg [863:0] candidate_data,output wire rsp_valid,input wire rsp_ready,output reg [3:0] rsp_fault,rsp_detail,output reg [10:0] rsp_count,rsp_length,output wire [63:0] rsp_data,output reg rsp_nonzero,output reg [15:0] rsp_job,rsp_tag,output reg [7:0] rsp_fmt,
output wire panel_req_valid,input wire panel_req_ready,output wire panel_req_write,output reg [31:0] panel_req_mask,output reg [287:0] panel_req_addr,output reg [863:0] panel_req_data,output wire [7:0] panel_req_rows,output wire [10:0] panel_req_cols,output wire [127:0] panel_req_key,output wire [31:0] panel_req_generation,output wire [15:0] panel_req_job,panel_req_tag,output wire [7:0] panel_req_fmt,output wire panel_invalidate,input wire panel_rsp_valid,output wire panel_rsp_ready,input wire panel_rsp_write,input wire [863:0] panel_rsp_data,input wire [31:0] panel_rsp_mask,panel_rsp_generation,input wire [15:0] panel_rsp_job,panel_rsp_tag,input wire [7:0] panel_rsp_fmt,input wire [3:0] panel_rsp_fault,
output wire fabric_cfg_valid,input wire fabric_cfg_ready,output wire [2047:0] fabric_cfg_contexts,input wire [3:0] fabric_cfg_fault,input wire fabric_cfg_loaded,output wire fabric_cmd_valid,input wire fabric_cmd_ready,output wire [15:0] fabric_cmd_job,fabric_cmd_tag,output wire [7:0] fabric_cmd_fmt,output wire [1:0] fabric_cmd_terminal,output wire [5:0] fabric_cmd_shift,output wire [31:0] fabric_cmd_terminal_mask,output wire [1:0] fabric_cmd_flow,output wire fabric_in_valid,input wire fabric_in_ready,output reg [863:0] fabric_in_a,fabric_in_b,output reg [31:0] fabric_in_mask,output wire fabric_in_last,input wire fabric_out_valid,output wire fabric_out_ready,input wire [863:0] fabric_out_data,input wire [2047:0] fabric_out_acc,input wire [31:0] fabric_out_mask,input wire [127:0] fabric_out_faults,input wire fabric_out_last,input wire fabric_done_valid,output wire fabric_done_ready,input wire [3:0] fabric_done_fault,input wire [15:0] fabric_done_job,fabric_done_tag,input wire [7:0] fabric_done_fmt,input wire [2047:0] terminal_acc,input wire [3:0] terminal_error
);
localparam [5:0] IDLE=0,CHECK=1,A_REQ=2,A_WAIT=3,B_REQ=4,B_WAIT=5,CONFIG=6,CONFIG_WAIT=7,LAUNCH=8,RUN=9,CANDIDATE=10,FAILED=11,DONE=12;
localparam [2:0] EMPTY=0,READ_PENDING=1,READY=2,PE_PENDING=3,RESULT=4,WRITE_PENDING=5;
localparam [1:0] PROJECT_DOT=0,PROJECT_SCALE=1,PROJECT_RANK=2;
localparam [63:0] PROJECT_DOT_CONTEXT=`CSR_KERNEL_PROJECT_DOT_CONTEXT;
localparam [63:0] PROJECT_SCALE_CONTEXT=`CSR_KERNEL_PROJECT_SCALE_CONTEXT;
localparam [63:0] PROJECT_RANK_CONTEXT=`CSR_KERNEL_PROJECT_RANK_CONTEXT;
localparam [63:0] PROJECT_PADDING_CONTEXT=`CSR_KERNEL_PROJECT_PADDING_CONTEXT;
reg [5:0] state,operation;
reg [2047:0] contexts;
reg [8:0] src_a,src_b,dst;
reg [26:0] scalar_a;
reg [7:0] rows,flags;
reg dense;
reg [10:0] support_length,row_start,row_count,col_start,col_position;
reg [127:0] key;
reg [31:0] generation;
reg [15:0] job,tag;
reg [7:0] fmt;
reg [1:0] source_bundle;
reg [26:0] a_cache[0:127];
reg [26:0] b_cache[0:95];
reg [2:0] slot_state[0:3];
reg [10:0] slot_row[0:3];
reg [31:0] slot_mask[0:3],slot_lane_mask[0:3];
reg [863:0] slot_factor[0:3],slot_result[0:3];
// Per-panel monotonic issue/feed/retire/ack counts; low bits are the slot id.
reg [10:0] issued_count,feed_count,retired_count,acked_count;
reg [1:0] project_phase;
reg [63:0] raw_acc;
reg tail_nonzero_seen;
reg scale_fed;
reg fabric_fault_seen,mat_context_bad,rank_context_bad,project_context_bad,range_context_bad,mat_output_nonzero;
reg [63:0] context_word;
reg request_valid,request_write,request_slot_valid;
reg [1:0] request_slot,feed_slot,response_slot;
reg feed_slot_valid,response_found,response_is_write;
reg req_hold_valid,req_hold_write;
reg [1:0] req_hold_slot;
integer comb_lane,comb_bank,comb_row,comb_col,comb_relative,comb_slot;
integer seq_lane,seq_bank,seq_row,seq_col,seq_slot;
integer lane,bank,row_value,col_value,slot_index;
wire active=!rst&&!cancel;
wire matvec=operation==`CSR_KERNEL_OP_FACTOR_MATVEC;
wire rank1=operation==`CSR_KERNEL_OP_FACTOR_RANK1;
wire project=operation==`CSR_KERNEL_OP_FACTOR_PROJECT_UPDATE;
wire range_template=operation==`CSR_KERNEL_OP_FACTOR_RANGE_TEMPLATE;
// FACTOR_ENERGY_TAP reuses the bounded range slots but drives retained factor
// data into both MAC operands.  It has no public-vector provider transaction.
wire factor_energy_tap=operation==`CSR_KERNEL_OP_FACTOR_ENERGY_TAP;
wire range_operation=range_template||factor_energy_tap;
wire range_row=flags[0],range_head_only=flags[1],range_patch_first=flags[2];
wire dot_phase=matvec||(project&&project_phase==PROJECT_DOT);
wire scale_phase=project&&project_phase==PROJECT_SCALE;
wire rank_phase=rank1||(project&&project_phase==PROJECT_RANK);
wire [10:0] column_count=support_length-col_start,remaining_columns=support_length-col_position;
wire [10:0] panel_width=remaining_columns>32 ? 11'd32 : remaining_columns,rank_width=remaining_columns>16 ? 11'd16 : remaining_columns;
// PROJECT_DOT alone may split a 9..16-column tail into an eight-column
// narrow panel followed by the existing <=8 narrow panel.  SCALE retains the
// normal 32-column width and RANK retains its normal 16-column width.
wire project_dot_split=PROJECT_DOT_SPLIT_ENABLE&&NARROW_PANEL_MAPPING&&
                       project&&project_phase==PROJECT_DOT&&
                       remaining_columns>=11'd9&&remaining_columns<=11'd16&&
                       row_count>=PROJECT_DOT_SPLIT_MIN_ROWS;
wire [10:0] dot_width=project_dot_split ? 11'd8 : panel_width;
wire [10:0] current_width=dot_phase ? dot_width : rank_width;
// A narrow trailing panel keeps the existing wide per-row schedule intact and
// only changes the internal frame geometry.  It deliberately has no public
// ABI, fabric-port, bank, PE or arithmetic change.
wire narrow_dot=NARROW_PANEL_MAPPING&&dot_phase&&dot_width<=8;
wire narrow_rank=NARROW_PANEL_MAPPING&&rank_phase&&rank_width<=8;
wire narrow_phase=narrow_dot||narrow_rank;
// DOT frames cover four rows spaced eight apart in each 32-row block; RANK
// covers two rows in each 16-row block.  A partially populated block still
// has one frame per legal residue, so this is intentionally not ceil(L/8).
wire [10:0] narrow_dot_frames=((row_count>>5)<<3)+((row_count[4:0]>8)?11'd8:{6'd0,row_count[4:0]});
wire [10:0] narrow_rank_frames=((row_count>>4)<<3)+((row_count[3:0]>8)?11'd8:{7'd0,row_count[3:0]});
wire [10:0] range_frame_count=(row_count+11'd31)>>5;
wire [10:0] range_source_blocks=({6'd0,row_start[4:0]}+row_count+11'd31)>>5;
wire [10:0] phase_frame_count=range_operation ? range_frame_count : (narrow_dot ? narrow_dot_frames : (narrow_rank ? narrow_rank_frames : row_count));
wire range_slots_done=issued_count==range_frame_count&&feed_count==range_frame_count&&retired_count==range_frame_count;
wire [31:0] rank_panel_mask=tail(rank_width,0);
wire [31:0] expected_dot_frame_mask=narrow_dot ? narrow_dot_mask(retired_count,dot_width,row_count) : tail(dot_width,0);
wire [31:0] expected_rank_frame_mask=narrow_rank ? narrow_rank_mask(retired_count,rank_width,row_count) : rank_panel_mask;
wire [11:0] row_end={1'b0,row_start}+{1'b0,row_count};
wire [11:0] a_span={3'b0,src_a}+(({1'b0,row_count}+12'd31)>>5),b_span={3'b0,src_b}+(({1'b0,column_count}+12'd31)>>5),dst_span={3'b0,dst}+(({1'b0,column_count}+12'd31)>>5);
wire [11:0] range_a_span={3'b0,src_a}+(({1'b0,row_start}+{1'b0,row_count}+12'd31)>>5);
wire [11:0] range_axis_limit=range_row ? {4'd0,support_length} : {4'd0,rows};
wire [11:0] range_axis_end={1'b0,row_start}+{1'b0,row_count};
wire metadata_bad=!matrix_valid||matrix_rows!=rows||matrix_cols!=support_length||matrix_key!=key||matrix_generation!=generation||matrix_job!=job||matrix_fmt!=fmt;
wire vector_a=state==A_REQ||state==A_WAIT;
wire [10:0] source_length=vector_a ? row_count : column_count;
wire [15:0] source_tag=tag+(vector_a ? {14'd0,source_bundle} : 16'd4+source_bundle);
wire [31:0] source_mask=range_template&&vector_a ? range_source_mask(row_start[4:0],row_count,source_bundle) : tail(source_length,source_bundle);
wire mat_slots_done=issued_count==phase_frame_count&&feed_count==phase_frame_count&&retired_count==phase_frame_count;
wire rank_slots_done=issued_count==phase_frame_count&&feed_count==phase_frame_count&&retired_count==phase_frame_count&&acked_count==phase_frame_count;
wire scale_feed_valid=scale_phase&&!scale_fed;
// Kept as a named observation point for the standalone store mock.  Reads
// use the next issued row; writes use the result-owning slot row.
wire [10:0] row_position=request_write ? slot_row[request_slot] : issued_count;
wire [10:0] request_row=request_write ? slot_row[request_slot] : issued_count;
function automatic [31:0] tail(input [10:0] size,input [1:0] block);
integer n;
begin
    tail=0;
    for(n=0;n<32;n=n+1)if(int'(block)*32+n<int'(size))tail[n]=1'b1;
end
endfunction
function automatic [31:0] range_source_mask(input [4:0] offset,input [10:0] size,input [1:0] block);
integer n,relative_lane;
begin
    range_source_mask=0;
    for(n=0;n<32;n=n+1)begin
        relative_lane=int'(block)*32+n-int'(offset);
        if(relative_lane>=0&&relative_lane<int'(size))range_source_mask[n]=1'b1;
    end
end
endfunction
function automatic [31:0] narrow_dot_mask(input [10:0] frame,input [10:0] width,input [10:0] length);
integer n,relative_row;
begin
    narrow_dot_mask=0;
    for(n=0;n<32;n=n+1)begin
        relative_row=(int'(frame>>3)*32)+int'(frame[2:0])+8*(n&3);
        if(n<int'(width)*4&&relative_row<int'(length))narrow_dot_mask[n]=1'b1;
    end
end
endfunction
function automatic [31:0] narrow_rank_mask(input [10:0] frame,input [10:0] width,input [10:0] length);
integer n,relative_row;
begin
    narrow_rank_mask=0;
    for(n=0;n<16;n=n+1)begin
        relative_row=(int'(frame>>3)*16)+int'(frame[2:0])+8*(n&1);
        if(n<int'(width)*2&&relative_row<int'(length))narrow_rank_mask[n]=1'b1;
    end
end
endfunction
function automatic [31:0] narrow_dot_terminal_mask(input [10:0] width);
integer n;
begin
    narrow_dot_terminal_mask=0;
    for(n=0;n<8;n=n+1)if(n<int'(width))narrow_dot_terminal_mask[n*4]=1'b1;
end
endfunction
function automatic [3:0] first_fault(input [127:0] faults);
integer n;
begin
    first_fault=0;
    for(n=0;n<32;n=n+1)if(first_fault==0&&faults[n*4+:4]!=0)first_fault=faults[n*4+:4];
end
endfunction
task automatic fail(input [3:0] code,input [3:0] detail);
begin
    rsp_fault<=code;
    rsp_detail<=detail;
    rsp_count<=0;
    rsp_length<=0;
    rsp_nonzero<=0;
    raw_acc<=0;
    tail_nonzero_seen<=0;
    state<=FAILED;
end
endtask
assign req_ready=active&&state==IDLE;
assign vec_valid=active&&(state==A_REQ||state==B_REQ);
assign vec_tag=source_tag;
assign vec_rsp_ready=active&&(state==A_WAIT||state==B_WAIT);
assign candidate_valid=active&&state==CANDIDATE;
assign rsp_valid=active&&state==DONE;
assign rsp_data=range_operation ? raw_acc : 0;
assign panel_req_valid=active&&state==RUN&&request_valid;
assign panel_req_write=request_write;
assign panel_req_rows=rows;
assign panel_req_cols=support_length;
assign panel_req_key=key;
assign panel_req_generation=generation;
assign panel_req_job=job;
assign panel_req_tag=tag+(request_write?16'h0800:16'h0400)+request_row;
assign panel_req_fmt=fmt;
// Responses are consumed only by an active bounded slot.  The service bridge
// independently rejects any stale legacy response before it reaches here.
assign panel_rsp_ready=active&&state==RUN;
assign panel_invalidate=cancel||(active&&state==FAILED);
assign fabric_cfg_valid=active&&state==CONFIG;
assign fabric_cfg_contexts=project ? (dot_phase ? {32{PROJECT_DOT_CONTEXT}} : scale_phase ? {32{PROJECT_SCALE_CONTEXT}} : {{16{PROJECT_RANK_CONTEXT}},{16{PROJECT_SCALE_CONTEXT}}}) : contexts;
assign fabric_cmd_valid=active&&state==LAUNCH;
assign fabric_cmd_job=job;
assign fabric_cmd_tag=tag;
assign fabric_cmd_fmt=fmt;
// Narrow DOT reduces the four residue lanes for each column through the
// existing registered R4 terminal, then rounds only its leader.  The wide
// path retains its original independent per-lane terminal-round command.
assign fabric_cmd_terminal=range_operation?2'd2:(narrow_dot?2'd1:(dot_phase?2'd3:0));
assign fabric_cmd_shift=dot_phase?6'd22:0;
assign fabric_cmd_terminal_mask=range_operation?tail(row_count,0):(narrow_dot?narrow_dot_terminal_mask(dot_width):(dot_phase?tail(dot_width,0):0));
assign fabric_cmd_flow=rank_phase?2'd1:0;
assign fabric_in_valid=active&&state==RUN&&(feed_slot_valid||scale_feed_valid);
assign fabric_in_last=scale_phase ? 1'b1 : feed_count+1'b1==phase_frame_count;
assign fabric_out_ready=active&&state==RUN&&(range_operation||dot_phase||scale_phase||(rank_phase&&slot_state[retired_count[1:0]]==PE_PENDING));
assign fabric_done_ready=active&&state==RUN&&(range_operation ? 1'b1 : (scale_phase?scale_fed:(dot_phase?mat_slots_done:rank_slots_done)));
always @* begin
    request_valid=0;
    request_write=0;
    request_slot=0;
    request_slot_valid=0;
    if(req_hold_valid) begin
        request_valid=1;
        request_write=req_hold_write;
        request_slot=req_hold_slot;
        request_slot_valid=1;
    end
    else begin
        if(rank_phase)for(comb_slot=0;comb_slot<4;comb_slot=comb_slot+1)if(!request_slot_valid&&slot_state[comb_slot]==RESULT)begin
            request_valid=1;
            request_write=1;
            request_slot=comb_slot[1:0];
            request_slot_valid=1;
        end
        if(!scale_phase&&!request_slot_valid&&issued_count<phase_frame_count&&slot_state[issued_count[1:0]]==EMPTY)begin
            request_valid=1;
            request_slot=issued_count[1:0];
            request_slot_valid=1;
        end
    end
    feed_slot=feed_count[1:0];
    feed_slot_valid=feed_count<phase_frame_count&&slot_state[feed_count[1:0]]==READY;
    response_found=0;
    response_slot=0;
    response_is_write=0;
    for(comb_slot=0;comb_slot<4;comb_slot=comb_slot+1)begin
        if(!response_found&&slot_state[comb_slot]==READ_PENDING&&panel_rsp_tag==tag+16'h0400+slot_row[comb_slot])begin
            response_found=1;
            response_slot=comb_slot[1:0];
        end
        if(!response_found&&slot_state[comb_slot]==WRITE_PENDING&&panel_rsp_tag==tag+16'h0800+slot_row[comb_slot])begin
            response_found=1;
            response_slot=comb_slot[1:0];
            response_is_write=1;
        end
    end
end
always @* begin
    panel_req_mask=0;
    panel_req_addr=0;
    panel_req_data=0;
    fabric_in_a=0;
    fabric_in_b=0;
    fabric_in_mask=0;
    mat_context_bad=0;
    rank_context_bad=0;
    project_context_bad=0;
    range_context_bad=0;
    mat_output_nonzero=0;
    context_word=0;
    for(comb_lane=0;comb_lane<32;comb_lane=comb_lane+1)begin
        context_word=contexts[comb_lane*64+:64];
        if(context_word[`CSR_STREAM_CONTEXT_RESERVED_LSB +: `CSR_STREAM_CONTEXT_RESERVED_W]!=0)begin
            mat_context_bad=1;
            rank_context_bad=1;
        end
        if(context_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_STREAM_OP_MAC||!context_word[`CSR_STREAM_CONTEXT_MODE_LSB]||context_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]!=`CSR_STREAM_SRC_A||context_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]!=`CSR_STREAM_SRC_B)mat_context_bad=1;
        if(comb_lane<16)begin
            if(context_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_STREAM_OP_MUL||!context_word[`CSR_STREAM_CONTEXT_MODE_LSB]||context_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]!=`CSR_STREAM_SRC_A||context_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]!=`CSR_STREAM_SRC_B)rank_context_bad=1;
        end
        else if(context_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_STREAM_OP_SUB||!context_word[`CSR_STREAM_CONTEXT_MODE_LSB]||context_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]!=`CSR_STREAM_SRC_A||context_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]!=`CSR_STREAM_SRC_B)rank_context_bad=1;
        if(range_operation&&context_word!=64'd297)range_context_bad=1;
        if(request_valid)begin
            if(range_operation)begin
                comb_relative=int'(request_row)*32+comb_lane;
                if(comb_relative<int'(row_count))begin
                    if(range_row)begin
                        comb_row=int'(col_start);
                        comb_col=int'(row_start)+comb_relative;
                    end
                    else begin
                        comb_row=int'(row_start)+comb_relative;
                        comb_col=int'(col_start);
                    end
                    comb_bank=(comb_row+comb_col)&31;
                    panel_req_mask[comb_bank]=1;
                    panel_req_addr[comb_bank*9+:9]=9'(3*comb_row+(comb_col>>5));
                end
            end
            else if(narrow_dot)begin
                comb_relative=(int'(request_row>>3)*32)+int'(request_row[2:0])+8*(comb_lane&3);
                comb_row=int'(row_start)+comb_relative;
                comb_col=int'(col_position)+(comb_lane>>2);
                if(comb_lane<int'(dot_width)*4&&comb_relative<int'(row_count))begin
                    comb_bank=(comb_row+comb_col)&31;
                    panel_req_mask[comb_bank]=1;
                    panel_req_addr[comb_bank*9+:9]=9'(3*comb_row+(comb_col>>5));
                end
            end
            else if(narrow_rank&&comb_lane<16)begin
                comb_relative=(int'(request_row>>3)*16)+int'(request_row[2:0])+8*(comb_lane&1);
                comb_row=int'(row_start)+comb_relative;
                comb_col=int'(col_position)+(comb_lane>>1);
                if(comb_lane<int'(rank_width)*2&&comb_relative<int'(row_count))begin
                    comb_bank=(comb_row+comb_col)&31;
                    panel_req_mask[comb_bank]=1;
                    panel_req_addr[comb_bank*9+:9]=9'(3*comb_row+(comb_col>>5));
                    if(request_write)panel_req_data[comb_bank*27+:27]=slot_result[request_slot][comb_lane*27+:27];
                end
            end
            else if(comb_lane<int'(current_width))begin
                comb_row=int'(row_start)+int'(request_row);
                comb_col=int'(col_position)+comb_lane;
                comb_bank=(comb_row+comb_col)&31;
                panel_req_mask[comb_bank]=1;
                panel_req_addr[comb_bank*9+:9]=9'(3*comb_row+(comb_col>>5));
                if(request_write)panel_req_data[comb_bank*27+:27]=slot_result[request_slot][comb_lane*27+:27];
            end
        end
        if(project&&context_word!=(comb_lane==0 ? PROJECT_DOT_CONTEXT : comb_lane==1 ? PROJECT_SCALE_CONTEXT : comb_lane==2 ? PROJECT_RANK_CONTEXT : PROJECT_PADDING_CONTEXT))project_context_bad=1;
        if(matvec&&comb_lane<int'(dot_width))if(narrow_dot)mat_output_nonzero=mat_output_nonzero||(fabric_out_data[(comb_lane*4)*27+:27]!=0);
        else mat_output_nonzero=mat_output_nonzero||(fabric_out_data[comb_lane*27+:27]!=0);
        if(feed_slot_valid&&range_operation&&comb_lane<32)begin
            comb_relative=int'(slot_row[feed_slot])*32+comb_lane;
            if(comb_relative<int'(row_count))begin
                fabric_in_a[comb_lane*27+:27]=(range_template&&range_patch_first&&comb_relative==0) ? scalar_a : slot_factor[feed_slot][comb_lane*27+:27];
                fabric_in_b[comb_lane*27+:27]=factor_energy_tap ? slot_factor[feed_slot][comb_lane*27+:27] : a_cache[comb_relative];
                fabric_in_mask[comb_lane]=1;
            end
        end
        else if(feed_slot_valid&&dot_phase)begin
            if(narrow_dot)begin
                comb_relative=(int'(slot_row[feed_slot]>>3)*32)+int'(slot_row[feed_slot][2:0])+8*(comb_lane&3);
                if(comb_lane<int'(dot_width)*4&&comb_relative<int'(row_count))begin
                    fabric_in_a[comb_lane*27+:27]=slot_factor[feed_slot][comb_lane*27+:27];
                    fabric_in_b[comb_lane*27+:27]=a_cache[comb_relative];
                    fabric_in_mask[comb_lane]=1;
                end
            end
            else if(comb_lane<int'(current_width))begin
                fabric_in_a[comb_lane*27+:27]=slot_factor[feed_slot][comb_lane*27+:27];
                fabric_in_b[comb_lane*27+:27]=a_cache[slot_row[feed_slot]];
                fabric_in_mask[comb_lane]=1;
            end
        end
        else if(feed_slot_valid&&rank_phase&&comb_lane<16)begin
            if(narrow_rank)begin
                comb_relative=(int'(slot_row[feed_slot]>>3)*16)+int'(slot_row[feed_slot][2:0])+8*(comb_lane&1);
                if(comb_lane<int'(rank_width)*2&&comb_relative<int'(row_count))begin
                    fabric_in_a[comb_lane*27+:27]=a_cache[comb_relative];
                    fabric_in_b[comb_lane*27+:27]=b_cache[col_position-col_start+(comb_lane>>1)];
                    fabric_in_a[(16+comb_lane)*27+:27]=slot_factor[feed_slot][comb_lane*27+:27];
                    fabric_in_mask[comb_lane]=1;
                    fabric_in_mask[16+comb_lane]=1;
                end
            end
            else if(comb_lane<int'(rank_width))begin
                fabric_in_a[comb_lane*27+:27]=a_cache[slot_row[feed_slot]];
                fabric_in_b[comb_lane*27+:27]=b_cache[col_position-col_start+comb_lane];
                fabric_in_a[(16+comb_lane)*27+:27]=slot_factor[feed_slot][comb_lane*27+:27];
                fabric_in_mask[comb_lane]=1;
                fabric_in_mask[16+comb_lane]=1;
            end
        end
        if(scale_feed_valid&&comb_lane<int'(panel_width))begin
            fabric_in_a[comb_lane*27+:27]=b_cache[col_position-col_start+comb_lane];
            fabric_in_b[comb_lane*27+:27]=scalar_a;
            fabric_in_mask[comb_lane]=1;
        end
    end
end
always @(posedge clk)begin
    if(!active)begin
        state<=IDLE;
        operation<=0;
        contexts<=0;
        src_a<=0;
        src_b<=0;
        dst<=0;
        scalar_a<=0;
        rows<=0;
        flags<=0;
        dense<=0;
        support_length<=0;
        row_start<=0;
        row_count<=0;
        col_start<=0;
        col_position<=0;
        key<=0;
        generation<=0;
        job<=0;
        tag<=0;
        fmt<=0;
        source_bundle<=0;
        issued_count<=0;
        feed_count<=0;
        retired_count<=0;
        acked_count<=0;
        project_phase<=PROJECT_DOT;
        scale_fed<=0;
        req_hold_valid<=0;
        req_hold_write<=0;
        req_hold_slot<=0;
        fabric_fault_seen<=0;
        vec_block<=0;
        vec_mask<=0;
        candidate_block<=0;
        candidate_mask<=0;
        candidate_data<=0;
        rsp_fault<=0;
        rsp_detail<=0;
        rsp_count<=0;
        rsp_length<=0;
        rsp_nonzero<=0;
        rsp_job<=0;
        rsp_tag<=0;
        rsp_fmt<=0;
        raw_acc<=0;
        tail_nonzero_seen<=0;
        for(slot_index=0;slot_index<4;slot_index=slot_index+1)begin
            slot_state[slot_index]<=EMPTY;
            slot_row[slot_index]<=0;
            slot_mask[slot_index]<=0;
            slot_lane_mask[slot_index]<=0;
            slot_factor[slot_index]<=0;
            slot_result[slot_index]<=0;
        end
    end
    else begin
        if(fabric_out_valid&&fabric_out_ready&&first_fault(fabric_out_faults)!=0)fabric_fault_seen<=1;
        if(state!=IDLE&&state!=CHECK&&state!=DONE&&state!=FAILED&&metadata_bad)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
        else case(state)
            IDLE:if(req_valid&&req_ready)begin
                operation<=req_op;
                contexts<=req_contexts;
                src_a<=req_src_a;
                src_b<=req_src_b;
                dst<=req_dst;
                scalar_a<=req_scalar_a;
                rows<=req_rows;
                flags<=req_flags;
                dense<=req_matrix_dense;
                support_length<=req_support_length;
                row_start<=req_aux_length;
                row_count<=req_length;
                col_start<=req_index;
                col_position<=req_index;
                key<=req_key;
                generation<=req_generation;
                job<=req_job;
                tag<=req_tag;
                fmt<=req_fmt;
                source_bundle<=0;
                project_phase<=PROJECT_DOT;
                scale_fed<=0;
                fabric_fault_seen<=0;
                raw_acc<=0;
                tail_nonzero_seen<=0;
                rsp_fault<=0;
                rsp_detail<=0;
                rsp_count<=0;
                rsp_length<=0;
                rsp_nonzero<=0;
                rsp_job<=req_job;
                rsp_tag<=req_tag;
                rsp_fmt<=req_fmt;
                state<=CHECK;
            end
            CHECK:if(!dense||fmt!=1||!(matvec||rank1||project||range_template||factor_energy_tap)||
                ((matvec||rank1||project)&&flags!=0)||(matvec&&mat_context_bad)||(rank1&&rank_context_bad)||
                (project&&(project_context_bad||src_b!=0||dst!=0))||
                (range_template&&(flags[7:3]!=0||range_context_bad||src_b!=0||(!range_patch_first&&scalar_a!=0)))||
                (factor_energy_tap&&(flags[7:1]!=0||range_context_bad||src_a!=0||src_b!=0||scalar_a!=0)))
                fail(`CSR_KERNEL_FAULT_COMMAND,0);
            else if(rows==0||rows>128||support_length==0||support_length>96||row_count==0||
                (range_operation ? (col_start>=(range_row ? rows : support_length)||range_axis_end>range_axis_limit||
                                    (range_template&&range_a_span>480)) :
                 (row_start>=rows||row_end>rows||col_start>=support_length||a_span>480||(rank1&&b_span>480)||(matvec&&dst_span>480))))
                fail(`CSR_KERNEL_FAULT_RANGE,0);
            else if(metadata_bad)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
            else begin
                vec_block<=src_a+(range_template ? (row_start>>5) : 0);
                vec_mask<=range_template ? range_source_mask(row_start[4:0],row_count,0) : tail(row_count,0);
                source_bundle<=0;
                state<=factor_energy_tap ? CONFIG : A_REQ;
            end
            A_REQ:if(vec_ready)state<=A_WAIT;
            A_WAIT:if(vec_rsp_valid)begin
                if(vec_rsp_fault!=0)fail(`CSR_KERNEL_FAULT_OPERAND,vec_rsp_fault);
                else if(vec_rsp_mask!=source_mask||vec_rsp_tag!=source_tag)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else begin
                    if(range_template)begin
                        for(seq_lane=0;seq_lane<32;seq_lane=seq_lane+1)if(source_mask[seq_lane])
                            a_cache[int'(source_bundle)*32+seq_lane-int'(row_start[4:0])]<=vec_rsp_data[seq_lane*27+:27];
                        if(source_bundle+1>=range_source_blocks) state<=CONFIG;
                        else begin
                            source_bundle<=source_bundle+1'b1;
                            vec_block<=src_a+(row_start>>5)+source_bundle+1'b1;
                            vec_mask<=range_source_mask(row_start[4:0],row_count,source_bundle+1'b1);
                            state<=A_REQ;
                        end
                    end
                    else begin
                        for(lane=0;lane<32;lane=lane+1)if(source_mask[lane])a_cache[int'(source_bundle)*32+lane]<=vec_rsp_data[lane*27+:27];
                        if((int'(source_bundle)+1)*32>=int'(row_count))if(rank1)begin
                            source_bundle<=0;
                            vec_block<=src_b;
                            vec_mask<=tail(column_count,0);
                            state<=B_REQ;
                        end
                        else state<=CONFIG;
                        else begin
                            source_bundle<=source_bundle+1;
                            vec_block<=src_a+source_bundle+1;
                            vec_mask<=tail(row_count,source_bundle+1);
                            state<=A_REQ;
                        end
                    end
                end
            end
            B_REQ:if(vec_ready)state<=B_WAIT;
            B_WAIT:if(vec_rsp_valid)begin
                if(vec_rsp_fault!=0)fail(`CSR_KERNEL_FAULT_OPERAND,vec_rsp_fault);
                else if(vec_rsp_mask!=source_mask||vec_rsp_tag!=source_tag)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else begin
                    for(lane=0;lane<32;lane=lane+1)if(source_mask[lane])b_cache[int'(source_bundle)*32+lane]<=vec_rsp_data[lane*27+:27];
                    if((int'(source_bundle)+1)*32>=int'(column_count))state<=CONFIG;
                    else begin
                        source_bundle<=source_bundle+1;
                        vec_block<=src_b+source_bundle+1;
                        vec_mask<=tail(column_count,source_bundle+1);
                        state<=B_REQ;
                    end
                end
            end
            CONFIG:if(fabric_cfg_ready)state<=CONFIG_WAIT;
            CONFIG_WAIT:if(fabric_cfg_fault!=0||!fabric_cfg_loaded)fail(`CSR_KERNEL_FAULT_FABRIC,fabric_cfg_fault);
            else state<=LAUNCH;
            LAUNCH:if(fabric_cmd_ready)begin
                issued_count<=0;
                feed_count<=0;
                retired_count<=0;
                acked_count<=0;
                req_hold_valid<=0;
                fabric_fault_seen<=0;
                scale_fed<=0;
                for(slot_index=0;slot_index<4;slot_index=slot_index+1)begin
                    slot_state[slot_index]<=EMPTY;
                    slot_row[slot_index]<=0;
                    slot_mask[slot_index]<=0;
                    slot_lane_mask[slot_index]<=0;
                    slot_factor[slot_index]<=0;
                    slot_result[slot_index]<=0;
                end
                state<=RUN;
            end
            RUN:begin
                // Fault checks have priority over every normal transition in this clock.
                if(panel_rsp_valid&&panel_rsp_ready&&(!response_found||panel_rsp_fault!=0||panel_rsp_generation!=generation||panel_rsp_job!=job||panel_rsp_fmt!=fmt||panel_rsp_write!=response_is_write||panel_rsp_mask!=slot_mask[response_slot]))
                fail(panel_rsp_fault!=0?`CSR_KERNEL_FAULT_OPERAND:`CSR_KERNEL_FAULT_IDENTITY,panel_rsp_fault);
                else if(range_operation&&fabric_out_valid&&fabric_out_ready&&
                    (first_fault(fabric_out_faults)!=0||fabric_out_mask!=slot_lane_mask[retired_count[1:0]]||
                     fabric_out_last!=(retired_count+1'b1==range_frame_count)))
                fail(`CSR_KERNEL_FAULT_FABRIC,first_fault(fabric_out_faults));
                else if(range_operation&&fabric_done_valid&&fabric_done_ready&&(!range_slots_done||fabric_fault_seen||terminal_error!=0||fabric_done_fault!=0||fabric_done_job!=job||fabric_done_tag!=tag||fabric_done_fmt!=fmt))
                fail((fabric_fault_seen||terminal_error!=0||fabric_done_fault!=0)?`CSR_KERNEL_FAULT_FABRIC:`CSR_KERNEL_FAULT_IDENTITY,terminal_error!=0?terminal_error:fabric_done_fault);
                else if(rank_phase&&fabric_out_valid&&fabric_out_ready&&(first_fault(fabric_out_faults)!=0||fabric_out_mask[31:16]!=0||fabric_out_mask[15:0]!=(narrow_rank?expected_rank_frame_mask[15:0]:rank_panel_mask[15:0])||fabric_out_last!=(retired_count+1'b1==(narrow_rank?phase_frame_count:row_count))))
                fail(`CSR_KERNEL_FAULT_FABRIC,first_fault(fabric_out_faults));
                else if(dot_phase&&fabric_out_valid&&fabric_out_ready&&(first_fault(fabric_out_faults)!=0||fabric_out_mask!=(narrow_dot?expected_dot_frame_mask:tail(dot_width,0))||fabric_out_last!=(retired_count+1'b1==(narrow_dot?phase_frame_count:row_count))))
                fail(`CSR_KERNEL_FAULT_FABRIC,first_fault(fabric_out_faults));
                else if(scale_phase&&fabric_out_valid&&fabric_out_ready&&(first_fault(fabric_out_faults)!=0||fabric_out_mask!=tail(panel_width,0)||!fabric_out_last))
                fail(`CSR_KERNEL_FAULT_FABRIC,first_fault(fabric_out_faults));
                else if(fabric_done_valid&&fabric_done_ready&&(fabric_fault_seen||terminal_error!=0||fabric_done_fault!=0||fabric_done_job!=job||fabric_done_tag!=tag||fabric_done_fmt!=fmt))
                fail((fabric_fault_seen||terminal_error!=0||fabric_done_fault!=0)?`CSR_KERNEL_FAULT_FABRIC:`CSR_KERNEL_FAULT_IDENTITY,terminal_error!=0?terminal_error:fabric_done_fault);
                else begin
                    if(panel_rsp_valid&&panel_rsp_ready) begin
                        if(!response_is_write) begin
                            for(lane=0;lane<32;lane=lane+1) begin
                                if(range_operation)begin
                                    row_value=int'(slot_row[response_slot])*32+lane;
                                    if(range_row)begin
                                        seq_row=int'(col_start);
                                        seq_col=int'(row_start)+row_value;
                                    end
                                    else begin
                                        seq_row=int'(row_start)+row_value;
                                        seq_col=int'(col_start);
                                    end
                                    bank=(seq_row+seq_col)&31;
                                    if(row_value<int'(row_count))slot_factor[response_slot][lane*27+:27]<=panel_rsp_data[bank*27+:27];
                                    else slot_factor[response_slot][lane*27+:27]<=0;
                                    if(factor_energy_tap&&row_value!=0&&row_value<int'(row_count)&&panel_rsp_data[bank*27+:27]!=0)
                                        tail_nonzero_seen<=1;
                                end
                                else if(narrow_dot)begin
                                    row_value=int'(row_start)+(int'(slot_row[response_slot]>>3)*32)+int'(slot_row[response_slot][2:0])+8*(lane&3);
                                    col_value=int'(col_position)+(lane>>2);
                                    bank=(row_value+col_value)&31;
                                    if(lane<int'(dot_width)*4&&row_value<int'(row_end))slot_factor[response_slot][lane*27+:27]<=panel_rsp_data[bank*27+:27];
                                    else slot_factor[response_slot][lane*27+:27]<=0;
                                end
                                else if(narrow_rank&&lane<16)begin
                                    row_value=int'(row_start)+(int'(slot_row[response_slot]>>3)*16)+int'(slot_row[response_slot][2:0])+8*(lane&1);
                                    col_value=int'(col_position)+(lane>>1);
                                    bank=(row_value+col_value)&31;
                                    if(lane<int'(rank_width)*2&&row_value<int'(row_end))slot_factor[response_slot][lane*27+:27]<=panel_rsp_data[bank*27+:27];
                                    else slot_factor[response_slot][lane*27+:27]<=0;
                                end
                                else begin
                                    row_value=int'(row_start)+int'(slot_row[response_slot]);
                                    col_value=int'(col_position)+lane;
                                    bank=(row_value+col_value)&31;
                                    if(lane<int'(current_width))slot_factor[response_slot][lane*27+:27]<=panel_rsp_data[bank*27+:27];
                                    else slot_factor[response_slot][lane*27+:27]<=0;
                                end
                            end
                            slot_state[response_slot]<=READY;
                        end
                        else begin
                            slot_state[response_slot]<=EMPTY;
                            acked_count<=acked_count+1'b1;
                        end
                    end
                    if(panel_req_valid) begin
                        if(panel_req_ready) begin
                            req_hold_valid<=0;
                            if(request_write) slot_state[request_slot]<=WRITE_PENDING;
                            else begin
                                slot_state[request_slot]<=READ_PENDING;
                                slot_row[request_slot]<=issued_count;
                                slot_mask[request_slot]<=panel_req_mask;
                                slot_lane_mask[request_slot]<=range_operation ? tail(row_count,issued_count[1:0]) : panel_req_mask;
                                issued_count<=issued_count+1'b1;
                            end
                        end
                        else if(!req_hold_valid) begin
                            req_hold_valid<=1;
                            req_hold_write<=request_write;
                            req_hold_slot<=request_slot;
                        end
                    end
                    if(fabric_in_valid&&fabric_in_ready) begin
                        if(range_operation) begin
                            slot_state[feed_slot]<=PE_PENDING;
                            feed_count<=feed_count+1'b1;
                        end
                        else if(dot_phase) begin
                            slot_state[feed_slot]<=EMPTY;
                            feed_count<=feed_count+1'b1;
                        end
                        else if(rank_phase) begin
                            slot_state[feed_slot]<=PE_PENDING;
                            feed_count<=feed_count+1'b1;
                        end
                        else scale_fed<=1;
                    end
                    if(fabric_out_valid&&fabric_out_ready) begin
                        if(range_operation) retired_count<=retired_count+1'b1;
                        else if(dot_phase) retired_count<=retired_count+1'b1;
                        else if(scale_phase) begin
                            for(lane=0;lane<32;lane=lane+1)if(lane<int'(panel_width))b_cache[col_position-col_start+lane]<=fabric_out_data[lane*27+:27];
                        end
                        else if(rank_phase) begin
                            slot_result[retired_count[1:0]]<=fabric_out_data;
                            slot_state[retired_count[1:0]]<=RESULT;
                            retired_count<=retired_count+1'b1;
                        end
                    end
                    if(fabric_done_valid&&fabric_done_ready) begin
                        if(range_operation) begin
                            raw_acc<=terminal_acc[63:0];
                            retired_count<=0;
                            candidate_block<=0;
                            candidate_mask<=range_template&&range_head_only ? 32'd1 : slot_lane_mask[0];
                            candidate_data<=0;
                            for(seq_lane=0;seq_lane<32;seq_lane=seq_lane+1)
                                if((range_template&&range_head_only ? seq_lane==0 : slot_lane_mask[0][seq_lane]))
                                    candidate_data[seq_lane*27+:27]<=range_template&&range_patch_first&&seq_lane==0 ? scalar_a : slot_factor[0][seq_lane*27+:27];
                            state<=CANDIDATE;
                        end
                        else if(dot_phase) begin
                            if(project) begin
                                for(lane=0;lane<32;lane=lane+1)if(lane<int'(dot_width))begin
                                    if(narrow_dot)b_cache[col_position-col_start+lane]<=fabric_out_data[(lane*4)*27+:27];
                                    else b_cache[col_position-col_start+lane]<=fabric_out_data[lane*27+:27];
                                end
                                if(col_position+dot_width==support_length) begin
                                    project_phase<=PROJECT_SCALE;
                                    col_position<=col_start;
                                end
                                else col_position<=col_position+dot_width;
                                state<=CONFIG;
                            end
                            else begin
                                if(narrow_dot)begin
                                    candidate_data<=0;
                                    for(lane=0;lane<32;lane=lane+1)if(lane<int'(dot_width))candidate_data[lane*27+:27]<=fabric_out_data[(lane*4)*27+:27];
                                end
                                else candidate_data<=fabric_out_data;
                                candidate_mask<=tail(dot_width,0);
                                candidate_block<=(col_position-col_start)>>5;
                                rsp_nonzero<=rsp_nonzero||mat_output_nonzero;
                                state<=CANDIDATE;
                            end
                        end
                        else if(scale_phase) begin
                            if(col_position+panel_width==support_length) begin
                                project_phase<=PROJECT_RANK;
                                col_position<=col_start;
                            end
                            else col_position<=col_position+panel_width;
                            state<=CONFIG;
                        end
                        else if(col_position+rank_width==support_length) begin
                            rsp_count<=0;
                            rsp_length<=0;
                            state<=DONE;
                        end
                        else begin
                            col_position<=col_position+rank_width;
                            state<=CONFIG;
                        end
                    end
                end
            end
            CANDIDATE:if(candidate_ready)begin
                if(range_operation) begin
                    for(seq_lane=0;seq_lane<32;seq_lane=seq_lane+1)
                        if((range_template&&range_head_only ? seq_lane==0 : slot_lane_mask[retired_count[1:0]][seq_lane])&&
                           (range_template&&range_patch_first&&retired_count==0&&seq_lane==0 ? scalar_a : slot_factor[retired_count[1:0]][seq_lane*27+:27])!=0)
                            rsp_nonzero<=1;
                    if((range_template&&range_head_only)||retired_count+1==range_frame_count) begin
                        rsp_count<=factor_energy_tap ? (tail_nonzero_seen ? 11'd1 : 11'd0) :
                                   (range_head_only ? 11'd1 : row_count);
                        rsp_length<=range_template&&range_head_only ? 11'd1 : row_count;
                        state<=DONE;
                    end
                    else begin
                        retired_count<=retired_count+1'b1;
                        candidate_block<=retired_count+1'b1;
                        candidate_mask<=slot_lane_mask[(retired_count+1'b1)&2'b11];
                        candidate_data<=0;
                        for(seq_lane=0;seq_lane<32;seq_lane=seq_lane+1)
                            if(slot_lane_mask[(retired_count+1'b1)&2'b11][seq_lane])
                                candidate_data[seq_lane*27+:27]<=range_template&&range_patch_first&&retired_count+1'b1==0&&seq_lane==0 ? scalar_a : slot_factor[(retired_count+1'b1)&2'b11][seq_lane*27+:27];
                    end
                end
                else if(col_position+panel_width==support_length)begin
                    rsp_count<=column_count;
                    rsp_length<=column_count;
                    state<=DONE;
                end
                else begin
                    col_position<=col_position+panel_width;
                    state<=CONFIG;
                end
            end
            FAILED:state<=DONE;
            DONE:if(rsp_ready)state<=IDLE;
            default:fail(`CSR_KERNEL_FAULT_COMMAND,0);
        endcase
    end
end
endmodule
