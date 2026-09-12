`timescale 1ns/1ps
module tb_factor_panel_bridge;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,cancel=0,req_valid=0;wire req_ready;reg [5:0] req_op=0;reg [8:0] req_src_a=0,req_dst=0;
 reg [7:0] req_rows=2;reg [10:0] req_cols=2,req_length=2,req_index=0,req_aux_length=0;reg [7:0] req_flags=0;reg req_matrix_dense=1;
 reg [127:0] req_key=128'h55;reg [31:0] req_generation=1;reg [15:0] req_job=7,req_tag=1;reg [7:0] req_fmt=1;
 reg matrix_valid=1;reg [7:0] matrix_rows=2;reg [10:0] matrix_cols=2;reg [127:0] matrix_key=128'h55;reg [31:0] matrix_generation=1;reg [15:0] matrix_job=7;reg [7:0] matrix_fmt=1;
 wire mat_valid;reg mat_ready=1;wire mat_dense;wire [31:0] mat_mask;wire [287:0] mat_addr;wire [127:0] mat_key;wire [31:0] mat_generation;wire [15:0] mat_job,mat_tag;wire [7:0] mat_fmt;
 reg mat_rsp_valid=0;wire mat_rsp_ready;reg [575:0] mat_rsp_data=0;reg [31:0] mat_rsp_mask=0,mat_rsp_generation=0;reg [15:0] mat_rsp_job=0,mat_rsp_tag=0;reg [7:0] mat_rsp_fmt=0;reg [3:0] mat_rsp_fault=0;
 wire vec_valid;reg vec_ready=1;wire [8:0] vec_block;wire [31:0] vec_mask;wire [15:0] vec_tag;reg vec_rsp_valid=0;wire vec_rsp_ready;reg [863:0] vec_rsp_data=0;reg [31:0] vec_rsp_mask=0;reg [15:0] vec_rsp_tag=0;reg [3:0] vec_rsp_fault=0;
 wire candidate_valid;reg candidate_ready=1;wire [4:0] candidate_block;wire [31:0] candidate_mask;wire [863:0] candidate_data;wire rsp_valid;reg rsp_ready=0;wire [3:0] rsp_fault,rsp_detail;wire [10:0] rsp_count,rsp_length;wire [63:0] rsp_data;wire rsp_nonzero;wire [15:0] rsp_job,rsp_tag;wire [7:0] rsp_fmt;wire factor_valid;
 reg panel_req_valid=0;wire panel_req_ready;reg panel_req_write=0;reg [31:0] panel_req_mask=0;reg [287:0] panel_req_addr=0;reg [863:0] panel_req_data=0;reg [7:0] panel_req_rows=2;reg [10:0] panel_req_cols=2;reg [127:0] panel_req_key=128'h55;reg [31:0] panel_req_generation=1;reg [15:0] panel_req_job=7,panel_req_tag=16'h44;reg [7:0] panel_req_fmt=1;reg panel_invalidate=0;
 wire panel_rsp_valid;reg panel_rsp_ready=0;wire panel_rsp_write;wire [863:0] panel_rsp_data;wire [31:0] panel_rsp_mask,panel_rsp_generation;wire [15:0] panel_rsp_job,panel_rsp_tag;wire [7:0] panel_rsp_fmt;wire [3:0] panel_rsp_fault;
 factor_service #(.ENABLE_PANEL_BRIDGE(1)) dut(.*);
 integer cycle,bank;reg [17:0] val;
 reg [863:0] held_data;reg [31:0] held_mask;reg [15:0] held_tag;reg held_write;reg [3:0] held_fault;
 always @(posedge clk) begin
  cycle<=cycle+1;
  if(mat_rsp_valid&&mat_rsp_ready)mat_rsp_valid<=0;
  if(mat_valid&&mat_ready) begin
   mat_rsp_valid<=1;mat_rsp_mask<=mat_mask;mat_rsp_generation<=mat_generation;mat_rsp_job<=mat_job;mat_rsp_tag<=mat_tag;mat_rsp_fmt<=mat_fmt;mat_rsp_fault<=0;mat_rsp_data<=0;
   for(bank=0;bank<32;bank=bank+1) if(mat_mask[bank]) begin
    if(mat_tag==1) val=(bank==0)?18'd11:18'd13; else val=(bank==1)?18'd12:18'd14;
    mat_rsp_data[bank*18+:18]<=val;
   end
  end
 end
 task tick;begin @(negedge clk);end endtask
 task wait_result;integer n;begin n=0;while(!rsp_valid)begin tick();n=n+1;if(n>200) $fatal(1,"init timeout");end;if(rsp_fault!=0||!factor_valid)$fatal(1,"init failed fault%0d detail%0d valid%0d",rsp_fault,rsp_detail,factor_valid);rsp_ready=1;tick();rsp_ready=0;tick();end endtask
 initial begin
  cycle=0;repeat(3)tick();rst=0;tick();req_op=13;
  while(!req_ready)tick();req_valid=1;tick();req_valid=0;wait_result();
  // Two reads occupy both bridge/store credits.  Their payloads and tags stay
  // held independently until each response is accepted in FIFO order.
  panel_req_mask=32'h2;panel_req_addr=0;panel_req_addr[1*9+:9]=0;panel_req_valid=1;
  while(!panel_req_ready)tick();tick();panel_req_valid=0;
  panel_req_tag=16'h46;panel_req_valid=1;while(!panel_req_ready)tick();tick();panel_req_valid=0;
  // The two bridge/store credits are now occupied.  A third request must not
  // be accepted while both prior responses are deliberately held.
  panel_req_tag=16'h47;panel_req_valid=1;
  repeat(3)begin tick();if(panel_req_ready)$fatal(1,"third bridge request exceeded two credits");end
  panel_req_valid=0;
  while(!panel_rsp_valid)tick();
  if(panel_rsp_fault!=0||panel_rsp_write||panel_rsp_mask!=32'h2||panel_rsp_data[1*27+:27]!==27'd768||panel_rsp_tag!=16'h44)$fatal(1,"first bridge read bad");
  held_data=panel_rsp_data;held_mask=panel_rsp_mask;held_tag=panel_rsp_tag;held_write=panel_rsp_write;held_fault=panel_rsp_fault;
  repeat(3)begin tick();if(!panel_rsp_valid||panel_rsp_data!==held_data||panel_rsp_mask!==held_mask||panel_rsp_tag!==held_tag||panel_rsp_write!==held_write||panel_rsp_fault!==held_fault)$fatal(1,"first bridge response not held stable");end
  panel_rsp_ready=1;tick();panel_rsp_ready=0;tick();
  while(!panel_rsp_valid)tick();
  if(panel_rsp_fault!=0||panel_rsp_write||panel_rsp_mask!=32'h2||panel_rsp_data[1*27+:27]!==27'd768||panel_rsp_tag!=16'h46)$fatal(1,"second bridge read bad");
  held_data=panel_rsp_data;held_mask=panel_rsp_mask;held_tag=panel_rsp_tag;held_write=panel_rsp_write;held_fault=panel_rsp_fault;
  repeat(3)begin tick();if(!panel_rsp_valid||panel_rsp_data!==held_data||panel_rsp_mask!==held_mask||panel_rsp_tag!==held_tag||panel_rsp_write!==held_write||panel_rsp_fault!==held_fault)$fatal(1,"second bridge response not held stable");end
  panel_rsp_ready=1;tick();panel_rsp_ready=0;tick();
  // A mismatched packet gets a held identity fault and invalidates ownership only when consumed.
  panel_req_generation=2;panel_req_tag=16'h45;panel_req_valid=1;while(!panel_req_ready)tick();tick();panel_req_valid=0;while(!panel_rsp_valid)tick();
  if(panel_rsp_fault!=6||!factor_valid)$fatal(1,"synthetic identity fault");panel_rsp_ready=1;tick();panel_rsp_ready=0;tick();if(factor_valid)$fatal(1,"fault retained factor image");
  $display("PASS factor_panel_bridge cycles=%0d",cycle);$finish;
 end
endmodule
