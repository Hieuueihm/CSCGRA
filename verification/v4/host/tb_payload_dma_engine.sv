`timescale 1ns/1ps
module tb_payload_dma_engine;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,cancel=0,ack=0,start=0,direction_write=0;
    reg [63:0] base_addr=0;
    reg [10:0] element_count=1;
    reg [8:0] block_base=3;
    reg [15:0] tag=16'h1234;
    wire busy,start_ready,done; wire [3:0] error_code;
    wire [31:0] completed_bytes,active_cycles,read_beats,write_beats,stall_cycles;
    wire host_valid,host_ready,host_rsp_ready,read_valid,read_ready,read_rsp_ready;
    wire [8:0] host_block; wire [31:0] host_mask; wire [863:0] host_data;
    wire [15:0] host_tag,read_tag; wire [9:0] read_index;
    reg host_rsp_valid=0,host_rsp_write=1; reg [31:0] host_rsp_mask=0;
    reg [15:0] host_rsp_tag=0; reg [3:0] host_rsp_fault=0;
    reg read_rsp_valid=0; reg [26:0] read_rsp_data=0; reg [9:0] read_rsp_index=0;
    reg [15:0] read_rsp_request_tag=0; reg [3:0] read_rsp_fault=0;
    wire [63:0] m_axi_araddr,m_axi_awaddr; wire [7:0] m_axi_arlen,m_axi_awlen;
    wire [2:0] m_axi_arsize,m_axi_awsize; wire [1:0] m_axi_arburst,m_axi_awburst;
    wire m_axi_arvalid,m_axi_awvalid,m_axi_arready,m_axi_awready;
    reg [127:0] m_axi_rdata=0; reg [1:0] m_axi_rresp=0;
    reg m_axi_rlast=0,m_axi_rvalid=0; wire m_axi_rready;
    wire [127:0] m_axi_wdata; wire [15:0] m_axi_wstrb;
    wire m_axi_wlast,m_axi_wvalid,m_axi_wready; reg [1:0] m_axi_bresp=0;
    reg m_axi_bvalid=0; wire m_axi_bready;
    reg [31:0] memory[0:8191]; reg [26:0] vector_pool[0:15359];
    reg reading=0,writing=0,b_pending=0;
    integer read_address=0,write_address=0,remaining_r=0,remaining_w=0;
    integer tick=0,checks=0,cases=0,mode=0,b_delay=0;
    integer index,lane,byte_lane,value;
    reg hold_ar=0,hold_aw=0,hold_r=0,hold_w=0,hold_b=0,hold_host=0,hold_read=0;
    reg ar_held=0,aw_held=0,w_held=0,host_held=0,read_held=0;
    reg [76:0] saved_ar,saved_aw; reg [144:0] saved_w;
    reg [920:0] saved_host; reg [25:0] saved_read;
    assign m_axi_arready=!reading&&!m_axi_rvalid&&!hold_ar&&tick%5!=0;
    assign m_axi_awready=!writing&&!b_pending&&!m_axi_bvalid&&!hold_aw&&tick%5!=1;
    assign m_axi_wready=writing&&!hold_w&&tick%3!=0;
    assign host_ready=!host_rsp_valid&&!hold_host&&tick%7!=0;
    assign read_ready=!read_rsp_valid&&!hold_read&&tick%3!=0;
    payload_dma_engine dut(.*);
    function automatic [31:0] sample(input integer position);
        integer signed raw;
        begin raw=position%2 ? -position*17-1 : position*31+3; sample=32'(raw); end
    endfunction
    task automatic check(input bit okay,input string message);
        begin if(!okay) $fatal(1,"case=%0d tick=%0d %s",cases,tick,message); checks=checks+1; end
    endtask
    always @(posedge clk) begin
        tick<=tick+1;
        if(tick>300000) $fatal(1,"watchdog state=%0d",dut.state);
        if(!rst) begin
            if(ar_held) check(m_axi_arvalid&&{m_axi_araddr,m_axi_arlen,m_axi_arsize,m_axi_arburst}===saved_ar,"AR changed under stall");
            if(aw_held) check(m_axi_awvalid&&{m_axi_awaddr,m_axi_awlen,m_axi_awsize,m_axi_awburst}===saved_aw,"AW changed under stall");
            if(w_held) check(m_axi_wvalid&&{m_axi_wdata,m_axi_wstrb,m_axi_wlast}===saved_w,"W changed under stall");
            if(host_held) check(host_valid&&{host_block,host_mask,host_data,host_tag}===saved_host,"native host changed under stall");
            if(read_held) check(read_valid&&{read_index,read_tag}===saved_read,"native read changed under stall");
            ar_held<=m_axi_arvalid&&!m_axi_arready; saved_ar<={m_axi_araddr,m_axi_arlen,m_axi_arsize,m_axi_arburst};
            aw_held<=m_axi_awvalid&&!m_axi_awready; saved_aw<={m_axi_awaddr,m_axi_awlen,m_axi_awsize,m_axi_awburst};
            w_held<=m_axi_wvalid&&!m_axi_wready; saved_w<={m_axi_wdata,m_axi_wstrb,m_axi_wlast};
            host_held<=host_valid&&!host_ready; saved_host<={host_block,host_mask,host_data,host_tag};
            read_held<=read_valid&&!read_ready; saved_read<={read_index,read_tag};
            if(m_axi_arvalid&&m_axi_arready) begin
                check(m_axi_arsize==4&&m_axi_arburst==1&&m_axi_arlen<8,"bad read burst");
                check(int'(m_axi_araddr[11:0])+(int'(m_axi_arlen)+1)*16<=4096,"read crosses 4K");
                reading<=1; read_address<=int'(m_axi_araddr);
                remaining_r<=mode==3 ? 1 : int'(m_axi_arlen)+1+(mode==4 ? 1:0);
            end
            if(reading&&!m_axi_rvalid&&!hold_r&&tick%3!=0) begin
                m_axi_rvalid<=1; m_axi_rresp<=mode==1 ? 2'b10 : 0;
                m_axi_rlast<=remaining_r==1;
                for(integer item=0;item<4;item=item+1) m_axi_rdata[item*32+:32]<=memory[read_address/4+item];
            end
            if(m_axi_rvalid&&m_axi_rready) begin
                m_axi_rvalid<=0; read_address<=read_address+16; remaining_r<=remaining_r-1;
                if(m_axi_rlast) reading<=0;
            end
            if(host_rsp_valid&&host_rsp_ready) host_rsp_valid<=0;
            if(host_valid&&host_ready) begin
                for(integer item=0;item<32;item=item+1)
                    if(host_mask[item]) vector_pool[int'(host_block)*32+item]<=host_data[item*27+:27];
                host_rsp_valid<=1; host_rsp_mask<=host_mask; host_rsp_write<=1;
                host_rsp_tag<=mode==6 ? host_tag^16'h1 : host_tag; host_rsp_fault<=mode==5 ? 4'd2 : 0;
            end
            if(read_rsp_valid&&read_rsp_ready) read_rsp_valid<=0;
            if(read_valid&&read_ready) begin
                read_rsp_valid<=1; read_rsp_data<=27'(sample(int'(read_index)));
                read_rsp_index<=read_index; read_rsp_request_tag<=mode==6 ? read_tag^16'h1 : read_tag;
                read_rsp_fault<=mode==5 ? 4'd2 : 0;
            end
            if(m_axi_awvalid&&m_axi_awready) begin
                check(m_axi_awsize==4&&m_axi_awburst==1&&m_axi_awlen<8,"bad write burst");
                check(int'(m_axi_awaddr[11:0])+(int'(m_axi_awlen)+1)*16<=4096,"write crosses 4K");
                writing<=1; write_address<=int'(m_axi_awaddr); remaining_w<=int'(m_axi_awlen)+1;
            end
            if(m_axi_wvalid&&m_axi_wready) begin
                check(m_axi_wlast==(remaining_w==1),"wrong WLAST");
                for(integer item=0;item<16;item=item+1)
                    if(m_axi_wstrb[item]) memory[write_address/4+item/4][(item%4)*8+:8]<=m_axi_wdata[item*8+:8];
                write_address<=write_address+16; remaining_w<=remaining_w-1;
                if(m_axi_wlast) begin writing<=0; b_pending<=1; b_delay<=3; end
            end
            if(b_pending&&!hold_b) begin
                if(b_delay>0) b_delay<=b_delay-1;
                else begin b_pending<=0; m_axi_bvalid<=1; m_axi_bresp<=mode==2 ? 2'b10 : 0; end
            end
            if(m_axi_bvalid&&m_axi_bready) m_axi_bvalid<=0;
        end
    end
    task automatic launch(input bit wr,input integer count,input reg [63:0] address,input integer fault_mode);
        begin
            check(!busy,"launch while busy"); @(negedge clk); ack=1;
            @(negedge clk); ack=0; direction_write=wr; element_count=11'(count); base_addr=address;
            mode=fault_mode; start=1; @(negedge clk); start=0; cases=cases+1;
        end
    endtask
    task automatic finish_case(input integer expected_error);
        begin
            wait(done); @(negedge clk);
            check(!busy&&error_code==expected_error,"completion/error mismatch");
            check(!reading&&!writing&&!b_pending&&!m_axi_rvalid&&!m_axi_bvalid,"orphan AXI transaction");
            check(!host_rsp_valid&&!read_rsp_valid,"orphan native transaction");
        end
    endtask
    task automatic normal_case(input bit wr,input integer count,input integer address);
        begin
            for(index=0;index<8192;index=index+1) memory[index]=32'h5555aaaa;
            for(index=0;index<15360;index=index+1) vector_pool[index]=27'h1555555;
            if(!wr) for(index=0;index<count;index=index+1) memory[address/4+index]=sample(index);
            launch(wr,count,64'(address),0); finish_case(0);
            check(completed_bytes==count*4,"wrong completed bytes");
            for(index=0;index<count;index=index+1)
                if(wr) check(memory[address/4+index]===sample(index),"wrong download value");
                else check(vector_pool[int'(block_base)*32+index]===27'(sample(index)),"wrong upload value");
            if(wr) check(memory[address/4+count]===32'h5555aaaa,"write tail corruption");
            else check(vector_pool[int'(block_base)*32+count]===27'h1555555,"upload tail corruption");
            check(stall_cycles>0,"no stall coverage");
        end
    endtask
    task automatic cancel_case(input integer phase);
        begin
            for(index=0;index<8192;index=index+1) memory[index]=32'd1;
            hold_ar=phase==0; hold_r=phase==1; hold_host=phase==2;
            hold_read=phase==3; hold_aw=phase==4; hold_w=phase==5; hold_b=phase==6;
            launch(phase>=3,33,64'hff0,0);
            case(phase)
                0: wait(m_axi_arvalid);
                1: wait(reading);
                2: wait(host_valid);
                3: wait(read_valid);
                4: wait(m_axi_awvalid);
                5: wait(m_axi_wvalid);
                6: wait(b_pending);
            endcase
            @(negedge clk); cancel=1; @(negedge clk); cancel=0;
            repeat(4) @(negedge clk);
            check(busy&&!done,"cancel abandoned outstanding transaction");
            hold_ar=0;hold_r=0;hold_host=0;hold_read=0;hold_aw=0;hold_w=0;hold_b=0;
            finish_case(4);
            normal_case(phase>=3,1,4096);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=0;
        normal_case(0,1,4096); normal_case(1,1,4096);
        normal_case(0,33,4080); normal_case(1,33,4080);
        normal_case(0,1024,4080); normal_case(1,1024,4080);
        launch(0,0,0,0); finish_case(1);
        launch(0,1025,0,0); finish_case(1);
        launch(0,1,4,0); finish_case(1);
        launch(0,32,64'hfffffffffffffff0,0); finish_case(1);
        block_base=479; launch(0,33,0,0); finish_case(1); block_base=3;
        for(index=0;index<8192;index=index+1) memory[index]=1;
        launch(0,33,4096,1); finish_case(2);
        launch(0,33,4096,3); finish_case(6);
        launch(0,33,4096,4); finish_case(6);
        memory[1024]=32'h04000000; launch(0,1,4096,0); finish_case(7); memory[1024]=1;
        launch(0,4,4096,5); finish_case(5); launch(0,4,4096,6); finish_case(6);
        launch(1,4,4096,5); finish_case(5); launch(1,4,4096,6); finish_case(6);
        launch(1,33,4096,2); finish_case(3);
        for(integer phase=0;phase<7;phase=phase+1) cancel_case(phase);
        $display("PASS payload_dma cases=%0d checks=%0d clocks=%0d",cases,checks,tick); $finish;
    end
endmodule
