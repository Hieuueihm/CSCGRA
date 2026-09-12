`timescale 1ns/1ps
module tb_factor_panel_slice_guard;
    reg clk=0;
    always #5 clk=~clk;
    reg [863:0] data=0;
    reg select_narrow=0;
    reg [10:0] width=1;
    reg select_matvec=1;
    reg [863:0] expected_data;
    reg expected_nonzero;
    integer mode,width_value,source_lane,target_lane,checks=0;
    factor_panel_service dut(.clk(clk),.rst(1'b1),.cancel(1'b0),
        .req_valid(1'b0),.fabric_out_data(data));
    initial begin
        force dut.narrow_dot=select_narrow;
        force dut.dot_width=width;
        force dut.matvec=select_matvec;
        for(mode=0;mode<2;mode=mode+1) begin
            select_narrow=mode!=0;
            for(width_value=1;width_value<=(mode==0?32:8);width_value=width_value+1) begin
                width=11'(width_value);
                for(source_lane=0;source_lane<32;source_lane=source_lane+1) begin
                    data=0;
                    data[source_lane*27+:27]=27'h4000000+27'(source_lane);
                    expected_data=0;
                    if(mode==0) expected_data=data;
                    else for(target_lane=0;target_lane<8;target_lane=target_lane+1)
                        expected_data[target_lane*27+:27]=data[(target_lane*4)*27+:27];
                    expected_nonzero=mode==0 ? source_lane<width_value :
                        (source_lane%4==0 && source_lane/4<width_value);
                    select_matvec=1;
                    #1;
                    if(dut.dot_result_data!==expected_data || dut.mat_output_nonzero!==expected_nonzero)
                        $fatal(1,"lane mapping mode=%0d width=%0d source=%0d",mode,width_value,source_lane);
                    select_matvec=0;
                    #1;
                    if(dut.mat_output_nonzero!==1'b0) $fatal(1,"non-MATVEC zero flag");
                    checks=checks+3;
                end
            end
        end
        data=0;select_matvec=1;#1;
        if(dut.mat_output_nonzero!==0) $fatal(1,"all-zero vector");
        $display("PASS factor_panel_slice_guard checks=%0d",checks+1);
        $finish;
    end
    initial begin #100000; $fatal(1,"watchdog"); end
endmodule
