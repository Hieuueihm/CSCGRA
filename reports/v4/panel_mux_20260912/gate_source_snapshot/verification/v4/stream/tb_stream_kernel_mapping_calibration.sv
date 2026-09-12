`timescale 1ns/1ps
`include "memory_defs.vh"
module tb_stream_kernel_mapping_calibration #(parameter RESIDENT_WRITEBACK=1, parameter GEMV_GROUP_PREFETCH=1);
    reg  clk;
    reg  rst;
    reg  cancel;
    reg  host_enable;
    reg  req_valid;
    wire  req_ready;
    reg [5:0] req_op;
    reg [2047:0] req_contexts;
    reg [31:0] req_descriptor;
    reg [8:0] req_src_a;
    reg [8:0] req_src_b;
    reg [8:0] req_dst;
    reg [10:0] req_length;
    reg [7:0] req_rows;
    reg [10:0] req_cols;
    reg  req_matrix_dense;
    reg  req_trans;
    reg  req_r4;
    reg [26:0] req_scalar_a;
    reg [26:0] req_scalar_b;
    reg [31:0] req_scalar_bind_a;
    reg [31:0] req_scalar_bind_b;
    reg [5:0] req_shift;
    reg [10:0] req_k;
    reg [17:0] req_scale;
    reg [127:0] req_key;
    reg [31:0] req_generation;
    reg [15:0] req_job;
    reg [15:0] req_tag;
    reg [7:0] req_fmt;
    reg [7:0] req_frame_count;
    reg [31:0] req_tail_mask;
    reg [1:0] req_store_mode;
    reg [8:0] req_support_base;
    reg [8:0] req_aux_base;
    reg [10:0] req_support_length;
    reg [10:0] req_aux_length;
    reg [10:0] req_index;
    reg [7:0] req_flags;
    wire  rsp_valid;
    reg  rsp_ready;
    wire [3:0] rsp_fault;
    wire [3:0] rsp_detail;
    wire [63:0] rsp_data;
    wire  rsp_nonzero;
    wire [10:0] rsp_count;
    wire [15:0] rsp_job;
    wire [15:0] rsp_tag;
    wire [7:0] rsp_fmt;
    reg  host_valid;
    wire  host_ready;
    reg  host_write;
    reg [8:0] host_block;
    reg [31:0] host_mask;
    reg [863:0] host_data;
    reg [15:0] host_tag;
    wire  host_rsp_valid;
    reg  host_rsp_ready;
    wire  host_rsp_write;
    wire [863:0] host_rsp_data;
    wire [31:0] host_rsp_mask;
    wire [15:0] host_rsp_tag;
    wire [3:0] host_rsp_fault;
    wire  matrix_valid;
    wire [7:0] matrix_rows;
    wire [10:0] matrix_cols;
    wire [127:0] matrix_key;
    wire [31:0] matrix_generation;
    wire [15:0] matrix_job;
    wire [7:0] matrix_fmt;
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
    wire  operator_cancel;
    wire  matrix_select;
    wire  busy;
    wire [4:0] events;
    reg  p_begin_valid;
    reg [31:0] p_begin_seed;
    reg [7:0] p_begin_rows;
    reg [10:0] p_begin_cols;
    reg [127:0] p_begin_key;
    reg [31:0] p_begin_generation;
    reg [15:0] p_begin_job;
    reg [7:0] p_begin_fmt;
    wire  p_begin_ready;
    wire  p_loading;
    wire [3:0] p_fault;
    reg  b_begin_valid;
    wire  b_begin_ready;
    reg [7:0] b_begin_rows;
    reg [6:0] b_begin_cols;
    reg [127:0] b_begin_key;
    reg [31:0] b_begin_generation;
    reg [15:0] b_begin_job;
    reg [7:0] b_begin_fmt;
    reg  b_fill_valid;
    wire  b_fill_ready;
    reg [6:0] b_fill_slot;
    reg [1:0] b_fill_block;
    reg [31:0] b_fill_mask;
    reg [32*`CSR_PE_C_W-1:0] b_fill_data;
    reg  b_fill_last;
    wire  b_loading;
    wire [3:0] b_load_fault;
    reg  build_req_valid;
    wire  build_req_ready;
    reg [7:0] build_req_rows;
    reg [10:0] build_req_cols;
    reg [6:0] build_req_count;
    reg [959:0] build_req_support;
    reg [17:0] build_req_scale;
    reg [127:0] build_req_phi_key;
    reg [127:0] build_req_b_key;
    reg [31:0] build_req_phi_generation;
    reg [31:0] build_req_b_generation;
    reg [15:0] build_req_job;
    reg [15:0] build_req_tag;
    reg [7:0] build_req_fmt;
    wire  build_rsp_valid;
    reg  build_rsp_ready;
    wire [3:0] build_rsp_fault;
    wire [15:0] build_rsp_job;
    wire [15:0] build_rsp_tag;
    wire [7:0] build_rsp_fmt;
    wire [31:0] build_rsp_cycles;
    wire [15:0] build_rsp_words;
    wire  build_busy;
    wire  p_valid;
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
    stream_kernel #(.RESIDENT_WRITEBACK(RESIDENT_WRITEBACK),.GEMV_GROUP_PREFETCH(GEMV_GROUP_PREFETCH)) dut(.*);
    live_operator_memory operators(
        .clk(clk),
        .rst(rst),
        .cancel(operator_cancel),
        .compute_active(busy),
        .p_begin_valid(p_begin_valid),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_begin_ready(p_begin_ready),
        .p_loading(p_loading),
        .p_fault(p_fault),
        .b_begin_valid(b_begin_valid),
        .b_begin_ready(b_begin_ready),
        .b_begin_rows(b_begin_rows),
        .b_begin_cols(b_begin_cols),
        .b_begin_key(b_begin_key),
        .b_begin_generation(b_begin_generation),
        .b_begin_job(b_begin_job),
        .b_begin_fmt(b_begin_fmt),
        .b_fill_valid(b_fill_valid),
        .b_fill_ready(b_fill_ready),
        .b_fill_slot(b_fill_slot),
        .b_fill_block(b_fill_block),
        .b_fill_mask(b_fill_mask),
        .b_fill_data(b_fill_data),
        .b_fill_last(b_fill_last),
        .b_loading(b_loading),
        .b_load_fault(b_load_fault),
        .build_req_valid(build_req_valid),
        .build_req_ready(build_req_ready),
        .build_req_rows(build_req_rows),
        .build_req_cols(build_req_cols),
        .build_req_count(build_req_count),
        .build_req_support(build_req_support),
        .build_req_scale(build_req_scale),
        .build_req_phi_key(build_req_phi_key),
        .build_req_b_key(build_req_b_key),
        .build_req_phi_generation(build_req_phi_generation),
        .build_req_b_generation(build_req_b_generation),
        .build_req_job(build_req_job),
        .build_req_tag(build_req_tag),
        .build_req_fmt(build_req_fmt),
        .build_rsp_valid(build_rsp_valid),
        .build_rsp_ready(build_rsp_ready),
        .build_rsp_fault(build_rsp_fault),
        .build_rsp_job(build_rsp_job),
        .build_rsp_tag(build_rsp_tag),
        .build_rsp_fmt(build_rsp_fmt),
        .build_rsp_cycles(build_rsp_cycles),
        .build_rsp_words(build_rsp_words),
        .build_busy(build_busy),
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
    assign matrix_valid=matrix_select ? b_valid : p_valid;
    assign matrix_rows=matrix_select ? b_rows : p_rows;
    assign matrix_cols=matrix_select ? b_cols : p_cols;
    assign matrix_key=matrix_select ? b_key : p_key;
    assign matrix_generation=matrix_select ? b_generation : p_generation;
    assign matrix_job=matrix_select ? b_job : p_job;
    assign matrix_fmt=matrix_select ? b_fmt : p_fmt;
    always #5 clk=~clk;
    reg [1023:0] scalar_scratch_before;
    integer scalar_check_lane;
    always @(posedge clk) begin
        if(req_valid&&req_ready&&req_op==16)
            for(scalar_check_lane=0;scalar_check_lane<32;scalar_check_lane=scalar_check_lane+1)
                scalar_scratch_before[scalar_check_lane*32 +: 32]<=dut.scratch_masks[scalar_check_lane];
        if(!rst&&!cancel&&dut.operation==16&&dut.state!=dut.IDLE)
            for(scalar_check_lane=0;scalar_check_lane<32;scalar_check_lane=scalar_check_lane+1)
                if(dut.scratch_masks[scalar_check_lane]!==scalar_scratch_before[scalar_check_lane*32 +: 32])
                    $fatal(1,"scalar template changed scratch mask");
    end
    always @(posedge clk)
        if(!rst&&!cancel&&dut.operation==16&&dut.state!=dut.IDLE&&dut.mem_valid)
            $fatal(1,"scalar template touched vector memory");
    // Resident writeback keeps every physical pool block uniquely owned.
    integer owner_i,owner_j,owner_physical;
    reg [511:0] owner_seen;
    always @(posedge clk)
    begin
        if(!rst)
        begin
            owner_seen=0;
            for(owner_i=0;owner_i<480;owner_i=owner_i+1)
            begin
                owner_physical=dut.public_map_valid[owner_i] ? dut.public_map[owner_i] : owner_i;
                if(owner_physical<0||owner_physical>=512||owner_seen[owner_physical])
                    $fatal(1,"resident public mapping is not a permutation");
                owner_seen[owner_physical]=1;
            end
            for(owner_j=0;owner_j<32;owner_j=owner_j+1)
            begin
                owner_physical=dut.scratch_handle[owner_j];
                if(owner_physical<0||owner_physical>=512||owner_seen[owner_physical])
                    $fatal(1,"resident scratch mapping aliases a public block");
                owner_seen[owner_physical]=1;
            end
        end
    end
    integer cycles=0,checks=0,commands=0,stalls=0,candidate_count=0,support_reads=0;
    always @(posedge clk) begin
        if(rst) begin candidate_count<=0;support_reads<=0;end
        else begin
            if(dut.candidate_valid&&dut.candidate_ready) candidate_count<=candidate_count+1;
            if(dut.support_vec_valid&&dut.support_vec_ready) support_reads<=support_reads+1;
        end
    end
    integer measured_frames=0, measured_matrix=0, measured_vector=0;
    integer first_frame=-1, last_frame=-1, maximum_gap=0;
    always @(posedge clk) begin
        if(req_valid&&req_ready) begin
            measured_frames<=0;measured_matrix<=0;measured_vector<=0;
            first_frame<=-1;last_frame<=-1;maximum_gap<=0;
        end else begin
            if(dut.input_valid&&dut.in_ready) begin
                measured_frames<=measured_frames+1;
                if(first_frame<0)first_frame<=cycles;
                if(last_frame>=0&&cycles-last_frame>maximum_gap)maximum_gap<=cycles-last_frame;
                last_frame<=cycles;
            end
            if(dut.mat_valid&&dut.mat_ready)measured_matrix<=measured_matrix+1;
            if(dut.vec_valid&&dut.vec_ready)measured_vector<=measured_vector+1;
        end
    end
    // Prefetch may retain up to four future-group transport frames while an
    // active group retires.  The final group must still drain before DONE;
    // earlier terminal boundaries must not dequeue a held future response.
    always @(posedge clk) if(!rst&&!cancel&&dut.gemv&&dut.fabric_done&&
        dut.gemv_out+dut.gemv_group_width>=dut.outputs) begin
        if(!dut.issue_done||dut.feeder.count!=0)$fatal(1,"final group retired with outstanding frames");
    end
    always @(posedge clk) if(!rst&&!cancel&&dut.gemv&&dut.delivery_group_done&&dut.feeder_rsp_ready)
        $fatal(1,"prefetched future group was dequeued during terminal hold");
    reg matrix_held=0,vector_held=0;
    reg [620:0] held_matrix_request;
    reg [56:0] held_vector_request;
    wire [620:0] matrix_request_bundle={dut.feeder.mat_dense,dut.feeder.mat_mask,dut.feeder.mat_addr,dut.feeder.mat_key,dut.feeder.mat_generation,dut.feeder.mem_job,dut.feeder.mem_tag,dut.feeder.mem_fmt};
    wire [56:0] vector_request_bundle={dut.feeder.vec_block,dut.feeder.vec_mask,dut.feeder.vec_tag};
    always @(posedge clk) begin
        if(rst||operator_cancel||dut.feeder.command_start)begin matrix_held<=0;vector_held<=0;end
        else begin
            if(matrix_held&&(!dut.feeder.mat_valid||matrix_request_bundle!==held_matrix_request))$fatal(1,"stalled matrix offer changed");
            if(vector_held&&(!dut.feeder.vec_valid||vector_request_bundle!==held_vector_request))$fatal(1,"stalled vector offer changed");
            matrix_held<=dut.feeder.mat_valid&&!dut.feeder.mat_ready;
            vector_held<=dut.feeder.vec_valid&&!dut.feeder.vec_ready;
            held_matrix_request<=matrix_request_bundle;
            held_vector_request<=vector_request_bundle;
        end
    end
    integer request_stalls=0,plusarg_result,require_overlap=0,offer_response_overlap=0;
    // Optional calibration-only command-relative epoch. Default zero preserves the legacy TB schedule.
    integer command_stall_epoch=0,stall_cycle;
    integer require_prefetch=0,prefetched_group_observations=0;
    always @(posedge clk) if(!rst&&!operator_cancel&&dut.feeder.mat_valid&&!dut.feeder.mat_ready&&dut.feeder.mat_rsp_valid&&dut.feeder.mat_rsp_ready)offer_response_overlap<=offer_response_overlap+1;
    always @(posedge clk) if(!rst&&!operator_cancel&&dut.gemv&&dut.delivery_group_done&&dut.feeder.count!=0)
        prefetched_group_observations<=prefetched_group_observations+1;
    integer fd,rc,ncases,c,op,rows_i,cols_i,dense_i,trans_i,r4_i,len_i,shift_i,store_i;
    integer wc,rcount,fc,ef,enz,expected_count,cancel_i,resident_remap_cancel,direct_operand_override,bi,slot,block_i,mask_i,i,j,start_cycle,start_candidates,cancel_blocks;
    integer template_reads,start_template_reads;
    reg [863:0] payload,expected;
    reg [63:0] expected_scalar,held_scalar;
    reg [31:0] expected_mask;
    reg [26:0] sa,sb;
    reg [2047:0] filename;
    reg [79:0] held;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(!rst&&dut.state==dut.RUN&&dut.mem_valid&&dut.mem_ready&&!dut.mem_write)
            template_reads<=template_reads+1;
    end
    always @(negedge clk) begin
        stall_cycle=command_stall_epoch ? cycles-start_cycle : cycles;
        if(request_stalls&&!rst&&busy&&stall_cycle%17<4)force operators.read_grant=1'b0;
        else release operators.read_grant;
        if(!rst&&busy&&stall_cycle%19<3) begin
            force dut.memory.req_ready=1'b0;
            stalls=stalls+1;
        end else release dut.memory.req_ready;
        if(!rst&&busy&&stall_cycle%23<2) force dut.fabric.in_ready=1'b0;
        else release dut.fabric.in_ready;
    end
    task host_access(input integer write_enable,input integer block_number,input [31:0] mask,input [863:0] data,
                     input integer expected_fault,input [863:0] expected_data);
        begin
            @(negedge clk);host_valid=1;host_write=write_enable;host_block=block_number;host_mask=mask;host_data=data;host_tag=77;
            do @(posedge clk);while(!host_ready);
            @(negedge clk);host_valid=0;
            while(!host_rsp_valid) @(negedge clk);
            if(host_rsp_fault!==expected_fault||host_rsp_tag!==77||host_rsp_write!==write_enable[0])
                $fatal(1,"host fault case%0d block%0d got%0d expected%0d",c,block_number,host_rsp_fault,expected_fault);
            if(!write_enable&&expected_fault==0&&host_rsp_data!==expected_data)
                $fatal(1,"host data case%0d block%0d got%h expected%h",c,block_number,host_rsp_data,expected_data);
            checks=checks+1;
            repeat(2) @(negedge clk);
            host_rsp_ready=1;@(posedge clk);@(negedge clk);host_rsp_ready=0;
        end
    endtask
    initial begin
        plusarg_result=$value$plusargs("request_stalls=%d",request_stalls);
        plusarg_result=$value$plusargs("require_overlap=%d",require_overlap);
        plusarg_result=$value$plusargs("require_prefetch=%d",require_prefetch);
        plusarg_result=$value$plusargs("command_stall_epoch=%d",command_stall_epoch);
        clk=0;rst=1;cancel=0;host_enable=1;req_valid=0;rsp_ready=0;template_reads=0;
        prefetched_group_observations=0;cancel_blocks=0;
        host_valid=0;host_write=0;host_block=0;host_mask=0;host_data=0;host_tag=0;host_rsp_ready=0;
        p_begin_valid=0;b_begin_valid=0;b_fill_valid=0;build_req_valid=0;build_rsp_ready=1;
        p_begin_seed=32'h12345678;p_begin_key=128'h1234;p_begin_generation=3;p_begin_job=7;p_begin_fmt=1;
        b_begin_key=128'h1234;b_begin_generation=3;b_begin_job=7;b_begin_fmt=1;
        req_key=128'h1234;req_generation=3;req_job=7;req_fmt=1;req_flags=0;req_k=0;
        req_support_base=0;req_aux_base=0;req_support_length=0;req_aux_length=0;req_index=0;
        req_scale=18'd4096;req_src_a=0;req_src_b=64;req_dst=128;
        if(!$value$plusargs("vectors=%s",filename)) $fatal(1,"vectors missing");
        fd=$fopen(filename,"r");if(fd==0)$fatal(1,"vector file missing");rc=$fscanf(fd,"%d",ncases);
        for(c=0;c<ncases;c=c+1) begin
            rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %h %h %h %h %h %d %h %d %h %d %d %d %d %d %d %d %h %d %d %d %d %d %d %h %d",
                op,rows_i,cols_i,dense_i,trans_i,r4_i,len_i,shift_i,store_i,sa,sb,
                req_scalar_bind_a,req_scalar_bind_b,req_descriptor,req_frame_count,req_tail_mask,
                ef,expected_scalar,enz,cancel_i,wc,rcount,fc,req_generation,req_dst,req_contexts,
                req_k,req_support_base,req_aux_base,req_support_length,req_aux_length,req_index,req_flags,expected_count);
            if(rc!=34)$fatal(1,"case header fields%0d",rc);
            // Markers 6/7/10/16 retain a preceding factor image. Marker 7
            // maps otherwise-zero metadata bases to direct test operands;
            // marker16 is the resident-remap cancellation path.
            resident_remap_cancel=cancel_i==16;
            direct_operand_override=cancel_i==7;
            if(op!=14&&op!=15&&cancel_i!=6&&cancel_i!=7&&cancel_i!=10&&cancel_i!=16)begin
                @(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
            end
            if(cancel_i==6||cancel_i==7)cancel_i=0;
            else if(cancel_i==16)cancel_i=10;
            else if(cancel_i==10)cancel_i=1;
            req_op=op;req_rows=rows_i;req_cols=cols_i;req_matrix_dense=dense_i;req_trans=trans_i;req_r4=r4_i;
            req_length=len_i;req_shift=shift_i;req_store_mode=store_i;req_scalar_a=sa;req_scalar_b=sb;req_tag=c+1;
            // Generic MUL fixtures normally retain the public 0/64 bases.
            // A nonzero support base is a test-only source-base override so
            // the operand-alias path can be driven without changing the ABI.
            req_src_a=0;req_src_b=(op==20||op==21) ? 0 : 64;
            if(op==0&&req_support_base!=0) begin
                req_src_a=req_support_base;
                req_src_b=req_aux_base;
            end
            // Marker 7 consumes otherwise-zero metadata bases only in this
            // testbench, then restores canonical values before DUT handoff.
            if((op==17||op==18)&&direct_operand_override) begin
                req_src_a=req_support_base;
                req_src_b=req_aux_base;
                req_support_base=0;
                req_aux_base=0;
            end
            if(op==1||op==13) begin
                if(dense_i) begin
                    b_begin_rows=rows_i;b_begin_cols=cols_i;b_begin_valid=1;
                    do @(posedge clk);while(!b_begin_ready);
                    @(negedge clk);b_begin_valid=0;
                    for(i=0;i<fc;i=i+1) begin
                        rc=$fscanf(fd,"%d %d %h %h",slot,block_i,expected_mask,b_fill_data);
                        b_fill_slot=slot;b_fill_block=block_i;b_fill_mask=expected_mask;b_fill_last=i+1==fc;b_fill_valid=1;
                        do @(posedge clk);while(!b_fill_ready);
                        @(negedge clk);b_fill_valid=0;
                    end
                    if(!b_valid||b_load_fault!=0)$fatal(1,"B not published %0d",b_load_fault);
                end else begin
                    p_begin_rows=rows_i;p_begin_cols=cols_i;p_begin_valid=1;
                    do @(posedge clk);while(!p_begin_ready);
                    @(negedge clk);p_begin_valid=0;
                    while(!p_valid||p_loading) @(negedge clk);
                    if(p_fault!=0)$fatal(1,"Phi load fault");
                end
            end
            for(i=0;i<wc;i=i+1) begin
                rc=$fscanf(fd,"%d %h %h",bi,expected_mask,payload);
                host_access(1,bi,expected_mask,payload,0,0);
            end
            @(negedge clk);req_valid=1;start_cycle=cycles;start_candidates=candidate_count;start_template_reads=template_reads;
            do @(posedge clk);while(!req_ready);
            @(negedge clk);req_valid=0;
            if(cancel_i==5)begin
                force dut.feeder.vec_rsp_valid=1'b0;
                force dut.feeder.mat_rsp_ready=1'b0;
                while(!dut.feeder.vector_pending)@(negedge clk);
                release dut.feeder.mat_rsp_ready;
                while(!dut.feeder.mat_rsp_valid)@(negedge clk);
                if(!dut.feeder.vector_pending)$fatal(1,"delayed vector was not outstanding");
                force dut.feeder.mat_rsp_tag=16'hffff;
                @(posedge clk);@(negedge clk);release dut.feeder.mat_rsp_tag;
                while(dut.state!=dut.FAIL)@(negedge clk);
                release dut.feeder.vec_rsp_valid;
                cancel_i=0;
            end
            if(cancel_i==4)begin
                while(candidate_count==start_candidates)@(negedge clk);
                while(!dut.factors.store_rsp_valid)@(negedge clk);
                force dut.factors.store_rsp_tag=16'hffff;
                @(posedge clk);@(negedge clk);release dut.factors.store_rsp_tag;
                cancel_i=0;
            end
            // Marker18 corrupts a matrix response for a prefetched future
            // group.  Its fault may be consumed only after the active group
            // handoff, so no retiring-frame payload can be affected.
            if(cancel_i==18)begin
                while(!(dut.state==dut.GEMV_WAIT&&dut.delivery_group_done&&
                    dut.feeder.mat_rsp_valid&&dut.feeder.mat_rsp_ready)) @(negedge clk);
                force dut.feeder.mat_rsp_tag=16'hffff;
                @(posedge clk);@(negedge clk);release dut.feeder.mat_rsp_tag;
                cancel_i=0;
            end
            if(cancel_i!=0) begin
                if(cancel_i==19||cancel_i==20) cancel_blocks=dut.count;
                if(cancel_i==8||cancel_i==9) while(dut.fabric.state!=dut.fabric.TERMINAL) @(negedge clk);
                else if(cancel_i==19||cancel_i==20) while(!(dut.state==dut.GEMV_WAIT&&dut.delivery_group_done&&dut.feeder.count!=0)) @(negedge clk);
                else if(cancel_i==1) while(dut.state!=dut.GEMV_WAIT&&dut.state!=dut.RUN&&dut.state!=dut.SUPPORT_WAIT) @(negedge clk);
                else if(resident_remap_cancel) begin
                    while(dut.state!=dut.REMAP) @(negedge clk);
                    while(dut.remap_frame==0) @(negedge clk);
                end
                else while(dut.state!=dut.COPY_WRITE&&dut.state!=dut.REMAP) @(negedge clk);
                if(resident_remap_cancel&&(!dut.public_map_valid[req_dst]||dut.public_map[req_dst]==req_dst))
                    $fatal(1,"resident cancel did not retain a completed ownership swap");
                if(cancel_i==3||cancel_i==9||cancel_i==20)rst=1;else cancel=1;
                @(negedge clk);cancel=0;rst=0;
                repeat(3) @(negedge clk);
                if(rsp_valid||busy)$fatal(1,"cancel leaked response/busy");
                // Future-group cancellation/reset invalidates all selected
                // destination blocks before the next command may recover.
                if(cancel_i==19||cancel_i==20)
                    for(i=0;i<cancel_blocks;i=i+1) host_access(0,req_dst+i,32'h1,0,2,0);
            end else begin
                while(!rsp_valid) @(negedge clk);
                if(rsp_fault!==ef||rsp_job!==7||rsp_tag!==c+1||rsp_fmt!==1||
                    (ef==0&&(rsp_data!==expected_scalar||rsp_nonzero!==enz[0]||rsp_count!==expected_count)))
                    $fatal(1,"response case%0d op%0d fault%0d/%0d scalar%h/%h nz%0d/%0d",c,op,rsp_fault,ef,rsp_data,expected_scalar,rsp_nonzero,enz);
                if((op==6||op==11||op==12)&&ef==7&&candidate_count<2)$fatal(1,"late source fault did not follow candidate writes");
                if(ef!=0&&(rsp_data!=0||rsp_nonzero!=0))$fatal(1,"fault leaked numerical candidate");
                held={rsp_fault,rsp_detail,rsp_nonzero,rsp_data};
                repeat(5) begin
                    @(negedge clk);
                    if(req_ready||!rsp_valid||{rsp_fault,rsp_detail,rsp_nonzero,rsp_data}!==held)$fatal(1,"held response changed");
                    checks=checks+1;
                end
                rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
            end
            $display("CASE %0d op=%0d rows=%0d cols=%0d dense=%0d trans=%0d r4=%0d cycles=%0d support_reads=%0d candidates=%0d",c,op,rows_i,cols_i,dense_i,trans_i,r4_i,cycles-start_cycle,support_reads,candidate_count);
            $display("TEMPLATE_READS case=%0d reads=%0d",c,template_reads-start_template_reads);
            $display("TRANSPORT case=%0d frames=%0d matrix=%0d vector=%0d first=%0d last=%0d maxgap=%0d",c,measured_frames,measured_matrix,measured_vector,first_frame,last_frame,maximum_gap);
            commands=commands+1;
            for(i=0;i<rcount;i=i+1) begin
                rc=$fscanf(fd,"%d %h %d %h",bi,expected_mask,mask_i,expected);
                host_access(0,bi,expected_mask,0,mask_i,expected);
            end
        end
        if(require_overlap&&offer_response_overlap==0)$fatal(1,"missing older-response/stalled-offer coverage");
        if(require_prefetch&&prefetched_group_observations==0)$fatal(1,"missing bounded future-group prefetch coverage");
        $display("OFFER_RESPONSE_OVERLAP %0d",offer_response_overlap);
        $display("PREFETCH_GROUP_OBSERVATIONS %0d",prefetched_group_observations);
        $display("PASS stream_kernel cycles=%0d checks=%0d commands=%0d stalls=%0d",cycles,checks,commands,stalls);$finish;
    end
    initial begin #5000000;$fatal(1,"bounded watchdog state%0d",dut.state);end
endmodule

