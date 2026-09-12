`include "operator_defs.vh"
`include "memory_defs.vh"
module tb_resident_engine;
    reg  clk = '0;
    reg  rst = '0;
    reg  cancel = '0;
    reg  begin_valid = '0;
    wire  begin_ready;
    reg [7:0] begin_rev = '0;
    reg [8:0] begin_depth = '0;
    reg  begin_verified = '0;
    reg [31:0] begin_generation = '0;
    reg  wr_valid = '0;
    wire  wr_ready;
    reg [7:0] wr_pc = '0;
    reg [5:0] wr_bank = '0;
    reg [255:0] wr_data = '0;
    reg  wr_last = '0;
    wire  image_ready;
    wire  loading;
    wire [3:0] load_fault;
    reg  start_valid = '0;
    wire  start_ready;
    reg [7:0] start_pc = '0;
    reg [31:0] start_limit = '0;
    reg [15:0] start_job = '0;
    reg [7:0] start_fmt = '0;
    reg [2:0] predicates = '0;
    wire  done_valid;
    reg  done_ready = '0;
    wire [3:0] done_fault;
    wire [7:0] pc;
    wire [31:0] retired;
    reg  cfg_valid = '0;
    wire  cfg_ready;
    reg [3:0] cfg_index = '0;
    reg [7:0] cfg_rev = '0;
    reg [`CSR_OP_DESC_W-1:0] cfg_data = '0;
    wire  cfg_fault;
    reg [127:0] link_ready = '0;
    wire  result_valid;
    reg  result_ready = '0;
    wire [863:0] result_data;
    wire [31:0] result_mask;
    wire [351:0] result_index;
    wire [15:0] result_job;
    wire [15:0] result_tag;
    wire [7:0] result_fmt;
    wire  result_last;
    reg [3:0] read_allow = '0;
    reg  b_begin_valid = '0;
    wire  b_begin_ready;
    reg [7:0] b_begin_rows = '0;
    reg [6:0] b_begin_cols = '0;
    reg [127:0] b_begin_key = '0;
    reg [31:0] b_begin_generation = '0;
    reg [15:0] b_begin_job = '0;
    reg [7:0] b_begin_fmt = '0;
    reg  b_fill_valid = '0;
    wire  b_fill_ready;
    reg [6:0] b_fill_slot = '0;
    reg [1:0] b_fill_block = '0;
    reg [31:0] b_fill_mask = '0;
    reg [32*`CSR_PE_C_W-1:0] b_fill_data = '0;
    reg  b_fill_last = '0;
    wire  b_loading;
    wire  b_cache_valid;
    wire [3:0] b_load_fault;
    reg  v_begin_valid = '0;
    wire  v_begin_ready;
    reg [1:0] v_begin_plane = '0;
    reg [12:0] v_begin_length = '0;
    reg [31:0] v_begin_generation = '0;
    reg [15:0] v_begin_job = '0;
    reg [7:0] v_begin_fmt = '0;
    reg  v_fill_valid = '0;
    wire  v_fill_ready;
    reg [6:0] v_fill_block = '0;
    reg [31:0] v_fill_mask = '0;
    reg [32*`CSR_PE_S_W-1:0] v_fill_data = '0;
    reg  v_fill_last = '0;
    wire  v_loading;
    wire [2:0] v_plane_valid;
    wire [3:0] v_load_fault;
    reg  p_begin_valid = '0;
    reg [31:0] p_begin_seed = '0;
    reg [7:0] p_begin_rows = '0;
    reg [10:0] p_begin_cols = '0;
    reg [127:0] p_begin_key = '0;
    reg [31:0] p_begin_generation = '0;
    reg [15:0] p_begin_job = '0;
    reg [7:0] p_begin_fmt = '0;
    wire  p_begin_ready;
    wire  p_valid;
    wire  p_loading;
    wire [3:0] p_fault;
    resident_engine dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .begin_valid(begin_valid),
        .begin_ready(begin_ready),
        .begin_rev(begin_rev),
        .begin_depth(begin_depth),
        .begin_verified(begin_verified),
        .begin_generation(begin_generation),
        .wr_valid(wr_valid),
        .wr_ready(wr_ready),
        .wr_pc(wr_pc),
        .wr_bank(wr_bank),
        .wr_data(wr_data),
        .wr_last(wr_last),
        .image_ready(image_ready),
        .loading(loading),
        .load_fault(load_fault),
        .start_valid(start_valid),
        .start_ready(start_ready),
        .start_pc(start_pc),
        .start_limit(start_limit),
        .start_job(start_job),
        .start_fmt(start_fmt),
        .predicates(predicates),
        .done_valid(done_valid),
        .done_ready(done_ready),
        .done_fault(done_fault),
        .pc(pc),
        .retired(retired),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_index(cfg_index),
        .cfg_rev(cfg_rev),
        .cfg_data(cfg_data),
        .cfg_fault(cfg_fault),
        .link_ready(link_ready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_data(result_data),
        .result_mask(result_mask),
        .result_index(result_index),
        .result_job(result_job),
        .result_tag(result_tag),
        .result_fmt(result_fmt),
        .result_last(result_last),
        .read_allow(read_allow),
        .b_begin_valid(b_begin_valid),
        .b_begin_ready(b_begin_ready),
        .b_begin_rows(b_begin_rows),
        .b_begin_cols(b_begin_cols),
        .b_begin_key(b_begin_key),
        .b_begin_generation(b_begin_generation),
        .b_begin_job(b_begin_job),
        .b_begin_fmt(b_begin_fmt),
        .b_fill_valid(b_fill_valid),
        .b_fill_ready(b_fill_ready),
        .b_fill_slot(b_fill_slot),
        .b_fill_block(b_fill_block),
        .b_fill_mask(b_fill_mask),
        .b_fill_data(b_fill_data),
        .b_fill_last(b_fill_last),
        .b_loading(b_loading),
        .b_cache_valid(b_cache_valid),
        .b_load_fault(b_load_fault),
        .v_begin_valid(v_begin_valid),
        .v_begin_ready(v_begin_ready),
        .v_begin_plane(v_begin_plane),
        .v_begin_length(v_begin_length),
        .v_begin_generation(v_begin_generation),
        .v_begin_job(v_begin_job),
        .v_begin_fmt(v_begin_fmt),
        .v_fill_valid(v_fill_valid),
        .v_fill_ready(v_fill_ready),
        .v_fill_block(v_fill_block),
        .v_fill_mask(v_fill_mask),
        .v_fill_data(v_fill_data),
        .v_fill_last(v_fill_last),
        .v_loading(v_loading),
        .v_plane_valid(v_plane_valid),
        .v_load_fault(v_load_fault),
        .p_begin_valid(p_begin_valid),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_begin_ready(p_begin_ready),
        .p_valid(p_valid),
        .p_loading(p_loading),
        .p_fault(p_fault)
    );

    integer rows, cols, mode, trans, seed, base, abort_kind, force_stall, corrupt;
    integer src, dst, scan, block_id, slot_id, lane, index, reduction, cycle, run_id;
    integer load_pc, load_bank, load_last, accepted, stores, stalled, saved_pc, saved_retired;
    integer clocks, start_clocks, source_stalls, result_stalls, completion_stalls, frame_issues;
    reg [255:0] load_word;
    reg [4095:0] stream_path, desc_path, trace_path;
    reg [`CSR_OP_DESC_W-1:0] descriptor [0:0];
    reg held;
    reg [863:0] held_data;
    reg [31:0] held_mask;
    reg [351:0] held_index;
    task tick;
        begin
            #4; clk = 1; #1; clk = 0; #1;
        end
    endtask
    always @(posedge clk) begin
        clocks=clocks+1;
        if (!rst && !cancel && dut.running) begin
            if ((dut.operands.mat_valid && !dut.operands.mat_ready) ||
                (dut.operands.vec_valid && !dut.operands.vec_ready)) source_stalls=source_stalls+1;
            if (result_valid && !result_ready) result_stalls=result_stalls+1;
            if (force_stall) completion_stalls=completion_stalls+1;
            if (dut.operator.issue && dut.operator.state==4 && !dut.operator.issue_bad) frame_issues=frame_issues+1;
        end
        if (!rst && !cancel && result_valid && result_ready) begin
            $fdisplay(dst, "R %0d %0d %h %h %h", run_id, result_tag, result_mask, result_index, result_data);
            accepted = accepted+1;
        end
        if (!rst && !cancel && held && !force_stall &&
            (!result_valid || result_data !== held_data || result_mask !== held_mask || result_index !== held_index))
            $fatal(1, "candidate response changed under stall");
        held = !rst && !cancel && result_valid && !result_ready;
        held_data = result_data; held_mask = result_mask; held_index = result_index;
    end
    task load;
        begin
            begin_rev=1; begin_depth=256; begin_verified=1; begin_generation=123; begin_valid=1;
            tick; begin_valid=0;
            src=$fopen(stream_path, "r");
            if (!src) $fatal(1,"missing verified stream");
            while (!$feof(src)) begin
                scan=$fscanf(src,"%h %h %h %h",load_pc,load_bank,load_word,load_last);
                if (scan==4) begin
                    wr_valid=1; wr_pc=8'(load_pc); wr_bank=6'(load_bank); wr_data=load_word; wr_last=1'(load_last);
                    if (!wr_ready) $fatal(1,"context loader stalled unexpectedly");
                    tick;
                end else if (!$feof(src)) $fatal(1,"bad loader stream");
            end
            $fclose(src); wr_valid=0;
            if (!image_ready || load_fault != 0) $fatal(1,"image did not publish");
            v_begin_valid=1; v_begin_plane=0; v_begin_length=13'(base+reduction);
            v_begin_generation=2; v_begin_job=7; v_begin_fmt=3;
            start_valid=1; #1;
            if(!v_begin_ready || start_ready) $fatal(1,"held START/load arbitration deadlock");
            tick; start_valid=0; v_begin_valid=0;
            for (block_id=0; block_id<(base+reduction+31)/32; block_id=block_id+1) begin
                v_fill_data='0; v_fill_mask='0;
                for (lane=0; lane<32; lane=lane+1) begin
                    index=block_id*32+lane;
                    if (index<base+reduction) begin
                        v_fill_mask[lane]=1; v_fill_data[lane*27 +: 27]=27'(10000-index*3);
                    end
                end
                v_fill_valid=1; v_fill_block=7'(block_id); v_fill_last=(block_id+1)*32>=base+reduction; tick;
            end
            v_fill_valid=0;
            if (v_plane_valid != 1 || v_load_fault != 0) $fatal(1,"vector did not publish");
            if (mode>=2) begin
                b_begin_valid=1; b_begin_rows=8'(rows); b_begin_cols=7'(cols); b_begin_key=91;
                b_begin_generation=1; b_begin_job=7; b_begin_fmt=3; tick; b_begin_valid=0;
                for (slot_id=0;slot_id<cols;slot_id=slot_id+1) begin
                    for (block_id=0;block_id<(rows+31)/32;block_id=block_id+1) begin
                        b_fill_mask='0; b_fill_data='0;
                        for(lane=0;lane<32;lane=lane+1) begin
                            index=block_id*32+lane;
                            if(index<rows) begin b_fill_mask[lane]=1; b_fill_data[lane*18 +: 18]=18'(index*101-slot_id*53); end
                        end
                        b_fill_valid=1; b_fill_slot=7'(slot_id); b_fill_block=2'(block_id);
                        b_fill_last=slot_id==cols-1 && (block_id+1)*32>=rows; tick;
                    end
                end
                b_fill_valid=0;
                if (!b_cache_valid || b_load_fault != 0) $fatal(1,"B did not publish");
            end else begin
                p_begin_valid=1; p_begin_seed=32'(seed); p_begin_rows=8'(rows); p_begin_cols=11'(cols);
                p_begin_key=91; p_begin_generation=1; p_begin_job=7; p_begin_fmt=3; tick; p_begin_valid=0;
                cycle=0;
                while (!p_valid && cycle<5000) begin tick; cycle=cycle+1; end
                if (!p_valid || p_fault != 0) $fatal(1,"live Phi did not publish");
            end
            cfg_valid=1; cfg_index=0; cfg_rev=1; cfg_data=descriptor[0]; start_valid=1; #1;
            if(!cfg_ready || start_ready) $fatal(1,"held START/config arbitration deadlock");
            repeat(2) tick;
            cfg_valid=0; start_valid=0;
            tick;
        end
    endtask
    task start;
        begin
            start_pc=0; start_limit=60000; start_job=7; start_fmt=3;
            if (!start_ready) $fatal(1,"start not ready after preload");
            start_valid=1; tick; start_valid=0;
        end
    endtask
    task execute;
        begin
            start_clocks=clocks; source_stalls=0; result_stalls=0; completion_stalls=0; frame_issues=0;
            start; cycle=0; stores=0; held=0; stalled=0;
            while (!done_valid && cycle<1000000) begin
                read_allow={cycle%7==0,cycle%5==0,cycle%3==0,cycle%2==0};
                result_ready=cycle%7==0; link_ready='1;
                if (dut.operator.frame_valid && (|dut.operator.frame_store) && stalled==0) begin
                    // The sequencer interface cannot retire: neither can the sink or PE.
                    force_stall=1; force dut.exec_rsp_ready=1'b0;
                    result_ready=1; saved_pc=int'(pc); saved_retired=int'(retired);
                    repeat(4) begin
                        tick;
                        if(result_valid || int'(pc)!=saved_pc || int'(retired)!=saved_retired)
                            $fatal(1,"sink/PC advanced while execution completion blocked");
                    end
                    release dut.exec_rsp_ready; force_stall=0; stalled=1;
                end
                tick; cycle=cycle+1;
            end
            if (!done_valid) $fatal(1,"resident execution timeout pc=%0d state=%0d",pc,dut.operator.state);
            $fdisplay(dst,"D %0d %0d %0d %0d %0d %0d %0d %0d",run_id,done_fault,retired,clocks-start_clocks,source_stalls,result_stalls,completion_stalls,frame_issues);
            repeat(3) tick;
            done_ready=1; tick; done_ready=0;
        end
    endtask
    initial begin
        if (!$value$plusargs("stream=%s",stream_path) || !$value$plusargs("desc=%s",desc_path) ||
            !$value$plusargs("trace=%s",trace_path) || !$value$plusargs("rows=%d",rows) ||
            !$value$plusargs("cols=%d",cols) || !$value$plusargs("mode=%d",mode) ||
            !$value$plusargs("trans=%d",trans) || !$value$plusargs("seed=%d",seed) ||
            !$value$plusargs("base=%d",base) || !$value$plusargs("abort=%d",abort_kind) || !$value$plusargs("corrupt=%d",corrupt)) $fatal(1,"missing arguments");
        dst=$fopen(trace_path,"w"); if(!dst) $fatal(1,"trace open failed");
        $readmemh(desc_path,descriptor); reduction=trans ? rows : cols;
        accepted=0; force_stall=0; held=0; run_id=0; clocks=0; source_stalls=0; result_stalls=0; completion_stalls=0;
        rst=1; tick; rst=0; read_allow='1; link_ready='1; result_ready=1;
        load;
        if(abort_kind!=0) begin
            start; read_allow=4'b0011;
            cycle=0;
            while(dut.operator.state!=2 && cycle<1000) begin tick; cycle=cycle+1; end
            if(cycle==1000) $fatal(1,"abort did not reach pending reader");
            if(abort_kind==1) cancel=1; else rst=1;
            tick; cancel=0; rst=0; read_allow='1;
            if(image_ready || p_valid || b_cache_valid || v_plane_valid!=0 || result_valid) $fatal(1,"abort retained publication");
            load;
        end
        if(corrupt==1) force dut.operands.c_rsp_tag=16'hffff;
        if(corrupt==2) force dut.operands.b_rsp_tag=16'hffff;
        execute;
        run_id=1; execute; // no image, descriptor, or operand reload between starts
        $fclose(dst); $display("PASS accepted=%0d",accepted); $finish;
    end
    initial begin #30000000; $fatal(1,"watchdog"); end
endmodule
