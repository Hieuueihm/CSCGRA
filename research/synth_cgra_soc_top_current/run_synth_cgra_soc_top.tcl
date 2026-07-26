set_param general.maxThreads 8
set out_dir "D:/vivado_pj/analysis/synth_cgra_soc_top_current"
file mkdir $out_dir
create_project -in_memory -part xczu7ev-ffvc1156-2-e
set rtl_dir "D:/vivado_pj/CSCGRA/CSCGRA.srcs/sources_1/new"
set rtl_files [list \
  $rtl_dir/addrgen.v \
  $rtl_dir/cgra_soc_top.v \
  $rtl_dir/cgra_top.v \
  $rtl_dir/configmem.v \
  $rtl_dir/csr_regs.v \
  $rtl_dir/ctx_decoder.v \
  $rtl_dir/dma_ctrl.v \
  $rtl_dir/global_scalar_rf.v \
  $rtl_dir/lfsr_phi.v \
  $rtl_dir/ls_matrix_scratchpad.v \
  $rtl_dir/ls_matrix_service.v \
  $rtl_dir/ls_matrix_update_service.v \
  $rtl_dir/ls_row_update_service.v \
  $rtl_dir/ls_scratchpad.v \
  $rtl_dir/pe_array_top1_tree_4x8.v \
  $rtl_dir/pe_cluster_4x4.v \
  $rtl_dir/pe_core.v \
  $rtl_dir/pe_stream_top1_4x8_service.v \
  $rtl_dir/pe_stream_top1_service.v \
  $rtl_dir/pe_stream_topk_serial_service.v \
  $rtl_dir/pe_tile.v \
  $rtl_dir/pearray.v \
  $rtl_dir/reduce_scan.v \
  $rtl_dir/sequencer.v \
  $rtl_dir/sparse_kernel_service_engine.v \
  $rtl_dir/sparse_loop_controller.v \
  $rtl_dir/spm_cluster.v \
  $rtl_dir/switchbox.v \
]
read_verilog -sv $rtl_files
synth_design -top cgra_soc_top -part xczu7ev-ffvc1156-2-e -flatten_hierarchy rebuilt
create_clock -period 10.000 -name ap_clk [get_ports ap_clk]
report_utilization -file $out_dir/cgra_soc_top_util.rpt
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 10 -file $out_dir/cgra_soc_top_timing.rpt
write_checkpoint -force $out_dir/cgra_soc_top_synth.dcp
exit
