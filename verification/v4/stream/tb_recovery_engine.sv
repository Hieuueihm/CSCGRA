`timescale 1ns/1ps
module tb_recovery_engine;
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
    reg  p_begin_valid=0;
    wire  p_begin_ready;
    reg [31:0] p_begin_seed=0;
    reg [7:0] p_begin_rows=0;
    reg [10:0] p_begin_cols=0;
    reg [127:0] p_begin_key=0;
    reg [31:0] p_begin_generation=0;
    reg [15:0] p_begin_job=0;
    reg [7:0] p_begin_fmt=0;
    wire  p_loading;
    wire [3:0] p_fault;
    wire  p_valid;
    reg  host_valid=0;
    wire  host_ready;
    reg  host_write=0;
    reg [8:0] host_block=0;
    reg [31:0] host_mask=0;
    reg [863:0] host_data=0;
    reg [15:0] host_tag=0;
    wire  host_rsp_valid;
    reg  host_rsp_ready=0;
    wire  host_rsp_write;
    wire [863:0] host_rsp_data;
    wire [31:0] host_rsp_mask;
    wire [15:0] host_rsp_tag;
    wire [3:0] host_rsp_fault;
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
    reg [1:0] start_storage_mode=0;
    reg signed [6:0] start_exponent=0;
    reg  start_active_support=0;
    wire  done_valid;
    reg  done_ready=0;
    wire [3:0] done_fault;
    wire [3:0] done_detail;
    wire [7:0] done_status;
    wire [15:0] done_outer_iterations;
    wire [15:0] done_inner_iterations;
    wire [6:0] done_support_count;
    wire  done_committed;
    wire [15:0] done_job;
    wire [15:0] done_tag;
    wire [7:0] done_fmt;
    wire [63:0] job_cycles;
    wire [9:0] trace_pc;
    wire [127:0] trace_word;
    wire  trace_retire;
    wire  busy;
    wire  committed_valid;
    wire [7:0] committed_rows;
    wire [10:0] committed_length;
    wire [1:0] committed_mode;
    wire signed [6:0] committed_exponent;
    wire  committed_active_support;
    wire [6:0] committed_support_count;
    wire [959:0] committed_support;
    wire [7:0] committed_status;
    wire [15:0] committed_outer_iterations;
    wire [15:0] committed_inner_iterations;
    wire [15:0] committed_job;
    wire [15:0] committed_tag;
    wire [7:0] committed_fmt;
    wire [127:0] committed_key;
    wire [31:0] committed_generation;
    reg  read_valid=0;
    wire  read_ready;
    reg [9:0] read_index=0;
    reg [15:0] read_tag=0;
    wire  read_rsp_valid;
    reg  read_rsp_ready=0;
    wire [26:0] read_rsp_data;
    wire [9:0] read_rsp_index;
    wire [15:0] read_rsp_request_tag;
    wire [3:0] read_rsp_fault;
    wire [1:0] read_rsp_mode;
    wire signed [6:0] read_rsp_exponent;
    wire [10:0] read_rsp_length;
    wire [15:0] read_rsp_job;
    wire [15:0] read_rsp_tag;
    wire [7:0] read_rsp_fmt;
    always #5 clk=~clk;
    recovery_engine dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .load_begin_valid(load_begin_valid),
        .load_begin_ready(load_begin_ready),
        .load_begin_revision(load_begin_revision),
        .load_begin_verified(load_begin_verified),
        .load_begin_program_count(load_begin_program_count),
        .load_begin_constant_count(load_begin_constant_count),
        .load_begin_template_count(load_begin_template_count),
        .load_begin_vector_count(load_begin_vector_count),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_kind(load_kind),
        .load_index(load_index),
        .load_data(load_data),
        .load_last(load_last),
        .load_status_valid(load_status_valid),
        .load_status_ready(load_status_ready),
        .load_status_fault(load_status_fault),
        .image_valid(image_valid),
        .p_begin_valid(p_begin_valid),
        .p_begin_ready(p_begin_ready),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_loading(p_loading),
        .p_fault(p_fault),
        .p_valid(p_valid),
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
        .start_valid(start_valid),
        .start_ready(start_ready),
        .start_rows(start_rows),
        .start_cols(start_cols),
        .start_key(start_key),
        .start_generation(start_generation),
        .start_scale(start_scale),
        .start_job(start_job),
        .start_tag(start_tag),
        .start_fmt(start_fmt),
        .start_instruction_limit(start_instruction_limit),
        .start_storage_mode(start_storage_mode),
        .start_exponent(start_exponent),
        .start_active_support(start_active_support),
        .done_valid(done_valid),
        .done_ready(done_ready),
        .done_fault(done_fault),
        .done_detail(done_detail),
        .done_status(done_status),
        .done_outer_iterations(done_outer_iterations),
        .done_inner_iterations(done_inner_iterations),
        .done_support_count(done_support_count),
        .done_committed(done_committed),
        .done_job(done_job),
        .done_tag(done_tag),
        .done_fmt(done_fmt),
        .job_cycles(job_cycles),
        .trace_pc(trace_pc),
        .trace_word(trace_word),
        .trace_retire(trace_retire),
        .busy(busy),
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
    integer fixture_fd,trace_fd,rc,jobs,job_number,records,blocks,i,j,number;
    integer cfg_rows,cfg_cols,cfg_mode,cfg_exponent,cfg_active,scenario,expected_fault,expected_status;
    integer debug_mode=0,debug_base,debug_length,scale_raw=32768,cycle_limit=500000;
    reg [31:0] instruction_limit=10000;
    integer cycles=0,checks=0,builds=0,kernels=0,scalars=0;
    reg [1023:0] fixture_path,trace_path;
    reg [127:0] record_data;
    reg [2:0] record_kind;
    reg [15:0] record_index;
    reg record_last;
    reg [127:0] held_read;
    reg [127:0] held_done;
    reg read_held=0;
    integer profile_frames=0;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(cycles>cycle_limit) $fatal(1,"watchdog state=%0d seq=%0d kernel=%0d result=%0d loading=%0d p=%0d",dut.state,dut.program_control.state,dut.kernel.state,dut.results.state,dut.loading,p_valid);
        if(trace_retire) $fdisplay(trace_fd,"T %0d %0d %032x",job_number,trace_pc,trace_word);
        // Profile uses accepted job clocks and does not alter functional traces.
        if(start_valid && start_ready) begin
            profile_frames<=0;
            $fdisplay(trace_fd,"P %0d 0 START 0",job_number);
        end
        if(dut.kernel.input_valid && dut.kernel.in_ready) profile_frames<=profile_frames+1;
        if(trace_retire) $fdisplay(trace_fd,"P %0d %0d RETIRE %0d",job_number,job_cycles,trace_pc);
        if(dut.kernel_valid && dut.kernel_ready)
            $fdisplay(trace_fd,"P %0d %0d KERNEL_BEGIN %0d",job_number,job_cycles,dut.kernel_op);
        if(dut.kernel_rsp_valid && dut.kernel_rsp_ready)
            $fdisplay(trace_fd,"P %0d %0d KERNEL_END %0d",job_number,job_cycles,profile_frames);
        if(dut.kernel_rsp_valid && dut.kernel_rsp_ready && dut.kernel_rsp_fault!=0)
            $fdisplay(trace_fd,"F %0d %0d %0d %0d",job_number,job_cycles,dut.kernel_rsp_fault,dut.kernel_rsp_detail);
        if(dut.scalar_valid && dut.scalar_ready)
            $fdisplay(trace_fd,"P %0d %0d SCALAR_BEGIN %0d",job_number,job_cycles,dut.scalar_op);
        if(dut.scalar_rsp_valid && dut.scalar_rsp_ready)
            $fdisplay(trace_fd,"P %0d %0d SCALAR_END 0",job_number,job_cycles);
        if(dut.build_valid && dut.build_ready)
            $fdisplay(trace_fd,"P %0d %0d BUILD_BEGIN %0d",job_number,job_cycles,dut.build_support_count);
        if(dut.build_rsp_valid && dut.build_rsp_ready)
            $fdisplay(trace_fd,"P %0d %0d BUILD_END 0",job_number,job_cycles);
        if(dut.seq_done_valid && dut.seq_done_ready)
            $fdisplay(trace_fd,"P %0d %0d PROGRAM_DONE 0",job_number,job_cycles);
        if(dut.live_build_req_valid && dut.live_build_req_ready) begin
            builds<=builds+1;
            $fdisplay(trace_fd,"B %0d %0d %0d %0240x",job_number,dut.live_build_req_count,dut.live_build_req_b_generation,dut.live_build_req_support);
        end
        if(dut.kernel_valid && dut.kernel_ready) begin
            kernels<=kernels+1;
            $fdisplay(trace_fd,"K %0d %0d %0d %0d",job_number,dut.kernel_op,dut.kernel_matrix_dense,dut.kernel.req_generation);
        end
        if(dut.scalar_rsp_valid && dut.scalar_rsp_ready) begin
            scalars<=scalars+1;
            $fdisplay(trace_fd,"S %0d %07x %0d",job_number,dut.scalar_rsp_data,dut.scalar_rsp_fault);
        end
        if(busy && (host_ready || load_begin_ready || p_begin_ready)) $fatal(1,"host ownership leaked");
    end
    task tick;
        begin @(posedge clk);#1;@(negedge clk);checks=checks+1;end
    endtask
    task get_result(input integer index_number);
        begin
            read_index=index_number;read_tag=16'h6000+index_number;read_valid=1;
            while(!read_ready) tick();
            tick();read_valid=0;
            while(!read_rsp_valid) tick();
            held_read={read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt};
            repeat(2) begin
                tick();
                if({read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt}!==held_read) $fatal(1,"result hold");
            end
            if(read_rsp_index!==index_number[9:0] || read_rsp_request_tag!==16'h6000+index_number) $fatal(1,"read identity");
            $fdisplay(trace_fd,"X %0d %0d %07x %0d %0d %0d %0d",job_number,index_number,read_rsp_data,read_rsp_fault,read_rsp_mode,$signed(read_rsp_exponent),read_rsp_tag);
            read_rsp_ready=1;tick();read_rsp_ready=0;
        end
    endtask
    initial begin
        rc=$value$plusargs("fixture=%s",fixture_path);rc=$value$plusargs("trace=%s",trace_path);
        rc=$value$plusargs("debug=%d",debug_mode);rc=$value$plusargs("scale=%d",scale_raw);rc=$value$plusargs("cycle_limit=%d",cycle_limit);
        rc=$value$plusargs("instruction_limit=%d",instruction_limit);
        if(instruction_limit==0) $fatal(1,"instruction_limit must be positive");
        fixture_fd=$fopen(fixture_path,"r");trace_fd=$fopen(trace_path,"w");
        if(!fixture_fd || !trace_fd) $fatal(1,"files");
        rc=$fscanf(fixture_fd,"%d %d %d\n",cfg_rows,cfg_cols,jobs);
        rst=1;repeat(3) tick();rst=0;tick();
        p_begin_rows=cfg_rows;p_begin_cols=cfg_cols;p_begin_seed=32'h12345678;
        p_begin_key=128'h123456789abc;p_begin_generation=3;p_begin_job=7;p_begin_fmt=1;
        p_begin_valid=1;while(!p_begin_ready) tick();tick();p_begin_valid=0;
        while(p_loading || !p_valid) tick();
        $display("Phi ready cycles=%0d",cycles);
        if(p_fault!==0) $fatal(1,"Phi load");
        for(job_number=0;job_number<jobs;job_number=job_number+1) begin
            rc=$fscanf(fixture_fd,"%d %d %d %d %d %d\n",cfg_mode,cfg_exponent,cfg_active,scenario,expected_fault,expected_status);
            rc=$fscanf(fixture_fd,"%d %d %d %d %d\n",number,i,j,blocks,records);
            load_begin_revision=2;load_begin_verified=1;
            load_begin_program_count=number;load_begin_template_count=i;load_begin_vector_count=j;load_begin_constant_count=blocks;
            load_begin_valid=1;while(!load_begin_ready) tick();tick();load_begin_valid=0;
            for(i=0;i<records;i=i+1) begin
                rc=$fscanf(fixture_fd,"%h %h %h %h\n",record_kind,record_index,record_data,record_last);
                if(rc!=4) $fatal(1,"program record");
                load_kind=record_kind;load_index=record_index;load_data=record_data;load_last=record_last;load_valid=1;
                while(!load_ready) begin
                    if(load_status_valid) $fatal(1,"early program load fault record=%0d kind=%0d index=%0d fault=%0d",i,record_kind,record_index,load_status_fault);
                    tick();
                end
                tick();load_valid=0;
            end
            while(!load_status_valid) tick();
            repeat(2) tick();
            if(load_status_fault!==0 || !image_valid) $fatal(1,"program load %0d",load_status_fault);
            load_status_ready=1;tick();load_status_ready=0;
            $display("Program loaded job=%0d cycles=%0d",job_number,cycles);
            rc=$fscanf(fixture_fd,"%d\n",blocks);
            for(i=0;i<blocks;i=i+1) begin
                rc=$fscanf(fixture_fd,"%d %h %h\n",number,host_mask,host_data);
                if(rc!=3) $fatal(1,"host fixture");
                host_block=number;host_tag=i;host_write=1;host_valid=1;
                while(!host_ready) tick();tick();host_valid=0;
                while(!host_rsp_valid) tick();
                if(host_rsp_fault!==0 || host_rsp_tag!==i[15:0] || host_rsp_write!==1'b1) $fatal(1,"host preload");
                if(i%3==0) repeat(2) tick();
                host_rsp_ready=1;tick();host_rsp_ready=0;
            end
            debug_length=0;
            if(debug_mode) begin
                rc=$fscanf(fixture_fd,"%d %d\n",debug_base,debug_length);
                if(rc!=2) $fatal(1,"debug descriptor");
            end
            if(scenario==9) begin
                read_index=0;read_tag=16'h9999;read_valid=1;
                while(!read_ready) tick();tick();read_valid=0;
                while(!read_rsp_valid) tick();
                held_read={read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt};
                read_held=1;
            end
            if(scenario==12) force dut.b_token=32'hffffffff;
            start_rows=cfg_rows;start_cols=cfg_cols;start_key=128'h123456789abc;
            start_generation=3;start_scale=scale_raw;start_job=7;start_tag=100+job_number;start_fmt=1;
            start_instruction_limit=instruction_limit;start_storage_mode=cfg_mode;start_exponent=cfg_exponent;start_active_support=cfg_active;
            if(scenario==11) start_generation=4;
            start_valid=1;while(!start_ready) tick();tick();start_valid=0;
            $display("Started job=%0d cycles=%0d",job_number,cycles);
            start_cols=0;start_key=0;start_job=0;start_tag=0;
            if(scenario>=1 && scenario<=4) begin
                case(scenario)
                    1: while(dut.state!=dut.BUILD_WAIT) tick();
                    2: while(dut.state!=dut.RUN || !dut.kernel_busy) tick();
                    3: while(dut.results.state!=dut.results.SERIAL) tick();
                    4: while(!done_valid) tick();
                endcase
                repeat(3) tick();cancel=1;tick();cancel=0;repeat(3) tick();
                if(done_valid || busy || !image_valid) $fatal(1,"cancel ownership");
                $fdisplay(trace_fd,"C %0d %0d",job_number,scenario);
            end else begin
                while(!done_valid) tick();
                held_done={done_fault,done_detail,done_status,done_outer_iterations,done_inner_iterations,done_support_count,done_committed,done_job,done_tag,done_fmt};
                repeat(7) begin
                    tick();
                    if({done_fault,done_detail,done_status,done_outer_iterations,done_inner_iterations,done_support_count,done_committed,done_job,done_tag,done_fmt}!==held_done) $fatal(1,"done hold");
                end
                if(done_fault!==expected_fault[3:0] || done_status!==expected_status[7:0] || done_job!==16'd7 || done_tag!==16'd100+job_number || done_fmt!==1)
                    $fatal(1,"completion fault=%0d detail=%0d status=%0d",done_fault,done_detail,done_status);
                $fdisplay(trace_fd,"D %0d %0d %0d %0d %0d %0d %0d %0d",job_number,done_fault,done_detail,done_status,done_committed,done_outer_iterations,done_inner_iterations,job_cycles);
                if(read_held) begin
                    if(!read_rsp_valid || {read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt}!==held_read)
                        $fatal(1,"internal fault stole committed read");
                    read_rsp_ready=1;tick();read_rsp_ready=0;read_held=0;
                end
                done_ready=1;tick();done_ready=0;
            end
            if(scenario==12) release dut.b_token;
            $fdisplay(trace_fd,"M %0d %0d %0d %0d %0d %0d %0d %0240x %032x %0d",job_number,committed_valid,committed_length,committed_mode,$signed(committed_exponent),committed_active_support,committed_support_count,committed_support,committed_key,committed_generation);
            for(j=0;j<cfg_cols;j=j+1) get_result(j);
            for(i=0;i<(debug_length+31)/32;i=i+1) begin
                host_write=0;host_block=debug_base+i;host_tag=16'h8000+i;host_mask=0;
                for(j=0;j<32;j=j+1) if(i*32+j<debug_length) host_mask[j]=1;
                host_valid=1;while(!host_ready) tick();tick();host_valid=0;
                while(!host_rsp_valid) tick();
                if(host_rsp_fault!==0 || host_rsp_tag!==16'h8000+i || host_rsp_mask!==host_mask || host_rsp_write!==0) $fatal(1,"residual read");
                for(j=0;j<32;j=j+1) if(i*32+j<debug_length)
                    $fdisplay(trace_fd,"V %0d %0d %07x",job_number,i*32+j,host_rsp_data[j*27 +: 27]);
                host_rsp_ready=1;tick();host_rsp_ready=0;
            end
        end
        $fdisplay(trace_fd,"END %0d %0d %0d %0d %0d",cycles,checks,builds,kernels,scalars);
        $display("PASS cycles=%0d checks=%0d",cycles,checks);$fclose(trace_fd);$finish;
    end
endmodule
