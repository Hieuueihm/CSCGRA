`timescale 1ns/1ps
`include "host_registers.vh"
`include "payload_dma_regs.vh"

module tb_payload_benchmark;
    localparam [1:0] AXI_OKAY = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;
    localparam integer WAIT_LIMIT = 1000000;
    localparam integer CYCLE_LIMIT = 8000000;

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


    integer bench_mode, bench_scale, bench_storage, bench_active, bench_status;
    integer bench_inner, bench_support_count, bench_residual_base;
    integer bench_begin, bench_setup, bench_load, bench_compute, bench_writeback;
    integer bench_mark, bench_index, bench_lane, bench_block, bench_words, bench_total;
    integer bench_dma_active=0, bench_dma_stall=0, bench_dma_reads=0, bench_dma_writes=0;
    integer bench_upload_active=0, bench_upload_stall=0;
    reg bench_dma_seen=0;
    reg [31:0] bench_x[0:1023];
    reg [26:0] bench_expected;
    reg [959:0] bench_support;
    reg [959:0] bench_expected_support;
    reg [63:0] bench_native;
    always @(posedge clk) begin
        if (dut.dma_busy) bench_dma_seen<=0;
        if (dut.dma_done && !dut.dma_busy && !bench_dma_seen) begin
            bench_dma_seen<=1;
            bench_dma_active<=bench_dma_active+dut.dma_cycles;
            bench_dma_stall<=bench_dma_stall+dut.dma_stalls;
            bench_dma_reads<=bench_dma_reads+dut.dma_read_beats;
            bench_dma_writes<=bench_dma_writes+dut.dma_write_beats;
        end
    end
    task bench_write(input [11:0] address,input [31:0] value);
        expect_write(address,value,4'hf,0,AXI_OKAY);
    endtask
    task bench_dma_finish;
        begin
            dma_wait=0;dma_status_value=0;
            while(!dma_status_value[1] && dma_wait<WAIT_LIMIT) begin
                axi_read(`CSR_DMA_REG_STATUS,0,dma_status_value,read_response);
                if(read_response!=AXI_OKAY) $fatal(1,"DMA status read");
                dma_wait=dma_wait+1;
            end
            if(!dma_status_value[1]||dma_status_value[0]) $fatal(1,"DMA completion timeout");
            expect_read(`CSR_DMA_REG_ERROR,0);
            if(!irq) $fatal(1,"DMA IRQ missing");
            bench_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_ACK);
        end
    endtask
    initial begin
        bench_mode=$test$plusargs("dma");
        rc=$value$plusargs("fixture=%s",fixture_path);
        rc=$value$plusargs("trace=%s",trace_path);
        fixture_fd=$fopen(fixture_path,"r"); trace_fd=$fopen(trace_path,"w");
        if(!fixture_fd||!trace_fd) $fatal(1,"benchmark file open");
        rc=$fscanf(fixture_fd,"%d %d %d %d %d %d %d\n",bench_scale,bench_storage,bench_active,
            bench_status,bench_inner,bench_support_count,bench_residual_base);
        if(rc!=7) $fatal(1,"benchmark metadata");
        reset_dut;
        bench_begin=cycles;
        load_image;
        bench_write(`CSR_HOST_REG_PHI_SEED,32'h12345678);
        bench_write(`CSR_HOST_REG_PHI_SHAPE,fixture_rows|(fixture_cols<<16));
        bench_write(`CSR_HOST_REG_PHI_KEY0,32'h89abcdef);
        bench_write(`CSR_HOST_REG_PHI_KEY1,32'h01234567);
        bench_write(`CSR_HOST_REG_PHI_KEY2,32'h76543210);
        bench_write(`CSR_HOST_REG_PHI_KEY3,32'hfedcba98);
        bench_write(`CSR_HOST_REG_PHI_GENERATION,3);
        bench_write(`CSR_HOST_REG_PHI_JOB_TAG,7);
        bench_write(`CSR_HOST_REG_PHI_FORMAT,1);
        bench_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_PHI_BEGIN);
        wait_status_set(`CSR_HOST_STATUS_PHI_VALID);
        bench_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_IRQ);
        bench_write(`CSR_HOST_REG_START_ROWS,fixture_rows);
        bench_write(`CSR_HOST_REG_START_COLS,fixture_cols);
        bench_write(`CSR_HOST_REG_START_SCALE,bench_scale);
        bench_write(`CSR_HOST_REG_START_GENERATION,3);
        bench_write(`CSR_HOST_REG_START_JOB_TAG,32'h12340007);
        bench_write(`CSR_HOST_REG_START_KEY0,32'h89abcdef);
        bench_write(`CSR_HOST_REG_START_KEY1,32'h01234567);
        bench_write(`CSR_HOST_REG_START_KEY2,32'h76543210);
        bench_write(`CSR_HOST_REG_START_KEY3,32'hfedcba98);
        bench_write(`CSR_HOST_REG_START_FORMAT,1);
        bench_write(`CSR_HOST_REG_START_STORAGE,bench_storage|(bench_active<<16));
        bench_write(`CSR_HOST_REG_START_LIMIT,1000000);
        bench_setup=cycles-bench_begin; bench_mark=cycles;
        rc=$fscanf(fixture_fd,"%d\n",fixture_host_count);
        if(rc!=1) $fatal(1,"preload count");
        for(bench_block=0;bench_block<fixture_host_count;bench_block=bench_block+1) begin
            rc=$fscanf(fixture_fd,"%d %h %h\n",host_block_number,host_mask_number,fixture_host_data);
            if(rc!=3) $fatal(1,"preload block");
            if(bench_mode) begin
                for(bench_lane=0;bench_lane<32;bench_lane=bench_lane+1)
                    dma_memory[1024+bench_block*32+bench_lane]={{5{fixture_host_data[bench_lane*27+26]}},fixture_host_data[bench_lane*27+:27]};
                if(bench_block==0) bench_words=host_block_number;
            end else begin
                bench_write(`CSR_HOST_REG_HOST_CONTROL,host_block_number);
                bench_write(`CSR_HOST_REG_HOST_MASK,host_mask_number);
                bench_write(`CSR_HOST_REG_HOST_TAG,66);
                for(bench_lane=0;bench_lane<32;bench_lane=bench_lane+1)
                    if(host_mask_number[bench_lane]) bench_write(`CSR_HOST_REG_HOST_DATA0+bench_lane*4,{5'b0,fixture_host_data[bench_lane*27+:27]});
                bench_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_HOST_WRITE);
                wait_status_set(`CSR_HOST_STATUS_HOST_RESPONSE);
                expect_read(`CSR_HOST_REG_HOST_RESPONSE_TAG_FAULT,66);
                bench_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_HOST|`CSR_HOST_ACK_IRQ);
            end
        end
        if(bench_mode) begin
            bench_write(`CSR_DMA_REG_IRQ,1);
            bench_write(`CSR_DMA_REG_ADDR_LO,4096);
            bench_write(`CSR_DMA_REG_COUNT,fixture_rows);
            bench_write(`CSR_DMA_REG_BLOCK,bench_words);
            bench_write(`CSR_DMA_REG_TAG,66);
            bench_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START);
            bench_dma_finish;
        end
        bench_load=cycles-bench_mark; bench_mark=cycles;
        bench_upload_active=bench_dma_active; bench_upload_stall=bench_dma_stall;
        bench_write(`CSR_HOST_REG_IRQ,1);
        bench_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_START);
        wait_status_set(`CSR_HOST_STATUS_DONE_VALID);
        bench_compute=cycles-bench_mark; bench_mark=cycles;
        if(!irq) $fatal(1,"core IRQ missing");
        expect_read(`CSR_HOST_REG_DONE_STATUS,(bench_status<<8)|32'h30000);
        expect_read(`CSR_HOST_REG_DONE_ITERATIONS,(bench_inner<<16)|8);
        expect_read(`CSR_HOST_REG_COMMITTED_LENGTH,fixture_cols|(bench_support_count<<12));
        axi_read(`CSR_HOST_REG_DONE_CYCLES_LO,0,done_cycles_lo,read_response);
        axi_read(`CSR_HOST_REG_DONE_CYCLES_HI,0,done_cycles_hi,read_response);
        bench_native={done_cycles_hi,done_cycles_lo}; bench_support=0;
        for(bench_index=0;bench_index<(bench_support_count*10+31)/32;bench_index=bench_index+1) begin
            axi_read(`CSR_HOST_REG_COMMITTED_SUPPORT0+bench_index*4,0,read_value,read_response);
            if(read_response!=AXI_OKAY) $fatal(1,"support response");
            bench_support[bench_index*32+:32]=read_value;
        end
        bench_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_DONE|`CSR_HOST_ACK_IRQ);
        if(bench_mode) begin
            bench_write(`CSR_HOST_REG_IRQ,0);
            bench_write(`CSR_DMA_REG_MODE,1);
            bench_write(`CSR_DMA_REG_ADDR_LO,8192);
            bench_write(`CSR_DMA_REG_COUNT,fixture_cols);
            bench_write(`CSR_DMA_REG_CONTROL,`CSR_DMA_START);
            bench_dma_finish;
        end else begin
            for(bench_index=0;bench_index<fixture_cols;bench_index=bench_index+1) begin
                bench_write(`CSR_HOST_REG_RESULT_CONTROL,(66<<16)|bench_index);
                bench_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_RESULT_READ);
                wait_status_set(`CSR_HOST_STATUS_RESULT_RESPONSE);
                axi_read(`CSR_HOST_REG_RESULT_DATA,0,read_value,read_response);
                if(read_response!=AXI_OKAY) $fatal(1,"result response");
                bench_x[bench_index]=read_value;
                bench_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_RESULT|`CSR_HOST_ACK_IRQ);
            end
        end
        bench_writeback=cycles-bench_mark; bench_total=cycles-bench_begin;
        $fdisplay(trace_fd,"PROFILE mode=%0d setup=%0d load=%0d compute=%0d writeback=%0d total=%0d native=%0d iterations=8 dma_active=%0d dma_stall=%0d read_beats=%0d write_beats=%0d upload_active=%0d upload_stall=%0d",
            bench_mode,bench_setup,bench_load,bench_compute,bench_writeback,bench_total,bench_native,
            bench_dma_active,bench_dma_stall,bench_dma_reads,bench_dma_writes,bench_upload_active,bench_upload_stall);
        for(bench_index=0;bench_index<fixture_cols;bench_index=bench_index+1) begin
            rc=$fscanf(fixture_fd,"%h\n",bench_expected);
            if(bench_mode) bench_x[bench_index]={5'b0,dma_memory[2048+bench_index][26:0]};
            if(rc!=1||bench_x[bench_index]!=={5'b0,bench_expected}) $fatal(1,"X mismatch %0d got=%h expected=%h",bench_index,bench_x[bench_index],bench_expected);
            $fdisplay(trace_fd,"X %0d %h",bench_index,bench_x[bench_index]);
        end
        rc=$fscanf(fixture_fd,"%h\n",bench_expected_support);
        if(rc!=1||bench_support!==bench_expected_support) $fatal(1,"support mismatch");
        $fdisplay(trace_fd,"SUPPORT %h",bench_support);
        for(bench_block=0;bench_block<(fixture_rows+31)/32;bench_block=bench_block+1) begin
            bench_words=fixture_rows-bench_block*32;
            if(bench_words>32) bench_words=32;
            bench_write(`CSR_HOST_REG_HOST_CONTROL,bench_residual_base+bench_block);
            bench_write(`CSR_HOST_REG_HOST_MASK,bench_words==32?32'hffffffff:(32'h1<<bench_words)-1);
            bench_write(`CSR_HOST_REG_HOST_TAG,66);
            bench_write(`CSR_HOST_REG_COMMAND,`CSR_HOST_COMMAND_HOST_READ);
            wait_status_set(`CSR_HOST_STATUS_HOST_RESPONSE);
            expect_read(`CSR_HOST_REG_HOST_RESPONSE_TAG_FAULT,66);
            for(bench_lane=0;bench_lane<bench_words;bench_lane=bench_lane+1) begin
                rc=$fscanf(fixture_fd,"%h\n",bench_expected);
                if(rc!=1) $fatal(1,"residual oracle missing");
                expect_read(`CSR_HOST_REG_HOST_RESPONSE_DATA0+bench_lane*4,{5'b0,bench_expected});
                $fdisplay(trace_fd,"V %0d %h",bench_block*32+bench_lane,bench_expected);
            end
            bench_write(`CSR_HOST_REG_ACK,`CSR_HOST_ACK_HOST|`CSR_HOST_ACK_IRQ);
        end
        $fdisplay(trace_fd,"PASS payload_benchmark");
        $display("PASS payload_benchmark mode=%0d native=%0d total=%0d",bench_mode,bench_native,bench_total);
        $fclose(trace_fd);$fclose(fixture_fd);$finish;
    end
endmodule
