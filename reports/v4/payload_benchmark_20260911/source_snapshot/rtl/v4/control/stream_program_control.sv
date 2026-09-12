`include "stream_interface.vh"

// Revision-one stream package loader and CALL/HALT control. No arithmetic here.
module stream_program_control (
    input wire clk, rst, cancel,
    input wire load_begin_valid,
    output wire load_begin_ready,
    input wire [7:0] load_begin_revision,
    input wire load_begin_verified,
    input wire [8:0] load_begin_program_count,
    input wire [4:0] load_begin_template_count,
    input wire load_program_valid,
    output wire load_program_ready,
    input wire [7:0] load_program_index,
    input wire [127:0] load_program_word,
    input wire load_program_last,
    input wire load_template_valid,
    output wire load_template_ready,
    input wire [3:0] load_template_id,
    input wire [5:0] load_template_lane,
    input wire [63:0] load_template_word,
    input wire load_template_last,
    output wire load_status_valid,
    input wire load_status_ready,
    output reg [3:0] load_status_fault,
    output reg image_valid,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] start_job, start_tag,
    input wire [7:0] start_fmt,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire [3:0] cmd_template,
    output wire [8:0] cmd_src_a, cmd_src_b, cmd_dst,
    output wire [7:0] cmd_frame_count,
    output wire [31:0] cmd_tail_mask, cmd_descriptor,
    output wire [2047:0] cmd_contexts,
    output wire [15:0] cmd_job, cmd_tag,
    output wire [7:0] cmd_fmt,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [3:0] rsp_fault,
    input wire [63:0] rsp_scalar,
    input wire [15:0] rsp_job, rsp_tag,
    input wire [7:0] rsp_fmt,
    output wire done_valid,
    input wire done_ready,
    output reg [3:0] done_fault, done_detail,
    output reg [63:0] done_scalar,
    output reg [15:0] done_job, done_tag,
    output reg [7:0] done_fmt,
    output wire [7:0] trace_pc,
    output wire [3:0] trace_template
);
    localparam IDLE=0, LOAD_PROGRAM=1, LOAD_TEMPLATE=2, FETCH=3, ISSUE=4, WAIT_RSP=5;
    reg [2:0] state;
    reg load_pending, done_pending;
    reg [8:0] program_count, load_pc;
    reg [4:0] template_count;
    reg [3:0] load_tid;
    reg [5:0] load_lane;
    reg [7:0] pc;
    reg [127:0] programs [0:255];
    reg [31:0] descriptors [0:15];
    reg [2047:0] contexts [0:15];
    reg [127:0] instruction;
    reg [31:0] descriptor_q;
    reg [2047:0] contexts_q;
    wire active = !rst && !cancel;
    wire idle = state == IDLE && !load_pending && !done_pending;
    wire [7:0] instruction_kind = instruction[`CSR_STREAM_PROGRAM_KIND_LSB +: `CSR_STREAM_PROGRAM_KIND_W];
    wire [3:0] instruction_template = instruction[`CSR_STREAM_PROGRAM_TEMPLATE_LSB +: `CSR_STREAM_PROGRAM_TEMPLATE_W];
    wire [1:0] output_kind = descriptor_q[`CSR_STREAM_DESC_OUTPUT_KIND_LSB +: `CSR_STREAM_DESC_OUTPUT_KIND_W];
    assign load_begin_ready = active && idle;
    assign start_ready = active && idle && image_valid && !load_begin_valid;
    assign load_program_ready = active && state == LOAD_PROGRAM;
    assign load_template_ready = active && state == LOAD_TEMPLATE;
    assign load_status_valid = active && load_pending;
    assign done_valid = active && done_pending;
    wire call_address_ok = address_ok(cmd_src_a,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_A_LSB]) &&
        address_ok(cmd_src_b,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_B_LSB]) &&
        address_ok(cmd_dst,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_DST_LSB]);
    assign cmd_valid = active && state == ISSUE && instruction_kind == `CSR_STREAM_KIND_CALL &&
        program_ok(instruction,template_count) && call_address_ok;
    assign rsp_ready = active && state == WAIT_RSP;
    assign cmd_template = instruction_template;
    assign cmd_src_a = instruction[`CSR_STREAM_PROGRAM_SRC_A_LSB +: `CSR_STREAM_PROGRAM_SRC_A_W];
    assign cmd_src_b = instruction[`CSR_STREAM_PROGRAM_SRC_B_LSB +: `CSR_STREAM_PROGRAM_SRC_B_W];
    assign cmd_dst = instruction[`CSR_STREAM_PROGRAM_DST_LSB +: `CSR_STREAM_PROGRAM_DST_W];
    assign cmd_frame_count = instruction[`CSR_STREAM_PROGRAM_FRAME_COUNT_LSB +: `CSR_STREAM_PROGRAM_FRAME_COUNT_W];
    assign cmd_tail_mask = instruction[`CSR_STREAM_PROGRAM_TAIL_MASK_LSB +: `CSR_STREAM_PROGRAM_TAIL_MASK_W];
    assign cmd_descriptor = descriptor_q;
    assign cmd_contexts = contexts_q;
    assign cmd_job = done_job;
    assign cmd_tag = done_tag;
    assign cmd_fmt = done_fmt;
    assign trace_pc = pc;
    assign trace_template = instruction_template;

    function automatic program_ok;
        input [127:0] word;
        input [4:0] count;
        reg [7:0] kind, frames;
        reg [3:0] tid;
        begin
            kind = word[`CSR_STREAM_PROGRAM_KIND_LSB +: `CSR_STREAM_PROGRAM_KIND_W];
            frames = word[`CSR_STREAM_PROGRAM_FRAME_COUNT_LSB +: `CSR_STREAM_PROGRAM_FRAME_COUNT_W];
            tid = word[`CSR_STREAM_PROGRAM_TEMPLATE_LSB +: `CSR_STREAM_PROGRAM_TEMPLATE_W];
            program_ok = 1'b0;
            if (kind == `CSR_STREAM_KIND_HALT)
                program_ok = (word >> `CSR_STREAM_PROGRAM_KIND_W) == 0;
            else if (kind == `CSR_STREAM_KIND_CALL)
                program_ok = word[`CSR_STREAM_PROGRAM_RESERVED_LSB +: `CSR_STREAM_PROGRAM_RESERVED_W] == 0 &&
                    {1'b0,tid} < count && frames != 0 && frames <= `CSR_STREAM_FRAME_LIMIT &&
                    word[`CSR_STREAM_PROGRAM_TAIL_MASK_LSB +: `CSR_STREAM_PROGRAM_TAIL_MASK_W] != 0;
        end
    endfunction

    function automatic descriptor_ok;
        input [63:0] word;
        begin
            descriptor_ok = word[63:32] == 0 &&
                word[`CSR_STREAM_DESC_RESERVED_LSB +: `CSR_STREAM_DESC_RESERVED_W] == 0 &&
                word[`CSR_STREAM_DESC_OUTPUT_KIND_LSB +: `CSR_STREAM_DESC_OUTPUT_KIND_W] <= `CSR_STREAM_OUTPUT_SUM_ACC &&
                (word[`CSR_STREAM_DESC_OUTPUT_KIND_LSB +: `CSR_STREAM_DESC_OUTPUT_KIND_W] == `CSR_STREAM_OUTPUT_LAST_ACC ||
                 word[`CSR_STREAM_DESC_SHIFT_LSB +: `CSR_STREAM_DESC_SHIFT_W] == 0);
        end
    endfunction

    function automatic context_ok;
        input [63:0] word;
        input [31:0] descriptor;
        reg [4:0] op;
        reg [1:0] kind;
        begin
            op = word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W];
            kind = descriptor[`CSR_STREAM_DESC_OUTPUT_KIND_LSB +: `CSR_STREAM_DESC_OUTPUT_KIND_W];
            context_ok = word[`CSR_STREAM_CONTEXT_RESERVED_LSB +: `CSR_STREAM_CONTEXT_RESERVED_W] == 0 &&
                ((kind == `CSR_STREAM_OUTPUT_EACH &&
                  (op == `CSR_PE_OP_MOV || op == `CSR_PE_OP_ADD || op == `CSR_PE_OP_SUB || op == `CSR_PE_OP_MUL)) ||
                 (kind != `CSR_STREAM_OUTPUT_EACH && op == `CSR_PE_OP_MAC));
        end
    endfunction

    function automatic address_ok;
        input [8:0] base;
        input [7:0] frames;
        input increment;
        reg [9:0] last_address;
        begin
            last_address = {1'b0,base} + (increment ? {2'b0,frames}-10'd1 : 10'd0);
            address_ok = last_address < `CSR_STREAM_PUBLIC_BLOCKS;
        end
    endfunction

    task load_fail;
        begin
            image_valid <= 1'b0;
            load_status_fault <= `CSR_STREAM_CTL_FAULT_LOAD;
            load_pending <= 1'b1;
            state <= IDLE;
        end
    endtask
    task finish;
        input [3:0] fault, detail;
        begin
            done_fault <= fault;
            done_detail <= detail;
            done_pending <= 1'b1;
            state <= IDLE;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; image_valid <= 0; load_pending <= 0; done_pending <= 0;
            load_status_fault <= 0; done_fault <= 0; done_detail <= 0; done_scalar <= 0;
            done_job <= 0; done_tag <= 0; done_fmt <= 0;
            program_count <= 0; template_count <= 0; load_pc <= 0; load_tid <= 0; load_lane <= 0;
            pc <= 0; instruction <= 0; descriptor_q <= 0; contexts_q <= 0;
        end else if (cancel) begin
            state <= IDLE; load_pending <= 0; done_pending <= 0;
            load_status_fault <= 0; done_fault <= 0; done_detail <= 0; done_scalar <= 0;
            done_job <= 0; done_tag <= 0; done_fmt <= 0;
            pc <= 0; instruction <= 0; descriptor_q <= 0; contexts_q <= 0;
            // Completed images persist. A begin already invalidated an incomplete image.
        end else begin
            if (load_pending && load_status_ready) load_pending <= 0;
            if (done_pending && done_ready) done_pending <= 0;
            case (state)
                IDLE: if (load_begin_valid && load_begin_ready) begin
                    image_valid <= 0; load_status_fault <= 0;
                    program_count <= load_begin_program_count;
                    template_count <= load_begin_template_count;
                    load_pc <= 0; load_tid <= 0; load_lane <= 0;
                    if (!load_begin_verified || load_begin_revision != `CSR_STREAM_REVISION ||
                        load_begin_program_count == 0 || load_begin_program_count > `CSR_STREAM_PROGRAM_DEPTH ||
                        load_begin_template_count == 0 || load_begin_template_count > `CSR_STREAM_TEMPLATE_DEPTH)
                        load_fail();
                    else state <= LOAD_PROGRAM;
                end else if (start_valid && start_ready) begin
                    pc <= 0; done_job <= start_job; done_tag <= start_tag; done_fmt <= start_fmt;
                    done_scalar <= 0; done_fault <= 0; done_detail <= 0;
                    if (start_fmt != `CSR_STREAM_FORMAT) finish(`CSR_STREAM_CTL_FAULT_FORMAT,0);
                    else state <= FETCH;
                end
                LOAD_PROGRAM: if (load_program_valid && load_program_ready) begin
                    if ({1'b0,load_program_index} != load_pc ||
                        load_program_last != (load_pc+9'd1 == program_count) ||
                        !program_ok(load_program_word,template_count)) load_fail();
                    else begin
                        programs[load_program_index] <= load_program_word;
                        if (load_program_last) state <= LOAD_TEMPLATE;
                        else load_pc <= load_pc+1'b1;
                    end
                end
                LOAD_TEMPLATE: if (load_template_valid && load_template_ready) begin
                    if (load_template_id != load_tid || load_template_lane != load_lane ||
                        load_template_last != ({1'b0,load_tid}+5'd1 == template_count && load_lane == 32) ||
                        (load_lane == 0 ? !descriptor_ok(load_template_word) :
                         !context_ok(load_template_word,descriptors[load_tid]))) load_fail();
                    else begin
                        if (load_lane == 0) descriptors[load_tid] <= load_template_word[31:0];
                        else contexts[load_tid][(int'(load_lane)-1)*64 +: 64] <= load_template_word;
                        if (load_template_last) begin
                            image_valid <= 1; load_status_fault <= 0; load_pending <= 1; state <= IDLE;
                        end else if (load_lane == 32) begin load_lane <= 0; load_tid <= load_tid+1'b1; end
                        else load_lane <= load_lane+1'b1;
                    end
                end
                FETCH: begin
                    instruction <= programs[pc];
                    descriptor_q <= descriptors[programs[pc][`CSR_STREAM_PROGRAM_TEMPLATE_LSB +: `CSR_STREAM_PROGRAM_TEMPLATE_W]];
                    contexts_q <= contexts[programs[pc][`CSR_STREAM_PROGRAM_TEMPLATE_LSB +: `CSR_STREAM_PROGRAM_TEMPLATE_W]];
                    state <= ISSUE;
                end
                ISSUE: begin
                    if (instruction_kind == `CSR_STREAM_KIND_HALT) finish(0,0);
                    else if (!program_ok(instruction,template_count)) finish(`CSR_STREAM_CTL_FAULT_PROGRAM,0);
                    else if (!address_ok(cmd_src_a,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_A_LSB]) ||
                             !address_ok(cmd_src_b,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_B_LSB]) ||
                             !address_ok(cmd_dst,cmd_frame_count,descriptor_q[`CSR_STREAM_DESC_INC_DST_LSB]))
                        finish(`CSR_STREAM_CTL_FAULT_RANGE,0);
                    else if (cmd_valid && cmd_ready) state <= WAIT_RSP;
                end
                WAIT_RSP: if (rsp_valid && rsp_ready) begin
                    if (rsp_job != done_job || rsp_tag != done_tag || rsp_fmt != done_fmt)
                        finish(`CSR_STREAM_CTL_FAULT_IDENTITY,0);
                    else if (rsp_fault != 0) finish(`CSR_STREAM_CTL_FAULT_KERNEL,rsp_fault);
                    else begin
                        if (output_kind == `CSR_STREAM_OUTPUT_SUM_ACC) done_scalar <= rsp_scalar;
                        if ({1'b0,pc}+9'd1 == program_count) finish(`CSR_STREAM_CTL_FAULT_PROGRAM,0);
                        else begin pc <= pc+1'b1; state <= FETCH; end
                    end
                end
                default: begin state <= IDLE; image_valid <= 0; end
            endcase
        end
    end
endmodule
