`include "control_defs.vh"

module context_sequencer (
    input wire clk, rst, cancel,
    input wire start_valid,
    output wire start_ready,
    input wire image_ready,
    input wire [31:0] image_generation,
    input wire [7:0] start_pc,
    input wire [31:0] start_limit,
    input wire [15:0] start_job,
    input wire [7:0] start_fmt,
    input wire [2:0] predicates,
    output wire idle,
    output wire fetch_valid,
    input wire fetch_ready,
    output wire [7:0] fetch_pc,
    output wire [31:0] fetch_generation,
    input wire mem_valid,
    output wire mem_ready,
    input wire [2047:0] mem_words,
    input wire [255:0] mem_control,
    input wire [7:0] mem_pc,
    input wire [31:0] mem_generation,
    input wire [3:0] mem_fault,
    output wire addr_valid,
    input wire addr_ready,
    output wire [2:0] addr_mode,
    output wire [23:0] addr_value,
    output wire [15:0] addr_stride,
    input wire addr_rsp_valid,
    output wire addr_rsp_ready,
    input wire addr_rsp_fault,
    input wire [15:0] addr_rsp_job, addr_rsp_tag,
    output wire exec_valid,
    input wire exec_ready,
    output wire [2047:0] exec_words,
    output wire [15:0] exec_job, exec_tag,
    output wire [7:0] exec_fmt,
    output wire exec_last, exec_cancel,
    input wire exec_rsp_valid,
    output wire exec_rsp_ready,
    input wire exec_rsp_fault,
    input wire [15:0] exec_rsp_job, exec_rsp_tag,
    input wire [7:0] exec_rsp_fmt,
    output wire done_valid,
    input wire done_ready,
    output reg [3:0] done_fault,
    output reg [7:0] pc,
    output reg [31:0] retired
);
    localparam integer LD = `CSR_CTL_LOOP_DEPTH;
    localparam integer LW = $clog2(LD+1);
    localparam [3:0] IDLE = 0, FETCH = 1, READ = 2, CHECK = 3, WAIT_PRED = 4,
                     ADDRESS = 5, ADDR_WAIT = 6, ISSUE = 7, RETIRE = 8, DONE = 9;
    reg [3:0] state;
    reg [2047:0] words;
    reg [255:0] control;
    reg [31:0] generation, limit;
    reg [15:0] job, tag;
    reg [7:0] fmt, next_pc;
    reg [LW-1:0] depth;
    reg [7:0] loop_pc [0:LD-1];
    reg [15:0] remaining [0:LD-1];
    reg push_loop, end_loop, halt_q;
    wire [3:0] kind, dec_fault;
    wire [15:0] count;
    wire [7:0] loop_target, branch_target;
    wire [2:0] predicate;
    wire active = !rst && !cancel;
    wire start_take = start_valid && start_ready;
    wire exec_bad_tag = exec_rsp_job != job || exec_rsp_tag != tag || exec_rsp_fmt != fmt;
    wire exec_failure = state == RETIRE && exec_rsp_valid && (exec_bad_tag || exec_rsp_fault);
    wire addr_bad_tag = addr_rsp_job != job || addr_rsp_tag != tag;
    reg [3:0] flow_fault;
    reg [8:0] successor;
    reg push_next;
    reg [$clog2(LD)-1:0] top_slot;
    integer slot;

    function automatic pred_value;
        input [2:0] code, values;
        begin
            case (code)
                0: pred_value = 1'b1;
                1: pred_value = values[0];
                2: pred_value = values[1];
                3: pred_value = values[2];
                4: pred_value = !values[0];
                5: pred_value = !values[1];
                6: pred_value = !values[2];
                default: pred_value = 1'b0;
            endcase
        end
    endfunction

    control_decode decode (
        .word(control), .rev(8'(`CSR_CTL_REV)), .kind(kind), .count(count), .loop_target(loop_target),
        .branch_target(branch_target), .predicate(predicate), .address_mode(addr_mode),
        .address(addr_value), .stride(addr_stride), .fault(dec_fault)
    );
    assign idle = state == IDLE;
    assign start_ready = active && idle;
    assign fetch_valid = active && state == FETCH;
    assign fetch_pc = pc;
    assign fetch_generation = generation;
    assign mem_ready = active && state == READ;
    assign addr_valid = active && state == ADDRESS;
    assign addr_rsp_ready = active && state == ADDR_WAIT;
    assign exec_valid = active && state == ISSUE;
    assign exec_words = words;
    assign exec_job = job;
    assign exec_tag = tag;
    assign exec_fmt = fmt;
    assign exec_last = halt_q;
    assign exec_cancel = rst || cancel || start_take || (state == DONE && done_fault != 0);
    assign exec_rsp_ready = active && state == RETIRE && !exec_bad_tag && !exec_rsp_fault;
    assign done_valid = active && state == DONE;

    always @* begin
        top_slot = depth == 0 ? '0 : $clog2(LD)'(depth-1'b1);
        successor = {1'b0, pc} + 9'd1;
        push_next = 1'b0;
        flow_fault = dec_fault;
        if (kind == `CSR_CTL_KIND_HALT) begin
            successor = {1'b0, pc};
            if (depth != 0) flow_fault = `CSR_CTL_FAULT_LOOP;
        end
        if (kind == `CSR_CTL_KIND_BRANCH) begin
            if (depth != 0) flow_fault = `CSR_CTL_FAULT_LOOP;
            if (pred_value(predicate, predicates)) successor = {1'b0, branch_target};
        end
        if (kind == `CSR_CTL_KIND_LOOP_BEGIN) begin
            if ({1'b0, loop_target} != {1'b0, pc}+9'd1) flow_fault = `CSR_CTL_FAULT_LOOP;
            if (depth == 0 || loop_pc[top_slot] != pc) begin
                push_next = 1'b1;
                if (int'(depth) == LD) flow_fault = `CSR_CTL_FAULT_LOOP;
            end
        end
        if (kind == `CSR_CTL_KIND_LOOP_END) begin
            if (depth == 0 || loop_pc[top_slot] != loop_target) flow_fault = `CSR_CTL_FAULT_LOOP;
            else if (remaining[top_slot] > 1) successor = {1'b0, loop_target};
        end
        if (successor[8]) flow_fault = `CSR_CTL_FAULT_PC;
        if (retired >= limit) flow_fault = `CSR_CTL_FAULT_EXEC;
        if (retired != 0 && tag == 0) flow_fault = `CSR_CTL_FAULT_TAG;
        if (dec_fault != 0) flow_fault = dec_fault;
    end

    always @(posedge clk) begin
        if (rst || cancel) begin
            state <= IDLE; words <= '0; control <= '0; generation <= '0; limit <= '0;
            job <= '0; tag <= '0; fmt <= '0; pc <= '0; next_pc <= '0; retired <= '0;
            done_fault <= '0; depth <= '0; push_loop <= 1'b0; end_loop <= 1'b0; halt_q <= 1'b0;
            for (slot = 0; slot < LD; slot = slot + 1) begin loop_pc[slot] <= '0; remaining[slot] <= '0; end
        end else begin
            case (state)
                IDLE: if (start_take) begin
                    pc <= start_pc; limit <= start_limit; generation <= image_generation;
                    job <= start_job; fmt <= start_fmt; tag <= '0; retired <= '0; depth <= '0;
                    done_fault <= image_ready && start_limit != 0 ? 4'b0 : `CSR_CTL_FAULT_HEADER;
                    state <= image_ready && start_limit != 0 ? FETCH : DONE;
                end
                FETCH: if (fetch_valid && fetch_ready) state <= READ;
                READ: if (mem_valid && mem_ready) begin
                    if (mem_fault != 0 || mem_pc != pc || mem_generation != generation) begin
                        done_fault <= `CSR_CTL_FAULT_FETCH; state <= DONE;
                    end else begin words <= mem_words; control <= mem_control; state <= CHECK; end
                end
                CHECK: begin
                    if (flow_fault != 0) begin done_fault <= flow_fault; state <= DONE; end
                    else begin
                        next_pc <= successor[7:0]; push_loop <= push_next;
                        end_loop <= kind == `CSR_CTL_KIND_LOOP_END; halt_q <= kind == `CSR_CTL_KIND_HALT;
                        if (kind == `CSR_CTL_KIND_WAIT) state <= WAIT_PRED;
                        else if (kind == `CSR_CTL_KIND_ADDRESS) state <= ADDRESS;
                        else state <= ISSUE;
                    end
                end
                WAIT_PRED: if (pred_value(predicate, predicates)) state <= ISSUE;
                ADDRESS: if (addr_valid && addr_ready) state <= ADDR_WAIT;
                ADDR_WAIT: if (addr_rsp_valid && addr_rsp_ready) begin
                    if (addr_bad_tag || addr_rsp_fault) begin
                        done_fault <= addr_bad_tag ? `CSR_CTL_FAULT_TAG : `CSR_CTL_FAULT_BACKEND; state <= DONE;
                    end else state <= ISSUE;
                end
                ISSUE: if (exec_valid && exec_ready) state <= RETIRE;
                RETIRE: if (exec_rsp_valid) begin
                    if (exec_failure) begin
                        done_fault <= exec_bad_tag ? `CSR_CTL_FAULT_TAG : `CSR_CTL_FAULT_BACKEND; state <= DONE;
                    end else if (exec_rsp_ready) begin
                        retired <= retired + 1'b1; tag <= tag + 1'b1;
                        if (push_loop) begin
                            loop_pc[int'(depth)] <= pc; remaining[int'(depth)] <= count; depth <= depth + 1'b1;
                        end
                        if (end_loop) begin
                            if (remaining[top_slot] > 1) remaining[top_slot] <= remaining[top_slot] - 1'b1;
                            else depth <= depth - 1'b1;
                        end
                        pc <= next_pc; state <= halt_q ? DONE : FETCH;
                    end
                end
                DONE: if (done_valid && done_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
