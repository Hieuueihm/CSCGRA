`include "stream_interface.vh"
module stream_array (
    input wire clk,rst,abort,
    input wire cfg_valid,input wire [1023:0] cfg_contexts,
    input wire start,
    input wire terminal_valid,
    input wire [2:0] terminal_step,
    input wire terminal_round,
    input wire [15:0] terminal_mask,
    input wire [5:0] terminal_shift,
    input wire [63:0] terminal_cross,
    input wire terminal_root,
    output wire [1023:0] terminal_acc,
    output wire [63:0] terminal_faults,
    input wire in_valid,output wire in_ready,
    input wire [431:0] in_a,in_b,
    input wire [15:0] in_mask,input wire in_last,
    output wire out_valid,input wire out_ready,
    output wire [431:0] out_data,
    output wire [1023:0] out_acc,
    output wire [15:0] out_mask,
    output wire out_last,
    output wire [63:0] out_faults
);
    wire [15:0] ready,valid,last;
    assign in_ready=(&ready)&&!rst&&!abort;
    assign out_valid=(&valid)&&!rst&&!abort;
    assign out_last=last[0];
    genvar lane;
    generate for(lane=0;lane<16;lane=lane+1)
    begin :pes
        wire add_enable=terminal_valid&&!terminal_round&&(
            (terminal_step==0&&lane%2==0)||
            (terminal_step==1&&lane%4==0)||
            (terminal_step==2&&lane%8==0)||
            (terminal_step==3&&lane==0)||
            (terminal_step==4&&lane==0&&terminal_root));
        wire [63:0] neighbor;
        if(lane%2==0) begin : pair_link
            wire [63:0] pair_value=terminal_acc[(lane+1)*64 +: 64];
            if(lane%4==0) begin : row_link
                wire [63:0] row_value=terminal_acc[(lane+2)*64 +: 64];
                if(lane%8==0) begin : half_link
                    wire [63:0] half_value=terminal_acc[(lane+4)*64 +: 64];
                    if(lane==0) begin : root_link
                        assign neighbor=terminal_step==0 ? pair_value : terminal_step==1 ? row_value :
                            terminal_step==2 ? half_value : terminal_step==3 ? terminal_acc[8*64 +: 64] : terminal_cross;
                    end else assign neighbor=terminal_step==0 ? pair_value : terminal_step==1 ? row_value : half_value;
                end else assign neighbor=terminal_step==0 ? pair_value : row_value;
            end else assign neighbor=pair_value;
        end else assign neighbor=64'd0;
        wire [63:0] context_word=cfg_contexts[lane*64+:64];
        stream_pe pe(.clk(clk),
            .rst(rst),
            .abort(abort),
            .cfg_valid(cfg_valid),
        .cfg_op(context_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]),
            .cfg_mode(context_word[`CSR_STREAM_CONTEXT_MODE_LSB]),
            .cfg_src_a(context_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]),
        .cfg_src_b(context_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]),
            .cfg_immediate(context_word[`CSR_STREAM_CONTEXT_IMMEDIATE_LSB +: `CSR_STREAM_CONTEXT_IMMEDIATE_W]),
            .start(start),
            .terminal_add(add_enable),
            .terminal_round(terminal_valid&&terminal_round&&terminal_mask[lane]),
            .terminal_operand(neighbor),.terminal_shift(terminal_shift),
            .terminal_acc(terminal_acc[lane*64 +: 64]),
            .terminal_fault(terminal_faults[lane*4 +: 4]),
        .in_valid(in_valid&&in_ready),
            .in_ready(ready[lane]),
            .in_a(in_a[lane*27+:27]),
            .in_b(in_b[lane*27+:27]),
        .in_mask(in_mask[lane]),
            .in_last(in_last),
            .out_valid(valid[lane]),
            .out_ready(out_valid&&out_ready),
        .out_data(out_data[lane*27+:27]),
            .out_acc(out_acc[lane*64+:64]),
            .out_mask(out_mask[lane]),
        .out_last(last[lane]),
            .out_fault(out_faults[lane*4+:4]));
    end
    endgenerate
endmodule
