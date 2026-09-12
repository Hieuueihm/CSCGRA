`timescale 1ns/1ps
module tb_program_sequencer #(
    parameter RETIRE_TIME_FETCH=1'b1
);
    reg  clk=0;
    reg  rst=0;
    reg  cancel=0;
    reg  load_begin_valid=0;
    wire  load_begin_ready;
    reg [7:0] load_begin_revision=0;
    reg  load_begin_verified=0;
    reg [10:0] load_begin_program_count=0;
    reg [10:0] load_begin_constant_count=0;
    reg [4:0] load_begin_template_count=0;
    reg [5:0] load_begin_vector_count=0;
    reg  load_valid=0;
    wire  load_ready;
    reg [2:0] load_kind=0;
    reg [15:0] load_index=0;
    reg [127:0] load_data=0;
    reg  load_last=0;
    wire  load_status_valid;
    reg  load_status_ready=0;
    wire [3:0] load_status_fault;
    wire  image_valid;
    reg  start_valid=0;
    wire  start_ready;
    reg [7:0] start_rows=0;
    reg [10:0] start_cols=0;
    reg [127:0] start_key=0;
    reg [31:0] start_generation=0;
    reg [17:0] start_scale=0;
    reg [15:0] start_job=0;
    reg [15:0] start_tag=0;
    reg [7:0] start_fmt=0;
    reg [31:0] start_instruction_limit=0;
    wire  kernel_valid;
    reg  kernel_ready=0;
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
    reg  kernel_rsp_valid=0;
    wire  kernel_rsp_ready;
    reg [3:0] kernel_rsp_fault=0;
    reg [3:0] kernel_rsp_detail=0;
    reg [63:0] kernel_rsp_data=0;
    reg  kernel_rsp_nonzero=0;
    reg [10:0] kernel_rsp_count=0;
    reg [15:0] kernel_rsp_job=0;
    reg [15:0] kernel_rsp_tag=0;
    reg [7:0] kernel_rsp_fmt=0;
    wire  scalar_valid;
    reg  scalar_ready=0;
    wire [1:0] scalar_op;
    wire [63:0] scalar_a;
    wire [63:0] scalar_b;
    wire [7:0] scalar_source_frac;
    wire [15:0] scalar_job;
    wire [15:0] scalar_tag;
    wire [7:0] scalar_fmt;
    reg  scalar_rsp_valid=0;
    wire  scalar_rsp_ready;
    reg [26:0] scalar_rsp_data=0;
    reg [2:0] scalar_rsp_fault=0;
    reg [15:0] scalar_rsp_job=0;
    reg [15:0] scalar_rsp_tag=0;
    reg [7:0] scalar_rsp_fmt=0;
    wire  build_valid;
    reg  build_ready=0;
    wire [8:0] build_support_base;
    wire [10:0] build_support_count;
    wire [15:0] build_job;
    wire [15:0] build_tag;
    wire [7:0] build_fmt;
    reg  build_rsp_valid=0;
    wire  build_rsp_ready;
    reg [3:0] build_rsp_fault=0;
    reg [15:0] build_rsp_job=0;
    reg [15:0] build_rsp_tag=0;
    reg [7:0] build_rsp_fmt=0;
    wire  done_valid;
    reg  done_ready=0;
    wire [3:0] done_fault;
    wire [3:0] done_detail;
    wire [7:0] done_status;
    wire [15:0] done_outer_iterations;
    wire [15:0] done_inner_iterations;
    wire [4:0] done_output_vector;
    wire [4:0] done_residual_vector;
    wire [4:0] done_support_vector;
    wire [10:0] done_support_count;
    wire [8:0] done_output_base;
    wire [8:0] done_residual_base;
    wire [8:0] done_support_base;
    wire [10:0] done_output_capacity;
    wire [10:0] done_residual_capacity;
    wire [10:0] done_support_capacity;
    wire [15:0] done_job;
    wire [15:0] done_tag;
    wire [7:0] done_fmt;
    wire  running;
    wire [9:0] trace_pc;
    wire [127:0] trace_word;
    wire  trace_retire;
    program_sequencer #(.RETIRE_TIME_FETCH(RETIRE_TIME_FETCH)) dut(.*);
    always #5 clk=~clk;
    wire [4095:0] kernel_payload={kernel_flags,kernel_index,kernel_aux_length,kernel_support_length,kernel_aux_base,kernel_support_base,kernel_store_mode,kernel_tail_mask,kernel_frame_count,kernel_fmt,kernel_tag,kernel_job,kernel_generation,kernel_key,kernel_scale,kernel_k,kernel_shift,kernel_scalar_bind_b,kernel_scalar_bind_a,kernel_scalar_b,kernel_scalar_a,kernel_r4,kernel_trans,kernel_matrix_dense,kernel_cols,kernel_rows,kernel_length,kernel_dst,kernel_src_b,kernel_src_a,kernel_descriptor,kernel_contexts,kernel_op};
    wire [4095:0] scalar_payload={scalar_fmt,scalar_tag,scalar_job,scalar_source_frac,scalar_b,scalar_a,scalar_op};
    wire [4095:0] build_payload={build_fmt,build_tag,build_job,build_support_count,build_support_base};
    wire request_valid=kernel_valid||scalar_valid||build_valid;
    wire request_ready=kernel_valid ? kernel_ready : scalar_valid ? scalar_ready : build_ready;
    wire [1:0] request_kind=kernel_valid ? 1 : scalar_valid ? 2 : 3;
    wire [4095:0] request_payload=kernel_valid ? kernel_payload : scalar_valid ? scalar_payload : build_payload;
    integer cycles=0,checks=0,fd,rc,ncases,c,i,j,records,services,accepted,delay_count,pending;
    integer revision,pcount,tcount,vcount,ccount,limit_value,expected_load_fault,expected_fault,expected_detail,expected_status,cancel_mode;
    integer record_kind,record_index,record_last,response_kind,response_fault,response_detail,response_count,response_nz,corrupt;
    reg [127:0] record_data;
    reg [4095:0] expected_payload,held_request;
    reg [63:0] response_data;
    reg [15:0] response_job,response_tag;
    reg [7:0] response_fmt;
    reg held_request_valid=0;
    reg [511:0] held_done;
    reg [2047:0] filename;
    wire [511:0] done_payload={done_fault,done_detail,done_status,done_outer_iterations,done_inner_iterations,
        done_output_vector,done_residual_vector,done_support_vector,done_support_count,
        done_output_base,done_residual_base,done_support_base,done_output_capacity,done_residual_capacity,done_support_capacity,
        done_job,done_tag,done_fmt};
    always @* begin
        kernel_ready=pending==0&&cycles%7>=3;
        scalar_ready=pending==0&&cycles%9>=4;
        build_ready=pending==0&&cycles%11>=5;
    end
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(rst||cancel) begin
            pending<=0;delay_count<=0;kernel_rsp_valid<=0;scalar_rsp_valid<=0;build_rsp_valid<=0;
            held_request_valid<=0;
        end else begin
            if(held_request_valid && (!request_valid||request_payload!==held_request)) $fatal(1,"held service request changed case%0d",c);
            held_request_valid<=request_valid&&!request_ready;
            if(request_valid&&!request_ready)held_request<=request_payload;
            if(request_valid&&request_ready) begin
                rc=$fscanf(fd,"%d %h %h %d %d %d %d %d",response_kind,expected_payload,response_data,response_fault,response_detail,response_count,response_nz,corrupt);
                if(rc!=8||response_kind!==request_kind||request_payload!==expected_payload)
                    $fatal(1,"service payload case%0d kind%0d/%0d got%h expected%h",c,request_kind,response_kind,request_payload,expected_payload);
                accepted=accepted+1;checks=checks+1;pending<=request_kind;delay_count<=7+cycles%5;
                response_job=kernel_valid ? kernel_job : scalar_valid ? scalar_job : build_job;
                response_tag=(kernel_valid ? kernel_tag : scalar_valid ? scalar_tag : build_tag)^(corrupt ? 16'd1 : 16'd0);
                response_fmt=kernel_valid ? kernel_fmt : scalar_valid ? scalar_fmt : build_fmt;
            end
            if(pending!=0) begin
                if(delay_count!=0)delay_count<=delay_count-1;
                else case(pending)
                    1:begin
                        kernel_rsp_valid<=1;kernel_rsp_data<=response_data;kernel_rsp_fault<=response_fault;kernel_rsp_detail<=response_detail;
                        kernel_rsp_count<=response_count;kernel_rsp_nonzero<=response_nz;kernel_rsp_job<=response_job;kernel_rsp_tag<=response_tag;kernel_rsp_fmt<=response_fmt;
                        if(kernel_rsp_valid&&kernel_rsp_ready)begin kernel_rsp_valid<=0;pending<=0;end
                    end
                    2:begin
                        scalar_rsp_valid<=1;scalar_rsp_data<=response_data[26:0];scalar_rsp_fault<=response_fault;
                        scalar_rsp_job<=response_job;scalar_rsp_tag<=response_tag;scalar_rsp_fmt<=response_fmt;
                        if(scalar_rsp_valid&&scalar_rsp_ready)begin scalar_rsp_valid<=0;pending<=0;end
                    end
                    3:begin
                        build_rsp_valid<=1;build_rsp_fault<=response_fault;
                        build_rsp_job<=response_job;build_rsp_tag<=response_tag;build_rsp_fmt<=response_fmt;
                        if(build_rsp_valid&&build_rsp_ready)begin build_rsp_valid<=0;pending<=0;end
                    end
                endcase
            end
        end
    end
    always @(negedge clk) if(!rst&&!cancel&&trace_retire) $display("RET case=%0d pc=%0d word=%h",c,trace_pc,trace_word);
    initial begin
        rst=1;pending=0;accepted=0;
        start_rows=33;start_cols=1024;start_scale=4096;start_key=128'h1234;start_generation=3;start_job=7;start_tag=100;start_fmt=1;
        if(!$value$plusargs("vectors=%s",filename))$fatal(1,"vectors missing");
        fd=$fopen(filename,"r");if(fd==0)$fatal(1,"vectors missing file");rc=$fscanf(fd,"%d",ncases);
        for(c=0;c<ncases;c=c+1) begin
            @(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
            accepted=0;load_valid=0;load_begin_valid=0;load_status_ready=0;start_valid=0;done_ready=0;
            rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d",revision,pcount,tcount,vcount,ccount,records,services,limit_value,expected_load_fault,expected_fault,expected_detail,expected_status,cancel_mode);
            if(rc!=13)$fatal(1,"case header");
            load_begin_revision=revision;load_begin_verified=1;load_begin_program_count=pcount;
            load_begin_template_count=tcount;load_begin_vector_count=vcount;load_begin_constant_count=ccount;
            load_begin_valid=1;do @(posedge clk);while(!load_begin_ready);
            @(negedge clk);load_begin_valid=0;
            for(i=0;i<records;i=i+1)begin
                rc=$fscanf(fd,"%d %d %h %d",record_kind,record_index,record_data,record_last);
                if(rc!=4)$fatal(1,"load record");
                if(!load_status_valid&&cancel_mode!=1||i==0&&cancel_mode==1)begin
                    load_kind=record_kind;load_index=record_index;load_data=record_data;load_last=record_last;load_valid=1;
                    do @(posedge clk);while(!load_ready);
                    @(negedge clk);load_valid=0;
                    if(cancel_mode==1&&i==0)begin cancel=1;@(negedge clk);cancel=0;end
                end
            end
            if(cancel_mode==1)begin
                if(image_valid||load_status_valid||start_ready)$fatal(1,"partial load survived cancel");
            end else begin
                while(!load_status_valid)@(negedge clk);
                if(load_status_fault!==expected_load_fault||image_valid!==(expected_load_fault==0))$fatal(1,"load result case%0d got%0d expected%0d",c,load_status_fault,expected_load_fault);
                repeat(4)begin @(negedge clk);if(!load_status_valid||load_status_fault!==expected_load_fault||start_ready)$fatal(1,"load status not held");checks=checks+1;end
                load_status_ready=1;@(posedge clk);@(negedge clk);load_status_ready=0;
                if(expected_load_fault==0) begin
                    start_instruction_limit=limit_value;start_valid=1;do @(posedge clk);while(!start_ready);
                    @(negedge clk);start_valid=0;
                    if(cancel_mode!=0)begin
                        if(cancel_mode==2)while(dut.state!=dut.KWAIT&&dut.state!=dut.SWAIT&&dut.state!=dut.BWAIT)@(negedge clk);
                        else while(dut.state!=dut.CERTIFY)@(negedge clk);
                        cancel=1;@(negedge clk);cancel=0;repeat(3)@(negedge clk);
                        if(done_valid||running||!image_valid||!start_ready)$fatal(1,"execution cancel ownership");
                        // A retained complete image can start again; START clears stale RF state.
                        start_valid=1;do @(posedge clk);while(!start_ready);
                        @(negedge clk);start_valid=0;
                        for(j=0;j<32;j=j+1)if(dut.rf[j]!==0)$fatal(1,"restart RF not cleared");
                        cancel=1;@(negedge clk);cancel=0;
                    end else begin
                        while(!done_valid)@(negedge clk);
                        if(done_fault!==expected_fault||done_detail!==expected_detail||done_status!==expected_status||done_job!==7||done_tag!==100||done_fmt!==1)
                            $fatal(1,"done case%0d fault%0d/%0d detail%0d/%0d status%0d/%0d",c,done_fault,expected_fault,done_detail,expected_detail,done_status,expected_status);
                        held_done=done_payload;
                        repeat(6)begin @(negedge clk);if(!done_valid||done_payload!==held_done||start_ready||load_begin_ready||request_valid)$fatal(1,"held done changed");checks=checks+1;end
                        $display("DONE case=%0d out=%0d/%0d residual=%0d/%0d support=%0d/%0d count=%0d",c,done_output_base,done_output_capacity,done_residual_base,done_residual_capacity,done_support_base,done_support_capacity,done_support_count);
                        for(j=0;j<32;j=j+1)$display("RF case=%0d index=%0d data=%h",c,j,dut.rf[j]);
                        done_ready=1;@(posedge clk);@(negedge clk);done_ready=0;
                    end
                end
            end
            if(accepted!=services)$fatal(1,"service count case%0d %0d/%0d",c,accepted,services);
            $display("CASE %0d complete",c);
        end
        $display("PASS program_sequencer cycles=%0d checks=%0d cases=%0d",cycles,checks,ncases);$finish;
    end
    initial begin #20000000;$fatal(1,"watchdog state%0d case%0d",dut.state,c);end
endmodule
