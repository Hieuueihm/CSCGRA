`include "context_defs.vh"

module pe_context #(
    parameter integer TILE_ID = 0,
    parameter integer ROUTING = 0
) (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [63:0] req_word,
    input wire [7:0] req_rev,
    input wire req_mode,
    input wire [`CSR_PE_S_W-1:0] req_mat, req_vec,
    input wire [4*`CSR_PE_S_W-1:0] req_links,
    input wire [4*`CSR_PE_ACC_W-1:0] req_wlinks,
    input wire req_mat_valid, req_vec_valid,
    input wire [3:0] req_link_valid,
    input wire req_lane,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    output wire rsp_valid,
    input wire rsp_ready,
    input wire rsp_drop,
    output reg [11:0] rsp_routes,
    output reg [`CSR_PE_ACC_W-1:0] rsp_rval, rsp_oldacc,
    output reg rsp_rvalid,
    output wire [`CSR_PE_S_W-1:0] rsp_data,
    output wire [`CSR_PE_ACC_W-1:0] rsp_acc,
    output wire [2:0] rsp_cmp,
    output wire [3:0] rsp_fault,
    output wire [`CSR_PE_JOB_W-1:0] rsp_job,
    output wire [`CSR_PE_TAG_W-1:0] rsp_tag,
    output wire [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output wire rsp_last, rsp_lane, rsp_exec, rsp_store, rsp_halt
);
    wire [`CSR_PE_OP_W-1:0] dec_op;
    wire [3:0] a_kind, b_kind, dec_fault, tile_fault;
    wire [2:0] a_idx, b_idx, guard, sel, dst, pred_src;
    wire [15:0] imm;
    wire rf_we, pred_we, wide, dec_store, dec_halt;
    wire [1:0] pred_dst, wide_idx;
    wire [11:0] routes;
    wire tile_lane, tile_exec;
    wire [3:0] scalar_link_valid;
    genvar direction;
    generate
        for (direction = 0; direction < 4; direction = direction + 1) begin : narrow_check
            wire [`CSR_PE_ACC_W-1:0] value = req_wlinks[direction*`CSR_PE_ACC_W +: `CSR_PE_ACC_W];
            wire fits = value == {{(`CSR_PE_ACC_W-`CSR_PE_S_W){value[`CSR_PE_S_W-1]}}, value[`CSR_PE_S_W-1:0]};
            assign scalar_link_valid[direction] = req_link_valid[direction] && (ROUTING == 0 || fits);
        end
    endgenerate
    reg [3:0] fault_q;
    reg lane_q, store_q, halt_q;
    wire [`CSR_PE_ACC_W-1:0] wide_data = wide ? req_wlinks[int'(wide_idx)*`CSR_PE_ACC_W +: `CSR_PE_ACC_W] : 64'b0;

    wire [`CSR_PE_ACC_W-1:0] state_acc;
    context_decode #(.TILE_ID(TILE_ID), .ROUTING(ROUTING)) decode (
        .word(req_word), .rev(req_rev), .mode(req_mode), .op(dec_op),
        .a_kind(a_kind), .b_kind(b_kind), .a_idx(a_idx), .b_idx(b_idx),
        .imm(imm), .guard(guard), .sel(sel), .rf_we(rf_we), .dst(dst),
        .pred_we(pred_we), .pred_dst(pred_dst), .pred_src(pred_src),
        .wide(wide), .wide_idx(wide_idx), .routes(routes), .store(dec_store), .halt(dec_halt), .fault(dec_fault)
    );
    pe_tile #(.TILE_ID(TILE_ID)) tile (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_ready(req_ready),
        .req_op(dec_op), .req_mode(req_mode), .req_a_kind(a_kind), .req_b_kind(b_kind),
        .req_a_idx(a_idx), .req_b_idx(b_idx), .req_imm(imm), .req_mat(req_mat), .req_vec(req_vec),
        .req_links(req_links), .req_mat_valid(req_mat_valid), .req_vec_valid(req_vec_valid),
        .req_link_valid(scalar_link_valid), .req_wide(wide_data), .req_wide_valid(wide && req_link_valid[wide_idx]),
        .req_guard(guard), .req_sel(sel), .req_rf_we(rf_we), .req_dst(dst),
        .req_pred_we(pred_we), .req_pred_dst(pred_dst), .req_pred_src(pred_src),
        .req_lane(req_lane && dec_fault == 0), .req_job(req_job), .req_tag(req_tag),
        .req_fmt(req_fmt), .req_last(req_last), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_drop(rsp_drop), .state_acc(state_acc),
        .rsp_data(rsp_data), .rsp_acc(rsp_acc), .rsp_cmp(rsp_cmp), .rsp_fault(tile_fault),
        .rsp_job(rsp_job), .rsp_tag(rsp_tag), .rsp_fmt(rsp_fmt), .rsp_last(rsp_last),
        .rsp_lane(tile_lane), .rsp_exec(tile_exec)
    );
    assign rsp_fault = fault_q != 0 ? fault_q : tile_fault;
    assign rsp_lane = fault_q != 0 ? lane_q : tile_lane;
    assign rsp_exec = fault_q == 0 && tile_exec;
    assign rsp_store = store_q && rsp_exec && rsp_fault == 0;
    assign rsp_halt = halt_q && rsp_exec && rsp_fault == 0;

    always @(posedge clk) begin
        if (rst || cancel) begin
            fault_q <= 0; lane_q <= 0; store_q <= 0; halt_q <= 0;
            rsp_routes <= 0; rsp_rval <= 0; rsp_oldacc <= 0; rsp_rvalid <= 0;
        end else if (req_valid && req_ready) begin
            fault_q <= dec_fault; lane_q <= req_lane; store_q <= dec_store; halt_q <= dec_halt;
            rsp_routes <= routes; rsp_oldacc <= state_acc;
            rsp_rvalid <= a_kind == `CSR_CTX_SRC_ACC ||
                          (a_kind == `CSR_CTX_SRC_LINK && req_link_valid[a_idx[1:0]]);
            rsp_rval <= a_kind == `CSR_CTX_SRC_ACC ? state_acc :
                        req_wlinks[int'(a_idx[1:0])*`CSR_PE_ACC_W +: `CSR_PE_ACC_W];
        end
    end
endmodule
