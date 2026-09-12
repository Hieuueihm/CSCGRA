`include "memory_defs.vh"
module phi_reader (
    input wire clk, rst, cancel,
    input wire cache_valid,
    input wire [127:0] cache_key,
    input wire [31:0] cache_generation,
    input wire [15:0] cache_job,
    input wire [7:0] cache_fmt,
    input wire req_valid,
    output wire req_ready,
    input wire [31:0] req_mask,
    input wire [287:0] req_addr,
    input wire [127:0] req_key,
    input wire [31:0] req_generation,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    output wire rd_valid,
    input wire rd_ready,
    output wire [7:0] rd_mask,
    output wire [71:0] rd_addr,
    output wire [31:0] rd_generation,
    output wire [15:0] rd_tag,
    input wire cache_rsp_valid,
    output wire cache_rsp_ready,
    input wire [255:0] cache_rsp_signs, cache_rsp_masks,
    input wire [7:0] cache_rsp_mask,
    input wire [31:0] cache_rsp_generation,
    input wire [15:0] cache_rsp_tag,
    input wire [3:0] cache_rsp_fault,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [575:0] rsp_data,
    output wire [255:0] rsp_masks,
    output wire [31:0] rsp_mask,
    output wire [31:0] rsp_generation,
    output wire [15:0] rsp_job, rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire [3:0] rsp_fault
);
    // Two credits include queued commands, in-flight cache reads and held replies.
    // Invalid requests occupy an ordered credit but issue no cache read.
    reg [1:0] count;
    reg head,tail;
    reg [7:0] mask[0:1],fmt[0:1];
    reg [71:0] address[0:1];
    reg [31:0] generation[0:1];
    reg [15:0] job[0:1],tag[0:1];
    reg [3:0] fault[0:1];
    reg sent[0:1],done[0:1];
    reg [255:0] signs[0:1],masks[0:1];
    reg send_found,response_found,send_slot,response_slot;
    integer n,slot;
    wire active=!rst&&!cancel;
    wire pop=rsp_valid&&rsp_ready;
    wire take=req_valid&&req_ready;
    wire bad_key=!cache_valid||req_key!=cache_key||req_generation!=cache_generation||req_job!=cache_job||req_fmt!=cache_fmt;
    wire bad_range=req_mask[31:8]!=0||req_addr[287:72]!=0;
    wire bad_response_tag=cache_rsp_generation!=generation[response_slot]||cache_rsp_tag!=tag[response_slot];
    wire [3:0] response_fault=bad_response_tag ? `CSR_MEM_FAULT_TAG :
        cache_rsp_fault!=0||cache_rsp_mask!=mask[response_slot] ? `CSR_MEM_FAULT_SOURCE : 4'd0;
    assign req_ready=active&&(count<2||pop);
    assign rd_valid=active&&send_found;
    assign rd_mask=mask[send_slot];assign rd_addr=address[send_slot];
    assign rd_generation=generation[send_slot];assign rd_tag=tag[send_slot];
    assign cache_rsp_ready=active&&response_found;
    wire direct_response=!done[head]&&response_found&&response_slot==head&&cache_rsp_valid;
    assign rsp_valid=active&&count!=0&&(done[head]||direct_response);
    assign rsp_fault=done[head] ? fault[head] : response_fault;
    // Fall through the synchronous cache reply; capture it if the consumer stalls.
    // This keeps two credits sufficient for consecutive requests without a third
    // response-register latency, while preserving stable held output.
    assign rsp_data=rsp_fault==0 ? {320'b0,(done[head] ? signs[head] : cache_rsp_signs)} : 576'b0;
    assign rsp_masks=rsp_fault==0 ? (done[head] ? masks[head] : cache_rsp_masks) : 256'b0;
    assign rsp_mask=rsp_fault==0 ? {24'b0,mask[head]} : 32'b0;
    assign rsp_generation=generation[head];assign rsp_job=job[head];assign rsp_tag=tag[head];assign rsp_fmt=fmt[head];
    always @* begin
        send_found=0;response_found=0;send_slot=head;response_slot=head;
        for(n=0;n<2;n=n+1)begin
            slot=(int'(head)+n)&1;
            if(n<int'(count))begin
                if(!send_found&&!sent[slot]&&!done[slot])begin send_found=1;send_slot=1'(slot);end
                if(!response_found&&sent[slot]&&!done[slot])begin response_found=1;response_slot=1'(slot);end
            end
        end
    end
    integer i;
    always @(posedge clk)begin
        if(!active)begin
            count<=0;head<=0;tail<=0;
            for(i=0;i<2;i=i+1)begin
                mask[i]<=0;fmt[i]<=0;address[i]<=0;generation[i]<=0;job[i]<=0;tag[i]<=0;
                fault[i]<=0;sent[i]<=0;done[i]<=0;signs[i]<=0;masks[i]<=0;
            end
        end else begin
            case({take,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(pop)head<=~head;
            if(rd_valid&&rd_ready)sent[send_slot]<=1;
            if(cache_rsp_valid&&cache_rsp_ready)begin
                done[response_slot]<=1;fault[response_slot]<=response_fault;
                signs[response_slot]<=response_fault==0 ? cache_rsp_signs : 256'b0;
                masks[response_slot]<=response_fault==0 ? cache_rsp_masks : 256'b0;
            end
            if(take)begin
                tail<=~tail;mask[tail]<=req_mask[7:0];fmt[tail]<=req_fmt;address[tail]<=req_addr[71:0];
                generation[tail]<=req_generation;job[tail]<=req_job;tag[tail]<=req_tag;
                sent[tail]<=0;done[tail]<=bad_key||bad_range;
                fault[tail]<=bad_key ? `CSR_MEM_FAULT_KEY : bad_range ? `CSR_MEM_FAULT_RANGE : 4'd0;
                signs[tail]<=0;masks[tail]<=0;
            end
        end
    end
endmodule
