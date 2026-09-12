`timescale 1ns/1ps
// Bounded fabric contract gate: full-S27 MUL rounds before the second-array
// SUB, old values/fault metadata survive stalls, and legacy flow remains intact.
module tb_factor_panel_fabric;
reg clk=0,rst=1,abort=0,cfg_valid=0,cmd_valid=0,in_valid=0,in_last=0,out_ready=0,done_ready=0;
wire cfg_ready,cfg_loaded,cmd_ready,in_ready,out_valid,out_last,done_valid;
reg [2047:0] cfg_contexts=0; wire [3:0] cfg_fault,done_fault; reg [15:0] cmd_job=16'h31,cmd_tag=16'h72; reg [7:0] cmd_fmt=1;
reg [1:0] cmd_terminal=0,cmd_flow=1; reg [5:0] cmd_shift=0; reg [31:0] cmd_terminal_mask=0;
reg [863:0] in_a=0,in_b=0; reg [31:0] in_mask=0;
wire [863:0] out_data; wire [2047:0] out_acc,terminal_acc; wire [31:0] out_mask; wire [127:0] out_faults; wire [3:0] terminal_error; wire [15:0] done_job,done_tag;wire [7:0] done_fmt;
stream_fabric #(.CASCADE_ENABLE(1)) dut(.*);
always #5 clk=~clk;
task tick; begin @(posedge clk);#1; end endtask
task put_frame(input integer n,input bit last); integer l; begin
  @(negedge clk); in_valid=1;in_last=last;in_mask=32'hffffffff;in_a=0;in_b=0;
  for(l=0;l<16;l=l+1) begin in_a[l*27+:27]=(1<<22)+n;in_b[l*27+:27]=(1<<22);in_a[(16+l)*27+:27]=(2<<22)+n;end
  while(!in_ready) tick(); tick(); @(negedge clk);in_valid=0;
end endtask
task put_values(input integer av,input integer bv,input integer ov,input bit last); integer l; begin
  @(negedge clk);in_valid=1;in_last=last;in_mask=32'hffffffff;in_a=0;in_b=0;
  for(l=0;l<16;l=l+1) begin in_a[l*27+:27]=av;in_b[l*27+:27]=bv;in_a[(16+l)*27+:27]=ov;end
  while(!in_ready)tick();tick();@(negedge clk);in_valid=0;
end endtask
task expect_one(input integer value,input [3:0] fault);integer q,e;begin
  out_ready=1;q=0;while(!out_valid&&q<200)begin tick();q=q+1;end
  if(!out_valid)$fatal(1,"missing output");for(e=0;e<16;e=e+1)if($signed(out_data[e*27+:27])!=value||out_faults[e*4+:4]!=fault)$fatal(1,"numeric lane%0d d%0d f%0d",e,$signed(out_data[e*27+:27]),out_faults[e*4+:4]);
  tick();
end endtask
localparam RANDOM_FRAMES=18;
integer random_expected[0:RANDOM_FRAMES-1][0:15];
reg [15:0] random_masks[0:RANDOM_FRAMES-1]; reg random_lasts[0:RANDOM_FRAMES-1];
integer random_received=0; reg random_active=0,random_held=0; reg [31:0] random_lfsr=32'h1b0a_91e7;
reg [863:0] random_hold_data; reg [31:0] random_hold_mask; reg [127:0] random_hold_fault; reg random_hold_last;
function integer round22(input integer av,input integer bv); reg signed [63:0] product,magnitude; begin
  product=av*bv; magnitude=product<0 ? -product : product; magnitude=(magnitude+(64'sd1<<21))>>>22;
  round22=product<0 ? -magnitude : magnitude;
end endfunction
task random_advance; begin random_lfsr={random_lfsr[30:0],random_lfsr[31]^random_lfsr[21]^random_lfsr[1]^random_lfsr[0]}; end endtask
task put_random_frame(input integer frame); integer rl,av,bv,ov,q; begin
  random_advance();
  random_masks[frame]=(frame==0||frame==9) ? 0 : (random_lfsr[15:0]|(frame[0] ? 16'h8000 : 16'h0001));
  random_lasts[frame]=(frame==RANDOM_FRAMES-1);
  @(negedge clk); in_valid=1;in_last=random_lasts[frame];in_mask={random_masks[frame],random_masks[frame]};in_a=0;in_b=0;
  for(rl=0;rl<16;rl=rl+1) begin
    random_advance();av=$signed({1'b0,random_lfsr[21:0]})-(1<<21);
    random_advance();bv=$signed({1'b0,random_lfsr[21:0]})-(1<<21);
    random_advance();ov=$signed({1'b0,random_lfsr[23:0]})-(1<<23);
    if(frame==1) begin av=1;bv=1<<21; end
    if(frame==2) begin av=-1;bv=1<<21; end
    q=round22(av,bv);random_expected[frame][rl]=random_masks[frame][rl] ? ov-q : 0;
    in_a[rl*27+:27]=av;in_b[rl*27+:27]=bv;in_a[(16+rl)*27+:27]=ov;
  end
  out_ready=(frame%3)!=0;
  while(!in_ready) begin @(negedge clk);out_ready=1;tick();end
  tick();@(negedge clk);in_valid=0;
end endtask
integer i,l,rl,got=0,cycles=0; reg [863:0] hold_data;reg [31:0] hold_mask;reg [127:0] hold_fault;reg hold_last,held=0;
always @(posedge clk) begin cycles<=cycles+1;if(cycles>2000)$fatal(1,"watchdog state=%0d got=%0d valid=%b ready=%b old=%0d meta=%0d",dut.state,random_received,out_valid,out_ready,dut.old_count,dut.meta_count); end
always @(posedge clk) if(random_active) begin
  if(random_held&&(!out_valid||out_data!==random_hold_data||out_mask!==random_hold_mask||out_faults!==random_hold_fault||out_last!==random_hold_last))$fatal(1,"random held output");
  random_held=out_valid&&!out_ready;random_hold_data=out_data;random_hold_mask=out_mask;random_hold_fault=out_faults;random_hold_last=out_last;
  if(out_valid&&out_ready) begin
    if(random_received>=RANDOM_FRAMES)$fatal(1,"unexpected random output");
    if(out_mask!=={16'd0,random_masks[random_received]}||out_last!==random_lasts[random_received]||out_faults!==0||out_data[863:432]!==0)$fatal(1,"random shape frame%0d",random_received);
    for(rl=0;rl<16;rl=rl+1)if($signed(out_data[rl*27+:27])!=random_expected[random_received][rl])$fatal(1,"random oracle frame%0d lane%0d got%0d exp%0d",random_received,rl,$signed(out_data[rl*27+:27]),random_expected[random_received][rl]);
    random_received=random_received+1;
  end
end
initial begin
  repeat(2) tick();@(negedge clk);rst=0;
  for(i=0;i<16;i=i+1) begin cfg_contexts[i*64+:64]=64'h128; cfg_contexts[(16+i)*64+:64]=64'h123; end
  @(negedge clk);cfg_valid=1;tick();@(negedge clk);cfg_valid=0;if(!cfg_loaded||cfg_fault!=0)$fatal(1,"cascade config");
  // Configuration bus is deliberately changed after cfg handshake; command
  // acceptance must use the captured eligible image, never this live bus.
  @(negedge clk);cfg_contexts=0;cmd_valid=1;tick();@(negedge clk);cmd_valid=0;if(!in_ready)$fatal(1,"cascade start");
  put_frame(0,0);put_frame(1,0);put_frame(2,1);
  while(!done_valid) begin
    @(negedge clk); out_ready=(cycles%4)!=0;
    if(held&&(!out_valid||out_data!==hold_data||out_mask!==hold_mask||out_faults!==hold_fault||out_last!==hold_last))$fatal(1,"held output");
    held=out_valid&&!out_ready;hold_data=out_data;hold_mask=out_mask;hold_fault=out_faults;hold_last=out_last;
    if(out_valid&&out_ready) begin
      if(out_mask!==16'hffff||out_faults!==0||out_last!==(got==2)||out_data[863:432]!==0)$fatal(1,"cascade shape mask=%h faults=%h last=%b high=%h",out_mask,out_faults,out_last,out_data[863:432]);
      for(l=0;l<16;l=l+1) if($signed(out_data[l*27+:27])!=(1<<22))$fatal(1,"round then sub lane%0d got%0d",l,$signed(out_data[l*27+:27]));
      got=got+1;
    end
    tick();
  end
  if(got!=3||done_fault!=0)$fatal(1,"cascade completion got%0d fault%0d",got,done_fault);
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Eighteen independent LFSR-derived frames cover paired partial masks,
  // zero-mask frames, signed half ties, tails, and randomized output stalls.
  // The integer round22 oracle is intentionally separate from the PE RTL.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;
  random_active=1;random_received=0;random_held=0;out_ready=1;
  for(i=0;i<RANDOM_FRAMES;i=i+1)put_random_frame(i);
  while(random_received<RANDOM_FRAMES) begin
    @(negedge clk);random_advance();out_ready=random_lfsr[0]||random_lfsr[2];tick();
  end
  random_active=0;if(!done_valid||done_fault!=0)$fatal(1,"random cascade completion");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // A bad paired mask is rejected before either stage is admitted, then the
  // fabric is available for a later command after DONE retirement.
  for(i=0;i<16;i=i+1) begin cfg_contexts[i*64+:64]=64'h128; cfg_contexts[(16+i)*64+:64]=64'h123; end
  @(negedge clk);cfg_valid=1;tick();@(negedge clk);cfg_valid=0;
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;
  @(negedge clk);in_valid=1;in_mask=32'h0000ffff;in_last=1;tick();@(negedge clk);in_valid=0;
  repeat(2)tick();if(!done_valid||done_fault!=1)$fatal(1,"pair mask rejection");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Admit a valid frame, then present a malformed paired mask while its work
  // is queued. DONE must hold without any later array handshakes; a fresh
  // command proves the queue was discarded transactionally.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=0;
  put_values(1<<22,1<<22,2<<22,0);repeat(3)tick();
  @(negedge clk);in_valid=1;in_last=1;in_mask=32'h0000ffff;in_a=0;in_b=0;tick();@(negedge clk);in_valid=0;
  if(!done_valid||done_fault!=1)$fatal(1,"queued pair mask rejection");
  repeat(3)begin
    if(dut.array_in_valid!==0||dut.array_out_ready!==0)$fatal(1,"array handshake after malformed DONE");
    tick();if(!done_valid||done_fault!=1)$fatal(1,"malformed DONE hold");
  end
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=1;put_values(1<<22,1<<22,2<<22,1);expect_one(1<<22,0);while(!done_valid)tick();if(done_fault!=0)$fatal(1,"malformed recovery");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Command legality is checked before RUN.  No array may see a frame for an
  // unsupported flow or a cascade command carrying terminal state.
  @(negedge clk);cmd_flow=2;cmd_valid=1;tick();@(negedge clk);cmd_valid=0;
  if(!done_valid||done_fault!=1)$fatal(1,"invalid flow");@(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  @(negedge clk);cmd_flow=1;cmd_terminal=1;cmd_valid=1;tick();@(negedge clk);cmd_valid=0;
  if(!done_valid||done_fault!=1)$fatal(1,"cascade terminal");cmd_terminal=0;@(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // A syntactically valid but non-cascade high context must load normally
  // yet be rejected when it is offered as flow1.
  cfg_contexts[16*64+:64]=64'h121;
  @(negedge clk);cfg_valid=1;tick();@(negedge clk);cfg_valid=0;if(!cfg_loaded)$fatal(1,"ordinary config");
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;
  if(!done_valid||done_fault!=1)$fatal(1,"cascade context");@(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Cancel while the old-factor FIFO owns data.  All visible ownership drops
  // immediately, then a fresh legal configuration/command completes.
  for(i=0;i<16;i=i+1) begin cfg_contexts[i*64+:64]=64'h128; cfg_contexts[(16+i)*64+:64]=64'h123; end
  @(negedge clk);cfg_valid=1;tick();@(negedge clk);cfg_valid=0;
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=0;
  put_frame(3,0);put_frame(4,0); // fills bounded old-value credit path
  @(negedge clk);abort=1;#1;if(in_ready||out_valid||done_valid||cfg_ready)$fatal(1,"abort visibility");tick();@(negedge clk);abort=0;
  if(!cfg_loaded)$fatal(1,"abort preserves config");
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=1;got=0;put_frame(5,1);
  while(!done_valid)tick();if(done_fault!=0)$fatal(1,"recovery fault");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Signed half tie: +2^21 shifted by 22 rounds away from zero to +1;
  // subtraction therefore publishes -1 with no fault.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;put_values(1,1<<21,0,1);expect_one(-1,0);while(!done_valid)tick();if(done_fault!=0)$fatal(1,"tie done");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Rounded MUL overflow is retained as the causal lane fault.  A legal MUL
  // followed by an out-of-range SUB separately proves the second-stage path.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;put_values(67108863,67108863,0,1);expect_one(0,3);while(!done_valid)tick();if(done_fault!=3)$fatal(1,"mul done");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;put_values(1<<24,1<<24,-(1<<26),1);expect_one(-(1<<26),3);while(!done_valid)tick();if(done_fault!=3)$fatal(1,"sub done");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // The fault mux must retain the original MUL range code when the downstream
  // metadata carries a distinct simultaneous SUB fault; numeric fault codes
  // are selected, never bitwise-ORed. The MUL range is produced by the PE;
  // the conflicting downstream metadata is injected at the fabric boundary.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=0;put_values(67108863,67108863,-(1<<26),1);
  force dut.arrays[1].array_core.in_b={16{27'h3ffffff}};force dut.array_out_faults[64+:64]={16{4'h4}};
  out_ready=1;expect_one(0,3);release dut.arrays[1].array_core.in_b;release dut.array_out_faults[64+:64];while(!done_valid)tick();if(done_fault!=3)$fatal(1,"mul precedence done");
  @(negedge clk);done_ready=1;tick();@(negedge clk);done_ready=0;
  // Reset while a real SUB result is valid and held drops that ownership and
  // clears configuration, so no pre-reset output can reappear.
  @(negedge clk);cmd_valid=1;tick();@(negedge clk);cmd_valid=0;out_ready=0;put_values(1<<22,1<<22,2<<22,1);
  while(!out_valid)tick();hold_data=out_data;hold_mask=out_mask;hold_fault=out_faults;hold_last=out_last;tick();
  if(!out_valid||out_data!==hold_data||out_mask!==hold_mask||out_faults!==hold_fault||out_last!==hold_last)$fatal(1,"sub held before reset");
  @(negedge clk);rst=1;#1;if(in_ready||out_valid||done_valid||cfg_ready)$fatal(1,"reset visibility");tick();@(negedge clk);rst=0;if(cfg_loaded)$fatal(1,"reset config");
  $display("PASS factor_panel_fabric frames=%0d cycles=%0d",got,cycles);$finish;
end
endmodule
