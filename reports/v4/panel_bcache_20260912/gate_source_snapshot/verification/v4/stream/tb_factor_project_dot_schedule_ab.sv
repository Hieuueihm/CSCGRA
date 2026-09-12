`timescale 1ns/1ps
// Observation-only A/B harness for PROJECT_DOT's 8+tail split.  The shared
// driver retains the real kernel, fabric, factor store, B image and host
// readback oracle.  This wrapper only selects panel parameters and reports
// accepted fabric frames by the private project phase.
module tb_factor_project_dot_schedule_ab #(
    parameter PROJECT_DOT_SPLIT_ENABLE=1'b0,
    parameter [10:0] PROJECT_DOT_SPLIT_MIN_ROWS=11'd32,
    parameter STALLS_ENABLE=1'b0
);
    tb_stream_kernel #(.STALLS_ENABLE(STALLS_ENABLE)) driver();

    defparam driver.dut.panels.PROJECT_DOT_SPLIT_ENABLE=PROJECT_DOT_SPLIT_ENABLE;
    defparam driver.dut.panels.PROJECT_DOT_SPLIT_MIN_ROWS=PROJECT_DOT_SPLIT_MIN_ROWS;

    integer tracked=0,tracked_tag=0,start_cycle=0;
    integer dot_frames=0,scale_frames=0,rank_frames=0;
    integer saw_split=0;

    always @(posedge driver.clk) begin
        if(driver.rst) begin
            tracked<=0;
            dot_frames<=0; scale_frames<=0; rank_frames<=0; saw_split<=0;
        end else begin
            if(driver.req_valid&&driver.req_ready&&driver.req_op==6'd20) begin
                tracked<=1;
                tracked_tag<=driver.req_tag;
                start_cycle<=driver.cycles;
                dot_frames<=0; scale_frames<=0; rank_frames<=0; saw_split<=0;
            end
            if(tracked&&driver.dut.panels.operation==6'd20) begin
                if(driver.dut.panels.project_dot_split &&
                   driver.dut.panels.dot_width==11'd8 &&
                   driver.dut.panels.remaining_columns>11'd8)
                    saw_split<=1;
                if(driver.dut.panels.fabric_in_valid&&driver.dut.panels.fabric_in_ready) begin
                    case(driver.dut.panels.project_phase)
                        0: dot_frames<=dot_frames+1;
                        1: scale_frames<=scale_frames+1;
                        2: rank_frames<=rank_frames+1;
                    endcase
                end
            end
            if(tracked&&driver.rsp_valid&&driver.rsp_tag==tracked_tag) begin
                $display("PROJECT_DOT_SCHEDULE tag=%0d cycles=%0d dot_frames=%0d scale_frames=%0d rank_frames=%0d split=%0d stalls=%0d",
                    tracked_tag,driver.cycles-start_cycle,dot_frames,scale_frames,rank_frames,saw_split,STALLS_ENABLE);
                tracked<=0;
            end
        end
    end
endmodule

module tb_factor_project_dot_schedule_baseline;
    tb_factor_project_dot_schedule_ab #(.PROJECT_DOT_SPLIT_ENABLE(1'b0),
        .PROJECT_DOT_SPLIT_MIN_ROWS(11'd32),.STALLS_ENABLE(1'b0)) harness();
endmodule

module tb_factor_project_dot_schedule_enabled;
    tb_factor_project_dot_schedule_ab #(.PROJECT_DOT_SPLIT_ENABLE(1'b1),
        .PROJECT_DOT_SPLIT_MIN_ROWS(11'd24),.STALLS_ENABLE(1'b0)) harness();
endmodule

module tb_factor_project_dot_schedule_min1;
    tb_factor_project_dot_schedule_ab #(.PROJECT_DOT_SPLIT_ENABLE(1'b1),
        .PROJECT_DOT_SPLIT_MIN_ROWS(11'd1),.STALLS_ENABLE(1'b0)) harness();
endmodule

module tb_factor_project_dot_schedule_enabled_stalls;
    tb_factor_project_dot_schedule_ab #(.PROJECT_DOT_SPLIT_ENABLE(1'b1),
        .PROJECT_DOT_SPLIT_MIN_ROWS(11'd24),.STALLS_ENABLE(1'b1)) harness();
endmodule
