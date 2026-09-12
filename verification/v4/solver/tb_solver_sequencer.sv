`timescale 1ns/1ps
module tb_solver_sequencer;
reg clk=0;
reg rst=0;
reg cancel=0;
reg load_begin_valid=0;
wire load_begin_ready;
reg [7:0] load_revision=0;
reg load_verified=0;
reg [8:0] load_depth=0;
reg load_valid=0;
wire load_ready;
reg [7:0] load_pc=0;
reg [127:0] load_word=0;
reg load_last=0;
wire image_valid;
wire [3:0] load_fault;
reg start_valid=0;
wire start_ready;
reg [7:0] start_rows=0;
reg [6:0] start_cols=0;
reg [127:0] start_key=0;
reg [31:0] start_generation=0;
reg [15:0] start_job=0;
reg [15:0] start_tag=0;
reg [7:0] start_fmt=0;
reg [7:0] start_max_iterations=0;
reg [31:0] start_instruction_limit=0;
wire done_valid;
reg done_ready=0;
wire [3:0] done_fault;
wire [3:0] done_candidate_slot;
wire [7:0] done_iterations;
wire [63:0] done_normal_energy;
wire [63:0] done_rhs_energy;
wire [15:0] done_job;
wire [15:0] done_tag;
wire [7:0] done_fmt;
wire kernel_valid;
reg kernel_ready=0;
wire [3:0] kernel_op;
wire [3:0] kernel_src_a;
wire [3:0] kernel_src_b;
wire [3:0] kernel_dst;
wire [7:0] kernel_length;
wire [7:0] kernel_rows;
wire [6:0] kernel_cols;
wire kernel_trans;
wire [26:0] kernel_scalar_a;
wire [26:0] kernel_scalar_b;
wire [5:0] kernel_shift;
wire [127:0] kernel_key;
wire [31:0] kernel_generation;
wire [15:0] kernel_job;
wire [15:0] kernel_tag;
wire [7:0] kernel_fmt;
reg kernel_rsp_valid=0;
wire kernel_rsp_ready;
reg [3:0] kernel_rsp_fault=0;
reg [63:0] kernel_rsp_data=0;
reg kernel_rsp_nonzero=0;
reg [15:0] kernel_rsp_job=0;
reg [15:0] kernel_rsp_tag=0;
reg [7:0] kernel_rsp_fmt=0;
wire scalar_valid;
wire scalar_ready;
wire [1:0] scalar_op;
wire signed [63:0] scalar_a;
wire signed [63:0] scalar_b;
wire [7:0] scalar_source_frac;
wire [15:0] scalar_job;
wire [15:0] scalar_tag;
wire [7:0] scalar_fmt;
wire scalar_rsp_valid;
wire scalar_rsp_ready;
wire signed [26:0] scalar_rsp_data;
wire [2:0] scalar_rsp_fault;
wire [15:0] scalar_rsp_job;
wire [15:0] scalar_rsp_tag;
wire [7:0] scalar_rsp_fmt;
wire running;
wire [7:0] trace_pc;
wire [127:0] trace_word;
wire trace_retire;
solver_sequencer dut(.*);
always #5 clk=~clk;
wire [0:0] service_valid;
assign scalar_rsp_valid=service_valid;
wire [26:0] service_data;
assign scalar_rsp_data=inject==4?27'h4000000:service_data;
wire [2:0] service_fault;
assign scalar_rsp_fault=service_fault;
wire [15:0] service_job;
assign scalar_rsp_job=service_job;
wire [15:0] service_tag;
assign scalar_rsp_tag=service_tag+(inject==3);
wire [7:0] service_fmt;
assign scalar_rsp_fmt=service_fmt;
wire service_ready; wire scalar_gate=(cycles%3)!=0;
assign scalar_ready=service_ready&&scalar_gate;
scalar_service scalar (.clk(clk),.rst(rst),.cancel(cancel),.req_valid(scalar_valid&&scalar_gate),.req_ready(service_ready),
.req_op(scalar_op),.req_a(scalar_a),.req_b(scalar_b),.req_source_frac(scalar_source_frac),.req_job(scalar_job),.req_tag(scalar_tag),.req_fmt(scalar_fmt),
.rsp_valid(service_valid),.rsp_ready(scalar_rsp_ready),.rsp_data(service_data),.rsp_fault(service_fault),.rsp_job(service_job),.rsp_tag(service_tag),.rsp_fmt(service_fmt));
integer cycles=0; always @(posedge clk) cycles<=cycles+1;
always @(negedge clk) if(running&&(load_ready||load_begin_ready||start_ready))$fatal(1,"running ownership");
always @(negedge clk) if(trace_retire&&trace_word!==words[trace_pc])$fatal(1,"retired trace mismatch");
reg [4095:0] program_path,kernel_path;
reg [127:0] words[0:255];
integer fd,rc,i,j,shape_rows,shape_cols,budget,watchdog,inject,abort_cycle,load_mode;
integer exp_op,exp_srca,exp_srcb,exp_dst,exp_length,exp_trans,exp_shift,exp_nonzero;
reg [26:0] exp_a,exp_b;reg [63:0] exp_data;reg [15:0] saved_tag;reg [255:0] saved_request;
task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
initial begin
if(!$value$plusargs("program=%s",program_path)||!$value$plusargs("kernels=%s",kernel_path))$fatal(1,"paths");
if(!$value$plusargs("rows=%d",shape_rows))shape_rows=4;
if(!$value$plusargs("cols=%d",shape_cols))shape_cols=2;
if(!$value$plusargs("budget=%d",budget))budget=32;
if(!$value$plusargs("watchdog=%d",watchdog))watchdog=10000;
if(!$value$plusargs("inject=%d",inject))inject=0;
if(!$value$plusargs("abort=%d",abort_cycle))abort_cycle=0;
if(!$value$plusargs("loadmode=%d",load_mode))load_mode=0;
$readmemh(program_path,words); fd=$fopen(kernel_path,"r");if(!fd)$fatal(1,"kernel file");
rst=1;tick();rst=0;tick();load_begin_valid=1;load_revision=load_mode==1?2:1;load_verified=load_mode!=2;load_depth=256;tick();load_begin_valid=0;
if(load_mode==0||load_mode==3||load_mode==4)begin for(i=0;i<256;i=i+1)begin load_valid=1;load_pc=(load_mode==3&&i==255)?0:i;load_word=words[i];load_last=(i==255)||(load_mode==4&&i==3);tick();end load_valid=0;end
start_valid=1;start_rows=shape_rows;start_cols=shape_cols;start_key=128'h1234;start_generation=77;start_job=12;start_tag=123;start_fmt=1;start_max_iterations=budget;start_instruction_limit=watchdog;tick();start_valid=0;
begin:execute_loop
while(!done_valid)begin
if(cycles>1000000)$fatal(1,"simulation watchdog");
if(abort_cycle!=0&&cycles>=260+abort_cycle)begin
cancel=1;tick();cancel=0;tick();if(running||done_valid||kernel_valid||scalar_valid||!image_valid)$fatal(1,"cancel epoch");
$display("ABORT PASS cycles=%0d",cycles);$finish;end
if(kernel_valid)begin
rc=$fscanf(fd,"%d %d %d %d %d %d %h %h %d %h %d\n",exp_op,exp_srca,exp_srcb,exp_dst,exp_length,exp_trans,exp_a,exp_b,exp_shift,exp_data,exp_nonzero);
if(rc!=11)$fatal(1,"unexpected kernel at PC%0d",trace_pc);
if(kernel_op!=exp_op||kernel_src_a!=exp_srca||kernel_src_b!=exp_srcb||kernel_dst!=exp_dst||kernel_length!=exp_length||kernel_trans!=exp_trans||kernel_scalar_a!=exp_a||kernel_scalar_b!=exp_b||kernel_shift!=exp_shift)$fatal(1,"kernel request PC%0d",trace_pc);
if(kernel_key!=128'h1234||kernel_generation!=77||kernel_job!=12||kernel_fmt!=1)$fatal(1,"kernel identity");
saved_tag=kernel_tag;saved_request={kernel_op,kernel_src_a,kernel_src_b,kernel_dst,kernel_length,kernel_rows,kernel_cols,kernel_trans,kernel_scalar_a,kernel_scalar_b,kernel_shift,kernel_tag};
for(j=0;j<3;j=j+1)begin tick();if(!kernel_valid||saved_request!={kernel_op,kernel_src_a,kernel_src_b,kernel_dst,kernel_length,kernel_rows,kernel_cols,kernel_trans,kernel_scalar_a,kernel_scalar_b,kernel_shift,kernel_tag})$fatal(1,"request changed under stall");end
kernel_ready=1;tick();kernel_ready=0;for(j=0;j<2;j=j+1)tick();
kernel_rsp_valid=1;kernel_rsp_job=12;kernel_rsp_tag=saved_tag+(inject==1);kernel_rsp_fmt=1;kernel_rsp_data=exp_data;kernel_rsp_nonzero=exp_nonzero;kernel_rsp_fault=inject==2?1:0;
if(!kernel_rsp_ready)$fatal(1,"response readiness");tick();kernel_rsp_valid=0;
end else tick();
end end
$display("DONE fault=%0d iterations=%0d normal=%0d rhs=%0d job=%0d tag=%0d fmt=%0d slot=%0d",done_fault,done_iterations,done_normal_energy,done_rhs_energy,done_job,done_tag,done_fmt,done_candidate_slot);
saved_request={done_fault,done_iterations,done_normal_energy,done_rhs_energy,done_job,done_tag,done_fmt,done_candidate_slot};
for(j=0;j<4;j=j+1)begin tick();if(!done_valid||saved_request!={done_fault,done_iterations,done_normal_energy,done_rhs_energy,done_job,done_tag,done_fmt,done_candidate_slot})$fatal(1,"done stall");end
done_ready=1;tick();done_ready=0;tick();if(done_valid||running)$fatal(1,"done retirement");
$fclose(fd);$display("PASS cycles=%0d",cycles);$finish;
end
endmodule
