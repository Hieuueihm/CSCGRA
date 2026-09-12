`include "stream_interface.vh"
// Config and command ownership for exactly two arrays (32 independent contexts).
module stream_fabric #(parameter TERMINAL_ENABLE=0, parameter CASCADE_ENABLE=0) (
    input wire clk,rst,abort,
    input wire cfg_valid,output wire cfg_ready,
    input wire [2047:0] cfg_contexts,
    output reg [3:0] cfg_fault,output reg cfg_loaded,
    input wire cmd_valid,output wire cmd_ready,
    input wire [15:0] cmd_job,cmd_tag,input wire [7:0] cmd_fmt,
    // Explicit internal ABI: 0 none, 1 row-of-four then round, 2 raw sum32,
    // 3 per-lane round. Legacy callers use TERMINAL_ENABLE=0.
    input wire [1:0] cmd_terminal,
    input wire [5:0] cmd_shift,
    input wire [31:0] cmd_terminal_mask,
    // Flow 0 is the legacy independent 32-lane fabric.  Flow 1 feeds the
    // rounded low array product into the high array subtraction.
    input wire [1:0] cmd_flow,
    output wire [2047:0] terminal_acc,
    output reg [3:0] terminal_error,
    input wire in_valid,output wire in_ready,
    input wire [863:0] in_a,in_b,input wire [31:0] in_mask,input wire in_last,
    output wire out_valid,input wire out_ready,
    output wire [863:0] out_data,output wire [2047:0] out_acc,
    output wire [31:0] out_mask,output wire [127:0] out_faults,output wire out_last,
    output wire done_valid,input wire done_ready,
    output reg [3:0] done_fault,
    output reg [15:0] done_job,done_tag,output reg [7:0] done_fmt
);
    localparam [1:0] IDLE=0,RUN=1,DONE=2,TERMINAL=3;
    reg [1:0] state;
    reg input_end;
    reg [1:0] terminal_mode;
    reg [2:0] terminal_step;
    reg [5:0] terminal_shift;
    reg [31:0] terminal_mask;
    wire terminal_round=terminal_mode==3||(terminal_mode==1&&terminal_step==2);
    wire terminal_last=terminal_mode==3||(terminal_mode==1&&terminal_step==2)||(terminal_mode==2&&terminal_step==4);
    wire [127:0] terminal_faults;

    reg [3:0] sticky_fault;
    wire active=!rst&&!abort;
    localparam [1:0] FLOW_PARALLEL=0,FLOW_CASCADE16=1;
    reg cascade_run;
    reg old_head,old_tail,meta_head,meta_tail;
    reg [1:0] old_count,meta_count;
    reg cascade_context_ok;
    reg [431:0] old_fifo[0:1];
    reg [15:0] old_mask_fifo[0:1];
    reg old_last_fifo[0:1];
    reg [63:0] mul_fault_fifo[0:1];
    reg [15:0] meta_mask_fifo[0:1];
    reg meta_last_fifo[0:1];
    wire [1:0] ready,valid,last;
    wire [863:0] array_out_data;
    wire [2047:0] array_out_acc;
    wire [31:0] array_out_mask;
    wire [127:0] array_out_faults;
    wire [1:0] array_in_valid,array_out_ready;
    wire [431:0] cascade_old=old_fifo[old_head];
    wire [15:0] cascade_old_mask=old_mask_fifo[old_head];
    wire cascade_old_last=old_last_fifo[old_head];
    wire [63:0] cascade_mul_fault=mul_fault_fifo[meta_head];
    wire [15:0] cascade_meta_mask=meta_mask_fifo[meta_head];
    wire cascade_meta_last=meta_last_fifo[meta_head];
    wire cascade_input_ok=in_mask[15:0]==in_mask[31:16];
    wire cascade_transfer=active&&state==RUN&&cascade_run&&valid[0]&&array_out_ready[0];
    wire cascade_retire=active&&state==RUN&&cascade_run&&valid[1]&&array_out_ready[1]&&meta_count!=0;
    wire cascade_config_bad=cmd_terminal!=0||cmd_shift!=0||cmd_terminal_mask!=0;
    wire flow_bad=CASCADE_ENABLE && cmd_flow!=FLOW_PARALLEL && cmd_flow!=FLOW_CASCADE16;
    wire config_take=cfg_valid&&cfg_ready;
    wire command_take=cmd_valid&&cmd_ready;
    reg config_bad;
    reg cascade_context_bad;
    reg [3:0] frame_fault;
    reg [63:0] checked_word;
    integer lane;
    assign cfg_ready=active&&state==IDLE;
    assign cmd_ready=active&&state==IDLE&&cfg_loaded&&!cfg_valid;
    assign in_ready=active&&state==RUN&&!input_end&&
        (cascade_run ? (ready[0]&&old_count<2) : (&ready));
    assign out_valid=active&&state==RUN&&(cascade_run ? valid[1] : (&valid));
    assign out_last=cascade_run ? cascade_meta_last : last[0];
    assign out_data=cascade_run ? {432'd0,array_out_data[432+:432]} : array_out_data;
    assign out_acc=cascade_run ? {1024'd0,array_out_acc[1024+:1024]} : array_out_acc;
    assign out_mask=cascade_run ? {16'd0,cascade_meta_mask} : array_out_mask;
    // A rounded MUL failure is the causal error for a cascade lane; retain it
    // through the second array instead of OR-ing unrelated numeric codes.
    genvar fault_lane;
    generate for(fault_lane=0;fault_lane<16;fault_lane=fault_lane+1) begin : cascade_fault_mux
        assign out_faults[fault_lane*4+:4]=cascade_run ?
          (cascade_mul_fault[fault_lane*4+:4]!=0 ? cascade_mul_fault[fault_lane*4+:4] : array_out_faults[(16+fault_lane)*4+:4]) : array_out_faults[fault_lane*4+:4];
        assign out_faults[(16+fault_lane)*4+:4]=cascade_run ? 4'd0 : array_out_faults[(16+fault_lane)*4+:4];
    end endgenerate
    assign done_valid=active&&state==DONE;
    always @*
    begin
        config_bad=0;
        cascade_context_bad=0;
        frame_fault=0;
        terminal_error=0;
        checked_word=0;
        for(lane=0;lane<32;lane=lane+1)
        begin
            checked_word=cfg_contexts[lane*64+:64];
            if(checked_word[`CSR_STREAM_CONTEXT_RESERVED_LSB +: `CSR_STREAM_CONTEXT_RESERVED_W]!=0||!(checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]==`CSR_PE_OP_MOV||checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]==`CSR_PE_OP_ADD||
            checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]==`CSR_PE_OP_SUB||checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]==`CSR_PE_OP_MUL||checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]==`CSR_PE_OP_MAC))config_bad=1;
            if(terminal_error==0&&terminal_faults[lane*4+:4]!=0)terminal_error=terminal_faults[lane*4+:4];
            if(frame_fault==0&&out_faults[lane*4+:4]!=0)frame_fault=out_faults[lane*4+:4];
            if(lane<16 && (checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_PE_OP_MUL || !checked_word[`CSR_STREAM_CONTEXT_MODE_LSB] || checked_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]!=`CSR_STREAM_SRC_A || checked_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]!=`CSR_STREAM_SRC_B)) cascade_context_bad=1;
            // Cascade16 keeps a rounded low MUL and applies it as high B.
            // The high half supports both C-product and C+product; legacy
            // factor rank continues to load SUB.
            if(lane>=16 && ((checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_PE_OP_SUB && checked_word[`CSR_STREAM_CONTEXT_OP_LSB +: `CSR_STREAM_CONTEXT_OP_W]!=`CSR_PE_OP_ADD) || !checked_word[`CSR_STREAM_CONTEXT_MODE_LSB] || checked_word[`CSR_STREAM_CONTEXT_SRC_A_LSB +: `CSR_STREAM_CONTEXT_SRC_A_W]!=`CSR_STREAM_SRC_A || checked_word[`CSR_STREAM_CONTEXT_SRC_B_LSB +: `CSR_STREAM_CONTEXT_SRC_B_W]!=`CSR_STREAM_SRC_B)) cascade_context_bad=1;
        end
    end
    genvar array_id;
    generate for(array_id=0;array_id<2;array_id=array_id+1)
    begin :arrays
        stream_array array_core(.clk(clk),
            .rst(rst),
            .abort(abort),
        .cfg_valid(config_take&&!config_bad),
        .cfg_contexts(cfg_contexts[array_id*1024+:1024]),
            .start(command_take),
            .terminal_valid(state==TERMINAL&&!input_end),
            .terminal_step(terminal_step),.terminal_round(terminal_round),
            .terminal_mask(terminal_mask[array_id*16 +: 16]),.terminal_shift(terminal_shift),
            .terminal_cross(terminal_acc[1024 +: 64]),.terminal_root(array_id==0),
            .terminal_acc(terminal_acc[array_id*1024 +: 1024]),
            .terminal_faults(terminal_faults[array_id*64 +: 64]),
        .in_valid(array_in_valid[array_id]),
            .in_ready(ready[array_id]),
            .in_a(cascade_run&&array_id==1 ? cascade_old : in_a[array_id*432+:432]),
            .in_b(cascade_run&&array_id==1 ? array_out_data[0+:432] : in_b[array_id*432+:432]),
        .in_mask(cascade_run&&array_id==1 ? cascade_old_mask : in_mask[array_id*16+:16]),
            .in_last(cascade_run&&array_id==1 ? cascade_old_last : in_last),
            .out_valid(valid[array_id]),
            .out_ready(array_out_ready[array_id]),
        .out_data(array_out_data[array_id*432+:432]),
            .out_acc(array_out_acc[array_id*1024+:1024]),
            .out_mask(array_out_mask[array_id*16+:16]),
        .out_faults(array_out_faults[array_id*64+:64]),
            .out_last(last[array_id]));
    end
endgenerate
    assign array_in_valid[0]=in_valid&&in_ready&&(!cascade_run||cascade_input_ok);
    assign array_in_valid[1]=cascade_run ? (active&&state==RUN&&valid[0]&&old_count!=0&&meta_count<2) : (in_valid&&in_ready);
    assign array_out_ready[0]=cascade_run ? (active&&state==RUN&&valid[0]&&old_count!=0&&ready[1]&&meta_count<2) : (out_valid&&out_ready);
    assign array_out_ready[1]=cascade_run ? (active&&state==RUN&&valid[1]&&out_ready) : (out_valid&&out_ready);
always @(posedge clk)
begin
    if(rst)
    begin
        state<=IDLE;
        terminal_mode<=0;
        terminal_step<=0;
        terminal_shift<=0;
        terminal_mask<=0;
        input_end<=0;
        sticky_fault<=0;
        cascade_run<=0;
        old_head<=0;old_tail<=0;old_count<=0;meta_head<=0;meta_tail<=0;meta_count<=0;
        cfg_fault<=0;
        cfg_loaded<=0;
        cascade_context_ok<=0;
        done_fault<=0;
        done_job<=0;
        done_tag<=0;
        done_fmt<=0;
    end
    else if(abort)
    begin
        state<=IDLE;
        terminal_mode<=0;
        terminal_step<=0;
        terminal_shift<=0;
        terminal_mask<=0;
        input_end<=0;
        sticky_fault<=0;
        cascade_run<=0;
        old_head<=0;old_tail<=0;old_count<=0;meta_head<=0;meta_tail<=0;meta_count<=0;
        done_fault<=0;
        done_job<=0;
        done_tag<=0;
        done_fmt<=0;
    end
    else
    begin
        if(config_take)
        begin
        cfg_loaded<=!config_bad;
            cascade_context_ok<=!cascade_context_bad;
            cfg_fault<=config_bad?`CSR_STREAM_PE_FAULT_CONFIG:`CSR_STREAM_PE_FAULT_NONE;
        end
        if(command_take)
        begin
            state<=cmd_fmt==`CSR_STREAM_FORMAT&&!flow_bad&&!(CASCADE_ENABLE&&cmd_flow==FLOW_CASCADE16&&(cascade_config_bad||!cascade_context_ok))?RUN:DONE;
            cascade_run<=CASCADE_ENABLE&&cmd_flow==FLOW_CASCADE16&&!cascade_config_bad&&cascade_context_ok;
            terminal_mode<=TERMINAL_ENABLE ? cmd_terminal : 2'd0;
            terminal_shift<=cmd_shift;
            terminal_mask<=cmd_terminal_mask;
            terminal_step<=0;
            input_end<=0;
            sticky_fault<=0;
            done_fault<=cmd_fmt!=`CSR_STREAM_FORMAT?`CSR_STREAM_PE_FAULT_FORMAT:(flow_bad||(CASCADE_ENABLE&&cmd_flow==FLOW_CASCADE16&&(cascade_config_bad||!cascade_context_ok))?`CSR_STREAM_PE_FAULT_CONFIG:`CSR_STREAM_PE_FAULT_NONE);
            done_job<=cmd_job;
            done_tag<=cmd_tag;
            done_fmt<=cmd_fmt;
            old_head<=0;old_tail<=0;old_count<=0;meta_head<=0;meta_tail<=0;meta_count<=0;
        end
        // Cascade admission retains old factors until array0's rounded output
        // is accepted by array1.  The two short queues are fully drained by
        // the final `last` retirement and are cleared by abort/reset/start.
        if(!command_take&&in_valid&&in_ready&&cascade_run&&cascade_input_ok)
        begin
            old_fifo[old_tail]<=in_a[432+:432];
            old_mask_fifo[old_tail]<=in_mask[31:16];
            old_last_fifo[old_tail]<=in_last;
            old_tail<=old_tail+1'b1;
        end
        if(!command_take&&cascade_transfer)
        begin
            old_head<=old_head+1'b1;
            mul_fault_fifo[meta_tail]<=array_out_faults[0+:64];
            meta_mask_fifo[meta_tail]<=cascade_old_mask;
            meta_last_fifo[meta_tail]<=cascade_old_last;
            meta_tail<=meta_tail+1'b1;
        end
        if(!command_take&&cascade_retire) meta_head<=meta_head+1'b1;
        if(!command_take) case ({(in_valid&&in_ready&&cascade_run&&cascade_input_ok),cascade_transfer})
          2'b10: old_count<=old_count+1'b1;
          2'b01: old_count<=old_count-1'b1;
          default: old_count<=old_count;
        endcase
        if(!command_take) case ({cascade_transfer,cascade_retire})
          2'b10: meta_count<=meta_count+1'b1;
          2'b01: meta_count<=meta_count-1'b1;
          default: meta_count<=meta_count;
        endcase
        if(in_valid&&in_ready&&cascade_run&&!cascade_input_ok)
        begin
            // A paired mask is an atomic cascade frame.  Do not feed either
            // array when it is malformed; publish its configuration fault.
            state<=DONE; done_fault<=`CSR_STREAM_PE_FAULT_CONFIG; input_end<=0;
        end
        if(in_valid&&in_ready&&in_last)input_end<=1;
        if(out_valid&&out_ready&&!(in_valid&&in_ready&&cascade_run&&!cascade_input_ok))
        begin
            if(sticky_fault==0&&frame_fault!=0)sticky_fault<=frame_fault;
            if(out_last)
            begin
                done_fault<=sticky_fault!=0?sticky_fault:frame_fault;
                state<=terminal_mode!=0&&sticky_fault==0&&frame_fault==0 ? TERMINAL : DONE;
                input_end<=0;
            end
        end
        // One registered level per tick; one final check tick sees the last
        // PE update before publishing DONE. No frame can enter this phase.
        if(state==TERMINAL)
        begin
            if(input_end)
            begin
                done_fault<=terminal_error;
                state<=DONE;
            end
            else if(terminal_last) input_end<=1;
            else terminal_step<=terminal_step+1'b1;
        end
        if(done_valid&&done_ready)state<=IDLE;
    end
end
endmodule
