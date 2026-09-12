`timescale 1ns/1ps
`include "kernel_interface.vh"
// Opcode-25 raw terminal protocol wrapper.  No shared driver source is changed.
module tb_stream_kernel_factor_energy_tap_terminal_fault;
    tb_stream_kernel driver();

    integer early_done_reached=0;
    integer terminal_identity_reached=0;
    integer terminal_fabric_fault_reached=0;
    integer recovery_reached=0;

    task expect_abort(input integer tag, input integer expected_fault, input integer block);
        begin
            wait(driver.rsp_valid && driver.rsp_tag==tag);
            if(driver.rsp_fault!==expected_fault || driver.rsp_data!==0 ||
               driver.rsp_nonzero!==0 || driver.rsp_count!==0 ||
               driver.dut.valid_masks[block]!==0 || driver.dut.valid_masks[block+1]!==0)
                $fatal(1,"op25 terminal protocol leaked tag=%0d fault=%0d expected=%0d",
                       tag,driver.rsp_fault,expected_fault);
        end
    endtask

    task force_matching_done(input [3:0] terminal_fault, input [15:0] terminal_tag);
        begin
            force driver.dut.fabric_done=1'b1;
            force driver.dut.fabric_fault=terminal_fault;
            force driver.dut.fabric_job=driver.dut.job;
            force driver.dut.fabric_tag=terminal_tag;
            force driver.dut.fabric_fmt=driver.dut.fmt;
            @(posedge driver.clk); @(negedge driver.clk);
            release driver.dut.fabric_done;
            release driver.dut.fabric_fault;
            release driver.dut.fabric_job;
            release driver.dut.fabric_tag;
            release driver.dut.fabric_fmt;
        end
    endtask

    initial begin
        wait(!driver.rst);
        // Case two: a matching terminal before the last ordinary output is not
        // a valid raw reduction completion and must not leave a held operation.
        wait(driver.dut.operation==6'd25 && driver.dut.tag==16'd2 &&
             driver.dut.panels.state==driver.dut.panels.RUN);
        if(driver.dut.panels.range_slots_done)
            $fatal(1,"op25 early DONE injection reached completed range");
        early_done_reached=1;
        force_matching_done(0,driver.dut.tag);
        expect_abort(2,6,192);
        $display("FACTOR_ENERGY_TAP_TERMINAL early_done_reached=1 fault=6");

        // Case four: after every private frame/ordinary output is accepted, a
        // wrong terminal identity is still fatal before raw ACC64 publication.
        wait(driver.dut.operation==6'd25 && driver.dut.tag==16'd4 &&
             driver.dut.panels.state==driver.dut.panels.RUN &&
             driver.dut.panels.range_slots_done);
        terminal_identity_reached=1;
        force_matching_done(0,driver.dut.tag^16'h0001);
        expect_abort(4,6,256);
        $display("FACTOR_ENERGY_TAP_TERMINAL terminal_identity_reached=1 fault=6");

        // Case six: matching identity with a fabric numeric fault retains its
        // causal fault code, while scalar/count/candidate state remains zero.
        wait(driver.dut.operation==6'd25 && driver.dut.tag==16'd6 &&
             driver.dut.panels.state==driver.dut.panels.RUN &&
             driver.dut.panels.range_slots_done);
        terminal_fabric_fault_reached=1;
        force_matching_done(4'd1,driver.dut.tag);
        expect_abort(6,`CSR_KERNEL_FAULT_FABRIC,320);
        $display("FACTOR_ENERGY_TAP_TERMINAL terminal_fabric_fault_reached=1 fault=%0d",`CSR_KERNEL_FAULT_FABRIC);

        wait(driver.rsp_valid && driver.rsp_tag==16'd8 && driver.rsp_fault==0);
        recovery_reached=1;
        $display("FACTOR_ENERGY_TAP_TERMINAL recovery_reached=1");
    end

    initial begin
        #9000000;
        $fatal(1,"factor-energy terminal wrapper watchdog early=%0d identity=%0d fabric=%0d recovery=%0d",
               early_done_reached,terminal_identity_reached,
               terminal_fabric_fault_reached,recovery_reached);
    end
endmodule
