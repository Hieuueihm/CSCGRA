`timescale 1ns/1ps
module tb_stream_vector_store;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,cancel=0,req_valid=0,req_write=0,rsp_ready=1;
    reg [8:0] req_block=0;
    reg [31:0] req_mask=0;
    reg [863:0] req_data=0;
    reg [15:0] req_tag=0;
    wire req_ready,rsp_valid;
    wire [863:0] rsp_data;
    wire [31:0] rsp_mask;
    wire [15:0] rsp_tag;
    stream_vector_store dut(.*);
    reg [863:0] mirror[0:511],expected_data[0:8191];
    reg [31:0] expected_mask[0:8191];
    reg [15:0] expected_tag[0:8191];
    integer head=0,tail=0,checks=0,cycles=0,reads=0,writes=0,stalls=0,flushed=0;
    integer lane,i,seed=32'h1984abce,random_value,read_start;
    reg held=0;
    reg [911:0] held_payload;
    reg [863:0] wanted;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst||cancel) begin
            if(req_ready||rsp_valid) $fatal(1,"active during flush");
            flushed=flushed+tail-head;head=0;tail=0;held=0;
        end else begin
            if(held && {rsp_tag,rsp_mask,rsp_data}!==held_payload) $fatal(1,"held payload changed");
            if(held && !rsp_valid) $fatal(1,"held response vanished");
            held=rsp_valid&&!rsp_ready;
            held_payload={rsp_tag,rsp_mask,rsp_data};
            if(rsp_valid&&rsp_ready) begin
                if(head==tail) $fatal(1,"orphan/duplicate response");
                if(rsp_data!==expected_data[head]||rsp_mask!==expected_mask[head]||rsp_tag!==expected_tag[head])
                    $fatal(1,"response mismatch at %0d tag%0d expected%0d",cycles,rsp_tag,expected_tag[head]);
                checks=checks+34;head=head+1;
            end
            if(req_valid&&!req_ready) stalls=stalls+1;
            if(req_valid&&req_ready) begin
                if(req_write) begin
                    writes=writes+1;
                    for(lane=0;lane<32;lane=lane+1)
                        if(req_mask[lane]) mirror[req_block][lane*27 +: 27]=req_data[lane*27 +: 27];
                end else begin
                    reads=reads+1;wanted=0;
                    for(lane=0;lane<32;lane=lane+1)
                        if(req_mask[lane]) wanted[lane*27 +: 27]=mirror[req_block][lane*27 +: 27];
                    expected_data[tail]=wanted;expected_mask[tail]=req_mask;expected_tag[tail]=req_tag;
                    tail=tail+1;
                end
            end
        end
    end
    task command(input bit wr,input integer block_id,input reg[31:0] mask,input integer salt);
        integer k;
        begin
            @(negedge clk);req_valid=1;req_write=wr;req_block=block_id;req_mask=mask;req_tag=salt;
            for(k=0;k<32;k=k+1) req_data[k*27 +: 27]=27'((block_id*391+k*7183)^salt^27'h401abcd);
            @(posedge clk);while(!req_ready) @(posedge clk);
        end
    endtask
    task drain;
        begin
            @(negedge clk);req_valid=0;rsp_ready=1;
            repeat(5) @(negedge clk);
            if(head!=tail||rsp_valid) $fatal(1,"failed drain");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        // Every word in both512-word port halves, including boundaries0/511.
        for(i=0;i<512;i=i+1) command(1,i,32'hffffffff,i);
        drain();read_start=cycles;
        for(i=0;i<512;i=i+1) command(0,i,32'hffffffff,1000+i);
        if(cycles-read_start!=512) $fatal(1,"consecutive-read throughput lost");
        drain();
        // FullN spans32blocks, partial row masks and partial writes.
        for(i=0;i<32;i=i+1) begin
            command(1,480+i,32'h1<<i,2000+i);
            command(0,480+i,32'hffffffff,2100+i);
            command(0,480+i,(32'h1<<i)-1,2200+i);
        end
        // Older read must snapshot before later same-block write, despite sink stall.
        drain();
        @(negedge clk);req_valid=0;rsp_ready=0;
        command(0,511,32'hffffffff,3000);
        command(1,511,32'hffffffff,3001);
        command(0,511,32'hffffffff,3002);
        @(negedge clk);req_valid=1;req_write=0;req_tag=3003;
        repeat(6) begin @(negedge clk);if(req_ready) $fatal(1,"missing credit backpressure");end
        req_valid=0;rsp_ready=1;drain();
        for(i=0;i<1500;i=i+1) begin
            @(negedge clk);random_value=$random(seed);
            // While blocked retain the complete source payload until acceptance.
            if(!req_valid||req_ready) begin
                req_valid=random_value[0];req_write=random_value[1];req_block=random_value[10:2];
                req_mask=random_value^32'h5a5aa5a5;req_tag=4000+i;
                req_data={32{27'(random_value)}};
            end
            rsp_ready=(i%11)>3;
        end
        drain();
        // Cancel and reset flush queued/pipeline reads but preserve published RAM payload.
        rsp_ready=0;command(0,0,32'hffffffff,6000);command(0,511,32'hffffffff,6001);
        @(negedge clk);req_valid=0;cancel=1;
        repeat(2) @(negedge clk);cancel=0;rsp_ready=1;
        command(0,0,32'hffffffff,6100);command(0,511,32'hffffffff,6101);drain();
        rsp_ready=0;command(0,1,32'hffffffff,6200);
        @(negedge clk);req_valid=0;rst=1;
        repeat(2) @(negedge clk);rst=0;rsp_ready=1;
        command(0,1,32'hffffffff,6300);drain();
        if(stalls==0||flushed<3) $fatal(1,"missing stall/flush coverage");
        $display("PASS stream_vector_store cycles=%0d checks=%0d reads=%0d writes=%0d stalls=%0d flushed=%0d",cycles,checks,reads,writes,stalls,flushed);
        $finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
