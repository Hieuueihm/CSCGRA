`timescale 1ns/1ps
// Directed opcode-24 fault wrapper.  It reuses the shared stream-kernel fixture
// driver and only forces terminal/metadata/cancel boundaries around op24.
module tb_stream_kernel_factor_range_fault;
    tb_stream_kernel driver();

    integer early_done_reached=0;
    integer terminal_identity_reached=0;
    integer metadata_after_raw_reached=0;
    integer cancel_after_candidate_reached=0;
    integer recovery_reissued=0;
    integer rebuild_col,rebuild_block,rebuild_lane,rebuild_row,rebuild_raw;
    reg [63:0] held_raw_acc;
    reg [863:0] rebuild_data;
    reg [31:0] rebuild_mask;

    task force_done_matching;
        begin
            force driver.dut.fabric_done=1'b1;
            force driver.dut.fabric_fault=4'd0;
            force driver.dut.fabric_job=driver.dut.job;
            force driver.dut.fabric_tag=driver.dut.tag;
            force driver.dut.fabric_fmt=driver.dut.fmt;
            @(posedge driver.clk); @(negedge driver.clk);
            release driver.dut.fabric_done; release driver.dut.fabric_fault;
            release driver.dut.fabric_job; release driver.dut.fabric_tag;
            release driver.dut.fabric_fmt;
        end
    endtask

    task rebuild_live_b;
        begin
            // Cancellation invalidates the factor/B identity as a unit.  Load
            // the same deterministic dense C18 image used by the fixture while
            // leaving public vector blocks (including the ordinary control
            // result at 400) untouched.  The next FACTOR_INIT must bind this
            // freshly published identity before the same op24 is reissued.
            driver.b_begin_rows=8'd33; driver.b_begin_cols=11'd17;
            driver.b_begin_valid=1'b1;
            do @(posedge driver.clk); while(!driver.b_begin_ready);
            @(negedge driver.clk); driver.b_begin_valid=1'b0;
            for(rebuild_col=0;rebuild_col<17;rebuild_col=rebuild_col+1)
                for(rebuild_block=0;rebuild_block<2;rebuild_block=rebuild_block+1) begin
                    rebuild_data=0; rebuild_mask=0;
                    for(rebuild_lane=0;rebuild_lane<32;rebuild_lane=rebuild_lane+1) begin
                        rebuild_row=rebuild_block*32+rebuild_lane;
                        if(rebuild_row<33) begin
                            rebuild_raw=((31*rebuild_row+17*rebuild_col+5)%131)-65;
                            rebuild_data[rebuild_lane*18 +: 18]=rebuild_raw[17:0];
                            rebuild_mask[rebuild_lane]=1'b1;
                        end
                    end
                    driver.b_fill_slot=rebuild_col;
                    driver.b_fill_block=rebuild_block;
                    driver.b_fill_mask=rebuild_mask;
                    driver.b_fill_data=rebuild_data;
                    driver.b_fill_last=(rebuild_col==16&&rebuild_block==1);
                    driver.b_fill_valid=1'b1;
                    do @(posedge driver.clk); while(!driver.b_fill_ready);
                    @(negedge driver.clk); driver.b_fill_valid=1'b0;
                end
            while(!driver.b_valid) @(negedge driver.clk);
            if(driver.b_load_fault!=0)
                $fatal(1,"recovery B rebuild fault=%0d",driver.b_load_fault);
        end
    endtask

    task issue_recovery_init;
        begin
            // The factor B image remains live, while cancel invalidates only
            // factor ownership.  Hide this internal INIT reply from the shared
            // parser; it must consume the following same-tag op24 reply.
            force driver.rsp_valid=1'b0;
            driver.rsp_ready=1'b1;
            driver.req_op=6'd13;
            driver.req_rows=8'd33; driver.req_cols=11'd17;
            driver.req_matrix_dense=1'b1; driver.req_trans=0; driver.req_r4=0;
            driver.req_scalar_a=0; driver.req_scalar_b=0;
            driver.req_scalar_bind_a=0; driver.req_scalar_bind_b=0;
            driver.req_descriptor=32'd5; driver.req_contexts=0;
            driver.req_length=11'd33; driver.req_shift=0; driver.req_store_mode=0;
            driver.req_support_base=0; driver.req_aux_base=0;
            driver.req_support_length=11'd17; driver.req_aux_length=0;
            driver.req_index=0; driver.req_flags=0;
            driver.req_frame_count=2; driver.req_tail_mask=32'h00000001;
            driver.req_dst=0; driver.req_src_a=0; driver.req_src_b=0;
            driver.req_tag=16'h7777;
            @(negedge driver.clk); driver.req_valid=1'b1;
            do @(posedge driver.clk); while(!driver.req_ready);
            @(negedge driver.clk); driver.req_valid=1'b0;
            // driver.rsp_valid is forced low so the shared vector parser does
            // not consume this internal rebuild reply.  Observe the kernel
            // state directly because a forced output net can alias the port.
            wait(driver.dut.state==driver.dut.RESPONSE);
            if(driver.dut.fault!==0 || driver.dut.result_count!==11'd17)
                $fatal(1,"factor INIT recovery did not complete fault=%0d count=%0d",
                       driver.dut.fault,driver.dut.result_count);
            @(posedge driver.clk); @(negedge driver.clk);
            driver.rsp_ready=1'b0;
            release driver.rsp_valid;
        end
    endtask

    task reissue_range_same_tag;
        begin
            // Same legal op24 shape as the canceled fixture: column/full,
            // offset zero and length 33 (two blocks), first-lane patch,
            // descriptor23 and raw terminal.
            driver.req_op=6'd24;
            driver.req_rows=8'd33; driver.req_cols=11'd17;
            driver.req_matrix_dense=1'b1; driver.req_trans=0; driver.req_r4=0;
            driver.req_scalar_a=27'sd1048593; driver.req_scalar_b=0;
            driver.req_scalar_bind_a=0; driver.req_scalar_bind_b=0;
            driver.req_descriptor=32'd23; driver.req_contexts={32{64'd297}};
            driver.req_length=11'd33; driver.req_shift=0; driver.req_store_mode=0;
            driver.req_support_base=0; driver.req_aux_base=0;
            driver.req_support_length=11'd17; driver.req_aux_length=0;
            driver.req_index=11'd7; driver.req_flags=8'h04;
            driver.req_frame_count=0; driver.req_tail_mask=0;
            driver.req_dst=9'd192; driver.req_src_a=0; driver.req_src_b=0;
            driver.req_tag=16'd9;
            @(negedge driver.clk); driver.req_valid=1'b1;
            do @(posedge driver.clk); while(!driver.req_ready);
            @(negedge driver.clk); driver.req_valid=1'b0;
            recovery_reissued=1;
        end
    endtask

    initial begin
        wait(!driver.rst);

        // Tag3: matching DONE before all range frames retire is invalid.
        wait(driver.dut.operation==6'd24 && driver.dut.tag==16'd3 &&
             driver.dut.panels.state==driver.dut.panels.RUN);
        if(driver.dut.panels.range_slots_done)
            $fatal(1,"early op24 terminal injection was not before retirement");
        early_done_reached=1;
        force_done_matching();
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 || driver.rsp_nonzero!==0 ||
           driver.dut.valid_masks[128]!==0 || driver.dut.valid_masks[129]!==0)
            $fatal(1,"op24 early DONE published scalar or candidate");
        $display("FACTOR_RANGE_FAULT early_done_reached=1 fault=%0d",driver.rsp_fault);

        // Tag5: after factor work began, a wrong terminal identity must still
        // fail before a raw scalar or candidate can be made visible.
        wait(driver.dut.operation==6'd24 && driver.dut.tag==16'd5 &&
             driver.dut.panels.state==driver.dut.panels.RUN &&
             driver.dut.panels.range_slots_done);
        if(!driver.dut.panels.range_slots_done)
            $fatal(1,"terminal identity injection did not reach all retired slots");
        terminal_identity_reached=1;
        force driver.dut.fabric_done=1'b1;
        force driver.dut.fabric_fault=4'd0;
        force driver.dut.fabric_job=driver.dut.job;
        force driver.dut.fabric_tag=(driver.dut.tag^16'h0001);
        force driver.dut.fabric_fmt=driver.dut.fmt;
        @(posedge driver.clk); @(negedge driver.clk);
        release driver.dut.fabric_done; release driver.dut.fabric_fault;
        release driver.dut.fabric_job; release driver.dut.fabric_tag;
        release driver.dut.fabric_fmt;
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 || driver.rsp_nonzero!==0 ||
           driver.dut.valid_masks[160]!==0 || driver.dut.valid_masks[161]!==0)
            $fatal(1,"op24 terminal identity fault published scalar or candidate");
        $display("FACTOR_RANGE_FAULT terminal_identity_reached=1 fault=%0d",driver.rsp_fault);

        // Tag7: hold the candidate path after a valid raw terminal result.
        // This proves that an identity change during a held publication cannot
        // leak the raw scalar or any candidate block.
        wait(driver.dut.operation==6'd24 && driver.dut.tag==16'd7 &&
             driver.dut.panels.state==driver.dut.panels.RUN &&
             driver.dut.panels.range_slots_done);
        force driver.dut.candidate_ready=1'b0;
        wait(driver.dut.state==driver.dut.SUPPORT_WAIT &&
             driver.dut.panels.state==driver.dut.panels.CANDIDATE);
        metadata_after_raw_reached=1;
        held_raw_acc=driver.dut.panels.raw_acc;
        if($isunknown(held_raw_acc) || held_raw_acc==0)
            $fatal(1,"op24 held candidate did not capture a known nonzero raw terminal");
        repeat(2) begin
            @(posedge driver.clk);
            if(driver.dut.panels.state!=driver.dut.panels.CANDIDATE ||
               driver.dut.panels.raw_acc!==held_raw_acc || !driver.dut.candidate_valid)
                $fatal(1,"op24 raw terminal/candidate was not held stable before metadata fault");
        end
        force driver.dut.panels.matrix_generation=(driver.dut.panels.generation^32'h1);
        @(posedge driver.clk); @(negedge driver.clk);
        release driver.dut.panels.matrix_generation;
        release driver.dut.candidate_ready;
        wait(driver.rsp_valid);
        if(driver.rsp_fault!==4'd6 || driver.rsp_data!==0 || driver.rsp_nonzero!==0 ||
           driver.dut.valid_masks[224]!==0 || driver.dut.valid_masks[225]!==0)
            $fatal(1,"op24 metadata fault after raw DONE published scalar or candidate");
        $display("FACTOR_RANGE_FAULT metadata_after_raw_reached=1 fault=%0d",driver.rsp_fault);

        // Tag9: wait for the first private candidate block, cancel, prove both
        // owned blocks clear while the unrelated tag1 ordinary commit remains,
        // then rebuild B/factor ownership and reissue the same legal op24 tag.
        wait(driver.dut.operation==6'd24 && driver.dut.tag==16'd9 &&
             driver.dut.state==driver.dut.SUPPORT_WAIT &&
             !$isunknown(driver.dut.scratch_masks[0]) && driver.dut.scratch_masks[0]!=0);
        cancel_after_candidate_reached=1;
        @(negedge driver.clk); driver.cancel=1'b1;
        @(posedge driver.clk); @(negedge driver.clk); driver.cancel=1'b0;
        repeat(2) @(negedge driver.clk);
        if(driver.dut.valid_masks[192]!==0 || driver.dut.valid_masks[193]!==0)
            $fatal(1,"op24 cancel retained an owned destination block");
        if(driver.rsp_valid || driver.busy)
            $fatal(1,"op24 cancel leaked response or busy");
        driver.host_access(0,400,32'h1,0,0,37);
        rebuild_live_b();
        issue_recovery_init();
        reissue_range_same_tag();
        $display("FACTOR_RANGE_FAULT cancel_after_candidate_reached=1 recovery_reissued=1");
    end

    initial begin
        #9000000;
        $fatal(1,"factor-range fault wrapper watchdog early=%0d terminal=%0d metadata=%0d cancel=%0d recovery=%0d",
               early_done_reached,terminal_identity_reached,metadata_after_raw_reached,
               cancel_after_candidate_reached,recovery_reissued);
    end
endmodule
