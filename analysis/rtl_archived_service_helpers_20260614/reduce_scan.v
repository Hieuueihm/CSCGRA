module reduce_scan #(
    parameter integer COLS     = 8,
    parameter integer DATA_W   = 24,
    parameter integer SCALAR_W = 56,
    parameter integer IDX_W    = 10
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     ctx_valid,
    input  wire [3:0]               uop_class,
    input  wire [COLS-1:0]          lane_valid,
    input  wire [IDX_W-1:0]         base_idx,
    input  wire                     addr_valid,
    input  wire                     addr_done,
    input  wire [COLS*DATA_W-1:0]   spm_pa_rdata,

    output wire                     reduce_valid,
    output wire [SCALAR_W-1:0]      reduce_result,
    output wire [IDX_W-1:0]         reduce_idx,
    output wire                     reduce_converged
);
    localparam integer PAIRS = (COLS + 1) / 2;
    localparam integer PAIR2 = (PAIRS + 1) / 2;

    function [DATA_W-1:0] abs_data;
        input [DATA_W-1:0] value;
        begin
            if (value == {1'b1, {(DATA_W-1){1'b0}}})
                abs_data = {1'b0, {(DATA_W-1){1'b1}}};
            else if (value[DATA_W-1])
                abs_data = ~value + 1'b1;
            else
                abs_data = value;
        end
    endfunction

    reg [SCALAR_W-1:0] best_value_q;
    reg [IDX_W-1:0] best_idx_q;
    reg best_flag_q;

    reg [SCALAR_W-1:0] pair_value_q [0:PAIRS-1];
    reg [IDX_W-1:0] pair_idx_q [0:PAIRS-1];
    reg pair_valid_q [0:PAIRS-1];

    reg [SCALAR_W-1:0] mid_value_q [0:PAIR2-1];
    reg [IDX_W-1:0] mid_idx_q [0:PAIR2-1];
    reg mid_valid_q [0:PAIR2-1];

    reg [SCALAR_W-1:0] cand_value_q;
    reg [IDX_W-1:0] cand_idx_q;
    reg cand_valid_q;

    reg [COLS-1:0] lane_valid_q;
    reg [IDX_W-1:0] base_idx_q;
    reg addr_valid_q;
    reg addr_done_q;

    reg [4:0] done_pipe;
    integer i;

    wire active = (uop_class == 4'd4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_value_q <= {SCALAR_W{1'b0}};
            best_idx_q <= {IDX_W{1'b0}};
            best_flag_q <= 1'b0;
            cand_value_q <= {SCALAR_W{1'b0}};
            cand_idx_q <= {IDX_W{1'b0}};
            cand_valid_q <= 1'b0;
            lane_valid_q <= {COLS{1'b0}};
            base_idx_q <= {IDX_W{1'b0}};
            addr_valid_q <= 1'b0;
            addr_done_q <= 1'b0;
            done_pipe <= 5'b00000;
            for (i = 0; i < PAIRS; i = i + 1) begin
                pair_value_q[i] <= {SCALAR_W{1'b0}};
                pair_idx_q[i] <= {IDX_W{1'b0}};
                pair_valid_q[i] <= 1'b0;
            end
            for (i = 0; i < PAIR2; i = i + 1) begin
                mid_value_q[i] <= {SCALAR_W{1'b0}};
                mid_idx_q[i] <= {IDX_W{1'b0}};
                mid_valid_q[i] <= 1'b0;
            end
        end else begin
            if (ctx_valid && active) begin
                best_value_q <= {SCALAR_W{1'b0}};
                best_idx_q <= {IDX_W{1'b0}};
                best_flag_q <= 1'b0;
                cand_value_q <= {SCALAR_W{1'b0}};
                cand_idx_q <= {IDX_W{1'b0}};
                cand_valid_q <= 1'b0;
                lane_valid_q <= {COLS{1'b0}};
                base_idx_q <= {IDX_W{1'b0}};
                addr_valid_q <= 1'b0;
                addr_done_q <= 1'b0;
                done_pipe <= 5'b00000;
                for (i = 0; i < PAIRS; i = i + 1)
                    pair_valid_q[i] <= 1'b0;
                for (i = 0; i < PAIR2; i = i + 1)
                    mid_valid_q[i] <= 1'b0;
            end else begin
                lane_valid_q <= lane_valid;
                base_idx_q <= base_idx;
                addr_valid_q <= addr_valid;
                addr_done_q <= addr_done;
                done_pipe <= {done_pipe[3:0], active && addr_done_q};

                for (i = 0; i < PAIRS; i = i + 1) begin
                    pair_valid_q[i] <= active && addr_valid_q && (lane_valid_q[2*i] || ((2*i+1 < COLS) && lane_valid_q[2*i+1]));
                    if ((2*i+1 < COLS) && lane_valid_q[2*i+1] && (!lane_valid_q[2*i] || (abs_data(spm_pa_rdata[(2*i+1)*DATA_W +: DATA_W]) > abs_data(spm_pa_rdata[(2*i)*DATA_W +: DATA_W])))) begin
                        pair_value_q[i] <= {{(SCALAR_W-DATA_W){1'b0}}, abs_data(spm_pa_rdata[(2*i+1)*DATA_W +: DATA_W])};
                        pair_idx_q[i] <= base_idx_q + (2*i+1);
                    end else begin
                        pair_value_q[i] <= {{(SCALAR_W-DATA_W){1'b0}}, abs_data(spm_pa_rdata[(2*i)*DATA_W +: DATA_W])};
                        pair_idx_q[i] <= base_idx_q + (2*i);
                    end
                end

                for (i = 0; i < PAIR2; i = i + 1) begin
                    mid_valid_q[i] <= pair_valid_q[2*i] || ((2*i+1 < PAIRS) && pair_valid_q[2*i+1]);
                    if ((2*i+1 < PAIRS) && pair_valid_q[2*i+1] && (!pair_valid_q[2*i] || (pair_value_q[2*i+1] > pair_value_q[2*i]))) begin
                        mid_value_q[i] <= pair_value_q[2*i+1];
                        mid_idx_q[i] <= pair_idx_q[2*i+1];
                    end else begin
                        mid_value_q[i] <= pair_value_q[2*i];
                        mid_idx_q[i] <= pair_idx_q[2*i];
                    end
                end

                cand_valid_q <= mid_valid_q[0] || ((PAIR2 > 1) && mid_valid_q[1]);
                if ((PAIR2 > 1) && mid_valid_q[1] && (!mid_valid_q[0] || (mid_value_q[1] > mid_value_q[0]))) begin
                    cand_value_q <= mid_value_q[1];
                    cand_idx_q <= mid_idx_q[1];
                end else begin
                    cand_value_q <= mid_value_q[0];
                    cand_idx_q <= mid_idx_q[0];
                end

                if (cand_valid_q && (!best_flag_q || (cand_value_q > best_value_q))) begin
                    best_value_q <= cand_value_q;
                    best_idx_q <= cand_idx_q;
                    best_flag_q <= 1'b1;
                end
            end
        end
    end

    assign reduce_valid = done_pipe[4];
    assign reduce_result = best_value_q;
    assign reduce_idx = best_idx_q;
    assign reduce_converged = best_flag_q;
endmodule
