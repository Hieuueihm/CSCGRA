`include "pe_interface.vh"

module pe_alu (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [`CSR_PE_OP_W-1:0] req_op,
    input wire req_mode,
    input wire [`CSR_PE_S_W-1:0] req_a, req_b,
    input wire [`CSR_PE_ACC_W-1:0] req_acc,
    input wire req_sel, req_lane, req_exec,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    output wire rsp_valid,
    input wire rsp_ready,
    input wire rsp_drop,
    output reg [`CSR_PE_S_W-1:0] rsp_data,
    output reg [`CSR_PE_ACC_W-1:0] rsp_acc,
    output reg [2:0] rsp_cmp,
    output reg [`CSR_PE_FAULT_W-1:0] rsp_fault,
    output reg [`CSR_PE_JOB_W-1:0] rsp_job,
    output reg [`CSR_PE_TAG_W-1:0] rsp_tag,
    output reg [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output reg rsp_last, rsp_lane, rsp_exec,
    output wire [`CSR_PE_ACC_W-1:0] state_acc,
    output wire state_mode
);
    localparam integer SW = `CSR_PE_S_W;
    localparam integer CW = `CSR_PE_C_W;
    localparam integer AW = `CSR_PE_ACC_W;
    localparam integer SPLIT = `CSR_PE_SPLIT;
    localparam integer PW = SW + CW;
    localparam signed [AW:0] S_MAX = (65'sd1 << (SW-1)) - 1;
    localparam signed [AW:0] S_MIN = -(65'sd1 << (SW-1));
    localparam signed [AW:0] A_MAX = (65'sd1 << (AW-1)) - 1;
    localparam signed [AW:0] A_MIN = -(65'sd1 << (AW-1));

    reg signed [AW-1:0] acc;
    reg acc_mode, phase, pending, wr_acc, wr_mode;
    reg signed [SW-1:0] saved_a, saved_b;
    reg [`CSR_PE_OP_W-1:0] saved_op;
    reg signed [PW-1:0] low_prod;
    wire [`CSR_PE_OP_W-1:0] op = phase ? saved_op : req_op;
    wire mode = phase ? 1'b1 : req_mode;
    wire enabled = phase || (req_lane && req_exec);
    wire signed [SW-1:0] arg_a = phase ? saved_a : $signed(req_a);
    wire signed [SW-1:0] arg_b = phase ? saved_b : $signed(req_b);
    wire is_mul = op == `CSR_PE_OP_MUL || op == `CSR_PE_OP_MAC;
    reg signed [CW-1:0] mul_b;
    wire signed [PW-1:0] prod = arg_a * mul_b;
    reg signed [AW:0] wide, product;
    reg [SW-1:0] data_next;
    reg [AW-1:0] acc_next;
    reg [2:0] cmp_next;
    reg [`CSR_PE_FAULT_W-1:0] fault_next;
    reg write_next, narrow;
    wire split_start = !phase && enabled && is_mul && mode && fault_next == 0;

    assign req_ready = !rst && !cancel && !phase && !pending;
    assign rsp_valid = !rst && !cancel && pending;
    assign state_acc = acc;
    assign state_mode = acc_mode;

    function automatic signed [AW:0] rounded;
        input signed [AW:0] value;
        input integer shift;
        reg [AW:0] mag;
        begin
            mag = value < 0 ? $unsigned(-value) : $unsigned(value);
            mag = (mag + (65'd1 << (shift-1))) >> shift;
            rounded = value < 0 ? -$signed(mag) : $signed(mag);
        end
    endfunction

    always @* begin
        if (phase)
            mul_b = {{(CW-(SW-SPLIT)){arg_b[SW-1]}}, arg_b[SW-1:SPLIT]};
        else if (mode)
            mul_b = $signed({1'b0, arg_b[SPLIT-1:0]});
        else
            mul_b = arg_b[CW-1:0];
        product = {{(AW+1-PW){prod[PW-1]}}, prod};
        if (phase)
            product = (product <<< SPLIT) + {{(AW+1-PW){low_prod[PW-1]}}, low_prod};
        data_next = '0;
        acc_next = acc;
        cmp_next = '0;
        fault_next = `CSR_PE_FAULT_NONE;
        wide = '0;
        write_next = 1'b0;
        narrow = 1'b0;
        if (enabled) begin
            if (int'(op) > `CSR_PE_OP_NOT)
                fault_next = `CSR_PE_FAULT_OP;
            else if ((op == `CSR_PE_OP_MAC || op == `CSR_PE_OP_ACC_ADD ||
                      op == `CSR_PE_OP_ACC_READ) && mode != acc_mode)
                fault_next = `CSR_PE_FAULT_MODE;
            else if (is_mul && !mode && arg_b != {{(SW-CW){arg_b[CW-1]}}, arg_b[CW-1:0]})
                fault_next = `CSR_PE_FAULT_COEFF;
            else begin
                case (op)
                    `CSR_PE_OP_MOV: data_next = arg_a;
                    `CSR_PE_OP_ADD: begin
                        wide = {{(AW+1-SW){arg_a[SW-1]}}, arg_a} + {{(AW+1-SW){arg_b[SW-1]}}, arg_b};
                        narrow = 1'b1;
                    end
                    `CSR_PE_OP_SUB: begin
                        wide = {{(AW+1-SW){arg_a[SW-1]}}, arg_a} - {{(AW+1-SW){arg_b[SW-1]}}, arg_b};
                        narrow = 1'b1;
                    end
                    `CSR_PE_OP_ABS: data_next = arg_a < 0 ? -arg_a : arg_a;
                    `CSR_PE_OP_CMP_S: begin
                        cmp_next = {arg_a > arg_b, arg_a == arg_b, arg_a < arg_b};
                        data_next = {{(SW-1){1'b0}}, cmp_next[0]};
                    end
                    `CSR_PE_OP_CMP_U: begin
                        cmp_next = {$unsigned(arg_a) > $unsigned(arg_b), arg_a == arg_b,
                                    $unsigned(arg_a) < $unsigned(arg_b)};
                        data_next = {{(SW-1){1'b0}}, cmp_next[0]};
                    end
                    `CSR_PE_OP_SELECT: data_next = req_sel ? arg_a : arg_b;
                    `CSR_PE_OP_AND: data_next = arg_a & arg_b;
                    `CSR_PE_OP_OR: data_next = arg_a | arg_b;
                    `CSR_PE_OP_XOR: data_next = arg_a ^ arg_b;
                    `CSR_PE_OP_NOT: data_next = ~arg_a;
                    `CSR_PE_OP_MUL: begin
                        if (!mode || phase) begin
                            wide = rounded(product, mode ? `CSR_PE_S_F : `CSR_PE_C_F);
                            narrow = 1'b1;
                        end
                    end
                    `CSR_PE_OP_MAC: begin
                        if (!mode || phase) begin
                            wide = $signed({acc[AW-1], acc}) + product;
                            write_next = 1'b1;
                        end
                    end
                    `CSR_PE_OP_ACC_CLEAR: begin wide = '0; write_next = 1'b1; end
                    `CSR_PE_OP_ACC_ADD: begin
                        wide = $signed({acc[AW-1], acc}) + $signed({req_acc[AW-1], req_acc});
                        write_next = 1'b1;
                    end
                    `CSR_PE_OP_ACC_READ: begin
                        wide = rounded($signed({acc[AW-1], acc}), mode ? `CSR_PE_S_F : `CSR_PE_C_F);
                        narrow = 1'b1;
                    end
                    default: begin end
                endcase
                if (narrow) begin
                    if (wide > S_MAX) begin data_next = S_MAX[SW-1:0]; fault_next = `CSR_PE_FAULT_SAT; end
                    else if (wide < S_MIN) begin data_next = S_MIN[SW-1:0]; fault_next = `CSR_PE_FAULT_SAT; end
                    else data_next = wide[SW-1:0];
                end
                if (write_next) begin
                    if (wide > A_MAX) begin acc_next = A_MAX[AW-1:0]; fault_next = `CSR_PE_FAULT_ACC; end
                    else if (wide < A_MIN) begin acc_next = A_MIN[AW-1:0]; fault_next = `CSR_PE_FAULT_ACC; end
                    else acc_next = wide[AW-1:0];
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst || cancel) begin
            acc <= '0; acc_mode <= 1'b0;
            phase <= 1'b0; pending <= 1'b0; wr_acc <= 1'b0; wr_mode <= 1'b0;
            saved_a <= '0; saved_b <= '0; saved_op <= '0; low_prod <= '0;
            rsp_data <= '0; rsp_acc <= '0; rsp_cmp <= '0; rsp_fault <= '0;
            rsp_job <= '0; rsp_tag <= '0; rsp_fmt <= '0;
            rsp_last <= 1'b0; rsp_lane <= 1'b0; rsp_exec <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready) begin
                pending <= 1'b0;
                if (wr_acc && rsp_fault == 0 && !rsp_drop) begin acc <= rsp_acc; acc_mode <= wr_mode; end
            end
            if (phase || (req_valid && req_ready)) begin
                if (!phase) begin
                    rsp_job <= req_job; rsp_tag <= req_tag; rsp_fmt <= req_fmt;
                    rsp_last <= req_last; rsp_lane <= req_lane; rsp_exec <= req_lane && req_exec;
                end
                if (split_start) begin
                    phase <= 1'b1;
                    saved_a <= req_a; saved_b <= req_b; saved_op <= req_op; low_prod <= prod;
                end else begin
                    phase <= 1'b0; pending <= 1'b1;
                    rsp_data <= data_next; rsp_acc <= acc_next; rsp_cmp <= cmp_next;
                    rsp_fault <= fault_next; wr_acc <= write_next; wr_mode <= mode;
                end
            end
        end
    end
endmodule
