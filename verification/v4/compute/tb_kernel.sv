`timescale 1ns/1ps
module tb_kernel;
reg  clk;
reg  rst;
reg  cancel;
reg  req_valid;
wire  req_ready;
reg [3:0] req_op;
reg [3:0] req_src_a;
reg [3:0] req_src_b;
reg [3:0] req_dst;
reg [7:0] req_length;
reg [7:0] req_rows;
reg [6:0] req_cols;
reg  req_trans;
reg [26:0] req_scalar_a;
reg [26:0] req_scalar_b;
reg [5:0] req_shift;
reg [127:0] req_key;
reg [31:0] req_generation;
reg [15:0] req_job;
reg [15:0] req_tag;
reg [7:0] req_fmt;
wire  rsp_valid;
reg  rsp_ready;
wire [3:0] rsp_fault;
wire [63:0] rsp_data;
wire  rsp_nonzero;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
reg  host_begin_valid;
wire  host_begin_ready;
reg [3:0] host_slot;
reg [7:0] host_length;
reg [15:0] host_job;
reg [15:0] host_tag;
reg [7:0] host_fmt;
reg  host_fill_valid;
wire  host_fill_ready;
reg [1:0] host_fill_block;
reg [31:0] host_fill_mask;
reg [863:0] host_fill_data;
reg  host_fill_last;
wire [3:0] host_fault;
reg  debug_valid;
wire  debug_ready;
reg [3:0] debug_slot;
reg [1:0] debug_block;
wire  debug_rsp_valid;
reg  debug_rsp_ready;
wire [863:0] debug_rsp_data;
wire [31:0] debug_rsp_mask;
wire [3:0] debug_rsp_fault;
wire  mat_valid;
wire  mat_ready;
wire  mat_dense;
wire [31:0] mat_mask;
wire [287:0] mat_addr;
wire [127:0] mat_key;
wire [31:0] mat_generation;
wire [15:0] mem_job;
wire [15:0] mem_tag;
wire [7:0] mem_fmt;
wire  mat_rsp_valid;
wire  mat_rsp_ready;
wire [575:0] mat_rsp_data;
wire [255:0] mat_rsp_masks;
wire [31:0] mat_rsp_mask;
wire [31:0] mat_rsp_generation;
wire [15:0] mat_rsp_job;
wire [15:0] mat_rsp_tag;
wire [7:0] mat_rsp_fmt;
wire [3:0] mat_rsp_fault;
kernel_engine dut(.clk(clk),.rst(rst),.cancel(cancel),.req_valid(req_valid),.req_ready(req_ready),.req_op(req_op),.req_src_a(req_src_a),.req_src_b(req_src_b),.req_dst(req_dst),.req_length(req_length),.req_rows(req_rows),.req_cols(req_cols),.req_trans(req_trans),.req_scalar_a(req_scalar_a),.req_scalar_b(req_scalar_b),.req_shift(req_shift),.req_key(req_key),.req_generation(req_generation),.req_job(req_job),.req_tag(req_tag),.req_fmt(req_fmt),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_fault(rsp_fault),.rsp_data(rsp_data),.rsp_nonzero(rsp_nonzero),.rsp_job(rsp_job),.rsp_tag(rsp_tag),.rsp_fmt(rsp_fmt),.host_begin_valid(host_begin_valid),.host_begin_ready(host_begin_ready),.host_slot(host_slot),.host_length(host_length),.host_job(host_job),.host_tag(host_tag),.host_fmt(host_fmt),.host_fill_valid(host_fill_valid),.host_fill_ready(host_fill_ready),.host_fill_block(host_fill_block),.host_fill_mask(host_fill_mask),.host_fill_data(host_fill_data),.host_fill_last(host_fill_last),.host_fault(host_fault),.debug_valid(debug_valid),.debug_ready(debug_ready),.debug_slot(debug_slot),.debug_block(debug_block),.debug_rsp_valid(debug_rsp_valid),.debug_rsp_ready(debug_rsp_ready),.debug_rsp_data(debug_rsp_data),.debug_rsp_mask(debug_rsp_mask),.debug_rsp_fault(debug_rsp_fault),.mat_valid(mat_valid),.mat_ready(mat_ready),.mat_dense(mat_dense),.mat_mask(mat_mask),.mat_addr(mat_addr),.mat_key(mat_key),.mat_generation(mat_generation),.mem_job(mem_job),.mem_tag(mem_tag),.mem_fmt(mem_fmt),.mat_rsp_valid(mat_rsp_valid),.mat_rsp_ready(mat_rsp_ready),.mat_rsp_data(mat_rsp_data),.mat_rsp_masks(mat_rsp_masks),.mat_rsp_mask(mat_rsp_mask),.mat_rsp_generation(mat_rsp_generation),.mat_rsp_job(mat_rsp_job),.mat_rsp_tag(mat_rsp_tag),.mat_rsp_fmt(mat_rsp_fmt),.mat_rsp_fault(mat_rsp_fault));
initial clk=0;always #5 clk=~clk;
integer cycles=0, checks=0,t,b,l,n,opn;reg signed [26:0] va[0:127],vb[0:127],gold[0:127];reg signed [63:0] expected_scalar;
integer oracle_fd,scan,oracle_fault,oracle_cases=0;reg [4095:0] oracle_path;
always @(posedge clk) begin cycles<=cycles+1;if(cycles>200000) $fatal(1,"timeout state=%0d",dut.state);end
task tick;begin @(posedge clk);#1;end endtask
task load_slot(input integer slot,input integer len,input integer source);begin
 @(negedge clk);host_begin_valid=1;host_slot=slot;host_length=len;host_job=7;host_fmt=1;
 while(!host_begin_ready) tick();tick();@(negedge clk);host_begin_valid=0;
 for(integer k=0;k<(len+31)/32;k=k+1) begin
  host_fill_valid=1;host_fill_block=k;host_fill_mask=0;host_fill_data=0;host_fill_last=(k+1)*32>=len;
  for(integer j=0;j<32;j=j+1) if(k*32+j<len) begin host_fill_mask[j]=1;host_fill_data[j*27+:27]=source==0?va[k*32+j]:vb[k*32+j];end
  tick();@(negedge clk);host_fill_valid=0;
 end
 if(host_fault!=0) $fatal(1,"host fault");
end endtask
task command(input integer opcode,input integer len,input integer dst,input integer fault);reg [63:0] held;reg expected_nonzero;begin
 @(negedge clk);req_valid=1;req_op=opcode;req_length=len;req_dst=dst;req_job=7;req_fmt=1;req_tag=req_tag+1;
 while(!req_ready) tick();tick();@(negedge clk);req_valid=0;
 while(!rsp_valid) tick();
 if(rsp_fault!==fault) $fatal(1,"op%0d fault %0d expected%0d state%0d",opcode,rsp_fault,fault,dut.state);
 if(fault==0&&opcode!=7&&opcode!=9&&opcode!=10)begin
 expected_nonzero=0;for(integer q=0;q<len;q=q+1)if(opcode!=0&&gold[q]!=0)expected_nonzero=1;
 if(rsp_nonzero!==expected_nonzero)$fatal(1,"nonzero flag op%0d",opcode);checks=checks+1;
 end
 if(rsp_job!==7||rsp_tag!==req_tag||rsp_fmt!==1)$fatal(1,"response identity");
 held=rsp_data;repeat(3) begin tick();if(!rsp_valid||rsp_data!==held||rsp_fault!==fault) $fatal(1,"held response");end
 if(fault==0&&(opcode==7||opcode==9||opcode==10)) begin if($signed(rsp_data)!==expected_scalar) $fatal(1,"scalar op%0d got%0d exp%0d",opcode,$signed(rsp_data),expected_scalar);checks=checks+1;end
 @(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;
end endtask
task check_slot(input integer slot,input integer len,input integer fault);begin
 for(integer k=0;k<(len+31)/32;k=k+1) begin
  @(negedge clk);debug_valid=1;debug_slot=slot;debug_block=k;
  while(!debug_ready) tick();tick();@(negedge clk);debug_valid=0;
  while(!debug_rsp_valid) tick();
  if(debug_rsp_fault!==fault) $fatal(1,"debug fault %0d expected%0d",debug_rsp_fault,fault);
  if(fault==0) for(integer j=0;j<32;j=j+1) begin
   if(debug_rsp_mask[j]!== (k*32+j<len)) $fatal(1,"mask");
   if(k*32+j<len&&$signed(debug_rsp_data[j*27+:27])!==gold[k*32+j]) $fatal(1,"op%0d index%0d got%0d exp%0d",req_op,k*32+j,$signed(debug_rsp_data[j*27+:27]),gold[k*32+j]);
   checks=checks+1;
  end
  repeat(2)tick();@(negedge clk);debug_rsp_ready=1;tick();@(negedge clk);debug_rsp_ready=0;
 end
end endtask

reg mbegin=0,mfill=0;wire mbready,mfready,mloading,mvalid;wire [3:0] mfault;
reg [7:0] mrows;reg [6:0] mcols,mslot;reg [1:0] mblock;reg [31:0] mmask;reg [575:0] mdata;reg mlast;
wire cache_ready,cache_valid;wire [3:0] cache_fault;integer inject_after=0;
assign mat_rsp_fault=(inject_after!=0&&frames>=inject_after)?4'd3:cache_fault;wire stall_req=cycles%7==0,stall_rsp=cycles%11<3;
integer frames=0,req_stalls=0,rsp_stalls=0;
assign mat_ready=cache_ready&&!stall_req;
assign mat_rsp_valid=cache_valid&&!stall_rsp;
assign mat_rsp_masks=0;
support_matrix_cache matrix_cache(.clk(clk),.rst(rst),.cancel(cancel),
 .begin_valid(mbegin),.begin_ready(mbready),.begin_rows(mrows),.begin_cols(mcols),.begin_key(128'h1234),.begin_generation(32'd9),.begin_job(16'd7),.begin_fmt(8'd1),
 .fill_valid(mfill),.fill_ready(mfready),.fill_slot(mslot),.fill_block(mblock),.fill_mask(mmask),.fill_data(mdata),.fill_last(mlast),.loading(mloading),.cache_valid(mvalid),.load_fault(mfault),
 .rd_valid(mat_valid&&!stall_req),.rd_ready(cache_ready),.rd_mask(mat_mask),.rd_addr(mat_addr),.rd_key(mat_key),.rd_generation(mat_generation),.rd_job(mem_job),.rd_tag(mem_tag),.rd_fmt(mem_fmt),
 .rsp_valid(cache_valid),.rsp_ready(mat_rsp_ready&&!stall_rsp),.rsp_data(mat_rsp_data),.rsp_mask(mat_rsp_mask),.rsp_generation(mat_rsp_generation),.rsp_job(mat_rsp_job),.rsp_tag(mat_rsp_tag),.rsp_fmt(mat_rsp_fmt),.rsp_fault(cache_fault));
always @(posedge clk)begin
 if(mat_valid&&mat_ready)frames<=frames+1;
 if(mat_valid&&!mat_ready)req_stalls<=req_stalls+1;
 if(cache_valid&&(!mat_rsp_ready||stall_rsp))rsp_stalls<=rsp_stalls+1;
end
function integer coefficient(input integer row,input integer col);begin coefficient=((row*17+col*31)%41-20)*123;end endfunction
task load_matrix(input integer nr,input integer nc);begin
 @(negedge clk);mrows=nr;mcols=nc;mbegin=1;while(!mbready)tick();tick();@(negedge clk);mbegin=0;
 for(integer c=0;c<nc;c=c+1)for(integer k=0;k<(nr+31)/32;k=k+1)begin
  mfill=1;mslot=c;mblock=k;mmask=0;mdata=0;mlast=c==nc-1&&(k+1)*32>=nr;
  for(integer j=0;j<32;j=j+1)if(k*32+j<nr)begin mmask[j]=1;mdata[j*18+:18]=coefficient(k*32+j,c);end
  tick();@(negedge clk);mfill=0;
 end
 if(!mvalid||mfault) $fatal(1,"matrix load fault");
end endtask
task gemv(input integer nr,input integer nc,input integer tr);integer before_frames,outn,redn;reg signed [63:0] sum;begin
 load_matrix(nr,nc);req_rows=nr;req_cols=nc;req_trans=tr;req_key=128'h1234;req_generation=9;req_src_a=0;
 outn=tr?nc:nr;redn=tr?nr:nc;load_slot(0,redn,0);
 for(integer o=0;o<outn;o=o+1)begin
  sum=0;for(integer k=0;k<redn;k=k+1)sum=sum+$signed(va[k])*(tr?coefficient(k,o):coefficient(o,k));
  gold[o]=sum<0?-((-sum+32768)>>>16):(sum+32768)>>>16;
 end
 before_frames=frames;command(6,outn,2,0);check_slot(2,outn,0);
 if(frames-before_frames!=((outn+31)/32)*redn)$fatal(1,"frame count");
 $display("GEMV rows=%0d cols=%0d trans=%0d frames=%0d cycles=%0d",nr,nc,tr,frames-before_frames,cycles);
end endtask

initial begin
rst=0;
cancel=0;
req_valid=0;
req_op=0;
req_src_a=0;
req_src_b=0;
req_dst=0;
req_length=0;
req_rows=0;
req_cols=0;
req_trans=0;
req_scalar_a=0;
req_scalar_b=0;
req_shift=0;
req_key=0;
req_generation=0;
req_job=0;
req_tag=0;
req_fmt=0;
rsp_ready=0;
host_begin_valid=0;
host_slot=0;
host_length=0;
host_job=0;
host_tag=0;
host_fmt=0;
host_fill_valid=0;
host_fill_block=0;
host_fill_mask=0;
host_fill_data=0;
host_fill_last=0;
debug_valid=0;
debug_slot=0;
debug_block=0;
debug_rsp_ready=0;
rst=1;repeat(3)tick();@(negedge clk);rst=0;
req_src_a=0;req_src_b=1;req_scalar_a=2097152;req_scalar_b=-4194304;
for(t=0;t<6;t=t+1) begin
 case(t)0:n=1;1:n=31;2:n=32;3:n=33;4:n=96;5:n=128;endcase
 for(l=0;l<128;l=l+1)begin va[l]=(l%2?-1:1)*(l*12345+17);vb[l]=(l%3?-1:1)*(l*2345+3);end
 load_slot(0,n,0);load_slot(1,n,1);
 for(opn=0;opn<=8;opn=opn+1) if(opn!=6) begin
  expected_scalar=0;req_shift=22;
  for(l=0;l<n;l=l+1)begin
   case(opn)
    0:gold[l]=0;1:gold[l]=va[l];2:gold[l]=va[l]+vb[l];3:gold[l]=va[l]-vb[l];
    4,5:gold[l]=va[l]<0?-((-va[l]+1)/2):(va[l]+1)/2;
    7:begin expected_scalar=expected_scalar+$signed(va[l])*$signed(va[l]);gold[l]=va[l];end
    8:gold[l]=(va[l]<0?-((-va[l]+2)/4):(va[l]+2)/4)*4;
   endcase
  end
  command(opn,n,2,0);if(opn!=7)check_slot(2,n,0);
 end
 // Alias-safe copy and add across all blocks.
 for(l=0;l<n;l=l+1)gold[l]=va[l]+vb[l];command(2,n,0,0);check_slot(0,n,0);
end
expected_scalar=-2097152;command(9,0,0,0);
expected_scalar=64'sd2097152*2097152+64'sd4194304*4194304;command(10,0,0,0);
// Scalar fault must preserve unrelated destination.
req_fmt=1;for(l=0;l<n;l=l+1)gold[l]=va[l]+vb[l];
req_src_a=15;command(7,n,0,2);check_slot(0,n,0);
req_src_a=1;req_scalar_a=67108863;req_shift=0;command(5,n,2,4);check_slot(2,n,2);

gemv(1,1,0);gemv(33,17,0);gemv(17,33,1);gemv(128,96,0);gemv(128,96,1);
req_key=128'h9999;command(6,96,2,5);check_slot(2,96,2);
req_key=128'h1234;req_generation=8;command(6,96,2,5);
req_generation=9;command(6,96,2,0);check_slot(2,96,0);

// Python arbitrary-integer vectors, including single-round normalization and extrema.
if($value$plusargs("oracle=%s",oracle_path))begin
 oracle_fd=$fopen(oracle_path,"r");if(oracle_fd==0)$fatal(1,"oracle missing");
 while(!$feof(oracle_fd))begin
  scan=$fscanf(oracle_fd,"%d %d %d %d %d %d %d",opn,n,req_scalar_a,req_scalar_b,req_shift,oracle_fault,expected_scalar);
  if(scan==7)begin
   for(l=0;l<128;l=l+1)begin scan=$fscanf(oracle_fd,"%d",va[l]);if(scan!=1)$fatal(1,"oracle A");end
   for(l=0;l<128;l=l+1)begin scan=$fscanf(oracle_fd,"%d",vb[l]);if(scan!=1)$fatal(1,"oracle B");end
   for(l=0;l<128;l=l+1)begin scan=$fscanf(oracle_fd,"%d",gold[l]);if(scan!=1)$fatal(1,"oracle gold");end
   req_src_a=0;req_src_b=1;load_slot(0,n,0);load_slot(1,n,1);
   command(opn,n,2,oracle_fault);if(opn!=7&&opn!=9&&opn!=10)check_slot(2,n,oracle_fault!=0?2:0);
   oracle_cases=oracle_cases+1;
  end else if(scan!=-1)$fatal(1,"oracle header");
 end
 $fclose(oracle_fd);
end
// Failure after a full output block has been staged must invalidate destination.
req_src_a=0;req_rows=128;req_cols=96;req_trans=0;req_key=128'h1234;req_generation=9;
load_matrix(128,96);load_slot(0,96,0);inject_after=frames+100;
command(6,128,2,5);check_slot(2,128,2);inject_after=0;
// Recovery after the failed read transaction drains.
command(0,128,2,0);for(l=0;l<128;l=l+1)gold[l]=0;check_slot(2,128,0);
// Cancel at arithmetic, candidate commit and held response: epoch invalidation.
for(t=0;t<4;t=t+1)begin
 load_slot(0,128,0);@(negedge clk);req_op=1;req_length=128;req_dst=2;req_valid=1;
 while(!req_ready)tick();tick();@(negedge clk);req_valid=0;
 while(dut.state!=(t==0?7:t==1?15:17))tick();
 @(negedge clk);if(t==3)rst=1;else cancel=1;tick();if(rsp_valid||req_ready||debug_rsp_valid)$fatal(1,"cancel visibility");
 @(negedge clk);cancel=0;rst=0;tick();check_slot(2,128,2);
 command(0,128,2,0);for(l=0;l<128;l=l+1)gold[l]=0;check_slot(2,128,0);
end

// Rejected scalar format leaves the existing destination intact.
@(negedge clk);req_valid=1;req_op=9;req_fmt=2;req_dst=2;
while(!req_ready)tick();tick();@(negedge clk);req_valid=0;
while(!rsp_valid)tick();if(rsp_fault!==1)$fatal(1,"format fault");
@(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;req_fmt=1;check_slot(2,128,0);
// Host prevalidation and malformed fill invalidate only the target.
@(negedge clk);host_begin_valid=1;host_slot=3;host_length=0;
tick();@(negedge clk);host_begin_valid=0;if(host_fault!==1)$fatal(1,"host length");check_slot(3,1,2);
@(negedge clk);host_begin_valid=1;host_length=33;tick();@(negedge clk);host_begin_valid=0;
host_fill_valid=1;host_fill_block=1;host_fill_mask=1;host_fill_data=0;host_fill_last=1;tick();@(negedge clk);host_fill_valid=0;
if(host_fault!==1)$fatal(1,"host order");check_slot(3,33,2);check_slot(2,128,0);
$display("ORACLE cases=%0d",oracle_cases);
$display("STALLS request=%0d response=%0d",req_stalls,rsp_stalls);
$display("PASS kernel checks=%0d cycles=%0d",checks,cycles);$finish;
end
endmodule
