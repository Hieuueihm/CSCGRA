`include "phi_interface.vh"
`timescale 1ns/1ps
module tb_phi_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg  c_rst=0;
 reg  c_invalidate=0;
 reg  c_begin_valid=0;
 wire  c_begin_ready;
 reg [`CSR_PHI_ROWS_W-1:0] c_begin_rows=0;
 reg [`CSR_PHI_COLUMNS_W-1:0] c_begin_columns=0;
 reg [`CSR_PHI_JOB_TAG_W-1:0] c_begin_job_tag=0;
 reg [`CSR_PHI_OP_TAG_W-1:0] c_begin_op_tag=0;
 reg [`CSR_PHI_FORMAT_TAG_W-1:0] c_begin_format_tag=0;
 reg [`CSR_PHI_GENERATION_W-1:0] c_begin_generation=0;
 reg [`CSR_PHI_KEY_W-1:0] c_begin_key=0;
 wire  c_filling;
 reg  c_fill_valid=0;
 wire  c_fill_ready;
 reg [`CSR_PHI_WORD_BITS-1:0] c_fill_signs=0;
 reg [`CSR_PHI_WORD_BITS-1:0] c_fill_mask=0;
 reg [`CSR_PHI_COLUMN_W-1:0] c_fill_column=0;
 reg [`CSR_PHI_ROW_BLOCK_W-1:0] c_fill_row_block=0;
 reg [`CSR_PHI_JOB_TAG_W-1:0] c_fill_job_tag=0;
 reg [`CSR_PHI_OP_TAG_W-1:0] c_fill_op_tag=0;
 reg [`CSR_PHI_FORMAT_TAG_W-1:0] c_fill_format_tag=0;
 reg [`CSR_PHI_GENERATION_W-1:0] c_fill_generation=0;
 reg  c_fill_last=0;
 wire  c_cache_valid;
 wire  c_published;
 wire [`CSR_PHI_KEY_W-1:0] c_cache_key;
 wire [`CSR_PHI_GENERATION_W-1:0] c_cache_generation;
 wire [`CSR_PHI_FAULT_W-1:0] c_fault_code;
 reg  c_rd_valid=0;
 wire  c_rd_ready;
 reg [`CSR_PHI_BANKS-1:0] c_rd_bank_mask=0;
 reg [`CSR_PHI_BANKS*`CSR_PHI_ADDR_W-1:0] c_rd_addresses=0;
 reg [`CSR_PHI_GENERATION_W-1:0] c_rd_generation=0;
 reg [`CSR_PHI_READ_TAG_W-1:0] c_rd_tag=0;
 wire  c_rsp_valid;
 reg  c_rsp_ready=0;
 wire [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] c_rsp_signs;
 wire [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] c_rsp_masks;
 wire [`CSR_PHI_BANKS-1:0] c_rsp_bank_mask;
 wire [`CSR_PHI_GENERATION_W-1:0] c_rsp_generation;
 wire [`CSR_PHI_READ_TAG_W-1:0] c_rsp_tag;
 wire [`CSR_PHI_FAULT_W-1:0] c_rsp_fault;
 phi_sign_cache cache(.clk(clk),.rst(c_rst),.invalidate(c_invalidate),.begin_valid(c_begin_valid),.begin_ready(c_begin_ready),.begin_rows(c_begin_rows),.begin_columns(c_begin_columns),.begin_job_tag(c_begin_job_tag),.begin_op_tag(c_begin_op_tag),.begin_format_tag(c_begin_format_tag),.begin_generation(c_begin_generation),.begin_key(c_begin_key),.filling(c_filling),.fill_valid(c_fill_valid),.fill_ready(c_fill_ready),.fill_signs(c_fill_signs),.fill_mask(c_fill_mask),.fill_column(c_fill_column),.fill_row_block(c_fill_row_block),.fill_job_tag(c_fill_job_tag),.fill_op_tag(c_fill_op_tag),.fill_format_tag(c_fill_format_tag),.fill_generation(c_fill_generation),.fill_last(c_fill_last),.cache_valid(c_cache_valid),.published(c_published),.cache_key(c_cache_key),.cache_generation(c_cache_generation),.fault_code(c_fault_code),.rd_valid(c_rd_valid),.rd_ready(c_rd_ready),.rd_bank_mask(c_rd_bank_mask),.rd_addresses(c_rd_addresses),.rd_generation(c_rd_generation),.rd_tag(c_rd_tag),.rsp_valid(c_rsp_valid),.rsp_ready(c_rsp_ready),.rsp_signs(c_rsp_signs),.rsp_masks(c_rsp_masks),.rsp_bank_mask(c_rsp_bank_mask),.rsp_generation(c_rsp_generation),.rsp_tag(c_rsp_tag),.rsp_fault(c_rsp_fault));
 reg rst=1,cancel=0,req_valid=0;wire req_ready;
 reg [31:0] req_mask=0;reg [287:0] req_addr=0;reg [127:0] req_key=0;
 reg [31:0] req_generation=0;reg [15:0] req_job=0,req_tag=0;reg [7:0] req_fmt=0;
 wire rd_valid,rd_ready;wire [7:0] rd_mask;wire [71:0] rd_addr;wire [31:0] rd_generation;wire [15:0] rd_tag;
 wire cache_rsp_ready,rsp_valid;reg rsp_ready=0;wire [575:0] rsp_data;wire [255:0] rsp_masks;wire [31:0] rsp_mask,rsp_generation;
 wire [15:0] rsp_job,rsp_tag;wire [7:0] rsp_fmt;wire [3:0] rsp_fault;
 reg [15:0] active_job=7;reg [7:0] active_fmt=1;
 reg direct=0,d_valid=0,d_ready=0,gate=1;reg [7:0] d_mask=0;reg [71:0] d_addr=0;reg [31:0] d_generation=0;reg [15:0] d_tag=0;
 reg [3:0] inject_by_tag[0:65535];wire [3:0] injected=inject_by_tag[c_rsp_tag];
 phi_reader reader(.clk(clk),.rst(rst),.cancel(cancel),.cache_valid(c_cache_valid),.cache_key(c_cache_key),
  .cache_generation(c_cache_generation),.cache_job(active_job),.cache_fmt(active_fmt),
  .req_valid(req_valid),.req_ready(req_ready),.req_mask(req_mask),.req_addr(req_addr),.req_key(req_key),.req_generation(req_generation),.req_job(req_job),.req_tag(req_tag),.req_fmt(req_fmt),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_mask(rd_mask),.rd_addr(rd_addr),.rd_generation(rd_generation),.rd_tag(rd_tag),
  .cache_rsp_valid(c_rsp_valid),.cache_rsp_ready(cache_rsp_ready),.cache_rsp_signs(c_rsp_signs),.cache_rsp_masks(c_rsp_masks),
  .cache_rsp_mask(c_rsp_bank_mask^(injected==2 ? 8'd1 : 8'd0)),.cache_rsp_generation(c_rsp_generation+(injected==3 ? 1 : 0)),
  .cache_rsp_tag(c_rsp_tag+(injected==1 ? 1 : 0)),.cache_rsp_fault(injected==4 ? 4'd3 : c_rsp_fault),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_data(rsp_data),.rsp_masks(rsp_masks),.rsp_mask(rsp_mask),.rsp_generation(rsp_generation),.rsp_job(rsp_job),.rsp_tag(rsp_tag),.rsp_fmt(rsp_fmt),.rsp_fault(rsp_fault));
 assign rd_ready=gate&&c_rd_ready;
 always @*begin
  c_rst=rst;c_invalidate=cancel;
  c_rd_valid=direct ? d_valid : rd_valid&&gate;
  c_rd_bank_mask=direct ? d_mask : rd_mask;c_rd_addresses=direct ? d_addr : rd_addr;
  c_rd_generation=direct ? d_generation : rd_generation;c_rd_tag=direct ? d_tag : rd_tag;
  c_rsp_ready=direct ? d_ready : cache_rsp_ready;
 end
 reg [31:0] image[0:4095];reg [8191:0] image_path,request_path;
 integer file,rc,m,n,blocks,column,block,lane,i,cycle=0,issued=0,retired=0,read_grants=0,refills=0,max_run=0,run_length=0,peak=0;
 integer requests,mode,stall,abort_at,accepted_since_abort,aborts=0,flushed=0,total_accepted=0;
 reg [31:0] masks[0:2047],gens[0:2047];reg [287:0] addresses[0:2047];reg [127:0] keys[0:2047];
 reg [15:0] jobs[0:2047],tags[0:2047];reg [7:0] formats[0:2047];reg [3:0] faults[0:2047],injections[0:2047];
 reg [255:0] gold[0:2047],gold_masks[0:2047];
 reg held_valid=0;reg [939:0] held_payload;wire [939:0] response_payload={rsp_data,rsp_masks,rsp_mask,rsp_generation,rsp_job,rsp_tag,rsp_fmt,rsp_fault};
 reg rd_held=0;reg [127:0] rd_payload;wire [127:0] current_rd={rd_mask,rd_addr,rd_generation,rd_tag};integer joined_stall=0;
 reg cache_held=0;reg [587:0] cache_payload;wire [587:0] current_cache={c_rsp_signs,c_rsp_masks,c_rsp_bank_mask,c_rsp_generation,c_rsp_tag,c_rsp_fault,16'b0};
 wire accepted=direct ? d_valid&&c_rd_ready : req_valid&&req_ready;
 wire returned=direct ? c_rsp_valid&&d_ready : rsp_valid&&rsp_ready;
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(rst||cancel)begin held_valid<=0;cache_held<=0;rd_held<=0;run_length<=0;end
  else begin
   if(rd_held&&(!rd_valid||current_rd!==rd_payload))$fatal(1,"reader cache request changed while stalled");
   rd_held<=rd_valid&&!rd_ready;rd_payload<=current_rd;
   if(rd_valid&&!rd_ready&&c_rsp_valid&&cache_rsp_ready)joined_stall<=joined_stall+1;
   if(held_valid&&(!rsp_valid||response_payload!==held_payload))$fatal(1,"reader held payload changed");
   held_valid<=rsp_valid&&!rsp_ready;held_payload<=response_payload;
   if(cache_held&&(!c_rsp_valid||current_cache!==cache_payload))$fatal(1,"cache held payload changed");
   cache_held<=c_rsp_valid&&!c_rsp_ready;cache_payload<=current_cache;
   if(accepted)begin
    issued<=issued+1;total_accepted<=total_accepted+1;run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
   end else run_length<=0;
   if(issued-retired>peak)peak<=issued-retired;
   if(c_rd_valid&&c_rd_ready)begin read_grants<=read_grants+1;if(c_rsp_valid&&c_rsp_ready)refills<=refills+1;end
   if(returned)begin
    if(retired>=issued)$fatal(1,"response without accepted command");
    if(direct)begin
     if(c_rsp_tag!==tags[retired]||c_rsp_generation!==gens[retired]||c_rsp_fault!==faults[retired]||c_rsp_signs!==gold[retired]||c_rsp_masks!==gold_masks[retired]||c_rsp_bank_mask!==masks[retired][7:0])$fatal(1,"cache mismatch item%0d",retired);
    end else if(rsp_tag!==tags[retired]||rsp_job!==jobs[retired]||rsp_fmt!==formats[retired]||rsp_generation!==gens[retired]||rsp_fault!==faults[retired]||rsp_data!=={320'b0,gold[retired]}||rsp_masks!==gold_masks[retired]||rsp_mask!==(faults[retired]==0 ? masks[retired] : 32'b0))$fatal(1,"reader mismatch item%0d tag%0d fault%0d expected%0d",retired,rsp_tag,rsp_fault,faults[retired]);
    retired<=retired+1;
   end
  end
 end
 task tick;begin @(negedge clk);end endtask
 task load_image;
 begin
  c_begin_rows=m;c_begin_columns=n;c_begin_job_tag=7;c_begin_op_tag=19;c_begin_format_tag=1;c_begin_generation=3;c_begin_key=128'h1234;
  while(!c_begin_ready)tick();c_begin_valid=1;tick();c_begin_valid=0;
  for(column=0;column<n;column=column+1)for(block=0;block<blocks;block=block+1)begin
   c_fill_column=column;c_fill_row_block=block;c_fill_signs=image[column*blocks+block];c_fill_mask=0;
   for(lane=0;lane<32;lane=lane+1)if(block*32+lane<m)c_fill_mask[lane]=1;
   c_fill_job_tag=7;c_fill_op_tag=19;c_fill_format_tag=1;c_fill_generation=3;c_fill_last=column+1==n&&block+1==blocks;
   if(c_rd_ready||c_begin_ready)$fatal(1,"read/begin during fill");
   c_fill_valid=1;tick();c_fill_valid=0;
  end
  if(!c_cache_valid)$fatal(1,"image did not publish");
 end endtask
 initial begin
  if(!$value$plusargs("image=%s",image_path)||!$value$plusargs("requests=%s",request_path)||!$value$plusargs("m=%d",m)||!$value$plusargs("n=%d",n)||!$value$plusargs("mode=%d",mode)||!$value$plusargs("stall=%d",stall)||!$value$plusargs("abort=%d",abort_at))$fatal(1,"missing arguments");
  blocks=(m+31)/32;$readmemh(image_path,image);file=$fopen(request_path,"r");if(!file)$fatal(1,"requests open");requests=0;
  for(i=0;i<65536;i=i+1)inject_by_tag[i]=0;
  while(!$feof(file))begin
   rc=$fscanf(file,"%h %h %h %h %h %h %h %h %h %h %h\n",masks[requests],addresses[requests],keys[requests],gens[requests],jobs[requests],tags[requests],formats[requests],injections[requests],faults[requests],gold[requests],gold_masks[requests]);
   if(rc!=11)$fatal(1,"parse%0d",rc);inject_by_tag[tags[requests]]=injections[requests];requests=requests+1;
  end
  $fclose(file);repeat(3)tick();rst=0;tick();load_image();direct=mode;
  // Abort one or two accepted commands before retirement, then reload and retry
  // the exact same tags/base/generation. Both leaf pipelines see the same cancel.
  if(abort_at!=0)begin
   gate=abort_at!=1&&abort_at!=4;rsp_ready=0;d_ready=0;
   req_mask=masks[0];req_addr=addresses[0];req_key=keys[0];req_generation=gens[0];req_job=jobs[0];req_tag=tags[0];req_fmt=formats[0];
   req_valid=1;tick();
   if(abort_at==4||abort_at==5)begin
    req_mask=masks[1];req_addr=addresses[1];req_key=keys[1];req_generation=gens[1];req_job=jobs[1];req_tag=tags[1];req_fmt=formats[1];
    if(!req_ready)$fatal(1,"second credit not available");tick();
   end
   req_valid=0;
   if(abort_at==2)begin while(!c_rsp_valid)tick();end
   if(abort_at==3||abort_at==5)begin while(!rsp_valid)tick();repeat(4)tick();end
   flushed=issued-retired;cancel=1;#1;if(req_ready||rd_valid||cache_rsp_ready||rsp_valid||c_rd_ready||c_rsp_valid)$fatal(1,"cancel visible handshake");
   tick();cancel=0;issued=0;retired=0;run_length=0;max_run=0;peak=0;aborts=1;gate=1;repeat(4)tick();
   if(rsp_valid||c_rsp_valid||c_cache_valid)$fatal(1,"old response/image survived abort");load_image();
  end
  while(retired<requests)begin
   req_valid=!direct&&issued<requests;d_valid=direct&&issued<requests;
   if(issued<requests)begin
    req_mask=masks[issued];req_addr=addresses[issued];req_key=keys[issued];req_generation=gens[issued];req_job=jobs[issued];req_tag=tags[issued];req_fmt=formats[issued];
    d_mask=masks[issued][7:0];d_addr=addresses[issued][71:0];d_generation=gens[issued];d_tag=tags[issued];
   end
   rsp_ready=stall==0||cycle%11>=5;d_ready=rsp_ready;gate=stall==0||cycle%7!=0;
   tick();if(cycle>100000)$fatal(1,"timeout");
  end
  req_valid=0;d_valid=0;repeat(3)tick();
  if(!stall&&max_run<8)$fatal(1,"no continuous transport run %0d",max_run);
  if(refills==0)$fatal(1,"no simultaneous cache consume/refill");
  if(!direct&&peak>2)$fatal(1,"reader credit overflow");
  if(total_accepted!=retired+flushed)$fatal(1,"accepted/retired/flushed mismatch");
  $display("PASS phi_pipeline commands=%0d cycles=%0d grants=%0d refills=%0d max_run=%0d peak=%0d aborts=%0d accepted=%0d flushed=%0d joined_stall=%0d",retired,cycle,read_grants,refills,max_run,peak,aborts,total_accepted,flushed,joined_stall);$finish;
 end
endmodule
