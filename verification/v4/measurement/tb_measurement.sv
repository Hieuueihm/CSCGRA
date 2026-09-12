`timescale 1ns/1ps
module tb_measurement;
reg  clk;
reg  rst;
reg  cancel;
reg  idle;
reg  begin_valid;
wire  begin_ready;
reg [7:0] begin_rows;
reg [15:0] begin_job;
reg [7:0] begin_fmt;
reg  fill_valid;
wire  fill_ready;
reg [1:0] fill_block;
reg [31:0] fill_mask;
reg [575:0] fill_data;
reg  fill_last;
wire  loading;
wire  valid;
wire [3:0] fault;
wire [7:0] rows;
wire [7:0] fmt;
wire [15:0] job;
wire  host_begin_valid;
reg  host_begin_ready;
wire [3:0] host_slot;
wire [7:0] host_length;
wire [15:0] host_job;
wire [15:0] host_tag;
wire [7:0] host_fmt;
wire  host_fill_valid;
reg  host_fill_ready;
wire [1:0] host_fill_block;
wire [31:0] host_fill_mask;
wire [863:0] host_fill_data;
wire  host_fill_last;
reg [3:0] host_fault;
measurement_loader dut(.clk(clk),.rst(rst),.cancel(cancel),.idle(idle),.begin_valid(begin_valid),.begin_ready(begin_ready),.begin_rows(begin_rows),.begin_job(begin_job),.begin_fmt(begin_fmt),.fill_valid(fill_valid),.fill_ready(fill_ready),.fill_block(fill_block),.fill_mask(fill_mask),.fill_data(fill_data),.fill_last(fill_last),.loading(loading),.valid(valid),.fault(fault),.rows(rows),.fmt(fmt),.job(job),.host_begin_valid(host_begin_valid),.host_begin_ready(host_begin_ready),.host_slot(host_slot),.host_length(host_length),.host_job(host_job),.host_tag(host_tag),.host_fmt(host_fmt),.host_fill_valid(host_fill_valid),.host_fill_ready(host_fill_ready),.host_fill_block(host_fill_block),.host_fill_mask(host_fill_mask),.host_fill_data(host_fill_data),.host_fill_last(host_fill_last),.host_fault(host_fault));
initial clk=0;always #5 clk=~clk;
integer cycles=0,checks=0,loads=0,words=0,stalls=0,ep_len=0,ep_block=0,inject=0;
integer n,k,test_id;reg [31:0] ep_mask;reg ep_bad;reg signed [63:0] converted;
always @(posedge clk)begin
 cycles<=cycles+1;if(cycles>5000)$fatal(1,"watchdog");
 if(rst||cancel)begin host_fault<=0;ep_len<=0;ep_block<=0;end
 else begin
  if(host_begin_valid&&host_begin_ready)begin
   if(host_slot!==0||host_tag!==0||host_length!==begin_rows||host_job!==begin_job||host_fmt!==begin_fmt)$fatal(1,"begin identity");
   ep_len<=host_length;ep_block<=0;host_fault<=0;loads<=loads+1;checks<=checks+1;
  end
  if(host_fill_valid&&host_fill_ready)begin
   ep_mask=0;ep_bad=0;
   for(integer j=0;j<32;j=j+1)begin
    ep_mask[j]=ep_block*32+j<ep_len;
    converted=$signed(fill_data[j*18+:18]);converted=converted*256;
    if($signed(host_fill_data[j*27+:27])!==converted)$fatal(1,"signed embedding lane%0d",j);
    if(!ep_mask[j]&&host_fill_data[j*27+:27]!=0)ep_bad=1;
   end
   if(host_fill_block!=ep_block||host_fill_mask!=ep_mask||host_fill_last!=((ep_block+1)*32>=ep_len)||ep_bad)host_fault<=1;
   else if(inject!=0)host_fault<=inject;
   words<=words+1;checks<=checks+32;ep_block<=ep_block+1;
  end
 end
end
task tick;begin @(posedge clk);#1;end endtask
task header(input integer len,input integer format_id);begin
 @(negedge clk);begin_valid=1;begin_rows=len;begin_fmt=format_id;begin_job=16'h8123;host_begin_ready=0;
 repeat(3)begin tick();if(begin_ready||host_begin_valid)$fatal(1,"begin stall");stalls=stalls+1;end
 @(negedge clk);host_begin_ready=1;#1;if(!begin_ready)$fatal(1,"begin blocked");tick();
 @(negedge clk);begin_valid=0;
 if(valid)$fatal(1,"oldvalid at newbegin");
end endtask
task frame(input integer blockno,input integer len,input integer badkind);begin
 @(negedge clk);fill_valid=1;fill_block=blockno;fill_mask=0;fill_data=0;fill_last=(blockno+1)*32>=len;
 for(integer j=0;j<32;j=j+1)if(blockno*32+j<len)begin fill_mask[j]=1;fill_data[j*18+:18]=j%2?-8192:8192;end
 case(badkind)
 1:fill_mask=fill_mask^1;
 2:fill_data[31*18+:18]=1;
 3:fill_block=blockno+1;
 4:fill_last=!fill_last;
 5:fill_data[17:0]=8193;
 6:fill_data[17:0]=-8193;
 7:fill_data[17:0]=-131072;
 endcase
 host_fill_ready=0;
 repeat(4)begin tick();if(fill_ready||host_fill_valid||valid)$fatal(1,"fill stall/valid leak");stalls=stalls+1;end
 @(negedge clk);host_fill_ready=1;#1;if(!fill_ready)$fatal(1,"fill blocked state%0d",dut.state);tick();
 if(valid)$fatal(1,"valid before endpoint checked");
 @(negedge clk);fill_valid=0;tick();
end endtask
task outcome(input integer good,input integer code);begin
 if(loading||valid!==good||fault!==code)$fatal(1,"case%0d outcome load%0d valid%0d fault%0d expected%0d/%0d",test_id,loading,valid,fault,good,code);
 if(good&&(rows!==ep_len||job!==16'h8123||fmt!==1))$fatal(1,"captured owner");
 repeat(3)begin tick();if(valid!==good||fault!==code)$fatal(1,"status hold");end
 checks=checks+1;
end endtask
initial begin
rst=0;
cancel=0;
idle=0;
begin_valid=0;
begin_rows=0;
begin_job=0;
begin_fmt=0;
fill_valid=0;
fill_block=0;
fill_mask=0;
fill_data=0;
fill_last=0;
host_begin_ready=0;
host_fill_ready=0;
rst=1;idle=1;host_begin_ready=1;host_fill_ready=1;repeat(2)tick();@(negedge clk);rst=0;
for(test_id=0;test_id<3;test_id=test_id+1)begin
 n=test_id==0?1:test_id==1?33:128;header(n,1);
 // Caller changes must not alter captured ownership.
 begin_rows=9;begin_job=1;begin_fmt=2;
 for(k=0;k<(n+31)/32;k=k+1)frame(k,n,0);outcome(1,0);
end
for(test_id=3;test_id<7;test_id=test_id+1)begin
 n=test_id==3?0:test_id==4?129:test_id==5?255:1;
 header(n,test_id==6?2:1);outcome(0,1);
end
for(test_id=7;test_id<14;test_id=test_id+1)begin
 header(1,1);frame(0,1,test_id-6);outcome(0,test_id<11?1:2);
end
// Nonfinal overpeak must remain invalid through an otherwise valid final block.
test_id=14;header(33,1);frame(0,33,5);if(valid||!loading)$fatal(1,"partial invalid");frame(1,33,0);outcome(0,2);
// Endpoint fault wins, and a subsequent new load recovers.
test_id=15;header(33,1);inject=9;frame(0,33,0);inject=0;outcome(0,9);
header(1,1);frame(0,1,0);outcome(1,0);
for(test_id=16;test_id<20;test_id=test_id+1)begin
 header(128,1);if(test_id<18)frame(0,128,0);
 @(negedge clk);if(test_id%2)rst=1;else cancel=1;tick();
 if(valid||loading||begin_ready||fill_ready||host_begin_valid||host_fill_valid)$fatal(1,"flush");
 @(negedge clk);rst=0;cancel=0;tick();outcome(0,0);
 header(1,1);frame(0,1,0);outcome(1,0);
end
// Idle lock rejects both header and body handshakes.
@(negedge clk);idle=0;begin_valid=1;fill_valid=1;repeat(3)begin tick();if(begin_ready||fill_ready||host_begin_valid||host_fill_valid)$fatal(1,"idle lock");end
@(negedge clk);idle=1;begin_valid=0;fill_valid=0;
$display("PASS measurement cycles=%0d checks=%0d loads=%0d words=%0d stalls=%0d",cycles,checks,loads,words,stalls);$finish;
end
endmodule
