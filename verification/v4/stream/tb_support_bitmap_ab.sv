`timescale 1ns/1ps
// Standalone support-service A/B driver.  Each top uses exactly the same
// command-relative stall schedule; only BITMAP_ENUM_ENABLE differs.
module support_bitmap_driver #(parameter BITMAP_ENUM_ENABLE=1'b0);
    reg clk=0; always #5 clk=~clk;
    reg rst=1,cancel=0,req_valid=0,rsp_ready=0;
    reg [5:0] req_op;
    reg [8:0] req_src_a=0,req_src_b=0,req_dst=128,req_support_base=64,req_aux_base=96;
    reg [10:0] req_length,req_k,req_support_length,req_aux_length,req_index;
    reg [26:0] req_scalar_a;
    reg [7:0] req_flags,req_fmt=1;
    reg [15:0] req_job=16'h1234,req_tag=16'h5678;
    wire req_ready,vec_valid,vec_ready,vec_rsp_ready,candidate_valid,candidate_ready,rsp_valid;
    wire [8:0] vec_block;
    wire [31:0] vec_mask,candidate_mask;
    wire [15:0] vec_tag;
    wire [4:0] candidate_block;
    wire [863:0] candidate_data;
    wire [3:0] rsp_fault,rsp_detail;
    wire [10:0] rsp_count,rsp_length;
    wire [63:0] rsp_data;
    wire rsp_nonzero;
    wire [15:0] rsp_job,rsp_tag;
    wire [7:0] rsp_fmt;
    reg host_valid=0,host_write=1;
    reg [8:0] host_block;
    reg [31:0] host_mask;
    reg [863:0] host_data;
    wire memory_ready,memory_valid;
    wire [863:0] memory_data;
    wire [31:0] memory_mask;
    wire [15:0] memory_tag;
    reg active=0,hold_read=0,hold_response=0,hold_write=0;
    integer cycles=0,command_cycles=0,reads=0,writes=0,stalls=0,checks=0;
    integer sort_cycles=0,bitmap_active_cycles=0,bitmap_word_cycles=0;
    integer fd,trace_fd,rc,blocks,i,number,stall_mode,inject,cancel_mode;
    integer saved_op,saved_length,saved_k,saved_flags,saved_s,saved_t,saved_index,saved_fmt,saved_scalar;
    integer source_address,support_address,auxiliary_address;
    reg [31:0] valid_masks[0:479];
    reg [3:0] captured_fault=0;
    reg [1023:0] fixture_path,trace_path;
    // Relative time begins only after the command has been accepted.  The OFF
    // and ON elaborations therefore see identical grant phases for one fixture.
    wire grant=!stall_mode || command_cycles%7!=0;
    wire response_grant=!hold_response && (!stall_mode || command_cycles%9!=0);
    wire write_grant=!hold_write && (!stall_mode || command_cycles%5!=0);
    wire read_request=active&&vec_valid&&!hold_read&&grant;
    wire write_request=active&&candidate_valid&&!vec_valid&&write_grant;
    assign vec_ready=active&&!hold_read&&grant&&memory_ready;
    assign candidate_ready=active&&!vec_valid&&write_grant&&memory_ready;
    wire [3:0] returned_fault=inject==3 ? 4'd7 : captured_fault;

    support_service #(.BITMAP_ENUM_ENABLE(BITMAP_ENUM_ENABLE)) dut(
        .clk(clk),.rst(rst),.cancel(cancel),.req_valid(req_valid),.req_ready(req_ready),
        .req_op(req_op),.req_src_a(req_src_a),.req_src_b(req_src_b),.req_dst(req_dst),
        .req_length(req_length),.req_k(req_k),.req_scalar_a(req_scalar_a),
        .req_support_base(req_support_base),.req_aux_base(req_aux_base),
        .req_support_length(req_support_length),.req_aux_length(req_aux_length),.req_index(req_index),
        .req_flags(req_flags),.req_job(req_job),.req_tag(req_tag),.req_fmt(req_fmt),
        .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_block(vec_block),.vec_mask(vec_mask),.vec_tag(vec_tag),
        .vec_rsp_valid(memory_valid&&response_grant),.vec_rsp_ready(vec_rsp_ready),
        .vec_rsp_data(memory_data),.vec_rsp_mask(inject==2 ? memory_mask^32'b1 : memory_mask),
        .vec_rsp_tag(inject==1 ? memory_tag^16'b1 : memory_tag),.vec_rsp_fault(returned_fault),
        .candidate_valid(candidate_valid),.candidate_ready(candidate_ready),.candidate_block(candidate_block),
        .candidate_mask(candidate_mask),.candidate_data(candidate_data),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_fault(rsp_fault),.rsp_detail(rsp_detail),
        .rsp_count(rsp_count),.rsp_length(rsp_length),.rsp_data(rsp_data),.rsp_nonzero(rsp_nonzero),
        .rsp_job(rsp_job),.rsp_tag(rsp_tag),.rsp_fmt(rsp_fmt));
    stream_vector_store memory(
        .clk(clk),.rst(rst),.cancel(cancel),.req_valid(host_valid||read_request||write_request),
        .req_ready(memory_ready),.req_write(host_valid||write_request),
        .req_block(host_valid ? host_block : write_request ? 9'd480+candidate_block : vec_block),
        .req_mask(host_valid ? host_mask : write_request ? candidate_mask : vec_mask),
        .req_data(host_valid ? host_data : candidate_data),.req_tag(vec_tag),
        .rsp_valid(memory_valid),.rsp_ready(vec_rsp_ready&&response_grant),
        .rsp_data(memory_data),.rsp_mask(memory_mask),.rsp_tag(memory_tag));
    reg previous_read=0,previous_write=0,previous_done=0;
    reg [56:0] held_read;
    reg [900:0] held_write;
    reg [134:0] held_done;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(cycles>2000000) $fatal(1,"bitmap A/B watchdog");
        if(rst||cancel) begin
            previous_read<=0; previous_write<=0; previous_done<=0;
        end else begin
            if(active) begin
                command_cycles<=command_cycles+1;
                if(dut.state==10) sort_cycles<=sort_cycles+1;
                if(dut.bitmap_enum_active) bitmap_active_cycles<=bitmap_active_cycles+1;
                if(dut.bitmap_word_valid) bitmap_word_cycles<=bitmap_word_cycles+1;
            end
            if(previous_read&&{vec_block,vec_mask,vec_tag}!==held_read) $fatal(1,"read changed while held");
            if(previous_write&&{candidate_block,candidate_mask,candidate_data}!==held_write) $fatal(1,"candidate changed while held");
            if(previous_done&&{rsp_fault,rsp_detail,rsp_count,rsp_length,rsp_data,rsp_nonzero,rsp_job,rsp_tag,rsp_fmt}!==held_done)
                $fatal(1,"response changed while held");
            previous_read<=vec_valid&&!vec_ready;
            previous_write<=candidate_valid&&!candidate_ready;
            previous_done<=rsp_valid&&!rsp_ready;
            held_read<={vec_block,vec_mask,vec_tag};
            held_write<={candidate_block,candidate_mask,candidate_data};
            held_done<={rsp_fault,rsp_detail,rsp_count,rsp_length,rsp_data,rsp_nonzero,rsp_job,rsp_tag,rsp_fmt};
            checks<=checks+3;
        end
        if(active&&!rst&&!cancel) begin
            if(vec_valid&&vec_ready) begin
                reads<=reads+1;
                if(vec_block>=480||vec_mask==0) $fatal(1,"invalid source request");
                captured_fault<=(valid_masks[vec_block]&vec_mask)==vec_mask ? 0 : 5;
            end
            if(candidate_valid&&candidate_ready) begin
                writes<=writes+1;
                if(candidate_mask==0) $fatal(1,"empty candidate");
                $fdisplay(trace_fd,"W %0d %08x %0216x",candidate_block,candidate_mask,candidate_data);
            end
            if((vec_valid&&!vec_ready)||(candidate_valid&&!candidate_ready)||(memory_valid&&!vec_rsp_ready)) stalls<=stalls+1;
        end
    end
    task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
    task launch;
        begin
            req_op=saved_op; req_length=saved_length; req_k=saved_k; req_flags=saved_flags;
            req_support_length=saved_s; req_aux_length=saved_t; req_index=saved_index;
            req_fmt=saved_fmt; req_scalar_a=saved_scalar; req_job=16'h1234; req_tag=16'h5678;
            req_valid=1; while(!req_ready) tick(); tick(); req_valid=0;
            req_op=0; req_length=0; req_k=0; req_scalar_a=0; req_flags=255; req_job=0; req_tag=0; req_fmt=0;
        end
    endtask
    initial begin
        rc=$value$plusargs("fixture=%s",fixture_path); rc=$value$plusargs("trace=%s",trace_path);
        fd=$fopen(fixture_path,"r"); trace_fd=$fopen(trace_path,"w");
        if(!fd||!trace_fd) $fatal(1,"bitmap A/B fixture files");
        rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d\n",saved_op,saved_length,saved_k,saved_flags,
                   saved_s,saved_t,saved_index,saved_fmt,stall_mode,inject,cancel_mode,saved_scalar);
        if(rc!=12) $fatal(1,"bitmap A/B fixture header");
        rc=$fscanf(fd,"%d %d %d\n",source_address,support_address,auxiliary_address);
        if(rc!=3) $fatal(1,"bitmap A/B bases");
        req_src_a=source_address; req_support_base=support_address; req_aux_base=auxiliary_address;
        rc=$fscanf(fd,"%d\n",blocks); for(i=0;i<480;i=i+1) valid_masks[i]=0;
        repeat(3) tick(); rst=0; tick();
        for(i=0;i<blocks;i=i+1) begin
            rc=$fscanf(fd,"%d %h %h\n",number,host_mask,host_data);
            if(rc!=3) $fatal(1,"bitmap A/B fixture memory");
            host_block=number; host_valid=1; while(!memory_ready) tick(); tick(); host_valid=0; valid_masks[number]=host_mask;
        end
        active=1; command_cycles=0;
        hold_read=cancel_mode==1; hold_response=cancel_mode==2; hold_write=cancel_mode==3||cancel_mode==5;
        launch();
        if(cancel_mode!=0) begin
            case(cancel_mode)
                1: while(!vec_valid) tick();
                2: while(!memory_valid) tick();
                3,5: while(!candidate_valid) tick();
                4: while(!rsp_valid) tick();
                // The ON path must reach a retained enumeration word.  The
                // legacy OFF path reaches a nontrivial linear SORT position;
                // both then take the same cancel/restart transaction path.
                6,7: if(BITMAP_ENUM_ENABLE) begin
                    while(!(dut.state==10&&dut.bitmap_enum_active&&dut.bitmap_word_valid)) tick();
                end else begin
                    while(!(dut.state==10&&!dut.bitmap_enum_active&&dut.walk!=0&&dut.walk<saved_length)) tick();
                end
            endcase
            // Do not add the ordinary endpoint delay here: the purpose of
            // modes 6/7 is to cancel/reset the retained bitmap word itself.
            if(cancel_mode!=6&&cancel_mode!=7) repeat(3) tick();
            @(negedge clk);
            if(BITMAP_ENUM_ENABLE&&(cancel_mode==6||cancel_mode==7) &&
               !(dut.bitmap_enum_active&&dut.bitmap_word_valid))
                $fatal(1,"bitmap word was not held at cancel/reset edge");
            if(cancel_mode==5||cancel_mode==7) rst=1; else cancel=1;
            tick();
            if((cancel_mode==6||cancel_mode==7) &&
               (dut.bitmap_enum_active||dut.bitmap_word_valid||dut.bitmap_word!=0))
                $fatal(1,"bitmap enumeration state survived cancel/reset");
            if(rsp_valid||vec_valid||candidate_valid||memory_valid) $fatal(1,"bitmap A/B cancel flush");
            rst=0; cancel=0; hold_read=0; hold_response=0; hold_write=0; repeat(3) tick();
            command_cycles=0; launch();
        end
        while(!rsp_valid) tick(); repeat(7) tick();
        if(rsp_job!==16'h1234||rsp_tag!==16'h5678||rsp_fmt!==saved_fmt[7:0]) $fatal(1,"bitmap A/B response identity");
        $fdisplay(trace_fd,"R %0d %0d %0d %0d %016x %0d",rsp_fault,rsp_detail,rsp_count,rsp_length,rsp_data,rsp_nonzero);
        rsp_ready=1; tick(); rsp_ready=0; repeat(3) tick();
        if(rsp_valid||memory_valid||!req_ready) $fatal(1,"bitmap A/B retirement");
        $fdisplay(trace_fd,"END %0d %0d %0d %0d %0d %0d %0d %0d %0d",cycles,reads,writes,stalls,checks,sort_cycles,bitmap_active_cycles,bitmap_word_cycles,command_cycles);
        $display("PASS bitmap=%0d cycles=%0d reads=%0d writes=%0d sort=%0d active=%0d words=%0d",BITMAP_ENUM_ENABLE,cycles,reads,writes,sort_cycles,bitmap_active_cycles,bitmap_word_cycles);
        $fclose(trace_fd); $finish;
    end
endmodule
module tb_support_bitmap_off; support_bitmap_driver #(.BITMAP_ENUM_ENABLE(1'b0)) driver(); endmodule
module tb_support_bitmap_on; support_bitmap_driver #(.BITMAP_ENUM_ENABLE(1'b1)) driver(); endmodule
