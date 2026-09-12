`timescale 1ns/1ps
module tb_factor_panel_bcache;
    reg [10:0] column_start=0,column_position=0,width=1;
    reg use_rank=0,use_narrow=0,use_scale=0;
    reg [26:0] expected_word;
    reg [863:0] expected_data;
    reg [31:0] expected_mask;
    integer pattern,index,delta,lane,relative,mode,width_value;
    integer reads=0,feeds=0;
    factor_panel_service dut(.clk(1'b0),.rst(1'b1),.cancel(1'b0),.req_valid(1'b0));
    initial begin
        force dut.col_start=column_start;
        force dut.col_position=column_position;
        force dut.feed_slot_valid=use_rank;
        force dut.feed_slot=2'd0;
        force dut.range_operation=1'b0;
        force dut.dot_phase=1'b0;
        force dut.rank_phase=use_rank;
        force dut.narrow_rank=use_narrow;
        force dut.scale_feed_valid=use_scale;
        force dut.rank_width=width;
        force dut.panel_width=width;
        force dut.row_count=11'd128;
        force dut.scalar_a=27'd0;
        dut.slot_row[0]=0;
        dut.slot_factor[0]=0;
        for(index=0;index<128;index=index+1)dut.a_cache[index]=0;
        for(pattern=0;pattern<4;pattern=pattern+1)begin
            for(index=0;index<96;index=index+1)begin
                case(pattern)
                    0:dut.b_cache[index]=27'h4000000^27'(index*65539);
                    1:dut.b_cache[index]=27'b1<<(index%27);
                    2:dut.b_cache[index]=27'h7ffffff-27'(index*131071);
                    3:dut.b_cache[index]=0;
                endcase
            end
            for(delta=-2047;delta<=2047;delta=delta+1)begin
                column_start=delta<0 ? 11'(-delta) : 11'd0;
                column_position=delta<0 ? 11'd0 : 11'(delta);
                #1;
                for(lane=0;lane<32;lane=lane+1)begin
                    relative=delta+lane;
                    expected_word=relative>=0&&relative<96 ? dut.b_cache[relative] : 27'bx;
                    if(dut.cache_read_window[lane*27+:27]!==expected_word)
                        $fatal(1,"cache read pattern=%0d delta=%0d lane=%0d",pattern,delta,lane);
                    reads=reads+1;
                end
            end
        end
        column_start=0;
        for(index=0;index<96;index=index+1)dut.b_cache[index]=27'h1000000+27'(index*65537);
        for(mode=0;mode<3;mode=mode+1)begin
            use_rank=mode!=2;
            use_narrow=mode==1;
            use_scale=mode==2;
            for(width_value=1;width_value<=(mode==0?16:mode==1?8:32);width_value=width_value+1)begin
                width=11'(width_value);
                for(delta=0;delta+width_value<=96;delta=delta+1)begin
                    column_position=11'(delta);
                    expected_data=0;
                    expected_mask=0;
                    for(lane=0;lane<(mode==1?2*width_value:width_value);lane=lane+1)begin
                        expected_data[lane*27+:27]=dut.b_cache[delta+(mode==1?lane/2:lane)];
                        expected_mask[lane]=1;
                        if(mode!=2)expected_mask[lane+16]=1;
                    end
                    #1;
                    if(dut.fabric_in_mask!==expected_mask)
                        $fatal(1,"feed mask mode=%0d width=%0d delta=%0d",mode,width_value,delta);
                    if(mode==2 ? dut.fabric_in_a!==expected_data : dut.fabric_in_b!==expected_data)
                        $fatal(1,"feed data mode=%0d width=%0d delta=%0d",mode,width_value,delta);
                    feeds=feeds+1;
                end
            end
        end
        $display("PASS factor_panel_bcache reads=%0d feeds=%0d",reads,feeds);
        $finish;
    end
endmodule
