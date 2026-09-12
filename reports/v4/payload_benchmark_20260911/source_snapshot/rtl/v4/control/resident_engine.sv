`include "operator_defs.vh"
`include "memory_defs.vh"
module resident_engine (
    input wire  clk,
    input wire  rst,
    input wire  cancel,
    input wire  begin_valid,
    output wire  begin_ready,
    input wire [7:0] begin_rev,
    input wire [8:0] begin_depth,
    input wire  begin_verified,
    input wire [31:0] begin_generation,
    input wire  wr_valid,
    output wire  wr_ready,
    input wire [7:0] wr_pc,
    input wire [5:0] wr_bank,
    input wire [255:0] wr_data,
    input wire  wr_last,
    output wire  image_ready,
    output wire  loading,
    output wire [3:0] load_fault,
    input wire  start_valid,
    output wire  start_ready,
    input wire [7:0] start_pc,
    input wire [31:0] start_limit,
    input wire [15:0] start_job,
    input wire [7:0] start_fmt,
    input wire [2:0] predicates,
    output wire  done_valid,
    input wire  done_ready,
    output wire [3:0] done_fault,
    output wire [7:0] pc,
    output wire [31:0] retired,
    input wire  cfg_valid,
    output wire  cfg_ready,
    input wire [3:0] cfg_index,
    input wire [7:0] cfg_rev,
    input wire [`CSR_OP_DESC_W-1:0] cfg_data,
    output wire  cfg_fault,
    input wire [127:0] link_ready,
    output wire  result_valid,
    input wire  result_ready,
    output wire [863:0] result_data,
    output wire [31:0] result_mask,
    output wire [351:0] result_index,
    output wire [15:0] result_job,
    output wire [15:0] result_tag,
    output wire [7:0] result_fmt,
    output wire  result_last,
    input wire [3:0] read_allow,
    input wire  b_begin_valid,
    output wire  b_begin_ready,
    input wire [7:0] b_begin_rows,
    input wire [6:0] b_begin_cols,
    input wire [127:0] b_begin_key,
    input wire [31:0] b_begin_generation,
    input wire [15:0] b_begin_job,
    input wire [7:0] b_begin_fmt,
    input wire  b_fill_valid,
    output wire  b_fill_ready,
    input wire [6:0] b_fill_slot,
    input wire [1:0] b_fill_block,
    input wire [31:0] b_fill_mask,
    input wire [32*`CSR_PE_C_W-1:0] b_fill_data,
    input wire  b_fill_last,
    output wire  b_loading,
    output wire  b_cache_valid,
    output wire [3:0] b_load_fault,
    input wire  v_begin_valid,
    output wire  v_begin_ready,
    input wire [1:0] v_begin_plane,
    input wire [12:0] v_begin_length,
    input wire [31:0] v_begin_generation,
    input wire [15:0] v_begin_job,
    input wire [7:0] v_begin_fmt,
    input wire  v_fill_valid,
    output wire  v_fill_ready,
    input wire [6:0] v_fill_block,
    input wire [31:0] v_fill_mask,
    input wire [32*`CSR_PE_S_W-1:0] v_fill_data,
    input wire  v_fill_last,
    output wire  v_loading,
    output wire [2:0] v_plane_valid,
    output wire [3:0] v_load_fault,
    input wire  p_begin_valid,
    input wire [31:0] p_begin_seed,
    input wire [7:0] p_begin_rows,
    input wire [10:0] p_begin_cols,
    input wire [127:0] p_begin_key,
    input wire [31:0] p_begin_generation,
    input wire [15:0] p_begin_job,
    input wire [7:0] p_begin_fmt,
    output wire  p_begin_ready,
    output wire  p_valid,
    output wire  p_loading,
    output wire [3:0] p_fault
);
    wire  addr_valid;
    wire  addr_ready;
    wire [2:0] addr_mode;
    wire [23:0] addr_value;
    wire [15:0] addr_stride;
    wire  addr_rsp_valid;
    wire  addr_rsp_ready;
    wire  addr_rsp_fault;
    wire [15:0] addr_rsp_job;
    wire [15:0] addr_rsp_tag;
    wire  exec_valid;
    wire  exec_ready;
    wire [2047:0] exec_words;
    wire [15:0] exec_job;
    wire [15:0] exec_tag;
    wire [7:0] exec_fmt;
    wire  exec_last;
    wire  exec_cancel;
    wire  exec_rsp_valid;
    wire  exec_rsp_ready;
    wire  exec_rsp_fault;
    wire [15:0] exec_rsp_job;
    wire [15:0] exec_rsp_tag;
    wire [7:0] exec_rsp_fmt;
    wire  read_valid;
    wire  read_ready;
    wire [`CSR_OP_DESC_W-1:0] read_desc;
    wire [10:0] read_out;
    wire [10:0] read_red;
    wire [2:0] read_step;
    wire [15:0] read_job;
    wire [15:0] read_tag;
    wire [7:0] read_fmt;
    wire  read_rsp_valid;
    wire  read_rsp_ready;
    wire [863:0] read_mat;
    wire [863:0] read_vec;
    wire [31:0] read_mask;
    wire [3:0] read_fault;
    wire [15:0] read_rsp_job;
    wire [15:0] read_rsp_tag;
    wire [7:0] read_rsp_fmt;
    reg running;
    wire engine_start_ready;
    wire stores_busy = p_loading || b_loading || v_loading;
    wire loading_request = p_begin_valid || b_begin_valid || v_begin_valid || cfg_valid;
    wire idle = !running;
    assign start_ready = engine_start_ready && !stores_busy && !loading_request;
    always @(posedge clk) begin
        if (rst || cancel) running <= 1'b0;
        else begin
            if (start_valid && start_ready) running <= 1'b1;
            if (done_valid && done_ready) running <= 1'b0;
        end
    end
    context_engine engine (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .begin_valid(begin_valid),
        .begin_ready(begin_ready),
        .begin_rev(begin_rev),
        .begin_depth(begin_depth),
        .begin_verified(begin_verified),
        .begin_generation(begin_generation),
        .wr_valid(wr_valid),
        .wr_ready(wr_ready),
        .wr_pc(wr_pc),
        .wr_bank(wr_bank),
        .wr_data(wr_data),
        .wr_last(wr_last),
        .image_ready(image_ready),
        .loading(loading),
        .load_fault(load_fault),
        .start_valid(start_valid && !stores_busy && !loading_request),
        .start_ready(engine_start_ready),
        .start_pc(start_pc),
        .start_limit(start_limit),
        .start_job(start_job),
        .start_fmt(start_fmt),
        .predicates(predicates),
        .addr_valid(addr_valid),
        .addr_ready(addr_ready),
        .addr_mode(addr_mode),
        .addr_value(addr_value),
        .addr_stride(addr_stride),
        .addr_rsp_valid(addr_rsp_valid),
        .addr_rsp_ready(addr_rsp_ready),
        .addr_rsp_fault(addr_rsp_fault),
        .addr_rsp_job(addr_rsp_job),
        .addr_rsp_tag(addr_rsp_tag),
        .exec_valid(exec_valid),
        .exec_ready(exec_ready),
        .exec_words(exec_words),
        .exec_job(exec_job),
        .exec_tag(exec_tag),
        .exec_fmt(exec_fmt),
        .exec_last(exec_last),
        .exec_cancel(exec_cancel),
        .exec_rsp_valid(exec_rsp_valid),
        .exec_rsp_ready(exec_rsp_ready),
        .exec_rsp_fault(exec_rsp_fault),
        .exec_rsp_job(exec_rsp_job),
        .exec_rsp_tag(exec_rsp_tag),
        .exec_rsp_fmt(exec_rsp_fmt),
        .done_valid(done_valid),
        .done_ready(done_ready),
        .done_fault(done_fault),
        .pc(pc),
        .retired(retired)
    );
    operator_controller operator (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .epoch(exec_cancel),
        .idle(idle),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_index(cfg_index),
        .cfg_rev(cfg_rev),
        .cfg_data(cfg_data),
        .cfg_fault(cfg_fault),
        .addr_valid(addr_valid),
        .addr_ready(addr_ready),
        .addr_mode(addr_mode),
        .addr_value(addr_value),
        .addr_stride(addr_stride),
        .addr_job(exec_job),
        .addr_tag(exec_tag),
        .addr_fmt(exec_fmt),
        .addr_rsp_valid(addr_rsp_valid),
        .addr_rsp_ready(addr_rsp_ready),
        .addr_rsp_fault(addr_rsp_fault),
        .addr_rsp_job(addr_rsp_job),
        .addr_rsp_tag(addr_rsp_tag),
        .read_valid(read_valid),
        .read_ready(read_ready),
        .read_desc(read_desc),
        .read_out(read_out),
        .read_red(read_red),
        .read_step(read_step),
        .read_job(read_job),
        .read_tag(read_tag),
        .read_fmt(read_fmt),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .read_mat(read_mat),
        .read_vec(read_vec),
        .read_mask(read_mask),
        .read_fault(read_fault),
        .read_rsp_job(read_rsp_job),
        .read_rsp_tag(read_rsp_tag),
        .read_rsp_fmt(read_rsp_fmt),
        .exec_valid(exec_valid),
        .exec_ready(exec_ready),
        .exec_words(exec_words),
        .exec_job(exec_job),
        .exec_tag(exec_tag),
        .exec_fmt(exec_fmt),
        .exec_last(exec_last),
        .exec_rsp_valid(exec_rsp_valid),
        .exec_rsp_ready(exec_rsp_ready),
        .exec_rsp_fault(exec_rsp_fault),
        .exec_rsp_job(exec_rsp_job),
        .exec_rsp_tag(exec_rsp_tag),
        .exec_rsp_fmt(exec_rsp_fmt),
        .link_ready(link_ready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_data(result_data),
        .result_mask(result_mask),
        .result_index(result_index),
        .result_job(result_job),
        .result_tag(result_tag),
        .result_fmt(result_fmt),
        .result_last(result_last)
    );
    wire unused_read_last;
    resident_operands operands (
        .clk(clk),
        .rst(rst),
        .cancel(cancel),
        .req_valid(read_valid),
        .req_ready(read_ready),
        .req_mode(read_desc[`CSR_OP_MODE_LSB +: `CSR_OP_MODE_W]),
        .req_trans(read_desc[`CSR_OP_TRANS_LSB +: `CSR_OP_TRANS_W]),
        .req_rows(read_desc[`CSR_OP_ROWS_LSB +: `CSR_OP_ROWS_W]),
        .req_cols(read_desc[`CSR_OP_COLS_LSB +: `CSR_OP_COLS_W]),
        .req_out(read_out),
        .req_red(read_red),
        .req_step(read_step),
        .req_vec_base(read_desc[`CSR_OP_VEC_BASE_LSB +: `CSR_OP_VEC_BASE_W]),
        .req_vec_plane(read_desc[`CSR_OP_VEC_PLANE_LSB +: `CSR_OP_VEC_PLANE_W]),
        .req_scale(read_desc[`CSR_OP_SCALE_LSB +: `CSR_OP_SCALE_W]),
        .req_key(read_desc[`CSR_OP_KEY_LSB +: `CSR_OP_KEY_W]),
        .req_mat_generation(read_desc[`CSR_OP_MAT_GENERATION_LSB +: `CSR_OP_MAT_GENERATION_W]),
        .req_vec_generation(read_desc[`CSR_OP_VEC_GENERATION_LSB +: `CSR_OP_VEC_GENERATION_W]),
        .req_job(read_job),
        .req_tag(read_tag),
        .req_fmt(read_fmt),
        .req_last(1'b0),
        .rsp_valid(read_rsp_valid),
        .rsp_ready(read_rsp_ready),
        .rsp_mat(read_mat),
        .rsp_vec(read_vec),
        .rsp_mask(read_mask),
        .rsp_fault(read_fault),
        .rsp_job(read_rsp_job),
        .rsp_tag(read_rsp_tag),
        .rsp_fmt(read_rsp_fmt),
        .rsp_last(unused_read_last),
        .idle(idle),
        .read_allow(read_allow),
        .b_begin_valid(b_begin_valid),
        .b_begin_ready(b_begin_ready),
        .b_begin_rows(b_begin_rows),
        .b_begin_cols(b_begin_cols),
        .b_begin_key(b_begin_key),
        .b_begin_generation(b_begin_generation),
        .b_begin_job(b_begin_job),
        .b_begin_fmt(b_begin_fmt),
        .b_fill_valid(b_fill_valid),
        .b_fill_ready(b_fill_ready),
        .b_fill_slot(b_fill_slot),
        .b_fill_block(b_fill_block),
        .b_fill_mask(b_fill_mask),
        .b_fill_data(b_fill_data),
        .b_fill_last(b_fill_last),
        .b_loading(b_loading),
        .b_cache_valid(b_cache_valid),
        .b_load_fault(b_load_fault),
        .v_begin_valid(v_begin_valid),
        .v_begin_ready(v_begin_ready),
        .v_begin_plane(v_begin_plane),
        .v_begin_length(v_begin_length),
        .v_begin_generation(v_begin_generation),
        .v_begin_job(v_begin_job),
        .v_begin_fmt(v_begin_fmt),
        .v_fill_valid(v_fill_valid),
        .v_fill_ready(v_fill_ready),
        .v_fill_block(v_fill_block),
        .v_fill_mask(v_fill_mask),
        .v_fill_data(v_fill_data),
        .v_fill_last(v_fill_last),
        .v_loading(v_loading),
        .v_plane_valid(v_plane_valid),
        .v_load_fault(v_load_fault),
        .p_begin_valid(p_begin_valid),
        .p_begin_seed(p_begin_seed),
        .p_begin_rows(p_begin_rows),
        .p_begin_cols(p_begin_cols),
        .p_begin_key(p_begin_key),
        .p_begin_generation(p_begin_generation),
        .p_begin_job(p_begin_job),
        .p_begin_fmt(p_begin_fmt),
        .p_begin_ready(p_begin_ready),
        .p_valid(p_valid),
        .p_loading(p_loading),
        .p_fault(p_fault)
    );
endmodule
