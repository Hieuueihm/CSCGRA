`timescale 1ns/1ps
`include "scalar_interface.vh"
module tb_arithmetic_service;
    reg clk=0;
    reg rst, cancel, req_valid, rsp_ready;
    reg [1:0] req_op;
    reg signed [63:0] req_a, req_b;
    reg [7:0] req_source_frac, req_fmt;
    reg [15:0] req_job, req_tag;
    wire req_ready, rsp_valid;
    wire signed [26:0] rsp_data;
    wire [2:0] rsp_fault;
    wire [15:0] rsp_job, rsp_tag;
    wire [7:0] rsp_fmt;
    arithmetic_service dut(.*);
    integer src,dst,rc,cycle;
    reg [4095:0] src_path,dst_path;
    task snapshot(input integer phase);
        $fdisplay(dst,"%0d %0d %h %h %h %h %h %h %h",cycle,phase,
                  req_ready,rsp_valid,rsp_data,rsp_fault,rsp_job,rsp_tag,rsp_fmt);
    endtask
    initial begin
        if (!$value$plusargs("src=%s",src_path) || !$value$plusargs("dst=%s",dst_path))
            $fatal(1,"missing paths");
        src=$fopen(src_path,"r"); dst=$fopen(dst_path,"w");
        if (!src || !dst) $fatal(1,"cannot open files");
        cycle=0;
        while (!$feof(src)) begin
            rc=$fscanf(src,"%h %h %h %h %h %h %h %h %h %h %h\n",
                       rst,cancel,req_valid,rsp_ready,req_op,req_a,req_b,
                       req_source_frac,req_job,req_tag,req_fmt);
            if (rc != 11) $fatal(1,"bad vector row");
            #5; snapshot(0);
            clk=1; #5; snapshot(1);
            clk=0; cycle=cycle+1;
        end
        $fclose(src); $fclose(dst);
        $display("PASS cycles=%0d",cycle);
        $finish;
    end
endmodule
