`include "kernel_interface.vh"
// Generic full-bundle factor transport. Numeric phases remain loaded programs.
module factor_service #(parameter ENABLE_PANEL_BRIDGE=0) (
    input wire clk,rst,cancel,
    input wire req_valid,output wire req_ready,input wire [5:0] req_op,
    input wire [8:0] req_src_a,req_dst,
    input wire [7:0] req_rows,input wire [10:0] req_cols,req_length,req_index,req_aux_length,
    input wire [7:0] req_flags,input wire req_matrix_dense,
    input wire [127:0] req_key,input wire [31:0] req_generation,
    input wire [15:0] req_job,req_tag,input wire [7:0] req_fmt,
    input wire matrix_valid,input wire [7:0] matrix_rows,input wire [10:0] matrix_cols,
    input wire [127:0] matrix_key,input wire [31:0] matrix_generation,
    input wire [15:0] matrix_job,input wire [7:0] matrix_fmt,
    output wire mat_valid,input wire mat_ready,output wire mat_dense,
    output reg [31:0] mat_mask,output reg [287:0] mat_addr,
    output wire [127:0] mat_key,output wire [31:0] mat_generation,
    output wire [15:0] mat_job,mat_tag,output wire [7:0] mat_fmt,
    input wire mat_rsp_valid,output wire mat_rsp_ready,input wire [575:0] mat_rsp_data,
    input wire [31:0] mat_rsp_mask,mat_rsp_generation,
    input wire [15:0] mat_rsp_job,mat_rsp_tag,input wire [7:0] mat_rsp_fmt,input wire [3:0] mat_rsp_fault,
    output wire vec_valid,input wire vec_ready,output wire [8:0] vec_block,
    output wire [31:0] vec_mask,output wire [15:0] vec_tag,
    input wire vec_rsp_valid,output wire vec_rsp_ready,input wire [863:0] vec_rsp_data,
    input wire [31:0] vec_rsp_mask,input wire [15:0] vec_rsp_tag,input wire [3:0] vec_rsp_fault,
    output wire candidate_valid,input wire candidate_ready,output wire [4:0] candidate_block,
    output wire [31:0] candidate_mask,output wire [863:0] candidate_data,
    output wire rsp_valid,input wire rsp_ready,output reg [3:0] rsp_fault,rsp_detail,
    output reg [10:0] rsp_count,rsp_length,output wire [63:0] rsp_data,output reg rsp_nonzero,
    output reg [15:0] rsp_job,rsp_tag,output reg [7:0] rsp_fmt,output wire factor_valid,
    // Optional exclusive private-store bridge.  It is deliberately disabled
    // for legacy leaf users; the kernel enables it only for the panel owner.
    input wire panel_req_valid,output wire panel_req_ready,input wire panel_req_write,
    input wire [31:0] panel_req_mask,input wire [287:0] panel_req_addr,input wire [863:0] panel_req_data,
    input wire [7:0] panel_req_rows,input wire [10:0] panel_req_cols,
    input wire [127:0] panel_req_key,input wire [31:0] panel_req_generation,
    input wire [15:0] panel_req_job,panel_req_tag,input wire [7:0] panel_req_fmt,
    input wire panel_invalidate,
    output wire panel_rsp_valid,input wire panel_rsp_ready,output wire panel_rsp_write,
    output wire [863:0] panel_rsp_data,output wire [31:0] panel_rsp_mask,panel_rsp_generation,
    output wire [15:0] panel_rsp_job,panel_rsp_tag,output wire [7:0] panel_rsp_fmt,
    output wire [3:0] panel_rsp_fault
);
    localparam [3:0] IDLE=0,CHECK=1,BEGIN_STORE=2,MAT_REQ=3,MAT_WAIT=4,FILL=5,LOAD_WAIT=6,
        POOL_REQ=7,POOL_WAIT=8,STORE_REQ=9,STORE_WAIT=10,EMIT=11,FAILED=12,DONE=13;
    reg [3:0] state;
    reg [5:0] operation;
    reg [8:0] source_base,destination_base;
    reg [7:0] rows;
    reg [10:0] cols,length,fixed_index,range_start;
    reg row_range,dense,owned_valid;
    reg [127:0] key,owned_key;
    reg [31:0] generation,owned_generation;
    reg [7:0] owned_rows;
    reg [10:0] owned_cols;
    reg [15:0] owned_job;
    reg [7:0] owned_fmt;
    reg [6:0] init_col;
    reg [1:0] init_block,bundle;
    reg [575:0] matrix_buffer;
    reg [863:0] packed_buffer,staged[0:3];
    reg [31:0] packed_mask,store_mask;
    reg [287:0] store_addr;
    reg [863:0] store_data,fill_data;
    reg [31:0] fill_mask;
    reg matrix_nonzero,pool_nonzero,store_nonzero;
    integer lane,r,c,bank,position,source_stride;
    wire active=!rst&&!cancel;
    wire initialize=operation==`CSR_KERNEL_OP_FACTOR_INIT;
    wire extending=operation==`CSR_KERNEL_OP_FACTOR_EXTEND;
    wire writing=operation==`CSR_KERNEL_OP_FACTOR_WRITE;
    wire final_bundle=({9'b0,bundle}+11'd1)*11'd32>=length;
    wire final_init_block=(int'(init_block)+1)*32>=int'(rows);
    wire final_fill=final_init_block&&{4'b0,init_col}+11'd1==cols;
    wire metadata_bad=!matrix_valid||matrix_rows!=rows||matrix_cols!=cols||matrix_key!=key||
        matrix_generation!=generation||matrix_job!=rsp_job||matrix_fmt!=rsp_fmt;
    wire [15:0] transfer_tag=rsp_tag+((initialize||extending) ? {7'b0,init_col,init_block} : {14'b0,bundle});
    wire [11:0] range_end={1'b0,range_start}+{1'b0,length};
    wire [11:0] span_end={3'b0,source_base}+(({1'b0,length}+12'd31)>>5);
    wire [11:0] destination_end={3'b0,destination_base}+(({1'b0,length}+12'd31)>>5);
    wire store_begin_ready,store_fill_ready,store_loading,store_image_valid,load_status_valid;
    wire [3:0] load_status_fault;
    wire store_ready,store_rsp_valid,store_rsp_write;
    wire [863:0] store_rsp_data;
    wire [31:0] store_rsp_mask,store_rsp_generation;
    wire [15:0] store_rsp_job,store_rsp_tag;
    wire [7:0] store_rsp_fmt;
    wire [3:0] store_rsp_fault;
    reg [1:0] panel_outstanding;
    reg panel_fault_pending;
    reg panel_write_hold;
    reg [31:0] panel_mask_hold,panel_generation_hold;
    reg [863:0] panel_data_hold;
    reg [15:0] panel_job_hold,panel_tag_hold;
    reg [7:0] panel_fmt_hold;
    wire panel_abort=ENABLE_PANEL_BRIDGE ? panel_invalidate : 1'b0;
    wire panel_owner_idle=ENABLE_PANEL_BRIDGE&&active&&state==IDLE&&!req_valid;
    wire panel_identity_good=owned_valid&&store_image_valid&&matrix_valid&&
        panel_req_rows==owned_rows&&panel_req_cols==owned_cols&&panel_req_key==owned_key&&panel_req_generation==owned_generation&&
        panel_req_job==owned_job&&panel_req_fmt==owned_fmt&&matrix_rows==panel_req_rows&&matrix_cols==panel_req_cols&&
        matrix_key==panel_req_key&&matrix_generation==panel_req_generation&&matrix_job==panel_req_job&&matrix_fmt==panel_req_fmt;
    wire panel_take=panel_req_valid&&panel_req_ready;
    wire legacy_store_req=active&&!panel_abort&&state==STORE_REQ&&!metadata_bad;
    wire legacy_store_rsp_ready=active&&state==STORE_WAIT&&!metadata_bad;
    wire owned_match=owned_valid&&store_image_valid&&owned_key==key&&owned_generation==generation&&
        owned_rows==rows&&owned_cols==cols&&owned_job==rsp_job&&owned_fmt==rsp_fmt;
    wire owned_extend_match=owned_valid&&store_image_valid&&owned_key==key&&owned_generation+1'b1==generation&&
        owned_rows==rows&&owned_job==rsp_job&&owned_fmt==rsp_fmt;

    assign req_ready=active&&!panel_abort&&state==IDLE&&panel_outstanding==0&&!panel_fault_pending;
    assign rsp_valid=active&&state==DONE;
    assign rsp_data=0;
    assign factor_valid=owned_valid&&store_image_valid;
    assign mat_valid=active&&state==MAT_REQ&&!metadata_bad;
    assign mat_rsp_ready=active&&state==MAT_WAIT&&!metadata_bad;
    assign mat_dense=1'b1;assign mat_key=key;assign mat_generation=generation;
    assign mat_job=rsp_job;assign mat_tag=transfer_tag;assign mat_fmt=rsp_fmt;
    assign vec_valid=active&&state==POOL_REQ&&!metadata_bad;
    assign vec_rsp_ready=active&&state==POOL_WAIT&&!metadata_bad;
    assign vec_block=source_base+{7'b0,bundle};assign vec_mask=packed_mask;assign vec_tag=transfer_tag;
    assign candidate_valid=active&&state==EMIT&&!metadata_bad;
    assign candidate_block={3'b0,bundle};assign candidate_mask=packed_mask;assign candidate_data=packed_buffer;
    // A mismatched identity is accepted as a held bridge fault.  Returning a
    // fault instead of withholding ready prevents a panel owner deadlock.
    assign panel_req_ready=panel_owner_idle&&!panel_abort&&!panel_fault_pending&&
        (panel_identity_good ? store_ready : panel_outstanding==0);
    // Do not expose a retained store response during reset/cancel/abort.  A
    // panel response is visible only when this bridge still owns its credit.
    assign panel_rsp_valid=ENABLE_PANEL_BRIDGE&&active&&!panel_abort&&
        (panel_fault_pending||(panel_outstanding!=0&&store_rsp_valid));
    assign panel_rsp_write=panel_fault_pending ? panel_write_hold : store_rsp_write;
    assign panel_rsp_data=panel_fault_pending ? 864'd0 : store_rsp_data;
    assign panel_rsp_mask=panel_fault_pending ? panel_mask_hold : store_rsp_mask;
    assign panel_rsp_generation=panel_fault_pending ? panel_generation_hold : store_rsp_generation;
    assign panel_rsp_job=panel_fault_pending ? panel_job_hold : store_rsp_job;
    assign panel_rsp_tag=panel_fault_pending ? panel_tag_hold : store_rsp_tag;
    assign panel_rsp_fmt=panel_fault_pending ? panel_fmt_hold : store_rsp_fmt;
    assign panel_rsp_fault=panel_fault_pending ? `CSR_KERNEL_FAULT_IDENTITY : store_rsp_fault;

    factor_store storage (
        .clk(clk),.rst(rst),.cancel(cancel||state==FAILED||panel_abort),
        .begin_valid(active&&state==BEGIN_STORE&&!metadata_bad&&!extending),.begin_ready(store_begin_ready),
        .begin_rows(rows),.begin_cols(cols[6:0]),.begin_key(key),.begin_generation(generation),.begin_job(rsp_job),.begin_fmt(rsp_fmt),
        .begin_append_valid(active&&state==BEGIN_STORE&&extending&&!metadata_bad),.begin_old_cols(fixed_index[6:0]),
        .fill_valid(active&&state==FILL&&!metadata_bad),.fill_ready(store_fill_ready),.fill_col(init_col),.fill_block(init_block),
        .fill_mask(fill_mask),.fill_data(fill_data),.fill_last(final_fill),.loading(store_loading),.store_valid(store_image_valid),
        .load_status_valid(load_status_valid),.load_status_ready(active&&state==LOAD_WAIT&&!metadata_bad),.load_status_fault(load_status_fault),
        .req_valid(legacy_store_req||(panel_take&&panel_identity_good)),.req_ready(store_ready),
        .req_write(legacy_store_req ? writing : panel_req_write),
        .req_mask(legacy_store_req ? store_mask : panel_req_mask),.req_addr(legacy_store_req ? store_addr : panel_req_addr),
        .req_data(legacy_store_req ? store_data : panel_req_data),.req_key(legacy_store_req ? key : panel_req_key),
        .req_generation(legacy_store_req ? generation : panel_req_generation),
        .req_job(legacy_store_req ? rsp_job : panel_req_job),.req_tag(legacy_store_req ? transfer_tag : panel_req_tag),
        .req_fmt(legacy_store_req ? rsp_fmt : panel_req_fmt),
        .rsp_valid(store_rsp_valid),.rsp_ready(legacy_store_rsp_ready||(!panel_abort&&panel_outstanding!=0&&!panel_fault_pending&&panel_rsp_ready)),.rsp_write(store_rsp_write),
        .rsp_data(store_rsp_data),.rsp_mask(store_rsp_mask),.rsp_generation(store_rsp_generation),
        .rsp_job(store_rsp_job),.rsp_tag(store_rsp_tag),.rsp_fmt(store_rsp_fmt),.rsp_fault(store_rsp_fault)
    );

    // Thirty-two words are mapped in parallel; no serial lane packing state.
    always @* begin
        packed_mask=0;store_mask=0;store_addr=0;store_data=0;mat_mask=0;mat_addr=0;fill_mask=0;fill_data=0;
        matrix_nonzero=0;pool_nonzero=0;store_nonzero=0;
        r=0;c=0;bank=0;position=0;source_stride=(int'(cols)+31)>>5;
        for(lane=0;lane<32;lane=lane+1)begin
            if(int'(bundle)*32+lane<int'(length))begin
                packed_mask[lane]=1;
                position=int'(range_start)+int'(bundle)*32+lane;
                r=row_range ? int'(fixed_index) : position;
                c=row_range ? position : int'(fixed_index);
                bank=(r+c)&31;
                store_mask[bank]=1;store_addr[bank*9 +:9]=9'(3*r+(c>>5));
                store_data[bank*27 +:27]=staged[bundle][lane*27 +:27];
                pool_nonzero=pool_nonzero||(|vec_rsp_data[lane*27 +:27]);
                store_nonzero=store_nonzero||(|store_rsp_data[bank*27 +:27]);
            end
            r=int'(init_block)*32+lane;c=int'(init_col);bank=(r+c)&31;
            if(r<int'(rows))begin
                mat_mask[bank]=1;mat_addr[bank*9 +:9]=9'(r*source_stride+(c>>5));
                fill_mask[lane]=1;
                matrix_nonzero=matrix_nonzero||(|mat_rsp_data[bank*18 +:18]);
                fill_data[lane*27 +:27]={{3{matrix_buffer[bank*18+17]}},matrix_buffer[bank*18 +:18],6'b0};
            end
        end
    end

    task fail(input [3:0] fault,input [3:0] detail);
        begin rsp_fault<=fault;rsp_detail<=detail;rsp_count<=0;rsp_length<=0;rsp_nonzero<=0;owned_valid<=0;state<=FAILED;end
    endtask
    integer j,read_r,read_c,read_bank;
    always @(posedge clk)begin
        if(!active)begin
            state<=IDLE;operation<=0;source_base<=0;destination_base<=0;rows<=0;cols<=0;length<=0;fixed_index<=0;range_start<=0;
            row_range<=0;dense<=0;key<=0;generation<=0;owned_valid<=0;owned_key<=0;owned_generation<=0;owned_rows<=0;owned_cols<=0;owned_job<=0;owned_fmt<=0;
            rsp_fault<=0;rsp_detail<=0;rsp_count<=0;rsp_length<=0;rsp_nonzero<=0;rsp_job<=0;rsp_tag<=0;rsp_fmt<=0;
            init_col<=0;init_block<=0;bundle<=0;matrix_buffer<=0;packed_buffer<=0;
            for(j=0;j<4;j=j+1)staged[j]<=0;
            panel_outstanding<=0;panel_fault_pending<=0;panel_write_hold<=0;panel_mask_hold<=0;panel_data_hold<=0;
            panel_generation_hold<=0;panel_job_hold<=0;panel_tag_hold<=0;panel_fmt_hold<=0;
        end else if(panel_abort) begin
            // Cancel flushes the store.  The panel has already stopped its
            // public candidate path, so no response may survive this epoch.
            panel_outstanding<=0;panel_fault_pending<=0;owned_valid<=0;
        end else if(state!=IDLE&&state!=CHECK&&state!=DONE&&state!=FAILED&&metadata_bad)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
        else if((initialize||extending)&&state!=IDLE&&state!=DONE&&state!=FAILED&&load_status_valid&&load_status_fault!=0)
            fail(`CSR_KERNEL_FAULT_OPERAND,load_status_fault);
        else case(state)
            IDLE:if(req_valid&&req_ready)begin
                operation<=req_op;source_base<=req_src_a;destination_base<=req_dst;rows<=req_rows;cols<=req_cols;length<=req_length;
                fixed_index<=req_index;range_start<=req_aux_length;row_range<=req_flags[0];dense<=req_matrix_dense;key<=req_key;generation<=req_generation;
                rsp_job<=req_job;rsp_tag<=req_tag;rsp_fmt<=req_fmt;rsp_fault<=0;rsp_detail<=0;rsp_count<=0;rsp_length<=0;rsp_nonzero<=0;
                init_col<=req_op==`CSR_KERNEL_OP_FACTOR_EXTEND ? req_index[6:0] : 0;init_block<=0;bundle<=0;
                if(req_op==`CSR_KERNEL_OP_FACTOR_INIT)owned_valid<=0;
                if(req_flags[7:1]!=0)fail(`CSR_KERNEL_FAULT_COMMAND,0);else state<=CHECK;
            end
            CHECK:if(!dense||rsp_fmt!=1||!(operation==`CSR_KERNEL_OP_FACTOR_INIT||operation==`CSR_KERNEL_OP_FACTOR_READ||operation==`CSR_KERNEL_OP_FACTOR_WRITE||operation==`CSR_KERNEL_OP_FACTOR_EXTEND))fail(`CSR_KERNEL_FAULT_COMMAND,0);
                else if(rows==0||rows>128||cols==0||cols>96)fail(`CSR_KERNEL_FAULT_RANGE,0);
                else if(metadata_bad)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else if(initialize)begin
                    if(length!={3'b0,rows}||fixed_index!=0||range_start!=0||row_range)fail(`CSR_KERNEL_FAULT_RANGE,0);
                    else state<=BEGIN_STORE;
                end else if(extending) begin
                    if(!owned_valid||!store_image_valid) fail(`CSR_KERNEL_FAULT_UNINITIALIZED,0);
                    else if(!owned_extend_match) fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                    else if(length!={3'b0,rows}||range_start!=0||row_range||fixed_index==0||fixed_index!=owned_cols||fixed_index>=cols) fail(`CSR_KERNEL_FAULT_RANGE,0);
                    else state<=BEGIN_STORE;
                end else if(!owned_valid||!store_image_valid)fail(`CSR_KERNEL_FAULT_UNINITIALIZED,0);
                else if(!owned_match)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else if(length==0||length>128||range_end>(row_range ? {1'b0,cols} : {4'b0,rows})||
                    fixed_index>=(row_range ? {3'b0,rows} : cols)||
                    (writing ? source_base>=480||span_end>480 : destination_base>=480||destination_end>480))fail(`CSR_KERNEL_FAULT_RANGE,0);
                else state<=writing ? POOL_REQ : STORE_REQ;
            BEGIN_STORE:if(store_begin_ready)state<=MAT_REQ;
            MAT_REQ:if(mat_ready)state<=MAT_WAIT;
            MAT_WAIT:if(mat_rsp_valid)begin
                if(mat_rsp_fault!=0)fail(`CSR_KERNEL_FAULT_OPERAND,mat_rsp_fault);
                else if(mat_rsp_mask!=mat_mask||mat_rsp_generation!=generation||mat_rsp_job!=rsp_job||mat_rsp_tag!=transfer_tag||mat_rsp_fmt!=rsp_fmt)
                    fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else begin matrix_buffer<=mat_rsp_data;rsp_nonzero<=rsp_nonzero||matrix_nonzero;state<=FILL;end
            end
            FILL:if(store_fill_ready)begin
                if(final_fill)state<=LOAD_WAIT;
                else begin
                    if(final_init_block)begin init_block<=0;init_col<=init_col+1'b1;end else init_block<=init_block+1'b1;
                    state<=MAT_REQ;
                end
            end
            LOAD_WAIT:if(load_status_valid)begin
                if(load_status_fault!=0||!store_image_valid)fail(`CSR_KERNEL_FAULT_OPERAND,load_status_fault);
                else begin
                    owned_valid<=1;owned_rows<=rows;owned_cols<=cols;owned_key<=key;owned_generation<=generation;owned_job<=rsp_job;owned_fmt<=rsp_fmt;
                    rsp_count<=cols;state<=DONE;
                end
            end
            POOL_REQ:if(vec_ready)state<=POOL_WAIT;
            POOL_WAIT:if(vec_rsp_valid)begin
                if(vec_rsp_fault!=0)fail(`CSR_KERNEL_FAULT_OPERAND,vec_rsp_fault);
                else if(vec_rsp_mask!=packed_mask||vec_rsp_tag!=transfer_tag)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else begin
                    for(j=0;j<32;j=j+1)staged[bundle][j*27 +:27]<=packed_mask[j] ? vec_rsp_data[j*27 +:27] : 27'b0;
                    rsp_nonzero<=rsp_nonzero||pool_nonzero;
                    if(final_bundle)begin bundle<=0;state<=STORE_REQ;end else begin bundle<=bundle+1'b1;state<=POOL_REQ;end
                end
            end
            STORE_REQ:if(store_ready)state<=STORE_WAIT;
            STORE_WAIT:if(store_rsp_valid)begin
                if(store_rsp_fault!=0)fail(`CSR_KERNEL_FAULT_OPERAND,store_rsp_fault);
                else if(store_rsp_write!=writing||store_rsp_mask!=store_mask||store_rsp_generation!=generation||
                        store_rsp_job!=rsp_job||store_rsp_tag!=transfer_tag||store_rsp_fmt!=rsp_fmt)fail(`CSR_KERNEL_FAULT_IDENTITY,0);
                else if(writing)begin
                    if(final_bundle)begin rsp_count<=length;state<=DONE;end else begin bundle<=bundle+1'b1;state<=STORE_REQ;end
                end else begin
                    for(j=0;j<32;j=j+1)begin
                        read_r=row_range ? int'(fixed_index) : int'(range_start)+int'(bundle)*32+j;
                        read_c=row_range ? int'(range_start)+int'(bundle)*32+j : int'(fixed_index);
                        read_bank=(read_r+read_c)&31;
                        packed_buffer[j*27 +:27]<=packed_mask[j] ? store_rsp_data[read_bank*27 +:27] : 27'b0;
                    end
                    rsp_nonzero<=rsp_nonzero||store_nonzero;state<=EMIT;
                end
            end
            EMIT:if(candidate_ready)begin
                if(final_bundle)begin rsp_count<=length;rsp_length<=length;state<=DONE;end
                else begin bundle<=bundle+1'b1;state<=STORE_REQ;end
            end
            FAILED:state<=DONE;
            DONE:if(rsp_ready)state<=IDLE;
            default:fail(`CSR_KERNEL_FAULT_COMMAND,0);
        endcase
        // The bridge is accepted only while the old worker is truly idle.
        // Packet identity is captured for a synthetic held fault; successful
        // packets are held by factor_store's existing response queue.
        if(active&&!panel_abort) begin
            if(panel_take) begin
                panel_fault_pending<=!panel_identity_good;
                panel_write_hold<=panel_req_write;panel_mask_hold<=panel_req_mask;panel_data_hold<=panel_req_data;
                panel_generation_hold<=panel_req_generation;panel_job_hold<=panel_req_job;panel_tag_hold<=panel_req_tag;panel_fmt_hold<=panel_req_fmt;
            end
            if(panel_rsp_valid&&panel_rsp_ready) begin
                panel_fault_pending<=0;
                if(panel_rsp_fault!=0) owned_valid<=0;
            end
            // The decrement is paired with the bridge-owned response that was
            // actually presented and consumed; a stale legacy store response
            // cannot release a panel credit.
            case ({panel_take&&panel_identity_good,panel_rsp_valid&&panel_rsp_ready&&!panel_fault_pending&&panel_outstanding!=0})
                2'b10: panel_outstanding<=panel_outstanding+1'b1;
                2'b01: panel_outstanding<=panel_outstanding-1'b1;
                default: panel_outstanding<=panel_outstanding;
            endcase
        end
    end
endmodule
