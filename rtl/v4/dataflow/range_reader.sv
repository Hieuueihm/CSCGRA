// Command-local unaligned packed-vector reader for RANGE_TEMPLATE.
// At most two 32-lane providers are needed per selected source.  Response
// words are cached only within the active frame transaction; assembled A/B
// operands are held until the owner accepts done_valid.
module range_reader (
    input wire clk,
    input wire rst,
    input wire cancel,
    input wire start_valid,
    output wire start_ready,
    input wire source_a_used,
    input wire source_b_used,
    input wire [8:0] source_a_base,
    input wire [8:0] source_b_base,
    input wire [10:0] source_a_offset,
    input wire [10:0] source_b_offset,
    input wire [5:0] frame_index,
    input wire [31:0] source_a_select,
    input wire [31:0] source_b_select,
    input wire [15:0] command_tag,
    output wire provider_valid,
    input wire provider_ready,
    output wire [8:0] provider_address,
    output wire [31:0] provider_mask,
    output wire [15:0] provider_tag,
    input wire provider_rsp_valid,
    output wire provider_rsp_ready,
    input wire [863:0] provider_rsp_data,
    input wire [31:0] provider_rsp_mask,
    input wire [15:0] provider_rsp_tag,
    input wire [3:0] provider_rsp_fault,
    output wire done_valid,
    input wire done_ready,
    output reg [1:0] done_fault,
    output reg [863:0] source_a_data,
    output reg [863:0] source_b_data
);
    localparam [1:0] IDLE=0,ISSUE=1,WAIT=2,DONE=3;
    localparam [1:0] FAULT_NONE=0,FAULT_RANGE=1,FAULT_PROVIDER=2;
    reg [1:0] state;
    reg a_used,b_used;
    reg [8:0] a_base,b_base;
    reg [10:0] a_offset,b_offset;
    reg [5:0] frame;
    reg [31:0] a_select,b_select;
    reg [15:0] command_token;
    reg [2:0] phase;
    reg [8:0] expected_address;
    reg [31:0] expected_mask;
    reg [15:0] expected_tag;
    (* ram_style = "distributed" *) reg cache_valid [0:1];
    reg [8:0] cache_address [0:1];
    reg [31:0] cache_mask [0:1];
    reg [863:0] cache_data [0:1];
    reg cache_replace;
    integer lane,entry;

    function automatic position_overflow(
        input [10:0] offset,
        input [5:0] frame_value,
        input [31:0] select_mask
    );
        integer overflow_lane,position;
        begin
            position_overflow=0;
            for(overflow_lane=0;overflow_lane<32;overflow_lane=overflow_lane+1) begin
                position=int'(offset)+int'(frame_value)*32+overflow_lane;
                if(select_mask[overflow_lane]&&position>=1024)position_overflow=1;
            end
        end
    endfunction
    function automatic [31:0] mask_for(
        input [10:0] offset,
        input [5:0] frame_value,
        input [31:0] select_mask,
        input high_word
    );
        integer mask_lane,position,first_word;
        begin
            mask_for=0;
            first_word=(int'(offset)+int'(frame_value)*32)>>5;
            for(mask_lane=0;mask_lane<32;mask_lane=mask_lane+1) begin
                position=int'(offset)+int'(frame_value)*32+mask_lane;
                if(select_mask[mask_lane]&&(position>>5)==first_word+int'(high_word))
                    mask_for[position[4:0]]=1'b1;
            end
        end
    endfunction
    function automatic integer address_full(
        input [8:0] base,
        input [10:0] offset,
        input [5:0] frame_value,
        input high_word
    );
        integer first_word;
        begin
            first_word=(int'(offset)+int'(frame_value)*32)>>5;
            address_full=int'(base)+first_word+int'(high_word);
        end
    endfunction
    function automatic [8:0] address_for(
        input [8:0] base,
        input [10:0] offset,
        input [5:0] frame_value,
        input high_word
    );
        begin address_for=address_full(base,offset,frame_value,high_word); end
    endfunction
    function automatic [15:0] tag_for(input [15:0] base,input [2:0] phase_value);
        begin tag_for={base[15:3],phase_value}; end
    endfunction

    wire phase_is_a=phase<2;
    wire phase_high=phase[0];
    wire [8:0] current_base=phase_is_a ? a_base : b_base;
    wire [10:0] current_offset=phase_is_a ? a_offset : b_offset;
    wire [31:0] current_select=phase_is_a ? a_select : b_select;
    wire current_used=phase_is_a ? a_used : b_used;
    wire [31:0] current_mask=current_used ? mask_for(current_offset,frame,current_select,phase_high) : 0;
    wire [8:0] current_address=address_for(current_base,current_offset,frame,phase_high);
    wire [15:0] current_tag=tag_for(command_token,phase);
    reg cache_hit;
    reg [1:0] cache_hit_entry;
    always @* begin
        cache_hit=0;
        cache_hit_entry=0;
        for(entry=0;entry<2;entry=entry+1)
            if(cache_valid[entry]&&cache_address[entry]==current_address&&
               (cache_mask[entry]&current_mask)==current_mask) begin
                cache_hit=1;
                cache_hit_entry=entry[1:0];
            end
    end

    assign start_ready=state==IDLE;
    assign provider_valid=state==ISSUE&&current_mask!=0&&!cache_hit;
    assign provider_address=current_address;
    assign provider_mask=current_mask;
    assign provider_tag=current_tag;
    assign provider_rsp_ready=state==WAIT;
    assign done_valid=state==DONE;

    task automatic assemble_provider(
        input phase_a,
        input [8:0] address_value,
        input [863:0] data_value
    );
        integer assemble_lane,position;
        begin
            for(assemble_lane=0;assemble_lane<32;assemble_lane=assemble_lane+1) begin
                position=int'(phase_a ? a_offset : b_offset)+int'(frame)*32+assemble_lane;
                if((phase_a ? a_select[assemble_lane] : b_select[assemble_lane])&&
                   address_value==int'(phase_a ? a_base : b_base)+(position>>5)) begin
                    if(phase_a)source_a_data[assemble_lane*27 +: 27]<=data_value[position[4:0]*27 +: 27];
                    else source_b_data[assemble_lane*27 +: 27]<=data_value[position[4:0]*27 +: 27];
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if(rst||cancel) begin
            state<=IDLE;
            a_used<=0;b_used<=0;a_base<=0;b_base<=0;a_offset<=0;b_offset<=0;frame<=0;a_select<=0;b_select<=0;command_token<=0;
            phase<=0;expected_address<=0;expected_mask<=0;expected_tag<=0;done_fault<=0;source_a_data<=0;source_b_data<=0;cache_replace<=0;
            for(entry=0;entry<2;entry=entry+1)begin cache_valid[entry]<=0;cache_address[entry]<=0;cache_mask[entry]<=0;cache_data[entry]<=0;end
        end else begin
            case(state)
                IDLE: if(start_valid) begin
                    a_used<=source_a_used;b_used<=source_b_used;a_base<=source_a_base;b_base<=source_b_base;
                    a_offset<=source_a_offset;b_offset<=source_b_offset;frame<=frame_index;
                    a_select<=source_a_select;b_select<=source_b_select;command_token<=command_tag;
                    phase<=0;source_a_data<=0;source_b_data<=0;done_fault<=FAULT_NONE;cache_replace<=0;
                    for(entry=0;entry<2;entry=entry+1)cache_valid[entry]<=0;
                    // Only selected lanes require public capacity.  Widened
                    // arithmetic in address_for prevents pre-truncation wrap.
                    if((source_a_used&&position_overflow(source_a_offset,frame_index,source_a_select))||
                       (source_b_used&&position_overflow(source_b_offset,frame_index,source_b_select))||
                       (source_a_used&&source_a_select!=0&&address_full(source_a_base,source_a_offset,frame_index,0)>=480)||
                       (source_a_used&&mask_for(source_a_offset,frame_index,source_a_select,1)!=0&&address_full(source_a_base,source_a_offset,frame_index,1)>=480)||
                       (source_b_used&&source_b_select!=0&&address_full(source_b_base,source_b_offset,frame_index,0)>=480)||
                       (source_b_used&&mask_for(source_b_offset,frame_index,source_b_select,1)!=0&&address_full(source_b_base,source_b_offset,frame_index,1)>=480)) begin
                        done_fault<=FAULT_RANGE;
                        state<=DONE;
                    end else state<=ISSUE;
                end
                ISSUE: begin
                    if(current_mask==0) begin
                        if(phase==3)state<=DONE;
                        else phase<=phase+1'b1;
                    end else if(cache_hit) begin
                        assemble_provider(phase_is_a,current_address,cache_data[cache_hit_entry]);
                        if(phase==3)state<=DONE;
                        else phase<=phase+1'b1;
                    end else if(provider_valid&&provider_ready) begin
                        expected_address<=current_address;expected_mask<=current_mask;expected_tag<=current_tag;
                        state<=WAIT;
                    end
                end
                WAIT: if(provider_rsp_valid&&provider_rsp_ready) begin
                    if(provider_rsp_tag!=expected_tag||provider_rsp_fault!=0||provider_rsp_mask!=expected_mask) begin
                        done_fault<=FAULT_PROVIDER;
                        state<=DONE;
                    end else begin
                        assemble_provider(phase_is_a,expected_address,provider_rsp_data);
                        cache_valid[cache_replace]<=1;cache_address[cache_replace]<=expected_address;
                        cache_mask[cache_replace]<=expected_mask;cache_data[cache_replace]<=provider_rsp_data;cache_replace<=~cache_replace;
                        if(phase==3)state<=DONE;
                        else begin
                            phase<=phase+1'b1;
                            state<=ISSUE;
                        end
                    end
                end
                DONE: if(done_ready)state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule