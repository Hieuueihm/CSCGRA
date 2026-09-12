`include "memory_defs.vh"
`include "phi_interface.vh"
`include "builder_defs.vh"
module tb_operator_queue;
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
    reg feed_active=0;integer feed_enable,ignored,fdense,frfour,ftrans,fo,fr,fs,fl,fstart,passes,negative_checks=0;
    reg [1804:0] held_frame;
    reg [127:0] saved_key;
    reg  f_req_valid=0;
    wire  f_req_ready;
    reg  f_req_dense=0;
    reg  f_req_rfour=0;
    reg  f_req_trans=0;
    reg [7:0] f_req_rows=0;
    reg [10:0] f_req_cols=0;
    reg [10:0] f_req_out=0;
    reg [10:0] f_req_red=0;
    reg [10:0] f_req_vec_length=0;
    reg [2:0] f_req_step=0;
    reg [8:0] f_req_vec_base=0;
    reg [17:0] f_req_scale=0;
    reg [127:0] f_req_key=0;
    reg [31:0] f_req_generation=0;
    reg [15:0] f_req_job=0;
    reg [15:0] f_req_tag=0;
    reg [7:0] f_req_fmt=0;
    reg  f_req_last=0;
    wire  f_mat_valid;
    wire  f_mat_dense;
    wire [31:0] f_mat_mask;
    wire [287:0] f_mat_addr;
    wire [127:0] f_mat_key;
    wire [31:0] f_mat_generation;
    wire [15:0] f_mem_job;
    wire [15:0] f_mem_tag;
    wire [7:0] f_mem_fmt;
    wire  f_mat_rsp_ready;
    reg f_mat_stall=0,f_rsp_stall=0,f_rsp_bad_tag=0,f_rsp_bad_mask=0;
    wire f_feeder_mat_ready=mat_ready&&!f_mat_stall;
    wire f_endpoint_mat_valid=f_mat_valid&&!f_mat_stall;
    wire f_feeder_rsp_valid=mat_rsp_valid&&!f_rsp_stall;
    wire [15:0] f_feeder_rsp_tag=f_rsp_bad_tag ? 16'hffff : mat_rsp_tag;
    wire [31:0] f_feeder_rsp_mask=f_rsp_bad_mask ? 32'b0 : mat_rsp_mask;
    wire  f_vec_valid;
    wire  f_vec_ready;
    wire [8:0] f_vec_block;
    wire [31:0] f_vec_mask;
    wire [15:0] f_vec_tag;
    wire  f_vec_rsp_valid;
    wire  f_vec_rsp_ready;
    wire [863:0] f_vec_rsp_data;
    wire [31:0] f_vec_rsp_mask;
    wire [15:0] f_vec_rsp_tag;
    wire [3:0] f_vec_rsp_fault;
    wire  f_rsp_valid;
    reg  f_rsp_ready=0;
    wire [863:0] f_rsp_mat;
    wire [863:0] f_rsp_vec;
    wire [31:0] f_rsp_mask;
    wire [3:0] f_rsp_fault;
    wire [15:0] f_rsp_job;
    wire [15:0] f_rsp_tag;
    wire [7:0] f_rsp_fmt;
    wire  f_rsp_last;
    reg f_command_start=0;
    operator_frame_feeder feeder(.command_start(f_command_start),.clk(clk),.rst(rst),.cancel(cancel),.req_valid(f_req_valid),.req_ready(f_req_ready),.req_dense(f_req_dense),.req_rfour(f_req_rfour),.req_trans(f_req_trans),.req_rows(f_req_rows),.req_cols(f_req_cols),.req_out(f_req_out),.req_red(f_req_red),.req_vec_length(f_req_vec_length),.req_step(f_req_step),.req_vec_base(f_req_vec_base),.req_scale(f_req_scale),.req_key(f_req_key),.req_generation(f_req_generation),.req_job(f_req_job),.req_tag(f_req_tag),.req_fmt(f_req_fmt),.req_last(f_req_last),.matrix_valid((f_req_dense ? b_valid : p_valid)),.matrix_rows((f_req_dense ? b_rows : p_rows)),.matrix_cols((f_req_dense ?  {4'b0,b_cols} : p_cols)),.matrix_key((f_req_dense ? b_key : p_key)),.matrix_generation((f_req_dense ? b_generation : p_generation)),.matrix_job((f_req_dense ? b_job : p_job)),.matrix_fmt((f_req_dense ? b_fmt : p_fmt)),.mat_valid(f_mat_valid),.mat_ready(f_feeder_mat_ready),.mat_dense(f_mat_dense),.mat_mask(f_mat_mask),.mat_addr(f_mat_addr),.mat_key(f_mat_key),.mat_generation(f_mat_generation),.mem_job(f_mem_job),.mem_tag(f_mem_tag),.mem_fmt(f_mem_fmt),.mat_rsp_valid(f_feeder_rsp_valid),.mat_rsp_ready(f_mat_rsp_ready),.mat_rsp_data(mat_rsp_data),.mat_rsp_masks(mat_rsp_masks),.mat_rsp_mask(f_feeder_rsp_mask),.mat_rsp_generation(mat_rsp_generation),.mat_rsp_job(mat_rsp_job),.mat_rsp_tag(f_feeder_rsp_tag),.mat_rsp_fmt(mat_rsp_fmt),.mat_rsp_fault(mat_rsp_fault),.vec_valid(f_vec_valid),.vec_ready(f_vec_ready),.vec_block(f_vec_block),.vec_mask(f_vec_mask),.vec_tag(f_vec_tag),.vec_rsp_valid(f_vec_rsp_valid),.vec_rsp_ready(f_vec_rsp_ready),.vec_rsp_data(f_vec_rsp_data),.vec_rsp_mask(f_vec_rsp_mask),.vec_rsp_tag(f_vec_rsp_tag),.vec_rsp_fault(f_vec_rsp_fault),.rsp_valid(f_rsp_valid),.rsp_ready(f_rsp_ready),.rsp_mat(f_rsp_mat),.rsp_vec(f_rsp_vec),.rsp_mask(f_rsp_mask),.rsp_fault(f_rsp_fault),.rsp_job(f_rsp_job),.rsp_tag(f_rsp_tag),.rsp_fmt(f_rsp_fmt),.rsp_last(f_rsp_last));
    reg pool_load=0;reg[8:0] pool_block=0;reg[863:0] pool_data=0;
    wire pool_ready;
    assign f_vec_ready=pool_ready&&!pool_load;
    assign f_vec_rsp_fault=0;
    stream_vector_store pool(.clk(clk),.rst(rst),.cancel(cancel),.req_valid(pool_load||f_vec_valid),.req_ready(pool_ready),
        .req_write(pool_load),.req_block(pool_load ? pool_block : f_vec_block),.req_mask(pool_load ? 32'hffffffff : f_vec_mask),
        .req_data(pool_data),.req_tag(f_vec_tag),.rsp_valid(f_vec_rsp_valid),.rsp_ready(f_vec_rsp_ready),
        .rsp_data(f_vec_rsp_data),.rsp_mask(f_vec_rsp_mask),.rsp_tag(f_vec_rsp_tag));
    task feed_one(input integer restart_command);
        begin
            if(restart_command)begin
                f_command_start=1;tick;f_command_start=0;
                if(feeder.tile_valid[0]||feeder.tile_valid[1]||feeder.tile_pending[0]||feeder.tile_pending[1])$fatal(1,"command start retained Phi tile");
            end
            f_req_valid=1;fstart=clocks;passes=0;tick;f_req_valid=0;
            saved_key=f_req_key;f_req_key=999;
            while(!f_rsp_valid) begin
                if(f_mat_valid&&mat_ready) passes=passes+1;
                tick;
            end
            if(f_rsp_fault!==0||f_rsp_job!==7||f_rsp_tag!==1234||f_rsp_fmt!==1||f_rsp_last!==1'b1) $fatal(1,"feeder fault%0d",f_rsp_fault);
            $fdisplay(trace,"F %0d %0d %0d %0d %0d %0d %h %h %h %0d %0d",fdense,frfour,ftrans,fo,fr,fs,f_rsp_mask,f_rsp_mat,f_rsp_vec,clocks-fstart,passes);
            held_frame={f_rsp_mat,f_rsp_vec,f_rsp_mask,f_rsp_fault,f_rsp_job,f_rsp_tag,f_rsp_fmt,f_rsp_last};
            repeat(2) begin tick;if(!f_rsp_valid||held_frame!=={f_rsp_mat,f_rsp_vec,f_rsp_mask,f_rsp_fault,f_rsp_job,f_rsp_tag,f_rsp_fmt,f_rsp_last}) $fatal(1,"feeder held frame changed");end
            f_rsp_ready=1;tick;f_rsp_ready=0;
            f_req_key=saved_key;
        end
    endtask
    task feed_fault(input integer expected_fault,input integer corrupt_tag);
        begin
            f_command_start=1;tick;f_command_start=0;
            f_req_valid=1;tick;f_req_valid=0;
            if(corrupt_tag) begin
                while(!f_vec_rsp_valid) tick;
                force f_vec_rsp_tag=16'hffff;tick;release f_vec_rsp_tag;
            end
            while(!f_rsp_valid) tick;
            if(f_rsp_fault!==expected_fault||f_rsp_mask!==0||f_rsp_mat!==0||f_rsp_vec!==0) $fatal(1,"feeder negative %0d want%0d",f_rsp_fault,expected_fault);
            f_rsp_ready=1;tick;f_rsp_ready=0;negative_checks=negative_checks+1;
        end
    endtask
    task feed_test;
        begin
            wait_idle;feed_active=1;compute_active=1;pool_load=1;
            for(fl=0;fl<32;fl=fl+1) begin
                pool_block=400+fl;
                for(bank=0;bank<32;bank=bank+1) pool_data[bank*27 +: 27]=27'((fl*32+bank)*17-123);
                tick;
            end
            pool_load=0;f_req_rows=rows;f_req_vec_base=400;f_req_vec_length=1024;f_req_scale=scale;
            f_req_job=7;f_req_tag=1234;f_req_fmt=1;f_req_last=1;
            for(fdense=0;fdense<2;fdense=fdense+1) begin
                f_req_dense=fdense;f_req_cols=fdense ? count : cols;f_req_key=fdense ? 92 : 91;f_req_generation=fdense ? 2 : 1;
                for(frfour=0;frfour<2;frfour=frfour+1) for(ftrans=0;ftrans<2;ftrans=ftrans+1) begin
                    f_req_rfour=frfour;f_req_trans=ftrans;
                    for(fo=0;fo<(ftrans ? int'(f_req_cols) : rows);fo=fo+(frfour ? 8 : 32))
                    for(fr=0;fr<(ftrans ? rows : int'(f_req_cols));fr=fr+(frfour ? 32 : 1))
                    for(fs=0;fs<(frfour ? 8 : 1);fs=fs+1) begin
                        f_req_out=fo;f_req_red=fr;f_req_step=fs;feed_one(1);
                    end
                end
            end
            // Reject descriptor metadata before issue, then corrupt a real pool response.
            f_req_dense=0;f_req_rfour=0;f_req_trans=0;f_req_cols=cols;f_req_out=0;f_req_red=0;f_req_step=0;f_req_key=91;f_req_generation=1;
            f_req_key=99;feed_fault(3,0);f_req_key=91;
            f_req_generation=2;feed_fault(3,0);f_req_generation=1;
            f_req_rows=0;feed_fault(1,0);f_req_rows=rows;
            f_req_vec_base=480;feed_fault(4,0);f_req_vec_base=400;
            f_req_step=1;feed_fault(4,0);f_req_step=0;
            f_req_job=8;feed_fault(3,0);f_req_job=7;
            feed_fault(8,1);
            // Stall the real vector endpoint while the independent Phi request proceeds.
            force pool.req_ready=1'b0;
            f_command_start=1;tick;f_command_start=0;
            f_req_valid=1;tick;f_req_valid=0;repeat(4) tick;
            if(f_rsp_valid||!f_vec_valid) $fatal(1,"vector stall ownership");
            release pool.req_ready;
            while(!f_rsp_valid) tick;
            if(f_rsp_fault!==0) $fatal(1,"vector stall recovery");
            f_rsp_ready=1;tick;f_rsp_ready=0;negative_checks=negative_checks+1;
            f_command_start=1;tick;f_command_start=0;
            f_req_valid=1;tick;f_req_valid=0;tick;cancel=1;tick;cancel=0;
            if(f_rsp_valid||f_vec_rsp_valid||mat_rsp_valid||p_valid||b_valid) $fatal(1,"cancel retained pending ownership");
            feed_active=0;compute_active=0;phi_load;
            feed_active=1;compute_active=1;
            fdense=0;frfour=0;ftrans=0;fo=0;fr=0;fs=0;feed_one(1);
            $fdisplay(trace,"NEG %0d",negative_checks);
            feed_active=0;compute_active=0;
        end
    endtask
    task feed_cached_fault;
        begin
            f_req_valid=1;tick;f_req_valid=0;
            while(!f_rsp_valid)tick;
            if(f_rsp_fault!=`CSR_MEM_FAULT_SOURCE||f_rsp_mask!=0||f_rsp_mat!=0)$fatal(1,"cached missing row was hidden");
            f_rsp_ready=1;tick;f_rsp_ready=0;
        end
    endtask
    task feed_prefetch_hole;
        begin
            f_req_valid=1;tick;f_req_valid=0;
            while(!mat_rsp_valid)tick;
            force mat_rsp_masks=mat_rsp_masks&~(256'h1<<32);tick;release mat_rsp_masks;
            while(!f_rsp_valid)tick;
            if(f_rsp_fault!=0)$fatal(1,"first demand should not use prefetched hole");
            f_rsp_ready=1;tick;f_rsp_ready=0;
        end
    endtask
    task tile_coalesce_stall;
        integer start_grants,done_frames;
        reg [31:0] held_tile_mask;
        reg [287:0] held_tile_addr;
        begin
            fo=0;fr=0;fs=0;f_command_start=1;tick;f_command_start=0;start_grants=feeder.matrix_grants;
            f_mat_stall=1;
            f_req_out=0;f_req_red=0;f_req_step=0;f_req_valid=1;tick;f_req_valid=0;
            #1;if(!f_mat_valid)$fatal(1,"missing held tile request");held_tile_mask=f_mat_mask;held_tile_addr=f_mat_addr;
            f_req_out=0;f_req_red=1;f_req_step=0;f_req_valid=1;tick;f_req_valid=0;
            repeat(2)begin #1;if(!f_mat_valid||f_mat_mask!==held_tile_mask||f_mat_addr!==held_tile_addr)$fatal(1,"held VALID tile payload changed");tick;end
            f_mat_stall=0;done_frames=0;
            while(done_frames<2)begin
                if(f_rsp_valid)begin if(f_rsp_fault!=0)$fatal(1,"coalesced frame fault");f_rsp_ready=1;tick;f_rsp_ready=0;done_frames=done_frames+1;end
                else tick;
            end
            if(feeder.matrix_grants-start_grants!=1)$fatal(1,"coalesced duplicate tile grants");
        end
    endtask
    task tile_bad_tag_cancel_restart;
        begin
            fo=0;fr=0;fs=0;f_command_start=1;tick;f_command_start=0;
            f_req_out=0;f_req_red=0;f_req_step=0;f_req_valid=1;tick;f_req_valid=0;
            while(!mat_rsp_valid)tick;
            f_rsp_bad_tag=1;tick;f_rsp_bad_tag=0;
            while(!f_rsp_valid)tick;
            if(f_rsp_fault!=`CSR_MEM_FAULT_TAG)$fatal(1,"bad tile tag not reported");f_rsp_ready=1;tick;f_rsp_ready=0;
            cancel=1;tick;cancel=0;
            if(f_rsp_valid||feeder.tile_valid[0]||feeder.tile_valid[1]||feeder.tile_pending[0]||feeder.tile_pending[1])$fatal(1,"cancel retained tile state");
            feed_active=0;compute_active=0;phi_load;
            feed_active=1;compute_active=1;pool_load=1;
            for(fl=0;fl<32;fl=fl+1)begin pool_block=400+fl;for(bank=0;bank<32;bank=bank+1)pool_data[bank*27 +:27]=27'((fl*32+bank)*17-123);tick;end
            pool_load=0;f_req_out=0;f_req_red=0;f_req_step=0;feed_one(1);
        end
    endtask
    task tile_reuse_test;
        integer start_grants;
        begin
            wait_idle;feed_active=1;compute_active=1;pool_load=1;
            for(fl=0;fl<32;fl=fl+1)begin
                pool_block=400+fl;
                for(bank=0;bank<32;bank=bank+1)pool_data[bank*27 +:27]=27'((fl*32+bank)*17-123);
                tick;
            end
            pool_load=0;
            // R1 forward: consecutive columns in one 32-row block share one
            // eight-bank tile.  The Python parser independently checks every F
            // frame against the LFSR coordinate oracle.
            fdense=0;frfour=0;ftrans=0;fo=0;fs=0;f_req_dense=0;f_req_rfour=0;f_req_trans=0;
            f_req_rows=rows;f_req_cols=cols;f_req_vec_base=400;f_req_vec_length=1024;f_req_scale=scale;
            f_req_key=91;f_req_generation=1;f_req_job=7;f_req_tag=1234;f_req_fmt=1;f_req_last=1;
            f_command_start=1;tick;f_command_start=0;start_grants=feeder.matrix_grants;
            for(fr=0;fr<8&&fr<cols;fr=fr+1)begin f_req_out=fo;f_req_red=fr;f_req_step=0;feed_one(0);end
            if(feeder.matrix_grants-start_grants!=1)$fatal(1,"R1 tile grants %0d",feeder.matrix_grants-start_grants);
            // R4 transpose: the eight steps revisit the same eight columns and
            // the same row block.  This also covers an incomplete final column tile.
            frfour=1;ftrans=1;f_req_rfour=1;f_req_trans=1;fo=0;fr=0;
            f_command_start=1;tick;f_command_start=0;start_grants=feeder.matrix_grants;
            for(fs=0;fs<8;fs=fs+1)begin f_req_out=fo;f_req_red=fr;f_req_step=fs;feed_one(0);end
            if(feeder.matrix_grants-start_grants!=1)$fatal(1,"R4 tile grants %0d",feeder.matrix_grants-start_grants);
            $fdisplay(trace,"TILE %0d %0d",feeder.matrix_grants,feeder.tile_valid[0]+feeder.tile_valid[1]);
            feed_active=0;compute_active=0;
        end
    endtask
    task tile_boundary_test;
        integer start_grants,entry;
        begin
            wait_idle;feed_active=1;compute_active=1;pool_load=1;
            for(fl=0;fl<32;fl=fl+1)begin pool_block=400+fl;for(bank=0;bank<32;bank=bank+1)pool_data[bank*27 +:27]=27'((fl*32+bank)*17-123);tick;end
            pool_load=0;fdense=0;frfour=0;ftrans=0;f_req_dense=0;f_req_rfour=0;f_req_trans=0;
            f_req_rows=rows;f_req_cols=cols;f_req_vec_base=400;f_req_vec_length=1024;f_req_scale=scale;f_req_key=91;f_req_generation=1;f_req_job=7;f_req_tag=1234;f_req_fmt=1;f_req_last=1;
            // Tail row block and final partial column tile retain raw validity.
            if(rows>32&&cols>64)begin
                fo=32;fs=0;f_command_start=1;tick;f_command_start=0;start_grants=feeder.matrix_grants;
                for(fr=64;fr<cols&&fr<72;fr=fr+1)begin f_req_out=fo;f_req_red=fr;f_req_step=0;feed_one(0);end
                if(feeder.matrix_grants-start_grants!=1)$fatal(1,"tail tile grants");
            end
            // Three distinct tiles exceed two entries; revisiting the oldest is a miss.
            if(cols>=17)begin
                fo=0;fs=0;f_command_start=1;tick;f_command_start=0;start_grants=feeder.matrix_grants;
                for(entry=0;entry<3;entry=entry+1)begin fr=entry*8;f_req_out=fo;f_req_red=fr;f_req_step=0;feed_one(0);end
                fr=0;f_req_out=fo;f_req_red=fr;f_req_step=0;feed_one(0);
                if(feeder.matrix_grants-start_grants!=4)$fatal(1,"tile eviction/revisit grants");
            end
            // A sparse prefetched row mask may populate the raw tile for the
            // first demanded frame, but a later demand for that row must fault.
            if(cols>1)begin
                fo=0;fr=0;fs=0;f_command_start=1;tick;f_command_start=0;
                f_req_out=fo;f_req_red=fr;f_req_step=fs;feed_prefetch_hole;
                fr=1;f_req_out=fo;f_req_red=fr;f_req_step=0;feed_cached_fault;
            end
            $fdisplay(trace,"MARK faultdone");
            tile_coalesce_stall;tile_bad_tag_cancel_restart;
            $fdisplay(trace,"BOUNDARY %0d",feeder.matrix_grants);feed_active=0;compute_active=0;
        end
    endtask


    live_operator_memory dut (
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
        .mat_valid(feed_active ? f_endpoint_mat_valid : mat_valid),
        .mat_ready(mat_ready),
        .mat_mask(feed_active ? f_mat_mask : mat_mask),
        .mat_addr(feed_active ? f_mat_addr : mat_addr),
        .mat_key(feed_active ? f_mat_key : mat_key),
        .mat_generation(feed_active ? f_mat_generation : mat_generation),
        .mat_rsp_valid(mat_rsp_valid),
        .mat_rsp_ready(feed_active ? (f_mat_rsp_ready&&!f_rsp_stall) : mat_rsp_ready),
        .mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks),
        .mat_rsp_mask(mat_rsp_mask),
        .mat_rsp_generation(mat_rsp_generation),
        .mat_rsp_job(mat_rsp_job),
        .mat_rsp_tag(mat_rsp_tag),
        .mat_rsp_fmt(mat_rsp_fmt),
        .mat_rsp_fault(mat_rsp_fault),
        .mat_dense(feed_active ? f_mat_dense : mat_dense),
        .mem_job(feed_active ? f_mem_job : mem_job),
        .mem_tag(feed_active ? f_mem_tag : mem_tag),
        .mem_fmt(feed_active ? f_mem_fmt : mem_fmt)
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
            p_begin_key=91;p_begin_generation=1;p_begin_job=7;p_begin_fmt=1;p_begin_valid=1;
            #1;if(!p_begin_ready)$fatal(1,"Phi begin blocked");tick;p_begin_valid=0;
            wait_idle;
            if(!p_valid || p_rows!=rows || p_cols!=cols || p_job!=7 || p_fmt!=1 || p_key!=91 || p_generation!=1 || p_fault!=0)
                $fatal(1,"Phi descriptor not published");
        end
    endtask
    task build_setup;
        begin
            build_req_rows=8'(rows);build_req_cols=11'(cols);build_req_count=7'(count);build_req_scale=18'(scale);
            build_req_phi_key=91;build_req_phi_generation=1;build_req_b_key=92;build_req_b_generation=2;
            build_req_job=7;build_req_tag=55;build_req_fmt=1;build_req_support='0;
            for(slot=0;slot<count;slot=slot+1)build_req_support[slot*10+:10]=10'(cols-1-slot);
        end
    endtask
    task phi_read;
        begin
            mat_dense=0;mat_mask=1;mat_addr=0;mat_key=91;mat_generation=1;mem_job=7;mem_tag=123;mem_fmt=1;mat_valid=1;
            #1;if(!mat_ready)$fatal(1,"Phi kernel read blocked");tick;mat_valid=0;
            cycle=0;while(!mat_rsp_valid && cycle<100)begin tick;cycle=cycle+1;end
            if(!mat_rsp_valid || mat_rsp_fault!=0 || mat_rsp_tag!=123 || mat_rsp_job!=7 || mat_rsp_fmt!=1)$fatal(1,"Phi read failed");
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
                tick;if(build_rsp_cycles!=saved_cycles || build_rsp_tag!=55 || build_rsp_job!=(scenario==1 ? 8 : 7) || build_rsp_fmt!=(scenario==8 ? 4 : 1))$fatal(1,"completion changed");
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
                                mat_dense=1;mat_mask=plan_mask;mat_addr=plan_addr;mat_key=92;mat_generation=2;mem_job=7;mem_tag=16'(reads);mem_fmt=1;
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
            b_begin_rows=8'(rows);b_begin_cols=7'(count);b_begin_key=92;b_begin_generation=2;b_begin_job=7;b_begin_fmt=1;b_begin_valid=1;
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
    task queue_test;
        begin
            wait_idle;compute_active=1;
            mat_dense=1;mat_mask=1;mat_addr=0;mat_key=92;mat_generation=2;mem_job=7;mem_fmt=1;
            mem_tag=16'hfffe;mat_valid=1;#1;if(!mat_ready)$fatal(1,"first credit not ready");tick;
            mem_tag=16'hffff;#1;if(!mat_ready)$fatal(1,"second credit not ready");tick;mat_valid=0;
            if(dut.read_count!=2)$fatal(1,"two credits not occupied");
            while(!mat_rsp_valid)tick;
            held_data=mat_rsp_data;
            mat_dense=0;mat_key=91;mat_generation=1;mem_tag=0;mat_valid=1;
            repeat(4)begin #1;if(mat_ready||mat_rsp_tag!=16'hfffe||mat_rsp_data!==held_data)$fatal(1,"opposite mode/held first failed");tick;end
            mat_rsp_ready=1;tick;mat_rsp_ready=0;
            while(!mat_rsp_valid)tick;
            if(mat_ready||mat_rsp_tag!=16'hffff||mat_rsp_data!==held_data||mat_rsp_fault!=0)$fatal(1,"ordered second failed");
            mat_rsp_ready=1;tick;mat_rsp_ready=0;
            #1;if(!mat_ready)$fatal(1,"Phi mode blocked after full drain");tick;mat_valid=0;
            while(!mat_rsp_valid)tick;
            if(mat_rsp_tag!=0||mat_rsp_fault!=0||mat_rsp_job!=7||mat_rsp_generation!=1||mat_rsp_fmt!=1)$fatal(1,"wrapped tag Phi response failed");
            mat_rsp_ready=1;tick;mat_rsp_ready=0;
            // Held host VALID may not deadlock an active compute owner.
            build_setup;build_req_valid=1;p_begin_valid=1;b_begin_valid=1;
            mat_dense=1;mat_key=92;mat_generation=2;mem_tag=1;mat_valid=1;
            #1;if(!mat_ready||build_req_ready||p_begin_ready||b_begin_ready)$fatal(1,"held host stole compute");tick;mat_valid=0;
            while(!mat_rsp_valid)tick;
            compute_active=0;p_begin_valid=0;b_begin_valid=0;mat_valid=1;mem_tag=2;
            repeat(3)begin #1;if(mat_ready||build_req_ready||mat_rsp_tag!=1)$fatal(1,"pending build failed to drain");tick;end
            mat_valid=0;mat_rsp_ready=1;tick;mat_rsp_ready=0;
            #1;if(!build_req_ready)$fatal(1,"build not released after drain");build_req_valid=0;
            // Cancel both outstanding B credits, then reconstruct the same image.
            compute_active=1;mem_tag=16'hfffe;mat_valid=1;#1;if(!mat_ready)$fatal(1,"restart read blocked");tick;
            mem_tag=16'hffff;#1;if(!mat_ready)$fatal(1,"restart second blocked");tick;mat_valid=0;
            cancel=1;tick;cancel=0;compute_active=0;
            repeat(3)begin tick;if(mat_rsp_valid||p_valid||b_valid||dut.read_count!=0)$fatal(1,"cancel credit leaked");end
            phi_load;build_setup;build_req_valid=1;tick;build_req_valid=0;finish_build;read_b;
            $display("PASS operator_queue two_credits mode_drain host_pending tag_wrap cancel_restart");
        end
    endtask
    initial begin
        if(!$value$plusargs("rows=%d",rows)||!$value$plusargs("cols=%d",cols)||!$value$plusargs("count=%d",count)||
            !$value$plusargs("seed=%d",seed)||!$value$plusargs("scale=%d",scale)||!$value$plusargs("scenario=%d",scenario)||
            !$value$plusargs("trace=%s",trace_path))$fatal(1,"missing args");
        trace=$fopen(trace_path,"w");if(!trace)$fatal(1,"trace open");clocks=0;reads=0;hold_identity=0;feed_enable=0;ignored=$value$plusargs("feed=%d",feed_enable);
        rst=1;tick;rst=0;phi_load;build_setup;
        if(feed_enable==2)begin
            tile_reuse_test;tile_boundary_test;
        end else begin
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
                    if(!b_valid || b_rows!=rows || b_cols!=count || b_job!=7 || b_fmt!=1 || b_key!=92 || b_generation!=2)$fatal(1,"built metadata wrong");
                    read_b;
                end else if(b_valid)$fatal(1,"invalid builder published B");
            end
        end
        queue_test;
        if(feed_enable==1)feed_test;
        if(feed_enable>=1)tile_reuse_test;
        end
        $fdisplay(trace,"END %0d %0d",clocks,reads);$fclose(trace);$display("PASS clocks=%0d reads=%0d",clocks,reads);$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
