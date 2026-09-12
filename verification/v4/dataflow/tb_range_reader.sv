module tb_range_reader;
    reg clk=0,rst=1,cancel=0;
    reg start_valid=0,a_used=0,b_used=0;
    wire start_ready;
    reg [8:0] a_base=0,b_base=0;
    reg [10:0] a_offset=0,b_offset=0;
    reg [5:0] frame=0;
    reg [31:0] a_select=0,b_select=0;
    reg [15:0] command_tag=0;
    wire provider_valid;
    reg provider_ready=1;
    wire [8:0] provider_address;
    wire [31:0] provider_mask;
    wire [15:0] provider_tag;
    reg provider_rsp_valid=0;
    wire provider_rsp_ready;
    reg [863:0] provider_rsp_data=0;
    reg [31:0] provider_rsp_mask=0;
    reg [15:0] provider_rsp_tag=0;
    reg [3:0] provider_rsp_fault=0;
    wire done_valid;
    reg done_ready=0;
    wire [1:0] done_fault;
    wire [863:0] a_data,b_data;
    reg corrupt_tag=0,corrupt_mask=0;
    integer requests,clock_count,lane;

    range_reader dut(
        .clk(clk),.rst(rst),.cancel(cancel),.start_valid(start_valid),.start_ready(start_ready),
        .source_a_used(a_used),.source_b_used(b_used),.source_a_base(a_base),.source_b_base(b_base),
        .source_a_offset(a_offset),.source_b_offset(b_offset),.frame_index(frame),.source_a_select(a_select),.source_b_select(b_select),.command_tag(command_tag),
        .provider_valid(provider_valid),.provider_ready(provider_ready),.provider_address(provider_address),.provider_mask(provider_mask),.provider_tag(provider_tag),
        .provider_rsp_valid(provider_rsp_valid),.provider_rsp_ready(provider_rsp_ready),.provider_rsp_data(provider_rsp_data),.provider_rsp_mask(provider_rsp_mask),.provider_rsp_tag(provider_rsp_tag),.provider_rsp_fault(provider_rsp_fault),
        .done_valid(done_valid),.done_ready(done_ready),.done_fault(done_fault),.source_a_data(a_data),.source_b_data(b_data));
    always #5 clk=~clk;
    function automatic [26:0] word_value(input [8:0] address,input integer word_lane);
        begin word_value=27'(int'(address)*100+word_lane+1); end
    endfunction
    function automatic [863:0] provider_word(input [8:0] address);
        integer data_lane;
        begin
            provider_word=0;
            for(data_lane=0;data_lane<32;data_lane=data_lane+1)
                provider_word[data_lane*27 +: 27]=word_value(address,data_lane);
        end
    endfunction
    always @(posedge clk) begin
        if(rst) begin provider_rsp_valid<=0;requests<=0;clock_count<=0;end
        else if(cancel) begin
            provider_rsp_valid<=0;
        end else begin
            clock_count<=clock_count+1;
            if(provider_rsp_valid&&provider_rsp_ready)begin provider_rsp_valid<=0;end
            if(provider_valid&&provider_ready)begin
                requests<=requests+1;
                provider_rsp_valid<=1;provider_rsp_data<=provider_word(provider_address);
                provider_rsp_mask<=corrupt_mask ? provider_mask&32'hfffffffe : provider_mask;
                provider_rsp_tag<=corrupt_tag ? provider_tag^16'h1 : provider_tag;
                provider_rsp_fault<=0;
            end
            if(clock_count>400)$fatal(1,"range reader timeout");
        end
    end
    task automatic launch_and_wait(input integer expected_fault);
        integer start_clock;
        begin
            wait(start_ready);start_clock=clock_count;start_valid=1;@(posedge clk);start_valid=0;
            while(!done_valid)@(posedge clk);
            if(done_fault!==expected_fault[1:0])$fatal(1,"range fault %0d want %0d",done_fault,expected_fault);
            // Held completion is part of the reader contract.
            repeat(2)begin @(posedge clk);if(!done_valid)$fatal(1,"range done not held");end
            done_ready=1;@(posedge clk);done_ready=0;
        end
    endtask
    task automatic check_linear(input source_a,input [8:0] base,input [10:0] offset,input [863:0] data,input [31:0] select_mask);
        integer check_lane,position;
        begin
            for(check_lane=0;check_lane<32;check_lane=check_lane+1)begin
                position=int'(offset)+check_lane;
                if(select_mask[check_lane]&&data[check_lane*27 +: 27]!==word_value(int'(base)+(position>>5),position&31))
                    $fatal(1,"range assembled lane %0d got %0d",check_lane,data[check_lane*27 +: 27]);
                if(!select_mask[check_lane]&&data[check_lane*27 +: 27]!==0)$fatal(1,"unselected lane %0d nonzero",check_lane);
            end
        end
    endtask
    initial begin
        repeat(3)@(posedge clk);rst=0;
        // Two unaligned sources consume two providers each and assemble every lane.
        a_used=1;b_used=1;a_base=10;b_base=20;a_offset=31;b_offset=33;frame=0;a_select=32'hffffffff;b_select=32'hffffffff;command_tag=16'h1234;
        launch_and_wait(0);
        check_linear(1,a_base,a_offset,a_data,a_select);check_linear(0,b_base,b_offset,b_data,b_select);
        if(requests!=4)$fatal(1,"unaligned provider count %0d",requests);
        // Equal logical providers with equal masks reuse the command-local cache.
        requests=0;a_base=40;b_base=40;a_offset=31;b_offset=31;a_select=32'hffffffff;b_select=32'hffffffff;command_tag=16'h4567;
        launch_and_wait(0);
        if(requests!=2)$fatal(1,"shared provider cache requests %0d",requests);
        // An unused B source is zero and makes no provider request, even if its base is invalid.
        requests=0;a_used=1;b_used=0;a_base=60;b_base=511;a_offset=0;b_offset=0;a_select=32'h00000001;b_select=0;command_tag=16'h0011;
        launch_and_wait(0);
        if(requests!=1||b_data!==0)$fatal(1,"unused source request/data failure requests=%0d",requests);
        // Widened capacity check must reject before the 9-bit address would wrap.
        requests=0;a_used=1;b_used=0;a_base=479;b_base=0;a_offset=32;b_offset=0;a_select=1;b_select=0;command_tag=16'h0012;
        launch_and_wait(1);
        if(requests!=0)$fatal(1,"overflow issued provider request");
        // Selected source capacity is also widened before the 11-bit offset can wrap.
        requests=0;a_used=1;b_used=0;a_base=0;a_offset=1000;frame=1;a_select=1;b_select=0;command_tag=16'h0016;
        launch_and_wait(1);
        if(requests!=0)$fatal(1,"source-capacity overflow issued provider request");
        frame=0;
        // Tags and masks are checked before exposing assembled data.
        requests=0;corrupt_tag=1;a_base=70;a_offset=0;a_select=1;command_tag=16'h0013;
        launch_and_wait(2);corrupt_tag=0;
        requests=0;corrupt_mask=1;command_tag=16'h0014;
        launch_and_wait(2);corrupt_mask=0;
        // Cancel drops an accepted partial transaction without a completion.
        a_base=80;a_offset=31;a_select=32'hffffffff;command_tag=16'h0015;wait(start_ready);start_valid=1;@(posedge clk);start_valid=0;
        while(!provider_valid)@(posedge clk);cancel=1;@(posedge clk);cancel=0;repeat(3)@(posedge clk);
        if(done_valid||provider_rsp_valid)$fatal(1,"cancel retained range transaction");
        $display("PASS requests=%0d clocks=%0d",requests,clock_count);
        $finish;
    end
endmodule