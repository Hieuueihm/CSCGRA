`include "memory_defs.vh"
// Four ordered frame credits; independent matrix/vector join and two-block cache.
// Cancel must also flush the shared pool and operator endpoint before reuse.
module operator_frame_feeder (
    input wire clk,rst,cancel,
    input wire command_start,
    input wire req_valid,output wire req_ready,
    input wire req_dense,req_rfour,req_trans,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols,req_out,req_red,req_vec_length,
    input wire [2:0] req_step,
    input wire [8:0] req_vec_base,
    input wire [17:0] req_scale,
    input wire [127:0] req_key,
    input wire [31:0] req_generation,
    input wire [15:0] req_job,req_tag,
    input wire [7:0] req_fmt,
    input wire req_last,
    input wire matrix_valid,
    input wire [7:0] matrix_rows,
    input wire [10:0] matrix_cols,
    input wire [127:0] matrix_key,
    input wire [31:0] matrix_generation,
    input wire [15:0] matrix_job,
    input wire [7:0] matrix_fmt,
    output wire mat_valid,input wire mat_ready,
    output wire mat_dense,
    output reg [31:0] mat_mask,
    output reg [287:0] mat_addr,
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
    input wire [3:0] mat_rsp_fault,
    output wire vec_valid,input wire vec_ready,
    output wire [8:0] vec_block,
    output reg [31:0] vec_mask,
    output wire [15:0] vec_tag,
    input wire vec_rsp_valid,output wire vec_rsp_ready,
    input wire [863:0] vec_rsp_data,
    input wire [31:0] vec_rsp_mask,
    input wire [15:0] vec_rsp_tag,
    input wire [3:0] vec_rsp_fault,
    output wire rsp_valid,input wire rsp_ready,
    output wire [863:0] rsp_mat,rsp_vec,
    output wire [31:0] rsp_mask,
    output reg [3:0] rsp_fault,
    output reg [15:0] rsp_job,rsp_tag,
    output reg [7:0] rsp_fmt,
    output reg rsp_last,
    output wire [13:0] rsp_frame
);
    reg [2:0] count;
    reg [1:0] head,tail;
    reg [13:0] serial;
    reg [13:0] frame [0:3];
    reg dense [0:3],rfour [0:3],trans [0:3],last [0:3];
    reg [7:0] rows [0:3],fmt [0:3];
    reg [10:0] cols [0:3],out_index [0:3],red_index [0:3];
    reg [2:0] step [0:3];
    reg [8:0] vector_base [0:3];
    reg [17:0] scale [0:3];
    reg [127:0] key [0:3];
    reg [31:0] generation [0:3];
    reg [15:0] job [0:3],tag [0:3];
    reg [1:0] pass [0:3];
    reg matrix_done [0:3],vector_done [0:3];
    reg [3:0] fault [0:3];
    reg [863:0] coefficients [0:3],vectors [0:3];
    reg [31:0] masks [0:3];
    reg vector_pending;
    reg [1:0] matrix_count;
    reg matrix_head,matrix_tail;
    reg [1:0] matrix_owners [0:1];
    reg [31:0] matrix_masks [0:1];
    reg [15:0] matrix_tokens [0:1];
    reg matrix_busy [0:3];
    wire matrix_pending=matrix_count!=0;
    wire [1:0] matrix_owner=matrix_owners[matrix_head];
    wire [31:0] matrix_expected_mask=matrix_masks[matrix_head];
    wire [15:0] matrix_token=matrix_tokens[matrix_head];
    reg [1:0] vector_owner;
    reg [31:0] vector_expected_mask;
    reg [15:0] vector_token;
    reg [8:0] vector_address;
    // Non-dense Phi is stored as eight 32-row sign words per column tile.
    // These two entries are raw signs, so changing an output scale does not
    // change the cached source data.  They are deliberately command-local.
    reg tile_valid [0:1],tile_pending [0:1];
    reg [255:0] tile_data [0:1],tile_row_mask [0:1];
    reg [127:0] tile_key [0:1];
    reg [31:0] tile_generation [0:1];
    reg [15:0] tile_job [0:1];
    reg [7:0] tile_fmt [0:1],tile_rows [0:1];
    reg [10:0] tile_cols [0:1],tile_row_block [0:1],tile_col_block [0:1];
    reg tile_replacement;
    reg matrix_tile [0:1];
    reg [1:0] matrix_tile_entry [0:1];
    reg cache_valid [0:1];
    reg [8:0] cache_address [0:1];
    reg [31:0] cache_mask [0:1];
    reg [863:0] cache_data [0:1];
    reg replacement;
    reg [1:0] matrix_slot,vector_slot;
    reg matrix_found,vector_found,any_fault;
    reg matrix_offer,vector_offer;
    reg [1:0] matrix_offer_slot,vector_offer_slot;
    reg [31:0] vector_request_mask;
    reg [8:0] vector_request_address;
    reg [863:0] gathered_matrix;
    reg [863:0] cached_matrix;
    reg missing;
    reg cached_missing;
    reg signed [17:0] coefficient,cached_coefficient;
    reg [3:0] request_fault;
    reg [31:0] request_lane_mask;
    reg matrix_coalesce,matrix_tile_issue;
    reg [1:0] matrix_tile_choice;
    reg matrix_offer_tile;
    reg [1:0] matrix_offer_tile_entry;
    reg tile_hit_found;
    reg [1:0] tile_hit_slot,tile_hit_entry;
    reg tile_valid_match,tile_pending_match,tile_alloc_found;
    reg [1:0] tile_valid_entry,tile_pending_entry,tile_alloc_entry;
    reg [7:0] matrix_tile_mask;
    reg matrix_frame_present;
    integer lane,i,j,index,output_index,reduction,row_index,col_index,bank,address,lane_pass,comb_entry;
    integer request_outputs,request_reductions,outputs,reductions;
    wire active=!rst&&!cancel&&!command_start;
    wire pop=rsp_valid&&rsp_ready;
    wire take=req_valid&&req_ready;
    wire [1:0] ms=matrix_slot;
    wire response_four=!dense[matrix_owner]&&(rfour[matrix_owner]!=trans[matrix_owner]);
    wire matrix_pop=mat_rsp_valid&&mat_rsp_ready;
    wire matrix_take=mat_valid&&mat_ready;
    wire four_passes=!dense[ms]&&(rfour[ms]!=trans[ms]);
    assign req_ready=active&&!any_fault&&(count<4||pop);
    assign rsp_valid=active&&count!=0&&(fault[head]!=0||(matrix_done[head]&&vector_done[head]));
    assign rsp_mat=fault[head]==0 ? coefficients[head] : 864'b0;
    assign rsp_vec=fault[head]==0 ? vectors[head] : 864'b0;
    assign rsp_mask=fault[head]==0 ? masks[head] : 32'b0;
    assign rsp_frame=frame[head];
    always @* begin
        rsp_fault=fault[head];rsp_job=job[head];rsp_tag=tag[head];rsp_fmt=fmt[head];rsp_last=last[head];
    end
    assign mat_valid=active&&matrix_found&&!matrix_coalesce&&(matrix_count<2||matrix_pop)&&mat_mask!=0;
    assign mat_rsp_ready=active&&matrix_pending;
    assign mat_dense=dense[ms];assign mat_key=key[ms];assign mat_generation=generation[ms];
    assign mem_job=job[ms];assign mem_fmt=fmt[ms];assign mem_tag={frame[ms],pass[ms]};
    assign vec_valid=active&&vector_found&&!vector_pending;
    assign vec_rsp_ready=active&&vector_pending;
    assign vec_block=vector_request_address;
    assign vec_tag={frame[vector_slot],2'b0};
    always @* vec_mask=vector_request_mask;

    function automatic [31:0] block_mask(input integer total,input integer start);
        integer n;
        begin
            block_mask=0;
            for(n=0;n<32;n=n+1)if(start+n<total)block_mask[n]=1;
        end
    endfunction
    function automatic [863:0] expand_vector(input [863:0] data,input integer slot);
        integer n,k;
        begin
            expand_vector=0;
            for(n=0;n<32;n=n+1)begin
                k=rfour[slot] ? 8*(n%4)+int'(step[slot]) : int'(red_index[slot][4:0]);
                if(masks[slot][n])expand_vector[n*27 +:27]=data[k*27 +:27];
            end
        end
    endfunction
    function automatic cache_hit(input integer slot);
        integer c;
        reg [31:0] needed;
        begin
            needed=block_mask(trans[slot] ? int'(rows[slot]) : int'(cols[slot]),(int'(red_index[slot])>>5)*32);
            cache_hit=0;
            for(c=0;c<2;c=c+1)
                if(cache_valid[c]&&cache_address[c]==vector_base[slot]+red_index[slot][10:5]&&
                   (cache_mask[c]&needed)==needed)cache_hit=1;
        end
    endfunction
    function automatic tile_eligible(input integer slot);
        begin tile_eligible=!dense[slot]&&(rfour[slot]==trans[slot]); end
    endfunction
    function automatic [10:0] tile_rows_block(input integer slot);
        begin tile_rows_block=(trans[slot] ? red_index[slot] : out_index[slot])>>5; end
    endfunction
    function automatic [10:0] tile_columns_block(input integer slot);
        begin tile_columns_block=(trans[slot] ? out_index[slot] : red_index[slot])>>3; end
    endfunction
    function automatic [7:0] tile_bank_mask(input integer slot);
        integer b;
        begin
            tile_bank_mask=0;
            for(b=0;b<8;b=b+1)
                if(int'(tile_columns_block(slot))*8+b<int'(cols[slot]))tile_bank_mask[b]=1;
        end
    endfunction
    function automatic tile_match(input integer entry,input integer slot,input pending);
        begin
            tile_match=(pending ? tile_pending[entry] : tile_valid[entry])&&
                tile_key[entry]==key[slot]&&tile_generation[entry]==generation[slot]&&
                tile_job[entry]==job[slot]&&tile_fmt[entry]==fmt[slot]&&
                tile_rows[entry]==rows[slot]&&tile_cols[entry]==cols[slot]&&
                tile_row_block[entry]==tile_rows_block(slot)&&tile_col_block[entry]==tile_columns_block(slot);
        end
    endfunction

    // One address generator serves the selected matrix slot. The external owner
    // may serialize grants; frame credits do not imply endpoint initiation II1.
    always @* begin
        matrix_found=0;vector_found=0;matrix_slot=head;vector_slot=head;any_fault=0;
        tile_hit_found=0;tile_hit_slot=head;tile_hit_entry=0;
        for(i=0;i<4;i=i+1)begin
            index=(int'(head)+i)&3;
            if(i<int'(count))begin
                if(fault[index]!=0)any_fault=1;
                if(!matrix_found&&!matrix_done[index]&&!matrix_busy[index]&&fault[index]==0&&
                   !(tile_eligible(index)&&(tile_match(0,index,0)||tile_match(1,index,0))))begin matrix_found=1;matrix_slot=2'(index);end
                if(!vector_found&&!vector_done[index]&&fault[index]==0&&!cache_hit(index))begin vector_found=1;vector_slot=2'(index);end
                if(!tile_hit_found&&!matrix_done[index]&&!matrix_busy[index]&&fault[index]==0&&tile_eligible(index))begin
                    if(tile_match(0,index,0))begin tile_hit_found=1;tile_hit_slot=2'(index);tile_hit_entry=0;end
                    else if(tile_match(1,index,0))begin tile_hit_found=1;tile_hit_slot=2'(index);tile_hit_entry=1;end
                end
            end
        end
        // Once VALID is offered, retain that owner through a stalled grant.
        // An older response or a younger fault may not replace the payload.
        if(matrix_offer)begin matrix_found=1;matrix_slot=matrix_offer_slot;end
        if(vector_offer)begin vector_found=1;vector_slot=vector_offer_slot;end
        vector_request_address=vector_base[vector_slot]+red_index[vector_slot][10:5];
        vector_request_mask=block_mask(trans[vector_slot] ? int'(rows[vector_slot]) : int'(cols[vector_slot]),(int'(red_index[vector_slot])>>5)*32);
        request_outputs=req_trans ? int'(req_cols) : int'(req_rows);
        request_reductions=req_trans ? int'(req_rows) : int'(req_cols);
        request_fault=0;request_lane_mask=0;
        if(req_rows==0||req_rows>128||req_cols==0||int'(req_cols)>(req_dense ? 96 : 1024)||
           req_fmt!=1||(!req_dense&&$signed(req_scale)<=0))request_fault=`CSR_MEM_FAULT_SHAPE;
        else if(!matrix_valid||matrix_rows!=req_rows||matrix_cols!=req_cols||matrix_key!=req_key||
                matrix_generation!=req_generation||matrix_job!=req_job||matrix_fmt!=req_fmt)request_fault=`CSR_MEM_FAULT_KEY;
        else if(int'(req_out)>=request_outputs||int'(req_red)>=request_reductions||
                (req_rfour&&(req_out[2:0]!=0||req_red[4:0]!=0))||(!req_rfour&&(req_out[4:0]!=0||req_step!=0))||
                req_vec_length<request_reductions||req_vec_length>1024||int'(req_vec_base)+(request_reductions+31)/32>480)
            request_fault=`CSR_MEM_FAULT_RANGE;
        for(lane=0;lane<32;lane=lane+1)
            request_lane_mask[lane]=int'(req_out)+(req_rfour ? lane/4 : lane)<request_outputs&&
                int'(req_red)+(req_rfour ? 8*(lane%4)+int'(req_step) : 0)<request_reductions;
        outputs=trans[ms] ? int'(cols[ms]) : int'(rows[ms]);
        reductions=trans[ms] ? int'(rows[ms]) : int'(cols[ms]);
        mat_mask=0;mat_addr=0;
        output_index=0;reduction=0;row_index=0;col_index=0;bank=0;address=0;lane_pass=0;
        for(lane=0;lane<32;lane=lane+1)begin
            output_index=int'(out_index[ms])+(rfour[ms] ? lane/4 : lane);
            reduction=int'(red_index[ms])+(rfour[ms] ? 8*(lane%4)+int'(step[ms]) : 0);
            row_index=trans[ms] ? reduction : output_index;
            col_index=trans[ms] ? output_index : reduction;
            lane_pass=four_passes ? (rfour[ms] ? lane%4 : lane/8) : 0;
            if(output_index<outputs&&reduction<reductions&&lane_pass==int'(pass[ms]))begin
                bank=dense[ms] ? (row_index+col_index)%32 : col_index%8;
                address=dense[ms] ? row_index*((int'(cols[ms])+31)/32)+col_index/32 :
                    (col_index/8)*((int'(rows[ms])+31)/32)+row_index/32;
                mat_mask[bank]=1;mat_addr[bank*9 +:9]=9'(address);

            end
        end
        matrix_frame_present=mat_mask!=0;
        tile_valid_match=0;tile_pending_match=0;tile_alloc_found=0;matrix_tile_mask=0;
        tile_valid_entry=0;tile_pending_entry=0;tile_alloc_entry=tile_replacement;
        if(matrix_found&&tile_eligible(ms))begin
            for(comb_entry=0;comb_entry<2;comb_entry=comb_entry+1)begin
                if(!tile_valid_match&&tile_match(comb_entry,ms,0))begin tile_valid_match=1;tile_valid_entry=2'(comb_entry);end
                if(!tile_pending_match&&tile_match(comb_entry,ms,1))begin tile_pending_match=1;tile_pending_entry=2'(comb_entry);end
            end
            for(comb_entry=0;comb_entry<2;comb_entry=comb_entry+1)
                if(!tile_alloc_found&&!tile_valid[comb_entry]&&!tile_pending[comb_entry])begin tile_alloc_found=1;tile_alloc_entry=2'(comb_entry);end
            if(!tile_alloc_found&&!tile_pending[tile_replacement])begin
                tile_alloc_found=1;tile_alloc_entry=tile_replacement;
            end
        end
        matrix_coalesce=matrix_found&&matrix_frame_present&&tile_eligible(ms)&&tile_pending_match&&!matrix_offer;
        matrix_tile_issue=matrix_found&&matrix_frame_present&&tile_eligible(ms)&&!tile_valid_match&&!tile_pending_match&&tile_alloc_found;
        matrix_tile_choice=matrix_tile_issue ? tile_alloc_entry : 0;
        if(matrix_offer)begin
            matrix_coalesce=0;
            matrix_tile_issue=matrix_offer_tile;
            matrix_tile_choice=matrix_offer_tile_entry;
        end
        if(matrix_tile_issue)begin
            matrix_tile_mask=tile_bank_mask(ms);
            mat_mask={24'b0,matrix_tile_mask};
            mat_addr=0;
            for(bank=0;bank<8;bank=bank+1)
                if(matrix_tile_mask[bank])mat_addr[bank*9 +:9]=9'(int'(tile_columns_block(ms))*((int'(rows[ms])+31)/32)+int'(tile_rows_block(ms)));
        end
    end
    integer response_lane,response_output,response_reduction,response_row,response_col,response_bank,response_pass;
    integer cached_lane,cached_output,cached_reduction,cached_row,cached_col,cached_bank;
    always @* begin
        gathered_matrix=coefficients[matrix_owner];missing=0;coefficient=0;
        response_output=0;response_reduction=0;response_row=0;response_col=0;response_bank=0;response_pass=0;
        for(response_lane=0;response_lane<32;response_lane=response_lane+1) begin
            response_output=int'(out_index[matrix_owner])+(rfour[matrix_owner] ? response_lane/4 : response_lane);
            response_reduction=int'(red_index[matrix_owner])+(rfour[matrix_owner] ? 8*(response_lane%4)+int'(step[matrix_owner]) : 0);
            response_row=trans[matrix_owner] ? response_reduction : response_output;
            response_col=trans[matrix_owner] ? response_output : response_reduction;
            response_pass=response_four ? (rfour[matrix_owner] ? response_lane%4 : response_lane/8) : 0;
            if(response_row<int'(rows[matrix_owner])&&response_col<int'(cols[matrix_owner])&&response_pass==int'(matrix_token[1:0])) begin
                response_bank=dense[matrix_owner] ? (response_row+response_col)%32 : response_col%8;
                if(dense[matrix_owner])coefficient=$signed(mat_rsp_data[response_bank*18 +:18]);
                else begin
                    coefficient=mat_rsp_data[response_bank*32+response_row%32] ? $signed(scale[matrix_owner]) : -$signed(scale[matrix_owner]);
                    if(!mat_rsp_masks[response_bank*32+response_row%32])missing=1;
                end
                gathered_matrix[response_lane*27 +:27]={{9{coefficient[17]}},coefficient};
            end
        end
    end
    // A tile hit uses the same lane mapping as an endpoint response.  A row
    // which was not valid in the prefetched response remains a source fault;
    // it must never be hidden by a later cache hit.
    always @* begin
        cached_matrix=coefficients[tile_hit_slot];cached_missing=0;cached_coefficient=0;
        cached_output=0;cached_reduction=0;cached_row=0;cached_col=0;cached_bank=0;
        for(cached_lane=0;cached_lane<32;cached_lane=cached_lane+1)begin
            cached_output=int'(out_index[tile_hit_slot])+(rfour[tile_hit_slot] ? cached_lane/4 : cached_lane);
            cached_reduction=int'(red_index[tile_hit_slot])+(rfour[tile_hit_slot] ? 8*(cached_lane%4)+int'(step[tile_hit_slot]) : 0);
            cached_row=trans[tile_hit_slot] ? cached_reduction : cached_output;
            cached_col=trans[tile_hit_slot] ? cached_output : cached_reduction;
            if(cached_row<int'(rows[tile_hit_slot])&&cached_col<int'(cols[tile_hit_slot]))begin
                cached_bank=cached_col%8;
                cached_coefficient=tile_data[tile_hit_entry][cached_bank*32+cached_row%32] ? $signed(scale[tile_hit_slot]) : -$signed(scale[tile_hit_slot]);
                if(!tile_row_mask[tile_hit_entry][cached_bank*32+cached_row%32])cached_missing=1;
                cached_matrix[cached_lane*27 +:27]={{9{cached_coefficient[17]}},cached_coefficient};
            end
        end
    end
    integer q,c,hit_count;
    reg [31:0] accepted_frames,matrix_grants,vector_grants,cache_hits;
    reg [2:0] peak_occupancy;
    always @(posedge clk)begin
        if(!active)begin
            matrix_offer<=0;vector_offer<=0;matrix_offer_slot<=0;vector_offer_slot<=0;matrix_offer_tile<=0;matrix_offer_tile_entry<=0;
            count<=0;head<=0;tail<=0;serial<=0;matrix_count<=0;matrix_head<=0;matrix_tail<=0;vector_pending<=0;
            vector_owner<=0;vector_token<=0;
            vector_expected_mask<=0;vector_address<=0;replacement<=0;tile_replacement<=0;
            accepted_frames<=0;matrix_grants<=0;vector_grants<=0;cache_hits<=0;peak_occupancy<=0;
            for(c=0;c<2;c=c+1)begin
                matrix_owners[c]<=0;matrix_masks[c]<=0;matrix_tokens[c]<=0;matrix_tile[c]<=0;matrix_tile_entry[c]<=0;
                cache_valid[c]<=0;cache_address[c]<=0;cache_mask[c]<=0;cache_data[c]<=0;
                tile_valid[c]<=0;tile_pending[c]<=0;tile_data[c]<=0;tile_row_mask[c]<=0;tile_key[c]<=0;tile_generation[c]<=0;
                tile_job[c]<=0;tile_fmt[c]<=0;tile_rows[c]<=0;tile_cols[c]<=0;tile_row_block[c]<=0;tile_col_block[c]<=0;
            end
            for(q=0;q<4;q=q+1)begin
                matrix_busy[q]<=0;frame[q]<=0;dense[q]<=0;rfour[q]<=0;trans[q]<=0;last[q]<=0;rows[q]<=0;cols[q]<=0;out_index[q]<=0;red_index[q]<=0;
                step[q]<=0;vector_base[q]<=0;scale[q]<=0;key[q]<=0;generation[q]<=0;job[q]<=0;tag[q]<=0;fmt[q]<=0;
                pass[q]<=0;matrix_done[q]<=0;vector_done[q]<=0;fault[q]<=0;coefficients[q]<=0;vectors[q]<=0;masks[q]<=0;
            end
        end else begin
            if(mat_valid&&mat_ready)matrix_offer<=0;
            else if(mat_valid&&!mat_ready)begin
                matrix_offer<=1;matrix_offer_slot<=matrix_slot;matrix_offer_tile<=matrix_tile_issue;matrix_offer_tile_entry<=matrix_tile_choice;
            end
            if(vec_valid&&vec_ready)vector_offer<=0;
            else if(vec_valid&&!vec_ready)begin vector_offer<=1;vector_offer_slot<=vector_slot;end
            case({take,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(pop)head<=head+1'b1;
            // Cache hits copy an expanded frame; queued frames never retain an
            // eviction-sensitive pointer to a cache entry.
            hit_count=0;
            for(q=0;q<4;q=q+1)if((((q-int'(head))&3)<int'(count))&&!vector_done[q]&&fault[q]==0)begin
                for(c=0;c<2;c=c+1)
                    if(cache_valid[c]&&cache_address[c]==vector_base[q]+red_index[q][10:5]&&(cache_mask[c]&block_mask(trans[q] ? int'(rows[q]) : int'(cols[q]),(int'(red_index[q])>>5)*32))==block_mask(trans[q] ? int'(rows[q]) : int'(cols[q]),(int'(red_index[q])>>5)*32))begin
                        vectors[q]<=expand_vector(cache_data[c],q);vector_done[q]<=1;hit_count=hit_count+1;
                    end
            end
            cache_hits<=cache_hits+hit_count;
            // Phi tile cache expands only one queued frame per cycle.  It may
            // run with an unrelated endpoint response but never owns that slot.
            if(tile_hit_found)begin
                matrix_done[tile_hit_slot]<=1;coefficients[tile_hit_slot]<=cached_matrix;
                if(cached_missing&&fault[tile_hit_slot]==0)fault[tile_hit_slot]<=`CSR_MEM_FAULT_SOURCE;
            end
            case({matrix_take,matrix_pop})
                2'b10:matrix_count<=matrix_count+1'b1;
                2'b01:matrix_count<=matrix_count-1'b1;
                default:matrix_count<=matrix_count;
            endcase
            if(matrix_take)begin
                matrix_owners[matrix_tail]<=matrix_slot;matrix_tokens[matrix_tail]<=mem_tag;matrix_masks[matrix_tail]<=mat_mask;
                matrix_tile[matrix_tail]<=matrix_tile_issue;matrix_tile_entry[matrix_tail]<=matrix_tile_choice;
                matrix_tail<=~matrix_tail;matrix_busy[matrix_slot]<=1;
                matrix_grants<=matrix_grants+1'b1;
                if(matrix_tile_issue)begin
                    tile_valid[matrix_tile_choice]<=0;tile_pending[matrix_tile_choice]<=1;
                    tile_key[matrix_tile_choice]<=key[matrix_slot];tile_generation[matrix_tile_choice]<=generation[matrix_slot];
                    tile_job[matrix_tile_choice]<=job[matrix_slot];tile_fmt[matrix_tile_choice]<=fmt[matrix_slot];
                    tile_rows[matrix_tile_choice]<=rows[matrix_slot];tile_cols[matrix_tile_choice]<=cols[matrix_slot];
                    tile_row_block[matrix_tile_choice]<=tile_rows_block(matrix_slot);tile_col_block[matrix_tile_choice]<=tile_columns_block(matrix_slot);
                    tile_replacement<=~matrix_tile_choice;
                end
            end
            if(matrix_found&&mat_mask==0)begin
                if(!four_passes||pass[ms]==3)matrix_done[ms]<=1;
                else pass[ms]<=pass[ms]+1'b1;
            end
            if(mat_rsp_valid&&mat_rsp_ready)begin
                matrix_head<=~matrix_head;matrix_busy[matrix_owner]<=0;coefficients[matrix_owner]<=gathered_matrix;
                if(!response_four||pass[matrix_owner]==3)matrix_done[matrix_owner]<=1;
                else pass[matrix_owner]<=pass[matrix_owner]+1'b1;
                if(fault[matrix_owner]==0)begin
                    if(mat_rsp_tag!=matrix_token||mat_rsp_generation!=generation[matrix_owner]||mat_rsp_job!=job[matrix_owner]||mat_rsp_fmt!=fmt[matrix_owner])fault[matrix_owner]<=`CSR_MEM_FAULT_TAG;
                    else if(mat_rsp_fault!=0||mat_rsp_mask!=matrix_expected_mask||missing)fault[matrix_owner]<=`CSR_MEM_FAULT_SOURCE;
                end
                if(matrix_tile[matrix_head])begin
                    tile_pending[matrix_tile_entry[matrix_head]]<=0;
                    if(mat_rsp_tag==matrix_token&&mat_rsp_generation==generation[matrix_owner]&&mat_rsp_job==job[matrix_owner]&&mat_rsp_fmt==fmt[matrix_owner]&&
                       mat_rsp_fault==0&&mat_rsp_mask==matrix_expected_mask&&!missing)begin
                        tile_valid[matrix_tile_entry[matrix_head]]<=1;
                        tile_data[matrix_tile_entry[matrix_head]]<=mat_rsp_data[255:0];
                        tile_row_mask[matrix_tile_entry[matrix_head]]<=mat_rsp_masks;
                    end else tile_valid[matrix_tile_entry[matrix_head]]<=0;
                end
            end
            if(vec_valid&&vec_ready)begin
                vector_pending<=1;vector_owner<=vector_slot;vector_token<=vec_tag;
                vector_expected_mask<=vec_mask;vector_address<=vec_block;vector_grants<=vector_grants+1'b1;
            end
            if(vec_rsp_valid&&vec_rsp_ready)begin
                vector_pending<=0;vector_done[vector_owner]<=1;vectors[vector_owner]<=expand_vector(vec_rsp_data,vector_owner);
                if(vec_rsp_tag!=vector_token)begin if(fault[vector_owner]==0)fault[vector_owner]<=`CSR_MEM_FAULT_TAG;end
                else if(vec_rsp_fault!=0||vec_rsp_mask!=vector_expected_mask)begin if(fault[vector_owner]==0)fault[vector_owner]<=`CSR_MEM_FAULT_SOURCE;end
                else begin
                    cache_valid[replacement]<=1;cache_address[replacement]<=vector_address;
                    cache_mask[replacement]<=vector_expected_mask;cache_data[replacement]<=vec_rsp_data;replacement<=~replacement;
                end
            end
            if(take)begin
                tail<=tail+1'b1;serial<=serial+1'b1;frame[tail]<=serial;
                dense[tail]<=req_dense;rfour[tail]<=req_rfour;trans[tail]<=req_trans;rows[tail]<=req_rows;cols[tail]<=req_cols;
                out_index[tail]<=req_out;red_index[tail]<=req_red;step[tail]<=req_step;vector_base[tail]<=req_vec_base;scale[tail]<=req_scale;
                key[tail]<=req_key;generation[tail]<=req_generation;job[tail]<=req_job;tag[tail]<=req_tag;fmt[tail]<=req_fmt;last[tail]<=req_last;
                pass[tail]<=0;matrix_done[tail]<=0;vector_done[tail]<=0;fault[tail]<=request_fault;
                coefficients[tail]<=0;vectors[tail]<=0;masks[tail]<=request_lane_mask;
                accepted_frames<=accepted_frames+1'b1;
                if(count+(pop ? 0 : 1)>peak_occupancy)peak_occupancy<=count+(pop ? 0 : 1);
            end
        end
    end
endmodule
