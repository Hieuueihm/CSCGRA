`timescale 1ns/1ps
module tb_topk_n1024_k32;
    reg clk = 0;
    reg rst_n = 0;
    reg clear = 0, token_valid = 0, eligible = 0, stream_done = 0;
    reg [10:0] token_idx = 0;
    reg [23:0] token_score = 0;
    wire result_valid;
    wire [5:0] result_count;
    wire [32*11-1:0] result_idx_bus;
    always #5 clk = ~clk;

    pe_cluster_4x4 #(.IDX_W(11), .MAX_K(32)) dut (
        .clk(clk), .rst_n(rst_n),
        .topk_pipe_clear(clear), .topk_pipe_token_valid(token_valid),
        .topk_pipe_token_idx(token_idx),
        .topk_pipe_token_score(token_score),
        .topk_pipe_token_eligible(eligible),
        .topk_pipe_stream_done(stream_done),
        .topk_pipe_max_count(6'd32),
        .topk_pipe_result_valid(result_valid),
        .topk_pipe_result_count(result_count),
        .topk_pipe_result_idx_bus(result_idx_bus)
    );

    integer i;
    initial begin
        repeat (4) @(negedge clk); rst_n=1;
        @(negedge clk); clear=1;
        @(negedge clk); clear=0;
        repeat (4) @(negedge clk);
        for (i=0; i<1024; i=i+1) begin
            token_valid=1; eligible=1; token_idx=i[10:0]; token_score=i[23:0];
            @(negedge clk);
        end
        token_valid=0; eligible=0; stream_done=1;
        @(negedge clk); stream_done=0;
        while (!result_valid) @(negedge clk);
        if (result_count !== 6'd32)
            $fatal(1,"topk count %0d",result_count);
        for (i=0; i<32; i=i+1)
            if (result_idx_bus[i*11 +: 11] !== (11'd1023-i))
                $fatal(1,"topk rank %0d idx=%0d",i,result_idx_bus[i*11 +: 11]);
        $display("TOPK_N1024_K32 PASS");
        $finish;
    end
endmodule
