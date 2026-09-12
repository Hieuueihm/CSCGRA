`include "stream_interface.vh"
// One registered 27x18 multiplier, one checked ACC64 feedback path, P1.
module stream_pe (
    input wire clk,rst,abort,
    input wire cfg_valid,
    input wire [4:0] cfg_op,
    input wire cfg_mode,
    input wire [1:0] cfg_src_a,cfg_src_b,
    input wire [26:0] cfg_immediate,
    input wire start,
    // Internal terminal phase: no frame or held output may remain owned.
    input wire terminal_add,terminal_round,
    input wire [63:0] terminal_operand,
    input wire [5:0] terminal_shift,
    output wire [63:0] terminal_acc,
    output reg [3:0] terminal_fault,
    input wire in_valid,output wire in_ready,
    input wire [26:0] in_a,in_b,
    input wire in_mask,in_last,
    output wire out_valid,input wire out_ready,
    output reg [26:0] out_data,
    output reg [63:0] out_acc,
    output reg out_mask,out_last,
    output reg [3:0] out_fault
);
    reg [4:0] op;
    reg mode;
    reg [1:0] src_a,src_b;
    reg [26:0] immediate;
    reg signed [63:0] acc;
    reg phase,product_valid,pending;
    reg signed [26:0] saved_a,saved_b,product_a,product_b;
    reg signed [44:0] low_product;
    reg signed [63:0] product_q;
    reg product_mask,product_last,saved_mask,saved_last;
    reg [3:0] product_fault;
    reg signed [26:0] selected_a,selected_b;
    wire active=!rst&&!abort;
    wire output_credit=!pending||out_ready;
    // The product slot can refill when empty or advancing into a credited output.
    wire product_credit=!product_valid||output_credit;
    wire multiply=op==`CSR_PE_OP_MUL||op==`CSR_PE_OP_MAC;
    wire take=in_valid&&in_ready;
    wire advance=product_valid&&output_credit;
    wire signed [26:0] multiplier_a=phase?saved_a:selected_a;
    wire signed [26:0] multiplier_b=phase?saved_b:selected_b;
    wire signed [17:0] multiplier_half=phase?{{8{multiplier_b[26]}},multiplier_b[26:17]}:
    mode?{1'b0,multiplier_b[16:0]}:multiplier_b[17:0];
    wire signed [44:0] multiplied=multiplier_a*multiplier_half;
    wire signed [64:0] high_extended={{20{multiplied[44]}},multiplied};
    wire signed [64:0] low_extended={{20{low_product[44]}},low_product};
    wire signed [64:0] combined=(high_extended<<<17)+low_extended;
    // One ACC adder serves normal feedback and registered neighbor reduction.
    wire signed [63:0] acc_operand=terminal_add ? $signed(terminal_operand) : product_q;
    wire signed [64:0] acc_sum=$signed({acc[63],acc})+$signed({acc_operand[63],acc_operand});
    assign terminal_acc=acc;
    wire [5:0] round_shift=terminal_round ? terminal_shift : mode ? 6'd22 : 6'd16;
    reg signed [64:0] value,magnitude;
    reg [26:0] data_next;
    reg [63:0] acc_next;
    reg [3:0] fault_next;
    assign in_ready=active&&!start&&!phase&&product_credit;
    assign out_valid=active&&pending;
    always @*
    begin
        case(src_a)
            `CSR_STREAM_SRC_A:selected_a=in_a;
            `CSR_STREAM_SRC_B:selected_a=in_b;
            `CSR_STREAM_SRC_IMM:selected_a=immediate;
            default:selected_a=0;
        endcase
        case(src_b)
            `CSR_STREAM_SRC_A:selected_b=in_a;
            `CSR_STREAM_SRC_B:selected_b=in_b;
            `CSR_STREAM_SRC_IMM:selected_b=immediate;
            default:selected_b=0;
        endcase
        data_next=0;
        acc_next=acc;
        fault_next=product_fault;
        value=0;
        magnitude=0;
        if(terminal_round||(product_mask&&product_fault==0))
        begin
            if(terminal_round)
            begin
                fault_next=0;
                value=$signed({acc[63],acc});
            end
            else case(op)
                `CSR_PE_OP_MOV:value=$signed(product_a);
                `CSR_PE_OP_ADD:value=$signed(product_a)+$signed({product_b[26],product_b});
                `CSR_PE_OP_SUB:value=$signed(product_a)-$signed({product_b[26],product_b});
                `CSR_PE_OP_MUL:value=$signed(product_q);
                `CSR_PE_OP_MAC:value=acc_sum;
                default:fault_next=`CSR_STREAM_PE_FAULT_CONFIG;
            endcase
            // One magnitude/round/range path serves MUL and terminal ACC
            // narrowing. A zero shift is exact; every other shift ties away.
            if(terminal_round||op==`CSR_PE_OP_MUL)
            begin
                magnitude=value<0 ? -value : value;
                if(round_shift!=0)
                    magnitude=(magnitude+(65'sd1<<(round_shift-1)))>>round_shift;
                value=value<0 ? -magnitude : magnitude;
            end
            if(op==`CSR_PE_OP_MAC&&!terminal_round)
            begin
                if(value[64]!=value[63]) fault_next=`CSR_STREAM_PE_FAULT_ACC;
                else acc_next=value[63:0];
            end
            else if(value>65'sd67108863||value< -65'sd67108864)
                fault_next=`CSR_STREAM_PE_FAULT_RANGE;
            else data_next=value[26:0];
        end
        if(fault_next!=0)
        begin
            data_next=0;
            acc_next=acc;
        end
    end
    always @(posedge clk)
    begin
        if(rst)
        begin
            op<=0;
            mode<=0;
            src_a<=0;
            src_b<=0;
            immediate<=0;
        end
        else if(cfg_valid)
        begin
            op<=cfg_op;
            mode<=cfg_mode;
            src_a<=cfg_src_a;
            src_b<=cfg_src_b;
            immediate<=cfg_immediate;
        end
        if(!active||start)
        begin
            acc<=0;
            phase<=0;
            product_valid<=0;
            pending<=0;
            saved_a<=0;
            saved_b<=0;
            product_a<=0;
            product_b<=0;
            low_product<=0;
            product_q<=0;
            product_mask<=0;
            product_last<=0;
            saved_mask<=0;
            saved_last<=0;
            product_fault<=0;
            out_data<=0;
            out_acc<=0;
            out_mask<=0;
            out_last<=0;
            out_fault<=0;
            terminal_fault<=0;
        end
        else
        begin
            if(pending&&out_ready)pending<=0;
            if(terminal_add)
            begin
                if(acc_sum[64]!=acc_sum[63]) terminal_fault<=`CSR_STREAM_PE_FAULT_ACC;
                else acc<=acc_sum[63:0];
            end
            if(terminal_round)
            begin
                out_data<=data_next;
                if(fault_next!=0) terminal_fault<=fault_next;
            end
            // P1 updates its private ACC when the product advances, not when
            // the older candidate output is consumed. Held outputs remain stable.
            if(advance)
            begin
                pending<=1;
                out_data<=data_next;
                out_acc<=acc_next;
                out_mask<=product_mask;
                out_last<=product_last;
                out_fault<=fault_next;
                acc<=acc_next;
                product_valid<=0;
            end
            // Full-S27 phase two owns the saved operands until product credit.
            // No new frame can replace the unsigned low-17 partial product.
            if(phase&&product_credit)
            begin
                product_q<=combined[63:0];
                product_a<=saved_a;
                product_b<=saved_b;
                product_mask<=saved_mask;
                product_last<=saved_last;
                product_fault<=0;
                product_valid<=1;
                phase<=0;
            end
            else if(take)
            begin
                if(mode&&multiply&&in_mask)
                begin
                    phase<=1;
                    low_product<=multiplied;
                    saved_a<=selected_a;
                    saved_b<=selected_b;
                    saved_mask<=in_mask;
                    saved_last<=in_last;
                end
                else
                begin
                    product_q<={{19{multiplied[44]}},multiplied};
                    product_a<=selected_a;
                    product_b<=selected_b;
                    product_mask<=in_mask;
                    product_last<=in_last;
                    product_valid<=1;
                    product_fault<=in_mask&&multiply&&!mode&&selected_b!={{9{selected_b[17]}},selected_b[17:0]}?`CSR_STREAM_PE_FAULT_COEFF:`CSR_STREAM_PE_FAULT_NONE;
                end
            end
        end
    end
endmodule
