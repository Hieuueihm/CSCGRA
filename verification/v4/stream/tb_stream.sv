`timescale 1ns/1ps
module tb_stream;
reg  clk;
reg  rst;
reg  abort;
reg  cfg_valid;
wire  cfg_ready;
reg [2047:0] cfg_contexts;
wire [3:0] cfg_fault;
wire  cfg_loaded;
reg  cmd_valid;
wire  cmd_ready;
reg [15:0] cmd_job;
reg [15:0] cmd_tag;
reg [7:0] cmd_fmt;
reg  in_valid;
wire  in_ready;
reg [863:0] in_a;
reg [863:0] in_b;
reg [31:0] in_mask;
reg  in_last;
wire  out_valid;
reg  out_ready;
wire [863:0] out_data;
wire [2047:0] out_acc;
wire [31:0] out_mask;
wire [127:0] out_faults;
wire  out_last;
wire  done_valid;
reg  done_ready;
wire [3:0] done_fault;
wire [15:0] done_job;
wire [15:0] done_tag;
wire [7:0] done_fmt;
stream_fabric dut(.clk(clk),.rst(rst),.abort(abort),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_contexts(cfg_contexts),.cfg_fault(cfg_fault),.cfg_loaded(cfg_loaded),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_job(cmd_job),.cmd_tag(cmd_tag),.cmd_fmt(cmd_fmt),.in_valid(in_valid),.in_ready(in_ready),.in_a(in_a),.in_b(in_b),.in_mask(in_mask),.in_last(in_last),.out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_acc(out_acc),.out_mask(out_mask),.out_faults(out_faults),.out_last(out_last),.done_valid(done_valid),.done_ready(done_ready),.done_fault(done_fault),.done_job(done_job),.done_tag(done_tag),.done_fmt(done_fmt));
initial clk=0;always #5 clk=~clk;
reg [863:0] va[0:127],vb[0:127],expected_data[0:127];
reg [2047:0] expected_acc[0:127];reg [127:0] expected_faults[0:127];reg [31:0] masks[0:127];
reg [4095:0] source_path,trace_path;integer src,trace,scan,case_id=0,frames,abort_kind,stall_mode,cfg_error;
integer sent,received,steps,cycles=0,checks=0,aborts=0,total_sent=0,total_received=0,previous_issue,gap,expect_done_fault;
reg [863:0] held_data;reg [2047:0] held_acc;reg [127:0] held_faults;reg [31:0] held_mask;reg held_last,held;
reg [3:0] saved_done_fault;reg [15:0] saved_job,saved_tag;reg [7:0] saved_fmt;
reg [2047:0] config_word;integer format_id;reg aborted;
always @(posedge clk)begin cycles<=cycles+1;if(cycles>200000)$fatal(1,"watchdog");end
task tick;begin @(posedge clk);#1;end endtask
initial begin
rst=0;
abort=0;
cfg_valid=0;
cfg_contexts=0;
cmd_valid=0;
cmd_job=0;
cmd_tag=0;
cmd_fmt=0;
in_valid=0;
in_a=0;
in_b=0;
in_mask=0;
in_last=0;
out_ready=0;
done_ready=0;
if(!$value$plusargs("source=%s",source_path)||!$value$plusargs("trace=%s",trace_path))$fatal(1,"paths");
src=$fopen(source_path,"r");trace=$fopen(trace_path,"w");if(!src||!trace)$fatal(1,"open");
rst=1;repeat(2)tick();@(negedge clk);rst=0;
while(!$feof(src))begin
 scan=$fscanf(src,"%h %d %d %d %d %d",config_word,format_id,frames,abort_kind,stall_mode,cfg_error);
 if(scan==6)begin
  for(integer f=0;f<frames;f=f+1)begin
   scan=$fscanf(src,"%h %h %h %h %h %h",va[f],vb[f],masks[f],expected_data[f],expected_acc[f],expected_faults[f]);
   if(scan!=6)$fatal(1,"frame parse");
  end
  @(negedge clk);cfg_valid=1;cfg_contexts=config_word;#1;if(!cfg_ready)$fatal(1,"config blocked");tick();
  @(negedge clk);cfg_valid=0;
  if(cfg_fault!==cfg_error||cfg_loaded!==(cfg_error==0))$fatal(1,"config result");checks=checks+1;
  if(cfg_error!=0)begin if(cmd_ready)$fatal(1,"bad config allowed");end
  else begin
   cmd_valid=1;cmd_job=16'h8123;cmd_tag=case_id;cmd_fmt=format_id;
   #1;if(!cmd_ready)$fatal(1,"command blocked");tick();@(negedge clk);cmd_valid=0;
   saved_job=cmd_job;saved_tag=cmd_tag;saved_fmt=cmd_fmt;cmd_job=0;cmd_tag=0;cmd_fmt=0;
   sent=0;received=0;steps=0;held=0;aborted=0;previous_issue=-1;expect_done_fault=format_id==1?0:5;
   while(!done_valid&&!aborted&&steps<10000)begin
    cfg_valid=1;cfg_contexts=~config_word; // Busy config writes must be ignored.
    in_valid=sent<frames&&(stall_mode==0||steps%5!=1);in_last=sent==frames-1;
    if(sent<frames)begin in_a=va[sent];in_b=vb[sent];in_mask=masks[sent];end
    out_ready=stall_mode==0?1:(steps%7>=3);
    if((abort_kind==2||abort_kind==5)&&received==0)out_ready=0;
    #1;if(cfg_ready||cmd_ready)$fatal(1,"busy ownership");
    if(held&&(!out_valid||out_data!==held_data||out_acc!==held_acc||out_faults!==held_faults||out_mask!==held_mask||out_last!==held_last))$fatal(1,"held payload changed");
    held=out_valid&&!out_ready;held_data=out_data;held_acc=out_acc;held_faults=out_faults;held_mask=out_mask;held_last=out_last;
    if(in_valid&&in_ready)begin
     if(previous_issue>=0)begin gap=cycles-previous_issue;if(case_id==0&&gap!=1)$fatal(1,"C18 II%0d",gap);if(case_id==1&&gap!=2)$fatal(1,"S27 II%0d",gap);end
     previous_issue=cycles;sent=sent+1;total_sent=total_sent+1;
    end
    if(out_valid&&out_ready)begin
     if(received>=sent||out_data!==expected_data[received]||out_acc!==expected_acc[received]||out_faults!==expected_faults[received]||out_mask!==masks[received]||out_last!==(received==frames-1))
       $fatal(1,"case%0d frame%0d mismatch data%h expected%h acc%h expected%h faults%h expected%h",case_id,received,out_data,expected_data[received],out_acc,expected_acc[received],out_faults,expected_faults[received]);
     for(integer l=0;l<32;l=l+1)if(expect_done_fault==0&&out_faults[l*4+:4]!=0)expect_done_fault=out_faults[l*4+:4];
     checks=checks+98;received=received+1;total_received=total_received+1;
    end
    tick();@(negedge clk);steps=steps+1;
    if(((abort_kind==1||abort_kind==4)&&sent>=1)||((abort_kind==2||abort_kind==5)&&out_valid))begin
     if(abort_kind>=4)rst=1;else abort=1;#1;if(in_ready||out_valid||done_valid||cfg_ready)$fatal(1,"abort visible");tick();@(negedge clk);abort=0;rst=0;aborted=1;aborts=aborts+1;
    end
   end
   cfg_valid=0;in_valid=0;out_ready=0;
   if(aborted)begin tick();if(out_valid||done_valid||cfg_loaded!==(abort_kind<4))$fatal(1,"abort/reset flush");end
   else begin
    if(!done_valid||done_fault!==expect_done_fault||done_job!==saved_job||done_tag!==saved_tag||done_fmt!==saved_fmt||received!=frames)$fatal(1,"done case%0d %0d expected%0d rec%0d frames%0d",case_id,done_fault,expect_done_fault,received,frames);
    saved_done_fault=done_fault;
    repeat(4)begin tick();if(!done_valid||done_fault!==saved_done_fault||done_job!==saved_job||done_tag!==saved_tag||done_fmt!==saved_fmt||in_ready||cmd_ready||cfg_ready)$fatal(1,"done hold");end
    @(negedge clk);
    if(abort_kind==3)begin abort=1;tick();@(negedge clk);abort=0;aborts=aborts+1;if(done_valid||!cfg_loaded)$fatal(1,"done abort");end
    else begin done_ready=1;tick();@(negedge clk);done_ready=0;end
   end
   if(case_id<2)$display("MEASURED case=%0d accepted=%0d II=%0d",case_id,sent,case_id+1);
   $fdisplay(trace,"CASE %0d sent=%0d retired=%0d cycles=%0d fault=%0d abort=%0d",case_id,sent,received,steps,expect_done_fault,aborted);
  end
  case_id=case_id+1;
 end else if(scan!=-1)$fatal(1,"header parse");
end
@(negedge clk);rst=1;tick();if(cfg_loaded||done_valid||out_valid)$fatal(1,"reset config");
$fclose(src);$fclose(trace);$display("PASS stream cases=%0d checks=%0d cycles=%0d accepted=%0d retired=%0d aborts=%0d",case_id,checks,cycles,total_sent,total_received,aborts);$finish;
end
endmodule
