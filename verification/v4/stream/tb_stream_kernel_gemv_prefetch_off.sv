module tb_stream_kernel_gemv_prefetch_off;
    tb_stream_kernel #(.RESIDENT_WRITEBACK(1),.GEMV_GROUP_PREFETCH(0)) dut();
endmodule
