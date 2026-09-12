module tb_support_builder;
reg  clk;
reg  rst;
reg  cancel;
reg  req_valid;
wire  req_ready;
reg [7:0] req_rows;
reg [10:0] req_cols;
reg [6:0] req_count;
reg [959:0] req_support;
reg [17:0] req_scale;
reg [127:0] req_phi_key;
reg [127:0] req_b_key;
reg [31:0] req_phi_generation;
reg [31:0] req_b_generation;
reg [15:0] req_job;
reg [15:0] req_tag;
reg [7:0] req_fmt;
wire  phi_valid;
wire [127:0] phi_key;
wire [31:0] phi_generation;
reg [7:0] phi_rows;
reg [10:0] phi_cols;
wire  phi_invalidate;
wire  phi_rd_valid;
wire  phi_rd_ready;
wire [7:0] phi_rd_bank_mask;
wire [71:0] phi_rd_addresses;
wire [31:0] phi_rd_generation;
wire [15:0] phi_rd_tag;
wire  phi_rsp_valid;
wire  phi_rsp_ready;
wire [255:0] phi_rsp_signs;
wire [255:0] phi_rsp_masks;
wire [7:0] phi_rsp_bank_mask;
wire [31:0] phi_rsp_generation;
wire [15:0] phi_rsp_tag;
wire [3:0] phi_rsp_fault;
wire  b_cancel;
wire  b_begin_valid;
wire  b_begin_ready;
wire [7:0] b_begin_rows;
wire [6:0] b_begin_cols;
wire [127:0] b_begin_key;
wire [31:0] b_begin_generation;
wire [15:0] b_begin_job;
wire [7:0] b_begin_fmt;
wire  b_fill_valid;
wire  b_fill_ready;
wire [6:0] b_fill_slot;
wire [1:0] b_fill_block;
wire [31:0] b_fill_mask;
wire [575:0] b_fill_data;
wire  b_fill_last;
wire  b_loading;
wire  b_valid;
wire [3:0] b_load_fault;
wire  rsp_valid;
reg  rsp_ready;
wire [3:0] rsp_fault;
wire [15:0] rsp_job;
wire [15:0] rsp_tag;
wire [7:0] rsp_fmt;
wire [31:0] rsp_cycles;
wire [15:0] rsp_words;
support_builder dut (.*);
reg [31:0] seed;
reg start, fill_gate, rd_gate, rsp_gate, begin_gate, data_gate;
reg [7:0] inject;
wire start_ready, gen_busy, gen_valid, gen_ready, gen_last, gen_done;
wire [31:0] gen_signs, gen_mask, gen_generation;
wire [9:0] gen_column;
wire [1:0] gen_block;
wire [15:0] gen_job, gen_tag;
wire [7:0] gen_fmt;
wire [3:0] gen_fault, cache_fault;
wire cache_begin_ready, cache_fill_ready, cache_filling, cache_published;
wire raw_rd_ready, raw_rsp_valid;
wire [255:0] raw_signs, raw_masks;
wire [7:0] raw_bank_mask;
wire [31:0] raw_generation;
wire [15:0] raw_tag;
wire [3:0] raw_fault;
wire raw_b_begin_ready, raw_b_fill_ready;
wire [3:0] raw_b_fault;
wire [15:0] unused_job;
wire [7:0] unused_fmt;
reg b_rd_valid, b_rsp_ready;
wire b_rd_ready, b_rsp_valid;
reg [31:0] b_rd_mask;
reg [287:0] b_rd_addr;
wire [575:0] b_rsp_data;
wire [31:0] b_rsp_mask, b_rsp_generation;
wire [15:0] b_rsp_job, b_rsp_tag;
wire [7:0] b_rsp_fmt;
wire [3:0] b_rsp_fault;
assign gen_ready=cache_fill_ready && fill_gate;
assign phi_rd_ready=raw_rd_ready && rd_gate;
assign phi_rsp_valid=raw_rsp_valid && rsp_gate;
assign phi_rsp_signs=raw_signs;
assign phi_rsp_masks=raw_masks ^ (inject[2] ? 256'b1 : 256'b0);
assign phi_rsp_bank_mask=raw_bank_mask ^ (inject[6] ? 8'b1 : 8'b0);
assign phi_rsp_generation=raw_generation ^ (inject[1] ? 32'b1 : 32'b0);
assign phi_rsp_tag=raw_tag ^ (inject[0] ? 16'b1 : 16'b0);
assign phi_rsp_fault=inject[3] ? 4'd3 : raw_fault;
assign b_begin_ready=raw_b_begin_ready && begin_gate;
assign b_fill_ready=raw_b_fill_ready && data_gate;
assign b_load_fault=inject[4] ? 4'd4 : raw_b_fault;
phi_sign_generator gen (
.clk(clk),.rst(rst),.cancel(cancel||phi_invalidate),.start_valid(start&&cache_begin_ready),.start_ready(start_ready),
.start_family(8'd1),.start_revision(8'd2),.start_seed(seed),.start_rows(phi_rows),.start_columns(phi_cols),
.start_job_tag(16'd9),.start_op_tag(16'd10),.start_format_tag(8'd11),.start_generation(32'd12),
.busy(gen_busy),.out_valid(gen_valid),.out_ready(gen_ready),.out_signs(gen_signs),.out_mask(gen_mask),
.out_column(gen_column),.out_row_block(gen_block),.out_job_tag(gen_job),.out_op_tag(gen_tag),
.out_format_tag(gen_fmt),.out_generation(gen_generation),.out_last(gen_last),.done(gen_done),.fault_code(gen_fault));
phi_sign_cache phi (
.clk(clk),.rst(rst),.invalidate(cancel||phi_invalidate),.begin_valid(start&&start_ready),.begin_ready(cache_begin_ready),
.begin_rows(phi_rows),.begin_columns(phi_cols),.begin_job_tag(16'd9),.begin_op_tag(16'd10),.begin_format_tag(8'd11),
.begin_generation(32'd12),.begin_key(128'd123),.filling(cache_filling),
.fill_valid(gen_valid&&fill_gate),.fill_ready(cache_fill_ready),.fill_signs(gen_signs),.fill_mask(gen_mask),
.fill_column(gen_column),.fill_row_block(gen_block),.fill_job_tag(gen_job),.fill_op_tag(gen_tag),
.fill_format_tag(gen_fmt),.fill_generation(gen_generation),.fill_last(gen_last),
.cache_valid(phi_valid),.published(cache_published),.cache_key(phi_key),.cache_generation(phi_generation),.fault_code(cache_fault),
.rd_valid(phi_rd_valid&&rd_gate),.rd_ready(raw_rd_ready),.rd_bank_mask(phi_rd_bank_mask),.rd_addresses(phi_rd_addresses),
.rd_generation(phi_rd_generation),.rd_tag(phi_rd_tag),.rsp_valid(raw_rsp_valid),.rsp_ready(phi_rsp_ready&&rsp_gate),
.rsp_signs(raw_signs),.rsp_masks(raw_masks),.rsp_bank_mask(raw_bank_mask),.rsp_generation(raw_generation),.rsp_tag(raw_tag),.rsp_fault(raw_fault));
support_matrix_cache b (
.clk(clk),.rst(rst),.cancel(b_cancel),.begin_valid(b_begin_valid&&begin_gate),.begin_ready(raw_b_begin_ready),
.begin_rows(b_begin_rows),.begin_cols(b_begin_cols),.begin_key(b_begin_key),.begin_generation(b_begin_generation),
.begin_job(b_begin_job),.begin_fmt(b_begin_fmt),.fill_valid(b_fill_valid&&data_gate),.fill_ready(raw_b_fill_ready),
.fill_slot(b_fill_slot),.fill_block(b_fill_block),.fill_mask(b_fill_mask ^ ((inject[5] && rsp_words==1) ? 32'b1 : 32'b0)),.fill_data(b_fill_data),.fill_last(b_fill_last),
.loading(b_loading),.cache_valid(b_valid),.load_fault(raw_b_fault),
.rd_valid(b_rd_valid),.rd_ready(b_rd_ready),.rd_mask(b_rd_mask),.rd_addr(b_rd_addr),.rd_key(128'd456),
.rd_generation(32'd34),.rd_job(16'd21),.rd_tag(16'd55),.rd_fmt(8'd22),
.rsp_valid(b_rsp_valid),.rsp_ready(b_rsp_ready),.rsp_data(b_rsp_data),.rsp_mask(b_rsp_mask),
.rsp_generation(b_rsp_generation),.rsp_job(b_rsp_job),.rsp_tag(b_rsp_tag),.rsp_fmt(b_rsp_fmt),.rsp_fault(b_rsp_fault));
integer cycles, src, rc, cmd, row_idx, slot_idx, bank_idx, addr_idx, expected, expected_fault, elapsed, nreads, nfill, abort_at, reset_kind, fill_cycles;
reg [4095:0] path;
reg [959:0] saved_support;
reg [103:0] held;
task tick;
begin
    #4; clk=1; #1; cycles=cycles+1; #4; clk=0;
end
endtask
task stalls;
begin
    rd_gate=inject[7] || (cycles%4!=0); rsp_gate=inject[7] || (cycles%5!=0); begin_gate=inject[7] || (cycles%3!=0); data_gate=inject[7] || (cycles%7!=0);
end
endtask
initial begin
clk=0; rst=1; cancel=0; req_valid=0; rsp_ready=0; start=0; seed=1; fill_gate=1; rd_gate=1; rsp_gate=1; begin_gate=1; data_gate=1;
inject=0; phi_rows=1; phi_cols=1; req_rows=1; req_cols=1; req_count=1; req_support=0; req_scale=1;
req_phi_key=123; req_b_key=456; req_phi_generation=12; req_b_generation=34; req_job=21; req_tag=23; req_fmt=22;
b_rd_valid=0; b_rsp_ready=0; b_rd_mask=0; b_rd_addr=0; cycles=0;
tick(); rst=0;
if (!$value$plusargs("src=%s",path)) $fatal(1,"missing input");
src=$fopen(path,"r"); if (!src) $fatal(1,"cannot open input");
while (!$feof(src)) begin
rc=$fscanf(src,"%d",cmd);
if (rc==1) begin
case(cmd)
0: begin
    rc=$fscanf(src,"%d %d %h",phi_rows,phi_cols,seed); if(rc!=3) $fatal(1,"bad phi command");
    #1; if(!start_ready||!cache_begin_ready) $fatal(1,"phi owner busy");
    start=1; tick(); start=0; fill_cycles=0;
    while(!phi_valid) begin fill_gate=(cycles%4!=0); tick(); fill_cycles=fill_cycles+1; if(fill_cycles>10000) $fatal(1,"phi timeout"); end
    if(gen_fault||cache_fault) $fatal(1,"phi fill fault");
    $display("PHI rows=%0d cols=%0d cycles=%0d",phi_rows,phi_cols,fill_cycles);
end
1: begin
    rc=$fscanf(src,"%d %d %d %h %h %h %h %d %d %d",req_rows,req_cols,req_count,req_support,req_scale,req_phi_key,req_phi_generation,inject,expected_fault,abort_at);
    if(rc!=10) $fatal(1,"bad build command");
    reset_kind=abort_at<0; if(reset_kind) abort_at=-abort_at;
    saved_support=req_support;
    req_valid=1; #1; if(!req_ready) $fatal(1,"builder not ready"); tick(); req_valid=0;
    #1; if(b_valid) $fatal(1,"old B remains valid on rebuild acceptance");
    req_support=~req_support; req_scale=0; req_b_key=999; req_b_generation=999; req_job=999; req_tag=999; req_fmt=99;
    elapsed=0; nreads=0; nfill=0;
    while(!rsp_valid && (abort_at==0 || elapsed<abort_at)) begin
        stalls(); #1;
        if(phi_rd_valid&&phi_rd_ready) nreads=nreads+1;
        if(b_fill_valid&&b_fill_ready) nfill=nfill+1;
        tick(); elapsed=elapsed+1;
        if(elapsed>5000) $fatal(1,"builder timeout");
    end
    if(abort_at!=0) begin
        if(reset_kind) rst=1; else cancel=1;
        rsp_ready=1; tick(); rst=0; cancel=0; rsp_ready=0;
        if(rsp_valid||b_valid||phi_valid) $fatal(1,"cancel/reset leaked state");
        $display("ABORT cycles=%0d reset=%0d",elapsed,reset_kind);
    end else begin
        if(rsp_fault!=expected_fault) $fatal(1,"fault expected=%0d got=%0d",expected_fault,rsp_fault);
        if(rsp_cycles!=elapsed) $fatal(1,"cycle accounting");
        if(inject[7] && expected_fault==0 && rsp_cycles!=req_count+2+4*nfill) $fatal(1,"unstalled schedule");
        if(rsp_job!=21||rsp_tag!=23||rsp_fmt!=22) $fatal(1,"completion identity");
        if((expected_fault==0)!=b_valid) $fatal(1,"publication state");
        if(expected_fault==0 && (rsp_words!=nfill || nreads!=nfill || nfill!=req_count*((req_rows+31)/32))) $fatal(1,"word accounting");
        if(expected_fault!=0 && b_loading) $fatal(1,"failure left B loading");
        held={rsp_fault,rsp_job,rsp_tag,rsp_fmt,rsp_cycles,rsp_words,12'b0};
        repeat(6) begin tick(); if(held!={rsp_fault,rsp_job,rsp_tag,rsp_fmt,rsp_cycles,rsp_words,12'b0}||!rsp_valid) $fatal(1,"response stall changed payload"); end
        $display("BUILD fault=%0d words=%0d cycles=%0d reads=%0d fills=%0d",rsp_fault,rsp_words,rsp_cycles,nreads,nfill);
        rsp_ready=1; tick(); rsp_ready=0;
    end
    inject=0; req_b_key=456; req_b_generation=34; req_job=21; req_tag=23; req_fmt=22;
end
2: begin
    rc=$fscanf(src,"%d %d %d",row_idx,slot_idx,expected); if(rc!=3) $fatal(1,"bad coordinate");
    bank_idx=(row_idx+slot_idx)%32; addr_idx=row_idx*((req_count+31)/32)+slot_idx/32;
    b_rd_mask=32'b1<<bank_idx; b_rd_addr=0; b_rd_addr[bank_idx*9 +: 9]=9'(addr_idx);
    b_rd_valid=1; #1; if(!b_rd_ready) $fatal(1,"B read not ready"); tick(); b_rd_valid=0;
    if(!b_rsp_valid||b_rsp_fault||b_rsp_mask!=b_rd_mask||b_rsp_generation!=34||b_rsp_job!=21||b_rsp_tag!=55||b_rsp_fmt!=22) $fatal(1,"B response metadata");
    if($signed(b_rsp_data[bank_idx*18 +: 18])!=expected) $fatal(1,"B mismatch row=%0d slot=%0d expected=%0d got=%0d",row_idx,slot_idx,expected,$signed(b_rsp_data[bank_idx*18 +: 18]));
    tick(); if(!b_rsp_valid) $fatal(1,"B response stall"); b_rsp_ready=1; tick(); b_rsp_ready=0;
end
3: begin
    // Corrupt the bound descriptor during an outstanding response; explicit Phi flush must drain it.
    req_rows=phi_rows; req_cols=phi_cols; req_count=1; req_support=0; req_scale=1; req_phi_key=123; req_phi_generation=12;
    req_valid=1; tick(); req_valid=0; rsp_gate=0;
    while(!raw_rsp_valid) begin rd_gate=1; begin_gate=1; tick(); end
    phi_rows=phi_rows+1; tick(); tick();
    if(!rsp_valid||rsp_fault!=3||b_valid||raw_rsp_valid||phi_valid) $fatal(1,"identity loss cleanup failed");
    rsp_ready=1; tick(); rsp_ready=0; rsp_gate=1;
end
default: $fatal(1,"unknown command");
endcase
end else if(!$feof(src)) $fatal(1,"bad command");
end
$display("PASS cycles=%0d",cycles); $finish;
end
initial begin #20000000; $fatal(1,"timeout"); end
endmodule

