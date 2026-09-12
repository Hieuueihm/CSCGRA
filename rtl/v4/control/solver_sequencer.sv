`include "solver_interface.vh"
module solver_sequencer (
    input wire clk,rst,cancel,
    input wire load_begin_valid,output wire load_begin_ready,
    input wire [7:0] load_revision,input wire load_verified,input wire [8:0] load_depth,
    input wire load_valid,output wire load_ready,input wire [7:0] load_pc,
    input wire [127:0] load_word,input wire load_last,
    output reg image_valid,output reg [3:0] load_fault,
    input wire start_valid,output wire start_ready,
    input wire [7:0] start_rows,input wire [6:0] start_cols,
    input wire [127:0] start_key,input wire [31:0] start_generation,
    input wire [15:0] start_job,start_tag,input wire [7:0] start_fmt,start_max_iterations,
    input wire [31:0] start_instruction_limit,
    output wire done_valid,input wire done_ready,output reg [3:0] done_fault,
    output reg [3:0] done_candidate_slot,
    output wire [7:0] done_iterations,output wire [63:0] done_normal_energy,done_rhs_energy,
    output reg [15:0] done_job,done_tag,output reg [7:0] done_fmt,
    output wire kernel_valid,input wire kernel_ready,
    output wire [3:0] kernel_op,kernel_src_a,kernel_src_b,kernel_dst,
    output wire [7:0] kernel_length,kernel_rows,output wire [6:0] kernel_cols,
    output wire kernel_trans,output wire [26:0] kernel_scalar_a,kernel_scalar_b,
    output wire [5:0] kernel_shift,output wire [127:0] kernel_key,
    output wire [31:0] kernel_generation,output wire [15:0] kernel_job,kernel_tag,
    output wire [7:0] kernel_fmt,
    input wire kernel_rsp_valid,output wire kernel_rsp_ready,input wire [3:0] kernel_rsp_fault,
    input wire [63:0] kernel_rsp_data,input wire kernel_rsp_nonzero,
    input wire [15:0] kernel_rsp_job,kernel_rsp_tag,input wire [7:0] kernel_rsp_fmt,
    output wire scalar_valid,input wire scalar_ready,output wire [1:0] scalar_op,
    output wire signed [63:0] scalar_a,scalar_b,output wire [7:0] scalar_source_frac,
    output wire [15:0] scalar_job,scalar_tag,output wire [7:0] scalar_fmt,
    input wire scalar_rsp_valid,output wire scalar_rsp_ready,input wire signed [26:0] scalar_rsp_data,
    input wire [2:0] scalar_rsp_fault,input wire [15:0] scalar_rsp_job,scalar_rsp_tag,
    input wire [7:0] scalar_rsp_fmt,
    output wire running,output reg [7:0] trace_pc,output wire [127:0] trace_word,
    output wire trace_retire
);
    localparam [3:0] IDLE=0,FETCH=1,EXEC=2,KREQ=3,KWAIT=4,SREQ=5,SWAIT=6,CERTIFY=7,DONE=8;
    reg [3:0] state;
    reg loading;
    reg [7:0] next_load;
    reg [127:0] program_mem[0:255], word, retired_word;
    reg [7:0] pc;
    reg [3:0] narrow_candidate;
    reg signed [63:0] rf[0:31];
    reg [7:0] rows;
    reg [6:0] cols;
    reg [127:0] key;
    reg [31:0] generation,limit,retired_count;
    reg [15:0] operation_tag;
    reg retired, certificate_pass;
    reg [2:0] certificate_stage;
    reg [3:0] certificate_vector;
    reg [4:0] certificate_register;
    reg [97:0] cert_sum,cert_term;
    reg [33:0] cert_factor;
    reg [5:0] cert_step;
    integer i,e;
    reg malformed;
    reg [127:0] allowed;
    wire active=!rst&&!cancel;
    wire [4:0] f_kind=word[`CSR_SOLVER_KIND_LSB +: `CSR_SOLVER_KIND_W];
    wire [3:0] f_kernel=word[`CSR_SOLVER_KERNEL_LSB +: `CSR_SOLVER_KERNEL_W];
    wire [3:0] f_dst_v=word[`CSR_SOLVER_DST_V_LSB +: `CSR_SOLVER_DST_V_W];
    wire [3:0] f_a_v=word[`CSR_SOLVER_A_V_LSB +: `CSR_SOLVER_A_V_W];
    wire [3:0] f_b_v=word[`CSR_SOLVER_B_V_LSB +: `CSR_SOLVER_B_V_W];
    wire [4:0] f_dst_s=word[`CSR_SOLVER_DST_S_LSB +: `CSR_SOLVER_DST_S_W];
    wire [4:0] f_a_s=word[`CSR_SOLVER_A_S_LSB +: `CSR_SOLVER_A_S_W];
    wire [4:0] f_b_s=word[`CSR_SOLVER_B_S_LSB +: `CSR_SOLVER_B_S_W];
    wire [4:0] f_flag_s=word[`CSR_SOLVER_FLAG_S_LSB +: `CSR_SOLVER_FLAG_S_W];
    wire [1:0] f_length_mode=word[`CSR_SOLVER_LENGTH_MODE_LSB +: `CSR_SOLVER_LENGTH_MODE_W];
    wire [4:0] f_shift_s=word[`CSR_SOLVER_SHIFT_S_LSB +: `CSR_SOLVER_SHIFT_S_W];
    wire [7:0] f_target=word[`CSR_SOLVER_TARGET_LSB +: `CSR_SOLVER_TARGET_W];
    wire [63:0] f_immediate=word[`CSR_SOLVER_IMMEDIATE_LSB +: `CSR_SOLVER_IMMEDIATE_W];
    wire [7:0] f_reserved=word[`CSR_SOLVER_RESERVED_LSB +: `CSR_SOLVER_RESERVED_W];
    wire [97:0] cert_next=cert_sum+(cert_factor[0]?cert_term:98'd0);
    wire scalar_kernel=f_kernel==9||f_kernel==10;
    wire returns_scalar=f_kernel==7||scalar_kernel;
    wire uses_a_scalar=f_kernel==4||f_kernel==5||scalar_kernel;
    wire uses_b_scalar=scalar_kernel;
    wire bad_a=rf[f_a_s] < -67108864 || rf[f_a_s] > 67108863;
    wire bad_b=rf[f_b_s] < -67108864 || rf[f_b_s] > 67108863;
    wire writes_scalar=f_kind==2||f_kind==3||f_kind==4||f_kind==5||f_kind==6||f_kind==7||f_kind==11||f_kind==12;
    assign running=state!=IDLE&&state!=DONE;
    assign load_begin_ready=active&&state==IDLE&&!loading;
    assign load_ready=active&&state==IDLE&&loading;
    assign start_ready=active&&state==IDLE&&!loading&&!load_begin_valid;
    assign done_valid=active&&state==DONE;
    assign done_iterations=rf[25][7:0];
    assign done_normal_energy=rf[21]; assign done_rhs_energy=rf[19];
    assign trace_word=retired_word;assign trace_retire=retired;
    assign kernel_valid=active&&state==KREQ;
    assign kernel_rsp_ready=active&&state==KWAIT;
    assign kernel_op=f_kernel;assign kernel_src_a=f_a_v;assign kernel_src_b=f_b_v;assign kernel_dst=f_dst_v;
    assign kernel_length=f_length_mode==0?rows:f_length_mode==1?{1'b0,cols}:f_immediate[15:8];
    assign kernel_rows=rows;assign kernel_cols=cols;assign kernel_trans=f_immediate[0];
    assign kernel_scalar_a=rf[f_a_s][26:0];assign kernel_scalar_b=rf[f_b_s][26:0];
    assign kernel_shift=rf[f_shift_s][5:0];assign kernel_key=key;assign kernel_generation=generation;
    assign kernel_job=done_job;assign kernel_tag=operation_tag;assign kernel_fmt=done_fmt;
    assign scalar_valid=active&&state==SREQ;assign scalar_rsp_ready=active&&state==SWAIT;
    assign scalar_op=f_kind==2?2'd0:2'd1;assign scalar_a=rf[f_a_s];assign scalar_b=rf[f_b_s];
    assign scalar_source_frac=f_kind==2?8'd0:8'd44;
    assign scalar_job=done_job;assign scalar_tag=operation_tag;assign scalar_fmt=done_fmt;
    task fail(input [3:0] fault);
        begin done_fault<=fault;state<=DONE;certificate_pass<=0;retired<=0;end
    endtask
    task retire(input [8:0] next_pc);
        begin
            retired<=1;retired_count<=retired_count+1'b1;trace_pc<=pc;retired_word<=word;
            if (next_pc>255) fail(`CSR_SOLVER_FAULT_PROGRAM);
            else begin pc<=next_pc[7:0];state<=FETCH;end
        end
    endtask
    always @* begin
        allowed=0;
        case(f_kind)
            `CSR_SOLVER_OP_NOP:allowed=128'h0000000000000000000000000000001f;
            `CSR_SOLVER_OP_KERNEL:allowed=128'h00ffffffffffffffff00ffffffffffff;
            `CSR_SOLVER_OP_DIV:allowed=128'h00000000000000000000000fffe0001f;
            `CSR_SOLVER_OP_SQRT:allowed=128'h0000000000000000000000007fe0001f;
            `CSR_SOLVER_OP_SET:allowed=128'h00ffffffffffffffff00000003e0001f;
            `CSR_SOLVER_OP_MOV:allowed=128'h0000000000000000000000007fe0001f;
            `CSR_SOLVER_OP_NEG:allowed=128'h0000000000000000000000007fe0001f;
            `CSR_SOLVER_OP_RECIP_PREP:allowed=128'h00000000000000000000f8007fe0001f;
            `CSR_SOLVER_OP_BR_ZERO:allowed=128'h000000000000000000ff00007c00001f;
            `CSR_SOLVER_OP_BR_NONZERO:allowed=128'h000000000000000000ff00007c00001f;
            `CSR_SOLVER_OP_JUMP:allowed=128'h000000000000000000ff00000000001f;
            `CSR_SOLVER_OP_CERT:allowed=128'h00000000000000000000000fffe0001f;
            `CSR_SOLVER_OP_INC:allowed=128'h0000000000000000000000007fe0001f;
            `CSR_SOLVER_OP_BR_GE:allowed=128'h000000000000000000ff000ffc00001f;
            `CSR_SOLVER_OP_SUCCESS:allowed=128'h0000000000000000000000000000001f;
            `CSR_SOLVER_OP_FAIL:allowed=128'h0000000000000000000000000000001f;
            default:allowed=0;
        endcase
        malformed=(word & ~allowed)!=0||f_kind>15;
        if (writes_scalar && (f_dst_s==0||f_dst_s==30)) malformed=1;
        if (f_kind==11 && (f_dst_s==f_a_s||f_dst_s==f_b_s)) malformed=1;
        if (f_kind==7 && (f_shift_s==0||f_shift_s==30||f_shift_s==f_dst_s)) malformed=1;
        if (f_kind==1) begin
            if (f_kernel>10||f_length_mode>2||f_immediate[63:16]!=0||f_immediate[7:1]!=0) malformed=1;
            if (f_flag_s==30||(f_flag_s!=0&&f_flag_s==f_dst_s)) malformed=1;
            if (returns_scalar && (f_dst_s==0||f_dst_s==30)) malformed=1;
            if (!returns_scalar && f_dst_s!=0) malformed=1;
            if (f_length_mode!=2&&f_immediate[15:8]!=0) malformed=1;
            if (f_kernel!=6&&f_immediate[0]!=0) malformed=1;
        end
        e=0;
        for(i=0;i<27;i=i+1) if(rf[f_a_s][i]) e=i+1;
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;loading<=0;image_valid<=0;load_fault<=0;next_load<=0;
            trace_pc<=0;pc<=0;word<=0;retired_word<=0;narrow_candidate<=0;done_candidate_slot<=0;rows<=0;cols<=0;key<=0;generation<=0;limit<=0;
            retired_count<=0;operation_tag<=0;retired<=0;certificate_pass<=0;
            certificate_stage<=0;certificate_vector<=0;certificate_register<=0;
            cert_sum<=0;cert_term<=0;cert_factor<=0;cert_step<=0;
            done_fault<=0;done_job<=0;done_tag<=0;done_fmt<=0;
            for(i=0;i<32;i=i+1) rf[i]<=0;
        end else if(cancel) begin
            state<=IDLE;loading<=0;retired<=0;certificate_pass<=0;certificate_stage<=0;
            if(loading) image_valid<=0;
            done_fault<=0;done_job<=0;done_tag<=0;done_fmt<=0;
        end else begin
            retired<=0;
            if(load_begin_valid&&load_begin_ready) begin
                image_valid<=0;load_fault<=0;next_load<=0;
                if(load_revision!=`CSR_SOLVER_REVISION||!load_verified||load_depth!=256) load_fault<=`CSR_SOLVER_FAULT_LOAD;
                else loading<=1;
            end
            if(load_valid&&load_ready) begin
                if(load_pc!=next_load||load_last!=(next_load==255)) begin
                    loading<=0;image_valid<=0;load_fault<=`CSR_SOLVER_FAULT_LOAD;
                end else begin
                    program_mem[load_pc]<=load_word;
                    if(next_load==255) begin loading<=0;image_valid<=1;end
                    else next_load<=next_load+1'b1;
                end
            end
            if(state==DONE&&done_ready) state<=IDLE;
            if(start_valid&&start_ready) begin
                done_job<=start_job;done_tag<=start_tag;done_fmt<=start_fmt;done_fault<=0;
                for(i=0;i<32;i=i+1) rf[i]<=0;
                rf[30]<={56'b0,start_max_iterations};
                rows<=start_rows;cols<=start_cols;key<=start_key;generation<=start_generation;
                limit<=start_instruction_limit;retired_count<=0;trace_pc<=0;pc<=0;done_candidate_slot<=0;
                operation_tag<=start_tag;certificate_pass<=0;certificate_stage<=0;
                if(!image_valid) fail(`CSR_SOLVER_FAULT_LOAD);
                else if(start_rows==0||start_rows>128||start_cols==0||start_cols>96||start_fmt!=1||
                    start_max_iterations==0||start_max_iterations>128||start_instruction_limit==0) fail(`CSR_SOLVER_FAULT_MODE);
                else state<=FETCH;
            end
            case(state)
                FETCH:begin
                    if(retired_count>=limit) fail(`CSR_SOLVER_FAULT_WATCHDOG);
                    else begin word<=program_mem[pc];state<=EXEC;end
                end
                EXEC:begin
                    if(malformed) fail(`CSR_SOLVER_FAULT_PROGRAM);
                    else case(f_kind)
                        `CSR_SOLVER_OP_NOP:retire({1'b0,pc}+1'b1);
                        `CSR_SOLVER_OP_KERNEL:begin
                            certificate_pass<=0;
                            if((uses_a_scalar&&bad_a)||(uses_b_scalar&&bad_b)||
                                (f_kernel==5&&(rf[f_shift_s]<0||rf[f_shift_s]>63))||
                                (!scalar_kernel&&(kernel_length==0||kernel_length>128))) fail(`CSR_SOLVER_FAULT_NUMERIC);
                            else state<=KREQ;
                        end
                        `CSR_SOLVER_OP_DIV,`CSR_SOLVER_OP_SQRT:begin certificate_pass<=0;state<=SREQ;end
                        `CSR_SOLVER_OP_SET:begin rf[f_dst_s]<=f_immediate;certificate_pass<=0;certificate_stage<=0;retire({1'b0,pc}+1'b1);end
                        `CSR_SOLVER_OP_MOV:begin rf[f_dst_s]<=rf[f_a_s];certificate_pass<=0;certificate_stage<=0;retire({1'b0,pc}+1'b1);end
                        `CSR_SOLVER_OP_NEG:begin
                            certificate_pass<=0;certificate_stage<=0;
                            if(bad_a||rf[f_a_s]==-67108864) fail(`CSR_SOLVER_FAULT_NUMERIC);
                            else begin rf[f_dst_s]<=-rf[f_a_s];retire({1'b0,pc}+1'b1);end
                        end
                        `CSR_SOLVER_OP_RECIP_PREP:begin
                            certificate_pass<=0;certificate_stage<=0;
                            if(rf[f_a_s]<=0||rf[f_a_s]>67108863) fail(`CSR_SOLVER_FAULT_NUMERIC);
                            else begin rf[f_dst_s]<=64'd1<<e;rf[f_shift_s]<=e;retire({1'b0,pc}+1'b1);end
                        end
                        `CSR_SOLVER_OP_INC:begin
                            certificate_pass<=0;certificate_stage<=0;
                            if(rf[f_a_s]<0||rf[f_a_s]==64'sh7fffffffffffffff) fail(`CSR_SOLVER_FAULT_NUMERIC);
                            else begin rf[f_dst_s]<=rf[f_a_s]+1'b1;retire({1'b0,pc}+1'b1);end
                        end
                        `CSR_SOLVER_OP_BR_ZERO:retire(rf[f_a_s]==0?{1'b0,f_target}:{1'b0,pc}+1'b1);
                        `CSR_SOLVER_OP_BR_NONZERO:retire(rf[f_a_s]!=0?{1'b0,f_target}:{1'b0,pc}+1'b1);
                        `CSR_SOLVER_OP_BR_GE:retire(rf[f_a_s]>=rf[f_b_s]?{1'b0,f_target}:{1'b0,pc}+1'b1);
                        `CSR_SOLVER_OP_JUMP:retire({1'b0,f_target});
                        `CSR_SOLVER_OP_CERT:begin
                            if(certificate_stage!=5||f_a_s!=certificate_register) fail(`CSR_SOLVER_FAULT_CERTIFICATE);
                            else if(rf[f_a_s]<0||rf[f_b_s]<0) fail(`CSR_SOLVER_FAULT_NUMERIC);
                            else begin cert_sum<=0;cert_term<={34'b0,rf[f_a_s]};cert_factor<=34'd10000000000;cert_step<=0;state<=CERTIFY;end
                        end
                        `CSR_SOLVER_OP_SUCCESS:begin
                            retired<=1;retired_count<=retired_count+1'b1;trace_pc<=pc;retired_word<=word;
                            if(!certificate_pass) fail(`CSR_SOLVER_FAULT_CERTIFICATE);
                            else begin state<=DONE;done_fault<=0;end
                        end
                        `CSR_SOLVER_OP_FAIL:fail(`CSR_SOLVER_FAULT_NOT_CONVERGED);
                        default:fail(`CSR_SOLVER_FAULT_PROGRAM);
                    endcase
                end
                KREQ:if(kernel_ready)state<=KWAIT;
                KWAIT:if(kernel_rsp_valid)begin
                    if(kernel_rsp_job!=done_job||kernel_rsp_tag!=operation_tag||kernel_rsp_fmt!=done_fmt) fail(`CSR_SOLVER_FAULT_IDENTITY);
                    else if(kernel_rsp_fault!=0) fail(`CSR_SOLVER_FAULT_KERNEL);
                    else if((returns_scalar&&kernel_rsp_data[63])&&f_kernel!=9) fail(`CSR_SOLVER_FAULT_NUMERIC);
                    else if(f_kernel==9&&($signed(kernel_rsp_data)<-67108864||$signed(kernel_rsp_data)>67108863)) fail(`CSR_SOLVER_FAULT_NUMERIC);
                    else begin
                        if(returns_scalar)rf[f_dst_s]<=kernel_rsp_data;
                        if(f_flag_s!=0)rf[f_flag_s]<={63'b0,kernel_rsp_nonzero};
                        certificate_stage<=0;
                        if(f_kernel==8)begin certificate_stage<=1;certificate_vector<=f_dst_v;narrow_candidate<=f_dst_v;end
                        else if(certificate_stage==1&&f_kernel==6&&!kernel_trans&&f_a_v==certificate_vector)begin certificate_stage<=2;certificate_vector<=f_dst_v;end
                        else if(certificate_stage==2&&f_kernel==3&&f_b_v==certificate_vector)begin certificate_stage<=3;certificate_vector<=f_dst_v;end
                        else if(certificate_stage==3&&f_kernel==6&&kernel_trans&&f_a_v==certificate_vector)begin certificate_stage<=4;certificate_vector<=f_dst_v;end
                        else if(certificate_stage==4&&f_kernel==7&&f_a_v==certificate_vector)begin certificate_stage<=5;certificate_register<=f_dst_s;end
                        operation_tag<=operation_tag+1'b1;retire({1'b0,pc}+1'b1);
                    end
                end
                SREQ:if(scalar_ready)state<=SWAIT;
                SWAIT:if(scalar_rsp_valid)begin
                    if(scalar_rsp_job!=done_job||scalar_rsp_tag!=operation_tag||scalar_rsp_fmt!=done_fmt)fail(`CSR_SOLVER_FAULT_IDENTITY);
                    else if(scalar_rsp_fault!=0)fail(`CSR_SOLVER_FAULT_SCALAR);
                    else if(f_kind==3&&scalar_rsp_data[26])fail(`CSR_SOLVER_FAULT_NUMERIC);
                    else begin rf[f_dst_s]<={{37{scalar_rsp_data[26]}},scalar_rsp_data};certificate_stage<=0;operation_tag<=operation_tag+1'b1;retire({1'b0,pc}+1'b1);end
                end
                CERTIFY:begin
                    cert_sum<=cert_next;cert_term<=cert_term<<1;cert_factor<=cert_factor>>1;cert_step<=cert_step+1'b1;
                    if(cert_step==33)begin
                        rf[f_dst_s]<={63'b0,(cert_next<={34'b0,rf[f_b_s]})};
                        certificate_pass<=cert_next<={34'b0,rf[f_b_s]};
                        if(cert_next<={34'b0,rf[f_b_s]})done_candidate_slot<=narrow_candidate;
                        retire({1'b0,pc}+1'b1);
                    end
                end
                default:begin end
            endcase
        end
    end
endmodule
