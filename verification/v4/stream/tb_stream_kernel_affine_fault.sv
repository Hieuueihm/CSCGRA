`timescale 1ns/1ps

// This wrapper deliberately reuses tb_stream_kernel's fixture parser, host
// oracle, stalls, and full stream_kernel integration.  It adds only directed
// fault forcing for opcode 23; it does not replace the shared driver.
module tb_stream_kernel_affine_fault;
    tb_stream_kernel driver();

    integer early_done_reached=0;
    integer terminal_identity_reached=0;
    integer cancel_after_scratch_reached=0;
    integer recovery_reissued=0;

    task force_done_matching;
        begin
            force driver.dut.fabric_done=1'b1;
            force driver.dut.fabric_fault=4'd0;
            force driver.dut.fabric_job=driver.dut.job;
            force driver.dut.fabric_tag=driver.dut.tag;
            force driver.dut.fabric_fmt=driver.dut.fmt;
            @(posedge driver.clk);
            @(negedge driver.clk);
            release driver.dut.fabric_done;
            release driver.dut.fabric_fault;
            release driver.dut.fabric_job;
            release driver.dut.fabric_tag;
            release driver.dut.fabric_fmt;
        end
    endtask

    initial begin
        // Case one is the ordinary published command.  Cases two through four
        // are supplied by the Python fixture in this exact tag order.
        wait(!driver.rst);

        // A matched early completion while affine RUN is malformed: private
        // scratch has not completed, so it must become an identity fault.
        wait(driver.dut.operation==6'd23 && driver.dut.tag==16'd2 &&
             driver.dut.state==driver.dut.RUN);
        early_done_reached=1;
        force_done_matching();
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 || driver.rsp_nonzero!==0 ||
           driver.dut.valid_masks[128]!==0)
            $fatal(1,"early affine DONE published scalar or destination");
        $display("AFFINE_FAULT early_done_reached=1 fault=%0d",driver.rsp_fault);

        // AFFINE_WAIT follows a private scratch write.  A terminal identity
        // mismatch must still fault before scratch remap/publication.
        wait(driver.dut.operation==6'd23 && driver.dut.tag==16'd3 &&
             driver.dut.state==driver.dut.AFFINE_WAIT &&
             driver.dut.scratch_masks[0]!==0);
        terminal_identity_reached=1;
        force driver.dut.fabric_done=1'b1;
        force driver.dut.fabric_fault=4'd0;
        force driver.dut.fabric_job=driver.dut.job;
        force driver.dut.fabric_tag=(driver.dut.tag^16'h0001);
        force driver.dut.fabric_fmt=driver.dut.fmt;
        @(posedge driver.clk);
        @(negedge driver.clk);
        release driver.dut.fabric_done;
        release driver.dut.fabric_fault;
        release driver.dut.fabric_job;
        release driver.dut.fabric_tag;
        release driver.dut.fabric_fmt;
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 || driver.rsp_nonzero!==0 ||
           driver.dut.valid_masks[160]!==0)
            $fatal(1,"AFFINE_WAIT identity fault published scalar or destination");
        $display("AFFINE_FAULT terminal_identity_reached=1 fault=%0d",driver.rsp_fault);

        // The fourth fixture leaves cancel_i=0 so the shared driver waits for
        // a response.  Assert real cancel only after the private scratch block
        // is written, prove the old ordinary result survives, then reissue the
        // same held request.  The shared driver validates that recovery result.
        wait(driver.dut.operation==6'd23 && driver.dut.tag==16'd4 &&
             driver.dut.scratch_masks[0]!==0);
        cancel_after_scratch_reached=1;
        @(negedge driver.clk);
        driver.cancel=1'b1;
        @(posedge driver.clk);
        // The cancel branch updates valid_masks with nonblocking assignments.
        // Sample after that edge has settled, not in its active region.
        @(negedge driver.clk);
        if(driver.dut.valid_masks[192]!==0 || driver.dut.valid_masks[193]!==0)
            $fatal(1,"cancel after affine scratch retained a destination block");
        driver.cancel=1'b0;
        repeat(2) @(negedge driver.clk);
        if(driver.dut.state!=driver.dut.IDLE || driver.rsp_valid)
            $fatal(1,"cancel after affine scratch leaked a response");
        driver.host_access(0,400,32'h1,0,0,37);

        @(negedge driver.clk);
        driver.req_valid=1'b1;
        do @(posedge driver.clk); while(!driver.req_ready);
        @(negedge driver.clk);
        driver.req_valid=1'b0;
        recovery_reissued=1;
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==0 || driver.rsp_data!==0)
            $fatal(1,"reissued affine command did not recover");
        $display("AFFINE_FAULT cancel_after_scratch_reached=1 recovery_reissued=1");
    end

    initial begin
        #5000000;
        $fatal(1,"affine fault wrapper watchdog early=%0d terminal=%0d cancel=%0d recovery=%0d",
               early_done_reached,terminal_identity_reached,
               cancel_after_scratch_reached,recovery_reissued);
    end
endmodule
