`include "memory_defs.vh"
`include "feeder_interface.vh"

module operand_reader (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [1:0] req_mode,
    input wire req_trans,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols, req_out, req_red,
    input wire [2:0] req_step,
    input wire [11:0] req_vec_base,
    input wire [1:0] req_vec_plane,
    input wire [`CSR_PE_C_W-1:0] req_scale,
    input wire [127:0] req_key,
    input wire [31:0] req_mat_generation, req_vec_generation,
    input wire [15:0] req_job, req_tag,
    input wire [7:0] req_fmt,
    input wire req_last,
    output wire mat_valid,
    input wire mat_ready,
    output wire mat_dense,
    output wire [31:0] mat_mask,
    output wire [287:0] mat_addr,
    output wire [127:0] mat_key,
    output wire [31:0] mat_generation,
    output wire [15:0] mem_job, mem_tag,
    output wire [7:0] mem_fmt,
    input wire mat_rsp_valid,
    output wire mat_rsp_ready,
    input wire [32*`CSR_PE_C_W-1:0] mat_rsp_data,
    input wire [255:0] mat_rsp_masks,
    input wire [31:0] mat_rsp_mask, mat_rsp_generation,
    input wire [15:0] mat_rsp_job, mat_rsp_tag,
    input wire [7:0] mat_rsp_fmt,
    input wire [3:0] mat_rsp_fault,
    output wire vec_valid,
    input wire vec_ready,
    output wire [1:0] vec_plane,
    output wire [31:0] vec_mask,
    output wire [223:0] vec_addr,
    output wire [31:0] vec_generation,
    input wire vec_rsp_valid,
    output wire vec_rsp_ready,
    input wire [32*`CSR_PE_S_W-1:0] vec_rsp_data,
    input wire [31:0] vec_rsp_mask, vec_rsp_generation,
    input wire [15:0] vec_rsp_job, vec_rsp_tag,
    input wire [7:0] vec_rsp_fmt,
    input wire [3:0] vec_rsp_fault,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [32*`CSR_PE_S_W-1:0] rsp_mat, rsp_vec,
    output wire [31:0] rsp_mask,
    output wire [3:0] rsp_fault,
    output wire [15:0] rsp_job, rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire rsp_last
);
    localparam integer SW = `CSR_PE_S_W;
    localparam [2:0] IDLE = 0, READ = 1, FEED = 2, WAIT_FEED = 3, ERROR = 4;
    reg [2:0] state;
    reg [1:0] sent, received;
    reg [1:0] mode_q, plane_q;
    reg trans_q, last_q;
    reg [7:0] rows_q, fmt_q;
    reg [10:0] cols_q, out_q, red_q;
    reg [2:0] step_q;
    reg [`CSR_PE_C_W-1:0] scale_q;
    reg [127:0] key_q;
    reg [31:0] mat_gen_q, vec_gen_q, mat_mask_q, vec_mask_q;
    reg [287:0] mat_addr_q;
    reg [223:0] vec_addr_q;
    reg [19:0] vec_banks_q;
    reg [3:0] vec_lanes_q, fault_q;
    reg [15:0] job_q, tag_q;
    reg [575:0] matrix_data;
    reg [255:0] sign_masks;
    reg [31:0] matrix_mask;
    reg [4*SW-1:0] vector_data;
    reg [3:0] source_faults [0:1];
    wire [31:0] plan_mat_mask, plan_vec_mask;
    wire [287:0] plan_mat_addr;
    wire [223:0] plan_vec_addr;
    wire [19:0] plan_banks;
    wire [3:0] plan_lanes, plan_fault;
    wire active = !rst && !cancel;
    wire dense_req = req_mode == `CSR_FEED_MODE_B_R1 || req_mode == `CSR_FEED_MODE_B_R4;
    wire feed_ready, feed_valid;
    wire [3:0] feed_fault;
    wire [32*SW-1:0] feed_mat, feed_vec;
    wire [31:0] feed_mask;
    wire [15:0] unused_feed_job, unused_feed_tag;
    wire [7:0] unused_feed_fmt;
    wire unused_feed_last;
    integer lane;
    operand_plan plan (
        .mode(req_mode), .trans(req_trans), .rows(req_rows), .cols(req_cols), .out_idx(req_out), .red_idx(req_red),
        .step(req_step), .vec_base(req_vec_base), .mat_mask(plan_mat_mask), .vec_mask(plan_vec_mask),
        .mat_addr(plan_mat_addr), .vec_addr(plan_vec_addr), .vec_banks(plan_banks), .vec_lanes(plan_lanes), .fault(plan_fault)
    );
    assign req_ready = active && state == IDLE;
    assign mat_valid = active && state == READ && !sent[0];
    assign mat_rsp_ready = active && state == READ && sent[0] && !received[0];
    assign vec_valid = active && state == READ && !sent[1];
    assign vec_rsp_ready = active && state == READ && sent[1] && !received[1];
    assign mat_dense = mode_q == `CSR_FEED_MODE_B_R1 || mode_q == `CSR_FEED_MODE_B_R4;
    assign mat_mask = mat_mask_q; assign mat_addr = mat_addr_q; assign mat_key = key_q; assign mat_generation = mat_gen_q;
    assign vec_plane = plane_q; assign vec_mask = vec_mask_q; assign vec_addr = vec_addr_q; assign vec_generation = vec_gen_q;
    assign mem_job = job_q; assign mem_tag = tag_q; assign mem_fmt = fmt_q;
    assign rsp_job = job_q; assign rsp_tag = tag_q; assign rsp_fmt = fmt_q; assign rsp_last = last_q;
    assign rsp_valid = active && (state == ERROR || (state == WAIT_FEED && feed_valid));
    assign rsp_fault = state == ERROR ? fault_q : (feed_fault != 0 ? `CSR_MEM_FAULT_SOURCE : 4'b0);
    assign rsp_mat = state == WAIT_FEED && feed_fault == 0 ? feed_mat : '0;
    assign rsp_vec = state == WAIT_FEED && feed_fault == 0 ? feed_vec : '0;
    assign rsp_mask = state == WAIT_FEED && feed_fault == 0 ? feed_mask : '0;
    operand_feeder feeder (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(active && state == FEED), .req_ready(feed_ready),
        .req_mode(mode_q), .req_trans(trans_q), .req_rows(rows_q), .req_cols(cols_q), .req_out(out_q), .req_red(red_q), .req_step(step_q),
        .req_scale(scale_q), .req_signs(matrix_data[255:0]), .req_masks(sign_masks), .req_sign_valid(matrix_mask[7:0]),
        .req_dense(matrix_data), .req_dense_valid(matrix_mask), .req_vec(vector_data), .req_vec_valid(vec_lanes_q), .req_src_fault(1'b0),
        .req_job(job_q), .req_tag(tag_q), .req_fmt(fmt_q), .req_last(last_q),
        .rsp_valid(feed_valid), .rsp_ready(state == WAIT_FEED && rsp_ready), .rsp_mat(feed_mat), .rsp_vec(feed_vec), .rsp_mask(feed_mask),
        .rsp_fault(feed_fault), .rsp_job(unused_feed_job), .rsp_tag(unused_feed_tag), .rsp_fmt(unused_feed_fmt), .rsp_last(unused_feed_last)
    );
    always @(posedge clk) begin
        if (!active) begin
            state <= IDLE; sent <= '0; received <= '0; mode_q <= '0; plane_q <= '0; trans_q <= 1'b0; last_q <= 1'b0;
            rows_q <= '0; cols_q <= '0; out_q <= '0; red_q <= '0; step_q <= '0; scale_q <= '0; key_q <= '0;
            mat_gen_q <= '0; vec_gen_q <= '0; mat_mask_q <= '0; vec_mask_q <= '0; mat_addr_q <= '0; vec_addr_q <= '0;
            vec_banks_q <= '0; vec_lanes_q <= '0; fault_q <= '0; job_q <= '0; tag_q <= '0; fmt_q <= '0;
            matrix_data <= '0; sign_masks <= '0; matrix_mask <= '0; vector_data <= '0;
            source_faults[0] <= '0; source_faults[1] <= '0;
        end else begin
            if (req_valid && req_ready) begin
                mode_q <= req_mode; plane_q <= req_vec_plane; trans_q <= req_trans; rows_q <= req_rows; cols_q <= req_cols;
                out_q <= req_out; red_q <= req_red; step_q <= req_step; scale_q <= req_scale; key_q <= req_key;
                mat_gen_q <= req_mat_generation; vec_gen_q <= req_vec_generation; job_q <= req_job; tag_q <= req_tag; fmt_q <= req_fmt; last_q <= req_last;
                mat_mask_q <= plan_mat_mask; vec_mask_q <= plan_vec_mask; mat_addr_q <= plan_mat_addr; vec_addr_q <= plan_vec_addr;
                vec_banks_q <= plan_banks; vec_lanes_q <= plan_lanes;
                sent <= {plan_vec_mask == 0, plan_mat_mask == 0}; received <= {plan_vec_mask == 0, plan_mat_mask == 0};
                matrix_data <= '0; sign_masks <= '0; matrix_mask <= '0; vector_data <= '0;
                source_faults[0] <= '0; source_faults[1] <= '0;
                fault_q <= plan_fault != 0 ? plan_fault : req_vec_plane > 2 ? `CSR_MEM_FAULT_PLANE : `CSR_MEM_FAULT_SHAPE;
                state <= plan_fault != 0 || req_vec_plane > 2 || (!dense_req && $signed(req_scale) <= 0) ? ERROR : READ;
            end
            if (mat_valid && mat_ready) sent[0] <= 1'b1;
            if (vec_valid && vec_ready) sent[1] <= 1'b1;
            if (mat_rsp_valid && mat_rsp_ready) begin
                received[0] <= 1'b1; matrix_data <= mat_rsp_data; sign_masks <= mat_rsp_masks; matrix_mask <= mat_rsp_mask;
                if (mat_rsp_job != job_q || mat_rsp_tag != tag_q || mat_rsp_fmt != fmt_q || mat_rsp_generation != mat_gen_q)
                    source_faults[0] <= `CSR_MEM_FAULT_TAG;
                else if (mat_rsp_fault != 0 || mat_rsp_mask != mat_mask_q) source_faults[0] <= `CSR_MEM_FAULT_SOURCE;
            end
            if (vec_rsp_valid && vec_rsp_ready) begin
                received[1] <= 1'b1;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    vector_data[lane*SW +: SW] <= vec_lanes_q[lane] ? vec_rsp_data[int'(vec_banks_q[lane*5 +: 5])*SW +: SW] : {SW{1'b0}};
                end
                if (vec_rsp_job != job_q || vec_rsp_tag != tag_q || vec_rsp_fmt != fmt_q || vec_rsp_generation != vec_gen_q)
                    source_faults[1] <= `CSR_MEM_FAULT_TAG;
                else if (vec_rsp_fault != 0 || vec_rsp_mask != vec_mask_q) source_faults[1] <= `CSR_MEM_FAULT_SOURCE;
            end
            if (state == READ && (&received)) begin
                fault_q <= source_faults[0] != 0 ? source_faults[0] : source_faults[1];
                state <= source_faults[0] != 0 || source_faults[1] != 0 ? ERROR : FEED;
            end
            if (state == FEED && feed_ready) state <= WAIT_FEED;
            if (rsp_valid && rsp_ready) state <= IDLE;
        end
    end
endmodule
