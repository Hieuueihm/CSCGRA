`include "memory_defs.vh"
`include "phi_interface.vh"
`include "builder_defs.vh"
module tb_operator_memory;
    reg  clk = '0;
    reg  rst = '0;
    reg  cancel = '0;
    reg  compute_active = '0;
    reg  p_begin_valid = '0;
    reg [31:0] p_begin_seed = '0;
    reg [7:0] p_begin_rows = '0;
    reg [10:0] p_begin_cols = '0;
    reg [127:0] p_begin_key = '0;
    reg [31:0] p_begin_generation = '0;
    reg [15:0] p_begin_job = '0;
    reg [7:0] p_begin_fmt = '0;
    wire  p_begin_ready;
    wire  p_loading;
    wire [3:0] p_fault;
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
    wire [3:0] b_load_fault;
    reg  build_req_valid = '0;
    wire  build_req_ready;
    reg [7:0] build_req_rows = '0;
    reg [10:0] build_req_cols = '0;
    reg [6:0] build_req_count = '0;
    reg [959:0] build_req_support = '0;
    reg [17:0] build_req_scale = '0;
    reg [127:0] build_req_phi_key = '0;
    reg [127:0] build_req_b_key = '0;
    reg [31:0] build_req_phi_generation = '0;
    reg [31:0] build_req_b_generation = '0;
    reg [15:0] build_req_job = '0;
    reg [15:0] build_req_tag = '0;
    reg [7:0] build_req_fmt = '0;
    wire  build_rsp_valid;
    reg  build_rsp_ready = '0;
    wire [3:0] build_rsp_fault;
    wire [15:0] build_rsp_job;
    wire [15:0] build_rsp_tag;
    wire [7:0] build_rsp_fmt;
    wire [31:0] build_rsp_cycles;
    wire [15:0] build_rsp_words;
    wire  build_busy;
    wire  p_valid;
    wire [7:0] p_rows;
    wire [10:0] p_cols;
    wire [127:0] p_key;
    wire [31:0] p_generation;
    wire [15:0] p_job;
    wire [7:0] p_fmt;
    wire  b_valid;
    wire [7:0] b_rows;
    wire [6:0] b_cols;
    wire [127:0] b_key;
    wire [31:0] b_generation;
    wire [15:0] b_job;
    wire [7:0] b_fmt;
    reg  mat_valid = '0;
    wire  mat_ready;
    reg [31:0] mat_mask = '0;
    reg [287:0] mat_addr = '0;
    reg [127:0] mat_key = '0;
    reg [31:0] mat_generation = '0;
    wire  mat_rsp_valid;
    reg  mat_rsp_ready = '0;
    wire [575:0] mat_rsp_data;
    wire [255:0] mat_rsp_masks;
    wire [31:0] mat_rsp_mask;
    wire [31:0] mat_rsp_generation;
    wire [15:0] mat_rsp_job;
    wire [15:0] mat_rsp_tag;
    wire [7:0] mat_rsp_fmt;
    wire [3:0] mat_rsp_fault;
    reg  mat_dense = '0;
    reg [15:0] mem_job = '0;
    reg [15:0] mem_tag = '0;
    reg [7:0] mem_fmt = '0;
    operator_memory dut (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .compute_active(compute_active),
        .p_begin_valid(p_begin_valid),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_begin_ready(p_begin_ready),
        .p_loading(p_loading),
        .p_fault(p_fault),
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
        .b_load_fault(b_load_fault),
        .build_req_valid(build_req_valid),
        .build_req_ready(build_req_ready),
        .build_req_rows(build_req_rows),
        .build_req_cols(build_req_cols),
        .build_req_count(build_req_count),
        .build_req_support(build_req_support),
        .build_req_scale(build_req_scale),
        .build_req_phi_key(build_req_phi_key),
        .build_req_b_key(build_req_b_key),
        .build_req_phi_generation(build_req_phi_generation),
        .build_req_b_generation(build_req_b_generation),
        .build_req_job(build_req_job),
        .build_req_tag(build_req_tag),
        .build_req_fmt(build_req_fmt),
        .build_rsp_valid(build_rsp_valid),
        .build_rsp_ready(build_rsp_ready),
        .build_rsp_fault(build_rsp_fault),
        .build_rsp_job(build_rsp_job),
        .build_rsp_tag(build_rsp_tag),
        .build_rsp_fmt(build_rsp_fmt),
        .build_rsp_cycles(build_rsp_cycles),
        .build_rsp_words(build_rsp_words),
        .build_busy(build_busy),
        .p_valid(p_valid),
        .p_rows(p_rows),
        .p_cols(p_cols),
        .p_key(p_key),
        .p_generation(p_generation),
        .p_job(p_job),
        .p_fmt(p_fmt),
        .b_valid(b_valid),
        .b_rows(b_rows),
        .b_cols(b_cols),
        .b_key(b_key),
        .b_generation(b_generation),
        .b_job(b_job),
        .b_fmt(b_fmt),
        .mat_valid(mat_valid),
        .mat_ready(mat_ready),
        .mat_mask(mat_mask),
        .mat_addr(mat_addr),
        .mat_key(mat_key),
        .mat_generation(mat_generation),
        .mat_rsp_valid(mat_rsp_valid),
        .mat_rsp_ready(mat_rsp_ready),
        .mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks),
        .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation),
        .mat_rsp_job(mat_rsp_job),
        .mat_rsp_tag(mat_rsp_tag),
        .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault),
        .mat_dense(mat_dense),
        .mem_job(mem_job),
        .mem_tag(mem_tag),
        .mem_fmt(mem_fmt)
    );

    integer rows, cols, count, seed, scale, scenario, cycle, bank, slot, block_id, row_id, mode_id, direction, out_idx, red_idx, step_idx;
    integer source, trace, checked, reads, accepted_builds, clocks, output_count, reduction_count, saved_cycles;
    reg hold_identity;
    reg [4095:0] trace_path;
    reg [1:0] plan_mode;
    reg plan_trans;
    reg [10:0] plan_out, plan_red;
    reg [2:0] plan_step;
    wire [31:0] plan_mask, unused_vec_mask;
    wire [287:0] plan_addr;
    wire [223:0] unused_vec_addr;
    wire [19:0] unused_vec_banks;
    wire [3:0] unused_vec_lanes, plan_fault;
    reg [575:0] held_data;
    reg [31:0] held_mask;
    reg [15:0] held_tag;
    operand_plan planner(.mode(plan_mode),.trans(plan_trans),.rows(8'(rows)),.cols(11'(count)),
        .out_idx(plan_out),.red_idx(plan_red),.step(plan_step),.vec_base(12'b0),.mat_mask(plan_mask),
        .mat_addr(plan_addr),.vec_mask(unused_vec_mask),.vec_addr(unused_vec_addr),.vec_banks(unused_vec_banks),
        .vec_lanes(unused_vec_lanes),.fault(plan_fault));
    task tick; begin #4;clk=1;#1;clk=0;#1;clocks=clocks+1; end endtask
    task wait_idle; begin cycle=0; while(dut.owner!=0 && cycle<10000) begin tick;cycle=cycle+1;end if(cycle==10000)$fatal(1,"owner stuck"); end endtask
    task phi_load;
        begin
            p_begin_seed=32'(seed);p_begin_rows=8'(rows);p_begin_cols=11'(cols);
            p_begin_key=91;p_begin_generation=1;p_begin_job=7;p_begin_fmt=3;p_begin_valid=1;
            #1;if(!p_begin_ready)$fatal(1,"Phi begin blocked");tick;p_begin_valid=0;
            wait_idle;
            if(!p_valid || p_rows!=rows || p_cols!=cols || p_job!=7 || p_fmt!=3 || p_key!=91 || p_generation!=1 || p_fault!=0)
                $fatal(1,"Phi descriptor not published");
        end
    endtask
    task build_setup;
        begin
            build_req_rows=8'(rows);build_req_cols=11'(cols);build_req_count=7'(count);build_req_scale=18'(scale);
            build_req_phi_key=91;build_req_phi_generation=1;build_req_b_key=92;build_req_b_generation=2;
            build_req_job=7;build_req_tag=55;build_req_fmt=3;build_req_support='0;
            for(slot=0;slot<count;slot=slot+1)build_req_support[slot*10+:10]=10'(cols-1-slot);
        end
    endtask
    task phi_read;
        begin
            mat_dense=0;mat_mask=1;mat_addr=0;mat_key=91;mat_generation=1;mem_job=7;mem_tag=123;mem_fmt=3;mat_valid=1;
            #1;if(!mat_ready)$fatal(1,"Phi kernel read blocked");tick;mat_valid=0;
            cycle=0;while(!mat_rsp_valid && cycle<100)begin tick;cycle=cycle+1;end
            if(!mat_rsp_valid || mat_rsp_fault!=0 || mat_rsp_tag!=123 || mat_rsp_job!=7 || mat_rsp_fmt!=3)$fatal(1,"Phi read failed");
        end
    endtask
    task finish_build;
        begin
            cycle=0;while(!build_rsp_valid && cycle<10000)begin
                // Pause both sides of the real source-response handshake, preserving ownership.
                if(dut.builder.state==5 && !hold_identity)begin
                    force dut.builder.phi_rsp_valid=1'b0;force dut.phi.rsp_ready=1'b0;
                    repeat(2)tick;
                    release dut.builder.phi_rsp_valid;release dut.phi.rsp_ready;
                end
                tick;cycle=cycle+1;
                if(mat_ready || p_begin_ready || b_begin_ready || build_req_ready)$fatal(1,"build lost exclusivity");
            end
            if(!build_rsp_valid)$fatal(1,"build timeout");
            saved_cycles=build_rsp_cycles;
            mat_valid=1;mat_dense=1;p_begin_valid=1;b_begin_valid=1;build_req_valid=1;
            repeat(4)begin
                #1;if(mat_ready || p_begin_ready || b_begin_ready || build_req_ready || !build_busy)$fatal(1,"held completion released owner");
                tick;if(build_rsp_cycles!=saved_cycles || build_rsp_tag!=55 || build_rsp_job!=(scenario==1 ? 8 : 7) || build_rsp_fmt!=(scenario==8 ? 4 : 3))$fatal(1,"completion changed");
            end
            mat_valid=0;p_begin_valid=0;b_begin_valid=0;build_req_valid=0;
            $fdisplay(trace,"B %0d %0d %0d %0d",build_rsp_fault,build_rsp_words,build_rsp_cycles,b_valid);
            build_rsp_ready=1;tick;build_rsp_ready=0;
        end
    endtask
    task read_b;
        begin
            compute_active=1;
            for(mode_id=2;mode_id<4;mode_id=mode_id+1)begin
                for(direction=0;direction<2;direction=direction+1)begin
                    output_count=direction ? count : rows;reduction_count=direction ? rows : count;
                    for(out_idx=0;out_idx<output_count;out_idx=out_idx+(mode_id==3 ? 8 : 32))begin
                        for(red_idx=0;red_idx<reduction_count;red_idx=red_idx+(mode_id==3 ? 32 : 1))begin
                            for(step_idx=0;step_idx<(mode_id==3 ? 8 : 1);step_idx=step_idx+1)begin
                                plan_mode=2'(mode_id);plan_trans=1'(direction);plan_out=11'(out_idx);plan_red=11'(red_idx);plan_step=3'(step_idx);#1;
                                if(plan_fault!=0)$fatal(1,"planner rejected legal frame");
                                mat_dense=1;mat_mask=plan_mask;mat_addr=plan_addr;mat_key=92;mat_generation=2;mem_job=7;mem_tag=16'(reads);mem_fmt=3;
                                mat_valid=1;#1;if(!mat_ready)$fatal(1,"B kernel blocked");tick;mat_valid=0;
                                cycle=0;while(!mat_rsp_valid && cycle<50)begin tick;cycle=cycle+1;end
                                if(!mat_rsp_valid || mat_rsp_fault!=0 || mat_rsp_mask!=plan_mask || mat_rsp_tag!=16'(reads))$fatal(1,"B response failed");
                                held_data=mat_rsp_data;held_mask=mat_rsp_mask;held_tag=mat_rsp_tag;
                                mat_dense=0;mem_tag=16'hffff;mat_key=999;mat_generation=99;
                                build_req_valid=1;p_begin_valid=1;b_begin_valid=1;
                                repeat(2)begin
                                    tick;if(mat_rsp_data!==held_data || mat_rsp_mask!==held_mask || mat_rsp_tag!==held_tag ||
                                        build_req_ready || p_begin_ready || b_begin_ready)$fatal(1,"read stall/compute lock failed");
                                end
                                build_req_valid=0;p_begin_valid=0;b_begin_valid=0;
                                $fdisplay(trace,"R %0d %0d %0d %0d %0d %h %h %h",mode_id,direction,out_idx,red_idx,step_idx,mat_rsp_mask,mat_addr,mat_rsp_data);
                                reads=reads+1;mat_rsp_ready=1;tick;mat_rsp_ready=0;
                            end
                        end
                    end
                end
            end
            compute_active=0;
        end
    endtask
    task dense_load;
        begin
            b_begin_rows=8'(rows);b_begin_cols=7'(count);b_begin_key=92;b_begin_generation=2;b_begin_job=7;b_begin_fmt=3;b_begin_valid=1;
            #1;if(!b_begin_ready)$fatal(1,"dense host begin blocked");tick;b_begin_valid=0;
            for(slot=0;slot<count;slot=slot+1)for(block_id=0;block_id<(rows+31)/32;block_id=block_id+1)begin
                b_fill_slot=7'(slot);b_fill_block=2'(block_id);b_fill_mask='0;b_fill_data='0;
                for(bank=0;bank<32;bank=bank+1)begin row_id=block_id*32+bank;if(row_id<rows)begin
                    b_fill_mask[bank]=1;b_fill_data[bank*18+:18]=18'(row_id*101-slot*53);end end
                b_fill_last=slot==count-1 && (block_id+1)*32>=rows;b_fill_valid=1;tick;
            end
            b_fill_valid=0;wait_idle;if(!b_valid || b_load_fault!=0)$fatal(1,"host dense fill failed");
        end
    endtask
    initial begin
        if(!$value$plusargs("rows=%d",rows)||!$value$plusargs("cols=%d",cols)||!$value$plusargs("count=%d",count)||
            !$value$plusargs("seed=%d",seed)||!$value$plusargs("scale=%d",scale)||!$value$plusargs("scenario=%d",scenario)||
            !$value$plusargs("trace=%s",trace_path))$fatal(1,"missing args");
        trace=$fopen(trace_path,"w");if(!trace)$fatal(1,"trace open");clocks=0;reads=0;hold_identity=0;
        rst=1;tick;rst=0;phi_load;build_setup;
        if(scenario==7)begin dense_load;read_b;end
        else begin
            // Existing read response must retire before builder can invalidate B.
            phi_read;mat_dense=1;mem_tag=16'hffff;mat_key=999;build_req_valid=1;repeat(3)begin tick;if(build_req_ready || build_busy || mat_rsp_tag!=123 || mat_rsp_fault!=0)$fatal(1,"build stole pending read");end
            mat_rsp_ready=1;tick;mat_rsp_ready=0;build_req_valid=0;
            compute_active=1;build_req_valid=1;p_begin_valid=1;b_begin_valid=1;
            repeat(2)begin tick;if(build_req_ready || p_begin_ready || b_begin_ready)$fatal(1,"compute did not lock fills");end
            compute_active=0;p_begin_valid=0;b_begin_valid=0;build_req_valid=0;
            if(scenario==1)build_req_job=8;
            if(scenario==2)build_req_rows=8'(rows-1);
            if(scenario==3)build_req_support[19:10]=build_req_support[9:0];
            if(scenario==8)build_req_fmt=4;
            if(scenario==9)build_req_phi_key=93;
            if(scenario==10)build_req_phi_generation=9;
            if(scenario==11)build_req_support[9:0]=10'(cols);
            build_req_valid=1;#1;if(!build_req_ready)$fatal(1,"build not ready after drain");tick;build_req_valid=0;
            // Mutation must not change accepted descriptor or its identity.
            build_req_support='1;build_req_phi_key=999;build_req_scale=0;
            if((scenario>=4 && scenario<=6) || scenario==12)begin
                cycle=0;while(!dut.builder_phi_rd_valid && cycle<2000)begin tick;cycle=cycle+1;end
                if(cycle==2000)$fatal(1,"no pending builder read");tick;
                if(scenario==12)begin
                    hold_identity=1;force dut.cache_cache_valid=1'b0;
                    finish_build;release dut.cache_cache_valid;hold_identity=0;
                    if(p_valid || b_valid)$fatal(1,"pending identity loss did not invalidate owners");
                    phi_load;build_setup;build_req_valid=1;tick;build_req_valid=0;finish_build;read_b;
                end else if(scenario==4)begin
                    force dut.cache_rsp_tag=16'hffff;
                    finish_build;release dut.cache_rsp_tag;
                    if(b_valid)$fatal(1,"corrupt read published B");
                    build_setup;build_req_valid=1;tick;build_req_valid=0;finish_build;
                    if(!b_valid)$fatal(1,"rebuild after drained stale response failed");read_b;
                end else begin
                    if(scenario==5)cancel=1;else rst=1;tick;cancel=0;rst=0;
                    if(p_valid || b_valid || mat_rsp_valid || build_rsp_valid || build_busy)$fatal(1,"abort retained state");
                    phi_load;build_setup;build_req_valid=1;tick;build_req_valid=0;finish_build;read_b;
                end
            end else begin
                finish_build;
                if(scenario==0)begin
                    if(!b_valid || b_rows!=rows || b_cols!=count || b_job!=7 || b_fmt!=3 || b_key!=92 || b_generation!=2)$fatal(1,"built metadata wrong");
                    read_b;
                end else if(b_valid)$fatal(1,"invalid builder published B");
            end
        end
        $fdisplay(trace,"END %0d %0d",clocks,reads);$fclose(trace);$display("PASS clocks=%0d reads=%0d",clocks,reads);$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
