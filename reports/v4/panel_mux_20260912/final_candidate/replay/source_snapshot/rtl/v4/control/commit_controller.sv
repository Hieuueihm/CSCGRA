`include "commit_interface.vh"
module commit_controller (
    input wire clk, rst, cancel,
    input wire begin_valid,
    output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [6:0] begin_count,
    input wire [959:0] begin_support,
    input wire [15:0] begin_job, begin_tag,
    input wire [7:0] begin_fmt,
    input wire signed [6:0] begin_exponent,
    input wire fill_valid,
    output wire fill_ready,
    input wire [1:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [863:0] fill_data,
    input wire fill_last,
    input wire [15:0] fill_job, fill_tag,
    input wire [7:0] fill_fmt,
    input wire decision_valid,
    output wire decision_ready,
    input wire decision_approve,
    input wire [15:0] decision_job, decision_tag,
    input wire [7:0] decision_fmt,
    output wire status_valid,
    input wire status_ready,
    output reg [3:0] status_fault,
    output reg status_committed,
    output reg [15:0] status_job, status_tag,
    output reg [7:0] status_fmt,
    output wire committed_valid,
    output wire [6:0] committed_count,
    output wire [7:0] committed_rows,
    input wire read_valid,
    output wire read_ready,
    input wire [6:0] read_slot,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire signed [23:0] rsp_x,
    output wire [9:0] rsp_index,
    output wire signed [6:0] rsp_exponent,
    output wire [15:0] rsp_job, rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire [3:0] rsp_fault
);
    reg candidate, complete, pending, checking;
    reg [6:0] support_slot;
    reg [959:0] support_shift;
    reg [1023:0] seen;
    reg [1:0] next_block;
    reg [6:0] count;
    reg [15:0] job, tag;
    reg [7:0] fmt;
    reg [3:0] begin_fault, fill_fault, decision_fault;
    reg [31:0] expected_mask;
    reg padding_bad, numeric_bad;
    reg signed [26:0] value;
    integer i;
    wire active=!rst && !cancel;
    wire expected_last=(int'(next_block)+1)*32>=int'(count);
    assign begin_ready=active && !candidate && !pending;
    assign decision_ready=active && candidate && !pending && !checking;
    assign fill_ready=active && candidate && !pending && !checking && !decision_valid;
    assign status_valid=active && pending;
    wire start=begin_valid && begin_ready && begin_fault==0;
    wire write_en=fill_valid && fill_ready && fill_fault==0;
    wire publish=decision_valid && decision_ready && decision_fault==0;

    always @* begin
        begin_fault=0; fill_fault=0; decision_fault=0; expected_mask=0; value=0;
        padding_bad=0; numeric_bad=0;
        if (begin_rows==0 || begin_rows>128 || begin_count>96 || begin_fmt!=`CSR_COMMIT_FORMAT ||
            begin_exponent < -31 || begin_exponent > 31) begin_fault=`CSR_COMMIT_FAULT_MODE;
        for (i=0;i<32;i=i+1) begin
            expected_mask[i]=int'(next_block)*32+i<int'(count);
            value=$signed(fill_data[i*27 +: 27]);
            if (!expected_mask[i] && value!=0) padding_bad=1;
            if (expected_mask[i] && (value[1:0]!=0 || value < -33554432 || value > 33554428)) numeric_bad=1;
        end
        if (fill_job!=job || fill_tag!=tag || fill_fmt!=fmt) fill_fault=`CSR_COMMIT_FAULT_IDENTITY;
        else if (complete || fill_block!=next_block || fill_mask!=expected_mask || fill_last!=expected_last || padding_bad)
            fill_fault=`CSR_COMMIT_FAULT_STREAM;
        else if (numeric_bad) fill_fault=`CSR_COMMIT_FAULT_NUMERIC;
        if (decision_job!=job || decision_tag!=tag || decision_fmt!=fmt) decision_fault=`CSR_COMMIT_FAULT_IDENTITY;
        else if (!complete) decision_fault=`CSR_COMMIT_FAULT_STREAM;
        else if (!decision_approve) decision_fault=`CSR_COMMIT_FAULT_CERTIFICATE;
    end
    always @(posedge clk) begin
        if (rst) begin
            candidate<=0; complete<=0; pending<=0; checking<=0; support_slot<=0; support_shift<=0; seen<=0; next_block<=0; count<=0;
            job<=0; tag<=0; fmt<=0;
            status_fault<=0; status_committed<=0; status_job<=0; status_tag<=0; status_fmt<=0;
        end else if (cancel) begin
            if (candidate) begin
                pending<=1; status_fault<=`CSR_COMMIT_FAULT_CANCEL; status_committed<=0;
                status_job<=job; status_tag<=tag; status_fmt<=fmt;
            end
            candidate<=0; complete<=0; checking<=0;
        end else begin
            if (pending && status_ready) begin
                pending<=0; status_fault<=0; status_committed<=0;
                status_job<=0; status_tag<=0; status_fmt<=0;
            end
            if (begin_valid && begin_ready) begin
                job<=begin_job; tag<=begin_tag; fmt<=begin_fmt;
                if (begin_fault!=0) begin
                    pending<=1; status_fault<=begin_fault; status_committed<=0;
                    status_job<=begin_job; status_tag<=begin_tag; status_fmt<=begin_fmt;
                end else begin
                    candidate<=1; complete<=begin_count==0; next_block<=0; count<=begin_count;
                    checking<=1; support_slot<=0; support_shift<=begin_support; seen<=0;
                end
            end
            if (checking) begin
                if ((support_slot<count && seen[support_shift[9:0]]) ||
                    (support_slot>=count && support_shift[9:0]!=0)) begin
                    candidate<=0; complete<=0; checking<=0; pending<=1;
                    status_fault<=`CSR_COMMIT_FAULT_SUPPORT; status_committed<=0;
                    status_job<=job; status_tag<=tag; status_fmt<=fmt;
                end else begin
                    if (support_slot<count) seen[support_shift[9:0]]<=1;
                    support_shift<={10'b0,support_shift[959:10]};
                    if (support_slot==95) checking<=0;
                    else support_slot<=support_slot+1'b1;
                end
            end
            if (fill_valid && fill_ready) begin
                if (fill_fault!=0) begin
                    candidate<=0; complete<=0; pending<=1; status_fault<=fill_fault; status_committed<=0;
                    status_job<=job; status_tag<=tag; status_fmt<=fmt;
                end else if (expected_last) complete<=1;
                else next_block<=next_block+1'b1;
            end
            if (decision_valid && decision_ready) begin
                candidate<=0; complete<=0; pending<=1;
                status_fault<=decision_fault; status_committed<=decision_fault==0;
                status_job<=job; status_tag<=tag; status_fmt<=fmt;
            end
        end
    end
    result_writeback store (
        .clk(clk),.rst(rst),.cancel(cancel),.start(start),.write_en(write_en),.publish(publish),
        .rows(begin_rows),.count(begin_count),.support(begin_support),.job(begin_job),.tag(begin_tag),
        .fmt(begin_fmt),.exponent(begin_exponent),.block(fill_block),.mask(fill_mask),.data(fill_data),
        .committed_valid(committed_valid),.committed_count(committed_count),.committed_rows(committed_rows),
        .read_valid(read_valid),.read_ready(read_ready),.read_slot(read_slot),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .rsp_x(rsp_x),.rsp_index(rsp_index),.rsp_exponent(rsp_exponent),.rsp_job(rsp_job),.rsp_tag(rsp_tag),
        .rsp_fmt(rsp_fmt),.rsp_fault(rsp_fault)
    );
endmodule
