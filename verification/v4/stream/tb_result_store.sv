`timescale 1ns/1ps
module tb_result_store;
    reg  clk=0;
    reg  rst=0;
    reg  cancel=0;
    reg  abort=0;
    reg  begin_valid=0;
    wire  begin_ready;
    reg [7:0] begin_rows=0;
    reg [10:0] begin_length=0;
    reg [1:0] begin_mode=0;
    reg signed [6:0] begin_exponent=0;
    reg  begin_active_support=0;
    reg [6:0] begin_support_count=0;
    reg [959:0] begin_support=0;
    reg [7:0] begin_status=0;
    reg [15:0] begin_outer_iterations=0;
    reg [15:0] begin_inner_iterations=0;
    reg [15:0] begin_job=0;
    reg [15:0] begin_tag=0;
    reg [7:0] begin_fmt=0;
    reg [127:0] begin_key=0;
    reg [31:0] begin_generation=0;
    reg  fill_valid=0;
    wire  fill_ready;
    reg [4:0] fill_block=0;
    reg [31:0] fill_mask=0;
    reg [863:0] fill_data=0;
    reg  fill_last=0;
    reg [15:0] fill_job=0;
    reg [15:0] fill_tag=0;
    reg [7:0] fill_fmt=0;
    reg  approve_valid=0;
    wire  approve_ready;
    reg  approve=0;
    reg [15:0] approve_job=0;
    reg [15:0] approve_tag=0;
    reg [7:0] approve_fmt=0;
    wire  status_valid;
    reg  status_ready=0;
    wire [3:0] status_fault;
    wire  status_committed;
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
    result_store dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .abort(abort),
        .begin_valid(begin_valid),
        .begin_ready(begin_ready),
        .begin_rows(begin_rows),
        .begin_length(begin_length),
        .begin_mode(begin_mode),
        .begin_exponent(begin_exponent),
        .begin_active_support(begin_active_support),
        .begin_support_count(begin_support_count),
        .begin_support(begin_support),
        .begin_status(begin_status),
        .begin_outer_iterations(begin_outer_iterations),
        .begin_inner_iterations(begin_inner_iterations),
        .begin_job(begin_job),
        .begin_tag(begin_tag),
        .begin_fmt(begin_fmt),
        .begin_key(begin_key),
        .begin_generation(begin_generation),
        .fill_valid(fill_valid),
        .fill_ready(fill_ready),
        .fill_block(fill_block),
        .fill_mask(fill_mask),
        .fill_data(fill_data),
        .fill_last(fill_last),
        .fill_job(fill_job),
        .fill_tag(fill_tag),
        .fill_fmt(fill_fmt),
        .approve_valid(approve_valid),
        .approve_ready(approve_ready),
        .approve(approve),
        .approve_job(approve_job),
        .approve_tag(approve_tag),
        .approve_fmt(approve_fmt),
        .status_valid(status_valid),
        .status_ready(status_ready),
        .status_fault(status_fault),
        .status_committed(status_committed),
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
    integer cycles=0,checks=0,i,j,block_number,offset;
    reg [26:0] expected_value;
    reg [127:0] held_read;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(cycles>100000) $fatal(1,"watchdog state=%0d",dut.state);
    end
    task tick;
        begin @(posedge clk);#1;@(negedge clk);checks=checks+1;end
    endtask
    task configure(input integer n,input integer storage,input integer serial);
        begin
            begin_rows=128;begin_length=n;begin_mode=storage;begin_exponent=-31;
            begin_active_support=0;begin_support_count=0;begin_support=0;
            begin_status=1;begin_outer_iterations=17;begin_inner_iterations=3;
            begin_job=7;begin_tag=serial;begin_fmt=1;begin_key=128'h123456789abc;begin_generation=9;
        end
    endtask
    task launch;
        begin
            begin_valid=1;while(!begin_ready) tick();tick();begin_valid=0;
        end
    endtask
    task frame(input integer n,input integer b,input integer addition);
        begin
            fill_block=b;fill_mask=0;fill_data=0;
            for(j=0;j<32;j=j+1) if(b*32+j<n) begin
                fill_mask[j]=1;
                fill_data[j*27 +: 27]=(b*32+j+addition)*256;
            end
            fill_last=(b+1)*32>=n;fill_job=7;fill_tag=begin_tag;fill_fmt=1;
            fill_valid=1;while(!fill_ready) tick();tick();fill_valid=0;
        end
    endtask
    task approve_candidate(input integer accepted,input integer bad_tag);
        begin
            approve=accepted;approve_job=7;approve_tag=begin_tag+bad_tag;approve_fmt=1;
            approve_valid=1;while(!approve_ready) tick();tick();approve_valid=0;
        end
    endtask
    task status(input integer fault,input integer published);
        begin
            while(!status_valid) tick();
            repeat(5) begin
                tick();
                if(status_fault!==fault[3:0] || status_committed!==published[0]) $fatal(1,"status %0d %0d",status_fault,status_committed);
            end
            status_ready=1;tick();status_ready=0;
        end
    endtask
    task read_word(input integer address,input integer value,input integer fault,input integer serial);
        begin
            read_index=address;read_tag=16'h1000+address;read_valid=1;
            while(!read_ready) tick();tick();read_valid=0;
            while(!read_rsp_valid) tick();
            held_read={read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt};
            repeat(2) begin
                tick();
                if({read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt}!==held_read) $fatal(1,"read hold");
            end
            if(read_rsp_data!==value[26:0] || read_rsp_fault!==fault[3:0] || (fault==0 && read_rsp_tag!==serial[15:0])) $fatal(1,"read index=%0d data=%0d fault=%0d tag=%0d",address,read_rsp_data,read_rsp_fault,read_rsp_tag);
            read_rsp_ready=1;tick();read_rsp_ready=0;
        end
    endtask
    initial begin
        rst=1;repeat(3) tick();rst=0;tick();
        read_word(0,0,7,0);
        configure(33,1,1);launch();
        frame(33,0,1);frame(33,1,1);
        while(!approve_ready) tick();
        if(committed_valid) $fatal(1,"published without approval");
        approve_candidate(1,0);status(0,1);
        for(i=0;i<33;i=i+1) read_word(i,(i+1)*256,0,1);
        read_word(33,0,2,1);
        read_index=0;read_tag=16'h7777;read_valid=1;
        while(!read_ready) tick();tick();read_valid=0;
        while(!read_rsp_valid) tick();
        held_read={read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt};
        configure(1024,2,2);launch();
        for(block_number=0;block_number<32;block_number=block_number+1) frame(1024,block_number,2);
        approve_candidate(1,0);status(0,1);
        configure(1,1,3);begin_valid=1;
        repeat(9) begin
            tick();
            if(begin_ready || !read_rsp_valid || {read_rsp_data,read_rsp_index,read_rsp_request_tag,read_rsp_fault,read_rsp_mode,read_rsp_exponent,read_rsp_length,read_rsp_job,read_rsp_tag,read_rsp_fmt}!==held_read)
                $fatal(1,"old read bank overwritten");
        end
        abort=1;tick();abort=0;tick();
        if(!read_rsp_valid || begin_ready) $fatal(1,"abort stole old read");
        read_rsp_ready=1;tick();read_rsp_ready=0;
        while(!begin_ready) tick();tick();begin_valid=0;
        while(!fill_ready) tick();
        fill_block=0;fill_mask=1;fill_data=256;fill_last=1;fill_job=7;fill_tag=4;fill_fmt=1;fill_valid=1;
        tick();fill_valid=0;status(5,0);
        for(i=0;i<1024;i=i+1) read_word(i,(i+2)*256,0,2);
        if(committed_length!==1024 || committed_mode!==2 || committed_exponent!==-31 || committed_key!==128'h123456789abc || committed_generation!==9) $fatal(1,"committed metadata");
        configure(33,1,4);begin_active_support=1;begin_support_count=2;begin_support[9:0]=1;begin_support[19:10]=1;
        launch();status(2,0);
        configure(1,1,5);launch();while(!fill_ready) tick();
        fill_job=7;fill_tag=5;fill_mask=0;fill_data=0;fill_block=0;fill_last=1;fill_valid=1;tick();fill_valid=0;status(3,0);
        configure(1,1,6);launch();while(!fill_ready) tick();
        fill_tag=6;fill_mask=1;fill_data=1;fill_valid=1;tick();fill_valid=0;status(4,0);
        configure(1,1,7);launch();while(!fill_ready) tick();
        fill_tag=7;fill_data=27'h2000000;fill_valid=1;tick();fill_valid=0;status(4,0);
        configure(1,1,8);launch();frame(1,0,8);approve_candidate(0,0);status(6,0);
        configure(1,1,9);launch();frame(1,0,9);approve_candidate(1,1);status(5,0);
        configure(33,1,10);launch();frame(33,0,10);repeat(5) tick();cancel=1;tick();cancel=0;tick();
        if(status_valid || !committed_valid) $fatal(1,"cancel publication");
        read_word(1023,1025*256,0,2);
        read_index=64;read_valid=1;while(!read_ready) tick();tick();read_valid=0;
        while(!read_rsp_valid) tick();
        cancel=1;#1;if(read_rsp_valid || read_ready) $fatal(1,"cancel accepted a read response");
        tick();cancel=0;tick();
        if(read_rsp_valid || !committed_valid) $fatal(1,"cancel read ownership");
        rst=1;tick();rst=0;tick();read_word(0,0,7,0);
        $display("PASS cycles=%0d checks=%0d",cycles,checks);$finish;
    end
endmodule
