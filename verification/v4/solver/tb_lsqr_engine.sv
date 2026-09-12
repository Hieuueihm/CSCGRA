`include "memory_defs.vh"
`include "scalar_interface.vh"
module tb_lsqr_engine;
    reg  clk = '0;
    reg  rst = '0;
    reg  cancel = '0;
    reg  p_begin_valid = '0;
    reg [31:0] p_begin_seed = '0;
    reg [7:0] p_begin_rows = '0;
    reg [10:0] p_begin_cols = '0;
    reg [127:0] p_begin_key = '0;
    reg [31:0] p_begin_generation = '0;
    reg [15:0] p_begin_job = '0;
    reg [7:0] p_begin_fmt = '0;
    wire  p_begin_ready;
    wire  p_loading;
    wire [3:0] p_fault;
    reg  b_begin_valid = '0;
    wire  b_begin_ready;
    reg [7:0] b_begin_rows = '0;
    reg [6:0] b_begin_cols = '0;
    reg [127:0] b_begin_key = '0;
    reg [31:0] b_begin_generation = '0;
    reg [15:0] b_begin_job = '0;
    reg [7:0] b_begin_fmt = '0;
    reg  b_fill_valid = '0;
    wire  b_fill_ready;
    reg [6:0] b_fill_slot = '0;
    reg [1:0] b_fill_block = '0;
    reg [31:0] b_fill_mask = '0;
    reg [32*`CSR_PE_C_W-1:0] b_fill_data = '0;
    reg  b_fill_last = '0;
    wire  b_loading;
    wire [3:0] b_load_fault;
    reg  y_begin_valid = '0;
    wire  y_begin_ready;
    reg [7:0] y_begin_rows = '0;
    reg [15:0] y_begin_job = '0;
    reg [7:0] y_begin_fmt = '0;
    reg  y_fill_valid = '0;
    wire  y_fill_ready;
    reg [1:0] y_fill_block = '0;
    reg [31:0] y_fill_mask = '0;
    reg [575:0] y_fill_data = '0;
    reg  y_fill_last = '0;
    wire  y_loading;
    wire  y_valid;
    wire [3:0] y_fault;
    wire [7:0] y_rows;
    wire [7:0] y_fmt;
    wire [15:0] y_job;
    reg  program_load_begin_valid = '0;
    wire  program_load_begin_ready;
    reg [7:0] program_load_revision = '0;
    reg  program_load_verified = '0;
    reg [8:0] program_load_depth = '0;
    reg  program_load_valid = '0;
    wire  program_load_ready;
    reg [7:0] program_load_pc = '0;
    reg [127:0] program_load_word = '0;
    reg  program_load_last = '0;
    wire  program_image_valid;
    wire [3:0] program_load_fault;
    reg  start_valid = '0;
    reg  start_generated = '0;
    reg [7:0] start_rows = '0;
    reg [10:0] start_columns = '0;
    reg [6:0] start_count = '0;
    reg [959:0] start_support = '0;
    reg [17:0] start_scale = '0;
    reg [127:0] start_phi_key = '0;
    reg [31:0] start_phi_generation = '0;
    reg [127:0] start_b_key = '0;
    reg [31:0] start_b_generation = '0;
    reg [15:0] start_job = '0;
    reg [15:0] start_tag = '0;
    reg [7:0] start_fmt = '0;
    reg signed [6:0] start_exponent = '0;
    reg [7:0] start_max_iterations = '0;
    reg [31:0] start_instruction_limit = '0;
    wire  start_ready;
    wire  done_valid;
    wire [3:0] done_fault;
    wire [3:0] done_detail;
    wire  done_committed;
    wire [7:0] done_iterations;
    wire [63:0] done_normal_energy;
    wire [63:0] done_rhs_energy;
    wire [15:0] done_job;
    wire [15:0] done_tag;
    wire [7:0] done_fmt;
    reg  done_ready = '0;
    wire  committed_valid;
    wire [6:0] committed_count;
    wire [7:0] committed_rows;
    reg  read_valid = '0;
    wire  read_ready;
    reg [6:0] read_slot = '0;
    wire  rsp_valid;
    reg  rsp_ready = '0;
    wire signed [23:0] rsp_x;
    wire [9:0] rsp_index;
    wire signed [6:0] rsp_exponent;
    wire [15:0] rsp_job;
    wire [15:0] rsp_tag;
    wire [7:0] rsp_fmt;
    wire [3:0] rsp_fault;
    lsqr_engine dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
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
        .y_begin_valid(y_begin_valid),
        .y_begin_ready(y_begin_ready),
        .y_begin_rows(y_begin_rows),
        .y_begin_job(y_begin_job),
        .y_begin_fmt(y_begin_fmt),
        .y_fill_valid(y_fill_valid),
        .y_fill_ready(y_fill_ready),
        .y_fill_block(y_fill_block),
        .y_fill_mask(y_fill_mask),
        .y_fill_data(y_fill_data),
        .y_fill_last(y_fill_last),
        .y_loading(y_loading),
        .y_valid(y_valid),
        .y_fault(y_fault),
        .y_rows(y_rows),
        .y_fmt(y_fmt),
        .y_job(y_job),
        .program_load_begin_valid(program_load_begin_valid),
        .program_load_begin_ready(program_load_begin_ready),
        .program_load_revision(program_load_revision),
        .program_load_verified(program_load_verified),
        .program_load_depth(program_load_depth),
        .program_load_valid(program_load_valid),
        .program_load_ready(program_load_ready),
        .program_load_pc(program_load_pc),
        .program_load_word(program_load_word),
        .program_load_last(program_load_last),
        .program_image_valid(program_image_valid),
        .program_load_fault(program_load_fault),
        .start_valid(start_valid),
        .start_generated(start_generated),
        .start_rows(start_rows),
        .start_columns(start_columns),
        .start_count(start_count),
        .start_support(start_support),
        .start_scale(start_scale),
        .start_phi_key(start_phi_key),
        .start_phi_generation(start_phi_generation),
        .start_b_key(start_b_key),
        .start_b_generation(start_b_generation),
        .start_job(start_job),
        .start_tag(start_tag),
        .start_fmt(start_fmt),
        .start_exponent(start_exponent),
        .start_max_iterations(start_max_iterations),
        .start_instruction_limit(start_instruction_limit),
        .start_ready(start_ready),
        .done_valid(done_valid),
        .done_fault(done_fault),
        .done_detail(done_detail),
        .done_committed(done_committed),
        .done_iterations(done_iterations),
        .done_normal_energy(done_normal_energy),
        .done_rhs_energy(done_rhs_energy),
        .done_job(done_job),
        .done_tag(done_tag),
        .done_fmt(done_fmt),
        .done_ready(done_ready),
        .committed_valid(committed_valid),
        .committed_count(committed_count),
        .committed_rows(committed_rows),
        .read_valid(read_valid),
        .read_ready(read_ready),
        .read_slot(read_slot),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_x(rsp_x),
        .rsp_index(rsp_index),
        .rsp_exponent(rsp_exponent),
        .rsp_job(rsp_job),
        .rsp_tag(rsp_tag),
        .rsp_fmt(rsp_fmt),
        .rsp_fault(rsp_fault)
    );

    integer rows,columns,count,generated,seed,scale,maxiter,exponent,abort_phase,header;
    integer src,trace,scan,pc_id,block_id,slot_id,last_flag,cycle,run_id,clocks,retire_count;
    reg [31:0] mask_word;
    reg [575:0] data_word;
    reg [4095:0] program_path,y_path,b_path,support_path,trace_path;
    reg [127:0] program_words[0:255];
    reg [959:0] support_words[0:0];
    reg [63:0] held_normal,held_rhs;
    reg [3:0] held_fault,held_detail;
    reg held_committed;
    reg [7:0] held_iterations,held_fmt,held_rows;
    reg [6:0] held_count;
    reg [15:0] held_job,held_tag;
    reg [23:0] held_x;
    task tick;begin #4;clk=1;#1;clk=0;#1;clocks=clocks+1;end endtask
    task load_program;
        begin
            program_load_begin_valid=1;program_load_revision=1;program_load_verified=1;program_load_depth=256;
            #1;if(!program_load_begin_ready)$fatal(1,"program begin blocked");tick;program_load_begin_valid=0;
            for(pc_id=0;pc_id<256;pc_id=pc_id+1)begin
                program_load_valid=1;program_load_pc=8'(pc_id);program_load_word=program_words[pc_id];program_load_last=pc_id==255;
                #1;if(!program_load_ready)$fatal(1,"program stream blocked");tick;
            end
            program_load_valid=0;if(!program_image_valid||program_load_fault!=0)$fatal(1,"program not verified");
        end
    endtask
    task baseline_load;
        begin
            b_begin_rows=1;b_begin_cols=1;b_begin_key=92;b_begin_generation=2;b_begin_job=7;b_begin_fmt=1;b_begin_valid=1;
            tick;b_begin_valid=0;
            b_fill_valid=1;b_fill_slot=0;b_fill_block=0;b_fill_mask=1;b_fill_data=576'd65536;b_fill_last=1;tick;b_fill_valid=0;
            repeat(2)tick;
            y_begin_rows=1;y_begin_job=7;y_begin_fmt=1;y_begin_valid=1;tick;y_begin_valid=0;
            y_fill_valid=1;y_fill_block=0;y_fill_mask=1;y_fill_data=576'd8192;y_fill_last=1;tick;y_fill_valid=0;
            while(y_loading)tick;
            if(!y_valid)$fatal(1,"baseline Y invalid");
        end
    endtask
    task case_load;
        begin
            if(generated)begin
                p_begin_rows=8'(rows);p_begin_cols=11'(columns);p_begin_seed=32'(seed);p_begin_key=91;p_begin_generation=1;
                p_begin_job=7;p_begin_fmt=1;p_begin_valid=1;#1;if(!p_begin_ready)$fatal(1,"Phi begin blocked");tick;p_begin_valid=0;
                while(p_loading)tick;tick;
                if(p_fault!=0)$fatal(1,"Phi load fault");
            end else begin
                b_begin_rows=8'(rows);b_begin_cols=7'(count);b_begin_key=92;b_begin_generation=2;b_begin_job=7;b_begin_fmt=1;b_begin_valid=1;
                #1;if(!b_begin_ready)$fatal(1,"B begin blocked");tick;b_begin_valid=0;
                src=$fopen(b_path,"r");if(!src)$fatal(1,"B input open");
                while(!$feof(src))begin
                    scan=$fscanf(src,"%h %h %h %h %h",slot_id,block_id,mask_word,data_word,last_flag);
                    if(scan==5)begin
                        b_fill_valid=1;b_fill_slot=7'(slot_id);b_fill_block=2'(block_id);b_fill_mask=mask_word;b_fill_data=data_word;b_fill_last=1'(last_flag);
                        #1;if(!b_fill_ready)$fatal(1,"B fill blocked");tick;
                    end else if(!$feof(src))$fatal(1,"B stream malformed");
                end
                $fclose(src);b_fill_valid=0;while(b_loading)tick;tick;
            end
            y_begin_rows=8'(rows);y_begin_job=7;y_begin_fmt=1;y_begin_valid=1;
            #1;if(!y_begin_ready)$fatal(1,"Y begin blocked");tick;y_begin_valid=0;
            src=$fopen(y_path,"r");if(!src)$fatal(1,"Y input open");
            while(!$feof(src))begin
                scan=$fscanf(src,"%h %h %h %h",block_id,mask_word,data_word,last_flag);
                if(scan==4)begin
                    y_fill_valid=1;y_fill_block=2'(block_id);y_fill_mask=mask_word;y_fill_data=data_word;y_fill_last=1'(last_flag);
                    while(!y_fill_ready)tick;tick;y_fill_valid=0;
                end else if(!$feof(src))$fatal(1,"Y stream malformed");
            end
            $fclose(src);while(y_loading)tick;
        end
    endtask
    task execute(input integer baseline,input integer abort_at);
        begin
            start_generated=baseline ? 0 : 1'(generated);start_rows=baseline ? 8'd1 : 8'(rows);
            start_columns=baseline ? 11'd1 : 11'(columns);start_count=baseline ? 7'd1 : 7'(count);
            start_support=baseline ? 960'b0 : support_words[0];start_scale=18'(scale);start_phi_key=91;start_phi_generation=1;
            start_b_key=92;start_b_generation=2;start_job=7;start_tag=16'(123+run_id);start_fmt=1;
            start_exponent=baseline ? 7'sd0 : 7'(exponent);start_max_iterations=baseline ? 8'd8 : 8'(maxiter);start_instruction_limit=100000;
            if(!baseline)begin
                if(header==1)start_count=0;
                if(header==2)start_fmt=2;
                if(header==3)start_exponent=32;
                if(header==4)start_max_iterations=0;
                if(header==5)start_instruction_limit=0;
                if(header==6)start_support[9:0]=10'(columns);
            end
            #1;if(!start_ready)$fatal(1,"job blocked state=%0d",dut.state);start_valid=1;tick;start_valid=0;
            // Changing all caller metadata cannot affect accepted job.
            start_support='1;start_b_key=999;start_job=999;start_exponent=31;start_rows=0;start_count=0;start_scale=0;
            cycle=0;retire_count=0;
            while(!done_valid&&cycle<10000000)begin
                if(dut.sequencer.trace_retire)retire_count=retire_count+1;
                if((abort_at==1&&dut.state==5)||(abort_at==2&&dut.state==7&&cycle>200)||
                    (abort_at==3&&dut.state==9)||(abort_at==4&&dut.state==11))begin
                    cancel=1;repeat(3)tick;cancel=0;abort_at=0;
                end
                if(p_begin_ready||b_begin_ready||y_begin_ready||program_load_begin_ready||program_load_ready)$fatal(1,"host write not locked");
                tick;cycle=cycle+1;
            end
            if(!done_valid)$fatal(1,"solver timeout state=%0d PC=%0d",dut.state,dut.sequencer.trace_pc);
            $fdisplay(trace,"D %0d %0d %0d %0d %0d %h %h %0d %0d",run_id,done_fault,done_detail,done_committed,done_iterations,done_normal_energy,done_rhs_energy,cycle,retire_count);
            held_fault=done_fault;held_detail=done_detail;held_normal=done_normal_energy;held_rhs=done_rhs_energy;
            held_committed=done_committed;held_iterations=done_iterations;held_job=done_job;held_tag=done_tag;held_fmt=done_fmt;
            held_count=committed_count;held_rows=committed_rows;
            repeat(4)begin tick;if(!done_valid||done_fault!=held_fault||done_normal_energy!=held_normal||done_rhs_energy!=held_rhs||done_detail!=held_detail||done_committed!=held_committed||done_iterations!=held_iterations||done_job!=held_job||done_tag!=held_tag||done_fmt!=held_fmt||committed_count!=held_count||committed_rows!=held_rows)$fatal(1,"held done changed");end
            done_ready=1;tick;done_ready=0;
        end
    endtask
    task read_committed;
        begin
            if(!committed_valid)$fatal(1,"old committed result lost");
            for(slot_id=0;slot_id<committed_count;slot_id=slot_id+1)begin
                read_slot=7'(slot_id);read_valid=1;#1;if(!read_ready)$fatal(1,"result read blocked");tick;read_valid=0;
                if(!rsp_valid||rsp_fault!=0)$fatal(1,"committed read fault");held_x=rsp_x;
                repeat(3)begin tick;if(!rsp_valid||rsp_x!=held_x)$fatal(1,"committed response stall changed");end
                $fdisplay(trace,"X %0d %0d %h %0d %0d %0d %0d",run_id,slot_id,rsp_x,rsp_index,rsp_exponent,rsp_job,rsp_tag);
                rsp_ready=1;tick;rsp_ready=0;
            end
        end
    endtask
    initial begin
        if(!$value$plusargs("rows=%d",rows)||!$value$plusargs("columns=%d",columns)||!$value$plusargs("count=%d",count)||
           !$value$plusargs("generated=%d",generated)||!$value$plusargs("seed=%d",seed)||!$value$plusargs("scale=%d",scale)||
           !$value$plusargs("maxiter=%d",maxiter)||!$value$plusargs("exponent=%d",exponent)||!$value$plusargs("abort=%d",abort_phase)||!$value$plusargs("header=%d",header)||
           !$value$plusargs("program=%s",program_path)||!$value$plusargs("y=%s",y_path)||!$value$plusargs("b=%s",b_path)||
           !$value$plusargs("support=%s",support_path)||!$value$plusargs("trace=%s",trace_path))$fatal(1,"missing args");
        trace=$fopen(trace_path,"w");if(!trace)$fatal(1,"trace open");clocks=0;run_id=0;
        $readmemh(program_path,program_words);$readmemh(support_path,support_words);
        rst=1;tick;rst=0;load_program;baseline_load;execute(1,0);read_committed;
        run_id=1;case_load;execute(0,abort_phase);read_committed;
        if(abort_phase!=0)begin run_id=2;case_load;execute(0,0);read_committed;end
        $fdisplay(trace,"END %0d",clocks);$fclose(trace);$display("PASS clocks=%0d",clocks);$finish;
    end
    initial begin #150000000;$fatal(1,"watchdog");end
endmodule
