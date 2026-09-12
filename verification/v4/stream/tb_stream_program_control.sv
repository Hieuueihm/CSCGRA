`timescale 1ns/1ps
`include "stream_interface.vh"
module tb_stream_program_control;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,cancel=0;
    reg load_begin_valid=0,load_begin_verified=1;
    wire load_begin_ready;
    reg [7:0] load_begin_revision=1;
    reg [8:0] load_begin_program_count;
    reg [4:0] load_begin_template_count;
    reg load_program_valid=0,load_program_last=0;
    wire load_program_ready;
    reg [7:0] load_program_index;
    reg [127:0] load_program_word;
    reg load_template_valid=0,load_template_last=0;
    wire load_template_ready;
    reg [3:0] load_template_id;
    reg [5:0] load_template_lane;
    reg [63:0] load_template_word;
    wire load_status_valid,image_valid;
    reg load_status_ready=0;
    wire [3:0] load_status_fault;
    reg start_valid=0;
    wire start_ready;
    reg [15:0] start_job=16'h1234,start_tag=16'habcd;
    reg [7:0] start_fmt=1;
    wire cmd_valid;
    reg cmd_ready=0;
    wire [3:0] cmd_template;
    wire [8:0] cmd_src_a,cmd_src_b,cmd_dst;
    wire [7:0] cmd_frame_count;
    wire [31:0] cmd_tail_mask,cmd_descriptor;
    wire [2047:0] cmd_contexts;
    wire [15:0] cmd_job,cmd_tag;
    wire [7:0] cmd_fmt;
    reg rsp_valid=0;
    wire rsp_ready;
    reg [3:0] rsp_fault=0;
    reg [63:0] rsp_scalar=0;
    reg [15:0] rsp_job=16'h1234,rsp_tag=16'habcd;
    reg [7:0] rsp_fmt=1;
    wire done_valid;
    reg done_ready=0;
    wire [3:0] done_fault,done_detail;
    wire [63:0] done_scalar;
    wire [15:0] done_job,done_tag;
    wire [7:0] done_fmt;
    wire [7:0] trace_pc;
    wire [3:0] trace_template;
    stream_program_control dut (.*);
    reg [127:0] programs[0:255];
    reg [63:0] templates[0:527];
    reg [4095:0] program_path,template_path;
    integer mode=0,pcount=0,tcount=0,expected=0,checks=0,cycles=0,commands=0,i,j,k,tid;
    reg [127:0] held_word;
    reg [2047:0] held_contexts;
    reg [63:0] last_scalar;
    always @(posedge clk) begin
        cycles <= cycles+1;
        if(cycles>30000) $fatal(1,"watchdog");
    end
    task tick; begin @(posedge clk); #1; end endtask
    task check;
        input condition;
        input [511:0] message;
        begin if(condition!==1'b1) $fatal(1,"check failed: %s",message); checks=checks+1; end
    endtask
    task end_test;
        begin $display("PASS checks=%0d cycles=%0d commands=%0d",checks,cycles,commands); $finish; end
    endtask
    task assert_quiet;
        begin
            #1;
            check(!cmd_valid&&!rsp_ready&&!done_valid&&!load_status_valid&&!start_ready&&
                  !load_begin_ready&&!load_program_ready&&!load_template_ready,"cancel/reset gates handshakes");
        end
    endtask
    initial begin
        if(!$value$plusargs("program=%s",program_path)) $fatal(1,"program argument");
        if(!$value$plusargs("templates=%s",template_path)) $fatal(1,"templates argument");
        if(!$value$plusargs("pcount=%d",pcount)) $fatal(1,"pcount argument");
        if(!$value$plusargs("tcount=%d",tcount)) $fatal(1,"tcount argument");
        if(!$value$plusargs("mode=%d",mode)) $fatal(1,"mode argument");
        if(!$value$plusargs("expected=%d",expected)) $fatal(1,"expected argument");
        $readmemh(program_path,programs,0,pcount-1);
        $readmemh(template_path,templates,0,tcount*33-1);
        tick(); assert_quiet(); rst=0; tick();
        check(!image_valid&&!start_ready,"reset clears image");
        load_begin_program_count=pcount;load_begin_template_count=tcount;
        if(mode==1) load_begin_revision=2;
        if(mode==2) load_begin_verified=0;
        if(mode==18) load_begin_program_count=0;
        load_begin_valid=1;tick();load_begin_valid=0;
        if(mode==7) begin
            cancel=1;assert_quiet();tick();cancel=0;tick();
            check(!image_valid&&load_begin_ready&&!start_ready,"cancel incomplete load invalid");end_test();
        end
        for(i=0;i<pcount&&!load_status_valid;i=i+1) begin
            check(load_program_ready,"program load ready");
            load_program_index=(mode==3&&i==0)?1:i;
            load_program_word=programs[i];
            load_program_last=(i==pcount-1);
            if(mode==4&&i==0) load_program_last=!load_program_last;
            load_program_valid=1;tick();load_program_valid=0;
            check(!image_valid,"program alone not published");
        end
        for(i=0;i<tcount&&!load_status_valid;i=i+1) begin
            for(j=0;j<33&&!load_status_valid;j=j+1) begin
                check(load_template_ready,"template load ready");
                load_template_id=i;load_template_lane=(mode==5&&i==0&&j==0)?1:j;
                load_template_word=templates[i*33+j];
                load_template_last=(i==tcount-1&&j==32);
                if(mode==6&&i==0&&j==0) load_template_last=1;
                load_template_valid=1;tick();load_template_valid=0;
                if(!load_template_last) check(!image_valid,"partial template not published");
            end
        end
        check(load_status_valid,"load status held");
        if(expected==1) begin
            check(load_status_fault==1&&!image_valid&&!start_ready,"load rejected");
            repeat(3) begin tick();check(load_status_valid&&load_status_fault==1,"load fault stable");end
            load_status_ready=1;tick();load_status_ready=0;
            check(load_begin_ready&&!start_ready,"retry possible");end_test();
        end
        check(load_status_fault==0&&image_valid&&!start_ready,"complete load waits ack");
        repeat(3) tick();load_status_ready=1;tick();load_status_ready=0;
        check(start_ready,"image ready");
        if(mode==14) start_fmt=2;
        start_valid=1;tick();start_valid=0;
        check(!load_begin_ready,"no load while run");
        last_scalar=0;k=0;
        while(!done_valid) begin
            tick();
            if(cmd_valid) begin
                held_word=programs[k];tid=held_word[`CSR_STREAM_PROGRAM_TEMPLATE_LSB +: `CSR_STREAM_PROGRAM_TEMPLATE_W];
                check(cmd_template==tid&&trace_template==tid&&trace_pc==k,"command PC/template");
                check(cmd_src_a==held_word[`CSR_STREAM_PROGRAM_SRC_A_LSB +: `CSR_STREAM_PROGRAM_SRC_A_W]&&
                      cmd_src_b==held_word[`CSR_STREAM_PROGRAM_SRC_B_LSB +: `CSR_STREAM_PROGRAM_SRC_B_W]&&
                      cmd_dst==held_word[`CSR_STREAM_PROGRAM_DST_LSB +: `CSR_STREAM_PROGRAM_DST_W]&&
                      cmd_frame_count==held_word[`CSR_STREAM_PROGRAM_FRAME_COUNT_LSB +: `CSR_STREAM_PROGRAM_FRAME_COUNT_W]&&
                      cmd_tail_mask==held_word[`CSR_STREAM_PROGRAM_TAIL_MASK_LSB +: `CSR_STREAM_PROGRAM_TAIL_MASK_W],"decoded CALL fields");
                check(cmd_descriptor==templates[tid*33],"descriptor identity");
                for(j=0;j<32;j=j+1) check(cmd_contexts[j*64 +:64]==templates[tid*33+j+1],"per-PE context identity");
                check(cmd_job==start_job&&cmd_tag==start_tag&&cmd_fmt==start_fmt,"captured tags");
                held_contexts=cmd_contexts;
                repeat(3) begin tick();check(cmd_valid&&cmd_contexts==held_contexts&&trace_pc==k,"stalled command stable");end
                if(mode==8) begin
                    cancel=1;assert_quiet();tick();cancel=0;tick();
                    check(image_valid&&start_ready&&!done_valid,"cancel run preserves image");end_test();
                end
                cmd_ready=1;tick();cmd_ready=0;commands=commands+1;
                check(rsp_ready&&!cmd_valid,"single outstanding CALL");
                repeat(2) tick();
                rsp_scalar=64'h8000000000000000+commands;
                if(templates[tid*33][`CSR_STREAM_DESC_OUTPUT_KIND_LSB +: `CSR_STREAM_DESC_OUTPUT_KIND_W]==`CSR_STREAM_OUTPUT_SUM_ACC)
                    last_scalar=rsp_scalar;
                if(mode==10) rsp_tag=0;
                if(mode==11) rsp_fault=4'ha;
                rsp_valid=1;tick();rsp_valid=0;k=k+1;
            end
        end
        check(done_fault==expected,"terminal fault matches");
        check(done_job==start_job&&done_tag==start_tag&&done_fmt==start_fmt,"done identity");
        if(mode==11) check(done_detail==4'ha,"kernel detail retained");
        if(expected==0) check(done_scalar==last_scalar,"last SUM scalar retained");
        if(mode==12||mode==14) check(commands==0,"invalid CALL/format never dispatched");
        repeat(4) begin tick();check(done_valid&&done_fault==expected&&!start_ready,"done held under stall");end
        if(mode==9) begin
            cancel=1;assert_quiet();tick();cancel=0;tick();
            check(!done_valid&&image_valid&&start_ready,"cancel done preserves image");
        end else begin done_ready=1;tick();done_ready=0;check(start_ready,"ready after done ack");end
        rst=1;assert_quiet();tick();rst=0;tick();check(!image_valid&&!start_ready,"reset invalidates complete image");
        end_test();
    end
endmodule
