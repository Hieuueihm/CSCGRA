`include "pe_interface.vh"
`include "feeder_interface.vh"

module operand_feeder (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [1:0] req_mode,
    input wire req_trans,
    input wire [7:0] req_rows,
    input wire [10:0] req_cols, req_out, req_red,
    input wire [2:0] req_step,
    input wire [`CSR_PE_C_W-1:0] req_scale,
    input wire [255:0] req_signs, req_masks,
    input wire [7:0] req_sign_valid,
    input wire [32*`CSR_PE_C_W-1:0] req_dense,
    input wire [31:0] req_dense_valid,
    input wire [4*`CSR_PE_S_W-1:0] req_vec,
    input wire [3:0] req_vec_valid,
    input wire req_src_fault,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    output wire rsp_valid,
    input wire rsp_ready,
    output reg [32*`CSR_PE_S_W-1:0] rsp_mat, rsp_vec,
    output reg [31:0] rsp_mask,
    output reg [3:0] rsp_fault,
    output reg [`CSR_PE_JOB_W-1:0] rsp_job,
    output reg [`CSR_PE_TAG_W-1:0] rsp_tag,
    output reg [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output reg rsp_last
);
    localparam integer SW = `CSR_PE_S_W;
    localparam integer CW = `CSR_PE_C_W;
    reg pending;
    wire active = !rst && !cancel;
    wire dense = req_mode == `CSR_FEED_MODE_B_R1 || req_mode == `CSR_FEED_MODE_B_R4;
    wire rfour = req_mode == `CSR_FEED_MODE_PHI_R4 || req_mode == `CSR_FEED_MODE_B_R4;
    wire trans = dense ? req_trans : rfour;
    reg [32*SW-1:0] mat_next, vec_next;
    reg [31:0] mask_next;
    reg [3:0] fault_next;
    reg missing;
    reg signed [CW-1:0] coeff;
    integer tile, lane, output_idx, red_idx, row_idx, col_idx, bank, bit_idx;
    integer outputs, reductions;

    assign req_ready = active && !pending;
    assign rsp_valid = active && pending;

    always @* begin
        mat_next = '0; vec_next = '0; mask_next = '0;
        fault_next = `CSR_FEED_FAULT_NONE; missing = req_src_fault; coeff = '0;
        lane = 0; output_idx = 0; red_idx = 0; row_idx = 0; col_idx = 0; bank = 0; bit_idx = 0;
        outputs = trans ? int'(req_cols) : int'(req_rows);
        reductions = trans ? int'(req_rows) : int'(req_cols);
        if (req_rows == 0 || int'(req_rows) > `CSR_FEED_MAX_ROWS || req_cols == 0 ||
            int'(req_cols) > (dense ? `CSR_FEED_MAX_SUPPORT : `CSR_FEED_MAX_COLS))
            fault_next = `CSR_FEED_FAULT_SHAPE;
        else if (int'(req_out) >= outputs || int'(req_red) >= reductions ||
                 (rfour && (req_out[2:0] != 0 || req_red[4:0] != 0)) ||
                 (!rfour && (req_out[4:0] != 0 || req_step != 0)) ||
                 (!dense && req_trans != rfour))
            fault_next = `CSR_FEED_FAULT_INDEX;
        else if (!dense && ($signed(req_scale) <= 0)) fault_next = `CSR_FEED_FAULT_SCALE;
        for (tile = 0; tile < 32; tile = tile + 1) begin
            lane = rfour ? tile % 4 : 0;
            output_idx = int'(req_out) + (rfour ? tile / 4 : tile);
            red_idx = int'(req_red) + (rfour ? 8*lane + int'(req_step) : 0);
            row_idx = trans ? red_idx : output_idx;
            col_idx = trans ? output_idx : red_idx;
            if (output_idx < outputs && red_idx < reductions) begin
                mask_next[tile] = 1'b1;
                if (!req_vec_valid[lane]) missing = 1'b1;
                vec_next[tile*SW +: SW] = req_vec[lane*SW +: SW];
                if (dense) begin
                    bank = (row_idx + col_idx) % 32;
                    coeff = $signed(req_dense[bank*CW +: CW]);
                    if (!req_dense_valid[bank]) missing = 1'b1;
                end else begin
                    bank = col_idx % 8;
                    bit_idx = row_idx % 32;
                    coeff = req_signs[bank*32 + bit_idx] ? $signed(req_scale) : -$signed(req_scale);
                    if (!req_sign_valid[bank] || !req_masks[bank*32 + bit_idx]) missing = 1'b1;
                end
                mat_next[tile*SW +: SW] = {{(SW-CW){coeff[CW-1]}}, coeff};
            end
        end
        if (fault_next == 0 && missing) fault_next = `CSR_FEED_FAULT_SOURCE;
        if (fault_next != 0) begin mat_next = '0; vec_next = '0; mask_next = '0; end
    end

    always @(posedge clk) begin
        if (rst || cancel) begin
            pending <= 1'b0; rsp_mat <= '0; rsp_vec <= '0; rsp_mask <= '0;
            rsp_fault <= '0; rsp_job <= '0; rsp_tag <= '0; rsp_fmt <= '0; rsp_last <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready) pending <= 1'b0;
            if (req_valid && req_ready) begin
                pending <= 1'b1; rsp_mat <= mat_next; rsp_vec <= vec_next;
                rsp_mask <= mask_next; rsp_fault <= fault_next;
                rsp_job <= req_job; rsp_tag <= req_tag; rsp_fmt <= req_fmt; rsp_last <= req_last;
            end
        end
    end
endmodule
