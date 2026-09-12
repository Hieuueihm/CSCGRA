`include "kernel_interface.vh"
// Selection/support adjunct. Public sources stay immutable until the core publishes.
// Cancel must flush the shared RAM epoch too. No RAM response remains owned at DONE.
module support_service #(parameter BITMAP_ENUM_ENABLE=1) (
    input wire clk, rst, cancel,
    input wire req_valid, output wire req_ready,
    input wire [5:0] req_op,
    input wire [8:0] req_src_a, req_src_b, req_dst,
    input wire [10:0] req_length, req_k,
    input wire [26:0] req_scalar_a,
    input wire [8:0] req_support_base, req_aux_base,
    input wire [10:0] req_support_length, req_aux_length, req_index,
    input wire [7:0] req_flags,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    output wire vec_valid, input wire vec_ready,
    output reg [8:0] vec_block,
    output reg [31:0] vec_mask,
    output wire [15:0] vec_tag,
    input wire vec_rsp_valid, output wire vec_rsp_ready,
    input wire [863:0] vec_rsp_data,
    input wire [31:0] vec_rsp_mask,
    input wire [15:0] vec_rsp_tag,
    input wire [3:0] vec_rsp_fault,
    output wire candidate_valid, input wire candidate_ready,
    output reg [4:0] candidate_block,
    output reg [31:0] candidate_mask,
    output reg [863:0] candidate_data,
    output wire rsp_valid, input wire rsp_ready,
    output reg [3:0] rsp_fault, rsp_detail,
    output reg [10:0] rsp_count, rsp_length,
    output reg [63:0] rsp_data,
    output reg rsp_nonzero,
    output reg [15:0] rsp_job, rsp_tag,
    output reg [7:0] rsp_fmt
);
    localparam [4:0] IDLE=0, LIST_START=1, LIST_WORD=2, DISPATCH=3,
        READ_REQ=4, READ_WAIT=5, TOP_START=6, TOP_LOAD=7, TREE=8,
        TOP_BLOCK=9, SORT=10, PACK=11, WRITE=12, DENSE=13,
        APPLY=14, SCALAR_READ=15, SCALAR_VALUE=16, DONE=17, RANGE_WORD=18, RANGE_LOADED=19, RANGE_ASSEMBLE=20,
        TOP_GLOBAL_LOAD=21, TOP_REFRESH=22, RANGE_PROVIDER=23;
    reg [4:0] state, read_return, write_return;
    reg [5:0] op;
    reg [7:0] flags;
    reg [26:0] insert_scalar;
    reg [8:0] source_base, list_base, auxiliary_base;
    reg [10:0] length, limit, support_length, auxiliary_length;
    reg [10:0] position, list_length, result_count, walk, slot;
    // SORT may enumerate a completed selection bitmap by 32-bit words.  The
    // word is command-local; selected/seen and the output path stay unchanged.
    reg bitmap_enum_active, bitmap_word_valid;
    reg [31:0] bitmap_word;
    reg second_list;
    reg [1023:0] seen, selected;
    reg [9:0] indices [0:1023];
    reg [863:0] read_data, packed_data;
    reg [4:0] block_index;
    reg [5:0] tree_width;
    reg [26:0] magnitude [0:31];
    reg [10:0] tree_index [0:31];
    reg [31:0] tree_valid;
    reg [26:0] best_magnitude;
    reg [10:0] best_index;
    reg best_valid;
    // TOPK with multiple results reuses one winner per source block.  These
    // records retain only compare inputs; they are not a second vector image.
    reg top_cached;
    reg [1:0] top_tree_kind;
    reg [26:0] top_block_magnitude [0:31];
    reg [10:0] top_block_index [0:31];
    reg top_block_valid [0:31];
    integer lane, pair_index;
    reg [26:0] raw_index, raw_value;
    reg [31:0] required_mask;
    reg [10:0] range_start, output_length;
    // RANGE transport has at most three distinct providers per candidate
    // block.  The plan is analytic: it has no lane-by-lane provider discovery
    // chain and keeps one shared-pool read outstanding at a time.
    reg [1:0] range_plan_count, range_slot;
    reg range_plan_valid0, range_plan_valid1, range_plan_valid2;
    reg [8:0] range_plan_address0, range_plan_address1, range_plan_address2;
    reg [31:0] range_plan_mask0, range_plan_mask1, range_plan_mask2;
    reg [863:0] range_data0, range_data1, range_data2, range_packed;
    reg range_nonzero;
    reg [10:0] range_block_start, range_remaining;
    reg [5:0] range_valid_count, range_pre_length, range_replace_length, range_post_length;
    reg [5:0] range_replace_lane, range_aux_first_length, range_aux_second_length;
    reg [4:0] range_aux_offset;
    reg [11:0] range_replace_begin, range_replace_end, range_aux_end;
    reg [8:0] range_source_address, range_source_second_address;
    reg [8:0] range_aux_first_address, range_aux_second_address;
    reg [4:0] range_source_offset;
    reg [31:0] range_output_mask, range_source_output_mask, range_aux_output_mask;
    reg range_logical_valid0, range_logical_valid1, range_logical_valid2;
    reg [8:0] range_logical_address0, range_logical_address1, range_logical_address2;
    reg [31:0] range_logical_mask0, range_logical_mask1, range_logical_mask2;
    reg [863:0] range_source_data, range_source_second_data;
    reg [863:0] range_aux_first_data, range_aux_second_data;
    reg [863:0] range_source_aligned, range_aux_aligned;
    reg [863:0] range_source_word_mask, range_aux_word_mask;
    reg [1727:0] range_joined_data;
    reg [10:0] range_source_shift_bits, range_aux_shift_bits, range_replace_shift_bits;
    // Command-local validated provider cache.  It owns at most two source
    // words and is keyed by address plus the lanes known valid in that word.
    reg range_cache_enabled, range_cache_valid0, range_cache_valid1, range_cache_replace;
    reg [8:0] range_cache_address0, range_cache_address1;
    reg [31:0] range_cache_mask0, range_cache_mask1;
    reg [863:0] range_cache_data0, range_cache_data1;

    assign req_ready = state==IDLE && !rst && !cancel;
    assign vec_valid = state==READ_REQ && !rst && !cancel;
    assign vec_rsp_ready = state==READ_WAIT && !rst && !cancel;
    assign vec_tag = rsp_tag;
    assign candidate_valid = state==WRITE && !rst && !cancel;
    assign rsp_valid = state==DONE && !rst && !cancel;

    function automatic valid_span(input [8:0] base, input [10:0] size);
        valid_span = size==0 || (int'(base)<480 && int'(base)+(int'(size)+31)/32<=480);
    endfunction
    function automatic [31:0] tail(input [10:0] size, input [4:0] block_number);
        integer i;
        begin
            tail=0;
            for(i=0;i<32;i=i+1)
                if(int'(block_number)*32+i<int'(size)) tail[i]=1;
        end
    endfunction
    function automatic [26:0] absolute(input [26:0] value);
        absolute = value[26] ? (~value+27'd1) : value;
    endfunction
    task automatic fail(input [3:0] fault, input [3:0] detail);
        begin
            rsp_fault<=fault;
            rsp_detail<=detail;
            rsp_count<=0;
            rsp_length<=0;
            rsp_data<=0;
            rsp_nonzero<=0;
            bitmap_enum_active<=0;
            bitmap_word_valid<=0;
            bitmap_word<=0;
            state<=DONE;
        end
    endtask

    function automatic [31:0] bitmap_tail_word(input [1023:0] bitmap,
                                                 input [10:0] base,
                                                 input [10:0] size);
        begin
            // base is word-aligned and is only indexed after walk<length.
            bitmap_tail_word=bitmap[{base[9:5],5'b0} +: 32] &
                             tail(size,base[9:5]);
        end
    endfunction

    function automatic [4:0] lowest_set_lane(input [31:0] bitmap);
        integer encoder_lane;
        reg found;
        begin
            lowest_set_lane=0;
            found=0;
            for(encoder_lane=0;encoder_lane<32;encoder_lane=encoder_lane+1)
                if(!found&&bitmap[encoder_lane]) begin
                    lowest_set_lane=encoder_lane[4:0];
                    found=1;
                end
        end
    endfunction

    task automatic start_sorted_bitmap(input [10:0] final_count);
        begin
            walk<=0;
            position<=0;
            bitmap_word_valid<=0;
            bitmap_word<=0;
            bitmap_enum_active<=BITMAP_ENUM_ENABLE&&
                ((({1'b0,length}+12'd31)>>5)+{1'b0,final_count}<{1'b0,length});
            state<=SORT;
        end
    endtask
    task automatic read_block(input [8:0] address, input [31:0] mask,
                              input [4:0] continuation);
        begin
            vec_block<=address;
            vec_mask<=mask;
            read_return<=continuation;
            state<=READ_REQ;
        end
    endtask
    task automatic emit_block(input [4:0] address, input [31:0] mask,
                              input [863:0] data, input [4:0] continuation);
        begin
            candidate_block<=address;
            candidate_mask<=mask;
            candidate_data<=data;
            write_return<=continuation;
            state<=WRITE;
        end
    endtask

    function automatic [31:0] range_lane_span(input [5:0] first, input [5:0] count);
        integer span_lane;
        begin
            range_lane_span=0;
            for(span_lane=0;span_lane<32;span_lane=span_lane+1)
                if(span_lane>=int'(first) && span_lane<int'(first)+int'(count))
                    range_lane_span[span_lane]=1'b1;
        end
    endfunction
    function automatic [863:0] range_expand_mask(input [31:0] words);
        integer mask_lane;
        begin
            range_expand_mask=0;
            for(mask_lane=0;mask_lane<32;mask_lane=mask_lane+1)
                if(words[mask_lane]) range_expand_mask[mask_lane*27 +: 27]={27{1'b1}};
        end
    endfunction
    // Every widened cache read is still a lane required somewhere in this
    // command.  SLICE consumes one source interval; REPLACE consumes the
    // source complement plus its auxiliary interval.  Address aliases merge
    // those two legitimate requirements rather than reading unused lanes.
    function automatic [31:0] range_command_mask(input [8:0] address);
        integer command_lane, source_position, auxiliary_position;
        begin
            range_command_mask=0;
            for(command_lane=0;command_lane<32;command_lane=command_lane+1) begin
                source_position=(int'(address)-int'(source_base))*32+command_lane;
                auxiliary_position=(int'(address)-int'(auxiliary_base))*32+command_lane;
                if(op==`CSR_KERNEL_OP_SLICE) begin
                    if(source_position>=int'(range_start) &&
                       source_position<int'(range_start)+int'(output_length))
                        range_command_mask[command_lane]=1'b1;
                end else if(op==`CSR_KERNEL_OP_SCALAR_INSERT) begin
                    if(source_position>=0 && source_position<int'(length) &&
                       source_position!=int'(range_start))
                        range_command_mask[command_lane]=1'b1;
                end else begin
                    if(source_position>=0 && source_position<int'(length) &&
                       !(source_position>=int'(range_start) &&
                         source_position<int'(range_start)+int'(auxiliary_length)))
                        range_command_mask[command_lane]=1'b1;
                    if(auxiliary_position>=0 && auxiliary_position<int'(auxiliary_length))
                        range_command_mask[command_lane]=1'b1;
                end
            end
        end
    endfunction
    wire [8:0] range_provider_address=range_slot==0 ? range_plan_address0 :
        range_slot==1 ? range_plan_address1 : range_plan_address2;
    wire [31:0] range_provider_mask=range_slot==0 ? range_plan_mask0 :
        range_slot==1 ? range_plan_mask1 : range_plan_mask2;
    wire [31:0] range_request_mask=range_cache_enabled ? range_command_mask(range_provider_address) : range_provider_mask;
    wire range_provider_hit0=range_cache_valid0 && range_cache_address0==range_provider_address &&
        (range_cache_mask0&range_provider_mask)==range_provider_mask;
    wire range_provider_hit1=range_cache_valid1 && range_cache_address1==range_provider_address &&
        (range_cache_mask1&range_provider_mask)==range_provider_mask;
    // Build logical providers in the original first-used order, then compact
    // their three possible addresses with fixed pair comparisons.  Each mask
    // names exactly the lanes consumed from that physical source block.
    always @* begin
        range_block_start={position[10:5],5'b0};
        range_remaining=0;
        range_valid_count=0;
        range_pre_length=0;
        range_replace_length=0;
        range_post_length=0;
        range_replace_lane=0;
        range_aux_offset=0;
        range_aux_first_length=0;
        range_aux_second_length=0;
        range_replace_begin=0;
        range_replace_end=0;
        range_aux_end=0;
        range_source_address=0;
        range_source_second_address=0;
        range_aux_first_address=0;
        range_aux_second_address=0;
        range_source_offset=0;
        range_output_mask=0;
        range_source_output_mask=0;
        range_aux_output_mask=0;
        range_logical_valid0=0;
        range_logical_valid1=0;
        range_logical_valid2=0;
        range_logical_address0=0;
        range_logical_address1=0;
        range_logical_address2=0;
        range_logical_mask0=0;
        range_logical_mask1=0;
        range_logical_mask2=0;
        range_plan_valid0=0;
        range_plan_valid1=0;
        range_plan_valid2=0;
        range_plan_count=0;
        range_plan_address0=0;
        range_plan_address1=0;
        range_plan_address2=0;
        range_plan_mask0=0;
        range_plan_mask1=0;
        range_plan_mask2=0;

        if(output_length>range_block_start) begin
            range_remaining=output_length-range_block_start;
            range_valid_count=range_remaining>32 ? 32 : range_remaining[5:0];
            range_output_mask=range_lane_span(0,range_valid_count);
            if(op==`CSR_KERNEL_OP_SLICE) begin
                range_aux_end={1'b0,range_start}+{1'b0,range_block_start};
                range_source_offset=range_aux_end[4:0];
                range_source_address=source_base+(range_aux_end>>5);
                range_aux_first_length=range_valid_count>(32-range_source_offset) ?
                    32-range_source_offset : range_valid_count;
                range_aux_second_length=range_valid_count-range_aux_first_length;
                range_source_second_address=range_source_address+1'b1;
                range_logical_valid0=1;
                range_logical_address0=range_source_address;
                range_logical_mask0=range_lane_span(range_source_offset,range_aux_first_length);
                if(range_aux_second_length!=0) begin
                    range_logical_valid1=1;
                    range_logical_address1=range_source_second_address;
                    range_logical_mask1=range_lane_span(0,range_aux_second_length);
                end
                range_source_output_mask=range_output_mask;
            end else if(op==`CSR_KERNEL_OP_SCALAR_INSERT) begin
                range_source_address=source_base+position[10:5];
                if(range_start>=range_block_start && range_start<range_block_start+range_valid_count) begin
                    range_replace_length=1;
                    range_replace_lane=range_start-range_block_start;
                end
                range_pre_length=range_replace_lane;
                range_post_length=range_valid_count-range_pre_length-range_replace_length;
                range_source_output_mask=range_lane_span(0,range_pre_length) |
                    range_lane_span(range_replace_lane+range_replace_length,range_post_length);
                range_aux_output_mask=range_lane_span(range_replace_lane,range_replace_length);
                if(range_source_output_mask!=0) begin
                    range_logical_valid0=1;
                    range_logical_address0=range_source_address;
                    range_logical_mask0=range_source_output_mask;
                end
            end else begin
                range_source_address=source_base+position[10:5];
                range_aux_end={1'b0,range_start}+{1'b0,auxiliary_length};
                range_replace_begin=range_block_start>range_start ? range_block_start : range_start;
                range_replace_end=({1'b0,range_block_start}+range_valid_count)<range_aux_end ?
                    ({1'b0,range_block_start}+range_valid_count) : range_aux_end;
                if(range_replace_end>range_replace_begin) begin
                    range_replace_length=range_replace_end-range_replace_begin;
                    range_replace_lane=range_replace_begin-range_block_start;
                    range_aux_offset=range_replace_begin-range_start;
                    range_aux_first_address=auxiliary_base+((range_replace_begin-range_start)>>5);
                    range_aux_first_length=range_replace_length>(32-range_aux_offset) ?
                        32-range_aux_offset : range_replace_length;
                    range_aux_second_length=range_replace_length-range_aux_first_length;
                    range_aux_second_address=range_aux_first_address+1'b1;
                end
                if(range_replace_lane!=0) range_pre_length=range_replace_lane;
                range_post_length=range_valid_count-range_pre_length-range_replace_length;
                range_source_output_mask=range_lane_span(0,range_pre_length) |
                    range_lane_span(range_replace_lane+range_replace_length,range_post_length);
                range_aux_output_mask=range_lane_span(range_replace_lane,range_replace_length);
                // First-used order matches the former lane scan.  Source masks
                // combine its pre/post runs before address alias compaction.
                if(range_pre_length!=0) begin
                    range_logical_valid0=1;
                    range_logical_address0=range_source_address;
                    range_logical_mask0=range_source_output_mask;
                    if(range_replace_length!=0) begin
                        range_logical_valid1=1;
                        range_logical_address1=range_aux_first_address;
                        range_logical_mask1=range_lane_span(range_aux_offset,range_aux_first_length);
                        if(range_aux_second_length!=0) begin
                            range_logical_valid2=1;
                            range_logical_address2=range_aux_second_address;
                            range_logical_mask2=range_lane_span(0,range_aux_second_length);
                        end
                    end
                end else if(range_replace_length!=0) begin
                    range_logical_valid0=1;
                    range_logical_address0=range_aux_first_address;
                    range_logical_mask0=range_lane_span(range_aux_offset,range_aux_first_length);
                    if(range_aux_second_length!=0) begin
                        range_logical_valid1=1;
                        range_logical_address1=range_aux_second_address;
                        range_logical_mask1=range_lane_span(0,range_aux_second_length);
                        if(range_post_length!=0) begin
                            range_logical_valid2=1;
                            range_logical_address2=range_source_address;
                            range_logical_mask2=range_source_output_mask;
                        end
                    end else if(range_post_length!=0) begin
                        range_logical_valid1=1;
                        range_logical_address1=range_source_address;
                        range_logical_mask1=range_source_output_mask;
                    end
                end else begin
                    range_logical_valid0=1;
                    range_logical_address0=range_source_address;
                    range_logical_mask0=range_source_output_mask;
                end
            end

            range_plan_valid0=range_logical_valid0;
            range_plan_address0=range_logical_address0;
            range_plan_mask0=range_logical_mask0;
            if(range_logical_valid1 && range_logical_address1==range_logical_address0)
                range_plan_mask0=range_plan_mask0|range_logical_mask1;
            if(range_logical_valid2 && range_logical_address2==range_logical_address0)
                range_plan_mask0=range_plan_mask0|range_logical_mask2;
            if(range_logical_valid1 && range_logical_address1!=range_logical_address0) begin
                range_plan_valid1=1;
                range_plan_address1=range_logical_address1;
                range_plan_mask1=range_logical_mask1;
                if(range_logical_valid2 && range_logical_address2==range_logical_address1)
                    range_plan_mask1=range_plan_mask1|range_logical_mask2;
            end else if(range_logical_valid2 && range_logical_address2!=range_logical_address0) begin
                range_plan_valid1=1;
                range_plan_address1=range_logical_address2;
                range_plan_mask1=range_logical_mask2;
            end
            if(range_logical_valid1 && range_logical_valid2 &&
               range_logical_address1!=range_logical_address0 &&
               range_logical_address2!=range_logical_address0 &&
               range_logical_address2!=range_logical_address1) begin
                range_plan_valid2=1;
                range_plan_address2=range_logical_address2;
                range_plan_mask2=range_logical_mask2;
            end
            range_plan_count=range_plan_valid0+range_plan_valid1+range_plan_valid2;

        end
    end

    // Common-offset word alignment replaces per-output-lane provider selects.
    // All shifts are logical shifts of unsigned packed words and their offsets
    // are constrained to lanes 0..31 by the analytic range plan.
    always @* begin
        range_source_data=0;
        range_source_second_data=0;
        range_aux_first_data=0;
        range_aux_second_data=0;
        if(range_plan_valid0 && range_source_address==range_plan_address0) range_source_data=range_data0;
        else if(range_plan_valid1 && range_source_address==range_plan_address1) range_source_data=range_data1;
        else if(range_plan_valid2 && range_source_address==range_plan_address2) range_source_data=range_data2;
        if(range_plan_valid0 && range_source_second_address==range_plan_address0) range_source_second_data=range_data0;
        else if(range_plan_valid1 && range_source_second_address==range_plan_address1) range_source_second_data=range_data1;
        else if(range_plan_valid2 && range_source_second_address==range_plan_address2) range_source_second_data=range_data2;
        if(range_plan_valid0 && range_aux_first_address==range_plan_address0) range_aux_first_data=range_data0;
        else if(range_plan_valid1 && range_aux_first_address==range_plan_address1) range_aux_first_data=range_data1;
        else if(range_plan_valid2 && range_aux_first_address==range_plan_address2) range_aux_first_data=range_data2;
        if(range_plan_valid0 && range_aux_second_address==range_plan_address0) range_aux_second_data=range_data0;
        else if(range_plan_valid1 && range_aux_second_address==range_plan_address1) range_aux_second_data=range_data1;
        else if(range_plan_valid2 && range_aux_second_address==range_plan_address2) range_aux_second_data=range_data2;
        range_source_shift_bits=range_source_offset*27;
        range_aux_shift_bits=range_aux_offset*27;
        range_replace_shift_bits=range_replace_lane*27;
        range_joined_data={range_source_second_data,range_source_data};
        range_source_aligned=range_joined_data>>range_source_shift_bits;
        range_joined_data={range_aux_second_data,range_aux_first_data};
        range_aux_aligned=range_joined_data>>range_aux_shift_bits;
        range_source_word_mask=range_expand_mask(range_source_output_mask);
        range_aux_word_mask=range_expand_mask(range_aux_output_mask);
        range_packed=op==`CSR_KERNEL_OP_SCALAR_INSERT ?
            ((range_source_aligned&range_source_word_mask) |
             (({{837{1'b0}},insert_scalar}<<range_replace_shift_bits)&range_aux_word_mask)) :
            ((range_source_aligned&range_source_word_mask) |
             ((range_aux_aligned<<range_replace_shift_bits)&range_aux_word_mask));
        range_nonzero=|range_packed;
    end

    // One read is owned until its response is consumed. Validation precedes use.
    // The TOPK tree has one registered level per cycle and unsigned magnitudes.
    always @(posedge clk) begin
        if(rst || cancel) begin
            state<=IDLE;
            rsp_fault<=0;
            rsp_detail<=0;
            rsp_count<=0;
            rsp_length<=0;
            rsp_data<=0;
            rsp_nonzero<=0;
            rsp_job<=0;
            rsp_tag<=0;
            rsp_fmt<=0;
            vec_block<=0;
            vec_mask<=0;
            candidate_block<=0;
            candidate_mask<=0;
            candidate_data<=0;
            top_cached<=0;
            top_tree_kind<=0;
            bitmap_enum_active<=0;
            bitmap_word_valid<=0;
            bitmap_word<=0;
            range_cache_valid0<=0;
            range_cache_valid1<=0;
            range_cache_replace<=0;
            range_cache_enabled<=0;
        end else case(state)
            IDLE: if(req_valid) begin
                op<=req_op;
                flags<=req_flags;
                source_base<=req_src_a;
                list_base<=req_support_base;
                auxiliary_base<=req_aux_base;
                length<=req_length;
                limit<=req_k;
                support_length<=req_support_length;
                auxiliary_length<=req_op==`CSR_KERNEL_OP_SCALAR_INSERT ? 11'd1 : req_aux_length;
                insert_scalar<=req_scalar_a;
                slot<=req_index;
                range_start<=req_index;
                rsp_job<=req_job;
                rsp_tag<=req_tag;
                rsp_fmt<=req_fmt;
                rsp_fault<=0;
                rsp_detail<=0;
                rsp_count<=0;
                rsp_length<=0;
                rsp_data<=0;
                rsp_nonzero<=0;
                result_count<=0;
                seen<=0;
                selected<=0;
                position<=0;
                second_list<=0;
                top_cached<=0;
                top_tree_kind<=0;
                bitmap_enum_active<=0;
                bitmap_word_valid<=0;
                bitmap_word<=0;
                // Public providers are immutable only for this command.
                // Never carry a validated lane mask into a later command.
                range_cache_valid0<=0;
                range_cache_valid1<=0;
                range_cache_replace<=0;
                // Cache only an unaligned command that can consume a source
                // provider on both sides of an output-word boundary.  Aligned
                // or head-only ranges have no reuse and keep the old schedule.
                range_cache_enabled<=req_op==`CSR_KERNEL_OP_SLICE ?
                    (req_aux_length>32 && req_index[4:0]!=0) :
                    req_op==`CSR_KERNEL_OP_REPLACE_RANGE && req_length>32 &&
                    req_index[4:0]!=0 && req_aux_length>(11'd32-{6'd0,req_index[4:0]});
                list_length<=req_op==`CSR_KERNEL_OP_TOPK && !(req_flags & `CSR_KERNEL_TOPK_EXCLUDE) ? 0 : req_support_length;
                state<=LIST_START;
                if(req_fmt!=1 || req_op<`CSR_KERNEL_OP_TOPK ||
                   (req_op>`CSR_KERNEL_OP_REPLACE_RANGE && req_op!=`CSR_KERNEL_OP_SCALAR_INSERT) ||
                   (req_op==`CSR_KERNEL_OP_TOPK ? (req_flags & 8'hfc)!=0 :
                    req_op==`CSR_KERNEL_OP_UNION ? (req_flags & 8'hfe)!=0 : req_flags!=0))
                    fail(`CSR_KERNEL_FAULT_COMMAND,0);
                else if(req_op>=`CSR_KERNEL_OP_SLICE &&
                    (req_k!=0 || req_support_base!=0 || req_support_length!=0 ||
                     (req_op==`CSR_KERNEL_OP_SCALAR_INSERT &&
                      (req_src_b!=0 || req_aux_base!=0 || req_aux_length!=0 || req_flags!=0))))
                    fail(`CSR_KERNEL_FAULT_COMMAND,0);
                else if(req_length==0 || req_length>1024 || req_support_length>req_length || req_aux_length>req_length ||
                    ((req_op==`CSR_KERNEL_OP_TOPK || req_op==`CSR_KERNEL_OP_UNION) && (req_k==0 || req_k>1024)) ||
                    (req_op==`CSR_KERNEL_OP_PICK && req_index>=req_length) ||
                    (req_op==`CSR_KERNEL_OP_SCALAR_INSERT && req_index>=req_length) ||
                    (req_op>=`CSR_KERNEL_OP_SLICE &&
                     (req_index>req_length || {1'b0,req_index}+{1'b0,req_aux_length}>{1'b0,req_length})) ||
                    (req_op!=`CSR_KERNEL_OP_UNION && !valid_span(req_src_a,req_op==`CSR_KERNEL_OP_SCATTER ? req_support_length : req_length)) ||
                    (req_op<`CSR_KERNEL_OP_PICK && !(req_op==`CSR_KERNEL_OP_TOPK && !(req_flags & `CSR_KERNEL_TOPK_EXCLUDE)) && !valid_span(req_support_base,req_support_length)) ||
                    ((req_op==`CSR_KERNEL_OP_UNION || req_op==`CSR_KERNEL_OP_REPLACE_RANGE) && !valid_span(req_aux_base,req_aux_length)))
                    fail(`CSR_KERNEL_FAULT_RANGE,0);
                else if(req_op==`CSR_KERNEL_OP_PICK) state<=SCALAR_READ;
                else if(req_op>=`CSR_KERNEL_OP_SLICE) begin
                    output_length<=req_op==`CSR_KERNEL_OP_SLICE ? req_aux_length : req_length;
                    rsp_length<=req_op==`CSR_KERNEL_OP_SLICE ? req_aux_length : req_length;
                    rsp_count<=req_op==`CSR_KERNEL_OP_SLICE ? req_aux_length : req_length;
                    position<=0;
                    packed_data<=0;
                    state<=req_op==`CSR_KERNEL_OP_SLICE && req_aux_length==0 ? DONE : RANGE_WORD;
                end
            end
            READ_REQ: if(vec_ready) state<=READ_WAIT;
            READ_WAIT: if(vec_rsp_valid) begin
                if(vec_rsp_tag!=rsp_tag) fail(`CSR_KERNEL_FAULT_IDENTITY,`CSR_KERNEL_SUPPORT_DETAIL_TAG);
                else if(vec_rsp_fault!=0) fail(`CSR_KERNEL_FAULT_OPERAND,vec_rsp_fault);
                else if(vec_rsp_mask!=vec_mask) fail(`CSR_KERNEL_FAULT_UNINITIALIZED,`CSR_KERNEL_SUPPORT_DETAIL_MASK);
                else begin
                    read_data<=vec_rsp_data;
                    state<=read_return;
                end
            end
            LIST_START: begin
                if(position==list_length) begin
                    if(op==`CSR_KERNEL_OP_UNION && !second_list) begin
                        second_list<=1;
                        list_base<=auxiliary_base;
                        list_length<=auxiliary_length;
                        position<=0;
                    end else state<=DISPATCH;
                end else read_block(list_base+position[10:5],tail(list_length,position[9:5]),LIST_WORD);
            end
            LIST_WORD: begin
                raw_index=read_data[position[4:0]*27 +: 27];
                if(raw_index>=length) fail(`CSR_KERNEL_FAULT_RANGE,`CSR_KERNEL_SUPPORT_DETAIL_INDEX);
                else if(seen[raw_index[9:0]] && op!=`CSR_KERNEL_OP_TOPK && op!=`CSR_KERNEL_OP_UNION)
                    fail(`CSR_KERNEL_FAULT_COMMAND,`CSR_KERNEL_SUPPORT_DETAIL_DUPLICATE);
                else if(!seen[raw_index[9:0]] && op==`CSR_KERNEL_OP_UNION && result_count==limit)
                    fail(`CSR_KERNEL_FAULT_RANGE,`CSR_KERNEL_SUPPORT_DETAIL_CAPACITY);
                else begin
                    seen[raw_index[9:0]]<=1;
                    if(op!=`CSR_KERNEL_OP_TOPK && !seen[raw_index[9:0]]) begin
                        indices[result_count]<=raw_index[9:0];
                        result_count<=result_count+1'b1;
                    end
                    position<=position+1'b1;
                    if(position+1==list_length || position[4:0]==31) state<=LIST_START;
                end
            end
            DISPATCH: begin
                position<=0;
                block_index<=0;
                packed_data<=0;
                slot<=0;
                rsp_count<=result_count;
                rsp_length<=result_count;
                case(op)
                    `CSR_KERNEL_OP_TOPK: begin
                        result_count<=0;
                        // Reusing block winners only avoids repeated scans
                        // when more than one answer spans more than one word.
                        // The one-result and single-word paths remain legacy.
                        // Measured break-even: two 32-word blocks with K=2
                        // lose two cycles to the global tree, while K>=3 or
                        // three-plus blocks win by avoiding full rescans.
                        top_cached<=length>32 && limit>1 && (length>64 || limit>2);
                        state<=TOP_START;
                    end
                    `CSR_KERNEL_OP_UNION: begin
                        if(flags & `CSR_KERNEL_UNION_ORDERED) begin
                            walk<=0;
                            bitmap_enum_active<=0;
                            bitmap_word_valid<=0;
                            state<=PACK;
                        end else start_sorted_bitmap(result_count);
                    end
                    `CSR_KERNEL_OP_APPLY_SUPPORT, `CSR_KERNEL_OP_SCATTER: begin
                        rsp_length<=length;
                        state<=DENSE;
                    end
                    `CSR_KERNEL_OP_GATHER: state<=result_count==0 ? DONE : SCALAR_READ;
                    default: fail(`CSR_KERNEL_FAULT_COMMAND,0);
                endcase
            end
            TOP_START: begin
                best_valid<=0;
                best_magnitude<=0;
                best_index<=0;
                block_index<=0;
                top_tree_kind<=top_cached ? 2'd1 : 2'd0;
                read_block(source_base,tail(length,0),TOP_LOAD);
            end
            TOP_LOAD: begin
                for(lane=0;lane<32;lane=lane+1) begin
                    magnitude[lane]<=absolute(read_data[lane*27 +: 27]);
                    tree_index[lane]<={block_index,5'b0}+lane;
                    tree_valid[lane]<=vec_mask[lane] && !seen[{block_index,5'b0}+lane];
                end
                tree_width<=16;
                state<=TREE;
            end
            TREE: begin
                for(lane=0;lane<16;lane=lane+1) if(lane<tree_width) begin
                    pair_index=2*lane;
                    if(tree_valid[pair_index+1] && (!tree_valid[pair_index] ||
                       magnitude[pair_index+1]>magnitude[pair_index] ||
                       (magnitude[pair_index+1]==magnitude[pair_index] && tree_index[pair_index+1]<tree_index[pair_index])))
                        pair_index=pair_index+1;
                    magnitude[lane]<=magnitude[pair_index];
                    tree_index[lane]<=tree_index[pair_index];
                    tree_valid[lane]<=tree_valid[pair_index];
                end
                tree_width<=tree_width>>1;
                if(tree_width==1) state<=TOP_BLOCK;
            end
            TOP_BLOCK: begin
                if(top_tree_kind==2'd1) begin
                    // Initial scan: retain only the local winner.  The global
                    // choice below is made by the same registered TREE.
                    top_block_valid[block_index]<=tree_valid[0];
                    top_block_magnitude[block_index]<=magnitude[0];
                    top_block_index[block_index]<=tree_index[0];
                    if((int'(block_index)+1)*32<int'(length)) begin
                        block_index<=block_index+1'b1;
                        read_block(source_base+block_index+1'b1,tail(length,block_index+1'b1),TOP_LOAD);
                    end else begin
                        state<=TOP_GLOBAL_LOAD;
                    end
                end else if(top_tree_kind==2'd2) begin
                    // Only the block whose winner was just selected can have
                    // changed eligibility, so refresh that one record.
                    top_block_valid[block_index]<=tree_valid[0];
                    top_block_magnitude[block_index]<=magnitude[0];
                    top_block_index[block_index]<=tree_index[0];
                    state<=TOP_GLOBAL_LOAD;
                end else if(top_tree_kind==2'd3) begin
                    best_valid<=tree_valid[0];
                    best_magnitude<=magnitude[0];
                    best_index<=tree_index[0];
                    // Preserve the legacy extra cycle before committing the
                    // final TREE winner into selected/seen.
                    state<=SCALAR_VALUE;
                end else begin
                    if(tree_valid[0] && (!best_valid || magnitude[0]>best_magnitude ||
                       (magnitude[0]==best_magnitude && tree_index[0]<best_index))) begin
                        best_valid<=1;
                        best_magnitude<=magnitude[0];
                        best_index<=tree_index[0];
                    end
                    if((int'(block_index)+1)*32<int'(length)) begin
                        block_index<=block_index+1'b1;
                        read_block(source_base+block_index+1'b1,tail(length,block_index+1'b1),TOP_LOAD);
                    end else begin
                        // A separate cycle includes the final block winner before selection.
                        state<=SCALAR_VALUE;
                    end
                end
            end
            TOP_GLOBAL_LOAD: begin
                for(lane=0;lane<32;lane=lane+1) begin
                    if(lane<(int'(length)+31)/32) begin
                        magnitude[lane]<=top_block_magnitude[lane];
                        tree_index[lane]<=top_block_index[lane];
                        tree_valid[lane]<=top_block_valid[lane];
                    end else begin
                        magnitude[lane]<=0;
                        tree_index[lane]<=0;
                        tree_valid[lane]<=0;
                    end
                end
                tree_width<=16;
                top_tree_kind<=2'd3;
                state<=TREE;
            end
            TOP_REFRESH: begin
                block_index<=best_index[10:5];
                top_tree_kind<=2'd2;
                read_block(source_base+best_index[10:5],tail(length,best_index[10:5]),TOP_LOAD);
            end
            SORT: begin
                if(!bitmap_enum_active) begin
                    if(walk==length) begin
                        position<=0;
                        state<=PACK;
                    end else begin
                        if(op==`CSR_KERNEL_OP_TOPK ? selected[walk[9:0]] : seen[walk[9:0]]) begin
                            indices[position]<=walk[9:0];
                            position<=position+1'b1;
                        end
                        walk<=walk+1'b1;
                    end
                end else if(!bitmap_word_valid) begin
                    if(walk>=length) begin
                        position<=0;
                        bitmap_enum_active<=0;
                        state<=PACK;
                    end else begin
                        bitmap_word<=op==`CSR_KERNEL_OP_TOPK ?
                            bitmap_tail_word(selected,walk,length) : bitmap_tail_word(seen,walk,length);
                        if((op==`CSR_KERNEL_OP_TOPK ? bitmap_tail_word(selected,walk,length) :
                            bitmap_tail_word(seen,walk,length))==0)
                            walk<=walk+11'd32;
                        else bitmap_word_valid<=1;
                    end
                end else begin
                    indices[position]<=walk+lowest_set_lane(bitmap_word);
                    position<=position+1'b1;
                    if((bitmap_word&~(32'b1<<lowest_set_lane(bitmap_word)))==0) begin
                        bitmap_word<=0;
                        bitmap_word_valid<=0;
                        walk<=walk+11'd32;
                    end else bitmap_word<=bitmap_word&~(32'b1<<lowest_set_lane(bitmap_word));
                end
            end
            PACK: begin
                if(position==result_count) state<=DONE;
                else begin
                    packed_data[position[4:0]*27 +: 27]<={17'b0,indices[position]};
                    if(indices[position]!=0) rsp_nonzero<=1;
                    position<=position+1'b1;
                    if(position[4:0]==31 || position+1==result_count) begin
                        candidate_data<=packed_data;
                        candidate_data[position[4:0]*27 +: 27]<={17'b0,indices[position]};
                        candidate_block<=position[9:5];
                        candidate_mask<=tail(result_count,position[9:5]);
                        packed_data<=0;
                        write_return<=PACK;
                        state<=WRITE;
                    end
                end
            end
            DENSE: begin
                required_mask=tail(length,block_index);
                if(op==`CSR_KERNEL_OP_APPLY_SUPPORT) begin
                    for(lane=0;lane<32;lane=lane+1)
                        required_mask[lane]=required_mask[lane] && seen[{block_index,5'b0}+lane];
                    if(required_mask!=0) read_block(source_base+block_index,required_mask,APPLY);
                    else begin
                        read_data<=0;
                        state<=APPLY;
                    end
                end else begin
                    emit_block(block_index,required_mask,0,
                        (int'(block_index)+1)*32>=int'(length) ? (support_length==0 ? DONE : SCALAR_READ) : DENSE);
                    block_index<=block_index+1'b1;
                end
            end
            APPLY: begin
                candidate_data<=0;
                for(lane=0;lane<32;lane=lane+1) if(seen[{block_index,5'b0}+lane] && int'(block_index)*32+lane<int'(length)) begin
                    candidate_data[lane*27 +: 27]<=read_data[lane*27 +: 27];
                    if(read_data[lane*27 +: 27]!=0) rsp_nonzero<=1;
                end
                candidate_block<=block_index;
                candidate_mask<=tail(length,block_index);
                write_return<=(int'(block_index)+1)*32>=int'(length) ? DONE : DENSE;
                block_index<=block_index+1'b1;
                state<=WRITE;
            end
            SCALAR_READ: begin
                if(op==`CSR_KERNEL_OP_GATHER)
                    read_block(source_base+indices[slot][9:5],32'b1<<indices[slot][4:0],SCALAR_VALUE);
                else read_block(source_base+slot[10:5],32'b1<<slot[4:0],SCALAR_VALUE);
            end
            SCALAR_VALUE: begin
                if(op==`CSR_KERNEL_OP_TOPK) begin
                    if(!best_valid || result_count==limit) begin
                        rsp_count<=result_count;
                        rsp_length<=result_count;
                        if(flags & `CSR_KERNEL_TOPK_SORT) start_sorted_bitmap(result_count);
                        else begin
                            walk<=0;
                            position<=0;
                            state<=PACK;
                        end
                    end else begin
                        indices[result_count]<=best_index[9:0];
                        result_count<=result_count+1'b1;
                        seen[best_index[9:0]]<=1;
                        selected[best_index[9:0]]<=1;
                        if(result_count+1==limit) begin
                            rsp_count<=result_count+1'b1;
                            rsp_length<=result_count+1'b1;
                            if(flags & `CSR_KERNEL_TOPK_SORT) start_sorted_bitmap(result_count+1'b1);
                            else begin
                                walk<=0;
                            position<=0;
                                state<=PACK;
                            end
                        end else state<=top_cached ? TOP_REFRESH : TOP_START;
                    end
                end else begin
                    raw_value=read_data[(op==`CSR_KERNEL_OP_GATHER ? indices[slot][4:0] : slot[4:0])*27 +: 27];
                    if(raw_value!=0) rsp_nonzero<=1;
                    if(op==`CSR_KERNEL_OP_PICK) begin
                        rsp_data<={{37{raw_value[26]}},raw_value};
                        state<=DONE;
                    end else begin
                        slot<=slot+1'b1;
                        if(op==`CSR_KERNEL_OP_SCATTER) begin
                            candidate_data<=0;
                            candidate_data[indices[slot][4:0]*27 +: 27]<=raw_value;
                            candidate_mask<=32'b1<<indices[slot][4:0];
                            candidate_block<=indices[slot][9:5];
                            write_return<=slot+1==support_length ? DONE : SCALAR_READ;
                            state<=WRITE;
                        end else begin
                            packed_data[slot[4:0]*27 +: 27]<=raw_value;
                            if(slot[4:0]==31 || slot+1==support_length) begin
                                candidate_data<=packed_data;
                                candidate_data[slot[4:0]*27 +: 27]<=raw_value;
                                candidate_mask<=tail(support_length,slot[9:5]);
                                candidate_block<=slot[9:5];
                                packed_data<=0;
                                write_return<=slot+1==support_length ? DONE : SCALAR_READ;
                                state<=WRITE;
                            end else state<=SCALAR_READ;
                        end
                    end
                end
            end
            // Gather every source block used by this output block.  READ_WAIT
            // still checks the exact request mask and tag before any response
            // can reach these staging registers.  Replaced source lanes are
            // intentionally absent from the plan; required source and aux lanes
            // retain the same invalid-mask/fault semantics as the scalar loop.
            RANGE_WORD: begin
                range_slot<=0;
                range_data0<=0;
                range_data1<=0;
                range_data2<=0;
                if(op==`CSR_KERNEL_OP_SCALAR_INSERT && range_plan_count==0 &&
                   range_replace_length==1 && range_valid_count==1)
                    state<=RANGE_ASSEMBLE;
                else if(!range_plan_valid0 || range_plan_mask0==0)
                    fail(`CSR_KERNEL_FAULT_COMMAND,0);
                else if(range_cache_enabled) state<=RANGE_PROVIDER;
                else read_block(range_plan_address0,range_plan_mask0,RANGE_LOADED);
            end
            RANGE_PROVIDER: begin
                // A hit is legal only when every requested lane was checked
                // by the original response.  Missing lanes still issue the
                // normal request and therefore retain its mask/tag/fault ABI.
                if(range_provider_hit0 || range_provider_hit1) begin
                    if(range_slot==0) range_data0<=range_provider_hit0 ? range_cache_data0 : range_cache_data1;
                    else if(range_slot==1) range_data1<=range_provider_hit0 ? range_cache_data0 : range_cache_data1;
                    else range_data2<=range_provider_hit0 ? range_cache_data0 : range_cache_data1;
                    if(range_slot+1<range_plan_count) begin
                        range_slot<=range_slot+1'b1;
                        state<=RANGE_PROVIDER;
                    end else state<=RANGE_ASSEMBLE;
                end else read_block(range_provider_address,range_request_mask,RANGE_LOADED);
            end
            RANGE_LOADED: begin
                if(range_slot==0) range_data0<=read_data;
                else if(range_slot==1) range_data1<=read_data;
                else range_data2<=read_data;
                if(!range_cache_valid0 || (range_cache_valid1 && !range_cache_replace)) begin
                    range_cache_valid0<=1;
                    range_cache_address0<=range_provider_address;
                    range_cache_mask0<=range_request_mask;
                    range_cache_data0<=read_data;
                    range_cache_replace<=1;
                end else begin
                    range_cache_valid1<=1;
                    range_cache_address1<=range_provider_address;
                    range_cache_mask1<=range_request_mask;
                    range_cache_data1<=read_data;
                    range_cache_replace<=0;
                end
                if(range_slot+1<range_plan_count) begin
                    range_slot<=range_slot+1'b1;
                    if(range_cache_enabled) state<=RANGE_PROVIDER;
                    else if(range_slot==0) read_block(range_plan_address1,range_plan_mask1,RANGE_LOADED);
                    else read_block(range_plan_address2,range_plan_mask2,RANGE_LOADED);
                end else state<=RANGE_ASSEMBLE;
            end
            RANGE_ASSEMBLE: begin
                candidate_block<=position[10:5];
                candidate_mask<=tail(output_length,position[10:5]);
                candidate_data<=range_packed;
                rsp_nonzero<=rsp_nonzero || range_nonzero;
                write_return<=int'(position)+32>=int'(output_length) ? DONE : RANGE_WORD;
                position<=position+32;
                state<=WRITE;
            end
            WRITE: if(candidate_ready) state<=write_return;
            DONE: if(rsp_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule


