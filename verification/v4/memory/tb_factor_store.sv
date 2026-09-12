`timescale 1ns/1ps
module tb_factor_store;
    // Legacy INIT/read/write regression leaves append disabled explicitly.
    reg begin_append_valid=0;
    reg [6:0] begin_old_cols=0;
    reg  clk, rst, cancel;
    reg  begin_valid;
    wire  begin_ready;
    reg [7:0] begin_rows;
    reg [6:0] begin_cols;
    reg [127:0] begin_key;
    reg [31:0] begin_generation;
    reg [15:0] begin_job;
    reg [7:0] begin_fmt;
    reg  fill_valid;
    wire  fill_ready;
    reg [6:0] fill_col;
    reg [1:0] fill_block;
    reg [31:0] fill_mask;
    reg [863:0] fill_data;
    reg  fill_last;
    wire  loading, store_valid;
    wire  load_status_valid;
    reg  load_status_ready;
    wire [3:0] load_status_fault;
    reg  req_valid;
    wire  req_ready;
    reg  req_write;
    reg [31:0] req_mask;
    reg [287:0] req_addr;
    reg [863:0] req_data;
    reg [127:0] req_key;
    reg [31:0] req_generation;
    reg [15:0] req_job, req_tag;
    reg [7:0] req_fmt;
    wire  rsp_valid;
    reg  rsp_ready;
    wire  rsp_write;
    wire [863:0] rsp_data;
    wire [31:0] rsp_mask;
    wire [31:0] rsp_generation;
    wire [15:0] rsp_job, rsp_tag;
    wire [7:0] rsp_fmt;
    wire [3:0] rsp_fault;
    factor_store dut (.*);
    always #5 clk=~clk;
    integer cycles=0,checks=0,accepted=0,retired=0,flushed=0;
    integer qhead=0,qtail=0,ready_mode=1,run_length=0,max_run=0;
    reg [863:0] expected_data [0:8191];
    reg [31:0] expected_mask [0:8191];
    reg [76:0] expected_meta [0:8191];
    always @(negedge clk) rsp_ready=ready_mode==0 || (ready_mode==1 && cycles%9>=4);
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(rst||cancel) begin
            flushed<=flushed+qtail-qhead;
            qhead<=0;qtail<=0;run_length<=0;
        end else begin
            if(req_valid&&req_ready) begin
                qtail<=qtail+1;accepted<=accepted+1;
                run_length<=run_length+1;
                if(run_length+1>max_run)max_run<=run_length+1;
            end else run_length<=0;
            if(rsp_valid) begin
                if(qhead>=qtail)$fatal(1,"unowned response");
                if(rsp_data!==expected_data[qhead] || rsp_mask!==expected_mask[qhead] ||
                   {rsp_write,rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt}!==expected_meta[qhead])
                    $fatal(1,"response mismatch head%0d fault%0d data%h expected%h",qhead,rsp_fault,rsp_data,expected_data[qhead]);
                checks<=checks+1;
                if(rsp_ready)begin qhead<=qhead+1;retired<=retired+1;end
            end
        end
    end
    task drain;
        begin
            while(qhead!=qtail)@(negedge clk);
            repeat(2)@(negedge clk);
        end
    endtask
    task load_status(input integer fault);
        begin
            while(!load_status_valid)@(negedge clk);
            repeat(4)begin
                if(load_status_fault!==fault||begin_ready||req_ready)$fatal(1,"load status mismatch");
                checks=checks+1;@(negedge clk);
            end
            load_status_ready=1;@(posedge clk);@(negedge clk);load_status_ready=0;
        end
    endtask
    integer fd,rc,command,ef,repeat_count,i,mode,minimum_run,append_generation;
    reg [2047:0] filename;
    reg [863:0] gold;
    initial begin
        clk=0;rst=1;cancel=0;begin_valid=0;begin_append_valid=0;fill_valid=0;req_valid=0;rsp_ready=0;
        begin_rows=0;begin_cols=0;begin_key=128'h1234;begin_generation=3;begin_job=7;begin_fmt=1;
        fill_col=0;fill_block=0;fill_mask=0;fill_data=0;fill_last=0;load_status_ready=0;
        req_write=0;req_mask=0;req_addr=0;req_data=0;req_key=0;req_generation=0;req_job=0;req_tag=0;req_fmt=0;
        repeat(3)@(negedge clk);rst=0;
        if(!$value$plusargs("vectors=%s",filename))$fatal(1,"vectors missing");
        fd=$fopen(filename,"r");if(!fd)$fatal(1,"file missing");
        while(!$feof(fd))begin
            rc=$fscanf(fd,"%d",command);
            if(rc==1)case(command)
                0:begin
                    drain();rc=$fscanf(fd,"%d %d %d %d",begin_rows,begin_cols,begin_fmt,ef);
                    begin_valid=1;do @(posedge clk);while(!begin_ready);
                    @(negedge clk);begin_valid=0;
                    if(store_valid)$fatal(1,"begin retained old factors");
                    if(ef>=0)load_status(ef);
                end
                1:begin
                    rc=$fscanf(fd,"%d %d %h %h %d %d",fill_col,fill_block,fill_mask,fill_data,fill_last,ef);
                    fill_valid=1;do @(posedge clk);while(!fill_ready);
                    @(negedge clk);fill_valid=0;
                    if(ef>=0)load_status(ef);
                    else if(ef==-1&&store_valid)$fatal(1,"partial fill published");
                end
                11:begin
                    drain();rc=$fscanf(fd,"%d %d %d %d %d %d %d",begin_rows,begin_cols,begin_old_cols,begin_fmt,ef,mode,append_generation);
                    begin_generation=append_generation;
                    begin_append_valid=1;
                    if(mode!=0) begin
                        req_valid=1;req_write=0;req_mask=1;req_addr=0;req_data=0;
                        req_key=begin_key;req_generation=begin_generation;req_job=begin_job;req_tag=16'h55;req_fmt=begin_fmt;
                    end
                    #1;
                    i=0;while(!begin_ready)begin
                        @(negedge clk);i=i+1;
                        if(i>100)$fatal(1,"append begin stalled loading%0d valid%0d status%0d reserved%0d queued%0d pipe%0d",loading,store_valid,load_status_valid,dut.reserved,dut.queued,dut.pipe_valid);
                    end
                    if(mode!=0&&req_ready)$fatal(1,"append did not exclude simultaneous request");
                    @(posedge clk);@(negedge clk);begin_append_valid=0;req_valid=0;
                    if(store_valid)$fatal(1,"append retained a published image while filling");
                    if(ef>=0)load_status(ef);
                    checks=checks+1;
                end
                2:begin
                    rc=$fscanf(fd,"%d %h %h %h %h %d %d %d %d %d %h",req_write,req_mask,req_addr,req_data,req_key,req_generation,req_job,req_tag,req_fmt,ef,gold);
                    expected_data[qtail]=gold;
                    expected_mask[qtail]=ef==0?req_mask:0;
                    expected_meta[qtail]={req_write,4'(ef),req_generation,req_job,req_tag,req_fmt};
                    req_valid=1;do @(posedge clk);while(!req_ready);
                    @(negedge clk);req_valid=0;
                end
                3,6:begin
                    if(command==3)cancel=1;else rst=1;
                    @(posedge clk);@(negedge clk);cancel=0;rst=0;
                    if(rsp_valid||store_valid||loading||load_status_valid)$fatal(1,"flush leaked state");
                end
                4:drain();
                5:begin rc=$fscanf(fd,"%d",repeat_count);repeat(repeat_count)@(negedge clk);end
                8:begin rc=$fscanf(fd,"%d",ready_mode);@(negedge clk);end
                9:begin
                    repeat(4)begin if(req_ready)$fatal(1,"overbooked two credits");@(negedge clk);end
                end
                10:begin
                    rc=$fscanf(fd,"%d",minimum_run);
                    if(max_run<minimum_run)$fatal(1,"no sustained grants %0d/%0d",max_run,minimum_run);
                end
                default:$fatal(1,"unknown stimulus command");
            endcase
        end
        ready_mode=0;drain();
        $display("PASS factor_store cycles=%0d checks=%0d accepted=%0d retired=%0d flushed=%0d max_run=%0d",cycles,checks,accepted,retired,flushed,max_run);
        $finish;
    end
    initial begin #20000000;$fatal(1,"watchdog");end
endmodule
