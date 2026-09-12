`include "memory_defs.vh"
`include "phi_interface.vh"
`include "builder_defs.vh"
module operator_memory (
    input wire  clk,
    input wire  rst,
    input wire  cancel,
    input wire  compute_active,
    input wire  p_begin_valid,
    input wire [31:0] p_begin_seed,
    input wire [7:0] p_begin_rows,
    input wire [10:0] p_begin_cols,
    input wire [127:0] p_begin_key,
    input wire [31:0] p_begin_generation,
    input wire [15:0] p_begin_job,
    input wire [7:0] p_begin_fmt,
    output wire  p_begin_ready,
    output wire  p_loading,
    output wire [3:0] p_fault,
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
    output wire [3:0] b_load_fault,
    input wire  build_req_valid,
    output wire  build_req_ready,
    input wire [7:0] build_req_rows,
    input wire [10:0] build_req_cols,
    input wire [6:0] build_req_count,
    input wire [959:0] build_req_support,
    input wire [17:0] build_req_scale,
    input wire [127:0] build_req_phi_key,
    input wire [127:0] build_req_b_key,
    input wire [31:0] build_req_phi_generation,
    input wire [31:0] build_req_b_generation,
    input wire [15:0] build_req_job,
    input wire [15:0] build_req_tag,
    input wire [7:0] build_req_fmt,
    output wire  build_rsp_valid,
    input wire  build_rsp_ready,
    output wire [3:0] build_rsp_fault,
    output wire [15:0] build_rsp_job,
    output wire [15:0] build_rsp_tag,
    output wire [7:0] build_rsp_fmt,
    output wire [31:0] build_rsp_cycles,
    output wire [15:0] build_rsp_words,
    output wire  build_busy,
    output wire  p_valid,
    output wire [7:0] p_rows,
    output wire [10:0] p_cols,
    output wire [127:0] p_key,
    output wire [31:0] p_generation,
    output wire [15:0] p_job,
    output wire [7:0] p_fmt,
    output wire  b_valid,
    output wire [7:0] b_rows,
    output wire [6:0] b_cols,
    output wire [127:0] b_key,
    output wire [31:0] b_generation,
    output wire [15:0] b_job,
    output wire [7:0] b_fmt,
    input wire  mat_valid,
    output wire  mat_ready,
    input wire [31:0] mat_mask,
    input wire [287:0] mat_addr,
    input wire [127:0] mat_key,
    input wire [31:0] mat_generation,
    output wire  mat_rsp_valid,
    input wire  mat_rsp_ready,
    output wire [575:0] mat_rsp_data,
    output wire [255:0] mat_rsp_masks,
    output wire [31:0] mat_rsp_mask,
    output wire [31:0] mat_rsp_generation,
    output wire [15:0] mat_rsp_job,
    output wire [15:0] mat_rsp_tag,
    output wire [7:0] mat_rsp_fmt,
    output wire [3:0] mat_rsp_fault,
    input wire  mat_dense,
    input wire [15:0] mem_job,
    input wire [15:0] mem_tag,
    input wire [7:0] mem_fmt
);
    wire  bmem_begin_ready;
    wire  bmem_fill_ready;
    wire  bmem_loading;
    wire  bmem_cache_valid;
    wire [3:0] bmem_load_fault;
    wire  bmem_rd_ready;
    wire  bmem_rsp_valid;
    wire [32*`CSR_PE_C_W-1:0] bmem_rsp_data;
    wire [31:0] bmem_rsp_mask;
    wire [31:0] bmem_rsp_generation;
    wire [15:0] bmem_rsp_job;
    wire [15:0] bmem_rsp_tag;
    wire [7:0] bmem_rsp_fmt;
    wire [3:0] bmem_rsp_fault;
    wire  builder_req_ready;
    wire [127:0] cache_cache_key;
    wire [31:0] cache_cache_generation;
    wire  builder_phi_invalidate;
    wire  builder_phi_rd_valid;
    wire  cache_rd_ready;
    wire [7:0] builder_phi_rd_bank_mask;
    wire [71:0] builder_phi_rd_addresses;
    wire [31:0] builder_phi_rd_generation;
    wire [15:0] builder_phi_rd_tag;
    wire  cache_rsp_valid;
    wire  builder_phi_rsp_ready;
    wire [255:0] cache_rsp_signs;
    wire [255:0] cache_rsp_masks;
    wire [7:0] cache_rsp_bank_mask;
    wire [31:0] cache_rsp_generation;
    wire [15:0] cache_rsp_tag;
    wire [3:0] cache_rsp_fault;
    wire  builder_b_cancel;
    wire  builder_b_begin_valid;
    wire [7:0] builder_b_begin_rows;
    wire [6:0] builder_b_begin_cols;
    wire [127:0] builder_b_begin_key;
    wire [31:0] builder_b_begin_generation;
    wire [15:0] builder_b_begin_job;
    wire [7:0] builder_b_begin_fmt;
    wire  builder_b_fill_valid;
    wire [6:0] builder_b_fill_slot;
    wire [1:0] builder_b_fill_block;
    wire [31:0] builder_b_fill_mask;
    wire [575:0] builder_b_fill_data;
    wire  builder_b_fill_last;
    wire  gen_start_ready;
    wire  gen_busy;
    wire  gen_out_valid;
    wire  cache_fill_ready;
    wire [`CSR_PHI_WORD_BITS-1:0] gen_out_signs;
    wire [`CSR_PHI_WORD_BITS-1:0] gen_out_mask;
    wire [`CSR_PHI_COLUMN_W-1:0] gen_out_column;
    wire [`CSR_PHI_ROW_BLOCK_W-1:0] gen_out_row_block;
    wire [`CSR_PHI_JOB_TAG_W-1:0] gen_out_job_tag;
    wire [`CSR_PHI_OP_TAG_W-1:0] gen_out_op_tag;
    wire [`CSR_PHI_FORMAT_TAG_W-1:0] gen_out_format_tag;
    wire [`CSR_PHI_GENERATION_W-1:0] gen_out_generation;
    wire  gen_out_last;
    wire  unused_gen_done;
    wire [`CSR_PHI_FAULT_W-1:0] gen_fault_code;
    wire  cache_begin_ready;
    wire  cache_filling;
    wire  cache_cache_valid;
    wire  unused_cache_published;
    wire [`CSR_PHI_FAULT_W-1:0] cache_fault_code;
    wire  adapter_req_ready;
    wire  adapter_rd_valid;
    wire [7:0] adapter_rd_mask;
    wire [71:0] adapter_rd_addr;
    wire [31:0] adapter_rd_generation;
    wire [15:0] adapter_rd_tag;
    wire  adapter_cache_rsp_ready;
    wire  adapter_rsp_valid;
    wire [575:0] adapter_rsp_data;
    wire [255:0] adapter_rsp_masks;
    wire [31:0] adapter_rsp_mask;
    wire [31:0] adapter_rsp_generation;
    wire [15:0] adapter_rsp_job;
    wire [15:0] adapter_rsp_tag;
    wire [7:0] adapter_rsp_fmt;
    wire [3:0] adapter_rsp_fault;
    localparam [2:0] IDLE=0, LOAD_P=1, LOAD_B=2, BUILD=3, READ=4;
    reg [2:0] owner;
    reg read_dense, build_authorized;
    reg [7:0] p_rows_q, b_rows_q;
    reg [10:0] p_cols_q;
    reg [6:0] b_cols_q;
    reg [15:0] p_job_q, b_job_q;
    reg [7:0] p_fmt_q, b_fmt_q;
    reg [127:0] b_key_q;
    reg [31:0] b_generation_q;
    wire active = !rst && !cancel;
    wire idle = active && owner == IDLE;
    wire host_p_take = p_begin_valid && p_begin_ready;
    wire host_b_take = b_begin_valid && b_begin_ready;
    wire build_take = build_req_valid && build_req_ready;
    wire read_grant = idle && (compute_active || (!p_begin_valid && !b_begin_valid && !build_req_valid));
    assign p_begin_ready = idle && !compute_active && gen_start_ready && cache_begin_ready;
    assign b_begin_ready = idle && !compute_active && !p_begin_valid && bmem_begin_ready;
    assign b_fill_ready = active && owner == LOAD_B && bmem_fill_ready;
    assign build_req_ready = idle && !compute_active && !p_begin_valid && !b_begin_valid && builder_req_ready;
    assign build_busy = owner == BUILD;
    assign mat_ready = read_grant && (mat_dense ? bmem_rd_ready : adapter_req_ready);
    assign mat_rsp_valid = active && owner == READ && (read_dense ? bmem_rsp_valid : adapter_rsp_valid);
    assign mat_rsp_masks = read_dense ? 256'b0 : adapter_rsp_masks;
    assign p_loading = gen_busy || cache_filling;
    assign p_fault = gen_fault_code != 0 ? gen_fault_code : cache_fault_code;
    assign p_valid = cache_cache_valid;
    assign p_rows = p_rows_q; assign p_cols = p_cols_q; assign p_job = p_job_q; assign p_fmt = p_fmt_q;
    assign p_key = cache_cache_key; assign p_generation = cache_cache_generation;
    assign b_valid = bmem_cache_valid;
    assign b_loading = bmem_loading; assign b_load_fault = bmem_load_fault;
    assign b_rows = b_rows_q; assign b_cols = b_cols_q; assign b_job = b_job_q; assign b_fmt = b_fmt_q;
    assign b_key = b_key_q; assign b_generation = b_generation_q;
    always @(posedge clk) begin
        if (!active) begin
            owner <= IDLE; read_dense <= 1'b0; build_authorized <= 1'b0;
            p_rows_q <= '0; p_cols_q <= '0; p_job_q <= '0; p_fmt_q <= '0;
            b_rows_q <= '0; b_cols_q <= '0; b_job_q <= '0; b_fmt_q <= '0; b_key_q <= '0; b_generation_q <= '0;
        end else begin
            if (host_p_take) begin
                owner <= LOAD_P; p_rows_q <= p_begin_rows; p_cols_q <= p_begin_cols;
                p_job_q <= p_begin_job; p_fmt_q <= p_begin_fmt;
            end
            if (host_b_take) owner <= LOAD_B;
            if (build_take) begin
                owner <= BUILD; build_authorized <= build_req_job == p_job_q && build_req_fmt == p_fmt_q;
            end
            if (mat_valid && mat_ready) begin owner <= READ; read_dense <= mat_dense; end
            if (owner == LOAD_P && !p_loading) owner <= IDLE;
            if (owner == LOAD_B && !b_loading) owner <= IDLE;
            if (build_rsp_valid && build_rsp_ready) owner <= IDLE;
            if (mat_rsp_valid && mat_rsp_ready) owner <= IDLE;
            if ((build_busy && builder_b_begin_valid && bmem_begin_ready) || host_b_take) begin
                b_rows_q <= build_busy ? builder_b_begin_rows : b_begin_rows;
                b_cols_q <= build_busy ? builder_b_begin_cols : b_begin_cols;
                b_job_q <= build_busy ? builder_b_begin_job : b_begin_job;
                b_fmt_q <= build_busy ? builder_b_begin_fmt : b_begin_fmt;
                b_key_q <= build_busy ? builder_b_begin_key : b_begin_key;
                b_generation_q <= build_busy ? builder_b_begin_generation : b_begin_generation;
            end
        end
    end
    assign mat_rsp_data = read_dense ? bmem_rsp_data : adapter_rsp_data;
    assign mat_rsp_mask = read_dense ? bmem_rsp_mask : adapter_rsp_mask;
    assign mat_rsp_generation = read_dense ? bmem_rsp_generation : adapter_rsp_generation;
    assign mat_rsp_job = read_dense ? bmem_rsp_job : adapter_rsp_job;
    assign mat_rsp_tag = read_dense ? bmem_rsp_tag : adapter_rsp_tag;
    assign mat_rsp_fmt = read_dense ? bmem_rsp_fmt : adapter_rsp_fmt;
    assign mat_rsp_fault = read_dense ? bmem_rsp_fault : adapter_rsp_fault;
    support_matrix_cache b (
        .clk(clk), .rst(rst), .cancel(cancel || builder_b_cancel),
        .begin_valid(build_busy ? builder_b_begin_valid : host_b_take), .begin_ready(bmem_begin_ready),
        .begin_rows(build_busy ? builder_b_begin_rows : b_begin_rows),
        .begin_cols(build_busy ? builder_b_begin_cols : b_begin_cols),
        .begin_key(build_busy ? builder_b_begin_key : b_begin_key),
        .begin_generation(build_busy ? builder_b_begin_generation : b_begin_generation),
        .begin_job(build_busy ? builder_b_begin_job : b_begin_job),
        .begin_fmt(build_busy ? builder_b_begin_fmt : b_begin_fmt),
        .fill_valid(build_busy ? builder_b_fill_valid : b_fill_valid && owner == LOAD_B), .fill_ready(bmem_fill_ready),
        .fill_slot(build_busy ? builder_b_fill_slot : b_fill_slot),
        .fill_block(build_busy ? builder_b_fill_block : b_fill_block),
        .fill_mask(build_busy ? builder_b_fill_mask : b_fill_mask),
        .fill_data(build_busy ? builder_b_fill_data : b_fill_data),
        .fill_last(build_busy ? builder_b_fill_last : b_fill_last), .loading(bmem_loading),
        .cache_valid(bmem_cache_valid), .load_fault(bmem_load_fault), .rd_valid(read_grant && mat_valid && mat_dense),
        .rd_ready(bmem_rd_ready), .rd_mask(mat_mask), .rd_addr(mat_addr), .rd_key(mat_key),
        .rd_generation(mat_generation), .rd_job(mem_job), .rd_tag(mem_tag), .rd_fmt(mem_fmt),
        .rsp_valid(bmem_rsp_valid), .rsp_ready(owner == READ && read_dense && mat_rsp_ready), .rsp_data(bmem_rsp_data),
        .rsp_mask(bmem_rsp_mask), .rsp_generation(bmem_rsp_generation), .rsp_job(bmem_rsp_job), .rsp_tag(bmem_rsp_tag),
        .rsp_fmt(bmem_rsp_fmt), .rsp_fault(bmem_rsp_fault)
    );
    support_builder builder (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(build_take), .req_ready(builder_req_ready),
        .req_rows(build_req_rows), .req_cols(build_req_cols), .req_count(build_req_count),
        .req_support(build_req_support), .req_scale(build_req_scale), .req_phi_key(build_req_phi_key),
        .req_b_key(build_req_b_key), .req_phi_generation(build_req_phi_generation),
        .req_b_generation(build_req_b_generation), .req_job(build_req_job), .req_tag(build_req_tag),
        .req_fmt(build_req_fmt), .phi_valid(cache_cache_valid && build_authorized), .phi_key(cache_cache_key),
        .phi_generation(cache_cache_generation), .phi_rows(p_rows), .phi_cols(p_cols),
        .phi_invalidate(builder_phi_invalidate), .phi_rd_valid(builder_phi_rd_valid), .phi_rd_ready(cache_rd_ready),
        .phi_rd_bank_mask(builder_phi_rd_bank_mask), .phi_rd_addresses(builder_phi_rd_addresses),
        .phi_rd_generation(builder_phi_rd_generation), .phi_rd_tag(builder_phi_rd_tag), .phi_rsp_valid(cache_rsp_valid),
        .phi_rsp_ready(builder_phi_rsp_ready), .phi_rsp_signs(cache_rsp_signs), .phi_rsp_masks(cache_rsp_masks),
        .phi_rsp_bank_mask(cache_rsp_bank_mask), .phi_rsp_generation(cache_rsp_generation), .phi_rsp_tag(cache_rsp_tag),
        .phi_rsp_fault(cache_rsp_fault), .b_cancel(builder_b_cancel), .b_begin_valid(builder_b_begin_valid),
        .b_begin_ready(bmem_begin_ready), .b_begin_rows(builder_b_begin_rows), .b_begin_cols(builder_b_begin_cols),
        .b_begin_key(builder_b_begin_key), .b_begin_generation(builder_b_begin_generation),
        .b_begin_job(builder_b_begin_job), .b_begin_fmt(builder_b_begin_fmt), .b_fill_valid(builder_b_fill_valid),
        .b_fill_ready(bmem_fill_ready), .b_fill_slot(builder_b_fill_slot), .b_fill_block(builder_b_fill_block),
        .b_fill_mask(builder_b_fill_mask), .b_fill_data(builder_b_fill_data), .b_fill_last(builder_b_fill_last),
        .b_loading(bmem_loading), .b_valid(bmem_cache_valid), .b_load_fault(bmem_load_fault),
        .rsp_valid(build_rsp_valid), .rsp_ready(build_rsp_ready), .rsp_fault(build_rsp_fault), .rsp_job(build_rsp_job),
        .rsp_tag(build_rsp_tag), .rsp_fmt(build_rsp_fmt), .rsp_cycles(build_rsp_cycles), .rsp_words(build_rsp_words)
    );
    phi_sign_generator generator (
        .clk(clk), .rst(rst), .cancel(cancel || builder_phi_invalidate), .start_valid(host_p_take),
        .start_ready(gen_start_ready), .start_family(8'(`CSR_PHI_FAMILY)), .start_revision(8'(`CSR_PHI_REVISION)),
        .start_seed(p_begin_seed), .start_rows(p_begin_rows), .start_columns(p_begin_cols), .start_job_tag(p_begin_job),
        .start_op_tag(16'b0), .start_format_tag(p_begin_fmt), .start_generation(p_begin_generation), .busy(gen_busy),
        .out_valid(gen_out_valid), .out_ready(cache_fill_ready), .out_signs(gen_out_signs), .out_mask(gen_out_mask),
        .out_column(gen_out_column), .out_row_block(gen_out_row_block), .out_job_tag(gen_out_job_tag),
        .out_op_tag(gen_out_op_tag), .out_format_tag(gen_out_format_tag), .out_generation(gen_out_generation),
        .out_last(gen_out_last), .done(unused_gen_done), .fault_code(gen_fault_code)
    );
    phi_sign_cache phi (
        .clk(clk), .rst(rst), .invalidate(cancel || builder_phi_invalidate), .begin_valid(host_p_take),
        .begin_ready(cache_begin_ready), .begin_rows(p_begin_rows), .begin_columns(p_begin_cols),
        .begin_job_tag(p_begin_job), .begin_op_tag(16'b0), .begin_format_tag(p_begin_fmt),
        .begin_generation(p_begin_generation), .begin_key(p_begin_key), .filling(cache_filling),
        .fill_valid(gen_out_valid), .fill_ready(cache_fill_ready), .fill_signs(gen_out_signs), .fill_mask(gen_out_mask),
        .fill_column(gen_out_column), .fill_row_block(gen_out_row_block), .fill_job_tag(gen_out_job_tag),
        .fill_op_tag(gen_out_op_tag), .fill_format_tag(gen_out_format_tag), .fill_generation(gen_out_generation),
        .fill_last(gen_out_last), .cache_valid(cache_cache_valid), .published(unused_cache_published),
        .cache_key(cache_cache_key), .cache_generation(cache_cache_generation), .fault_code(cache_fault_code),
        .rd_valid(build_busy ? builder_phi_rd_valid : adapter_rd_valid), .rd_ready(cache_rd_ready),
        .rd_bank_mask(build_busy ? builder_phi_rd_bank_mask : adapter_rd_mask),
        .rd_addresses(build_busy ? builder_phi_rd_addresses : adapter_rd_addr),
        .rd_generation(build_busy ? builder_phi_rd_generation : adapter_rd_generation),
        .rd_tag(build_busy ? builder_phi_rd_tag : adapter_rd_tag), .rsp_valid(cache_rsp_valid),
        .rsp_ready(build_busy ? builder_phi_rsp_ready : adapter_cache_rsp_ready), .rsp_signs(cache_rsp_signs),
        .rsp_masks(cache_rsp_masks), .rsp_bank_mask(cache_rsp_bank_mask), .rsp_generation(cache_rsp_generation),
        .rsp_tag(cache_rsp_tag), .rsp_fault(cache_rsp_fault)
    );
    phi_reader adapter (
        .clk(clk), .rst(rst), .cancel(cancel), .cache_valid(cache_cache_valid), .cache_key(cache_cache_key),
        .cache_generation(cache_cache_generation), .cache_job(p_job), .cache_fmt(p_fmt),
        .req_valid(read_grant && mat_valid && !mat_dense), .req_ready(adapter_req_ready), .req_mask(mat_mask),
        .req_addr(mat_addr), .req_key(mat_key), .req_generation(mat_generation), .req_job(mem_job), .req_tag(mem_tag),
        .req_fmt(mem_fmt), .rd_valid(adapter_rd_valid), .rd_ready(cache_rd_ready), .rd_mask(adapter_rd_mask),
        .rd_addr(adapter_rd_addr), .rd_generation(adapter_rd_generation), .rd_tag(adapter_rd_tag),
        .cache_rsp_valid(cache_rsp_valid), .cache_rsp_ready(adapter_cache_rsp_ready), .cache_rsp_signs(cache_rsp_signs),
        .cache_rsp_masks(cache_rsp_masks), .cache_rsp_mask(cache_rsp_bank_mask),
        .cache_rsp_generation(cache_rsp_generation), .cache_rsp_tag(cache_rsp_tag), .cache_rsp_fault(cache_rsp_fault),
        .rsp_valid(adapter_rsp_valid), .rsp_ready(owner == READ && !read_dense && mat_rsp_ready),
        .rsp_data(adapter_rsp_data), .rsp_masks(adapter_rsp_masks), .rsp_mask(adapter_rsp_mask),
        .rsp_generation(adapter_rsp_generation), .rsp_job(adapter_rsp_job), .rsp_tag(adapter_rsp_tag),
        .rsp_fmt(adapter_rsp_fmt), .rsp_fault(adapter_rsp_fault)
    );
endmodule
