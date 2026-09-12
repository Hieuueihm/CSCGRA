`timescale 1ns/1ps
module tb_factor_panel_service #(parameter NARROW_PANEL_MAPPING=1'b1);
 reg clk=0; always #5 clk=~clk;
 reg rst=1,cancel=0,req_valid=0; wire req_ready;
 reg [5:0] req_op=0; reg [2047:0] req_contexts=0;
 reg [8:0] req_src_a=0,req_src_b=8,req_dst=40;
 reg [26:0] req_scalar_a=0;
 reg [7:0] req_rows=33; reg [10:0] req_support_length=35,req_aux_length=0,req_length=0,req_index=0;
 reg [7:0] req_flags=0; reg req_matrix_dense=1;
 reg [127:0] req_key=128'h77; reg [31:0] req_generation=9; reg [15:0] req_job=5,req_tag=0; reg [7:0] req_fmt=1;
 reg matrix_valid=1; reg [7:0] matrix_rows=33; reg [10:0] matrix_cols=35;
 reg [127:0] matrix_key=128'h77; reg [31:0] matrix_generation=9; reg [15:0] matrix_job=5; reg [7:0] matrix_fmt=1;
 wire vec_valid; wire vec_ready; wire [8:0] vec_block; wire [31:0] vec_mask; wire [15:0] vec_tag;
 reg vec_rsp_valid=0; wire vec_rsp_ready; reg [863:0] vec_rsp_data=0; reg [31:0] vec_rsp_mask=0; reg [15:0] vec_rsp_tag=0; reg [3:0] vec_rsp_fault=0;
 wire candidate_valid; reg candidate_ready=0; wire [4:0] candidate_block; wire [31:0] candidate_mask; wire [863:0] candidate_data;
 wire rsp_valid; reg rsp_ready=0; wire [3:0] rsp_fault,rsp_detail; wire [10:0] rsp_count,rsp_length; wire [63:0] rsp_data; wire rsp_nonzero; wire [15:0] rsp_job,rsp_tag; wire [7:0] rsp_fmt;
 wire panel_req_valid; reg panel_req_ready=0; wire panel_req_write; wire [31:0] panel_req_mask; wire [287:0] panel_req_addr; wire [863:0] panel_req_data; wire [7:0] panel_req_rows; wire [10:0] panel_req_cols; wire [127:0] panel_req_key; wire [31:0] panel_req_generation; wire [15:0] panel_req_job,panel_req_tag; wire [7:0] panel_req_fmt; wire panel_invalidate;
 reg panel_rsp_valid=0; wire panel_rsp_ready; reg panel_rsp_write=0; reg [863:0] panel_rsp_data=0; reg [31:0] panel_rsp_mask=0,panel_rsp_generation=0; reg [15:0] panel_rsp_job=0,panel_rsp_tag=0; reg [7:0] panel_rsp_fmt=0; reg [3:0] panel_rsp_fault=0;
 wire fabric_cfg_valid; reg fabric_cfg_ready=1; wire [2047:0] fabric_cfg_contexts; reg [3:0] fabric_cfg_fault=0; reg fabric_cfg_loaded=1;
 wire fabric_cmd_valid; reg fabric_cmd_ready=1; wire [15:0] fabric_cmd_job,fabric_cmd_tag; wire [7:0] fabric_cmd_fmt; wire [1:0] fabric_cmd_terminal,fabric_cmd_flow; wire [5:0] fabric_cmd_shift; wire [31:0] fabric_cmd_terminal_mask;
 wire fabric_in_valid; reg fabric_in_ready=1; wire [863:0] fabric_in_a,fabric_in_b; wire [31:0] fabric_in_mask; wire fabric_in_last;
 reg fabric_out_valid=0; wire fabric_out_ready; reg [863:0] fabric_out_data=0; reg [2047:0] fabric_out_acc=0; reg [31:0] fabric_out_mask=0; reg [127:0] fabric_out_faults=0; reg fabric_out_last=0;
 reg fabric_done_valid=0; wire fabric_done_ready; reg [3:0] fabric_done_fault=0; reg [15:0] fabric_done_job=0,fabric_done_tag=0; reg [7:0] fabric_done_fmt=0; reg [2047:0] terminal_acc=0; reg [3:0] terminal_error=0;
 factor_panel_service #(.NARROW_PANEL_MAPPING(NARROW_PANEL_MAPPING)) dut(.*);
 reg signed [26:0] factor[0:127][0:95],expected[0:127][0:95],avec[0:127],bvec[0:95],qexpected[0:95];
 reg signed [63:0] acc[0:31];
 integer cycle,lane,bank,row,col,ii,jj,term_lane,term_r,watch,outputs,write_count,rank_write_packets,project_dot_done,project_scale_done,project_rank_done,project_read_packets,project_write_packets; reg signed [63:0] qsum;
 reg [4:0] configured_op=0; reg [26:0] project_alpha=27'sd4194304;
 // 1 first bridge fault, 2 B-preflight fault, 3 reply mask, 4 reply tag,
 // 5 store fault after one private rank write, 6 fabric numeric fault after one write.
reg [3:0] inject_mode=0,seen_invalidate=0; reg cancel_after_write=0,numeric_armed=0,narrow_terminal_pending=0;
 function automatic signed [26:0] r22(input signed [63:0] value);
   reg signed [64:0] mag; begin mag=value<0?-value:value;mag=(mag+(65'sd1<<21))>>>22;r22=value<0?-mag[26:0]:mag[26:0];end
 endfunction
 function automatic signed [26:0] word(input [863:0] data,input integer n); word=data[n*27+:27]; endfunction
 assign vec_ready=!rst&&!cancel&&(cycle%3!=0)&&!vec_rsp_valid;
 always @(posedge clk) begin
   cycle<=cycle+1; panel_req_ready<=!rst&&!cancel&&!panel_rsp_valid&&(cycle%4!=0); candidate_ready<=!rst&&!cancel&&(cycle%3!=1);
   if(rst) for(lane=0;lane<32;lane=lane+1) acc[lane]<=0;
   if(fabric_cfg_valid&&fabric_cfg_ready) configured_op<=fabric_cfg_contexts[4:0];
   if(panel_invalidate) seen_invalidate<=1;
   if(cancel) begin panel_rsp_valid<=0;vec_rsp_valid<=0;fabric_out_valid<=0;fabric_done_valid<=0;narrow_terminal_pending<=0;end
   if(cancel_after_write&&rank_write_packets>=1&&!cancel) cancel<=1;
   if(vec_rsp_valid&&vec_rsp_ready) vec_rsp_valid<=0;
   if(vec_valid&&vec_ready) begin
     vec_rsp_data<=0; vec_rsp_mask<=vec_mask; vec_rsp_tag<=vec_tag; vec_rsp_fault<=(inject_mode==2&&vec_block>=8)?7:0;if(inject_mode==2&&vec_block>=8)inject_mode<=0;
     if(inject_mode==7&&vec_block<8) begin vec_rsp_mask<=vec_mask^32'h1;inject_mode<=0;end
     if(inject_mode==8&&vec_block<8) begin vec_rsp_tag<=16'hffff;inject_mode<=0;end
     for(lane=0;lane<32;lane=lane+1) if(vec_mask[lane]) begin
       if(vec_block<8) vec_rsp_data[lane*27+:27]<=avec[int'(vec_block)*32+lane];
       else vec_rsp_data[lane*27+:27]<=bvec[(int'(vec_block)-8)*32+lane];
     end
     vec_rsp_valid<=1;
   end
   if(panel_rsp_valid&&panel_rsp_ready) panel_rsp_valid<=0;
   if(panel_req_valid&&panel_req_ready) begin
      panel_rsp_valid<=1;panel_rsp_write<=panel_req_write;panel_rsp_mask<=panel_req_mask;panel_rsp_generation<=panel_req_generation;
      panel_rsp_job<=panel_req_job;panel_rsp_tag<=panel_req_tag;panel_rsp_fmt<=panel_req_fmt;panel_rsp_fault<=0;panel_rsp_data<=0;
      if(inject_mode==1) begin panel_rsp_fault<=7;inject_mode<=0;end
      else if(inject_mode==3) begin panel_rsp_mask<=panel_req_mask^32'h1;inject_mode<=0;end
      else if(inject_mode==4) begin panel_rsp_tag<=panel_req_tag+1'b1;inject_mode<=0;end
      else if(inject_mode==5&&panel_req_write&&rank_write_packets>=1) begin panel_rsp_fault<=7;inject_mode<=0;end
      // Decode the physical request itself.  Do not use DUT scheduling state:
      // this catches a wrong bank/address or nonzero column-start mapping.
      for(bank=0;bank<32;bank=bank+1) if(panel_req_mask[bank]) begin
        row=panel_req_addr[bank*9+:9]/3;
        col=32*(panel_req_addr[bank*9+:9]%3)+((bank-row+32)%32);
        if(row<0||row>=req_rows||col<0||col>=req_support_length)$fatal(1,"bad factor packet bank%0d row%0d col%0d",bank,row,col);
        if(panel_req_write) begin factor[row][col]<=word(panel_req_data,bank);write_count<=write_count+1;end
        else panel_rsp_data[bank*27+:27]<=factor[row][col];
      end
     if(req_op==20) begin
       if(panel_req_write) begin
         if(project_dot_done<((req_support_length-req_index+31)>>5))$fatal(1,"project write before final dot");
         if(project_scale_done<((req_support_length-req_index+31)>>5))$fatal(1,"project write before final scale");
         project_write_packets<=project_write_packets+1;
       end else project_read_packets<=project_read_packets+1;
     end
     if(panel_req_write) begin
       // Arm the numeric fault only after this command has accepted a
       // preceding private write.  A failed command can leave a held mock
       // fabric response; it must not consume the next command's injection.
       if(inject_mode==6&&rank_write_packets>=1) numeric_armed<=1;
       rank_write_packets<=rank_write_packets+1;
     end
   end
   if(fabric_done_valid&&fabric_done_ready&&req_op==20&&configured_op==9)project_dot_done<=project_dot_done+1;
   // RANK carries the scale primitive in its low cascade context, so count a
   // scale completion only on the ordinary (non-cascade) fabric flow.
   if(fabric_done_valid&&fabric_done_ready&&req_op==20&&fabric_cmd_flow==0&&configured_op==8)project_scale_done<=project_scale_done+1;
   if(fabric_done_valid&&fabric_done_ready&&req_op==20&&fabric_cmd_flow==1)project_rank_done<=project_rank_done+1;
   if(fabric_out_valid&&fabric_out_ready) fabric_out_valid<=0;
   if(fabric_in_valid&&fabric_in_ready) begin
     if(fabric_cmd_flow==0&&configured_op==9) begin
        // A real terminal fabric retires one ordinary output frame per input;
        // only its terminal-rounded final frame is used as the MATVEC result.
        fabric_out_data<=0;fabric_out_mask<=fabric_in_mask;fabric_out_faults<=0;fabric_out_last<=fabric_in_last;fabric_out_valid<=1;
        for(lane=0;lane<32;lane=lane+1) if(fabric_in_mask[lane]) acc[lane]<=acc[lane]+$signed(word(fabric_in_a,lane))*$signed(word(fabric_in_b,lane));
       if(fabric_in_last&&fabric_cmd_terminal!=1) begin
         fabric_out_data<=0;
         for(lane=0;lane<32;lane=lane+1) if(fabric_in_mask[lane]) begin
           terminal_acc[lane*64+:64]<=acc[lane]+$signed(word(fabric_in_a,lane))*$signed(word(fabric_in_b,lane));
           fabric_out_data[lane*27+:27]<=r22(acc[lane]+$signed(word(fabric_in_a,lane))*$signed(word(fabric_in_b,lane)));
         end
         fabric_done_valid<=1;fabric_done_fault<=0;fabric_done_job<=fabric_cmd_job;fabric_done_tag<=fabric_cmd_tag;fabric_done_fmt<=fabric_cmd_fmt;
       end else if(fabric_in_last)narrow_terminal_pending<=1;
     end else if(fabric_cmd_flow==0&&configured_op==8) begin
       // A resident scale uses the same terminal S27 round as the standalone
       // SCALE command; no Q candidate is published by the worker.
       fabric_out_data<=0;fabric_out_mask<=fabric_in_mask;fabric_out_faults<=0;fabric_out_last<=fabric_in_last;fabric_out_valid<=1;
       for(lane=0;lane<32;lane=lane+1) if(fabric_in_mask[lane]) fabric_out_data[lane*27+:27]<=r22($signed(word(fabric_in_a,lane))*$signed(word(fabric_in_b,lane)));
       if(fabric_in_last) begin fabric_done_valid<=1;fabric_done_fault<=0;fabric_done_job<=fabric_cmd_job;fabric_done_tag<=fabric_cmd_tag;fabric_done_fmt<=fabric_cmd_fmt;end
     end else begin
       fabric_out_data<=0;fabric_out_mask<=0;fabric_out_faults<=0;fabric_out_last<=fabric_in_last;
       if(numeric_armed) begin
         fabric_out_faults[3:0]<=3;numeric_armed<=0;inject_mode<=0;
       end
       for(lane=0;lane<16;lane=lane+1) if(fabric_in_mask[lane]) begin
         fabric_out_data[lane*27+:27]<= $signed(word(fabric_in_a,16+lane))-r22($signed(word(fabric_in_a,lane))*$signed(word(fabric_in_b,lane)));
         fabric_out_mask[lane]<=1;
       end
       fabric_out_valid<=1;
       if(fabric_in_last) begin fabric_done_valid<=1;fabric_done_fault<=0;fabric_done_job<=fabric_cmd_job;fabric_done_tag<=fabric_cmd_tag;fabric_done_fmt<=fabric_cmd_fmt;end
     end
   end
   // Terminal R4 starts only after the final frame's MAC data advances.  This
   // models the registered terminal ownership instead of reading an ACC that
   // is one input frame old at the same acceptance edge.
   if(narrow_terminal_pending&&!fabric_done_valid) begin
     fabric_out_data<=0;
     for(term_lane=0;term_lane<8;term_lane=term_lane+1) begin
       qsum=0;
       for(term_r=0;term_r<4;term_r=term_r+1)
         qsum=qsum+acc[term_lane*4+term_r];
       if(fabric_cmd_terminal_mask[term_lane*4]) begin
         terminal_acc[(term_lane*4)*64+:64]<=qsum;
         fabric_out_data[(term_lane*4)*27+:27]<=r22(qsum);
       end
     end
     fabric_done_valid<=1;fabric_done_fault<=0;fabric_done_job<=fabric_cmd_job;fabric_done_tag<=fabric_cmd_tag;fabric_done_fmt<=fabric_cmd_fmt;
     narrow_terminal_pending<=0;
   end
   if(fabric_done_valid&&fabric_done_ready) begin
     // The real fabric has drained every output before DONE.  Model that
     // ownership edge explicitly so a former panel output cannot enter a
     // newly configured panel after its terminal acknowledgement.
     fabric_done_valid<=0; fabric_out_valid<=0;
     for(lane=0;lane<32;lane=lane+1) acc[lane]<=0;
   end
 end
 task automatic tick; begin @(negedge clk); end endtask
 task automatic drain_aborted_worker;
   begin
     // The owning kernel aborts the fabric worker and discards private-store
     // replies after panel_invalidate.  Model that boundary only after the
     // case has checked its original fault response and lack of publication.
     cancel=1; tick();
     panel_rsp_valid=0; vec_rsp_valid=0; fabric_out_valid=0;
     fabric_done_valid=0; numeric_armed=0;
     for(lane=0;lane<32;lane=lane+1) acc[lane]=0;
     tick(); cancel=0; tick();
   end
 endtask
 task automatic issue(input integer op,input integer rs,input integer cnt,input integer cs,input integer tagv,input integer fault_case);
   begin
     // Do not arm an injected reply while a prior failed command is still
     // draining.  The fault must belong to the command below.
     req_op=op;req_aux_length=rs;req_length=cnt;req_index=cs;req_tag=tagv;req_src_a=0;req_src_b=(op==20)?0:8;req_dst=(op==20)?0:40;req_scalar_a=(op==20)?project_alpha:0;inject_mode=0;numeric_armed=0;outputs=0;seen_invalidate=0;write_count=0;rank_write_packets=0;project_dot_done=0;project_scale_done=0;project_rank_done=0;project_read_packets=0;project_write_packets=0;cancel_after_write=0;
     while(!req_ready) tick(); inject_mode=fault_case;req_valid=1;tick();req_valid=0;watch=0;
     while(!rsp_valid) begin
       if(candidate_valid&&candidate_ready) begin
         if(candidate_block!=outputs)$fatal(1,"candidate order");
         for(lane=0;lane<32;lane=lane+1) if(candidate_mask[lane]&&candidate_data[lane*27+:27]!==qexpected[outputs*32+lane]) $fatal(1,"MATVEC q mismatch lane%0d actual%0d expected%0d",lane,$signed(candidate_data[lane*27+:27]),qexpected[outputs*32+lane]);
         outputs=outputs+1;
       end
       tick();watch=watch+1;if(watch>20000)$fatal(1,"timeout op%0d",op);
     end
     repeat(3) begin
       tick();
       if(!rsp_valid)$fatal(1,"response not held");
       if(fault_case!=0&&candidate_valid)$fatal(1,"fault published candidate while response held");
     end
     if(fault_case!=0) begin
       if(rsp_fault==0||!seen_invalidate)$fatal(1,"fault did not invalidate mode=%0d rsp=%0d",fault_case,rsp_fault);
       if(fault_case==2&&write_count!=0)$fatal(1,"B preflight wrote factor");
       // A failed second write is sufficient: the first write has already
       // mutated only the private factor image.  Do not require the failed
       // transaction itself to be acknowledged as a second packet.
       if((fault_case==5||fault_case==6)&&(rank_write_packets<1||write_count==0))$fatal(1,"post-write fault was too early: mode=%0d packets=%0d writes=%0d rsp_fault=%0d",fault_case,rank_write_packets,write_count,rsp_fault);
       if((fault_case==5||fault_case==6)&&outputs!=0)$fatal(1,"rank fault published candidate");
       if((fault_case==3||fault_case==4)&&outputs!=0)$fatal(1,"bad bridge reply published candidate");
     end
     else if(rsp_fault!=0||rsp_job!=5||rsp_tag!=tagv||rsp_fmt!=1)$fatal(1,"bad panel response op%0d row%0d count%0d col%0d tag%0d fault%0d detail%0d",op,rs,cnt,cs,tagv,rsp_fault,rsp_detail);
     rsp_ready=1;tick();rsp_ready=0;tick();
     if(fault_case!=0) drain_aborted_worker();
   end
 endtask
 task automatic issue_cancel(input integer op,input integer rs,input integer cnt,input integer cs,input integer tagv);
   begin
     req_op=op;req_aux_length=rs;req_length=cnt;req_index=cs;req_tag=tagv;req_src_a=0;req_src_b=(op==20)?0:8;req_dst=(op==20)?0:40;req_scalar_a=(op==20)?project_alpha:0;inject_mode=0;outputs=0;seen_invalidate=0;write_count=0;rank_write_packets=0;cancel_after_write=1;
     while(!req_ready)tick();req_valid=1;tick();req_valid=0;watch=0;
     while(!cancel) begin tick();watch=watch+1;if(watch>20000)$fatal(1,"cancel rank timeout");end
     repeat(3)begin tick();if(rsp_valid||candidate_valid)$fatal(1,"cancel exposed completion");end
     if(!seen_invalidate||rank_write_packets<1||write_count==0)$fatal(1,"cancel did not follow private write");
     cancel=0;cancel_after_write=0;repeat(3)tick();if(!req_ready)$fatal(1,"cancel did not return idle");
   end
 endtask
task automatic set_contexts(input integer op);
   begin
    req_contexts=0;
    if(op==20) begin
      req_contexts[0+:64]=64'd297;
      req_contexts[64+:64]=64'd296;
      req_contexts[128+:64]=64'd291;
    end else for(lane=0;lane<32;lane=lane+1) begin
        req_contexts[lane*64+:5]=(op==17)?9:((lane<16)?8:3);
        req_contexts[lane*64+5]=1;
        req_contexts[lane*64+6+:2]=0;
        req_contexts[lane*64+8+:2]=1;
      end
 end
endtask
function automatic integer panel_frames(input integer count_i,input integer columns_i,input integer panel_i);
 integer offset_i,width_i;
 begin
   panel_frames=0;
   for(offset_i=0;offset_i<columns_i;offset_i=offset_i+panel_i) begin
     width_i=columns_i-offset_i;
     if(width_i>panel_i)width_i=panel_i;
     // The test oracle derives packet counts from the public panel width and
     // frame contract; it does not inspect the worker's private counters.
     panel_frames=panel_frames+((NARROW_PANEL_MAPPING&&width_i<=8) ? ((count_i/panel_i)*8+(((count_i%panel_i)>8)?8:(count_i%panel_i))) : count_i);
   end
 end
endfunction
// One directed, non-cross-product Phase-B row.  The mock factor-store packet
// decoder above checks the physical bank/address mapping; this task checks the
// architectural result after the three required rounded phases.  It therefore
// detects an accidental fused dot/scale round or a rank phase started before
// every column's q has been retained.
task automatic project_boundary(
  input integer rows_i,input integer support_i,input integer row_start_i,
  input integer row_count_i,input integer col_start_i,
  input signed [26:0] alpha_i,input integer tag_i
);
  integer br,bc,bi,cols_i,dot_panels_i,rank_panels_i,dot_frames_i,rank_frames_i;
  reg signed [63:0] boundary_sum;
  reg signed [26:0] boundary_q,boundary_scaled;
  begin
    req_rows=rows_i;req_support_length=support_i;
    matrix_rows=rows_i;matrix_cols=support_i;
    for(br=0;br<rows_i;br=br+1) for(bc=0;bc<support_i;bc=bc+1) begin
      // Values keep every sum and update inside S27 while ensuring that
      // alpha=-0.75 has a visible, separately rounded effect.
      factor[br][bc]=80000+br*101+bc*71;
      expected[br][bc]=80000+br*101+bc*71;
    end
    for(bc=col_start_i;bc<support_i;bc=bc+1) begin
      boundary_sum=0;
      for(br=0;br<row_count_i;br=br+1)
        boundary_sum=boundary_sum+$signed(factor[row_start_i+br][bc])*$signed(avec[br]);
      boundary_q=r22(boundary_sum);
      boundary_scaled=r22($signed(boundary_q)*$signed(alpha_i));
      for(br=0;br<row_count_i;br=br+1)
        expected[row_start_i+br][bc]=factor[row_start_i+br][bc]-r22($signed(avec[br])*$signed(boundary_scaled));
    end
    cols_i=support_i-col_start_i;
    dot_panels_i=(cols_i+31)>>5;
    rank_panels_i=(cols_i+15)>>4;
    dot_frames_i=panel_frames(row_count_i,cols_i,32);
    rank_frames_i=panel_frames(row_count_i,cols_i,16);
    project_alpha=alpha_i;
    set_contexts(20);issue(20,row_start_i,row_count_i,col_start_i,tag_i,0);
    if(outputs!=0||rsp_count!==0||rsp_length!==0)$fatal(1,"boundary op20 public output rows=%0d support=%0d",rows_i,support_i);
    if(project_dot_done!=dot_panels_i||project_scale_done!=dot_panels_i||project_rank_done!=rank_panels_i||
       project_read_packets!=dot_frames_i+rank_frames_i||project_write_packets!=rank_frames_i)
      $fatal(1,"boundary phase counts M%0d S%0d start%0d/%0d col%0d dot/scale/rank=%0d/%0d/%0d reads/writes=%0d/%0d expected=%0d/%0d",rows_i,support_i,row_start_i,row_count_i,col_start_i,project_dot_done,project_scale_done,project_rank_done,project_read_packets,project_write_packets,dot_frames_i+rank_frames_i,rank_frames_i);
    for(br=0;br<rows_i;br=br+1) for(bc=0;bc<support_i;bc=bc+1)
      if(factor[br][bc]!==expected[br][bc])
        $fatal(1,"boundary project mismatch M%0d S%0d r%0d c%0d actual%0d expected%0d",rows_i,support_i,br,bc,factor[br][bc],expected[br][bc]);
  end
endtask
initial begin
   cycle=0;
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) factor[ii][jj]=10000+ii*11+jj*7;
   for(ii=0;ii<128;ii=ii+1) avec[ii]=20000+ii*101;
   for(ii=0;ii<96;ii=ii+1) bvec[ii]=5000+ii*17;
   repeat(3) tick();rst=0;tick();
   for(jj=3;jj<35;jj=jj+1) begin qsum=0;for(ii=1;ii<33;ii=ii+1)qsum=qsum+$signed(factor[ii][jj])*$signed(avec[ii-1]);qexpected[jj-3]=r22(qsum);end
   // M=33/S=35 exercises MATVEC width32 and every source row.
   set_contexts(17);
   issue(17,1,32,3,17,0);
   if(outputs!=1||rsp_count!==32||rsp_length!==32)$fatal(1,"MATVEC output extent");
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) expected[ii][jj]=factor[ii][jj];
   for(ii=2;ii<33;ii=ii+1) for(jj=4;jj<35;jj=jj+1) expected[ii][jj]=factor[ii][jj]-r22($signed(avec[ii-2])*$signed(bvec[jj-4]));
   // width31 splits into cascade panels16/15 and validates every write.
   set_contexts(18);issue(18,2,31,4,18,0);
   if(outputs!=0||rsp_count!==0||rsp_length!==0)$fatal(1,"RANK1 publication");
   for(ii=2;ii<33;ii=ii+1) for(jj=4;jj<35;jj=jj+1) if(factor[ii][jj]!==expected[ii][jj]) $fatal(1,"rank mismatch r%0d c%0d actual%0d expected%0d",ii,jj,factor[ii][jj],expected[ii][jj]);
   // B is fully prevalidated before the first private rank write.
   set_contexts(18);issue(18,2,31,4,19,2);
   // Maximum M/S geometry with col_start=1: three MAT panels (32+32+31).
   // This also forces four source-A blocks before any private-factor read.
   req_rows=128;req_support_length=96;matrix_rows=128;matrix_cols=96;
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) factor[ii][jj]=3000+ii*19+jj*5;
   for(jj=1;jj<96;jj=jj+1) begin
     qsum=0;for(ii=0;ii<128;ii=ii+1)qsum=qsum+$signed(factor[ii][jj])*$signed(avec[ii]);qexpected[jj-1]=r22(qsum);
   end
   set_contexts(17);issue(17,0,128,1,20,0);
   if(outputs!=3||rsp_count!==95||rsp_length!==95)$fatal(1,"M128/S96 MATVEC extent");
   // Full trailing rank update covers five 16-column panels and a 15-column
   // tail.  Compare the whole private image so unselected coordinates prove
   // untouched as well as every selected write.
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) expected[ii][jj]=factor[ii][jj];
   for(ii=1;ii<128;ii=ii+1) for(jj=1;jj<96;jj=jj+1) expected[ii][jj]=factor[ii][jj]-r22($signed(avec[ii-1])*$signed(bvec[jj-1]));
   set_contexts(18);issue(18,1,127,1,21,0);
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) if(factor[ii][jj]!==expected[ii][jj]) $fatal(1,"M128 rank mismatch r%0d c%0d",ii,jj);
   // Opcode20 keeps V and rounded Q resident through DOT, SCALE and RANK1.
   // It has no source-B, destination or candidate publication and spans the
   // same M128/S96 tails as the separate three-command lowering.
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) factor[ii][jj]=6000+ii*23+jj*3;
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) expected[ii][jj]=factor[ii][jj];
   for(jj=1;jj<96;jj=jj+1) begin
     qsum=0;for(ii=1;ii<128;ii=ii+1)qsum=qsum+$signed(factor[ii][jj])*$signed(avec[ii-1]);
     qexpected[jj-1]=r22(qsum);
   end
   for(ii=1;ii<128;ii=ii+1) for(jj=1;jj<96;jj=jj+1) expected[ii][jj]=factor[ii][jj]-r22($signed(avec[ii-1])*$signed(qexpected[jj-1]));
   set_contexts(20);issue(20,1,127,1,27,0);
   if(outputs!=0||rsp_count!==0||rsp_length!==0)$fatal(1,"PROJECT_UPDATE publication");
   if(project_dot_done!=3||project_scale_done!=3||project_read_packets!=1143||project_write_packets!=762)$fatal(1,"project phase packet counts dot=%0d scale=%0d reads=%0d writes=%0d",project_dot_done,project_scale_done,project_read_packets,project_write_packets);
   for(ii=0;ii<128;ii=ii+1) for(jj=0;jj<96;jj=jj+1) if(factor[ii][jj]!==expected[ii][jj]) $fatal(1,"project mismatch r%0d c%0d",ii,jj);
   // Phase-B boundary table.  These are deliberately selected tuples rather
   // than a geometry cross-product.  Together they cover every contract M/S
   // boundary, nonzero row/column starts, a last-column tail, and the real
   // M128 all-row case the earlier row_count=127 test could not establish.
   // -0.75 in S27F22 makes dot->round22->scale->round22 observable; a merged
   // multiply or an alpha-only integer path cannot satisfy this oracle.
   project_boundary(1,16,0,1,15,-27'sd3145728,36);
   project_boundary(31,17,1,30,16,-27'sd3145728,37);
   project_boundary(32,24,0,32,7,-27'sd3145728,38);
   project_boundary(33,32,1,32,31,-27'sd3145728,39);
   project_boundary(64,33,0,64,1,-27'sd3145728,40);
   project_boundary(64,65,1,63,32,-27'sd3145728,41);
   project_boundary(64,96,31,33,31,-27'sd3145728,42);
   project_boundary(128,64,0,128,0,-27'sd3145728,43);
   // Zero and negative alpha remain ordinary S27 inputs.  The scale phase
   // must preserve the separately rounded dot and use no public Q vector.
   req_rows=33;req_support_length=35;matrix_rows=33;matrix_cols=35;
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) factor[ii][jj]=9000+ii*13+jj*5;
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) expected[ii][jj]=factor[ii][jj];
   project_alpha=0;set_contexts(20);issue(20,1,32,3,28,0);
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) if(factor[ii][jj]!==expected[ii][jj]) $fatal(1,"zero-alpha project mismatch r%0d c%0d",ii,jj);
   for(jj=3;jj<35;jj=jj+1) begin qsum=0;for(ii=1;ii<33;ii=ii+1)qsum=qsum+$signed(factor[ii][jj])*$signed(avec[ii-1]);qexpected[jj-3]=r22(qsum);end
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) expected[ii][jj]=factor[ii][jj];
   for(ii=1;ii<33;ii=ii+1) for(jj=3;jj<35;jj=jj+1) expected[ii][jj]=factor[ii][jj]-r22($signed(avec[ii-1])*$signed(-qexpected[jj-3]));
   project_alpha=-27'sd4194304;set_contexts(20);issue(20,1,32,3,29,0);
   for(ii=0;ii<33;ii=ii+1) for(jj=0;jj<35;jj=jj+1) if(factor[ii][jj]!==expected[ii][jj]) $fatal(1,"negative-alpha project mismatch r%0d c%0d",ii,jj);
   project_alpha=27'sd4194304;
   req_rows=128;req_support_length=96;matrix_rows=128;matrix_cols=96;
   // Only opcode20 may consume the compact three-context image; a nonzero
   // padding word must fail before a bridge request or private write.
   set_contexts(20);req_contexts[192+:64]=64'd1;issue(20,0,2,0,30,1);
   // Operand replies are fully validated before DOT begins; no factor packet
   // is issued for either an A-mask or A-tag mismatch.
   set_contexts(20);issue(20,1,127,1,31,7);
   if(write_count!=0||project_read_packets!=0)$fatal(1,"project A-mask fault reached factor store");
   set_contexts(20);issue(20,1,127,1,32,8);
   if(write_count!=0||project_read_packets!=0)$fatal(1,"project A-tag fault reached factor store");
   // Both failures occur after at least one private rank write.  They must
   // invalidate the factor image and expose no candidate/public q payload.
   set_contexts(20);issue(20,1,127,1,33,5);
   set_contexts(20);issue(20,1,127,1,34,6);
   set_contexts(20);issue_cancel(20,1,127,1,35);
   // Wrong bridge replies fail before scratch publication.  The service must
   // consume neither a wrong mask nor a wrong tag as a valid row slot.
   set_contexts(17);issue(17,0,2,0,22,3);
   set_contexts(17);issue(17,0,2,0,23,4);
   // Force a store response and a cascade numeric response only after a
   // preceding rank packet wrote private factors.  Both paths invalidate and
   // never publish a public candidate.
   set_contexts(18);issue(18,1,127,1,24,5);
   set_contexts(18);issue(18,1,127,1,25,6);
   // Cancel after an observed private write; the worker must disappear with
   // no held service response or candidate publication.
   set_contexts(18);issue_cancel(18,1,127,1,26);
   // First bridge response faults before mutation and forces private-image invalidation.
   set_contexts(17);issue(17,0,2,0,19,1);
   $display("PASS factor_panel cycles=%0d",cycle);$finish;
 end
endmodule
