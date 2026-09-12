`timescale 1ns/1ps
// Opcode-25 response-integrity wrapper.  The shared driver supplies real B and
// factor-store traffic; this wrapper changes only the final held panel reply.
module tb_stream_kernel_factor_energy_tap_fault;
    tb_stream_kernel driver();

    integer count_mismatch_reached=0;
    integer length_mismatch_reached=0;
    integer recovery_reached=0;

    task expect_private_publication_abort(input integer tag, input integer block);
        begin
            wait(driver.rsp_valid && driver.rsp_tag==tag);
            if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 ||
               driver.rsp_nonzero!==0 || driver.rsp_count!==0 ||
               driver.dut.valid_masks[block]!==0 || driver.dut.valid_masks[block+1]!==0)
                $fatal(1,"op25 malformed reply published result tag=%0d fault=%0d count=%0d",
                       tag,driver.rsp_fault,driver.rsp_count);
        end
    endtask

    initial begin
        wait(!driver.rst);
        // Case two has emitted all candidates and is holding the normal panel
        // reply to kernel SUPPORT_WAIT.  Count is an op25 boolean, never a
        // candidate length; two is identity-fatal and clears both owned blocks.
        wait(driver.dut.operation==6'd25 && driver.dut.tag==16'd2 &&
             driver.dut.state==driver.dut.SUPPORT_WAIT &&
             driver.dut.panels.state==driver.dut.panels.DONE);
        count_mismatch_reached=1;
        force driver.dut.panels.rsp_count=11'd2;
        @(posedge driver.clk); @(negedge driver.clk);
        release driver.dut.panels.rsp_count;
        expect_private_publication_abort(2,192);
        $display("FACTOR_ENERGY_TAP_FAULT count_mismatch_reached=1 fault=6");

        // Case four proves the full unpatched tap remains mandatory even when
        // its tail flag is zero/nonzero independently.  A short reply cannot
        // commit a prefix candidate.
        wait(driver.dut.operation==6'd25 && driver.dut.tag==16'd4 &&
             driver.dut.state==driver.dut.SUPPORT_WAIT &&
             driver.dut.panels.state==driver.dut.panels.DONE);
        length_mismatch_reached=1;
        force driver.dut.panels.rsp_length=11'd32;
        @(posedge driver.clk); @(negedge driver.clk);
        release driver.dut.panels.rsp_length;
        expect_private_publication_abort(4,256);
        $display("FACTOR_ENERGY_TAP_FAULT length_mismatch_reached=1 fault=6");

        // A fresh B/INIT/op25 sequence follows the two rejected replies.  The
        // shared parser checks its exact raw ACC64 and candidate readback.
        wait(driver.rsp_valid && driver.rsp_tag==16'd6 && driver.rsp_fault==0);
        recovery_reached=1;
        $display("FACTOR_ENERGY_TAP_FAULT recovery_reached=1");
    end

    initial begin
        #9000000;
        $fatal(1,"factor-energy-tap response wrapper watchdog count=%0d length=%0d recovery=%0d",
               count_mismatch_reached,length_mismatch_reached,recovery_reached);
    end
endmodule
