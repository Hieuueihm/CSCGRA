`include "tile_interface.vh"

module pe_tile #(
    parameter integer TILE_ID = 0
) (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [`CSR_PE_OP_W-1:0] req_op,
    input wire req_mode,
    input wire [`CSR_TILE_SRC_W-1:0] req_a_kind, req_b_kind,
    input wire [`CSR_TILE_REG_W-1:0] req_a_idx, req_b_idx,
    input wire [`CSR_TILE_IMM_W-1:0] req_imm,
    input wire [`CSR_PE_S_W-1:0] req_mat, req_vec,
    input wire [4*`CSR_PE_S_W-1:0] req_links,
    input wire req_mat_valid, req_vec_valid,
    input wire [3:0] req_link_valid,
    input wire [`CSR_PE_ACC_W-1:0] req_wide,
    input wire req_wide_valid,
    input wire [`CSR_TILE_GUARD_W-1:0] req_guard, req_sel,
    input wire req_rf_we,
    input wire [`CSR_TILE_REG_W-1:0] req_dst,
    input wire req_pred_we,
    input wire [`CSR_TILE_PDST_W-1:0] req_pred_dst,
    input wire [2:0] req_pred_src,
    input wire req_lane,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    output wire rsp_valid,
    input wire rsp_ready,
    input wire rsp_drop,
    output wire [`CSR_PE_ACC_W-1:0] state_acc,
    output wire [`CSR_PE_S_W-1:0] rsp_data,
    output wire [`CSR_PE_ACC_W-1:0] rsp_acc,
    output wire [2:0] rsp_cmp,
    output wire [`CSR_PE_FAULT_W-1:0] rsp_fault,
    output wire [`CSR_PE_JOB_W-1:0] rsp_job,
    output wire [`CSR_PE_TAG_W-1:0] rsp_tag,
    output wire [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output wire rsp_last, rsp_lane, rsp_exec
);
    localparam integer SW = `CSR_PE_S_W;
    reg [SW-1:0] rf [0:`CSR_TILE_RF_WORDS-1];
    reg [`CSR_TILE_RF_WORDS-1:0] rf_valid;
    reg [`CSR_TILE_PRED_BITS-1:0] preds;
    wire [`CSR_TILE_RF_WORDS*SW-1:0] rf_flat;
    wire [`CSR_PE_ACC_W-1:0] acc_view;
    wire mode_view;
    wire [SW-1:0] arg_a, arg_b;
    wire [`CSR_PE_FAULT_W-1:0] fault_a, fault_b, alu_fault;
    reg use_a, use_b;
    reg [`CSR_PE_FAULT_W-1:0] src_fault, saved_fault;
    reg save_rf_we, save_pred_we, save_exec;
    reg [`CSR_TILE_REG_W-1:0] save_dst;
    reg [`CSR_TILE_PDST_W-1:0] save_pdst;
    reg [2:0] save_psrc;
    reg pred_next;
    wire active = !rst && !cancel;
    wire enabled = req_lane && guard_value(req_guard, preds);
    wire selected = guard_value(req_sel, preds);
    wire alu_exec;
    integer slot;

    function automatic guard_value;
        input [`CSR_TILE_GUARD_W-1:0] guard_sel;
        input [`CSR_TILE_PRED_BITS-1:0] pred_bits;
        begin
            case (guard_sel)
                `CSR_TILE_GUARD_ALWAYS: guard_value = 1'b1;
                `CSR_TILE_GUARD_P0: guard_value = pred_bits[0];
                `CSR_TILE_GUARD_P1: guard_value = pred_bits[1];
                `CSR_TILE_GUARD_P2: guard_value = pred_bits[2];
                `CSR_TILE_GUARD_NOT_P0: guard_value = !pred_bits[0];
                `CSR_TILE_GUARD_NOT_P1: guard_value = !pred_bits[1];
                `CSR_TILE_GUARD_NOT_P2: guard_value = !pred_bits[2];
                default: guard_value = 1'b0;
            endcase
        end
    endfunction

    genvar word_id;
    generate
        for (word_id = 0; word_id < `CSR_TILE_RF_WORDS; word_id = word_id + 1) begin : rf_pack
            assign rf_flat[word_id*SW +: SW] = rf[word_id];
        end
    endgenerate

    always @* begin
        use_a = 1'b0; use_b = 1'b0;
        case (req_op)
            `CSR_PE_OP_MOV, `CSR_PE_OP_ABS, `CSR_PE_OP_NOT: use_a = 1'b1;
            `CSR_PE_OP_ADD, `CSR_PE_OP_SUB, `CSR_PE_OP_CMP_S, `CSR_PE_OP_CMP_U,
            `CSR_PE_OP_SELECT, `CSR_PE_OP_AND, `CSR_PE_OP_OR, `CSR_PE_OP_XOR,
            `CSR_PE_OP_MUL, `CSR_PE_OP_MAC: begin use_a = 1'b1; use_b = 1'b1; end
            default: begin end
        endcase
        src_fault = '0;
        if (enabled) begin
            if (req_pred_we && (int'(req_pred_dst) >= `CSR_TILE_PRED_BITS || req_pred_src == 7))
                src_fault = `CSR_TILE_FAULT_PRED;
            else if (fault_a != 0) src_fault = fault_a;
            else if (fault_b != 0) src_fault = fault_b;
            else if (req_op == `CSR_PE_OP_ACC_ADD && !req_wide_valid) src_fault = `CSR_TILE_FAULT_SOURCE;
        end
        case (save_psrc)
            `CSR_TILE_PSEL_DATA: pred_next = rsp_data[0];
            `CSR_TILE_PSEL_LT: pred_next = rsp_cmp[0];
            `CSR_TILE_PSEL_EQ: pred_next = rsp_cmp[1];
            `CSR_TILE_PSEL_GT: pred_next = rsp_cmp[2];
            `CSR_TILE_PSEL_NOT_DATA: pred_next = !rsp_data[0];
            `CSR_TILE_PSEL_ONE: pred_next = 1'b1;
            default: pred_next = 1'b0;
        endcase
    end

    pe_operand #(.TILE_ID(TILE_ID)) src_a (
        .enable(enabled && use_a), .kind(req_a_kind), .idx(req_a_idx), .imm(req_imm),
        .rf_data(rf_flat), .rf_valid(rf_valid), .preds(preds), .acc(acc_view), .mode(mode_view),
        .mat(req_mat), .vec(req_vec), .mat_valid(req_mat_valid), .vec_valid(req_vec_valid),
        .links(req_links), .link_valid(req_link_valid), .data(arg_a), .fault(fault_a)
    );
    pe_operand #(.TILE_ID(TILE_ID)) src_b (
        .enable(enabled && use_b), .kind(req_b_kind), .idx(req_b_idx), .imm(req_imm),
        .rf_data(rf_flat), .rf_valid(rf_valid), .preds(preds), .acc(acc_view), .mode(mode_view),
        .mat(req_mat), .vec(req_vec), .mat_valid(req_mat_valid), .vec_valid(req_vec_valid),
        .links(req_links), .link_valid(req_link_valid), .data(arg_b), .fault(fault_b)
    );
    pe_alu alu (
        .clk(clk), .rst(rst), .cancel(cancel), .req_valid(req_valid), .req_ready(req_ready),
        .req_op(req_op), .req_mode(req_mode), .req_a(arg_a), .req_b(arg_b), .req_acc(req_wide),
        .req_sel(selected), .req_lane(req_lane), .req_exec(enabled && src_fault == 0),
        .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_drop(rsp_drop), .rsp_data(rsp_data), .rsp_acc(rsp_acc),
        .rsp_cmp(rsp_cmp), .rsp_fault(alu_fault), .rsp_job(rsp_job), .rsp_tag(rsp_tag),
        .rsp_fmt(rsp_fmt), .rsp_last(rsp_last), .rsp_lane(rsp_lane), .rsp_exec(alu_exec),
        .state_acc(acc_view), .state_mode(mode_view)
    );
    assign state_acc = acc_view;
    assign rsp_fault = saved_fault != 0 ? saved_fault : alu_fault;
    assign rsp_exec = saved_fault != 0 ? save_exec : alu_exec;

    always @(posedge clk) begin
        if (rst || cancel) begin
            rf_valid <= '0; preds <= '0;
            for (slot = 0; slot < `CSR_TILE_RF_WORDS; slot = slot + 1) rf[slot] <= '0;
            saved_fault <= '0; save_rf_we <= 1'b0; save_pred_we <= 1'b0; save_exec <= 1'b0;
            save_dst <= '0; save_pdst <= '0; save_psrc <= '0;
        end else begin
            if (active && req_valid && req_ready) begin
                saved_fault <= src_fault; save_exec <= enabled;
                save_rf_we <= req_rf_we; save_dst <= req_dst;
                save_pred_we <= req_pred_we; save_pdst <= req_pred_dst; save_psrc <= req_pred_src;
            end
            if (rsp_valid && rsp_ready && !rsp_drop && rsp_fault == 0 && rsp_exec) begin
                if (save_rf_we) begin rf[save_dst] <= rsp_data; rf_valid[save_dst] <= 1'b1; end
                if (save_pred_we) preds[save_pdst] <= pred_next;
            end
        end
    end
endmodule
