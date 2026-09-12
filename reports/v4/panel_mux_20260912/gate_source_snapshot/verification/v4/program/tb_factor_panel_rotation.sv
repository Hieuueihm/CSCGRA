`timescale 1ns/1ps
module tb_factor_panel_rotation;
    reg [863:0] response_data=0;
    reg [863:0] write_data=0;
    reg [10:0] row_base=0,column_base=0,column_position=0,row_index=0;
    reg [1:0] selected_slot=0;
    reg range_mode=0,dot_mode=0,rank_mode=0;
    reg [863:0] expected_response,expected_write;
    integer mode,shift_value,row_value,source_lane,target_lane,bank_value,relative_lane;
    integer slot_value,checks=0;
    factor_panel_service dut(.clk(1'b0),.rst(1'b1),.cancel(1'b0),
        .req_valid(1'b0),.panel_rsp_data(response_data));
    initial begin
        force dut.row_start=row_base;
        force dut.col_start=column_base;
        force dut.col_position=column_position;
        force dut.request_row=row_index;
        force dut.request_slot=selected_slot;
        force dut.response_slot=selected_slot;
        force dut.range_operation=range_mode;
        force dut.narrow_dot=dot_mode;
        force dut.narrow_rank=rank_mode;
        for(mode=0;mode<4;mode=mode+1)begin
            range_mode=mode==0;
            dot_mode=mode==2;
            rank_mode=mode==3;
            for(shift_value=0;shift_value<32;shift_value=shift_value+1)begin
                row_base=11'(shift_value);
                column_base=11'(95-2*shift_value);
                column_position=11'(2*shift_value+1);
                for(row_value=0;row_value<32;row_value=row_value+1)begin
                    row_index=11'(row_value);
                    for(slot_value=0;slot_value<4;slot_value=slot_value+1)begin
                        selected_slot=2'(slot_value);
                        dut.slot_row[slot_value]=row_index;
                        response_data=0;
                        write_data=0;
                        for(source_lane=0;source_lane<32;source_lane=source_lane+1)begin
                            response_data[source_lane*27+:27]=27'h4000000+27'(source_lane*2053+row_value*67+shift_value);
                            write_data[source_lane*27+:27]=27'h1234567^27'(source_lane*65539+slot_value*1025+row_value);
                        end
                        dut.slot_result[0]=write_data^864'h1234;
                        dut.slot_result[1]=write_data^864'h4567;
                        dut.slot_result[2]=write_data^864'h89ab;
                        dut.slot_result[3]=write_data^864'hcdef;
                        dut.slot_result[slot_value]=write_data;
                        expected_response=0;
                        expected_write=0;
                        for(target_lane=0;target_lane<32;target_lane=target_lane+1)begin
                            if(range_mode)bank_value=(int'(row_base)+int'(column_base)+target_lane)&31;
                            else if(dot_mode)bank_value=(int'(row_base)+(row_value/8)*32+(row_value%8)+int'(column_position)+8*(target_lane%4)+target_lane/4)&31;
                            else if(rank_mode)bank_value=(int'(row_base)+(row_value/8)*16+(row_value%8)+int'(column_position)+8*(target_lane%2)+target_lane/2)&31;
                            else bank_value=(int'(row_base)+row_value+int'(column_position)+target_lane)&31;
                            if(!rank_mode||target_lane<16)
                                expected_response[target_lane*27+:27]=response_data[bank_value*27+:27];
                            if(rank_mode)begin
                                relative_lane=(target_lane-int'(row_base)-(row_value/8)*16-(row_value%8)-int'(column_position))&31;
                                if(relative_lane<16)
                                    expected_write[target_lane*27+:27]=write_data[(2*(relative_lane%8)+relative_lane/8)*27+:27];
                            end
                            else begin
                                relative_lane=(target_lane-int'(row_base)-row_value-int'(column_position))&31;
                                expected_write[target_lane*27+:27]=write_data[relative_lane*27+:27];
                            end
                        end
                        #1;
                        if(dut.response_ordered!==expected_response)
                            $fatal(1,"response rotation mode=%0d shift=%0d row=%0d slot=%0d",mode,shift_value,row_value,slot_value);
                        if(dut.request_banked!==expected_write)
                            $fatal(1,"write rotation mode=%0d shift=%0d row=%0d slot=%0d",mode,shift_value,row_value,slot_value);
                        checks=checks+2;
                    end
                end
            end
        end
        $display("PASS factor_panel_rotation checks=%0d",checks);
        $finish;
    end
endmodule
