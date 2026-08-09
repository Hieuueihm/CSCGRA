`timescale 1ns/1ps
module tb_run1_k_sweep;
localparam DATA_W=24;
localparam CTX_LIMIT=2048;
localparam REG_CTRL=12'h000;
localparam REG_STATUS=12'h004;
localparam REG_M_SIZE=12'h00c;
localparam REG_N_SIZE=12'h010;
localparam REG_K_PARAM=12'h014;
localparam REG_Y_DDR=12'h018;
localparam REG_X_DDR=12'h01c;
localparam REG_SEED=12'h020;
localparam REG_PHI_SCALE=12'h024;
localparam REG_FLAGS=12'h030;
localparam REG_MAX_ITER=12'h028;
localparam REG_MU_SHIFT=12'h070;
localparam REG_PROG_BASE=12'h040;
localparam REG_PROG_LEN=12'h044;
localparam REG_CYCLE_CNT=12'h054;
localparam REG_PC_DBG=12'h058;
localparam REG_CTX_BASE=12'h100;
localparam DDR_Y_BASE=32'h00001000;
localparam DDR_X_BASE=32'h00002000;
localparam SOP_REFINE=8'h80, SOP_CORR=8'h81, SOP_IHT_UPDATE=8'h82, SOP_RESID=8'h83;
localparam SOP_PRUNE_X=8'h84, SOP_MP_UPDATE=8'h85, SOP_GP_NO_LS_UPDATE=8'h85, SOP_REFINE_SPARSE=8'h86, SOP_GRAD_STEP=8'h87, SOP_CORR_UPDATE=8'h88;
localparam ALG_OMP=0, ALG_COSAMP=1, ALG_IHT=2, ALG_HTP=3, ALG_SP=4, ALG_5=5, ALG_6=6, ALG_MP=7;
localparam VEC_X=0, VEC_R=1, VEC_Y=2;
localparam CASE_COUNT=8;

reg clk,rst_n;
reg [13:0] s_axi_awaddr; reg s_axi_awvalid; wire s_axi_awready;
reg [31:0] s_axi_wdata; reg [3:0] s_axi_wstrb; reg s_axi_wvalid; wire s_axi_wready;
wire [1:0] s_axi_bresp; wire s_axi_bvalid; reg s_axi_bready;
reg [13:0] s_axi_araddr; reg s_axi_arvalid; wire s_axi_arready; wire [31:0] s_axi_rdata; wire [1:0] s_axi_rresp; wire s_axi_rvalid; reg s_axi_rready;
wire [31:0] m_axi_araddr; wire [7:0] m_axi_arlen; wire [2:0] m_axi_arsize; wire [1:0] m_axi_arburst; wire m_axi_arvalid; reg m_axi_arready;
reg [31:0] m_axi_rdata; reg m_axi_rvalid; reg m_axi_rlast; wire m_axi_rready;
wire [31:0] m_axi_awaddr; wire [7:0] m_axi_awlen; wire [2:0] m_axi_awsize; wire [1:0] m_axi_awburst; wire m_axi_awvalid; reg m_axi_awready;
wire [31:0] m_axi_wdata; wire [3:0] m_axi_wstrb; wire m_axi_wlast; wire m_axi_wvalid; reg m_axi_wready;
reg [1:0] m_axi_bresp; reg m_axi_bvalid; wire m_axi_bready;
wire irq_done, irq_error;

reg [31:0] ddr_y [0:255];
reg [31:0] ddr_x [0:255];
reg [31:0] rd_base_word;
reg rd_sel_x;
reg [8:0] rd_len, rd_count;
reg [31:0] wr_base_word;
reg [8:0] wr_len, wr_count;
reg [31:0] status_rd, cycle_rd, pc_rd;
reg [23:0] got; reg signed [24:0] diff;
integer pass_cnt, fail_cnt, alg, i, timeout, pc, ctx_loop_count, iter;
integer start_alg, end_alg, case_idx, start_case, end_case, run_case_alg;
integer case_m, case_n, case_k, nz_count, mismatch_prints;
integer profile_states, profile_total_cycles;
integer profile_ctrl_cycles [0:127];
integer profile_topk_cycles [0:7];
integer profile_support_cycles [0:15];
integer profile_uop_cycles [0:15];
reg done_seen, error_seen;

`include "k_sweep_golden_mu3.vh"

cgra_top dut(.clk(clk),.rst_n(rst_n),.s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),.s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),.s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),.s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),.s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),.m_axi_rdata(m_axi_rdata),.m_axi_rvalid(m_axi_rvalid),.m_axi_rlast(m_axi_rlast),.m_axi_rready(m_axi_rready),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),.m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),.irq_done(irq_done),.irq_error(irq_error));

always #5 clk=~clk;
task tick; begin @(posedge clk); #1; end endtask
task check; input [255:0] name; input cond; begin if(cond) begin pass_cnt=pass_cnt+1; end else begin $display("FAIL %0s",name); fail_cnt=fail_cnt+1; end end endtask
task profile_reset; integer p; begin
    profile_total_cycles=0;
    for(p=0;p<128;p=p+1) profile_ctrl_cycles[p]=0;
    for(p=0;p<8;p=p+1) profile_topk_cycles[p]=0;
    for(p=0;p<16;p=p+1) begin
        profile_support_cycles[p]=0;
        profile_uop_cycles[p]=0;
    end
end endtask
task profile_dump; input integer alg_id; integer p; integer factor_total; integer topk_total; integer support_total; begin
    if(profile_states) begin
        factor_total=profile_ctrl_cycles[125]+profile_ctrl_cycles[126]+profile_ctrl_cycles[127];
        topk_total=0; support_total=0;
        for(p=0;p<8;p=p+1) topk_total=topk_total+profile_topk_cycles[p];
        for(p=1;p<16;p=p+1) support_total=support_total+profile_support_cycles[p];
        $display("STATE_PROFILE_SUMMARY case=%0d alg=%0d total=%0d factor=%0d topk=%0d support_nonidle=%0d reduce_uop=%0d",
                 case_idx,alg_id,profile_total_cycles,factor_total,topk_total,support_total,profile_uop_cycles[4]);
        for(p=0;p<128;p=p+1)
            if(profile_ctrl_cycles[p]!=0)
                $display("STATE_PROFILE case=%0d alg=%0d kind=CTRL state=%0d cycles=%0d",case_idx,alg_id,p,profile_ctrl_cycles[p]);
        for(p=0;p<8;p=p+1)
            if(profile_topk_cycles[p]!=0)
                $display("STATE_PROFILE case=%0d alg=%0d kind=TOPK state=%0d cycles=%0d",case_idx,alg_id,p,profile_topk_cycles[p]);
        for(p=1;p<16;p=p+1)
            if(profile_support_cycles[p]!=0)
                $display("STATE_PROFILE case=%0d alg=%0d kind=SUPPORT state=%0d cycles=%0d",case_idx,alg_id,p,profile_support_cycles[p]);
        for(p=0;p<16;p=p+1)
            if(profile_uop_cycles[p]!=0)
                $display("STATE_PROFILE case=%0d alg=%0d kind=UOP state=%0d cycles=%0d",case_idx,alg_id,p,profile_uop_cycles[p]);
    end
end endtask
function absdiff_le; input [23:0] a,b; input integer tol; begin diff={a[23],a}-{b[23],b}; if(diff<0) diff=-diff; absdiff_le=(diff<=tol); end endfunction
task axi_write; input [13:0] a; input [31:0] d; begin
    while(!s_axi_awready || !s_axi_wready) tick();
    s_axi_awaddr=a; s_axi_wdata=d; s_axi_awvalid=1; s_axi_wvalid=1; tick();
    s_axi_awvalid=0; s_axi_wvalid=0;
    while(!s_axi_bvalid) tick(); tick();
end endtask

task axi_read; input [13:0] a; output [31:0] d; begin
    while(!s_axi_arready) tick();
    s_axi_araddr=a; s_axi_arvalid=1; tick(); s_axi_arvalid=0;
    while(!s_axi_rvalid) tick(); d=s_axi_rdata; tick();
end endtask

task write_ctx; input integer cidx; input [63:0] word; begin
    if(cidx >= CTX_LIMIT) begin $display("FAIL ctx_overflow idx=%0d", cidx); fail_cnt=fail_cnt+1; end
    if(word[59:56] == 4'd9 && word[43:40] == 4'd3) ctx_loop_count=ctx_loop_count+1;
    axi_write(REG_CTX_BASE + (cidx<<3), word[31:0]);
    axi_write(REG_CTX_BASE + (cidx<<3) + 14'd4, word[63:32]);
end endtask

function [63:0] sparse_op_ctx; input [7:0] sparse_op; input is_last; begin sparse_op_ctx=64'd0; sparse_op_ctx[63:60]=4'h1; sparse_op_ctx[59:56]=4'd8; sparse_op_ctx[27:20]=sparse_op; if(is_last) sparse_op_ctx[47:44]=4'd6; end endfunction
function [63:0] reduce_argmax_ctx; input is_last; begin reduce_argmax_ctx=64'd0; reduce_argmax_ctx[63:60]=4'h1; reduce_argmax_ctx[59:56]=4'd4; reduce_argmax_ctx[55:52]=4'd1; reduce_argmax_ctx[51:48]=4'd2; if(is_last) reduce_argmax_ctx[47:44]=4'd6; reduce_argmax_ctx[43:41]=3'd3; reduce_argmax_ctx[34:32]=3'd3; reduce_argmax_ctx[27:24]=4'd4; end endfunction
function [63:0] reduce_argmax_mp_ctx; input is_last; begin reduce_argmax_mp_ctx=reduce_argmax_ctx(is_last); reduce_argmax_mp_ctx[34:32]=3'd0; end endfunction
function [63:0] reduce_x_ctx; input is_last; begin reduce_x_ctx=64'd0; reduce_x_ctx[63:60]=4'h1; reduce_x_ctx[59:56]=4'd4; reduce_x_ctx[55:52]=4'd1; reduce_x_ctx[51:48]=4'd2; if(is_last) reduce_x_ctx[47:44]=4'd6; reduce_x_ctx[43:41]=3'd0; reduce_x_ctx[34:32]=3'd3; reduce_x_ctx[27:24]=4'd4; end endfunction
function [63:0] reduce_x_support_ctx; input is_last; begin reduce_x_support_ctx=reduce_x_ctx(is_last); reduce_x_support_ctx[34:32]=3'd4; end endfunction
function [63:0] stream_topk_ctx; input [7:0] count; input [7:0] path; input exclude_support; input allow_tiny; input is_last; begin
    stream_topk_ctx=64'd0;
    stream_topk_ctx[63:60]=4'h1;
    stream_topk_ctx[59:56]=4'd5;
    if(is_last) stream_topk_ctx[47:44]=4'd6;
    stream_topk_ctx[31]=1'b1;
    stream_topk_ctx[30]=allow_tiny;
    stream_topk_ctx[27:24]=exclude_support ? 4'd2 : (allow_tiny ? 4'd3 : 4'd1);
    stream_topk_ctx[22:20]=path[2:0];
    stream_topk_ctx[15:11]=count[4:0];
end endfunction
function [63:0] post_update_x_topk_ctx; input [7:0] count; input [7:0] path; input is_last; begin
    // Repeated reduce-x always returns a lane, including quantized |x| <= 1.
    // Preserve that exact support-fill behavior in the one-pass stream.
    post_update_x_topk_ctx=stream_topk_ctx(count,path,0,1,is_last);
    post_update_x_topk_ctx[29]=1'b1;
end endfunction
function [63:0] candidate_append_result_ctx; input is_last; begin candidate_append_result_ctx=64'd0; candidate_append_result_ctx[63:60]=4'h1; candidate_append_result_ctx[59:56]=4'd6; if(is_last) candidate_append_result_ctx[47:44]=4'd6; candidate_append_result_ctx[19:16]=4'd1; end endfunction
function [63:0] candidate_append_path_ctx; input [7:0] path; input is_last; begin candidate_append_path_ctx=64'd0; candidate_append_path_ctx[63:60]=4'h1; candidate_append_path_ctx[59:56]=4'd6; if(is_last) candidate_append_path_ctx[47:44]=4'd6; candidate_append_path_ctx[22:20]=path[2:0]; candidate_append_path_ctx[19:16]=4'd9; end endfunction
function [63:0] candidate_meta_depth_ctx; input [7:0] path; input [7:0] depth; input is_last; begin candidate_meta_depth_ctx=64'd0; candidate_meta_depth_ctx[63:60]=4'h1; candidate_meta_depth_ctx[59:56]=4'd6; if(is_last) candidate_meta_depth_ctx[47:44]=4'd6; candidate_meta_depth_ctx[22:20]=path[2:0]; candidate_meta_depth_ctx[19:16]=4'd4; candidate_meta_depth_ctx[15:11]=depth[4:0]; end endfunction
function [63:0] candidate_select_path_ctx; input [7:0] path; input is_last; begin candidate_select_path_ctx=64'd0; candidate_select_path_ctx[63:60]=4'h1; candidate_select_path_ctx[59:56]=4'd6; if(is_last) candidate_select_path_ctx[47:44]=4'd6; candidate_select_path_ctx[22:20]=path[2:0]; candidate_select_path_ctx[19:16]=4'd6; end endfunction
function [63:0] candidate_merge_path_ctx; input [7:0] path; input is_last; begin candidate_merge_path_ctx=64'd0; candidate_merge_path_ctx[63:60]=4'h1; candidate_merge_path_ctx[59:56]=4'd6; if(is_last) candidate_merge_path_ctx[47:44]=4'd6; candidate_merge_path_ctx[22:20]=path[2:0]; candidate_merge_path_ctx[19:16]=4'd2; end endfunction
function [63:0] candidate_copy_to_p0_ctx; input [7:0] path; input is_last; begin candidate_copy_to_p0_ctx=64'd0; candidate_copy_to_p0_ctx[63:60]=4'h1; candidate_copy_to_p0_ctx[59:56]=4'd6; if(is_last) candidate_copy_to_p0_ctx[47:44]=4'd6; candidate_copy_to_p0_ctx[22:20]=path[2:0]; candidate_copy_to_p0_ctx[19:16]=4'd14; end endfunction
function [63:0] dma_ctx; input [7:0] vec_id; input [7:0] addr_dim; input ddr_write; input is_last; begin dma_ctx=64'd0; dma_ctx[63:60]=4'h1; dma_ctx[59:56]=4'd7; if(is_last) dma_ctx[47:44]=4'd6; dma_ctx[43:41]=vec_id[2:0]; dma_ctx[31:28]=addr_dim[3:0]; dma_ctx[0]=ddr_write; end endfunction
function [63:0] ctrl_loop_rel_ctx; input integer rel_off; input [7:0] count; input [7:0] loop_id; input is_last; reg [5:0] rel6; begin rel6=rel_off[5:0]; ctrl_loop_rel_ctx=64'd0; ctrl_loop_rel_ctx[63:60]=4'h1; ctrl_loop_rel_ctx[59:56]=4'd9; if(is_last) ctrl_loop_rel_ctx[47:44]=4'd6; ctrl_loop_rel_ctx[43:40]=4'd3; ctrl_loop_rel_ctx[33:28]=rel6; ctrl_loop_rel_ctx[27:20]=count; ctrl_loop_rel_ctx[19:18]=loop_id[1:0]; end endfunction

task emit_select_append; inout integer pcv; begin write_ctx(pcv, stream_topk_ctx(1,0,1,0,0)); pcv=pcv+1; write_ctx(pcv, sparse_op_ctx(SOP_CORR,0)); pcv=pcv+1; end endtask
task emit_mp_select_append; inout integer pcv; begin write_ctx(pcv, sparse_op_ctx(SOP_CORR,0)); pcv=pcv+1; write_ctx(pcv, reduce_argmax_mp_ctx(0)); pcv=pcv+1; write_ctx(pcv, candidate_append_result_ctx(0)); pcv=pcv+1; end endtask
task emit_reduce_append_loop; inout integer pcv; input [63:0] reduce_word; input [63:0] append_word; input [7:0] count; input [7:0] loop_id; begin write_ctx(pcv, reduce_word); pcv=pcv+1; write_ctx(pcv, append_word); pcv=pcv+1; write_ctx(pcv, ctrl_loop_rel_ctx(-2,count,loop_id,0)); pcv=pcv+1; end endtask
task emit_loop_tail; inout integer pcv; input integer body_start; input [7:0] count; input [7:0] loop_id; integer rel; begin if(count>1) begin rel=body_start-pcv; write_ctx(pcv, ctrl_loop_rel_ctx(rel,count,loop_id,0)); pcv=pcv+1; end end endtask

task build_program; input integer alg_id; input integer k_param; output integer plen; integer body_start; begin
    pc=0; ctx_loop_count=0;
    write_ctx(pc,dma_ctx(VEC_X,0,0,0)); pc=pc+1;
    write_ctx(pc,dma_ctx(VEC_R,1,0,0)); pc=pc+1;
    write_ctx(pc,dma_ctx(VEC_Y,1,0,0)); pc=pc+1;
    body_start=pc;
    case(alg_id)
    ALG_OMP: begin emit_select_append(pc); write_ctx(pc,sparse_op_ctx(SOP_REFINE_SPARSE,0)); pc=pc+1; end
    ALG_COSAMP: begin write_ctx(pc,sparse_op_ctx(SOP_CORR,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(1,0,0)); pc=pc+1; write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_argmax_ctx(0),candidate_append_path_ctx(1,0),(k_param<<1),1); write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; write_ctx(pc,candidate_merge_path_ctx(0,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(1,0,0)); pc=pc+1; write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_support_ctx(0),candidate_append_path_ctx(1,0),k_param,1); write_ctx(pc,candidate_copy_to_p0_ctx(1,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; end
    ALG_IHT: begin write_ctx(pc,sparse_op_ctx(SOP_CORR_UPDATE,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(0,0,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_ctx(0),candidate_append_path_ctx(0,0),k_param,1); write_ctx(pc,sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_RESID,0)); pc=pc+1; end
    ALG_HTP: begin write_ctx(pc,candidate_meta_depth_ctx(1,0,0)); pc=pc+1; write_ctx(pc,post_update_x_topk_ctx(k_param,1,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_CORR_UPDATE,0)); pc=pc+1; write_ctx(pc,candidate_copy_to_p0_ctx(1,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; end
    ALG_SP: begin write_ctx(pc,sparse_op_ctx(SOP_CORR,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(1,0,0)); pc=pc+1; write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_argmax_ctx(0),candidate_append_path_ctx(1,0),k_param,1); write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; write_ctx(pc,candidate_merge_path_ctx(0,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(1,0,0)); pc=pc+1; write_ctx(pc,candidate_select_path_ctx(1,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_support_ctx(0),candidate_append_path_ctx(1,0),k_param,1); write_ctx(pc,candidate_copy_to_p0_ctx(1,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; end
    ALG_5: begin write_ctx(pc,sparse_op_ctx(SOP_CORR_UPDATE,0)); pc=pc+1; write_ctx(pc,reduce_argmax_ctx(0)); pc=pc+1; write_ctx(pc,candidate_append_result_ctx(0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(0,0,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_ctx(0),candidate_append_path_ctx(0,0),k_param,1); write_ctx(pc,sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_RESID,0)); pc=pc+1; end
    ALG_6: begin write_ctx(pc,stream_topk_ctx(2,0,1,0,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_CORR,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_REFINE,0)); pc=pc+1; end
    ALG_MP: begin emit_mp_select_append(pc); write_ctx(pc,sparse_op_ctx(SOP_MP_UPDATE,0)); pc=pc+1; end
    endcase
    emit_loop_tail(pc,body_start,k_param,0);
    write_ctx(pc,dma_ctx(VEC_X,0,1,1)); pc=pc+1;
    plen=pc;
end endtask

task reset_dut; begin rst_n=0; s_axi_awaddr=0; s_axi_awvalid=0; s_axi_wdata=0; s_axi_wstrb=4'hf; s_axi_wvalid=0; s_axi_bready=1; s_axi_araddr=0; s_axi_arvalid=0; s_axi_rready=1; m_axi_arready=1; m_axi_rdata=0; m_axi_rvalid=0; m_axi_rlast=0; m_axi_awready=1; m_axi_wready=1; m_axi_bresp=0; m_axi_bvalid=0; rd_count=0; wr_count=0; repeat(5) tick(); rst_n=1; repeat(5) tick(); end endtask

task init_ddr; input integer m; input integer n; begin
    for(i=0;i<256;i=i+1) begin
        ddr_y[i]=(i<m) ? ksgold_y(i) : 0;
        ddr_x[i]=0;
    end
end endtask

task run_alg_case_iter; input integer alg_id; input integer m; input integer n; input integer k; input integer iter_count; integer plen; begin
    init_ddr(m,n); build_program(alg_id,iter_count,plen);
    $display("SOC_PROGRAM m=%0d n=%0d k=%0d alg=%0d iter=%0d plen=%0d cf_loop_words=%0d", m, n, k, alg_id, iter_count, plen, ctx_loop_count);
    check("program_len_nonzero", plen > 0);
    check("program_len_fits_ctx", plen < CTX_LIMIT);
    if((alg_id==ALG_COSAMP)||(alg_id==ALG_SP)||(alg_id==ALG_IHT)||(alg_id==ALG_HTP)||(alg_id==ALG_5)) check("cf_loop_present", ctx_loop_count > 0);
    axi_write(REG_M_SIZE,m); axi_write(REG_N_SIZE,n); axi_write(REG_K_PARAM,k);
    axi_write(REG_Y_DDR,DDR_Y_BASE); axi_write(REG_X_DDR,DDR_X_BASE); axi_write(REG_SEED,ksgold_case_seed(case_idx)); axi_write(REG_PHI_SCALE,ksgold_case_scale(case_idx));
    axi_write(REG_FLAGS,{28'd0,ksgold_case_phi_kind(case_idx),1'b0,1'b0}); axi_write(REG_MU_SHIFT,32'd3); axi_write(REG_MAX_ITER,iter_count); axi_write(REG_PROG_BASE,0); axi_write(REG_PROG_LEN,plen);
    profile_reset();
    axi_write(REG_CTRL,1);
    done_seen=0; error_seen=0; timeout=0; while(!done_seen && !error_seen && timeout<50000000) begin timeout=timeout+1; tick(); if(irq_done) done_seen=1; if(irq_error) error_seen=1; end
    profile_dump(alg_id);
    axi_read(REG_STATUS,status_rd); axi_read(REG_CYCLE_CNT,cycle_rd); axi_read(REG_PC_DBG,pc_rd);
    nz_count=0;
    mismatch_prints=0;
    for(i=0;i<n;i=i+1) begin
        got=ddr_x[i][23:0];
        if(got != 24'd0) nz_count=nz_count+1;
        if(!absdiff_le(got,ksgold_x_final(case_idx,alg_id,i),KSWEEP_GOLD_TOL)) begin
            if(mismatch_prints < 8) begin
                $display("X_MISM case=%0d alg=%0d iter=%0d i=%0d got=%h exp=%h", case_idx, alg_id, iter_count, i, got, ksgold_x_final(case_idx,alg_id,i));
                mismatch_prints=mismatch_prints+1;
            end
            fail_cnt=fail_cnt+1;
        end
    end
    $display("SOC_ITER_RESULT case=%0d m=%0d n=%0d k=%0d alg=%0d iter=%0d cycles=%0d status=%h pc_dbg=%0d nz=%0d",
             case_idx, m, n, k, alg_id, iter_count, cycle_rd, status_rd, pc_rd, nz_count);
    check("irq_done", done_seen && !error_seen);
    check("pc_in_program_or_done", pc_rd < plen);
    check("nonzero_le_n", nz_count <= n);
    // Each algorithm/case is an independent measurement.  Soft-reset the
    // core boundary so SPM scratch from a streamed HTP run cannot leak into
    // the following algorithm.  The next run reloads data and configmem.
    axi_write(REG_CTRL,2);
    repeat(10) tick();
end endtask

task run_alg_case; input integer alg_id; input integer m; input integer n; input integer k; begin
    if((k==16) && ((alg_id==ALG_COSAMP)||(alg_id==ALG_SP))) begin
        $display("SKIP_CASE case=%0d m=%0d n=%0d k=%0d alg=%0d reason=requires_2K_candidate_support", case_idx, m, n, k, alg_id);
    end else begin
        run_alg_case_iter(alg_id,m,n,k,(alg_id==ALG_6)?((k+1)/2):k);
    end
end endtask

always @* begin
    m_axi_rdata = m_axi_rvalid ? (rd_sel_x ? ddr_x[rd_base_word + rd_count] : ddr_y[rd_base_word + rd_count]) : 32'd0;
    m_axi_rlast = m_axi_rvalid && (rd_count + 1 >= rd_len);
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin m_axi_rvalid<=0; rd_count<=0; rd_base_word<=0; rd_len<=0; rd_sel_x<=0; end
    else begin
        if(m_axi_arvalid && m_axi_arready) begin rd_sel_x <= (m_axi_araddr >= DDR_X_BASE); rd_base_word <= ((m_axi_araddr >= DDR_X_BASE) ? (m_axi_araddr - DDR_X_BASE) : (m_axi_araddr - DDR_Y_BASE)) >> 2; rd_len <= m_axi_arlen + 1; rd_count <= 0; m_axi_rvalid <= 1; end
        else if(m_axi_rvalid && m_axi_rready) begin if(rd_count + 1 >= rd_len) m_axi_rvalid<=0; rd_count <= rd_count + 1; end
    end
end

always @(posedge clk) begin
    if(profile_states && dut.seq_busy) begin
        profile_total_cycles=profile_total_cycles+1;
        profile_ctrl_cycles[dut.u_sparse_kernel_service_engine.u_sparse_loop_controller.state]=
            profile_ctrl_cycles[dut.u_sparse_kernel_service_engine.u_sparse_loop_controller.state]+1;
        profile_uop_cycles[dut.uop_class]=profile_uop_cycles[dut.uop_class]+1;
        if(dut.u_sparse_kernel_service_engine.u_stream_topk.state_q!=0)
            profile_topk_cycles[dut.u_sparse_kernel_service_engine.u_stream_topk.state_q]=
                profile_topk_cycles[dut.u_sparse_kernel_service_engine.u_stream_topk.state_q]+1;
        if(dut.u_sparse_kernel_service_engine.u_support_service.state_q!=0)
            profile_support_cycles[dut.u_sparse_kernel_service_engine.u_support_service.state_q]=
                profile_support_cycles[dut.u_sparse_kernel_service_engine.u_support_service.state_q]+1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin m_axi_bvalid<=0; wr_count<=0; end
    else begin
        if(m_axi_awvalid && m_axi_awready) begin wr_base_word <= (m_axi_awaddr - DDR_X_BASE) >> 2; wr_len <= m_axi_awlen + 1; wr_count <= 0; end
        if(m_axi_wvalid && m_axi_wready) begin ddr_x[wr_base_word + wr_count] <= m_axi_wdata; wr_count <= wr_count + 1; if(m_axi_wlast) m_axi_bvalid <= 1; end
        if(m_axi_bvalid && m_axi_bready) m_axi_bvalid <= 0;
    end
end

initial begin
    clk=0; pass_cnt=0; fail_cnt=0; start_alg=0; end_alg=7; start_case=0; end_case=CASE_COUNT-1; profile_states=0;
`ifdef TB_STATE_PROFILE
    profile_states=1;
`endif
    if($value$plusargs("ALG=%d", start_alg)) end_alg=start_alg;
    if($value$plusargs("START_ALG=%d", start_alg)) begin if(!$value$plusargs("END_ALG=%d", end_alg)) end_alg=start_alg; end
    if($value$plusargs("CASE=%d", start_case)) end_case=start_case;
    if($value$plusargs("START_CASE=%d", start_case)) begin if(!$value$plusargs("END_CASE=%d", end_case)) end_case=start_case; end
    if($value$plusargs("RUN_CASE_ALG=%d", run_case_alg)) begin
        start_case=run_case_alg/8; end_case=start_case;
        start_alg=run_case_alg%8; end_alg=start_alg;
    end
`ifdef TB_ALG
    start_alg=`TB_ALG; end_alg=`TB_ALG;
`endif
`ifdef TB_START_ALG
    start_alg=`TB_START_ALG;
`endif
`ifdef TB_END_ALG
    end_alg=`TB_END_ALG;
`endif
`ifdef TB_CASE
    start_case=`TB_CASE; end_case=`TB_CASE;
`endif
`ifdef TB_START_CASE
    start_case=`TB_START_CASE;
`endif
`ifdef TB_END_CASE
    end_case=`TB_END_CASE;
`endif

`ifdef TB_CASE_0
    start_case=0; end_case=0;
`endif
`ifdef TB_CASE_1
    start_case=1; end_case=1;
`endif
`ifdef TB_CASE_2
    start_case=2; end_case=2;
`endif
`ifdef TB_CASE_3
    start_case=3; end_case=3;
`endif
`ifdef TB_CASE_4
    start_case=4; end_case=4;
`endif
`ifdef TB_CASE_5
    start_case=5; end_case=5;
`endif
`ifdef TB_CASE_6
    start_case=6; end_case=6;
`endif
`ifdef TB_CASE_7
    start_case=7; end_case=7;
`endif
`ifdef TB_ALG_0
    start_alg=0; end_alg=0;
`endif
`ifdef TB_ALG_1
    start_alg=1; end_alg=1;
`endif
`ifdef TB_ALG_2
    start_alg=2; end_alg=2;
`endif
`ifdef TB_ALG_3
    start_alg=3; end_alg=3;
`endif
`ifdef TB_ALG_4
    start_alg=4; end_alg=4;
`endif
`ifdef TB_ALG_5
    start_alg=5; end_alg=5;
`endif
`ifdef TB_ALG_6
    start_alg=6; end_alg=6;
`endif
`ifdef TB_ALG_7
    start_alg=7; end_alg=7;
`endif
    profile_reset();
    reset_dut();
    $display("tb_soc_program_k_sweep CASES: 0=(64,256,16) 1=(64,256,8) 2=(64,256,4) 3=(32,128,8) 4=(32,128,4) 5=(32,128,2) 6=(16,64,4) 7=(16,64,2)");
    for(case_idx=start_case; case_idx<=end_case; case_idx=case_idx+1) begin
        case_m = ksgold_case_m(case_idx);
        case_n = ksgold_case_n(case_idx);
        case_k = ksgold_case_k(case_idx);
        $display("RUN_CASE case=%0d m=%0d n=%0d k=%0d", case_idx, case_m, case_n, case_k);
        for(alg=start_alg; alg<=end_alg; alg=alg+1) run_alg_case(alg, case_m, case_n, case_k);
    end
    $display("tb_run1_k_sweep: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    $finish;
end
endmodule



















