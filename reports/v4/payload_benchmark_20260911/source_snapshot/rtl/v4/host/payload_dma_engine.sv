module payload_dma_engine (
    input wire clk, input wire rst, input wire cancel, input wire ack,
    input wire start, output wire start_ready, input wire direction_write,
    input wire [63:0] base_addr, input wire [10:0] element_count,
    input wire [8:0] block_base, input wire [15:0] tag,
    output wire busy, output reg done, output reg [3:0] error_code,
    output reg [31:0] completed_bytes, output reg [31:0] active_cycles,
    output reg [31:0] read_beats, output reg [31:0] write_beats,
    output reg [31:0] stall_cycles,
    output wire host_valid, input wire host_ready, output wire [8:0] host_block,
    output wire [31:0] host_mask, output reg [863:0] host_data,
    output wire [15:0] host_tag, input wire host_rsp_valid,
    output wire host_rsp_ready, input wire host_rsp_write,
    input wire [31:0] host_rsp_mask, input wire [15:0] host_rsp_tag,
    input wire [3:0] host_rsp_fault,
    output wire read_valid, input wire read_ready, output wire [9:0] read_index,
    output wire [15:0] read_tag, input wire read_rsp_valid,
    output wire read_rsp_ready, input wire [26:0] read_rsp_data,
    input wire [9:0] read_rsp_index, input wire [15:0] read_rsp_request_tag,
    input wire [3:0] read_rsp_fault,
    output wire [63:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid, input wire m_axi_arready,
    input wire [127:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast, input wire m_axi_rvalid, output wire m_axi_rready,
    output wire [63:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid, input wire m_axi_awready,
    output reg [127:0] m_axi_wdata, output reg [15:0] m_axi_wstrb,
    output wire m_axi_wlast, output wire m_axi_wvalid, input wire m_axi_wready,
    input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready
);
    localparam [3:0] IDLE=0, BLOCK=1, AR_PREP=2, AR_SEND=3, R_DATA=4,
        HOST_SEND=5, HOST_WAIT=6, READ_SEND=7, READ_WAIT=8,
        AW_PREP=9, AW_SEND=10, W_DATA=11, B_WAIT=12, FINISH=13;
    reg [3:0] state;
    reg abort_q, write_q;
    reg [63:0] address_q;
    reg [10:0] count_q, offset_q;
    reg [8:0] block_q;
    reg [15:0] tag_q;
    reg [5:0] words_q, buffered_q, result_q;
    reg [3:0] burst_q, beat_q;
    reg [1023:0] buffer_q;
    integer lane, word_index, burst_size, burst_words;
    reg bad_sign;
    wire abort_now = abort_q || cancel;
    wire [64:0] end_address = {1'b0,base_addr} + ((({54'b0,element_count}+65'd3)>>2)<<4);
    wire [10:0] end_block = {2'b0,block_base}+(({element_count}+11'd31)>>5);
    assign busy = state!=IDLE;
    assign start_ready = !rst && !busy && !done;
    assign host_valid = !rst && state==HOST_SEND;
    assign host_block = block_q+offset_q[10:5];
    assign host_mask = words_q==32 ? 32'hffffffff : (32'h1<<words_q)-1'b1;
    assign host_tag = tag_q;
    assign host_rsp_ready = !rst && state==HOST_WAIT;
    assign read_valid = !rst && state==READ_SEND;
    assign read_index = 10'(offset_q+result_q);
    assign read_tag = tag_q;
    assign read_rsp_ready = !rst && state==READ_WAIT;
    assign m_axi_araddr = address_q;
    assign m_axi_awaddr = address_q;
    assign m_axi_arlen = {4'b0,burst_q}-1'b1;
    assign m_axi_awlen = {4'b0,burst_q}-1'b1;
    assign m_axi_arsize = 3'd4;
    assign m_axi_awsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_awburst = 2'b01;
    assign m_axi_arvalid = !rst && state==AR_SEND;
    assign m_axi_awvalid = !rst && state==AW_SEND;
    assign m_axi_rready = !rst && state==R_DATA;
    assign m_axi_wvalid = !rst && state==W_DATA;
    assign m_axi_wlast = beat_q+1'b1==burst_q;
    assign m_axi_bready = !rst && state==B_WAIT;
    always @* begin
        burst_size = (int'(words_q)-int'(buffered_q)+3)/4;
        if(burst_size>8) burst_size=8;
        if(burst_size>(4096-int'(address_q[11:0]))/16)
            burst_size=(4096-int'(address_q[11:0]))/16;
        burst_words=int'(burst_q)*4;
        if(burst_words>int'(words_q)-int'(buffered_q)) burst_words=int'(words_q)-int'(buffered_q);
        host_data=0;
        for(lane=0;lane<32;lane=lane+1) host_data[lane*27+:27]=buffer_q[lane*32+:27];
        m_axi_wdata=0; m_axi_wstrb=0; bad_sign=0; word_index=0;
        for(lane=0;lane<4;lane=lane+1) begin
            word_index=int'(buffered_q)+int'(beat_q)*4+lane;
            if(word_index<int'(words_q) && word_index<32) begin
                m_axi_wdata[lane*32+:32]=buffer_q[word_index*32+:32];
                m_axi_wstrb[lane*4+:4]=4'hf;
                if(m_axi_rdata[lane*32+27+:5]!={5{m_axi_rdata[lane*32+26]}}) bad_sign=1;
            end
        end
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; done<=0; error_code<=0; completed_bytes<=0;
            active_cycles<=0; read_beats<=0; write_beats<=0; stall_cycles<=0;
            abort_q<=0; write_q<=0; address_q<=0; count_q<=0; offset_q<=0;
            block_q<=0; tag_q<=0; words_q<=0; buffered_q<=0; result_q<=0;
            burst_q<=0; beat_q<=0; buffer_q<=0;
        end else begin
            if(ack && !busy) begin done<=0; error_code<=0; end
            if(busy) begin
                active_cycles<=active_cycles+1'b1;
                if((m_axi_arvalid&&!m_axi_arready)||(m_axi_awvalid&&!m_axi_awready)||
                   (m_axi_wvalid&&!m_axi_wready)||(m_axi_rready&&!m_axi_rvalid)||
                   (m_axi_bready&&!m_axi_bvalid)||(host_valid&&!host_ready)||
                   (host_rsp_ready&&!host_rsp_valid)||(read_valid&&!read_ready)||
                   (read_rsp_ready&&!read_rsp_valid)) stall_cycles<=stall_cycles+1'b1;
                if(cancel) begin abort_q<=1; if(error_code==0) error_code<=4; end
            end
            case(state)
            IDLE: if(start && start_ready) begin
                done<=0; error_code<=0; completed_bytes<=0; active_cycles<=0;
                read_beats<=0; write_beats<=0; stall_cycles<=0; abort_q<=0;
                write_q<=direction_write; address_q<=base_addr; count_q<=element_count;
                offset_q<=0; block_q<=block_base; tag_q<=tag;
                if(base_addr[3:0]!=0 || element_count==0 || element_count>1024 || end_address[64] ||
                   (!direction_write && end_block>480)) begin error_code<=1; state<=FINISH; end
                else state<=BLOCK;
            end
            BLOCK: begin
                words_q<=count_q-offset_q>32 ? 6'd32 : 6'(count_q-offset_q);
                buffered_q<=0; result_q<=0; buffer_q<=0;
                state<=abort_now ? FINISH : write_q ? READ_SEND : AR_PREP;
            end
            AR_PREP: begin burst_q<=4'(burst_size); beat_q<=0; state<=abort_now?FINISH:AR_SEND; end
            AR_SEND: if(m_axi_arready) state<=R_DATA;
            R_DATA: if(m_axi_rvalid) begin
                read_beats<=read_beats+1'b1;
                if(m_axi_rresp!=0 || bad_sign || (m_axi_rlast!=(beat_q+1'b1==burst_q))) begin
                    abort_q<=1;
                    if(error_code==0) error_code<=m_axi_rresp!=0 ? 4'd2 : bad_sign ? 4'd7 : 4'd6;
                end
                if(!abort_now && m_axi_rresp==0 && !bad_sign && beat_q<burst_q)
                    for(integer item=0;item<4;item=item+1)
                        if(int'(buffered_q)+int'(beat_q)*4+item<int'(words_q))
                            buffer_q[(int'(buffered_q)+int'(beat_q)*4+item)*32+:32]<=m_axi_rdata[item*32+:32];
                if(m_axi_rlast) begin
                    address_q<=address_q+({60'b0,burst_q}<<4);
                    buffered_q<=buffered_q+6'(burst_words);
                    if(abort_now || m_axi_rresp!=0 || bad_sign || beat_q+1'b1!=burst_q) state<=FINISH;
                    else state<=int'(buffered_q)+burst_words>=int'(words_q) ? HOST_SEND : AR_PREP;
                end else if(beat_q<burst_q) beat_q<=beat_q+1'b1;
            end
            HOST_SEND: if(host_ready) state<=HOST_WAIT;
            HOST_WAIT: if(host_rsp_valid) begin
                if(host_rsp_fault!=0 || !host_rsp_write || host_rsp_tag!=tag_q || host_rsp_mask!=host_mask) begin
                    if(error_code==0) error_code<=host_rsp_fault!=0 ? 4'd5 : 4'd6;
                    state<=FINISH;
                end else begin
                    completed_bytes<=completed_bytes+({26'b0,words_q}<<2);
                    offset_q<=offset_q+words_q;
                    state<=abort_now || offset_q+words_q==count_q ? FINISH : BLOCK;
                end
            end
            READ_SEND: if(read_ready) state<=READ_WAIT;
            READ_WAIT: if(read_rsp_valid) begin
                if(read_rsp_fault!=0 || read_rsp_index!=read_index || read_rsp_request_tag!=tag_q) begin
                    if(error_code==0) error_code<=read_rsp_fault!=0 ? 4'd5 : 4'd6;
                    state<=FINISH;
                end else begin
                    buffer_q[result_q*32+:32]<={{5{read_rsp_data[26]}},read_rsp_data};
                    result_q<=result_q+1'b1;
                    state<=abort_now ? FINISH : result_q+1'b1==words_q ? AW_PREP : READ_SEND;
                end
            end
            AW_PREP: begin burst_q<=4'(burst_size); beat_q<=0; state<=abort_now?FINISH:AW_SEND; end
            AW_SEND: if(m_axi_awready) state<=W_DATA;
            W_DATA: if(m_axi_wready) begin
                write_beats<=write_beats+1'b1;
                if(m_axi_wlast) state<=B_WAIT; else beat_q<=beat_q+1'b1;
            end
            B_WAIT: if(m_axi_bvalid) begin
                if(m_axi_bresp!=0) begin if(error_code==0) error_code<=3; state<=FINISH; end
                else begin
                    completed_bytes<=completed_bytes+32'(burst_words*4);
                    address_q<=address_q+({60'b0,burst_q}<<4);
                    buffered_q<=buffered_q+6'(burst_words);
                    if(abort_now) state<=FINISH;
                    else if(int'(buffered_q)+burst_words==int'(words_q)) begin
                        offset_q<=offset_q+words_q;
                        state<=offset_q+words_q==count_q ? FINISH : BLOCK;
                    end else state<=AW_PREP;
                end
            end
            FINISH: begin done<=1; state<=IDLE; end
            default: begin error_code<=6; state<=FINISH; end
            endcase
        end
    end
endmodule
