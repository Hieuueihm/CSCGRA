`include "memory_defs.vh"
// Private S27 factors. The coordinate worker validates M/S holes before bank mapping.
// Fixed stride3 gives 384 logical words per bank; paired ports own disjoint halves.
module factor_store (
    input wire clk, rst, cancel,
    input wire begin_valid, output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [6:0] begin_cols,
    input wire [127:0] begin_key,
    input wire [31:0] begin_generation,
    input wire [15:0] begin_job,
    input wire [7:0] begin_fmt,
    // Append keeps the published prefix RAM intact and starts ordered fill at
    // begin_old_cols.  Existing begin_valid remains destructive INIT.
    input wire begin_append_valid,
    input wire [6:0] begin_old_cols,
    input wire fill_valid, output wire fill_ready,
    input wire [6:0] fill_col,
    input wire [1:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [863:0] fill_data,
    input wire fill_last,
    output reg loading, store_valid,
    output reg load_status_valid,
    input wire load_status_ready,
    output reg [3:0] load_status_fault,
    input wire req_valid, output wire req_ready,
    input wire req_write,
    input wire [31:0] req_mask,
    input wire [287:0] req_addr,
    input wire [863:0] req_data,
    input wire [127:0] req_key,
    input wire [31:0] req_generation,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    output wire rsp_valid, input wire rsp_ready,
    output wire rsp_write,
    output wire [863:0] rsp_data,
    output wire [31:0] rsp_mask,
    output wire [31:0] rsp_generation,
    output wire [15:0] rsp_job, rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire [3:0] rsp_fault
);
    reg [7:0] rows;
    reg [6:0] cols, target_cols, next_col;
    reg [1:0] next_block;
    reg [127:0] key;
    reg [31:0] generation,target_generation;
    reg [15:0] job;
    reg [7:0] fmt;
    reg [1:0] reserved, queued;
    reg head, tail, pipe_valid;
    reg [76:0] pipe_meta, queue_meta [0:1];
    reg [31:0] pipe_mask, queue_mask [0:1];
    reg [863:0] queue_data [0:1];
    wire [863:0] ram_data;
    wire active=!rst&&!cancel;
    wire pop=rsp_valid&&rsp_ready;
    wire take=req_valid&&req_ready;
    wire last_block=(int'(next_block)+1)*32>=int'(rows);
    wire last_word=last_block&&next_col+1==target_cols;
    reg [31:0] expected_mask;
    reg padding_bad;
    reg [3:0] request_fault;
    integer lane;
    wire fill_good=fill_col==next_col&&fill_block==next_block&&fill_mask==expected_mask&&
        fill_last==last_word&&!padding_bad;
    wire fill_take=fill_valid&&fill_ready;
    wire fill_write=fill_take&&fill_good;
    assign begin_ready=active&&!loading&&!load_status_valid&&reserved==0&&queued==0&&!pipe_valid;
    assign fill_ready=active&&loading;
    assign req_ready=active&&!loading&&!load_status_valid&&!begin_valid&&!begin_append_valid&&(reserved<2||pop);
    assign rsp_valid=active&&queued!=0;
    assign rsp_data=queue_data[head];
    assign rsp_mask=queue_mask[head];
    assign {rsp_write,rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt}=queue_meta[head];

    always @* begin
        expected_mask=0;
        padding_bad=0;
        request_fault=0;
        for(lane=0;lane<32;lane=lane+1) begin
            expected_mask[lane]=int'(next_block)*32+lane<int'(rows);
            if(!expected_mask[lane]&&fill_data[lane*27 +: 27]!=0) padding_bad=1;
        end
        if(!store_valid||req_key!=key||req_generation!=generation||req_job!=job||req_fmt!=fmt)
            request_fault=`CSR_MEM_FAULT_KEY;
        else for(lane=0;lane<32;lane=lane+1)
            if(req_mask[lane]&&req_addr[lane*9 +: 9]>=384) request_fault=`CSR_MEM_FAULT_RANGE;
    end

    genvar bank, port;
    generate for(bank=0;bank<16;bank=bank+1) begin : banks
        for(port=0;port<2;port=port+1) begin : ports
            localparam integer LOGICAL=bank+16*port;
            (* ram_style="block" *) reg [26:0] ram [0:511];
            wire [4:0] fill_lane=5'(LOGICAL-int'(next_col));
            wire [8:0] fill_address=9'((int'(next_block)*32+int'(fill_lane))*3+int'(next_col)/32);
            wire [8:0] request_address=req_addr[LOGICAL*9 +: 9];
            wire fill_enable=fill_write&&fill_mask[fill_lane];
            wire write_enable=fill_enable||(take&&req_write&&request_fault==0&&req_mask[LOGICAL]);
            wire [8:0] write_address=fill_enable ? fill_address : request_address;
            wire [26:0] write_data=fill_enable ? fill_data[int'(fill_lane)*27 +: 27] : req_data[LOGICAL*27 +: 27];
            reg [26:0] data;
            assign ram_data[LOGICAL*27 +: 27]=data;
            always @(posedge clk) begin
                if(write_enable) ram[write_address]<=write_data;
                if(take)
                    data<=!req_write&&request_fault==0&&req_mask[LOGICAL] ? ram[request_address] : 27'b0;
            end
        end
    end endgenerate

    // Credits reserve both the synchronous RAM stage and the held response queue.
    // Read/write responses have equal latency; failed writes never change the RAM.
    always @(posedge clk) begin
        if(!active) begin
            reserved<=0; queued<=0; head<=0; tail<=0; pipe_valid<=0;
            pipe_meta<=0; pipe_mask<=0;
        end else begin
            case({take,pop})
                2'b10: reserved<=reserved+1'b1;
                2'b01: reserved<=reserved-1'b1;
                default: reserved<=reserved;
            endcase
            case({pipe_valid,pop})
                2'b10: queued<=queued+1'b1;
                2'b01: queued<=queued-1'b1;
                default: queued<=queued;
            endcase
            pipe_valid<=take;
            if(take) begin
                pipe_meta<={req_write,request_fault,req_generation,req_job,req_tag,req_fmt};
                pipe_mask<=request_fault==0 ? req_mask : 32'b0;
            end
            if(pipe_valid) begin
                queue_data[tail]<=ram_data;
                queue_mask[tail]<=pipe_mask;
                queue_meta[tail]<=pipe_meta;
                tail<=~tail;
            end
            if(pop) head<=~head;
        end
    end

    // Initial publication is ordered and complete. Subsequent factors are private:
    // the service must cancel this store after any partially updated solve fails.
    always @(posedge clk) begin
        if(!active) begin
            loading<=0; store_valid<=0; load_status_valid<=0; load_status_fault<=0;
            rows<=0; cols<=0; target_cols<=0; key<=0; generation<=0; target_generation<=0; job<=0; fmt<=0;
            next_col<=0; next_block<=0;
        end else begin
            if(load_status_valid&&load_status_ready) load_status_valid<=0;
            if((begin_valid||begin_append_valid)&&begin_ready) begin
                store_valid<=0;
                next_col<=begin_append_valid ? begin_old_cols : 0; next_block<=0;
                load_status_fault<=0;
                if(begin_valid&&begin_append_valid) begin
                    loading<=0; load_status_valid<=1; load_status_fault<=`CSR_MEM_FAULT_STREAM;
                end else if(begin_rows==0||begin_rows>128||begin_cols==0||begin_cols>96||begin_fmt!=1||
                    (begin_append_valid&&(!store_valid||begin_old_cols==0||begin_old_cols!=cols||begin_old_cols>=begin_cols||begin_rows!=rows||begin_key!=key||begin_generation!=generation+1'b1||begin_job!=job||begin_fmt!=fmt))) begin
                    loading<=0; load_status_valid<=1; load_status_fault<=`CSR_MEM_FAULT_SHAPE;
                end else begin
                    loading<=1;
                    target_cols<=begin_cols;target_generation<=begin_generation;
                    if(!begin_append_valid) begin
                        rows<=begin_rows; cols<=begin_cols; key<=begin_key; job<=begin_job; fmt<=begin_fmt;
                    end
                end
            end
            if(fill_take) begin
                if(!fill_good) begin
                    loading<=0; store_valid<=0; load_status_valid<=1;
                    load_status_fault<=`CSR_MEM_FAULT_STREAM;
                end else if(last_word) begin
                    loading<=0; store_valid<=1; cols<=target_cols; generation<=target_generation; load_status_valid<=1; load_status_fault<=0;
                end else if(last_block) begin
                    next_col<=next_col+1'b1; next_block<=0;
                end else next_block<=next_block+1'b1;
            end
        end
    end
endmodule

