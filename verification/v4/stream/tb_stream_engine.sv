`timescale 1ns/1ps
module tb_stream_engine;
    reg clk=0, rst=1, cancel=0;
    reg load_begin_valid;
    wire load_begin_ready;
    reg [7:0] load_begin_revision;
    reg load_begin_verified;
    reg [8:0] load_begin_program_count;
    reg [4:0] load_begin_template_count;
    reg load_program_valid;
    wire load_program_ready;
    reg [7:0] load_program_index;
    reg [127:0] load_program_word;
    reg load_program_last;
    reg load_template_valid;
    wire load_template_ready;
    reg [3:0] load_template_id;
    reg [5:0] load_template_lane;
    reg [63:0] load_template_word;
    reg load_template_last;
    wire load_status_valid;
    reg load_status_ready;
    wire [3:0] load_status_fault;
    wire image_valid;
    reg start_valid;
    wire start_ready;
    reg [15:0] start_job, start_tag;
    reg [7:0] start_fmt;
    reg host_valid;
    wire host_ready;
    reg host_write;
    reg [8:0] host_block;
    reg [31:0] host_mask;
    reg [863:0] host_data;
    reg [15:0] host_tag;
    wire host_rsp_valid;
    reg host_rsp_ready;
    wire host_rsp_write;
    wire [863:0] host_rsp_data;
    wire [31:0] host_rsp_mask;
    wire [15:0] host_rsp_tag;
    wire [3:0] host_rsp_fault;
    wire busy;
    wire [63:0] job_cycles, frames_in, frames_out, memory_reads, memory_writes, stall_cycles;
    wire done_valid;
    reg done_ready;
    wire [3:0] done_fault, done_detail;
    wire [63:0] done_scalar;
    wire [15:0] done_job, done_tag;
    wire [7:0] done_fmt;
    wire [7:0] trace_pc;
    wire [3:0] trace_template;
    always #5 clk=~clk;
    stream_engine dut(.*);
    reg [127:0] program_words[0:255];
    reg [63:0] template_words[0:527];
    reg [863:0] data,expected_data;
    reg [31:0] mask;
    reg [63:0] expected_scalar;
    reg [119:0] held_done;
    reg [916:0] held_host;
    reg [2047:0] directory,path;
    integer phase,pcount,tcount,wcount,rcount,expected_fault,expected_detail,cancel_mode,stall_mode,load_bad,inject_mode;
    reg injected=0;
    integer fd,rc,i,k,block_id,expected_host_fault,checks=0,cycles=0,jobs=0,seen_stalls=0;
    always @(posedge clk) cycles<=cycles+1;
    // Endpoint backpressure preserves the same request/accept wires inside each leaf.
    always @(negedge clk) begin
        if(stall_mode && dut.kernel.state==dut.kernel.RUN && cycles%17<4) begin
            force dut.kernel.memory.req_ready=1'b0;seen_stalls=seen_stalls+1;
        end else release dut.kernel.memory.req_ready;
        if(stall_mode && dut.kernel.state==dut.kernel.RUN && cycles%13<3) force dut.kernel.fabric.in_ready=1'b0;
        else release dut.kernel.fabric.in_ready;
        if(phase==1&&!injected&&inject_mode==1&&dut.kernel.state==dut.kernel.RUN&&dut.kernel.mem_rsp_valid) begin
            force dut.kernel.mem_rsp_tag=16'hffff;injected=1;
        end else release dut.kernel.mem_rsp_tag;
        if(phase==1&&!injected&&inject_mode==2&&dut.kernel.fabric_done) begin
            force dut.kernel.fabric_job=16'hffff;injected=1;
        end else release dut.kernel.fabric_job;
    end
    task host_command(input bit wr,input integer address,input reg[31:0] lanes,input reg[863:0] payload,input integer want_fault);
        begin
            @(negedge clk);host_valid=1;host_write=wr;host_block=address;host_mask=lanes;host_data=payload;host_tag=16'h6789;
            @(posedge clk);while(!host_ready) @(posedge clk);
            @(negedge clk);host_valid=0;
            while(!host_rsp_valid) @(negedge clk);
            if(host_rsp_write!==wr||host_rsp_tag!==16'h6789||host_rsp_mask!==lanes||host_rsp_fault!==want_fault)
                $fatal(1,"host response identity/fault block%0d got%0d want%0d",address,host_rsp_fault,want_fault);
            if(!wr&&host_rsp_data!==(want_fault==0 ? payload : 864'b0)) $fatal(1,"host data block%0d got%h want%h",address,host_rsp_data,payload);
            held_host={host_rsp_write,host_rsp_fault,host_rsp_tag,host_rsp_mask,host_rsp_data};
            repeat(3) begin @(negedge clk);if(!host_rsp_valid||held_host!=={host_rsp_write,host_rsp_fault,host_rsp_tag,host_rsp_mask,host_rsp_data}) $fatal(1,"host hold");end
            host_rsp_ready=1;@(negedge clk);host_rsp_ready=0;checks=checks+34;
        end
    endtask
    task launch;
        begin
            @(negedge clk);start_valid=1;start_job=91;start_tag=200+phase;start_fmt=1;
            @(posedge clk);while(!start_ready) @(posedge clk);
            @(negedge clk);start_valid=0;jobs=jobs+1;
        end
    endtask
    task wait_done;
        begin
            while(!done_valid) @(negedge clk);
            if(done_fault!==expected_fault||done_detail!==expected_detail||done_scalar!==expected_scalar||done_job!==91||done_tag!==200+phase||done_fmt!==1)
                $fatal(1,"done phase%0d fault%0d/%0d expected%0d/%0d scalar%h want%h",phase,done_fault,done_detail,expected_fault,expected_detail,done_scalar,expected_scalar);
            held_done={done_fault,done_detail,done_scalar,done_job,done_tag,done_fmt};
            repeat(7) begin @(negedge clk);if(!done_valid||held_done!=={done_fault,done_detail,done_scalar,done_job,done_tag,done_fmt}) $fatal(1,"done hold");end
            $display("JOB phase=%0d cycles=%0d frames_in=%0d frames_out=%0d reads=%0d writes=%0d stalls=%0d fault=%0d detail=%0d scalar=%h",phase,job_cycles,frames_in,frames_out,memory_reads,memory_writes,stall_cycles,done_fault,done_detail,done_scalar);
            done_ready=1;@(negedge clk);done_ready=0;checks=checks+8;
        end
    endtask
    initial begin
        load_begin_valid=0;load_program_valid=0;load_template_valid=0;load_status_ready=0;
        load_begin_revision=1;load_begin_verified=1;load_begin_program_count=0;load_begin_template_count=0;
        load_program_index=0;load_program_word=0;load_program_last=0;load_template_id=0;load_template_lane=0;load_template_word=0;load_template_last=0;
        start_valid=0;start_job=0;start_tag=0;start_fmt=1;done_ready=0;
        host_valid=0;host_write=0;host_block=0;host_mask=0;host_data=0;host_tag=0;host_rsp_ready=0;stall_mode=0;
        if(!$value$plusargs("DIR=%s",directory)) $fatal(1,"DIR required");
        repeat(3) @(negedge clk);rst=0;
        host_command(0,480,32'hffffffff,0,2);host_command(1,511,32'hffffffff,0,2);
        for(phase=0;phase<2;phase=phase+1) begin
            $sformat(path,"%0s/%0d/meta.txt",directory,phase);fd=$fopen(path,"r");if(fd==0)$fatal(1,"meta open");
            rc=$fscanf(fd,"%d %d %d %d %d %d %h %d %d %d %d",pcount,tcount,wcount,rcount,expected_fault,expected_detail,expected_scalar,cancel_mode,stall_mode,load_bad,inject_mode);$fclose(fd);
            $sformat(path,"%0s/%0d/program.hex",directory,phase);$readmemh(path,program_words,0,pcount-1);
            $sformat(path,"%0s/%0d/templates.hex",directory,phase);$readmemh(path,template_words,0,tcount*33-1);
            @(negedge clk);load_begin_valid=1;load_begin_program_count=pcount;load_begin_template_count=tcount;
            @(posedge clk);while(!load_begin_ready) @(posedge clk);
            @(negedge clk);load_begin_valid=0;
            for(i=0;i<pcount;i=i+1) begin
                load_program_valid=1;load_program_index=i;load_program_word=program_words[i];load_program_last=i==pcount-1;
                @(posedge clk);while(!load_program_ready) @(posedge clk);
                @(negedge clk);
            end
            load_program_valid=0;
            for(i=0;i<tcount*33;i=i+1) begin
                load_template_valid=1;load_template_id=i/33;load_template_lane=i%33;
                load_template_word=template_words[i];load_template_last=i==tcount*33-1;
                @(posedge clk);while(!load_template_ready) @(posedge clk);
                @(negedge clk);
            end
            load_template_valid=0;
            while(!load_status_valid) @(negedge clk);
            if(load_status_fault!==load_bad) $fatal(1,"load status %0d want%0d",load_status_fault,load_bad);
            repeat(3) @(negedge clk);load_status_ready=1;@(negedge clk);load_status_ready=0;
            if(load_bad==0) begin
                $sformat(path,"%0s/%0d/writes.txt",directory,phase);fd=$fopen(path,"r");
                for(i=0;i<wcount;i=i+1) begin rc=$fscanf(fd,"%d %h %h",block_id,mask,data);host_command(1,block_id,mask,data,0);end
                $fclose(fd);launch();
                if(cancel_mode!=0) begin
                    if(cancel_mode==1) begin while(frames_in==0) @(negedge clk);end
                    else begin while(dut.kernel.state!=dut.kernel.COPY_WRITE) @(negedge clk);end
                    cancel=1;repeat(2) @(negedge clk);cancel=0;
                    repeat(5) begin @(negedge clk);if(done_valid) $fatal(1,"cancel orphandone");end
                    if(!image_valid) $fatal(1,"cancel lostimage");
                end else wait_done();
                $sformat(path,"%0s/%0d/reads.txt",directory,phase);fd=$fopen(path,"r");
                for(i=0;i<rcount;i=i+1) begin rc=$fscanf(fd,"%d %h %d %h",block_id,mask,expected_host_fault,expected_data);host_command(0,block_id,mask,expected_data,expected_host_fault);end
                $fclose(fd);
                if(cancel_mode!=0) begin
                    // Restart the exact retained image without reloading its templates.
                    launch();wait_done();
                    $sformat(path,"%0s/%0d/recovery.txt",directory,phase);fd=$fopen(path,"r");
                    for(i=0;i<rcount;i=i+1) begin rc=$fscanf(fd,"%d %h %d %h",block_id,mask,expected_host_fault,expected_data);host_command(0,block_id,mask,expected_data,expected_host_fault);end
                    $fclose(fd);
                end
            end else begin
                if(image_valid!==1'b0) $fatal(1,"invalid load published");
                for(k=0;k<32;k=k+1) data[k*27 +: 27]=27'(k-16);
                host_command(0,450,32'hffffffff,data,0);
            end
        end
        if(stall_mode&&!seen_stalls) $fatal(1,"nostallcoverage");
        $display("PASS stream_engine cycles=%0d checks=%0d jobs=%0d endpoint_stalls=%0d",cycles,checks,jobs,seen_stalls);$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog state%0d",dut.kernel.state);end
endmodule
