// D18F14 input ownership and normalization policy for the kernel's Y slot0.
module measurement_loader (
    input wire clk,rst,cancel,idle,
    input wire begin_valid,output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [15:0] begin_job,
    input wire [7:0] begin_fmt,
    input wire fill_valid,output wire fill_ready,
    input wire [1:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [575:0] fill_data,
    input wire fill_last,
    output wire loading,
    output reg valid,
    output reg [3:0] fault,
    output reg [7:0] rows,fmt,
    output reg [15:0] job,
    output wire host_begin_valid,input wire host_begin_ready,
    output wire [3:0] host_slot,
    output wire [7:0] host_length,
    output wire [15:0] host_job,host_tag,
    output wire [7:0] host_fmt,
    output wire host_fill_valid,input wire host_fill_ready,
    output wire [1:0] host_fill_block,
    output wire [31:0] host_fill_mask,
    output reg [863:0] host_fill_data,
    output wire host_fill_last,
    input wire [3:0] host_fault
);
    localparam [1:0] IDLE=0,FILL=1,CHECK=2;
    reg [1:0] state,block_idx;
    reg final_word,bad;
    reg [31:0] expected_mask;
    reg data_bad;
    reg signed [17:0] value;
    integer lane;
    wire active=!rst&&!cancel;
    wire header_good=begin_rows!=0 && begin_rows<=128 && begin_fmt==1;
    wire expected_last=(int'(block_idx)+1)*32>=int'(rows);
    wire word_bad=fill_block!=block_idx || fill_mask!=expected_mask || fill_last!=expected_last || data_bad;
    assign begin_ready=active&&idle&&state==IDLE&&host_begin_ready;
    assign host_begin_valid=begin_valid&&begin_ready&&header_good;
    assign host_slot=0;assign host_length=begin_rows;assign host_job=begin_job;assign host_tag=0;assign host_fmt=begin_fmt;
    assign fill_ready=active&&idle&&state==FILL&&host_fill_ready;
    assign host_fill_valid=fill_valid&&fill_ready;
    assign host_fill_block=fill_block;assign host_fill_mask=fill_mask;assign host_fill_last=fill_last;
    assign loading=state!=IDLE;
    always @* begin
        expected_mask=0;data_bad=0;host_fill_data=0;value=0;
        for(lane=0;lane<32;lane=lane+1)begin
            expected_mask[lane]=int'(block_idx)*32+lane<int'(rows);
            value=$signed(fill_data[lane*18+:18]);
            if(expected_mask[lane] ? value>8192 || value< -8192 : value!=0)data_bad=1;
            host_fill_data[lane*27+:27]={value[17],value,8'b0};
        end
    end
    always @(posedge clk)begin
        if(!active)begin state<=IDLE;block_idx<=0;final_word<=0;bad<=0;valid<=0;fault<=0;rows<=0;job<=0;fmt<=0;end
        else begin
            if(begin_valid&&begin_ready)begin
                valid<=0;fault<=header_good ? 4'd0 : 4'd1;rows<=begin_rows;job<=begin_job;fmt<=begin_fmt;
                bad<=0;block_idx<=0;state<=header_good ? FILL : IDLE;
            end
            if(fill_valid&&fill_ready)begin
                bad<=bad||word_bad;final_word<=expected_last;block_idx<=block_idx+1'b1;state<=CHECK;
            end
            if(state==CHECK)begin
                if(host_fault!=0)begin fault<=host_fault;valid<=0;state<=IDLE;end
                else if(final_word)begin fault<=bad ? 4'd2 : 4'd0;valid<=!bad;state<=IDLE;end
                else state<=FILL;
            end
        end
    end
endmodule
