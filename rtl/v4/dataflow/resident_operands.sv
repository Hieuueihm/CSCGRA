`include "memory_defs.vh"
`include "phi_interface.vh"
module resident_operands (
    input wire  clk,
    input wire  rst,
    input wire  cancel,
    input wire  req_valid,
    output wire  req_ready,
    input wire [1:0] req_mode,
    input wire  req_trans,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols,
    input wire [10:0] req_out,
    input wire [10:0] req_red,
    input wire [2:0] req_step,
    input wire [11:0] req_vec_base,
    input wire [1:0] req_vec_plane,
    input wire [`CSR_PE_C_W-1:0] req_scale,
    input wire [127:0] req_key,
    input wire [31:0] req_mat_generation,
    input wire [31:0] req_vec_generation,
    input wire [15:0] req_job,
    input wire [15:0] req_tag,
    input wire [7:0] req_fmt,
    input wire  req_last,
    output wire  rsp_valid,
    input wire  rsp_ready,
    output wire [32*`CSR_PE_S_W-1:0] rsp_mat,
    output wire [32*`CSR_PE_S_W-1:0] rsp_vec,
    output wire [31:0] rsp_mask,
    output wire [3:0] rsp_fault,
    output wire [15:0] rsp_job,
    output wire [15:0] rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire  rsp_last,
    input wire  idle,
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
    wire  mat_valid;
    wire  mat_ready;
    wire  mat_dense;
    wire [31:0] mat_mask;
    wire [287:0] mat_addr;
    wire [127:0] mat_key;
    wire [31:0] mat_generation;
    wire [15:0] mem_job;
    wire [15:0] mem_tag;
    wire [7:0] mem_fmt;
    wire  mat_rsp_valid;
    wire  mat_rsp_ready;
    wire [32*`CSR_PE_C_W-1:0] mat_rsp_data;
    wire [255:0] mat_rsp_masks;
    wire [31:0] mat_rsp_mask;
    wire [31:0] mat_rsp_generation;
    wire [15:0] mat_rsp_job;
    wire [15:0] mat_rsp_tag;
    wire [7:0] mat_rsp_fmt;
    wire [3:0] mat_rsp_fault;
    wire  vec_valid;
    wire  vec_ready;
    wire [1:0] vec_plane;
    wire [31:0] vec_mask;
    wire [223:0] vec_addr;
    wire [31:0] vec_generation;
    wire  vec_rsp_valid;
    wire  vec_rsp_ready;
    wire [32*`CSR_PE_S_W-1:0] vec_rsp_data;
    wire [31:0] vec_rsp_mask;
    wire [31:0] vec_rsp_generation;
    wire [15:0] vec_rsp_job;
    wire [15:0] vec_rsp_tag;
    wire [7:0] vec_rsp_fmt;
    wire [3:0] vec_rsp_fault;
    reg [7:0] phi_rows, b_rows;
    reg [10:0] phi_cols, b_cols;
    wire shape_good = req_mode[1] ? req_rows == b_rows && req_cols == b_cols : req_rows == phi_rows && req_cols == phi_cols;
    wire p_take = p_begin_valid && p_begin_ready;
    operand_reader reader (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_ready(req_ready), .req_mode(req_mode),
        .req_trans(req_trans), .req_rows(shape_good ? req_rows : 8'b0), .req_cols(req_cols), .req_out(req_out),
        .req_red(req_red), .req_step(req_step), .req_vec_base(req_vec_base), .req_vec_plane(req_vec_plane),
        .req_scale(req_scale), .req_key(req_key), .req_mat_generation(req_mat_generation),
        .req_vec_generation(req_vec_generation), .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt),
        .req_last(req_last), .mat_valid(mat_valid), .mat_ready(mat_ready), .mat_dense(mat_dense), .mat_mask(mat_mask),
        .mat_addr(mat_addr), .mat_key(mat_key), .mat_generation(mat_generation), .mem_job(mem_job), .mem_tag(mem_tag),
        .mem_fmt(mem_fmt), .mat_rsp_valid(mat_rsp_valid), .mat_rsp_ready(mat_rsp_ready), .mat_rsp_data(mat_rsp_data),
        .mat_rsp_masks(mat_rsp_masks), .mat_rsp_mask(mat_rsp_mask), .mat_rsp_generation(mat_rsp_generation),
        .mat_rsp_job(mat_rsp_job), .mat_rsp_tag(mat_rsp_tag), .mat_rsp_fmt(mat_rsp_fmt), .mat_rsp_fault(mat_rsp_fault),
        .vec_valid(vec_valid), .vec_ready(vec_ready), .vec_plane(vec_plane), .vec_mask(vec_mask), .vec_addr(vec_addr),
        .vec_generation(vec_generation), .vec_rsp_valid(vec_rsp_valid), .vec_rsp_ready(vec_rsp_ready),
        .vec_rsp_data(vec_rsp_data), .vec_rsp_mask(vec_rsp_mask), .vec_rsp_generation(vec_rsp_generation),
        .vec_rsp_job(vec_rsp_job), .vec_rsp_tag(vec_rsp_tag), .vec_rsp_fmt(vec_rsp_fmt), .vec_rsp_fault(vec_rsp_fault),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_mat(rsp_mat), .rsp_vec(rsp_vec), .rsp_mask(rsp_mask),
        .rsp_fault(rsp_fault), .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_last(rsp_last)
    );
    wire  b_rd_valid;
    wire  b_rd_ready;
    wire [31:0] b_rd_mask;
    wire [32*`CSR_MEM_B_AW-1:0] b_rd_addr;
    wire [127:0] b_rd_key;
    wire [31:0] b_rd_generation;
    wire [15:0] b_rd_job;
    wire [15:0] b_rd_tag;
    wire [7:0] b_rd_fmt;
    wire  b_rsp_valid;
    wire  b_rsp_ready;
    wire [32*`CSR_PE_C_W-1:0] b_rsp_data;
    wire [31:0] b_rsp_mask;
    wire [31:0] b_rsp_generation;
    wire [15:0] b_rsp_job;
    wire [15:0] b_rsp_tag;
    wire [7:0] b_rsp_fmt;
    wire [3:0] b_rsp_fault;
    wire b_begin_ready_internal;
    assign b_begin_ready = b_begin_ready_internal && idle;
    support_matrix_cache b_store (
        .clk(clk), .rst(rst), .cancel(cancel), .begin_valid(b_begin_valid && idle), .begin_ready(b_begin_ready_internal),
        .begin_rows(b_begin_rows), .begin_cols(b_begin_cols), .begin_key(b_begin_key), .begin_generation(b_begin_generation),
        .begin_job(b_begin_job), .begin_fmt(b_begin_fmt), .fill_valid(b_fill_valid), .fill_ready(b_fill_ready),
        .fill_slot(b_fill_slot), .fill_block(b_fill_block), .fill_mask(b_fill_mask), .fill_data(b_fill_data),
        .fill_last(b_fill_last), .loading(b_loading), .cache_valid(b_cache_valid), .load_fault(b_load_fault),
        .rd_valid(b_rd_valid), .rd_ready(b_rd_ready), .rd_mask(b_rd_mask), .rd_addr(b_rd_addr), .rd_key(b_rd_key),
        .rd_generation(b_rd_generation), .rd_job(b_rd_job), .rd_tag(b_rd_tag), .rd_fmt(b_rd_fmt), .rsp_valid(b_rsp_valid),
        .rsp_ready(b_rsp_ready), .rsp_data(b_rsp_data), .rsp_mask(b_rsp_mask), .rsp_generation(b_rsp_generation),
        .rsp_job(b_rsp_job), .rsp_tag(b_rsp_tag), .rsp_fmt(b_rsp_fmt), .rsp_fault(b_rsp_fault)
    );
    wire [1:0] v_rd_valid;
    wire [1:0] v_rd_ready;
    wire [3:0] v_rd_plane;
    wire [63:0] v_rd_mask;
    wire [64*`CSR_MEM_V_AW-1:0] v_rd_addr;
    wire [63:0] v_rd_generation;
    wire [31:0] v_rd_job;
    wire [31:0] v_rd_tag;
    wire [15:0] v_rd_fmt;
    wire [1:0] v_rsp_valid;
    wire [1:0] v_rsp_ready;
    wire [64*`CSR_PE_S_W-1:0] v_rsp_data;
    wire [63:0] v_rsp_mask;
    wire [63:0] v_rsp_generation;
    wire [31:0] v_rsp_job;
    wire [31:0] v_rsp_tag;
    wire [15:0] v_rsp_fmt;
    wire [7:0] v_rsp_fault;
    wire v_begin_ready_internal;
    assign v_begin_ready = v_begin_ready_internal && idle;
    vector_store v_store (
        .clk(clk), .rst(rst), .cancel(cancel), .begin_valid(v_begin_valid && idle), .begin_ready(v_begin_ready_internal),
        .begin_plane(v_begin_plane), .begin_length(v_begin_length), .begin_generation(v_begin_generation),
        .begin_job(v_begin_job), .begin_fmt(v_begin_fmt), .fill_valid(v_fill_valid), .fill_ready(v_fill_ready),
        .fill_block(v_fill_block), .fill_mask(v_fill_mask), .fill_data(v_fill_data), .fill_last(v_fill_last),
        .loading(v_loading), .plane_valid(v_plane_valid), .load_fault(v_load_fault), .rd_valid(v_rd_valid),
        .rd_ready(v_rd_ready), .rd_plane(v_rd_plane), .rd_mask(v_rd_mask), .rd_addr(v_rd_addr),
        .rd_generation(v_rd_generation), .rd_job(v_rd_job), .rd_tag(v_rd_tag), .rd_fmt(v_rd_fmt), .rsp_valid(v_rsp_valid),
        .rsp_ready(v_rsp_ready), .rsp_data(v_rsp_data), .rsp_mask(v_rsp_mask), .rsp_generation(v_rsp_generation),
        .rsp_job(v_rsp_job), .rsp_tag(v_rsp_tag), .rsp_fmt(v_rsp_fmt), .rsp_fault(v_rsp_fault)
    );
    wire  p_req_ready;
    wire  p_rd_valid;
    wire  p_rd_ready;
    wire [7:0] p_rd_mask;
    wire [71:0] p_rd_addr;
    wire [31:0] p_rd_generation;
    wire [15:0] p_rd_tag;
    wire  p_rsp_valid;
    wire [575:0] p_rsp_data;
    wire [255:0] p_rsp_masks;
    wire [31:0] p_rsp_mask;
    wire [31:0] p_rsp_generation;
    wire [15:0] p_rsp_job;
    wire [15:0] p_rsp_tag;
    wire [7:0] p_rsp_fmt;
    wire [3:0] p_rsp_fault;
    wire  g_start_ready;
    wire  g_busy;
    wire  g_out_valid;
    wire [`CSR_PHI_WORD_BITS-1:0] g_out_signs;
    wire [`CSR_PHI_WORD_BITS-1:0] g_out_mask;
    wire [`CSR_PHI_COLUMN_W-1:0] g_out_column;
    wire [`CSR_PHI_ROW_BLOCK_W-1:0] g_out_row_block;
    wire [`CSR_PHI_JOB_TAG_W-1:0] g_out_job_tag;
    wire [`CSR_PHI_OP_TAG_W-1:0] g_out_op_tag;
    wire [`CSR_PHI_FORMAT_TAG_W-1:0] g_out_format_tag;
    wire [`CSR_PHI_GENERATION_W-1:0] g_out_generation;
    wire  g_out_last;
    wire  unused_g_done;
    wire [`CSR_PHI_FAULT_W-1:0] g_fault_code;
    wire  c_begin_ready;
    wire  c_filling;
    wire  c_fill_ready;
    wire  c_cache_valid;
    wire  unused_c_published;
    wire [`CSR_PHI_KEY_W-1:0] c_cache_key;
    wire [`CSR_PHI_GENERATION_W-1:0] c_cache_generation;
    wire [`CSR_PHI_FAULT_W-1:0] c_fault_code;
    wire  c_rsp_valid;
    wire  c_rsp_ready;
    wire [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] c_rsp_signs;
    wire [`CSR_PHI_BANKS*`CSR_PHI_WORD_BITS-1:0] c_rsp_masks;
    wire [`CSR_PHI_BANKS-1:0] c_rsp_bank_mask;
    wire [`CSR_PHI_GENERATION_W-1:0] c_rsp_generation;
    wire [`CSR_PHI_READ_TAG_W-1:0] c_rsp_tag;
    wire [`CSR_PHI_FAULT_W-1:0] c_rsp_fault;
    always @(posedge clk) begin
        if (rst || cancel) begin phi_rows <= '0; phi_cols <= '0; b_rows <= '0; b_cols <= '0; end
        else begin
            if (p_take) begin phi_rows <= p_begin_rows; phi_cols <= p_begin_cols; end
            if (b_begin_valid && b_begin_ready) begin b_rows <= b_begin_rows; b_cols <= {4'b0,b_begin_cols}; end
        end
    end
    reg [15:0] phi_job;
    reg [7:0] phi_fmt;
    assign p_begin_ready = idle && c_begin_ready && g_start_ready;
    assign p_valid = c_cache_valid;
    assign p_loading = c_filling || g_busy;
    assign p_fault = c_fault_code != 0 ? c_fault_code : g_fault_code;
    always @(posedge clk) begin
        if (rst || cancel) begin phi_job <= '0; phi_fmt <= '0; end
        else if (p_take) begin phi_job <= p_begin_job; phi_fmt <= p_begin_fmt; end
    end
    phi_sign_generator phi (
        .clk(clk), .rst(rst), .cancel(cancel), .start_valid(p_take), .start_ready(g_start_ready),
        .start_family(8'(`CSR_PHI_FAMILY)), .start_revision(8'(`CSR_PHI_REVISION)), .start_seed(p_begin_seed),
        .start_rows(p_begin_rows), .start_columns(p_begin_cols), .start_job_tag(p_begin_job), .start_op_tag(16'b0),
        .start_format_tag(p_begin_fmt), .start_generation(p_begin_generation), .busy(g_busy), .out_valid(g_out_valid),
        .out_ready(c_fill_ready), .out_signs(g_out_signs), .out_mask(g_out_mask), .out_column(g_out_column),
        .out_row_block(g_out_row_block), .out_job_tag(g_out_job_tag), .out_op_tag(g_out_op_tag),
        .out_format_tag(g_out_format_tag), .out_generation(g_out_generation), .out_last(g_out_last), .done(unused_g_done),
        .fault_code(g_fault_code)
    );
    phi_sign_cache cache (
        .clk(clk), .rst(rst), .invalidate(cancel), .begin_valid(p_take), .begin_ready(c_begin_ready),
        .begin_rows(p_begin_rows), .begin_columns(p_begin_cols), .begin_job_tag(p_begin_job), .begin_op_tag(16'b0),
        .begin_format_tag(p_begin_fmt), .begin_generation(p_begin_generation), .begin_key(p_begin_key), .filling(c_filling),
        .fill_valid(g_out_valid), .fill_ready(c_fill_ready), .fill_signs(g_out_signs), .fill_mask(g_out_mask),
        .fill_column(g_out_column), .fill_row_block(g_out_row_block), .fill_job_tag(g_out_job_tag),
        .fill_op_tag(g_out_op_tag), .fill_format_tag(g_out_format_tag), .fill_generation(g_out_generation),
        .fill_last(g_out_last), .cache_valid(c_cache_valid), .published(unused_c_published), .cache_key(c_cache_key),
        .cache_generation(c_cache_generation), .fault_code(c_fault_code), .rd_valid(p_rd_valid), .rd_ready(p_rd_ready),
        .rd_bank_mask(p_rd_mask), .rd_addresses(p_rd_addr), .rd_generation(p_rd_generation), .rd_tag(p_rd_tag),
        .rsp_valid(c_rsp_valid), .rsp_ready(c_rsp_ready), .rsp_signs(c_rsp_signs), .rsp_masks(c_rsp_masks),
        .rsp_bank_mask(c_rsp_bank_mask), .rsp_generation(c_rsp_generation), .rsp_tag(c_rsp_tag), .rsp_fault(c_rsp_fault)
    );
    phi_reader phi_adapter (
        .clk(clk), .rst(rst), .cancel(cancel), .cache_valid(c_cache_valid), .cache_key(c_cache_key),
        .cache_generation(c_cache_generation), .cache_job(phi_job), .cache_fmt(phi_fmt),
        .req_valid(mat_valid && !mat_dense && read_allow[0]), .req_ready(p_req_ready), .req_mask(mat_mask),
        .req_addr(mat_addr), .req_key(mat_key), .req_generation(mat_generation), .req_job(mem_job), .req_tag(mem_tag),
        .req_fmt(mem_fmt), .rd_valid(p_rd_valid), .rd_ready(p_rd_ready), .rd_mask(p_rd_mask), .rd_addr(p_rd_addr),
        .rd_generation(p_rd_generation), .rd_tag(p_rd_tag), .cache_rsp_valid(c_rsp_valid), .cache_rsp_ready(c_rsp_ready),
        .cache_rsp_signs(c_rsp_signs), .cache_rsp_masks(c_rsp_masks), .cache_rsp_mask(c_rsp_bank_mask),
        .cache_rsp_generation(c_rsp_generation), .cache_rsp_tag(c_rsp_tag), .cache_rsp_fault(c_rsp_fault),
        .rsp_valid(p_rsp_valid), .rsp_ready(mat_rsp_ready && !mat_dense && read_allow[2]), .rsp_data(p_rsp_data),
        .rsp_masks(p_rsp_masks), .rsp_mask(p_rsp_mask), .rsp_generation(p_rsp_generation), .rsp_job(p_rsp_job),
        .rsp_tag(p_rsp_tag), .rsp_fmt(p_rsp_fmt), .rsp_fault(p_rsp_fault)
    );
    assign b_rd_valid = mat_valid && mat_dense && read_allow[0];
    assign b_rd_mask = mat_mask; assign b_rd_addr = mat_addr; assign b_rd_key = mat_key;
    assign b_rd_generation = mat_generation; assign b_rd_job = mem_job; assign b_rd_tag = mem_tag; assign b_rd_fmt = mem_fmt;
    assign b_rsp_ready = mat_rsp_ready && mat_dense && read_allow[2];
    assign mat_ready = (mat_dense ? b_rd_ready : p_req_ready) && read_allow[0];
    assign mat_rsp_valid = (mat_dense ? b_rsp_valid : p_rsp_valid) && read_allow[2];
    assign mat_rsp_masks = mat_dense ? 256'b0 : p_rsp_masks;
    assign mat_rsp_data = mat_dense ? b_rsp_data : p_rsp_data;
    assign mat_rsp_mask = mat_dense ? b_rsp_mask : p_rsp_mask;
    assign mat_rsp_generation = mat_dense ? b_rsp_generation : p_rsp_generation;
    assign mat_rsp_job = mat_dense ? b_rsp_job : p_rsp_job;
    assign mat_rsp_tag = mat_dense ? b_rsp_tag : p_rsp_tag;
    assign mat_rsp_fmt = mat_dense ? b_rsp_fmt : p_rsp_fmt;
    assign mat_rsp_fault = mat_dense ? b_rsp_fault : p_rsp_fault;
    assign v_rd_valid = {1'b0, vec_valid && read_allow[1]};
    assign v_rd_plane = {2'b0, vec_plane}; assign v_rd_mask = {32'b0, vec_mask}; assign v_rd_addr = {224'b0, vec_addr};
    assign v_rd_generation = {32'b0, vec_generation}; assign v_rd_job = {16'b0, mem_job};
    assign v_rd_tag = {16'b0, mem_tag}; assign v_rd_fmt = {8'b0, mem_fmt};
    assign v_rsp_ready = {1'b0, vec_rsp_ready && read_allow[3]};
    assign vec_ready = v_rd_ready[0] && read_allow[1];
    assign vec_rsp_valid = v_rsp_valid[0] && read_allow[3];
    assign vec_rsp_data = v_rsp_data[863:0];
    assign vec_rsp_mask = v_rsp_mask[31:0];
    assign vec_rsp_generation = v_rsp_generation[31:0];
    assign vec_rsp_job = v_rsp_job[15:0];
    assign vec_rsp_tag = v_rsp_tag[15:0];
    assign vec_rsp_fmt = v_rsp_fmt[7:0];
    assign vec_rsp_fault = v_rsp_fault[3:0];
endmodule
