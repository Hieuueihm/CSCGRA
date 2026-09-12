`include "scalar_interface.vh"

// Fixed candidate arithmetic leaf. There is no scalar register file here.
module scalar_service (
    input logic clk, rst, cancel,
    input logic req_valid,
    output logic req_ready,
    input logic [`CSR_SCALAR_OP_W-1:0] req_op,
    input logic signed [`CSR_SCALAR_N_W-1:0] req_a, req_b,
    input logic [`CSR_SCALAR_FRAC_W-1:0] req_source_frac,
    input logic [`CSR_SCALAR_JOB_W-1:0] req_job,
    input logic [`CSR_SCALAR_TAG_W-1:0] req_tag,
    input logic [`CSR_SCALAR_FMT_W-1:0] req_fmt,
    output logic rsp_valid,
    input logic rsp_ready,
    output logic signed [`CSR_SCALAR_S_W-1:0] rsp_data,
    output logic [`CSR_SCALAR_FAULT_W-1:0] rsp_fault,
    output logic [`CSR_SCALAR_JOB_W-1:0] rsp_job,
    output logic [`CSR_SCALAR_TAG_W-1:0] rsp_tag,
    output logic [`CSR_SCALAR_FMT_W-1:0] rsp_fmt
);
    typedef enum logic [2:0] {IDLE, DIVIDE, ROOT, FINISH_DIV, FINISH_ROOT, FAULT} state_t;
    state_t state;
    logic response_pending;
    logic [6:0] remaining;
    logic negative;
    logic [63:0] denominator;
    logic [85:0] quotient;
    logic [64:0] remainder_div, trial_div, next_remainder_div;
    logic [85:0] next_quotient;
    logic [86:0] rounded_div;
    logic [63:0] radicand;
    logic [31:0] root;
    logic [33:0] remainder_root, trial_root, shifted_root_remainder;
    logic [32:0] rounded_root;
    logic [63:0] magnitude_a, magnitude_b;

    // Unsigned two's complement magnitude preserves abs(-2**63).
    assign magnitude_a = req_a[63] ? (~$unsigned(req_a) + 64'd1) : $unsigned(req_a);
    assign magnitude_b = req_b[63] ? (~$unsigned(req_b) + 64'd1) : $unsigned(req_b);
    assign req_ready = (state == IDLE) && !response_pending && !rst && !cancel;
    assign rsp_valid = response_pending && !rst && !cancel;
    assign trial_div = {remainder_div[63:0], quotient[85]};
    assign next_remainder_div = trial_div >= {1'b0,denominator} ?
                                trial_div - {1'b0,denominator} : trial_div;
    assign next_quotient = {quotient[84:0], (trial_div >= {1'b0,denominator})};
    assign rounded_div = {1'b0,quotient} +
                         {{86{1'b0}}, ((remainder_div << 1) >= {1'b0,denominator})};
    assign shifted_root_remainder = {remainder_root[31:0],radicand[63:62]};
    assign trial_root = {root,2'b01};
    // n=q*q+r; nearest sqrt(n) rounds up exactly when integer r>q.
    assign rounded_root = {1'b0,root} + {{32{1'b0}},(remainder_root > {2'b0,root})};

    always_ff @(posedge clk) begin
        if (rst || cancel) begin
            state <= IDLE;
            response_pending <= 1'b0;
            rsp_data <= '0;
            rsp_fault <= '0;
            rsp_job <= '0;
            rsp_tag <= '0;
            rsp_fmt <= '0;
            remaining <= '0;
            negative <= 1'b0;
            denominator <= '0;
            quotient <= '0;
            remainder_div <= '0;
            radicand <= '0;
            root <= '0;
            remainder_root <= '0;
        end else begin
            if (response_pending && rsp_ready) begin
                response_pending <= 1'b0;
                rsp_data <= '0;
                rsp_fault <= '0;
                rsp_job <= '0;
                rsp_tag <= '0;
                rsp_fmt <= '0;
            end
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    rsp_job <= req_job;
                    rsp_tag <= req_tag;
                    rsp_fmt <= req_fmt;
                    rsp_data <= '0;
                    rsp_fault <= `CSR_SCALAR_FAULT_NONE;
                    if (req_fmt != `CSR_SCALAR_FORMAT ||
                        (req_op != `CSR_SCALAR_OP_DIV && req_op != `CSR_SCALAR_OP_SQRT) ||
                        (req_op == `CSR_SCALAR_OP_DIV && req_source_frac != `CSR_SCALAR_DIV_FRAC) ||
                        (req_op == `CSR_SCALAR_OP_SQRT && req_source_frac != `CSR_SCALAR_SQRT_FRAC)) begin
                        rsp_fault <= `CSR_SCALAR_FAULT_MODE;
                        state <= FAULT;
                    end else if (req_op == `CSR_SCALAR_OP_DIV) begin
                        if (req_b == 0) begin
                            rsp_fault <= `CSR_SCALAR_FAULT_ZERO;
                            state <= FAULT;
                        end else begin
                            quotient <= {magnitude_a,22'b0};
                            denominator <= magnitude_b;
                            remainder_div <= '0;
                            negative <= req_a[63] ^ req_b[63];
                            remaining <= 7'd86;
                            state <= DIVIDE;
                        end
                    end else if (req_a[63]) begin
                        rsp_fault <= `CSR_SCALAR_FAULT_NEGATIVE;
                        state <= FAULT;
                    end else begin
                        radicand <= $unsigned(req_a);
                        root <= '0;
                        remainder_root <= '0;
                        remaining <= 7'd32;
                        state <= ROOT;
                    end
                end
                DIVIDE: begin
                    quotient <= next_quotient;
                    remainder_div <= next_remainder_div;
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) state <= FINISH_DIV;
                end
                ROOT: begin
                    radicand <= {radicand[61:0],2'b0};
                    if (shifted_root_remainder >= trial_root) begin
                        remainder_root <= shifted_root_remainder - trial_root;
                        root <= {root[30:0],1'b1};
                    end else begin
                        remainder_root <= shifted_root_remainder;
                        root <= {root[30:0],1'b0};
                    end
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) state <= FINISH_ROOT;
                end
                FINISH_DIV: begin
                    if (rounded_div > (negative ? 87'd67108864 : 87'd67108863))
                        rsp_fault <= `CSR_SCALAR_FAULT_RANGE;
                    else rsp_data <= negative ? -$signed(rounded_div[26:0]) : $signed(rounded_div[26:0]);
                    response_pending <= 1'b1;
                    state <= IDLE;
                end
                FINISH_ROOT: begin
                    if (rounded_root > 33'd67108863) rsp_fault <= `CSR_SCALAR_FAULT_RANGE;
                    else rsp_data <= $signed(rounded_root[26:0]);
                    response_pending <= 1'b1;
                    state <= IDLE;
                end
                FAULT: begin
                    response_pending <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
