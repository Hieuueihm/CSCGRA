// Generic command ABI: ZERO0 COPY1 ADD2 SUB3 SCALE4 NORMALIZE5 GEMV_B6
// ENERGY7 NARROW_X8 SCALAR_MUL9 SCALAR_ENERGY10.
`include "context_defs.vh"
`include "memory_defs.vh"
module kernel_engine (
    input wire clk,rst,cancel,
    input wire req_valid, output wire req_ready,
    input wire [3:0] req_op,req_src_a,req_src_b,req_dst,
    input wire [7:0] req_length,req_rows,
    input wire [6:0] req_cols,
    input wire req_trans,
    input wire [26:0] req_scalar_a,req_scalar_b,
    input wire [5:0] req_shift,
    input wire [127:0] req_key,
    input wire [31:0] req_generation,
    input wire [15:0] req_job,req_tag,
    input wire [7:0] req_fmt,
    output wire rsp_valid, input wire rsp_ready,
    output reg [3:0] rsp_fault,
    output reg [63:0] rsp_data,
    output reg rsp_nonzero,
    output reg [15:0] rsp_job,rsp_tag,
    output reg [7:0] rsp_fmt,
    input wire host_begin_valid, output wire host_begin_ready,
    input wire [3:0] host_slot,
    input wire [7:0] host_length,
    input wire [15:0] host_job,host_tag,
    input wire [7:0] host_fmt,
    input wire host_fill_valid, output wire host_fill_ready,
    input wire [1:0] host_fill_block,
    input wire [31:0] host_fill_mask,
    input wire [863:0] host_fill_data,
    input wire host_fill_last,
    output reg [3:0] host_fault,
    input wire debug_valid, output wire debug_ready,
    input wire [3:0] debug_slot,
    input wire [1:0] debug_block,
    output wire debug_rsp_valid, input wire debug_rsp_ready,
    output wire [863:0] debug_rsp_data,
    output wire [31:0] debug_rsp_mask,
    output wire [3:0] debug_rsp_fault,
    output wire mat_valid,input wire mat_ready,
    output wire mat_dense,
    output wire [31:0] mat_mask,
    output wire [287:0] mat_addr,
    output wire [127:0] mat_key,
    output wire [31:0] mat_generation,
    output wire [15:0] mem_job,mem_tag,
    output wire [7:0] mem_fmt,
    input wire mat_rsp_valid,output wire mat_rsp_ready,
    input wire [575:0] mat_rsp_data,
    input wire [255:0] mat_rsp_masks,
    input wire [31:0] mat_rsp_mask,mat_rsp_generation,
    input wire [15:0] mat_rsp_job,mat_rsp_tag,
    input wire [7:0] mat_rsp_fmt,
    input wire [3:0] mat_rsp_fault
);
    localparam [4:0] IDLE=0,CHECK=1,READ_VEC=2,WAIT_VEC=3,CLEAR=4,WAIT_CLEAR=5,
        EXEC=6,WAIT_EXEC=7,GEMV_READ=8,GEMV_WAIT=9,GEMV_MAC=10,GEMV_MAC_WAIT=11,
        GEMV_OUT=12,GEMV_OUT_WAIT=13,INVALIDATE=14,COMMIT=15,PUBLISH=16,DONE=17,
        HOST=18,FAIL=19,REDUCE=20;
    reg [4:0] state;
    reg [3:0] op,src_a,src_b,dest;
    reg [7:0] length,rows;
    reg [6:0] cols;
    reg trans;
    reg [26:0] scalar_a,scalar_b;
    reg [5:0] shift;
    reg [127:0] key;
    reg [31:0] generation;
    reg [1:0] block_idx;
    reg [7:0] reduction;
    reg [863:0] a_data,b_data;
    reg [26:0] candidate[0:127];
    reg [63:0] energy;
    reg [2047:0] reduction_acc;
    reg [5:0] energy_lane;
    wire [63:0] energy_term=reduction_acc[int'(energy_lane)*64 +: 64];
    wire [64:0] energy_next={1'b0,energy}+{1'b0,energy_term};
    wire energy_last=scalar_op ? energy_lane==1 : (energy_lane==31||int'(block_idx)*32+int'(energy_lane)+1>=int'(output_length));
    reg [15:0] owners_job[0:15];
    reg [7:0] owners_fmt[0:15];
    reg [31:0] host_mask;
    reg host_bad;
    wire active=!rst&&!cancel;
    wire scalar_op=op==9||op==10;
    wire writes_vector=op!=7&&!scalar_op;
    wire [7:0] output_length=op==6 ? (trans ? {1'b0,cols} : rows) : length;
    wire [7:0] reduction_length=trans ? rows : {1'b0,cols};
    wire last_block=(int'(block_idx)+1)*32>=int'(output_length);
    reg [31:0] lane_mask;
    wire [15:0] slot_valid;
    wire [127:0] slot_lengths;
    wire [1:0] wrd_ready,wrsp_valid;
    reg [1:0] wrd_valid,wrsp_ready;
    reg [7:0] wrd_slot;
    reg [3:0] wrd_block;
    wire [1727:0] wrsp_data;
    wire [63:0] wrsp_mask;
    wire [7:0] wrsp_fault;
    wire unused_wr_ready;
    wire write_take=state==COMMIT||(state==HOST&&host_fill_valid&&host_fill_ready&&!host_bad);
    reg [863:0] commit_data;
    wire invalidate=state==INVALIDATE||(state==FAIL&&writes_vector)||(host_begin_valid&&host_begin_ready);
    wire [3:0] invalid_slot=host_begin_valid&&host_begin_ready ? host_slot : dest;
    wire host_last=(int'(block_idx)+1)*32>=int'(length);
    wire publish=state==PUBLISH||(state==HOST&&host_fill_valid&&host_fill_ready&&!host_bad&&host_last);
    wire reader_req_ready,reader_rsp_valid;
    wire [863:0] reader_mat,reader_vec;
    wire [31:0] reader_mask;
    wire [3:0] reader_fault;
    wire [15:0] reader_job,reader_tag;
    wire [7:0] reader_fmt;
    wire unused_reader_last;
    wire vec_valid,vec_ready,vec_rsp_ready;
    wire [1:0] unused_vec_plane;
    wire [31:0] vec_mask,unused_vec_generation;
    wire [223:0] vec_addr;
    reg [31:0] vec_mask_q;
    reg [863:0] vec_response;
    wire fabric_ready,fabric_valid,fabric_fault;
    wire [863:0] fabric_data;
    wire [2047:0] fabric_acc;
    reg [63:0] fabric_word;
    reg [863:0] fabric_a,fabric_b;
    wire fabric_issue=state==CLEAR||state==EXEC||state==GEMV_MAC||state==GEMV_OUT;
    wire fabric_retire=state==WAIT_CLEAR||state==WAIT_EXEC||state==GEMV_MAC_WAIT||state==GEMV_OUT_WAIT;
    wire full_mode=op==4||op==5||op==7||scalar_op;
    integer i,j;
    reg [863:0] rounded_data;
    reg [3:0] numeric_fault;
    reg signed [64:0] value,mag;
    reg nonzero;
    wire [63:0] scalar_result={{37{fabric_data[26]}},fabric_data[26:0]};
    assign req_ready=active&&state==IDLE&&!host_begin_valid&&!debug_valid&&!(|wrsp_valid);
    assign rsp_valid=active&&state==DONE;
    assign host_begin_ready=active&&state==IDLE&&!debug_valid&&!(|wrsp_valid);
    assign host_fill_ready=active&&state==HOST;
    assign debug_ready=active&&state==IDLE&&!host_begin_valid&&wrd_ready[0];
    assign debug_rsp_valid=active&&state==IDLE&&wrsp_valid[0];
    assign debug_rsp_data=wrsp_data[863:0];
    assign debug_rsp_mask=wrsp_mask[31:0];
    assign debug_rsp_fault=wrsp_fault[3:0];
    assign vec_ready=state==GEMV_WAIT&&wrd_ready[0];
    always @* begin
        lane_mask=0;host_mask=0;host_bad=0;commit_data=0;vec_response=0;
        for(i=0;i<32;i=i+1) begin
            lane_mask[i]=scalar_op ? (op==10 ? i<2 : i==0) : int'(block_idx)*32+i<int'(output_length);
            host_mask[i]=int'(block_idx)*32+i<int'(length);
            if(!host_mask[i]&&host_fill_data[i*27 +: 27]!=0) host_bad=1;
            commit_data[i*27 +: 27]=candidate[int'(block_idx)*32+i];
            if(vec_mask_q[i]) vec_response[i*27 +: 27]=wrsp_data[i*27 +: 27];
        end
        if(host_fill_block!=block_idx||host_fill_mask!=host_mask||host_fill_last!=host_last) host_bad=1;
        wrd_valid=0;wrd_slot={src_b,src_a};wrd_block={block_idx,block_idx};wrsp_ready=0;
        if(state==IDLE) begin wrd_valid[0]=debug_valid&&!host_begin_valid;wrd_slot[3:0]=debug_slot;wrd_block[1:0]=debug_block;wrsp_ready[0]=debug_rsp_ready;end
        if(state==READ_VEC) wrd_valid=op==2||op==3 ? {2{&wrd_ready}} : 2'b01;
        if(state==WAIT_VEC) wrsp_ready=op==2||op==3 ? {2{&wrsp_valid}} : 2'b01;
        if(state==GEMV_WAIT) begin
            wrd_valid[0]=vec_valid;wrd_slot[3:0]=src_a;
            wrd_block[1:0]=reduction[6:5];wrsp_ready[0]=vec_rsp_ready;
        end
        fabric_word=0;
        fabric_word[`CSR_CTX_FORMAT_LSB +: 3]=`CSR_CTX_FMT_FIXED;
        fabric_word[`CSR_CTX_SRCA_KIND_LSB +: 4]=`CSR_CTX_SRC_MATRIX;
        fabric_word[`CSR_CTX_SRCB_KIND_LSB +: 4]=`CSR_CTX_SRC_VECTOR;
        fabric_a=a_data;fabric_b=b_data;
        if(state==CLEAR) begin fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_CLEAR;fabric_word[`CSR_CTX_ACC_WRITE_LSB]=1;end
        else if(state==GEMV_MAC) begin fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MAC;fabric_word[`CSR_CTX_ACC_WRITE_LSB]=1;fabric_a=reader_mat;fabric_b=reader_vec;end
        else if(state==GEMV_OUT) begin fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MOV;fabric_word[`CSR_CTX_SRCA_KIND_LSB +: 4]=`CSR_CTX_SRC_ACC;end
        else case(op)
            0: begin fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MOV;fabric_word[`CSR_CTX_SRCA_KIND_LSB +: 4]=`CSR_CTX_SRC_IMMEDIATE;end
            1,8: fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MOV;
            2: fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_ADD;
            3: fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_SUB;
            4,9: fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MUL;
            default: begin fabric_word[`CSR_CTX_OPCODE_LSB +: 6]=`CSR_CTX_OP_MAC;fabric_word[`CSR_CTX_ACC_WRITE_LSB]=1;end
        endcase
        numeric_fault=0;rounded_data=fabric_data;nonzero=0;value=0;mag=0;
        for(i=0;i<32;i=i+1) if(lane_mask[i]) begin
            if(op==5) begin
                value=$signed({fabric_acc[i*64+63],fabric_acc[i*64 +: 64]});
                mag=value<0 ? -value : value;
                if(shift!=0) mag=(mag+(65'sd1<<(shift-1)))>>shift;
                value=value<0 ? -mag : mag;
                if(value>65'sd67108863||value< -65'sd67108864) numeric_fault=4;
                rounded_data[i*27 +: 27]=value[26:0];
            end
            if(op==8) begin
                value=$signed({{38{fabric_data[i*27+26]}},fabric_data[i*27 +: 27]});
                mag=value<0 ? -value : value;mag=(mag+2)>>2;value=value<0 ? -mag : mag;
                if(value>65'sd8388607||value< -65'sd8388608) numeric_fault=4;
                rounded_data[i*27 +: 27]={value[24:0],2'b0};
            end
            if(rounded_data[i*27 +: 27]!=0) nonzero=1;
        end
    end
    vector_workspace workspace (
        .clk(clk),.rst(rst),.cancel(cancel),.rd_valid(wrd_valid),.rd_ready(wrd_ready),.rd_slot(wrd_slot),.rd_block(wrd_block),
        .rsp_valid(wrsp_valid),.rsp_ready(wrsp_ready),.rsp_data(wrsp_data),.rsp_mask(wrsp_mask),.rsp_fault(wrsp_fault),
        .wr_valid(write_take),.wr_ready(unused_wr_ready),.wr_slot(dest),.wr_block(block_idx),
        .wr_data(state==HOST ? host_fill_data : commit_data),.wr_mask(state==HOST ? host_mask : lane_mask),
        .invalidate(invalidate),.invalidate_slot(invalid_slot),.publish(publish),.publish_slot(dest),.publish_length(state==HOST ? length : output_length),
        .slot_valid(slot_valid),.slot_lengths(slot_lengths));
    kernel_fabric fabric (
        .clk(clk),.rst(rst),.cancel(cancel||state==FAIL),.req_valid(active&&fabric_issue),.req_ready(fabric_ready),
        .req_mode(full_mode),.req_word(fabric_word),.req_a(fabric_a),.req_b(fabric_b),
        .req_mask(state==GEMV_MAC ? reader_mask : lane_mask),.req_job(rsp_job),.req_tag(rsp_tag),.req_fmt(rsp_fmt),
        .rsp_valid(fabric_valid),.rsp_ready(fabric_retire),.rsp_data(fabric_data),.rsp_acc(fabric_acc),.rsp_fault(fabric_fault));
    operand_reader reader (
        .clk(clk),.rst(rst),.cancel(cancel),.req_valid(state==GEMV_READ),.req_ready(reader_req_ready),
        .req_mode(2'd2),.req_trans(trans),.req_rows(rows),.req_cols({4'b0,cols}),.req_out({4'b0,block_idx,5'b0}),
        .req_red({3'b0,reduction}),.req_step(3'b0),.req_vec_base(12'b0),.req_vec_plane(2'b0),.req_scale(18'b0),
        .req_key(key),.req_mat_generation(generation),.req_vec_generation(32'b0),.req_job(rsp_job),.req_tag(rsp_tag),.req_fmt(rsp_fmt),.req_last(1'b0),
        .mat_valid(mat_valid),.mat_ready(mat_ready),.mat_dense(mat_dense),.mat_mask(mat_mask),.mat_addr(mat_addr),.mat_key(mat_key),.mat_generation(mat_generation),
        .mem_job(mem_job),.mem_tag(mem_tag),.mem_fmt(mem_fmt),.mat_rsp_valid(mat_rsp_valid),.mat_rsp_ready(mat_rsp_ready),.mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks),.mat_rsp_mask(mat_rsp_mask),.mat_rsp_generation(mat_rsp_generation),.mat_rsp_job(mat_rsp_job),.mat_rsp_tag(mat_rsp_tag),.mat_rsp_fmt(mat_rsp_fmt),.mat_rsp_fault(mat_rsp_fault),
        .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_plane(unused_vec_plane),.vec_mask(vec_mask),.vec_addr(vec_addr),.vec_generation(unused_vec_generation),
        .vec_rsp_valid(state==GEMV_WAIT&&wrsp_valid[0]),.vec_rsp_ready(vec_rsp_ready),.vec_rsp_data(vec_response),.vec_rsp_mask(vec_mask_q),.vec_rsp_generation(32'b0),
        .vec_rsp_job(rsp_job),.vec_rsp_tag(rsp_tag),.vec_rsp_fmt(rsp_fmt),.vec_rsp_fault(wrsp_fault[3:0]),
        .rsp_valid(reader_rsp_valid),.rsp_ready(state==GEMV_MAC&&fabric_ready||(state==GEMV_WAIT&&reader_rsp_valid&&(reader_fault!=0||reader_job!=rsp_job||reader_tag!=rsp_tag||reader_fmt!=rsp_fmt))),
        .rsp_mat(reader_mat),.rsp_vec(reader_vec),.rsp_mask(reader_mask),.rsp_fault(reader_fault),.rsp_job(reader_job),.rsp_tag(reader_tag),.rsp_fmt(reader_fmt),.rsp_last(unused_reader_last));
    always @(posedge clk) begin
        if(!active) begin
            state<=IDLE;op<=0;src_a<=0;src_b<=0;dest<=0;length<=0;rows<=0;cols<=0;trans<=0;scalar_a<=0;scalar_b<=0;shift<=0;key<=0;generation<=0;
            block_idx<=0;reduction<=0;a_data<=0;b_data<=0;energy<=0;reduction_acc<=0;energy_lane<=0;rsp_fault<=0;rsp_data<=0;rsp_nonzero<=0;rsp_job<=0;rsp_tag<=0;rsp_fmt<=0;host_fault<=0;vec_mask_q<=0;
            for(j=0;j<128;j=j+1) candidate[j]<=0;
            for(j=0;j<16;j=j+1) begin owners_job[j]<=0;owners_fmt[j]<=0;end
        end else begin
            if(vec_valid&&vec_ready) vec_mask_q<=vec_mask;
            case(state)
                IDLE: begin
                    if(req_valid&&req_ready) begin
                        op<=req_op;src_a<=req_src_a;src_b<=req_src_b;dest<=req_dst;length<=req_length;rows<=req_rows;cols<=req_cols;trans<=req_trans;
                        scalar_a<=req_scalar_a;scalar_b<=req_scalar_b;shift<=req_shift;key<=req_key;generation<=req_generation;
                        rsp_job<=req_job;rsp_tag<=req_tag;rsp_fmt<=req_fmt;rsp_fault<=0;rsp_data<=0;rsp_nonzero<=0;energy<=0;block_idx<=0;reduction<=0;state<=CHECK;
                    end else if(host_begin_valid&&host_begin_ready) begin
                        dest<=host_slot;length<=host_length;block_idx<=0;host_fault<=0;
                        owners_job[host_slot]<=host_job;owners_fmt[host_slot]<=host_fmt;
                        if(host_fmt!=1||host_length==0||host_length>128) host_fault<=1;else state<=HOST;
                    end
                end
                CHECK: begin
                    if(rsp_fmt!=1||op>10||(!scalar_op&&(length==0||length>128))||(op==6&&(rows==0||rows>128||cols==0||cols>96))) begin rsp_fault<=1;state<=FAIL;end
                    else if(op!=0&&!scalar_op&&(!slot_valid[src_a]||slot_lengths[int'(src_a)*8 +: 8]<(op==6 ? reduction_length : length)||owners_job[src_a]!=rsp_job||owners_fmt[src_a]!=rsp_fmt)) begin rsp_fault<=2;state<=FAIL;end
                    else if((op==2||op==3)&&(!slot_valid[src_b]||slot_lengths[int'(src_b)*8 +: 8]<length||owners_job[src_b]!=rsp_job||owners_fmt[src_b]!=rsp_fmt)) begin rsp_fault<=2;state<=FAIL;end
                    else if(op==6) state<=CLEAR;
                    else if(op==0) state<=EXEC;
                    else if(scalar_op) begin
                        a_data<=op==10 ? {{30{27'b0}},scalar_b,scalar_a} : {{31{27'b0}},scalar_a};
                        b_data<=op==10 ? {{30{27'b0}},scalar_b,scalar_a} : {{31{27'b0}},scalar_b};
                        state<=op==10 ? CLEAR : EXEC;
                    end else state<=READ_VEC;
                end
                READ_VEC: if(wrd_ready[0]&&((op!=2&&op!=3)||wrd_ready[1])) state<=WAIT_VEC;
                WAIT_VEC: if(wrsp_valid[0]&&((op!=2&&op!=3)||wrsp_valid[1])) begin
                    if(wrsp_fault[3:0]!=0||((op==2||op==3)&&wrsp_fault[7:4]!=0)) begin rsp_fault<=2;state<=FAIL;end
                    else begin
                        a_data<=wrsp_data[863:0];b_data<=op==7 ? wrsp_data[863:0] : op==4||op==5 ? {32{scalar_a}} : wrsp_data[1727:864];
                        state<=op==5||op==7 ? CLEAR : EXEC;
                    end
                end
                CLEAR: if(fabric_ready) state<=WAIT_CLEAR;
                WAIT_CLEAR: if(fabric_valid) begin
                    if(fabric_fault) begin rsp_fault<=3;state<=FAIL;end
                    else state<=op==6 ? GEMV_READ : EXEC;
                end
                EXEC: if(fabric_ready) state<=WAIT_EXEC;
                WAIT_EXEC: if(fabric_valid) begin
                    if(fabric_fault||numeric_fault!=0) begin rsp_fault<=fabric_fault ? 3 : numeric_fault;state<=FAIL;end
                    else if(op==7||op==10) begin reduction_acc<=fabric_acc;energy_lane<=0;state<=REDUCE;end
                    else if(scalar_op) begin rsp_data<=scalar_result;rsp_nonzero<=scalar_result!=0;state<=DONE;end
                    else begin
                        for(j=0;j<32;j=j+1) candidate[int'(block_idx)*32+j]<=lane_mask[j] ? rounded_data[j*27 +: 27] : 27'b0;
                        rsp_nonzero<=rsp_nonzero||nonzero;
                        if(last_block) begin block_idx<=0;state<=INVALIDATE;end else begin block_idx<=block_idx+1'b1;state<=op==0 ? EXEC : READ_VEC;end
                    end
                end
                REDUCE: begin
                    if(energy_term[63]||energy_next[64:63]!=0) begin rsp_fault<=4;state<=FAIL;end
                    else begin
                        energy<=energy_next[63:0];
                        if(energy_last) begin
                            if(scalar_op||last_block) begin rsp_data<=energy_next[63:0];rsp_nonzero<=energy_next!=0;state<=DONE;end
                            else begin block_idx<=block_idx+1'b1;state<=READ_VEC;end
                        end else energy_lane<=energy_lane+1'b1;
                    end
                end
                GEMV_READ: if(reader_req_ready) state<=GEMV_WAIT;
                GEMV_WAIT: if(reader_rsp_valid) begin
                    if(reader_fault!=0||reader_job!=rsp_job||reader_tag!=rsp_tag||reader_fmt!=rsp_fmt) begin rsp_fault<=5;state<=FAIL;end else state<=GEMV_MAC;
                end
                GEMV_MAC: if(fabric_ready) state<=GEMV_MAC_WAIT;
                GEMV_MAC_WAIT: if(fabric_valid) begin
                    if(fabric_fault) begin rsp_fault<=3;state<=FAIL;end
                    else if(reduction+1==reduction_length) state<=GEMV_OUT;
                    else begin reduction<=reduction+1'b1;state<=GEMV_READ;end
                end
                GEMV_OUT: if(fabric_ready) state<=GEMV_OUT_WAIT;
                GEMV_OUT_WAIT: if(fabric_valid) begin
                    if(fabric_fault) begin rsp_fault<=3;state<=FAIL;end
                    else begin
                        for(j=0;j<32;j=j+1) candidate[int'(block_idx)*32+j]<=lane_mask[j] ? fabric_data[j*27 +: 27] : 27'b0;
                        rsp_nonzero<=rsp_nonzero||nonzero;
                        if(last_block) begin block_idx<=0;state<=INVALIDATE;end
                        else begin block_idx<=block_idx+1'b1;reduction<=0;state<=CLEAR;end
                    end
                end
                INVALIDATE: state<=COMMIT;
                COMMIT: if(last_block) state<=PUBLISH;else block_idx<=block_idx+1'b1;
                PUBLISH: begin owners_job[dest]<=rsp_job;owners_fmt[dest]<=rsp_fmt;state<=DONE;end
                FAIL: state<=DONE;
                DONE: if(rsp_ready) state<=IDLE;
                HOST: if(host_fill_valid&&host_fill_ready) begin
                    if(host_bad) begin host_fault<=1;state<=IDLE;end
                    else if(host_last) state<=IDLE;
                    else block_idx<=block_idx+1'b1;
                end
                default: state<=IDLE;
            endcase
        end
    end
    wire unused_host_tag=|host_tag;
    wire unused_vec_address=|vec_addr;
endmodule
