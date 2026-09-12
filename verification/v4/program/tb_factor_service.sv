`timescale 1ns/1ps
module tb_factor_service;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,cancel=0,req_valid=0;wire req_ready;
 reg [5:0] req_op=0;reg [8:0] req_src_a=0,req_dst=0;
 reg [7:0] req_rows=0;reg [10:0] req_cols=0,req_length=0,req_index=0,req_aux_length=0;
 reg [7:0] req_flags=0;reg req_matrix_dense=1;
 reg [127:0] req_key=128'h55;reg [31:0] req_generation=1;reg [15:0] req_job=7,req_tag=0;reg [7:0] req_fmt=1;
 reg matrix_valid=1;reg [7:0] matrix_rows=0;reg [10:0] matrix_cols=0;
 reg [127:0] matrix_key=128'h55;reg [31:0] matrix_generation=1;reg [15:0] matrix_job=7;reg [7:0] matrix_fmt=1;
 wire mat_valid,mat_dense,mat_rsp_ready;wire mat_ready;
 wire [31:0] mat_mask,mat_generation;wire [287:0] mat_addr;wire [127:0] mat_key;wire [15:0] mat_job,mat_tag;wire [7:0] mat_fmt;
 reg mat_rsp_valid=0;reg [575:0] mat_rsp_data=0;reg [31:0] mat_rsp_mask=0,mat_rsp_generation=0;
 reg [15:0] mat_rsp_job=0,mat_rsp_tag=0;reg [7:0] mat_rsp_fmt=0;reg [3:0] mat_rsp_fault=0;
 wire vec_valid,vec_ready,vec_rsp_ready;wire [8:0] vec_block;wire [31:0] vec_mask;wire [15:0] vec_tag;
 reg vec_rsp_valid=0;reg [863:0] vec_rsp_data=0;reg [31:0] vec_rsp_mask=0;reg [15:0] vec_rsp_tag=0;reg [3:0] vec_rsp_fault=0;
 wire candidate_valid;wire candidate_ready;wire [4:0] candidate_block;wire [31:0] candidate_mask;wire [863:0] candidate_data;
 wire rsp_valid;reg rsp_ready=0;wire [3:0] rsp_fault,rsp_detail;wire [10:0] rsp_count,rsp_length;
 wire [63:0] rsp_data;wire rsp_nonzero;wire [15:0] rsp_job,rsp_tag;wire [7:0] rsp_fmt;wire factor_valid;
 // This is a legacy leaf test.  Keep the optional panel bridge disabled and
 // tie every newly added bridge input explicitly instead of relying on `.*`.
 factor_service #(.ENABLE_PANEL_BRIDGE(0)) dut(.*,
  .panel_req_valid(1'b0),.panel_req_write(1'b0),.panel_req_mask(32'd0),
  .panel_req_addr(288'd0),.panel_req_data(864'd0),.panel_req_rows(8'd0),
  .panel_req_cols(11'd0),.panel_req_key(128'd0),.panel_req_generation(32'd0),
  .panel_req_job(16'd0),.panel_req_tag(16'd0),.panel_req_fmt(8'd0),
  .panel_invalidate(1'b0),.panel_rsp_ready(1'b0),.panel_req_ready(),
  .panel_rsp_valid(),.panel_rsp_write(),.panel_rsp_data(),.panel_rsp_mask(),
  .panel_rsp_generation(),.panel_rsp_job(),.panel_rsp_tag(),.panel_rsp_fmt(),
  .panel_rsp_fault()
 );
 // Keep the source B in a fixed dense M-by-96 fixture.  Each command repacks
 // it into the live endpoint's current column stride before it is accepted.
 // This catches an EXTEND that still uses the prefix stride for its suffix.
 reg [17:0] matrix_memory[0:16383];reg [17:0] matrix_dense_memory[0:12287];
 reg [26:0] pool[0:15359];reg [26:0] pending[0:127];
 integer cycles=0,mat_delay=0,vec_delay=0,mat_reads=0,pool_reads=0,pool_returns=0,store_writes=0;
 integer inject=0,inject_at=0,cancel_mode=0,command=0,logfile,bank,lane,address,packets=0,command_cols;
 assign mat_ready=!rst&&!cancel&&!mat_rsp_valid&&mat_delay==0&&cycles%3!=0;
 assign vec_ready=!rst&&!cancel&&!vec_rsp_valid&&vec_delay==0&&cycles%3!=1;
 assign candidate_ready=!rst&&!cancel&&cancel_mode!=4&&cycles%4!=0;
 always @(posedge clk)begin
  cycles<=cycles+1;
  // The owning core flushes its operand endpoints when a worker fault retires.
  if(rst||cancel||(rsp_valid&&rsp_ready&&rsp_fault!=0))begin mat_rsp_valid<=0;vec_rsp_valid<=0;mat_delay<=0;vec_delay<=0;end
  else begin
   if(mat_rsp_valid&&mat_rsp_ready)mat_rsp_valid<=0;
   if(vec_rsp_valid&&vec_rsp_ready)begin vec_rsp_valid<=0;pool_returns<=pool_returns+1;end
   if(mat_delay>0)begin mat_delay<=mat_delay-1;if(mat_delay==1)mat_rsp_valid<=1;end
   if(vec_delay>0)begin vec_delay<=vec_delay-1;if(vec_delay==1)vec_rsp_valid<=1;end
   if(mat_valid&&mat_ready)begin
    if(!mat_dense||mat_key!=128'h55||mat_mask==0)$fatal(1,"bad dense matrix request");
    $fdisplay(logfile,"MAT %0d %08h %072h",command,mat_mask,mat_addr);
    for(bank=0;bank<32;bank=bank+1)begin
     address=int'(mat_addr[bank*9 +:9]);
     mat_rsp_data[bank*18 +:18]<=mat_mask[bank] ? matrix_memory[bank*512+address] : 18'h15555;
    end
    mat_rsp_mask<=inject==2&&mat_reads==inject_at ? mat_mask^1 : mat_mask;
    mat_rsp_tag<=mat_tag+(inject==1&&mat_reads==inject_at ? 1 : 0);
    mat_rsp_generation<=mat_generation+(inject==4&&mat_reads==inject_at ? 1 : 0);
    mat_rsp_job<=mat_job;mat_rsp_fmt<=mat_fmt;mat_rsp_fault<=inject==3&&mat_reads==inject_at ? 4 : 0;
    if(inject==5&&mat_reads==inject_at)matrix_generation<=matrix_generation+1;
    mat_reads<=mat_reads+1;mat_delay<=2;
   end
   if(vec_valid&&vec_ready)begin
    $fdisplay(logfile,"POOL %0d %0d %08h",command,vec_block,vec_mask);
    for(lane=0;lane<32;lane=lane+1)vec_rsp_data[lane*27 +:27]<=vec_mask[lane] ? pool[int'(vec_block)*32+lane] : 27'h5555555;
    vec_rsp_mask<=inject==7&&pool_reads==inject_at ? vec_mask^1 : vec_mask;
    vec_rsp_tag<=vec_tag+(inject==6&&pool_reads==inject_at ? 1 : 0);
    vec_rsp_fault<=inject==8&&pool_reads==inject_at ? 4 : 0;
    pool_reads<=pool_reads+1;vec_delay<=2;
   end
   if(dut.storage.req_valid&&dut.storage.req_ready)begin
    $fdisplay(logfile,"BANK %0d %0d %08h %072h",command,dut.storage.req_write,dut.storage.req_mask,dut.storage.req_addr);
    if(dut.storage.req_write)begin
     if(pool_returns<(int'(req_length)+31)/32)$fatal(1,"factor mutation before complete source validation");
     store_writes<=store_writes+1;
    end
   end
   if(candidate_valid&&candidate_ready)begin
    if(int'(candidate_block)!=packets)$fatal(1,"unordered packed candidate");
    for(lane=0;lane<32;lane=lane+1)begin
     if(candidate_mask[lane]!=(packets*32+lane<int'(req_length)))$fatal(1,"bad packed tail mask");
     if(!candidate_mask[lane]&&candidate_data[lane*27 +:27]!=0)$fatal(1,"nonzero packed padding");
     if(candidate_mask[lane])pending[packets*32+lane]<=candidate_data[lane*27 +:27];
    end
    packets<=packets+1;
   end
  end
 end
 reg [8191:0] matrix_path,matrix_dense_path,pool_path,command_path,trace_path;
 integer file,rc,m,s,opv,lenv,indexv,startv,flagsv,srcv,dstv,efault,ecount,genv,fmtv,densev,watch,hold,j;
 reg [134:0] held;
 reg cancelled;
 reg fill_injected=0;
 always @(negedge clk) begin
  if(inject==9&&!fill_injected&&dut.storage.fill_valid&&dut.storage.fill_ready&&!dut.storage.fill_last)begin
   force dut.storage.fill_good=0;fill_injected=1;
  end else release dut.storage.fill_good;
 end
 task tick;begin @(negedge clk);end endtask
 task repack_matrix;
  integer rr,cc,packed_bank,packed_address;
  begin
   for(rr=0;rr<16384;rr=rr+1)matrix_memory[rr]=0;
   for(rr=0;rr<m;rr=rr+1)for(cc=0;cc<command_cols&&cc<96;cc=cc+1)begin
    packed_bank=(rr+cc)&31;packed_address=rr*((command_cols+31)>>5)+(cc>>5);
    matrix_memory[packed_bank*512+packed_address]=matrix_dense_memory[rr*96+cc];
   end
  end
 endtask
 initial begin
  if(!$value$plusargs("matrix_dense=%s",matrix_dense_path)||!$value$plusargs("pool=%s",pool_path)||!$value$plusargs("commands=%s",command_path)||!$value$plusargs("trace=%s",trace_path)||!$value$plusargs("m=%d",m)||!$value$plusargs("s=%d",s))$fatal(1,"missing paths");
  $readmemh(matrix_dense_path,matrix_dense_memory);$readmemh(pool_path,pool);
  logfile=$fopen(trace_path,"w");file=$fopen(command_path,"r");if(!file||!logfile)$fatal(1,"open failed");
  req_rows=m;req_cols=s;matrix_rows=m;matrix_cols=s;
  repeat(3)tick();rst=0;tick();
  while(!$feof(file))begin
   rc=$fscanf(file,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",opv,lenv,indexv,startv,flagsv,srcv,dstv,efault,ecount,inject,inject_at,cancel_mode,genv,fmtv,densev,command_cols);
   if(rc!=16)$fatal(1,"command parse %0d",rc);
   command=command+1;mat_reads=0;pool_reads=0;pool_returns=0;store_writes=0;packets=0;fill_injected=0;
   if(opv==0)begin
    if(!factor_valid)$fatal(1,"idle Phi probe requires initialized factor");
    matrix_key=128'h99;matrix_generation=777;matrix_cols=1024;
    repeat(6)begin tick();if(!factor_valid)$fatal(1,"idle Phi selection invalidated factors");end
    matrix_key=128'h55;matrix_generation=genv;matrix_cols=s;$fdisplay(logfile,"PHI %0d",command);
   end else begin
    matrix_generation=genv;matrix_cols=command_cols;repack_matrix();req_generation=genv;req_cols=command_cols;req_op=opv;req_length=lenv;req_index=indexv;req_aux_length=startv;req_flags=flagsv;
    req_src_a=srcv;req_dst=dstv;req_tag=command;req_fmt=fmtv;req_matrix_dense=densev;
    while(!req_ready)tick();req_valid=1;tick();req_valid=0;watch=0;cancelled=0;
    while(!rsp_valid&&!cancelled)begin
     if((cancel_mode==1&&mat_reads>0)||(cancel_mode==2&&pool_reads>0)||(cancel_mode==3&&store_writes>0)||(cancel_mode==4&&candidate_valid)||(cancel_mode==6&&mat_reads>1))cancelled=1;
     else begin tick();watch=watch+1;if(watch>20000)$fatal(1,"worker timeout cmd%0d",command);end
    end
    if(cancel_mode==5&&rsp_valid)cancelled=1;
    if(cancelled)begin
     cancel=1;tick();if(rsp_valid||factor_valid)$fatal(1,"cancel visible result");cancel=0;
     repeat(12)begin tick();if(rsp_valid)$fatal(1,"late cancelled response");end
     $fdisplay(logfile,"CANCEL %0d",command);
    end else begin
     if(rsp_fault!=efault||rsp_count!=ecount||rsp_job!=7||rsp_tag!=command||rsp_fmt!=fmtv||rsp_data!=0)
      $fatal(1,"bad completion cmd%0d fault%0d expected%0d count%0d expected%0d",command,rsp_fault,efault,rsp_count,ecount);
     held={rsp_fault,rsp_detail,rsp_count,rsp_length,rsp_data,rsp_nonzero,rsp_job,rsp_tag,rsp_fmt};
     repeat(4)begin tick();if(!rsp_valid||req_ready||{rsp_fault,rsp_detail,rsp_count,rsp_length,rsp_data,rsp_nonzero,rsp_job,rsp_tag,rsp_fmt}!=held)$fatal(1,"held response changed");end
     if(efault!=0&&factor_valid)$fatal(1,"fault did not invalidate factors");
     if(efault==0&&opv==14)begin
      if(rsp_length!=lenv||packets!=(lenv+31)/32)$fatal(1,"incomplete read publication");
      for(j=0;j<lenv;j=j+1)begin pool[dstv*32+j]=pending[j];$fdisplay(logfile,"OUT %0d %0d %07h",command,j,pending[j]);end
     end else if(rsp_length!=0)$fatal(1,"unexpected vector publication");
     $fdisplay(logfile,"RESULT %0d %0d %0d %0d %0d",command,rsp_fault,rsp_count,rsp_length,rsp_nonzero);
     rsp_ready=1;tick();rsp_ready=0;tick();
    end
   end
  end
  $fclose(file);$fclose(logfile);$display("PASS factor commands=%0d cycles=%0d",command,cycles);$finish;
 end
endmodule
