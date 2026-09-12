`include "recovery_interface.vh"
module result_store (
    input wire clk,rst,cancel,abort,
    input wire begin_valid,output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [10:0] begin_length,
    input wire [1:0] begin_mode,
    input wire signed [6:0] begin_exponent,
    input wire begin_active_support,
    input wire [6:0] begin_support_count,
    input wire [959:0] begin_support,
    input wire [7:0] begin_status,
    input wire [15:0] begin_outer_iterations,begin_inner_iterations,begin_job,begin_tag,
    input wire [7:0] begin_fmt,
    input wire [127:0] begin_key,
    input wire [31:0] begin_generation,
    input wire fill_valid,output wire fill_ready,
    input wire [4:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [863:0] fill_data,
    input wire fill_last,
    input wire [15:0] fill_job,fill_tag,
    input wire [7:0] fill_fmt,
    input wire approve_valid,output wire approve_ready,
    input wire approve,
    input wire [15:0] approve_job,approve_tag,
    input wire [7:0] approve_fmt,
    output wire status_valid,input wire status_ready,
    output reg [3:0] status_fault,
    output reg status_committed,
    output reg committed_valid,
    output wire [7:0] committed_rows,
    output wire [10:0] committed_length,
    output wire [1:0] committed_mode,
    output wire signed [6:0] committed_exponent,
    output wire committed_active_support,
    output wire [6:0] committed_support_count,
    output wire [959:0] committed_support,
    output wire [7:0] committed_status,
    output wire [15:0] committed_outer_iterations,committed_inner_iterations,committed_job,committed_tag,
    output wire [7:0] committed_fmt,
    output wire [127:0] committed_key,
    output wire [31:0] committed_generation,
    input wire read_valid,output wire read_ready,
    input wire [9:0] read_index,
    input wire [15:0] read_tag,
    output wire read_rsp_valid,input wire read_rsp_ready,
    output wire [26:0] read_rsp_data,
    output reg [9:0] read_rsp_index,
    output reg [15:0] read_rsp_request_tag,
    output reg [3:0] read_rsp_fault,
    output reg [1:0] read_rsp_mode,
    output reg signed [6:0] read_rsp_exponent,
    output reg [10:0] read_rsp_length,
    output reg [15:0] read_rsp_job,read_rsp_tag,
    output reg [7:0] read_rsp_fmt
);
    localparam [2:0] IDLE=0,CHECK=1,FILL=2,SERIAL=3,APPROVE=4,STATUS=5;
    reg [2:0] state;
    reg bank,candidate_bank,read_bank,read_pending;
    (* ram_style="block" *) reg [26:0] words[0:2047];
    reg [26:0] ram_read;
    reg [7:0] rows[0:1],terminal_status[0:1],format[0:1];
    reg [10:0] length[0:1];
    reg [1:0] mode[0:1];
    reg signed [6:0] exponent[0:1];
    reg active_support[0:1];
    reg [6:0] support_count[0:1];
    reg [959:0] support[0:1];
    reg [15:0] outer_iterations[0:1],inner_iterations[0:1],job[0:1],tag[0:1];
    reg [127:0] key[0:1];
    reg [31:0] generation[0:1];
    reg [1023:0] seen;
    reg [6:0] check_slot;
    reg [4:0] expected_block,lane;
    reg [863:0] buffer;
    reg padding_bad;
    integer i;
    wire [9:0] word_index={expected_block,lane};
    wire [26:0] value=buffer[lane*27 +: 27];
    wire embedding_bad=mode[candidate_bank]==`CSR_RECOVERY_STORE_X24 ?
        (value[1:0]!=0 || value[26]!=value[25]) :
        (value[7:0]!=0 || value[26]!=value[25]);
    wire [9:0] support_index=support[candidate_bank][check_slot*10 +: 10];
    wire active=!rst&&!cancel&&!abort;
    // A pending read retains its old physical bank even after another publication.
    assign begin_ready=active && state==IDLE && !(read_rsp_valid && read_bank==!bank);
    assign fill_ready=active && state==FILL;
    assign approve_ready=active && state==APPROVE;
    assign status_valid=active && state==STATUS;
    assign read_rsp_valid=read_pending && !rst && !cancel;
    assign read_ready=!rst&&!cancel && (!read_rsp_valid || read_rsp_ready);
    assign read_rsp_data=read_rsp_fault==0 ? ram_read : 27'b0;
    assign committed_rows=committed_valid ? rows[bank] : 0;
    assign committed_length=committed_valid ? length[bank] : 0;
    assign committed_mode=committed_valid ? mode[bank] : 0;
    assign committed_exponent=committed_valid ? exponent[bank] : 0;
    assign committed_active_support=committed_valid && active_support[bank];
    assign committed_support_count=committed_valid ? support_count[bank] : 0;
    assign committed_support=committed_valid ? support[bank] : 0;
    assign committed_status=committed_valid ? terminal_status[bank] : 0;
    assign committed_outer_iterations=committed_valid ? outer_iterations[bank] : 0;
    assign committed_inner_iterations=committed_valid ? inner_iterations[bank] : 0;
    assign committed_job=committed_valid ? job[bank] : 0;
    assign committed_tag=committed_valid ? tag[bank] : 0;
    assign committed_fmt=committed_valid ? format[bank] : 0;
    assign committed_key=committed_valid ? key[bank] : 0;
    assign committed_generation=committed_valid ? generation[bank] : 0;

    function automatic [31:0] block_mask(input [10:0] size,input [4:0] number);
        integer j;
        begin
            block_mask=0;
            for(j=0;j<32;j=j+1) if(int'(number)*32+j<int'(size)) block_mask[j]=1;
        end
    endfunction
    task automatic fail(input [3:0] fault);
        begin
            status_fault<=fault;
            status_committed<=0;
            state<=STATUS;
        end
    endtask

    // One write and one synchronous read; RAM contents are never reset.
    always @(posedge clk) begin
        if(active && state==SERIAL && !embedding_bad)
            words[{candidate_bank,word_index}]<=value;
        if(read_valid && read_ready && committed_valid && {1'b0,read_index}<length[bank])
            ram_read<=words[{bank,read_index}];
    end
    always @(posedge clk) begin
        if(rst || cancel) begin
            state<=IDLE;
            status_fault<=0;
            status_committed<=0;
            read_pending<=0;
            read_rsp_fault<=`CSR_RECOVERY_RESULT_FAULT_UNINITIALIZED;
            read_rsp_index<=0;
            read_rsp_request_tag<=0;
            read_rsp_mode<=0;
            read_rsp_exponent<=0;
            read_rsp_length<=0;
            read_rsp_job<=0;
            read_rsp_tag<=0;
            read_rsp_fmt<=0;
            if(rst) begin
                bank<=0;
                committed_valid<=0;
            end
        end else begin
            if(read_rsp_valid && read_rsp_ready) read_pending<=0;
            if(read_valid && read_ready) begin
                read_pending<=1;
                read_bank<=bank;
                read_rsp_index<=read_index;
                read_rsp_request_tag<=read_tag;
                read_rsp_fault<=!committed_valid ? `CSR_RECOVERY_RESULT_FAULT_UNINITIALIZED :
                    {1'b0,read_index}>=length[bank] ? `CSR_RECOVERY_RESULT_FAULT_RANGE : 0;
                read_rsp_mode<=committed_mode;
                read_rsp_exponent<=committed_exponent;
                read_rsp_length<=committed_length;
                read_rsp_job<=committed_job;
                read_rsp_tag<=committed_tag;
                read_rsp_fmt<=committed_fmt;
            end
            if(abort) begin
                state<=IDLE;
                status_fault<=0;
                status_committed<=0;
            end else case(state)
                IDLE: if(begin_valid && begin_ready) begin
                    candidate_bank<=!bank;
                    rows[!bank]<=begin_rows;
                    length[!bank]<=begin_length;
                    mode[!bank]<=begin_mode;
                    exponent[!bank]<=begin_exponent;
                    active_support[!bank]<=begin_active_support;
                    support_count[!bank]<=begin_support_count;
                    support[!bank]<=begin_support;
                    terminal_status[!bank]<=begin_status;
                    outer_iterations[!bank]<=begin_outer_iterations;
                    inner_iterations[!bank]<=begin_inner_iterations;
                    job[!bank]<=begin_job;
                    tag[!bank]<=begin_tag;
                    format[!bank]<=begin_fmt;
                    key[!bank]<=begin_key;
                    generation[!bank]<=begin_generation;
                    status_fault<=0;
                    status_committed<=0;
                    expected_block<=0;
                    check_slot<=0;
                    seen<=0;
                    state<=CHECK;
                    if(begin_fmt!=`CSR_RECOVERY_LIMIT_FORMAT || begin_status>5 ||
                       (begin_mode!=`CSR_RECOVERY_STORE_X24 && begin_mode!=`CSR_RECOVERY_STORE_D18) ||
                       (!begin_active_support && (begin_support_count!=0 || begin_support!=0)))
                        fail(`CSR_RECOVERY_RESULT_FAULT_COMMAND);
                    else if(begin_rows==0 || begin_rows>`CSR_RECOVERY_LIMIT_MAX_ROWS ||
                            begin_length==0 || begin_length>`CSR_RECOVERY_LIMIT_MAX_LENGTH ||
                            begin_exponent< -31 || begin_exponent>31 ||
                            begin_support_count>`CSR_RECOVERY_LIMIT_MAX_SUPPORT || begin_support_count>begin_length)
                        fail(`CSR_RECOVERY_RESULT_FAULT_RANGE);
                end
                CHECK: begin
                    if(check_slot<support_count[candidate_bank]) begin
                        if({1'b0,support_index}>=length[candidate_bank] || seen[support_index])
                            fail(`CSR_RECOVERY_RESULT_FAULT_RANGE);
                        else seen[support_index]<=1;
                    end else if(support_index!=0) fail(`CSR_RECOVERY_RESULT_FAULT_ORDER);
                    if(check_slot==95) begin
                        if((check_slot<support_count[candidate_bank] && {1'b0,support_index}<length[candidate_bank] && !seen[support_index]) ||
                           (check_slot>=support_count[candidate_bank] && support_index==0)) state<=FILL;
                    end else check_slot<=check_slot+1'b1;
                end
                FILL: if(fill_valid) begin
                    padding_bad=0;
                    for(i=0;i<32;i=i+1) if(!fill_mask[i] && fill_data[i*27 +: 27]!=0) padding_bad=1;
                    if(fill_job!=job[candidate_bank] || fill_tag!=tag[candidate_bank] || fill_fmt!=format[candidate_bank])
                        fail(`CSR_RECOVERY_RESULT_FAULT_IDENTITY);
                    else if(fill_block!=expected_block || fill_mask!=block_mask(length[candidate_bank],expected_block) ||
                            fill_last!=((int'(expected_block)+1)*32>=int'(length[candidate_bank])) || padding_bad)
                        fail(`CSR_RECOVERY_RESULT_FAULT_ORDER);
                    else begin
                        buffer<=fill_data;
                        lane<=0;
                        state<=SERIAL;
                    end
                end
                SERIAL: begin
                    if(embedding_bad) fail(`CSR_RECOVERY_RESULT_FAULT_EMBEDDING);
                    else if({1'b0,word_index}+11'd1==length[candidate_bank]) state<=APPROVE;
                    else if(lane==31) begin
                        expected_block<=expected_block+1'b1;
                        state<=FILL;
                    end else lane<=lane+1'b1;
                end
                APPROVE: if(approve_valid) begin
                    if(approve_job!=job[candidate_bank] || approve_tag!=tag[candidate_bank] || approve_fmt!=format[candidate_bank])
                        fail(`CSR_RECOVERY_RESULT_FAULT_IDENTITY);
                    else if(!approve) fail(`CSR_RECOVERY_RESULT_FAULT_REJECTED);
                    else begin
                        bank<=candidate_bank;
                        committed_valid<=1;
                        status_committed<=1;
                        state<=STATUS;
                    end
                end
                STATUS: if(status_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
