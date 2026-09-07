`timescale 1ns/1ps
`default_nettype none
`include "architecture_parameters.vh"
`include "context_isa_defs.vh"
`include "reconstruction_control_defs.vh"
`include "result_format_defs.vh"

module tb_m12_lifecycle_top;
localparam [63:0] CFG_ADDR=64'h1000;
localparam integer DW=`RECON_SOLVER_W;
reg clk=0; always #5 clk=~clk;
reg rst_n=0; integer failures=0;
reg [11:0] s_axi_awaddr=0; reg s_axi_awvalid=0; wire s_axi_awready;
reg [31:0] s_axi_wdata=0; reg [3:0] s_axi_wstrb=4'hf; reg s_axi_wvalid=0; wire s_axi_wready;
wire [1:0] s_axi_bresp; wire s_axi_bvalid; reg s_axi_bready=1;
reg [11:0] s_axi_araddr=0; reg s_axi_arvalid=0; wire s_axi_arready;
wire [31:0] s_axi_rdata; wire [1:0] s_axi_rresp; wire s_axi_rvalid; reg s_axi_rready=1; wire irq;
reg active_context_image_ok=1; wire phase_rd_en; wire [7:0] phase_rd_addr;
reg phase_rd_resp_valid=0,phase_rd_valid=0; reg [7:0] phase_rd_pc=0; reg [35:0] phase_word=0;
wire array_launch_valid; reg array_launch_ready=1; wire [7:0] array_entry_pc; wire [3:0] array_event_id;
reg array_done_valid=0; wire array_done_ready; reg [3:0] array_done_event_id=0; reg array_done_aborted=0;
reg array_fault_valid=0; wire array_fault_ready; reg [7:0] array_fault_code=0,array_fault_pc=0; reg [31:0] array_fault_detail=0;
reg resource_valid=0; wire resource_ready; reg [3:0] resource_event=0; reg compute_dma_done=0;
reg residual_limit_reached=0,iteration_limit_reached=0,support_stable=0,residual_decreased=0,solver_converged=0,solver_fault=0;
reg exec_error_pending=0; reg [3:0] exec_error_class=0; reg [7:0] exec_error_code=0; reg [31:0] exec_error_detail=0;
reg [15:0] outer_iter=0; reg [7:0] solver_iter=0;
reg [6:0] final_support_count=1; reg [`RECON_K_MAX*10-1:0] final_support_indices=0;
reg [`RECON_K_MAX*DW-1:0] final_support_coefficients=0;
wire active_cfg_valid; wire [1:0] active_result_mode,active_matrix_kind; wire [8:0] active_measurement_count;
wire [10:0] active_signal_length; wire [6:0] active_sparsity; wire [15:0] active_outer_limit;
wire [7:0] active_refine_limit; wire [4:0] active_normal_residual_shift; wire [1:0] active_refinement_profile;
wire [61:0] active_residual_limit; wire [63:0] active_phi_seed,active_measurement_address;
wire [63:0] active_dense_result_address,active_sparse_result_address; wire [31:0] active_user_tag;
wire [17:0] active_phi_scale_mantissa_uq17; wire [4:0] active_phi_scale_exponent;
wire [7:0] active_phi_column_weight; wire active_require_unit_norm;
reg [1:0] aux_req_valid=0,aux_req_write=0; wire [1:0] aux_req_ready; reg [127:0] aux_req_addr=0; reg [31:0] aux_req_bytes=0; reg [15:0] aux_req_tag=0;
reg [1:0] aux_wr_valid=0; wire [1:0] aux_wr_ready; reg [255:0] aux_wr_data=0; reg [31:0] aux_wr_keep=0; reg [1:0] aux_wr_last=0;
wire [1:0] aux_rd_valid; reg [1:0] aux_rd_ready=0; wire [255:0] aux_rd_data; wire [1:0] aux_rd_last; wire [3:0] aux_rd_resp; wire [15:0] aux_rd_tag;
wire [1:0] aux_done_valid; reg [1:0] aux_done_ready=0; wire [15:0] aux_done_tag; wire [1:0] aux_done_error; wire [3:0] aux_done_resp; wire [17:0] aux_done_beat;
wire [63:0] m_axi_araddr; wire [7:0] m_axi_arlen; wire [2:0] m_axi_arsize; wire [1:0] m_axi_arburst; wire m_axi_arvalid; wire m_axi_arready;
reg [127:0] m_axi_rdata=0; reg [1:0] m_axi_rresp=0; reg m_axi_rlast=0,m_axi_rvalid=0; wire m_axi_rready;
wire [63:0] m_axi_awaddr; wire [7:0] m_axi_awlen; wire [2:0] m_axi_awsize; wire [1:0] m_axi_awburst; wire m_axi_awvalid; wire m_axi_awready;
wire [127:0] m_axi_wdata; wire [15:0] m_axi_wstrb; wire m_axi_wlast,m_axi_wvalid; wire m_axi_wready;
reg [1:0] m_axi_bresp=0; reg m_axi_bvalid=0; wire m_axi_bready;
wire engine_busy,phase_active,compute_abort_pending,writeback_active;
wire run_start_pulse; wire [2:0] lifecycle_state;
reg [127:0] cfg_beats[0:3]; reg read_active=0; reg [7:0] read_idx=0,read_len=0;
reg write_active=0; reg [7:0] write_idx=0,write_len=0; reg active_write_error=0;
integer bursts=0,beats=0,inject_error_burst=-1; reg [63:0] burst_addr[0:15]; reg [127:0] beat_data[0:31];
assign m_axi_arready=!read_active&&!m_axi_rvalid; assign m_axi_awready=!write_active&&!m_axi_bvalid; assign m_axi_wready=write_active;

function automatic [35:0] complete_word; reg [35:0] v; begin v=0; v[2:0]=`RECON_PHASE_OP_COMPLETE; v[31:28]=`RECON_STOP_SUPPORT_STABLE; v[32]=1; complete_word=v; end endfunction
function automatic [127:0] header; input [1:0] mode; input [3:0] reason; begin header={7'd0,1'b1,11'd8,13'd16,`RECON_RESULT_FORMAT_REVISION,mode,reason,7'd1,11'd4,32'hfeed1234,`RECON_RESULT_HEADER_MAGIC}; end endfunction
task automatic check; input condition; input [8*100-1:0] msg; begin if(!condition) begin $display("FAIL: %0s",msg); failures=failures+1; end end endtask

task automatic csr_write; input [11:0] a; input [31:0] d; reg ad,wd; begin ad=0;wd=0; @(negedge clk); s_axi_awaddr=a;s_axi_awvalid=1;s_axi_wdata=d;s_axi_wvalid=1;
while(!ad||!wd) begin @(posedge clk); if(s_axi_awvalid&&s_axi_awready)ad=1; if(s_axi_wvalid&&s_axi_wready)wd=1; @(negedge clk); if(ad)s_axi_awvalid=0;if(wd)s_axi_wvalid=0; end
while(!s_axi_bvalid)@(posedge clk); check(s_axi_bresp==`AXI_RESP_OKAY,"CSR write response"); @(posedge clk); end endtask
task automatic csr_read; input [11:0] a; output [31:0] d; begin @(negedge clk);s_axi_araddr=a;s_axi_arvalid=1; while(!(s_axi_arvalid&&s_axi_arready))@(posedge clk); @(negedge clk);s_axi_arvalid=0; while(!s_axi_rvalid)@(posedge clk); d=s_axi_rdata;check(s_axi_rresp==`AXI_RESP_OKAY,"CSR read response");@(posedge clk);end endtask

task automatic load_cfg; input [1:0] mode; input [63:0] da,sa; begin
cfg_beats[0]=0;cfg_beats[1]=0;cfg_beats[2]=0;cfg_beats[3]=0;
cfg_beats[0][31:0]={2'd0,mode,4'd0,`RECON_RUN_CONFIGURATION_REVISION,`RECON_RUN_CONFIGURATION_MAGIC}; cfg_beats[0][63:32]={5'd0,7'd1,11'd4,9'd4}; cfg_beats[0][95:64]=32'h04100014;
cfg_beats[1][31:0]=32'h100;cfg_beats[1][95:64]=32'h89abcdef;cfg_beats[1][127:96]=32'h01234567;
cfg_beats[2][31:0]=32'h4000;cfg_beats[2][95:64]=da[31:0];cfg_beats[2][127:96]=da[63:32];
cfg_beats[3][31:0]=sa[31:0];cfg_beats[3][63:32]=sa[63:32];cfg_beats[3][95:64]=32'hfeed1234;cfg_beats[3][127:96]=32'h01820000;end endtask
task automatic start_run; begin csr_write(`RECON_CSR_RUN_CONFIGURATION_LO,CFG_ADDR[31:0]);csr_write(`RECON_CSR_RUN_CONFIGURATION_HI,CFG_ADDR[63:32]);csr_write(`RECON_CSR_COMMAND,1);end endtask
task automatic wait_term; output [31:0] st; integer t; begin
t=0;while(!engine_busy&&t<100)begin @(posedge clk);t=t+1;end
check(t<100,"lifecycle did not start");
t=0;while(engine_busy&&t<3000)begin @(posedge clk);t=t+1;end
check(t<3000,"terminal timeout");csr_read(`RECON_CSR_STATUS,st);end endtask
task automatic clear_log; begin bursts=0;beats=0;inject_error_burst=-1;end endtask

always @(posedge clk) begin
phase_rd_resp_valid<=phase_rd_en;phase_rd_valid<=phase_rd_en;if(phase_rd_en)begin phase_rd_pc<=phase_rd_addr;phase_word<=complete_word();end
if(!rst_n)begin read_active<=0;m_axi_rvalid<=0;write_active<=0;m_axi_bvalid<=0;end else begin
if(m_axi_arvalid&&m_axi_arready)begin check(m_axi_araddr==CFG_ADDR,"config address");check(m_axi_arlen==3,"config length");read_active<=1;read_idx<=0;read_len<=m_axi_arlen;end
if(read_active&&!m_axi_rvalid)begin m_axi_rvalid<=1;m_axi_rdata<=cfg_beats[read_idx];m_axi_rresp<=0;m_axi_rlast<=(read_idx==read_len);end
if(m_axi_rvalid&&m_axi_rready)begin m_axi_rvalid<=0;if(m_axi_rlast)read_active<=0;else read_idx<=read_idx+1;end
if(m_axi_awvalid&&m_axi_awready)begin burst_addr[bursts]<=m_axi_awaddr;active_write_error<=(bursts==inject_error_burst);bursts<=bursts+1;write_active<=1;write_idx<=0;write_len<=m_axi_awlen;check(m_axi_awsize==4,"AW size");end
if(m_axi_wvalid&&m_axi_wready)begin beat_data[beats]<=m_axi_wdata;beats<=beats+1;check(m_axi_wstrb==16'hffff,"WSTRB");check(m_axi_wlast==(write_idx==write_len),"WLAST");if(m_axi_wlast)begin write_active<=0;m_axi_bvalid<=1;m_axi_bresp<=active_write_error?2'b10:0;end else write_idx<=write_idx+1;end
if(m_axi_bvalid&&m_axi_bready)m_axi_bvalid<=0;end end

wire [4:0] active_measurement_row_blocks;
m12_lifecycle_top dut(.*);
reg [31:0] status; integer expected_bursts; reg [1:0] mode;
initial begin final_support_indices[0+:10]=2;final_support_coefficients[0+:DW]=-27'sd6;repeat(6)@(posedge clk);rst_n=1;repeat(4)@(posedge clk);
for(mode=0;mode<3;mode=mode+1)begin clear_log();load_cfg(mode,64'h8000+(mode*64'h2000),64'h9000+(mode*64'h2000));start_run();wait_term(status);expected_bursts=(mode==2)?3:2;
check(status[5]&&!status[6],"success status");check(bursts==expected_bursts&&beats==expected_bursts,"mode burst count");
if(mode==0)begin check(burst_addr[0]==64'h8010&&burst_addr[1]==64'h8000,"dense addresses");check(beat_data[0]=={32'd0,32'hfffffffa,64'd0},"dense payload");end
if(mode==1)begin check(burst_addr[0]==64'hb010&&burst_addr[1]==64'hb000,"sparse addresses");check(beat_data[0]=={64'd0,32'd2,32'hfffffffa},"sparse payload");end
if(mode==2)check(burst_addr[0]==64'hc010&&burst_addr[1]==64'hd010&&burst_addr[2]==64'hd000,"both ordering");check(beat_data[expected_bursts-1]==header(mode,`RECON_STOP_SUPPORT_STABLE),"success header");end
clear_log();load_cfg(2,64'he000,64'hf000);start_run();while(!writeback_active)@(posedge clk);csr_write(`RECON_CSR_COMMAND,2);wait_term(status);check(status[5]&&!status[6]&&status[11:8]==`RECON_STOP_ABORTED,"writeback abort");check(bursts<3,"abort suppresses header");
clear_log();load_cfg(2,64'h12000,64'h13000);inject_error_burst=0;start_run();wait_term(status);check(!status[5]&&status[6],"DMA error status");check(bursts==1,"DMA error suppresses later writes");
clear_log();load_cfg(0,64'h14000,64'h15000);start_run();while(!read_active)@(posedge clk);csr_write(`RECON_CSR_COMMAND,2);wait_term(status);repeat(20)@(posedge clk);check(status[5]&&!status[6]&&status[11:8]==`RECON_STOP_ABORTED,"config abort");check(!active_cfg_valid&&bursts==0,"config abort no orphan commit");
if(failures==0)$display("M12 LIFECYCLE TOP PASS");else $display("FAIL: M12 LIFECYCLE TOP failures=%0d",failures);$finish;end
endmodule
`default_nettype wire
