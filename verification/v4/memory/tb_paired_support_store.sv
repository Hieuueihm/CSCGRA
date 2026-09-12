`include "memory_defs.vh"
`timescale 1ns/1ps
module tb_paired_support_store;
reg clk=0, rst=1, cancel=0;
    reg begin_valid;
    wire begin_ready;
    reg [7:0] begin_rows;
    reg [6:0] begin_cols;
    reg [127:0] begin_key;
    reg [31:0] begin_generation;
    reg [15:0] begin_job;
    reg [7:0] begin_fmt;
    reg fill_valid;
    wire fill_ready;
    reg [6:0] fill_slot;
    reg [1:0] fill_block;
    reg [31:0] fill_mask;
    reg [32*`CSR_PE_C_W-1:0] fill_data;
    reg fill_last;
    wire loading, cache_valid;
    wire [3:0] load_fault;
    reg rd_valid;
    wire rd_ready;
    reg [31:0] rd_mask;
    reg [32*`CSR_MEM_B_AW-1:0] rd_addr;
    reg [127:0] rd_key;
    reg [31:0] rd_generation;
    reg [15:0] rd_job, rd_tag;
    reg [7:0] rd_fmt;
    wire rsp_valid;
    reg rsp_ready;
    wire [32*`CSR_PE_C_W-1:0] rsp_data;
    wire [31:0] rsp_mask;
    wire [31:0] rsp_generation;
    wire [15:0] rsp_job, rsp_tag;
    wire [7:0] rsp_fmt;
    wire [3:0] rsp_fault;
    always #5 clk=~clk;
    paired_support_store dut(.*);
    reg [575:0] expected_data[0:1023],wanted;
    reg [111:0] expected_meta[0:1023];
    reg [687:0] held_data;
    reg held=0;
    integer head=0,tail=0,checks=0,cycles=0,reads=0,stalls=0,flushed=0;
    integer i,k,b,r,c,a,start_cycle,want_fault=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst||cancel) begin flushed=flushed+tail-head;head=0;tail=0;held=0;end
        else begin
            if(held&&(!rsp_valid||held_data!=={rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt,rsp_mask,rsp_data})) $fatal(1,"held response changed");
            held=rsp_valid&&!rsp_ready;
            held_data={rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt,rsp_mask,rsp_data};
            if(rsp_valid&&rsp_ready) begin
                if(head==tail||rsp_data!==expected_data[head]||
                   {rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt,rsp_mask}!==expected_meta[head]) $fatal(1,"queue/payload mismatch tag%0d",rsp_tag);
                head=head+1;checks=checks+36;
            end
            if(rd_valid&&!rd_ready) stalls=stalls+1;
            if(rd_valid&&rd_ready) begin
                wanted=0;
                if(want_fault==0) for(b=0;b<32;b=b+1) if(rd_mask[b]) begin
                    a=rd_addr[b*9 +: 9];r=a/3;c=(a%3)*32+(b+32-r%32)%32;
                    wanted[b*18 +: 18]=18'(r*101-c*53);
                end
                expected_data[tail]=wanted;
                expected_meta[tail]={4'(want_fault),rd_generation,rd_job,rd_tag,rd_fmt,want_fault==0 ? rd_mask : 32'b0};
                tail=tail+1;reads=reads+1;
            end
        end
    end
    task request(input integer index,input integer fault_code);
        integer bank;
        begin
            @(negedge clk);rd_valid=1;rd_tag=index;want_fault=fault_code;
            for(bank=0;bank<32;bank=bank+1) rd_addr[bank*9 +: 9]=9'((index+bank*7)%384);
            if(fault_code==4) rd_addr[8:0]=511;
            @(posedge clk);while(!rd_ready) @(posedge clk);
        end
    endtask
    task drain;
        begin @(negedge clk);rd_valid=0;rsp_ready=1;repeat(5) @(negedge clk);if(head!=tail) $fatal(1,"not drained");end
    endtask
    initial begin
        begin_valid=0;begin_rows=128;begin_cols=96;begin_key=92;begin_generation=2;begin_job=7;begin_fmt=1;
        fill_valid=0;fill_slot=0;fill_block=0;fill_mask='1;fill_data=0;fill_last=0;
        rd_valid=0;rd_mask='1;rd_addr=0;rd_key=92;rd_generation=2;rd_job=7;rd_tag=0;rd_fmt=1;rsp_ready=1;
        repeat(3) @(negedge clk);rst=0;begin_valid=1;
        @(negedge clk);begin_valid=0;
        for(i=0;i<96;i=i+1) for(k=0;k<4;k=k+1) begin
            fill_valid=1;fill_slot=i;fill_block=k;fill_last=i==95&&k==3;
            for(b=0;b<32;b=b+1) fill_data[b*18 +: 18]=18'((k*32+b)*101-i*53);
            @(negedge clk);
        end
        fill_valid=0;if(!cache_valid||load_fault!==0) $fatal(1,"fill failed");
        start_cycle=cycles;
        for(i=0;i<512;i=i+1) request(i,0);
        if(cycles-start_cycle!=512) $fatal(1,"paired B lost II1");
        drain();rsp_ready=0;request(512,0);request(513,0);
        @(negedge clk);rd_valid=1;begin_valid=1;
        repeat(5) begin @(negedge clk);if(rd_ready||begin_ready) $fatal(1,"credit/ownership violation");end
        begin_valid=0;drain();
        rd_mask=32'h5555aaaa;request(600,0);drain();
        rd_generation=3;request(601,3);drain();rd_generation=2;
        rd_mask='1;request(602,4);drain();
        rsp_ready=0;request(603,0);request(604,0);
        @(negedge clk);rd_valid=0;cancel=1;
        repeat(2) @(negedge clk);cancel=0;
        if(cache_valid||rsp_valid) $fatal(1,"cancel retained publication/response");
        rsp_ready=1;request(605,3);drain();
        if(stalls<5||flushed!=2) $fatal(1,"missing coverage");
        $display("PASS paired_support_store cycles=%0d checks=%0d reads=%0d stalls=%0d flushed=%0d",cycles,checks,reads,stalls,flushed);$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
