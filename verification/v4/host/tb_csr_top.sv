`timescale 1ns/1ps
`include "host_registers.vh"
`include "payload_dma_regs.vh"

module tb_csr_top;
    localparam [1:0] AXI_OKAY = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;
    localparam integer WAIT_LIMIT = 3000;
    localparam integer CYCLE_LIMIT = 250000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg s_axi_aresetn = 1'b0;
    reg [11:0] s_axi_awaddr = 12'b0;
    reg s_axi_awvalid = 1'b0;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata = 32'b0;
    reg [3:0] s_axi_wstrb = 4'b0;
    reg s_axi_wvalid = 1'b0;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready = 1'b0;
    reg [11:0] s_axi_araddr = 12'b0;
    reg s_axi_arvalid = 1'b0;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready = 1'b0;
    wire irq;

    wire [63:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire m_axi_awlock;
    wire [3:0] m_axi_awcache;
    wire [2:0] m_axi_awprot;
    wire [3:0] m_axi_awqos;
    wire m_axi_awvalid;
    wire m_axi_awready;
    wire [127:0] m_axi_wdata;
    wire [15:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_wready;
    reg [1:0] m_axi_bresp=0;
    reg m_axi_bvalid=0;
    wire m_axi_bready;
    wire [63:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arlock;
    wire [3:0] m_axi_arcache;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arqos;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [127:0] m_axi_rdata=0;
    reg [1:0] m_axi_rresp=0;
    reg m_axi_rlast=0;
    reg m_axi_rvalid=0;
    wire m_axi_rready;

    reg [31:0] dma_memory[0:8191];
    reg dma_hold_ar=0,dma_hold_b=0,dma_inject_rerr=0;
    reg dma_reading=0,dma_writing=0,dma_b_pending=0;
    integer dma_raddress=0,dma_waddress=0,dma_rleft=0,dma_wleft=0;
    integer dma_b_delay=0,dma_wait=0,dma_lane=0;
    reg [31:0] dma_status_value;
    assign m_axi_arready=!dma_reading&&!m_axi_rvalid&&!dma_hold_ar&&cycles%3!=0;
    assign m_axi_awready=!dma_writing&&!m_axi_bvalid&&!dma_b_pending&&cycles%5!=0;
    assign m_axi_wready=dma_writing&&cycles%3!=1;
    always @(posedge clk) begin
        if(!s_axi_aresetn) begin
            dma_reading<=0;dma_writing<=0;dma_b_pending<=0;
            m_axi_rvalid<=0;m_axi_bvalid<=0;m_axi_rresp<=0;m_axi_bresp<=0;m_axi_rlast<=0;
        end else begin
            if(m_axi_arvalid&&m_axi_arready) begin
                if(m_axi_arsize!=4||m_axi_arburst!=1||m_axi_arlen>7||
                   int'(m_axi_araddr[11:0])+(int'(m_axi_arlen)+1)*16>4096)
                    $fatal(1,"invalid DMA read burst");
                dma_reading<=1;dma_raddress<=int'(m_axi_araddr);dma_rleft<=int'(m_axi_arlen)+1;
            end
            if(dma_reading&&!m_axi_rvalid&&cycles%3!=0) begin
                m_axi_rvalid<=1;m_axi_rresp<=dma_inject_rerr?2'b10:2'b0;m_axi_rlast<=dma_rleft==1;
                for(integer item=0;item<4;item=item+1) m_axi_rdata[item*32+:32]<=dma_memory[dma_raddress/4+item];
            end
            if(m_axi_rvalid&&m_axi_rready) begin
                m_axi_rvalid<=0;dma_raddress<=dma_raddress+16;dma_rleft<=dma_rleft-1;
                if(m_axi_rlast) dma_reading<=0;
            end
            if(m_axi_awvalid&&m_axi_awready) begin
                if(m_axi_awsize!=4||m_axi_awburst!=1||m_axi_awlen>7||
                   int'(m_axi_awaddr[11:0])+(int'(m_axi_awlen)+1)*16>4096)
                    $fatal(1,"invalid DMA write burst");
                dma_writing<=1;dma_waddress<=int'(m_axi_awaddr);dma_wleft<=int'(m_axi_awlen)+1;
            end
            if(m_axi_wvalid&&m_axi_wready) begin
                if(m_axi_wlast!=(dma_wleft==1)) $fatal(1,"DMA WLAST mismatch");
                for(integer item=0;item<16;item=item+1)
                    if(m_axi_wstrb[item]) dma_memory[dma_waddress/4+item/4][(item%4)*8+:8]<=m_axi_wdata[item*8+:8];
                dma_waddress<=dma_waddress+16;dma_wleft<=dma_wleft-1;
                if(m_axi_wlast) begin dma_writing<=0;dma_b_pending<=1;dma_b_delay<=4;end
            end
            if(dma_b_pending&&!dma_hold_b) begin
                if(dma_b_delay>0) dma_b_delay<=dma_b_delay-1;
                else begin dma_b_pending<=0;m_axi_bvalid<=1;m_axi_bresp<=0;end
            end
            if(m_axi_bvalid&&m_axi_bready) m_axi_bvalid<=0;
        end
    end

    task dma_wait_done;
        begin
            dma_wait=0;dma_status_value=0;
            while(!dma_status_value[1]&&dma_wait<WAIT_LIMIT) begin
                axi_read(`CSR_DMA_REG_STATUS,1,dma_status_value,read_response);dma_wait=dma_wait+1;
            end
            if(!dma_status_value[1]||dma_status_value[0]||read_response!=AXI_OKAY)
                $fatal(1,"DMA completion timeout/status %h",dma_status_value);
        end
    endtask
    task dma_upload_then_read;
        begin
            host_tag_number = 16'h0042;
            expect_read(`CSR_DMA_REG_ID,32'h00010080);
            expect_write(`CSR_DMA_REG_TAG,32'h1234,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_TAG,32'h56,4'h1,1,AXI_OKAY);
            expect_read(`CSR_DMA_REG_TAG,32'h1256);
            expect_write(`CSR_DMA_REG_TAG,32'hffffffff,4'h0,2,AXI_OKAY);
            expect_read(`CSR_DMA_REG_TAG,32'h1256);
            expect_write(`CSR_DMA_REG_MODE,2,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_ERROR|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_IRQ,0,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_IRQ,1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_ADDR_LO,4096,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_COUNT,fixture_cols,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_BLOCK,host_block_number,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_TAG,16'h55aa,4'hf,0,AXI_OKAY);
            for(dma_lane=0;dma_lane<fixture_cols;dma_lane=dma_lane+1)
                dma_memory[1024+dma_lane]={{5{fixture_host_data[dma_lane*27+26]}},fixture_host_data[dma_lane*27+:27]};
            dma_hold_ar=1;
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_COUNT,1,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_CANCEL,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK,4'hf,0,AXI_SLVERR);
            axi_read(`CSR_DMA_REG_STATUS,2,dma_status_value,read_response);
            if(!dma_status_value[0]||dma_status_value[1]||!m_axi_arvalid) $fatal(1,"cancel abandoned DMA offer");
            dma_hold_ar=0;dma_wait_done;
            expect_read(`CSR_DMA_REG_ERROR,4);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_ERROR|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            dma_inject_rerr=1;
            expect_write(`CSR_DMA_REG_COUNT,fixture_cols+1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_DMA_REG_COUNT,fixture_cols,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_BLOCK,host_block_number+1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_DMA_REG_BLOCK,host_block_number,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_ERROR|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_OKAY);dma_wait_done;
            expect_read(`CSR_DMA_REG_ERROR,2);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK,4'hf,0,AXI_OKAY);dma_inject_rerr=0;
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_OKAY);dma_wait_done;
            expect_read(`CSR_DMA_REG_ERROR,0);expect_read(`CSR_DMA_REG_BYTES,fixture_cols*4);
            expect_read(`CSR_DMA_REG_READ_BEATS,(fixture_cols+3)/4);
            axi_read(`CSR_DMA_REG_CYCLES,1,read_value,read_response);
            $display("DMA_UPLOAD_CYCLES=%0d",read_value);
            axi_read(`CSR_DMA_REG_STATUS,1,dma_status_value,read_response);
            if(!irq||dma_status_value[4]) $fatal(1,"DMA IRQ or poison clear failed");
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            if(!irq) $fatal(1,"legacy ack stole DMA IRQ");
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK,4'hf,0,AXI_OKAY);
            if(irq) $fatal(1,"DMA ACK failed");
            expect_write(`CSR_HOST_REG_IRQ,1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_HOST_READ,4'hf,0,AXI_OKAY);
            check_host_response(0);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_HOST|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            $display("DMA_UPLOAD_PASS");
        end
    endtask
    task dma_download;
        begin
            for(dma_lane=0;dma_lane<16;dma_lane=dma_lane+1) dma_memory[2048+dma_lane]=32'h55aa55aa;
            expect_write(`CSR_HOST_REG_IRQ,0,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_MODE,1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_ADDR_LO,8192,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_COUNT,fixture_cols+1,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_ERROR|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            expect_write(`CSR_DMA_REG_COUNT,fixture_cols-1,4'hf,0,AXI_OKAY);
            dma_hold_b=1;
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_START,4'hf,0,AXI_SLVERR);
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START,4'hf,0,AXI_SLVERR);
            dma_hold_b=0;dma_wait_done;
            expect_read(`CSR_DMA_REG_ERROR,0);expect_read(`CSR_DMA_REG_BYTES,(fixture_cols-1)*4);
            expect_read(`CSR_DMA_REG_WRITE_BEATS,(fixture_cols+2)/4);
            axi_read(`CSR_DMA_REG_CYCLES,1,read_value,read_response);
            $display("DMA_DOWNLOAD_CYCLES=%0d",read_value);
            for(dma_lane=0;dma_lane<fixture_cols-1;dma_lane=dma_lane+1)
                if(dma_memory[2048+dma_lane]!=={{5{fixture_host_data[dma_lane*27+26]}},fixture_host_data[dma_lane*27+:27]})
                    $fatal(1,"DMA DDR result mismatch lane=%0d",dma_lane);
            if(dma_memory[2048+fixture_cols-1]!==32'h55aa55aa) $fatal(1,"DMA partial WSTRB clobbered tail");
            if(!irq) $fatal(1,"DMA download IRQ missing");
            expect_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_ERROR|`CSR_HOST_ACK_IRQ,4'hf,0,AXI_OKAY);
            expect_write(`CSR_HOST_REG_IRQ,1,4'hf,0,AXI_OKAY);
            $display("DMA_DOWNLOAD_PASS");
        end
    endtask

    csr_top dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(3'b0),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(3'b0),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .irq(irq),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    integer cycles = 0;
    integer assertions = 0;
    integer fixture_fd;
    integer trace_fd;
    integer rc;
    integer fixture_rows;
    integer fixture_cols;
    integer fixture_revision;
    integer fixture_verified;
    integer fixture_program_count;
    integer fixture_constant_count;
    integer fixture_template_count;
    integer fixture_vector_count;
    integer fixture_record_count;
    integer fixture_host_count;
    integer record_number;
    integer lane_number;
    integer wait_number;
    integer host_block_number;
    integer host_mask_number;
    integer host_tag_number;
    integer expected_exp = -3;
    integer expected_job = 7;
    integer expected_tag = 16'h1234;
    integer phi_tag = 16'h0007;
    integer phi_generation = 3;
    reg [1023:0] fixture_path;
    reg [1023:0] trace_path;
    reg [2:0] record_kind;
    reg [15:0] record_index;
    reg [127:0] record_data;
    reg record_last;
    reg [31:0] item_control;
    reg [31:0] phi_shape;
    reg [31:0] start_storage;
    reg [31:0] read_value;
    reg [1:0] read_response;
    reg [1:0] write_response;
    reg [863:0] fixture_host_data;
    reg [31:0] fixture_host_word;
    reg [31:0] held_bresp;
    reg [31:0] held_rdata;
    reg [1:0] held_rresp;
    reg [31:0] done_cycles_lo;
    reg [31:0] done_cycles_hi;
    reg [31:0] status_value;
    reg [31:0] committed_job_tag;
    reg [31:0] committed_length;
    reg [31:0] result_data;
    reg [31:0] result_id;
    reg [31:0] result_meta;
    reg [31:0] result_job_tag;
    reg [31:0] result_format;
    reg [31:0] result_state;
    reg [31:0] host_response_control;
    reg [31:0] host_response_mask;
    reg [31:0] host_response_tag_fault;
    reg [31:0] expected_control;
    reg [31:0] expected_item_control;
    reg [31:0] expected_phi_shape;
    reg [31:0] expected_host_control;
    reg [31:0] expected_result_control;

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles > CYCLE_LIMIT)
            $fatal(1, "watchdog cycles=%0d", cycles);
    end

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task reset_dut;
        begin
            s_axi_aresetn = 1'b0;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            s_axi_arvalid = 1'b0;
            s_axi_bready = 1'b0;
            s_axi_rready = 1'b0;
            repeat (4) tick;
            s_axi_aresetn = 1'b1;
            repeat (4) tick;
            if (s_axi_bvalid || s_axi_rvalid)
                $fatal(1, "reset left AXI response outstanding");
        end
    endtask

    task drive_aw;
        input [11:0] address;
        begin
            @(negedge clk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            wait_number = 0;
            while (!s_axi_awready && wait_number < WAIT_LIMIT) begin
                @(posedge clk);
                #1;
                wait_number = wait_number + 1;
            end
            if (!s_axi_awready)
                $fatal(1, "AW timeout address=%h", address);
            @(posedge clk);
            #1;
            @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_awaddr = 12'b0;
        end
    endtask

    task drive_w;
        input [31:0] data_value;
        input [3:0] strobe;
        begin
            @(negedge clk);
            s_axi_wdata = data_value;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;
            wait_number = 0;
            while (!s_axi_wready && wait_number < WAIT_LIMIT) begin
                @(posedge clk);
                #1;
                wait_number = wait_number + 1;
            end
            if (!s_axi_wready)
                $fatal(1, "W timeout data=%h", data_value);
            @(posedge clk);
            #1;
            @(negedge clk);
            s_axi_wvalid = 1'b0;
            s_axi_wdata = 32'b0;
            s_axi_wstrb = 4'b0;
        end
    endtask

    task drive_aw_w_together;
        input [11:0] address;
        input [31:0] data_value;
        input [3:0] strobe;
        begin
            @(negedge clk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            s_axi_wdata = data_value;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;
            wait_number = 0;
            while ((!s_axi_awready || !s_axi_wready) && wait_number < WAIT_LIMIT) begin
                @(posedge clk);
                #1;
                wait_number = wait_number + 1;
            end
            if (!s_axi_awready || !s_axi_wready)
                $fatal(1, "AW/W together timeout address=%h", address);
            @(posedge clk);
            #1;
            @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            s_axi_awaddr = 12'b0;
            s_axi_wdata = 32'b0;
            s_axi_wstrb = 4'b0;
        end
    endtask

    task wait_b;
        input integer stall_cycles;
        output [1:0] response;
        begin
            wait_number = 0;
            while (!s_axi_bvalid && wait_number < WAIT_LIMIT) begin
                tick;
                wait_number = wait_number + 1;
            end
            if (!s_axi_bvalid)
                $fatal(1, "B timeout");
            response = s_axi_bresp;
            held_bresp = {30'b0, s_axi_bresp};
            repeat (stall_cycles) begin
                if (!s_axi_bvalid || {30'b0, s_axi_bresp} !== held_bresp)
                    $fatal(1, "B response changed while stalled");
                tick;
            end
            @(negedge clk);
            s_axi_bready = 1'b1;
            tick;
            @(negedge clk);
            s_axi_bready = 1'b0;
            if (s_axi_bvalid)
                $fatal(1, "B response did not retire");
        end
    endtask

    task axi_write;
        input [11:0] address;
        input [31:0] data_value;
        input [3:0] strobe;
        input integer order;
        input integer stall_cycles;
        output [1:0] response;
        begin
            if (order == 0) begin
                drive_aw(address);
                repeat (1) tick;
                drive_w(data_value, strobe);
            end else if (order == 1) begin
                drive_w(data_value, strobe);
                repeat (1) tick;
                drive_aw(address);
            end else begin
                drive_aw_w_together(address, data_value, strobe);
            end
            wait_b(stall_cycles, response);
        end
    endtask

    task drive_ar;
        input [11:0] address;
        begin
            @(negedge clk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            wait_number = 0;
            while (!s_axi_arready && wait_number < WAIT_LIMIT) begin
                @(posedge clk);
                #1;
                wait_number = wait_number + 1;
            end
            if (!s_axi_arready)
                $fatal(1, "AR timeout address=%h", address);
            @(posedge clk);
            #1;
            @(negedge clk);
            s_axi_arvalid = 1'b0;
            s_axi_araddr = 12'b0;
        end
    endtask

    task wait_r;
        input integer stall_cycles;
        output [31:0] data_value;
        output [1:0] response;
        begin
            wait_number = 0;
            while (!s_axi_rvalid && wait_number < WAIT_LIMIT) begin
                tick;
                wait_number = wait_number + 1;
            end
            if (!s_axi_rvalid)
                $fatal(1, "R timeout");
            data_value = s_axi_rdata;
            response = s_axi_rresp;
            held_rdata = s_axi_rdata;
            held_rresp = s_axi_rresp;
            repeat (stall_cycles) begin
                if (!s_axi_rvalid || s_axi_rdata !== held_rdata || s_axi_rresp !== held_rresp)
                    $fatal(1, "R response changed while stalled");
                tick;
            end
            @(negedge clk);
            s_axi_rready = 1'b1;
            tick;
            @(negedge clk);
            s_axi_rready = 1'b0;
            if (s_axi_rvalid)
                $fatal(1, "R response did not retire");
        end
    endtask

    task axi_read;
        input [11:0] address;
        input integer stall_cycles;
        output [31:0] data_value;
        output [1:0] response;
        begin
            drive_ar(address);
            wait_r(stall_cycles, data_value, response);
        end
    endtask

    task expect_write;
        input [11:0] address;
        input [31:0] data_value;
        input [3:0] strobe;
        input integer order;
        input [1:0] expected_response;
        begin
            axi_write(address, data_value, strobe, order, 2, write_response);
            if (write_response !== expected_response)
                $fatal(1, "write response address=%h got=%b want=%b", address, write_response, expected_response);
            assertions = assertions + 1;
        end
    endtask

    task expect_read;
        input [11:0] address;
        input [31:0] expected_data;
        begin
            axi_read(address, 2, read_value, read_response);
            if (read_response !== AXI_OKAY || read_value !== expected_data)
                $fatal(1, "read address=%h got=%b/%h want=%b/%h", address, read_response, read_value, AXI_OKAY, expected_data);
            assertions = assertions + 1;
        end
    endtask

    task wait_status_set;
        input [31:0] mask;
        begin
            wait_number = 0;
            status_value = 32'b0;
            while ((status_value & mask) != mask && wait_number < WAIT_LIMIT) begin
                axi_read(`CSR_HOST_REG_STATUS, 0, status_value, read_response);
                if (read_response !== AXI_OKAY)
                    $fatal(1, "status read response=%b", read_response);
                wait_number = wait_number + 1;
            end
            if ((status_value & mask) != mask)
                $fatal(1, "status mask timeout mask=%h value=%h", mask, status_value);
        end
    endtask

    task wait_status_clear;
        input [31:0] mask;
        begin
            wait_number = 0;
            status_value = 32'hffff_ffff;
            while ((status_value & mask) != 0 && wait_number < WAIT_LIMIT) begin
                axi_read(`CSR_HOST_REG_STATUS, 0, status_value, read_response);
                if (read_response !== AXI_OKAY)
                    $fatal(1, "status read response=%b", read_response);
                wait_number = wait_number + 1;
            end
            if ((status_value & mask) != 0)
                $fatal(1, "status clear timeout mask=%h value=%h", mask, status_value);
        end
    endtask

    task reset_partial_transactions;
        begin
            drive_aw(`CSR_HOST_REG_START_ROWS);
            reset_dut;
            drive_w(32'h0000_0007, 4'hf);
            reset_dut;

            drive_aw(`CSR_HOST_REG_START_ROWS);
            drive_w(32'h0000_0007, 4'hf);
            wait_number = 0;
            while (!s_axi_bvalid && wait_number < WAIT_LIMIT) begin
                tick;
                wait_number = wait_number + 1;
            end
            if (!s_axi_bvalid)
                $fatal(1, "B response did not appear before reset");
            reset_dut;

            drive_ar(`CSR_HOST_REG_ID);
            wait_number = 0;
            while (!s_axi_rvalid && wait_number < WAIT_LIMIT) begin
                tick;
                wait_number = wait_number + 1;
            end
            if (!s_axi_rvalid)
                $fatal(1, "R response did not appear before reset");
            reset_dut;
            assertions = assertions + 4;
        end
    endtask

    task load_image;
        begin
            rc = $fscanf(fixture_fd, "%d %d %d %d %d %d %d %d %d\n",
                fixture_rows, fixture_cols, fixture_revision, fixture_verified,
                fixture_program_count, fixture_constant_count, fixture_template_count,
                fixture_vector_count, fixture_record_count);
            if (rc != 9)
                $fatal(1, "fixture header rc=%0d", rc);
            expect_write(`CSR_HOST_REG_LOAD_PROGRAM_COUNT, fixture_program_count, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_LOAD_CONSTANT_COUNT, fixture_constant_count, 4'hf, 1, AXI_OKAY);
            expected_control = fixture_revision |
                (fixture_template_count << `CSR_HOST_LOAD_TEMPLATE_LSB) |
                (fixture_vector_count << `CSR_HOST_LOAD_VECTOR_LSB) |
                (fixture_verified << `CSR_HOST_LOAD_VERIFIED_LSB);
            expect_write(`CSR_HOST_REG_LOAD_CONTROL, expected_control, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_LOAD_BEGIN, 4'hf, 0, AXI_OKAY);
            for (record_number = 0; record_number < fixture_record_count; record_number = record_number + 1) begin
                rc = $fscanf(fixture_fd, "%h %h %h %h\n", record_kind, record_index, record_data, record_last);
                if (rc != 4)
                    $fatal(1, "fixture record=%0d rc=%0d", record_number, rc);
                item_control = record_kind |
                    (record_index << `CSR_HOST_LOAD_ITEM_INDEX_LSB) |
                    (record_last << `CSR_HOST_LOAD_ITEM_LAST_LSB);
                expect_write(`CSR_HOST_REG_LOAD_ITEM_CONTROL, item_control, 4'hf, record_number % 3, AXI_OKAY);
                expect_write(`CSR_HOST_REG_LOAD_ITEM0, record_data[31:0], 4'hf, (record_number + 1) % 3, AXI_OKAY);
                expect_write(`CSR_HOST_REG_LOAD_ITEM1, record_data[63:32], 4'hf, (record_number + 2) % 3, AXI_OKAY);
                expect_write(`CSR_HOST_REG_LOAD_ITEM2, record_data[95:64], 4'hf, record_number % 3, AXI_OKAY);
                expect_write(`CSR_HOST_REG_LOAD_ITEM3, record_data[127:96], 4'hf, (record_number + 1) % 3, AXI_OKAY);
                expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_LOAD_ITEM, 4'hf, record_number % 3, AXI_OKAY);
            end
            wait_status_set(`CSR_HOST_STATUS_LOAD_STATUS);
            expect_read(`CSR_HOST_REG_IMAGE_STATUS, 32'h0000_0003);
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_LOAD, 4'hf, 1, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_LOAD_STATUS);
        end
    endtask

    task configure_phi;
        begin
            expect_write(`CSR_HOST_REG_PHI_SEED, 32'h1234_5678, 4'hf, 0, AXI_OKAY);
            phi_shape = fixture_rows | (fixture_cols << `CSR_HOST_PHI_COLS_LSB);
            expect_write(`CSR_HOST_REG_PHI_SHAPE, phi_shape, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_KEY0, 32'h89ab_cdef, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_KEY1, 32'h0123_4567, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_KEY2, 32'h7654_3210, 4'hf, 4'hf, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_KEY3, 32'hfedc_ba98, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_GENERATION, phi_generation, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_JOB_TAG, phi_tag, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_FORMAT, 32'h1, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_PHI_BEGIN, 4'hf, 2, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_PHI_LOADING);
            wait_status_set(`CSR_HOST_STATUS_PHI_VALID);
            expect_read(`CSR_HOST_REG_PHI_STATUS, 32'h0000_0001);
            expect_read(`CSR_HOST_REG_PHI_IDENTITY, 32'h0001_0007);
            expect_read(`CSR_HOST_REG_PHI_GENERATION_READ, phi_generation);
            expect_read(`CSR_HOST_REG_PHI_SEED_READ, 32'h1234_5678);

            expect_write(`CSR_HOST_REG_PHI_SEED, 32'h8765_4321, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_GENERATION, 32'h0000_0004, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_PHI_JOB_TAG, 32'hbeef_0008, 4'hf, 2, AXI_OKAY);
            expect_read(`CSR_HOST_REG_PHI_IDENTITY, 32'h0001_0007);
            expect_read(`CSR_HOST_REG_PHI_GENERATION_READ, phi_generation);
            expect_read(`CSR_HOST_REG_PHI_SEED_READ, 32'h1234_5678);
        end
    endtask

    task stage_host_payload;
        begin
            rc = $fscanf(fixture_fd, "%d\n", fixture_host_count);
            if (rc != 1 || fixture_host_count != 1)
                $fatal(1, "host fixture count=%0d rc=%0d", fixture_host_count, rc);
            rc = $fscanf(fixture_fd, "%d %h %h\n", host_block_number, host_mask_number, fixture_host_data);
            if (rc != 3)
                $fatal(1, "host fixture rc=%0d", rc);
            expect_write(`CSR_HOST_REG_HOST_CONTROL, host_block_number, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_HOST_MASK, host_mask_number, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_HOST_TAG, 32'h0000_0042, 4'hf, 2, AXI_OKAY);
            for (lane_number = 0; lane_number < fixture_cols; lane_number = lane_number + 1) begin
                fixture_host_word = fixture_host_data[lane_number*27 +: 27];
                expect_write(`CSR_HOST_REG_HOST_DATA0 + lane_number*12'h004,
                    fixture_host_word, 4'hf, lane_number % 3, AXI_OKAY);
            end
        end
    endtask

    task check_host_response;
        input integer expected_write;
        begin
            wait_status_set(`CSR_HOST_STATUS_HOST_RESPONSE);
            expect_read(`CSR_HOST_REG_HOST_RESPONSE_CONTROL,
                (expected_write << 16) | host_block_number | (1 << 24));
            expect_read(`CSR_HOST_REG_HOST_RESPONSE_MASK, host_mask_number);
            expect_read(`CSR_HOST_REG_HOST_RESPONSE_TAG_FAULT, host_tag_number);
            for (lane_number = 0; lane_number < fixture_cols; lane_number = lane_number + 1) begin
                if (expected_write)
                    expect_read(`CSR_HOST_REG_HOST_RESPONSE_DATA0 + lane_number*12'h004, 32'b0);
                else
                    expect_read(`CSR_HOST_REG_HOST_RESPONSE_DATA0 + lane_number*12'h004,
                        fixture_host_data[lane_number*27 +: 27]);
            end
        end
    endtask

    task host_write_then_read;
        begin
            host_tag_number = 16'h0042;
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_HOST_WRITE, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_HOST_READ, 4'hf, 1, AXI_SLVERR);
            check_host_response(1);
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_HOST, 4'hf, 2, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_HOST_RESPONSE);
            expect_read(`CSR_HOST_REG_HOST_CONTROL, host_block_number);

            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_HOST_READ, 4'hf, 0, AXI_OKAY);
            check_host_response(0);
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_HOST, 4'hf, 1, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_HOST_RESPONSE);
        end
    endtask

    task configure_start;
        begin
            expect_write(`CSR_HOST_REG_START_ROWS, fixture_rows, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_COLS, fixture_cols, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_SCALE, 32'd32768, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_GENERATION, phi_generation, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_JOB_TAG, (expected_tag << 16) | expected_job, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_KEY0, 32'h89ab_cdef, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_KEY1, 32'h0123_4567, 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_KEY2, 32'h7654_3210, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_KEY3, 32'hfedc_ba98, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_FORMAT, 32'h1, 4'hf, 0, AXI_OKAY);
            start_storage = (7'h7d << `CSR_HOST_START_EXPONENT_LSB) | 2'd1;
            expect_write(`CSR_HOST_REG_START_STORAGE, start_storage, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_START_LIMIT, 32'd1000, 4'hf, 2, AXI_OKAY);
        end
    endtask

    task check_done_and_result;
        begin
            wait_status_set(`CSR_HOST_STATUS_DONE_VALID);
            expect_read(`CSR_HOST_REG_DONE_STATUS,
                (32'b1 << `CSR_HOST_STATUS_DONE_COMMITTED_LSB) |
                (32'b1 << `CSR_HOST_STATUS_DONE_VALID_LSB));
            expect_read(`CSR_HOST_REG_DONE_ITERATIONS, 32'b0);
            expect_read(`CSR_HOST_REG_DONE_SUPPORT, (expected_job << 16) | (1 << 8));
            expect_read(`CSR_HOST_REG_DONE_TAG, expected_tag);
            axi_read(`CSR_HOST_REG_DONE_CYCLES_LO, 2, done_cycles_lo, read_response);
            if (read_response !== AXI_OKAY)
                $fatal(1, "DONE cycles low response=%b", read_response);
            axi_read(`CSR_HOST_REG_DONE_CYCLES_HI, 2, done_cycles_hi, read_response);
            if (read_response !== AXI_OKAY || {done_cycles_hi, done_cycles_lo} == 0)
                $fatal(1, "DONE cycles invalid hi=%h lo=%h", done_cycles_hi, done_cycles_lo);
            expect_read(`CSR_HOST_REG_COMMITTED_LENGTH, fixture_cols);
            committed_job_tag = (expected_tag << 16) | expected_job;
            expect_read(`CSR_HOST_REG_COMMITTED_JOB_TAG, committed_job_tag);
            expect_read(`CSR_HOST_REG_COMMITTED_FORMAT, 32'h1);
            expect_read(`CSR_HOST_REG_COMMITTED_GENERATION, phi_generation);
            axi_read(`CSR_HOST_REG_COMMITTED_META, 2, read_value, read_response);
            if (read_response !== AXI_OKAY || !read_value[0])
                $fatal(1, "committed valid metadata=%h response=%b", read_value, read_response);
            assertions = assertions + 1;

            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_START, 4'hf, 0, AXI_SLVERR);
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_DONE | `CSR_HOST_ACK_IRQ, 4'hf, 1, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_DONE_VALID);

            expect_write(`CSR_HOST_REG_RESULT_CONTROL, (16'h6600 << 16), 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_RESULT_READ, 4'hf, 0, AXI_OKAY);
            wait_status_set(`CSR_HOST_STATUS_RESULT_RESPONSE);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_RESULT_READ, 4'hf, 1, AXI_SLVERR);
            axi_read(`CSR_HOST_REG_RESULT_DATA, 2, result_data, read_response);
            if (read_response !== AXI_OKAY || result_data[31:28] != 0 ||
                result_data[26:0] !== fixture_host_data[26:0])
                $fatal(1, "result data=%h response=%b", result_data, read_response);
            axi_read(`CSR_HOST_REG_RESULT_ID, 2, result_id, read_response);
            if (read_response !== AXI_OKAY || result_id !== (16'h6600 << 16))
                $fatal(1, "result identity=%h response=%b", result_id, read_response);
            axi_read(`CSR_HOST_REG_RESULT_META, 2, result_meta, read_response);
            if (read_response !== AXI_OKAY || result_meta[1:0] !== 2'd1 ||
                result_meta[8:2] !== 7'h7d || result_meta[19:9] !== fixture_cols)
                $fatal(1, "result metadata=%h response=%b", result_meta, read_response);
            expect_read(`CSR_HOST_REG_RESULT_JOB_TAG, committed_job_tag);
            expect_read(`CSR_HOST_REG_RESULT_FORMAT, 32'h0001_0001);
            expect_read(`CSR_HOST_REG_RESULT_STATE, 32'h0000_0100);
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_RESULT | `CSR_HOST_ACK_IRQ, 4'hf, 2, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_RESULT_RESPONSE);
        end
    endtask

    task cancel_and_fault_preserve;
        begin
            expect_write(`CSR_HOST_REG_PHI_SHAPE, (8 << `CSR_HOST_PHI_ROWS_LSB) | (8 << `CSR_HOST_PHI_COLS_LSB), 4'hf, 0, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_PHI_BEGIN, 4'hf, 1, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_PHI_LOADING);
            wait_status_set(`CSR_HOST_STATUS_PHI_VALID);
            configure_start;
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_START, 4'hf, 2, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_CANCEL, 4'hf, 0, AXI_OKAY);
            wait_status_set(`CSR_HOST_STATUS_CANCEL_SEEN);
            wait_status_clear(`CSR_HOST_STATUS_COMMAND_PENDING | `CSR_HOST_STATUS_BUSY | `CSR_HOST_STATUS_MAILBOX_VALID);
            expect_read(`CSR_HOST_REG_COMMITTED_LENGTH, fixture_cols);
            expect_read(`CSR_HOST_REG_COMMITTED_JOB_TAG, committed_job_tag);

            expect_write(`CSR_HOST_REG_START_ROWS, 32'd2, 4'hf, 1, AXI_OKAY);
            expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_START, 4'hf, 2, AXI_OKAY);
            wait_status_set(`CSR_HOST_STATUS_DONE_VALID);
            axi_read(`CSR_HOST_REG_DONE_STATUS, 2, read_value, read_response);
            if (read_response !== AXI_OKAY || read_value[3:0] == 0 || read_value[16] != 0)
                $fatal(1, "fault completion=%h response=%b", read_value, read_response);
            assertions = assertions + 1;
            expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_DONE | `CSR_HOST_ACK_IRQ, 4'hf, 0, AXI_OKAY);
            wait_status_clear(`CSR_HOST_STATUS_DONE_VALID);
            expect_read(`CSR_HOST_REG_COMMITTED_LENGTH, fixture_cols);
            expect_read(`CSR_HOST_REG_COMMITTED_JOB_TAG, committed_job_tag);
        end
    endtask

    initial begin
        rc = $value$plusargs("fixture=%s", fixture_path);
        rc = $value$plusargs("trace=%s", trace_path);
        fixture_fd = $fopen(fixture_path, "r");
        if (!fixture_fd)
            $fatal(1, "cannot open fixture=%s", fixture_path);
        trace_fd = $fopen(trace_path, "w");
        if (!trace_fd)
            $fatal(1, "cannot open trace=%s", trace_path);
        reset_dut;
        reset_partial_transactions;

        expect_read(`CSR_HOST_REG_ID, `CSR_HOST_VERSION);
        expect_write(`CSR_HOST_REG_START_ROWS, 32'h1122_3307, 4'hf, 0, AXI_OKAY);
        expect_read(`CSR_HOST_REG_START_ROWS, 32'h0000_0007);
        expect_write(`CSR_HOST_REG_START_ROWS, 32'h0000_0009, 4'h1, 4'h1, AXI_OKAY);
        expect_read(`CSR_HOST_REG_START_ROWS, 32'h0000_0009);
        expect_write(`CSR_HOST_REG_START_ROWS, 32'hffff_ffff, 4'h0, 2, AXI_OKAY);
        expect_read(`CSR_HOST_REG_START_ROWS, 32'h0000_0009);

        expected_control = 32'h0008_6102;
        expect_write(`CSR_HOST_REG_LOAD_CONTROL, expected_control, 4'hf, 0, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_LIMIT, 32'hcafe_babe, 4'hf, 1, AXI_OKAY);
        expect_read(`CSR_HOST_REG_LOAD_CONTROL, expected_control);
        expected_item_control = 32'h0008_002a;
        expect_write(`CSR_HOST_REG_LOAD_ITEM_CONTROL, expected_item_control, 4'hf, 2, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_LIMIT, 32'hdead_beef, 4'hf, 0, AXI_OKAY);
        expect_read(`CSR_HOST_REG_LOAD_ITEM_CONTROL, expected_item_control);
        expected_phi_shape = 32'h0007_0003;
        expect_write(`CSR_HOST_REG_PHI_SHAPE, expected_phi_shape, 4'hf, 1, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_LIMIT, 32'h1020_3040, 4'hf, 2, AXI_OKAY);
        expect_read(`CSR_HOST_REG_PHI_SHAPE, expected_phi_shape);
        expected_host_control = 32'h0001_0009;
        expect_write(`CSR_HOST_REG_HOST_CONTROL, expected_host_control, 4'hf, 0, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_LIMIT, 32'h5060_7080, 4'hf, 1, AXI_OKAY);
        expect_read(`CSR_HOST_REG_HOST_CONTROL, expected_host_control);
        expected_result_control = 32'h55aa_0007;
        expect_write(`CSR_HOST_REG_RESULT_CONTROL, expected_result_control, 4'hf, 2, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_LIMIT, 32'h90a0_b0c0, 4'hf, 0, AXI_OKAY);
        expect_read(`CSR_HOST_REG_RESULT_CONTROL, expected_result_control);

        expect_write(`CSR_HOST_REG_ID, 32'hffff_ffff, 4'hf, 0, AXI_SLVERR);
        expect_write(`CSR_HOST_REG_STATUS, 32'hffff_ffff, 4'hf, 1, AXI_SLVERR);
        expect_write(`CSR_HOST_REG_ID + 12'h001, 32'hffff_ffff, 4'hf, 2, AXI_SLVERR);
        expect_write(12'h3f0, 32'hffff_ffff, 4'hf, 0, AXI_SLVERR);
        expect_write(`CSR_HOST_REG_COMMAND, 32'h0000_0101, 4'hf, 1, AXI_SLVERR);
        axi_read(`CSR_HOST_REG_STATUS, 2, status_value, read_response);
        if (read_response !== AXI_OKAY || (status_value & (`CSR_HOST_STATUS_BUSY | `CSR_HOST_STATUS_COMMAND_PENDING)) != 0)
            $fatal(1, "reserved command side effect status=%h response=%b", status_value, read_response);
        expect_read(`CSR_HOST_REG_ERROR, `CSR_HOST_ERROR_STROBE |
            ((`CSR_HOST_REG_COMMAND & 12'h0ff) << 8) |
            (`CSR_HOST_REG_COMMAND << 16));
        expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_ERROR | `CSR_HOST_ACK_IRQ, 4'hf, 2, AXI_OKAY);

        expect_write(`CSR_HOST_REG_IRQ, 32'h1, 4'hf, 0, AXI_OKAY);
        expect_read(`CSR_HOST_REG_IRQ, 32'h1);
        load_image;
        if (!irq)
            $fatal(1, "load event did not raise enabled IRQ");
        expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_IRQ, 4'hf, 1, AXI_OKAY);
        if (irq)
            $fatal(1, "IRQ W1C did not clear pending");
        configure_phi;
        if (!irq)
            $fatal(1, "Phi event did not raise enabled IRQ");
        expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_IRQ, 4'hf, 2, AXI_OKAY);

        stage_host_payload;
        if($test$plusargs("dma")) dma_upload_then_read; else host_write_then_read;
        configure_start;
        expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_START, 4'hf, 0, AXI_OKAY);
        expect_write(`CSR_HOST_REG_START_ROWS, 32'd9, 4'hf, 1, AXI_SLVERR);
        expect_read(`CSR_HOST_REG_START_ROWS, fixture_rows);
        check_done_and_result;
        if($test$plusargs("dma")) dma_download;
        expect_write(`CSR_HOST_REG_HOST_CONTROL, host_block_number, 4'hf, 2, AXI_OKAY);
        expect_write(`CSR_HOST_REG_COMMAND, `CSR_HOST_COMMAND_HOST_READ, 4'hf, 0, AXI_OKAY);
        check_host_response(0);
        expect_write(`CSR_HOST_REG_ACK, `CSR_HOST_ACK_HOST | `CSR_HOST_ACK_IRQ, 4'hf, 1, AXI_OKAY);
        wait_status_clear(`CSR_HOST_STATUS_HOST_RESPONSE);
        cancel_and_fault_preserve;

        $fclose(fixture_fd);
        $fdisplay(trace_fd, "PASS csr_top_axi cycles=%0d assertions=%0d", cycles, assertions);
        $fclose(trace_fd);
        $display("PASS csr_top_axi cycles=%0d assertions=%0d", cycles, assertions);
        $display("EVIDENCE trace=%s", trace_path);
        $finish;
    end
endmodule
